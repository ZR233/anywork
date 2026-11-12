//! Dynamic LSP invocation without a product session or mutable tool call context.
use crate::workspace::ToolWorkspace;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_lsp::{query::LspQuery, runtime::LspRuntimeRegistry};
use pl_tool_lsp::support::{
    CapabilityReader, LspContext, Operation, QueryRequest, QueryResult, QueryService, StatusReader,
};
use std::sync::Arc;

/// Paths belong to the physical service host selected during Thread assembly.
#[derive(Debug, Clone)]
pub enum LspPathBinding {
    Local(ToolWorkspace),
    Remote {
        workspace: ToolWorkspace,
        files: Arc<crate::remote::RemoteWorkspaceFileBackend>,
    },
}

impl LspPathBinding {
    pub fn workspace_root(&self) -> &std::path::Path {
        self.workspace().root()
    }

    fn workspace(&self) -> &ToolWorkspace {
        match self {
            Self::Local(workspace) | Self::Remote { workspace, .. } => workspace,
        }
    }

    async fn resolve(
        &self,
        path: std::path::PathBuf,
        operation: pl_lsp::query::LspQueryOperation,
        grant: &pl_core::tool::execution_policy::ExecutionGrant,
    ) -> Result<std::path::PathBuf, ToolError> {
        let resolved = match self {
            Self::Local(workspace) => {
                let root = workspace.root().to_owned();
                let host_access = workspace.workspace().boundary().allows_host_paths()
                    && grant.contains(crate::approval::HOST_WORKSPACE_ACCESS);
                tokio::task::spawn_blocking(move || {
                    let policy =
                        crate::workspace::ToolPathPolicy::new(root, host_access, "lsp_query")?;
                    let display = path.display().to_string();
                    if operation.requires_file() {
                        policy.resolve_existing_path(&path, &display)
                    } else {
                        policy.resolve_existing_or_parent_path(&path, &display)
                    }
                })
                .await
                .map_err(ToolError::new)?
                .map_err(ToolError::new)?
            }
            Self::Remote { files, .. } => {
                crate::remote::resolve_lsp_query_path(files, &path, operation)
                    .await
                    .map_err(ToolError::new)?
            }
        };
        Ok(resolved)
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

    /// Transfers an instance as a deferred tool with no framework control permissions.
    ///
    /// The supplied preparation has already validated the registration identity.
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let contract = match self.kind {
            LspToolKind::Status => "builtin.lsp_status@1",
            LspToolKind::Capabilities => "builtin.lsp_capabilities@1",
            LspToolKind::Query => "builtin.lsp_query@1",
        };
        let authorization = self.paths.workspace().authorization();
        prepared
            .attach(pl_agent_tool::ToolHandle::new(self))
            .with_presentation_contract(pl_core::model::ToolPresentationContract::new(contract))
            .deferred()
            .with_authorization(authorization)
    }
}

impl pl_agent_tool::Tool for ThreadLspTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(crate::tool_error(
                "lsp",
                "unsupported argument encoding",
            )));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let service = ThreadLspPort {
            registry: self.registry.clone(),
            paths: self.paths.clone(),
            grant: context.grant,
        };
        let domain_context = LspContext {
            service,
            cancellation: context.cancellation,
        };
        let (encoded, text) = match self.kind {
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
                result.encode().map_err(ToolError::new)?
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
                result.encode().map_err(ToolError::new)?
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
                result.encode().map_err(ToolError::new)?
            }
        };
        Ok(ToolOutput::new(
            OpaquePayload::new("pl.tool.lsp", 1, encoded).map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: Arc::from(text),
            }],
        ))
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
            configuration_directory: root.join(".anywork/lsp").display().to_string(),
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
