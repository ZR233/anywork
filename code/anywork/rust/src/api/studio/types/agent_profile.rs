use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeAgentWorkspaceMode {
    Unrestricted,
    Directory,
    Worktree,
    Review,
}

impl From<pl_protocol::AgentWorkspaceMode> for BridgeAgentWorkspaceMode {
    fn from(value: pl_protocol::AgentWorkspaceMode) -> Self {
        match value {
            pl_protocol::AgentWorkspaceMode::Unrestricted => Self::Unrestricted,
            pl_protocol::AgentWorkspaceMode::Directory => Self::Directory,
            pl_protocol::AgentWorkspaceMode::Worktree => Self::Worktree,
            pl_protocol::AgentWorkspaceMode::Review => Self::Review,
        }
    }
}

/// Agent Profile 设置页使用的只读快照；系统 Profile 的 `system` 为 true。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeAgentProfileDto {
    pub definition: BridgeAgentDefinitionSnapshot,
    pub binding: super::BridgeAgentBinding,
    pub system: bool,
    pub enabled: bool,
    pub workspace_mode: BridgeAgentWorkspaceMode,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeAgentDefinitionSnapshot {
    pub definition_id: String,
    pub display_name: String,
    pub description: String,
    pub when_to_use: String,
    pub source: String,
    pub revision: String,
    pub content_hash: String,
}

impl From<pl_protocol::AgentDefinitionSnapshot> for BridgeAgentDefinitionSnapshot {
    fn from(profile: pl_protocol::AgentDefinitionSnapshot) -> Self {
        Self {
            definition_id: profile.definition_id,
            display_name: profile.display_name,
            description: profile.description,
            when_to_use: profile.when_to_use,
            source: profile.source,
            revision: profile.revision,
            content_hash: profile.content_hash,
        }
    }
}

impl From<BridgeAgentDefinitionSnapshot> for pl_protocol::AgentDefinitionSnapshot {
    fn from(profile: BridgeAgentDefinitionSnapshot) -> Self {
        Self {
            definition_id: profile.definition_id,
            display_name: profile.display_name,
            description: profile.description,
            when_to_use: profile.when_to_use,
            source: profile.source,
            revision: profile.revision,
            content_hash: profile.content_hash,
        }
    }
}

impl From<pl_protocol::AgentProfile> for BridgeAgentProfileDto {
    fn from(profile: pl_protocol::AgentProfile) -> Self {
        Self {
            definition: profile.definition.into(),
            binding: profile.binding.into(),
            system: profile.system,
            enabled: profile.enabled,
            workspace_mode: profile.workspace_mode.into(),
        }
    }
}

impl From<BridgeAgentWorkspaceMode> for pl_protocol::AgentWorkspaceMode {
    fn from(value: BridgeAgentWorkspaceMode) -> Self {
        match value {
            BridgeAgentWorkspaceMode::Unrestricted => Self::Unrestricted,
            BridgeAgentWorkspaceMode::Directory => Self::Directory,
            BridgeAgentWorkspaceMode::Worktree => Self::Worktree,
            BridgeAgentWorkspaceMode::Review => Self::Review,
        }
    }
}

impl From<BridgeAgentProfileDto> for pl_protocol::AgentProfile {
    fn from(profile: BridgeAgentProfileDto) -> Self {
        Self {
            definition: profile.definition.into(),
            binding: profile.binding.into(),
            system: profile.system,
            enabled: profile.enabled,
            workspace_mode: profile.workspace_mode.into(),
        }
    }
}
