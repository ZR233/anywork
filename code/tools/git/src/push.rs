//! Independent `git_push` declaration and restricted push planning.

use crate::{
    GitCredentialOperation, GitCredentialProvider, GitError, GitExecutor, GitNetwork, GitOutput,
    non_empty,
};
use pl_agent_tool::{
    Tool, ToolDefinition,
    typed::{decode_json, input_schema_for},
};
use schemars::JsonSchema;
use serde::Deserialize;

pub const NAME: &str = "git_push";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct GitRemoteInput {
    /// Remote name; defaults to origin.
    remote: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GitPushWire {
    /// Remote name; defaults to origin.
    remote: Option<String>,
    /// Destination branch; defaults to the configured push branch.
    branch: Option<String>,
    /// Set the upstream branch while pushing.
    #[serde(default)]
    set_upstream: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(from = "GitPushWire")]
pub struct GitPushInput {
    remote: GitRemoteInput,
    pub branch: Option<String>,
    pub set_upstream: bool,
}

impl From<GitPushWire> for GitPushInput {
    fn from(wire: GitPushWire) -> Self {
        Self {
            remote: GitRemoteInput {
                remote: wire.remote,
            },
            branch: wire.branch,
            set_upstream: wire.set_upstream,
        }
    }
}

impl GitPushInput {
    pub fn remote(&self) -> Option<String> {
        self.remote.remote.clone()
    }
}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Push the current branch using host-injected credentials.",
        input_schema_for::<GitPushInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitPush<E, P> {
    definition: ToolDefinition,
    network: GitNetwork<E, P>,
}

impl<E, P> GitPush<E, P> {
    pub fn new(network: GitNetwork<E, P>, definition: ToolDefinition) -> Self {
        Self {
            definition,
            network,
        }
    }
}

impl<E: GitExecutor + 'static, P: GitCredentialProvider + 'static> Tool for GitPush<E, P> {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        let input: GitPushInput = decode_json(&input)?;
        let config = &self.network.runner.config;
        let remote = non_empty(input.remote()).unwrap_or_else(|| "origin".to_string());
        config.policy.validate_remote(&remote)?;
        let branch = non_empty(input.branch)
            .or_else(|| config.default_push_branch.clone())
            .ok_or_else(|| GitError::invalid(NAME, "missing string field `branch`"))?;
        config.policy.validate_branch(&branch)?;
        let destination = format!("HEAD:refs/heads/{branch}");
        let mut args = vec!["push", "--no-verify"];
        if input.set_upstream {
            args.push("-u");
        }
        args.push(&remote);
        args.push(&destination);
        self.network
            .run(NAME, args, GitCredentialOperation::Push, remote.clone())
            .await
    }
}
