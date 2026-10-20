//! Work mode authoring documents and owner-produced command results.

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use super::{ThreadModeCatalogSnapshot, ThreadModeId};
use crate::{WorkflowDefinition, WorkflowState, WorkflowTransition};

/// Complete execution definition, shared by registration, files and saved Thread snapshots.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModeDefinition {
    pub id: ThreadModeId,
    pub display_name: String,
    pub description: String,
    pub order: u32,
    pub prompt: String,
    pub workflow: Option<WorkflowDefinition>,
}

/// Editor metadata is deliberately outside the execution definition and workflow hash.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModeEditorLayout {
    #[serde(default)]
    pub nodes: Vec<WorkflowNodePosition>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowNodePosition {
    pub state_id: String,
    pub x: f64,
    pub y: f64,
}

/// JSON files retain the established six Mode fields at the top level.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeDocument {
    #[serde(flatten)]
    pub definition: ThreadModeDefinition,
    #[serde(default)]
    pub editor: ThreadModeEditorLayout,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeDefinitionSnapshot {
    pub revision: u64,
    pub document: ThreadModeDocument,
    pub read_only: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeValidationIssue {
    pub code: String,
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeValidationResult {
    pub document: Option<ThreadModeDocument>,
    pub issues: Vec<ThreadModeValidationIssue>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeDefinitionCommandReply {
    pub catalog: ThreadModeCatalogSnapshot,
    pub definition: Option<ThreadModeDefinitionSnapshot>,
    pub receipt: crate::studio::StudioCommandReceipt,
}

/// Stateless, bounded replay. Every transition uses the production Rust machine.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkflowPreviewRequest {
    pub document: ThreadModeDocument,
    #[serde(default)]
    pub path: Vec<String>,
    pub target_state_id: Option<String>,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkflowPreviewSnapshot {
    pub accepted: bool,
    pub message: String,
    pub current_state: Option<WorkflowState>,
    pub transitions: Vec<WorkflowTransition>,
    pub path: Vec<String>,
    pub terminal: bool,
}
