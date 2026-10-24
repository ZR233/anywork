//! ACP 接入与认证的 Bridge 转换。
//!
//! 只做 wire ↔ FRB 镜像的字面映射：不解释状态、不重排 revision，也不在此处产生任何资源或
//! 副作用。凭据、进程与 SDK 类型都不进入这条边界。

use crate::api::studio::types::{
    BridgeAcpAccountCatalog, BridgeAcpAccountSettings, BridgeAcpAccountTemplate,
    BridgeAcpAccountUpdate, BridgeAcpAuthAccount, BridgeAcpAuthAction, BridgeAcpAuthFailure,
    BridgeAcpAuthFailureCode, BridgeAcpAuthMethod, BridgeAcpAuthMethodKind, BridgeAcpAuthSnapshot,
    BridgeAcpAuthStage, BridgeAcpAuthState, BridgeAcpProvider, BridgeAcpServerInfo,
};

pub(crate) fn bridge_acp_provider(provider: pl_protocol::studio::AcpProvider) -> BridgeAcpProvider {
    match provider {
        pl_protocol::studio::AcpProvider::Antigravity => BridgeAcpProvider::Antigravity,
    }
}

pub(crate) fn bridge_acp_account_settings(
    account: pl_protocol::studio::AcpAccountSettings,
) -> BridgeAcpAccountSettings {
    BridgeAcpAccountSettings {
        account_id: account.account_id,
        name: account.name,
        provider: bridge_acp_provider(account.provider),
        connection_revision: account.connection_revision,
    }
}

pub(crate) fn bridge_acp_account_catalog(
    catalog: pl_protocol::studio::AcpAccountCatalog,
) -> BridgeAcpAccountCatalog {
    BridgeAcpAccountCatalog {
        templates: catalog
            .templates
            .into_iter()
            .map(|template| BridgeAcpAccountTemplate {
                provider: bridge_acp_provider(template.provider),
                display_name: template.display_name,
                description: template.description,
                icon_key: template.icon_key,
                supported_version: template.supported_version,
                install_url: template.install_url,
                terms_url: template.terms_url,
                automatic_install: super::acp_install::bridge_acp_install_availability(
                    template.automatic_install,
                ),
            })
            .collect(),
    }
}

/// 保存意图 → wire 请求；`expected_revision` 是调用方观察到的 Settings revision。
pub(crate) fn update_acp_account_request(
    operation_id: String,
    expected_revision: u64,
    account: BridgeAcpAccountUpdate,
) -> pl_protocol::studio::UpdateAcpAccountRequest {
    pl_protocol::studio::UpdateAcpAccountRequest {
        operation_id,
        expected_revision,
        account: pl_protocol::studio::AcpAccountUpdate {
            account_id: account.account_id,
            name: account.name,
            provider: protocol_provider(account.provider),
        },
    }
}

fn protocol_provider(provider: BridgeAcpProvider) -> pl_protocol::studio::AcpProvider {
    match provider {
        BridgeAcpProvider::Antigravity => pl_protocol::studio::AcpProvider::Antigravity,
    }
}

/// 认证动作 → wire 请求体。
pub(crate) fn protocol_auth_action(
    action: BridgeAcpAuthAction,
) -> pl_protocol::studio::AcpAuthAction {
    match action {
        BridgeAcpAuthAction::Check => pl_protocol::studio::AcpAuthAction::Check,
        BridgeAcpAuthAction::Authenticate { method_id } => {
            pl_protocol::studio::AcpAuthAction::Authenticate { method_id }
        }
    }
}

pub(crate) fn bridge_acp_auth_snapshot(
    snapshot: pl_protocol::studio::AcpAuthSnapshot,
) -> BridgeAcpAuthSnapshot {
    BridgeAcpAuthSnapshot {
        revision: snapshot.revision,
        updated_at: snapshot.updated_at,
        accounts: snapshot
            .accounts
            .into_iter()
            .map(|account| BridgeAcpAuthAccount {
                account_id: account.account_id,
                connection_revision: account.connection_revision,
                state: bridge_acp_auth_state(account.state),
            })
            .collect(),
    }
}

fn bridge_acp_auth_state(state: pl_protocol::studio::AcpAuthState) -> BridgeAcpAuthState {
    match state {
        pl_protocol::studio::AcpAuthState::Unchecked => BridgeAcpAuthState::Unchecked,
        pl_protocol::studio::AcpAuthState::Checking { operation_id } => {
            BridgeAcpAuthState::Checking { operation_id }
        }
        pl_protocol::studio::AcpAuthState::Required { methods, server } => {
            BridgeAcpAuthState::Required {
                methods: methods.into_iter().map(bridge_acp_auth_method).collect(),
                server: bridge_acp_server(server),
            }
        }
        pl_protocol::studio::AcpAuthState::Authenticating {
            operation_id,
            method_id,
        } => BridgeAcpAuthState::Authenticating {
            operation_id,
            method_id,
        },
        pl_protocol::studio::AcpAuthState::Verifying { operation_id } => {
            BridgeAcpAuthState::Verifying { operation_id }
        }
        pl_protocol::studio::AcpAuthState::Closing {
            operation_id,
            failure,
        } => BridgeAcpAuthState::Closing {
            operation_id,
            failure: failure.map(bridge_acp_auth_failure),
        },
        pl_protocol::studio::AcpAuthState::Verified { checked_at, server } => {
            BridgeAcpAuthState::Verified {
                checked_at,
                server: bridge_acp_server(server),
            }
        }
        pl_protocol::studio::AcpAuthState::Cancelling { operation_id } => {
            BridgeAcpAuthState::Cancelling { operation_id }
        }
        pl_protocol::studio::AcpAuthState::Cancelled => BridgeAcpAuthState::Cancelled,
        pl_protocol::studio::AcpAuthState::Failed { failure } => BridgeAcpAuthState::Failed {
            failure: bridge_acp_auth_failure(failure),
        },
    }
}

fn bridge_acp_auth_failure(failure: pl_protocol::studio::AcpAuthFailure) -> BridgeAcpAuthFailure {
    BridgeAcpAuthFailure {
        code: bridge_acp_failure_code(failure.code),
        stage: bridge_acp_failure_stage(failure.stage),
        message: failure.message,
        retryable: failure.retryable,
    }
}

fn bridge_acp_auth_method(method: pl_protocol::studio::AcpAuthMethod) -> BridgeAcpAuthMethod {
    BridgeAcpAuthMethod {
        id: method.id,
        name: method.name,
        description: method.description,
        kind: match method.kind {
            pl_protocol::studio::AcpAuthMethodKind::Agent => BridgeAcpAuthMethodKind::Agent,
            pl_protocol::studio::AcpAuthMethodKind::Terminal => BridgeAcpAuthMethodKind::Terminal,
            pl_protocol::studio::AcpAuthMethodKind::Unsupported => {
                BridgeAcpAuthMethodKind::Unsupported
            }
        },
    }
}

fn bridge_acp_server(
    server: Option<pl_protocol::studio::AcpServerInfo>,
) -> Option<BridgeAcpServerInfo> {
    server.map(|server| BridgeAcpServerInfo {
        name: server.name,
        title: server.title,
        version: server.version,
    })
}

fn bridge_acp_failure_code(
    code: pl_protocol::studio::AcpAuthFailureCode,
) -> BridgeAcpAuthFailureCode {
    match code {
        pl_protocol::studio::AcpAuthFailureCode::PreparationRequired => {
            BridgeAcpAuthFailureCode::PreparationRequired
        }
        pl_protocol::studio::AcpAuthFailureCode::InstallationInvalid => {
            BridgeAcpAuthFailureCode::InstallationInvalid
        }
        pl_protocol::studio::AcpAuthFailureCode::UnsupportedPlatform => {
            BridgeAcpAuthFailureCode::UnsupportedPlatform
        }
        pl_protocol::studio::AcpAuthFailureCode::ServerVersionMismatch => {
            BridgeAcpAuthFailureCode::ServerVersionMismatch
        }
        pl_protocol::studio::AcpAuthFailureCode::Startup => BridgeAcpAuthFailureCode::Startup,
        pl_protocol::studio::AcpAuthFailureCode::MissingExecutable => {
            BridgeAcpAuthFailureCode::MissingExecutable
        }
        pl_protocol::studio::AcpAuthFailureCode::Io => BridgeAcpAuthFailureCode::Io,
        pl_protocol::studio::AcpAuthFailureCode::UnsupportedVersion => {
            BridgeAcpAuthFailureCode::UnsupportedVersion
        }
        pl_protocol::studio::AcpAuthFailureCode::UnsupportedMethod => {
            BridgeAcpAuthFailureCode::UnsupportedMethod
        }
        pl_protocol::studio::AcpAuthFailureCode::Authentication => {
            BridgeAcpAuthFailureCode::Authentication
        }
        pl_protocol::studio::AcpAuthFailureCode::Probe => BridgeAcpAuthFailureCode::Probe,
        pl_protocol::studio::AcpAuthFailureCode::Protocol => BridgeAcpAuthFailureCode::Protocol,
        pl_protocol::studio::AcpAuthFailureCode::Transport => BridgeAcpAuthFailureCode::Transport,
        pl_protocol::studio::AcpAuthFailureCode::Timeout => BridgeAcpAuthFailureCode::Timeout,
        pl_protocol::studio::AcpAuthFailureCode::ResourceLimit => {
            BridgeAcpAuthFailureCode::ResourceLimit
        }
        pl_protocol::studio::AcpAuthFailureCode::Cancelled => BridgeAcpAuthFailureCode::Cancelled,
        pl_protocol::studio::AcpAuthFailureCode::StaleOperation => {
            BridgeAcpAuthFailureCode::StaleOperation
        }
        pl_protocol::studio::AcpAuthFailureCode::ConfigChanged => {
            BridgeAcpAuthFailureCode::ConfigChanged
        }
        pl_protocol::studio::AcpAuthFailureCode::Cleanup => BridgeAcpAuthFailureCode::Cleanup,
        pl_protocol::studio::AcpAuthFailureCode::Internal => BridgeAcpAuthFailureCode::Internal,
    }
}

fn bridge_acp_failure_stage(stage: pl_protocol::studio::AcpAuthStage) -> BridgeAcpAuthStage {
    match stage {
        pl_protocol::studio::AcpAuthStage::Prepare => BridgeAcpAuthStage::Prepare,
        pl_protocol::studio::AcpAuthStage::Process => BridgeAcpAuthStage::Process,
        pl_protocol::studio::AcpAuthStage::Config => BridgeAcpAuthStage::Config,
        pl_protocol::studio::AcpAuthStage::Initialize => BridgeAcpAuthStage::Initialize,
        pl_protocol::studio::AcpAuthStage::Authenticate => BridgeAcpAuthStage::Authenticate,
        pl_protocol::studio::AcpAuthStage::Probe => BridgeAcpAuthStage::Probe,
        pl_protocol::studio::AcpAuthStage::Close => BridgeAcpAuthStage::Close,
        pl_protocol::studio::AcpAuthStage::Cleanup => BridgeAcpAuthStage::Cleanup,
    }
}
