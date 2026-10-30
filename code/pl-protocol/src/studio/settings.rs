//! Studio 无密钥 canonical Settings 快照。

use super::AcpAccountSettings;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::BillingKind;

/// Secret-free canonical configuration snapshot.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsConfigSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub settings: StudioSettings,
}

/// One account's model directory observation. It is owned by the catalog clock and
/// is deliberately absent from [`StudioAccountSettings`].
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioAccountModelCatalog {
    pub account_id: String,
    pub effective_models: Vec<crate::ModelDescriptor>,
    pub model_catalog: StudioModelCatalogStatus,
}

/// Canonical model directory snapshot. Catalog refreshes never rewrite the
/// configuration snapshot or its revision.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelCatalogSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub accounts: Vec<StudioAccountModelCatalog>,
}

/// Direct response for a configuration command. The two resources are
/// returned together for convenience, while each retains its own clock.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SettingsStateResponse {
    pub config: SettingsConfigSnapshot,
    pub catalog: ModelCatalogSnapshot,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioSettings {
    pub default_account_id: Option<String>,
    pub accounts: Vec<StudioAccountSettings>,
    /// ACP 接入的 desired 配置；与 Native `accounts` 是两套语义，不进入默认账号或模型路由。
    pub acp_accounts: Vec<AcpAccountSettings>,
    pub mode_model_routes: Vec<StudioModeModelSettings>,
    pub roles: Vec<StudioRoleSettings>,
    /// 新会话默认分发模式与偏好；已有会话保留自己的 canonical 选择。
    #[serde(default)]
    pub delegation: crate::DelegationSettings,
    pub permission_mode: String,
    pub instructions: StudioInstructionsSettings,
    pub skills: StudioSkillsSettings,
    pub mcp_servers: Vec<StudioMcpServerSettings>,
    pub general: StudioGeneralSettings,
    pub web_search: StudioWebSearchSettings,
    pub deepseek_web_search: StudioDeepSeekWebSearchSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioAccountSettings {
    /// 生效计费类别；订阅不证明订阅有效或额度充足。
    #[serde(default)]
    pub billing_kind: crate::BillingKind,
    /// 计费类别的显式覆盖原意图；`None` 表示未显式配置、由模板与 canonical endpoint 推导。
    ///
    /// `Some(BillingKind::Unknown)` 与 `None` 语义不同：前者是用户显式选择「未知」，后者是
    /// 跟随推导。完整账号编辑必须原样保留该覆盖，不把生效值写回。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub billing_kind_override: Option<crate::BillingKind>,
    pub account_id: String,
    /// 可选的内置账号模板引用；完全自定义账号为 `None`。
    pub template_id: Option<String>,
    /// 明确的厂商协议适配选择。
    pub protocol: String,
    pub name: String,
    pub base_url: String,
    pub has_bearer_token: bool,
    /// Owner-local, non-secret identity of this instance's usage query inputs.
    pub usage_query_revision: u64,
    pub credential_required: bool,
    pub capability_source: String,
    pub hosted_web_search: bool,
    pub hosted_web_search_dialect: String,
    pub standalone_web_search: Option<String>,
    pub prompt_cache_dialect: String,
    pub responses_programmatic_tool_calling: bool,
    /// 目录或创建路由的默认模型投影；不是账号 runtime 的第二份模型选择。
    pub default_model_id: String,
    pub custom_models: Vec<StudioCustomModelSettings>,
    pub model_connection_modes: Vec<StudioModelConnectionSettings>,
    pub model_auto_compact_limits: Vec<StudioModelAutoCompactSettings>,
    /// 精确 model_id 的显式启用覆盖；缺项表示自动，撤下的成员仍保留覆盖。
    #[serde(default)]
    pub model_enabled_overrides: std::collections::BTreeMap<String, bool>,
    pub catalog_id: Option<String>,
}

/// One account instance's derived directory observation, never desired configuration.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModelCatalogStatus {
    pub query_generation: u64,
    pub operation_id: Option<String>,
    pub supported: bool,
    pub source: StudioModelCatalogSource,
    pub probing: bool,
    pub last_success_at: Option<i64>,
    pub checked_at: Option<i64>,
    pub error: Option<StudioModelCatalogError>,
    pub cache_warning: Option<StudioModelCatalogCacheWarning>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioModelCatalogSource {
    Default,
    Cached,
    Online,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum StudioModelCatalogError {
    Unsupported,
    Configuration,
    Timeout,
    Transport {
        #[serde(rename = "httpStatus")]
        http_status: Option<u16>,
    },
    Http {
        status: u16,
    },
    TooLarge,
    Protocol,
    CacheIdentity,
    UnexpectedNotModified,
    CacheWrite,
    TaskFailed,
    Closing,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioModelCatalogCacheWarning {
    Read,
    Schema,
    Identity,
    Declaration,
}

/// 删除手动模型的配置命令。只接受 `additional_models` 或 Explicit 目录中的 model_id。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RemoveAccountModelRequest {
    /// 调用方操作身份；回执原样携带同一个 ID，不能由服务端生成或替换。
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    pub model_id: String,
}

/// 账号模型启用状态命令。
///
/// 它是独立字段意图：只改变该 `(accountId, modelId)` 的启用状态，保留凭据、其他模型、
/// 连接与压缩覆盖，也不把在线成员转成手工成员。切换即保存，不进入账号编辑页草稿。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetAccountModelEnabledRequest {
    /// 调用方操作身份；回执原样携带同一个 ID，不能由服务端生成或替换。
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    pub model_id: String,
    pub enabled: bool,
}

/// 账号计费类别的显式写入意图。
///
/// wire 上就是 `billingKind` 字段：`null` 明确清除显式覆盖并恢复模板/canonical endpoint
/// 推导，具体类别（含 `unknown`）表示显式覆盖。字段缺失是非法请求，不会因为 serde 的
/// 缺省行为被悄悄当成「清除」，因此这里不使用裸 `Option`。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(transparent)]
pub struct BillingKindIntent(Option<BillingKind>);

impl BillingKindIntent {
    /// 显式覆盖为具体类别；`unknown` 也是显式选择。
    pub fn set(kind: BillingKind) -> Self {
        Self(Some(kind))
    }

    /// 清除显式覆盖，恢复推导。
    pub fn clear() -> Self {
        Self(None)
    }

    /// 返回原意图；`None` 表示恢复推导。
    pub fn value(self) -> Option<BillingKind> {
        self.0
    }
}

impl<'de> Deserialize<'de> for BillingKindIntent {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct IntentVisitor;

        impl serde::de::Visitor<'_> for IntentVisitor {
            type Value = BillingKindIntent;

            fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
                formatter.write_str("an explicit billing kind or null to clear the override")
            }

            /// `null` 是明确的清除意图。
            fn visit_unit<E>(self) -> Result<Self::Value, E> {
                Ok(BillingKindIntent(None))
            }

            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                use crate::labeled::LabeledEnum;
                BillingKind::from_label(value)
                    .map(BillingKindIntent::set)
                    .map_err(|error| E::custom(error.to_string()))
            }
        }

        // 用 `deserialize_any`：serde 的 missing-field 路径会直接报错，而
        // `deserialize_option` 会把缺失字段当成 `None`，从而把「缺失」误判成「清除」。
        deserializer.deserialize_any(IntentVisitor)
    }
}

/// 独立账号级计费类别命令。
///
/// 只改该 account 的显式覆盖：`billingKind: null` 清除并恢复推导，具体类别写入覆盖。
/// 它不携带价格统计开关、模型、凭据或连接，普通账号编辑也不复用同一个写入口。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SetAccountBillingKindRequest {
    /// 调用方操作身份；回执原样携带同一个 ID，不能由服务端生成或替换。
    pub operation_id: String,
    pub expected_revision: u64,
    pub account_id: String,
    /// 字段必须出现：`null` 表示清除覆盖并恢复推导，具体类别表示显式覆盖；缺失字段是
    /// 非法请求。schema 因此把它列为 `required` 并允许 `null` 值。
    #[schema(value_type = BillingKind, nullable = true)]
    pub billing_kind: BillingKindIntent,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioCustomModelSettings {
    pub input_capabilities: Vec<crate::ModelInputCapabilityDto>,
    pub context_window: Option<u64>,
    pub max_output_tokens: Option<u64>,
    pub model_id: String,
    pub display_name: String,
    pub reasoning_efforts: Vec<String>,
    pub base_instructions: String,
    pub wire_api: String,
    pub supported_connection_modes: Vec<String>,
    pub default_connection_mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModelConnectionSettings {
    pub model_id: String,
    pub connection_mode: String,
}

/// Persisted account override intent; resolved policy belongs to the effective catalog.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModelAutoCompactSettings {
    pub model_id: String,
    pub override_limit: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioRoleSettings {
    pub key: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioModeModelSettings {
    pub mode_id: String,
    pub account_id: String,
    pub model_id: String,
    pub effort: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioInstructionsSettings {
    pub base_override: String,
    pub developer: String,
    pub user: String,
    pub project_doc_max_bytes: u64,
    pub project_doc_fallback_filenames: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioSkillsSettings {
    pub enabled: bool,
    pub auto_learn: bool,
    pub system_enabled: bool,
    pub project_dir: String,
    pub user_dir: String,
    pub external_dirs: Vec<String>,
    pub disabled: Vec<String>,
    pub auto_learn_min_tool_calls: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioMcpServerSettings {
    pub id: String,
    pub transport: String,
    pub endpoint: String,
    pub configuration: StudioMcpServerConfiguration,
    pub source_kind: String,
    pub mutation_policy: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioMcpServerConfiguration {
    Enabled,
    Disabled,
    MissingCredential,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioGeneralSettings {
    pub follow_active_turn: bool,
    pub compact_timeline: bool,
    #[serde(default)]
    pub sidebar_width: Option<u16>,
    #[serde(default)]
    pub pinned_thread_ids: Vec<String>,
    #[serde(default)]
    pub pinned_workspace_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioWebSearchSettings {
    pub configured_mode: String,
    pub effective_mode: String,
    pub availability: String,
    pub context_size: Option<String>,
    pub allowed_domains: Vec<String>,
    pub country: Option<String>,
    pub region: Option<String>,
    pub city: Option<String>,
    pub timezone: Option<String>,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioDeepSeekWebSearchSettings {
    pub configured_enabled: bool,
    pub effective_enabled: bool,
    pub configured_fetch_enabled: bool,
    pub effective_fetch_enabled: bool,
    pub availability: String,
    pub account_id: Option<String>,
}
