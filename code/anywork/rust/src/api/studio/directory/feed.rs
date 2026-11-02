use super::{convert, types::*};
use crate::api::studio::bridge_runtime::{active_bridge, current_bridge};
use crate::api::studio::types::BridgeError;
use pl_studio_runtime::{ThreadMetadataObservation, ThreadsObservation};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use tokio_util::sync::CancellationToken;

pub async fn open_threads_observation(
    query: BridgeThreadDirectoryQuery,
    window: BridgeThreadDirectoryWindow,
) -> Result<BridgeThreadsObservation, BridgeError> {
    let bridge = active_bridge().await?;
    let observation = bridge.studio.observe_threads(query.into(), window.into())?;
    let inner = Arc::new(BridgeDirectoryObservationInner {
        id: bridge.subscriptions.next_id(),
        observation: DirectoryObservation::Threads(observation),
        shutdown: bridge.shutdown.child_token(),
        settled: AtomicBool::new(false),
        closing: AtomicBool::new(false),
        next_gate: tokio::sync::Mutex::new(()),
    });
    if let Err(error) = bridge
        .subscriptions
        .register_directory_observation(&inner, &bridge.shutdown)
    {
        inner.request_close();
        inner.close().await?;
        bridge
            .subscriptions
            .unregister_directory_observation(inner.id);
        return Err(error);
    }
    Ok(BridgeThreadsObservation { inner })
}

pub async fn open_thread_observation(
    thread_id: String,
) -> Result<BridgeThreadObservation, BridgeError> {
    let bridge = active_bridge().await?;
    let observation = bridge.studio.observe_thread(thread_id)?;
    let inner = Arc::new(BridgeDirectoryObservationInner {
        id: bridge.subscriptions.next_id(),
        observation: DirectoryObservation::Metadata(observation),
        shutdown: bridge.shutdown.child_token(),
        settled: AtomicBool::new(false),
        closing: AtomicBool::new(false),
        next_gate: tokio::sync::Mutex::new(()),
    });
    if let Err(error) = bridge
        .subscriptions
        .register_directory_observation(&inner, &bridge.shutdown)
    {
        inner.request_close();
        inner.close().await?;
        bridge
            .subscriptions
            .unregister_directory_observation(inner.id);
        return Err(error);
    }
    Ok(BridgeThreadObservation { inner })
}

pub struct BridgeThreadsObservation {
    inner: Arc<BridgeDirectoryObservationInner>,
}

pub struct BridgeThreadObservation {
    inner: Arc<BridgeDirectoryObservationInner>,
}

enum DirectoryObservation {
    Threads(ThreadsObservation),
    Metadata(ThreadMetadataObservation),
}

pub(crate) struct BridgeDirectoryObservationInner {
    pub(crate) id: u64,
    observation: DirectoryObservation,
    shutdown: CancellationToken,
    settled: AtomicBool,
    closing: AtomicBool,
    next_gate: tokio::sync::Mutex<()>,
}

impl BridgeDirectoryObservationInner {
    pub(crate) fn request_close(&self) {
        self.closing.store(true, Ordering::Release);
        match &self.observation {
            DirectoryObservation::Threads(observation) => observation.request_close(),
            DirectoryObservation::Metadata(observation) => observation.request_close(),
        }
    }

    pub(crate) fn is_settled(&self) -> bool {
        self.settled.load(Ordering::Acquire)
    }

    async fn next_threads(&self) -> Result<Option<BridgeThreadDirectoryFrame>, BridgeError> {
        if self.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let _next = self.next_gate.try_lock().map_err(|_| busy())?;
        if self.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let DirectoryObservation::Threads(observation) = &self.observation else {
            return Err(BridgeError::runtime_stopped());
        };
        tokio::select! {
            biased;
            _ = self.shutdown.cancelled() => { self.request_close(); Ok(None) },
            next = observation.next() => Ok(next?.map(convert::directory_frame)),
        }
    }

    async fn next_metadata(&self) -> Result<Option<BridgeThreadMetadataFrame>, BridgeError> {
        if self.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let _next = self.next_gate.try_lock().map_err(|_| busy())?;
        if self.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let DirectoryObservation::Metadata(observation) = &self.observation else {
            return Err(BridgeError::runtime_stopped());
        };
        tokio::select! {
            biased;
            _ = self.shutdown.cancelled() => { self.request_close(); Ok(None) },
            next = observation.next() => Ok(next?.map(convert::metadata_frame)),
        }
    }

    pub(crate) async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        match &self.observation {
            DirectoryObservation::Threads(observation) => observation.close().await?,
            DirectoryObservation::Metadata(observation) => observation.close().await?,
        }
        let _next = self.next_gate.lock().await;
        self.settled.store(true, Ordering::Release);
        Ok(())
    }
}

fn busy() -> BridgeError {
    BridgeError::from(pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "A directory observation next read is already in flight",
        true,
    ))
}

impl BridgeThreadsObservation {
    pub async fn next(&self) -> Result<Option<BridgeThreadDirectoryFrame>, BridgeError> {
        self.inner.next_threads().await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().await?;
        if let Some(bridge) = current_bridge() {
            bridge
                .subscriptions
                .unregister_directory_observation(self.inner.id);
        }
        Ok(())
    }
}

impl BridgeThreadObservation {
    pub async fn next(&self) -> Result<Option<BridgeThreadMetadataFrame>, BridgeError> {
        self.inner.next_metadata().await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().await?;
        if let Some(bridge) = current_bridge() {
            bridge
                .subscriptions
                .unregister_directory_observation(self.inner.id);
        }
        Ok(())
    }
}
