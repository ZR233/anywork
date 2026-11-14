//! Canonical `UsageExportV1` builder and raw-receipt reconciliation against authoritative `UsageSummary`.

use std::collections::BTreeMap;

use anyhow::{Result, ensure};
use pl_core::model::ModelUsage;
use pl_core::thread::UsageSummary;
use pl_core::usage::{UsageAnalysis, UsageField, UsageStatus, analyze_usage};
use pl_protocol::{InferenceBillingRecord, PricingOutcome};

use super::types::{
    ModelUsageExportV1, ThreadUsageExportV1, UsageCoverage, UsageExportV1, UsageKnownTotalsV1,
    UsageMetricKey, UsageTotalsV1,
};
use crate::studio::thread_projection::PreparedAccounting;

#[derive(Debug, Default)]
struct MetricGroupAcc {
    inference_count: Option<u64>,
    known_inference_count: u64,
    input_tokens: Option<u64>,
    known_input_tokens: u64,
    output_tokens: Option<u64>,
    known_output_tokens: u64,
    cache_read_tokens: Option<u64>,
    known_cache_read_tokens: u64,
    cache_write_tokens: Option<u64>,
    known_cache_write_tokens: u64,
    reasoning_tokens: Option<u64>,
    known_reasoning_tokens: u64,
    total_tokens: Option<u64>,
    known_total_tokens: u64,
    estimated_cost_usd: Option<f64>,
    known_estimated_cost_usd: f64,
    any_incomplete_analysis: bool,
    any_overflow: bool,
    cost_overflow: bool,
}

impl MetricGroupAcc {
    fn new_complete_zero() -> Self {
        Self {
            inference_count: Some(0),
            known_inference_count: 0,
            input_tokens: Some(0),
            known_input_tokens: 0,
            output_tokens: Some(0),
            known_output_tokens: 0,
            cache_read_tokens: Some(0),
            known_cache_read_tokens: 0,
            cache_write_tokens: Some(0),
            known_cache_write_tokens: 0,
            reasoning_tokens: Some(0),
            known_reasoning_tokens: 0,
            total_tokens: Some(0),
            known_total_tokens: 0,
            estimated_cost_usd: Some(0.0),
            known_estimated_cost_usd: 0.0,
            any_incomplete_analysis: false,
            any_overflow: false,
            cost_overflow: false,
        }
    }

    fn record_call(&mut self, record: &InferenceBillingRecord) {
        let model_usage = pl_model::model::usage::model_usage(&record.accounting.usage);
        let analysis = analyze_usage(&model_usage);
        if !analysis.is_complete() {
            self.any_incomplete_analysis = true;
        }
        let cache_valid = cache_subset_valid(&model_usage);
        let reasoning_valid = reasoning_subset_valid(&model_usage);

        add_u64_metric(
            &mut self.inference_count,
            &mut self.known_inference_count,
            Some(1),
            &mut self.any_overflow,
        );
        add_u64_metric(
            &mut self.input_tokens,
            &mut self.known_input_tokens,
            (cache_valid && !has_field_issue(&analysis, UsageField::Input))
                .then_some(model_usage.input_tokens)
                .flatten(),
            &mut self.any_overflow,
        );
        add_u64_metric(
            &mut self.output_tokens,
            &mut self.known_output_tokens,
            (reasoning_valid && !has_field_issue(&analysis, UsageField::Output))
                .then_some(model_usage.output_tokens)
                .flatten(),
            &mut self.any_overflow,
        );
        add_u64_metric(
            &mut self.cache_read_tokens,
            &mut self.known_cache_read_tokens,
            (cache_valid && !has_field_issue(&analysis, UsageField::CacheRead))
                .then_some(model_usage.cache_read_tokens)
                .flatten(),
            &mut self.any_overflow,
        );
        add_u64_metric(
            &mut self.cache_write_tokens,
            &mut self.known_cache_write_tokens,
            (cache_valid && !has_field_issue(&analysis, UsageField::CacheWrite))
                .then_some(model_usage.cache_write_tokens)
                .flatten(),
            &mut self.any_overflow,
        );
        add_u64_metric(
            &mut self.reasoning_tokens,
            &mut self.known_reasoning_tokens,
            (reasoning_valid && !has_field_issue(&analysis, UsageField::Reasoning))
                .then_some(model_usage.reasoning_tokens)
                .flatten(),
            &mut self.any_overflow,
        );
        // Never copy a provider-contradicted total_tokens into knownTotals or totals.
        let total_contrib = if has_field_issue(&analysis, UsageField::Total) {
            None
        } else {
            analysis.total_tokens
        };
        add_u64_metric(
            &mut self.total_tokens,
            &mut self.known_total_tokens,
            total_contrib,
            &mut self.any_overflow,
        );

        let usd_contrib = frozen_usd_cost(&record.accounting.pricing);
        add_usd_metric(
            &mut self.estimated_cost_usd,
            &mut self.known_estimated_cost_usd,
            usd_contrib,
            &mut self.cost_overflow,
        );
    }

    fn finish(
        &self,
        coverage: UsageCoverage,
    ) -> (UsageTotalsV1, UsageKnownTotalsV1, Vec<UsageMetricKey>) {
        let complete = coverage == UsageCoverage::Complete;
        let totals = UsageTotalsV1 {
            inference_count: complete.then_some(self.inference_count).flatten(),
            input_tokens: complete.then_some(self.input_tokens).flatten(),
            output_tokens: complete.then_some(self.output_tokens).flatten(),
            cache_read_tokens: complete.then_some(self.cache_read_tokens).flatten(),
            cache_write_tokens: complete.then_some(self.cache_write_tokens).flatten(),
            reasoning_tokens: complete.then_some(self.reasoning_tokens).flatten(),
            total_tokens: complete.then_some(self.total_tokens).flatten(),
            estimated_cost_usd: complete.then_some(self.estimated_cost_usd).flatten(),
        };
        let known_totals = UsageKnownTotalsV1 {
            inference_count: self.known_inference_count,
            input_tokens: self.known_input_tokens,
            output_tokens: self.known_output_tokens,
            cache_read_tokens: self.known_cache_read_tokens,
            cache_write_tokens: self.known_cache_write_tokens,
            reasoning_tokens: self.known_reasoning_tokens,
            total_tokens: self.known_total_tokens,
            estimated_cost_usd: self.known_estimated_cost_usd,
        };
        let unknown_fields = collect_unknown_fields(&totals);
        (totals, known_totals, unknown_fields)
    }
}

fn cache_subset_valid(usage: &ModelUsage) -> bool {
    let cached = usage
        .cache_read_tokens
        .unwrap_or(0)
        .checked_add(usage.cache_write_tokens.unwrap_or(0));
    match (usage.input_tokens, cached) {
        (Some(input), Some(total_cache)) => total_cache <= input,
        (None, Some(_)) => true,
        (_, None) => false,
    }
}

fn reasoning_subset_valid(usage: &ModelUsage) -> bool {
    match (usage.output_tokens, usage.reasoning_tokens) {
        (Some(output), Some(reasoning)) => reasoning <= output,
        (None, _) | (_, None) => true,
    }
}

fn has_field_issue(analysis: &UsageAnalysis, field: UsageField) -> bool {
    analysis.issues.iter().any(|issue| issue.field == field)
        || (field == UsageField::Total
            && analysis.status == UsageStatus::Invalid
            && analysis.context_tokens.is_none()
            && analysis
                .issues
                .iter()
                .any(|issue| issue.field == UsageField::Total))
}

fn add_u64_metric(
    total: &mut Option<u64>,
    known: &mut u64,
    contribution: Option<u64>,
    any_overflow: &mut bool,
) {
    let Some(value) = contribution else {
        *total = None;
        return;
    };
    if let Some(next_known) = known.checked_add(value) {
        *known = next_known;
    } else {
        *any_overflow = true;
        *total = None;
    }
    if let Some(current_total) = *total {
        match current_total.checked_add(value) {
            Some(next_total) => *total = Some(next_total),
            None => {
                *any_overflow = true;
                *total = None;
            }
        }
    }
}

fn add_usd_metric(
    total: &mut Option<f64>,
    known: &mut f64,
    contribution: Option<f64>,
    any_overflow: &mut bool,
) {
    let Some(value) = contribution else {
        *total = None;
        return;
    };
    let next_known = *known + value;
    if next_known.is_finite() {
        *known = next_known;
    } else {
        *any_overflow = true;
        *total = None;
    }
    if let Some(current_total) = *total {
        let next_total = current_total + value;
        if next_total.is_finite() {
            *total = Some(next_total);
        } else {
            *any_overflow = true;
            *total = None;
        }
    }
}

fn frozen_usd_cost(pricing: &PricingOutcome) -> Option<f64> {
    match pricing {
        PricingOutcome::NoCharge => Some(0.0),
        PricingOutcome::Estimated { cost, .. }
            if cost.currency.eq_ignore_ascii_case("USD")
                && cost.amount.is_finite()
                && cost.amount >= 0.0 =>
        {
            Some(cost.amount)
        }
        PricingOutcome::Estimated { .. }
        | PricingOutcome::Disabled
        | PricingOutcome::Unpriced { .. } => None,
    }
}

fn collect_unknown_fields(totals: &UsageTotalsV1) -> Vec<UsageMetricKey> {
    let mut missing = Vec::new();
    if totals.inference_count.is_none() {
        missing.push(UsageMetricKey::InferenceCount);
    }
    if totals.input_tokens.is_none() {
        missing.push(UsageMetricKey::InputTokens);
    }
    if totals.output_tokens.is_none() {
        missing.push(UsageMetricKey::OutputTokens);
    }
    if totals.cache_read_tokens.is_none() {
        missing.push(UsageMetricKey::CacheReadTokens);
    }
    if totals.cache_write_tokens.is_none() {
        missing.push(UsageMetricKey::CacheWriteTokens);
    }
    if totals.reasoning_tokens.is_none() {
        missing.push(UsageMetricKey::ReasoningTokens);
    }
    if totals.total_tokens.is_none() {
        missing.push(UsageMetricKey::TotalTokens);
    }
    if totals.estimated_cost_usd.is_none() {
        missing.push(UsageMetricKey::EstimatedCostUsd);
    }
    missing
}

/// Authoritative per-thread input supplied to the reconciler & exporter summary builder.
pub struct ThreadUsageInput<'a> {
    pub thread_id: &'a str,
    pub through_effect_seq: u64,
    pub summary: &'a UsageSummary,
    pub replayed: &'a UsageSummary,
}

/// Output of full run usage aggregation + raw-receipt reconciliation.
pub struct BuiltUsageExport {
    pub export: UsageExportV1,
    pub usage_complete: bool,
    pub cost_complete: bool,
    pub reconciled: bool,
    pub reconcile_error: Option<String>,
}

/// Replays every admitted raw `PreparedAccounting` through the canonical reducer and verifies
/// exact field-for-field agreement with each thread's authoritative `UsageSummary`, then builds
/// `UsageExportV1` with frozen model identities and honest unknown-value handling.
pub struct UsageAccumulator {
    run: MetricGroupAcc,
    by_model: BTreeMap<(Option<String>, Option<String>), MetricGroupAcc>,
}

impl Default for UsageAccumulator {
    fn default() -> Self {
        Self {
            run: MetricGroupAcc::new_complete_zero(),
            by_model: BTreeMap::new(),
        }
    }
}

impl UsageAccumulator {
    pub fn record(&mut self, prepared: &PreparedAccounting) {
        for fact in prepared.facts.iter() {
            self.run.record_call(&fact.record);
            let account_id =
                (!fact.record.account_id.is_empty()).then(|| fact.record.account_id.clone());
            let model_id = fact
                .record
                .model_id
                .as_deref()
                .filter(|id| !id.is_empty())
                .map(str::to_owned);
            self.by_model
                .entry((account_id, model_id))
                .or_insert_with(MetricGroupAcc::new_complete_zero)
                .record_call(&fact.record);
        }
    }

    pub fn finish(
        &self,
        trace_complete: bool,
        threads: &[ThreadUsageInput<'_>],
    ) -> BuiltUsageExport {
        let mut reconcile_error = None;
        for thread in threads {
            if let Err(error) = reconcile_single_thread(thread) {
                reconcile_error = Some(error.to_string());
                break;
            }
        }
        let reconciled = reconcile_error.is_none();
        let coverage = if trace_complete && reconciled {
            UsageCoverage::Complete
        } else {
            UsageCoverage::Partial
        };

        let run_acc = &self.run;
        let mut any_thread_counts_overflowed = false;
        let mut by_thread = Vec::with_capacity(threads.len());

        for thread in threads {
            any_thread_counts_overflowed |= thread.summary.diagnostics.counts_overflowed
                || thread.summary.diagnostics.overflow_calls != 0;
            by_thread.push(ThreadUsageExportV1 {
                thread_id: thread.thread_id.to_string(),
                through_effect_seq: thread.through_effect_seq,
                summary: thread.summary.clone(),
            });
        }

        let (totals, known_totals, run_unknown_fields) = run_acc.finish(coverage);
        let mut by_model = Vec::with_capacity(self.by_model.len());
        let mut any_model_unknown = false;
        for ((account_id, model_id), acc) in &self.by_model {
            let (m_totals, m_known, m_unknown) = acc.finish(coverage);
            let has_unknown_values = coverage != UsageCoverage::Complete || !m_unknown.is_empty();
            any_model_unknown |= has_unknown_values;
            by_model.push(ModelUsageExportV1 {
                account_id: account_id.clone(),
                model_id: model_id.clone(),
                coverage,
                has_unknown_values,
                totals: m_totals,
                known_totals: m_known,
                unknown_fields: m_unknown,
            });
        }

        let has_unknown_values = coverage != UsageCoverage::Complete
            || !run_unknown_fields.is_empty()
            || any_model_unknown;
        let usage_complete = coverage == UsageCoverage::Complete
            && !run_acc.any_incomplete_analysis
            && !run_acc.any_overflow
            && !any_thread_counts_overflowed;
        let cost_complete = coverage == UsageCoverage::Complete
            && totals.estimated_cost_usd.is_some()
            && !run_acc.cost_overflow;

        BuiltUsageExport {
            export: UsageExportV1 {
                coverage,
                has_unknown_values,
                totals,
                known_totals,
                by_model,
                by_thread,
            },
            usage_complete,
            cost_complete,
            reconciled,
            reconcile_error,
        }
    }
}

fn reconcile_single_thread(thread: &ThreadUsageInput<'_>) -> Result<()> {
    let expected_seq = thread.through_effect_seq;
    ensure!(
        thread.summary.applied_sequence == expected_seq,
        "thread {} summary applied_sequence ({}) differs from final effect cut ({})",
        thread.thread_id,
        thread.summary.applied_sequence,
        expected_seq
    );
    ensure!(
        thread.replayed == thread.summary,
        "thread {} replayed raw billing receipts differ from authoritative UsageSummary (applied_seq={})",
        thread.thread_id,
        expected_seq
    );
    Ok(())
}

/// Incremental replay retains the native reducer result, not every raw billing record.
pub fn fold_next_accounting(
    thread_id: &str,
    prepared: &PreparedAccounting,
    replayed: &mut UsageSummary,
) -> Result<()> {
    ensure!(
        prepared.thread_id == thread_id,
        "accounting receipt belongs to another thread"
    );
    ensure!(
        replayed.applied_sequence.checked_add(1) == Some(prepared.sequence),
        "accounting effect gap for thread {thread_id}: after {}, got {}",
        replayed.applied_sequence,
        prepared.sequence
    );
    prepared.fold_into(replayed);
    Ok(())
}
