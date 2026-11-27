//! Dynamic LSP invocation without a product session or mutable tool call context.
use crate::workspace::ToolWorkspace;
use pl_agent_tool::Tool as _;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{ToolOutput, opaque::ToolError},
};
use pl_lsp::{query::LspQuery, runtime::LspRuntimeRegistry};
use pl_tool_lsp::support::{
    CapabilityReader, LspContext, Operation, QueryRequest, QueryResult, QueryService, StatusReader,
};
use std::sync::Arc;

/// Paths belong to the physical service host selected during Thread assembly.
#[derive(Debug, Clone)]
pub struct LspPathBinding {
    workspace: ToolWorkspace,
    files: Arc<crate::workspace_file::ExecutorWorkspaceFileBackend>,
}

impl LspPathBinding {
    pub fn new(
        workspace: ToolWorkspace,
        files: crate::workspace_file::ExecutorWorkspaceFileBackend,
    ) -> Self {
        Self {
            files: Arc::new(files.with_workspace(workspace.clone())),
            workspace,
        }
    }
    pub fn workspace_root(&self) -> &std::path::Path {
        self.workspace.root()
    }
    pub fn workspace(&self) -> &ToolWorkspace {
        &self.workspace
    }
    fn configuration_directory(&self) -> Result<String, ToolError> {
        let executor = self.files.executor();
        let root = executor
            .path(self.files.canonical_path())
            .map_err(ToolError::new)?;
        Ok(executor
            .join_path(&root, ".anywork/lsp")
            .map_err(ToolError::new)?
            .as_str()
            .into())
    }
    async fn resolve(
        &self,
        path: std::path::PathBuf,
        operation: pl_lsp::query::LspQueryOperation,
        grant: &pl_core::tool::execution_policy::ExecutionGrant,
    ) -> Result<std::path::PathBuf, ToolError> {
        use crate::workspace_file::WorkspaceFileBackend;
        let granted = self.files.for_grant(grant);
        let files = granted.as_ref().unwrap_or(&self.files);
        let path = path.to_str().ok_or_else(|| {
            ToolError::new(crate::tool_error("lsp_query", "query path is not UTF-8"))
        })?;
        let target = files
            .resolve_query_path(path, operation.requires_file())
            .await
            .map_err(ToolError::new)?;
        Ok(target.as_str().into())
    }
}

/// Stable LSP tool operations; current service readiness is returned as data, not inserted into schemas.
#[derive(Debug, Clone, Copy)]
pub enum LspToolKind {
    Status,
    Capabilities,
    Query,
}

impl LspToolKind {
    /// Stable model declaration for this operation.
    pub fn declaration(self) -> pl_agent_tool::ToolDefinition {
        match self {
            Self::Status => pl_tool_lsp::status::lsp_status_definition(),
            Self::Capabilities => pl_tool_lsp::capabilities::lsp_capabilities_definition(),
            Self::Query => pl_tool_lsp::query::lsp_query_definition(),
        }
    }
}

/// A Thread-owned tool instance over an explicitly shared language-service registry.
#[derive(Debug)]
pub struct ThreadLspTool {
    definition: pl_agent_tool::ToolDefinition,
    registry: LspRuntimeRegistry,
    paths: LspPathBinding,
    kind: LspToolKind,
}

impl ThreadLspTool {
    /// Binds service lookup and path validation to the same workspace.
    pub fn new(
        registry: LspRuntimeRegistry,
        paths: LspPathBinding,
        kind: LspToolKind,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        Self {
            definition,
            registry,
            paths,
            kind,
        }
    }
}

impl pl_agent_tool::Tool for ThreadLspTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = crate::invocation::WorkspaceInvocation;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: crate::invocation::WorkspaceInvocation,
    ) -> Result<ToolOutput, ToolError> {
        self.execute_bound(input, context.cancellation, context.grant)
            .await
    }
}

impl ThreadLspTool {
    async fn execute_bound(
        &self,
        input: OpaquePayload,
        cancellation: tokio_util::sync::CancellationToken,
        grant: pl_core::tool::execution_policy::ExecutionGrant,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(crate::tool_error(
                "lsp",
                "unsupported argument encoding",
            )));
        }
        if cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let service = ThreadLspPort {
            registry: self.registry.clone(),
            paths: self.paths.clone(),
            grant,
        };
        let domain_context = LspContext {
            service,
            cancellation,
        };
        let result = match self.kind {
            LspToolKind::Status => {
                let tool = pl_tool_lsp::status::LspStatusTool::new(self.definition.clone());
                let result = tool
                    .execute(input.content().to_owned(), domain_context)
                    .await
                    .map_err(|error| match error {
                        pl_tool_lsp::status::StatusError::Cancelled => {
                            ToolError::new(pl_core::thread::ThreadError::Cancelled)
                        }
                        error => ToolError::new(error),
                    })?;
                result.into_result().map_err(ToolError::new)?
            }
            LspToolKind::Capabilities => {
                let tool =
                    pl_tool_lsp::capabilities::LspCapabilitiesTool::new(self.definition.clone());
                let result = tool
                    .execute(input.content().to_owned(), domain_context)
                    .await
                    .map_err(|error| match error {
                        pl_tool_lsp::capabilities::CapabilitiesError::Cancelled => {
                            ToolError::new(pl_core::thread::ThreadError::Cancelled)
                        }
                        error => ToolError::new(error),
                    })?;
                result.into_result().map_err(ToolError::new)?
            }
            LspToolKind::Query => {
                let tool = pl_tool_lsp::query::LspQueryTool::new(self.definition.clone());
                let result = tool
                    .execute(input.content().to_owned(), domain_context)
                    .await
                    .map_err(|error| match error {
                        pl_tool_lsp::query::QueryError::Cancelled => {
                            ToolError::new(pl_core::thread::ThreadError::Cancelled)
                        }
                        pl_tool_lsp::query::QueryError::Path(error) => error,
                        error => ToolError::new(error),
                    })?;
                result.into_result().map_err(ToolError::new)?
            }
        };
        Ok(ToolOutput::new(result.map_content(|text| {
            ContextContent::Text { text: text.into() }
        })))
    }
}

// This adapter holds the existing registry and invocation grant. Tools cannot
// start/close servers, replace the registry, or manufacture a path grant.
struct ThreadLspPort {
    registry: LspRuntimeRegistry,
    paths: LspPathBinding,
    grant: pl_core::tool::execution_policy::ExecutionGrant,
}
impl StatusReader for ThreadLspPort {
    type Error = ToolError;

    async fn status(&self) -> Result<pl_tool_lsp::support::WorkspaceStatus, ToolError> {
        let root = self.paths.workspace().root();
        let servers = self.registry.snapshots_for_workspace(root).await;
        Ok(pl_tool_lsp::support::WorkspaceStatus {
            workspace_root: root.display().to_string(),
            configuration_directory: self.paths.configuration_directory()?,
            servers: servers
                .into_iter()
                .map(|server| pl_tool_lsp::support::ServerStatus {
                    id: server.id,
                    display_name: server.display_name,
                    language_ids: server.language_ids,
                    configuration_path: server.configuration_path,
                    phase: match server.phase {
                        pl_lsp::runtime::LspLifecyclePhase::Loading => "loading",
                        pl_lsp::runtime::LspLifecyclePhase::Probing => "probing",
                        pl_lsp::runtime::LspLifecyclePhase::Starting => "starting",
                        pl_lsp::runtime::LspLifecyclePhase::Initializing => "initializing",
                        pl_lsp::runtime::LspLifecyclePhase::Ready => "ready",
                        pl_lsp::runtime::LspLifecyclePhase::Failed => "failed",
                        pl_lsp::runtime::LspLifecyclePhase::Stopped => "stopped",
                        pl_lsp::runtime::LspLifecyclePhase::Disabled => "disabled",
                    }
                    .to_owned(),
                    availability: server.availability_kind.as_str().to_owned(),
                    message: server.availability_message,
                    activity: server.activity_kind.as_str().to_owned(),
                    activity_title: server.activity_title,
                    activity_message: server.activity_message,
                    activity_percentage: server.activity_percentage,
                    last_error: server.last_error,
                })
                .collect(),
        })
    }
}
impl CapabilityReader for ThreadLspPort {
    type Error = ToolError;
    async fn capabilities(&self) -> Result<pl_tool_lsp::support::Capabilities, ToolError> {
        let result = self
            .registry
            .capabilities_for_workspace(self.paths.workspace().root())
            .await;
        Ok(pl_tool_lsp::support::Capabilities {
            servers: result
                .servers
                .into_iter()
                .map(|server| pl_tool_lsp::support::ServerCapabilities {
                    id: server.id,
                    display_name: server.display_name,
                    language_ids: server.language_ids,
                    operations: server.operations,
                    availability: server.availability,
                    ready: server.ready,
                })
                .collect(),
        })
    }
}
impl QueryService for ThreadLspPort {
    type Error = ToolError;
    async fn resolve_path(
        &self,
        path: std::path::PathBuf,
        operation: Operation,
    ) -> Result<std::path::PathBuf, ToolError> {
        self.paths
            .resolve(path, host_operation(operation), &self.grant)
            .await
    }
    async fn query(&self, request: QueryRequest) -> Result<QueryResult, ToolError> {
        let operation = request.operation;
        let result = self
            .registry
            .query_in_workspace(
                self.paths.workspace().root(),
                LspQuery {
                    server_id: request.server_id,
                    operation: host_operation(operation),
                    file_path: request.file_path,
                    line: request.line,
                    character: request.character,
                    query: request.query,
                    max_results: request.max_results,
                    language_id: Some(request.language_id),
                },
            )
            .await
            .map_err(ToolError::new)?;
        Ok(QueryResult {
            success: result.success,
            operation,
            server_id: result.server_id,
            result: result.result,
            result_count: result.result_count,
            file_count: result.file_count,
        })
    }
}
fn host_operation(operation: Operation) -> pl_lsp::query::LspQueryOperation {
    use pl_lsp::query::LspQueryOperation as Host;
    match operation {
        Operation::GoToDefinition => Host::GoToDefinition,
        Operation::FindReferences => Host::FindReferences,
        Operation::Hover => Host::Hover,
        Operation::DocumentSymbol => Host::DocumentSymbol,
        Operation::WorkspaceSymbol => Host::WorkspaceSymbol,
        Operation::GoToImplementation => Host::GoToImplementation,
        Operation::PrepareCallHierarchy => Host::PrepareCallHierarchy,
        Operation::IncomingCalls => Host::IncomingCalls,
        Operation::OutgoingCalls => Host::OutgoingCalls,
        Operation::Diagnostics => Host::Diagnostics,
    }
}
