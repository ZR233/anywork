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

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use pl_core::model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, PreparedModelCall,
    };
    use pl_core::thread::ThreadHandle;
    use pl_tool::mcp::{McpConnector, McpRuntime};
    use std::{collections::BTreeMap, time::Duration};

    mod peer {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../pl-tool/tests/support/mcp_stdio.rs"
        ));
    }
    mod helper {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../pl-tool/tests/support/helper.rs"
        ));
    }
    struct UnusedModel;
    impl ModelSession for UnusedModel {
        async fn prepare(&mut self, _: ModelRequest) -> Result<PreparedModelCall, ModelError> {
            unreachable!("catalog exposure does not execute the model")
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[tokio::test]
    async fn resource_facades_are_installed_only_for_advertised_resources() -> anyhow::Result<()> {
        let root = tempfile::tempdir()?;
        let script =
            peer::write_python_mcp_server(root.path(), "exposure.py", peer::STDIO_MCP_SCRIPT);
        let runtime = McpRuntime::new(
            McpConnector::default()
                .with_stdio_worker(helper::remote_helper_executable().to_path_buf()),
        )
        .handle();
        for resources in [false, true] {
            let mut updates = runtime.subscribe();
            runtime
                .reconcile(BTreeMap::from([(
                    "peer".into(),
                    peer::stdio_effective_config(
                        "peer",
                        &script,
                        Vec::new(),
                        BTreeMap::from([
                            (
                                "MCP_NO_RESOURCES".into(),
                                if resources { "0" } else { "1" }.into(),
                            ),
                            ("MCP_BINDING_RESULTS".into(), "1".into()),
                            ("MCP_SCHEMA_TAG".into(), resources.to_string()),
                        ]),
                        Some(root.path().to_string_lossy().into_owned()),
                        pl_tool::mcp::config::McpExecutionContext::Host,
                    ),
                )]))
                .await?;
            let lease = tokio::time::timeout(Duration::from_secs(10), async {
                loop {
                    let lease = runtime.acquire_turn_lease().await?;
                    if lease.tools().first().is_some_and(|tool| {
                        tool.input_schema["description"] == resources.to_string()
                    }) {
                        return anyhow::Ok(lease);
                    }
                    updates.recv().await?;
                }
            })
            .await??;
            let mut tools = StudioThreadTools::selected(
                crate::resource_store::FileResourceStore::new(root.path().join("resources")),
                Vec::new(),
            );
            tools.capabilities.mcp = true;
            let tools = tools.with_mcp(lease.clone())?;
            let ids = tools
                .registrations
                .iter()
                .map(|tool| tool.tool_id())
                .collect::<Vec<_>>();
            for name in [
                "list_mcp_resources",
                "list_mcp_resource_templates",
                "read_mcp_resource",
            ] {
                assert_eq!(ids.contains(&name), resources, "{name} resource exposure");
            }
            assert_eq!(ids.len(), if resources { 4 } else { 1 });
            let thread = ThreadHandle::start(
                format!("exposure-{resources}"),
                DynModelSession::new(UnusedModel),
            )?;
            thread.register_tools(tools.registrations).await?;
            thread.close().await?;
            drop(lease);
        }
        runtime.shutdown().await?;
        Ok(())
    }
}
