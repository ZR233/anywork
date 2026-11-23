//! Provider-native history compatibility belongs to the selected model adapter.
use crate::completion::ModelContextItem;
use crate::completion::tool_schema::ToolProjection;
use crate::protocol::WireApi;
use crate::{PureError, Result};

use super::ModelRuntime;

impl ModelRuntime {
    /// Checks whether this binding can consume every supplied native context item.
    ///
    /// # Errors
    /// Rejects incompatible native material without rewriting or dropping history.
    pub fn validate_context(&self, items: &[ModelContextItem]) -> Result<()> {
        validate(self.model().binding.transport.protocol, items)
    }
    /// Projects tools and checks capabilities before the caller admits this frozen request.
    ///
    /// # Errors
    /// Rejects unsupported content, tool schemas and model parameters without starting IO.
    pub fn prepare_request(
        &self,
        request: crate::completion::CompletionRequest,
    ) -> Result<crate::completion::CompletionRequest> {
        project_request(self.endpoint(), self.model(), self.account_id(), request)
    }
}

pub(super) fn validate(protocol: WireApi, items: &[ModelContextItem]) -> Result<()> {
    if protocol == WireApi::Responses {
        return Ok(());
    }
    for item in items {
        match item {
            ModelContextItem::Compaction { .. } | ModelContextItem::Native { .. } => {
                return Err(PureError::ConfigError(
                    "session history contains native Responses context (for example an encrypted \
                     compaction checkpoint) that a Chat Completions model cannot consume; use a \
                     Responses-protocol model for this session or start a new session"
                        .into(),
                ));
            }
            ModelContextItem::Message { .. }
            | ModelContextItem::ToolResult { .. }
            | ModelContextItem::ToolMedia { .. } => {}
        }
    }
    Ok(())
}

pub(super) fn project_request(
    endpoint: &crate::protocol::ProtocolEndpoint,
    model: &crate::model::ModelInfo,
    account_id: &str,
    mut request: crate::completion::CompletionRequest,
) -> Result<crate::completion::CompletionRequest> {
    pl_model_openai_wire::service_tiers::validate(
        endpoint,
        model,
        request.service_tier.as_deref(),
    )?;
    if endpoint.authorization.is_some() {
        super::openai::validate_chatgpt_request(&request)?;
        if !endpoint.service_capabilities.web_search.hosted_responses
            && request
                .tools
                .iter()
                .any(|tool| matches!(tool, crate::completion::ToolSpec::WebSearch { .. }))
        {
            return Err(PureError::ConfigError(
                "ChatGPT request.tools.web_search requires the account's hosted search capability"
                    .into(),
            ));
        }
    }
    validate(model.binding.transport.protocol, &request.input)?;
    if model.binding.transport.protocol == WireApi::ChatCompletions
        && model
            .capabilities
            .interleaved
            .as_ref()
            .is_some_and(|capability| {
                capability.field == crate::model::reasoning_fields::REASONING_DETAILS
            })
        && request
            .input
            .iter()
            .filter_map(ModelContextItem::as_message)
            .any(|message| {
                message
                    .reasoning_content
                    .as_ref()
                    .is_some_and(|text| !text.is_empty())
            })
    {
        return Err(PureError::ConfigError(
            "typed reasoning_details cannot be reconstructed from text reasoning history".into(),
        ));
    }
    let isolation = crate::runtime::binding_cache_namespace(account_id, endpoint);
    if request.replay_spans.iter().any(|span| {
        span.source_isolation
            .as_deref()
            .is_some_and(|source| source != isolation)
            && span.output.iter().any(|item| {
                item.get("type").and_then(serde_json::Value::as_str) == Some("reasoning")
            })
    }) {
        return Err(PureError::ConfigError(
            "this request cannot replay native reasoning from a different credential owner".into(),
        ));
    }
    let capabilities = model
        .capabilities
        .clone()
        .with_native_custom_tools(endpoint.uses_native_custom_tools());
    let projection = ToolProjection::for_endpoint(endpoint, &capabilities);
    let mut request = if endpoint.authorization.is_some() {
        // The SIWC plan is frozen: do not convert custom tools to functions (or synthesize
        // apply_patch grammar) as the generic API compatibility path is allowed to do.
        for tool in &mut request.tools {
            if let crate::completion::ToolSpec::Function { input_schema, .. } = tool {
                crate::completion::tool_schema::project_function_schema(input_schema);
            }
        }
        request.tools = crate::completion::stable_tool_schemas(request.tools);
        request
    } else {
        request.provider_compatible(projection)
    };
    if endpoint.authorization.is_none()
        && !request
            .tools
            .iter()
            .any(crate::completion::ToolSpec::is_programmatic_tool_calling)
    {
        for tool in &mut request.tools {
            match tool {
                crate::completion::ToolSpec::Function {
                    allowed_callers,
                    output_schema,
                    ..
                }
                | crate::completion::ToolSpec::Custom {
                    allowed_callers,
                    output_schema,
                    ..
                } => {
                    if allowed_callers.contains(&crate::completion::ToolCallerMode::Programmatic) {
                        if !allowed_callers.contains(&crate::completion::ToolCallerMode::Direct) {
                            return Err(PureError::ConfigError(
                                "programmatic-only tool requires the selected hosted coordinator"
                                    .into(),
                            ));
                        }
                        allowed_callers.clear();
                        *output_schema = None;
                    }
                }
                crate::completion::ToolSpec::WebSearch { .. }
                | crate::completion::ToolSpec::ProgrammaticToolCalling => {}
            }
        }
    }

    request.validate_against(&model.model_id, &capabilities)?;
    Ok(request)
}
