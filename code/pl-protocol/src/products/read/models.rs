use super::primitives::TypedListRef;
use crate::studio::{
    ReadText, StudioModelCatalogCacheWarning, StudioModelCatalogError, StudioModelCatalogSource,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelDescriptorRead {
    pub model_id: ReadText,
    pub type_support: TypedListRef,
    pub origin: crate::ModelOriginDto,
    pub enabled: bool,
    pub display_name: ReadText,
    pub description: Option<ReadText>,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub context: ModelContextResolutionRead,
    pub max_output_tokens: Option<u64>,
    pub transport: ModelTransportDescriptorRead,
    pub capabilities: ModelCapabilitiesRead,
    pub reasoning: Option<ModelReasoningDescriptorRead>,
    pub pricing: Option<ModelPricingRead>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelTypeSupportRead {
    pub model_type: crate::ModelType,
    pub exclusions: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelTypeExclusionReadItem {
    pub value: crate::ModelTypeExclusion,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelContextResolutionRead {
    pub unavailable: Option<crate::ModelContextUnavailable>,
    pub context_window: Option<u64>,
    pub input_token_limit: Option<u64>,
    pub auto_compact_limit: Option<u64>,
    pub adjustment: Option<crate::ModelContextAdjustment>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelTransportDescriptorRead {
    pub protocol: ReadText,
    pub connection_modes: TypedListRef,
    pub default_connection_mode: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ConnectionModeRead {
    pub id: ReadText,
    pub display_name: ReadText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelCapabilitiesRead {
    pub input: TypedListRef,
    pub output: TypedListRef,
    pub streaming: bool,
    pub temperature: bool,
    pub reasoning: bool,
    pub web_search: bool,
    pub function_calling: bool,
    pub parallel_tool_calls: bool,
    pub custom_tools: bool,
    pub freeform_tools: bool,
    pub instruction_snapshot_overrides: bool,
    pub native_context_family: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelInputCapabilityRead {
    pub modality: crate::ModelModalityDto,
    pub sources: TypedListRef,
    pub max_count: Option<u32>,
    pub max_bytes: Option<u64>,
    pub max_total_bytes: Option<u64>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub media_types: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelInputSourceReadItem {
    pub value: crate::ModelInputSourceDto,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelModalityReadItem {
    pub value: crate::ModelModalityDto,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelReasoningDescriptorRead {
    pub parameter: ReadText,
    pub label: ReadText,
    pub default: Option<ReadText>,
    pub candidates: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelPricingRead {
    pub currency: ReadText,
    pub tiers: TypedListRef,
    pub source: ReadText,
    pub verified_at: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelPriceTierRead {
    pub label: ReadText,
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: Option<f64>,
    pub cache_write_per_mtok: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelCatalogStatusRead {
    pub supported: bool,
    pub source: StudioModelCatalogSource,
    pub probing: bool,
    pub last_success_at: Option<i64>,
    pub checked_at: Option<i64>,
    pub error: Option<StudioModelCatalogError>,
    pub cache_warning: Option<StudioModelCatalogCacheWarning>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountCatalogEntryRead {
    pub account_id: ReadText,
    pub credential_required: bool,
    pub capability_source: ReadText,
    pub hosted_web_search: bool,
    pub hosted_web_search_dialect: ReadText,
    pub standalone_web_search: Option<ReadText>,
    pub prompt_cache_dialect: ReadText,
    pub responses_programmatic_tool_calling: bool,
    pub default_model_id: ReadText,
    pub effective_models: TypedListRef,
    pub model_catalog: ModelCatalogStatusRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct EffectiveWebSearchRead {
    pub effective_mode: ReadText,
    pub availability: ReadText,
    pub account_id: Option<ReadText>,
    pub model_id: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct EffectiveDeepSeekSearchRead {
    pub effective_enabled: bool,
    pub effective_fetch_enabled: bool,
    pub availability: ReadText,
    pub account_id: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ModelCatalogReadHeader {
    pub accounts: TypedListRef,
    pub web_search: EffectiveWebSearchRead,
    pub deepseek_web_search: EffectiveDeepSeekSearchRead,
}
