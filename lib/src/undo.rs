use std::fmt::Debug;
use std::sync::{Arc, Mutex, MutexGuard};
use yrs::undo::EventKind;
use yrs::{Doc, Transact};
use crate::doc::{YrsCollectionPtr, YrsOrigin};

pub(crate) struct YrsUndoManager(Mutex<yrs::undo::UndoManager<u64>>, Doc);

unsafe impl Send for YrsUndoManager {}
unsafe impl Sync for YrsUndoManager {}


impl YrsUndoManager {
    pub(crate) fn new(manager: yrs::undo::UndoManager<u64>, doc: Doc) -> Self {
        Self(Mutex::new(manager), doc)
    }


    #[inline]
    fn acquire_lock(&self) -> MutexGuard<'_, yrs::undo::UndoManager<u64>> {
        // unwrap should be safe, as the only occasion to cause error would be a panic
        // while holding a lock and all operations holding a lock here only do so for
        // a time needed to perform a non-panicing operation
        self.0.lock().unwrap()
    }

    pub(crate) fn add_origin(&self, origin: YrsOrigin) {
        let mut m = self.acquire_lock();
        m.include_origin(origin)
    }

    pub(crate) fn remove_origin(&self, origin: YrsOrigin) {
        let mut m = self.acquire_lock();
        m.exclude_origin(origin);
    }

    pub(crate) fn add_scope(&self, tracked_ref: YrsCollectionPtr) {
        let mut m = self.acquire_lock();
        m.expand_scope(&self.1, &tracked_ref);
    }

    pub(crate) fn undo(&self) -> Result<bool, YrsUndoError> {
        let mut m = self.acquire_lock();
        Ok(m.undo_blocking())
    }

    pub(crate) fn redo(&self) -> Result<bool, YrsUndoError> {
        let mut m = self.acquire_lock();
        Ok(m.redo_blocking())
    }

    pub(crate) fn clear(&self) -> Result<(), YrsUndoError> {
        let mut m = self.acquire_lock();
        m.clear_all();
        Ok(())
    }

    pub(crate) fn wrap_changes(&self) {
        let mut m = self.acquire_lock();
        m.reset();
    }

    pub(crate) fn observe_added(&self, key: String, delegate: Box<dyn YrsUndoManagerObservationDelegate>) -> Result<(), YrsUndoError> {
        let mut m = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        // Document commits dispatch undo callbacks without taking the wrapper mutex.
        let _tx = self.1.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?;
        m.observe_item_added(key.as_str(), move |_, e| {
            *e.meta_mut() = delegate.call(YrsUndoEvent::new(e), *e.meta_mut());
        });
        Ok(())
    }

    pub(crate) fn unobserve_added(&self, key: String) -> Result<bool, YrsUndoError> {
        let mut m = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        let _tx = self.1.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?;
        Ok(m.unobserve_item_added(key.as_str()))
    }

    pub(crate) fn observe_updated(&self, key: String, delegate: Box<dyn YrsUndoManagerObservationDelegate>) -> Result<(), YrsUndoError> {
        let mut m = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        // Document commits dispatch undo callbacks without taking the wrapper mutex.
        let _tx = self.1.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?;
        m.observe_item_updated(key.as_str(), move |_, e| {
            *e.meta_mut() = delegate.call(YrsUndoEvent::new(e), *e.meta_mut());
        });
        Ok(())
    }

    pub(crate) fn unobserve_updated(&self, key: String) -> Result<bool, YrsUndoError> {
        let mut m = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        let _tx = self.1.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?;
        Ok(m.unobserve_item_updated(key.as_str()))
    }

    pub(crate) fn observe_popped(&self, key: String, delegate: Box<dyn YrsUndoManagerObservationDelegate>) -> Result<(), YrsUndoError> {
        let mut m = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        // Document commits dispatch undo callbacks without taking the wrapper mutex.
        let _tx = self.1.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?;
        m.observe_item_popped(key.as_str(), move |_, e| {
            *e.meta_mut() = delegate.call(YrsUndoEvent::new(e), *e.meta_mut());
        });
        Ok(())
    }

    pub(crate) fn unobserve_popped(&self, key: String) -> Result<bool, YrsUndoError> {
        let mut m = self.0.try_lock().map_err(|_| YrsUndoError::PendingTransaction)?;
        let _tx = self.1.try_transact().map_err(|_| YrsUndoError::PendingTransaction)?;
        Ok(m.unobserve_item_popped(key.as_str()))
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum YrsUndoError {
    #[error("Operations failed - there's already an active transaction on a current document")]
    PendingTransaction
}

pub(crate) trait YrsUndoManagerObservationDelegate: Send + Sync + Debug {
    fn call(&self, e: Arc<YrsUndoEvent>, ptr: u64) -> u64;
}

pub(crate) struct YrsUndoEvent {
    inner: &'static mut yrs::undo::Event<u64>,
}

unsafe impl Send for YrsUndoEvent {}
unsafe impl Sync for YrsUndoEvent {}

impl YrsUndoEvent {
    fn new(inner: &mut yrs::undo::Event<u64>) -> Arc<Self> {
        let inner = unsafe { std::mem::transmute(inner) };
        Arc::new(YrsUndoEvent {
            inner
        })
    }

    pub(crate) fn origin(&self) -> Option<YrsOrigin> {
        self.inner.origin().cloned().map(YrsOrigin::from)
    }
    pub(crate) fn kind(&self) -> YrsUndoEventKind {
        match self.inner.kind() {
            EventKind::Undo => YrsUndoEventKind::Undo,
            EventKind::Redo => YrsUndoEventKind::Redo,
        }
    }
    pub(crate) fn has_changed(&self, shared_ref: YrsCollectionPtr) -> bool {
        self.inner.has_changed(&shared_ref)
    }
}

#[repr(u8)]
pub(crate) enum YrsUndoEventKind {
    Undo,
    Redo
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
