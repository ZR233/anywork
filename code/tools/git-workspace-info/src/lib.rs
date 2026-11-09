//! Independent `git_workspace_info` result projection over frozen Git facts.

use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use pl_tool_git_support::{GitError, GitOutput, GitWorkspaceConfig};
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::{Value, json};

pub const NAME: &str = "git_workspace_info";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GitEmptyInput {}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Show information about this git workspace.",
        input_schema_for::<GitEmptyInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitWorkspaceInfo {
    definition: ToolDefinition,
    config: GitWorkspaceConfig,
}

impl GitWorkspaceInfo {
    pub fn new(config: GitWorkspaceConfig, definition: ToolDefinition) -> Self {
        Self { definition, config }
    }
}

impl Tool for GitWorkspaceInfo {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        decode_json::<GitEmptyInput>(&input)?;
        let mut payload = serde_json::Map::new();
        payload.insert("worktree".to_string(), json!(self.config.worktree));
        payload.insert("clone".to_string(), json!(self.config.worktree));
        for (key, value) in &self.config.workspace_info {
            payload.insert(key.clone(), value.clone());
        }
        Ok(GitOutput::new(Value::Object(payload)))
    }
}
