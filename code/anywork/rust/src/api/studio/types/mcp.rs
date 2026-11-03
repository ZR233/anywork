use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum BridgeMcpScope {
    Host,
    Ssh {
        #[serde(rename = "sshAlias")]
        ssh_alias: String,
    },
}

impl From<BridgeMcpScope> for pl_protocol::McpScope {
    fn from(value: BridgeMcpScope) -> Self {
        match value {
            BridgeMcpScope::Host => Self::Host,
            BridgeMcpScope::Ssh { ssh_alias } => Self::Ssh { ssh_alias },
        }
    }
}

impl From<pl_protocol::McpScope> for BridgeMcpScope {
    fn from(value: pl_protocol::McpScope) -> Self {
        match value {
            pl_protocol::McpScope::Host => Self::Host,
            pl_protocol::McpScope::Ssh { ssh_alias } => Self::Ssh { ssh_alias },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpDocumentRef {
    pub scope: BridgeMcpScope,
    pub relative_path: String,
}

impl From<BridgeMcpDocumentRef> for pl_protocol::McpDocumentRef {
    fn from(value: BridgeMcpDocumentRef) -> Self {
        Self {
            scope: value.scope.into(),
            relative_path: value.relative_path,
        }
    }
}

impl From<pl_protocol::McpDocumentRef> for BridgeMcpDocumentRef {
    fn from(value: pl_protocol::McpDocumentRef) -> Self {
        Self {
            scope: value.scope.into(),
            relative_path: value.relative_path,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BridgeMcpConfigStatusKind {
    Enabled,
    Disabled,
    ShadowedDisable,
    MissingPrereq,
    InvalidDocument,
}

impl From<pl_protocol::McpConfigStatusKind> for BridgeMcpConfigStatusKind {
    fn from(value: pl_protocol::McpConfigStatusKind) -> Self {
        match value {
            pl_protocol::McpConfigStatusKind::Enabled => Self::Enabled,
            pl_protocol::McpConfigStatusKind::Disabled => Self::Disabled,
            pl_protocol::McpConfigStatusKind::ShadowedDisable => Self::ShadowedDisable,
            pl_protocol::McpConfigStatusKind::MissingPrereq => Self::MissingPrereq,
            pl_protocol::McpConfigStatusKind::InvalidDocument => Self::InvalidDocument,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BridgeMcpEffectiveSource {
    HostServer,
    HostBuiltin,
    InheritedHostServer,
    InheritedHostBuiltin,
    SshOverrideServer,
    SshOverrideBuiltin,
    SshDisabledTombstone,
    InvalidFile,
}

impl From<pl_protocol::McpEffectiveSource> for BridgeMcpEffectiveSource {
    fn from(value: pl_protocol::McpEffectiveSource) -> Self {
        match value {
            pl_protocol::McpEffectiveSource::HostServer => Self::HostServer,
            pl_protocol::McpEffectiveSource::HostBuiltin => Self::HostBuiltin,
            pl_protocol::McpEffectiveSource::InheritedHostServer => Self::InheritedHostServer,
            pl_protocol::McpEffectiveSource::InheritedHostBuiltin => Self::InheritedHostBuiltin,
            pl_protocol::McpEffectiveSource::SshOverrideServer => Self::SshOverrideServer,
            pl_protocol::McpEffectiveSource::SshOverrideBuiltin => Self::SshOverrideBuiltin,
            pl_protocol::McpEffectiveSource::SshDisabledTombstone => Self::SshDisabledTombstone,
            pl_protocol::McpEffectiveSource::InvalidFile => Self::InvalidFile,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum BridgeMcpExecutionLocation {
    HostLocal,
    HostRemoteStreamableHttp,
    SshRemote {
        #[serde(rename = "sshAlias")]
        ssh_alias: String,
    },
    SshRemoteStreamableHttp {
        #[serde(rename = "sshAlias")]
        ssh_alias: String,
    },
}

impl From<pl_protocol::McpExecutionLocation> for BridgeMcpExecutionLocation {
    fn from(value: pl_protocol::McpExecutionLocation) -> Self {
        match value {
            pl_protocol::McpExecutionLocation::HostLocal => Self::HostLocal,
            pl_protocol::McpExecutionLocation::HostRemoteStreamableHttp => {
                Self::HostRemoteStreamableHttp
            }
            pl_protocol::McpExecutionLocation::SshRemote { ssh_alias } => {
                Self::SshRemote { ssh_alias }
            }
            pl_protocol::McpExecutionLocation::SshRemoteStreamableHttp { ssh_alias } => {
                Self::SshRemoteStreamableHttp { ssh_alias }
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpCatalogEntry {
    pub id: String,
    pub document: Option<BridgeMcpDocumentRef>,
    pub config_status: BridgeMcpConfigStatusKind,
    pub effective_source: BridgeMcpEffectiveSource,
    pub execution_location: Option<BridgeMcpExecutionLocation>,
    pub transport: Option<String>,
    pub endpoint_summary: Option<String>,
    pub built_in: bool,
    pub inherited_from_host: bool,
    pub overridden_in_scope: bool,
    pub can_override_in_ssh: bool,
    pub can_disable_in_ssh: bool,
    pub can_restore_inheritance: bool,
    pub message: Option<String>,
}

impl From<pl_protocol::McpCatalogEntry> for BridgeMcpCatalogEntry {
    fn from(value: pl_protocol::McpCatalogEntry) -> Self {
        Self {
            id: value.id,
            document: value.document.map(Into::into),
            config_status: value.config_status.into(),
            effective_source: value.effective_source.into(),
            execution_location: value.execution_location.map(Into::into),
            transport: value.transport,
            endpoint_summary: value.endpoint_summary,
            built_in: value.built_in,
            inherited_from_host: value.inherited_from_host,
            overridden_in_scope: value.overridden_in_scope,
            can_override_in_ssh: value.can_override_in_ssh,
            can_disable_in_ssh: value.can_disable_in_ssh,
            can_restore_inheritance: value.can_restore_inheritance,
            message: value.message,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpDocumentDiagnostic {
    pub document: BridgeMcpDocumentRef,
    pub id: Option<String>,
    pub code: String,
    pub message: String,
}

impl From<pl_protocol::McpDocumentDiagnostic> for BridgeMcpDocumentDiagnostic {
    fn from(value: pl_protocol::McpDocumentDiagnostic) -> Self {
        Self {
            document: value.document.into(),
            id: value.id,
            code: value.code,
            message: value.message,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpCatalogSnapshot {
    pub scope: BridgeMcpScope,
    pub revision: u64,
    pub entries: Vec<BridgeMcpCatalogEntry>,
    pub diagnostics: Vec<BridgeMcpDocumentDiagnostic>,
}

impl From<pl_protocol::McpCatalogSnapshot> for BridgeMcpCatalogSnapshot {
    fn from(value: pl_protocol::McpCatalogSnapshot) -> Self {
        Self {
            scope: value.scope.into(),
            revision: value.revision,
            entries: value.entries.into_iter().map(Into::into).collect(),
            diagnostics: value.diagnostics.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpDocumentContent {
    pub document: BridgeMcpDocumentRef,
    pub id: Option<String>,
    pub revision: u64,
    pub raw_toml: String,
    pub diagnostic: Option<BridgeMcpDocumentDiagnostic>,
}

impl From<pl_protocol::McpDocumentContent> for BridgeMcpDocumentContent {
    fn from(value: pl_protocol::McpDocumentContent) -> Self {
        Self {
            document: value.document.into(),
            id: value.id,
            revision: value.revision,
            raw_toml: value.raw_toml,
            diagnostic: value.diagnostic.map(Into::into),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeCreateMcpDocumentInput {
    pub scope: BridgeMcpScope,
    pub id: String,
    pub raw_toml: String,
}

impl From<BridgeCreateMcpDocumentInput> for pl_protocol::CreateMcpDocumentRequest {
    fn from(value: BridgeCreateMcpDocumentInput) -> Self {
        Self {
            scope: value.scope.into(),
            id: value.id,
            raw_toml: value.raw_toml,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeUpdateMcpDocumentInput {
    pub document: BridgeMcpDocumentRef,
    pub expected_revision: u64,
    pub raw_toml: String,
}

impl From<BridgeUpdateMcpDocumentInput> for pl_protocol::UpdateMcpDocumentRequest {
    fn from(value: BridgeUpdateMcpDocumentInput) -> Self {
        Self {
            document: value.document.into(),
            expected_revision: value.expected_revision,
            raw_toml: value.raw_toml,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeDeleteMcpDocumentInput {
    pub document: BridgeMcpDocumentRef,
    pub expected_revision: u64,
}

impl From<BridgeDeleteMcpDocumentInput> for pl_protocol::DeleteMcpDocumentRequest {
    fn from(value: BridgeDeleteMcpDocumentInput) -> Self {
        Self {
            document: value.document.into(),
            expected_revision: value.expected_revision,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeMcpDocumentCommitReceipt {
    pub document: Option<BridgeMcpDocumentRef>,
    pub revision: u64,
    pub snapshot: BridgeMcpCatalogSnapshot,
}

impl From<pl_protocol::McpDocumentCommitReceipt> for BridgeMcpDocumentCommitReceipt {
    fn from(value: pl_protocol::McpDocumentCommitReceipt) -> Self {
        Self {
            document: value.document.map(Into::into),
            revision: value.revision,
            snapshot: value.snapshot.into(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BridgeThreadMcpLifecycleKind {
    Connecting,
    Available,
    Unavailable,
    Unsupported,
    ShuttingDown,
}

impl From<pl_protocol::ThreadMcpLifecycleKind> for BridgeThreadMcpLifecycleKind {
    fn from(value: pl_protocol::ThreadMcpLifecycleKind) -> Self {
        match value {
            pl_protocol::ThreadMcpLifecycleKind::Connecting => Self::Connecting,
            pl_protocol::ThreadMcpLifecycleKind::Available => Self::Available,
            pl_protocol::ThreadMcpLifecycleKind::Unavailable => Self::Unavailable,
            pl_protocol::ThreadMcpLifecycleKind::Unsupported => Self::Unsupported,
            pl_protocol::ThreadMcpLifecycleKind::ShuttingDown => Self::ShuttingDown,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadMcpServerState {
    pub id: String,
    pub effective_source: BridgeMcpEffectiveSource,
    pub execution_location: BridgeMcpExecutionLocation,
    pub transport: String,
    pub endpoint_summary: String,
    pub built_in: bool,
    pub lifecycle: BridgeThreadMcpLifecycleKind,
    pub tool_count: Option<u64>,
    pub message: Option<String>,
    pub last_checked_at: Option<i64>,
}

impl From<pl_protocol::ThreadMcpServerState> for BridgeThreadMcpServerState {
    fn from(value: pl_protocol::ThreadMcpServerState) -> Self {
        Self {
            id: value.id,
            effective_source: value.effective_source.into(),
            execution_location: value.execution_location.into(),
            transport: value.transport,
            endpoint_summary: value.endpoint_summary,
            built_in: value.built_in,
            lifecycle: value.lifecycle.into(),
            tool_count: value.tool_count.and_then(|count| u64::try_from(count).ok()),
            message: value.message,
            last_checked_at: value.last_checked_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeThreadMcpStateSnapshot {
    pub thread_id: String,
    pub scope: BridgeMcpScope,
    pub generation: u64,
    pub servers: Vec<BridgeThreadMcpServerState>,
}

impl From<pl_protocol::ThreadMcpStateSnapshot> for BridgeThreadMcpStateSnapshot {
    fn from(value: pl_protocol::ThreadMcpStateSnapshot) -> Self {
        Self {
            thread_id: value.thread_id,
            scope: value.scope.into(),
            generation: value.generation,
            servers: value.servers.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeReconnectThreadMcpInput {
    pub thread_id: String,
    pub server_id: Option<String>,
}

impl From<BridgeReconnectThreadMcpInput> for pl_protocol::ReconnectThreadMcpRequest {
    fn from(value: BridgeReconnectThreadMcpInput) -> Self {
        Self {
            thread_id: value.thread_id,
            server_id: value.server_id,
        }
    }
}
