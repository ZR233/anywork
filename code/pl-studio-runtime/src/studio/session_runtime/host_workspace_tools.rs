//! Shared workspace-family assembly. Consumers prepare transport material before
//! attaching a static author, and erase that author exactly once at their boundary.
use super::ThreadAssemblyError;
use super::tools::{StudioCommandBinding, StudioGitBinding};
use crate::resource_store::FileResourceStore;
use pl_agent_tool::{Tool, ToolDefinition};
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{ToolAuthorization, ToolError},
    },
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_native_tool},
    invocation::WorkspaceInvocation,
};
use std::{path::PathBuf, sync::Arc};

pub(crate) type CommandProcesses =
    Arc<pl_tool::command::CommandProcessManager<pl_tool::command::ExecutorCommandBackend>>;

pub(crate) struct WorkspaceResources {
    pub commands: Option<CommandProcesses>,
    /// Shared physical file binding for the session's workspace tools.
    pub files: Arc<pl_tool::workspace_file::ExecutorWorkspaceFileBackend>,
}

#[derive(Debug, Clone, Copy)]
pub(crate) enum HostToolDomain {
    Workspace,
    Skill,
}

/// JSON values whose author schema is not an object need a protocol-level carrier.
/// Raw text and grammar projection are determined from ToolDefinition, not here.
#[derive(Debug, Clone, Copy)]
pub(crate) enum HostJsonInput {
    Object,
    Value,
}

#[derive(Debug, Clone, Copy)]
pub(crate) enum HostScheduling {
    Default,
    Foreground,
    ForegroundCoexisting,
}

#[derive(Debug)]
pub(crate) struct HostToolMetadata {
    pub policy: ToolCallPolicy,
    pub domain: HostToolDomain,
    pub json_input: HostJsonInput,
    pub presentation: Option<&'static str>,
    pub authorization: Option<ToolAuthorization>,
    pub scheduling: HostScheduling,
    pub deferred: bool,
    pub nested: Option<bool>,
    /// Only the Native owner may commit the corresponding extension mutation.
    pub native_skill_view_effect: bool,
}
impl HostToolMetadata {
    fn workspace(authorization: ToolAuthorization) -> Self {
        Self {
            authorization: Some(authorization),
            ..Self::plain()
        }
    }
    fn plain() -> Self {
        Self {
            policy: ToolCallPolicy::DirectOnly,
            domain: HostToolDomain::Workspace,
            json_input: HostJsonInput::Object,
            presentation: None,
            authorization: None,
            scheduling: HostScheduling::Default,
            deferred: false,
            nested: None,
            native_skill_view_effect: false,
        }
    }
}

/// Not a registry or execution interface: this transfers a single statically
/// typed author to the actual Native or MCP owner after fallible preparation.
pub(crate) trait HostWorkspaceSink {
    type Prepared;
    type Error: From<pl_agent_tool::DefinitionError> + From<ThreadAssemblyError>;
    fn prepare(
        &mut self,
        definition: &ToolDefinition,
        metadata: HostToolMetadata,
    ) -> Result<Self::Prepared, Self::Error>;
    fn attach<T>(&mut self, prepared: Self::Prepared, author: T)
    where
        T: Tool<
                Input = OpaquePayload,
                Context = WorkspaceInvocation,
                Output = ToolOutput,
                Error = ToolError,
            >;
}

/// Resolves the physical file and command backends and selects enabled families.
/// An existing manager is reused only for the identical physical binding.
pub(crate) fn workspace<S: HostWorkspaceSink>(
    sink: &mut S,
    binding: StudioCommandBinding,
    store: &FileResourceStore,
    host_scratch: PathBuf,
    capabilities: &pl_tool::workspace::ToolCapabilityConfig,
    existing: Option<CommandProcesses>,
) -> Result<WorkspaceResources, S::Error> {
    let StudioCommandBinding {
        commands: backend,
        workspace,
        access,
    } = binding;
    let files = Arc::new(backend.binding().files().with_workspace(workspace.clone()));
    let processes = if capabilities.exec {
        let exec_definition = pl_tool::thread_catalog::ThreadBuiltin::Exec.declaration();
        let stdin_definition = pl_tool::thread_catalog::ThreadBuiltin::WriteStdin.declaration();
        let mut metadata = HostToolMetadata::plain();
        metadata.presentation = Some("builtin.exec@2");
        let exec = sink.prepare(&exec_definition, metadata)?;
        let mut metadata = HostToolMetadata::plain();
        metadata.presentation = Some("builtin.write_stdin@1");
        let stdin = sink.prepare(&stdin_definition, metadata)?;
        let processes = match existing {
            Some(existing) if existing.backend().is_same_binding(&backend) => existing,
            Some(_) => {
                return Err(ThreadAssemblyError::Identity(
                    "physical execution binding changed; reactivate this Thread".into(),
                )
                .into());
            }
            None => Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
                backend,
            ))),
        };
        let archive = store.command_archive(files.clone(), host_scratch);
        sink.attach(
            exec,
            pl_tool::exec::ThreadExecTool::from_process_manager(
                processes.clone(),
                Arc::new(archive),
                access,
                exec_definition,
            ),
        );
        sink.attach(
            stdin,
            pl_tool::exec::ThreadWriteStdinTool::new(processes.clone(), stdin_definition),
        );
        Some(processes)
    } else {
        existing
    };
    if capabilities.workspace_files {
        for &kind in pl_tool::workspace_file::WorkspaceMutationKind::all() {
            use pl_tool::workspace_file::WorkspaceMutationKind as Kind;
            let definition = kind.definition();
            let mut metadata = HostToolMetadata::workspace(workspace.authorization());
            metadata.presentation = Some(match kind {
                Kind::CreateDirectory => "builtin.create_directory@1",
                Kind::Delete => "builtin.delete_path@1",
                Kind::Copy => "builtin.copy_path@1",
                Kind::Move => "builtin.move_path@1",
            });
            let prepared = sink.prepare(&definition, metadata)?;
            sink.attach(
                prepared,
                pl_tool::workspace_file::WorkspaceMutationTool::new(
                    kind,
                    definition,
                    files.clone(),
                    workspace.clone(),
                ),
            );
        }
        for &kind in pl_tool::workspace_file::WorkspaceFileToolKind::all() {
            let definition = kind.definition();
            let mut metadata = HostToolMetadata::workspace(workspace.authorization());
            metadata.presentation = Some("builtin.apply_patch@1");
            metadata.scheduling = HostScheduling::ForegroundCoexisting;
            let prepared = sink.prepare(&definition, metadata)?;
            sink.attach(
                prepared,
                pl_tool::workspace_file::ThreadWorkspaceFileTool::new(
                    kind,
                    files.clone(),
                    workspace.clone(),
                    definition,
                ),
            );
        }
        let adapter = prepare_native_tool::<
            pl_tool::workspace_file::ThreadStatPathTool<
                pl_tool::workspace_file::ExecutorWorkspaceFileBackend,
            >,
        >()?;
        let mut metadata = HostToolMetadata::workspace(workspace.authorization());
        metadata.presentation = Some("builtin.stat_path@1");
        let prepared = sink.prepare(adapter.definition(), metadata)?;
        sink.attach(
            prepared,
            adapter.attach(pl_tool::workspace_file::ThreadStatPathTool::new(
                files.clone(),
            )),
        );
        let adapter = prepare_native_tool::<
            pl_tool::workspace_file::ThreadWriteFileTool<
                pl_tool::workspace_file::ExecutorWorkspaceFileBackend,
            >,
        >()?;
        let mut metadata = HostToolMetadata::workspace(workspace.authorization());
        metadata.presentation = Some("builtin.write_file@1");
        metadata.scheduling = HostScheduling::ForegroundCoexisting;
        let prepared = sink.prepare(adapter.definition(), metadata)?;
        sink.attach(
            prepared,
            adapter.attach(pl_tool::workspace_file::ThreadWriteFileTool::new(
                files.clone(),
                workspace,
            )),
        );
    }
    Ok(WorkspaceResources {
        commands: processes,
        files,
    })
}

pub(crate) fn git<S, B, P>(
    sink: &mut S,
    enabled: bool,
    binding: StudioGitBinding<B, P>,
) -> Result<(), S::Error>
where
    S: HostWorkspaceSink,
    B: pl_tool::execution::ExecutionBackend + 'static,
    B::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
    P: pl_tool::git::GitCredentialProvider + 'static,
{
    if !enabled {
        return Ok(());
    }
    for kind in binding.kinds {
        let read = kind.effect() == pl_tool::approval::ToolEffect::Read;
        let mut metadata = HostToolMetadata::workspace(binding.authorization.clone());
        metadata.policy = if read {
            ToolCallPolicy::DirectAndProgrammatic
        } else {
            ToolCallPolicy::DirectOnly
        };
        metadata.nested = Some(read);
        let definition = kind.definition();
        let prepared = sink.prepare(&definition, metadata)?;
        sink.attach(
            prepared,
            pl_tool::git::GitTool::new(
                kind,
                binding.config.clone(),
                binding.backend.clone(),
                binding.credentials.clone(),
                definition,
            ),
        );
    }
    Ok(())
}

pub(crate) fn skills<S: HostWorkspaceSink>(
    sink: &mut S,
    enabled: bool,
    sources: pl_tool::skill::SkillDiscoverySources,
) -> Result<(), S::Error> {
    if !enabled {
        return Ok(());
    }
    for kind in [
        pl_tool::skill::ThreadSkillKind::List,
        pl_tool::skill::ThreadSkillKind::View,
    ] {
        let definition = kind.declaration();
        let mut metadata = HostToolMetadata::workspace(sources.authorization());
        metadata.domain = HostToolDomain::Skill;
        metadata.native_skill_view_effect = matches!(kind, pl_tool::skill::ThreadSkillKind::View);
        let prepared = sink.prepare(&definition, metadata)?;
        sink.attach(
            prepared,
            pl_tool::skill::ThreadSkillTool::new(sources.clone(), kind, definition),
        );
    }
    Ok(())
}

/// The host must supply actual locality; remote discovery does not imply a local writer.
pub(crate) fn local_skill_management<S: HostWorkspaceSink>(
    sink: &mut S,
    enabled: bool,
    local: bool,
    catalog: Arc<pl_tool::skill::FrozenSkillCatalog>,
    workspace: pl_tool::workspace::ToolWorkspace,
) -> Result<(), S::Error> {
    if !enabled || !local {
        return Ok(());
    }
    let adapter = prepare_native_tool::<pl_tool::skill::ThreadSkillManageTool>()?;
    let mut metadata = HostToolMetadata::workspace(workspace.authorization());
    metadata.domain = HostToolDomain::Skill;
    metadata.json_input = HostJsonInput::Value;
    metadata.scheduling = HostScheduling::Foreground;
    let prepared = sink.prepare(adapter.definition(), metadata)?;
    sink.attach(
        prepared,
        adapter.attach(pl_tool::skill::ThreadSkillManageTool::new(
            catalog, workspace,
        )),
    );
    Ok(())
}

#[derive(Clone, Copy)]
pub(crate) enum LspReadiness {
    ReadyOnly,
    IncludePending,
}

/// Consumers without live catalog replacement retain query entries while the
/// actual registry remains the authority for readiness and supported operations.
pub(crate) async fn lsp<S: HostWorkspaceSink>(
    sink: &mut S,
    enabled: bool,
    registry: pl_lsp::runtime::LspRuntimeRegistry,
    paths: pl_tool::lsp::LspPathBinding,
    readiness: LspReadiness,
) -> Result<(), S::Error> {
    if !enabled {
        return Ok(());
    }
    let mut kinds = vec![pl_tool::lsp::LspToolKind::Status];
    let capabilities = registry
        .capabilities_for_workspace(paths.workspace_root())
        .await;
    if matches!(readiness, LspReadiness::IncludePending)
        || capabilities.servers.iter().any(|server| server.ready)
    {
        kinds.extend([
            pl_tool::lsp::LspToolKind::Capabilities,
            pl_tool::lsp::LspToolKind::Query,
        ]);
    }
    for kind in kinds {
        let definition = kind.declaration();
        let mut metadata = HostToolMetadata::workspace(paths.workspace().authorization());
        metadata.policy = ToolCallPolicy::DirectAndProgrammatic;
        metadata.nested = Some(true);
        metadata.deferred = true;
        metadata.presentation = Some(match kind {
            pl_tool::lsp::LspToolKind::Status => "builtin.lsp_status@1",
            pl_tool::lsp::LspToolKind::Capabilities => "builtin.lsp_capabilities@1",
            pl_tool::lsp::LspToolKind::Query => "builtin.lsp_query@1",
        });
        let prepared = sink.prepare(&definition, metadata)?;
        sink.attach(
            prepared,
            pl_tool::lsp::ThreadLspTool::new(registry.clone(), paths.clone(), kind, definition),
        );
    }
    Ok(())
}
