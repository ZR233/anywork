use pl_model_openai_wire::{
    adapter::Adapter, discovery::DiscoveryPolicy, protocol::InstructionWireRole,
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy::COMPATIBLE;

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    responses_instruction_role: InstructionWireRole::Developer,
    discovery: CATALOG,
    file_upload: None,
    prepare_request: None,
    hosted_search_label: None,
    on_base_url_override: None,
    parse_catalog: pl_model_openai_wire::generic_catalog::records,
};
