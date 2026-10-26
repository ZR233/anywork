use super::response::{ArchiveThreadResult, BridgeSettingsStateResponse};
use super::thread_stream::{BridgeInteractionRequest, BridgeThread, BridgeThreadRuntimeSnapshot};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeResourceStamp {
    pub resource_key: String,
    pub owner_epoch: String,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeCommandDisposition {
    Applied,
    NoChange,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeCommandEffectPoint {
    Immediate,
    NextTurn,
    FutureSession,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStudioCommandReceipt {
    pub operation_id: String,
    pub disposition: BridgeCommandDisposition,
    pub targets: Vec<BridgeResourceStamp>,
    pub effect: BridgeCommandEffectPoint,
    pub effective: bool,
    pub durable: bool,
    pub requires_identity_observation: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeSettingsCommandReply {
    pub snapshot: BridgeSettingsStateResponse,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadModeCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadModelRouteCommandReply {
    pub runtime: BridgeThreadRuntimeSnapshot,
    pub settings: BridgeSettingsStateResponse,
    pub mode_default_saved: bool,
    pub warning: Option<String>,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRenameThreadCommandReply {
    pub thread: BridgeThread,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeArchiveThreadCommandReply {
    pub result: ArchiveThreadResult,
    pub receipt: BridgeStudioCommandReceipt,
}

/// 无内容继续的受理回执：控制输入、继续点与受理序号，不含尚未存在的轮次编号。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContinueThreadReply {
    pub thread_id: String,
    pub input_id: String,
    pub continuation_id: String,
    pub cursor: u64,
    pub receipt: BridgeStudioCommandReceipt,
}

/// 精确停止的受理回执：`stopped` 只说明请求已被接受。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStopThreadReply {
    pub thread_id: String,
    pub execution_id: String,
    pub stopped: bool,
    pub receipt: BridgeStudioCommandReceipt,
}

/// 一次继续操作的当前阶段，由输入事实唯一推导。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeContinuationOperationState {
    Pending,
    Consumed { turn_id: String },
    Discarded,
}

/// 继续操作的只读回查结果；查询本身不激活执行。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContinuationOperationView {
    pub thread_id: String,
    pub operation_id: String,
    pub input_id: String,
    pub continuation_id: String,
    pub accepted_sequence: u64,
    pub state: BridgeContinuationOperationState,
    pub durable: bool,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeInteractionCommandReply {
    pub interaction: BridgeInteractionRequest,
    pub receipt: BridgeStudioCommandReceipt,
}
