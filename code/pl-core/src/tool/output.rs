//! Producer-owned business output and its separately frozen model-facing projection.

use crate::context::{ContextContent, OpaquePayload};
use pl_agent_tool::ToolResult;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;

/// Trusted framework control, separate from arbitrary result content.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ToolControl {
    #[default]
    Continue,
    EndTurn,
    AwaitInteraction,
}

/// Complete tool data and the exact content selected for the original model delivery.
///
/// The Thread supplies call identity and the tool-result role. Neither program values nor
/// content values grant authority to end a Turn, approve work, or rewrite a system instruction.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolOutput {
    result: Arc<ToolResult<ContextContent>>,
    #[serde(default)]
    control: ToolControl,
    #[serde(default)]
    extension_mutations: Vec<crate::thread::extensions::ExtensionMutation>,
    #[serde(default)]
    revealed_tools: Vec<String>,
    #[serde(default)]
    interaction: Option<OpaquePayload>,
}

impl ToolOutput {
    /// Freezes the author's result alongside independent framework control.
    pub fn new(result: ToolResult<ContextContent>) -> Self {
        Self {
            result: Arc::new(result),
            control: ToolControl::Continue,
            extension_mutations: Vec::new(),
            revealed_tools: Vec::new(),
            interaction: None,
        }
    }

    pub fn from_data(value: Value, content: Vec<ContextContent>) -> Self {
        Self::new(ToolResult::from_data(value, content))
    }

    /// Provides one compact JSON text block alongside the original program value.
    pub fn json(value: Value) -> Self {
        let content = ContextContent::Text {
            text: value.to_string().into(),
        };
        Self::from_data(value, vec![content])
    }

    /// Preserves text verbatim as both a JSON string value and a model text block.
    pub fn text(text: String) -> Self {
        let content = ContextContent::Text {
            text: text.as_str().into(),
        };
        Self::from_data(Value::String(text), vec![content])
    }

    /// Requests a host interaction; core assigns its identity and validates registered authority.
    pub fn with_interaction(mut self, payload: OpaquePayload) -> Self {
        self.interaction = Some(payload);
        self.control = ToolControl::AwaitInteraction;
        self
    }

    /// Returns the opaque interaction request material, if supplied.
    pub fn interaction(&self) -> Option<&OpaquePayload> {
        self.interaction.as_ref()
    }

    /// Proposes tool discovery changes, validated against explicit registration authority.
    pub fn with_revealed_tools(mut self, ids: Vec<String>) -> Self {
        self.revealed_tools = ids;
        self
    }

    /// Stable tool identities requested for the next model step.
    pub fn revealed_tools(&self) -> &[String] {
        &self.revealed_tools
    }

    /// Proposes opaque state changes to commit atomically with this result, subject to registration authority.
    pub fn with_extension_mutations(
        mut self,
        mutations: Vec<crate::thread::extensions::ExtensionMutation>,
    ) -> Self {
        self.extension_mutations = mutations;
        self
    }

    /// Returns proposed framework mutations; payload content alone never mutates state.
    pub fn extension_mutations(&self) -> &[crate::thread::extensions::ExtensionMutation] {
        &self.extension_mutations
    }

    /// Requests Turn completion; the Thread validates the frozen registration's control permission.
    pub fn ending_turn(mut self) -> Self {
        self.control = ToolControl::EndTurn;
        self.interaction = None;
        self
    }

    /// Returns framework control without inspecting the dynamic business payload.
    pub fn control(&self) -> ToolControl {
        self.control
    }

    pub fn result(&self) -> &ToolResult<ContextContent> {
        &self.result
    }

    pub fn data(&self) -> Option<&Value> {
        self.result.data()
    }

    /// Returns the original model projection, including on history replay.
    pub fn content(&self) -> &[ContextContent] {
        self.result.content()
    }

    pub fn details(&self) -> Option<&Value> {
        self.result.details()
    }

    pub fn with_details(mut self, details: Value) -> Self {
        self.result = Arc::new(Arc::unwrap_or_clone(self.result).with_details(details));
        self
    }
}
