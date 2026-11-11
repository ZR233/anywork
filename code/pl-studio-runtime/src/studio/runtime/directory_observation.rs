//! Pull-only, complete observations of a fixed directory demand.

use std::sync::Arc;

use anyhow::Result;
use pl_protocol::studio::{
    StudioError, StudioErrorCode, ThreadDirectoryFrame, ThreadDirectoryQuery,
    ThreadDirectoryWindow, ThreadMetadataFrame,
};
use tokio::sync::{Mutex, watch};
use tokio_util::sync::CancellationToken;

use super::StudioRuntime;
use crate::StudioProductTopic;
use crate::studio::product_event_bus::{ProductEventBus, ThreadMetadataSignal};
use crate::studio::store::directory::ThreadDirectoryCursor;

#[cfg(test)]
mod tests;

enum DirectorySignal {
    Structure(watch::Receiver<()>),
    Metadata(ThreadMetadataSignal),
}

impl DirectorySignal {
    fn receiver(&mut self) -> &mut watch::Receiver<()> {
        match self {
            Self::Structure(receiver) => receiver,
            Self::Metadata(signal) => signal.receiver(),
        }
    }
}

struct ReadState<T> {
    signal: Option<DirectorySignal>,
    initial: bool,
    last: Option<T>,
}

impl<T> ReadState<T> {
    fn new(signal: DirectorySignal) -> Self {
        Self {
            signal: Some(signal),
            initial: true,
            last: None,
        }
    }

    async fn ready(&mut self, cancellation: &CancellationToken) -> bool {
        if cancellation.is_cancelled() {
            return false;
        }
        if !self.initial {
            let Some(signal) = self.signal.as_mut() else {
                return false;
            };
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => return false,
                changed = signal.receiver().changed() => if changed.is_err() { return false; },
            }
        }
        self.initial = false;
        if let Some(signal) = self.signal.as_mut() {
            // Consume before reading, so a mutation during the read remains pending.
            signal.receiver().borrow_and_update();
        }
        true
    }
}

#[derive(Clone)]
pub struct ThreadsObservation {
    inner: Arc<ThreadsInner>,
}

struct ThreadsInner {
    events: ProductEventBus,
    epoch: String,
    query: ThreadDirectoryQuery,
    window: ThreadDirectoryWindow,
    cancellation: CancellationToken,
    next: Mutex<ReadState<(Vec<String>, Option<String>)>>,
}

#[derive(Clone)]
pub struct ThreadMetadataObservation {
    inner: Arc<MetadataInner>,
}

struct MetadataInner {
    events: ProductEventBus,
    epoch: String,
    thread_id: String,
    cancellation: CancellationToken,
    next: Mutex<ReadState<Option<pl_protocol::SessionDirectoryRow>>>,
}

impl StudioRuntime {
    pub fn observe_threads(
        &self,
        query: ThreadDirectoryQuery,
        window: ThreadDirectoryWindow,
    ) -> Result<ThreadsObservation> {
        ThreadsObservation::open(
            self.agent_facility.product_events.clone(),
            self.owner_epoch.clone(),
            query,
            window,
        )
    }

    pub fn observe_thread(&self, thread_id: String) -> Result<ThreadMetadataObservation> {
        ThreadMetadataObservation::open(
            self.agent_facility.product_events.clone(),
            self.owner_epoch.clone(),
            thread_id,
        )
    }
}

impl ThreadsObservation {
    fn open(
        events: ProductEventBus,
        epoch: String,
        query: ThreadDirectoryQuery,
        window: ThreadDirectoryWindow,
    ) -> Result<Self> {
        let query = query.normalized()?;
        window.validate()?;
        if window
            .before
            .as_ref()
            .is_some_and(|before| ThreadDirectoryCursor::decode(before).is_none())
        {
            return Err(StudioError::invalid_argument("Invalid directory boundary").into());
        }
        // Registration precedes every initial read, including an empty result.
        let next = Mutex::new(ReadState::new(DirectorySignal::Structure(
            events.subscribe_topic_signal(&StudioProductTopic::ThreadDirectory),
        )));
        Ok(ThreadsObservation {
            inner: Arc::new(ThreadsInner {
                events,
                epoch,
                query,
                window,
                cancellation: CancellationToken::new(),
                next,
            }),
        })
    }
}

impl ThreadMetadataObservation {
    fn open(events: ProductEventBus, epoch: String, thread_id: String) -> Result<Self> {
        if thread_id.trim().is_empty() {
            return Err(StudioError::invalid_argument("Thread identity is required").into());
        }
        let next = Mutex::new(ReadState::new(DirectorySignal::Metadata(
            events.subscribe_thread_metadata(&thread_id),
        )));
        Ok(ThreadMetadataObservation {
            inner: Arc::new(MetadataInner {
                events,
                epoch,
                thread_id,
                cancellation: CancellationToken::new(),
                next,
            }),
        })
    }
}

fn busy() -> StudioError {
    StudioError::new(
        StudioErrorCode::Busy,
        "A directory observation next read is already in flight",
        true,
    )
}

impl ThreadsObservation {
    pub async fn next(&self) -> Result<Option<ThreadDirectoryFrame>> {
        if self.inner.cancellation.is_cancelled() {
            return Ok(None);
        }
        let mut state = self.inner.next.try_lock().map_err(|_| busy())?;
        while state.ready(&self.inner.cancellation).await {
            let frame = self.inner.events.read_threads_window(
                &self.inner.query,
                &self.inner.window,
                &self.inner.epoch,
            )?;
            if state.last.as_ref().is_some_and(|(ids, cursor)| {
                ids == &frame.thread_ids && cursor == &frame.next_cursor
            }) {
                continue;
            }
            // No await separates the consistent owner read and delivery.
            state.last = Some((frame.thread_ids.clone(), frame.next_cursor.clone()));
            return Ok(Some(frame));
        }
        Ok(None)
    }

    pub fn request_close(&self) {
        self.inner.cancellation.cancel();
    }

    pub async fn close(&self) -> Result<()> {
        self.request_close();
        let mut state = self.inner.next.lock().await;
        state.signal.take();
        state.last.take();
        Ok(())
    }
}

impl ThreadMetadataObservation {
    pub async fn next(&self) -> Result<Option<ThreadMetadataFrame>> {
        if self.inner.cancellation.is_cancelled() {
            return Ok(None);
        }
        let mut state = self.inner.next.try_lock().map_err(|_| busy())?;
        while state.ready(&self.inner.cancellation).await {
            let frame = self
                .inner
                .events
                .read_thread_metadata(&self.inner.thread_id, &self.inner.epoch)?;
            if state.last.as_ref() == Some(&frame.row) {
                continue;
            }
            state.last = Some(frame.row.clone());
            return Ok(Some(frame));
        }
        Ok(None)
    }

    pub fn request_close(&self) {
        self.inner.cancellation.cancel();
    }

    pub async fn close(&self) -> Result<()> {
        self.request_close();
        let mut state = self.inner.next.lock().await;
        state.signal.take();
        state.last.take();
        Ok(())
    }
}
