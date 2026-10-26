//! Configuration of the original Thread observation. Only current, delivery windows and scopes
//! pin immutable details; a locator never follows a newer configuration with the same Thread ID.
mod capture;
mod delivery;
mod inputs;

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::thread_facets::configuration::ConfigurationValue;
use pl_protocol::thread_facets::identity::{
    ConfigurationReadRef, FeedClosedReason, ResyncReason, ThreadFacet, ThreadFacetStamp,
};
use tokio::sync::Notify;

use super::super::super::thread_reads::configuration::ConfigurationSource;
pub(in crate::studio::runtime) use delivery::ConfigurationDelivery;
pub use delivery::DeliveryStep;
pub(in crate::studio::runtime) use inputs::ConfigurationInputs;

struct ConfigurationSnapshot {
    stamp: ThreadFacetStamp,
    value: ConfigurationValue,
    source: Arc<ConfigurationSource>,
    source_bytes: usize,
}

struct Locator {
    source: Weak<ConfigurationSource>,
    born: u64,
    exposed_from: Option<u64>,
    retired_at: Option<u64>,
}

struct State {
    current: Option<Arc<ConfigurationSnapshot>>,
    capture_error: Option<StudioError>,
    terminal: Option<Terminal>,
    next_entry: u64,
    locators: BTreeMap<(u64, u64), Locator>,
    listeners: Vec<Weak<ConfigurationDelivery>>,
}

#[derive(Clone)]
enum Terminal {
    Failure(StudioError),
    Closed(FeedClosedReason),
}

pub(in crate::studio::runtime) struct ConfigurationProjection {
    epoch: String,
    incarnation: u64,
    state: Mutex<State>,
    changed: Notify,
}

impl ConfigurationProjection {
    pub(super) fn new(epoch: String, incarnation: u64) -> Self {
        Self {
            epoch,
            incarnation,
            state: Mutex::new(State {
                current: None,
                capture_error: None,
                terminal: None,
                next_entry: 1,
                locators: BTreeMap::new(),
                listeners: Vec::new(),
            }),
            changed: Notify::new(),
        }
    }

    pub(in crate::studio::runtime) fn matches_origin(&self, origin: &ThreadFacetStamp) -> bool {
        origin.facet == ThreadFacet::Configuration
            && origin.runtime_epoch == self.epoch
            && origin.incarnation == self.incarnation
    }

    pub(in crate::studio::runtime) fn ensure_open(&self) -> Result<(), StudioError> {
        ensure_open(
            &self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }

    pub(in crate::studio::runtime) async fn ready(&self) -> Result<(), StudioError> {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let state = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                ensure_open(&state)?;
                if let Some(error) = &state.capture_error {
                    return Err(error.clone());
                }
                if state.current.is_some() {
                    return Ok(());
                }
            }
            changed.await;
        }
    }

    pub(in crate::studio::runtime) fn close(&self, reason: FeedClosedReason) {
        self.finish(Terminal::Closed(reason));
    }
    pub(in crate::studio::runtime) fn fail(&self, error: StudioError) {
        self.finish(Terminal::Failure(error));
    }

    fn finish(&self, terminal: Terminal) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return;
        }
        state.terminal = Some(terminal.clone());
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.finish(terminal.clone());
        }
        drop(state);
        self.changed.notify_waiters();
    }

    pub(in crate::studio::runtime) fn resync(&self, reason: ResyncReason) {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.request_resync(reason);
        }
    }

    pub(in crate::studio::runtime) fn capture_failed(&self, error: StudioError) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return;
        }
        state.capture_error = Some(error);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.request_resync(ResyncReason::SourceLagged);
        }
        drop(state);
        self.changed.notify_waiters();
    }

    pub(in crate::studio::runtime) fn material_at(
        &self,
        reference: ConfigurationReadRef,
        origin: &ThreadFacetStamp,
    ) -> Result<Arc<ConfigurationSource>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        if !self.matches_origin(origin)
            || !state
                .current
                .as_ref()
                .is_some_and(|current| origin.revision <= current.stamp.revision)
        {
            return Err(superseded());
        }
        let locator = state
            .locators
            .get(&(reference.entry, reference.revision))
            .ok_or_else(superseded)?;
        if locator.born > origin.revision
            || locator.retired_at.is_some_and(|end| origin.revision >= end)
            || !locator
                .exposed_from
                .is_some_and(|first| first <= origin.revision)
        {
            return Err(superseded());
        }
        locator.source.upgrade().ok_or_else(superseded)
    }
}

fn ensure_open(state: &State) -> Result<(), StudioError> {
    match &state.terminal {
        Some(Terminal::Failure(error)) => Err(error.clone()),
        Some(Terminal::Closed(_)) => Err(cancelled()),
        None => Ok(()),
    }
}
pub(in crate::studio::runtime) fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Thread Configuration observation is closed",
        false,
    )
}
fn superseded() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The exact requested Thread Configuration source/ref is not available",
        false,
    )
}
fn exhausted() -> StudioError {
    StudioError::new(
        StudioErrorCode::Overloaded,
        "Thread Configuration identity or delivery budget is exhausted",
        false,
    )
}
