//! Minimal consumer DTOs for the real Responses/tool/report wire. Unknown
//! producer fields remain ignored, but every field used for a decision is typed
//! and required. A tool acceptance acknowledgement is never a terminal report.

use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::Value;

#[derive(Debug, Deserialize)]
pub(super) struct Request {
    pub model: String,
    pub input: Vec<Item>,
    #[serde(default)]
    pub tools: Vec<Function>,
    pub tool_choice: Option<Value>,
    pub reasoning: Option<Reasoning>,
}

#[derive(Debug, Deserialize)]
pub(super) struct Reasoning {
    pub effort: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct CompletionExpectation {
    pub model_id: String,
    pub endpoint_alias: String,
    pub account_id: Option<String>,
    pub effort: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<ContinuationTag>,
}

/// Scenario-owned input correlation, never a Runtime message/Turn identity or permission.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ContinuationTag {
    pub target_agent_id: String,
    pub intent: String,
}

#[derive(Debug, Deserialize)]
pub(super) struct Function {
    pub name: Option<String>,
    pub function: Option<Box<Function>>,
}

impl Function {
    pub fn name(&self) -> Option<&str> {
        self.name
            .as_deref()
            .or_else(|| self.function.as_ref()?.name())
    }
}

#[derive(Debug, Deserialize)]
pub(super) struct Item {
    #[serde(rename = "type", default)]
    pub kind: String,
    pub role: Option<String>,
    pub content: Option<Text>,
    pub call_id: Option<String>,
    pub name: Option<String>,
    pub output: Option<Text>,
    pub arguments: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub(super) enum Text {
    Plain(String),
    Parts(Vec<TextPart>),
}

#[derive(Debug, Deserialize)]
pub(super) struct TextPart {
    pub text: Option<String>,
}

impl Text {
    pub fn joined(&self) -> String {
        match self {
            Self::Plain(text) => text.clone(),
            Self::Parts(parts) => parts
                .iter()
                .filter_map(|part| part.text.as_deref())
                .collect::<Vec<_>>()
                .join("\n"),
        }
    }
}

impl Request {
    /// The leading trusted instruction text as it appears on the wire: the first input message
    /// (`developer` or `system` depending on the vendor). There is no legacy top-level
    /// `instructions` fallback; the fixture rejects that shape in the request handler.
    pub fn system_instructions(&self) -> String {
        self.input
            .first()
            .filter(|item| matches!(item.role.as_deref(), Some("developer") | Some("system")))
            .and_then(|item| item.content.as_ref())
            .map(Text::joined)
            .unwrap_or_default()
    }

    pub fn expected_completion(&self) -> Result<Option<CompletionExpectation>> {
        let Ok((_, prompt)) = self.prompt() else {
            return Ok(None);
        };
        prompt
            .lines()
            .find_map(|line| line.strip_prefix("DELEGATION_EXPECT_COMPLETION:"))
            .map(|text| {
                serde_json::from_str(text).context("decode scenario completion expectation")
            })
            .transpose()
    }
    pub fn declared(&self, name: &str) -> bool {
        self.tools.iter().any(|tool| tool.name() == Some(name))
    }

    pub fn is_title(&self) -> bool {
        self.system_instructions()
            .contains("You name coding sessions from untrusted request data")
            && self.tools.is_empty()
            && self.tool_choice.as_ref().and_then(Value::as_str) == Some("none")
    }

    pub fn reports(&self) -> Result<Vec<Report>> {
        let reports: Vec<Report> = self
            .input
            .iter()
            .filter(|item| item.role.as_deref() == Some("user"))
            .filter_map(|item| item.content.as_ref().map(Text::joined))
            .filter(|text| {
                text.trim_start().starts_with('{')
                    && text.contains("\"childId\"")
                    && text.contains("\"commitSequence\"")
            })
            .map(|text| {
                serde_json::from_str(&text).context("decode complete production terminal report")
            })
            .collect::<Result<_>>()?;
        let mut identities = std::collections::BTreeSet::new();
        for report in &reports {
            report.validate_identity()?;
        }
        ensure!(
            reports
                .iter()
                .all(|report| identities.insert((&report.child_id, &report.turn.turn_id))),
            "the same child terminal Turn report was delivered more than once"
        );
        Ok(reports)
    }

    /// Only exact authored scenario markers start a new request window. Reports,
    /// host facts and task notices cannot replace the parent's original input.
    pub fn prompt(&self) -> Result<(usize, String)> {
        self.input
            .iter()
            .enumerate()
            .rev()
            .filter(|(_, item)| item.role.as_deref() == Some("user"))
            .filter_map(|(index, item)| Some((index, item.content.as_ref()?.joined())))
            .find(|(_, text)| text.trim_start().starts_with("[[delegation:"))
            .context("request has no authored delegation marker")
    }

    pub fn output(&self, id: &str) -> Result<Option<String>> {
        let calls = self
            .input
            .iter()
            .filter(|item| item.kind == "function_call" && item.call_id.as_deref() == Some(id))
            .count();
        let outputs: Vec<_> = self
            .input
            .iter()
            .filter(|item| {
                item.kind == "function_call_output" && item.call_id.as_deref() == Some(id)
            })
            .collect();
        ensure!(
            calls <= 1 && outputs.len() <= 1,
            "duplicate call/output identity {id}"
        );
        if let Some(output) = outputs.first() {
            ensure!(calls == 1, "orphan tool output {id}");
            return Ok(Some(
                output
                    .output
                    .as_ref()
                    .context("tool output missing text")?
                    .joined(),
            ));
        }
        Ok(None)
    }
}

pub(super) fn decode<T: DeserializeOwned>(text: &str) -> Result<T> {
    ensure!(
        !text.contains("Framework recorded tool failure:"),
        "production tool failed: {text}"
    );
    serde_json::from_str(text)
        .context("tool did not return its required typed result (an ACK is not completion)")
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct DiscoveredTools {
    pub tool_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Route {
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Spawn {
    pub agent_id: String,
    pub profile_id: String,
    pub model: Route,
    pub message_accepted: bool,
    pub message_sequence: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Report {
    pub child_id: String,
    pub commit_sequence: u64,
    pub turn: Turn,
    pub message: String,
    pub messages: Vec<MessageIdentity>,
    pub running_tasks: Vec<String>,
    pub pending_interactions: Vec<String>,
    pub permissions: Vec<Permission>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Turn {
    pub input_id: Option<String>,
    pub turn_id: String,
    pub state: TurnState,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub(super) enum TurnState {
    Running,
    Finished(String),
    Cancelled,
    Interrupted,
    Failed(Value),
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct MessageIdentity {
    pub id: String,
    pub source_id: String,
    pub sequence: u64,
    pub consumed: bool,
}

#[derive(Debug, Deserialize)]
pub(super) struct Permission {
    pub state: PermissionState,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) enum PermissionState {
    Pending,
    Allowed,
    Denied,
    Cancelled,
}

impl Report {
    fn validate_identity(&self) -> Result<()> {
        ensure!(
            !self.child_id.trim().is_empty()
                && self.commit_sequence > 0
                && !self.turn.turn_id.trim().is_empty(),
            "terminal report lacks committed child/Turn identity"
        );
        // A message-triggered Turn has no chat inputId. Never infer an input
        // identity by parsing the opaque turnId or the send receipt's messageId.
        ensure!(
            self.turn
                .input_id
                .as_ref()
                .is_none_or(|id| !id.trim().is_empty()),
            "terminal report has an invalid optional chat input identity"
        );
        Ok(())
    }

    pub fn completed(&self) -> Result<()> {
        self.validate_identity()?;
        let outcome = match &self.turn.state {
            TurnState::Finished(value) => value.as_str(),
            TurnState::Failed(failure) => anyhow::bail!("child failed: {failure}"),
            _ => anyhow::bail!("child is not a completed delivery: {:?}", self.turn.state),
        };
        ensure!(
            outcome == "completed",
            "child stopped without completing: {outcome}"
        );
        ensure!(
            self.running_tasks.is_empty()
                && self.pending_interactions.is_empty()
                && self
                    .permissions
                    .iter()
                    .all(|permission| permission.state != PermissionState::Pending),
            "terminal report still has pending work/interaction/permission"
        );
        ensure!(
            self.messages.iter().all(|message| message.consumed
                && message.sequence > 0
                && !message.id.trim().is_empty()
                && !message.source_id.trim().is_empty()),
            "terminal report has an invalid or unconsumed projected message identity"
        );
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ModelList {
    pub models: Vec<Model>,
    pub next_cursor: Option<String>,
    pub catalog_revision: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Model {
    pub account_id: String,
    pub model_id: String,
    pub context_window: Option<u64>,
    #[serde(default)]
    pub reasoning_efforts: Vec<String>,
    pub pricing: Option<ReferencePricing>,
    pub billing_kind: String,
    pub performance: Performance,
}

impl Model {
    pub fn route(&self) -> Route {
        Route {
            account_id: self.account_id.clone(),
            model_id: self.model_id.clone(),
            effort: self.reasoning_efforts.first().cloned(),
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Performance {
    pub sample_count: u64,
    pub tokens_per_second: Option<f64>,
    pub average_ttft_millis: Option<f64>,
    pub ttft_sample_count: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(super) struct Evaluation {
    pub agent_id: String,
    pub parent_agent_id: String,
    pub model: Route,
    pub profile_id: String,
    pub mode: String,
    pub preference: String,
    pub turn_id: String,
    pub revision: u64,
    pub outcome: String,
    pub quality: Option<u8>,
    pub instruction_following: Option<u8>,
    pub comment: String,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub(super) struct EvaluationReceipt {
    pub target: String,
    pub write: String,
    pub evaluation: Evaluation,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Detail {
    pub account_id: String,
    pub available: bool,
    pub unavailable_reason: Option<String>,
    pub guide: Option<Value>,
    pub billing_kind: String,
    pub descriptor: ModelReference,
    pub performance: Performance,
    pub recent_evaluations: Vec<Evaluation>,
    pub evaluations: EvaluationSummary,
}

#[derive(Debug, Deserialize)]
pub(super) struct ModelReference {
    pub pricing: Option<ReferencePricing>,
}

#[derive(Debug, Deserialize, PartialEq)]
pub(super) struct ReferencePricing {
    pub currency: String,
    pub tiers: Vec<ReferencePriceTier>,
}

#[derive(Debug, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReferencePriceTier {
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: Option<f64>,
    pub cache_write_per_mtok: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct EvaluationSummary {
    pub rated_samples: usize,
    pub not_rated: usize,
    pub average_quality: Option<f64>,
    pub average_instruction_following: Option<f64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct AgentRow {
    pub id: String,
    pub parent_id: Option<String>,
    pub frozen_model: Option<Route>,
    pub lifecycle: Lifecycle,
    pub pending_inputs: usize,
    pub running_tasks: usize,
    pub last_turn: Option<Turn>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Closed {
    pub target: String,
    pub lifecycle: Lifecycle,
    pub workspace_disposition: String,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "kind", content = "value")]
pub(super) enum Lifecycle {
    Open,
    Closing,
    Closed,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Sent {
    pub target: String,
    pub message_id: String,
    pub sequence: u64,
}

/// Minimal typed consumer of read_agent_session, not a private history reader.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SavedPage {
    pub agent_id: String,
    pub path: Vec<String>,
    pub through_sequence: u64,
    pub order: SavedOrder,
    pub detail: SavedDetail,
    pub items: Vec<SavedItem>,
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum SavedOrder {
    Descending,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum SavedDetail {
    Full,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SavedItem {
    pub id: String,
    pub thread_id: String,
    pub turn_id: String,
    pub ordinal: u64,
    pub state: SavedItemState,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub(super) enum SavedItemState {
    Turn {
        data: SavedTurn,
    },
    // Non-Turn items are not evidence for a Turn. Their payload is irrelevant
    // to this projection; their thread/ordinal fields are still validated.
    // Internal tagging ignores their data object without treating malformed
    // known Turn data as an unknown variant.
    #[serde(other)]
    Other,
}

#[derive(Deserialize)]
pub(super) struct SavedTurn {
    pub state: SavedTurnState,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub(super) enum SavedTurnState {
    Completed {
        data: SavedCompleted,
    },
    #[serde(other)]
    NotCompleted,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SavedCompleted {
    pub completed_at: i64,
    pub completion: SavedCompletion,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum SavedCompletion {
    Normal,
}
