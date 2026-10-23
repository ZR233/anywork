use crate::api::studio::observation::{BridgeReadText, BridgeTypedListRef};
use crate::api::studio::types::{BridgeModelCatalogStatusDto, BridgeModelContextResolution,
    BridgeModelInputSource, BridgeModelModality, BridgeModelOrigin, BridgeModelType, BridgeModelTypeExclusion};

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModelDescriptorRead {
    pub model_id: BridgeReadText,
    pub type_support: BridgeTypedListRef,
    pub origin: BridgeModelOrigin,
    pub display_name: BridgeReadText,
    pub description: Option<BridgeReadText>,
    pub context_window: Option<u64>,
    pub max_context_window: Option<u64>,
    pub context: BridgeModelContextResolution,
    pub max_output_tokens: Option<u64>,
    pub transport: BridgeModelTransportDescriptorRead,
    pub capabilities: BridgeModelCapabilitiesRead,
    pub reasoning: Option<BridgeModelReasoningDescriptorRead>,
    pub pricing: Option<BridgeModelPricingRead>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelTypeSupportRead { pub model_type: BridgeModelType, pub exclusions: BridgeTypedListRef }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelTypeExclusionReadItem { pub value: BridgeModelTypeExclusion }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelTransportDescriptorRead {
    pub protocol: BridgeReadText,
    pub connection_modes: BridgeTypedListRef,
    pub default_connection_mode: BridgeReadText,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConnectionModeRead { pub id: BridgeReadText, pub display_name: BridgeReadText }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCapabilitiesRead {
    pub input: BridgeTypedListRef,
    pub output: BridgeTypedListRef,
    pub streaming: bool,
    pub temperature: bool,
    pub reasoning: bool,
    pub web_search: bool,
    pub function_calling: bool,
    pub parallel_tool_calls: bool,
    pub custom_tools: bool,
    pub freeform_tools: bool,
    pub instruction_snapshot_overrides: bool,
    pub native_context_family: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelInputCapabilityRead {
    pub modality: BridgeModelModality,
    pub sources: BridgeTypedListRef,
    pub max_count: Option<u32>,
    pub max_bytes: Option<u64>,
    pub max_total_bytes: Option<u64>,
    pub max_width: Option<u32>,
    pub max_height: Option<u32>,
    pub media_types: BridgeTypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelInputSourceReadItem { pub value: BridgeModelInputSource }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelModalityReadItem { pub value: BridgeModelModality }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelReasoningDescriptorRead {
    pub parameter: BridgeReadText,
    pub label: BridgeReadText,
    /// The protocol field is `default`; the Dart adapter maps this to `defaultValue`.
    pub default: Option<BridgeReadText>,
    pub candidates: BridgeTypedListRef,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModelPricingRead {
    pub currency: BridgeReadText,
    pub tiers: BridgeTypedListRef,
    pub source: BridgeReadText,
    pub verified_at: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModelPriceTierRead {
    pub label: BridgeReadText,
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: Option<f64>,
    pub cache_write_per_mtok: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAccountCatalogEntryRead {
    pub account_id: BridgeReadText,
    pub credential_required: bool,
    pub capability_source: BridgeReadText,
    pub hosted_web_search: bool,
    pub hosted_web_search_dialect: BridgeReadText,
    pub standalone_web_search: Option<BridgeReadText>,
    pub prompt_cache_dialect: BridgeReadText,
    pub responses_programmatic_tool_calling: bool,
    pub default_model_id: BridgeReadText,
    pub effective_models: BridgeTypedListRef,
    pub model_catalog: BridgeModelCatalogStatusDto,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeEffectiveWebSearchRead {
    pub effective_mode: BridgeReadText,
    pub availability: BridgeReadText,
    pub account_id: Option<BridgeReadText>,
    pub model_id: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeEffectiveDeepSeekSearchRead {
    pub effective_enabled: bool,
    pub effective_fetch_enabled: bool,
    pub availability: BridgeReadText,
    pub account_id: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCatalogReadHeader {
    pub accounts: BridgeTypedListRef,
    pub web_search: BridgeEffectiveWebSearchRead,
    pub deepseek_web_search: BridgeEffectiveDeepSeekSearchRead,
}
