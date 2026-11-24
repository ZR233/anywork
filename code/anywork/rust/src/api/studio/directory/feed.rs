use super::{convert, types::*};
use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::subscription::{
    error::{close_error, open_error},
    factory::BridgeObservationFactory,
};
use crate::api::studio::types::BridgeError;
use crate::pull_observation::{ManagedPullObservation, PullObservationSource};
use pl_lifecycle::Managed;
use pl_studio_runtime::{ThreadMetadataObservation, ThreadsObservation};

const DIRECTORY_BUSY_MESSAGE: &str = "A directory observation next read is already in flight";

pub async fn open_threads_observation(
    query: BridgeThreadDirectoryQuery,
    window: BridgeThreadDirectoryWindow,
) -> Result<BridgeThreadsObservation, BridgeError> {
    let bridge = active_bridge().await?;
    bridge.observation_factory.open_threads(query, window).await
}

pub async fn open_thread_observation(
    thread_id: String,
) -> Result<BridgeThreadObservation, BridgeError> {
    let bridge = active_bridge().await?;
    bridge.observation_factory.open_thread(thread_id).await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_threads(
        &self,
        query: BridgeThreadDirectoryQuery,
        window: BridgeThreadDirectoryWindow,
    ) -> Result<BridgeThreadsObservation, BridgeError> {
        let source = self.source.clone();
        let inner = self
            .scope
            .open("directoryObservations", move |shutdown| async move {
                let observation = source.observe_threads(query.into(), window.into())?;
                Ok(ManagedPullObservation::new(
                    observation,
                    shutdown,
                    DIRECTORY_BUSY_MESSAGE,
                ))
            })
            .await
            .map_err(open_error)?;
        Ok(BridgeThreadsObservation { inner })
    }

    pub(crate) async fn open_thread(
        &self,
        thread_id: String,
    ) -> Result<BridgeThreadObservation, BridgeError> {
        let source = self.source.clone();
        let inner = self
            .scope
            .open("directoryObservations", move |shutdown| async move {
                let observation = source.observe_thread(thread_id)?;
                Ok(ManagedPullObservation::new(
                    observation,
                    shutdown,
                    DIRECTORY_BUSY_MESSAGE,
                ))
            })
            .await
            .map_err(open_error)?;
        Ok(BridgeThreadObservation { inner })
    }
}

impl PullObservationSource for ThreadsObservation {
    type Frame = BridgeThreadDirectoryFrame;

    async fn next(&self) -> Result<Option<Self::Frame>, BridgeError> {
        Ok(self.next().await?.map(convert::directory_frame))
    }

    fn request_close(&self) {
        self.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        Ok(self.close().await?)
    }
}

impl PullObservationSource for ThreadMetadataObservation {
    type Frame = BridgeThreadMetadataFrame;

    async fn next(&self) -> Result<Option<Self::Frame>, BridgeError> {
        Ok(self.next().await?.map(convert::metadata_frame))
    }

    fn request_close(&self) {
        self.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        Ok(self.close().await?)
    }
}

pub struct BridgeThreadsObservation {
    inner: Managed<ManagedPullObservation<ThreadsObservation>>,
}

pub struct BridgeThreadObservation {
    inner: Managed<ManagedPullObservation<ThreadMetadataObservation>>,
}

impl BridgeThreadsObservation {
    pub async fn next(&self) -> Result<Option<BridgeThreadDirectoryFrame>, BridgeError> {
        self.inner.get().next().await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.retry_close().await.map_err(close_error)
    }
}

impl BridgeThreadObservation {
    pub async fn next(&self) -> Result<Option<BridgeThreadMetadataFrame>, BridgeError> {
        self.inner.get().next().await
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.retry_close().await.map_err(close_error)
    }
}
