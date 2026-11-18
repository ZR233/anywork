//! Versioned DTOs and shared formatting/path validation for `run_export`.

use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::{ChatContentRole, InferenceBillingRecord, TurnFailure};
use anyhow::{Result, ensure};
use pl_core::thread::UsageSummary;
use pl_tool::skill::{SkillDiscoverySourceSummary, SkillWinnerSummary};
use serde::{Deserialize, Serialize};

use crate::StudioShutdownReport;
use crate::history::{
    HistoryBodyRole, HistoryCut, HistoryEntityHead, HistoryEventBodyRef, HistoryEventHeader,
};

/// Schema version for `run.json`.
pub const RUN_MANIFEST_SCHEMA_VERSION: u32 = 3;
/// Schema version for `events.jsonl`.
pub const EVENTS_SCHEMA_VERSION: u32 = 3;
/// Schema version for `result.json`.
pub const RESULT_SCHEMA_VERSION: u32 = 3;

/// Bound constants for the exporter bounded admission queue and content streaming.
pub const MAX_QUEUED_BATCHES: usize = 256;
pub const MAX_QUEUED_METADATA_BYTES: usize = 16 * 1024 * 1024;
pub const CONTENT_EXPORT_CHUNK_BYTES: u32 = 64 * 1024;

/// Host configuration enabling atomic run artifact export.
#[derive(Debug, Clone)]
pub struct RunExportOptions {
    pub output_dir: PathBuf,
    pub run_id: String,
    pub cwd: PathBuf,
    pub studio_home: PathBuf,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
    pub reasoning_effort: Option<String>,
    pub mode: Option<String>,
    pub max_model_steps: Option<u32>,
    pub prompt_sha256: String,
    pub skill_search: pl_tool::skill::SkillSearchOptions,
    pub config: Option<crate::config::StudioConfig>,
}

/// Exporter build metadata recorded in `run.json`, `runStarted`, and `result.json`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BuildInfoV3 {
    pub version: String,
    pub git_commit: Option<String>,
    pub target: String,
}

impl BuildInfoV3 {
    /// Captures the compile-time build identity without running `git` at runtime.
    pub fn current() -> Self {
        let version = pl_studio_update::STUDIO_VERSION.trim().to_string();
        let git_commit = option_env!("PL_GIT_COMMIT")
            .map(str::trim)
            .filter(|commit| !commit.is_empty())
            .map(str::to_owned);
        let target = option_env!("PL_BUILD_TARGET")
            .filter(|target| !target.is_empty())
            .unwrap_or("unknown")
            .to_string();
        Self {
            version,
            git_commit,
            target,
        }
    }
}

/// Formats `SystemTime` as a canonical UTC RFC3339 string with millisecond precision.
pub fn format_utc_rfc3339(time: SystemTime) -> String {
    let since_epoch = time
        .duration_since(UNIX_EPOCH)
        .unwrap_or(std::time::Duration::ZERO);
    let total_secs = since_epoch.as_secs() as i64;
    let millis = since_epoch.subsec_millis();
    let days = total_secs.div_euclid(86_400);
    let secs_of_day = total_secs.rem_euclid(86_400);
    let hour = secs_of_day / 3_600;
    let minute = (secs_of_day % 3_600) / 60;
    let second = secs_of_day % 60;
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z")
}

/// Howard Hinnant's civil-from-days conversion (days since 1970-01-01).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = y + i64::from(m <= 2);
    (year, m as u32, d as u32)
}

/// Validates that an artifact-relative path stays strictly within `<output-dir>`.
pub fn validate_export_relative_path(path: &str) -> Result<()> {
    ensure!(!path.is_empty(), "export relative path must not be empty");
    ensure!(
        !path.starts_with('/') && !path.starts_with('\\'),
        "export relative path must not be absolute: {path}"
    );
    ensure!(
        !path.contains('\\'),
        "export relative path must use forward slashes: {path}"
    );
    ensure!(
        path.split('/')
            .all(|segment| !segment.is_empty() && segment != "." && segment != ".."),
        "export relative path contains traversal or empty segment: {path}"
    );
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExportSchemaV3 {
    pub manifest: u32,
    pub events: u32,
    pub result: u32,
    pub content_addressing: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunInvocationV3 {
    pub cwd: String,
    pub studio_home: String,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
    pub reasoning_effort: Option<String>,
    pub mode: Option<String>,
    pub max_model_steps: Option<u32>,
    pub prompt_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillSearchManifestV3 {
    pub include_default_user_dir: bool,
    pub additional_dirs: Vec<String>,
    pub external_dirs: Vec<String>,
    pub system_enabled: bool,
    pub skills_enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigInputEntryV3 {
    pub logical_name: String,
    pub present: bool,
    pub sha256: Option<String>,
    pub redacted_summary: Option<serde_json::Value>,
}

/// Immutable startup manifest written atomically to `<output-dir>/run.json` before runtime init.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunManifestV3 {
    pub schema_version: u32,
    pub run_id: String,
    pub started_at: String,
    pub build: BuildInfoV3,
    pub invocation: RunInvocationV3,
    pub skill_search: SkillSearchManifestV3,
    pub config_inputs: Vec<ConfigInputEntryV3>,
    pub export_schema: ExportSchemaV3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ResultOutcome {
    Completed,
    InvalidInput,
    BlockedOnInput,
    BudgetExceeded,
    Failed,
    StartupFailed,
    ExportFailed,
    ShutdownFailed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ExecutionOutcome {
    Completed,
    BlockedOnInput,
    BudgetExceeded,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ExecutionErrorStage {
    Preflight,
    Startup,
    Turn,
    Export,
    Shutdown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecutionErrorV3 {
    pub stage: ExecutionErrorStage,
    pub code: String,
    pub message: String,
    pub turn_failure: Option<TurnFailure>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimingReportV3 {
    pub total_wall_ms: u64,
    pub initialize_wall_ms: Option<u64>,
    pub agent_wall_ms: Option<u64>,
    pub shutdown_wall_ms: Option<u64>,
    pub export_finalize_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TraceSummaryV3 {
    pub events_path: String,
    pub events_sha256: Option<String>,
    pub event_count: u64,
    pub last_event_seq: Option<u64>,
    pub sealed: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageCoverage {
    Complete,
    Partial,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UsageMetricKey {
    InferenceCount,
    InputTokens,
    OutputTokens,
    CacheReadTokens,
    CacheWriteTokens,
    ReasoningTokens,
    TotalTokens,
    EstimatedCostUsd,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UsageTotalsV3 {
    pub inference_count: Option<u64>,
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub cache_read_tokens: Option<u64>,
    pub cache_write_tokens: Option<u64>,
    pub reasoning_tokens: Option<u64>,
    pub total_tokens: Option<u64>,
    pub estimated_cost_usd: Option<f64>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UsageKnownTotalsV3 {
    pub inference_count: u64,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub total_tokens: u64,
    pub estimated_cost_usd: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelUsageExportV3 {
    pub account_id: Option<String>,
    pub model_id: Option<String>,
    pub coverage: UsageCoverage,
    pub has_unknown_values: bool,
    pub totals: UsageTotalsV3,
    pub known_totals: UsageKnownTotalsV3,
    pub unknown_fields: Vec<UsageMetricKey>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadUsageExportV3 {
    pub thread_id: String,
    pub through_effect_seq: u64,
    pub summary: UsageSummary,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UsageExportV3 {
    pub coverage: UsageCoverage,
    pub has_unknown_values: bool,
    pub totals: UsageTotalsV3,
    pub known_totals: UsageKnownTotalsV3,
    pub by_model: Vec<ModelUsageExportV3>,
    pub by_thread: Vec<ThreadUsageExportV3>,
}

/// Terminal result file written atomically to `<output-dir>/result.json`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ResultV3 {
    pub schema_version: u32,
    pub run_id: String,
    pub root_thread_id: Option<String>,
    pub outcome: ResultOutcome,
    pub execution_outcome: Option<ExecutionOutcome>,
    pub exit_code: i32,
    pub started_at: String,
    pub finished_at: String,
    pub build: BuildInfoV3,
    pub timing: TimingReportV3,
    pub final_text: Option<String>,
    pub trace_complete: bool,
    pub usage_complete: bool,
    pub cost_complete: bool,
    pub trace: TraceSummaryV3,
    pub usage: Option<UsageExportV3>,
    pub shutdown: StudioShutdownReport,
    pub error: Option<ExecutionErrorV3>,
    pub execution_error: Option<ExecutionErrorV3>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EventSourceV3 {
    pub history_event_id: Option<String>,
    pub history_event_seq: Option<u64>,
    pub effect_seq: Option<u64>,
    pub turn_id: Option<String>,
    pub attempt_id: Option<String>,
    pub tool_call_id: Option<String>,
    pub current_owner_id: Option<String>,
    pub current_revision: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CompletionCursorV3 {
    pub cut: HistoryCut,
    pub history_seq: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatItemHeaderExportV3 {
    pub event: HistoryEventHeader,
}

impl ChatItemHeaderExportV3 {
    pub fn from_history(header: &HistoryEventHeader) -> Self {
        Self {
            event: header.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExportedBlobV3 {
    pub path: String,
    pub byte_length: u64,
    pub sha256: String,
    pub media_type: Option<String>,
    pub encoding: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExportedContentV3 {
    pub native_ref: HistoryEventBodyRef,
    pub role: Option<ChatContentRole>,
    pub history_role: HistoryBodyRole,
    pub path: String,
    pub byte_length: u64,
    pub sha256: String,
    pub media_type: Option<String>,
    pub encoding: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SealedMemberCutV3 {
    pub thread_id: String,
    pub agent_id: String,
    pub parent_agent_id: Option<String>,
    pub role: Option<String>,
    pub through_effect_seq: u64,
    pub history_cut: CompletionCursorV3,
    pub aborted: bool,
    pub sealed: bool,
}

/// One canonical History change projected into bounded export metadata.
///
/// The full `HistoryEvent` and its bodies stay in the writer transaction. The export queue retains
/// only this accepted identity, time, kind, and typed head.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecutionLifecycleExportV3 {
    pub event_id: String,
    pub event_kind: crate::history::HistoryEventKind,
    pub occurred_at: Option<i64>,
    pub recorded_at: i64,
    pub head: HistoryEntityHead,
}
impl From<&crate::history::HistoryEntityChange> for ExecutionLifecycleExportV3 {
    fn from(value: &crate::history::HistoryEntityChange) -> Self {
        Self {
            event_id: value.event.header.event_id.clone(),
            event_kind: value.event.header.kind.clone(),
            occurred_at: value.event.header.occurred_at,
            recorded_at: value.event.header.recorded_at,
            head: value.entity.clone(),
        }
    }
}
pub(super) fn handoff_fingerprint(
    accounting: &crate::studio::thread_projection::PreparedAccounting,
    lifecycle: &[ExecutionLifecycleExportV3],
) -> String {
    crate::hash::canonical_json_hash(&serde_json::json!([
        accounting.export_fingerprint(),
        lifecycle
    ]))
}

/// Typed `EventV3` payload variants (`type` + `data`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "type",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum EventBodyV3 {
    RunStarted {
        run_id: String,
        build: BuildInfoV3,
        manifest_sha256: String,
    },
    AgentRegistered {
        agent_id: String,
        thread_id: String,
        parent_agent_id: Option<String>,
        parent_thread_id: Option<String>,
        role: Option<String>,
        workspace_id: String,
        spawn_tool_call_id: Option<String>,
        initial_effect_seq: u64,
        initial_history_cursor: CompletionCursorV3,
    },
    SkillsDiscovered {
        thread_id: String,
        source_fingerprint: String,
        sources: Vec<SkillDiscoverySourceSummary>,
        winners: Vec<SkillWinnerSummary>,
        warnings: Vec<String>,
        complete: bool,
    },
    InferenceFinished {
        status: String,
        auxiliary: bool,
        billing: Box<InferenceBillingRecord>,
    },
    ExecutionLifecycle {
        facts: Vec<ExecutionLifecycleExportV3>,
    },
    Completion {
        header: Box<ChatItemHeaderExportV3>,
        atom: Box<HistoryEntityHead>,
        payload: ExportedBlobV3,
        contents_manifest: ExportedBlobV3,
    },
    ThreadSealed {
        thread_id: String,
        through_effect_seq: u64,
        history_cut: CompletionCursorV3,
        summary: Box<UsageSummary>,
        status: Option<String>,
        aborted: bool,
        error: Option<String>,
    },
    RunSealed {
        members: Vec<SealedMemberCutV3>,
        reconciled: bool,
        reconcile_error: Option<String>,
        trace_complete: bool,
        usage_complete: bool,
        cost_complete: bool,
    },
}

/// One JSONL record written to `<output-dir>/events.jsonl`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EventV3 {
    pub schema_version: u32,
    pub run_id: String,
    pub event_seq: u64,
    #[serde(flatten)]
    pub body: EventBodyV3,
    pub emitted_at: String,
    pub thread_id: Option<String>,
    pub source: EventSourceV3,
}

/// Final exporter report isolated from native `StudioShutdownReport`.
#[derive(Debug, Clone)]
pub struct RunExportReport {
    pub run_id: String,
    pub started_at: String,
    pub manifest_sha256: String,
    pub root_thread_id: Option<String>,
    pub trace_complete: bool,
    pub usage_complete: bool,
    pub cost_complete: bool,
    pub trace: TraceSummaryV3,
    pub usage: Option<UsageExportV3>,
    pub export_finalize_ms: Option<u64>,
    pub failure: Option<ExecutionErrorV3>,
}
