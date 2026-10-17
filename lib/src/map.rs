use crate::array::YrsArray;
use crate::doc::{YrsCollectionPtr, YrsDoc};
use crate::error::CodingError;
use crate::mapchange::{try_from_entry_change, YrsMapChange};
use crate::text::YrsText;
use crate::transaction::YrsTransaction;
use parking_lot::ReentrantMutex;
use std::cell::UnsafeCell;
use std::fmt::Debug;
use std::sync::Arc;
use yrs::branch::Branch;
use yrs::{Hook, SharedRef};
use yrs::{Any, Map, MapRef, Observable, Out};

pub(crate) struct YrsMap(ReentrantMutex<UnsafeCell<MapRef>>, Hook<MapRef>);

// Marks that this type can be transferred across thread boundaries.
// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Send for YrsMap {}
// Marks that this type is safe to share references between threads.
// Safe because ReentrantMutex provides proper thread synchronization.
unsafe impl Sync for YrsMap {}

/// A guard that holds the lock and provides access to the inner MapRef.
pub(crate) struct MapRefGuard<'a> {
    _guard: parking_lot::ReentrantMutexGuard<'a, UnsafeCell<MapRef>>,
    ptr: *mut MapRef,
}

impl<'a> MapRefGuard<'a> {
    pub(crate) fn as_ref(&self) -> &MapRef {
        unsafe { &*self.ptr }
    }

    pub(crate) fn as_mut(&mut self) -> &mut MapRef {
        unsafe { &mut *self.ptr }
    }
}

impl YrsMap {
    fn inner(&self) -> MapRefGuard<'_> {
        let guard = self.0.lock();
        let ptr = unsafe { (*self.0.data_ptr()).get() };
        MapRefGuard { _guard: guard, ptr }
    }
}

impl AsRef<Branch> for YrsMap {
    fn as_ref(&self) -> &Branch {
        //FIXME: after yrs v0.18 use logical references
        let guard = self.inner();
        let branch = guard.as_ref();
        unsafe { std::mem::transmute(branch.as_ref()) }
    }
}

// Provides the implementation for the From trait, supporting
// converting from a MapRef type into a YrsMap type.
impl From<MapRef> for YrsMap {
    fn from(value: MapRef) -> Self {
        let hook = value.hook();
        YrsMap(ReentrantMutex::new(UnsafeCell::new(value)), hook)
    }
}

#[derive(Debug, PartialEq)]
pub(crate) struct YrsMapEntry {
    pub key: String,
    pub value: String,
}

pub(crate) trait YrsMapObservationDelegate: Send + Sync + Debug {
    fn call(&self, value: Vec<YrsMapChange>);
}

/*
IMPL order:
- [X] [insert, len, contains_key]
- [X] [get, remove, clear]
- [X] [keys, values, iter]
- [ ] [observe, unobserve]
 */

impl YrsMap {
    pub(crate) fn raw_ptr(&self) -> YrsCollectionPtr {
        let guard = self.inner();
        YrsCollectionPtr::from(guard.as_ref().as_ref())
    }

    /// Inserts the key and value you provide into the map.
    pub(crate) fn insert(&self, transaction: &YrsTransaction, key: String, value: String) {
        // decodes the `value` as JSON and converts it into a lib0::Any enumeration
        let any_value = Any::from_json(value.as_str()).unwrap();

        // acquire a *mutable* transaction
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();

        // pull out a mutable reference to the YrsMap this type wraps
        let mut map = self.inner();
        // insert into the wrapped map.
        map.as_mut().insert(tx, key, any_value);

        // Documentation note from YrsMap about inserting a preliminary type - for future
        // reference...
        // // insert nested shared type
        // let nested = map.insert(&mut txn, "key2", MapPrelim::from([("inner", "value2")]));
        // nested.insert(&mut txn, "inner2", 100);
    }

    /// Returns the size of the map.
    pub(crate) fn length(&self, transaction: &YrsTransaction) -> u32 {
        let map = self.inner();
        // acquire a transaction, but we don't need to borrow it since we're
        // not mutating anything in this method.
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        // If we try and do the above on a single line, I get the error:
        // creates a temporary value which is freed while still in use

        map.as_ref().len(tx)
    }

    /// Returns a Boolean value that indicates whether the map contains the key you provide.
    pub(crate) fn contains_key(&self, transaction: &YrsTransaction, key: String) -> bool {
        let map = self.inner();
        // acquire a transaction, but we don't need to borrow it since we're
        // not mutating anything in this method.
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();

        map.as_ref().contains_key(tx, key.as_str())
    }

    pub(crate) fn get(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Result<String, CodingError> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();
        let v = map.as_ref().get(tx, key.as_str()).unwrap();
        let mut buf = String::new();
        if let Out::Any(any) = v {
            any.to_json(&mut buf);
            Ok(buf)
        } else {
            Err(CodingError::EncodingError)
        }
    }

    pub(crate) fn remove(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Result<Option<String>, CodingError> {
        // acquire a *mutable* transaction
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();

        // get a mutable reference to the YrsMap this type wraps
        let mut map = self.inner();

        let optional_value = map.as_mut().remove(tx, key.as_str());
        match optional_value {
            // there was some kind of value in the map, try to cast it and convert
            // to JSON
            Some(v) => {
                if let Out::Any(any) = v {
                    let mut buf = String::new();
                    any.to_json(&mut buf);
                    return Ok(Some(buf));
                } else {
                    return Err(CodingError::EncodingError);
                }
            }
            // No value returned from the map on remove, so return the Optional
            // string as None.
            None => {
                return Ok(None);
            }
        }
    }

    pub(crate) fn clear(&self, transaction: &YrsTransaction) {
        // acquire a *mutable* transaction
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();

        // get a mutable reference to the YrsMap this type wraps
        let mut map = self.inner();

        map.as_mut().clear(tx);
    }

    pub(crate) fn keys(&self, transaction: &YrsTransaction) -> Vec<String> {
        let binding = transaction.transaction();
        let txn = binding.as_ref().unwrap();
        let map = self.inner();
        map.as_ref().keys(txn).map(str::to_owned).collect()
    }

    /// Returns owned JSON entries, excluding nested shared types and subdocuments.
    pub(crate) fn entries(&self, transaction: &YrsTransaction) -> Vec<YrsMapEntry> {
        let binding = transaction.transaction();
        let txn = binding.as_ref().unwrap();
        let map = self.inner();
        map.as_ref().iter(txn).filter_map(|(key, value)| {
            let Out::Any(any) = value else { return None; };
            let mut value = String::new();
            any.to_json(&mut value);
            Some(YrsMapEntry { key: key.to_owned(), value })
        }).collect()
    }

    pub(crate) fn observe(&self, transaction: &YrsTransaction, key: String, delegate: Box<dyn YrsMapObservationDelegate>) -> bool {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        let Some(source) = self.1.get(tx) else { return false; };
        source.observe(key.as_str(), move |transaction, event| {
            let delta = event.keys(transaction);
            // Nested shared types are observed through their own collections.
            let result = delta.iter().filter_map(|(key, value)| try_from_entry_change(key, value)).collect();
            delegate.call(result);
        });
        true
    }

    pub(crate) fn unobserve(&self, transaction: &YrsTransaction, key: String) -> bool {
        let tx = transaction.transaction();
        let tx = tx.as_ref().unwrap();
        self.1.get(tx).is_some_and(|source| source.unobserve(key.as_str()))
    }

    // MARK: - Subdoc methods

    /// Gets a subdocument for the specified key.
    /// Returns None if the key doesn't exist or the value is not a document.
    pub(crate) fn get_doc(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsDoc>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YDoc(doc)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsDoc::from_doc(doc)))
        } else {
            None
        }
    }

    /// Inserts a subdocument with the specified key.
    /// Returns a reference to the integrated subdocument.
    pub(crate) fn insert_doc(
        &self,
        transaction: &YrsTransaction,
        key: String,
        doc: &YrsDoc,
    ) -> Arc<YrsDoc> {
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        // Clone the inner Doc and insert it
        let inner_doc = doc.inner().clone();
        let inserted = map.as_mut().insert(tx, key, inner_doc);
        Arc::new(YrsDoc::from_doc(inserted))
    }

    // MARK: - Nested shared type methods

    /// Gets a nested YMap for the specified key.
    /// Returns None if the key doesn't exist or the value is not a map.
    pub(crate) fn get_map(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsMap>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YMap(nested)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsMap::from(nested)))
        } else {
            None
        }
    }

    /// Gets a nested YArray for the specified key.
    /// Returns None if the key doesn't exist or the value is not an array.
    pub(crate) fn get_array(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsArray>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YArray(nested)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsArray::from(nested)))
        } else {
            None
        }
    }

    /// Gets a nested YText for the specified key.
    /// Returns None if the key doesn't exist or the value is not text.
    pub(crate) fn get_text(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Option<Arc<YrsText>> {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        if let Some(Out::YText(nested)) = map.as_ref().get(tx, key.as_str()) {
            Some(Arc::new(YrsText::from(nested)))
        } else {
            None
        }
    }

    /// Checks if the value at the specified key is an undefined reference.
    /// Returns true if the key exists but holds an undefined/deleted reference.
    pub(crate) fn is_undefined(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> bool {
        let binding = transaction.transaction();
        let tx = binding.as_ref().unwrap();
        let map = self.inner();

        matches!(map.as_ref().get(tx, key.as_str()), Some(Out::UndefinedRef(_)))
    }

    /// Inserts an empty nested YMap at the specified key.
    /// Returns a reference to the inserted map.
    pub(crate) fn insert_map(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsMap> {
        use yrs::MapPrelim;

        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        let prelim: MapPrelim = Default::default();
        let nested: MapRef = map.as_mut().insert(tx, key, prelim);
        Arc::new(YrsMap::from(nested))
    }

    /// Inserts an empty nested YArray at the specified key.
    /// Returns a reference to the inserted array.
    pub(crate) fn insert_array(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsArray> {
        use yrs::{ArrayPrelim, ArrayRef};

        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        let nested: ArrayRef = map.as_mut().insert(tx, key, ArrayPrelim::default());
        Arc::new(YrsArray::from(nested))
    }

    /// Inserts an empty nested YText at the specified key.
    /// Returns a reference to the inserted text.
    pub(crate) fn insert_text(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsText> {
        use yrs::{TextPrelim, TextRef};

        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();

        let nested: TextRef = map.as_mut().insert(tx, key, TextPrelim::new(""));
        Arc::new(YrsText::from(nested))
    }

    /// Updates value only if different from current. Returns true if updated.
    pub(crate) fn try_update(
        &self,
        transaction: &YrsTransaction,
        key: String,
        value: String,
    ) -> bool {
        use yrs::Map;
        let any_value = Any::from_json(value.as_str()).unwrap();
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        map.as_mut().try_update(tx, key, any_value)
    }

    /// Gets existing nested map or creates new one at key.
    pub(crate) fn get_or_insert_map(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsMap> {
        use yrs::Map;
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        let nested: MapRef = map.as_mut().get_or_init(tx, key.as_str());
        Arc::new(YrsMap::from(nested))
    }

    /// Gets existing nested array or creates new one at key.
    pub(crate) fn get_or_insert_array(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsArray> {
        use yrs::{ArrayRef, Map};
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        let nested: ArrayRef = map.as_mut().get_or_init(tx, key.as_str());
        Arc::new(YrsArray::from(nested))
    }

    /// Gets existing nested text or creates new one at key.
    pub(crate) fn get_or_insert_text(
        &self,
        transaction: &YrsTransaction,
        key: String,
    ) -> Arc<YrsText> {
        use yrs::{Map, TextRef};
        let mut binding = transaction.transaction();
        let tx = binding.as_mut().unwrap();
        let mut map = self.inner();
        let nested: TextRef = map.as_mut().get_or_init(tx, key.as_str());
        Arc::new(YrsText::from(nested))
    }
}

#[cfg(test)]
mod tests {
    use crate::YrsDoc;
    use super::YrsMapEntry;

    #[test]
    fn iteration_snapshots_own_values_and_filter_nested_types() {
        let (mut keys, mut entries) = {
            let doc = YrsDoc::new();
            let map = doc.get_map("map".into());
            let txn = doc.transact(None);
            map.insert(&txn, "text".into(), "\"hello\"".into());
            map.insert(&txn, "number".into(), "42".into());
            map.insert(&txn, "null".into(), "null".into());
            map.insert_array(&txn, "array".into());
            map.insert_map(&txn, "map".into());
            map.insert_text(&txn, "rich-text".into());
            map.insert_doc(&txn, "document".into(), &YrsDoc::new());
            let keys = map.keys(&txn);
            let entries = map.entries(&txn);
            map.clear(&txn);
            assert!(map.keys(&txn).is_empty());
            assert!(map.entries(&txn).is_empty());
            txn.free();
            (keys, entries)
        };
        keys.sort();
        entries.sort_by(|a, b| a.key.cmp(&b.key));
        assert_eq!(keys, ["array", "document", "map", "null", "number", "rich-text", "text"]);
        assert_eq!(entries, vec![
            YrsMapEntry { key: "null".into(), value: "null".into() },
            YrsMapEntry { key: "number".into(), value: "42".into() },
            YrsMapEntry { key: "text".into(), value: "\"hello\"".into() },
        ]);
    }

    #[test]
    fn verify_new_map_has_zero_count() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let txn = doc.transact(None);
        assert_eq!(map.length(&txn), 0);
    }

    #[test]
    fn map_insert_and_count() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        assert_eq!(map.contains_key(&txn, key_to_insert.clone()), false);

        map.insert(&txn, key_to_insert.clone(), value_to_insert);
        assert_eq!(map.length(&txn), 1);

        assert_eq!(map.contains_key(&txn, key_to_insert), true);
    }

    #[test]
    fn map_insert_and_get() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        assert_eq!(map.contains_key(&txn, key_to_insert.clone()), false);

        map.insert(&txn, key_to_insert.clone(), value_to_insert.clone());
        assert_eq!(map.length(&txn), 1);

        let result = map.get(&txn, key_to_insert.clone()).unwrap();
        assert_eq!(result, value_to_insert);
    }

    #[test]
    fn map_remove() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        assert_eq!(map.contains_key(&txn, key_to_insert.clone()), false);

        map.insert(&txn, key_to_insert.clone(), value_to_insert.clone());

        let returned = map.remove(&txn, key_to_insert.clone());
        let unwrapped_return = returned.unwrap();
        assert_eq!(unwrapped_return, Some(value_to_insert.clone()));
        assert_eq!(map.length(&txn), 0);
    }

    #[test]
    fn map_clear() {
        let doc = YrsDoc::new();
        let map = doc.get_map("example_map".to_string());

        let key_to_insert = "AB123".to_string();
        let value_to_insert = "\"Hello\"".to_string();

        let txn = doc.transact(None);

        map.insert(&txn, key_to_insert.clone(), value_to_insert.clone());
        assert_eq!(map.length(&txn), 1);

        map.clear(&txn);
        assert_eq!(map.length(&txn), 0);
    }


}
