//! Passive source registration. Slots outlive every execution incarnation, including absence.

use std::sync::{Arc, Mutex};
use tokio::sync::watch;

use super::ThreadLiveFeed;

#[derive(Clone)]
pub(in crate::studio::runtime) struct SourcePosition {
    pub epoch: u64,
    pub source: Option<Arc<ThreadLiveFeed>>,
}

/// 执行状态观察的登记屏障及会话读取的显式撤销入口。
/// 内容读取由稳定 Store 持有，不用这里的执行代际判断内容连续性。
pub(in crate::studio::runtime) struct ObservationSlot {
    state: Mutex<SourcePosition>,
    changed: watch::Sender<u64>,
    readers: Mutex<Option<Vec<std::sync::Weak<super::super::conversation_reader::ReadLease>>>>,
}

impl Default for ObservationSlot {
    fn default() -> Self {
        Self {
            state: Mutex::new(SourcePosition {
                epoch: 0,
                source: None,
            }),
            changed: watch::channel(0).0,
            readers: Mutex::new(Some(Vec::new())),
        }
    }
}

impl ObservationSlot {
    pub(in crate::studio::runtime) fn register_reader(
        &self,
        reader: &super::super::ConversationReader,
    ) {
        let mut readers = self
            .readers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(readers) = readers.as_mut() {
            readers.retain(|reader| reader.strong_count() > 0);
            readers.push(Arc::downgrade(&reader.inner));
        } else {
            reader.request_close();
        }
    }

    pub(in crate::studio::runtime) async fn close_readers(&self) -> anyhow::Result<()> {
        let readers = self
            .readers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
            .unwrap_or_default()
            .into_iter()
            .filter_map(|reader| reader.upgrade())
            .map(|inner| super::super::ConversationReader { inner })
            .collect::<Vec<_>>();
        for reader in &readers {
            reader.request_close();
        }
        for reader in readers {
            reader.close().await?;
        }
        Ok(())
    }

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
        let source = Arc::new(ThreadLiveFeed::new(None, progress, Default::default()));
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
        let old = Arc::new(ThreadLiveFeed::new(None, old_progress, Default::default()));
        let new = Arc::new(ThreadLiveFeed::new(None, new_progress, Default::default()));
        slot.install(old.clone());
        slot.install(new.clone());
        let (position, _) = slot.capture();
        slot.retire(&old);
        assert!(slot.is_current(position.epoch));
        assert!(Arc::ptr_eq(&slot.source().unwrap(), &new));
    }
}
