//! Independent `git_commit` declaration and commit command planning.

use crate::{GitError, GitExecutor, GitOutput, GitRunner, required_text};
use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use schemars::JsonSchema;
use serde::Deserialize;

pub const NAME: &str = "git_commit";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GitCommitInput {
    /// Commit message.
    pub message: String,
    /// Commit all tracked modified and deleted files.
    #[serde(default)]
    pub all: bool,
}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Create a git commit in this workspace.",
        input_schema_for::<GitCommitInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitCommit<E> {
    definition: ToolDefinition,
    runner: GitRunner<E>,
}

impl<E> GitCommit<E> {
    pub fn new(runner: GitRunner<E>, definition: ToolDefinition) -> Self {
        Self { definition, runner }
    }
}

impl<E: GitExecutor + 'static> Tool for GitCommit<E> {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        let input: GitCommitInput = decode_json(&input)?;
        let message = required_text(NAME, Some(input.message), "message")?;
        let args = if input.all {
            vec!["commit", "--no-verify", "-am", &message]
        } else {
            vec!["commit", "--no-verify", "-m", &message]
        };
        self.runner.run_plain(NAME, args).await
    }
}
