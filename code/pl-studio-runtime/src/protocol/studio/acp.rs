//! ACP 接入配置与认证观察的 typed wire DTO。
//!
//! 这些类型是 Studio 与外围 adapter（FRB/HTTP）之间的唯一公共契约：接入 desired 配置出现在
//! Settings 快照，认证进展是独立版本域的资源快照。ACP 不是 HTTP 模型协议，因此这里既不复用
//! Native account 的 endpoint/secret 结构，也不携带原始进程输出或 SDK 内部类型；ACP 程序自行
//! 管理登录凭据。用户显式设置的 env 只作为配置编辑值传递，不得写入诊断或日志。
//!
//! command 与字面 argv 支持通用 ACP 程序；托管模板是可选启动来源，不是供应商准入枚举。
//! 设置消费同一用户级资源，文档修订用于单文件 CAS，连接修订仅用于运行期准入。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::StudioCommandReceipt;

/// 受管启动模板类别。通用 command 不需要、也不增加此枚举的分支。
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

/// canonical 设置中的一条 ACP 定义编辑投影。
///
/// `connection_revision` 是配置资源拥有的运行期连接身份；command/args/env/模板改变时推进，
/// 名称编辑不改变它。它不是文档修订、Settings 修订或认证 topic 修订，也不持久化到 Profile。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAccountSettings {
    pub account_id: String,
    pub name: String,
    pub template: Option<AcpProvider>,
    pub enabled: bool,
    pub command: Option<String>,
    pub args: Vec<String>,
    pub env: std::collections::BTreeMap<String, String>,
    pub document_revision: u64,
    pub connection_revision: u64,
}

/// 一种接入类型的模板：固定的官方发行版本、图标与官方安装说明。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAccountTemplate {
    pub provider: AcpProvider,
    pub display_name: String,
    pub description: String,
    pub icon_key: String,
    /// 产品固定支持的官方 server 版本；与内部启动资格消费同一清单，客户端不持有第二份选择表。
    pub supported_version: String,
    /// 官方安装/下载说明；空字符串表示本平台没有可确认的官方说明，UI 不展示链接。
    pub install_url: String,
    /// 官方条款/隐私说明；空字符串表示不展示。客户端不硬编码品牌链接。
    pub terms_url: String,
    /// 当前宿主平台能否由产品自动准备官方 server；读取模板本身不联网。
    pub automatic_install: super::AcpInstallAvailability,
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
    #[serde(default)]
    pub template: Option<AcpProvider>,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub args: Option<Vec<String>>,
    #[serde(default)]
    pub env: std::collections::BTreeMap<String, String>,
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
}

fn enabled_by_default() -> bool {
    true
}

/// 保存/新增一条 ACP 接入。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateAcpAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    /// Absent for creation; exact document revision for an update.
    pub expected_document_revision: Option<u64>,
    pub account: AcpAccountUpdate,
}

/// 删除一条 ACP 接入；只移除本地接入，不注销官方账号或删除其凭据。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoveAcpAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    pub expected_document_revision: u64,
}

/// 一个显式认证动作。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "action", deny_unknown_fields)]
pub enum AcpAuthAction {
    /// 只检查连接与当前凭据状态。
    Check,
    /// 在受控探测会话中执行固定 `/usage`，不调用语言模型。
    QueryUsage,
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
    /// 固定发行的受管安装尚未准备：必须显式准备，命令不会隐式下载或修复。
    PreparationRequired,
    /// 受管安装存在但回执、完整成员或权限与冻结描述符不一致。
    InstallationInvalid,
    /// 当前宿主平台没有产品支持的官方发行。
    UnsupportedPlatform,
    /// 协商出的 server 版本缺失或不是产品固定支持的版本。
    ServerVersionMismatch,
    /// 无法启动官方程序或所需监督资源。
    Startup,
    /// 已验证安装的入口程序缺失或不可执行。
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
    /// 启动前验证受管安装（只读，不下载、不修复）。
    Prepare,
    /// 官方程序启动。
    Process,
    /// 准备接入专属探测目录。
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
        operation_id: String,
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
            | Self::Required { operation_id, .. }
            | Self::Authenticating { operation_id, .. }
            | Self::Verifying { operation_id }
            | Self::Closing { operation_id, .. }
            | Self::Cancelling { operation_id } => Some(operation_id),
            Self::Unchecked | Self::Verified { .. } | Self::Cancelled | Self::Failed { .. } => None,
        }
    }
}

/// 当前操作槽位上的进行中认证操作；由认证所有者与 state 在同一提交边界投影。
///
/// 连接已替换而旧进程仍在收束时，这里的连接修订可以小于账号当前修订，动作也仍是旧操作
/// 启动时冻结的真实意图；不能按账号当前 state、时间或已有额度推导（design/28 §28.9）。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthActiveOperation {
    pub operation_id: String,
    /// 该操作启动时冻结的连接修订；与账号当前修订不同表示旧连接仍在收束。
    pub connection_revision: u64,
    /// 该操作真实的启动动作；来自准入意图，不从忙碌阶段猜测。
    pub action: AcpAuthAction,
}

/// 一个接入的认证观察条目。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    rename_all = "camelCase",
    deny_unknown_fields,
    from = "AcpAuthAccountWire"
)]
pub struct AcpAuthAccount {
    pub account_id: String,
    /// 本次观察对应的连接身份；不等于 Settings revision。
    pub connection_revision: u64,
    pub state: AcpAuthState,
    /// 本连接代次最近一次显式额度查询；未查询时为空。
    #[serde(default)]
    pub usage: Option<AcpUsageObservation>,
    /// 当前操作槽位上的进行中操作；无在途操作时为空。
    ///
    /// 序列化总是显式出现（无操作为 `null`）；解码要求字段必须出现，缺失即是错误——
    /// 不能把缺失伪装成"没有在途操作"，也不吞掉未知动作类型。
    pub active_operation: Option<AcpAuthActiveOperation>,
}

/// [`AcpAuthAccount`] 的严格解码中间层：`activeOperation` 由非 `Option` 包装承接，
/// 字段缺失时 serde 直接报 `missing field`，绕开 `Option` 字段隐式取 `None` 的行为。
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AcpAuthAccountWire {
    account_id: String,
    connection_revision: u64,
    state: AcpAuthState,
    #[serde(default)]
    usage: Option<AcpUsageObservation>,
    active_operation: ExplicitNull<AcpAuthActiveOperation>,
}

impl From<AcpAuthAccountWire> for AcpAuthAccount {
    fn from(wire: AcpAuthAccountWire) -> Self {
        Self {
            account_id: wire.account_id,
            connection_revision: wire.connection_revision,
            state: wire.state,
            usage: wire.usage,
            active_operation: wire.active_operation.0,
        }
    }
}

/// 显式可空的 JSON 字段：`null` → `None`，值 → `Some`。
///
/// serde 对缺失字段会走 `missing_field` 后门：用一个只支持 `deserialize_option` 的
/// 反序列化器调用字段自身的 `Deserialize`（即使配 `deserialize_with` 也拦不住，缺失
/// 字段不会调用它）。因此这里**不能**走 option 协议（含委托 `Option::deserialize`），
/// 而是用 `deserialize_any`：null → `visit_unit`，对象 → `visit_map`；缺失字段在该
/// 后门上没有 option 出口，直接成为 `missing field` 错误。
#[derive(Debug, Clone, PartialEq, Eq)]
struct ExplicitNull<T>(Option<T>);

impl<'de, T> Deserialize<'de> for ExplicitNull<T>
where
    T: Deserialize<'de>,
{
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct ExplicitNullVisitor<T>(std::marker::PhantomData<T>);

        impl<'de, T> serde::de::Visitor<'de> for ExplicitNullVisitor<T>
        where
            T: Deserialize<'de>,
        {
            type Value = ExplicitNull<T>;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("an explicit value or null")
            }

            fn visit_unit<E>(self) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(ExplicitNull(None))
            }

            fn visit_none<E>(self) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(ExplicitNull(None))
            }

            fn visit_map<A>(self, map: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::MapAccess<'de>,
            {
                T::deserialize(serde::de::value::MapAccessDeserializer::new(map))
                    .map(|value| ExplicitNull(Some(value)))
            }
        }

        deserializer.deserialize_any(ExplicitNullVisitor(std::marker::PhantomData))
    }
}

/// `Busy` 拒绝（同账号操作槽位已占用）的结构化详情信封；wire 形状固定为单个 `acpAuthBusy` 键。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthBusyRejection {
    pub acp_auth_busy: AcpAuthBusyDetails,
}

/// 拒绝准入那一刻的权威忙碌切面；由认证所有者在拒绝的同一准入锁内捕获。
///
/// 它只描述拒绝时刻的占用事实，不代表本次请求已受理；占用操作可能在错误送达前已经
/// 终态，调用方不能把稍后其他来源的版本附在该切面上（design/28 §28.9）。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpAuthBusyDetails {
    pub account_id: String,
    /// 拒绝时的当前账号连接修订。
    pub connection_revision: u64,
    /// 拒绝时的 `acpAuth` 快照修订；与忙碌槽位在同一锁内原子一致。
    pub snapshot_revision: u64,
    /// 拒绝时占用槽位的真实操作身份；可能属于仍在收束的旧连接。
    pub active_operation: AcpAuthActiveOperation,
}

/// 与认证结论独立的账户额度观察。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpUsageObservation {
    pub checked_at: i64,
    pub state: AcpUsageState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum AcpUsageState {
    Ready { groups: Vec<AcpQuotaGroup> },
    NotApplicable,
    Unavailable,
    Failed { code: AcpUsageFailureCode },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AcpUsageFailureCode {
    Query,
    Timeout,
    Transport,
    ResourceLimit,
    InvalidResponse,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpQuotaGroup {
    pub name: String,
    pub limits: Vec<AcpQuotaLimit>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpQuotaLimit {
    pub label: String,
    pub remaining: AcpQuotaRemaining,
    pub next_reset_at: Option<i64>,
}

/// 未提供比例或总量时不推导进度，停用也不等同于剩余零。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum AcpQuotaRemaining {
    Percentage { value: u8 },
    Units { value: u64 },
    Unknown,
    Disabled,
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

/// 在仍然存活的原连接上继续登录；命令身份与目标流程身份分别校验。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinueAcpAuthRequest {
    pub operation_id: String,
    pub account_id: String,
    pub expected_connection_revision: u64,
    pub target_operation_id: String,
    pub method_id: String,
}

/// 取消当前认证操作；`target_operation_id` 必须命中当前操作。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CancelAcpAuthRequest {
    pub operation_id: String,
    pub account_id: String,
    pub target_operation_id: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_active_operation_field_is_a_decode_error() {
        let busy = AcpAuthAccount {
            account_id: "account".to_string(),
            connection_revision: 7,
            state: AcpAuthState::Checking {
                operation_id: "op-1".to_string(),
            },
            usage: None,
            active_operation: Some(AcpAuthActiveOperation {
                operation_id: "op-1".to_string(),
                connection_revision: 7,
                action: AcpAuthAction::Check,
            }),
        };
        // serde 对 Option 字段缺失会隐式取 None；严格解码必须让缺失直接失败，
        // 否则忙碌切面被伪装成"没有在途操作"。
        let mut missing = serde_json::to_value(&busy).expect("serialize busy account");
        missing
            .as_object_mut()
            .expect("json object")
            .remove("activeOperation");
        assert!(serde_json::from_value::<AcpAuthAccount>(missing).is_err());

        // 同样拒绝信封内的未知字段：wire 形状不能被静默扩写。
        let mut unknown_field = serde_json::to_value(&busy).expect("serialize busy account");
        unknown_field["activeOperation"]["unexpected"] = serde_json::json!(1);
        assert!(serde_json::from_value::<AcpAuthAccount>(unknown_field).is_err());
    }
}
