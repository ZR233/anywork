//! Typed diagnostic projections. Rules and cumulative arithmetic belong to core, not this wire.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageReportStatus {
    LegacyUnknown,
    Missing,
    Partial,
    Reported,
    Invalid,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageTerminalStatus {
    Succeeded,
    Rejected,
    Cancelled,
    Failed,
    Interrupted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageCounterField {
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
pub enum UsageGapReason {
    Unreported,
    Inconsistent,
    Overflow,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageGapIssue {
    pub field: UsageCounterField,
    pub reason: UsageGapReason,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageCallSnapshot {
    pub thread_id: String,
    pub call_id: String,
    pub turn_id: Option<String>,
    pub effect_sequence: u64,
    pub observed_at: i64,
    pub purpose: Option<String>,
    pub outcome: UsageTerminalStatus,
    pub status: UsageReportStatus,
    pub usage: crate::UsageReport,
    pub issues: Vec<UsageGapIssue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageOutcomeCountSnapshot {
    pub outcome: UsageTerminalStatus,
    pub calls: u64,
    pub incomplete_calls: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsagePurposeCountSnapshot {
    pub purpose: Option<String>,
    pub calls: u64,
    pub incomplete_calls: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageIssueCountSnapshot {
    pub issue: UsageGapIssue,
    pub calls: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadUsageDiagnostics {
    pub incomplete_calls: u64,
    pub missing_calls: u64,
    pub partial_calls: u64,
    pub invalid_calls: u64,
    pub overflow_calls: u64,
    pub by_outcome: Vec<UsageOutcomeCountSnapshot>,
    pub by_purpose: Vec<UsagePurposeCountSnapshot>,
    pub other_purpose_calls: u64,
    pub by_issue: Vec<UsageIssueCountSnapshot>,
    pub recent_gaps: Vec<UsageCallSnapshot>,
    pub latest_call: Option<UsageCallSnapshot>,
    pub legacy_unknown: bool,
    pub counts_overflowed: bool,
}

/// Why an individual performance metric can or cannot be displayed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MetricAvailability {
    Available,
    NotCollected,
    NoVisibleOutput,
    MissingOutput,
    ZeroOutput,
    InvalidUsage,
    InvalidTiming,
    LegacyUnknown,
}
