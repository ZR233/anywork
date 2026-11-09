//! Lists only servers assigned resource capability by the frozen MCP lease.
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

pub struct ListMcpResources<L> {
    lease: LeaseSlot<L>,
}

impl<L: FrozenMcpLease> ListMcpResources<L> {
    pub fn new(lease: L) -> Self {
        Self {
            lease: LeaseSlot::new(lease),
        }
    }
}

impl<L: FrozenMcpLease> TypedTool for ListMcpResources<L> {
    const NAME: &'static str = "list_mcp_resources";
    const DESCRIPTION: &'static str = "List resources provided by MCP servers.";
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
                ResourceOperation::ListResources {
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
