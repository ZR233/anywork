//! A concrete retained command result, registered in the existing bridge task owner before work.
use pl_protocol::products::configuration_calls::{ConfigurationCallKind, ConfigurationCallRequest};
use pl_protocol::products::configuration_commands::{
    ConfigurationCommandOutcome, ConfigurationCommandRequest,
};
use pl_protocol::studio as native;
use std::sync::Arc;

use super::super::references::{BridgeConfigurationReadTarget, BridgeModelCatalogReadTarget};
use super::configuration_command_registry::{BridgeCallOutcome, CommandOwner, close_call};
use crate::api::studio::bridge_runtime::{BridgeRuntime, installed_bridge};
use crate::api::studio::convert::{commands::command_receipt, settings::account_settings_request};
use crate::api::studio::types::{
    AccountSettingsInput, BridgeBillingKind, BridgeError, BridgeFeedCloseReport,
    BridgeStudioCommandReceipt, SettingsFieldInput,
};

/// Exactly the SDK's frozen command fields. Profiles remain a separate capability.
#[derive(Debug, Clone)]
pub struct BridgeConfigurationCommandRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub command: BridgeConfigurationMutation,
}
#[derive(Clone)]
pub enum BridgeConfigurationMutation {
    SaveAccount {
        input: AccountSettingsInput,
    },
    SetDefaultAccount {
        account_id: String,
    },
    RemoveAccount {
        account_id: String,
        replacement_account_id: Option<String>,
    },
    RemoveAccountModel {
        account_id: String,
        model_id: String,
    },
    SetAccountModelEnabled {
        account_id: String,
        model_id: String,
        enabled: bool,
    },
    SetAccountBillingKind {
        account_id: String,
        billing_kind: Option<BridgeBillingKind>,
    },
    ApplyField {
        update: SettingsFieldInput,
    },
    SetPermission {
        mode: String,
    },
}
impl std::fmt::Debug for BridgeConfigurationMutation {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let kind = match self {
            Self::SaveAccount { .. } => "SaveAccount",
            Self::SetDefaultAccount { .. } => "SetDefaultAccount",
            Self::RemoveAccount { .. } => "RemoveAccount",
            Self::RemoveAccountModel { .. } => "RemoveAccountModel",
            Self::SetAccountModelEnabled { .. } => "SetAccountModelEnabled",
            Self::SetAccountBillingKind { .. } => "SetAccountBillingKind",
            Self::ApplyField { .. } => "ApplyField",
            Self::SetPermission { .. } => "SetPermission",
        };
        formatter.debug_struct(kind).finish_non_exhaustive()
    }
}
#[derive(Debug, Clone)]
pub struct BridgeConfigurationCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
    pub configuration: BridgeConfigurationReadTarget,
    pub models: BridgeModelCatalogReadTarget,
}
#[derive(Debug, Clone)]
pub enum BridgeConfigurationCommandOutcome {
    Committed {
        reply: BridgeConfigurationCommandReply,
    },
    CommittedButUnobserved {
        receipt: BridgeStudioCommandReceipt,
        error: BridgeError,
    },
    Rejected {
        operation_id: String,
        error: BridgeError,
    },
    Unknown {
        operation_id: String,
        error: BridgeError,
    },
}

/// One original retained call. Dropping an opaque is not explicit consumption: the real bridge
/// index retains the task/result/capture so find can recover a lost or dropped begin reply.
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConfigurationCommandCall {
    owner: Arc<CommandOwner>,
    bridge: &'static BridgeRuntime,
}

pub async fn begin_configuration_command(
    request: BridgeConfigurationCommandRequest,
) -> Result<BridgeConfigurationCommandCall, BridgeError> {
    let bridge = installed_bridge()?;
    let owner = bridge.configuration_commands.begin(
        bridge,
        ConfigurationCallRequest::Configuration(native_request(request)),
    )?;
    Ok(BridgeConfigurationCommandCall { owner, bridge })
}

/// Only looks up the original live call. Missing never creates a request or proves rejection.
pub async fn find_configuration_command(
    operation_id: String,
) -> Result<Option<BridgeConfigurationCommandCall>, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge
        .configuration_commands
        .find(&operation_id, ConfigurationCallKind::Configuration)?
        .map(|owner| BridgeConfigurationCommandCall { owner, bridge }))
}

impl BridgeConfigurationCommandCall {
    #[flutter_rust_bridge::frb(sync)]
    pub fn call_id(&self) -> String {
        self.owner.identity().call_id
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn operation_id(&self) -> String {
        self.owner.identity().operation_id
    }
    pub async fn result(&self) -> Result<BridgeConfigurationCommandOutcome, BridgeError> {
        let mut query = self.owner.result_query()?;
        match query.result().await? {
            BridgeCallOutcome::Configuration(outcome) => Ok(outcome),
            BridgeCallOutcome::Profile(_) | BridgeCallOutcome::Reload(_) => {
                Err(pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Protocol,
                    "Original call result has the wrong resource kind",
                    false,
                )
                .into())
            }
        }
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner
            .require_kind(ConfigurationCallKind::Configuration)?;
        Ok(close_call(&self.owner, self.bridge).await)
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}

fn native_request(request: BridgeConfigurationCommandRequest) -> ConfigurationCommandRequest {
    let BridgeConfigurationCommandRequest {
        operation_id,
        expected_revision,
        command,
    } = request;
    match command {
        BridgeConfigurationMutation::SaveAccount { input } => {
            ConfigurationCommandRequest::SaveAccount(account_settings_request(
                operation_id,
                expected_revision,
                input,
            ))
        }
        BridgeConfigurationMutation::SetDefaultAccount { account_id } => {
            ConfigurationCommandRequest::SetDefaultAccount(native::SetDefaultAccountRequest {
                operation_id,
                expected_revision,
                account_id,
            })
        }
        BridgeConfigurationMutation::RemoveAccount {
            account_id,
            replacement_account_id,
        } => ConfigurationCommandRequest::RemoveAccount(native::RemoveAccountRequest {
            operation_id,
            expected_revision,
            account_id,
            replacement_account_id,
        }),
        BridgeConfigurationMutation::RemoveAccountModel {
            account_id,
            model_id,
        } => ConfigurationCommandRequest::RemoveAccountModel(native::RemoveAccountModelRequest {
            operation_id,
            expected_revision,
            account_id,
            model_id,
        }),
        BridgeConfigurationMutation::SetAccountModelEnabled {
            account_id,
            model_id,
            enabled,
        } => ConfigurationCommandRequest::SetAccountModelEnabled(
            native::SetAccountModelEnabledRequest {
                operation_id,
                expected_revision,
                account_id,
                model_id,
                enabled,
            },
        ),
        BridgeConfigurationMutation::SetAccountBillingKind {
            account_id,
            billing_kind,
        } => ConfigurationCommandRequest::SetAccountBillingKind(
            native::SetAccountBillingKindRequest {
                operation_id,
                expected_revision,
                account_id,
                billing_kind: billing_kind
                    .map(|kind| native::BillingKindIntent::set(kind.into()))
                    .unwrap_or_else(native::BillingKindIntent::clear),
            },
        ),
        BridgeConfigurationMutation::ApplyField { update } => {
            ConfigurationCommandRequest::ApplyField(native::UpdateSettingsFieldRequest {
                operation_id,
                expected_revision,
                update: update.into(),
            })
        }
        BridgeConfigurationMutation::SetPermission { mode } => {
            ConfigurationCommandRequest::SetPermission(native::UpdatePermissionSettingsRequest {
                operation_id,
                expected_revision,
                mode,
            })
        }
    }
}
impl From<ConfigurationCommandOutcome> for BridgeConfigurationCommandOutcome {
    fn from(value: ConfigurationCommandOutcome) -> Self {
        match value {
            ConfigurationCommandOutcome::Committed { reply } => Self::Committed {
                reply: BridgeConfigurationCommandReply {
                    receipt: command_receipt(reply.receipt),
                    configuration: reply.configuration.into(),
                    models: reply.models.into(),
                },
            },
            ConfigurationCommandOutcome::CommittedButUnobserved { receipt, error } => {
                Self::CommittedButUnobserved {
                    receipt: command_receipt(receipt),
                    error: error.into(),
                }
            }
            ConfigurationCommandOutcome::Rejected {
                operation_id,
                error,
            } => Self::Rejected {
                operation_id,
                error: error.into(),
            },
            ConfigurationCommandOutcome::Unknown {
                operation_id,
                error,
            } => Self::Unknown {
                operation_id,
                error: error.into(),
            },
        }
    }
}
