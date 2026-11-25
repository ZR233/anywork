//! Thread Mode 的稳定协议类型。

use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::thread_mode_id::ThreadModeId;
use crate::workflow_tool::WorkflowDefinition;

/// GUI 与其他只读消费者可见的一项 Mode 元数据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeDescriptor {
    pub id: ThreadModeId,
    pub display_name: String,
    pub description: String,
    pub order: u32,
    pub has_workflow: bool,
    pub read_only: bool,
}

/// 某一时刻已注册 Mode 的不可变目录投影。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThreadModeCatalogSnapshot {
    pub revision: u64,
    #[serde(default)]
    pub modes: Vec<ThreadModeDescriptor>,
}

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
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModeDocument {
    pub id: ThreadModeId,
    pub display_name: String,
    pub description: String,
    pub order: u32,
    pub prompt: String,
    pub workflow: Option<WorkflowDefinition>,
    #[serde(default)]
    pub editor: ThreadModeEditorLayout,
}

impl ThreadModeDocument {
    pub fn from_parts(definition: ThreadModeDefinition, editor: ThreadModeEditorLayout) -> Self {
        Self {
            id: definition.id,
            display_name: definition.display_name,
            description: definition.description,
            order: definition.order,
            prompt: definition.prompt,
            workflow: definition.workflow,
            editor,
        }
    }

    pub fn into_parts(self) -> (ThreadModeDefinition, ThreadModeEditorLayout) {
        let definition = ThreadModeDefinition {
            id: self.id,
            display_name: self.display_name,
            description: self.description,
            order: self.order,
            prompt: self.prompt,
            workflow: self.workflow,
        };
        (definition, self.editor)
    }
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
    pub receipt: crate::StudioCommandReceipt,
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
