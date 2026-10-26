use super::{super::StudioRuntime, McpReadTarget};
use anyhow::Result;
use pl_protocol::studio::McpResetRequest;
use std::future::Future;

impl StudioRuntime {
    pub fn mcp_reset_server(
        &self,
        server_id: String,
    ) -> impl Future<Output = Result<McpReadTarget>> + Send + 'static + use<> {
        self.mcp_reset(McpResetRequest::Server { server_id })
    }
    pub fn mcp_reset_all(
        &self,
    ) -> impl Future<Output = Result<McpReadTarget>> + Send + 'static + use<> {
        self.mcp_reset(McpResetRequest::All)
    }
    fn mcp_reset(
        &self,
        request: McpResetRequest,
    ) -> impl Future<Output = Result<McpReadTarget>> + Send + 'static + use<> {
        let runtime = self.clone();
        let pending = self.read_calls.run(async move {
            runtime.mcp_source.ensure_open()?;
            let captured = runtime.reset_mcp(request).await?;
            let target = runtime.mcp_source.expose_committed(&captured)?;
            Ok((target, captured))
        });
        async move {
            let (target, _capture) = pending.await?;
            Ok(target)
        }
    }
}
