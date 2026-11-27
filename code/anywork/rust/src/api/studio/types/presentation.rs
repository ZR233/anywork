//! FRB DTOs for the Native conversation feed and shared thread snapshot references.

use serde::Deserialize;

use super::{
    BridgeInteractionRequest, BridgePlanRuntimeSnapshot, BridgeRuntimeCostAmount,
    BridgeThreadActivity, BridgeThreadModelRouteSnapshot, BridgeThreadRuntimeSnapshot,
    BridgeThreadRuntimeUsage, BridgeThreadStatus, BridgeThreadStorageState, BridgeTurn,
    BridgeTurnFailureDto, BridgeUsageGapIssue, BridgeUsageIssueCountSnapshot,
    BridgeUsageOutcomeCountSnapshot, BridgeUsagePurposeCountSnapshot, BridgeUsageReport,
    BridgeUsageReportStatus, BridgeUsageTerminalStatus,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentContentRef {
    pub owner_id: String,
    pub domain: String,
    pub entity_id: String,
    pub content_key: String,
    pub generation: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeCurrentStateField {
    Body {
        field: String,
        reference: BridgeCurrentContentRef,
        byte_length: u64,
    },
    Collection {
        field: String,
        reference: BridgeCurrentCollectionRef,
        count: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCurrentCollectionRef {
    pub owner_id: String,
    pub collection: String,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeModelRecoveryPhase {
    Repairing,
    Waiting,
    Retrying,
    Recovered,
    Exhausted,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelRecoveryNotice {
    pub failure_kind: Option<String>,
    pub reason: Option<String>,
    pub retry_count: u32,
    pub max_retries: u32,
    pub effective_wait_millis: Option<u64>,
    pub phase: BridgeModelRecoveryPhase,
    pub failure: Option<BridgeTurnFailureDto>,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct BridgeBodyRef {
    pub database_id: String,
    pub body_id: String,
    pub owner_event_id: String,
    pub body_key: String,
    pub role: String,
    pub byte_length: u64,
    pub media_type: Option<String>,
    pub inline_text: Option<String>,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct BridgeBodyWindow {
    pub offset: u64,
    pub text: Option<String>,
    pub bytes_base64: Option<String>,
    pub total_bytes: u64,
    pub eof: bool,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum BridgeSessionDetailKind {
    Plan,
    Interactions,
    Todo,
    Workflow,
    ActiveSkills,
    ActiveMcpServers,
    ActiveLspServers,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct BridgeSessionDetailWindow {
    pub owner_epoch: String,
    pub revision: u64,
    pub offset: u64,
    pub total_bytes: u64,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum BridgeWorkGroupStatus {
    Active,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelineItem {
    UserMessage {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        input_id: Option<String>,
        channel: String,
        text: String,
        attachments_json: String,
        occurred_at_ms: Option<i64>,
    },
    AssistantText {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        attempt_id: Option<String>,
        channel: String,
        text: String,
        body_ref: Option<BridgeBodyRef>,
        is_final_turn_delivery: bool,
        outcome: String,
        model_recovery: Option<Box<BridgeModelRecoveryNotice>>,
        occurred_at_ms: Option<i64>,
    },
    WorkGroup {
        id: String,
        first_seq: u64,
        last_seq: u64,
        after_boundary_seq: Option<u64>,
        before_boundary_seq: Option<u64>,
        member_count: u32,
        summary: String,
        status: BridgeWorkGroupStatus,
        started_at_ms: Option<i64>,
        finished_at_ms: Option<i64>,
    },
    Compaction {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        summary: String,
        outcome: String,
        tokens_before: Option<u64>,
        tokens_after: Option<u64>,
        occurred_at_ms: Option<i64>,
    },
    PlanResolution {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        decision: String,
        document: Option<String>,
        document_ref: Option<BridgeBodyRef>,
        feedback: Option<String>,
        occurred_at_ms: Option<i64>,
    },
    ConnectionNotice {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        scope: String,
        state: String,
        transport: String,
        fallback_transport: Option<String>,
        attempt: u32,
        max_attempts: u32,
        recoverable: bool,
        reason: Option<String>,
        duration_ms: Option<u64>,
        occurred_at_ms: Option<i64>,
    },
    TurnOutcome {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        input_id: Option<String>,
        outcome: String,
        message: Option<String>,
        turn_failure: Option<Box<BridgeTurnFailureDto>>,
        occurred_at_ms: Option<i64>,
    },
    StandaloneTool {
        id: String,
        seq: u64,
        turn_id: Option<String>,
        call_id: String,
        tool_name: String,
        presentation_contract: Option<String>,
        state: String,
        summary: String,
        payload_json: String,
        bodies: Vec<BridgeBodyRef>,
        occurred_at_ms: Option<i64>,
    },
    Fallback {
        id: String,
        seq: u64,
        event_id: String,
        event_kind: String,
        reason: String,
        raw_preview: Option<String>,
        occurred_at_ms: Option<i64>,
    },
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum BridgeWorkGroupMember {
    Reasoning {
        id: String,
        seq: u64,
        text: String,
        summary: String,
        body_ref: Option<BridgeBodyRef>,
        outcome: String,
        started_at_ms: Option<i64>,
        finished_at_ms: Option<i64>,
    },
    ToolCall {
        id: String,
        seq: u64,
        call_id: String,
        turn_id: Option<String>,
        tool_name: String,
        presentation_contract: Option<String>,
        status: String,
        summary: String,
        arguments: Option<String>,
        result_preview: Option<String>,
        payload_json: String,
        bodies: Vec<BridgeBodyRef>,
        wait_json: Option<String>,
        started_at_ms: Option<i64>,
        finished_at_ms: Option<i64>,
    },
    Agent {
        id: String,
        seq: u64,
        agent_id: String,
        name: String,
        status: String,
        summary: String,
        payload_json: String,
        started_at_ms: Option<i64>,
        finished_at_ms: Option<i64>,
    },
    FileChange {
        id: String,
        seq: u64,
        summary: String,
        payload_json: String,
        bodies: Vec<BridgeBodyRef>,
        occurred_at_ms: Option<i64>,
    },
    Skill {
        id: String,
        seq: u64,
        name: String,
        summary: String,
        payload_json: String,
        occurred_at_ms: Option<i64>,
    },
    Fallback {
        id: String,
        seq: u64,
        event_id: String,
        event_kind: String,
        reason: String,
        occurred_at_ms: Option<i64>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelinePatch {
    Reset {
        items: Vec<BridgeTimelineItem>,
        has_more_older: bool,
        older_cursor: Option<String>,
        revision: u64,
    },
    PrependOlder {
        items: Vec<BridgeTimelineItem>,
        has_more_older: bool,
        older_cursor: Option<String>,
    },
    Append {
        items: Vec<BridgeTimelineItem>,
    },
    Update {
        item: Box<BridgeTimelineItem>,
    },
    Remove {
        item_id: String,
    },
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct BridgeLiveAttention {
    pub id: String,
    pub kind: String,
    pub summary: String,
    pub call_id: Option<String>,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum BridgeLiveStatusPhase {
    Idle,
    Working {
        items: Vec<BridgeWorkGroupMember>,
        reasoning_preview: Option<String>,
        started_at_ms: Option<i64>,
    },
    StreamingText {
        attempt_id: String,
        item_id: String,
        text: String,
        started_at_ms: Option<i64>,
    },
    Compacting {
        manual: bool,
        started_at_ms: Option<i64>,
    },
    Reconnecting {
        attempt_id: String,
        message: String,
        retry_after_ms: Option<u64>,
        attempt: u32,
        max_attempts: u32,
    },
    Stopping {
        started_at_ms: Option<i64>,
    },
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct BridgeLiveStatusSnapshot {
    pub revision: u64,
    pub phase: BridgeLiveStatusPhase,
    pub attentions: Vec<BridgeLiveAttention>,
    pub suppressed_by_interaction: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeUsageSummary {
    pub applied_sequence: u64,
    pub binding: Option<BridgeUsageBinding>,
    pub totals: BridgeUsageTotals,
    pub cache: BridgeUsageCacheSummary,
    pub context: BridgeUsageContextSummary,
    pub throughput: BridgeUsageThroughputSummary,
    pub diagnostics: BridgeUsageDiagnostics,
    pub pricing: BridgeUsagePricingSummary,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUsageBinding {
    pub route_identity: Option<String>,
    pub model: String,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub auto_compact_limit: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUsageTotals {
    pub inference_count: u64,
    pub prompt_tokens: u64,
    pub completion_tokens: u64,
    pub cached_prompt_tokens: u64,
    pub cache_write_tokens: u64,
    pub reasoning_tokens: u64,
    pub total_tokens: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUsageCacheSummary {
    pub input_tokens: u64,
    pub read_tokens: u64,
    pub sample_count: u64,
    pub incomplete: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeUsageContextSummary {
    pub tokens: u64,
    pub latest_call: Option<BridgeUsageObservation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUsageThroughputSummary {
    pub turn_id: String,
    pub completion_tokens: u64,
    pub response_millis: u64,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeUsageDiagnostics {
    pub incomplete_calls: u64,
    pub missing_calls: u64,
    pub partial_calls: u64,
    pub invalid_calls: u64,
    pub overflow_calls: u64,
    pub by_outcome: Vec<BridgeUsageOutcomeCountSnapshot>,
    pub by_purpose: Vec<BridgeUsagePurposeCountSnapshot>,
    pub other_purpose_calls: u64,
    pub by_issue: Vec<BridgeUsageIssueCountSnapshot>,
    pub recent_gaps: Vec<BridgeUsageObservation>,
    pub legacy_unknown: bool,
    pub legacy_incomplete: bool,
    pub counts_overflowed: bool,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeUsageObservation {
    pub source: BridgeUsageSource,
    pub status: BridgeUsageReportStatus,
    pub usage: BridgeUsageReport,
    pub issues: Vec<BridgeUsageGapIssue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeUsageSource {
    pub thread_id: String,
    pub call_id: String,
    pub turn_id: Option<String>,
    pub effect_sequence: u64,
    pub observed_at: i64,
    pub purpose: Option<String>,
    pub outcome: BridgeUsageTerminalStatus,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeUsagePricingSummary {
    pub incomplete: bool,
    pub estimated_costs: Vec<BridgeRuntimeCostAmount>,
    pub estimated_cache_savings: Vec<BridgeRuntimeCostAmount>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeSessionMetaSnapshot {
    pub thread_id: String,
    pub status: BridgeThreadStatus,
    pub title: Option<String>,
    pub parent_thread_id: Option<String>,
    pub root_thread_id: String,
    pub owner_epoch: String,
    pub revision: u64,
    pub active_turn: Option<BridgeTurn>,
    pub last_turn: Option<BridgeTurn>,
    pub activity: Option<BridgeThreadActivity>,
    pub usage: BridgeUsageSummary,
    pub context_metrics: Option<BridgeThreadRuntimeUsage>,
    pub model_route: Option<BridgeThreadModelRouteSnapshot>,
    pub runtime: Option<BridgeThreadRuntimeSnapshot>,
    pub storage_state: Option<BridgeThreadStorageState>,
    pub interactions: Vec<BridgeInteractionRequest>,
    pub pending_interaction_count: u32,
    pub plan: Option<BridgePlanRuntimeSnapshot>,
    pub mode: Option<String>,
    pub execution_present: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeConversationEvent {
    Timeline {
        patch: BridgeTimelinePatch,
    },
    LiveStatus {
        snapshot: BridgeLiveStatusSnapshot,
    },
    SessionMeta {
        snapshot: Box<BridgeSessionMetaSnapshot>,
    },
    InputPresented {
        input_id: String,
        item_id: String,
    },
    ResyncRequired {
        reason: String,
    },
}
