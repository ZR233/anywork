use super::identity::BridgeProductSourceStatusRef;
use crate::api::studio::observation::BridgeReadText;
use crate::api::studio::types::BridgeStateOperation;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeObservedHeader {
    pub brief: BridgeObservedBrief,
    pub status: BridgeProductSourceStatusRef,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeObservedBrief {
    Uninitialized {
        revision: u64,
        updated_at: i64,
    },
    Loading {
        revision: u64,
        started_at: i64,
    },
    Ready {
        revision: u64,
        updated_at: i64,
        last_checked_at: Option<i64>,
    },
    Refreshing {
        revision: u64,
        started_at: i64,
        last_checked_at: Option<i64>,
    },
    Stale {
        revision: u64,
        stale_at: i64,
        last_checked_at: Option<i64>,
    },
    Degraded {
        revision: u64,
        failed_at: i64,
        last_checked_at: Option<i64>,
        retryable: bool,
    },
    Failed {
        revision: u64,
        failed_at: i64,
        retryable: bool,
    },
    Stopped {
        revision: u64,
        stopped_at: i64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSourceStateErrorRead {
    pub code: BridgeReadText,
    pub message: BridgeReadText,
    pub retryable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeProductSourceStatusReadHeader {
    Uninitialized {
        revision: u64,
        updated_at: i64,
    },
    Loading {
        revision: u64,
        operation: BridgeStateOperation,
        operation_id: BridgeReadText,
        started_at: i64,
    },
    Ready {
        revision: u64,
        updated_at: i64,
        last_checked_at: Option<i64>,
    },
    Refreshing {
        revision: u64,
        operation: BridgeStateOperation,
        operation_id: BridgeReadText,
        started_at: i64,
        last_checked_at: Option<i64>,
    },
    Stale {
        revision: u64,
        stale_at: i64,
        last_checked_at: Option<i64>,
    },
    Degraded {
        revision: u64,
        failed_at: i64,
        last_checked_at: Option<i64>,
        operation: BridgeStateOperation,
        error: BridgeSourceStateErrorRead,
    },
    Failed {
        revision: u64,
        failed_at: i64,
        operation: BridgeStateOperation,
        error: BridgeSourceStateErrorRead,
    },
    Stopped {
        revision: u64,
        stopped_at: i64,
    },
}
