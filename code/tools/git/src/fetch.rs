//! Independent `git_fetch` declaration, validation and credential-aware fetch.

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

pub const NAME: &str = "git_fetch";

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct GitRemoteInput {
    /// Remote name; defaults to origin.
    remote: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GitFetchWire {
    /// Remote name; defaults to origin.
    remote: Option<String>,
    /// Optional fetch refspec.
    refspec: Option<String>,
    /// Whether to prune stale remote-tracking refs.
    #[serde(default = "default_true")]
    prune: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(from = "GitFetchWire")]
pub struct GitFetchInput {
    remote: GitRemoteInput,
    pub refspec: Option<String>,
    pub prune: bool,
}

impl From<GitFetchWire> for GitFetchInput {
    fn from(wire: GitFetchWire) -> Self {
        Self {
            remote: GitRemoteInput {
                remote: wire.remote,
            },
            refspec: wire.refspec,
            prune: wire.prune,
        }
    }
}

impl GitFetchInput {
    pub fn remote(&self) -> Option<String> {
        self.remote.remote.clone()
    }
}

fn default_true() -> bool {
    true
}

pub fn definition() -> ToolDefinition {
    ToolDefinition::json(
        NAME,
        "Fetch from the repository remote using host-injected credentials.",
        input_schema_for::<GitFetchInput>(),
    )
    .expect("valid Git tool definition")
}

#[derive(Debug)]
pub struct GitFetch<E, P> {
    definition: ToolDefinition,
    network: GitNetwork<E, P>,
}

impl<E, P> GitFetch<E, P> {
    pub fn new(network: GitNetwork<E, P>, definition: ToolDefinition) -> Self {
        Self {
            definition,
            network,
        }
    }
}

impl<E: GitExecutor + 'static, P: GitCredentialProvider + 'static> Tool for GitFetch<E, P> {
    type Input = String;
    type Context = ();
    type Output = GitOutput;
    type Error = GitError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(&self, input: String, _context: ()) -> Result<GitOutput, GitError> {
        let input: GitFetchInput = decode_json(&input)?;
        let remote = non_empty(input.remote()).unwrap_or_else(|| "origin".to_string());
        let policy = &self.network.runner.config.policy;
        policy.validate_remote(&remote)?;
        let refspec = non_empty(input.refspec);
        policy.validate_fetch_refspec(refspec.as_deref())?;
        let mut args = vec!["fetch"];
        if input.prune {
            args.push("--prune");
        }
        args.push(&remote);
        if let Some(refspec) = refspec.as_deref() {
            args.push(refspec);
        }
        self.network
            .run(NAME, args, GitCredentialOperation::Fetch, remote.clone())
            .await
    }
}
