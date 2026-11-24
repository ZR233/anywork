use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::commands::settings_command_reply;
use crate::api::studio::types::{
    BridgeAgentBinding, BridgeAgentWorkspaceMode, BridgeError, BridgeSettingsCommandReply,
};

/// Enables or disables an immutable built-in Agent Profile.
pub async fn set_system_agent_enabled(
    operation_id: String,
    profile_id: String,
    enabled: bool,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(settings_command_reply(
        bridge
            .studio
            .set_system_agent_enabled(operation_id, &profile_id, enabled)?,
    ))
}

/// Atomically creates or replaces one user Agent Profile TOML file.
#[allow(clippy::too_many_arguments)]
pub async fn save_user_agent_profile(
    operation_id: String,
    expected_document_revision: Option<String>,
    profile_id: String,
    enabled: bool,
    display_name: String,
    description: String,
    when_to_use: String,
    binding: BridgeAgentBinding,
    workspace_mode: BridgeAgentWorkspaceMode,
) -> Result<BridgeSettingsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let profile = pl_studio_runtime::UserAgentProfile {
        enabled,
        display_name,
        description,
        when_to_use,
        binding: binding.into(),
        workspace_mode: match workspace_mode {
            BridgeAgentWorkspaceMode::Unrestricted => {
                pl_studio_runtime::AgentWorkspaceMode::Unrestricted
            }
            BridgeAgentWorkspaceMode::Directory => pl_studio_runtime::AgentWorkspaceMode::Directory,
            BridgeAgentWorkspaceMode::Worktree => pl_studio_runtime::AgentWorkspaceMode::Worktree,
            BridgeAgentWorkspaceMode::Review => pl_studio_runtime::AgentWorkspaceMode::Review,
        },
    };
    Ok(settings_command_reply(
        bridge.studio.save_user_agent_profile(
            operation_id,
            expected_document_revision.as_deref(),
            &profile_id,
            &profile,
        )?,
    ))
}

/// Explicitly removes one revision-matched preserved Pure worktree and branch.
///
/// `owner_kind` must match the durable lease ownership (`session` or `child`); a mismatch
/// is rejected instead of falling back to the other source.
pub async fn cleanup_preserved_worktree(
    owner_kind: String,
    owner_thread_id: String,
    expected_lease_revision: u64,
) -> Result<(), BridgeError> {
    let bridge = active_bridge().await?;
    let owner_kind =
        match pl_studio_runtime::StudioRecoveryWorktreeOwner::from_label(owner_kind.trim()) {
            Some(owner_kind) => owner_kind,
            None => {
                return Err(anyhow::anyhow!(
                    "worktree cleanup requires ownerKind session or child, received {owner_kind:?}"
                )
                .into());
            }
        };
    bridge
        .studio
        .cleanup_preserved_worktree(owner_kind, &owner_thread_id, expected_lease_revision)
        .await?;
    Ok(())
}
