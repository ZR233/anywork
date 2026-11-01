//! Passive source registration. Slots outlive every execution incarnation, including absence.

use std::sync::{Arc, Mutex};
use tokio::sync::watch;

use super::ThreadLiveFeed;

#[derive(Clone)]
pub(in crate::studio::runtime) struct SourcePosition {
    pub epoch: u64,
    pub source: Option<Arc<ThreadLiveFeed>>,
}

/// The slot, rather than the current source pointer, is the observation registration barrier.
/// A cold read captures absence and must revalidate the same epoch after IO.
pub(in crate::studio::runtime) struct ObservationSlot {
    state: Mutex<SourcePosition>,
    changed: watch::Sender<u64>,
}

impl Default for ObservationSlot {
    fn default() -> Self {
        Self {
            state: Mutex::new(SourcePosition {
                epoch: 0,
                source: None,
            }),
            changed: watch::channel(0).0,
        }
    }
}

impl ObservationSlot {
    pub(in crate::studio::runtime) fn capture(&self) -> (SourcePosition, watch::Receiver<u64>) {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Subscribe under the publication lock, before releasing the captured position.
        (state.clone(), self.changed.subscribe())
    }

    pub(in crate::studio::runtime) fn is_current(&self, epoch: u64) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Overflow permanently closes continuity; it never reuses a readable incarnation.
        epoch != u64::MAX && state.epoch == epoch
    }

    pub(super) fn source(&self) -> Option<Arc<ThreadLiveFeed>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .source
            .clone()
    }

    pub(in crate::studio::runtime) fn install(&self, source: Arc<ThreadLiveFeed>) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.epoch = state.epoch.saturating_add(1);
        state.source = (state.epoch != u64::MAX).then_some(source);
        self.changed.send_replace(state.epoch);
    }

    pub(in crate::studio::runtime) fn retire(&self, source: &Arc<ThreadLiveFeed>) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state
            .source
            .as_ref()
            .is_some_and(|current| Arc::ptr_eq(current, source))
        {
            state.epoch = state.epoch.saturating_add(1);
            state.source = None;
            self.changed.send_replace(state.epoch);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absent_live_absent_never_reuses_a_cold_read_position() {
        let slot = ObservationSlot::default();
        let (absent, mut changes) = slot.capture();
        let (_owner, progress) = watch::channel(Default::default());
        let source = Arc::new(ThreadLiveFeed::new(None, progress));
        slot.install(source.clone());
        slot.retire(&source);
        assert!(!slot.is_current(absent.epoch));
        let (after, _) = slot.capture();
        assert!(after.source.is_none());
        assert_eq!(after.epoch, absent.epoch + 2);
        assert_eq!(*changes.borrow_and_update(), after.epoch);
    }

    #[test]
    fn retiring_an_old_owner_cannot_clear_a_new_incarnation() {
        let slot = ObservationSlot::default();
        let (_old_owner, old_progress) = watch::channel(Default::default());
        let (_new_owner, new_progress) = watch::channel(Default::default());
        let old = Arc::new(ThreadLiveFeed::new(None, old_progress));
        let new = Arc::new(ThreadLiveFeed::new(None, new_progress));
        slot.install(old.clone());
        slot.install(new.clone());
        let (position, _) = slot.capture();
        slot.retire(&old);
        assert!(slot.is_current(position.epoch));
        assert!(Arc::ptr_eq(&slot.source().unwrap(), &new));
    }
}
