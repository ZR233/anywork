//! ACP 本机检测的 FRB 镜像；不包含探测进程或第二份检测状态。

use serde::{Deserialize, Serialize};

use super::BridgeStudioCommandReceipt;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpLocalDetectionSnapshot {
    pub revision: u64,
    pub operation_id: Option<String>,
    pub state: BridgeAcpLocalDetectionState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpLocalDetectionState {
    Idle,
    Checking,
    Available {
        program: String,
        version: String,
    },
    Missing,
    Unsupported,
    Failed {
        failure: BridgeAcpLocalDetectionFailure,
    },
    Cancelling,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpLocalDetectionFailure {
    pub kind: BridgeAcpLocalDetectionFailureKind,
    pub message: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpLocalDetectionFailureKind {
    Timeout,
    OutputLimit,
    Execution,
    Cleanup,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpLocalDetectionCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
    pub snapshot: BridgeAcpLocalDetectionSnapshot,
}
