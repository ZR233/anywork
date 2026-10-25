use std::future::Future;
use std::sync::Arc;

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
