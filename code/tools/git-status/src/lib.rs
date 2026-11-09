//! Independent `git_status` declaration and execution.

use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use pl_tool_git_support::{GitError, GitExecutor, GitOutput, GitRunner};
use schemars::JsonSchema;
use serde::Deserialize;

pub const NAME: &str = "git_status";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct GitEmptyInput {}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Show git working tree status for this workspace.",
        input_schema_for::<GitEmptyInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitStatus<E> {
    definition: ToolDefinition,
    runner: GitRunner<E>,
}

impl<E> GitStatus<E> {
    pub fn new(runner: GitRunner<E>, definition: ToolDefinition) -> Self {
        Self { definition, runner }
    }
}

impl<E: GitExecutor + 'static> Tool for GitStatus<E> {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        decode_json::<GitEmptyInput>(&input)?;
        self.runner
            .run_plain(NAME, vec!["status", "--short", "--branch"])
            .await
    }
}
