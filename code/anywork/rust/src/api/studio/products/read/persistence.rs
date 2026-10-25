//! Persistence reads map only original immutable native material.
use super::super::identity::*;
use super::super::references::{BridgePersistenceReadRef, BridgePersistenceReadTarget};
use super::super::source::BridgeSourceStateErrorRead;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::BridgeHistoryFault;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::persistence as protocol;
use pl_studio_runtime::persistence::StudioPersistenceRead;
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceReadHeader {
    pub revision: u64,
    pub state: BridgePersistenceStatusRead,
}

impl From<protocol::PersistenceReadHeader> for BridgePersistenceReadHeader {
    fn from(value: protocol::PersistenceReadHeader) -> Self {
        Self {
            revision: value.revision,
            state: value.state.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadPersistenceRead {
    pub thread_id: BridgeReadText,
    pub fault_generation: u64,
    pub fault: Option<BridgeHistoryFault>,
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
    pub last_error: Option<BridgeReadText>,
    pub pressure_paused: bool,
}

impl From<protocol::ThreadPersistenceRead> for BridgeThreadPersistenceRead {
    fn from(value: protocol::ThreadPersistenceRead) -> Self {
        Self {
            thread_id: value.thread_id.into(),
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
            last_error: value.last_error.map(Into::into),
            pressure_paused: value.pressure_paused,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueSnapshotRead {
    pub statistics_gap: bool,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub in_flight_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub last_error: Option<BridgeReadText>,
    pub pressure_paused: bool,
    pub threads: BridgeTypedListRef,
}

impl From<protocol::PersistenceQueueSnapshotRead> for BridgePersistenceQueueSnapshotRead {
    fn from(value: protocol::PersistenceQueueSnapshotRead) -> Self {
        Self {
            statistics_gap: value.statistics_gap,
            pending_operations: value.pending_operations,
            pending_bytes: value.pending_bytes,
            in_flight_bytes: value.in_flight_bytes,
            oldest_pending_age_millis: value.oldest_pending_age_millis,
            last_error: value.last_error.map(Into::into),
            pressure_paused: value.pressure_paused,
            threads: value.threads.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueReadHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub queue: BridgePersistenceQueueSnapshotRead,
}

impl From<protocol::PersistenceQueueReadHeader> for BridgePersistenceQueueReadHeader {
    fn from(value: protocol::PersistenceQueueReadHeader) -> Self {
        Self {
            revision: value.revision,
            updated_at: value.updated_at,
            queue: value.queue.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeThreadPersistenceRead,
}

impl From<protocol::PersistenceQueueEntityRead> for BridgePersistenceQueueEntityRead {
    fn from(value: protocol::PersistenceQueueEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}

impl From<protocol::PersistenceQueueEntryPage> for BridgePersistenceQueueEntryPage {
    fn from(value: protocol::PersistenceQueueEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadPersistenceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeThreadPersistenceRead>,
    pub next_offset: Option<u64>,
}

impl From<protocol::ThreadPersistenceReadPage> for BridgeThreadPersistenceReadPage {
    fn from(value: protocol::ThreadPersistenceReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgePersistenceStatusRead {
    Ready {
        pending_commits: u64,
    },
    Flushing {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
    },
    Degraded {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
        first_failed_at: i64,
        error: BridgeSourceStateErrorRead,
    },
    Recovering {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
        first_failed_at: i64,
    },
    Blocked {
        pending_commits: u64,
        oldest_pending_revision: Option<u64>,
        first_failed_at: i64,
        error: BridgeSourceStateErrorRead,
    },
}

impl From<protocol::PersistenceStatusRead> for BridgePersistenceStatusRead {
    fn from(value: protocol::PersistenceStatusRead) -> Self {
        match value {
            protocol::PersistenceStatusRead::Ready { pending_commits } => {
                Self::Ready { pending_commits }
            }
            protocol::PersistenceStatusRead::Flushing {
                pending_commits,
                oldest_pending_revision,
            } => Self::Flushing {
                pending_commits,
                oldest_pending_revision,
            },
            protocol::PersistenceStatusRead::Degraded {
                pending_commits,
                oldest_pending_revision,
                first_failed_at,
                error,
            } => Self::Degraded {
                pending_commits,
                oldest_pending_revision,
                first_failed_at,
                error: error.into(),
            },
            protocol::PersistenceStatusRead::Recovering {
                pending_commits,
                oldest_pending_revision,
                first_failed_at,
            } => Self::Recovering {
                pending_commits,
                oldest_pending_revision,
                first_failed_at,
            },
            protocol::PersistenceStatusRead::Blocked {
                pending_commits,
                oldest_pending_revision,
                first_failed_at,
                error,
            } => Self::Blocked {
                pending_commits,
                oldest_pending_revision,
                first_failed_at,
                error: error.into(),
            },
        }
    }
}
impl ModelsRead for StudioPersistenceRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        StudioPersistenceRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        StudioPersistenceRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioPersistenceRead::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        StudioPersistenceRead::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgePersistenceReadConnection {
    read: ModelsReadHandle<StudioPersistenceRead>,
}
impl BridgePersistenceReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePersistenceReadHeader, BridgeError> {
        let query = self.read.query(move |source| source.header())?;
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
pub async fn open_persistence_read(
    reference: BridgePersistenceReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePersistenceReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePersistenceReadConnection {
        read: open_read(move |runtime| runtime.open_persistence_read(reference, origin)).await?,
    })
}
pub async fn retry_persistence() -> Result<BridgePersistenceReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::active_bridge().await?;
    let result = bridge.studio.retry_persistence().await?;
    Ok(result.target.into())
}
