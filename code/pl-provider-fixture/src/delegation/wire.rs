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

#[derive(Debug)]
pub(super) enum ToolCallOutput {
    Immediate(String),
    Pending {
        task_id: String,
        acknowledgement: String,
    },
}

#[derive(Debug, PartialEq, Eq)]
pub(super) enum TaskCompletionStatus {
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

#[derive(Debug)]
pub(super) struct TaskCompletion {
    pub status: TaskCompletionStatus,
    pub projection: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) enum ToolTaskStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    Interrupted,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ToolTaskStatusView {
    pub task_id: String,
    pub tool_id: String,
    pub status: ToolTaskStatus,
    pub cancel_requested: bool,
}

#[derive(Debug, Deserialize)]
pub(super) struct ToolTaskQuery {
    pub task: ToolTaskStatusView,
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

    fn joined_complete(&self) -> Result<String> {
        match self {
            Self::Plain(text) => Ok(text.clone()),
            Self::Parts(parts) => joined_text_parts(parts),
        }
    }
}

fn joined_text_parts(parts: &[TextPart]) -> Result<String> {
    parts
        .iter()
        .map(|part| part.text.as_deref().context("text part has no text"))
        .collect::<Result<Vec<_>>>()
        .map(|parts| parts.join("\n"))
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

    pub fn tool_call_output(
        &self,
        id: &str,
        tool: &str,
        expected_arguments: &Value,
    ) -> Result<Option<(usize, ToolCallOutput)>> {
        let calls: Vec<_> = self
            .input
            .iter()
            .enumerate()
            .filter(|(_, item)| item.kind == "function_call" && item.call_id.as_deref() == Some(id))
            .collect();
        let outputs: Vec<_> = self
            .input
            .iter()
            .filter(|item| {
                item.kind == "function_call_output" && item.call_id.as_deref() == Some(id)
            })
            .collect();
        ensure!(
            calls.len() <= 1 && outputs.len() <= 1,
            "duplicate call/output identity {id}"
        );
        let Some((call_index, declaration)) = calls.first().copied() else {
            ensure!(outputs.is_empty(), "orphan tool output {id}");
            return Ok(None);
        };
        ensure!(
            declaration.name.as_deref() == Some(tool),
            "tool result belongs to the wrong tool"
        );
        let declared_arguments: Value = serde_json::from_str(
            declaration
                .arguments
                .as_deref()
                .context("tool call declaration has no arguments")?,
        )
        .context("decode tool call declaration arguments")?;
        ensure!(
            &declared_arguments == expected_arguments,
            "tool call arguments changed during history replay"
        );
        let Some(output) = outputs.first() else {
            anyhow::bail!("tool call {id} has no committed result")
        };
        let text = output
            .output
            .as_ref()
            .context("tool output missing text")?
            .joined_complete()?;
        if let Some(task_id) = parse_task_ack(&text)? {
            ensure!(
                task_id == format!("task:{id}"),
                "tool ACK task identity does not match its call"
            );
            return Ok(Some((
                call_index,
                ToolCallOutput::Pending {
                    task_id,
                    acknowledgement: text,
                },
            )));
        }
        Ok(Some((call_index, ToolCallOutput::Immediate(text))))
    }

    pub fn task_completion_after(
        &self,
        call_index: usize,
        task_id: &str,
        tool: &str,
    ) -> Result<Option<TaskCompletion>> {
        let identity_prefix = format!("Task {task_id} for tool ");
        let mut completion = None;
        for (index, item) in self.input.iter().enumerate() {
            if item.role.as_deref() != Some("user") {
                continue;
            }
            let Some(content) = &item.content else {
                continue;
            };
            let parts = match content {
                Text::Parts(parts) => parts,
                Text::Plain(text) if text.starts_with(&identity_prefix) => {
                    anyhow::bail!("task completion did not preserve production text parts")
                }
                Text::Plain(_) => continue,
            };
            let Some(first) = parts.first().and_then(|part| part.text.as_deref()) else {
                continue;
            };
            if !first.starts_with(&identity_prefix) {
                continue;
            }
            ensure!(
                index > call_index,
                "task completion predates its originating call"
            );
            let after_prefix = &first[identity_prefix.len()..];
            let (reported_tool, reported_status) = after_prefix
                .split_once(" finished: ")
                .context("malformed task completion identity/status prefix")?;
            ensure!(
                reported_tool == tool,
                "task completion belongs to another tool"
            );
            let status = if reported_status == "Succeeded." {
                TaskCompletionStatus::Succeeded
            } else if reported_status == "Failed." {
                TaskCompletionStatus::Failed
            } else if reported_status == "Cancelled." {
                TaskCompletionStatus::Cancelled
            } else if reported_status == "Interrupted." {
                TaskCompletionStatus::Interrupted
            } else {
                anyhow::bail!("unknown or malformed task completion status")
            };
            // The producer inserts the status as one ContextContent::Text, then
            // the original tool projection as its following text parts. The
            // codec and Responses adapter preserve those part boundaries; this
            // join matches the fixture's ordinary immediate-output projection.
            let projection =
                joined_text_parts(&parts[1..]).context("task result text part has no text")?;
            ensure!(
                !projection.is_empty(),
                "task completion has no result projection parts"
            );
            ensure!(
                completion.is_none(),
                "duplicate task completion report for {task_id}"
            );
            completion = Some(TaskCompletion { status, projection });
        }
        Ok(completion)
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
}

fn parse_task_ack(text: &str) -> Result<Option<String>> {
    if !text.starts_with("Task ") {
        return Ok(None);
    }
    let task_id = text
        .strip_prefix("Task ")
        .and_then(|text| {
            text.strip_suffix(" is running. Its result will be delivered when execution finishes.")
        })
        .context("unrecognized task-style tool output")?;
    ensure!(
        !task_id.is_empty() && !task_id.chars().any(char::is_whitespace),
        "invalid background task acknowledgement identity"
    );
    Ok(Some(task_id.to_owned()))
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
    pub agents: Vec<ClosedAgent>,
    pub error: Option<CloseFailure>,
}

impl Closed {
    pub fn succeeded_for(&self, target: &str) -> bool {
        self.target == target
            && self.error.is_none()
            && self.agents.iter().any(|agent| agent.agent_id == target)
            && self.agents.iter().all(|agent| {
                agent.execution_closed
                    && matches!(
                        &agent.worktree_cleanup,
                        WorktreeCleanup::NotApplicable
                            | WorktreeCleanup::NotPresent { .. }
                            | WorktreeCleanup::Removed { .. }
                    )
            })
    }
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct ClosedAgent {
    pub agent_id: String,
    pub execution_closed: bool,
    pub worktree_cleanup: WorktreeCleanup,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(super) enum WorktreeCleanup {
    Pending,
    NotApplicable,
    NotPresent {
        path: String,
        registration_present: bool,
    },
    Removed {
        path: String,
    },
    Failed {
        path: Option<String>,
        error: CloseFailure,
    },
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct CloseFailure {
    pub code: String,
    pub message: String,
    pub retryable: bool,
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
