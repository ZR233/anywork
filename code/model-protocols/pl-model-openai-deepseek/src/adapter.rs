use pl_model_wire::{
    adapter::Adapter,
    discovery::DiscoveryPolicy,
    model::MediaSendOrder,
    protocol::{ApiKeyHeaderScheme, InstructionWireRole},
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy {
    media_send_order: MediaSendOrder::ProviderFileFirst,
    ..DiscoveryPolicy::COMPATIBLE
};

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    codec: &pl_model_openai_wire::OPENAI_WIRE_CODEC,
    error_policy: &crate::error::DeepSeekErrorPolicy,
    api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
    responses_instruction_role: InstructionWireRole::System,
    discovery: CATALOG,
    discovery_query_params: &[],
    discovery_page_token_param: None,
    file_upload: Some(&crate::upload::FILE_UPLOAD),
    prepare_request: None,
    hosted_search_label: Some((crate::endpoint::HOSTED_SEARCH_DIALECT, "deepseek_responses")),
    on_base_url_override: Some(restrict_custom_base_url),
    parse_catalog_page: crate::deepseek_catalog::page,
};

fn restrict_custom_base_url(
    capabilities: &mut pl_model_wire::protocol::ProtocolServiceCapabilities,
) {
    if capabilities.web_search.standalone == Some(crate::endpoint::SEARCH_DIALECT) {
        capabilities.web_search.standalone = None;
    }
}
