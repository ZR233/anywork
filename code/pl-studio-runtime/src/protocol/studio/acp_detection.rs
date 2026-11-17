//! Ephemeral local CLI detection; not an account or authentication fact.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::StudioCommandReceipt;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpLocalDetectionSnapshot {
    pub revision: u64,
    pub operation_id: Option<String>,
    pub state: AcpLocalDetectionState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind",
    deny_unknown_fields
)]
pub enum AcpLocalDetectionState {
    Idle,
    Checking,
    Available { program: String, version: String },
    Missing,
    Unsupported,
    Failed { failure: AcpLocalDetectionFailure },
    Cancelling,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpLocalDetectionFailure {
    pub kind: AcpLocalDetectionFailureKind,
    /// Safe, actionable summary; never process output or environment values.
    pub message: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpLocalDetectionFailureKind {
    Timeout,
    OutputLimit,
    Execution,
    Cleanup,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartAcpLocalDetectionRequest {
    pub operation_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelAcpLocalDetectionRequest {
    pub operation_id: String,
    pub target_operation_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpLocalDetectionCommandReply {
    pub receipt: StudioCommandReceipt,
    pub snapshot: AcpLocalDetectionSnapshot,
}
