mod activity;
mod activity_delivery;
pub(crate) use activity_delivery::activity_content as bridge_activity_content;
mod interaction;
mod usage;

pub(crate) use interaction::child_interaction as bridge_child_interaction;
pub(crate) use interaction::interaction as bridge_interaction;

use anyhow::Result;
use pl_protocol::{
    AgentSessionPlanDocument, AgentSessionPlanPhase, AgentSessionPlanRuntimeSnapshot,
    BudgetLimitKind, BudgetLimitSnapshot, McpAvailabilityDescriptor, McpHealthSnapshot,
    McpServerDescriptor, PromptPrefixChangedReason, RuntimeCostAmount, Thread, ThreadAttachment,
    ThreadNotification, ThreadNotificationEnvelope, ThreadRuntimeLiveUsage, ThreadRuntimeSnapshot,
    ThreadRuntimeUsage, ThreadRuntimeUsageState, ThreadSnapshot, ThreadStatus,
    ThreadSubscriptionUpdate, TodoItem, TodoListSnapshot, TodoStatus, TokenUsageSnapshot, Turn,
    TurnCancellationCause, TurnCompletion, TurnPhase, TurnRolloverOutcome, TurnState,
    WorkflowRunLifecycle, WorkflowRuntimeRunSnapshot, WorkflowRuntimeSnapshot,
};

use crate::api::studio::types::*;

pub(crate) fn bridge_thread_update(
    update: ThreadSubscriptionUpdate,
) -> Result<BridgeThreadSubscriptionUpdate> {
    match update {
        ThreadSubscriptionUpdate::Snapshot { snapshot } => {
            Ok(BridgeThreadSubscriptionUpdate::Snapshot {
                snapshot: Box::new(bridge_thread_snapshot(*snapshot)?),
            })
        }
        ThreadSubscriptionUpdate::Notification { notification } => {
            Ok(BridgeThreadSubscriptionUpdate::Notification {
                notification: Box::new(thread_notification(*notification)?),
            })
        }
    }
}

fn thread_notification(
    envelope: ThreadNotificationEnvelope,
) -> Result<BridgeThreadNotificationEnvelope> {
    let notification = match envelope.notification {
        ThreadNotification::TurnStarted { turn: value } => BridgeThreadNotification::TurnStarted {
            turn: Box::new(bridge_turn(value)),
        },
        ThreadNotification::TurnUpdated { turn: value } => BridgeThreadNotification::TurnUpdated {
            turn: Box::new(bridge_turn(value)),
        },
        ThreadNotification::TurnCompleted { turn: value } => {
            BridgeThreadNotification::TurnCompleted {
                turn: Box::new(bridge_turn(value)),
            }
        }
        ThreadNotification::InteractionChanged { interaction: value } => {
            BridgeThreadNotification::InteractionChanged {
                interaction: Box::new(interaction::interaction(*value)?),
            }
        }
        ThreadNotification::ThreadRuntimeUpdated { runtime: value } => {
            BridgeThreadNotification::ThreadRuntimeUpdated {
                runtime: Box::new(runtime_snapshot(*value)),
            }
        }
        ThreadNotification::ActivityChanged { activity: value } => {
            BridgeThreadNotification::ActivityChanged {
                activity: value.map(|current| Box::new(activity::activity(*current))),
            }
        }
        ThreadNotification::StorageChanged { storage: value } => {
            BridgeThreadNotification::StorageChanged {
                storage: value.map(|current| Box::new(activity::storage(*current))),
            }
        }
        ThreadNotification::Lagged { dropped } => BridgeThreadNotification::Lagged { dropped },
    };
    Ok(BridgeThreadNotificationEnvelope {
        thread_id: envelope.thread_id,
        epoch: envelope.epoch,
        base_revision: envelope.base_revision,
        revision: envelope.revision,
        emitted_at: envelope.emitted_at,
        notification,
    })
}

pub(crate) fn bridge_thread_snapshot(value: ThreadSnapshot) -> Result<BridgeThreadSnapshot> {
    let runtime_availability = if value.runtime.is_some() {
        BridgeThreadRuntimeAvailability::Active
    } else {
        BridgeThreadRuntimeAvailability::Inactive
    };
    Ok(BridgeThreadSnapshot {
        schema_version: value.schema_version,
        revision: value.revision,
        thread: bridge_thread(value.thread),
        active_turn: value.active_turn.map(bridge_turn),
        interactions: value
            .interactions
            .into_iter()
            .map(interaction::interaction)
            .collect::<Result<Vec<_>>>()?,
        runtime: value.runtime.map(runtime_snapshot),
        activity: value.activity.map(activity::activity),
        storage: value.storage.map(activity::storage),
        runtime_availability,
    })
}

pub(crate) fn bridge_thread(value: Thread) -> BridgeThread {
    BridgeThread {
        id: value.id,
        workspace_id: value.workspace_id,
        title: value.title,
        mode: value.mode.as_str().to_string(),
        delegation_mode: value.delegation_mode.into(),
        delegation_preference: value.delegation_preference.into(),
        frozen_model: value.frozen_model.map(Into::into),
        workspace_mode: value.workspace_mode.label().to_string(),
        workspace_path: value.workspace_path,
        root_thread_id: value.root_thread_id,
        parent_thread_id: value.parent_thread_id,
        role: value.role,
        agent_path: value.agent_path,
        status: match value.status {
            ThreadStatus::Idle => BridgeThreadStatus::Idle,
            ThreadStatus::Queued => BridgeThreadStatus::Queued,
            ThreadStatus::Running => BridgeThreadStatus::Running,
            ThreadStatus::WaitingTool => BridgeThreadStatus::WaitingTool,
            ThreadStatus::WaitingInteraction => BridgeThreadStatus::WaitingInteraction,
            ThreadStatus::Cancelling => BridgeThreadStatus::Cancelling,
            ThreadStatus::Closing => BridgeThreadStatus::Closing,
            ThreadStatus::Closed => BridgeThreadStatus::Closed,
            ThreadStatus::Faulted => BridgeThreadStatus::Faulted,
        },
        created_at: value.created_at,
        updated_at: value.updated_at,
        last_user_message_at: value.last_user_message_at,
        archived: value.archived,
    }
}

pub(crate) fn bridge_turn(value: Turn) -> BridgeTurn {
    BridgeTurn {
        input_id: value.input_id,
        id: value.id,
        thread_id: value.thread_id,
        revision: value.revision,
        state: bridge_turn_state(&value.state),
        updated_at: value.updated_at,
    }
}

pub(super) fn bridge_turn_state(value: &TurnState) -> BridgeTurnState {
    match value {
        TurnState::Queued(state) => BridgeTurnState::Queued {
            queued_at: state.queued_at(),
        },
        TurnState::Running(state) => BridgeTurnState::Running {
            started_at: state.started_at(),
            phase: turn_phase(state.phase()),
        },
        TurnState::Completed(state) => BridgeTurnState::Completed {
            started_at: state.started_at(),
            completed_at: state.completed_at(),
            completion: match state.completion() {
                TurnCompletion::Normal => BridgeTurnCompletion::Normal,
                TurnCompletion::InteractionRequested => BridgeTurnCompletion::InteractionRequested,
            },
        },
        TurnState::Cancelled(state) => BridgeTurnState::Cancelled {
            started_at: state.started_at(),
            requested_at: state.requested_at(),
            completed_at: state.completed_at(),
            cause: turn_cancellation_cause(state.cause().clone()),
        },
        TurnState::Failed(state) => BridgeTurnState::Failed {
            started_at: state.started_at(),
            completed_at: state.completed_at(),
            failure: bridge_turn_failure(state.failure().clone()),
        },
        TurnState::BudgetLimited(state) => BridgeTurnState::BudgetLimited {
            started_at: state.started_at(),
            completed_at: state.completed_at(),
            limit: turn_budget_limit(*state.limit()),
            rollover: turn_rollover(state.rollover().clone()),
        },
    }
}

pub(super) fn turn_cancellation_cause(value: TurnCancellationCause) -> BridgeTurnCancellationCause {
    match value {
        TurnCancellationCause::Unspecified => BridgeTurnCancellationCause::Unspecified,
        TurnCancellationCause::UserRequested => BridgeTurnCancellationCause::UserRequested,
        TurnCancellationCause::RuntimeShutdown => BridgeTurnCancellationCause::RuntimeShutdown,
        TurnCancellationCause::AgentClosed => BridgeTurnCancellationCause::AgentClosed,
        TurnCancellationCause::Interrupted => BridgeTurnCancellationCause::Interrupted,
        TurnCancellationCause::Recovery => BridgeTurnCancellationCause::Recovery,
        TurnCancellationCause::Coalesced { target_turn_id } => {
            BridgeTurnCancellationCause::Coalesced { target_turn_id }
        }
    }
}

pub(super) fn turn_rollover(value: TurnRolloverOutcome) -> BridgeTurnRolloverOutcome {
    match value {
        TurnRolloverOutcome::NotAttempted => BridgeTurnRolloverOutcome::NotAttempted,
        TurnRolloverOutcome::Succeeded => BridgeTurnRolloverOutcome::Succeeded,
        TurnRolloverOutcome::Failed { error } => BridgeTurnRolloverOutcome::Failed { error },
    }
}

pub(super) fn turn_budget_limit(value: BudgetLimitSnapshot) -> BridgeTurnBudgetLimit {
    BridgeTurnBudgetLimit {
        kind: match value.kind {
            BudgetLimitKind::ModelStep => BridgeTurnBudgetLimitKind::ModelStep,
            BudgetLimitKind::ToolCall => BridgeTurnBudgetLimitKind::ToolCall,
            BudgetLimitKind::Wait => BridgeTurnBudgetLimitKind::Wait,
            BudgetLimitKind::WallClock => BridgeTurnBudgetLimitKind::WallClock,
            BudgetLimitKind::AgentCount => BridgeTurnBudgetLimitKind::AgentCount,
            BudgetLimitKind::AgentDepth => BridgeTurnBudgetLimitKind::AgentDepth,
            BudgetLimitKind::Finalization => BridgeTurnBudgetLimitKind::Finalization,
        },
        usage: BridgeTurnBudgetUsage {
            model_steps: value.usage.model_steps,
            tool_calls: value.usage.tool_calls,
            wait_calls: value.usage.wait_calls,
            elapsed_ms: value.usage.elapsed_ms,
        },
    }
}

pub(super) fn bridge_turn_failure(value: pl_protocol::TurnFailure) -> BridgeTurnFailureDto {
    BridgeTurnFailureDto {
        category: format!("{:?}", value.category).to_ascii_lowercase(),
        provider_kind: value
            .provider_kind
            .map(|kind| format!("{kind:?}").to_ascii_lowercase()),
        code: value.code,
        http_status: value.http_status,
        message: value.message,
        retryable: value.retry.is_retryable(),
        retry_after_ms: value.retry.retry_after_ms(),
    }
}

fn turn_phase(value: TurnPhase) -> BridgeTurnPhase {
    match value {
        TurnPhase::Preparing => BridgeTurnPhase::Preparing,
        TurnPhase::Thinking => BridgeTurnPhase::Thinking,
        TurnPhase::Responding => BridgeTurnPhase::Responding,
        TurnPhase::Planning => BridgeTurnPhase::Planning,
        TurnPhase::RunningTool => BridgeTurnPhase::RunningTool,
        TurnPhase::Persisting => BridgeTurnPhase::Persisting,
    }
}

pub(super) fn attachment(value: &ThreadAttachment) -> BridgeThreadAttachment {
    BridgeThreadAttachment {
        id: value.id.clone(),
        modality: match value.modality {
            pl_protocol::AttachmentModality::Image => BridgeAttachmentModality::Image,
            pl_protocol::AttachmentModality::Video => BridgeAttachmentModality::Video,
            pl_protocol::AttachmentModality::File => BridgeAttachmentModality::File,
        },
        media_type: value.media_type.clone(),
        filename: value.filename.clone(),
        width: value.width,
        height: value.height,
        byte_size: value.byte_size,
    }
}

pub(super) fn wait_presentation(
    value: pl_protocol::ThreadWaitPresentation,
) -> BridgeThreadWaitPresentation {
    BridgeThreadWaitPresentation {
        intent: match value.intent() {
            pl_protocol::ThreadWaitIntent::Events {
                targets,
                timeout_ms,
            } => BridgeThreadWaitIntent::Events {
                targets: targets.iter().map(wait_target).collect(),
                timeout_ms: *timeout_ms,
            },
            pl_protocol::ThreadWaitIntent::Timer { duration_ms } => BridgeThreadWaitIntent::Timer {
                duration_ms: *duration_ms,
            },
        },
        state: match value.state() {
            pl_protocol::ThreadWaitState::Waiting => BridgeThreadWaitState::Waiting,
            pl_protocol::ThreadWaitState::Ready => BridgeThreadWaitState::Ready,
            pl_protocol::ThreadWaitState::TimedOut => BridgeThreadWaitState::TimedOut,
            pl_protocol::ThreadWaitState::Elapsed => BridgeThreadWaitState::Elapsed,
            pl_protocol::ThreadWaitState::Cancelled => BridgeThreadWaitState::Cancelled,
            pl_protocol::ThreadWaitState::Failed => BridgeThreadWaitState::Failed,
            pl_protocol::ThreadWaitState::Interrupted => BridgeThreadWaitState::Interrupted,
        },
        messages_ready: value.messages_ready(),
    }
}

fn wait_target(value: &pl_protocol::ThreadWaitTarget) -> BridgeThreadWaitTarget {
    BridgeThreadWaitTarget {
        task_id: value.task_id().to_owned(),
        tool_name: value.tool_name().map(str::to_owned),
        summary: value.summary().map(str::to_owned),
        summary_truncated: value.summary_truncated(),
        status: value.status().map(|status| match status {
            pl_protocol::ThreadWaitTargetStatus::Running => BridgeThreadWaitTargetStatus::Running,
            pl_protocol::ThreadWaitTargetStatus::Succeeded => {
                BridgeThreadWaitTargetStatus::Succeeded
            }
            pl_protocol::ThreadWaitTargetStatus::Failed => BridgeThreadWaitTargetStatus::Failed,
            pl_protocol::ThreadWaitTargetStatus::Cancelled => {
                BridgeThreadWaitTargetStatus::Cancelled
            }
            pl_protocol::ThreadWaitTargetStatus::Interrupted => {
                BridgeThreadWaitTargetStatus::Interrupted
            }
        }),
    }
}

/// 普通问答投影 → bridge typed 投影：问题顺序、权威状态与脱敏标记原样过桥。
pub(crate) fn runtime_snapshot(value: ThreadRuntimeSnapshot) -> BridgeThreadRuntimeSnapshot {
    BridgeThreadRuntimeSnapshot {
        thread_id: value.thread_id,
        model_route: value
            .model_route
            .map(|route| BridgeThreadModelRouteSnapshot {
                bot_id: route.bot_id,
                account_id: route.account_id,
                model_id: route.model_id,
                effort: route.effort,
                revision: route.revision,
                available: route.available,
                unavailable_reason: route.unavailable_reason,
            }),
        usage: runtime_usage(value.usage),
        live_usage: value.live_usage.map(runtime_live_usage),
        turn_completion_tokens: value.turn_completion_tokens,
        turn_response_millis: value.turn_response_millis,
        todo: value.todo.map(todo),
        active_skills: value.active_skills,
        active_mcp_servers: value.active_mcp_servers,
        active_lsp_servers: value.active_lsp_servers,
        progress: value.progress,
        mcp_health: value.mcp_health.map(mcp_health),
        workflow: value.workflow.map(workflow_runtime_snapshot),
        plan: value.plan.map(plan_runtime_snapshot),
        execution: value.execution.map(|execution| BridgeAgentExecution {
            turn_id: execution.turn_id().map(str::to_owned),
            phase: match execution.phase() {
                pl_protocol::AgentExecutionPhase::Preparing => BridgeAgentExecutionPhase::Preparing,
                pl_protocol::AgentExecutionPhase::AwaitingStorage => {
                    BridgeAgentExecutionPhase::AwaitingStorage
                }
                pl_protocol::AgentExecutionPhase::AwaitingAdmission => {
                    BridgeAgentExecutionPhase::AwaitingAdmission
                }
                pl_protocol::AgentExecutionPhase::Running => BridgeAgentExecutionPhase::Running,
                pl_protocol::AgentExecutionPhase::Stopping => BridgeAgentExecutionPhase::Stopping,
            },
            id: execution.id().to_owned(),
        }),
        continuation: value
            .continuation
            .map(|continuation| BridgeContinuationView {
                id: continuation.id().to_owned(),
                source_turn_id: continuation.source_turn_id().map(str::to_owned),
                reason: continuation.reason().map(|reason| match reason {
                    pl_protocol::ContinuationReason::UserStop => BridgeContinuationReason::UserStop,
                    pl_protocol::ContinuationReason::HostShutdown => {
                        BridgeContinuationReason::HostShutdown
                    }
                    pl_protocol::ContinuationReason::ProcessInterrupted => {
                        BridgeContinuationReason::ProcessInterrupted
                    }
                    pl_protocol::ContinuationReason::StepLimit => {
                        BridgeContinuationReason::StepLimit
                    }
                    pl_protocol::ContinuationReason::ExecutionFailed => {
                        BridgeContinuationReason::ExecutionFailed
                    }
                }),
                created_at: continuation.created_at(),
                claimed: continuation.claimed(),
            }),
        updated_at: value.updated_at,
    }
}

fn runtime_live_usage(value: ThreadRuntimeLiveUsage) -> BridgeThreadRuntimeLiveUsage {
    BridgeThreadRuntimeLiveUsage {
        turn_id: value.turn_id,
        attempt_id: value.attempt_id,
        completion_tokens: value.completion_tokens,
        response_millis: value.response_millis,
        latest_context_tokens: value.latest_context_tokens,
        state: match value.state {
            ThreadRuntimeUsageState::Live => BridgeThreadRuntimeUsageState::Live,
            ThreadRuntimeUsageState::Authoritative => BridgeThreadRuntimeUsageState::Authoritative,
        },
        observation_sequence: value.observation_sequence,
    }
}

fn workflow_runtime_snapshot(value: WorkflowRuntimeSnapshot) -> BridgeWorkflowRuntimeSnapshot {
    BridgeWorkflowRuntimeSnapshot {
        revision: value.revision,
        current_run: value.current_run.map(workflow_run),
    }
}

fn plan_runtime_snapshot(value: AgentSessionPlanRuntimeSnapshot) -> BridgePlanRuntimeSnapshot {
    BridgePlanRuntimeSnapshot {
        revision: value.revision,
        state: plan_phase(value.state),
        document: value.document.map(plan_document),
        updated_at: value.updated_at,
    }
}

fn plan_document(value: AgentSessionPlanDocument) -> BridgePlanDocument {
    BridgePlanDocument {
        version: value.version,
        markdown: value.markdown,
        content_hash: value.content_hash,
    }
}

fn plan_phase(value: AgentSessionPlanPhase) -> BridgePlanPhase {
    match value {
        AgentSessionPlanPhase::Drafting => BridgePlanPhase::Drafting,
        AgentSessionPlanPhase::AwaitingConfirmation => BridgePlanPhase::AwaitingConfirmation,
        AgentSessionPlanPhase::RevisionRequested => BridgePlanPhase::RevisionRequested,
        AgentSessionPlanPhase::Approved => BridgePlanPhase::Approved,
    }
}

fn workflow_run(value: WorkflowRuntimeRunSnapshot) -> BridgeWorkflowRun {
    BridgeWorkflowRun {
        lineage_id: value.lineage_id,
        run_id: value.run_id,
        mode_id: value.mode_id.to_string(),
        graph_revision: value.graph_revision,
        graph_hash: value.graph_hash,
        lifecycle: match value.lifecycle {
            WorkflowRunLifecycle::Active => BridgeWorkflowRunLifecycle::Active,
            WorkflowRunLifecycle::Terminal => BridgeWorkflowRunLifecycle::Terminal,
        },
        current_state_id: value.current_state_id,
        started_at: value.started_at,
        updated_at: value.updated_at,
        current_state_title: value.current_state_title,
        mode_display_name: value.mode_display_name,
        mode_deleted: value.mode_deleted,
    }
}

fn runtime_usage(value: ThreadRuntimeUsage) -> BridgeThreadRuntimeUsage {
    BridgeThreadRuntimeUsage {
        diagnostics: value.diagnostics.into(),
        has_incomplete_usage: value.has_incomplete_usage,
        model_id: value.model_id,
        context_window: value.context_window,
        max_context_window: value.max_context_window,
        auto_compact_limit: value.auto_compact_limit,
        latest_context_tokens: value.latest_context_tokens,
        prompt_tokens: value.prompt_tokens,
        completion_tokens: value.completion_tokens,
        cached_prompt_tokens: value.cached_prompt_tokens,
        cache_write_tokens: value.cache_write_tokens,
        reasoning_tokens: value.reasoning_tokens,
        inference_count: value.inference_count,
        total_tokens: value.total_tokens,
        cache_usage: cache_usage(value.cache_usage),
        estimated_costs: value
            .estimated_costs
            .into_iter()
            .map(runtime_cost)
            .collect(),
        estimated_cache_savings: value
            .estimated_cache_savings
            .into_iter()
            .map(runtime_cost)
            .collect(),
        has_unpriced_usage: value.has_unpriced_usage,
        prompt_generation: value.prompt_generation,
        prompt_cache_policy: value.prompt_cache_policy,
        prefix_changed_reason: value
            .prefix_changed_reason
            .map(prompt_prefix_changed_reason),
        updated_at: value.updated_at,
    }
}

fn cache_usage(value: pl_protocol::CacheUsageSummary) -> BridgeCacheUsageSummary {
    BridgeCacheUsageSummary {
        sample_count: value.sample_count,
        legacy_sample_count_unknown: value.legacy_sample_count_unknown,
        input_tokens: value.input_tokens,
        cache_read_tokens: value.cache_read_tokens,
        hit_rate: value.hit_rate,
        has_incomplete_usage: value.has_incomplete_usage,
    }
}

fn prompt_prefix_changed_reason(
    value: PromptPrefixChangedReason,
) -> BridgePromptPrefixChangedReason {
    match value {
        PromptPrefixChangedReason::Initial => BridgePromptPrefixChangedReason::Initial,
        PromptPrefixChangedReason::PromptScopeChanged => {
            BridgePromptPrefixChangedReason::PromptScopeChanged
        }
        PromptPrefixChangedReason::AccountChanged => {
            BridgePromptPrefixChangedReason::AccountChanged
        }
        PromptPrefixChangedReason::ModelChanged => BridgePromptPrefixChangedReason::ModelChanged,
        PromptPrefixChangedReason::BaseInstructionsChanged => {
            BridgePromptPrefixChangedReason::BaseInstructionsChanged
        }
        PromptPrefixChangedReason::GlobalInstructionsChanged => {
            BridgePromptPrefixChangedReason::GlobalInstructionsChanged
        }
        PromptPrefixChangedReason::ModeRoleChanged => {
            BridgePromptPrefixChangedReason::ModeRoleChanged
        }
        PromptPrefixChangedReason::SkillCatalogChanged => {
            BridgePromptPrefixChangedReason::SkillCatalogChanged
        }
        PromptPrefixChangedReason::WorkspaceInstructionsChanged => {
            BridgePromptPrefixChangedReason::WorkspaceInstructionsChanged
        }
        PromptPrefixChangedReason::RequestPropertiesChanged => {
            BridgePromptPrefixChangedReason::RequestPropertiesChanged
        }
        PromptPrefixChangedReason::FixedPrefixChanged => {
            BridgePromptPrefixChangedReason::FixedPrefixChanged
        }
        PromptPrefixChangedReason::ToolSchemaChanged => {
            BridgePromptPrefixChangedReason::ToolSchemaChanged
        }
        PromptPrefixChangedReason::ContextCompacted => {
            BridgePromptPrefixChangedReason::ContextCompacted
        }
        PromptPrefixChangedReason::ContextAppended => {
            BridgePromptPrefixChangedReason::ContextAppended
        }
        PromptPrefixChangedReason::ContextRecovered => {
            BridgePromptPrefixChangedReason::ContextRecovered
        }
    }
}

fn runtime_cost(value: RuntimeCostAmount) -> BridgeRuntimeCostAmount {
    BridgeRuntimeCostAmount {
        currency: value.currency,
        amount: value.amount,
    }
}

pub(super) fn token_usage(value: TokenUsageSnapshot) -> BridgeTokenUsageSnapshot {
    BridgeTokenUsageSnapshot {
        prompt_tokens: value.prompt_tokens,
        completion_tokens: value.completion_tokens,
        cached_prompt_tokens: value.cached_prompt_tokens,
        total_tokens: value.total_tokens,
    }
}

fn todo(value: TodoListSnapshot) -> BridgeTodoListSnapshot {
    BridgeTodoListSnapshot {
        call_id: value.call_id,
        agent_id: value.agent_id,
        path: value.path,
        parent_path: value.parent_path,
        explanation: value.explanation,
        items: value.items.into_iter().map(todo_item).collect(),
    }
}

fn todo_item(value: TodoItem) -> BridgeTodoItem {
    BridgeTodoItem {
        step: value.step,
        status: match value.status {
            TodoStatus::Pending => BridgeTodoStatus::Pending,
            TodoStatus::InProgress => BridgeTodoStatus::InProgress,
            TodoStatus::Completed => BridgeTodoStatus::Completed,
        },
    }
}

fn mcp_health(value: McpHealthSnapshot) -> BridgeThreadMcpHealthSnapshot {
    BridgeThreadMcpHealthSnapshot {
        generation: value.generation,
        servers: value.servers.into_iter().map(mcp_availability).collect(),
    }
}

fn mcp_availability(value: McpAvailabilityDescriptor) -> BridgeThreadMcpAvailabilityDescriptor {
    BridgeThreadMcpAvailabilityDescriptor {
        server: mcp_server(value.server),
        availability: value.availability,
        message: value.message,
        last_checked_at: value.last_checked_at,
        tool_count: value.tool_count.and_then(|count| u64::try_from(count).ok()),
    }
}

fn mcp_server(value: McpServerDescriptor) -> BridgeThreadMcpServerDescriptor {
    BridgeThreadMcpServerDescriptor {
        id: value.id,
        source: value.source,
        transport: value.transport,
        endpoint: value.endpoint,
        built_in: value.built_in,
    }
}
