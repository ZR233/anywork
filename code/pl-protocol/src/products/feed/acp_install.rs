//! `acpInstall`：整值快照 feed。安装是共享资产，revision/topic 与认证完全独立。
use crate::products::identity::*;
use crate::studio::{AcpInstallSnapshot, StudioError};
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
pub enum AcpInstallEvent {
    /// 首帧必达（含 revision 0 的“尚未准备”快照）。
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        value: AcpInstallSnapshot,
    },
    Change {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        value: AcpInstallSnapshot,
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
pub enum AcpInstallFrame {
    Data {
        delivery_sequence: u64,
        event: AcpInstallEvent,
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
