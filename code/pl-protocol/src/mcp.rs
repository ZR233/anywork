use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// 无敏感信息的 MCP server 描述。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpServerDescriptor {
    pub id: String,
    pub source: String,
    pub transport: String,
    pub endpoint: String,
    pub built_in: bool,
}

/// MCP server 当前可用性的公共投影。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpAvailabilityDescriptor {
    pub server: McpServerDescriptor,
    pub availability: String,
    pub message: Option<String>,
    pub last_checked_at: Option<i64>,
    pub tool_count: Option<usize>,
}

/// 某个 runtime generation 的无敏感信息健康快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpHealthSnapshot {
    pub generation: u64,
    pub servers: Vec<McpAvailabilityDescriptor>,
}

/// MCP 配置与运行时状态所属的环境作用域。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum McpScope {
    Host,
    Ssh {
        #[serde(rename = "sshAlias")]
        ssh_alias: String,
    },
}

/// `<StudioHome>` 下的 MCP 单文件配置引用。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpDocumentRef {
    pub scope: McpScope,
    /// `<StudioHome>` 下的规范相对路径，如 `mcp/host/filesystem.toml` 或 `mcp/ssh/<ssh-key>/<id-key>.toml`。
    pub relative_path: String,
}

/// 环境作用域内唯一的 MCP server 标识。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpServerKey {
    pub scope: McpScope,
    pub id: String,
}

/// 指定环境作用域的 MCP 配置目录快照。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpCatalogSnapshot {
    pub scope: McpScope,
    pub revision: u64,
    pub entries: Vec<McpCatalogEntry>,
    pub diagnostics: Vec<McpDocumentDiagnostic>,
}

/// MCP 目录中的单条有效/继承/覆盖/坏文件投影。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpCatalogEntry {
    pub id: String,
    pub document: Option<McpDocumentRef>,
    pub config_status: McpConfigStatusKind,
    pub effective_source: McpEffectiveSource,
    pub execution_location: Option<McpExecutionLocation>,
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

/// MCP 单文件解析或校验诊断。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpDocumentDiagnostic {
    pub document: McpDocumentRef,
    pub id: Option<String>,
    pub code: String,
    pub message: String,
}

/// MCP 条目在静态配置目录中的状态分类。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum McpConfigStatusKind {
    Enabled,
    Disabled,
    ShadowedDisable,
    MissingPrereq,
    InvalidDocument,
}

/// MCP 条目的生效来源。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum McpEffectiveSource {
    HostServer,
    HostBuiltin,
    InheritedHostServer,
    InheritedHostBuiltin,
    SshOverrideServer,
    SshOverrideBuiltin,
    SshDisabledTombstone,
    InvalidFile,
}

/// MCP 条目的执行位置。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum McpExecutionLocation {
    HostLocal,
    SshRemote {
        #[serde(rename = "sshAlias")]
        ssh_alias: String,
    },
    HostRemoteStreamableHttp,
    SshRemoteStreamableHttp {
        #[serde(rename = "sshAlias")]
        ssh_alias: String,
    },
}

/// 单个 MCP 配置文件的只读源码与修订。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpDocumentContent {
    pub document: McpDocumentRef,
    pub id: Option<String>,
    pub revision: u64,
    pub raw_toml: String,
    pub diagnostic: Option<McpDocumentDiagnostic>,
}

/// MCP 单文件创建、更新或删除的提交回执。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct McpDocumentCommitReceipt {
    pub document: Option<McpDocumentRef>,
    pub revision: u64,
    pub snapshot: McpCatalogSnapshot,
}

/// 创建 MCP 单文件配置请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CreateMcpDocumentRequest {
    pub scope: McpScope,
    pub id: String,
    pub raw_toml: String,
}

/// 更新 MCP 单文件配置请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct UpdateMcpDocumentRequest {
    pub document: McpDocumentRef,
    pub expected_revision: u64,
    pub raw_toml: String,
}

/// 删除 MCP 单文件配置请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct DeleteMcpDocumentRequest {
    pub document: McpDocumentRef,
    pub expected_revision: u64,
}

/// 重新加载指定环境作用域的 MCP 配置目录请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ReloadMcpCatalogRequest {
    pub scope: McpScope,
}

/// 重连指定 Thread 的全部或单个 MCP server 请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ReconnectThreadMcpRequest {
    pub thread_id: String,
    pub server_id: Option<String>,
}

/// 单个打开 Thread 的实时 MCP 运行时状态快照。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ThreadMcpStateSnapshot {
    pub thread_id: String,
    pub scope: McpScope,
    pub generation: u64,
    pub servers: Vec<ThreadMcpServerState>,
}

/// 单个 Thread 内某台 MCP server 的实时连接状态。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ThreadMcpServerState {
    pub id: String,
    pub effective_source: McpEffectiveSource,
    pub execution_location: McpExecutionLocation,
    pub transport: String,
    pub endpoint_summary: String,
    pub built_in: bool,
    pub lifecycle: ThreadMcpLifecycleKind,
    pub tool_count: Option<usize>,
    pub message: Option<String>,
    pub last_checked_at: Option<i64>,
}

/// Thread 内单台 MCP server 的生命周期状态分类。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ThreadMcpLifecycleKind {
    Connecting,
    Available,
    Unavailable,
    Unsupported,
    ShuttingDown,
}
