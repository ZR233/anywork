use crate::api::studio::types::*;

impl From<pl_studio_runtime::UsageReportStatus> for BridgeUsageReportStatus {
    fn from(value: pl_studio_runtime::UsageReportStatus) -> Self {
        match value {
            pl_studio_runtime::UsageReportStatus::LegacyUnknown => Self::LegacyUnknown,
            pl_studio_runtime::UsageReportStatus::Missing => Self::Missing,
            pl_studio_runtime::UsageReportStatus::Partial => Self::Partial,
            pl_studio_runtime::UsageReportStatus::Reported => Self::Reported,
            pl_studio_runtime::UsageReportStatus::Invalid => Self::Invalid,
        }
    }
}

impl From<pl_studio_runtime::UsageTerminalStatus> for BridgeUsageTerminalStatus {
    fn from(value: pl_studio_runtime::UsageTerminalStatus) -> Self {
        match value {
            pl_studio_runtime::UsageTerminalStatus::Succeeded => Self::Succeeded,
            pl_studio_runtime::UsageTerminalStatus::Rejected => Self::Rejected,
            pl_studio_runtime::UsageTerminalStatus::Cancelled => Self::Cancelled,
            pl_studio_runtime::UsageTerminalStatus::Failed => Self::Failed,
            pl_studio_runtime::UsageTerminalStatus::Interrupted => Self::Interrupted,
        }
    }
}

impl From<pl_studio_runtime::UsageCounterField> for BridgeUsageCounterField {
    fn from(value: pl_studio_runtime::UsageCounterField) -> Self {
        match value {
            pl_studio_runtime::UsageCounterField::Input => Self::Input,
            pl_studio_runtime::UsageCounterField::Output => Self::Output,
            pl_studio_runtime::UsageCounterField::CacheRead => Self::CacheRead,
            pl_studio_runtime::UsageCounterField::CacheWrite => Self::CacheWrite,
            pl_studio_runtime::UsageCounterField::Reasoning => Self::Reasoning,
            pl_studio_runtime::UsageCounterField::Total => Self::Total,
            pl_studio_runtime::UsageCounterField::InferenceCount => Self::InferenceCount,
            pl_studio_runtime::UsageCounterField::CachePair => Self::CachePair,
            pl_studio_runtime::UsageCounterField::ThroughputPair => Self::ThroughputPair,
        }
    }
}

impl From<pl_studio_runtime::UsageGapReason> for BridgeUsageGapReason {
    fn from(value: pl_studio_runtime::UsageGapReason) -> Self {
        match value {
            pl_studio_runtime::UsageGapReason::Unreported => Self::Unreported,
            pl_studio_runtime::UsageGapReason::Inconsistent => Self::Inconsistent,
            pl_studio_runtime::UsageGapReason::Overflow => Self::Overflow,
        }
    }
}

impl From<pl_studio_runtime::MetricAvailability> for BridgeMetricAvailability {
    fn from(value: pl_studio_runtime::MetricAvailability) -> Self {
        match value {
            pl_studio_runtime::MetricAvailability::Available => Self::Available,
            pl_studio_runtime::MetricAvailability::NotCollected => Self::NotCollected,
            pl_studio_runtime::MetricAvailability::NoVisibleOutput => Self::NoVisibleOutput,
            pl_studio_runtime::MetricAvailability::MissingOutput => Self::MissingOutput,
            pl_studio_runtime::MetricAvailability::ZeroOutput => Self::ZeroOutput,
            pl_studio_runtime::MetricAvailability::InvalidUsage => Self::InvalidUsage,
            pl_studio_runtime::MetricAvailability::InvalidTiming => Self::InvalidTiming,
            pl_studio_runtime::MetricAvailability::LegacyUnknown => Self::LegacyUnknown,
        }
    }
}

impl From<pl_studio_runtime::FirstOutputSource> for BridgeFirstOutputSource {
    fn from(value: pl_studio_runtime::FirstOutputSource) -> Self {
        match value {
            pl_studio_runtime::FirstOutputSource::Unobserved => Self::Unobserved,
            pl_studio_runtime::FirstOutputSource::Incremental => Self::Incremental,
            pl_studio_runtime::FirstOutputSource::CompletedToolInput => Self::CompletedToolInput,
            pl_studio_runtime::FirstOutputSource::LegacyUnknown => Self::LegacyUnknown,
        }
    }
}

impl From<pl_studio_runtime::UsageGapIssue> for BridgeUsageGapIssue {
    fn from(value: pl_studio_runtime::UsageGapIssue) -> Self {
        Self {
            field: value.field.into(),
            reason: value.reason.into(),
        }
    }
}

impl From<pl_studio_runtime::UsageCallSnapshot> for BridgeUsageCallSnapshot {
    fn from(value: pl_studio_runtime::UsageCallSnapshot) -> Self {
        Self {
            thread_id: value.thread_id,
            call_id: value.call_id,
            turn_id: value.turn_id,
            effect_sequence: value.effect_sequence,
            observed_at: value.observed_at,
            purpose: value.purpose,
            outcome: value.outcome.into(),
            status: value.status.into(),
            usage: value.usage.into(),
            issues: value.issues.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<pl_studio_runtime::UsageOutcomeCountSnapshot> for BridgeUsageOutcomeCountSnapshot {
    fn from(value: pl_studio_runtime::UsageOutcomeCountSnapshot) -> Self {
        Self {
            outcome: value.outcome.into(),
            calls: value.calls,
            incomplete_calls: value.incomplete_calls,
        }
    }
}

impl From<pl_studio_runtime::UsagePurposeCountSnapshot> for BridgeUsagePurposeCountSnapshot {
    fn from(value: pl_studio_runtime::UsagePurposeCountSnapshot) -> Self {
        Self {
            purpose: value.purpose,
            calls: value.calls,
            incomplete_calls: value.incomplete_calls,
        }
    }
}

impl From<pl_studio_runtime::UsageIssueCountSnapshot> for BridgeUsageIssueCountSnapshot {
    fn from(value: pl_studio_runtime::UsageIssueCountSnapshot) -> Self {
        Self {
            issue: value.issue.into(),
            calls: value.calls,
        }
    }
}

impl From<pl_studio_runtime::ThreadUsageDiagnostics> for BridgeThreadUsageDiagnostics {
    fn from(value: pl_studio_runtime::ThreadUsageDiagnostics) -> Self {
        Self {
            incomplete_calls: value.incomplete_calls,
            missing_calls: value.missing_calls,
            partial_calls: value.partial_calls,
            invalid_calls: value.invalid_calls,
            overflow_calls: value.overflow_calls,
            by_outcome: value.by_outcome.into_iter().map(Into::into).collect(),
            by_purpose: value.by_purpose.into_iter().map(Into::into).collect(),
            other_purpose_calls: value.other_purpose_calls,
            by_issue: value.by_issue.into_iter().map(Into::into).collect(),
            recent_gaps: value.recent_gaps.into_iter().map(Into::into).collect(),
            latest_call: value.latest_call.map(Into::into),
            legacy_unknown: value.legacy_unknown,
            counts_overflowed: value.counts_overflowed,
        }
    }
}

impl From<pl_studio_runtime::UsageReport> for BridgeUsageReport {
    fn from(value: pl_studio_runtime::UsageReport) -> Self {
        Self {
            input_tokens: value.input_tokens,
            output_tokens: value.output_tokens,
            cache_read_tokens: value.cache_read_tokens,
            cache_write_tokens: value.cache_write_tokens,
            reasoning_tokens: value.reasoning_tokens,
            total_tokens: value.total_tokens,
        }
    }
}
