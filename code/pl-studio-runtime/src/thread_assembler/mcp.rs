//! MCP tools and resource façades share the Thread's persistent media host.
use super::{StudioThreadTools, ThreadAssemblyError, media::MediaHost};
use pl_tool::mcp::{McpTurnLease, thread::ThreadMcpTool};
use std::sync::Arc;

impl StudioThreadTools {
    /// Creates Thread-local deferred MCP tools over the supplied generation's shared service lease.
    /// All retained resources use the same store installed as this Thread's resource reader.
    ///
    /// # Errors
    /// Rejects missing lease identities, model declaration encoding or tool registration errors.
    pub fn with_mcp(mut self, lease: McpTurnLease) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.mcp {
            return Ok(self);
        }
        let archive = self.archive.clone().ok_or_else(|| {
            ThreadAssemblyError::Identity(
                "MCP media requires the Thread's shared reliable resource owner".into(),
            )
        })?;
        let media = Arc::new(MediaHost(archive));
        for descriptor in lease.tools() {
            let tool = ThreadMcpTool::new(lease.clone(), &descriptor.exposed_name, media.clone())
                .map_err(|error| pl_core::thread::ThreadError::Tool(Arc::new(error)))?;
            let declaration = pl_model::runtime::thread_tool_declaration(&tool.declaration())?;
            self.registrations.push(tool.registration(declaration)?);
        }
        if lease.has_resources() {
            for kind in pl_tool::mcp::resources::McpResourceToolKind::all() {
                let tool = pl_tool::mcp::resources::ThreadMcpResourceTool::new(
                    lease.clone(),
                    *kind,
                    media.clone(),
                );
                let declaration = pl_model::runtime::thread_tool_declaration(&tool.declaration())?;
                self.registrations.push(tool.registration(declaration)?);
            }
        }
        Ok(self)
    }
}
