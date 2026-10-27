//! Root activation uses the same physical tools as children and resumes a current-state checkpoint.
use super::{
    StudioThreadFactory,
    errors::resource_error,
    thread_seed::{self, ThreadInstructionSeed},
    thread_tools::ThreadToolAssembly,
};
use crate::{
    agent::definition::{AgentRootEntry, ResolvedAgentDefinition, VerifiedAgentIdentity},
    instruction::ModeInstructionProfile,
    resource_store::FileResourceStore,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError, ThreadPreparation},
};
use pl_core::context::{OpaquePayload, ResourceAccess};
use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
use std::collections::BTreeMap;

#[derive(Clone, Copy)]
pub(super) enum BotWorkspacePreparation {
    New,
    Existing,
}

impl StudioThreadFactory {
    pub(super) async fn resolve_root_delegation(
        &self,
        identity: &crate::thread_assembler::ThreadActivation,
    ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
        let thread = self.thread_record(&identity.id).await?;
        if identity.parent_id.is_some() || thread.parent_thread_id.is_some() {
            return Err(ThreadAssemblyError::Identity(identity.id.clone()));
        }
        self.ensure_bot_execution_workspace(&thread.clone().into(), None)
            .await?;
        let checkpoint = super::recovery::load_checkpoint_for_recovery(
            &self.services.store,
            &thread.clone().into(),
        )
        .await
        .map_err(|error| resource_error("load root delegation checkpoint", error))?;
        root_delegation(
            &thread,
            checkpoint.as_ref().map(|checkpoint| &checkpoint.state),
        )
    }

    pub(super) async fn bind_bot_project(
        &self,
        thread_id: &str,
        root_id: &str,
        project: &mut crate::studio::ProjectRecord,
        execution: &crate::studio::WorkspaceUsageLease,
        preparation: BotWorkspacePreparation,
    ) -> Result<Option<std::path::PathBuf>, ThreadAssemblyError> {
        if let Some(bot) = self
            .services
            .bots
            .config_for_thread(root_id)
            .await
            .map_err(|error| resource_error("resolve bot workspace", error))?
        {
            // Migration reads the previous execution root as well as writing the bot-owned root.
            // Both admissions precede the copy; a resolver alone is not permission to prepare.
            let complete = matches!(preparation, BotWorkspacePreparation::New)
                || self
                    .services
                    .bots
                    .workspace_migration_complete(&bot, thread_id, &project.path)
                    .await
                    .map_err(|error| resource_error("verify bot workspace migration", error))?;
            let source = if complete {
                None
            } else {
                let source = self
                    .services
                    .worktrees
                    .reserve_project_workspace(thread_id, &self.services.ssh_manager, project)
                    .await
                    .map_err(Self::workspace_usage_error)?;
                let original = self
                    .resolve_workspace_identity(project, std::path::Path::new(&project.path))
                    .await
                    .map_err(Self::workspace_usage_error)?;
                self.services
                    .worktrees
                    .assign_workspace(&source, original)
                    .map_err(Self::workspace_usage_error)?;
                Some(source)
            };
            let root = self.services.bots.workspace_root(&bot);
            let mut assigned = project.clone();
            assigned.path = root.to_string_lossy().into_owned();
            assigned.ssh_alias = None;
            // Migration uses its own source/target reservations. Strict bot Profile admission has
            // already established that the final execution root is this managed root, never a WT.
            let target = self
                .reserve_workspace_use(thread_id, &assigned)
                .await
                .map_err(Self::workspace_usage_error)?;
            let parent = root
                .parent()
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity("bot workspace has no managed parent".into())
                })?
                .to_owned();
            let canonical_parent = tokio::task::spawn_blocking(move || dunce::canonicalize(parent))
                .await?
                .map_err(|error| resource_error("resolve managed bot directory", error))?;
            let planned = canonical_parent.join("workspace");
            let identity = crate::studio::agent_host::worktree_lease::WorkspaceIdentity::canonical(
                crate::studio::agent_host::worktree_lease::WorkspaceEndpoint::Local,
                planned.to_string_lossy().into_owned(),
            )
            .map_err(Self::workspace_usage_error)?;
            if let Some(frozen) = self
                .services
                .store
                .workspace_identity(thread_id)
                .await
                .map_err(|error| resource_error("read frozen bot migration target", error))?
                && frozen != identity
            {
                return Err(ThreadAssemblyError::Workspace {
                    thread_id: thread_id.into(),
                    reason: "bot migration cannot rebind an existing physical execution identity"
                        .into(),
                });
            }
            self.services
                .worktrees
                .assign_workspace(&target, identity.clone())
                .map_err(Self::workspace_usage_error)?;
            pl_tool::workspace::path_safety::validate_path_for_write_async(
                &canonical_parent,
                &planned,
            )
            .await
            .map_err(|error| resource_error("validate managed bot workspace preparation", error))?;
            tokio::fs::create_dir_all(&planned)
                .await
                .map_err(|error| resource_error("materialize managed bot workspace", error))?;
            let actual = self
                .resolve_workspace_identity(&assigned, &planned)
                .await
                .map_err(Self::workspace_usage_error)?;
            self.services
                .worktrees
                .assign_workspace(&target, actual.clone())
                .map_err(Self::workspace_usage_error)?;
            // The canonical final assignment is known before any SessionFiles copy starts. The
            // real preparer/Entry owns `execution`, and the same lease owner retains failed files
            // across ordinary errors and restart. No auxiliary migration registry is needed.
            self.services
                .worktrees
                .assign_workspace(execution, actual.clone())
                .map_err(Self::workspace_usage_error)?;
            self.services
                .store
                .bind_workspace_identity(thread_id, &actual)
                .await
                .map_err(|error| resource_error("freeze final bot execution identity", error))?;
            self.services
                .worktrees
                .preserve_workspace_resources(thread_id, actual);
            project.path = match preparation {
                BotWorkspacePreparation::New => {
                    self.services
                        .bots
                        .prepare_new_workspace(&bot, thread_id)
                        .await
                }
                BotWorkspacePreparation::Existing => {
                    self.services
                        .bots
                        .prepare_workspace(&bot, thread_id, &project.path)
                        .await
                }
            }
            .map_err(|error| resource_error("prepare bot workspace", error))?
            .to_string_lossy()
            .into_owned();
            project.ssh_alias = None;
            drop(source);
            return Ok(Some(std::path::PathBuf::from(&project.path)));
        }
        Ok(None)
    }

    pub(in crate::studio) async fn prepare_root_thread(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let ThreadPreparation {
            workspace_owner,
            identity,
            cancellation,
            agent_controls,
            delegation: preflight_delegation,
        } = request;
        let id = identity.id.as_str();
        let thread = self.thread_record(id).await?;
        if identity.parent_id.is_some() || thread.parent_thread_id.is_some() {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        self.ensure_bot_execution_workspace(&thread.clone().into(), None)
            .await?;
        let mut project = self.project_record(&thread.project_id).await?;
        let workspace_usage = self
            .reserve_thread_workspace_use(id, id, &project)
            .await
            .map_err(Self::workspace_usage_error)?;
        workspace_owner.retain(&workspace_usage);
        let bot = self
            .services
            .bots
            .config_for_thread(id)
            .await
            .map_err(|error| resource_error("resolve bot ownership", error))?;
        let config = self.services.config_runtime.read()?.config;
        let protocol_thread: pl_protocol::Thread = thread.clone().into();
        let mut checkpoint =
            super::recovery::load_checkpoint_for_recovery(&self.services.store, &protocol_thread)
                .await
                .map_err(|error| resource_error("load Thread checkpoint", error))?;
        // Only decoded, validated ownership selects the bot definition: the live binding and the
        // fact frozen in this session must agree when both exist. Titles, user text, paths and
        // arbitrary metadata never decide the Agent role.
        let bot_owner = crate::studio::model_route::verified_bot_owner(
            bot.as_ref().map(|bot| bot.id.as_str()),
            checkpoint.as_ref().map(|checkpoint| &checkpoint.state),
        )
        .map_err(|error| resource_error("verify bot ownership", error))?;
        let agent = ResolvedAgentDefinition::root(if bot_owner.is_some() {
            AgentRootEntry::Bot
        } else {
            AgentRootEntry::Studio
        })?;
        // 旧快照的身份由已核实事实决定：有 bot 归属证明时沿用飞书渠道，否则是明确渠道未指定
        // 的 legacy-root；两者都不会伪装成当前内置的普通根定义。
        let saved_identity = match bot_owner {
            Some(_) => VerifiedAgentIdentity::BotRoot,
            None => VerifiedAgentIdentity::GenericRoot,
        };
        if let Some(checkpoint) = &mut checkpoint {
            let history = self
                .services
                .store
                .history_for(&thread.project_id, id)
                .await
                .map_err(|error| resource_error("open Mode recovery writer", error))?;
            *checkpoint = history
                .prepare_execution_identity(|state| {
                    crate::mode::migrate_mode_snapshot(state, &self.services.thread_modes)?;
                    // A root's saved Mode identity is required evidence: without it neither the
                    // Mode nor the legacy Agent role can be attributed, so the original
                    // checkpoint stays as it is.
                    anyhow::ensure!(
                        state.extensions.contains_key("studio.mode"),
                        "root Thread has no saved Mode identity; original checkpoint preserved"
                    );
                    // Mode recovery reads the saved role text before this migration rewrites the
                    // snapshot structure; the Agent identity is the verified one above.
                    crate::instruction::migrate_saved_representation(state, &saved_identity)?;
                    Ok(())
                })
                .await
                .map_err(|error| resource_error("migrate saved Mode and instructions", error))?;
        }
        let saved = checkpoint
            .as_ref()
            .map_or_else(pl_core::thread::ThreadSnapshot::default, |checkpoint| {
                checkpoint.state.clone()
            });
        let is_new = checkpoint.is_none();
        let delegation = root_delegation(
            &thread,
            checkpoint.as_ref().map(|checkpoint| &checkpoint.state),
        )?;
        if preflight_delegation != Some(delegation) {
            return Err(ThreadAssemblyError::Identity(
                "root delegation differs from its preflight".into(),
            ));
        }
        if bot.is_some() {
            self.bind_bot_project(
                id,
                id,
                &mut project,
                &workspace_usage,
                if is_new {
                    BotWorkspacePreparation::New
                } else {
                    BotWorkspacePreparation::Existing
                },
            )
            .await?;
        }
        let selected_mode = crate::studio::thread_projection::saved_mode(&saved)
            .map_err(|error| resource_error("read saved Mode", error))?
            .unwrap_or_else(|| thread.mode.clone());
        let mode = crate::mode::saved_registered_mode(&saved)
            .map_err(|error| resource_error("restore Mode snapshot", error))?
            .or_else(|| self.services.thread_modes.snapshot().mode(&selected_mode))
            .ok_or_else(|| ThreadAssemblyError::Identity(thread.mode.to_string()))?;
        let saved_route = crate::studio::model_route::saved(&saved)
            .map_err(|error| resource_error("decode saved model route", error))?;
        let has_saved_route = saved_route.is_some();
        let default_route = match self.initial_route(id).filter(|_| is_new) {
            Some(frozen) => frozen,
            None => config.mode_model_route(&selected_mode)?.clone(),
        };
        // Restore with the saved route. Bot settings are reconciled at the next input
        // admission, so reopening a Thread cannot change an already frozen request.
        let route_selector = match (saved_route, &bot) {
            (Some(saved), _) => saved.route,
            (None, Some(bot)) => self
                .services
                .bots
                .model_selector(bot)
                .map_err(|error| resource_error("resolve bot model", error))?,
            (None, None) => default_route.clone(),
        };
        let resolved_route = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &route_selector)
            .and_then(|route| {
                crate::studio::delegation::validate_credential(&route)?;
                Ok(route)
            });
        let (route, model_available) = match resolved_route {
            Ok(route) => (route, true),
            Err(error) if has_saved_route => {
                tracing::warn!(thread_id = id, %error, "saved Thread model route is unavailable");
                let fallback = crate::studio::model_route::unavailable_placeholder(
                    &config,
                    crate::config::root_agent_route_id(),
                    &route_selector,
                )
                .map_err(|error| resource_error("restore unavailable root placeholder", error))?;

                (fallback, false)
            }
            Err(error) => return Err(error.into()),
        };
        // 会话工作区只能由 canonical workspace_mode 与 durable lease 解析；
        // `worktree` 缺失、身份不符或已清理都显式失败，绝不回落到主工作区。
        let workspace_mode = thread.workspace_mode;
        let project_copy = project.clone();
        let bot_root = bot
            .as_ref()
            .map(|_| std::path::PathBuf::from(&project.path));
        let local_root = bot_root
            .clone()
            .unwrap_or_else(|| std::path::PathBuf::from(&thread.workspace_path));
        let canonical_project_root = tokio::task::spawn_blocking(move || {
            let project_root = match bot_root {
                Some(root) => root,
                None => crate::studio::agent_host::workspace_preparation::resolved_project_root(
                    &project_copy,
                )?,
            };
            Ok::<_, anyhow::Error>(project_root)
        })
        .await?
        .map_err(|error| resource_error("resolve root workspace", error))?;
        let root = crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
            &self.services.store,
            &self.services.worktrees,
            &self.services.ssh_manager,
            &thread,
            &project,
            local_root,
        )
        .await
        .map_err(|error| resource_error("resolve root workspace", error))?;
        let workspace = ToolWorkspace::new(match workspace_mode {
            pl_protocol::ThreadWorkspaceMode::Local => AgentWorkspace::local(&root),
            pl_protocol::ThreadWorkspaceMode::Worktree => {
                AgentWorkspace::worktree(&canonical_project_root, &root)
            }
        })
        .with_lsp_runtime(Some(self.services.lsp_runtime.clone()));
        self.assign_workspace_use(&workspace_usage, &project, workspace.root())
            .await
            .map_err(Self::workspace_usage_error)?;
        let store = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&thread.project_id, id)
                .map_err(|error| resource_error("resolve root session resources", error))?,
        );
        let mut prepared = self
            .prepare_thread_tools(ThreadToolAssembly {
                assignment: None,
                workspace_usage: workspace_usage.clone(),
                thread_id: id,
                cancellation: &cancellation,
                config: &config,
                route: &route,
                project: &project,
                root_thread_id: &thread.root_thread_id,
                workspace,
                store: store.clone(),
                helper_source: self.services.helper_source.clone(),
            })
            .await?;
        prepared.tools = prepared
            .tools
            .with_tools(crate::workflow_tool::workflow_registrations()?);
        let mut initial_context = Vec::new();
        let mut initial_extensions = BTreeMap::new();
        if is_new {
            initial_extensions.insert(
                crate::studio::delegation::EXTENSION.into(),
                crate::studio::delegation::encode(delegation)
                    .map_err(|error| resource_error("freeze delegation selection", error))?,
            );
        }
        if let Some(bot) = &bot
            && !saved
                .extensions
                .contains_key(crate::studio::model_route::BOT_OWNER_EXTENSION)
        {
            initial_extensions.insert(
                crate::studio::model_route::BOT_OWNER_EXTENSION.into(),
                crate::studio::model_route::encode_bot_owner(&bot.id)
                    .map_err(|error| resource_error("freeze bot owner", error))?,
            );
        }
        if !saved.extensions.contains_key("studio.mode") {
            initial_extensions.insert(
                "studio.mode".into(),
                crate::mode::encode_mode_snapshot(&crate::mode::SavedThreadMode::capture(
                    &mode, None,
                ))
                .map_err(|error| resource_error("freeze root Mode", error))?,
            );
        }
        if !has_saved_route {
            initial_extensions.insert(
                crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
                crate::studio::model_route::encode(&route_selector)
                    .map_err(|error| resource_error("freeze initial model route", error))?,
            );
        }
        if is_new {
            let (context, sources) = thread_seed::capture(ThreadInstructionSeed {
                thread_id: id,
                config: &config,
                model: &route.model,
                root: &root,
                agent: &agent,
                mode: Some(ModeInstructionProfile {
                    label: mode.descriptor().display_name.as_str(),
                    instructions: mode.prompt(),
                }),
                delegation: Some(delegation),
                resources: &prepared,
            })
            .await?;
            initial_context = context;
            initial_extensions.insert("studio.instructions".into(), sources);
            if config.runtime.tool_capabilities.ask_user {
                initial_extensions.insert(
                    crate::plan_tool::PLAN_EXTENSION.into(),
                    crate::plan_tool::encode_plan_state(&Default::default())
                        .map_err(|error| resource_error("freeze initial plan state", error))?,
                );
            }

            initial_extensions.insert(
                "studio.project".into(),
                OpaquePayload::new(
                    "pl.studio.project",
                    1,
                    serde_json::to_string(&project)
                        .map_err(|error| resource_error("encode root project", error))?,
                )
                .map_err(|error| resource_error("freeze root project", error))?,
            );
        }
        // Opening saved history preserves its run, even when the registered graph changed.
        // Context preparation reconciles the graph only when execution is explicitly resumed.
        if !is_new
            && let Some(workflow) = saved
                .extensions
                .get(crate::workflow_tool::WORKFLOW_EXTENSION)
        {
            crate::workflow_tool::decode_workflow_state(&workflow.payload)
                .map_err(|error| resource_error("decode restored workflow", error))?;
        }
        if cancellation.is_cancelled() {
            return Err(pl_core::thread::ThreadError::Cancelled.into());
        }
        let persistence = crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            protocol_thread,
            checkpoint.as_ref(),
        )
        .await
        .map_err(|error| resource_error("open Thread persistence", error))?;
        let model = pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            route.reasoning_config(),
        )
        .with_hosted_tools(prepared.hosted);
        let spec = StudioThreadSpec {
            workspace_usage: Some(workspace_usage),
            preparation_guard: prepared.binding_guard.take(),
            context_preparation: crate::compaction::preparer(
                &route,
                model.clone(),
                config.runtime.openai_compaction_mode,
                self.services.thread_modes.clone(),
            )?,
            agent_controls,
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
            },
            id: id.into(),
            parent_id: None,
            route,
            model_available,
            model,
            checkpoint,
            initial_context,
            initial_runtime_facts: super::session_files::session_files_fact(&prepared.workspace)
                .into_iter()
                .collect(),
            initial_extensions,
            tools: Vec::new(),
            resources: ResourceAccess::new(store),
            capacity: Default::default(),
            cold_store: Some(pl_core::thread::cold::ColdStoreHandle::new(persistence)),
        };
        Ok(prepared.tools.install(spec))
    }
}

fn root_delegation(
    thread: &crate::studio::ThreadRecord,
    saved: Option<&pl_core::thread::ThreadSnapshot>,
) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
    match saved {
        Some(saved) => crate::studio::delegation::saved(saved)
            .map_err(|error| resource_error("read saved delegation", error))?
            .ok_or_else(|| {
                ThreadAssemblyError::Identity("saved root has no delegation selection".into())
            }),
        None => Ok(pl_protocol::DelegationSettings {
            mode: thread.delegation_mode,
            preference: thread.delegation_preference,
        }),
    }
}
