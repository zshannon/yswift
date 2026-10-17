use std::fmt::Debug;
use std::sync::{Arc, Mutex};
use yrs::undo::{EventKind, Options};
use yrs::{Doc, Transact};
use crate::doc::{YrsCollectionPtr, YrsDoc, YrsOrigin};

// Swift serializes document commits and these operations on the same Swift global actor.
// Read transactions additionally reject synchronous callback re-entry and keep
// observer registration from racing with a document commit.
pub(crate) struct YrsUndoManager(Mutex<ManagerState>);

struct ManagerState {
    manager: yrs::undo::UndoManager<Option<Vec<u8>>>,
    documents: Vec<Doc>,
}

pub(crate) struct YrsUndoState {
    pub document_guids: Vec<String>,
    pub redo_count: u64,
    pub undo_count: u64,
}

pub(crate) trait YrsUndoClock: Send + Sync + Debug {
    fn now(&self) -> u64;
}

pub(crate) trait YrsUndoClearedDelegate: Send + Sync + Debug {
    fn call(&self, undo_cleared: bool, redo_cleared: bool);
}

impl YrsUndoManager {
    pub(crate) fn new(capture_timeout_millis: u64, clock: Option<Box<dyn YrsUndoClock>>) -> Self {
        let mut options = Options::default();
        options.capture_timeout_millis = capture_timeout_millis;
        if let Some(clock) = clock {
            options.timestamp = Arc::new(move || clock.now());
        }
        Self(Mutex::new(ManagerState {
            manager: yrs::undo::UndoManager::with_options(options),
            documents: Vec::new(),
        }))
    }

    fn with_manager<T>(&self, operation: impl FnOnce(&mut yrs::undo::UndoManager<Option<Vec<u8>>>) -> T) -> Result<T, YrsUndoError> {
        let mut state = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        let documents = state.documents.clone();
        let _transactions = documents.iter().map(|doc| doc.try_transact())
            .collect::<Result<Vec<_>, _>>().map_err(|_| YrsUndoError::PendingTransaction)?;
        Ok(operation(&mut state.manager))
    }

    // Swift actor isolation prevents a transaction from starting between this check and
    // the upstream operation, which acquires its own document transactions.
    fn with_document_operation<T>(&self, operation: impl FnOnce(&mut ManagerState) -> T) -> Result<T, YrsUndoError> {
        let mut state = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        for doc in &state.documents {
            drop(doc.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?);
        }
        Ok(operation(&mut state))
    }

    pub(crate) fn add_origin(&self, origin: YrsOrigin) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.include_origin(origin))
    }

    pub(crate) fn remove_origin(&self, origin: YrsOrigin) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.exclude_origin(origin))
    }

    pub(crate) fn add_scope(&self, doc: &YrsDoc, tracked_ref: YrsCollectionPtr) -> Result<(), YrsUndoError> {
        let doc = doc.inner();
        // Do not let upstream's GUID-keyed document map silently alias two replicas.
        self.with_document_operation(|state| {
            if state.documents.iter().any(|existing| existing.guid() == doc.guid() && !Doc::ptr_eq(existing, &doc)) {
                return Err(YrsUndoError::DuplicateDocument);
            }
            drop(doc.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?);
            state.manager.expand_scope(&doc, &tracked_ref);
            if !state.documents.iter().any(|existing| Doc::ptr_eq(existing, &doc)) {
                state.documents.push(doc);
            }
            Ok(())
        })?
    }

    pub(crate) fn state(&self) -> Result<YrsUndoState, YrsUndoError> {
        self.with_manager(|m| {
            let mut document_guids: Vec<_> = m.docs().map(|doc| doc.guid().to_string()).collect();
            document_guids.sort();
            YrsUndoState {
                document_guids,
                redo_count: m.redo_stack().len() as u64,
                undo_count: m.undo_stack().len() as u64,
            }
        })
    }

    pub(crate) fn undo(&self) -> Result<bool, YrsUndoError> {
        self.with_document_operation(|state| state.manager.undo_blocking())
    }

    pub(crate) fn redo(&self) -> Result<bool, YrsUndoError> {
        self.with_document_operation(|state| state.manager.redo_blocking())
    }

    pub(crate) fn clear(&self) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.clear_all())
    }

    pub(crate) fn clear_undo(&self) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.clear_undo())
    }

    pub(crate) fn clear_redo(&self) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.clear_redo())
    }

    pub(crate) fn wrap_changes(&self) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.reset())
    }

    pub(crate) fn observe_added(&self, key: String, delegate: Box<dyn YrsUndoManagerObservationDelegate>) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.observe_item_added(key.as_str(), move |txn, e| {
            let event = YrsUndoEvent::new(e, txn.doc());
            let metadata = e.meta_mut().take();
            *e.meta_mut() = delegate.call(event, metadata);
        }))
    }

    pub(crate) fn unobserve_added(&self, key: String) -> Result<bool, YrsUndoError> {
        self.with_manager(|m| m.unobserve_item_added(key.as_str()))
    }

    pub(crate) fn observe_updated(&self, key: String, delegate: Box<dyn YrsUndoManagerObservationDelegate>) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.observe_item_updated(key.as_str(), move |txn, e| {
            let event = YrsUndoEvent::new(e, txn.doc());
            let metadata = e.meta_mut().take();
            *e.meta_mut() = delegate.call(event, metadata);
        }))
    }

    pub(crate) fn unobserve_updated(&self, key: String) -> Result<bool, YrsUndoError> {
        self.with_manager(|m| m.unobserve_item_updated(key.as_str()))
    }

    pub(crate) fn observe_popped(&self, key: String, delegate: Box<dyn YrsUndoManagerObservationDelegate>) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.observe_item_popped(key.as_str(), move |txn, e| {
            let event = YrsUndoEvent::new(e, txn.doc());
            let metadata = e.meta_mut().take();
            *e.meta_mut() = delegate.call(event, metadata);
        }))
    }

    pub(crate) fn unobserve_popped(&self, key: String) -> Result<bool, YrsUndoError> {
        self.with_manager(|m| m.unobserve_item_popped(key.as_str()))
    }

    pub(crate) fn observe_cleared(&self, key: String, delegate: Box<dyn YrsUndoClearedDelegate>) -> Result<(), YrsUndoError> {
        self.with_manager(|m| m.observe_stack_cleared(key.as_str(), move |e| {
            delegate.call(e.undo_stack_cleared, e.redo_stack_cleared);
        }))
    }

    pub(crate) fn unobserve_cleared(&self, key: String) -> Result<bool, YrsUndoError> {
        self.with_manager(|m| m.unobserve_stack_cleared(key.as_str()))
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum YrsUndoError {
    #[error("An operation or transaction is already active on a tracked document")]
    PendingTransaction,
    #[error("Distinct tracked documents must have distinct GUIDs")]
    DuplicateDocument,
}

pub(crate) trait YrsUndoManagerObservationDelegate: Send + Sync + Debug {
    fn call(&self, e: Arc<YrsUndoEvent>, metadata: Option<Vec<u8>>) -> Option<Vec<u8>>;
}

// Own the event data: Swift observers and AsyncStream consumers may retain it
// after the native callback has returned.
pub(crate) struct YrsUndoEvent {
    changed_refs: Vec<YrsCollectionPtr>,
    document_guid: String,
    kind: YrsUndoEventKind,
    origin: Option<YrsOrigin>,
}

impl YrsUndoEvent {
    fn new(event: &yrs::undo::Event<Option<Vec<u8>>>, doc: &Doc) -> Arc<Self> {
        Arc::new(Self {
            changed_refs: event.changed_parent_types().iter().map(|ptr| YrsCollectionPtr::from(ptr.as_ref())).collect(),
            document_guid: doc.guid().to_string(),
            kind: match event.kind() { EventKind::Undo => YrsUndoEventKind::Undo, EventKind::Redo => YrsUndoEventKind::Redo },
            origin: event.origin().cloned().map(YrsOrigin::from),
        })
    }

    pub(crate) fn changed_refs(&self) -> Vec<YrsCollectionPtr> { self.changed_refs.clone() }
    pub(crate) fn document_guid(&self) -> String { self.document_guid.clone() }
    pub(crate) fn origin(&self) -> Option<YrsOrigin> { self.origin.clone() }
    pub(crate) fn kind(&self) -> YrsUndoEventKind { self.kind }
}

#[derive(Clone, Copy)]
pub(crate) enum YrsUndoEventKind {
    Undo,
    Redo,
}
#[cfg(test)]
mod lifetime_tests {
    use std::sync::{Arc, Barrier, Mutex};
    use yrs::undo::Options;
    use yrs::{Doc, GetString, Text, Transact, UndoManager};

    #[test]
    fn release_during_transaction() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let state_probe = Arc::new(());
        let released_state = Arc::downgrade(&state_probe);
        let mut manager = UndoManager::with_options(Options {
            timestamp: Arc::new(move || {
                let _ = &state_probe;
                1
            }),
            ..Options::default()
        });
        manager.expand_scope(&doc, &text);
        let probe = Arc::new(());
        let released = Arc::downgrade(&probe);
        manager.observe_item_added("capture", move |_, _| {
            let _ = &probe;
            panic!("released manager must not receive events");
        });
        let mut txn = doc.transact_mut();
        text.push(&mut txn, "a");
        drop(manager);
        assert!(released.upgrade().is_none());
        assert!(released_state.upgrade().is_none());
        text.push(&mut txn, "b");
        drop(txn);
        text.push(&mut doc.transact_mut(), "c");
        assert_eq!(text.get_string(&doc.transact()), "abc");
    }

    #[test]
    fn release_from_own_callback() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let state_probe = Arc::new(());
        let released_state = Arc::downgrade(&state_probe);
        let mut manager = UndoManager::with_options(Options {
            timestamp: Arc::new(move || {
                let _ = &state_probe;
                1
            }),
            ..Options::default()
        });
        manager.expand_scope(&doc, &text);
        let slot = Arc::new(Mutex::new(None));
        let release_slot = slot.clone();
        let probe = Arc::new(());
        let released = Arc::downgrade(&probe);
        let callback_state = released_state.clone();
        manager.observe_item_added("release", move |_, _| {
            drop(release_slot.lock().unwrap().take());
            // The clock capture belongs solely to Inner, not to this observer closure.
            assert!(callback_state.upgrade().is_some());
            // The callback and native metadata write must finish before state is freed.
            assert_eq!(Arc::strong_count(&probe), 1);
        });
        *slot.lock().unwrap() = Some(manager);
        text.push(&mut doc.transact_mut(), "a");
        assert!(slot.lock().unwrap().is_none());
        assert!(released.upgrade().is_none());
        assert!(released_state.upgrade().is_none());
        text.push(&mut doc.transact_mut(), "b");
        assert_eq!(text.get_string(&doc.transact()), "ab");
    }

    #[test]
    fn release_while_callback_runs_on_another_thread() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let state_probe = Arc::new(());
        let released_state = Arc::downgrade(&state_probe);
        let mut manager = UndoManager::with_options(Options {
            timestamp: Arc::new(move || {
                let _ = &state_probe;
                1
            }),
            ..Options::default()
        });
        manager.expand_scope(&doc, &text);
        let entered = Arc::new(Barrier::new(2));
        let resume = Arc::new(Barrier::new(2));
        let callback_entered = entered.clone();
        let callback_resume = resume.clone();
        let probe = Arc::new(());
        let released = Arc::downgrade(&probe);
        manager.observe_item_added("release", move |_, _| {
            callback_entered.wait();
            callback_resume.wait();
            assert_eq!(Arc::strong_count(&probe), 1);
        });
        let remote_doc = doc.clone();
        let remote_text = text.clone();
        let worker = std::thread::spawn(move || {
            remote_text.push(&mut remote_doc.transact_mut(), "a");
        });
        entered.wait();
        drop(manager);
        assert!(released.upgrade().is_some());
        assert!(released_state.upgrade().is_some());
        resume.wait();
        worker.join().unwrap();
        assert!(released.upgrade().is_none());
        assert!(released_state.upgrade().is_none());
        text.push(&mut doc.transact_mut(), "b");
        assert_eq!(text.get_string(&doc.transact()), "ab");
    }

    #[test]
    fn release_after_document_destroy() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let state_probe = Arc::new(());
        let released_state = Arc::downgrade(&state_probe);
        let mut manager = UndoManager::with_options(Options {
            timestamp: Arc::new(move || {
                let _ = &state_probe;
                1
            }),
            ..Options::default()
        });
        manager.expand_scope(&doc, &text);
        let probe = Arc::new(());
        let released = Arc::downgrade(&probe);
        manager.observe_item_added("capture", move |_, _| {
            let _ = &probe;
        });
        doc.destroy(None);
        assert_eq!(manager.docs().count(), 0);
        drop(manager);
        assert!(released.upgrade().is_none());
        assert!(released_state.upgrade().is_none());
    }
}

#[cfg(test)]
mod released_feature_tests {
    use super::*;
    use yrs::{GetString, Text, UndoManager};

    #[derive(Debug)]
    struct FixedClock;

    impl YrsUndoClock for FixedClock {
        fn now(&self) -> u64 { 1 }
    }

    #[derive(Debug)]
    struct MetadataDelegate {
        observed: Arc<Mutex<Vec<Option<Vec<u8>>>>>,
        replacement: Option<Vec<u8>>,
    }

    impl YrsUndoManagerObservationDelegate for MetadataDelegate {
        fn call(&self, _: Arc<YrsUndoEvent>, metadata: Option<Vec<u8>>) -> Option<Vec<u8>> {
            self.observed.lock().unwrap().push(metadata);
            self.replacement.clone()
        }
    }

    #[test]
    fn owned_metadata_round_trips_nil_empty_and_binary_values() {
        let doc = Doc::new();
        let text = doc.get_or_insert_text("text");
        let manager = YrsUndoManager::new(500, Some(Box::new(FixedClock)));
        manager.add_scope(&YrsDoc::from_doc(doc.clone()), YrsCollectionPtr::from(text.as_ref())).unwrap();
        let added = Arc::new(Mutex::new(Vec::new()));
        let updated = Arc::new(Mutex::new(Vec::new()));
        let popped = Arc::new(Mutex::new(Vec::new()));
        manager.observe_added("added".into(), Box::new(MetadataDelegate {
            observed: added.clone(), replacement: Some(vec![0, 128, 255]),
        })).unwrap();
        manager.observe_updated("updated".into(), Box::new(MetadataDelegate {
            observed: updated.clone(), replacement: Some(Vec::new()),
        })).unwrap();
        manager.observe_popped("popped".into(), Box::new(MetadataDelegate {
            observed: popped.clone(), replacement: None,
        })).unwrap();

        text.push(&mut doc.transact_mut(), "a");
        text.push(&mut doc.transact_mut(), "b");
        assert_eq!(*added.lock().unwrap(), vec![None]);
        assert_eq!(*updated.lock().unwrap(), vec![Some(vec![0, 128, 255])]);
        assert!(manager.undo().unwrap());
        assert_eq!(*popped.lock().unwrap(), vec![Some(Vec::new())]);
        assert!(manager.redo().unwrap());
        assert_eq!(*popped.lock().unwrap(), vec![Some(Vec::new()), Some(vec![0, 128, 255])]);
        manager.clear().unwrap();
    }

    #[test]
    fn selective_clear_preserves_the_other_stack() {
        for clear_undo in [true, false] {
            let doc = Doc::new();
            let text = doc.get_or_insert_text("text");
            let mut manager = UndoManager::with_options(Options {
                capture_timeout_millis: 0,
                timestamp: Arc::new(|| 1),
                ..Options::default()
            });
            manager.expand_scope(&doc, &text);
            text.push(&mut doc.transact_mut(), "a");
            text.push(&mut doc.transact_mut(), "b");
            assert!(manager.undo_blocking());
            if clear_undo { manager.clear_undo() } else { manager.clear_redo() }
            assert_eq!(manager.can_undo(), !clear_undo);
            assert_eq!(manager.can_redo(), clear_undo);
            if clear_undo {
                assert!(manager.redo_blocking());
                assert_eq!(text.get_string(&doc.transact()), "ab");
            } else {
                assert!(manager.undo_blocking());
                assert_eq!(text.get_string(&doc.transact()), "");
            }
        }
    }

    #[test]
    fn destroying_one_document_preserves_capture_and_redo_on_another() {
        let first = Doc::new();
        let second = Doc::new();
        let a = first.get_or_insert_text("text");
        let b = second.get_or_insert_text("text");
        let mut manager = UndoManager::with_options(Options {
            capture_timeout_millis: 0,
            timestamp: Arc::new(|| 1),
            ..Options::default()
        });
        manager.expand_scope(&first, &a);
        manager.expand_scope(&second, &b);
        a.push(&mut first.transact_mut(), "a");
        b.push(&mut second.transact_mut(), "b");
        second.destroy(None);
        assert!(manager.undo_blocking());
        assert!(manager.redo_blocking());
        assert_eq!(a.get_string(&first.transact()), "a");
        a.push(&mut first.transact_mut(), "c");
        assert!(manager.undo_blocking());
        assert_eq!(a.get_string(&first.transact()), "a");
    }
}
