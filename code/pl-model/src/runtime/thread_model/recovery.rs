//! Apply a saved logical plan to new, confirmed input; never replay a saved prompt or stream.

use std::collections::BTreeSet;

use pl_core::{
    context::OpaquePayload,
    model::{ModelRequest, ModelToolDeclaration, ToolCallMode},
};

use super::{AdapterError, ModelError, ModelFailureKind, ThreadModel, failure, receipt};
use crate::completion::{CompletionRequest, ToolSpec};

fn incompatible(message: &'static str) -> ModelError {
    failure(
        ModelFailureKind::IncompatibleContext,
        AdapterError::Content(message),
    )
}

pub(super) fn apply(
    configuration: &ThreadModel,
    request: &ModelRequest,
    parameters: &OpaquePayload,
    declarations: &[(&ModelToolDeclaration, ToolSpec)],
    encoded: &mut CompletionRequest,
) -> Result<String, ModelError> {
    let saved = receipt::model_request_receipt(parameters).map_err(|mut error| {
        error.kind = ModelFailureKind::IncompatibleContext;
        error
    })?;
    let saved_model = saved.sent_model.as_deref().ok_or_else(|| incompatible(
        "saved request has no sentModel; compatibility with the original physical model cannot be proven",
    ))?;
    let target = receipt::ModelCallBinding::capture(&configuration.runtime, &configuration.purpose);
    if saved.binding.account_id != target.account_id
        || saved.binding.model_id != target.model_id
        || saved.binding.protocol != target.protocol
        || saved.binding.wire_api != target.wire_api
        || saved.binding.isolation != target.isolation
    {
        return Err(incompatible(
            "saved request belongs to a different account, model or protocol binding",
        ));
    }
    if saved.parallel_tool_calls
        && saved.tool_choice != "none"
        && !saved.tools.is_empty()
        && (request.tool_call_mode != ToolCallMode::Parallel
            || !configuration
                .runtime
                .model()
                .capabilities
                .tools
                .parallel_tool_calls)
    {
        return Err(incompatible(
            "saved parallel tool calls conflict with the current Core tool policy",
        ));
    }
    if saved
        .max_tokens
        .zip(configuration.runtime.context().context_window)
        .is_some_and(|(output, window)| output >= window)
    {
        return Err(incompatible(
            "saved output budget exhausts the current model context window",
        ));
    }

    // The receipt owns the advertised subset, but only Core's catalog grants local execution.
    // Project that catalog with the saved hosted plan, not today's hosted defaults.
    let mut names = BTreeSet::new();
    let tools = saved
        .tools
        .iter()
        .map(|tool| {
            if !names.insert(tool.name()) {
                return Err(incompatible("saved tools contain conflicting identities"));
            }
            if tool.is_hosted() {
                let capabilities = &configuration.runtime.endpoint().service_capabilities;
                let supported = match tool {
                    ToolSpec::WebSearch { options } => {
                        use pl_protocol::{HostedWebSearchDialect, HostedWebSearchOptions};
                        capabilities.web_search.hosted_responses
                            && matches!(
                                (options, capabilities.web_search.hosted_dialect),
                                (
                                    HostedWebSearchOptions::OpenAi { .. },
                                    HostedWebSearchDialect::OpenAiResponses
                                ) | (
                                    HostedWebSearchOptions::DeepSeek,
                                    HostedWebSearchDialect::DeepSeekResponses
                                )
                            )
                    }
                    ToolSpec::ProgrammaticToolCalling => {
                        capabilities.responses_tools.programmatic_tool_calling
                            && configuration
                                .runtime
                                .model()
                                .binding
                                .request
                                .supports_programmatic_tool_calling()
                    }
                    ToolSpec::Function { .. } | ToolSpec::Custom { .. } => {
                        unreachable!("hosted tool")
                    }
                };
                if !supported {
                    return Err(incompatible(
                        "saved hosted tool format is not supported by this account binding",
                    ));
                }
                if declarations
                    .iter()
                    .any(|(_, spec)| spec.name() == tool.name())
                {
                    return Err(incompatible(
                        "saved hosted tool conflicts with the Core tool catalog",
                    ));
                }
                Ok(tool.clone())
            } else {
                declarations
                    .iter()
                    .find(|(_, spec)| !spec.is_hosted() && spec.name() == tool.name())
                    .map(|(_, spec)| spec.clone())
                    .ok_or_else(|| {
                        incompatible("saved local tool is not registered in the Core tool catalog")
                    })
            }
        })
        .collect::<Result<Vec<_>, _>>()?;
    let mut plan = CompletionRequest::builder()
        .tools(tools)
        .tool_choice(saved.tool_choice)
        .parallel_tool_calls(saved.parallel_tool_calls)
        .reasoning(saved.reasoning)
        .temperature(saved.temperature)
        .maybe_max_tokens(saved.max_tokens)
        .build();
    plan.frozen_options = true;
    plan = configuration
        .runtime
        .prepare_request(plan)
        .map_err(|error| failure(ModelFailureKind::IncompatibleContext, error))?;
    if plan.tools != saved.tools {
        return Err(incompatible(
            "saved tools no longer match the projected Core tool catalog",
        ));
    }
    let sent_model = configuration
        .runtime
        .project_request_options(&plan, &request.thread_id)
        .map_err(|error| failure(ModelFailureKind::IncompatibleContext, error))?;
    if sent_model != saved_model {
        return Err(incompatible(
            "saved request targets a different physical model after wire projection",
        ));
    }

    encoded.tools = plan.tools;
    encoded.tool_choice = plan.tool_choice;
    encoded.parallel_tool_calls = plan.parallel_tool_calls;
    encoded.reasoning = plan.reasoning;
    encoded.temperature = plan.temperature;
    encoded.max_tokens = plan.max_tokens;
    encoded.frozen_options = true;
    Ok(sent_model)
}
