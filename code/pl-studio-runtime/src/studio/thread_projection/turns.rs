//! Turn lifecycle and diagnostics projected from saved commit metadata.
use super::ProjectionError;
use crate::{Turn, TurnPhase, TurnState};
use pl_core::thread::{
    AttemptStatus, ThreadSnapshot, TurnOutcome as CoreTurnOutcome, TurnRecord,
    TurnState as CoreTurnState,
};

struct Stamp {
    started_at: i64,
    updated_at: i64,
    revision: u64,
}

pub(super) fn project_turn(
    thread_id: &str,
    snapshot: &ThreadSnapshot,
    record: &TurnRecord,
    created_at: i64,
    updated_at: i64,
    revision: u64,
) -> Result<Turn, ProjectionError> {
    let stamp = Stamp {
        started_at: created_at,
        updated_at,
        revision,
    };
    Ok(Turn {
        input_id: record.input_id.clone(),
        id: record.turn_id.clone(),
        thread_id: thread_id.into(),
        revision,
        state: state(snapshot, record, &stamp)?,
        updated_at,
    })
}

pub(in crate::studio) fn project_active_turn(
    thread_id: &str,
    snapshot: &ThreadSnapshot,
    updated_at: i64,
) -> Result<Option<Turn>, ProjectionError> {
    let Some(record) = snapshot
        .turns
        .iter()
        .rev()
        .find(|record| record.state == CoreTurnState::Running)
    else {
        return Ok(None);
    };
    let stamp = Stamp {
        started_at: updated_at,
        updated_at,
        revision: snapshot.commit_sequence,
    };
    Ok(Some(Turn {
        input_id: record.input_id.clone(),
        id: record.turn_id.clone(),
        thread_id: thread_id.into(),
        revision: stamp.revision,
        state: state(snapshot, record, &stamp)?,
        updated_at: stamp.updated_at,
    }))
}

fn state(
    snapshot: &ThreadSnapshot,
    record: &TurnRecord,
    stamp: &Stamp,
) -> Result<TurnState, ProjectionError> {
    let started = Some(stamp.started_at);
    let at = stamp.updated_at;
    Ok(match &record.state {
        CoreTurnState::Running => TurnState::Running(crate::RunningTurnState::new(
            stamp.started_at,
            phase(snapshot, &record.turn_id),
        )),
        CoreTurnState::Finished(CoreTurnOutcome::Completed) => TurnState::Completed(
            crate::CompletedTurnState::new(started, at, crate::TurnCompletion::Normal),
        ),
        CoreTurnState::Finished(CoreTurnOutcome::WaitingInteraction) => {
            TurnState::Completed(crate::CompletedTurnState::new(
                started,
                at,
                crate::TurnCompletion::InteractionRequested,
            ))
        }
        CoreTurnState::Finished(CoreTurnOutcome::StepLimit) => {
            let tasks = snapshot
                .tasks
                .values()
                .filter(|task| task.turn_id == record.turn_id)
                .collect::<Vec<_>>();
            let usage = crate::BudgetUsage {
                model_steps: record.model_steps,
                tool_calls: tasks.len().try_into().map_err(|_| ProjectionError::Count)?,
                wait_calls: tasks
                    .iter()
                    .filter(|task| task.tool_id == "wait")
                    .count()
                    .try_into()
                    .map_err(|_| ProjectionError::Count)?,
                elapsed_ms: record
                    .elapsed_ms
                    .ok_or_else(|| ProjectionError::MissingDuration(record.turn_id.clone()))?,
            };
            TurnState::BudgetLimited(crate::BudgetLimitedTurnState::new(
                started,
                at,
                crate::BudgetLimitSnapshot {
                    kind: crate::BudgetLimitKind::ModelStep,
                    usage,
                },
                crate::TurnRolloverOutcome::NotAttempted,
            ))
        }
        CoreTurnState::Cancelled => TurnState::Cancelled(crate::CancelledTurnState::new(
            started,
            at,
            at,
            crate::TurnCancellationCause::Unspecified,
        )),
        CoreTurnState::Interrupted => TurnState::Cancelled(crate::CancelledTurnState::new(
            started,
            at,
            at,
            if record.elapsed_ms.is_some() {
                crate::TurnCancellationCause::Interrupted
            } else {
                crate::TurnCancellationCause::Recovery
            },
        )),
        CoreTurnState::Failed {
            description,
            model_failure: facts,
        } => {
            let failure = match facts {
                Some(facts) => model_failure_facts(facts),
                None => failure(snapshot, &record.turn_id, description),
            };
            TurnState::Failed(crate::FailedTurnState::new(started, at, failure))
        }
    })
}

fn model_failure_facts(facts: &pl_core::model::ModelFailureFacts) -> crate::TurnFailure {
    let mut failure = model_failure(&pl_core::model::ModelError {
        context_recovery: None,
        kind: facts.kind,
        details: facts.details.clone(),
        usage: facts.usage.clone(),
        source: None,
    });
    if let Some(repair) = &facts.repair {
        let recovery = failure.recovery.get_or_insert(crate::ModelRecoveryInfo {
            retry_count: None,
            max_retries: None,
            effective_wait_millis: None,
            reason: None,
            stop_reason: None,
            error: None,
        });
        recovery.stop_reason = Some(crate::ModelRecoveryStopReason::RepairFailed);
        recovery.error = Some(repair.to_string());
    }
    failure
}

/// Canonical phase of a running Turn, derived from the live facts of the snapshot.
///
/// The phase is a projection of the running tasks and the newest attempt outcome, so it changes
/// whenever a tool task starts or finishes and whenever an attempt commits — neither of which
/// rewrites the Turn record. Live projection therefore re-derives it after every effect instead of
/// relying on a Turn record update.
pub(super) fn phase(snapshot: &ThreadSnapshot, turn_id: &str) -> TurnPhase {
    if snapshot.tasks.values().any(|task| {
        task.turn_id == turn_id && task.status == pl_core::thread::task::TaskStatus::Running
    }) {
        return TurnPhase::RunningTool;
    }
    match snapshot
        .attempts
        .iter()
        .rev()
        .find(|attempt| attempt.turn_id == turn_id)
        .map(|attempt| &attempt.status)
    {
        None => TurnPhase::Preparing,
        Some(AttemptStatus::Committed)
            if snapshot
                .context
                .records
                .iter()
                .rev()
                .find(|record| {
                    record.turn_id.as_deref() == Some(turn_id)
                        && matches!(record.source, pl_core::context::ContextSource::Assistant)
                })
                .is_some_and(|record| !record.tool_calls.is_empty()) =>
        {
            TurnPhase::Planning
        }
        Some(AttemptStatus::Committed) => TurnPhase::Responding,
        Some(
            AttemptStatus::Running
            | AttemptStatus::Interrupted
            | AttemptStatus::Cancelled
            | AttemptStatus::Failed
            | AttemptStatus::Rejected { .. },
        ) => TurnPhase::Thinking,
    }
}

fn failure(snapshot: &ThreadSnapshot, turn_id: &str, description: &str) -> crate::TurnFailure {
    let category = if snapshot
        .attempts
        .iter()
        .any(|attempt| attempt.turn_id == turn_id && attempt.status == AttemptStatus::Failed)
    {
        crate::TurnFailureCategory::Provider
    } else {
        crate::TurnFailureCategory::Internal
    };
    crate::TurnFailure::permanent(category, description)
}

pub(super) fn model_failure(error: &pl_core::model::ModelError) -> crate::TurnFailure {
    let description = error.to_string();
    match pl_model::runtime::model_failure_receipt(error) {
        Ok(Some(receipt)) => {
            let mut projected = receipt.provider_failure.as_ref().map_or_else(
                || {
                    crate::TurnFailure::permanent(
                        crate::TurnFailureCategory::Provider,
                        if receipt.message.is_empty() {
                            description.clone()
                        } else {
                            receipt.message
                        },
                    )
                },
                provider_failure,
            );
            let last_decision = receipt
                .partial_progress
                .as_ref()
                .and_then(|progress| progress.observation().failed.last()?.recovery.as_ref())
                .and_then(|payload| pl_model::runtime::model_recovery_decision(payload).ok());
            if receipt.retry_count.is_some()
                || receipt.recovery_stop.is_some()
                || receipt.recovery_error.is_some()
            {
                projected.recovery = Some(crate::ModelRecoveryInfo {
                    retry_count: receipt.retry_count,
                    max_retries: receipt.max_retries,
                    effective_wait_millis: last_decision
                        .as_ref()
                        .map(|decision| decision.effective_wait_millis),
                    reason: last_decision.as_ref().map(|decision| decision.recovery),
                    stop_reason: receipt.recovery_stop,
                    error: receipt.recovery_error,
                });
            }
            projected
        }
        Ok(None) => {
            crate::TurnFailure::permanent(crate::TurnFailureCategory::Provider, &description)
        }
        Err(error) => crate::TurnFailure::permanent(
            crate::TurnFailureCategory::Protocol,
            format!("{description}; saved model failure cannot be decoded: {error}"),
        ),
    }
}

pub(super) fn provider_failure(failure: &pl_protocol::ProviderFailure) -> crate::TurnFailure {
    let category = if matches!(
        failure.kind,
        crate::ProviderFailureKind::ContextLimit | crate::ProviderFailureKind::OutputLimit
    ) {
        crate::TurnFailureCategory::ProviderCapacity
    } else {
        crate::TurnFailureCategory::Provider
    };
    crate::TurnFailure {
        category,
        provider_kind: Some(failure.kind),
        code: failure.code.clone(),
        http_status: failure.http_status,
        error_type: failure.error_type.clone(),
        request_id: failure.context.request_id.clone(),
        stage: Some(failure.context.stage),
        recovery: None,
        message: failure.message.clone(),
        retry: failure.retry.clone(),
    }
}
