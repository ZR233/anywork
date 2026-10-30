//! Studio Settings 更新请求体。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::settings::SettingsStateResponse;

/// One independently mutable settings field/resource.
///
/// The unit of a mutation is intentionally smaller than the settings
/// snapshot.  A caller must describe the one value it intends to change; the
/// runtime reads every other value from its canonical state.  Route model and
/// reasoning effort are separate variants because a selector must not replay a
/// stale route snapshot when the other selector changes.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind", deny_unknown_fields)]
pub enum SettingsFieldUpdate {
    InstructionBaseOverride {
        value: String,
    },
    InstructionDeveloper {
        value: String,
    },
    InstructionUser {
        value: String,
    },
    ProjectDocMaxBytes {
        value: u64,
    },
    ProjectDocFallbackFilenames {
        value: Vec<String>,
    },
    SkillsEnabled {
        value: bool,
    },
    SkillsAutoLearn {
        value: bool,
    },
    SkillsSystemEnabled {
        value: bool,
    },
    SkillsProjectDir {
        value: String,
    },
    SkillsExternalDirs {
        value: Vec<String>,
    },
    SkillsDisabled {
        value: Vec<String>,
    },
    SkillsAutoLearnMinToolCalls {
        value: u32,
    },
    McpServerEnabled {
        id: String,
        value: bool,
    },
    McpServerTransport {
        id: String,
        transport: String,
    },
    McpServerEndpoint {
        id: String,
        endpoint: String,
    },
    GeneralFollowActiveTurn {
        value: bool,
    },
    GeneralCompactTimeline {
        value: bool,
    },
    GeneralLanguage {
        value: super::StudioUiLanguage,
    },
    GeneralSidebarWidth {
        value: Option<u16>,
    },
    GeneralPinnedThreadIds {
        value: Vec<String>,
    },
    GeneralPinnedProjectIds {
        value: Vec<String>,
    },
    WebSearchMode {
        value: String,
    },
    WebSearchContextSize {
        value: Option<String>,
    },
    WebSearchAllowedDomains {
        value: Vec<String>,
    },
    WebSearchCountry {
        value: Option<String>,
    },
    WebSearchRegion {
        value: Option<String>,
    },
    WebSearchCity {
        value: Option<String>,
    },
    WebSearchTimezone {
        value: Option<String>,
    },
    DeepSeekWebSearchEnabled {
        value: bool,
    },
    DeepSeekWebFetchEnabled {
        value: bool,
    },
    ModeModel {
        mode_id: String,
        account_id: String,
        model_id: String,
    },
    ModeReasoningEffort {
        mode_id: String,
        effort: Option<String>,
    },
    RoleModel {
        role: String,
        account_id: String,
        model_id: String,
    },
    RoleReasoningEffort {
        role: String,
        effort: Option<String>,
    },
    /// 新会话默认分发模式；只影响未来会话。
    DelegationMode {
        value: crate::DelegationMode,
    },
    /// 自动选模默认偏好；固定模式保存但不生效。
    DelegationPreference {
        value: crate::DelegationPreference,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateSettingsFieldRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub update: SettingsFieldUpdate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdatePermissionSettingsRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
/// Existing Thread 的模型路由是一个原子资源：模型、思考强度和其对应的
/// runtime route 必须在同一次 CAS 中通过联合校验。新会话/Mode 默认值和
/// Agent role 则使用上面的单字段更新，选择模型不会重放旧思考强度。
pub struct SetThreadModelRouteRequest {
    pub operation_id: String,
    pub expected_model_route_revision: u64,
    pub expected_settings_revision: u64,
    pub account_id: String,
    pub model_id: String,
    pub effort: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModelRouteCommandReply {
    #[schema(value_type = Object)]
    pub runtime: crate::ThreadRuntimeSnapshot,
    pub receipt: super::StudioCommandReceipt,
    pub settings: SettingsStateResponse,
    pub mode_default_saved: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub warning: Option<String>,
}

/// 创建一个 account 的完整初始配置；已有 ID 必须使用字段 patch，不能整卡覆盖。
///
/// Account、默认 account、模式路由和角色路由是四个独立的配置意图。
/// 这个请求只允许改变一个 account 资源；account 内部的 endpoint、凭据和
/// 模型声明需要一起校验并原子提交，避免保存半个不可用 account。它不会携带
/// 默认 account、模式路由或角色路由，设置页也不能把其它集合的旧快照一起写回。
/// 账号 ID 创建后稳定，不提供 `originalId` 重命名路径。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CreateAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account: AccountSettingsUpdate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoveAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    /// 删除仍被模式或角色路由引用的 account 时，必须显式指定替换 account。
    /// 未被引用时可以省略；删除逻辑不会因为界面旧快照而静默改写路由。
    #[serde(default)]
    pub replacement_account_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetDefaultAccountRequest {
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountSettingsUpdate {
    pub account_id: String,
    /// 可选的内置账号模板引用；完全自定义账号为 `None`。
    pub template_id: Option<String>,
    /// 明确的厂商协议适配选择；不从地址或名称推断。
    pub protocol: String,
    pub name: String,
    pub base_url: String,
    pub secret: AccountSecretUpdate,
    /// 仅创建时的初始计费覆盖；已有账号必须使用窄计费类别命令。
    #[serde(default)]
    pub initial_billing_kind: Option<crate::BillingKind>,
    // 账号不保存第二份默认模型：模型选择只由 Mode/角色/Thread route 决定。
    pub custom_models: Vec<AccountModelUpdate>,
    pub model_connection_modes: Vec<AccountModelConnectionUpdate>,
    pub model_auto_compact_limits: Vec<AccountModelAutoCompactUpdate>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountModelUpdate {
    pub model_id: String,
    pub display_name: String,
    pub wire_api: String,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountModelConnectionUpdate {
    pub model_id: String,
    pub connection_mode: String,
}

/// 某模型上下文压缩阈值用户覆盖的完整集合项；`limit` 必须为正整数 tokens。
///
/// 该列表是该 account 实例的完整覆盖集合；未列出的模型使用模型默认值。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountModelAutoCompactUpdate {
    pub model_id: String,
    pub limit: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "action", deny_unknown_fields)]
pub enum AccountSecretUpdate {
    Preserve,
    Replace { value: String },
    Clear,
}
