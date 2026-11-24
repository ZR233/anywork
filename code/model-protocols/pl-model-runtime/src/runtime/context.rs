//! Provider-native history compatibility belongs to the selected model adapter.
use crate::completion::ModelContextItem;
use crate::completion::tool_schema::ToolProjection;
use crate::{PureError, Result};
use pl_model_wire::wire_codec::WireCodec;

use super::ModelRuntime;

impl ModelRuntime {
    /// Checks whether this binding can consume every supplied native context item.
    ///
    /// # Errors
    /// Rejects incompatible native material without rewriting or dropping history.
    pub fn validate_context(&self, items: &[ModelContextItem]) -> Result<()> {
        self.codec
            .validate_context_items(self.model().binding.transport.protocol, items)
    }
    /// Projects tools and checks capabilities before the caller admits this frozen request.
    ///
    /// # Errors
    /// Rejects unsupported content, tool schemas and model parameters without starting IO.
    pub fn prepare_request(
        &self,
        request: crate::completion::CompletionRequest,
    ) -> Result<crate::completion::CompletionRequest> {
        project_request(
            self.endpoint(),
            self.model(),
            self.account_id(),
            self.codec,
            request,
        )
    }
}

pub(super) fn project_request(
    endpoint: &crate::protocol::ProtocolEndpoint,
    model: &crate::model::ModelInfo,
    account_id: &str,
    codec: &dyn WireCodec,
    mut request: crate::completion::CompletionRequest,
) -> Result<crate::completion::CompletionRequest> {
    let isolation = crate::runtime::binding_cache_namespace(account_id, endpoint);
    codec.validate_context(endpoint, model, &isolation, &request)?;
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
