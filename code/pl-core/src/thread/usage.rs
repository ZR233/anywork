//! Portable cumulative accounting for the plain SQLite Thread store.

use super::{AttemptOutcome, ThreadEffectBatch, UsageSummary};
use crate::model::ModelUsage;
use crate::usage::{UsageOutcome, UsageSource};

pub(crate) fn fold_effect(summary: &mut UsageSummary, effect: &ThreadEffectBatch) {
    if effect.sequence <= summary.applied_sequence {
        return;
    }
    if let Some(attempt) = &effect.attempt {
        // Admission replaces the entire binding, including unknown values.
        summary.binding = attempt.usage_binding.clone();
        let missing = ModelUsage::default();
        let terminal: Option<(&ModelUsage, UsageOutcome)> = match &attempt.outcome {
            AttemptOutcome::Running => None,
            AttemptOutcome::Interrupted => Some((&missing, UsageOutcome::Interrupted)),
            AttemptOutcome::Committed(output) => Some((&output.usage, UsageOutcome::Succeeded)),
            AttemptOutcome::Rejected { output, .. } => {
                Some((&output.usage, UsageOutcome::Rejected))
            }
            AttemptOutcome::Failed(error) => Some((&error.usage, UsageOutcome::Failed)),
            AttemptOutcome::Cancelled { result } => Some((
                match result {
                    Ok(output) => &output.usage,
                    Err(error) => &error.usage,
                },
                UsageOutcome::Cancelled,
            )),
        };
        if let Some((usage, outcome)) = terminal {
            summary.add_usage(
                usage,
                UsageSource {
                    thread_id: effect.thread_id.clone(),
                    call_id: attempt.attempt_id.clone(),
                    turn_id: Some(attempt.turn_id.clone()),
                    effect_sequence: effect.sequence,
                    observed_at: effect.committed_at,
                    purpose: None,
                    outcome,
                },
                true,
                None, // Plain storage has no timing: retain the last valid paired sample.
            );
            summary.pricing.incomplete = true;
        }
    }
    summary.applied_sequence = effect.sequence;
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{ModelError, ModelFailureKind, ModelStepOutput, ModelUsageBinding};
    use crate::thread::{ModelOutputViolation, journal::AttemptUpdate};
    use crate::usage::UsageThroughputSummary;
    use std::sync::Arc;

    #[test]
    fn terminal_mapping_retains_identity_while_running_only_replaces_binding() {
        let usage = ModelUsage {
            input_tokens: Some(4),
            output_tokens: Some(2),
            cache_read_tokens: Some(0),
            ..Default::default()
        };
        let output = ModelStepOutput {
            attempt_id: "attempt".into(),
            base_context_revision: 0,
            content: Vec::new(),
            tool_calls: Vec::new(),
            private_context: None,
            usage: usage.clone(),
        };
        let error = Arc::new(ModelError {
            details: None,
            kind: ModelFailureKind::Unavailable,
            usage: Box::new(usage),
            source: None,
        });
        for (outcome, expected) in [
            (
                AttemptOutcome::Committed(output.clone()),
                UsageOutcome::Succeeded,
            ),
            (
                AttemptOutcome::Rejected {
                    output: output.clone(),
                    reason: ModelOutputViolation::EmptyCallIdentity,
                },
                UsageOutcome::Rejected,
            ),
            (AttemptOutcome::Failed(error.clone()), UsageOutcome::Failed),
            (
                AttemptOutcome::Cancelled {
                    result: Ok(output.clone()),
                },
                UsageOutcome::Cancelled,
            ),
            (
                AttemptOutcome::Cancelled {
                    result: Err(error.clone()),
                },
                UsageOutcome::Cancelled,
            ),
            (AttemptOutcome::Interrupted, UsageOutcome::Interrupted),
        ] {
            let mut summary = UsageSummary::default();
            let binding = ModelUsageBinding {
                route_identity: Some("route".into()),
                model: "model".into(),
                context_window: Some(100),
                max_context_window: Some(200),
                auto_compact_limit: Some(80),
            };
            summary.throughput = UsageThroughputSummary {
                turn_id: "previous".into(),
                completion_tokens: 20,
                response_millis: 30,
            };
            let previous_throughput = summary.throughput.clone();
            let mut effect = ThreadEffectBatch {
                thread_id: "thread".into(),
                sequence: 1,
                committed_at: 123,
                attempt: Some(AttemptUpdate {
                    request_metadata: None,
                    usage_binding: Some(binding.clone()),
                    tool_projection: None,
                    turn_id: "turn".into(),
                    attempt_id: "attempt".into(),
                    retry_of: None,
                    input_revision: 0,
                    tools: Default::default(),
                    outcome: AttemptOutcome::Running,
                    input_estimate: None,
                }),
                ..Default::default()
            };
            fold_effect(&mut summary, &effect);
            assert_eq!(summary.binding, Some(binding));
            assert_eq!(summary.totals.inference_count, 0);
            assert!(summary.context.latest_call.is_none());
            assert!(!summary.pricing.incomplete);
            assert_eq!(summary.throughput, previous_throughput);
            // An unbound terminal attempt clears the whole earlier binding group.
            let attempt = effect.attempt.as_mut().unwrap();
            attempt.usage_binding = None;
            attempt.outcome = outcome;
            effect.sequence = 2;
            fold_effect(&mut summary, &effect);
            assert_eq!(summary.binding, None);
            assert_eq!(summary.totals.inference_count, 1);
            assert!(summary.pricing.incomplete);
            assert_eq!(summary.throughput, previous_throughput);
            let observation = summary.context.latest_call.as_ref().unwrap();
            assert_eq!(
                observation.source,
                UsageSource {
                    thread_id: "thread".into(),
                    call_id: "attempt".into(),
                    turn_id: Some("turn".into()),
                    effect_sequence: 2,
                    observed_at: 123,
                    purpose: None,
                    outcome: expected,
                }
            );
            assert_eq!(
                summary.totals.total_tokens,
                if expected == UsageOutcome::Interrupted {
                    0
                } else {
                    6
                }
            );
            assert_eq!(
                summary.diagnostics.missing_calls,
                u64::from(expected == UsageOutcome::Interrupted)
            );
            let saved = summary.clone();
            fold_effect(&mut summary, &effect);
            assert_eq!(summary, saved);
        }
    }
}
