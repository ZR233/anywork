use pl_model_wire::{
    adapter::Adapter,
    discovery::DiscoveryPolicy,
    protocol::{ApiKeyHeaderScheme, InstructionWireRole},
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy {
    responses_effort: true,
    ..DiscoveryPolicy::COMPATIBLE
};

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    codec: &pl_model_openai_wire::OPENAI_WIRE_CODEC,
    error_policy: &crate::error::XaiErrorPolicy,
    api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
    responses_instruction_role: InstructionWireRole::Developer,
    discovery: CATALOG,
    discovery_query_params: &[],
    discovery_page_token_param: None,
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: None,
    parse_catalog_page: crate::xai_catalog::page,
};
