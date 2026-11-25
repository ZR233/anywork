use pl_model_wire::{
    adapter::Adapter,
    discovery::DiscoveryPolicy,
    model::ModelModality,
    protocol::{ApiKeyHeaderScheme, InstructionWireRole},
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy {
    responses_effort: true,
    unknown_input: &[ModelModality::Text, ModelModality::Image],
    ..DiscoveryPolicy::COMPATIBLE
};

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    codec: &pl_model_openai_wire::OPENAI_WIRE_CODEC,
    error_policy: &crate::error::OpenAiErrorPolicy,
    api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
    responses_instruction_role: InstructionWireRole::Developer,
    discovery: CATALOG,
    discovery_query_params: &[],
    discovery_page_token_param: None,
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: None,
    parse_catalog_page: pl_model_wire::generic_catalog::openai_page,
};

pub static COMPATIBLE_ADAPTER: Adapter = Adapter {
    id: crate::endpoint::COMPATIBLE_ID,
    codec: &pl_model_openai_wire::OPENAI_WIRE_CODEC,
    error_policy: &crate::error::CompatibleErrorPolicy,
    api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
    responses_instruction_role: InstructionWireRole::Developer,
    discovery: DiscoveryPolicy::COMPATIBLE,
    discovery_query_params: &[],
    discovery_page_token_param: None,
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: None,
    parse_catalog_page: pl_model_wire::generic_catalog::page,
};
