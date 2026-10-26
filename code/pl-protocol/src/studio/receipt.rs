//! Owner-produced acknowledgements, independent of transport delivery versions.
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResourceStamp {
    pub resource_key: String,
    pub owner_epoch: String,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum CommandDisposition {
    Applied,
    NoChange,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum CommandEffectPoint {
    Immediate,
    NextTurn,
    FutureSession,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioCommandReceipt {
    pub operation_id: String,
    pub disposition: CommandDisposition,
    pub targets: Vec<ResourceStamp>,
    pub effect: CommandEffectPoint,
    pub effective: bool,
    pub durable: bool,
    /// Confirmation requires a matching identity predicate in the owner stream;
    /// resource delivery versions alone cannot prove this command observed.
    pub requires_identity_observation: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsCommandReply {
    pub snapshot: super::SettingsStateResponse,
    pub receipt: StudioCommandReceipt,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModeCommandReply {
    pub receipt: StudioCommandReceipt,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioCommandRequest {
    pub operation_id: String,
}

/// Durable evidence from the original input identity index, not a Turn saved marker.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InputAcceptanceEvidence {
    pub accepted_sequence: u64,
    pub request_digest: Option<String>,
    pub disposition: PersistedInputDisposition,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum PersistedInputDisposition {
    Consumed,
    Discarded,
}
