//! Creation-time standard catalog; the resulting registrations belong exclusively to core Thread.
use super::{StudioThreadSpec, ThreadAssemblyError};
use crate::resource_store::FileResourceStore;
use pl_core::{
    context::{OpaquePayload, ResourceAccess},
    tool::opaque::Registration,
};
use pl_tool::{
    exec::{CommandAccess, ThreadExecTool},
    task_control::{TaskControlKind, TaskControlTool},
    thread_catalog::ThreadBuiltin,
};
use std::sync::Arc;

/// Explicit physical command binding chosen from the current product configuration.
#[derive(Debug)]
pub enum StudioCommandBinding {
    Local {
        file_root: pl_tool::workspace_file::LocalWorkspaceRoot,
        file_creates: pl_tool::workspace_file::LocalFileCreateOwner,
        workspace: pl_tool::workspace::ToolWorkspace,
        environment: pl_tool::environment::ExecutionEnvironment,
        child_environment: std::collections::BTreeMap<String, String>,
        access: CommandAccess,
    },
    Remote {
        host: pl_tool::remote::RemoteWorkspaceHost,
        workspace: pl_tool::workspace::ToolWorkspace,
    },
}

/// Physical command controllers remain unique per Thread across catalog refreshes.
#[derive(Debug, Clone)]
pub(crate) enum StudioCommandProcesses {
    Local(Arc<pl_tool::command::CommandProcessManager<pl_tool::command::LocalCommandBackend>>),
    Remote(Arc<pl_tool::command::CommandProcessManager<pl_tool::remote::RemoteCommandBackend>>),
}
#[derive(Debug, Clone)]
pub(crate) enum WeakCommandProcesses {
    Local(
        std::sync::Weak<
            pl_tool::command::CommandProcessManager<pl_tool::command::LocalCommandBackend>,
        >,
    ),
    Remote(
        std::sync::Weak<
            pl_tool::command::CommandProcessManager<pl_tool::remote::RemoteCommandBackend>,
        >,
    ),
}
impl StudioCommandProcesses {
    pub(crate) fn downgrade(&self) -> WeakCommandProcesses {
        match self {
            Self::Local(manager) => WeakCommandProcesses::Local(Arc::downgrade(manager)),
            Self::Remote(manager) => WeakCommandProcesses::Remote(Arc::downgrade(manager)),
        }
    }
}
impl WeakCommandProcesses {
    pub(crate) fn upgrade(&self) -> Option<StudioCommandProcesses> {
        match self {
            Self::Local(manager) => manager.upgrade().map(StudioCommandProcesses::Local),
            Self::Remote(manager) => manager.upgrade().map(StudioCommandProcesses::Remote),
        }
    }
}

/// Explicit Git resources and allowed operation kinds selected by the product host.
#[derive(Debug)]
pub struct StudioGitBinding<B, P> {
    pub config: pl_tool::git::GitWorkspaceConfig,
    pub backend: Arc<B>,
    pub credentials: Arc<P>,
    pub kinds: Vec<pl_tool::git::GitToolKind>,
    pub authorization: pl_core::tool::opaque::ToolAuthorization,
}

/// Physical resources and capability policy resolved from one Studio configuration snapshot.
#[derive(Debug)]
pub struct StudioWorkspaceTools {
    pub binding: StudioCommandBinding,
    pub store: FileResourceStore,
    pub helper_source: crate::worker_assets::RemoteHelperSource,
    /// Host-owned transfer scratch for this Thread. Never exposed as model-writable workspace.
    pub host_scratch: std::path::PathBuf,
    pub capabilities: pl_tool::workspace::ToolCapabilityConfig,
}

/// Ready-to-transfer instances and their matching resource reader.
#[derive(Debug)]
pub struct StudioThreadTools {
    pub(super) registrations: Vec<Registration>,
    pub(crate) command_processes: Option<StudioCommandProcesses>,
    pub(crate) approval_policies:
        std::collections::BTreeMap<String, pl_core::tool::execution_policy::ExecutionPolicyHandle>,
    pub(super) store: FileResourceStore,
    pub(super) capabilities: pl_tool::workspace::ToolCapabilityConfig,
}

impl StudioThreadTools {
    /// Transfers an explicitly selected catalog, without constructing standard capabilities.
    /// Optional capability builders remain disabled for this restricted catalog.
    pub fn selected(store: FileResourceStore, registrations: Vec<Registration>) -> Self {
        Self {
            command_processes: None,
            approval_policies: Default::default(),
            store,
            registrations,
            capabilities: pl_tool::workspace::ToolCapabilityConfig {
                exec: false,
                workspace_files: false,
                skills: false,
                mcp: false,
                lsp: false,
                ask_user: false,
                git: false,
            },
        }
    }

    /// Constructs fresh standard tools for one Thread, using shared storage only for immutable bytes.
    ///
    /// # Errors
    /// Returns declaration encoding or registration failure before publishing a Thread.
    pub async fn standard(options: StudioWorkspaceTools) -> Result<Self, ThreadAssemblyError> {
        Self::with_command_processes(options, None).await
    }

    pub(crate) async fn with_command_processes(
        options: StudioWorkspaceTools,
        mut commands: Option<StudioCommandProcesses>,
    ) -> Result<Self, ThreadAssemblyError> {
        // The local worker exists only on Linux; other platforms drop the field
        // via `..` so it never becomes an unused binding.
        #[cfg(target_os = "linux")]
        let helper_source = options.helper_source.clone();
        let StudioWorkspaceTools {
            binding,
            store,
            host_scratch,
            capabilities,
            ..
        } = options;
        let mut registrations = Vec::new();
        match binding {
            StudioCommandBinding::Local {
                file_root,
                file_creates,
                workspace,
                environment,
                child_environment,
                access,
            } => {
                if capabilities.exec {
                    let processes = match &commands {
                        Some(StudioCommandProcesses::Local(processes)) => processes.clone(),
                        Some(StudioCommandProcesses::Remote(_)) => {
                            return Err(ThreadAssemblyError::Identity(
                                "physical command binding changed; reactivate this Thread".into(),
                            ));
                        }
                        None => {
                            let backend = pl_tool::command::LocalCommandBackend::new(
                                workspace.root().to_path_buf(),
                            )
                            .with_execution_environment(environment)
                            .with_child_environment(child_environment);
                            #[cfg(target_os = "linux")]
                            let backend = backend.with_worker_executable(
                                crate::worker_assets::local_worker(helper_source).await?,
                            );
                            Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
                                backend,
                            )))
                        }
                    };
                    commands = Some(StudioCommandProcesses::Local(processes.clone()));
                    registrations.extend(
                        ThreadExecTool::from_process_manager(
                            processes,
                            Arc::new(store.local_command_archive()),
                            access,
                        )
                        .registrations(
                            declaration(ThreadBuiltin::Exec)?,
                            declaration(ThreadBuiltin::WriteStdin)?,
                        )?,
                    );
                }
                if capabilities.workspace_files {
                    let files = Arc::new(
                        pl_tool::workspace_file::LocalWorkspaceFileBackend::confined_root(
                            workspace.clone(),
                            file_root,
                        )
                        .await?
                        .with_create_owner(file_creates),
                    );
                    registrations.extend(local_mutation_tools(workspace.clone())?);
                    registrations.extend(file_tools(
                        files,
                        workspace,
                        Arc::new(super::media::MediaHost(store.clone())),
                    )?);
                }
            }
            StudioCommandBinding::Remote { host, workspace } => {
                if capabilities.exec {
                    let archive = store
                        .remote_command_archive(Arc::new(host.files.clone()), host_scratch.clone());
                    let processes = match &commands {
                        Some(StudioCommandProcesses::Remote(processes)) => processes.clone(),
                        Some(StudioCommandProcesses::Local(_)) => {
                            return Err(ThreadAssemblyError::Identity(
                                "physical command binding changed; reactivate this Thread".into(),
                            ));
                        }
                        None => Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
                            host.commands.clone(),
                        ))),
                    };
                    commands = Some(StudioCommandProcesses::Remote(processes.clone()));
                    registrations.extend(
                        ThreadExecTool::from_process_manager(
                            processes,
                            Arc::new(archive),
                            CommandAccess::WorkspaceOnly,
                        )
                        .registrations(
                            declaration(ThreadBuiltin::Exec)?,
                            declaration(ThreadBuiltin::WriteStdin)?,
                        )?,
                    );
                }
                if capabilities.workspace_files {
                    for &kind in pl_tool::remote::RemoteMutationKind::all() {
                        let tool = pl_tool::remote::RemoteWorkspaceMutationTool::new(
                            kind,
                            Arc::new(host.files.clone()),
                            workspace.clone(),
                        );
                        let spec = tool.declaration();
                        registrations.push(
                            Registration::new(
                                spec.name().into(),
                                pl_model::runtime::thread_tool_declaration(&spec)?,
                                tool,
                            )?
                            .with_authorization(workspace.authorization()),
                        );
                    }
                    let files = pl_tool::workspace_file::WorkspacePolicyBackend::new(
                        Arc::new(host.files.clone()),
                        workspace.clone(),
                    );
                    registrations.extend(file_tools(
                        Arc::new(files),
                        workspace,
                        Arc::new(super::media::MediaHost(store.clone())),
                    )?);
                }
            }
        }
        if capabilities.ask_user {
            registrations.push(pl_tool::ask_user::registration(declaration(
                ThreadBuiltin::AskUser,
            )?)?);
        }
        registrations.extend([
            pl_tool::finish_turn::registration(declaration(ThreadBuiltin::FinishTurn)?)?,
            pl_tool::todo::registration(declaration(ThreadBuiltin::Todo)?)?,
            pl_tool::discovery::registration(declaration(ThreadBuiltin::Discover)?)?,
        ]);
        registrations.push(
            pl_tool::task_control::ListTasksTool
                .registration(declaration(ThreadBuiltin::ListTasks)?)?,
        );
        registrations.push(Registration::new(
            "sleep".into(),
            declaration(ThreadBuiltin::Sleep)?,
            pl_tool::session::SleepTool,
        )?);
        for kind in [
            TaskControlKind::Wait,
            TaskControlKind::Query,
            TaskControlKind::Cancel,
        ] {
            registrations.push(
                TaskControlTool::new(kind).registration(declaration(ThreadBuiltin::Task(kind))?)?,
            );
        }
        for kind in pl_tool::session_note::SessionNoteToolKind::all() {
            registrations.push(pl_tool::session_note::registration(
                *kind,
                declaration(ThreadBuiltin::Note(*kind))?,
            )?);
        }
        Ok(Self {
            command_processes: commands,
            approval_policies: Default::default(),
            registrations,
            store,
            capabilities,
        })
    }

    /// Installs fresh Git tool instances over shared execution and credential services.
    ///
    /// # Errors
    /// Returns model declaration or registry errors.
    pub fn with_git<
        B: pl_tool::execution::ExecutionBackend + 'static,
        P: pl_tool::git::GitCredentialProvider + 'static,
    >(
        mut self,
        binding: StudioGitBinding<B, P>,
    ) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.git {
            return Ok(self);
        }
        for kind in binding.kinds {
            let declaration = pl_model::runtime::thread_tool_declaration(&kind.to_spec())?;
            let tool = pl_tool::git::GitTool::new(
                kind,
                binding.config.clone(),
                binding.backend.clone(),
                binding.credentials.clone(),
            );
            self.registrations
                .push(tool.registration(declaration, binding.authorization.clone())?);
        }
        Ok(self)
    }

    /// Installs independent search with explicit service parameters and core-provided frozen context.
    ///
    /// # Errors
    /// Returns model declaration encoding or registry failures.
    pub fn with_web_search(
        mut self,
        client: pl_tool::search::WebSearchClient,
        options: pl_tool::search::ThreadSearchOptions,
    ) -> Result<Self, ThreadAssemblyError> {
        let declaration = pl_model::runtime::thread_tool_declaration(
            &pl_tool::search::ThreadWebSearchTool::declaration(),
        )?;
        self.registrations.push(
            pl_tool::search::ThreadWebSearchTool::new(client, options).registration(declaration)?,
        );
        Ok(self)
    }

    /// Installs independent image generation over the selected account backend and media host.
    ///
    /// The caller resolves the backend from the current directory observation, so an absent
    /// service capability, online image model or credential never reaches this builder.
    ///
    /// # Errors
    /// Returns service construction, declaration encoding or registry errors.
    pub fn with_image_generation<H: pl_tool::media::ToolMediaHost + 'static>(
        mut self,
        backend: pl_model::config::ImageGenerationBackend,
        media: std::sync::Arc<H>,
    ) -> Result<Self, ThreadAssemblyError> {
        let client =
            pl_model::protocol::images::ImagesClient::new(backend.endpoint).map_err(|error| {
                ThreadAssemblyError::Resource {
                    operation: "bind image generation",
                    source: Box::new(error),
                }
            })?;
        let declaration = pl_model::runtime::thread_tool_declaration(
            &pl_tool::image_generation::ThreadImageGenerationTool::<H>::declaration(),
        )?;
        self.registrations.push(
            pl_tool::image_generation::ThreadImageGenerationTool::new(
                client,
                backend.model,
                backend.account_id.to_string(),
                media,
            )
            .registration(declaration)?,
        );
        Ok(self)
    }

    /// Installs skill discovery and read snapshots over a frozen provider directory.
    ///
    /// # Errors
    /// Returns declaration encoding or registry errors.
    pub fn with_skills(
        mut self,
        catalog: Arc<pl_tool::skill::FrozenSkillCatalog>,
    ) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.skills {
            return Ok(self);
        }
        for kind in [
            pl_tool::skill::ThreadSkillKind::List,
            pl_tool::skill::ThreadSkillKind::View,
        ] {
            let declaration = pl_model::runtime::thread_tool_declaration(&kind.declaration())?;
            let tool = pl_tool::skill::ThreadSkillTool::new(catalog.clone(), kind);
            self.registrations.push(tool.registration(declaration)?);
        }
        Ok(self)
    }

    /// Adds project Skill mutations only for an explicitly local writable binding.
    ///
    /// # Errors
    /// Returns declaration or tool registration failures.
    pub fn with_local_skill_management(
        mut self,
        catalog: Arc<pl_tool::skill::FrozenSkillCatalog>,
        workspace: pl_tool::workspace::ToolWorkspace,
    ) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.skills {
            return Ok(self);
        }
        let declaration = pl_model::runtime::thread_tool_declaration(
            &pl_tool::skill::ThreadSkillManageTool::declaration(),
        )?;
        self.registrations.push(
            pl_tool::skill::ThreadSkillManageTool::new(catalog, workspace)
                .registration(declaration)?,
        );
        Ok(self)
    }

    pub fn with_bot_tools(
        mut self,
        runtime: crate::bots::BotRuntime,
        project_id: String,
    ) -> Result<Self, ThreadAssemblyError> {
        let host = std::sync::Arc::new(crate::bots::StudioBotSessionHost { runtime });
        for kind in [
            pl_tool::bots::BotToolKind::ListBots,
            pl_tool::bots::BotToolKind::ListConversations,
            pl_tool::bots::BotToolKind::ReadMessages,
            pl_tool::bots::BotToolKind::SendMessage,
        ] {
            let declaration = pl_model::runtime::thread_tool_declaration(&kind.declaration())?;
            let tool = pl_tool::bots::ThreadBotTool::new(host.clone(), kind, project_id.clone());
            self.registrations.push(tool.registration(declaration)?);
        }
        Ok(self)
    }

    /// Binds language-service tools to the selected physical workspace without rebuilding them each Turn.
    ///
    /// # Errors
    /// Returns declaration encoding or registration errors.
    pub fn with_lsp(
        mut self,
        registry: pl_lsp::runtime::LspRuntimeRegistry,
        paths: pl_tool::lsp::LspPathBinding,
    ) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.lsp {
            return Ok(self);
        }
        for kind in [
            pl_tool::lsp::LspToolKind::Capabilities,
            pl_tool::lsp::LspToolKind::Query,
        ] {
            let declaration = pl_model::runtime::thread_tool_declaration(&kind.declaration())?;
            let tool = pl_tool::lsp::ThreadLspTool::new(registry.clone(), paths.clone(), kind);
            self.registrations.push(tool.registration(declaration)?);
        }
        Ok(self)
    }

    /// Adds host-selected file, MCP, LSP or product tools before transferring the complete catalog.
    pub fn with_tools(mut self, tools: impl IntoIterator<Item = Registration>) -> Self {
        self.registrations.extend(tools);
        self
    }

    pub(crate) fn into_registrations(self) -> Vec<Registration> {
        self.registrations
    }

    /// Transfers this catalog and reader into the one assembly specification.
    pub fn install(self, mut spec: StudioThreadSpec) -> StudioThreadSpec {
        spec.tools.extend(self.registrations);
        spec.resources = ResourceAccess::new(self.store);
        spec
    }
}

fn declaration(tool: ThreadBuiltin) -> Result<OpaquePayload, ThreadAssemblyError> {
    Ok(pl_model::runtime::thread_tool_declaration(
        &tool.declaration(),
    )?)
}

fn local_mutation_tools(
    workspace: pl_tool::workspace::ToolWorkspace,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    use pl_tool::file::{CopyPathTool, CreateDirectoryTool, DeletePathTool, MovePathTool};
    let authority = workspace.authorization();
    Ok(vec![
        Registration::new(
            "create_directory".into(),
            declaration(ThreadBuiltin::CreateDirectory)?,
            CreateDirectoryTool::new(workspace.clone()),
        )?
        .with_authorization(authority.clone()),
        Registration::new(
            "delete_path".into(),
            declaration(ThreadBuiltin::DeletePath)?,
            DeletePathTool::new(workspace.clone()),
        )?
        .with_authorization(authority.clone()),
        Registration::new(
            "copy_path".into(),
            declaration(ThreadBuiltin::CopyPath)?,
            CopyPathTool::new(workspace.clone()),
        )?
        .with_authorization(authority.clone()),
        Registration::new(
            "move_path".into(),
            declaration(ThreadBuiltin::MovePath)?,
            MovePathTool::new(workspace),
        )?
        .with_authorization(authority),
    ])
}

fn file_tools<B: pl_tool::workspace_file::WorkspaceFileBackend + 'static>(
    backend: Arc<B>,
    workspace: pl_tool::workspace::ToolWorkspace,
    media: Arc<super::media::MediaHost>,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    use pl_tool::workspace_file::{ThreadWorkspaceFileTool, WorkspaceFileToolKind};
    let mut tools = WorkspaceFileToolKind::all()
        .iter()
        .copied()
        .map(|kind| {
            Ok(
                ThreadWorkspaceFileTool::new(kind, backend.clone(), workspace.clone())
                    .registration(declaration(ThreadBuiltin::File(kind))?)?,
            )
        })
        .collect::<Result<Vec<_>, ThreadAssemblyError>>()?;
    tools.push(
        pl_tool::image::ThreadViewImageTool::new(backend.clone(), workspace.authorization(), media)
            .registration(declaration(ThreadBuiltin::ViewImage)?)?,
    );
    tools.push(
        pl_tool::image_card::ThreadShowImageTool::new()
            .registration(declaration(ThreadBuiltin::ShowImage)?)?,
    );
    tools.push(
        pl_tool::workspace_file::ThreadStatPathTool::new(
            backend.clone(),
            workspace.authorization(),
        )
        .registration(declaration(ThreadBuiltin::StatPath)?)?,
    );
    tools.push(
        pl_tool::workspace_file::ThreadWriteFileTool::new(backend, workspace)
            .registration(declaration(ThreadBuiltin::WriteFile)?)?,
    );
    Ok(tools)
}

impl super::StudioThreadAssembler {
    /// Builds the standard catalog and transfers it through the same root/child/recovery owner path.
    ///
    /// # Errors
    /// Returns backend setup, declaration, history or resource-assembly failure.
    pub async fn assemble_standard(
        &self,
        mut spec: StudioThreadSpec,
        tools: StudioWorkspaceTools,
    ) -> Result<pl_core::thread::ThreadHandle, ThreadAssemblyError> {
        spec.agent_controls = if spec.parent_id.is_none() {
            super::AgentControlExposure::Enabled
        } else {
            super::AgentControlExposure::Disabled
        };
        let tools = StudioThreadTools::standard(tools).await?;
        self.assemble(tools.install(spec)).await
    }
}
