//! One immutable extraction shared by live accounting, reliable accounting and cost publication.

use std::sync::Arc;

use pl_core::model::ModelUsageBinding;
use pl_core::thread::{ThreadEffectBatch, UsageSummary};
use pl_core::usage::{UsageOutcome, UsageSource, UsageThroughputSample};

use super::super::storage::calls::CallStatus;
use super::ProjectionError;
use super::billing::BillingFact;

/// Validated, body-free accounting belonging to exactly one effect.
#[derive(Debug, Clone)]
pub(crate) struct PreparedAccounting {
    pub(in crate::studio) thread_id: String,
    pub(in crate::studio) sequence: u64,
    committed_at: i64,
    binding: Option<Option<ModelUsageBinding>>,
    primary_turn_id: Option<String>,
    pub(in crate::studio) facts: Arc<[BillingFact]>,
    retained_bytes: u64,
}

impl PreparedAccounting {
    pub(in crate::studio) fn prepare(effect: &ThreadEffectBatch) -> Result<Self, ProjectionError> {
        let facts = super::billing::billing_facts(effect)
            .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?;
        let mut identities = std::collections::BTreeSet::new();
        let mut retained_bytes = (std::mem::size_of::<Self>() + effect.thread_id.len()) as u64;
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
                .saturating_add(std::mem::size_of::<BillingFact>() as u64);
            if fact.record.inference_id.is_empty()
                || !identities.insert(fact.record.inference_id.as_str())
                || (!fact.auxiliary
                    && effect
                        .attempt
                        .as_ref()
                        .is_none_or(|attempt| attempt.attempt_id != fact.record.inference_id))
            {
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
            let primary = !fact.auxiliary;
            let source = UsageSource {
                thread_id: self.thread_id.clone(),
                call_id: fact.record.inference_id.clone(),
                turn_id: primary.then(|| self.primary_turn_id.clone()).flatten(),
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
            let throughput = fact.record.timing.and_then(|timing| {
                pl_model::model::usage::throughput_output_tokens(
                    timing,
                    &fact.record.accounting.usage,
                )
                .map(|output_tokens| UsageThroughputSample {
                    output_tokens,
                    response_millis: timing.response_millis,
                })
            });
            summary.add_usage(
                &pl_model::model::usage::model_usage(&fact.record.accounting.usage),
                source,
                primary,
                throughput,
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
        summary.applied_sequence = self.sequence;
    }

    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        self.retained_bytes
    }
}

fn merge_costs(
    target: &mut Vec<pl_core::thread::UsageCost>,
    incoming: &[pl_protocol::RuntimeCostAmount],
) -> bool {
    let mut complete = true;
    for cost in incoming {
        if let Some(existing) = target
            .iter_mut()
            .find(|existing| existing.currency == cost.currency)
        {
            let next = existing.amount + cost.amount;
            if next.is_finite() {
                existing.amount = next;
            } else {
                complete = false;
            }
        } else {
            target.push(pl_core::thread::UsageCost {
                currency: cost.currency.clone(),
                amount: cost.amount,
            });
        }
    }
    target.sort_by(|left, right| left.currency.cmp(&right.currency));
    complete
}
