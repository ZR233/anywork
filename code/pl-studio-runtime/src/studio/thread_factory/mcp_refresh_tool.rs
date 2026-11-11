//! Product-owned configuration refresh, bound to one physical Thread MCP owner.

use std::sync::{Arc, Weak};

use pl_agent_tool::ToolHandle;
use pl_agent_tool::typed::TypedTool;
use pl_core::tool::opaque::{CallContext, Registration, ToolError};
use pl_protocol::{McpScope, ThreadMcpStateSnapshot};
use pl_tool::binding::{ToolCallPolicy, prepare_json_tool, prepare_registration};

use super::{StudioThreadFactory, mcp::ThreadMcpOwner};
use crate::thread_assembler::ThreadAssemblyError;

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub(super) struct RefreshMcpInput {}

/// Runtime discovery and catalog installation are deliberately separate facts.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ThreadMcpRefreshReceipt {
    pub scope: McpScope,
    pub catalog_revision: u64,
    pub discovery: pl_tool::mcp::McpToolRefreshReport,
    pub state: ThreadMcpStateSnapshot,
    pub tool_catalog: McpToolCatalogStatus,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum McpToolCatalogStatus {
    RefreshScheduled,
}

struct RefreshMcpTool {
    factory: StudioThreadFactory,
    owner: Weak<ThreadMcpOwner>,
}

#[derive(Debug, thiserror::Error)]
enum RefreshMcpError {
    #[error("MCP owner is no longer active")]
    InactiveOwner,
    #[error("MCP refresh belongs to a different Thread")]
    WrongThread,
    #[error(transparent)]
    Refresh(anyhow::Error),
}

impl TypedTool for RefreshMcpTool {
    const NAME: &'static str = "refresh_mcp";
    const DESCRIPTION: &'static str = "Reload the calling Thread's fixed MCP configuration scope (including Host inheritance for SSH), apply server configuration differences, and re-list tools over available connections without restarting unchanged servers. Takes an empty object; cannot target another Thread or edit configuration. Reports catalog revision, runtime discovery outcomes and connection state separately from scheduled tool-catalog installation. Connecting, skipped or failed servers are not successful discoveries. Use discover_tools after catalog refresh to inspect available tools; use the Thread reconnect action for transport failures.";
    type Args = RefreshMcpInput;
    type Context = CallContext;
    type Output = ThreadMcpRefreshReceipt;
    type Error = ToolError;

    async fn execute(
        &self,
        _: Self::Args,
        context: CallContext,
    ) -> Result<Self::Output, Self::Error> {
        let owner = self
            .owner
            .upgrade()
            .ok_or_else(|| ToolError::new(RefreshMcpError::InactiveOwner))?;
        if context.thread_id != owner.thread_id {
            return Err(ToolError::new(RefreshMcpError::WrongThread));
        }
        self.factory
            .refresh_mcp_for_owner(&owner, context.cancellation)
            .await
            .map_err(|error| ToolError::new(RefreshMcpError::Refresh(error)))
    }
}

pub(super) fn registration(
    factory: StudioThreadFactory,
    owner: &Arc<ThreadMcpOwner>,
) -> Result<Registration, ThreadAssemblyError> {
    let tool = prepare_json_tool::<RefreshMcpTool>(std::convert::identity, std::convert::identity)?;
    let prepared =
        prepare_registration("refresh_mcp", tool.definition(), ToolCallPolicy::DirectOnly)?;
    Ok(prepared.attach(ToolHandle::new(tool.attach(RefreshMcpTool {
        factory,
        owner: Arc::downgrade(owner),
    }))))
}
