use anyhow::{Context, Result};
use pl_studio_runtime::{
    StudioProductBaseline, StudioProductBaselineState, StudioProductEventEnvelope,
    StudioProductEventKind,
};

use super::runtime::{
    bridge_account_usage_state, bridge_agent_directory, bridge_agent_profiles, bridge_bots_state,
    bridge_lsp_state, bridge_mcp_state, bridge_model_catalog_state, bridge_persistence_queue_state,
    bridge_persistence_state, bridge_project_directory, bridge_recovery_state,
    bridge_session_costs_state, bridge_settings_config_state, bridge_skills_state,
    bridge_thread_mode_catalog, bridge_update_state,
};
use super::thread_stream::{bridge_child_interaction, bridge_thread};
use crate::api::studio::types::*;

pub(crate) fn bridge_product_event(
    event: StudioProductEventEnvelope,
) -> Result<BridgeProductEventEnvelope> {
    Ok(BridgeProductEventEnvelope {
        event_id: event.event_id,
        sequence: event.sequence,
        created_at: event.created_at,
        payload: match event.kind {
            StudioProductEventKind::ProjectDirectoryChanged(state) => {
                BridgeProductEventPayload::ProjectDirectoryChanged(bridge_project_directory(
                    state.state,
                ))
            }
            StudioProductEventKind::ThreadDirectoryChanged(state) => {
                BridgeProductEventPayload::ThreadDirectoryChanged(BridgeThreadDirectoryDelta {
                    revision: state.revision,
                    updated_at: state.updated_at,
                    upserted: state.upserted.into_iter().map(bridge_thread).collect(),
                    removed: state.removed,
                })
            }
            StudioProductEventKind::AgentDirectoryChanged(state) => {
                BridgeProductEventPayload::AgentDirectoryChanged(bridge_agent_directory(
                    state.state,
                ))
            }
            StudioProductEventKind::SettingsConfigStateChanged(state) => {
                BridgeProductEventPayload::SettingsConfigStateChanged(Box::new(
                    bridge_settings_config_state(state.state),
                ))
            }
            StudioProductEventKind::ModelCatalogStateChanged(state) => {
                BridgeProductEventPayload::ModelCatalogStateChanged(Box::new(
                    bridge_model_catalog_state(state.state),
                ))
            }
            StudioProductEventKind::RecoveryStateChanged(state) => {
                BridgeProductEventPayload::RecoveryStateChanged(bridge_recovery_state(state.state))
            }
            StudioProductEventKind::McpStateChanged(state) => {
                BridgeProductEventPayload::McpStateChanged(bridge_mcp_state(state.state))
            }
            StudioProductEventKind::LspStateChanged(state) => {
                BridgeProductEventPayload::LspStateChanged(bridge_lsp_state(state.state))
            }
            StudioProductEventKind::SkillsStateChanged(state) => {
                BridgeProductEventPayload::SkillsStateChanged(bridge_skills_state(state))
            }
            StudioProductEventKind::ThreadModeCatalogChanged(state) => {
                BridgeProductEventPayload::ThreadModeCatalogChanged(bridge_thread_mode_catalog(
                    state,
                ))
            }
            StudioProductEventKind::AccountUsageStateChanged(state) => {
                BridgeProductEventPayload::AccountUsageStateChanged(bridge_account_usage_state(
                    state.state,
                ))
            }
            StudioProductEventKind::AcpAuthStateChanged(state) => {
                BridgeProductEventPayload::AcpAuthStateChanged(Box::new(
                    super::acp::bridge_acp_auth_snapshot(*state),
                ))
            }
            StudioProductEventKind::AcpInstallStateChanged(state) => {
                BridgeProductEventPayload::AcpInstallStateChanged(Box::new(
                    super::acp_install::bridge_acp_install_snapshot(*state),
                ))
            }
            StudioProductEventKind::ModelPerformanceStateChanged(_) => {
                anyhow::bail!("model performance events use the dedicated statistics feed")
            }
            StudioProductEventKind::SessionCostsChanged(state) => {
                BridgeProductEventPayload::SessionCostsChanged(Box::new(
                    bridge_session_costs_state(state),
                ))
            }
            StudioProductEventKind::ChildInteractionsChanged(state) => {
                BridgeProductEventPayload::ChildInteractionsChanged(Box::new(
                    bridge_child_interactions_state(state)?,
                ))
            }
            StudioProductEventKind::UpdaterStateChanged(state) => {
                BridgeProductEventPayload::UpdaterStateChanged(bridge_update_state(state))
            }
            StudioProductEventKind::PersistenceStateChanged(state) => {
                BridgeProductEventPayload::PersistenceStateChanged(bridge_persistence_state(state))
            }
            StudioProductEventKind::PersistenceQueueStateChanged(state) => {
                BridgeProductEventPayload::PersistenceQueueStateChanged(Box::new(
                    bridge_persistence_queue_state(state),
                ))
            }
            StudioProductEventKind::AgentProfilesStateChanged(state) => {
                BridgeProductEventPayload::AgentProfilesStateChanged(Box::new(
                    BridgeAgentProfilesStateSnapshot {
                        state: bridge_agent_profiles(state.state),
                    },
                ))
            }
            StudioProductEventKind::BotsStateChanged(state) => {
                BridgeProductEventPayload::BotsStateChanged(Box::new(bridge_bots_state(state)))
            }
        },
    })
}

/// 把 runtime 的 typed 基线转换为 FRB 基线 payload。
pub(crate) fn bridge_product_baseline(
    baseline: StudioProductBaseline,
) -> Result<(u64, BridgeProductBaseline)> {
    let revision = baseline.revision;
    let state = match baseline.state {
        StudioProductBaselineState::ProjectDirectory(state) => {
            BridgeProductBaseline::ProjectDirectory(bridge_project_directory(state.state))
        }
        StudioProductBaselineState::ThreadDirectory(state) => {
            BridgeProductBaseline::ThreadDirectory(super::runtime::bridge_thread_directory_page(
                state.state,
            ))
        }
        StudioProductBaselineState::AgentDirectory(state) => {
            BridgeProductBaseline::AgentDirectory(bridge_agent_directory(state.state))
        }
        StudioProductBaselineState::SettingsConfig(state) => BridgeProductBaseline::SettingsConfig(
            Box::new(bridge_settings_config_state(state.state)),
        ),
        StudioProductBaselineState::ModelCatalog(state) => {
            BridgeProductBaseline::ModelCatalog(Box::new(bridge_model_catalog_state(state.state)))
        }
        StudioProductBaselineState::Recovery(state) => {
            BridgeProductBaseline::Recovery(bridge_recovery_state(state.state))
        }
        StudioProductBaselineState::Mcp(state) => {
            BridgeProductBaseline::Mcp(bridge_mcp_state(state.state))
        }
        StudioProductBaselineState::Lsp(state) => {
            BridgeProductBaseline::Lsp(bridge_lsp_state(state.state))
        }
        StudioProductBaselineState::Skills(state) => {
            BridgeProductBaseline::Skills(bridge_skills_state(*state))
        }
        StudioProductBaselineState::ThreadModeCatalog(state) => {
            BridgeProductBaseline::ThreadModeCatalog(bridge_thread_mode_catalog(*state))
        }
        StudioProductBaselineState::AccountUsage(state) => {
            BridgeProductBaseline::AccountUsage(bridge_account_usage_state(state.state))
        }
        StudioProductBaselineState::AcpAuth(state) => {
            BridgeProductBaseline::AcpAuth(Box::new(super::acp::bridge_acp_auth_snapshot(*state)))
        }
        StudioProductBaselineState::AcpInstall(state) => BridgeProductBaseline::AcpInstall(
            Box::new(super::acp_install::bridge_acp_install_snapshot(*state)),
        ),
        StudioProductBaselineState::ModelPerformance(_) => {
            anyhow::bail!("model performance baselines use the dedicated statistics feed")
        }
        StudioProductBaselineState::SessionCosts(state) => {
            BridgeProductBaseline::SessionCosts(Box::new(bridge_session_costs_state(*state)))
        }
        StudioProductBaselineState::ChildInteractions(state) => {
            BridgeProductBaseline::ChildInteractions(Box::new(bridge_child_interactions_state(
                *state,
            )?))
        }
        StudioProductBaselineState::Updater(state) => {
            BridgeProductBaseline::Updater(bridge_update_state(*state))
        }
        StudioProductBaselineState::Persistence(state) => {
            BridgeProductBaseline::Persistence(bridge_persistence_state(*state))
        }
        StudioProductBaselineState::PersistenceQueue(state) => {
            BridgeProductBaseline::PersistenceQueue(Box::new(bridge_persistence_queue_state(
                *state,
            )))
        }
        StudioProductBaselineState::AgentProfiles(state) => {
            BridgeProductBaseline::AgentProfiles(Box::new(BridgeAgentProfilesStateSnapshot {
                state: bridge_agent_profiles(state.state),
            }))
        }
        StudioProductBaselineState::Bots(state) => {
            BridgeProductBaseline::Bots(Box::new(bridge_bots_state(*state)))
        }
    };
    Ok((revision, state))
}

fn bridge_child_interactions_state(
    value: pl_studio_runtime::StudioChildInteractionsState,
) -> Result<BridgeChildInteractionsState> {
    let revision = value.state.revision();
    let updated_at = value.state.updated_at();
    let items = value
        .state
        .into_value()
        .context("child interactions projection has no committed baseline")?
        .into_iter()
        .map(bridge_child_interaction)
        .collect::<Result<Vec<_>>>()?;
    Ok(BridgeChildInteractionsState {
        host_thread_id: value.host_thread_id,
        revision,
        updated_at,
        items,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{
        ChildInteractionSummary, InteractionRequest, InteractionScope, UserQuestion,
    };
    use pl_studio_runtime::{StudioChildInteractionsState, StudioProductTopic};

    #[test]
    fn child_interactions_baseline_and_event_preserve_scope_and_pending_payload() -> Result<()> {
        let mut interaction = InteractionRequest::user_input(
            "interaction-1",
            InteractionScope {
                thread_id: "child-1".into(),
                turn_id: "turn-1".into(),
                item_id: Some("item-1".into()),
                tool_id: Some("tool-1".into()),
                agent_path: Some("root/child-1".into()),
                purpose: Default::default(),
            },
            vec![UserQuestion {
                id: "question-1".into(),
                header: "Credential".into(),
                question: "Provide the test credential".into(),
                is_other: true,
                is_secret: true,
                options: None,
            }],
            41,
        );
        interaction.revision = 23;
        let state = StudioChildInteractionsState {
            host_thread_id: "root".into(),
            state: pl_protocol::ObservedResource::ready(
                7,
                43,
                vec![ChildInteractionSummary::new(interaction)],
            ),
        };
        let (_, baseline) = bridge_product_baseline(StudioProductBaseline {
            topic: StudioProductTopic::ChildInteractions {
                host_thread_id: "root".into(),
            },
            revision: 7,
            state: StudioProductBaselineState::ChildInteractions(Box::new(state.clone())),
        })?;
        let event = bridge_product_event(StudioProductEventEnvelope {
            event_id: "event-1".into(),
            sequence: 101,
            created_at: 47,
            kind: StudioProductEventKind::ChildInteractionsChanged(state),
        })?;
        let BridgeProductBaseline::ChildInteractions(baseline) = baseline else {
            anyhow::bail!("expected a scoped child-interactions baseline");
        };
        let BridgeProductEventPayload::ChildInteractionsChanged(ref payload) = event.payload else {
            anyhow::bail!("expected a scoped child-interactions event");
        };
        assert_eq!(baseline, *payload);
        assert_eq!(payload.host_thread_id, "root");
        assert_eq!(payload.revision, 7);
        assert_eq!(payload.updated_at, 43);
        let item = &payload.items[0];
        assert_eq!(item.child_thread_id, "child-1");
        assert_eq!(item.interaction_id, "interaction-1");
        assert_eq!(item.revision, 23);
        assert_eq!(item.interaction.scope.turn_id, "turn-1");
        let BridgeInteractionContent::UserInput { questions, state } = &item.interaction.content
        else {
            anyhow::bail!("pending user input changed kind");
        };
        assert!(questions[0].is_secret);
        assert_eq!(questions[0].question, "Provide the test credential");
        assert_eq!(
            state,
            &BridgeUserInputInteractionState::Pending {
                operation_id: "interaction-1".into(),
            }
        );
        let encoded = serde_json::to_vec(&event)?;
        assert_eq!(
            serde_json::from_slice::<BridgeProductEventEnvelope>(&encoded)?,
            event
        );

        let empty = bridge_child_interactions_state(StudioChildInteractionsState {
            host_thread_id: "root".into(),
            state: pl_protocol::ObservedResource::ready(8, 49, vec![]),
        })?;
        assert_eq!(empty.revision, 8);
        assert!(empty.items.is_empty());
        Ok(())
    }

    #[test]
    fn child_interactions_without_committed_state_cannot_masquerade_as_empty() {
        let result = bridge_child_interactions_state(StudioChildInteractionsState {
            host_thread_id: "root".into(),
            state: pl_protocol::ObservedResource::uninitialized(0),
        });
        assert!(result.is_err());
        let invalid = BridgeProductTopic::ChildInteractions {
            host_thread_id: " ".into(),
        };
        assert!(invalid.validate_scope().is_err());
    }
}
