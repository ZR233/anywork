use crate::api::studio::types::BridgeError;
use super::super::identity::*;
use super::super::references::BridgePersistenceReadRef;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgePersistenceBrief {
    Ready { pending_commits: u64 },
    Flushing { pending_commits: u64, oldest_pending_revision: Option<u64> },
    Degraded { pending_commits: u64, oldest_pending_revision: Option<u64>, first_failed_at: i64 },
    Recovering { pending_commits: u64, oldest_pending_revision: Option<u64>, first_failed_at: i64 },
    Blocked { pending_commits: u64, oldest_pending_revision: Option<u64>, first_failed_at: i64 },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceHeader { pub reference: BridgePersistenceReadRef, pub revision: u64, pub state: BridgePersistenceBrief }
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePersistenceEvent {
    Baseline { identity: BridgeProductFeedIdentity, stamp: BridgeProductProjectionStamp, value: BridgePersistenceHeader },
    Replace { stamp: BridgeProductProjectionStamp, base_revision: u64, value: BridgePersistenceHeader },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgePersistenceFrame {
    Data { delivery_sequence: u64, event: BridgePersistenceEvent },
    ResyncRequired { identity: BridgeProductFeedIdentity, reason: BridgeProductResyncReason },
    Failure { identity: BridgeProductFeedIdentity, error: BridgeError },
    Closed { identity: BridgeProductFeedIdentity, reason: BridgeProductFeedCloseReason },
}
