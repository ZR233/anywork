//! Thread Mode 的稳定协议类型。

use std::fmt;
use std::hash::{Hash, Hasher};

use schemars::JsonSchema;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::workflow_tool::{WorkflowDefinition, WorkflowState, WorkflowTransition};

/// Thread 所选择的 Mode ID。
///
/// ID 的 wire 形式固定为 `mode.<name>`。内置与未来外部注册的 Mode 使用同一类型。
#[derive(Clone)]
pub struct ThreadModeId(String);

impl ThreadModeId {
    pub const AUTO: &'static str = "mode.auto";

    pub fn new(value: impl Into<String>) -> Result<Self, crate::UnknownLabelError> {
        let canonical = value.into();
        let name = canonical.strip_prefix("mode.").unwrap_or_default();
        if name.is_empty()
            || canonical.len() > 64
            || !name.bytes().all(|byte| {
                byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
            })
        {
            return Err(crate::UnknownLabelError::new("ThreadModeId", canonical));
        }
        Ok(Self(canonical))
    }

    pub fn auto() -> Self {
        Self(Self::AUTO.to_string())
    }

    pub(crate) fn legacy_builtin_replacement(&self) -> Option<Self> {
        matches!(self.as_str(), "mode.simple" | "mode.task").then(Self::auto)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }

    pub fn label(&self) -> &str {
        self.as_str()
    }

    pub fn from_label(label: &str) -> Result<Self, crate::UnknownLabelError> {
        Self::new(label)
    }
}

impl Default for ThreadModeId {
    fn default() -> Self {
        Self::auto()
    }
}

impl fmt::Debug for ThreadModeId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_tuple("ThreadModeId")
            .field(&self.0)
            .finish()
    }
}

impl fmt::Display for ThreadModeId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl PartialEq for ThreadModeId {
    fn eq(&self, other: &Self) -> bool {
        self.as_str() == other.as_str()
    }
}

impl Eq for ThreadModeId {}

impl PartialOrd for ThreadModeId {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for ThreadModeId {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.as_str().cmp(other.as_str())
    }
}

impl Hash for ThreadModeId {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.as_str().hash(state);
    }
}

impl Serialize for ThreadModeId {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for ThreadModeId {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Self::new(value).map_err(serde::de::Error::custom)
    }
}

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

impl schemars::JsonSchema for ThreadModeId {
    fn schema_name() -> std::borrow::Cow<'static, str> {
        "ThreadModeId".into()
    }

    fn json_schema(_: &mut schemars::SchemaGenerator) -> schemars::Schema {
        schemars::json_schema!({"type": "string", "pattern": "^mode\\.[a-z0-9_-]+$", "maxLength": 64})
    }
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
