use std::future::Future;
use std::sync::Arc;

use pl_protocol::products::configuration_calls::{
    AcpAccountCallRequest, AcpAccountCommandOutcome, AcpAccountCommandReply,
};
use pl_protocol::products::configuration_commands::{
    ConfigurationCommandOutcome, ConfigurationCommandReply, ConfigurationCommandRequest,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::super::{StudioRuntime, settings_api::SettingsCommit};

/// The original command result owns its exact immutable commit publication. Hosts retain this
/// resource until explicit call close, independently of serializing or reading the wire outcome.
/// The publication itself retains Configuration, pair, Models and original metadata/status pins.
/// Profiles adoption evidence is retained independently; its failure does not rewrite the
/// approved eight-mutation wire outcome or pretend a public three-target reply already exists.
pub struct ConfigurationCommandResult {
    outcome: ConfigurationCommandOutcome,
    _capture: Option<Arc<crate::config::ConfigurationSnapshot>>,
    _profiles: Option<Result<Arc<crate::config::ProfilesSnapshot>, StudioError>>,
}

impl ConfigurationCommandResult {
    /// A pure wire value; cloning it does not transfer the original capture's ownership.
    pub fn outcome(&self) -> &ConfigurationCommandOutcome {
        &self.outcome
    }
}

/// 一次 ACP 接入提交的原始结果。
///
/// 与普通配置命令共用同一调用所有者、操作身份与真实关闭机制；成功只携带 Settings-only 回执与
/// 本次提交捕获的 Configuration 读取目标，并保留该目标的材料责任直到显式关闭。
pub struct AcpAccountCommandResult {
    outcome: AcpAccountCommandOutcome,
    _capture: Option<Arc<crate::config::ConfigurationSnapshot>>,
}

impl AcpAccountCommandResult {
    /// 纯 wire 值；克隆不转移原始捕获的所有权。
    pub fn outcome(&self) -> &AcpAccountCommandOutcome {
        &self.outcome
    }
}

impl StudioRuntime {
    /// Runs exactly one original CAS command. Hosts must register and retain this future before
    /// polling it; cancellation of a client waiter must not drop the admitted command/followup.
    /// There is no automatic retry, request digest, alternative writer or command budget here.
    pub fn configuration_command(
        &self,
        request: ConfigurationCommandRequest,
    ) -> impl Future<Output = ConfigurationCommandResult> + Send + 'static + use<> {
        let runtime = self.clone();
        async move {
            let operation_id = request.operation_id().to_owned();
            if runtime.shutdown_committed() {
                return ConfigurationCommandResult {
                    outcome: ConfigurationCommandOutcome::Rejected {
                        operation_id,
                        error: StudioError::new(
                            StudioErrorCode::Cancelled,
                            "Configuration commands are sealed",
                            false,
                        ),
                    },
                    _capture: None,
                    _profiles: None,
                };
            }
            let committed = match request {
                ConfigurationCommandRequest::SaveAccount(request) => {
                    runtime.commit_account(request)
                }
                ConfigurationCommandRequest::SetDefaultAccount(request) => {
                    runtime.commit_default_account(request)
                }
                ConfigurationCommandRequest::RemoveAccount(request) => {
                    runtime.commit_remove_account(request)
                }
                ConfigurationCommandRequest::RemoveAccountModel(request) => {
                    runtime.commit_remove_account_model(request)
                }
                ConfigurationCommandRequest::SetAccountModelEnabled(request) => {
                    runtime.commit_account_model_enabled(request)
                }
                ConfigurationCommandRequest::SetAccountBillingKind(request) => {
                    runtime.commit_account_billing_kind(request)
                }
                ConfigurationCommandRequest::ApplyField(request) => {
                    runtime.commit_settings_field(request)
                }
                ConfigurationCommandRequest::SetPermission(request) => {
                    runtime.commit_permission_settings(request)
                }
            };
            let commit = match committed {
                Ok(commit) => commit,
                Err(error) => {
                    return ConfigurationCommandResult {
                        outcome: classify_uncommitted(operation_id, error),
                        _capture: None,
                        _profiles: None,
                    };
                }
            };
            runtime.configuration_committed(commit).await
        }
    }

    async fn configuration_committed(&self, commit: SettingsCommit) -> ConfigurationCommandResult {
        let receipt = self.command_receipt(
            commit.operation_id.clone(),
            commit.changed,
            vec![self.resource_stamp("settings", commit.evidence.configuration.revision)],
            commit.effect,
            true,
        );
        // This map is captured by the original commit guard, not a source.current() after await.
        let publication = commit
            .evidence
            .captures
            .get(self.owner_epoch())
            .cloned()
            .unwrap_or_else(|| {
                Err(StudioError::new(
                    StudioErrorCode::Unavailable,
                    "The committed Configuration publication is not attached to this runtime",
                    true,
                ))
            });
        let capture = publication.as_ref().ok().cloned();
        let profiles = commit
            .evidence
            .profiles
            .captures
            .get(self.owner_epoch())
            .cloned()
            .unwrap_or_else(|| {
                Err(StudioError::new(
                    StudioErrorCode::Unavailable,
                    "The committed Profiles capture is not attached to this runtime",
                    true,
                ))
            });
        let reply = publication.and_then(|publication| {
            let pair = publication
                .pair
                .as_ref()
                .map_err(|failure| failure.diagnostic.clone())?;
            if pair.target.stamp.settings_revision != commit.evidence.configuration.revision
                || pair.target.stamp.model_catalog_revision != commit.evidence.catalog.revision
            {
                return Err(StudioError::new(
                    StudioErrorCode::Protocol,
                    "Configuration command capture watermarks differ from its commit",
                    false,
                ));
            }
            self.configuration_source.expose_committed(&publication)?;
            Ok(ConfigurationCommandReply {
                receipt: receipt.clone(),
                configuration: pair.target.configuration.clone(),
                models: pair.target.catalog.clone(),
            })
        });
        // Publication/usage/skills failures after the durable transaction are never Rejected.
        let followup = commit
            .followup(self)
            .await
            .map_err(crate::studio_error_from_anyhow);
        let outcome = match (reply, followup) {
            (Ok(reply), Ok(())) => ConfigurationCommandOutcome::Committed { reply },
            (Err(error), _) | (Ok(_), Err(error)) => {
                ConfigurationCommandOutcome::CommittedButUnobserved { receipt, error }
            }
        };
        // Also retain a genuine capture when later source exposure or followup failed. The
        // committed receipt and resource cleanup remain independent facts, never latest reads.
        ConfigurationCommandResult {
            outcome,
            _capture: capture,
            _profiles: Some(profiles),
        }
    }

    /// Runs exactly one original ACP account CAS command in the existing Configuration call owner.
    ///
    /// 与普通配置命令一样只有一次提交：请求登记、冻结与结果保留都由调用所有者承担，本方法不
    /// 重试、不重放，也不把提交后的捕获失败改写为拒绝。
    pub fn acp_account_command(
        &self,
        request: AcpAccountCallRequest,
    ) -> impl Future<Output = AcpAccountCommandResult> + Send + 'static + use<> {
        let runtime = self.clone();
        async move {
            let operation_id = request.operation_id().to_owned();
            if runtime.shutdown_committed() {
                return AcpAccountCommandResult {
                    outcome: AcpAccountCommandOutcome::Rejected {
                        operation_id,
                        error: StudioError::new(
                            StudioErrorCode::Cancelled,
                            "ACP account commands are sealed",
                            false,
                        ),
                    },
                    _capture: None,
                };
            }
            let committed = match request {
                AcpAccountCallRequest::Save(request) => runtime.commit_save_acp_account(request),
                AcpAccountCallRequest::Remove(request) => {
                    runtime.commit_remove_acp_account(request)
                }
            };
            let commit = match committed {
                Ok(commit) => commit,
                Err(error) => {
                    return AcpAccountCommandResult {
                        outcome: classify_acp_uncommitted(operation_id, error),
                        _capture: None,
                    };
                }
            };
            runtime.acp_account_committed(commit).await
        }
    }

    async fn acp_account_committed(&self, commit: SettingsCommit) -> AcpAccountCommandResult {
        let receipt = self.command_receipt(
            commit.operation_id.clone(),
            commit.changed,
            vec![self.resource_stamp("settings", commit.evidence.configuration.revision)],
            commit.effect,
            true,
        );
        let publication = commit
            .evidence
            .captures
            .get(self.owner_epoch())
            .cloned()
            .unwrap_or_else(|| {
                Err(StudioError::new(
                    StudioErrorCode::Unavailable,
                    "The committed Configuration publication is not attached to this runtime",
                    true,
                ))
            });
        let capture = publication.as_ref().ok().cloned();
        // 只采用本次提交捕获的 Configuration 材料：不借用 Models pair，也不含模型目标或回执。
        let reply = publication.and_then(|publication| {
            Ok(AcpAccountCommandReply {
                receipt: receipt.clone(),
                configuration: self
                    .configuration_source
                    .expose_committed_configuration(&publication)?,
            })
        });
        let followup = commit
            .followup(self)
            .await
            .map_err(crate::studio_error_from_anyhow);
        let outcome = match (reply, followup) {
            (Ok(reply), Ok(())) => AcpAccountCommandOutcome::Committed { reply },
            (Err(error), _) | (Ok(_), Err(error)) => {
                AcpAccountCommandOutcome::CommittedButUnobserved { receipt, error }
            }
        };
        AcpAccountCommandResult {
            outcome,
            _capture: capture,
        }
    }
}

fn classify_acp_uncommitted(
    operation_id: String,
    error: anyhow::Error,
) -> AcpAccountCommandOutcome {
    // 持久化未知与提交确定后无回执都保持 Unknown；只有提交边界前的类型化拒绝才是 Rejected。
    match error.downcast::<crate::config::ConfigMutationFailure>() {
        Ok(
            crate::config::ConfigMutationFailure::Commit(error)
            | crate::config::ConfigMutationFailure::Confirmed(error),
        ) => AcpAccountCommandOutcome::Unknown {
            operation_id,
            error: crate::studio_error_from_anyhow(error.into()),
        },
        Ok(crate::config::ConfigMutationFailure::Preflight(error)) => {
            AcpAccountCommandOutcome::Rejected {
                operation_id,
                error: crate::studio_error_from_anyhow(error.into()),
            }
        }
        Err(error) => AcpAccountCommandOutcome::Rejected {
            operation_id,
            error: crate::studio_error_from_anyhow(error),
        },
    }
}

fn classify_uncommitted(operation_id: String, error: anyhow::Error) -> ConfigurationCommandOutcome {
    // Preserve the eight-command wire contract: both an uncertain durable failure and a known
    // save without a usable state reply remain Unknown here. Profile calls use the extra
    // private Confirmed evidence separately; all other errors precede the mutation boundary.
    match error.downcast::<crate::config::ConfigMutationFailure>() {
        Ok(
            crate::config::ConfigMutationFailure::Commit(error)
            | crate::config::ConfigMutationFailure::Confirmed(error),
        ) => ConfigurationCommandOutcome::Unknown {
            operation_id,
            error: crate::studio_error_from_anyhow(error.into()),
        },
        Ok(crate::config::ConfigMutationFailure::Preflight(error)) => {
            ConfigurationCommandOutcome::Rejected {
                operation_id,
                error: crate::studio_error_from_anyhow(error.into()),
            }
        }
        Err(error) => ConfigurationCommandOutcome::Rejected {
            operation_id,
            error: crate::studio_error_from_anyhow(error),
        },
    }
}
