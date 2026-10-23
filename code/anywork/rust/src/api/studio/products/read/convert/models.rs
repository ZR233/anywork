use pl_protocol::products::read::models as protocol;
use crate::api::studio::types::{BridgeModelCatalogStatusDto, BridgeModelContextAdjustment,
    BridgeModelContextResolution, BridgeModelContextUnavailable, BridgeModelInputSource,
    BridgeModelModality, BridgeModelType, BridgeModelTypeExclusion};
use super::super::model_values::*;

impl From<protocol::ModelDescriptorRead> for BridgeModelDescriptorRead {
    fn from(value: protocol::ModelDescriptorRead) -> Self {
        Self { model_id: value.model_id.into(), type_support: value.type_support.into(), origin: value.origin.into(),
            display_name: value.display_name.into(), description: value.description.map(Into::into),
            context_window: value.context_window, max_context_window: value.max_context_window,
            context: value.context.into(), max_output_tokens: value.max_output_tokens, transport: value.transport.into(),
            capabilities: value.capabilities.into(), reasoning: value.reasoning.map(Into::into),
            pricing: value.pricing.map(Into::into) }
    }
}

impl From<protocol::ModelContextResolutionRead> for BridgeModelContextResolution {
    fn from(value: protocol::ModelContextResolutionRead) -> Self {
        Self { unavailable: value.unavailable.map(|reason| match reason {
            pl_protocol::ModelContextUnavailable::WindowUnknown => BridgeModelContextUnavailable::WindowUnknown,
            pl_protocol::ModelContextUnavailable::InvalidParameters => BridgeModelContextUnavailable::InvalidParameters,
            pl_protocol::ModelContextUnavailable::InputBudgetExhausted => BridgeModelContextUnavailable::InputBudgetExhausted,
        }), context_window: value.context_window, input_token_limit: value.input_token_limit,
            auto_compact_limit: value.auto_compact_limit, adjustment: value.adjustment.map(|reason| match reason {
                pl_protocol::ModelContextAdjustment::SafetyLimit => BridgeModelContextAdjustment::SafetyLimit,
            }) }
    }
}

impl From<protocol::ModelTypeSupportRead> for BridgeModelTypeSupportRead {
    fn from(value: protocol::ModelTypeSupportRead) -> Self {
        Self { model_type: match value.model_type { pl_protocol::ModelType::Text => BridgeModelType::Text },
            exclusions: value.exclusions.into() }
    }
}

impl From<protocol::ModelTypeExclusionReadItem> for BridgeModelTypeExclusionReadItem {
    fn from(value: protocol::ModelTypeExclusionReadItem) -> Self {
        Self { value: match value.value {
            pl_protocol::ModelTypeExclusion::TextInputUnsupported => BridgeModelTypeExclusion::TextInputUnsupported,
            pl_protocol::ModelTypeExclusion::TextOutputUnsupported => BridgeModelTypeExclusion::TextOutputUnsupported,
            pl_protocol::ModelTypeExclusion::ContextWindowUnknown => BridgeModelTypeExclusion::ContextWindowUnknown,
            pl_protocol::ModelTypeExclusion::ContextParametersInvalid => BridgeModelTypeExclusion::ContextParametersInvalid,
            pl_protocol::ModelTypeExclusion::InputBudgetExhausted => BridgeModelTypeExclusion::InputBudgetExhausted,
        } }
    }
}

impl From<protocol::ModelTransportDescriptorRead> for BridgeModelTransportDescriptorRead {
    fn from(value: protocol::ModelTransportDescriptorRead) -> Self {
        Self { protocol: value.protocol.into(), connection_modes: value.connection_modes.into(),
            default_connection_mode: value.default_connection_mode.into() }
    }
}

impl From<protocol::ConnectionModeRead> for BridgeConnectionModeRead {
    fn from(value: protocol::ConnectionModeRead) -> Self { Self { id: value.id.into(), display_name: value.display_name.into() } }
}

impl From<protocol::ModelCapabilitiesRead> for BridgeModelCapabilitiesRead {
    fn from(value: protocol::ModelCapabilitiesRead) -> Self {
        Self { input: value.input.into(), output: value.output.into(), streaming: value.streaming,
            temperature: value.temperature, reasoning: value.reasoning, web_search: value.web_search,
            function_calling: value.function_calling, parallel_tool_calls: value.parallel_tool_calls,
            custom_tools: value.custom_tools, freeform_tools: value.freeform_tools,
            instruction_snapshot_overrides: value.instruction_snapshot_overrides,
            native_context_family: value.native_context_family.map(Into::into) }
    }
}

fn modality(value: pl_protocol::ModelModalityDto) -> BridgeModelModality {
    match value {
        pl_protocol::ModelModalityDto::Text => BridgeModelModality::Text,
        pl_protocol::ModelModalityDto::Image => BridgeModelModality::Image,
        pl_protocol::ModelModalityDto::Audio => BridgeModelModality::Audio,
        pl_protocol::ModelModalityDto::Video => BridgeModelModality::Video,
        pl_protocol::ModelModalityDto::File => BridgeModelModality::File,
    }
}

impl From<protocol::ModelInputCapabilityRead> for BridgeModelInputCapabilityRead {
    fn from(value: protocol::ModelInputCapabilityRead) -> Self {
        Self { modality: modality(value.modality), sources: value.sources.into(), max_count: value.max_count,
            max_bytes: value.max_bytes, max_total_bytes: value.max_total_bytes, max_width: value.max_width,
            max_height: value.max_height, media_types: value.media_types.into() }
    }
}

impl From<protocol::ModelInputSourceReadItem> for BridgeModelInputSourceReadItem {
    fn from(value: protocol::ModelInputSourceReadItem) -> Self {
        Self { value: match value.value {
            pl_protocol::ModelInputSourceDto::Local => BridgeModelInputSource::Local,
            pl_protocol::ModelInputSourceDto::RemoteUrl => BridgeModelInputSource::RemoteUrl,
        } }
    }
}

impl From<protocol::ModelModalityReadItem> for BridgeModelModalityReadItem {
    fn from(value: protocol::ModelModalityReadItem) -> Self { Self { value: modality(value.value) } }
}

impl From<protocol::ModelReasoningDescriptorRead> for BridgeModelReasoningDescriptorRead {
    fn from(value: protocol::ModelReasoningDescriptorRead) -> Self {
        Self { parameter: value.parameter.into(), label: value.label.into(), default: value.default.map(Into::into),
            candidates: value.candidates.into() }
    }
}

impl From<protocol::ModelPricingRead> for BridgeModelPricingRead {
    fn from(value: protocol::ModelPricingRead) -> Self {
        Self { currency: value.currency.into(), tiers: value.tiers.into(), source: value.source.into(), verified_at: value.verified_at }
    }
}

impl From<protocol::ModelPriceTierRead> for BridgeModelPriceTierRead {
    fn from(value: protocol::ModelPriceTierRead) -> Self {
        Self { label: value.label.into(), input_per_mtok: value.input_per_mtok, output_per_mtok: value.output_per_mtok,
            cache_read_per_mtok: value.cache_read_per_mtok, cache_write_per_mtok: value.cache_write_per_mtok }
    }
}

impl From<protocol::ModelCatalogStatusRead> for BridgeModelCatalogStatusDto {
    fn from(value: protocol::ModelCatalogStatusRead) -> Self {
        // This is the same original account-level status, not the resource's Observed metadata.
        pl_protocol::studio::StudioModelCatalogStatus { supported: value.supported, source: value.source,
            probing: value.probing, last_success_at: value.last_success_at, checked_at: value.checked_at,
            error: value.error, cache_warning: value.cache_warning }.into()
    }
}

impl From<protocol::AccountCatalogEntryRead> for BridgeAccountCatalogEntryRead {
    fn from(value: protocol::AccountCatalogEntryRead) -> Self {
        Self { account_id: value.account_id.into(), credential_required: value.credential_required,
            capability_source: value.capability_source.into(), hosted_web_search: value.hosted_web_search,
            hosted_web_search_dialect: value.hosted_web_search_dialect.into(),
            standalone_web_search: value.standalone_web_search.map(Into::into),
            prompt_cache_dialect: value.prompt_cache_dialect.into(),
            responses_programmatic_tool_calling: value.responses_programmatic_tool_calling,
            default_model_id: value.default_model_id.into(), effective_models: value.effective_models.into(),
            model_catalog: value.model_catalog.into() }
    }
}

impl From<protocol::EffectiveWebSearchRead> for BridgeEffectiveWebSearchRead {
    fn from(value: protocol::EffectiveWebSearchRead) -> Self {
        Self { effective_mode: value.effective_mode.into(), availability: value.availability.into(),
            account_id: value.account_id.map(Into::into), model_id: value.model_id.map(Into::into) }
    }
}

impl From<protocol::EffectiveDeepSeekSearchRead> for BridgeEffectiveDeepSeekSearchRead {
    fn from(value: protocol::EffectiveDeepSeekSearchRead) -> Self {
        Self { effective_enabled: value.effective_enabled, effective_fetch_enabled: value.effective_fetch_enabled,
            availability: value.availability.into(), account_id: value.account_id.map(Into::into) }
    }
}

impl From<protocol::ModelCatalogReadHeader> for BridgeModelCatalogReadHeader {
    fn from(value: protocol::ModelCatalogReadHeader) -> Self {
        Self { accounts: value.accounts.into(), web_search: value.web_search.into(), deepseek_web_search: value.deepseek_web_search.into() }
    }
}
