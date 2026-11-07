use pl_agent_tool::ToolDefinition;
use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::Value;

use crate::approval::ToolEffect;
use pl_agent_tool::typed::input_schema_for;

pub const TOOL_GIT_STATUS: &str = "git_status";
pub const TOOL_GIT_DIFF: &str = "git_diff";
pub const TOOL_GIT_BRANCH: &str = "git_branch";
pub const TOOL_GIT_FETCH: &str = "git_fetch";
pub const TOOL_GIT_COMMIT: &str = "git_commit";
pub const TOOL_GIT_PUSH: &str = "git_push";
pub const TOOL_GIT_WORKSPACE_INFO: &str = "git_workspace_info";
pub const TOOL_GIT_SYNC_DEFAULT_BRANCH: &str = "git_sync_default_branch";

/// pl-core 提供的通用 git 工具类型。
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
        match name {
            TOOL_GIT_STATUS => Some(Self::Status),
            TOOL_GIT_DIFF => Some(Self::Diff),
            TOOL_GIT_BRANCH => Some(Self::Branch),
            TOOL_GIT_FETCH => Some(Self::Fetch),
            TOOL_GIT_COMMIT => Some(Self::Commit),
            TOOL_GIT_PUSH => Some(Self::Push),
            TOOL_GIT_WORKSPACE_INFO => Some(Self::WorkspaceInfo),
            TOOL_GIT_SYNC_DEFAULT_BRANCH => Some(Self::SyncDefaultBranch),
            _ => None,
        }
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

    /// 该类别 git 工具的副作用声明。
    pub fn effect(self) -> ToolEffect {
        match self {
            Self::Status | Self::Diff | Self::WorkspaceInfo => ToolEffect::Read,
            Self::Branch | Self::Fetch | Self::Commit | Self::Push | Self::SyncDefaultBranch => {
                ToolEffect::BranchControl
            }
        }
    }

    pub(super) fn description(self) -> &'static str {
        match self {
            Self::Status => "Show git working tree status for this workspace.",
            Self::Diff => "Show git diff for this workspace.",
            Self::Branch => "List branches or create/switch the current branch.",
            Self::Fetch => "Fetch from the repository remote using host-injected credentials.",
            Self::Commit => "Create a git commit in this workspace.",
            Self::Push => "Push the current branch using host-injected credentials.",
            Self::WorkspaceInfo => "Show information about this git workspace.",
            Self::SyncDefaultBranch => {
                "Synchronize this workspace branch with the configured default branch."
            }
        }
    }

    pub fn input_schema(self) -> Value {
        match self {
            Self::Status | Self::WorkspaceInfo => input_schema_for::<GitEmptyInput>(),
            Self::Diff => input_schema_for::<GitDiffInput>(),
            Self::Branch => input_schema_for::<GitBranchInput>(),
            Self::Fetch => input_schema_for::<GitFetchInput>(),
            Self::Commit => input_schema_for::<GitCommitInput>(),
            Self::Push => input_schema_for::<GitPushInput>(),
            Self::SyncDefaultBranch => input_schema_for::<GitSyncDefaultBranchInput>(),
        }
    }

    pub fn definition(self) -> ToolDefinition {
        ToolDefinition::json(self.name(), self.description(), self.input_schema())
            .expect("valid tool definition")
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub(super) struct GitEmptyInput {}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct GitDiffInput {
    /// Show staged changes instead of unstaged changes.
    #[serde(default)]
    pub(super) staged: bool,
    /// Optional repository-relative path to limit the diff.
    pub(super) path: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct GitBranchInput {
    /// Branch action; defaults to list.
    pub(super) action: Option<GitBranchAction>,
    /// Branch name used by switch and create.
    pub(super) name: Option<String>,
    /// Optional starting revision for create.
    pub(super) start_point: Option<String>,
}

#[derive(Debug, Clone, Copy, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub(super) enum GitBranchAction {
    List,
    Switch,
    Create,
}

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
pub(super) struct GitFetchInput {
    remote: GitRemoteInput,
    pub(super) refspec: Option<String>,
    pub(super) prune: bool,
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
    pub(super) fn remote(&self) -> Option<String> {
        self.remote.remote.clone()
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct GitCommitInput {
    /// Commit message.
    pub(super) message: String,
    /// Commit all tracked modified and deleted files.
    #[serde(default)]
    pub(super) all: bool,
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
pub(super) struct GitPushInput {
    remote: GitRemoteInput,
    pub(super) branch: Option<String>,
    pub(super) set_upstream: bool,
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
    pub(super) fn remote(&self) -> Option<String> {
        self.remote.remote.clone()
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct GitSyncDefaultBranchInput {
    /// Discard uncommitted workspace changes while syncing.
    #[serde(default)]
    pub(super) force: bool,
    /// Stash uncommitted changes before syncing and restore them afterwards.
    #[serde(default)]
    pub(super) preserve_changes: bool,
}

fn default_true() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_agent_tool::typed::{ArgumentError, decode_json, input_schema_for};

    #[test]
    fn strict_wire_defaults_schema_and_raw_decode_share_the_contract() {
        let fetch: GitFetchInput = decode_json("{}").unwrap();
        assert_eq!(fetch.remote(), None);
        assert_eq!(fetch.refspec, None);
        assert!(fetch.prune);
        let push: GitPushInput = decode_json("{}").unwrap();
        assert_eq!(push.remote(), None);
        assert_eq!(push.branch, None);
        assert!(!push.set_upstream);
        let fetch: GitFetchInput =
            decode_json(r#"{"remote":"upstream","refspec":"main","prune":false}"#).unwrap();
        assert_eq!(fetch.remote().as_deref(), Some("upstream"));
        assert_eq!(fetch.refspec.as_deref(), Some("main"));
        assert!(!fetch.prune);
        let push: GitPushInput =
            decode_json(r#"{"remote":"fork","branch":"topic","setUpstream":true}"#).unwrap();
        assert_eq!(push.remote().as_deref(), Some("fork"));
        assert_eq!(push.branch.as_deref(), Some("topic"));
        assert!(push.set_upstream);

        for schema in [
            input_schema_for::<GitFetchInput>(),
            input_schema_for::<GitPushInput>(),
        ] {
            assert_eq!(schema["additionalProperties"], false);
            assert_eq!(
                schema["properties"]["remote"]["type"],
                serde_json::json!(["string", "null"])
            );
        }
        assert_eq!(
            input_schema_for::<GitFetchInput>()["properties"]["prune"]["default"],
            true
        );
        assert_eq!(
            input_schema_for::<GitPushInput>()["properties"]["setUpstream"]["default"],
            false
        );

        for raw in [r#"{"unexpected":1}"#, r#"{"remote":{}}"#] {
            for error in [
                decode_json::<GitFetchInput>(raw).unwrap_err(),
                decode_json::<GitPushInput>(raw).unwrap_err(),
            ] {
                let ArgumentError::Decode { source, .. } = error else {
                    panic!("not a decode failure")
                };
                assert!(source.column() > 0);
            }
        }
        assert!(matches!(
            decode_json::<GitFetchInput>("{} {}"),
            Err(ArgumentError::Trailing { .. })
        ));
        assert!(matches!(
            decode_json::<GitPushInput>("{} {}"),
            Err(ArgumentError::Trailing { .. })
        ));
    }
}
