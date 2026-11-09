//! Product policy identities for the independent Git declarations.

use pl_agent_tool::{InputFormat, ToolDefinition};
use serde_json::Value;

use crate::approval::ToolEffect;

pub const TOOL_GIT_STATUS: &str = pl_tool_git_status::NAME;
pub const TOOL_GIT_DIFF: &str = pl_tool_git_diff::NAME;
pub const TOOL_GIT_BRANCH: &str = pl_tool_git_branch::NAME;
pub const TOOL_GIT_FETCH: &str = pl_tool_git_fetch::NAME;
pub const TOOL_GIT_COMMIT: &str = pl_tool_git_commit::NAME;
pub const TOOL_GIT_PUSH: &str = pl_tool_git_push::NAME;
pub const TOOL_GIT_WORKSPACE_INFO: &str = pl_tool_git_workspace_info::NAME;
pub const TOOL_GIT_SYNC_DEFAULT_BRANCH: &str = pl_tool_git_sync_default_branch::NAME;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitToolKind {
    Status,
    Diff,
    Branch,
    Fetch,
    Commit,
    Push,
    WorkspaceInfo,
    SyncDefaultBranch,
}

impl GitToolKind {
    pub fn all() -> &'static [Self] {
        &[
            Self::Status,
            Self::Diff,
            Self::Branch,
            Self::Fetch,
            Self::Commit,
            Self::Push,
            Self::WorkspaceInfo,
            Self::SyncDefaultBranch,
        ]
    }

    pub fn from_name(name: &str) -> Option<Self> {
        Self::all().iter().copied().find(|kind| kind.name() == name)
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Status => TOOL_GIT_STATUS,
            Self::Diff => TOOL_GIT_DIFF,
            Self::Branch => TOOL_GIT_BRANCH,
            Self::Fetch => TOOL_GIT_FETCH,
            Self::Commit => TOOL_GIT_COMMIT,
            Self::Push => TOOL_GIT_PUSH,
            Self::WorkspaceInfo => TOOL_GIT_WORKSPACE_INFO,
            Self::SyncDefaultBranch => TOOL_GIT_SYNC_DEFAULT_BRANCH,
        }
    }

    pub fn effect(self) -> ToolEffect {
        match self {
            Self::Status | Self::Diff | Self::WorkspaceInfo => ToolEffect::Read,
            Self::Branch | Self::Fetch | Self::Commit | Self::Push | Self::SyncDefaultBranch => {
                ToolEffect::BranchControl
            }
        }
    }

    pub fn input_schema(self) -> Value {
        let definition = self.definition();
        let InputFormat::JsonSchema(schema) = definition.input() else {
            unreachable!("all Git tools consume JSON")
        };
        schema.clone()
    }

    pub fn definition(self) -> ToolDefinition {
        match self {
            Self::Status => pl_tool_git_status::definition(),
            Self::Diff => pl_tool_git_diff::definition(),
            Self::Branch => pl_tool_git_branch::definition(),
            Self::Fetch => pl_tool_git_fetch::definition(),
            Self::Commit => pl_tool_git_commit::definition(),
            Self::Push => pl_tool_git_push::definition(),
            Self::WorkspaceInfo => pl_tool_git_workspace_info::definition(),
            Self::SyncDefaultBranch => pl_tool_git_sync_default_branch::definition(),
        }
    }
}
