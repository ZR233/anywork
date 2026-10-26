use super::super::identity::*;
use super::super::references::{
    BridgeUpdateDetailsReadRef, BridgeUpdateErrorReadRef, BridgeUpdateOperationReadRef,
    BridgeUpdateSummaryReadRef, BridgeUpdatesReadRef,
};
use crate::api::studio::types::BridgeError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeUpdatesBrief {
    Disabled {
        revision: u64,
        updated_at: i64,
    },
    Idle {
        revision: u64,
        updated_at: i64,
    },
    Checking {
        revision: u64,
        started_at: i64,
    },
    UpToDate {
        revision: u64,
        checked_at: i64,
    },
    Available {
        revision: u64,
        checked_at: i64,
    },
    Downloading {
        revision: u64,
        updated_at: i64,
        downloaded: u64,
        total: u64,
    },
    Verifying {
        revision: u64,
        updated_at: i64,
        downloaded: u64,
        total: u64,
    },
    Ready {
        revision: u64,
        ready_at: i64,
    },
    InstallerLaunched {
        revision: u64,
        launched_at: i64,
    },
    CheckFailed {
        revision: u64,
        failed_at: i64,
        retryable: bool,
    },
    InstallFailed {
        revision: u64,
        failed_at: i64,
        retryable: bool,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdatesHeader {
    pub reference: BridgeUpdatesReadRef,
    pub brief: BridgeUpdatesBrief,
    pub summary: Option<BridgeUpdateSummaryReadRef>,
    pub operation: Option<BridgeUpdateOperationReadRef>,
    pub error: Option<BridgeUpdateErrorReadRef>,
    pub details: Option<BridgeUpdateDetailsReadRef>,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeUpdatesEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeUpdatesHeader,
    },
    Replace {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeUpdatesHeader,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeUpdatesFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeUpdatesEvent,
    },
    ResyncRequired {
        identity: BridgeProductFeedIdentity,
        reason: BridgeProductResyncReason,
    },
    Failure {
        identity: BridgeProductFeedIdentity,
        error: BridgeError,
    },
    Closed {
        identity: BridgeProductFeedIdentity,
        reason: BridgeProductFeedCloseReason,
    },
}
