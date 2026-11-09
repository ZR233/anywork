//! Anywork binding for the eight independently executable Git tools.
//!
//! Repository selection, authorization, cancellation and history mapping stay
//! here; declarations, argument validation and Git orchestration live in tools.

use std::sync::Arc;

use pl_agent_tool::{Tool, ToolDefinition};
use pl_core::tool::{ToolOutput, opaque::ToolError};
use pl_tool_git_support::{
    GitCommand, GitCommandOutput, GitError, GitExecutor, GitNetwork, GitOutput, GitRunner,
};

use crate::execution::{ExecutionBackend, ExecutionRequest};

mod error;
mod schema;
pub use error::GitHostError;
pub use pl_tool_git_support::{
    GIT_TOKEN_ENV, GitCredential, GitCredentialOperation, GitCredentialProvider,
    GitCredentialRequest, GitPolicy, GitWorkspaceConfig, NoGitCredentialProvider,
    git_askpass_script,
};
pub use schema::*;

#[derive(Debug)]
struct HostGitBackend<B>(Arc<B>);

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
struct HostGitExecutionError(#[source] pl_tool_git_support::BoxError);

impl<B> GitExecutor for HostGitBackend<B>
where
    B: ExecutionBackend,
    B::Error: Into<pl_tool_git_support::BoxError>,
{
    type Error = HostGitExecutionError;

    async fn run(&self, command: GitCommand) -> Result<GitCommandOutput, Self::Error> {
        let output = self
            .0
            .run(ExecutionRequest {
                program: command.program,
                args: command.args,
                cwd: command.cwd,
                env: command.env,
                timeout: command.timeout,
            })
            .await
            .map_err(|source| HostGitExecutionError(source.into()))?;
        Ok(GitCommandOutput {
            status: output.status,
            stdout: output.stdout,
            stderr: output.stderr,
        })
    }
}

#[derive(Debug)]
enum BoundGit<B, P> {
    Status(pl_tool_git_status::GitStatus<HostGitBackend<B>>),
    Diff(pl_tool_git_diff::GitDiff<HostGitBackend<B>>),
    Branch(pl_tool_git_branch::GitBranch<HostGitBackend<B>>),
    Fetch(pl_tool_git_fetch::GitFetch<HostGitBackend<B>, P>),
    Commit(pl_tool_git_commit::GitCommit<HostGitBackend<B>>),
    Push(pl_tool_git_push::GitPush<HostGitBackend<B>, P>),
    WorkspaceInfo(pl_tool_git_workspace_info::GitWorkspaceInfo),
    SyncDefaultBranch(pl_tool_git_sync_default_branch::GitSyncDefaultBranch<HostGitBackend<B>, P>),
}

/// Static product adaptation; this type contains no Git command planning.
#[derive(Debug)]
pub struct GitTool<B, P> {
    kind: GitToolKind,
    bound: BoundGit<B, P>,
}

impl<B, P> GitTool<B, P>
where
    B: ExecutionBackend + 'static,
    B::Error: Into<pl_tool_git_support::BoxError>,
    P: GitCredentialProvider + 'static,
{
    pub fn new(
        kind: GitToolKind,
        config: GitWorkspaceConfig,
        backend: Arc<B>,
        credential_provider: Arc<P>,
        definition: ToolDefinition,
    ) -> Self {
        let runner = GitRunner::new(config.clone(), Arc::new(HostGitBackend(backend)));
        let bound = match kind {
            GitToolKind::Status => {
                BoundGit::Status(pl_tool_git_status::GitStatus::new(runner, definition))
            }
            GitToolKind::Diff => BoundGit::Diff(pl_tool_git_diff::GitDiff::new(runner, definition)),
            GitToolKind::Branch => {
                BoundGit::Branch(pl_tool_git_branch::GitBranch::new(runner, definition))
            }
            GitToolKind::Fetch => BoundGit::Fetch(pl_tool_git_fetch::GitFetch::new(
                GitNetwork::new(runner, credential_provider),
                definition,
            )),
            GitToolKind::Commit => {
                BoundGit::Commit(pl_tool_git_commit::GitCommit::new(runner, definition))
            }
            GitToolKind::Push => BoundGit::Push(pl_tool_git_push::GitPush::new(
                GitNetwork::new(runner, credential_provider),
                definition,
            )),
            GitToolKind::WorkspaceInfo => BoundGit::WorkspaceInfo(
                pl_tool_git_workspace_info::GitWorkspaceInfo::new(config, definition),
            ),
            GitToolKind::SyncDefaultBranch => BoundGit::SyncDefaultBranch(
                pl_tool_git_sync_default_branch::GitSyncDefaultBranch::new(
                    GitNetwork::new(runner, credential_provider),
                    definition,
                ),
            ),
        };
        Self { kind, bound }
    }

    async fn invoke(&self, input: String) -> Result<GitOutput, GitError> {
        match &self.bound {
            BoundGit::Status(tool) => tool.execute(input, ()).await,
            BoundGit::Diff(tool) => tool.execute(input, ()).await,
            BoundGit::Branch(tool) => tool.execute(input, ()).await,
            BoundGit::Fetch(tool) => tool.execute(input, ()).await,
            BoundGit::Commit(tool) => tool.execute(input, ()).await,
            BoundGit::Push(tool) => tool.execute(input, ()).await,
            BoundGit::WorkspaceInfo(tool) => tool.execute(input, ()).await,
            BoundGit::SyncDefaultBranch(tool) => tool.execute(input, ()).await,
        }
    }

    /// Transfers this statically adapted instance under the host's policy identity.
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
        authorization: pl_core::tool::opaque::ToolAuthorization,
    ) -> pl_core::tool::opaque::Registration {
        prepared
            .attach(pl_agent_tool::ToolHandle::new(self))
            .with_authorization(authorization)
    }
}

impl<B, P> Tool for GitTool<B, P>
where
    B: ExecutionBackend + 'static,
    B::Error: Into<pl_tool_git_support::BoxError>,
    P: GitCredentialProvider + 'static,
{
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        match &self.bound {
            BoundGit::Status(tool) => tool.definition(),
            BoundGit::Diff(tool) => tool.definition(),
            BoundGit::Branch(tool) => tool.definition(),
            BoundGit::Fetch(tool) => tool.definition(),
            BoundGit::Commit(tool) => tool.definition(),
            BoundGit::Push(tool) => tool.definition(),
            BoundGit::WorkspaceInfo(tool) => tool.definition(),
            BoundGit::SyncDefaultBranch(tool) => tool.definition(),
        }
    }

    async fn execute(
        &self,
        input: pl_core::context::OpaquePayload,
        context: pl_core::tool::opaque::CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(crate::tool_error(
                self.kind.name(),
                "unsupported Git argument encoding",
            )));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        match self.invoke(input.content().to_owned()).await {
            Ok(output) => dynamic_output(&output),
            Err(source) => {
                let observed = source.observed().map(dynamic_output).transpose()?;
                let error = ToolError::new(GitHostError::new(self.kind.name(), source));
                Err(match observed {
                    Some(output) => error.with_output(output),
                    None => error,
                })
            }
        }
    }
}

fn dynamic_output(outcome: &GitOutput) -> Result<ToolOutput, ToolError> {
    use pl_core::context::{ContextContent, OpaquePayload};
    let description = outcome.payload().to_string();
    let preview = pl_output::bounded_text(&description, 12 * 1024, 0);
    let context = if preview.truncated {
        format!(
            "{}\n[Git preview omitted {} bytes; full result retained in history.]",
            preview.text, preview.bytes_omitted
        )
    } else {
        preview.text
    };
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.tool.git", 1, description).map_err(ToolError::new)?,
        vec![ContextContent::Text {
            text: Arc::from(context),
        }],
    ))
}
