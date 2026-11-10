//! ACP 接入与认证的 Bridge DTO。
//!
//! 这里是 FRB 侧的镜像类型，字段与 `pl_protocol::studio::acp` 一一对应；不含认证凭据、原始进程
//! 输出或 SDK 类型。编辑投影保留调用方配置的 env，不能作为诊断输出。
//!
//! 通用接入保留独立的 command、args 与 env；受管接入通过可选 template 标识。

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use super::BridgeStudioCommandReceipt;

// ── 接入配置 ──

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpProvider {
    Antigravity,
}

/// canonical 设置中的一条 ACP 接入编辑投影。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAccountSettings {
    pub account_id: String,
    pub name: String,
    pub template: Option<BridgeAcpProvider>,
    pub enabled: bool,
    pub command: Option<String>,
    pub args: Vec<String>,
    pub env: HashMap<String, String>,
    pub document_revision: u64,
    /// runtime 拥有的非密钥连接身份；名称编辑不改变它。
    pub connection_revision: u64,
}

/// 一种接入类型的模板：固定的官方发行版本、图标与官方安装说明。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAccountTemplate {
    pub provider: BridgeAcpProvider,
    pub display_name: String,
    pub description: String,
    pub icon_key: String,
    /// 产品固定支持的官方 server 版本；客户端不硬编码第二份选择表。
    pub supported_version: String,
    pub install_url: String,
    /// 官方条款/隐私说明；空字符串表示不展示。
    pub terms_url: String,
    /// 当前宿主平台能否由产品自动准备官方 server。
    pub automatic_install: super::BridgeAcpInstallAvailability,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAccountCatalog {
    pub templates: Vec<BridgeAcpAccountTemplate>,
}

/// 保存一条接入的唯一意图。
#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAccountUpdate {
    pub account_id: String,
    pub name: String,
    pub template: Option<BridgeAcpProvider>,
    pub command: Option<String>,
    pub args: Option<Vec<String>>,
    pub env: HashMap<String, String>,
    pub enabled: bool,
}

// ── 认证观察 ──

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpAuthMethodKind {
    Agent,
    Terminal,
    /// 服务端声明的未知/未实现类型：明确不支持，不伪装成另一种真实方式。
    Unsupported,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAuthMethod {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub kind: BridgeAcpAuthMethodKind,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpServerInfo {
    pub name: String,
    pub title: Option<String>,
    pub version: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpAuthFailureCode {
    /// 固定发行的受管安装尚未准备：必须显式准备，不隐式下载或修复。
    PreparationRequired,
    /// 受管安装存在但与冻结描述符不一致。
    InstallationInvalid,
    /// 当前宿主平台没有产品支持的官方发行。
    UnsupportedPlatform,
    /// 协商出的 server 版本缺失或不是产品固定支持的版本。
    ServerVersionMismatch,
    Startup,
    MissingExecutable,
    Io,
    UnsupportedVersion,
    UnsupportedMethod,
    Authentication,
    Probe,
    Protocol,
    Transport,
    Timeout,
    ResourceLimit,
    Cancelled,
    StaleOperation,
    ConfigChanged,
    Cleanup,
    Internal,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpAuthStage {
    /// 启动前验证受管安装（只读）。
    Prepare,
    Process,
    Config,
    Initialize,
    Authenticate,
    Probe,
    Close,
    Cleanup,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAuthFailure {
    pub code: BridgeAcpAuthFailureCode,
    pub stage: BridgeAcpAuthStage,
    pub message: String,
    pub retryable: bool,
}

/// 一个接入的认证观察状态。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpAuthState {
    Unchecked,
    Checking {
        operation_id: String,
    },
    Required {
        operation_id: String,
        methods: Vec<BridgeAcpAuthMethod>,
        /// 协议观察；对端未提供 `agentInfo` 时为 `None`（未知），不用本地账号名冒充。
        server: Option<BridgeAcpServerInfo>,
    },
    Authenticating {
        operation_id: String,
        method_id: String,
    },
    Verifying {
        operation_id: String,
    },
    /// 协议已结束、进程与管道仍在收束的 busy 非终态。
    Closing {
        operation_id: String,
        failure: Option<BridgeAcpAuthFailure>,
    },
    Verified {
        checked_at: i64,
        server: Option<BridgeAcpServerInfo>,
    },
    Cancelling {
        operation_id: String,
    },
    Cancelled,
    Failed {
        failure: BridgeAcpAuthFailure,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAuthAccount {
    pub account_id: String,
    pub connection_revision: u64,
    pub state: BridgeAcpAuthState,
    pub usage: Option<BridgeAcpUsageObservation>,
    /// 当前操作槽位上的进行中操作；由 owner 与 state 同一提交边界投影。
    pub active_operation: Option<BridgeAcpAuthActiveOperation>,
}

/// 进行中认证操作在 FRB 镜像中的身份：ID、启动时冻结的连接修订与真实动作。
///
/// 连接已替换但旧操作仍在收束时，这里的修订可以小于账号当前修订。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAuthActiveOperation {
    pub operation_id: String,
    pub connection_revision: u64,
    pub action: BridgeAcpAuthAction,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpUsageObservation {
    pub checked_at: i64,
    pub state: BridgeAcpUsageState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpUsageState {
    Ready { groups: Vec<BridgeAcpQuotaGroup> },
    NotApplicable,
    Unavailable,
    Failed { code: BridgeAcpUsageFailureCode },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpUsageFailureCode {
    Query,
    Timeout,
    Transport,
    ResourceLimit,
    InvalidResponse,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpQuotaGroup {
    pub name: String,
    pub limits: Vec<BridgeAcpQuotaLimit>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpQuotaLimit {
    pub label: String,
    pub remaining: BridgeAcpQuotaRemaining,
    pub next_reset_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpQuotaRemaining {
    Percentage { value: u8 },
    Units { value: u64 },
    Unknown,
    Disabled,
}

/// ACP 认证 topic 的 canonical 快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BridgeAcpAuthSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub accounts: Vec<BridgeAcpAuthAccount>,
}

/// 认证命令输入动作。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BridgeAcpAuthAction {
    Check,
    QueryUsage,
}

/// 认证命令的受理回执与受理时快照。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpAuthCommandReply {
    pub receipt: BridgeStudioCommandReceipt,
    pub snapshot: BridgeAcpAuthSnapshot,
}
