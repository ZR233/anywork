//! `acpAuth`：整值快照 feed。每个事件携带该 topic 的 canonical 快照，不做字段级增量。
use crate::products::identity::*;
use crate::studio::{AcpAuthSnapshot, StudioError};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum AcpAuthEvent {
    /// 首帧必达（含 revision 0 的“尚未观察”快照）。
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        value: AcpAuthSnapshot,
    },
    Change {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        value: AcpAuthSnapshot,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum AcpAuthFrame {
    Data {
        delivery_sequence: u64,
        event: AcpAuthEvent,
    },
    ResyncRequired {
        identity: ProductFeedIdentity,
        reason: ProductResyncReason,
    },
    Failure {
        identity: ProductFeedIdentity,
        error: StudioError,
    },
    Closed {
        identity: ProductFeedIdentity,
        reason: ProductFeedCloseReason,
    },
}
