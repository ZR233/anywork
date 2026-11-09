//! Independent `git_diff` declaration, validation and command planning.

use crate::{GitError, GitExecutor, GitOutput, GitRunner, non_empty};
use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use schemars::JsonSchema;
use serde::Deserialize;

pub const NAME: &str = "git_diff";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GitDiffInput {
    /// Show staged changes instead of unstaged changes.
    #[serde(default)]
    pub staged: bool,
    /// Optional repository-relative path to limit the diff.
    pub path: Option<String>,
}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Show git diff for this workspace.",
        input_schema_for::<GitDiffInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitDiff<E> {
    definition: ToolDefinition,
    runner: GitRunner<E>,
}

impl<E> GitDiff<E> {
    pub fn new(runner: GitRunner<E>, definition: ToolDefinition) -> Self {
        Self { definition, runner }
    }
}

impl<E: GitExecutor + 'static> Tool for GitDiff<E> {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        let input: GitDiffInput = decode_json(&input)?;
        let path = non_empty(input.path);
        if let Some(path) = path.as_deref() {
            self.runner.config.policy.validate_path(path)?;
        }
        let args = match (input.staged, path.as_deref()) {
            (true, Some(path)) => vec!["diff", "--staged", "--", path],
            (true, None) => vec!["diff", "--staged"],
            (false, Some(path)) => vec!["diff", "--", path],
            (false, None) => vec!["diff"],
        };
        self.runner.run_plain(NAME, args).await
    }
}
