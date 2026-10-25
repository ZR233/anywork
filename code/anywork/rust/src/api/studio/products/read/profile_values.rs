use super::super::identity::{BridgeProductCollectionRef, BridgeProductEntityRef};
use crate::api::studio::observation::{BridgeReadText, BridgeTypedListRef};
use crate::api::studio::types::BridgeAgentWorkspaceMode;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesReadHeader {
    pub profiles: BridgeTypedListRef,
    pub diagnostics: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfileRead {
    pub profile_id: BridgeReadText,
    pub display_name: BridgeReadText,
    pub description: BridgeReadText,
    pub when_to_use: BridgeReadText,
    pub system_instructions: BridgeReadText,
    pub account_id: BridgeReadText,
    pub model_id: BridgeReadText,
    pub effort: Option<BridgeReadText>,
    pub source: BridgeReadText,
    pub revision: BridgeReadText,
    pub content_hash: BridgeReadText,
    pub system: bool,
    pub enabled: bool,
    pub workspace_mode: BridgeAgentWorkspaceMode,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProfileDiagnosticRead {
    pub path: BridgeReadText,
    pub message: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeAgentProfileRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfileReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAgentProfileRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProfileDiagnosticReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeProfileDiagnosticRead>,
    pub next_offset: Option<u64>,
}
