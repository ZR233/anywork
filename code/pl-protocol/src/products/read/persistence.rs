use super::super::identity::{ProductCollectionRef, ProductEntityRef};
use super::super::source::SourceStateErrorRead;
use super::primitives::TypedListRef;
use crate::studio::{HistoryFault, ReadText};
use serde::{Deserialize, Serialize};
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum PersistenceStatusRead {
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
        error: SourceStateErrorRead,
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
        error: SourceStateErrorRead,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceReadHeader {
    pub revision: u64,
    pub state: PersistenceStatusRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadPersistenceRead {
    pub thread_id: ReadText,
    pub fault_generation: u64,
    pub fault: Option<HistoryFault>,
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
    pub last_error: Option<ReadText>,
    pub pressure_paused: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueSnapshotRead {
    pub statistics_gap: bool,
    pub pending_operations: u64,
    pub pending_bytes: u64,
    pub in_flight_bytes: u64,
    pub oldest_pending_age_millis: Option<u64>,
    pub last_error: Option<ReadText>,
    pub pressure_paused: bool,
    pub threads: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueReadHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub queue: PersistenceQueueSnapshotRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueEntityRead {
    pub reference: ProductEntityRef,
    pub value: ThreadPersistenceRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceQueueEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadPersistenceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<ThreadPersistenceRead>,
    pub next_offset: Option<u64>,
}
