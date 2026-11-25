//! agent 目录、MCP/LSP 健康与观测状态桥接。

use crate::api::studio::types::*;
use pl_studio_runtime::AgentExecutionPhase;
use pl_studio_runtime::*;

pub(crate) fn bridge_agent_directory_entry(
    agent: StudioAgentDirectoryEntry,
) -> BridgeAgentDirectoryEntryDto {
    BridgeAgentDirectoryEntryDto {
        agent_id: agent.agent_id,
        session_id: agent.session_id,
        parent_agent_id: agent.parent_agent_id,
        thread_id: agent.thread_id,
        role: agent.role,
        delegation_mode: agent.delegation_mode.into(),
        delegation_preference: agent.delegation_preference.into(),
        frozen_model: agent.frozen_model.map(Into::into),
        task: agent.task,
        summary: agent.summary,
        activity: match agent.activity {
            StudioAgentActivity::Native {
                state,
                execution,
                can_stop,
                awaiting_scheduling,
            } => BridgeAgentActivity::Native {
                state: bridge_agent_state(state),
                execution: execution.map(|execution| BridgeAgentExecution {
                    turn_id: execution.turn_id().map(str::to_owned),
                    phase: match execution.phase() {
                        AgentExecutionPhase::Preparing => BridgeAgentExecutionPhase::Preparing,
                        AgentExecutionPhase::AwaitingStorage => {
                            BridgeAgentExecutionPhase::AwaitingStorage
                        }
                        AgentExecutionPhase::AwaitingAdmission => {
                            BridgeAgentExecutionPhase::AwaitingAdmission
                        }
                        AgentExecutionPhase::Running => BridgeAgentExecutionPhase::Running,
                        AgentExecutionPhase::Stopping => BridgeAgentExecutionPhase::Stopping,
                    },
                    id: execution.id().to_owned(),
                }),
                can_stop,
                awaiting_scheduling,
            },
            StudioAgentActivity::Acp { explicitly_closed } => {
                BridgeAgentActivity::Acp { explicitly_closed }
            }
        },
        updated_at: agent.updated_at,
    }
}

fn bridge_agent_state(state: AgentState) -> BridgeAgentState {
    match state {
        AgentState::Idle(_) => BridgeAgentState::Idle(BridgeIdleAgent {}),
        AgentState::Running(value) => BridgeAgentState::Running(BridgeRunningAgent {
            turn_id: value.turn_id().to_string(),
        }),
        AgentState::WaitingInteraction(value) => {
            BridgeAgentState::WaitingInteraction(BridgeWaitingInteractionAgent {
                turn_id: value.turn_id().to_string(),
                interaction_id: value.interaction_id().to_string(),
            })
        }
        AgentState::Closing(_) => BridgeAgentState::Closing(BridgeClosingAgent {}),
        AgentState::Closed(_) => BridgeAgentState::Closed(BridgeClosedAgent {}),
    }
}

impl From<StudioLspHealth> for BridgeLspHealthDto {
    fn from(health: StudioLspHealth) -> Self {
        Self {
            active_lsp_servers: health.active_lsp_servers,
            lsp_servers: health
                .lsp_servers
                .into_iter()
                .map(bridge_lsp_server)
                .collect(),
        }
    }
}

pub(crate) fn bridge_lsp_server(server: StudioLspServer) -> BridgeLspServerDto {
    BridgeLspServerDto {
        id: server.id,
        configuration_path: server.configuration_path,
        phase: server.phase,
        display_name: server.display_name,
        extensions: server.extensions,
        language_ids: server.language_ids,
        state: bridge_lsp_server_state(server.state),
    }
}

fn bridge_lsp_server_state(state: StudioLspServerState) -> BridgeLspServerState {
    match state {
        StudioLspServerState::Checking(state) => BridgeLspServerState::Checking {
            message: state.message().to_string(),
        },
        StudioLspServerState::Available(state) => BridgeLspServerState::Available {
            checked_at: state.checked_at(),
            diagnostic_count: state.diagnostic_count(),
            activity: bridge_lsp_activity(state.activity()),
        },
        StudioLspServerState::Unavailable(state) => BridgeLspServerState::Unavailable {
            checked_at: state.checked_at(),
            error: bridge_state_error(state.error()),
        },
        StudioLspServerState::Disabled(state) => BridgeLspServerState::Disabled {
            message: state.message().to_string(),
        },
    }
}

fn bridge_lsp_activity(activity: &LspAvailableActivity) -> BridgeLspActivity {
    match activity {
        LspAvailableActivity::Idle(_) => BridgeLspActivity::Idle,
        LspAvailableActivity::Busy(state) => BridgeLspActivity::Busy {
            title: state.title().map(ToString::to_string),
            message: state.message().map(ToString::to_string),
            percentage: state.percentage(),
        },
        LspAvailableActivity::Indexing(state) => BridgeLspActivity::Indexing {
            title: state.title().map(ToString::to_string),
            message: state.message().map(ToString::to_string),
            percentage: state.percentage(),
        },
    }
}

pub(crate) fn bridge_state_error(error: &pl_studio_runtime::StateError) -> BridgeStateError {
    error.into()
}

pub(crate) fn bridge_uninitialized_resource(
    state: &pl_studio_runtime::UninitializedResource,
) -> BridgeUninitializedResource {
    BridgeUninitializedResource {
        revision: state.revision(),
        updated_at: state.updated_at(),
    }
}

pub(crate) fn bridge_loading_resource(
    state: &pl_studio_runtime::LoadingResource,
) -> BridgeLoadingResource {
    BridgeLoadingResource {
        revision: state.revision(),
        operation: state.operation().into(),
        operation_id: state.operation_id().to_string(),
        started_at: state.started_at(),
    }
}

pub(crate) fn bridge_ready_resource<T>(
    state: &pl_studio_runtime::ReadyResource<T>,
) -> BridgeReadyResource {
    BridgeReadyResource {
        revision: state.revision(),
        updated_at: state.updated_at(),
        last_checked_at: state.last_checked_at(),
    }
}

pub(crate) fn bridge_refreshing_resource<T>(
    state: &pl_studio_runtime::RefreshingResource<T>,
) -> BridgeRefreshingResource {
    BridgeRefreshingResource {
        revision: state.revision(),
        operation: state.operation().into(),
        operation_id: state.operation_id().to_string(),
        started_at: state.started_at(),
        last_checked_at: state.last_checked_at(),
    }
}

pub(crate) fn bridge_stale_resource<T>(
    state: &pl_studio_runtime::StaleResource<T>,
) -> BridgeStaleResource {
    BridgeStaleResource {
        revision: state.revision(),
        stale_at: state.stale_at(),
        last_checked_at: state.last_checked_at(),
    }
}

pub(crate) fn bridge_degraded_resource<T>(
    state: &pl_studio_runtime::DegradedResource<T>,
) -> BridgeDegradedResource {
    BridgeDegradedResource {
        revision: state.revision(),
        failed_at: state.failed_at(),
        last_checked_at: state.last_checked_at(),
        operation: state.operation().into(),
        error: state.error().clone().into(),
    }
}

pub(crate) fn bridge_failed_resource(
    state: &pl_studio_runtime::FailedResource,
) -> BridgeFailedResource {
    BridgeFailedResource {
        revision: state.revision(),
        failed_at: state.failed_at(),
        operation: state.operation().into(),
        error: state.error().clone().into(),
    }
}

pub(crate) fn bridge_stopped_resource(
    state: &pl_studio_runtime::StoppedResource,
) -> BridgeStoppedResource {
    BridgeStoppedResource {
        revision: state.revision(),
        stopped_at: state.stopped_at(),
    }
}

impl From<pl_studio_runtime::StateError> for BridgeStateError {
    fn from(error: pl_studio_runtime::StateError) -> Self {
        Self {
            code: error.code,
            message: error.message,
            retryable: error.retryable,
        }
    }
}

impl From<&pl_studio_runtime::StateError> for BridgeStateError {
    fn from(error: &pl_studio_runtime::StateError) -> Self {
        Self {
            code: error.code.clone(),
            message: error.message.clone(),
            retryable: error.retryable,
        }
    }
}

impl From<pl_studio_runtime::StateOperation> for BridgeStateOperation {
    fn from(operation: pl_studio_runtime::StateOperation) -> Self {
        match operation {
            pl_studio_runtime::StateOperation::Initialize => Self::Initialize,
            pl_studio_runtime::StateOperation::Activate => Self::Activate,
            pl_studio_runtime::StateOperation::Reload => Self::Reload,
            pl_studio_runtime::StateOperation::Reconcile => Self::Reconcile,
            pl_studio_runtime::StateOperation::Discover => Self::Discover,
            pl_studio_runtime::StateOperation::Check => Self::Check,
            pl_studio_runtime::StateOperation::Probe => Self::Probe,
            pl_studio_runtime::StateOperation::Repair => Self::Repair,
            pl_studio_runtime::StateOperation::Reset => Self::Reset,
            pl_studio_runtime::StateOperation::Shutdown => Self::Shutdown,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn member(activity: StudioAgentActivity) -> StudioAgentDirectoryEntry {
        StudioAgentDirectoryEntry {
            agent_id: "agent".into(),
            session_id: "session".into(),
            parent_agent_id: Some("parent".into()),
            thread_id: "thread".into(),
            role: "executor".into(),
            delegation_mode: Default::default(),
            delegation_preference: Default::default(),
            frozen_model: None,
            task: "task".into(),
            summary: None,
            activity,
            updated_at: 1,
        }
    }

    #[test]
    fn agent_directory_keeps_backend_identity_and_native_stop_qualification() {
        let native = bridge_agent_directory_entry(member(StudioAgentActivity::Native {
            state: AgentState::idle(),
            execution: Some(pl_studio_runtime::AgentExecution::new(
                "execution",
                AgentExecutionPhase::Preparing,
                None,
            )),
            can_stop: true,
            awaiting_scheduling: false,
        }));
        assert_eq!(native.agent_id, "agent");
        assert_eq!(native.session_id, "session");
        assert_eq!(native.thread_id, "thread");
        assert!(matches!(
            native.activity,
            BridgeAgentActivity::Native {
                state: BridgeAgentState::Idle(_),
                execution: Some(BridgeAgentExecution {
                    ref id,
                    phase: BridgeAgentExecutionPhase::Preparing,
                    ..
                }),
                can_stop: true,
                awaiting_scheduling: false,
            } if id == "execution"
        ));

        let acp = bridge_agent_directory_entry(member(StudioAgentActivity::Acp {
            explicitly_closed: true,
        }));
        assert!(matches!(
            acp.activity,
            BridgeAgentActivity::Acp {
                explicitly_closed: true
            }
        ));
    }
}
