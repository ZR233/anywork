//! The flat accounting layout is decoded only at an explicit checkpoint migration boundary.
use super::{UsageCost, UsageSummary};
use crate::model::ModelUsageBinding;
use crate::usage::{
    UsageCacheSummary, UsageContextSummary, UsageDiagnostics, UsageThroughputSummary, UsageTotals,
};

#[derive(Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", default, deny_unknown_fields)]
pub(crate) struct LegacyUsageSummary {
    pub applied_sequence: u64,
    model: String,
    context_window: Option<u64>,
    max_context_window: Option<u64>,
    auto_compact_limit: Option<u64>,
    inference_count: u64,
    prompt_tokens: u64,
    completion_tokens: u64,
    cached_prompt_tokens: u64,
    cache_write_tokens: u64,
    reasoning_tokens: u64,
    total_tokens: u64,
    cache_input_tokens: u64,
    cache_read_tokens: u64,
    latest_context_tokens: u64,
    has_incomplete_usage: bool,
    has_unpriced_usage: bool,
    cache_incomplete: bool,
    estimated_costs: Vec<UsageCost>,
    estimated_cache_savings: Vec<UsageCost>,
    turn_completion_tokens: u64,
    turn_response_millis: u64,
    turn_id: String,
}

impl From<LegacyUsageSummary> for UsageSummary {
    fn from(old: LegacyUsageSummary) -> Self {
        Self {
            applied_sequence: old.applied_sequence,
            binding: (!old.model.is_empty()
                || old.context_window.is_some()
                || old.max_context_window.is_some()
                || old.auto_compact_limit.is_some())
            .then_some(ModelUsageBinding {
                route_identity: None,
                model: old.model,
                context_window: old.context_window,
                max_context_window: old.max_context_window,
                auto_compact_limit: old.auto_compact_limit,
            }),
            totals: UsageTotals {
                inference_count: old.inference_count,
                prompt_tokens: old.prompt_tokens,
                completion_tokens: old.completion_tokens,
                cached_prompt_tokens: old.cached_prompt_tokens,
                cache_write_tokens: old.cache_write_tokens,
                reasoning_tokens: old.reasoning_tokens,
                total_tokens: old.total_tokens,
            },
            cache: UsageCacheSummary {
                input_tokens: old.cache_input_tokens,
                read_tokens: old.cache_read_tokens,
                sample_count: 0, // The old layout did not record a sample count.
                incomplete: old.cache_incomplete,
            },
            context: UsageContextSummary {
                tokens: old.latest_context_tokens,
                latest_call: None,
            },
            throughput: if old.turn_completion_tokens > 0
                && old.turn_response_millis > 0
                && !old.turn_id.is_empty()
            {
                UsageThroughputSummary {
                    turn_id: old.turn_id,
                    completion_tokens: old.turn_completion_tokens,
                    response_millis: old.turn_response_millis,
                }
            } else {
                UsageThroughputSummary::default()
            },
            diagnostics: UsageDiagnostics {
                legacy_unknown: true,
                legacy_incomplete: old.has_incomplete_usage,
                ..Default::default()
            },
            pricing: super::UsagePricingSummary {
                incomplete: old.has_unpriced_usage,
                estimated_costs: old.estimated_costs,
                estimated_cache_savings: old.estimated_cache_savings,
            },
        }
    }
}

/// Retain the fixed output layout of the historical usage backfill, before schema 6 exists.
impl From<UsageSummary> for LegacyUsageSummary {
    fn from(summary: UsageSummary) -> Self {
        let has_incomplete_usage = summary.has_incomplete_usage();
        let binding = summary.binding;
        Self {
            applied_sequence: summary.applied_sequence,
            model: binding
                .as_ref()
                .map_or_else(String::new, |b| b.model.clone()),
            context_window: binding.as_ref().and_then(|b| b.context_window),
            max_context_window: binding.as_ref().and_then(|b| b.max_context_window),
            auto_compact_limit: binding.as_ref().and_then(|b| b.auto_compact_limit),
            inference_count: summary.totals.inference_count,
            prompt_tokens: summary.totals.prompt_tokens,
            completion_tokens: summary.totals.completion_tokens,
            cached_prompt_tokens: summary.totals.cached_prompt_tokens,
            cache_write_tokens: summary.totals.cache_write_tokens,
            reasoning_tokens: summary.totals.reasoning_tokens,
            total_tokens: summary.totals.total_tokens,
            cache_input_tokens: summary.cache.input_tokens,
            cache_read_tokens: summary.cache.read_tokens,
            latest_context_tokens: summary.context.tokens,
            has_incomplete_usage,
            has_unpriced_usage: summary.pricing.incomplete,
            cache_incomplete: summary.cache.incomplete,
            estimated_costs: summary.pricing.estimated_costs,
            estimated_cache_savings: summary.pricing.estimated_cache_savings,
            turn_completion_tokens: summary.throughput.completion_tokens,
            turn_response_millis: summary.throughput.response_millis,
            turn_id: summary.throughput.turn_id,
        }
    }
}

pub(super) fn upgrade(root: &mut serde_json::Value) -> Result<(), serde_json::Error> {
    let state = root
        .get_mut("state")
        .and_then(serde_json::Value::as_object_mut)
        .ok_or_else(|| {
            <serde_json::Error as serde::de::Error>::custom("checkpoint state must be an object")
        })?;
    let old = state
        .remove("usageSummary")
        .unwrap_or_else(|| serde_json::json!({}));
    if !old.is_object() {
        return Err(<serde_json::Error as serde::de::Error>::custom(
            "legacy usage summary must be an object",
        ));
    }
    let summary: LegacyUsageSummary = serde_json::from_value(old)?;
    state.insert(
        "usageSummary".into(),
        serde_json::to_value(UsageSummary::from(summary))?,
    );
    Ok(())
}
