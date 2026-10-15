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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInterruptTurnCommandReply {
    pub thread_id: String,
    pub turn_id: String,
    pub interrupted: bool,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeInteractionCommandReply {
    pub interaction: BridgeInteractionRequest,
    pub receipt: BridgeStudioCommandReceipt,
}
