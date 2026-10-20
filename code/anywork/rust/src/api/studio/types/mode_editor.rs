use super::command::BridgeStudioCommandReceipt;
use super::response::BridgeThreadModeCatalogSnapshot;

/// Typed FRB mirror of a saved Mode document.
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadModeDocument {
    pub definition: BridgeThreadModeDefinition,
    pub editor: BridgeThreadModeEditorLayout,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadModeDefinition {
    pub id: String,
    pub display_name: String,
    pub description: String,
    pub order: u32,
    pub prompt: String,
    pub workflow: Option<BridgeWorkflowDefinition>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct BridgeThreadModeEditorLayout {
    pub nodes: Vec<BridgeWorkflowNodePosition>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeWorkflowNodePosition {
    pub state_id: String,
    pub x: f64,
    pub y: f64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkflowDefinition {
    pub title: String,
    pub goal: String,
    pub initial_state_id: String,
    pub states: Vec<BridgeWorkflowState>,
    pub transitions: Vec<BridgeWorkflowTransition>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkflowState {
    pub id: String,
    pub title: String,
    pub instructions: String,
    pub completion_criteria: Vec<String>,
    pub kind: BridgeWorkflowStateKind,
}

/// `Final` would produce an awkward Dart identifier, so the FRB surface names
/// the variant `FinalState`; the file/JSON wire spelling remains `final`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeWorkflowStateKind {
    Atomic,
    FinalState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkflowTransition {
    pub source_state_id: String,
    pub target_state_id: String,
    pub guard: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadModeDefinitionSnapshot {
    pub revision: u64,
    pub document: BridgeThreadModeDocument,
    pub read_only: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadModeValidationIssue {
    pub code: String,
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadModeValidationResult {
    pub document: Option<BridgeThreadModeDocument>,
    pub issues: Vec<BridgeThreadModeValidationIssue>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeThreadModeDefinitionCommandReply {
    pub catalog: BridgeThreadModeCatalogSnapshot,
    pub definition: Option<BridgeThreadModeDefinitionSnapshot>,
    pub receipt: BridgeStudioCommandReceipt,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeWorkflowPreviewRequest {
    pub document: BridgeThreadModeDocument,
    pub path: Vec<String>,
    pub target_state_id: Option<String>,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeWorkflowPreviewSnapshot {
    pub accepted: bool,
    pub message: String,
    pub current_state: Option<BridgeWorkflowState>,
    pub transitions: Vec<BridgeWorkflowTransition>,
    pub path: Vec<String>,
    pub terminal: bool,
}
