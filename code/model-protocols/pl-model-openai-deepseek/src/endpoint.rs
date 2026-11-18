use pl_model_openai_wire::protocol::*;

pub const ID: ProtocolId = ProtocolId::from_static("deep_seek");

pub fn endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    let canonical = base_url
        .as_deref()
        .is_none_or(|url| url.trim_end_matches('/') == "https://api.deepseek.com");
    ProtocolEndpoint {
        protocol: ID,
        responses_instruction_role: crate::adapter::ADAPTER.responses_instruction_role,
        authorization: None,
        name: "DeepSeek".into(),
        base_url: base_url.unwrap_or_else(|| "https://api.deepseek.com".into()),
        bearer_token: None,
        http_headers: None,
        tool_wire_policy: ToolWirePolicy::FunctionFallback,
        apply_patch_tool_type: None,
        service_capabilities: ProtocolServiceCapabilities {
            // DeepSeek 的 in-history/leading-only 更新能力只在 Messages API 下声明，
            // Responses 不可证明；这里不声明历史指令覆盖能力，安全走 ReplacePrefix。
            history_instruction_role: HistoryInstructionRole::None,
            files: if canonical {
                crate::upload::FILE_UPLOAD.id.clone()
            } else {
                FileUploadCapability::NONE
            },
            web_search: WebSearchServiceCapabilities {
                standalone: canonical.then_some(crate::endpoint::SEARCH_DIALECT),
                ..WebSearchServiceCapabilities::default()
            },
            prompt_cache: PromptCacheServiceCapabilities {
                dialect: PromptCacheDialect::ImplicitPrefix,
            },
            ..ProtocolServiceCapabilities::default()
        },
    }
}

pub const SEARCH_DIALECT: StandaloneWebSearchDialect =
    StandaloneWebSearchDialect::from_static("deep_seek_tools_api");

pub const HOSTED_SEARCH_DIALECT: HostedWebSearchDialect =
    HostedWebSearchDialect::from_static("deep_seek_responses");
