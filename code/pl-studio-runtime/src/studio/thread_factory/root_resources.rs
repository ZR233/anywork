//! Root activation uses the same physical tools as children and resumes a current-state checkpoint.
use super::{
    StudioThreadFactory,
    errors::resource_error,
    thread_seed::{self, ThreadInstructionSeed},
    thread_tools::ThreadToolAssembly,
};
use crate::{
    resource_store::FileResourceStore,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError},
};
use pl_core::context::{OpaquePayload, ResourceAccess};
use pl_tool::workspace::{AgentWorkspace, ToolWorkspace};
use std::collections::BTreeMap;

impl StudioThreadFactory {
    pub(super) async fn bind_bot_project(
        &self,
        thread_id: &str,
        root_id: &str,
        project: &mut crate::studio::ProjectRecord,
    ) -> Result<Option<std::path::PathBuf>, ThreadAssemblyError> {
        if let Some(bot) = self
            .services
            .bots
            .config_for_thread(root_id)
            .await
            .map_err(|error| resource_error("resolve bot workspace", error))?
        {
            project.path = self
                .services
                .bots
                .prepare_workspace(&bot, thread_id, &project.path)
                .await
                .map_err(|error| resource_error("prepare bot workspace", error))?
                .to_string_lossy()
                .into_owned();
            project.ssh_alias = None;
            return Ok(Some(std::path::PathBuf::from(&project.path)));
        }
        Ok(None)
    }

    pub(in crate::studio) async fn prepare_root_thread(
        &self,
        id: &str,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        let preparation_cancellation = cancellation.clone();
        self.with_prepared_lifetime(id, &preparation_cancellation, |lifetime| async move {
        let thread = self.thread_record(id).await?;
        if thread.parent_thread_id.is_some() {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        let mut project = self.project_record(&thread.project_id).await?;
        let bot = self
            .services
            .bots
            .config_for_thread(id)
            .await
            .map_err(|error| resource_error("resolve bot ownership", error))?;
        if let Some(bot) = &bot {
            let root = self
                .services
                .bots
                .prepare_workspace(bot, id, &project.path)
                .await
                .map_err(|error| resource_error("prepare bot workspace", error))?;
            project.path = root.to_string_lossy().into_owned();
            project.ssh_alias = None;
        }
        let config = self.services.config_runtime.read()?.config;
        let protocol_thread: pl_protocol::Thread = thread.clone().into();
        let mut checkpoint =
            super::recovery::load_checkpoint_for_recovery(&self.services.store, &protocol_thread)
                .await
                .map_err(|error| resource_error("load Thread checkpoint", error))?;
        if let Some(checkpoint) = &mut checkpoint {
            let history = self
                .services
                .store
                .history_for(&thread.project_id, id)
                .await
                .map_err(|error| resource_error("open Mode recovery writer", error))?;
            *checkpoint = history
                .migrate_recovery_checkpoint(checkpoint, |state| {
                    crate::mode::migrate_mode_snapshot(state, &self.services.thread_modes)?;
                    Ok(())
                })
                .await
                .map_err(|error| resource_error("migrate saved Mode", error))?;
        }
        let saved = checkpoint
            .as_ref()
            .map_or_else(pl_core::thread::ThreadSnapshot::default, |checkpoint| {
                checkpoint.state.clone()
            });
        let is_new = checkpoint.is_none();
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
            .resolve_route(crate::config::StudioRole::Planner.id(), &route_selector)
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
                    crate::config::StudioRole::Planner.id(),
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
        let workspace_root_id = thread.root_thread_id.clone();
        let project_copy = project.clone();
        let bot_root = bot
            .as_ref()
            .map(|_| std::path::PathBuf::from(&project.path));
        let worktrees = self.services.worktrees.clone();
        let (root, canonical_project_root) = tokio::task::spawn_blocking(move || {
            let project_root = match bot_root {
                Some(root) => root,
                None => crate::studio::agent_host::workspace_preparation::resolved_project_root(
                    &project_copy,
                )?,
            };
            let session_root =
                crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                    &worktrees,
                    workspace_mode,
                    &workspace_root_id,
                    project_root.clone(),
                )?;
            Ok::<_, crate::PureError>((session_root, project_root))
        })
        .await?
        .map_err(|error| ThreadAssemblyError::Workspace {
            thread_id: id.to_owned(),
            reason: error.to_string(),
        })?;
        let workspace = ToolWorkspace::new(match workspace_mode {
            pl_protocol::ThreadWorkspaceMode::Local => AgentWorkspace::local(&root),
            pl_protocol::ThreadWorkspaceMode::Worktree => {
                AgentWorkspace::worktree(&canonical_project_root, &root)
            }
        })
        .with_lsp_runtime(Some(self.services.lsp_runtime.clone()));
        let store = FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&thread.project_id, id)
                .map_err(|error| resource_error("resolve root session resources", error))?,
        );
        let mut prepared = self
            .prepare_thread_tools(ThreadToolAssembly {
                thread_id: id,
                lifetime: lifetime.clone(),
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
        let delegation = crate::studio::delegation::saved(&saved)
            .map_err(|error| resource_error("read saved delegation", error))?
            .unwrap_or(pl_protocol::DelegationSettings {
                mode: thread.delegation_mode,
                preference: thread.delegation_preference,
            });
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
                label: &mode.descriptor().display_name,
                instructions: mode.prompt(),
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
        .with_hosted_tools(prepared.hosted)
        .with_preparation_owner(lifetime.preparation.clone())
        .with_user_files(self.user_file_access());
        let spec = StudioThreadSpec {
            preparation_guard: None,
            context_preparation: crate::compaction::preparer(
                &route,
                model.clone(),
                config.runtime.openai_compaction_mode,
                self.services.thread_modes.clone(),
                self.clone(),
            )?,
            agent_controls: crate::thread_assembler::AgentControlExposure::Enabled,
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
        }).await
    }
}
