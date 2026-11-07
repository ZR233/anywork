//! MCP tools and resource façades share the Thread's persistent media host.
use super::{StudioThreadTools, ThreadAssemblyError, media::MediaHost};
use pl_tool::binding::{ToolCallPolicy, prepare_registration};
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
        let media = Arc::new(MediaHost(self.store.clone()));
        for descriptor in lease.tools() {
            let definition = descriptor.definition()?;
            let policy = if descriptor.effect == Some(pl_tool::approval::ToolEffect::Read) {
                ToolCallPolicy::DirectAndProgrammatic
            } else {
                ToolCallPolicy::DirectOnly
            };
            let prepared = prepare_registration(&descriptor.exposed_name, &definition, policy)?;
            let tool = ThreadMcpTool::new(lease.clone(), &descriptor.exposed_name, media.clone())
                .map_err(|error| pl_core::thread::ThreadError::Tool(Arc::new(error)))?;
            self.registrations.push(tool.registration(prepared));
        }
        if lease.has_resources() {
            for kind in pl_tool::mcp::resources::McpResourceToolKind::all() {
                let definition = kind.definition();
                let prepared = prepare_registration(
                    kind.name(),
                    &definition,
                    ToolCallPolicy::DirectAndProgrammatic,
                )?;
                let tool = pl_tool::mcp::resources::ThreadMcpResourceTool::new(
                    lease.clone(),
                    *kind,
                    media.clone(),
                    definition,
                );
                self.registrations.push(tool.registration(prepared));
            }
        }
        Ok(self)
    }
}
