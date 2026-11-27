//! Independent `git_workspace_info` result projection over frozen Git facts.

use crate::{GitError, GitOutput, GitWorkspaceConfig};
use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::json;

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
    .with_output_schema(json!({
        "type": "object",
        "properties": {
            "clone": {"type": "string"},
            "worktree": {"type": "string"},
            "metadata": {"type": "object", "description": "Host-provided repository metadata keyed by name."},
        },
        "required": ["clone", "worktree", "metadata"],
        "additionalProperties": false,
    }))
    .expect("valid Git workspace info schema")
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
        Ok(GitOutput::new(json!({
            "clone": self.config.worktree,
            "worktree": self.config.worktree,
            "metadata": self.config.workspace_info,
        })))
    }
}
