use std::sync::Arc;

use rmcp::{
    RoleServer, ServerHandler,
    model::{
        CallToolRequestParams, CallToolResponse, CallToolResult, ContentBlock, ErrorData,
        ListToolsResult, PaginatedRequestParams, ServerCapabilities, ServerConfig, Tool,
    },
    service::RequestContext,
};

use crate::{HostContent, HostError, HostInvocation, HostTools};

/// The same protocol service is used by in-process HTTP and IPC-backed stdio.
#[derive(Clone)]
pub struct HostMcpService<B> {
    backend: B,
}

impl<B: HostTools> HostMcpService<B> {
    pub fn new(backend: B) -> Self {
        Self { backend }
    }
}

fn protocol_error(error: HostError) -> ErrorData {
    match error {
        HostError::InvalidRequest | HostError::TooLarge => {
            ErrorData::invalid_params(error.to_string(), None)
        }
        _ => ErrorData::internal_error(error.to_string(), None),
    }
}

impl<B: HostTools> ServerHandler for HostMcpService<B> {
    fn get_info(&self) -> ServerConfig {
        let mut config = ServerConfig::default();
        config.capabilities = ServerCapabilities::builder().enable_tools().build();
        config.instructions = Some("Use anywork_ tools for anywork-managed collaboration. Tool prefixes do not change permissions.".into());
        config
    }

    async fn list_tools(
        &self,
        request: Option<PaginatedRequestParams>,
        _: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        if request.is_some_and(|request| request.cursor.is_some()) {
            return Err(ErrorData::invalid_params(
                "this tool list is not paginated",
                None,
            ));
        }
        let tools = self
            .backend
            .catalog()
            .await
            .map_err(protocol_error)?
            .into_iter()
            .map(|entry| {
                let mut tool = Tool::default();
                tool.name = entry.tool_id.into();
                tool.description = Some(entry.description.into());
                tool.input_schema = Arc::new(entry.input_schema);
                tool.output_schema = entry.output_schema.map(Arc::new);
                tool
            })
            .collect();
        Ok(ListToolsResult {
            tools,
            ..Default::default()
        })
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, ErrorData> {
        let tool_id = self
            .backend
            .catalog()
            .await
            .map_err(protocol_error)?
            .into_iter()
            .find(|entry| entry.tool_id == request.name)
            .map(|entry| entry.tool_id)
            .ok_or_else(|| ErrorData::invalid_params("unknown host tool", None))?;
        let cancellation = context.ct.child_token();
        let _cancel_on_drop = cancellation.clone().drop_guard();
        let result = self
            .backend
            .invoke(
                HostInvocation {
                    tool_id,
                    arguments: request.arguments.unwrap_or_default(),
                },
                cancellation,
            )
            .await
            .map_err(protocol_error)?;
        // MCP structuredContent is an object. Keep the author value under a
        // fixed transport field; ToolProjection applies the matching schema.
        let structured_content = result
            .result
            .data()
            .map(|value| serde_json::json!({"result": value}));
        let content = result
            .result
            .content()
            .iter()
            .map(|content| match content {
                HostContent::Text(text) => ContentBlock::text(text.clone()),
                HostContent::Image { data, mime_type } => {
                    ContentBlock::image(data.clone(), mime_type.clone())
                }
            })
            .collect();
        let mut response = if result.is_error {
            CallToolResult::error(content)
        } else {
            CallToolResult::success(content)
        };
        response.structured_content = structured_content;
        Ok(response.into())
    }
}
