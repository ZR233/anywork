//! Passive source registration. Slots outlive every execution incarnation, including absence.

use std::sync::{Arc, Mutex};
use tokio::sync::watch;

struct SlotState {
    bus: Option<crate::timeline::MetaEventBus>,
    last_turn: Option<Arc<crate::Turn>>,
    feeds: Option<Vec<crate::timeline::FeedCloseHandle>>,
}

/// Passive per-thread handle slot linking resident `MetaEventBus` instances and active
/// `ConversationFeed` handles for seamless cold->live attachment, deletion, and shutdown.
pub(in crate::studio::runtime) struct ObservationSlot {
    state: Mutex<SlotState>,
    bus_tx: watch::Sender<Option<crate::timeline::MetaEventBus>>,
}

impl Default for ObservationSlot {
    fn default() -> Self {
        let (bus_tx, _) = watch::channel(None);
        Self {
            state: Mutex::new(SlotState {
                bus: None,
                last_turn: None,
                feeds: Some(Vec::new()),
            }),
            bus_tx,
        }
    }
}

impl ObservationSlot {
    pub(in crate::studio::runtime) fn register_feed(
        &self,
        handle: crate::timeline::FeedCloseHandle,
    ) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(feeds) = state.feeds.as_mut() {
            feeds.retain(|entry| !entry.is_closed());
            feeds.push(handle);
        } else {
            drop(state);
            handle.request_close();
        }
    }

    pub(in crate::studio::runtime) async fn close_readers(&self) -> anyhow::Result<()> {
        let feeds = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feeds
            .take()
            .unwrap_or_default();
        for handle in feeds {
            handle.close().await;
        }
        Ok(())
    }

    pub(in crate::studio::runtime) fn install_bus(&self, bus: crate::timeline::MetaEventBus) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.bus = Some(bus.clone());
        self.bus_tx.send_replace(Some(bus));
    }

    pub(in crate::studio::runtime) fn retire_bus(&self, bus: &crate::timeline::MetaEventBus) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state
            .bus
            .as_ref()
            .is_some_and(|current| current.ptr_eq(bus))
        {
            state.bus = None;
            self.bus_tx.send_replace(None);
        }
    }

    pub(in crate::studio::runtime) fn meta_bus(&self) -> Option<crate::timeline::MetaEventBus> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .bus
            .clone()
    }

    pub(in crate::studio::runtime) fn subscribe_bus(
        &self,
    ) -> watch::Receiver<Option<crate::timeline::MetaEventBus>> {
        self.bus_tx.subscribe()
    }

    pub(in crate::studio::runtime) fn set_last_turn(&self, turn: Arc<crate::Turn>) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .last_turn = Some(turn);
    }

    pub(in crate::studio::runtime) fn last_turn(&self) -> Option<Arc<crate::Turn>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .last_turn
            .clone()
    }
}
