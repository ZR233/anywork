use pl_model_openai_wire::{
    adapter::Adapter, discovery::DiscoveryPolicy, model::ModelModality,
    protocol::InstructionWireRole,
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy {
    responses_effort: true,
    unknown_input: &[ModelModality::Text, ModelModality::Image],
    ..DiscoveryPolicy::COMPATIBLE
};

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    responses_instruction_role: InstructionWireRole::Developer,
    discovery: CATALOG,
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: None,
    parse_catalog: pl_model_openai_wire::generic_catalog::openai_records,
};

pub static COMPATIBLE_ADAPTER: Adapter = Adapter {
    id: crate::endpoint::COMPATIBLE_ID,
    responses_instruction_role: InstructionWireRole::Developer,
    discovery: DiscoveryPolicy::COMPATIBLE,
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: None,
    parse_catalog: pl_model_openai_wire::generic_catalog::records,
};
