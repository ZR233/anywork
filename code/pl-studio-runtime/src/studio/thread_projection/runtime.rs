//! Usage and product state are decoded by their producers, never inferred from tool text.
use super::ProjectionError;
use crate::{
    CacheUsageSummary, ThreadRuntimeLiveUsage, ThreadRuntimeSnapshot, ThreadRuntimeUsage,
    ThreadRuntimeUsageState,
};
use pl_core::thread::ThreadSnapshot;

pub(in crate::studio) fn project_runtime(
    thread_id: &str,
    state: &ThreadSnapshot,
    updated_at: i64,
    summary: &pl_core::thread::UsageSummary,
) -> Result<ThreadRuntimeSnapshot, ProjectionError> {
    let mode = state
        .extensions
        .get("studio.mode")
        .map(|record| crate::mode::decode_mode_snapshot(&record.payload))
        .transpose()?;
    project_with_mode(thread_id, state, updated_at, summary, mode.as_ref())
}

pub(crate) fn workflow_graph_from_definition(
    definition: &crate::mode::ThreadModeDefinition,
    mode_deleted: bool,
) -> Option<crate::workflow_tool::WorkflowRuntimeGraphSnapshot> {
    let graph = definition.workflow.as_ref()?;
    Some(crate::workflow_tool::WorkflowRuntimeGraphSnapshot {
        mode_id: definition.id.clone(),
        mode_display_name: definition.display_name.clone(),
        mode_deleted,
        initial_state_id: graph.initial_state_id.clone(),
        states: graph
            .states
            .iter()
            .map(|s| crate::workflow_tool::WorkflowRuntimeGraphState {
                id: s.id.clone(),
                title: s.title.clone(),
                kind: s.kind,
                instructions: s.instructions.clone(),
            })
            .collect(),
        edges: graph
            .transitions
            .iter()
            .enumerate()
            .map(|(idx, e)| crate::workflow_tool::WorkflowRuntimeGraphEdge {
                id: format!("{}:{idx}->{}", e.source_state_id, e.target_state_id),
                source_state_id: e.source_state_id.clone(),
                target_state_id: e.target_state_id.clone(),
                guard: e.guard.clone(),
            })
            .collect(),
    })
}

pub(crate) fn workflow_graph_from_saved_mode(
    saved: &crate::mode::SavedThreadMode,
    mode_deleted: bool,
) -> Option<crate::workflow_tool::WorkflowRuntimeGraphSnapshot> {
    workflow_graph_from_definition(&saved.definition, mode_deleted)
}

fn project_with_mode(
    thread_id: &str,
    state: &ThreadSnapshot,
    updated_at: i64,
    summary: &pl_core::thread::UsageSummary,
    mode: Option<&crate::mode::SavedThreadMode>,
) -> Result<ThreadRuntimeSnapshot, ProjectionError> {
    // Totals come from the Thread's cumulative summary, never from whatever attempts are still
    // resident: finished attempts are dropped by the commit that produced them, so aggregating
    // them here is what made a hot increment, a reconnect and a cold restore disagree.
    let usage = ThreadRuntimeUsage {
        diagnostics: super::usage_projection::diagnostics(summary),
        has_incomplete_usage: summary.has_incomplete_usage(),
        model_id: summary
            .binding
            .as_ref()
            .map_or_else(String::new, |binding| binding.model.clone()),
        context_window: summary
            .binding
            .as_ref()
            .and_then(|binding| binding.context_window),
        max_context_window: summary
            .binding
            .as_ref()
            .and_then(|binding| binding.max_context_window),
        auto_compact_limit: summary
            .binding
            .as_ref()
            .and_then(|binding| binding.auto_compact_limit),
        latest_context_tokens: summary.context.tokens,
        prompt_tokens: summary.totals.prompt_tokens,
        completion_tokens: summary.totals.completion_tokens,
        cached_prompt_tokens: summary.totals.cached_prompt_tokens,
        cache_write_tokens: summary.totals.cache_write_tokens,
        reasoning_tokens: summary.totals.reasoning_tokens,
        inference_count: summary.totals.inference_count,
        total_tokens: summary.totals.total_tokens,
        cache_usage: CacheUsageSummary {
            sample_count: summary.cache.sample_count,
            legacy_sample_count_unknown: summary.diagnostics.legacy_unknown,
            input_tokens: summary.cache.input_tokens,
            cache_read_tokens: summary.cache.read_tokens,
            hit_rate: (summary.cache.input_tokens > 0)
                .then(|| summary.cache.read_tokens as f64 / summary.cache.input_tokens as f64),
            has_incomplete_usage: summary.cache.incomplete,
        },
        estimated_costs: protocol_costs(&summary.pricing.estimated_costs),
        estimated_cache_savings: protocol_costs(&summary.pricing.estimated_cache_savings),
        has_unpriced_usage: summary.pricing.incomplete,
        prompt_generation: None,
        prompt_cache_policy: None,
        prefix_changed_reason: None,
        updated_at,
    };
    let live_usage = state.model_progress.as_ref().and_then(|active| {
        let attempt = state.attempts.last()?;
        let observation = active.progress.usage_observation()?;
        if active.attempt_id != attempt.attempt_id
            || observation.attempt_id != active.attempt_id
            || observation.turn_id != attempt.turn_id
        {
            return None;
        }
        Some(ThreadRuntimeLiveUsage {
            turn_id: observation.turn_id.clone(),
            attempt_id: observation.attempt_id.clone(),
            completion_tokens: observation.completion_tokens,
            response_millis: observation.response_millis,
            latest_context_tokens: observation.latest_context_tokens,
            state: match observation.state {
                pl_core::model::ModelUsageObservationState::Live => ThreadRuntimeUsageState::Live,
                pl_core::model::ModelUsageObservationState::Authoritative => {
                    ThreadRuntimeUsageState::Authoritative
                }
            },
            observation_sequence: observation.observation_sequence,
        })
    });
    let todo = state
        .extensions
        .get("pl.tool.todo")
        .map(|record| {
            let call_id = state
                .deliveries
                .iter()
                .rev()
                .find(|delivery| delivery.output.payload() == &record.payload)
                .map_or_else(String::new, |delivery| delivery.call_id.clone());
            pl_tool::todo::saved_snapshot(&record.payload, call_id)
        })
        .transpose()?;
    let workflow = state
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION)
        .map(|record| {
            crate::workflow_tool::decode_workflow_state(&record.payload).map(|state| match mode {
                Some(mode) => mode.project_workflow_state(&state, false),
                None => {
                    crate::workflow_tool::WorkflowRuntimeSnapshot::from_state(&state, "", "", false)
                }
            })
        })
        .transpose()?;
    let plan = state
        .extensions
        .get(crate::plan_tool::PLAN_EXTENSION)
        .map(|record| {
            crate::plan_tool::decode_plan_state(&record.payload)
                .map(|state| crate::plan_tool::AgentSessionPlanRuntimeSnapshot::from(&state))
                .map_err(
                    |source| crate::studio::session_data_error::SessionDataError::Plan {
                        revision: record.payload.version(),
                        source: source.into(),
                    },
                )
        })
        .transpose()?;
    let active_skills = state
        .extensions
        .values()
        .filter(|record| record.payload.format() == "pl.tool.skill-view")
        .map(|record| pl_tool::skill::saved_skill_name(&record.payload))
        .collect::<Result<std::collections::BTreeSet<_>, _>>()?
        .into_iter()
        .collect();
    Ok(ThreadRuntimeSnapshot {
        thread_id: thread_id.into(),
        deferred: Vec::new(),
        // The execution identity is a fact of this Thread's own state, so the same per-Thread
        // projection that publishes usage also publishes what a precise stop would target.
        execution: super::agent_directory::project_execution(state),
        // The owed work is part of this Thread's own state: the client's first continue needs this
        // identity, and only the owner can publish it. It is never derived from history or guessed
        // locally. Acceptance consumes the token and retains the original operation receipt.
        continuation: state.continuation.as_ref().map(|point| {
            crate::ContinuationView::new(
                point.id.clone(),
                point.source_turn_id.clone(),
                point.reason.map(|reason| match reason {
                    pl_core::thread::ContinuationReason::UserStop => {
                        crate::ContinuationReason::UserStop
                    }
                    pl_core::thread::ContinuationReason::HostShutdown => {
                        crate::ContinuationReason::HostShutdown
                    }
                    pl_core::thread::ContinuationReason::ProcessInterrupted => {
                        crate::ContinuationReason::ProcessInterrupted
                    }
                    pl_core::thread::ContinuationReason::StepLimit => {
                        crate::ContinuationReason::StepLimit
                    }
                    pl_core::thread::ContinuationReason::ExecutionFailed => {
                        crate::ContinuationReason::ExecutionFailed
                    }
                }),
                point.created_at,
            )
        }),
        usage,
        live_usage,
        turn_completion_tokens: summary.throughput.completion_tokens,
        turn_response_millis: summary.throughput.response_millis,
        todo,
        workflow,
        plan,
        active_skills,
        active_mcp_servers: Vec::new(),
        active_lsp_servers: Vec::new(),
        progress: None,
        mcp_health: None,
        updated_at,
    })
}

fn protocol_costs(costs: &[pl_core::thread::UsageCost]) -> Vec<crate::RuntimeCostAmount> {
    costs
        .iter()
        .map(|cost| crate::RuntimeCostAmount {
            currency: cost.currency.clone(),
            amount: cost.amount,
        })
        .collect()
}
