//! Frozen SSH workspaces reopen on their physical endpoint; the saved alias is only a handle.
use crate::studio::agent_host::worktree_lease::WorkspaceEndpoint;
use anyhow::{Context, Result};
use pl_tool::remote::{SshManager, SshWorkspaceBinding};

/// Reopens the workspace whose frozen `endpoint` resolves canonically to `root`.
///
/// Several saved profiles may share one endpoint, so the first matching alias opens it.
/// Opening may create the connection, as every frozen owner did before. The owner keeps its
/// diagnostics: `not_configured` when no saved profile matches the endpoint, `changed` when the
/// reopened binding is no longer that endpoint and canonical root.
pub(super) async fn open_frozen_workspace(
    ssh: &SshManager,
    endpoint: &WorkspaceEndpoint,
    root: &str,
    not_configured: &'static str,
    changed: &'static str,
) -> Result<SshWorkspaceBinding> {
    let profile = ssh
        .list_servers()
        .await
        .into_iter()
        .find(|entry| WorkspaceEndpoint::from_profile(Some(&entry.profile)) == *endpoint)
        .context(not_configured)?
        .profile;
    let host = ssh
        .open_workspace_binding(&profile.alias, root.to_owned())
        .await?;
    anyhow::ensure!(
        WorkspaceEndpoint::from_profile(Some(&host.profile)) == *endpoint
            && host.files().canonical_path() == root,
        "{changed}"
    );
    Ok(host)
}
