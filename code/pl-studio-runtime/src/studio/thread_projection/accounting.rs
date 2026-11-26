//! One immutable extraction shared by live accounting, reliable accounting and cost publication.

use std::sync::Arc;

use pl_core::model::ModelUsageBinding;
use pl_core::thread::{ThreadEffectBatch, UsageSummary};
use pl_core::usage::{UsageOutcome, UsageSource, UsageThroughputSample};

use super::super::storage::calls::CallStatus;
use super::ProjectionError;
use super::billing::BillingFact;

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::{context::OpaquePayload, model::ModelSubAttemptSettlement};

    #[test]
    fn a_complete_set_of_counters_from_a_nonterminal_sample_stays_incomplete() -> anyhow::Result<()>
    {
        let settlements = [(0, "failed", false, 13), (1, "succeeded", true, 7)].into_iter().map(|(generation, outcome, terminal, input)| {
            let payload = serde_json::json!({
                "turnId": "turn", "attemptId": "a", "logicalRequestId": "a", "generation": generation,
                "retry": generation,
                "billing": {
                    "inferenceId": format!("sub-attempt:1:a:{generation}"),
                    "accountId": "account", "purpose": "turn", "recordedAt": 1,
                    "attempt": {"logicalRequestId": "a", "coreAttemptId": "a", "generation": generation,
                        "stage": "stream", "outcome": outcome, "usageIsTerminal": terminal},
                    "accounting": {"usage": {"inputTokens": input, "outputTokens": 3, "cacheReadTokens": 0,
                        "totalTokens": input + 3}, "pricing": {"kind": "disabled"}},
                }
            });
            Ok(ModelSubAttemptSettlement {
                turn_id: Some("turn".into()), attempt_id: "a".into(), generation,
                payload: OpaquePayload::new("pl.model.sub-attempt-settlement", 2, payload.to_string())?,
            })
        }).collect::<anyhow::Result<Vec<_>>>()?;
        let mut summary = UsageSummary::default();
        for (index, settlement) in settlements.into_iter().enumerate() {
            PreparedAccounting::prepare(&ThreadEffectBatch {
                thread_id: "thread".into(),
                sequence: index as u64 + 1,
                model_sub_attempt_settlements: Arc::from([settlement]),
                ..Default::default()
            })?
            .fold_into(&mut summary);
        }
        assert_eq!(summary.totals.inference_count, 2);
        assert_eq!(summary.totals.total_tokens, 26);
        assert_eq!(summary.diagnostics.incomplete_calls, 1);
        assert!(summary.has_incomplete_usage());
        Ok(())
    }
}

/// Validated, body-free accounting belonging to exactly one effect.
#[derive(Debug, Clone)]
pub(crate) struct PreparedAccounting {
    pub(crate) thread_id: String,
    pub(crate) sequence: u64,
    committed_at: i64,
    binding: Option<Option<ModelUsageBinding>>,
    primary_turn_id: Option<String>,
    committed_context: Option<crate::InferenceBillingRecord>,
    pub(crate) facts: Arc<[BillingFact]>,
    retained_bytes: u64,
}

impl PreparedAccounting {
    pub(crate) fn shared(effect: &ThreadEffectBatch) -> Result<Arc<Self>, ProjectionError> {
        effect
            .prepared_accounting
            .get_or_prepare(|| Self::prepare(effect))
    }

    pub(crate) fn prepare(effect: &ThreadEffectBatch) -> Result<Self, ProjectionError> {
        let facts = super::billing::billing_facts(effect)
            .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?;
        let mut identities = std::collections::BTreeSet::new();
        let mut retained_bytes = (std::mem::size_of::<Self>() + effect.thread_id.len()) as u64;
        let committed_context = effect
            .attempt
            .as_ref()
            .map(pl_model::runtime::model_committed_sub_attempt_billing)
            .transpose()
            .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?
            .flatten();
        if let Some(context) = &committed_context {
            retained_bytes =
                retained_bytes.saturating_add(serde_json::to_vec(context)?.len() as u64);
        }
        if let Some(attempt) = &effect.attempt {
            retained_bytes = retained_bytes.saturating_add(attempt.turn_id.len() as u64);
            if let Some(binding) = &attempt.usage_binding {
                retained_bytes = retained_bytes.saturating_add(
                    (std::mem::size_of::<ModelUsageBinding>()
                        + binding.model.len()
                        + binding.route_identity.as_ref().map_or(0, String::len))
                        as u64,
                );
            }
        }
        for fact in &facts {
            if fact
                .record
                .accounting
                .estimated_costs()
                .iter()
                .chain(fact.record.accounting.estimated_cache_savings().iter())
                .any(|cost| {
                    cost.currency.is_empty() || !cost.amount.is_finite() || cost.amount < 0.0
                })
                || fact.status == CallStatus::Running
            {
                return Err(ProjectionError::UnsupportedOutput(
                    "invalid terminal accounting".into(),
                ));
            }
            // Only the lightweight record is sized, once at preparation. Include nested frozen
            // pricing strings instead of a fixed allowance that could hide a large retained body.
            retained_bytes = retained_bytes
                .saturating_add((serde_json::to_vec(&fact.record)?.len() as u64).saturating_mul(2))
                .saturating_add(fact.settlement.content().len() as u64)
                .saturating_add(std::mem::size_of::<BillingFact>() as u64);
            if !identities.insert(fact.record.inference_id.as_str()) {
                return Err(ProjectionError::DuplicateCall(
                    fact.record.inference_id.clone(),
                ));
            }
        }
        Ok(Self {
            thread_id: effect.thread_id.clone(),
            sequence: effect.sequence,
            committed_at: effect.committed_at,
            binding: effect
                .attempt
                .as_ref()
                .map(|attempt| attempt.usage_binding.clone()),
            primary_turn_id: effect
                .attempt
                .as_ref()
                .map(|attempt| attempt.turn_id.clone()),
            facts: facts.into(),
            committed_context,
            retained_bytes,
        })
    }

    /// Each consumer owns its own watermark; sharing the input never promotes live to durable.
    pub(in crate::studio) fn fold_into(&self, summary: &mut UsageSummary) {
        if self.sequence <= summary.applied_sequence {
            return;
        }
        if let Some(binding) = &self.binding {
            summary.binding.clone_from(binding);
        }
        for fact in self.facts.iter() {
            let source = UsageSource {
                thread_id: self.thread_id.clone(),
                call_id: fact.record.inference_id.clone(),
                turn_id: fact.turn_id.clone(),
                effect_sequence: self.sequence,
                observed_at: self.committed_at,
                purpose: fact.record.purpose.clone(),
                outcome: match fact.status {
                    CallStatus::Committed => UsageOutcome::Succeeded,
                    CallStatus::Rejected => UsageOutcome::Rejected,
                    CallStatus::Cancelled => UsageOutcome::Cancelled,
                    CallStatus::Interrupted => UsageOutcome::Interrupted,
                    CallStatus::Failed => UsageOutcome::Failed,
                    CallStatus::Running => unreachable!("prepared billing is terminal"),
                },
            };
            summary.add_usage_sample(
                &pl_model::model::usage::model_usage(&fact.record.accounting.usage),
                source,
                false,
                None,
                fact.record
                    .attempt
                    .as_ref()
                    .map(|attempt| attempt.usage_is_terminal),
            );
            summary.pricing.incomplete |= fact.record.accounting.has_unpriced_usage();
            let costs_valid = merge_costs(
                &mut summary.pricing.estimated_costs,
                &fact.record.accounting.estimated_costs(),
            );
            let savings_valid = merge_costs(
                &mut summary.pricing.estimated_cache_savings,
                &fact.record.accounting.estimated_cache_savings(),
            );
            summary.pricing.incomplete |= !costs_valid || !savings_valid;
        }
        if let Some(record) = &self.committed_context {
            summary.observe_committed_usage(
                &pl_model::model::usage::model_usage(&record.accounting.usage),
                UsageSource {
                    thread_id: self.thread_id.clone(),
                    call_id: record.inference_id.clone(),
                    turn_id: self.primary_turn_id.clone(),
                    effect_sequence: self.sequence,
                    observed_at: self.committed_at,
                    purpose: record.purpose.clone(),
                    outcome: UsageOutcome::Succeeded,
                },
                throughput(record),
            );
        }
        summary.applied_sequence = self.sequence;
    }

    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        self.retained_bytes
    }

    pub(in crate::studio) fn export_fingerprint(&self) -> String {
        crate::hash::canonical_json_hash(&serde_json::json!({
            "threadId": self.thread_id,
            "sequence": self.sequence,
            "committedAt": self.committed_at,
            "binding": self.binding,
            "primaryTurnId": self.primary_turn_id,
            "committedContext": self.committed_context,
            "facts": self.facts.iter().map(|fact| serde_json::json!({
                "status": fact.status.as_str(), "auxiliary": fact.auxiliary, "record": fact.record,
                "turnId": fact.turn_id,
                "settlement": fact.settlement,
            })).collect::<Vec<_>>(),
        }))
    }

    #[cfg(test)]
    pub(in crate::studio) fn binding(&self) -> Option<&Option<ModelUsageBinding>> {
        self.binding.as_ref()
    }
}

fn throughput(record: &crate::InferenceBillingRecord) -> Option<UsageThroughputSample> {
    let timing = record.timing?;
    let output_tokens =
        pl_model::model::usage::throughput_output_tokens(timing, &record.accounting.usage)?;
    Some(UsageThroughputSample {
        output_tokens,
        response_millis: timing.response_millis,
    })
}

trait MergeableCost: Sized {
    fn currency(&self) -> &str;
    fn amount(&mut self) -> &mut f64;
    fn from_runtime(cost: &crate::RuntimeCostAmount) -> Self;
}

impl MergeableCost for crate::RuntimeCostAmount {
    fn currency(&self) -> &str {
        &self.currency
    }
    fn amount(&mut self) -> &mut f64 {
        &mut self.amount
    }
    fn from_runtime(cost: &crate::RuntimeCostAmount) -> Self {
        cost.clone()
    }
}

impl MergeableCost for pl_core::thread::UsageCost {
    fn currency(&self) -> &str {
        &self.currency
    }
    fn amount(&mut self) -> &mut f64 {
        &mut self.amount
    }
    fn from_runtime(cost: &crate::RuntimeCostAmount) -> Self {
        Self {
            currency: cost.currency.clone(),
            amount: cost.amount,
        }
    }
}

pub(in crate::studio) fn merge_runtime_costs(
    target: &mut Vec<crate::RuntimeCostAmount>,
    incoming: &[crate::RuntimeCostAmount],
) {
    let _ = merge_costs(target, incoming);
}

/// Fold same-currency runtime costs. Non-finite sums are left unchanged and reported.
fn merge_costs<T: MergeableCost>(
    target: &mut Vec<T>,
    incoming: &[crate::RuntimeCostAmount],
) -> bool {
    let mut complete = true;
    for cost in incoming {
        if let Some(existing) = target
            .iter_mut()
            .find(|existing| existing.currency() == cost.currency)
        {
            let next = *existing.amount() + cost.amount;
            if next.is_finite() {
                *existing.amount() = next;
            } else {
                complete = false;
            }
        } else {
            target.push(T::from_runtime(cost));
        }
    }
    target.sort_by(|left, right| left.currency().cmp(right.currency()));
    complete
}
