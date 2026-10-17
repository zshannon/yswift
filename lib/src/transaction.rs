use crate::array::YrsArray;
use crate::doc::{YrsDoc, YrsOrigin};
use crate::error::CodingError;
use crate::id_set::YrsIdSet;
use crate::map::YrsMap;
use crate::text::YrsText;
use parking_lot::ReentrantMutex;
use std::borrow::Borrow;
use std::cell::UnsafeCell;
use std::sync::Arc;
use yrs::{
    updates::decoder::Decode, updates::encoder::Encode, ReadTxn, StateVector, TransactionMut,
    Update,
};
use yrs::{Store, WriteTxn};

/// YrsTransaction wraps a yrs TransactionMut for use across the FFI boundary.
///
/// Uses ReentrantMutex<UnsafeCell<...>> because:
/// 1. ReentrantMutex provides thread safety for Swift's async runtime
/// 2. ReentrantMutex allows same-thread re-entry for observer callbacks
/// 3. UnsafeCell provides interior mutability - safe because ReentrantMutex
///    ensures exclusive access (only one thread at a time)
pub(crate) struct YrsTransaction(pub(crate) ReentrantMutex<UnsafeCell<Option<TransactionMut<'static>>>>);

// Safe because ReentrantMutex provides proper thread synchronization
unsafe impl Send for YrsTransaction {}
unsafe impl Sync for YrsTransaction {}

impl YrsTransaction {}

impl ReadTxn for YrsTransaction {
    fn store(&self) -> &Store {
        let _guard = self.0.lock();
        // SAFETY: ReentrantMutex ensures exclusive thread access
        let tx = unsafe { &mut *(*self.0.data_ptr()).get() };
        let tx = tx.as_mut().unwrap();
        unsafe { std::mem::transmute::<&mut Store, &'static Store>(tx.store_mut()) }
    }
}

impl<'doc> From<TransactionMut<'doc>> for YrsTransaction {
    fn from(txn: TransactionMut<'doc>) -> Self {
        let txn: TransactionMut<'static> = unsafe { std::mem::transmute(txn) };
        YrsTransaction(ReentrantMutex::new(UnsafeCell::new(Some(txn))))
    }
}

/// A guard that provides mutable access to the transaction.
/// Holds the ReentrantMutex lock for the duration of its lifetime.
pub(crate) struct TransactionGuard<'a> {
    _guard: parking_lot::ReentrantMutexGuard<'a, UnsafeCell<Option<TransactionMut<'static>>>>,
    ptr: *mut Option<TransactionMut<'static>>,
}

impl<'a> TransactionGuard<'a> {
    pub(crate) fn as_ref(&self) -> Option<&TransactionMut<'static>> {
        // SAFETY: We hold the lock via _guard
        unsafe { (*self.ptr).as_ref() }
    }

    pub(crate) fn as_mut(&mut self) -> Option<&mut TransactionMut<'static>> {
        // SAFETY: We hold the lock via _guard
        unsafe { (*self.ptr).as_mut() }
    }
}

impl YrsTransaction {
    /// Returns a guard that provides access to the inner transaction.
    /// The guard holds the ReentrantMutex lock for its lifetime.
    pub(crate) fn transaction(&self) -> TransactionGuard<'_> {
        let guard = self.0.lock();
        // Get pointer to the inner Option, not the UnsafeCell wrapper
        let ptr = unsafe { (*self.0.data_ptr()).get() };
        TransactionGuard { _guard: guard, ptr }
    }

    pub(crate) fn origin(&self) -> Option<YrsOrigin> {
        let guard = self.transaction();
        guard.as_ref()?.origin().cloned().map(YrsOrigin::from)
    }

    pub(crate) fn transaction_encode_update(&self) -> Vec<u8> {
        let guard = self.transaction();
        guard.as_ref().unwrap().encode_update_v1()
    }

    pub(crate) fn transaction_encode_state_as_update_from_sv(
        &self,
        state_vector: Vec<u8>,
    ) -> Result<Vec<u8>, CodingError> {
        let mut guard = self.transaction();
        let tx = guard.as_mut().unwrap();

        StateVector::decode_v1(state_vector.borrow())
            .map_err(|_e| CodingError::DecodingError)
            .map(|sv: StateVector| tx.encode_state_as_update_v1(&sv))
    }

    pub(crate) fn transaction_encode_state_as_update(&self) -> Vec<u8> {
        let mut guard = self.transaction();
        let tx = guard.as_mut().unwrap();
        tx.encode_state_as_update_v1(&StateVector::default())
    }

    pub(crate) fn transaction_state_vector(&self) -> Vec<u8> {
        let guard = self.transaction();
        guard.as_ref().unwrap().state_vector().encode_v1()
    }

    pub(crate) fn transaction_apply_update(&self, update: Vec<u8>) -> Result<(), CodingError> {
        Update::decode_v1(update.as_slice())
            .map_err(|_e| CodingError::DecodingError)
            .and_then(|u| {
                let mut guard = self.transaction();
                guard.as_mut()
                    .unwrap()
                    .apply_update(u)
                    .map_err(|_| CodingError::DecodingError)
            })
    }

    pub(crate) fn transaction_get_text(&self, name: String) -> Option<Arc<YrsText>> {
        let guard = self.transaction();
        guard.as_ref()
            .unwrap()
            .get_text(name.as_str())
            .map(YrsText::from)
            .map(Arc::from)
    }

    pub(crate) fn transaction_get_array(&self, name: String) -> Option<Arc<YrsArray>> {
        let guard = self.transaction();
        guard.as_ref()
            .unwrap()
            .get_array(name.as_str())
            .map(YrsArray::from)
            .map(Arc::from)
    }

    pub(crate) fn transaction_get_map(&self, name: String) -> Option<Arc<YrsMap>> {
        let guard = self.transaction();
        guard.as_ref()
            .unwrap()
            .get_map(name.as_str())
            .map(YrsMap::from)
            .map(Arc::from)
    }

    // MARK: - Subdoc methods

    /// Returns GUIDs of all subdocuments in this document.
    pub(crate) fn subdoc_guids(&self) -> Vec<String> {
        let guard = self.transaction();
        guard.as_ref()
            .map(|txn| txn.subdoc_guids().map(|g| g.to_string()).collect())
            .unwrap_or_default()
    }

    /// Returns all subdocuments in this document.
    pub(crate) fn subdocs(&self) -> Vec<Arc<YrsDoc>> {
        let guard = self.transaction();
        guard.as_ref()
            .map(|txn| {
                txn.subdocs()
                    .map(|d| Arc::new(YrsDoc::from_doc(d.clone())))
                    .collect()
            })
            .unwrap_or_default()
    }

    pub(crate) fn free(&self) {
        let _guard = self.0.lock();
        // SAFETY: We hold the lock
        unsafe { *(*self.0.data_ptr()).get() = None };
    }
}

/// Owned transaction data, valid beyond the callback or transaction lifetime.
pub(crate) struct YrsTransactionChanges {
    pub after_state: Vec<u8>,
    pub before_state: Vec<u8>,
    pub deletions: Arc<YrsIdSet>,
    pub document_guid: String,
    pub insertions: Arc<YrsIdSet>,
    pub origin: Option<YrsOrigin>,
}

impl YrsTransactionChanges {
    fn from_transaction(txn: &TransactionMut) -> Self {
        Self {
            // Snapshots may be taken before more changes are made in the same
            // transaction. Do not populate Yrs's cached post-commit state early.
            after_state: txn.state_vector().encode_v1(),
            before_state: txn.before_state().encode_v1(),
            deletions: Arc::new(YrsIdSet(txn.delete_set().clone())),
            document_guid: txn.doc().guid().to_string(),
            insertions: Arc::new(YrsIdSet(txn.insert_set().clone())),
            origin: txn.origin().cloned().map(YrsOrigin::from),
        }
    }
}

pub(crate) trait YrsBeforeObserverDelegate: Send + Sync + std::fmt::Debug {
    fn call(&self, changes: YrsTransactionChanges);
}

impl YrsTransaction {
    pub(crate) fn insert_set(&self) -> Arc<YrsIdSet> {
        let guard = self.transaction();
        Arc::new(YrsIdSet(guard.as_ref().unwrap().insert_set().clone()))
    }

    pub(crate) fn delete_set(&self) -> Arc<YrsIdSet> {
        let guard = self.transaction();
        Arc::new(YrsIdSet(guard.as_ref().unwrap().delete_set().clone()))
    }

    pub(crate) fn changes(&self) -> YrsTransactionChanges {
        let guard = self.transaction();
        YrsTransactionChanges::from_transaction(guard.as_ref().unwrap())
    }

    pub(crate) fn observe_before_observer_calls(&self, key: String, delegate: Box<dyn YrsBeforeObserverDelegate>) {
        let mut guard = self.transaction();
        guard.as_mut().unwrap().observe_before_observer_calls(key.as_str(), move |txn| {
            delegate.call(YrsTransactionChanges::from_transaction(txn));
        });
    }

    pub(crate) fn unobserve_before_observer_calls(&self, key: String) -> bool {
        let guard = self.transaction();
        guard.as_ref().unwrap().unobserve_before_observer_calls(key.as_str())
    }
}

#[cfg(test)]
mod snapshot_tests {
    use super::*;
    use std::sync::Mutex;
    use yrs::{Doc, Text, Transact};

    #[test]
    fn snapshots_do_not_cache_the_final_state_before_commit() {
        let doc = Doc::with_client_id(7);
        let text = doc.get_or_insert_text("text");
        let observed = Arc::new(Mutex::new(Vec::new()));
        let callback_observed = observed.clone();
        let mut txn = doc.transact_mut();
        txn.observe_before_observer_calls("snapshot", move |txn| {
            callback_observed.lock().unwrap().push(YrsTransactionChanges::from_transaction(txn));
        });

        text.push(&mut txn, "a");
        let early = YrsTransactionChanges::from_transaction(&txn);
        text.push(&mut txn, "b");
        let late = YrsTransactionChanges::from_transaction(&txn);

        let state = |bytes: &[u8]| StateVector::decode_v1(bytes).unwrap().get(&doc.client_id());
        assert_eq!(state(&early.before_state), 0);
        assert_eq!(state(&early.after_state), 1);
        assert_eq!(state(&late.before_state), 0);
        assert_eq!(state(&late.after_state), 2);
        assert_eq!(early.insertions.ranges()[0].length, 1);
        assert_eq!(late.insertions.ranges()[0].length, 2);
        assert_eq!(txn.after_state().get(&doc.client_id()), 2);
        drop(txn);

        let events = observed.lock().unwrap();
        assert_eq!(events.len(), 1);
        assert_eq!(state(&events[0].after_state), 2);
        assert_eq!(events[0].insertions.ranges()[0].length, 2);
    }
}
