use super::BridgeSessionDirectoryRow;
use super::response::{ArchiveThreadResult, BridgeSettingsStateResponse, DeleteThreadResult};
use super::thread_stream::{BridgeInteractionRequest, BridgeThreadRuntimeSnapshot};

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

/// A root Thread's model selection and the revisions it was based on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSetThreadModelRouteRequest {
    pub operation_id: String,
    pub thread_id: String,
    pub expected_model_route_revision: u64,
    pub expected_settings_revision: u64,
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
    pub service_tier: Option<String>,
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
    pub thread: BridgeSessionDirectoryRow,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeArchiveThreadCommandReply {
    pub result: ArchiveThreadResult,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeDeleteThreadCommandReply {
    pub result: DeleteThreadResult,
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
    Known,
    NotAccepted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeContinuationDisposition {
    Scheduled,
    Effective,
    NotExecuted { reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeContinuationOperationView {
    pub thread_id: String,
    pub operation_id: String,
    pub expected_continuation_token: String,
    pub state: BridgeContinuationOperationState,
    pub acceptance_epoch: Option<String>,
    pub execution_id: Option<String>,
    pub turn_id: Option<String>,
    pub accepted_revision: Option<u64>,
    pub disposition: Option<BridgeContinuationDisposition>,
    pub receipt: Option<BridgeStudioCommandReceipt>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeInteractionCommandReply {
    pub interaction: BridgeInteractionRequest,
    pub receipt: BridgeStudioCommandReceipt,
}
