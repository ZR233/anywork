//! Queue offsets read one immutable coordinator publication, never current statistics.
use super::super::identity::*;
use super::super::references::BridgePersistenceQueueReadRef;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::persistence::*;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::persistence::StudioPersistenceQueueRead;
impl ModelsRead for StudioPersistenceQueueRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        StudioPersistenceQueueRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        StudioPersistenceQueueRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioPersistenceQueueRead::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        StudioPersistenceQueueRead::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgePersistenceQueueReadConnection {
    read: ModelsReadHandle<StudioPersistenceQueueRead>,
}
impl BridgePersistenceQueueReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePersistenceQueueReadHeader, BridgeError> {
        let query = self.read.query(move |source| source.header())?;
        Ok(query.await?.into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgePersistenceQueueEntryPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entries(offset, limit))?;
        Ok(query.await?.into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgePersistenceQueueEntityRead, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entity(reference.into()))?;
        Ok(query.await?.into())
    }
    pub async fn lookup_thread(
        &self,
        id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        let query = self.read.query(move |source| source.lookup_thread(id))?;
        Ok(query.await?.map(Into::into))
    }
    pub async fn threads(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeThreadPersistenceReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.threads(list_id, offset, limit))?;
        Ok(query.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        let query = self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?;
        Ok(query.await?.into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}
pub async fn open_persistence_queue_read(
    reference: BridgePersistenceQueueReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePersistenceQueueReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePersistenceQueueReadConnection {
        read: open_read(move |runtime| runtime.open_persistence_queue_read(reference, origin))
            .await?,
    })
}

/// Command replies have no publication revision; all optional watermarks retain Unknown.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadPersistenceCommandSnapshot {
    pub thread_id: String,
    pub fault_generation: u64,
    pub fault: Option<crate::api::studio::types::BridgeHistoryFault>,
    pub state_dirty_revision: Option<u64>,
    pub state_saving_revision: Option<u64>,
    pub state_durable_revision: Option<u64>,
    pub history_admitted_sequence: Option<u64>,
    pub history_durable_sequence: Option<u64>,
    pub calls_admitted_sequence: Option<u64>,
    pub calls_durable_sequence: Option<u64>,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub in_flight_bytes: u64,
    pub last_error: Option<String>,
    pub pressure_paused: bool,
}
impl From<pl_protocol::ThreadPersistenceSnapshot> for BridgeThreadPersistenceCommandSnapshot {
    fn from(value: pl_protocol::ThreadPersistenceSnapshot) -> Self {
        Self {
            thread_id: value.thread_id,
            fault_generation: value.fault_generation,
            fault: value.fault.map(Into::into),
            state_dirty_revision: value.state_dirty_revision,
            state_saving_revision: value.state_saving_revision,
            state_durable_revision: value.state_durable_revision,
            history_admitted_sequence: value.history_admitted_sequence,
            history_durable_sequence: value.history_durable_sequence,
            calls_admitted_sequence: value.calls_admitted_sequence,
            calls_durable_sequence: value.calls_durable_sequence,
            pending_operations: value.pending_operations,
            pending_bytes: value.pending_bytes,
            oldest_pending_age_millis: value.oldest_pending_age_millis,
            in_flight_bytes: value.in_flight_bytes,
            last_error: value.last_error,
            pressure_paused: value.pressure_paused,
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueCommandSnapshot {
    pub statistics_gap: bool,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub in_flight_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub last_error: Option<String>,
    pub pressure_paused: bool,
    pub threads: Vec<BridgeThreadPersistenceCommandSnapshot>,
}
impl From<pl_protocol::PersistenceQueueSnapshot> for BridgePersistenceQueueCommandSnapshot {
    fn from(value: pl_protocol::PersistenceQueueSnapshot) -> Self {
        Self {
            statistics_gap: value.statistics_gap,
            pending_operations: value.pending_operations,
            pending_bytes: value.pending_bytes,
            in_flight_bytes: value.in_flight_bytes,
            oldest_pending_age_millis: value.oldest_pending_age_millis,
            last_error: value.last_error,
            pressure_paused: value.pressure_paused,
            threads: value.threads.into_iter().map(Into::into).collect(),
        }
    }
}
pub async fn retry_thread_history(
    thread_id: String,
    fault_generation: u64,
) -> Result<BridgePersistenceQueueCommandSnapshot, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .retry_thread_history(&thread_id, fault_generation)
        .await?
        .into())
}
pub async fn resume_thread_history(
    thread_id: String,
    fault_generation: u64,
) -> Result<BridgePersistenceQueueCommandSnapshot, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .resume_thread_history(&thread_id, fault_generation)
        .await?
        .into())
}
