use pl_model_openai_wire::{
    adapter::Adapter, discovery::DiscoveryPolicy, model::MediaSendOrder,
    protocol::InstructionWireRole,
};

pub const CATALOG: DiscoveryPolicy = DiscoveryPolicy {
    media_send_order: MediaSendOrder::ProviderFileFirst,
    ..DiscoveryPolicy::COMPATIBLE
};

pub static ADAPTER: Adapter = Adapter {
    id: crate::endpoint::ID,
    responses_instruction_role: InstructionWireRole::System,
    discovery: CATALOG,
    file_upload: Some(&crate::upload::FILE_UPLOAD),
    prepare_request: None,
    hosted_search_label: Some((crate::endpoint::HOSTED_SEARCH_DIALECT, "deepseek_responses")),
    on_base_url_override: Some(restrict_custom_base_url),
    parse_catalog: crate::deepseek_catalog::records,
};

fn restrict_custom_base_url(
    capabilities: &mut pl_model_openai_wire::protocol::ProtocolServiceCapabilities,
) {
    if capabilities.web_search.standalone == Some(crate::endpoint::SEARCH_DIALECT) {
        capabilities.web_search.standalone = None;
    }
}
