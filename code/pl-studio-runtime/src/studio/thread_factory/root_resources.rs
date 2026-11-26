//! Root activation uses the same physical tools as children and restores complete current facts.
use super::bot_workspace::BotWorkspacePreparation;
use super::{
    StudioThreadFactory,
    errors::resource_error,
    thread_seed::{self, ThreadInstructionSeed},
};
use crate::{
    agent::definition::{AgentRootEntry, ResolvedAgentDefinition, VerifiedAgentIdentity},
    instruction::ModeInstructionProfile,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError, ThreadPreparation},
};
use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
use std::collections::BTreeMap;

impl StudioThreadFactory {
    pub(in crate::studio) async fn prepare_root_thread(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        super::native_assembly::NativeThreadAssemblyBuilder::root(self, request)
            .assemble()
            .await
    }

    /// Root pipeline. Shared steps are reservation, canonical root resolution, assignment,
    /// session resources, tool binding, project freeze, persistence, export history, model
    /// binding, spec composition, worktree confirmation, and enrolled export.
    pub(super) async fn assemble_native_root(
        &self,
        request: ThreadPreparation,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let ThreadPreparation {
            workspace_owner,
            identity,
            cancellation,
            agent_controls,
            delegation: preflight_delegation,
            mut current,
        } = request;
        let id = identity.id();
        self.bind_resource_scope(id, &workspace_owner.native_resources())?;
        let thread = self.thread_record(id).await?;
        if identity.parent_thread_id.is_some() || thread.parent_thread_id.is_some() {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        if thread.visibility != crate::studio::ThreadVisibility::Active {
            return Err(ThreadAssemblyError::Closed);
        }
        let protocol_thread: crate::Thread = thread.clone().into();
        let saved_snapshot = current
            .as_ref()
            .map(|current| current.state.to_paused_snapshot());
        self.admit_saved_execution(&protocol_thread, saved_snapshot.as_ref())
            .await?;
        // This activation already knows whether the root has a saved publication baseline.
        self.services
            .store
            .record_thread_preparation(
                crate::studio::store::thread_preparation::PreparationIdentity {
                    thread_id: thread.id.clone(),
                    workspace_id: thread.workspace_id.clone(),
                    parent_id: None,
                    root_id: thread.id.clone(),
                },
                current.is_some(),
            )
            .await
            .map_err(|error| resource_error("record root assembly owner", error))?;
        let mut project = self.project_record(&thread.workspace_id).await?;
        let workspace_usage = self
            .reserve_native_workspace(id, id, &project, &workspace_owner)
            .await?;
        let bot = self
            .services
            .bots
            .saved_config_for_thread(id)
            .await
            .map_err(|error| resource_error("resolve bot ownership", error))?;
        let config = self.services.config_runtime.read()?.config;
        // Only decoded, validated ownership selects the bot definition: the live binding and the
        // fact frozen in this session must agree when both exist. Titles, user text, paths and
        // arbitrary metadata never decide the Agent role.
        let bot_owner = crate::studio::bot_owner::verified_bot_owner(
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
        let is_new = current.is_none();
        let mut saved = saved_snapshot.unwrap_or_default();
        if let Some(current) = &mut current {
            // These migrations only rewrite frozen extension payloads. Keep the complete current
            // state (including model_call and tool previews) intact instead of replacing it from
            // the paused product snapshot.
            crate::mode::migrate_mode_snapshot(&mut saved, &self.services.thread_modes)
                .map_err(|error| resource_error("migrate saved Mode and instructions", error))?;
            if !saved.extensions.contains_key("studio.mode") {
                return Err(ThreadAssemblyError::Identity(
                    "root Thread has no saved Mode identity; original current preserved".into(),
                ));
            }
            crate::instruction::migrate_saved_representation(&mut saved, &saved_identity)
                .map_err(|error| resource_error("migrate saved Mode and instructions", error))?;
            debug_assert!(
                saved.extensions.contains_key("studio.mode"),
                "saved Mode migration preserved its identity"
            );
            current.state.extensions = saved.extensions.clone();
            current.state.extension_sequence = saved.extension_sequence;
        }
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
        let catalog = self.services.thread_modes.snapshot();
        let mode = crate::mode::saved_registered_mode(&saved)
            .map_err(|error| resource_error("restore Mode snapshot", error))?
            .or_else(|| catalog.mode(&selected_mode))
            .or_else(|| {
                selected_mode
                    .legacy_builtin_replacement()
                    .and_then(|replacement| catalog.mode(&replacement))
            })
            .ok_or_else(|| ThreadAssemblyError::Identity(selected_mode.to_string()))?;
        let saved_route = crate::studio::model_route::saved(&saved)
            .map_err(|error| resource_error("decode saved model route", error))?;
        let has_saved_route = saved_route.is_some();
        let default_route = match self.initial_route(id).filter(|_| is_new) {
            Some(frozen) => frozen,
            None => config.mode_model_route(&selected_mode)?.clone().into(),
        };
        // Restore with the saved route. Bot settings are reconciled at the next input
        // admission, so reopening a Thread cannot change an already frozen request.
        let route_selector = match (saved_route, &bot) {
            (Some(saved), _) => saved.route,
            (None, Some(bot)) => self
                .services
                .bots
                .model_selector(bot)
                .map_err(|error| resource_error("resolve bot model", error))?
                .into(),
            (None, None) => default_route.clone(),
        };
        let resolved_route = route_selector.resolve(&config).and_then(|route| {
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
                    &route_selector.model,
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
        let canonical_project_root =
            Self::resolve_canonical_project_root(project_copy, bot_root, "resolve root workspace")
                .await?;
        let (root, verified_lease) =
            crate::studio::worktree::workspace_preparation::root_session_workspace_root(
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
        });
        self.assign_native_workspace(&workspace_usage, &project, workspace.root())
            .await?;
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "activation_workspace", elapsed_ms = workspace_started.elapsed().as_millis() as u64, "completed");
        let store = self.open_session_resources(
            &thread.workspace_id,
            id,
            "resolve root session resources",
        )?;
        let tools_started = std::time::Instant::now();
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "tools", "starting");
        let mut prepared = self
            .bind_native_tools(super::native_assembly::NativeToolBinding {
                workspace_usage: workspace_usage.clone(),
                thread_id: id,
                cancellation: &cancellation,
                config: &config,
                route: &route,
                project: &project,
                root_thread_id: &thread.root_thread_id,
                workspace,
                store: store.clone(),
                assignment: None,
            })
            .await?;
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "tools", elapsed_ms = tools_started.elapsed().as_millis() as u64, "completed");
        prepared.tools = prepared
            .tools
            .with_tools(crate::workflow_tool::workflow_registrations(
                crate::mode::workflow_binding_from_snapshot,
            )?);
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
                .contains_key(crate::studio::bot_owner::BOT_OWNER_EXTENSION)
        {
            initial_extensions.insert(
                crate::studio::bot_owner::BOT_OWNER_EXTENSION.into(),
                crate::studio::bot_owner::encode_bot_owner(&bot.id)
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
            initial_extensions.insert(
                crate::plan_tool::PLAN_EXTENSION.into(),
                crate::plan_tool::encode_plan_state(&Default::default())
                    .map_err(|error| resource_error("freeze initial plan state", error))?,
            );

            initial_extensions.insert(
                "studio.project".into(),
                Self::encode_frozen_project(
                    &project,
                    "encode root project",
                    "freeze root project",
                )?,
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
        let persistence = self
            .open_native_persistence(protocol_thread, "open Thread persistence")
            .await?;
        let export_history = self.open_native_export_history(id).await?;
        tracing::debug!(target: "thread_preparation", thread_id = id, stage = "persistence", elapsed_ms = persistence_started.elapsed().as_millis() as u64, "completed");
        let model = self.bind_native_model(
            &route,
            &config,
            prepared.hosted,
            if model_available {
                super::native_assembly::NativeModelAvailability::Bind
            } else {
                super::native_assembly::NativeModelAvailability::LeaveUnbound
            },
        )?;
        let spec = Self::compose_native_spec(super::native_assembly::NativeSpecParts {
            workspace: &prepared.workspace,
            preparation_guard: prepared.binding_guard.take(),
            agent_controls,
            max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
            id: id.into(),
            parent_id: None,
            route,
            model,
            current,
            initial_context,
            initial_extensions,
            store,
            workspace_usage: Some(workspace_usage),
            persistence,
        });
        if let Some(lease) = verified_lease {
            self.confirm_native_worktree(
                &lease,
                spec.workspace_usage.as_ref().expect("root preparation use"),
                &workspace_owner,
                "confirm root worktree binding",
            )
            .await?;
        }
        if let Some(exporter) = self.enrolled_exporter(&thread.root_thread_id) {
            Self::publish_enrolled_member(
                exporter,
                &thread.root_thread_id,
                id,
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
                prepared.catalog.as_deref(),
            )
            .await;
        }
        Ok(prepared.tools.install(spec))
    }
}

pub(super) fn root_delegation(
    thread: &crate::studio::ThreadRecord,
    current: Option<&pl_core::thread::current::ThreadCurrent>,
) -> Result<crate::DelegationSettings, ThreadAssemblyError> {
    match current {
        Some(current) => current
            .state
            .extensions
            .get(crate::studio::delegation::EXTENSION)
            .map(|record| crate::studio::delegation::decode(&record.payload))
            .transpose()
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
