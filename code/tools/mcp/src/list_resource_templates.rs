//! Lists templates without probing servers that omitted the resources capability.
use crate::support::{
    FrozenMcpLease, LeaseSlot, McpContext, McpError, McpOutput, ResourceOperation, list_output,
    validate_resource_server,
};
use pl_agent_tool::typed::TypedTool;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Input {
    pub server: Option<String>,
    pub cursor: Option<String>,
}

pub struct ListMcpResourceTemplates<L> {
    lease: LeaseSlot<L>,
}

impl<L: FrozenMcpLease> ListMcpResourceTemplates<L> {
    pub fn new(lease: L) -> Self {
        Self {
            lease: LeaseSlot::new(lease),
        }
    }
}

impl<L: FrozenMcpLease> TypedTool for ListMcpResourceTemplates<L> {
    const NAME: &'static str = "list_mcp_resource_templates";
    const DESCRIPTION: &'static str = "List resource templates provided by MCP servers.";
    type Args = Input;
    type Context = McpContext;
    type Output = McpOutput<()>;
    type Error = McpError<()>;

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
        validate_resource_server(&lease, input.server.as_deref())?;
        let value = lease
            .resource_query(
                input.server,
                ResourceOperation::ListResourceTemplates {
                    cursor: input.cursor,
                },
            )
            .await
            .map_err(McpError::new)?;
        list_output(value)
    }

    async fn close(&self) -> Result<(), Self::Error> {
        self.lease.release()
    }
}
