//! Thin adaptation of the model wire report to core's one usage analyzer.

use pl_core::model::ModelUsage;
use pl_core::usage::{UsageAnalysis, UsageStatus};
use pl_protocol::{InferenceTiming, UsageReport};

/// Preserve all vendor fields, including missing sides and contradictory reported totals.
pub fn model_usage(report: &UsageReport) -> ModelUsage {
    ModelUsage {
        input_tokens: report.input_tokens,
        output_tokens: report.output_tokens,
        cache_read_tokens: report.cache_read_tokens,
        cache_write_tokens: report.cache_write_tokens,
        reasoning_tokens: report.reasoning_tokens,
        total_tokens: report.total_tokens,
    }
}

pub fn usage_report(usage: &ModelUsage) -> UsageReport {
    UsageReport {
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cache_read_tokens: usage.cache_read_tokens,
        cache_write_tokens: usage.cache_write_tokens,
        reasoning_tokens: usage.reasoning_tokens,
        total_tokens: usage.total_tokens,
    }
}

pub fn analyze(report: &UsageReport) -> UsageAnalysis {
    pl_core::usage::analyze_usage(&model_usage(report))
}

/// Output tokens / total response time; the independent first-content observation may be unknown.
pub fn throughput_output_tokens(timing: InferenceTiming, usage: &UsageReport) -> Option<u64> {
    if !timing.has_throughput_sample() || analyze(usage).status == UsageStatus::Invalid {
        return None;
    }
    usage.output_tokens.filter(|tokens| *tokens > 0)
}
