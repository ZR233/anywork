//! Independent `git_branch` declaration and branch operations.

use crate::{GitError, GitExecutor, GitOutput, GitRunner, non_empty, required_text};
use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use schemars::JsonSchema;
use serde::Deserialize;

pub const NAME: &str = "git_branch";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GitBranchInput {
    /// Branch action; defaults to list.
    pub action: Option<GitBranchAction>,
    /// Branch name used by switch and create.
    pub name: Option<String>,
    /// Optional starting revision for create.
    pub start_point: Option<String>,
}

#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum GitBranchAction {
    List,
    Switch,
    Create,
}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "List branches or create/switch the current branch.",
        input_schema_for::<GitBranchInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitBranch<E> {
    definition: ToolDefinition,
    runner: GitRunner<E>,
}

impl<E> GitBranch<E> {
    pub fn new(runner: GitRunner<E>, definition: ToolDefinition) -> Self {
        Self { definition, runner }
    }
}

impl<E: GitExecutor + 'static> Tool for GitBranch<E> {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        let input: GitBranchInput = decode_json(&input)?;
        match input.action.unwrap_or(GitBranchAction::List) {
            GitBranchAction::List => {
                self.runner
                    .run_plain(NAME, vec!["branch", "--list", "--all"])
                    .await
            }
            GitBranchAction::Switch => {
                let name = required_text(NAME, input.name, "name")?;
                self.runner.config.policy.validate_branch(&name)?;
                self.runner.run_plain(NAME, vec!["switch", &name]).await
            }
            GitBranchAction::Create => {
                let name = required_text(NAME, input.name, "name")?;
                self.runner.config.policy.validate_branch(&name)?;
                if let Some(start_point) = non_empty(input.start_point) {
                    self.runner.config.policy.validate_branch(&start_point)?;
                    self.runner
                        .run_plain(NAME, vec!["switch", "-c", &name, &start_point])
                        .await
                } else {
                    self.runner
                        .run_plain(NAME, vec!["switch", "-c", &name])
                        .await
                }
            }
        }
    }
}
