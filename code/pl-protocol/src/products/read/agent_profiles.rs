//! Immutable Profiles reads. Text/list identifiers are local to the original pinned scope.
use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::{AgentWorkspaceMode, studio::ReadText};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfilesReadHeader {
    pub profiles: TypedListRef,
    pub diagnostics: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfileRead {
    pub profile_id: ReadText,
    pub display_name: ReadText,
    pub description: ReadText,
    pub when_to_use: ReadText,
    pub system_instructions: ReadText,
    pub account_id: ReadText,
    pub model_id: ReadText,
    pub effort: Option<ReadText>,
    pub source: ReadText,
    pub revision: ReadText,
    pub content_hash: ReadText,
    pub system: bool,
    pub enabled: bool,
    pub workspace_mode: AgentWorkspaceMode,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProfileDiagnosticRead {
    pub path: ReadText,
    pub message: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfilesEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfilesEntityRead {
    pub reference: ProductEntityRef,
    pub value: AgentProfileRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfileReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<AgentProfileRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProfileDiagnosticReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<ProfileDiagnosticRead>,
    pub next_offset: Option<u64>,
}
