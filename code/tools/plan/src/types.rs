use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fmt;

pub const PLAN_CURRENT_TOOL: &str = "plan_current";
pub const PLAN_NEXT_TOOL: &str = "plan_next";
pub const PLAN_HISTORY_TOOL: &str = "plan_history";
pub const PLAN_TRANSITION_TOOL: &str = "plan_transition";

pub const MAX_PLAN_BYTES: usize = 64 * 1024;
pub const MAX_FEEDBACK_BYTES: usize = 8 * 1024;
pub const MAX_REASON_BYTES: usize = 2 * 1024;
pub const MAX_HISTORY_RECORDS: usize = 64;
pub const MAX_RECEIPT_RECORDS: usize = 32;
pub const DEFAULT_HISTORY_LIMIT: usize = 32;

/// Computes canonical lowercase `sha256:<hex>` content digest matching `pl-core`.
#[must_use]
pub fn content_hash(content: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(content)))
}

/// Closed lifecycle states of a single agent's standalone Plan state machine.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum PlanState {
    #[default]
    Drafting,
    AwaitingConfirmation,
    RevisionRequested,
    Approved,
}

impl PlanState {
    pub const ALL: [Self; 4] = [
        Self::Drafting,
        Self::AwaitingConfirmation,
        Self::RevisionRequested,
        Self::Approved,
    ];

    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Drafting => "drafting",
            Self::AwaitingConfirmation => "awaitingConfirmation",
            Self::RevisionRequested => "revisionRequested",
            Self::Approved => "approved",
        }
    }

    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Drafting => "Drafting",
            Self::AwaitingConfirmation => "Awaiting Confirmation",
            Self::RevisionRequested => "Revision Requested",
            Self::Approved => "Approved",
        }
    }
}

impl fmt::Display for PlanState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Who initiated a Plan transition.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum PlanActor {
    #[default]
    Agent,
    User,
    Host,
}

/// Versioned Markdown Plan document held by an agent's Plan object.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanDocument {
    pub revision: u64,
    pub content: String,
    pub hash: String,
    pub updated_at_ms: i64,
}

/// Declarative transition rule allowed from the current Plan state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanTransitionRule {
    pub target_state: PlanState,
    pub condition: String,
    pub requires_content: bool,
    pub requires_feedback: bool,
    pub requires_confirmation: bool,
}

/// Committed record of one Plan transition.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanTransitionRecord {
    pub seq: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub idempotency_key: Option<String>,
    pub from_state: PlanState,
    pub to_state: PlanState,
    #[serde(default)]
    pub forced: bool,
    pub actor: PlanActor,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feedback: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document_revision: Option<u64>,
    pub timestamp_ms: i64,
}

/// Bounded idempotency receipt for retry-safe transitions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanOperationReceipt {
    pub key: String,
    pub argument_hash: String,
    pub resulting_revision: u64,
}

/// Canonical persisted state of one `Plan` object.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanRecord {
    #[serde(default)]
    pub state: PlanState,
    #[serde(default)]
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document: Option<PlanDocument>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_revision_feedback: Option<String>,
    #[serde(default)]
    pub history: Vec<PlanTransitionRecord>,
    #[serde(default)]
    pub archived_transition_count: u64,
    #[serde(default)]
    pub archived_transition_digest: String,
    #[serde(default)]
    pub receipts: Vec<PlanOperationReceipt>,
    #[serde(default)]
    pub next_seq: u64,
    #[serde(default)]
    pub updated_at_ms: i64,
}

/// Public read projection returned by `plan_current` and mutation outcomes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanSnapshot {
    pub state: PlanState,
    pub revision: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document: Option<PlanDocument>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_revision_feedback: Option<String>,
    pub allowed_transitions: Vec<PlanTransitionRule>,
    pub all_states: Vec<PlanState>,
    pub updated_at_ms: i64,
}

/// Structured result returned by `plan_next`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanNextResponse {
    pub revision: u64,
    pub state: PlanState,
    pub allowed_transitions: Vec<PlanTransitionRule>,
    pub all_states: Vec<PlanState>,
}

/// Structured result returned by `plan_history`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanHistoryResponse {
    pub revision: u64,
    pub state: PlanState,
    pub history: Vec<PlanTransitionRecord>,
    pub archived_transition_count: u64,
    pub archived_transition_digest: String,
}

/// JSON arguments for `plan_transition`.
#[derive(Debug, Clone, Deserialize, Serialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlanTransitionArgs {
    /// Target Plan state (`drafting`, `awaitingConfirmation`, `revisionRequested`, `approved`).
    pub target_state: PlanState,
    /// Markdown Plan content. Required when transitioning to `awaitingConfirmation` if no plan document exists yet, or when supplying an updated plan.
    #[serde(default)]
    pub content: Option<String>,
    /// Revision feedback, required when transitioning to `revisionRequested` (unless `reason` is supplied).
    #[serde(default)]
    pub feedback: Option<String>,
    /// Concise reason explaining this state transition.
    #[serde(default)]
    pub reason: Option<String>,
    /// Bypass Plan transition graph restrictions and force jump to `targetState` (default: false).
    #[serde(default)]
    pub force: bool,
    /// Optional optimistic CAS revision returned by `plan_current`. When present, must match current revision.
    #[serde(default)]
    pub expected_revision: Option<u64>,
    /// Optional idempotency key for retry safety.
    #[serde(default)]
    pub idempotency_key: Option<String>,
}

/// JSON arguments for `plan_history`.
#[derive(Debug, Clone, Default, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct PlanHistoryArgs {
    /// Maximum number of recent transition records to return (default: 32).
    #[serde(default)]
    pub limit: Option<usize>,
}

/// Empty JSON arguments object for query tools (`plan_current`, `plan_next`).
#[derive(Debug, Clone, Default, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct PlanEmptyArgs {}

/// Host-enriched command passed directly to `Plan::transition`.
#[derive(Debug, Clone)]
pub struct PlanTransitionCommand {
    pub target_state: PlanState,
    pub content: Option<String>,
    pub feedback: Option<String>,
    pub reason: Option<String>,
    pub force: bool,
    pub expected_revision: Option<u64>,
    pub idempotency_key: Option<String>,
    pub argument_hash: Option<String>,
    pub actor: PlanActor,
    pub timestamp_ms: i64,
}

impl PlanTransitionCommand {
    #[must_use]
    pub fn from_args(args: PlanTransitionArgs, actor: PlanActor, timestamp_ms: i64) -> Self {
        let argument_hash = serde_json::to_vec(&args)
            .ok()
            .map(|bytes| content_hash(&bytes));
        Self {
            target_state: args.target_state,
            content: args.content,
            feedback: args.feedback,
            reason: args.reason,
            force: args.force,
            expected_revision: args.expected_revision,
            idempotency_key: args.idempotency_key,
            argument_hash,
            actor,
            timestamp_ms,
        }
    }
}

/// Stable machine-readable error codes for rejected Plan transitions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PlanErrorCode {
    TransitionNotAllowed,
    MissingPlanContent,
    PlanTooLarge,
    MissingFeedback,
    FeedbackTooLarge,
    ReasonTooLarge,
    StaleRevision,
    IdempotencyConflict,
}

/// Rich structured diagnostic payload returned on rejected transitions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanTransitionError {
    pub code: PlanErrorCode,
    pub message: String,
    pub current_state: PlanState,
    pub current_revision: u64,
    pub attempted_target_state: PlanState,
    pub allowed_transitions: Vec<PlanTransitionRule>,
    pub all_states: Vec<PlanState>,
    pub recovery_action: String,
}

/// Unified response returned by `plan_transition`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PlanTransitionOutcome {
    pub accepted: bool,
    pub forced: bool,
    pub replayed: bool,
    pub awaiting_confirmation: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub record: Option<PlanTransitionRecord>,
    pub snapshot: PlanSnapshot,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<PlanTransitionError>,
}
