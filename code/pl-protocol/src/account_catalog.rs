//! 账号模板与模型目录的产品 wire。
//!
//! 这些类型只用于 HTTP/FRB 投影，全部使用 camelCase；配置 TOML 与厂商原始 JSON 不在
//! 这里定义，也不与本模块共享字段拼写。

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

/// Account/模型目录跨产品传输协议版本。
pub const ACCOUNT_CATALOG_SCHEMA_VERSION: u32 = 19;

/// 账号计费意图的唯一事实源；请求由此冻结 [`crate::PricingMode`]。
///
/// `subscription` 只表示账号走订阅计量，不证明订阅有效、额度充足或实际零费用；
/// 未知价格也不能被解释为免费。
#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    schemars::JsonSchema,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum BillingKind {
    Metered,
    Subscription,
    /// 用户声明后续调用不计费；不抹去模型目录参考价格。
    NoCharge,
    #[default]
    Unknown,
}

crate::impl_labeled_enum!(
    BillingKind,
    "BillingKind",
    [
        BillingKind::Metered => "metered",
        BillingKind::Subscription => "subscription",
        BillingKind::NoCharge => "noCharge",
        BillingKind::Unknown => "unknown",
    ]
);

/// 无敏感信息、可供 Web 与桌面端直接渲染的账号模板目录快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AccountCatalogSnapshot {
    pub schema_version: u32,
    pub revision: String,
    pub templates: Vec<AccountTemplateDescriptor>,
    pub model_catalogs: BTreeMap<String, ModelCatalogDescriptor>,
}

/// 一个可创建账号实例的内置账号模板。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AccountTemplateDescriptor {
    pub id: String,
    pub display_name: String,
    pub description: Option<String>,
    pub base_url: String,
    pub credential: CredentialDescriptorDto,
    pub model_catalog_id: String,
    /// 模板默认的厂商协议选择；与 `ProtocolKind` 的 wire 值一致，不从模板 ID/URL 推断。
    pub protocol: String,
    pub default_billing_kind: BillingKind,
    pub supports_model_discovery: bool,
    /// None means this catalog publisher does not provide runtime usage-query capability.
    pub supports_usage_query: Option<bool>,
    /// 模板推荐的默认模型；不是账号 runtime 的第二份模型选择。
    pub suggested_model_id: String,
    pub icon_key: Option<String>,
    pub service_capabilities: AccountServiceCapabilitiesDescriptor,
}

/// 无敏感信息的 endpoint 外部服务能力。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct AccountServiceCapabilitiesDescriptor {
    pub web_search: WebSearchServiceCapabilitiesDescriptor,
    #[serde(default)]
    pub prompt_cache_dialect: String,
    #[serde(default)]
    pub responses_programmatic_tool_calling: bool,
}

/// UI 可直接渲染的 Web Search 服务能力。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct WebSearchServiceCapabilitiesDescriptor {
    pub hosted_responses: bool,
    pub hosted_dialect: String,
    pub standalone: Option<String>,
}

/// 当前 Web Search configured/effective 路径的无密钥投影。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct WebSearchResolutionDescriptor {
    pub configured_mode: String,
    pub effective_mode: String,
    pub availability: String,
    pub path: Option<String>,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
}

/// UI 可直接渲染的模型连接模式选项。
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionModeDescriptor {
    pub id: String,
    pub display_name: String,
}

/// 账号凭证输入提示；不包含真实 secret。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct CredentialDescriptorDto {
    pub label: String,
    pub env_var: Option<String>,
}

/// 一组共享同一模型语义的内置目录。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct ModelCatalogDescriptor {
    pub id: String,
    pub models: Vec<ModelDescriptor>,
}

/// 有效目录成员的来源，供 GUI 区分内置、在线与手动模型。
#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelOriginDto {
    Bundled,
    Online,
    Manual,
}

/// Optional classification for final catalog queries.
#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelType {
    Text,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelTypeExclusion {
    TextInputUnsupported,
    TextOutputUnsupported,
    ContextWindowUnknown,
    ContextParametersInvalid,
    InputBudgetExhausted,
}

/// Final model-owned context policy, frozen after catalog and account configuration merge.
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelContextResolution {
    pub unavailable: Option<ModelContextUnavailable>,
    pub context_window: Option<u64>,
    pub input_token_limit: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub adjustment: Option<ModelContextAdjustment>,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelContextUnavailable {
    WindowUnknown,
    InvalidParameters,
    InputBudgetExhausted,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelContextAdjustment {
    SafetyLimit,
}

#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelTypeSupport {
    pub model_type: ModelType,
    pub exclusions: Vec<ModelTypeExclusion>,
}

/// UI 和外部宿主需要的模型元数据投影。
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelDescriptor {
    pub model_id: String,
    #[serde(rename = "typeSupport")]
    pub type_support: Vec<ModelTypeSupport>,
    pub origin: ModelOriginDto,
    /// 用户启用意图；禁用成员仍保留在目录中，选择入口必须排除它。
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    pub display_name: String,
    pub description: Option<String>,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub context: ModelContextResolution,
    pub max_output_tokens: Option<u64>,
    pub transport: ModelTransportDescriptor,
    pub capabilities: ModelCapabilitiesDto,
    pub reasoning: Option<ModelReasoningDescriptor>,
    pub pricing: Option<ModelPricingDto>,
}

const fn enabled_by_default() -> bool {
    true
}

/// 模型选模资料的只读投影：有界短简介、适配任务、局限与可追溯来源。
///
/// 它是参考元数据，不是能力声明、不是模型指令，也不在查询时联网或调用模型生成。
#[derive(
    Debug, Clone, Serialize, Deserialize, PartialEq, schemars::JsonSchema, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionGuideDto {
    /// 短简介，最多 240 个 Unicode 字符。
    pub summary: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub task_suitability: Vec<crate::AgentTaskCategory>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub limitations: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sources: Vec<ModelSelectionSourceDto>,
}

/// 一条可追溯来源；测量条件不完整时必须如实标注，不能合成网络总分。
#[derive(
    Debug, Clone, Serialize, Deserialize, PartialEq, schemars::JsonSchema, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionSourceDto {
    pub kind: ModelSelectionSourceKindDto,
    pub url: String,
    /// 核验日期（Unix 秒）。
    pub verified_at: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub measurement: Option<ModelSelectionMeasurementDto>,
}

/// 来源类型：官方说明、独立基准或社区反馈。
#[derive(
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    schemars::JsonSchema,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelSelectionSourceKindDto {
    Official,
    Benchmark,
    Community,
}

/// 基准测量条件：被测型号、effort、指标与分数必须成组出现。
#[derive(
    Debug, Clone, Serialize, Deserialize, PartialEq, schemars::JsonSchema, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelectionMeasurementDto {
    /// 被测量的精确型号或版本，不能用别名冒充。
    pub model: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effort: Option<String>,
    pub metric: String,
    /// 指标版本；给出分数时必须明确，否则分数不可比。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub metric_version: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub score: Option<f64>,
}

/// UI 可直接渲染的模型 API 协议与连接策略。
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelTransportDescriptor {
    pub protocol: String,
    pub connection_modes: Vec<ConnectionModeDescriptor>,
    pub default_connection_mode: String,
}

/// UI 可直接判断的模型能力摘要。
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelCapabilitiesDto {
    pub input: Vec<ModelInputCapabilityDto>,
    pub output: Vec<ModelModalityDto>,
    pub streaming: bool,
    pub temperature: bool,
    pub reasoning: bool,
    pub web_search: bool,
    pub function_calling: bool,
    pub parallel_tool_calls: bool,
    pub custom_tools: bool,
    pub freeform_tools: bool,
    #[serde(default, rename = "instructionSnapshotOverrides")]
    pub instruction_snapshot_overrides: bool,
    #[serde(default, rename = "nativeContextFamily")]
    pub native_context_family: Option<String>,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelModalityDto {
    Text,
    Image,
    Audio,
    Video,
    File,
}

#[derive(
    schemars::JsonSchema,
    Debug,
    Clone,
    Copy,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum ModelInputSourceDto {
    Local,
    RemoteUrl,
}

#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelInputCapabilityDto {
    pub modality: ModelModalityDto,
    pub sources: Vec<ModelInputSourceDto>,
    pub max_count: Option<u32>,
    pub max_bytes: Option<u64>,
    pub max_total_bytes: Option<u64>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub media_types: Vec<String>,
}

/// reasoning/effort 下拉的完整动态描述。
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelReasoningDescriptor {
    pub parameter: String,
    pub label: String,
    pub default: Option<String>,
    pub candidates: Vec<String>,
}

/// Display projection of all applicable catalog price bands, per million tokens.
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelPricingDto {
    pub currency: String,
    pub tiers: Vec<ModelPriceTierDto>,
    pub source: String,
    pub verified_at: i64,
}

/// A complete display row; clients format these rates without calculating multipliers.
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelPriceTierDto {
    pub label: String,
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: Option<f64>,
    pub cache_write_per_mtok: Option<f64>,
}
