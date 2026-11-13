//! Explicit session replacement bound to the original physical Thread MCP owner.

use std::sync::{Arc, Weak};

use pl_agent_tool::{ToolHandle, typed::TypedTool};
use pl_core::tool::opaque::{CallContext, Registration, ToolError};
use pl_protocol::ThreadMcpStateSnapshot;
use pl_tool::binding::{ToolCallPolicy, prepare_json_tool, prepare_registration};

use super::{StudioThreadFactory, mcp::ThreadMcpOwner, mcp_refresh_tool::McpToolCatalogStatus};
use crate::thread_assembler::ThreadAssemblyError;

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ReconnectMcpInput {
    #[schemars(length(min = 1))]
    server_id: String,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ReconnectMcpReceipt {
    server_id: String,
    catalog_revision: u64,
    runtime_generation: u64,
    state: ThreadMcpStateSnapshot,
    tool_catalog: McpToolCatalogStatus,
    session_state_reset: bool,
    guidance: &'static str,
}

struct ReconnectMcpTool {
    factory: StudioThreadFactory,
    owner: Weak<ThreadMcpOwner>,
}

#[derive(Debug, thiserror::Error)]
enum ReconnectMcpError {
    #[error("serverId must be a non-empty string")]
    EmptyServerId,
    #[error("MCP owner is no longer active")]
    InactiveOwner,
    #[error("MCP reconnect belongs to a different Thread")]
    WrongThread,
    #[error(transparent)]
    Reconnect(anyhow::Error),
}

impl TypedTool for ReconnectMcpTool {
    const NAME: &'static str = "reconnect_mcp";
    const DESCRIPTION: &'static str = "Explicitly replace one configured MCP server session in the calling Thread after a connection failure. Requires a non-empty serverId; cannot target another Thread, override configuration or restart other servers. Repeats handshake and tool discovery, not historical tool calls. Reports actual connection state and runtime generation separately from scheduled tool-catalog installation. Session state is reset: register Dart roots and reconnect runtime/debug sessions again. Use discover_tools after the catalog refresh to inspect available tools.";
    type Args = ReconnectMcpInput;
    type Context = CallContext;
    type Output = ReconnectMcpReceipt;
    type Error = ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<Self::Output, Self::Error> {
        if input.server_id.trim().is_empty() {
            return Err(ToolError::new(ReconnectMcpError::EmptyServerId));
        }
        let owner = self
            .owner
            .upgrade()
            .ok_or_else(|| ToolError::new(ReconnectMcpError::InactiveOwner))?;
        if context.thread_id != owner.thread_id {
            return Err(ToolError::new(ReconnectMcpError::WrongThread));
        }
        let (catalog_revision, runtime_generation, state) = self
            .factory
            .reconnect_mcp_for_owner(&owner, Some(&input.server_id), context.cancellation)
            .await
            .map_err(|error| ToolError::new(ReconnectMcpError::Reconnect(error)))?;
        Ok(ReconnectMcpReceipt {
            server_id: input.server_id,
            catalog_revision,
            runtime_generation,
            state,
            tool_catalog: McpToolCatalogStatus::RefreshScheduled,
            session_state_reset: true,
            guidance: "The server session was replaced. Register Dart roots and reconnect runtime/debug sessions as needed; historical calls were not replayed. Use discover_tools to observe the asynchronously installed tool catalog.",
        })
    }
}

pub(super) fn registration(
    factory: StudioThreadFactory,
    owner: &Arc<ThreadMcpOwner>,
) -> Result<Registration, ThreadAssemblyError> {
    let tool =
        prepare_json_tool::<ReconnectMcpTool>(std::convert::identity, std::convert::identity)?;
    let prepared = prepare_registration(
        "reconnect_mcp",
        tool.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    Ok(
        prepared.attach(ToolHandle::new(tool.attach(ReconnectMcpTool {
            factory,
            owner: Arc::downgrade(owner),
        }))),
    )
}
