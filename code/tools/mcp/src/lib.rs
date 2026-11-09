//! Dynamic MCP tools over immutable declarations and one frozen transport generation.
use pl_agent_tool::{Tool, ToolDefinition};
use pl_tool_mcp_support::{
    FrozenMcpLease, FrozenTool, LeaseSlot, McpContext, McpError, McpOutput, Observed, ResultKind,
    project_content,
};
use pl_tool_media_support::MediaHost;
use serde_json::Value;
use std::sync::Arc;

pub struct McpTool<L, H> {
    definition: ToolDefinition,
    descriptor: FrozenTool,
    generation: u64,
    lease: LeaseSlot<L>,
    media: Arc<H>,
}

impl<L: FrozenMcpLease, H: MediaHost> McpTool<L, H> {
    pub fn new(
        lease: L,
        exposed_name: &str,
        media: Arc<H>,
    ) -> Result<Self, McpError<H::Projection>> {
        let descriptor = lease
            .tool(exposed_name)
            .ok_or_else(|| McpError::invalid("tool is absent from the frozen MCP lease"))?;
        let definition = descriptor.definition().map_err(McpError::new)?;
        Ok(Self {
            definition,
            descriptor,
            generation: lease.generation(),
            lease: LeaseSlot::new(lease),
            media,
        })
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }
}

impl<L: FrozenMcpLease, H: MediaHost> Tool for McpTool<L, H> {
    type Input = String;
    type Context = McpContext;
    type Output = McpOutput<H::Projection>;
    type Error = McpError<H::Projection>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: String,
        context: McpContext,
    ) -> Result<Self::Output, Self::Error> {
        let arguments: Value = pl_agent_tool::typed::decode_json(&input).map_err(McpError::new)?;
        if !arguments.is_object() && !arguments.is_null() {
            return Err(McpError::invalid("MCP arguments must be an object or null"));
        }
        if context.cancellation.is_cancelled() {
            return Err(McpError::invalid("MCP call cancelled before dispatch"));
        }
        let lease = self.lease.acquire()?;
        // Once accepted, wait for the received outcome even if local cancellation arrives.
        let result = lease
            .call_tool(
                self.descriptor.server_id.clone(),
                self.descriptor.raw_name.clone(),
                arguments,
            )
            .await
            .map_err(McpError::new)?;
        let projected =
            match project_content(&result, self.media.as_ref(), context.image_limits).await {
                Ok(projected) => projected,
                Err(error) => {
                    return Err(error.with_unarchived(
                        serde_json::to_value(&result).map_err(McpError::new)?,
                        ResultKind::Tool,
                    ));
                }
            };
        if result.is_error == Some(true) {
            let mut error = McpError::invalid("MCP server reported a tool execution error");
            error.observed = Some(Observed::Projected(projected));
            Err(error)
        } else {
            Ok(projected)
        }
    }

    async fn close(&self) -> Result<(), Self::Error> {
        self.lease.release()
    }
}
