use serde::{Deserialize, Serialize};

use super::identity::ProductSourceStatusRef;
use crate::StateOperation;
use crate::studio::ReadText;

/// Only resources backed by the canonical ObservedResource carry this header.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ObservedHeader {
    pub brief: ObservedBrief,
    pub status: ProductSourceStatusRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ObservedBrief {
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct SourceStateErrorRead {
    pub code: ReadText,
    pub message: ReadText,
    pub retryable: bool,
}

/// Metadata only: no generic business value and no invented correlation/operation ID fields.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ProductSourceStatusReadHeader {
    Uninitialized {
        revision: u64,
        updated_at: i64,
    },
    Loading {
        revision: u64,
        operation: StateOperation,
        operation_id: ReadText,
        started_at: i64,
    },
    Ready {
        revision: u64,
        updated_at: i64,
        last_checked_at: Option<i64>,
    },
    Refreshing {
        revision: u64,
        operation: StateOperation,
        operation_id: ReadText,
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
        operation: StateOperation,
        error: SourceStateErrorRead,
    },
    Failed {
        revision: u64,
        failed_at: i64,
        operation: StateOperation,
        error: SourceStateErrorRead,
    },
    Stopped {
        revision: u64,
        stopped_at: i64,
    },
}
