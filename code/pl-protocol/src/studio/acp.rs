//! ACP 接入配置与认证观察的 typed wire DTO。
//!
//! 这些类型是 Studio 与外围 adapter（FRB/HTTP）之间的唯一公共契约：接入 desired 配置出现在
//! Settings 快照，认证进展是独立版本域的资源快照。ACP 不是 HTTP 模型协议，因此这里既不复用
//! Native account 的 endpoint/secret 结构，也不携带任何凭据、token、原始进程输出或 SDK 内部
//! 类型；官方程序自行管理登录凭据（见 design/28）。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::StudioCommandReceipt;

/// 支持的 ACP 接入类型。
///
/// 本阶段只有官方 Antigravity server；新增厂商必须同时提供真实模板与验收证据，不能用显示名
/// 或 template id 猜测执行协议。
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum AcpProvider {
    Antigravity,
}

impl AcpProvider {
    /// 稳定的 wire/配置标签；与配置 TOML 中的取值一致。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Antigravity => "antigravity",
        }
    }
}

/// canonical 设置中的一条 ACP 接入（不含 secret）。
///
/// `connection_revision` 是 runtime 拥有的**非密钥**连接身份：只有 provider/程序/参数真正变化
/// 才改变，名称编辑不改变它。它既不是 Settings revision，也不是认证 topic 的 revision。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAccountSettings {
    pub account_id: String,
    pub name: String,
    pub provider: AcpProvider,
    pub program: String,
    pub args: Vec<String>,
    pub connection_revision: u64,
}

/// 一种接入类型的模板：默认启动参数、图标与官方安装说明。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAccountTemplate {
    pub provider: AcpProvider,
    pub display_name: String,
    pub description: String,
    pub icon_key: String,
    pub default_args: Vec<String>,
    /// 官方安装/下载说明；空字符串表示本平台没有可确认的官方说明，UI 不展示链接。
    pub install_url: String,
}

/// ACP 模板目录；只读默认值，不启动任何程序。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAccountCatalog {
    pub templates: Vec<AcpAccountTemplate>,
}

/// 保存一条接入的唯一意图；不携带其它 settings 字段。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAccountUpdate {
    pub account_id: String,
    pub name: String,
    pub provider: AcpProvider,
    pub program: String,
    pub args: Vec<String>,
}

/// 保存/新增一条 ACP 接入。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateAcpAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account: AcpAccountUpdate,
}

/// 删除一条 ACP 接入；只移除本地接入，不注销官方账号或删除其凭据。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoveAcpAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
}

/// 一个显式认证动作。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "action", deny_unknown_fields)]
pub enum AcpAuthAction {
    /// 只检查连接与当前凭据状态。
    Check,
    /// 用服务端实际公布的方法登录。
    Authenticate { method_id: String },
}

/// 认证方法的实现类型；`terminal` 在本阶段没有专门实现，不能当作 agent 方法发送。
///
/// 服务端声明但本客户端未实现的类型归入 `Unsupported`，绝不伪装成 `Agent` 或 `Terminal`。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpAuthMethodKind {
    Agent,
    Terminal,
    Unsupported,
}

/// 服务端实际公布的认证方法。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthMethod {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub kind: AcpAuthMethodKind,
}

/// 已连接 server 的身份；只用于展示，不表示永久在线。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpServerInfo {
    pub name: String,
    pub title: Option<String>,
    pub version: String,
}

/// 认证失败的安全类别；原始原因只作内部诊断，不跨边界。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpAuthFailureCode {
    /// 无法启动官方程序或所需监督资源。
    Startup,
    /// 配置的程序路径不存在或不可执行。
    MissingExecutable,
    /// 文件系统、管道或其它本地 IO 失败。
    Io,
    /// 协商的 ACP 版本不受支持。
    UnsupportedVersion,
    /// 认证方法不支持（含仅有 terminal 方法）。
    UnsupportedMethod,
    /// 官方程序报告的认证失败。
    Authentication,
    /// `session/new` 探测失败。
    Probe,
    /// 协议错误或意外响应。
    Protocol,
    /// 管道断开或进程提前退出。
    Transport,
    /// 阶段超时。
    Timeout,
    /// 输出/资源预算超限。
    ResourceLimit,
    /// 显式取消。
    Cancelled,
    /// 操作已过期（配置变化、删除或迟到结果）。
    StaleOperation,
    /// 所属接入的连接身份已被改写，旧操作不再代表当前配置。
    ConfigChanged,
    /// 进程或管道未能确认回收。
    Cleanup,
    /// 内部不变量被破坏（例如受理期间接入记录消失）。
    Internal,
}

/// 失败发生在哪个阶段。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpAuthStage {
    /// 官方程序启动。
    Process,
    /// 读取或准备接入配置/探测目录。
    Config,
    Initialize,
    Authenticate,
    Probe,
    Close,
    /// 进程与管道收尾。
    Cleanup,
}

/// 类型化认证失败：阶段、类别、安全消息与可重试提示。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthFailure {
    pub code: AcpAuthFailureCode,
    pub stage: AcpAuthStage,
    /// 面向用户的安全摘要；不含 URL、token、原始 stderr 或 SDK 文本。
    pub message: String,
    pub retryable: bool,
}

/// 一个接入的认证观察状态。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum AcpAuthState {
    /// 重启后、保存后或身份变化后的初始状态。
    Unchecked,
    Checking {
        operation_id: String,
    },
    /// 需要登录；携带服务端实际公布的方法。
    ///
    /// `server` 是协议观察：对端未提供 `agentInfo` 时为 `None`，不能用本地账号名冒充服务端名称。
    Required {
        methods: Vec<AcpAuthMethod>,
        server: Option<AcpServerInfo>,
    },
    Authenticating {
        operation_id: String,
        method_id: String,
    },
    Verifying {
        operation_id: String,
    },
    /// 协议已结束、进程与管道仍在收束的非终态。
    ///
    /// 未完成的清理可以附带安全失败摘要；只有资源确认停止后才发布终态。
    Closing {
        operation_id: String,
        failure: Option<AcpAuthFailure>,
    },
    /// 认证可用；`checked_at` 只是当时观察，不是永久在线。
    Verified {
        checked_at: i64,
        server: Option<AcpServerInfo>,
    },
    Cancelling {
        operation_id: String,
    },
    Cancelled,
    Failed {
        failure: AcpAuthFailure,
    },
}

impl AcpAuthState {
    /// 该状态是否持有一个进行中的操作身份。
    pub fn operation_id(&self) -> Option<&str> {
        match self {
            Self::Checking { operation_id }
            | Self::Authenticating { operation_id, .. }
            | Self::Verifying { operation_id }
            | Self::Closing { operation_id, .. }
            | Self::Cancelling { operation_id } => Some(operation_id),
            Self::Unchecked
            | Self::Required { .. }
            | Self::Verified { .. }
            | Self::Cancelled
            | Self::Failed { .. } => None,
        }
    }
}

/// 一个接入的认证观察条目。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthAccount {
    pub account_id: String,
    /// 本次观察对应的连接身份；不等于 Settings revision。
    pub connection_revision: u64,
    pub state: AcpAuthState,
}

/// ACP 认证 topic 的 canonical 快照（独立 revision 与时间基线）。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub accounts: Vec<AcpAuthAccount>,
}

impl AcpAuthSnapshot {
    /// 尚未产生任何观察的空快照；不是“全部未检查”的伪造条目。
    pub fn empty(updated_at: i64) -> Self {
        Self {
            revision: 0,
            updated_at,
            accounts: Vec::new(),
        }
    }
}

/// 认证命令的受理回执与受理时的 canonical 快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthCommandReply {
    pub receipt: StudioCommandReceipt,
    pub snapshot: AcpAuthSnapshot,
}

/// 启动一次认证操作；命令快速返回受理身份，不等待人工登录。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartAcpAuthRequest {
    pub operation_id: String,
    pub account_id: String,
    pub expected_connection_revision: u64,
    pub action: AcpAuthAction,
}

/// 取消当前认证操作；`target_operation_id` 必须命中当前操作。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelAcpAuthRequest {
    pub operation_id: String,
    pub account_id: String,
    pub target_operation_id: String,
}
