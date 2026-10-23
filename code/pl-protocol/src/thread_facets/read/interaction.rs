use serde::{Deserialize, Serialize};

use crate::MessagePresentation;
use crate::studio::ReadText;
use crate::thread_facets::identity::ReadScopeIdentity;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InteractionReadHeader {
    pub scope: ReadScopeIdentity,
    pub interaction_id: ReadText,
    pub thread_id: ReadText,
    pub turn_id: ReadText,
    pub item_id: Option<ReadText>,
    pub tool_id: Option<ReadText>,
    pub agent_path: Option<ReadText>,
    pub revision: u64,
    pub purpose: InteractionReadPurpose,
    pub continuation: Option<InteractionReadContinuation>,
    pub created_at: i64,
    pub updated_at: i64,
    pub content: InteractionReadContent,
    pub state: InteractionReadState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum InteractionReadPurpose {
    General,
    PlanConfirmation {
        expected_revision: u64,
        operation_id: ReadText,
        argument_hash: ReadText,
        plan_hash: ReadText,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum InteractionReadContinuation {
    Resolution { presentation: MessagePresentation },
    Question { question_id: ReadText, presentation: MessagePresentation },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum InteractionReadContent {
    UserInput { question_count: u64 },
    ToolApproval {
        name: ReadText,
        /// Only the original opaque tool arguments are JSON text, never the header schema.
        arguments: ReadText,
        working_directory: Option<ReadText>,
        parent_agent_id: Option<ReadText>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum InteractionReadState {
    Pending { operation_id: ReadText },
    UserInputResolved { operation_id: ReadText, resolved_at: i64, answer_entry_count: u64 },
    ApprovalResolved {
        operation_id: ReadText,
        resolved_at: i64,
        decision: crate::ToolApprovalResolution,
        reason: Option<ReadText>,
    },
    Cancelled { operation_id: ReadText, cancelled_at: i64, reason: ReadText },
    Expired { operation_id: ReadText, expired_at: i64 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuestionReadItem {
    pub index: u64,
    pub id: ReadText,
    pub header: ReadText,
    pub question: ReadText,
    pub is_other: bool,
    pub is_secret: bool,
    pub options_count: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OptionReadItem {
    pub index: u64,
    pub label: ReadText,
    pub description: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AnswerEntryReadItem {
    pub index: u64,
    pub question_id: ReadText,
    pub answer_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AnswerValueReadItem {
    pub index: u64,
    pub value: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuestionPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<QuestionReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct OptionPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<OptionReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AnswerEntryPage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<AnswerEntryReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AnswerValuePage {
    pub scope: ReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<AnswerValueReadItem>,
    pub next_offset: Option<u64>,
}
