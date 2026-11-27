//! Creation-time standard catalog; the resulting registrations belong exclusively to core Thread.
use super::host_workspace_tools::{self, HostScheduling, HostToolMetadata, HostWorkspaceSink};
use super::{StudioThreadSpec, ThreadAssemblyError};
use crate::resource_store::FileResourceStore;
use pl_agent_tool::ToolHandle;
use pl_core::{
    context::ResourceAccess, model::ToolPresentationContract, tool::opaque::Registration,
};
use pl_tool::binding::{ToolCallPolicy, prepare_native_tool, prepare_registration};
use pl_tool::{exec::CommandAccess, thread_catalog::ThreadBuiltin};
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
    pub(crate) async fn close(&self) {
        self.0.close().await;
    }

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
    /// Host-owned transfer scratch for this Thread. Never exposed as model-writable workspace.
    pub host_scratch: std::path::PathBuf,
    pub capabilities: pl_tool::workspace::ToolCapabilityConfig,
}

/// Ready-to-transfer instances and their matching resource reader.
#[derive(Debug)]
pub struct StudioThreadTools {
    pub(crate) registrations: Vec<Registration>,
    pub(crate) command_processes: Option<StudioCommandProcesses>,
    pub(crate) approval_policies:
        std::collections::BTreeMap<String, pl_core::tool::execution_policy::ExecutionPolicyHandle>,
    pub(crate) store: FileResourceStore,
    pub(crate) capabilities: pl_tool::workspace::ToolCapabilityConfig,
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
    #[cfg(all(test, target_os = "linux"))]
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
        let workspace = binding.workspace.clone();
        let resources = host_workspace_tools::workspace(
            &mut NativeWorkspaceSink(&mut registrations),
            binding,
            &store,
            host_scratch,
            &capabilities,
            commands.map(|commands| commands.0),
        )?;
        commands = resources.commands.map(StudioCommandProcesses);
        if capabilities.workspace_files {
            registrations.extend(media_tools(
                resources.files,
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
        let todo = prepare_native_tool::<pl_tool::todo::TodoUpdateTool>()?.with_output_schema(
            pl_tool::todo::todo_update_tool_definition()
                .output_schema()
                .cloned()
                .expect("todo author declares its result"),
        )?;
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
        super::host_task_tools::list(&mut super::host_task_tools::NativeTaskTools(
            &mut registrations,
        ))?;
        let sleep = prepare_native_tool::<pl_tool::session::SleepTool>()?
            .with_output_schema(pl_agent_tool::typed::output_schema_for::<String>())?;
        let prepared_sleep =
            prepare_registration("sleep", sleep.definition(), ToolCallPolicy::DirectOnly)?;
        registrations.push(
            prepared_sleep
                .attach(ToolHandle::new(sleep.attach(pl_tool::session::SleepTool)))
                .top_level_only()
                .with_presentation_contract(ToolPresentationContract::new("builtin.sleep@1")),
        );
        super::host_task_tools::controls(&mut super::host_task_tools::NativeTaskTools(
            &mut registrations,
        ))?;
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
        host_workspace_tools::git(
            &mut NativeWorkspaceSink(&mut self.registrations),
            self.capabilities.git,
            binding,
        )?;
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
            prepare_native_tool::<pl_tool::image_generation::ThreadImageGenerationTool<H>>()?
                .with_output_schema(
                    pl_tool::image_generation::ThreadImageGenerationTool::<H>::declaration()
                        .output_schema()
                        .cloned()
                        .expect("image generation author declares its result"),
                )?;
        let declaration = prepare_registration(
            adapter.definition().name(),
            adapter.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        let client =
            pl_model_openai::images::ImagesClient::new(backend.endpoint).map_err(|error| {
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
        host_workspace_tools::skills(
            &mut NativeWorkspaceSink(&mut self.registrations),
            self.capabilities.skills,
            sources,
        )?;
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
        host_workspace_tools::local_skill_management(
            &mut NativeWorkspaceSink(&mut self.registrations),
            self.capabilities.skills,
            true,
            catalog,
            workspace,
        )?;
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
        host_workspace_tools::lsp(
            &mut NativeWorkspaceSink(&mut self.registrations),
            self.capabilities.lsp,
            registry,
            paths,
            host_workspace_tools::LspReadiness::ReadyOnly,
        )
        .await?;
        Ok(self)
    }

    /// Adds host-selected file, MCP, LSP or product tools before transferring the complete catalog.
    pub fn with_tools(mut self, tools: impl IntoIterator<Item = Registration>) -> Self {
        self.registrations.extend(tools);
        self
    }

    pub(crate) fn into_registrations(self) -> Vec<Registration> {
        lua_registrations(self.registrations)
    }

    /// Transfers this catalog and reader into the one assembly specification.
    pub fn install(self, mut spec: StudioThreadSpec) -> StudioThreadSpec {
        spec.tools.extend(lua_registrations(self.registrations));
        spec.resources = ResourceAccess::new(self.store);
        spec
    }
}

/// Freeze one program surface from the same registrations passed to Thread. Control tools
/// retain their top-level declarations and authority; ordinary tools become program-only.
fn lua_registrations(registrations: Vec<Registration>) -> Vec<Registration> {
    if !registrations.iter().any(Registration::permits_nesting) {
        return registrations;
    }
    let mut result = Vec::new();
    for registration in registrations {
        if registration.permits_nesting() {
            let parallel = registration.nested_parallel();
            result.push(registration.nested(parallel));
        } else {
            result.push(registration);
        }
    }
    let tool = pl_tool::lua::LuaTool::new("");
    use pl_agent_tool::Tool;
    let prepared = prepare_registration("exec", tool.definition(), ToolCallPolicy::DirectOnly)
        .expect("static Lua registration");
    result.push(
        prepared
            .attach(ToolHandle::new(tool))
            .with_nested_catalog(pl_tool::lua::project_catalog),
    );
    result
}

fn media_tools<B: pl_tool::workspace_file::WorkspaceFileBackend + 'static>(
    backend: Arc<B>,
    workspace: pl_tool::workspace::ToolWorkspace,
    media: Arc<super::media::MediaHost>,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    let mut tools = Vec::new();
    let view_image =
        prepare_native_tool::<pl_tool::image::ThreadViewImageTool<B, super::media::MediaHost>>()?
            .with_output_schema(
            pl_tool::image::thread_view_image_tool_definition()
                .output_schema()
                .cloned()
                .expect("image author declares its result"),
        )?;
    let view_registration = prepare_registration(
        "view_image",
        view_image.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    let show_files = prepare_native_tool::<
        pl_tool::file_display::ThreadShowFilesTool<B, super::media::MediaHost>,
    >()?
    .with_output_schema(
        pl_tool::file_display::thread_show_files_tool_definition()
            .output_schema()
            .cloned()
            .expect("file display author declares its result"),
    )?;
    let show_registration = prepare_registration(
        "show_files",
        show_files.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
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
    Ok(tools)
}

/// Native-only policy projection, after the shared family has selected its author.
struct NativeWorkspaceSink<'a>(&'a mut Vec<Registration>);
struct PreparedNativeWorkspace {
    registration: pl_core::tool::opaque::PreparedRegistration,
    metadata: HostToolMetadata,
}
impl HostWorkspaceSink for NativeWorkspaceSink<'_> {
    type Prepared = PreparedNativeWorkspace;
    type Error = ThreadAssemblyError;
    fn prepare(
        &mut self,
        definition: &pl_agent_tool::ToolDefinition,
        metadata: HostToolMetadata,
    ) -> Result<Self::Prepared, Self::Error> {
        let registration = prepare_registration(definition.name(), definition, metadata.policy)?;
        Ok(PreparedNativeWorkspace {
            registration,
            metadata,
        })
    }
    fn attach<T>(&mut self, prepared: Self::Prepared, author: T)
    where
        T: pl_agent_tool::Tool<
                Input = pl_core::context::OpaquePayload,
                Context = pl_tool::invocation::WorkspaceInvocation,
                Output = pl_core::tool::ToolOutput,
                Error = pl_core::tool::opaque::ToolError,
            >,
    {
        let PreparedNativeWorkspace {
            registration,
            metadata,
        } = prepared;
        let author = pl_tool::binding::NativeWorkspaceTool::new(author);
        let author = if metadata.native_skill_view_effect {
            author.with_skill_view_effect()
        } else {
            author
        };
        let mut registration = registration.attach(ToolHandle::new(author));
        if let Some(contract) = metadata.presentation {
            registration =
                registration.with_presentation_contract(ToolPresentationContract::new(contract));
        }
        if let Some(authorization) = metadata.authorization {
            registration = registration.with_authorization(authorization);
        }
        registration = match metadata.scheduling {
            HostScheduling::Default => registration,
            HostScheduling::Foreground => registration.foreground(),
            HostScheduling::ForegroundCoexisting => registration.foreground_coexisting(),
        };
        if metadata.deferred {
            registration = registration.deferred();
        }
        if let Some(parallel) = metadata.nested {
            registration = registration.nested(parallel);
        }
        if metadata.native_skill_view_effect {
            registration = registration.with_extension_updates();
        }
        self.0.push(registration);
    }
}
