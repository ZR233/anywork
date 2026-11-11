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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wire_preserves_operation_identity_and_rejects_unknown_detection_fields() {
        let snapshot = AcpLocalDetectionSnapshot {
            revision: 8,
            operation_id: Some("probe-editor-1".into()),
            state: AcpLocalDetectionState::Available {
                program: "/isolated/bin/agy".into(),
                version: "1.5.4".into(),
            },
        };
        let value = serde_json::to_value(&snapshot).unwrap();
        assert_eq!(value["operationId"], "probe-editor-1");
        assert_eq!(value["state"]["kind"], "available");
        assert_eq!(
            serde_json::from_value::<AcpLocalDetectionSnapshot>(value.clone()).unwrap(),
            snapshot
        );
        let mut invalid = value;
        invalid["state"]["rawOutput"] = serde_json::json!("must not enter product state");
        assert!(serde_json::from_value::<AcpLocalDetectionSnapshot>(invalid).is_err());
        assert!(
            serde_json::from_value::<StartAcpLocalDetectionRequest>(serde_json::json!({
                "operationId": "start", "program": "override-not-in-command-contract"
            }))
            .is_err()
        );
        let cancel: CancelAcpLocalDetectionRequest = serde_json::from_value(serde_json::json!({
            "operationId": "cancel-command",
            "targetOperationId": "probe-editor-1"
        }))
        .unwrap();
        assert_ne!(cancel.operation_id, cancel.target_operation_id);
    }
}
