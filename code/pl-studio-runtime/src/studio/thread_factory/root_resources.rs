//! Root activation uses the same physical tools as children and restores complete current facts.
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
    pub(super) async fn prepare_root_state(
        &self,
        identity: &crate::thread_assembler::ThreadActivation,
    ) -> Result<
        (
            crate::DelegationSettings,
            Option<pl_core::thread::current::ThreadCurrent>,
        ),
        ThreadAssemblyError,
    > {
        let thread = self.thread_record(identity.id()).await?;
        if identity.parent_thread_id.is_some() || thread.parent_thread_id.is_some() {
            return Err(ThreadAssemblyError::Identity(identity.id().to_owned()));
        }
        self.verify_saved_bot_execution_workspace(&thread.clone().into(), None)
            .await?;
        let current = super::recovery::load_current_for_recovery(
            &self.services.store,
            &thread.clone().into(),
        )
        .await
        .map_err(|error| resource_error("load root delegation current", error))?;
        let saved = current
            .as_ref()
            .map(|current| current.state.to_paused_snapshot());
        let delegation = root_delegation(&thread, saved.as_ref())?;
        Ok((delegation, current))
    }

    pub(super) async fn bind_bot_project(
        &self,
        thread_id: &str,
        root_id: &str,
        project: &mut crate::studio::WorkspaceRecord,
        execution: &crate::studio::WorkspaceUsageLease,
        preparation: BotWorkspacePreparation,
    ) -> Result<Option<std::path::PathBuf>, ThreadAssemblyError> {
        if let Some(bot) = self
            .services
            .bots
            .saved_config_for_thread(root_id)
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
            if self
                .services
                .store
                .thread_preparation(thread_id)
                .await
                .map_err(|error| resource_error("read managed preparation owner", error))?
                .is_some()
            {
                self.services
                    .store
                    .bind_thread_preparation(thread_id, &identity)
                    .await
                    .map_err(|error| {
                        resource_error("fix managed execution binding before preparation", error)
                    })?;
            }
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
            root_current: mut current,
        } = request;
        let id = identity.id();
        self.bind_resource_scope(id, &workspace_owner.native_resources())?;
        let thread = self.thread_record(id).await?;
        self.services
            .store
            .begin_thread_preparation(
                crate::studio::store::thread_preparation::PreparationIdentity {
                    thread_id: thread.id.clone(),
                    workspace_id: thread.workspace_id.clone(),
                    parent_id: None,
                    root_id: thread.id.clone(),
                },
            )
            .await
            .map_err(|error| resource_error("record root assembly owner", error))?;
        if identity.parent_thread_id.is_some() || thread.parent_thread_id.is_some() {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        self.verify_saved_bot_execution_workspace(&thread.clone().into(), None)
            .await?;
        let mut project = self.project_record(&thread.workspace_id).await?;
        let workspace_usage = self
            .reserve_thread_workspace_use(id, id, &project)
            .await
            .map_err(Self::workspace_usage_error)?;
        workspace_owner.retain(&workspace_usage);
        let bot = self
            .services
            .bots
            .saved_config_for_thread(id)
            .await
            .map_err(|error| resource_error("resolve bot ownership", error))?;
        let config = self.services.config_runtime.read()?.config;
        let protocol_thread: crate::Thread = thread.clone().into();
        // Only decoded, validated ownership selects the bot definition: the live binding and the
        // fact frozen in this session must agree when both exist. Titles, user text, paths and
        // arbitrary metadata never decide the Agent role.
        let saved_snapshot = current
            .as_ref()
            .map(|current| current.state.to_paused_snapshot());
        let bot_owner = crate::studio::model_route::verified_bot_owner(
            bot.as_ref().map(|bot| bot.id.as_str()),
            saved_snapshot.as_ref(),
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
        if let Some(current) = &mut current {
            // These migrations only rewrite frozen extension payloads. Keep the complete current
            // state (including model_call and tool previews) intact instead of replacing it from
            // the paused product snapshot.
            let mut state = current.state.to_paused_snapshot();
            crate::mode::migrate_mode_snapshot(&mut state, &self.services.thread_modes)
                .map_err(|error| resource_error("migrate saved Mode and instructions", error))?;
            if !state.extensions.contains_key("studio.mode") {
                return Err(ThreadAssemblyError::Identity(
                    "root Thread has no saved Mode identity; original current preserved".into(),
                ));
            }
            crate::instruction::migrate_saved_representation(&mut state, &saved_identity)
                .map_err(|error| resource_error("migrate saved Mode and instructions", error))?;
            debug_assert!(
                state.extensions.contains_key("studio.mode"),
                "saved Mode migration preserved its identity"
            );
            current.state.extensions = state.extensions;
            current.state.extension_sequence = state.extension_sequence;
        }
        let saved = current
            .as_ref()
            .map_or_else(pl_core::thread::ThreadSnapshot::default, |current| {
                current.state.to_paused_snapshot()
            });
        let is_new = current.is_none();
        let delegation = preflight_delegation.ok_or_else(|| {
            ThreadAssemblyError::Identity(
                "root preparation is missing its frozen delegation".into(),
            )
        })?;
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
        let directory_mode = thread
            .mode
            .clone()
            .ok_or_else(|| ThreadAssemblyError::Identity("Native root has no Mode".into()))?;
        let selected_mode = crate::studio::thread_projection::saved_mode(&saved)
            .map_err(|error| resource_error("read saved Mode", error))?
            .unwrap_or(directory_mode);
        let mode = crate::mode::saved_registered_mode(&saved)
            .map_err(|error| resource_error("restore Mode snapshot", error))?
            .or_else(|| self.services.thread_modes.snapshot().mode(&selected_mode))
            .ok_or_else(|| ThreadAssemblyError::Identity(selected_mode.to_string()))?;
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
        let workspace_started = std::time::Instant::now();
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "activation_workspace", "starting");
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
        let (root, verified_lease) =
            crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                &self.services.store,
                &self.services.worktrees,
                &self.services.ssh_manager,
                &self.directory_member(&thread.id)?,
                &project,
                local_root,
            )
            .await
            .map_err(|error| resource_error("resolve root workspace", error))?;
        let workspace = ToolWorkspace::new(match workspace_mode {
            crate::ThreadWorkspaceMode::Local => AgentWorkspace::local(&root),
            crate::ThreadWorkspaceMode::Worktree => {
                AgentWorkspace::worktree(&canonical_project_root, &root)
            }
        })
        .with_lsp_runtime(Some(self.services.lsp_runtime.clone()));
        self.assign_workspace_use(&workspace_usage, &project, workspace.root())
            .await
            .map_err(Self::workspace_usage_error)?;
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "activation_workspace", elapsed_ms = workspace_started.elapsed().as_millis() as u64, "completed");
        let store = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&thread.workspace_id, id)
                .map_err(|error| resource_error("resolve root session resources", error))?,
        );
        let tools_started = std::time::Instant::now();
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "tools", "starting");
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
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "tools", elapsed_ms = tools_started.elapsed().as_millis() as u64, "completed");
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
            let instructions_started = std::time::Instant::now();
            tracing::debug!(target: "thread_preparation", thread_id = id, stage = "instructions", "starting");
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
            tracing::debug!(target: "thread_preparation", thread_id = id, stage = "instructions", elapsed_ms = instructions_started.elapsed().as_millis() as u64, "completed");
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
        let persistence_started = std::time::Instant::now();
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "persistence", "starting");
        let persistence = crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            protocol_thread,
        )
        .await
        .map_err(|error| resource_error("open Thread persistence", error))?;
        let export_history = self
            .services
            .store
            .history(id)
            .await
            .map_err(|error| resource_error("open export history", error))?
            .reader();
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "persistence", elapsed_ms = persistence_started.elapsed().as_millis() as u64, "completed");
        let model = model_available
            .then(|| {
                crate::studio::model_binding::configured_model(
                    &route,
                    &config,
                    self.services.thread_modes.clone(),
                    prepared.hosted,
                )
            })
            .transpose()
            .map_err(|error| resource_error("prepare Native model binding", error))?;
        let spec = StudioThreadSpec {
            workspace_usage: Some(workspace_usage),
            preparation_guard: prepared.binding_guard.take(),
            agent_controls,
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
            },
            id: id.into(),
            parent_id: None,
            route,
            model,
            current,
            initial_context,
            initial_runtime_facts: super::session_files::session_files_fact(&prepared.workspace)
                .into_iter()
                .collect(),
            initial_extensions,
            tools: Vec::new(),
            resources: ResourceAccess::new(store),
            capacity: Default::default(),
            history_sink: Some(persistence),
        };
        if let Some(lease) = verified_lease {
            self.confirm_worktree_binding(
                &lease,
                spec.workspace_usage.as_ref().expect("root preparation use"),
                &workspace_owner,
            )
            .await
            .map_err(|error| resource_error("confirm root worktree binding", error))?;
        }
        if let Some(exporter) = &self.services.run_export
            && exporter.is_enrolled_root(&thread.root_thread_id)
        {
            Box::pin(exporter.register_member(
                crate::studio::runtime::run_export::NewMemberRegistration {
                    root_thread_id: thread.root_thread_id.clone(),
                    thread_id: id.into(),
                    agent_id: id.into(),
                    parent_agent_id: None,
                    parent_thread_id: None,
                    role: Some(crate::config::ROOT_AGENT_ROUTE_KEY.to_owned()),
                    workspace_id: thread.workspace_id.clone(),
                    spawn_tool_call_id: None,
                    initial_effect_seq: saved.commit_sequence,
                    history: export_history,
                },
            ))
            .await;
            if let Some(catalog) = prepared.catalog.as_deref() {
                Box::pin(exporter.record_skills_discovered(&thread.root_thread_id, id, catalog))
                    .await;
            }
        }
        Ok(prepared.tools.install(spec))
    }
}

fn root_delegation(
    thread: &crate::studio::ThreadRecord,
    saved: Option<&pl_core::thread::ThreadSnapshot>,
) -> Result<crate::DelegationSettings, ThreadAssemblyError> {
    match saved {
        Some(saved) => crate::studio::delegation::saved(saved)
            .map_err(|error| resource_error("read saved delegation", error))?
            .ok_or_else(|| {
                ThreadAssemblyError::Identity("saved root has no delegation selection".into())
            }),
        None => Ok(crate::DelegationSettings {
            mode: thread.delegation_mode,
            preference: thread.delegation_preference,
        }),
    }
}
