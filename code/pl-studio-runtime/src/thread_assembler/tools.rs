//! Creation-time standard catalog; the resulting registrations belong exclusively to core Thread.
use super::{StudioThreadSpec, ThreadAssemblyError};
use crate::resource_store::FileResourceStore;
use pl_agent_tool::ToolHandle;
use pl_core::{
    context::ResourceAccess, model::ToolPresentationContract, tool::opaque::Registration,
};
use pl_tool::binding::{ToolCallPolicy, prepare_native_tool, prepare_registration};
use pl_tool::{
    exec::{CommandAccess, ThreadExecTool},
    task_control::{TaskControlKind, TaskControlTool},
    thread_catalog::ThreadBuiltin,
};
use std::sync::Arc;

/// Explicit physical command binding chosen from the current product configuration.
#[derive(Debug)]
pub struct StudioCommandBinding {
    pub commands: pl_tool::command::ExecutorCommandBackend,
    pub workspace: pl_tool::workspace::ToolWorkspace,
    pub access: CommandAccess,
}

/// Physical command controllers remain unique per Thread across catalog refreshes.
#[derive(Debug, Clone)]
pub(crate) struct StudioCommandProcesses(
    Arc<pl_tool::command::CommandProcessManager<pl_tool::command::ExecutorCommandBackend>>,
);
#[derive(Debug, Clone)]
pub(crate) struct WeakCommandProcesses(
    std::sync::Weak<
        pl_tool::command::CommandProcessManager<pl_tool::command::ExecutorCommandBackend>,
    >,
);
impl StudioCommandProcesses {
    pub(crate) fn downgrade(&self) -> WeakCommandProcesses {
        WeakCommandProcesses(Arc::downgrade(&self.0))
    }
}
impl WeakCommandProcesses {
    pub(crate) fn upgrade(&self) -> Option<StudioCommandProcesses> {
        self.0.upgrade().map(StudioCommandProcesses)
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
    /// Replaces only the standard finish registration, preserving the frozen role on refresh.
    pub(crate) fn configure_review_finish(
        &mut self,
        authority: pl_tool::finish_turn::ReviewAuthority,
    ) -> Result<(), ThreadAssemblyError> {
        if !self
            .registrations
            .iter()
            .any(|tool| tool.tool_id() == pl_tool::finish_turn::TOOL_FINISH_TURN)
        {
            return Ok(());
        }
        let definition = pl_tool::finish_turn::review_declaration();
        let registration = pl_tool::finish_turn::registration_with_review(
            prepare_registration(
                pl_tool::finish_turn::TOOL_FINISH_TURN,
                &definition,
                ToolCallPolicy::DirectOnly,
            )?,
            Some(authority),
            definition,
        );
        self.registrations
            .retain(|tool| tool.tool_id() != pl_tool::finish_turn::TOOL_FINISH_TURN);
        self.registrations.push(registration);
        Ok(())
    }
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
        let StudioWorkspaceTools {
            binding,
            store,
            host_scratch,
            capabilities,
            ..
        } = options;
        let mut registrations = Vec::new();
        let StudioCommandBinding {
            commands: backend,
            workspace,
            access,
        } = binding;
        let execution = backend.binding();
        let files = Arc::new(
            pl_tool::workspace_file::ExecutorWorkspaceFileBackend::new(
                execution.executor,
                execution.root.as_str(),
            )
            .map_err(|error| ThreadAssemblyError::Identity(error.to_string()))?
            .with_workspace(workspace.clone()),
        );
        if capabilities.exec {
            let exec_definition = ThreadBuiltin::Exec.declaration();
            let stdin_definition = ThreadBuiltin::WriteStdin.declaration();
            let exec = prepare_registration("exec", &exec_definition, ToolCallPolicy::DirectOnly)?;
            let stdin =
                prepare_registration("write_stdin", &stdin_definition, ToolCallPolicy::DirectOnly)?;
            let archive = store.command_archive(files.clone(), host_scratch);
            let processes = command_processes(&commands, backend)?;
            commands = Some(StudioCommandProcesses(processes.clone()));
            registrations.extend(
                ThreadExecTool::from_process_manager(
                    processes,
                    Arc::new(archive),
                    access,
                    exec_definition,
                )
                .registrations(exec, stdin, stdin_definition),
            );
        }
        if capabilities.workspace_files {
            for &kind in pl_tool::workspace_file::WorkspaceMutationKind::all() {
                let definition = kind.definition();
                let prepared = prepare_registration(
                    definition.name(),
                    &definition,
                    ToolCallPolicy::DirectOnly,
                )?;
                let tool = pl_tool::workspace_file::WorkspaceMutationTool::new(
                    kind,
                    definition,
                    files.clone(),
                    workspace.clone(),
                );
                registrations.push(
                    prepared
                        .attach(ToolHandle::new(tool))
                        .with_presentation_contract(ToolPresentationContract::new(
                            mutation_presentation_contract(kind),
                        ))
                        .with_authorization(workspace.authorization()),
                );
            }
            registrations.extend(file_tools(
                files,
                workspace,
                Arc::new(super::media::MediaHost(store.clone())),
            )?);
        }
        if capabilities.ask_user {
            let ask_user = prepare_native_tool::<pl_tool::ask_user::AskUserTool>()?;
            let prepared = prepare_registration(
                "request_user_input",
                ask_user.definition(),
                ToolCallPolicy::DirectOnly,
            )?;
            registrations.push(
                prepared
                    .attach(ToolHandle::new(
                        ask_user.attach(pl_tool::ask_user::AskUserTool),
                    ))
                    .with_interactions(),
            );
        }
        let definition = ThreadBuiltin::FinishTurn.declaration();
        let prepared =
            prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
        registrations.push(pl_tool::finish_turn::registration(prepared, definition));
        let todo = prepare_native_tool::<pl_tool::todo::TodoUpdateTool>()?;
        let prepared = prepare_registration(
            pl_tool::todo::TOOL_UPDATE_TODO_LIST,
            todo.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        registrations.push(
            prepared
                .attach(ToolHandle::new(todo.attach(pl_tool::todo::TodoUpdateTool)))
                .with_extension_updates(),
        );
        let discover = prepare_native_tool::<pl_tool::discovery::DiscoverTools>()?;
        let prepared = prepare_registration(
            "discover_tools",
            discover.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        registrations.push(
            prepared
                .attach(ToolHandle::new(
                    discover.attach(pl_tool::discovery::DiscoverTools),
                ))
                .with_tool_discovery(),
        );
        let list_tasks = prepare_native_tool::<pl_tool::task_control::ListTasksTool>()?;
        let prepared = prepare_registration(
            "list_tool_tasks",
            list_tasks.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        registrations.push(prepared.attach(ToolHandle::new(
            list_tasks.attach(pl_tool::task_control::ListTasksTool),
        )));
        let sleep = prepare_native_tool::<pl_tool::session::SleepTool>()?;
        let prepared_sleep =
            prepare_registration("sleep", sleep.definition(), ToolCallPolicy::DirectOnly)?;
        registrations.push(
            prepared_sleep
                .attach(ToolHandle::new(sleep.attach(pl_tool::session::SleepTool)))
                .with_presentation_contract(ToolPresentationContract::new("builtin.sleep@1")),
        );
        for kind in [
            TaskControlKind::Wait,
            TaskControlKind::Query,
            TaskControlKind::Cancel,
        ] {
            let definition = ThreadBuiltin::Task(kind).declaration();
            let prepared =
                prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
            registrations.push(TaskControlTool::new(kind, definition).registration(prepared));
        }
        for kind in pl_tool::session_note::SessionNoteToolKind::all() {
            let definition = ThreadBuiltin::Note(*kind).declaration();
            let prepared =
                prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
            registrations.push(pl_tool::session_note::registration(
                *kind, prepared, definition,
            ));
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
    ) -> Result<Self, ThreadAssemblyError>
    where
        B::Error: Into<Box<dyn std::error::Error + Send + Sync>>,
    {
        if !self.capabilities.git {
            return Ok(self);
        }
        for kind in binding.kinds {
            let policy = if kind.effect() == pl_tool::approval::ToolEffect::Read {
                ToolCallPolicy::DirectAndProgrammatic
            } else {
                ToolCallPolicy::DirectOnly
            };
            let definition = kind.definition();
            let declaration = prepare_registration(definition.name(), &definition, policy)?;
            let tool = pl_tool::git::GitTool::new(
                kind,
                binding.config.clone(),
                binding.backend.clone(),
                binding.credentials.clone(),
                definition,
            );
            self.registrations
                .push(tool.registration(declaration, binding.authorization.clone()));
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
        let adapter = prepare_native_tool::<pl_tool::search::ThreadWebSearchTool>()?;
        let declaration = prepare_registration(
            adapter.definition().name(),
            adapter.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        self.registrations.push(
            declaration
                .attach(ToolHandle::new(adapter.attach(
                    pl_tool::search::ThreadWebSearchTool::new(client, options),
                )))
                .with_presentation_contract(ToolPresentationContract::new("builtin.web_search@1")),
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
        let adapter =
            prepare_native_tool::<pl_tool::image_generation::ThreadImageGenerationTool<H>>()?;
        let declaration = prepare_registration(
            adapter.definition().name(),
            adapter.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        let client =
            pl_model::protocol::images::ImagesClient::new(backend.endpoint).map_err(|error| {
                ThreadAssemblyError::Resource {
                    operation: "bind image generation",
                    source: Box::new(error),
                }
            })?;
        self.registrations
            .push(declaration.attach(ToolHandle::new(adapter.attach(
                pl_tool::image_generation::ThreadImageGenerationTool::new(
                    client,
                    backend.model,
                    backend.account_id.to_string(),
                    media,
                ),
            ))));
        Ok(self)
    }

    /// Installs per-call Skill discovery over fixed workspace/configuration and Providers.
    ///
    /// # Errors
    /// Returns declaration encoding or registry errors.
    pub fn with_skills(
        mut self,
        sources: pl_tool::skill::SkillDiscoverySources,
    ) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.skills {
            return Ok(self);
        }
        for kind in [
            pl_tool::skill::ThreadSkillKind::List,
            pl_tool::skill::ThreadSkillKind::View,
        ] {
            let definition = kind.declaration();
            let declaration =
                prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
            let tool = pl_tool::skill::ThreadSkillTool::new(sources.clone(), kind, definition);
            self.registrations.push(tool.registration(declaration));
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
        let adapter = prepare_native_tool::<pl_tool::skill::ThreadSkillManageTool>()?;
        let declaration = prepare_registration(
            adapter.definition().name(),
            adapter.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        let authorization = workspace.authorization();
        self.registrations.push(
            declaration
                .attach(ToolHandle::new(adapter.attach(
                    pl_tool::skill::ThreadSkillManageTool::new(catalog, workspace),
                )))
                .foreground()
                .with_authorization(authorization),
        );
        Ok(self)
    }

    pub fn with_bot_tools(
        mut self,
        runtime: crate::bots::BotRuntime,
        workspace_id: String,
    ) -> Result<Self, ThreadAssemblyError> {
        let host = std::sync::Arc::new(crate::bots::StudioBotSessionHost { runtime });
        for kind in [
            pl_tool::bots::BotToolKind::ListBots,
            pl_tool::bots::BotToolKind::ListConversations,
            pl_tool::bots::BotToolKind::ReadMessages,
            pl_tool::bots::BotToolKind::SendMessage,
        ] {
            let definition = kind.declaration();
            let declaration =
                prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
            let tool = pl_tool::bots::ThreadBotTool::new(
                host.clone(),
                kind,
                workspace_id.clone(),
                definition,
            );
            self.registrations.push(tool.registration(declaration));
        }
        Ok(self)
    }

    /// Binds language-service tools to the selected physical workspace without rebuilding them each Turn.
    ///
    /// # Errors
    /// Returns declaration encoding or registration errors.
    pub async fn with_lsp(
        mut self,
        registry: pl_lsp::runtime::LspRuntimeRegistry,
        paths: pl_tool::lsp::LspPathBinding,
    ) -> Result<Self, ThreadAssemblyError> {
        if !self.capabilities.lsp {
            return Ok(self);
        }
        let mut kinds = vec![pl_tool::lsp::LspToolKind::Status];
        let capabilities = registry
            .capabilities_for_workspace(paths.workspace_root())
            .await;
        if capabilities.servers.iter().any(|server| server.ready) {
            kinds.extend([
                pl_tool::lsp::LspToolKind::Capabilities,
                pl_tool::lsp::LspToolKind::Query,
            ]);
        }
        for kind in kinds {
            let definition = kind.declaration();
            let declaration = prepare_registration(
                definition.name(),
                &definition,
                ToolCallPolicy::DirectAndProgrammatic,
            )?;
            let tool =
                pl_tool::lsp::ThreadLspTool::new(registry.clone(), paths.clone(), kind, definition);
            self.registrations.push(tool.registration(declaration));
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

fn mutation_presentation_contract(
    kind: pl_tool::workspace_file::WorkspaceMutationKind,
) -> &'static str {
    match kind {
        pl_tool::workspace_file::WorkspaceMutationKind::CreateDirectory => {
            "builtin.create_directory@1"
        }
        pl_tool::workspace_file::WorkspaceMutationKind::Delete => "builtin.delete_path@1",
        pl_tool::workspace_file::WorkspaceMutationKind::Copy => "builtin.copy_path@1",
        pl_tool::workspace_file::WorkspaceMutationKind::Move => "builtin.move_path@1",
    }
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
            let definition = kind.definition();
            let prepared =
                prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
            Ok(
                ThreadWorkspaceFileTool::new(kind, backend.clone(), workspace.clone(), definition)
                    .registration(prepared),
            )
        })
        .collect::<Result<Vec<_>, ThreadAssemblyError>>()?;
    let view_image =
        prepare_native_tool::<pl_tool::image::ThreadViewImageTool<B, super::media::MediaHost>>()?;
    let view_registration = prepare_registration(
        "view_image",
        view_image.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    let show_files = prepare_native_tool::<
        pl_tool::file_display::ThreadShowFilesTool<B, super::media::MediaHost>,
    >()?;
    let show_registration = prepare_registration(
        "show_files",
        show_files.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    let stat = prepare_native_tool::<pl_tool::workspace_file::ThreadStatPathTool<B>>()?;
    let stat_registration =
        prepare_registration("stat_path", stat.definition(), ToolCallPolicy::DirectOnly)?;
    let write = prepare_native_tool::<pl_tool::workspace_file::ThreadWriteFileTool<B>>()?;
    let write_registration =
        prepare_registration("write_file", write.definition(), ToolCallPolicy::DirectOnly)?;
    tools.push(
        view_registration
            .attach(ToolHandle::new(view_image.attach(
                pl_tool::image::ThreadViewImageTool::new(backend.clone(), media.clone()),
            )))
            .with_presentation_contract(ToolPresentationContract::new("builtin.view_image@1"))
            .with_authorization(workspace.authorization()),
    );
    tools.push(
        show_registration
            .attach(ToolHandle::new(show_files.attach(
                pl_tool::file_display::ThreadShowFilesTool::new(backend.clone(), media),
            )))
            .with_presentation_contract(ToolPresentationContract::new(
                pl_tool::file_display::FILE_DISPLAY_PRESENTATION,
            ))
            .with_authorization(workspace.authorization())
            .foreground_coexisting(),
    );
    tools.push(
        stat_registration
            .attach(ToolHandle::new(stat.attach(
                pl_tool::workspace_file::ThreadStatPathTool::new(backend.clone()),
            )))
            .with_presentation_contract(ToolPresentationContract::new("builtin.stat_path@1"))
            .with_authorization(workspace.authorization()),
    );
    let authorization = workspace.authorization();
    tools.push(
        write_registration
            .attach(ToolHandle::new(write.attach(
                pl_tool::workspace_file::ThreadWriteFileTool::new(backend, workspace),
            )))
            .with_presentation_contract(ToolPresentationContract::new("builtin.write_file@1"))
            .foreground_coexisting()
            .with_authorization(authorization),
    );
    Ok(tools)
}

fn command_processes(
    existing: &Option<StudioCommandProcesses>,
    backend: pl_tool::command::ExecutorCommandBackend,
) -> Result<
    Arc<pl_tool::command::CommandProcessManager<pl_tool::command::ExecutorCommandBackend>>,
    ThreadAssemblyError,
> {
    match existing {
        Some(existing) if existing.0.backend().is_same_binding(&backend) => Ok(existing.0.clone()),
        Some(_) => Err(ThreadAssemblyError::Identity(
            "physical execution binding changed; reactivate this Thread".into(),
        )),
        None => Ok(Arc::new(pl_tool::command::CommandProcessManager::new(
            Arc::new(backend),
        ))),
    }
}
