use crate::api::studio::observation::BridgeReadText;
use crate::api::studio::types::BridgeToolApprovalResolution;
use super::super::identity::BridgeReadScopeIdentity;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeInteractionReadHeader {
    pub scope: BridgeReadScopeIdentity,
    pub interaction_id: BridgeReadText,
    pub thread_id: BridgeReadText,
    pub turn_id: BridgeReadText,
    pub item_id: Option<BridgeReadText>,
    pub tool_id: Option<BridgeReadText>,
    pub agent_path: Option<BridgeReadText>,
    pub revision: u64,
    pub purpose: BridgeInteractionReadPurpose,
    pub continuation: Option<BridgeInteractionReadContinuation>,
    pub created_at: i64,
    pub updated_at: i64,
    pub content: BridgeInteractionReadContent,
    pub state: BridgeInteractionReadState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeInteractionReadPurpose {
    General,
    PlanConfirmation {
        expected_revision: u64,
        operation_id: BridgeReadText,
        argument_hash: BridgeReadText,
        plan_hash: BridgeReadText,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeInteractionPresentation { Visible, Hidden }

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeInteractionReadContinuation {
    Resolution { presentation: BridgeInteractionPresentation },
    Question { question_id: BridgeReadText, presentation: BridgeInteractionPresentation },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeInteractionReadContent {
    UserInput { question_count: u64 },
    ToolApproval {
        name: BridgeReadText,
        arguments: BridgeReadText,
        working_directory: Option<BridgeReadText>,
        parent_agent_id: Option<BridgeReadText>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeInteractionReadState {
    Pending { operation_id: BridgeReadText },
    UserInputResolved { operation_id: BridgeReadText, resolved_at: i64, answer_entry_count: u64 },
    ApprovalResolved { operation_id: BridgeReadText, resolved_at: i64,
        decision: BridgeToolApprovalResolution, reason: Option<BridgeReadText> },
    Cancelled { operation_id: BridgeReadText, cancelled_at: i64, reason: BridgeReadText },
    Expired { operation_id: BridgeReadText, expired_at: i64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeQuestionReadItem {
    pub index: u64,
    pub id: BridgeReadText,
    pub header: BridgeReadText,
    pub question: BridgeReadText,
    pub is_other: bool,
    pub is_secret: bool,
    pub options_count: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOptionReadItem {
    pub index: u64,
    pub label: BridgeReadText,
    pub description: BridgeReadText,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAnswerEntryReadItem {
    pub index: u64,
    pub question_id: BridgeReadText,
    pub answer_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAnswerValueReadItem { pub index: u64, pub value: BridgeReadText }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeQuestionPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeQuestionReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeOptionPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeOptionReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAnswerEntryPage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAnswerEntryReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAnswerValuePage {
    pub scope: BridgeReadScopeIdentity,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAnswerValueReadItem>,
    pub next_offset: Option<u64>,
}
