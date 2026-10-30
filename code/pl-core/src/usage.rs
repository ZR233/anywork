//! Provider-independent analysis of raw usage and checked, bounded accounting diagnostics.
//!
//! Raw reports are never repaired. Products adapt their wire report to [`ModelUsage`] and add
//! monetary contributions separately; both plain storage and product storage use this reducer.

use serde::{Deserialize, Serialize};

use crate::model::ModelUsage;

pub const RECENT_USAGE_GAP_LIMIT: usize = 8;
pub const USAGE_PURPOSE_LIMIT: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageStatus {
    /// Explicit migration provenance when an old projection did not retain the raw report.
    LegacyUnknown,
    Missing,
    Partial,
    Reported,
    Invalid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageField {
    Input,
    Output,
    CacheRead,
    CacheWrite,
    Reasoning,
    Total,
    InferenceCount,
    CachePair,
    ThroughputPair,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageIssueReason {
    Unreported,
    Inconsistent,
    Overflow,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageIssue {
    pub field: UsageField,
    pub reason: UsageIssueReason,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageOutcome {
    Succeeded,
    Rejected,
    Cancelled,
    Failed,
    Interrupted,
}

/// Opaque product purpose and real invocation identity; core does not interpret either.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageSource {
    pub thread_id: String,
    pub call_id: String,
    pub turn_id: Option<String>,
    pub effect_sequence: u64,
    pub observed_at: i64,
    pub purpose: Option<String>,
    pub outcome: UsageOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageObservation {
    pub source: UsageSource,
    pub status: UsageStatus,
    pub usage: ModelUsage,
    pub issues: Vec<UsageIssue>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageTotals {
    pub inference_count: u64,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub total_tokens: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageCacheSummary {
    pub input_tokens: u64,
    pub read_tokens: u64,
    pub sample_count: u64,
    pub incomplete: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageContextSummary {
    /// Last usable context observation. Zero in a legacy summary does not prove an explicit zero.
    pub tokens: u64,
    pub latest_call: Option<UsageObservation>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageThroughputSummary {
    pub turn_id: String,
    pub completion_tokens: u64,
    pub response_millis: u64,
}

/// A validated numerator/denominator pair from a successful primary call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct UsageThroughputSample {
    pub output_tokens: u64,
    pub response_millis: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageOutcomeCount {
    pub outcome: UsageOutcome,
    pub calls: u64,
    pub incomplete_calls: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsagePurposeCount {
    pub purpose: Option<String>,
    pub calls: u64,
    pub incomplete_calls: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageIssueCount {
    pub issue: UsageIssue,
    pub calls: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageDiagnostics {
    pub incomplete_calls: u64,
    pub missing_calls: u64,
    pub partial_calls: u64,
    pub invalid_calls: u64,
    pub overflow_calls: u64,
    pub by_outcome: Vec<UsageOutcomeCount>,
    /// Bounded opaque categories, not an unbounded dimension supplied by a provider.
    pub by_purpose: Vec<UsagePurposeCount>,
    pub other_purpose_calls: u64,
    pub by_issue: Vec<UsageIssueCount>,
    pub recent_gaps: Vec<UsageObservation>,
    /// Old totals/flags are retained without inventing missing counts or invocation identities.
    pub legacy_unknown: bool,
    pub legacy_incomplete: bool,
    pub counts_overflowed: bool,
}

/// Derived observations, distinct from the original report.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsageAnalysis {
    pub status: UsageStatus,
    pub total_tokens: Option<u64>,
    pub context_tokens: Option<u64>,
    pub cache_sample: Option<(u64, u64)>,
    pub issues: Vec<UsageIssue>,
}

impl UsageAnalysis {
    pub fn is_complete(&self) -> bool {
        self.status == UsageStatus::Reported && self.cache_sample.is_some()
    }
}

/// Analyze counters without overwriting vendor totals, missing fields or explicit zero.
pub fn analyze_usage(usage: &ModelUsage) -> UsageAnalysis {
    let mut issues = Vec::new();
    for (field, value) in [
        (UsageField::Input, usage.input_tokens),
        (UsageField::Output, usage.output_tokens),
        (UsageField::CacheRead, usage.cache_read_tokens),
    ] {
        if value.is_none() {
            issues.push(UsageIssue {
                field,
                reason: UsageIssueReason::Unreported,
            });
        }
    }
    let derived_total = usage
        .input_tokens
        .zip(usage.output_tokens)
        .and_then(|(input, output)| input.checked_add(output));
    if usage.input_tokens.is_some() && usage.output_tokens.is_some() {
        if derived_total.is_none() {
            issues.push(UsageIssue {
                field: UsageField::Total,
                reason: UsageIssueReason::Overflow,
            });
        } else if usage
            .total_tokens
            .is_some_and(|total| Some(total) != derived_total)
        {
            issues.push(UsageIssue {
                field: UsageField::Total,
                reason: UsageIssueReason::Inconsistent,
            });
        }
    }
    let cache_valid = usage.input_tokens.is_none_or(|input| {
        usage
            .cache_read_tokens
            .unwrap_or(0)
            .checked_add(usage.cache_write_tokens.unwrap_or(0))
            .is_some_and(|cached| cached <= input)
    });
    if !cache_valid {
        issues.push(UsageIssue {
            field: UsageField::CachePair,
            reason: UsageIssueReason::Inconsistent,
        });
    }
    if usage
        .output_tokens
        .zip(usage.reasoning_tokens)
        .is_some_and(|(output, reasoning)| reasoning > output)
    {
        issues.push(UsageIssue {
            field: UsageField::Reasoning,
            reason: UsageIssueReason::Inconsistent,
        });
    }
    let invalid = issues
        .iter()
        .any(|issue| issue.reason != UsageIssueReason::Unreported);
    let status = if invalid {
        UsageStatus::Invalid
    } else if usage == &ModelUsage::default() {
        UsageStatus::Missing
    } else if usage.input_tokens.is_some() && usage.output_tokens.is_some() {
        UsageStatus::Reported
    } else {
        UsageStatus::Partial
    };
    let total_tokens = usage.total_tokens.or(derived_total);
    UsageAnalysis {
        status,
        total_tokens,
        context_tokens: (!invalid).then_some(total_tokens).flatten(),
        cache_sample: usage
            .input_tokens
            .zip(usage.cache_read_tokens)
            .filter(|_| cache_valid),
        issues,
    }
}

impl crate::thread::UsageSummary {
    pub fn has_incomplete_usage(&self) -> bool {
        self.diagnostics.legacy_incomplete
            || self.diagnostics.incomplete_calls != 0
            || self.diagnostics.counts_overflowed
    }

    /// Add one terminal invocation. The caller owns effect-sequence idempotence and validates
    /// invocation identity before calling. Overflow retains representable existing totals, marks
    /// the contribution incomplete and never prevents reliable execution history from being saved.
    pub fn add_usage(
        &mut self,
        usage: &ModelUsage,
        source: UsageSource,
        primary: bool,
        throughput: Option<UsageThroughputSample>,
    ) {
        let analysis = analyze_usage(usage);
        let mut issues = analysis.issues;
        for (current, value, field) in [
            (
                &mut self.totals.inference_count,
                Some(1),
                UsageField::InferenceCount,
            ),
            (
                &mut self.totals.prompt_tokens,
                usage.input_tokens,
                UsageField::Input,
            ),
            (
                &mut self.totals.completion_tokens,
                usage.output_tokens,
                UsageField::Output,
            ),
            (
                &mut self.totals.cached_prompt_tokens,
                usage.cache_read_tokens,
                UsageField::CacheRead,
            ),
            (
                &mut self.totals.cache_write_tokens,
                usage.cache_write_tokens,
                UsageField::CacheWrite,
            ),
            (
                &mut self.totals.reasoning_tokens,
                usage.reasoning_tokens,
                UsageField::Reasoning,
            ),
            (
                &mut self.totals.total_tokens,
                analysis.total_tokens,
                UsageField::Total,
            ),
        ] {
            if let Some(value) = value {
                if let Some(next) = current.checked_add(value) {
                    *current = next;
                } else {
                    push_overflow(&mut issues, field);
                }
            }
        }
        if let Some((input, read)) = analysis.cache_sample {
            match (
                self.cache.input_tokens.checked_add(input),
                self.cache.read_tokens.checked_add(read),
                self.cache.sample_count.checked_add(1),
            ) {
                (Some(input), Some(read), Some(samples)) => {
                    self.cache.input_tokens = input;
                    self.cache.read_tokens = read;
                    self.cache.sample_count = samples;
                }
                _ => {
                    self.cache.incomplete = true;
                    push_overflow(&mut issues, UsageField::CachePair);
                }
            }
        } else {
            self.cache.incomplete = true;
        }
        if primary && let Some(tokens) = analysis.context_tokens {
            self.context.tokens = tokens;
        }
        if let Some(sample) = throughput
            && primary
            && source.outcome == UsageOutcome::Succeeded
            && sample.output_tokens > 0
            && sample.response_millis > 0
            && let Some(turn_id) = source.turn_id.as_deref()
        {
            let previous = if self.throughput.turn_id == turn_id {
                self.throughput.clone()
            } else {
                UsageThroughputSummary::default()
            };
            match (
                previous.completion_tokens.checked_add(sample.output_tokens),
                previous.response_millis.checked_add(sample.response_millis),
            ) {
                (Some(tokens), Some(millis)) => {
                    self.throughput = UsageThroughputSummary {
                        turn_id: turn_id.to_owned(),
                        completion_tokens: tokens,
                        response_millis: millis,
                    };
                }
                _ => push_overflow(&mut issues, UsageField::ThroughputPair),
            }
        }
        let observation = UsageObservation {
            source,
            status: analysis.status,
            usage: usage.clone(),
            issues,
        };
        if primary {
            self.context.latest_call = Some(observation.clone());
        }
        self.diagnostics.record(observation);
    }
}

fn push_overflow(issues: &mut Vec<UsageIssue>, field: UsageField) {
    let issue = UsageIssue {
        field,
        reason: UsageIssueReason::Overflow,
    };
    if !issues.contains(&issue) {
        issues.push(issue);
    }
}

impl UsageDiagnostics {
    fn record(&mut self, observation: UsageObservation) {
        let incomplete = !observation.issues.is_empty();
        for (counter, active) in [
            (&mut self.incomplete_calls, incomplete),
            (
                &mut self.missing_calls,
                observation.status == UsageStatus::Missing,
            ),
            (
                &mut self.partial_calls,
                observation.status == UsageStatus::Partial,
            ),
            (
                &mut self.invalid_calls,
                observation.status == UsageStatus::Invalid,
            ),
            (
                &mut self.overflow_calls,
                observation
                    .issues
                    .iter()
                    .any(|issue| issue.reason == UsageIssueReason::Overflow),
            ),
        ] {
            if active {
                increment(counter, &mut self.counts_overflowed);
            }
        }
        if let Some(row) = self
            .by_outcome
            .iter_mut()
            .find(|row| row.outcome == observation.source.outcome)
        {
            increment(&mut row.calls, &mut self.counts_overflowed);
            if incomplete {
                increment(&mut row.incomplete_calls, &mut self.counts_overflowed);
            }
        } else {
            self.by_outcome.push(UsageOutcomeCount {
                outcome: observation.source.outcome,
                calls: 1,
                incomplete_calls: u64::from(incomplete),
            });
        }
        if let Some(row) = self
            .by_purpose
            .iter_mut()
            .find(|row| row.purpose == observation.source.purpose)
        {
            increment(&mut row.calls, &mut self.counts_overflowed);
            if incomplete {
                increment(&mut row.incomplete_calls, &mut self.counts_overflowed);
            }
        } else if self.by_purpose.len() < USAGE_PURPOSE_LIMIT {
            self.by_purpose.push(UsagePurposeCount {
                purpose: observation.source.purpose.clone(),
                calls: 1,
                incomplete_calls: u64::from(incomplete),
            });
        } else {
            increment(&mut self.other_purpose_calls, &mut self.counts_overflowed);
        }
        for issue in &observation.issues {
            if let Some(row) = self.by_issue.iter_mut().find(|row| row.issue == *issue) {
                increment(&mut row.calls, &mut self.counts_overflowed);
            } else {
                self.by_issue.push(UsageIssueCount {
                    issue: *issue,
                    calls: 1,
                });
            }
        }
        if incomplete {
            self.recent_gaps.push(observation);
            if self.recent_gaps.len() > RECENT_USAGE_GAP_LIMIT {
                self.recent_gaps.remove(0);
            }
        }
    }
}

fn increment(counter: &mut u64, overflowed: &mut bool) {
    if let Some(next) = counter.checked_add(1) {
        *counter = next;
    } else {
        *overflowed = true;
    }
}
