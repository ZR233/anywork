//! Three-target replies are materialized from original commit/adoption evidence and kept alive
//! by the call owner. Followups never rebuild targets from watch/current.
use super::super::StudioRuntime;
use crate::config::{
    AccountId, ConfigMutationEvidence, ProfileMutationFailure, ReasoningEffort, UserAgentProfile,
};
use pl_protocol::products::profile_commands::*;
use pl_protocol::studio::{CommandEffectPoint, StudioError, StudioErrorCode};
use std::future::Future;

pub struct ProfileCommandResult {
    outcome: ProfileCommandOutcome,
    _evidence: Option<ConfigMutationEvidence>,
}
impl ProfileCommandResult {
    pub fn outcome(&self) -> &ProfileCommandOutcome {
        &self.outcome
    }
}
pub struct ConfigurationReloadCommandResult {
    outcome: ConfigurationReloadOutcome,
    _evidence: Option<ConfigMutationEvidence>,
}
impl ConfigurationReloadCommandResult {
    pub fn outcome(&self) -> &ConfigurationReloadOutcome {
        &self.outcome
    }
}

impl StudioRuntime {
    /// Hosts register this future in the original call owner before polling it. A client waiter
    /// must not own/cancel the accepted write or drop its retained result before consumption.
    pub fn profile_command(
        &self,
        request: ProfileCommandRequest,
    ) -> impl Future<Output = ProfileCommandResult> + Send + 'static + use<> {
        let runtime = self.clone();
        async move {
            let operation_id = request.operation_id().to_owned();
            if let Err(error) = Self::validate_operation_id(&operation_id) {
                return ProfileCommandResult {
                    outcome: ProfileCommandOutcome::Rejected {
                        operation_id,
                        error: crate::studio_error_from_anyhow(error),
                    },
                    _evidence: None,
                };
            }
            if runtime.shutdown_committed() {
                return ProfileCommandResult {
                    outcome: ProfileCommandOutcome::Rejected {
                        operation_id,
                        error: sealed(),
                    },
                    _evidence: None,
                };
            }
            let committed = match request {
                ProfileCommandRequest::SaveProfile(request) => {
                    let profile_id = request.profile.profile_id.clone();
                    let profile = match profile_input(request.profile) {
                        Ok(profile) => profile,
                        Err(error) => {
                            return ProfileCommandResult {
                                outcome: ProfileCommandOutcome::Rejected {
                                    operation_id,
                                    error: crate::studio_error_from_anyhow(error),
                                },
                                _evidence: None,
                            };
                        }
                    };
                    runtime.config_runtime.save_user_agent_profile_phased(
                        request.expected_settings_revision,
                        &profile_id,
                        &profile,
                    )
                }
                ProfileCommandRequest::SetSystemProfileEnabled(request) => {
                    runtime.config_runtime.set_system_agent_enabled_phased(
                        request.expected_settings_revision,
                        &request.profile_id,
                        request.enabled,
                    )
                }
            };
            let committed = match committed {
                Ok(value) => value,
                Err(failure) => {
                    return ProfileCommandResult {
                        outcome: profile_failure(operation_id, failure),
                        _evidence: None,
                    };
                }
            };
            let evidence = committed._evidence;
            let receipt = runtime.command_receipt(
                operation_id,
                committed.changed,
                vec![
                    runtime.resource_stamp("settings", evidence.configuration.revision),
                    runtime.resource_stamp("agent-profiles", evidence.profiles.snapshot.revision),
                ],
                CommandEffectPoint::FutureSession,
                true,
            );
            let targets = runtime.expose_configuration_targets(&evidence);
            // Original Profile followup is publish_settings_state (not reload's skills/accounts).
            let followup = runtime
                .publish_settings_state()
                .map_err(crate::studio_error_from_anyhow);
            let outcome = match (targets, followup) {
                (Ok(targets), Ok(())) => ProfileCommandOutcome::Committed {
                    reply: ProfileCommandReply {
                        receipt,
                        configuration: targets.configuration,
                        models: targets.models,
                        profiles: targets.profiles,
                    },
                },
                (Err(error), _) | (Ok(_), Err(error)) => {
                    ProfileCommandOutcome::CommittedButUnobserved { receipt, error }
                }
            };
            ProfileCommandResult {
                outcome,
                _evidence: Some(evidence),
            }
        }
    }

    /// The same registered-owner rule applies to disk adoption and its asynchronous followup.
    /// No automatic replay, synthetic receipt, or promise of a cross-file transaction.
    pub fn configuration_reload(
        &self,
        request: ConfigurationReloadRequest,
    ) -> impl Future<Output = ConfigurationReloadCommandResult> + Send + 'static + use<> {
        let runtime = self.clone();
        async move {
            let operation_id = request.operation_id;
            if let Err(error) = Self::validate_operation_id(&operation_id) {
                return ConfigurationReloadCommandResult {
                    outcome: ConfigurationReloadOutcome::Rejected {
                        operation_id,
                        error: crate::studio_error_from_anyhow(error),
                    },
                    _evidence: None,
                };
            }
            if runtime.shutdown_committed() {
                return ConfigurationReloadCommandResult {
                    outcome: ConfigurationReloadOutcome::Rejected {
                        operation_id,
                        error: sealed(),
                    },
                    _evidence: None,
                };
            }
            // All ordinary Err returns in this original function precede state adoption: read,
            // CAS, disk/reconcile/validation, or obtaining the state write guard. Publication
            // failures after state replacement are returned inside the captured evidence.
            let reloaded = match runtime
                .config_runtime
                .reload_from_disk(request.expected_revision)
            {
                Ok(value) => value,
                Err(error) => {
                    return ConfigurationReloadCommandResult {
                        outcome: ConfigurationReloadOutcome::Rejected {
                            operation_id,
                            error: crate::studio_error_from_anyhow(error.into()),
                        },
                        _evidence: None,
                    };
                }
            };
            let evidence = reloaded.evidence;
            let targets = runtime.expose_configuration_targets(&evidence);
            let followup = runtime
                .configuration_reload_followup()
                .await
                .map_err(crate::studio_error_from_anyhow);
            let outcome = match (targets, followup) {
                (Ok(result), Ok(())) => ConfigurationReloadOutcome::Returned {
                    operation_id,
                    result,
                },
                (Err(error), _) | (Ok(_), Err(error)) => {
                    ConfigurationReloadOutcome::AdoptedButUnobserved {
                        operation_id,
                        error,
                    }
                }
            };
            ConfigurationReloadCommandResult {
                outcome,
                _evidence: Some(evidence),
            }
        }
    }

    fn expose_configuration_targets(
        &self,
        evidence: &ConfigMutationEvidence,
    ) -> Result<ConfigurationReloadResult, StudioError> {
        let configuration = evidence
            .captures
            .get(self.owner_epoch())
            .cloned()
            .ok_or_else(missing_capture)??;
        let profiles = evidence
            .profiles
            .captures
            .get(self.owner_epoch())
            .cloned()
            .ok_or_else(missing_capture)??;
        let pair = configuration
            .pair
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        let material = profiles
            .material
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        profiles
            .source_status
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        if pair.target.stamp.settings_revision != evidence.configuration.revision
            || pair.target.stamp.model_catalog_revision != evidence.catalog.revision
            || profiles.profiles_revision != evidence.profiles.snapshot.revision
            || material.value != evidence.profiles.snapshot.catalog
            || &profiles.origin != self.profiles_source.origin()
        {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Original three-target capture does not match its command/adoption evidence",
                false,
            ));
        }
        self.configuration_source.expose_committed(&configuration)?;
        self.profiles_source
            .expose_committed(&profiles, evidence.profiles.snapshot.revision)?;
        Ok(ConfigurationReloadResult {
            configuration: pair.target.configuration.clone(),
            models: pair.target.catalog.clone(),
            profiles: pl_protocol::products::references::AgentProfilesReadTarget {
                origin: profiles.origin.clone(),
                reference: material.reference,
            },
        })
    }
}
fn profile_input(input: AgentProfileEdit) -> anyhow::Result<UserAgentProfile> {
    Ok(UserAgentProfile {
        enabled: input.enabled,
        display_name: input.display_name,
        description: input.description,
        when_to_use: input.when_to_use,
        system_instructions: input.system_instructions,
        account_id: AccountId::new(input.account_id)?,
        model_id: input.model_id,
        // Preserve the live Profile command adapter's existing optional-effort normalization.
        effort: input
            .effort
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty())
            .map(ReasoningEffort::new),
        workspace_mode: input.workspace_mode,
    })
}
fn profile_failure(operation_id: String, failure: ProfileMutationFailure) -> ProfileCommandOutcome {
    match failure {
        ProfileMutationFailure::Preflight(error) => ProfileCommandOutcome::Rejected {
            operation_id,
            error: crate::studio_error_from_anyhow(error.into()),
        },
        ProfileMutationFailure::Commit(error) => ProfileCommandOutcome::Unknown {
            operation_id,
            error: crate::studio_error_from_anyhow(error.into()),
        },
        ProfileMutationFailure::Confirmed(error) => {
            ProfileCommandOutcome::ConfirmedWithoutUsableReceipt {
                operation_id,
                error: crate::studio_error_from_anyhow(error.into()),
            }
        }
    }
}
fn sealed() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Configuration/Profile calls are sealed",
        false,
    )
}
fn missing_capture() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "The original three-target capture is not attached to this runtime",
        true,
    )
}
