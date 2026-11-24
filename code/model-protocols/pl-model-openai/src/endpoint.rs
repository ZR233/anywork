use pl_model_wire::protocol::*;

pub const ID: ProtocolId = ProtocolId::from_static("open_ai");

pub fn endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    let custom_endpoint = base_url.is_some();
    let mut service_capabilities = ProtocolServiceCapabilities::openai_web_search();
    service_capabilities.web_search.standalone = Some(SEARCH_DIALECT);
    // 覆盖 base_url 保留图像生成能力：Images 路径追加在该前缀之后，与
    // standalone Web Search 的继承语义一致。
    service_capabilities.image_generation = Some(ImageGenerationCapabilities::openai_images());
    if custom_endpoint {
        service_capabilities.remote_compaction = false;
        service_capabilities.responses_tools = ResponsesHostedToolCapabilities::default();
    }
    ProtocolEndpoint {
        protocol: ID,
        responses_instruction_role: crate::adapter::ADAPTER.responses_instruction_role,
        authorization: None,
        name: "OpenAI".into(),
        base_url: base_url.unwrap_or_else(|| "https://api.openai.com/v1".into()),
        bearer_token: None,
        api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
        http_headers: None,
        tool_wire_policy: ToolWirePolicy::NativeCustomTools,
        apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
        service_capabilities,
    }
}

pub const COMPATIBLE_ID: ProtocolId = ProtocolId::from_static("open_ai_compatible");
pub fn compatible_endpoint(
    name: impl Into<String>,
    base_url: impl Into<String>,
) -> ProtocolEndpoint {
    ProtocolEndpoint::new(COMPATIBLE_ID, name, base_url)
}

pub const SEARCH_DIALECT: StandaloneWebSearchDialect =
    StandaloneWebSearchDialect::from_static("open_ai_search_api");
