use pl_model_wire::{
    adapter::Adapter,
    discovery::DiscoveryPolicy,
    model::{MediaSendOrder, ModelModality},
    protocol::{
        ApiKeyHeaderScheme, InstructionWireRole, PromptCacheDialect, ProtocolServiceCapabilities,
    },
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy {
    responses_effort: false,
    media_send_order: MediaSendOrder::DataUrlOnly,
    unknown_input: &[
        ModelModality::Text,
        ModelModality::Image,
        ModelModality::File,
    ],
};

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    codec: &crate::codec::GEMINI_WIRE_CODEC,
    error_policy: &crate::error::GeminiErrorPolicy,
    api_key_header: ApiKeyHeaderScheme::XGoogApiKey,
    responses_instruction_role: InstructionWireRole::System,
    discovery: CATALOG,
    discovery_query_params: &[("pageSize", "1000")],
    discovery_page_token_param: Some("pageToken"),
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: Some(restrict_custom_base_url),
    parse_catalog_page: crate::catalog::parse_page,
};

fn restrict_custom_base_url(capabilities: &mut ProtocolServiceCapabilities) {
    capabilities.prompt_cache.dialect = PromptCacheDialect::None;
}
