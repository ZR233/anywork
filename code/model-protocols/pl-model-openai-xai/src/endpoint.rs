use pl_model_wire::protocol::*;

pub const ID: ProtocolId = ProtocolId::from_static("xai");

pub fn endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    let canonical = base_url
        .as_deref()
        .is_none_or(|url| url.trim_end_matches('/') == "https://api.x.ai/v1");
    ProtocolEndpoint {
        protocol: ID,
        responses_instruction_role: crate::adapter::ADAPTER.responses_instruction_role,
        authorization: None,
        name: "xAI".into(),
        base_url: base_url.unwrap_or_else(|| "https://api.x.ai/v1".into()),
        bearer_token: None,
        api_key_header: ApiKeyHeaderScheme::AuthorizationBearer,
        http_headers: None,
        tool_wire_policy: ToolWirePolicy::FunctionFallback,
        apply_patch_tool_type: None,
        service_capabilities: ProtocolServiceCapabilities {
            prompt_cache: PromptCacheServiceCapabilities {
                dialect: if canonical {
                    PromptCacheDialect::ExplicitKey
                } else {
                    PromptCacheDialect::None
                },
            },
            ..ProtocolServiceCapabilities::default()
        },
    }
}
