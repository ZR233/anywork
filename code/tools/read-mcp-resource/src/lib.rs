//! Reads and projects a resource from a frozen, explicitly resource-capable MCP server.
use pl_agent_tool::typed::TypedTool;
use pl_tool_mcp_support::{
    FrozenMcpLease, LeaseSlot, McpContext, McpError, McpOutput, ResourceOperation,
    project_resource, validate_resource_server,
};
pub const NAME: &str = "read_mcp_resource";
pub const DESCRIPTION: &str = "Read a specific resource from an MCP server.";
use pl_tool_media::MediaHost;
use std::sync::Arc;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Input {
    pub server: String,
    pub uri: String,
}

pub struct ReadMcpResource<L, H> {
    lease: LeaseSlot<L>,
    media: Arc<H>,
}

impl<L: FrozenMcpLease, H: MediaHost> ReadMcpResource<L, H> {
    pub fn new(lease: L, media: Arc<H>) -> Self {
        Self {
            lease: LeaseSlot::new(lease),
            media,
        }
    }
}

impl<L: FrozenMcpLease, H: MediaHost> TypedTool for ReadMcpResource<L, H> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Input;
    type Context = McpContext;
    type Output = McpOutput<H::Projection>;
    type Error = McpError<H::Projection>;

    async fn execute(
        &self,
        input: Input,
        context: McpContext,
    ) -> Result<Self::Output, Self::Error> {
        if context.cancellation.is_cancelled() {
            return Err(McpError::invalid(
                "MCP resource query cancelled before dispatch",
            ));
        }
        let lease = self.lease.acquire()?;
        validate_resource_server(&lease, Some(&input.server))?;
        let value = lease
            .resource_query(
                Some(input.server),
                ResourceOperation::ReadResource { uri: input.uri },
            )
            .await
            .map_err(McpError::new)?;
        project_resource(value, self.media.as_ref(), context.image_limits).await
    }

    async fn close(&self) -> Result<(), Self::Error> {
        self.lease.release()
    }
}
