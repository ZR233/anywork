//! Usage and product state are decoded by their producers, never inferred from tool text.
use super::ProjectionError;
use pl_core::thread::ThreadSnapshot;
use pl_protocol::{
    CacheUsageSummary, ThreadRuntimeLiveUsage, ThreadRuntimeSnapshot, ThreadRuntimeUsage,
    ThreadRuntimeUsageState,
};

pub(in crate::studio) fn project_runtime(
    thread_id: &str,
    state: &ThreadSnapshot,
    updated_at: i64,
    summary: &pl_core::thread::UsageSummary,
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
    let mut workflow = state
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION)
        .map(|record| {
            crate::workflow_tool::decode_workflow_state(&record.payload)
                .map(|state| pl_protocol::WorkflowRuntimeSnapshot::from(&state))
        })
        .transpose()?;
    if let Some(run) = workflow
        .as_mut()
        .and_then(|workflow| workflow.current_run.as_mut())
        && let Some(record) = state.extensions.get("studio.mode")
    {
        // Recovery/preparation owns compilation. Token projections only read saved metadata.
        let mode =
            crate::mode::decode_mode_snapshot(&record.payload).map_err(ProjectionError::from)?;
        run.mode_display_name
            .clone_from(&mode.definition.display_name);
        if let Some(current) = mode.definition.workflow.as_ref().and_then(|graph| {
            graph
                .states
                .iter()
                .find(|state| state.id == run.current_state_id)
        }) {
            run.current_state_title.clone_from(&current.title);
        }
    }
    let plan = state
        .extensions
        .get(crate::plan_tool::PLAN_EXTENSION)
        .map(|record| {
            crate::plan_tool::decode_plan_state(&record.payload)
                .map(|state| pl_protocol::AgentSessionPlanRuntimeSnapshot::from(&state))
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
    let child = state
        .extensions
        .contains_key(crate::studio::model_route::AGENT_PROFILE_EXTENSION);
    let bot_id = crate::studio::model_route::bot_owner(state)
        .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?;
    let model_route = crate::studio::model_route::route_record(state, child)
        .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?
        .map(|(record, route)| pl_protocol::ThreadModelRouteSnapshot {
            bot_id,
            account_id: route.account_id.into_string(),
            model_id: route.model_id,
            effort: route.effort.map(|effort| effort.as_str().to_owned()),
            revision: record.revision,
            available: state.model_available,
            unavailable_reason: (!state.model_available)
                .then(|| "the selected model binding is unavailable".to_string()),
        });
    Ok(ThreadRuntimeSnapshot {
        thread_id: thread_id.into(),
        model_route,
        // The execution identity is a fact of this Thread's own state, so the same per-Thread
        // projection that publishes usage also publishes what a precise stop would target.
        execution: state.execution.as_ref().map(|execution| {
            pl_protocol::AgentExecution::new(
                execution.id.clone(),
                match execution.phase {
                    pl_core::thread::ExecutionPhase::Preparing => {
                        pl_protocol::AgentExecutionPhase::Preparing
                    }
                    pl_core::thread::ExecutionPhase::AwaitingStorage => {
                        pl_protocol::AgentExecutionPhase::AwaitingStorage
                    }
                    pl_core::thread::ExecutionPhase::AwaitingAdmission => {
                        pl_protocol::AgentExecutionPhase::AwaitingAdmission
                    }
                    pl_core::thread::ExecutionPhase::Running => {
                        pl_protocol::AgentExecutionPhase::Running
                    }
                    pl_core::thread::ExecutionPhase::Stopping => {
                        pl_protocol::AgentExecutionPhase::Stopping
                    }
                },
                execution.turn_id.clone(),
            )
        }),
        // The owed work is part of this Thread's own state: the client's first continue needs this
        // identity, and only the owner can publish it. It is never derived from history or guessed
        // locally, and `claimed` separates "can continue" from "continue already accepted".
        continuation: state.continuation.as_ref().map(|point| {
            pl_protocol::ContinuationView::new(
                point.id.clone(),
                point.source_turn_id.clone(),
                point.reason.map(|reason| match reason {
                    pl_core::thread::ContinuationReason::UserStop => {
                        pl_protocol::ContinuationReason::UserStop
                    }
                    pl_core::thread::ContinuationReason::HostShutdown => {
                        pl_protocol::ContinuationReason::HostShutdown
                    }
                    pl_core::thread::ContinuationReason::ProcessInterrupted => {
                        pl_protocol::ContinuationReason::ProcessInterrupted
                    }
                    pl_core::thread::ContinuationReason::StepLimit => {
                        pl_protocol::ContinuationReason::StepLimit
                    }
                    pl_core::thread::ContinuationReason::ExecutionFailed => {
                        pl_protocol::ContinuationReason::ExecutionFailed
                    }
                }),
                point.created_at,
                point.claim.is_some(),
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

fn protocol_costs(costs: &[pl_core::thread::UsageCost]) -> Vec<pl_protocol::RuntimeCostAmount> {
    costs
        .iter()
        .map(|cost| pl_protocol::RuntimeCostAmount {
            currency: cost.currency.clone(),
            amount: cost.amount,
        })
        .collect()
}

/// Cold/recovery extraction boundary. The normal live/durable handoff shares PreparedAccounting.
pub(in crate::studio) fn fold_effect_accounting(
    summary: &mut pl_core::thread::UsageSummary,
    effect: &pl_core::thread::ThreadEffectBatch,
) -> Result<(), ProjectionError> {
    if effect.sequence > summary.applied_sequence {
        super::PreparedAccounting::prepare(effect)?.fold_into(summary);
    }
    Ok(())
}
