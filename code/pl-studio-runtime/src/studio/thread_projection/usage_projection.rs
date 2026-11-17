//! Data-only mapping of core accounting diagnostics to the product wire.

pub(in crate::studio) fn usage_status(
    status: pl_core::usage::UsageStatus,
) -> crate::UsageReportStatus {
    use crate::UsageReportStatus as Wire;
    use pl_core::usage::UsageStatus as Core;
    match status {
        Core::LegacyUnknown => Wire::LegacyUnknown,
        Core::Missing => Wire::Missing,
        Core::Partial => Wire::Partial,
        Core::Reported => Wire::Reported,
        Core::Invalid => Wire::Invalid,
    }
}

fn outcome(status: pl_core::usage::UsageOutcome) -> crate::UsageTerminalStatus {
    use crate::UsageTerminalStatus as Wire;
    use pl_core::usage::UsageOutcome as Core;
    match status {
        Core::Succeeded => Wire::Succeeded,
        Core::Rejected => Wire::Rejected,
        Core::Cancelled => Wire::Cancelled,
        Core::Failed => Wire::Failed,
        Core::Interrupted => Wire::Interrupted,
    }
}

fn issue(issue: &pl_core::usage::UsageIssue) -> crate::UsageGapIssue {
    use crate::{UsageCounterField as Field, UsageGapReason as Reason};
    use pl_core::usage::{UsageField, UsageIssueReason};
    crate::UsageGapIssue {
        field: match issue.field {
            UsageField::Input => Field::Input,
            UsageField::Output => Field::Output,
            UsageField::CacheRead => Field::CacheRead,
            UsageField::CacheWrite => Field::CacheWrite,
            UsageField::Reasoning => Field::Reasoning,
            UsageField::Total => Field::Total,
            UsageField::InferenceCount => Field::InferenceCount,
            UsageField::CachePair => Field::CachePair,
            UsageField::ThroughputPair => Field::ThroughputPair,
        },
        reason: match issue.reason {
            UsageIssueReason::Unreported => Reason::Unreported,
            UsageIssueReason::Inconsistent => Reason::Inconsistent,
            UsageIssueReason::Overflow => Reason::Overflow,
        },
    }
}

fn observation(value: &pl_core::usage::UsageObservation) -> crate::UsageCallSnapshot {
    let source = &value.source;
    crate::UsageCallSnapshot {
        thread_id: source.thread_id.clone(),
        call_id: source.call_id.clone(),
        turn_id: source.turn_id.clone(),
        effect_sequence: source.effect_sequence,
        observed_at: source.observed_at,
        purpose: source.purpose.clone(),
        outcome: outcome(source.outcome),
        status: usage_status(value.status),
        usage: pl_model::model::usage::usage_report(&value.usage),
        issues: value.issues.iter().map(issue).collect(),
    }
}

pub(super) fn diagnostics(
    summary: &pl_core::thread::UsageSummary,
) -> crate::ThreadUsageDiagnostics {
    let value = &summary.diagnostics;
    crate::ThreadUsageDiagnostics {
        incomplete_calls: value.incomplete_calls,
        missing_calls: value.missing_calls,
        partial_calls: value.partial_calls,
        invalid_calls: value.invalid_calls,
        overflow_calls: value.overflow_calls,
        by_outcome: value
            .by_outcome
            .iter()
            .map(|row| crate::UsageOutcomeCountSnapshot {
                outcome: outcome(row.outcome),
                calls: row.calls,
                incomplete_calls: row.incomplete_calls,
            })
            .collect(),
        by_purpose: value
            .by_purpose
            .iter()
            .map(|row| crate::UsagePurposeCountSnapshot {
                purpose: row.purpose.clone(),
                calls: row.calls,
                incomplete_calls: row.incomplete_calls,
            })
            .collect(),
        other_purpose_calls: value.other_purpose_calls,
        by_issue: value
            .by_issue
            .iter()
            .map(|row| crate::UsageIssueCountSnapshot {
                issue: issue(&row.issue),
                calls: row.calls,
            })
            .collect(),
        recent_gaps: value.recent_gaps.iter().map(observation).collect(),
        latest_call: summary.context.latest_call.as_ref().map(observation),
        legacy_unknown: value.legacy_unknown,
        counts_overflowed: value.counts_overflowed,
    }
}
