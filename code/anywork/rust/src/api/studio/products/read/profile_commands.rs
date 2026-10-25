//! Named Profile/reload call wrappers over the one existing Configuration registry.
use super::super::references::{
    BridgeAgentProfilesReadTarget, BridgeConfigurationReadTarget, BridgeModelCatalogReadTarget,
};
use super::configuration_command_registry::{BridgeCallOutcome, CommandOwner, close_call};
use crate::api::studio::bridge_runtime::{BridgeRuntime, installed_bridge};
use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::types::{
    BridgeAgentWorkspaceMode, BridgeError, BridgeFeedCloseReport, BridgeStudioCommandReceipt,
};
use pl_protocol::products::configuration_calls::{ConfigurationCallKind, ConfigurationCallRequest};
use pl_protocol::products::profile_commands as native;
use std::sync::Arc;

#[derive(Clone)]
pub struct BridgeAgentProfileEdit {
    pub profile_id: String,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub system_instructions: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
    pub enabled: bool,
    pub workspace_mode: BridgeAgentWorkspaceMode,
}
#[derive(Clone)]
pub struct BridgeSaveProfileRequest {
    pub operation_id: String,
    pub expected_settings_revision: u64,
    pub profile: BridgeAgentProfileEdit,
}
#[derive(Debug, Clone)]
pub struct BridgeSetSystemProfileEnabledRequest {
    pub operation_id: String,
    pub expected_settings_revision: u64,
    pub profile_id: String,
    pub enabled: bool,
}
#[derive(Clone)]
pub enum BridgeProfileCommandRequest {
    SaveProfile {
        request: BridgeSaveProfileRequest,
    },
    SetSystemProfileEnabled {
        request: BridgeSetSystemProfileEnabledRequest,
    },
}
#[derive(Debug, Clone)]
pub struct BridgeConfigurationReloadRequest {
    pub operation_id: String,
    pub expected_revision: u64,
}
#[derive(Debug, Clone)]
pub struct BridgeProfileCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
    pub configuration: BridgeConfigurationReadTarget,
    pub models: BridgeModelCatalogReadTarget,
    pub profiles: BridgeAgentProfilesReadTarget,
}
#[derive(Debug, Clone)]
pub struct BridgeConfigurationReloadResult {
    pub configuration: BridgeConfigurationReadTarget,
    pub models: BridgeModelCatalogReadTarget,
    pub profiles: BridgeAgentProfilesReadTarget,
}
#[derive(Debug, Clone)]
pub enum BridgeProfileCommandOutcome {
    Committed {
        reply: BridgeProfileCommandReply,
    },
    CommittedButUnobserved {
        receipt: BridgeStudioCommandReceipt,
        error: BridgeError,
    },
    ConfirmedWithoutUsableReceipt {
        operation_id: String,
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
#[derive(Debug, Clone)]
pub enum BridgeConfigurationReloadOutcome {
    Returned {
        operation_id: String,
        result: BridgeConfigurationReloadResult,
    },
    AdoptedButUnobserved {
        operation_id: String,
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
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeProfileCommandCall {
    owner: Arc<CommandOwner>,
    bridge: &'static BridgeRuntime,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeConfigurationReloadCall {
    owner: Arc<CommandOwner>,
    bridge: &'static BridgeRuntime,
}

pub async fn begin_profile_command(
    request: BridgeProfileCommandRequest,
) -> Result<BridgeProfileCommandCall, BridgeError> {
    let bridge = installed_bridge()?;
    let request = match request {
        BridgeProfileCommandRequest::SaveProfile { request } => {
            native::ProfileCommandRequest::SaveProfile(native::SaveProfileRequest {
                operation_id: request.operation_id,
                expected_settings_revision: request.expected_settings_revision,
                profile: profile_input(request.profile),
            })
        }
        BridgeProfileCommandRequest::SetSystemProfileEnabled { request } => {
            native::ProfileCommandRequest::SetSystemProfileEnabled(
                native::SetSystemProfileEnabledRequest {
                    operation_id: request.operation_id,
                    expected_settings_revision: request.expected_settings_revision,
                    profile_id: request.profile_id,
                    enabled: request.enabled,
                },
            )
        }
    };
    Ok(BridgeProfileCommandCall {
        owner: bridge
            .configuration_commands
            .begin(bridge, ConfigurationCallRequest::Profile(request))?,
        bridge,
    })
}
pub async fn find_profile_command(
    operation_id: String,
) -> Result<Option<BridgeProfileCommandCall>, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge
        .configuration_commands
        .find(&operation_id, ConfigurationCallKind::Profile)?
        .map(|owner| BridgeProfileCommandCall { owner, bridge }))
}
pub async fn begin_configuration_reload(
    request: BridgeConfigurationReloadRequest,
) -> Result<BridgeConfigurationReloadCall, BridgeError> {
    let bridge = installed_bridge()?;
    let request = native::ConfigurationReloadRequest {
        operation_id: request.operation_id,
        expected_revision: request.expected_revision,
    };
    Ok(BridgeConfigurationReloadCall {
        owner: bridge
            .configuration_commands
            .begin(bridge, ConfigurationCallRequest::Reload(request))?,
        bridge,
    })
}
pub async fn find_configuration_reload(
    operation_id: String,
) -> Result<Option<BridgeConfigurationReloadCall>, BridgeError> {
    let bridge = installed_bridge()?;
    Ok(bridge
        .configuration_commands
        .find(&operation_id, ConfigurationCallKind::Reload)?
        .map(|owner| BridgeConfigurationReloadCall { owner, bridge }))
}
impl BridgeProfileCommandCall {
    #[flutter_rust_bridge::frb(sync)]
    pub fn call_id(&self) -> String {
        self.owner.identity().call_id
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn operation_id(&self) -> String {
        self.owner.identity().operation_id
    }
    pub async fn result(&self) -> Result<BridgeProfileCommandOutcome, BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::Profile)?;
        let mut query = self.owner.result_query()?;
        match query.result().await? {
            BridgeCallOutcome::Profile(value) => Ok(value),
            _ => Err(wrong_kind()),
        }
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) -> Result<(), BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::Profile)?;
        self.owner.request_close();
        Ok(())
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::Profile)?;
        Ok(close_call(&self.owner, self.bridge).await)
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}
impl BridgeConfigurationReloadCall {
    #[flutter_rust_bridge::frb(sync)]
    pub fn call_id(&self) -> String {
        self.owner.identity().call_id
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn operation_id(&self) -> String {
        self.owner.identity().operation_id
    }
    pub async fn result(&self) -> Result<BridgeConfigurationReloadOutcome, BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::Reload)?;
        let mut query = self.owner.result_query()?;
        match query.result().await? {
            BridgeCallOutcome::Reload(value) => Ok(value),
            _ => Err(wrong_kind()),
        }
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) -> Result<(), BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::Reload)?;
        self.owner.request_close();
        Ok(())
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner.require_kind(ConfigurationCallKind::Reload)?;
        Ok(close_call(&self.owner, self.bridge).await)
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.close().await
    }
}
fn profile_input(value: BridgeAgentProfileEdit) -> native::AgentProfileEdit {
    native::AgentProfileEdit {
        profile_id: value.profile_id,
        display_name: value.display_name,
        description: value.description,
        when_to_use: value.when_to_use,
        system_instructions: value.system_instructions,
        account_id: value.account_id,
        model_id: value.model_id,
        effort: value.effort,
        enabled: value.enabled,
        workspace_mode: match value.workspace_mode {
            BridgeAgentWorkspaceMode::Unrestricted => pl_protocol::AgentWorkspaceMode::Unrestricted,
            BridgeAgentWorkspaceMode::Directory => pl_protocol::AgentWorkspaceMode::Directory,
            BridgeAgentWorkspaceMode::Worktree => pl_protocol::AgentWorkspaceMode::Worktree,
            BridgeAgentWorkspaceMode::Review => pl_protocol::AgentWorkspaceMode::Review,
        },
    }
}
impl From<native::ProfileCommandOutcome> for BridgeProfileCommandOutcome {
    fn from(value: native::ProfileCommandOutcome) -> Self {
        match value {
            native::ProfileCommandOutcome::Committed { reply } => Self::Committed {
                reply: BridgeProfileCommandReply {
                    receipt: command_receipt(reply.receipt),
                    configuration: reply.configuration.into(),
                    models: reply.models.into(),
                    profiles: reply.profiles.into(),
                },
            },
            native::ProfileCommandOutcome::CommittedButUnobserved { receipt, error } => {
                Self::CommittedButUnobserved {
                    receipt: command_receipt(receipt),
                    error: error.into(),
                }
            }
            native::ProfileCommandOutcome::ConfirmedWithoutUsableReceipt {
                operation_id,
                error,
            } => Self::ConfirmedWithoutUsableReceipt {
                operation_id,
                error: error.into(),
            },
            native::ProfileCommandOutcome::Rejected {
                operation_id,
                error,
            } => Self::Rejected {
                operation_id,
                error: error.into(),
            },
            native::ProfileCommandOutcome::Unknown {
                operation_id,
                error,
            } => Self::Unknown {
                operation_id,
                error: error.into(),
            },
        }
    }
}
impl From<native::ConfigurationReloadOutcome> for BridgeConfigurationReloadOutcome {
    fn from(value: native::ConfigurationReloadOutcome) -> Self {
        match value {
            native::ConfigurationReloadOutcome::Returned {
                operation_id,
                result,
            } => Self::Returned {
                operation_id,
                result: BridgeConfigurationReloadResult {
                    configuration: result.configuration.into(),
                    models: result.models.into(),
                    profiles: result.profiles.into(),
                },
            },
            native::ConfigurationReloadOutcome::AdoptedButUnobserved {
                operation_id,
                error,
            } => Self::AdoptedButUnobserved {
                operation_id,
                error: error.into(),
            },
            native::ConfigurationReloadOutcome::Rejected {
                operation_id,
                error,
            } => Self::Rejected {
                operation_id,
                error: error.into(),
            },
            native::ConfigurationReloadOutcome::Unknown {
                operation_id,
                error,
            } => Self::Unknown {
                operation_id,
                error: error.into(),
            },
        }
    }
}
fn wrong_kind() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Protocol,
        "Original call result has the wrong resource kind",
        false,
    )
    .into()
}
