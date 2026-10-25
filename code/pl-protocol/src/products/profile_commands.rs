//! Profile mutations and explicit reload have separate truthful outcomes and result schemas.
use super::references::{AgentProfilesReadTarget, ConfigurationReadTarget, ModelCatalogReadTarget};
use crate::{
    AgentWorkspaceMode,
    studio::{StudioCommandReceipt, StudioError},
};
use serde::{Deserialize, Serialize};

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfileEdit {
    pub profile_id: String,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub system_instructions: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
    pub enabled: bool,
    pub workspace_mode: AgentWorkspaceMode,
}
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SaveProfileRequest {
    pub operation_id: String,
    pub expected_settings_revision: u64,
    pub profile: AgentProfileEdit,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetSystemProfileEnabledRequest {
    pub operation_id: String,
    pub expected_settings_revision: u64,
    pub profile_id: String,
    pub enabled: bool,
}
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ProfileCommandRequest {
    SaveProfile(SaveProfileRequest),
    SetSystemProfileEnabled(SetSystemProfileEnabledRequest),
}
impl ProfileCommandRequest {
    pub fn operation_id(&self) -> &str {
        match self {
            Self::SaveProfile(request) => &request.operation_id,
            Self::SetSystemProfileEnabled(request) => &request.operation_id,
        }
    }
}
impl std::fmt::Debug for ProfileCommandRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let kind = match self {
            Self::SaveProfile(_) => "saveProfile",
            Self::SetSystemProfileEnabled(_) => "setSystemProfileEnabled",
        };
        formatter
            .debug_struct("ProfileCommandRequest")
            .field("kind", &kind)
            .field("operation_id", &self.operation_id())
            .finish_non_exhaustive()
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigurationReloadRequest {
    pub operation_id: String,
    pub expected_revision: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProfileCommandReply {
    pub receipt: StudioCommandReceipt,
    pub configuration: ConfigurationReadTarget,
    pub models: ModelCatalogReadTarget,
    pub profiles: AgentProfilesReadTarget,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigurationReloadResult {
    pub configuration: ConfigurationReadTarget,
    pub models: ModelCatalogReadTarget,
    pub profiles: AgentProfilesReadTarget,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ProfileCommandOutcome {
    Committed {
        reply: ProfileCommandReply,
    },
    CommittedButUnobserved {
        receipt: StudioCommandReceipt,
        error: StudioError,
    },
    ConfirmedWithoutUsableReceipt {
        operation_id: String,
        error: StudioError,
    },
    Rejected {
        operation_id: String,
        error: StudioError,
    },
    Unknown {
        operation_id: String,
        error: StudioError,
    },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ConfigurationReloadOutcome {
    Returned {
        operation_id: String,
        result: ConfigurationReloadResult,
    },
    AdoptedButUnobserved {
        operation_id: String,
        error: StudioError,
    },
    Rejected {
        operation_id: String,
        error: StudioError,
    },
    Unknown {
        operation_id: String,
        error: StudioError,
    },
}
