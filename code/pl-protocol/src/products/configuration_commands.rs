//! Concrete Configuration requests and truthful commit-stage outcomes, never aggregate Settings.
use super::references::{ConfigurationReadTarget, ModelCatalogReadTarget};
use crate::studio::{self, StudioCommandReceipt, StudioError};
use serde::{Deserialize, Serialize};

/// Resource identity of one retained attempt, distinct from the business intent's OperationId.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigurationCommandCallIdentity {
    pub call_id: String,
    pub operation_id: String,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ConfigurationCommandRequest {
    SaveAccount(studio::UpdateAccountRequest),
    SetDefaultAccount(studio::SetDefaultAccountRequest),
    RemoveAccount(studio::RemoveAccountRequest),
    RemoveAccountModel(studio::RemoveAccountModelRequest),
    SetAccountModelEnabled(studio::SetAccountModelEnabledRequest),
    SetAccountBillingKind(studio::SetAccountBillingKindRequest),
    ApplyField(studio::UpdateSettingsFieldRequest),
    SetPermission(studio::UpdatePermissionSettingsRequest),
}

impl ConfigurationCommandRequest {
    pub fn operation_id(&self) -> &str {
        match self {
            Self::SaveAccount(request) => &request.operation_id,
            Self::SetDefaultAccount(request) => &request.operation_id,
            Self::RemoveAccount(request) => &request.operation_id,
            Self::RemoveAccountModel(request) => &request.operation_id,
            Self::SetAccountModelEnabled(request) => &request.operation_id,
            Self::SetAccountBillingKind(request) => &request.operation_id,
            Self::ApplyField(request) => &request.operation_id,
            Self::SetPermission(request) => &request.operation_id,
        }
    }
}

impl std::fmt::Debug for ConfigurationCommandRequest {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let kind = match self {
            Self::SaveAccount(_) => "saveAccount",
            Self::SetDefaultAccount(_) => "setDefaultAccount",
            Self::RemoveAccount(_) => "removeAccount",
            Self::RemoveAccountModel(_) => "removeAccountModel",
            Self::SetAccountModelEnabled(_) => "setAccountModelEnabled",
            Self::SetAccountBillingKind(_) => "setAccountBillingKind",
            Self::ApplyField(_) => "applyField",
            Self::SetPermission(_) => "setPermission",
        };
        formatter
            .debug_struct("ConfigurationCommandRequest")
            .field("operation_id", &self.operation_id())
            .field("kind", &kind)
            .finish_non_exhaustive()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ConfigurationCommandReply {
    pub receipt: StudioCommandReceipt,
    pub configuration: ConfigurationReadTarget,
    pub models: ModelCatalogReadTarget,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ConfigurationCommandOutcome {
    Committed {
        reply: ConfigurationCommandReply,
    },
    CommittedButUnobserved {
        receipt: StudioCommandReceipt,
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
