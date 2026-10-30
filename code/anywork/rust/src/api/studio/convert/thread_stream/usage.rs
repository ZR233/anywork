use crate::api::studio::types::*;

impl From<pl_protocol::UsageReportStatus> for BridgeUsageReportStatus {
    fn from(value: pl_protocol::UsageReportStatus) -> Self {
        match value {
            pl_protocol::UsageReportStatus::LegacyUnknown => Self::LegacyUnknown,
            pl_protocol::UsageReportStatus::Missing => Self::Missing,
            pl_protocol::UsageReportStatus::Partial => Self::Partial,
            pl_protocol::UsageReportStatus::Reported => Self::Reported,
            pl_protocol::UsageReportStatus::Invalid => Self::Invalid,
        }
    }
}

impl From<pl_protocol::UsageTerminalStatus> for BridgeUsageTerminalStatus {
    fn from(value: pl_protocol::UsageTerminalStatus) -> Self {
        match value {
            pl_protocol::UsageTerminalStatus::Succeeded => Self::Succeeded,
            pl_protocol::UsageTerminalStatus::Rejected => Self::Rejected,
            pl_protocol::UsageTerminalStatus::Cancelled => Self::Cancelled,
            pl_protocol::UsageTerminalStatus::Failed => Self::Failed,
            pl_protocol::UsageTerminalStatus::Interrupted => Self::Interrupted,
        }
    }
}

impl From<pl_protocol::UsageCounterField> for BridgeUsageCounterField {
    fn from(value: pl_protocol::UsageCounterField) -> Self {
        match value {
            pl_protocol::UsageCounterField::Input => Self::Input,
            pl_protocol::UsageCounterField::Output => Self::Output,
            pl_protocol::UsageCounterField::CacheRead => Self::CacheRead,
            pl_protocol::UsageCounterField::CacheWrite => Self::CacheWrite,
            pl_protocol::UsageCounterField::Reasoning => Self::Reasoning,
            pl_protocol::UsageCounterField::Total => Self::Total,
            pl_protocol::UsageCounterField::InferenceCount => Self::InferenceCount,
            pl_protocol::UsageCounterField::CachePair => Self::CachePair,
            pl_protocol::UsageCounterField::ThroughputPair => Self::ThroughputPair,
        }
    }
}

impl From<pl_protocol::UsageGapReason> for BridgeUsageGapReason {
    fn from(value: pl_protocol::UsageGapReason) -> Self {
        match value {
            pl_protocol::UsageGapReason::Unreported => Self::Unreported,
            pl_protocol::UsageGapReason::Inconsistent => Self::Inconsistent,
            pl_protocol::UsageGapReason::Overflow => Self::Overflow,
        }
    }
}

impl From<pl_protocol::MetricAvailability> for BridgeMetricAvailability {
    fn from(value: pl_protocol::MetricAvailability) -> Self {
        match value {
            pl_protocol::MetricAvailability::Available => Self::Available,
            pl_protocol::MetricAvailability::NotCollected => Self::NotCollected,
            pl_protocol::MetricAvailability::NoVisibleOutput => Self::NoVisibleOutput,
            pl_protocol::MetricAvailability::MissingOutput => Self::MissingOutput,
            pl_protocol::MetricAvailability::ZeroOutput => Self::ZeroOutput,
            pl_protocol::MetricAvailability::InvalidUsage => Self::InvalidUsage,
            pl_protocol::MetricAvailability::InvalidTiming => Self::InvalidTiming,
            pl_protocol::MetricAvailability::LegacyUnknown => Self::LegacyUnknown,
        }
    }
}

impl From<pl_protocol::FirstOutputSource> for BridgeFirstOutputSource {
    fn from(value: pl_protocol::FirstOutputSource) -> Self {
        match value {
            pl_protocol::FirstOutputSource::Unobserved => Self::Unobserved,
            pl_protocol::FirstOutputSource::Incremental => Self::Incremental,
            pl_protocol::FirstOutputSource::CompletedToolInput => Self::CompletedToolInput,
            pl_protocol::FirstOutputSource::LegacyUnknown => Self::LegacyUnknown,
        }
    }
}

impl From<pl_protocol::UsageGapIssue> for BridgeUsageGapIssue {
    fn from(value: pl_protocol::UsageGapIssue) -> Self {
        Self {
            field: value.field.into(),
            reason: value.reason.into(),
        }
    }
}

impl From<pl_protocol::UsageCallSnapshot> for BridgeUsageCallSnapshot {
    fn from(value: pl_protocol::UsageCallSnapshot) -> Self {
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

impl From<pl_protocol::UsageOutcomeCountSnapshot> for BridgeUsageOutcomeCountSnapshot {
    fn from(value: pl_protocol::UsageOutcomeCountSnapshot) -> Self {
        Self {
            outcome: value.outcome.into(),
            calls: value.calls,
            incomplete_calls: value.incomplete_calls,
        }
    }
}

impl From<pl_protocol::UsagePurposeCountSnapshot> for BridgeUsagePurposeCountSnapshot {
    fn from(value: pl_protocol::UsagePurposeCountSnapshot) -> Self {
        Self {
            purpose: value.purpose,
            calls: value.calls,
            incomplete_calls: value.incomplete_calls,
        }
    }
}

impl From<pl_protocol::UsageIssueCountSnapshot> for BridgeUsageIssueCountSnapshot {
    fn from(value: pl_protocol::UsageIssueCountSnapshot) -> Self {
        Self {
            issue: value.issue.into(),
            calls: value.calls,
        }
    }
}

impl From<pl_protocol::ThreadUsageDiagnostics> for BridgeThreadUsageDiagnostics {
    fn from(value: pl_protocol::ThreadUsageDiagnostics) -> Self {
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

impl From<pl_protocol::UsageReport> for BridgeUsageReport {
    fn from(value: pl_protocol::UsageReport) -> Self {
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
