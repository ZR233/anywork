//! Independent `git_sync_default_branch` orchestration.

use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use pl_tool_git_support::{
    GitCredentialOperation, GitCredentialProvider, GitError, GitExecutor, GitNetwork, GitOutput,
};
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::json;

pub const NAME: &str = "git_sync_default_branch";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct GitSyncDefaultBranchInput {
    /// Discard uncommitted workspace changes while syncing.
    #[serde(default)]
    pub force: bool,
    /// Stash uncommitted changes before syncing and restore them afterwards.
    #[serde(default)]
    pub preserve_changes: bool,
}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Synchronize this workspace branch with the configured default branch.",
        input_schema_for::<GitSyncDefaultBranchInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitSyncDefaultBranch<E, P> {
    definition: ToolDefinition,
    network: GitNetwork<E, P>,
}

impl<E, P> GitSyncDefaultBranch<E, P> {
    pub fn new(network: GitNetwork<E, P>, definition: ToolDefinition) -> Self {
        Self {
            definition,
            network,
        }
    }
}

impl<E: GitExecutor, P: GitCredentialProvider> GitSyncDefaultBranch<E, P> {
    async fn sync(
        &self,
        input: GitSyncDefaultBranchInput,
        completed: &mut Vec<GitOutput>,
    ) -> Result<GitOutput, GitError> {
        if input.force && input.preserve_changes {
            return Err(GitError::invalid(
                NAME,
                "force and preserveChanges cannot both be true",
            ));
        }
        let runner = &self.network.runner;
        let dirty = {
            let status = runner
                .run_plain(NAME, vec!["status", "--porcelain"])
                .await?;
            !status.stdout().trim().is_empty()
        };
        if dirty && !input.force && !input.preserve_changes {
            return Err(GitError::invalid(
                NAME,
                "git workspace has uncommitted changes; pass force=true to discard them or preserveChanges=true to stash them before sync",
            ));
        }
        if dirty && input.preserve_changes {
            completed.push(
                runner
                    .run_plain(
                        NAME,
                        vec!["stash", "push", "-u", "-m", "pl-core sync default branch"],
                    )
                    .await?,
            );
        }
        if let Some(remote_url) = runner.config.remote_url.as_deref() {
            completed.push(
                runner
                    .run_plain(NAME, vec!["remote", "set-url", "origin", remote_url])
                    .await?,
            );
        }
        completed.push(
            self.network
                .run(
                    NAME,
                    vec!["fetch", "--prune", "origin"],
                    GitCredentialOperation::Fetch,
                    "origin".to_string(),
                )
                .await?,
        );
        let branch = runner
            .config
            .default_push_branch
            .as_deref()
            .unwrap_or(&runner.config.policy.default_branch);
        runner.config.policy.validate_branch(branch)?;
        let origin_branch = format!("origin/{}", runner.config.policy.default_branch);
        completed.push(
            runner
                .run_plain(NAME, vec!["checkout", "-B", branch, &origin_branch])
                .await?,
        );
        completed.push(
            runner
                .run_plain(NAME, vec!["reset", "--hard", &origin_branch])
                .await?,
        );
        if input.force {
            completed.push(runner.run_plain(NAME, vec!["clean", "-fdx"]).await?);
        }
        if dirty && input.preserve_changes {
            completed.push(runner.run_plain(NAME, vec!["stash", "pop"]).await?);
        }
        Ok(GitOutput::new(json!({
            "clone": runner.config.worktree,
            "worktree": runner.config.worktree,
            "preservedChanges": dirty && input.preserve_changes,
            "forced": input.force,
        })))
    }
}

impl<E: GitExecutor + 'static, P: GitCredentialProvider + 'static> Tool
    for GitSyncDefaultBranch<E, P>
{
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        let input = decode_json(&input)?;
        let mut completed = Vec::new();
        self.sync(input, &mut completed)
            .await
            .map_err(|error| error.after_commands(completed))
    }
}
