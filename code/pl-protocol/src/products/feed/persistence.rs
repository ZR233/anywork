use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::PersistenceReadRef;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum PersistenceBrief {
    Ready { pending_commits: u64 },
    Flushing { pending_commits: u64, oldest_pending_revision: Option<u64> },
    Degraded { pending_commits: u64, oldest_pending_revision: Option<u64>, first_failed_at: i64 },
    Recovering { pending_commits: u64, oldest_pending_revision: Option<u64>, first_failed_at: i64 },
    Blocked { pending_commits: u64, oldest_pending_revision: Option<u64>, first_failed_at: i64 },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PersistenceHeader { pub reference: PersistenceReadRef, pub revision: u64, pub state: PersistenceBrief }
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum PersistenceEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: PersistenceHeader },
    Replace { stamp: ProductProjectionStamp, base_revision: u64, value: PersistenceHeader },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum PersistenceFrame {
    Data { delivery_sequence: u64, event: PersistenceEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}
