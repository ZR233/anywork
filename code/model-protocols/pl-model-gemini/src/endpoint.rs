use pl_model_wire::ApiKeyHeaderScheme;
use pl_model_wire::protocol::*;

pub const ID: ProtocolId = ProtocolId::from_static("gemini");

pub const VERTEX_BASE_URL: &str = "https://aiplatform.googleapis.com/v1/publishers/google";
pub const GEMINI_API_BASE_URL: &str = "https://generativelanguage.googleapis.com/v1beta";

fn build_endpoint(name: &str, default_url: &str, base_url: Option<String>) -> ProtocolEndpoint {
    let resolved_url = base_url.unwrap_or_else(|| default_url.to_owned());
    let canonical = resolved_url.trim_end_matches('/') == default_url;
    ProtocolEndpoint {
        protocol: ID,
        responses_instruction_role: InstructionWireRole::System,
        api_key_header: ApiKeyHeaderScheme::XGoogApiKey,
        authorization: None,
        name: name.to_owned(),
        base_url: resolved_url,
        bearer_token: None,
        http_headers: None,
        tool_wire_policy: ToolWirePolicy::FunctionFallback,
        apply_patch_tool_type: None,
        service_capabilities: ProtocolServiceCapabilities {
            prompt_cache: PromptCacheServiceCapabilities {
                dialect: if canonical {
                    PromptCacheDialect::ImplicitPrefix
                } else {
                    PromptCacheDialect::None
                },
            },
            ..ProtocolServiceCapabilities::default()
        },
    }
}

pub fn vertex_endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    build_endpoint("Vertex AI", VERTEX_BASE_URL, base_url)
}

pub fn gemini_api_endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    build_endpoint("AI Studio", GEMINI_API_BASE_URL, base_url)
}
