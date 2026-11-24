//! Native root, new-child, and restored-child assembly share one skeleton.
//!
//! The eleven steps are admission, resource-scope binding, preparation ownership,
//! workspace reservation, account/model route, workspace resolution, workspace
//! assignment, session resources, tool binding, role facts, and spec finish.
//! Helpers here own the steps that do the same work. Role pipelines keep their own
//! order for admission, route selection, history migration, registration, and
//! confirmation so a failure still drops the same workspace use, preparation guard,
//! and registered-child cleanup owner.

use super::{
    StudioThreadFactory,
    errors::resource_error,
    thread_tools::{PreparedThreadTools, ThreadToolAssembly},
};
use crate::{
    resource_store::FileResourceStore,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError, ThreadPreparation},
};
use pl_core::{
    context::{OpaquePayload, ResourceAccess},
    tool::opaque::Registration,
};
use pl_model::config::ResolvedModelRoute;
use pl_tool::workspace::ToolWorkspace;
use std::collections::BTreeMap;

/// Which native assembly pipeline owns the role-specific steps.
pub(super) enum ThreadAssemblyRole<'a> {
    Root(ThreadPreparation),
    NewChild {
        request: &'a crate::thread_assembler::ChildThreadRequest,
        profile: &'a crate::config::ResolvedAgentProfile,
    },
    RestoredChild(ThreadPreparation),
}

/// Dispatches one native role without creating a second preparation fact source.
pub(super) struct NativeThreadAssemblyBuilder<'a> {
    factory: &'a StudioThreadFactory,
    role: ThreadAssemblyRole<'a>,
}

impl<'a> NativeThreadAssemblyBuilder<'a> {
    pub(super) fn root(factory: &'a StudioThreadFactory, request: ThreadPreparation) -> Self {
        Self {
            factory,
            role: ThreadAssemblyRole::Root(request),
        }
    }

    pub(super) fn new_child(
        factory: &'a StudioThreadFactory,
        request: &'a crate::thread_assembler::ChildThreadRequest,
        profile: &'a crate::config::ResolvedAgentProfile,
    ) -> Self {
        Self {
            factory,
            role: ThreadAssemblyRole::NewChild { request, profile },
        }
    }

    pub(super) fn restored_child(
        factory: &'a StudioThreadFactory,
        request: ThreadPreparation,
    ) -> Self {
        Self {
            factory,
            role: ThreadAssemblyRole::RestoredChild(request),
        }
    }

    /// Runs the selected role pipeline. Shared steps are the helpers below; each
    /// pipeline calls them at the point its existing failure cleanup expects.
    pub(super) async fn assemble(self) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        match self.role {
            ThreadAssemblyRole::Root(request) => self.factory.assemble_native_root(request).await,
            ThreadAssemblyRole::NewChild { request, profile } => {
                self.factory
                    .assemble_native_new_child(request, profile)
                    .await
            }
            ThreadAssemblyRole::RestoredChild(request) => {
                self.factory.assemble_native_restored_child(request).await
            }
        }
    }
}

/// Tool-binding inputs shared by the three native roles.
pub(super) struct NativeToolBinding<'a> {
    pub workspace_usage: crate::studio::WorkspaceUsageLease,
    pub thread_id: &'a str,
    pub cancellation: &'a tokio_util::sync::CancellationToken,
    pub config: &'a crate::config::StudioConfig,
    pub route: &'a ResolvedModelRoute,
    pub project: &'a crate::studio::WorkspaceRecord,
    pub root_thread_id: &'a str,
    pub workspace: ToolWorkspace,
    pub store: FileResourceStore,
    pub assignment: Option<&'a crate::AgentWorkspaceAssignmentSnapshot>,
}

/// Spec fields that remain role-owned after the shared finish has bound the model.
pub(super) struct NativeSpecParts<'a> {
    pub workspace: &'a ToolWorkspace,
    pub preparation_guard: Option<crate::thread_assembler::ThreadPreparationGuard>,
    pub agent_controls: Vec<Registration>,
    pub max_model_steps: pl_core::thread::ModelStepLimit,
    pub id: String,
    pub parent_id: Option<String>,
    pub route: ResolvedModelRoute,
    pub model: Option<pl_core::thread::RuntimeModel>,
    pub current: Option<pl_core::thread::current::ThreadCurrent>,
    pub initial_context: Vec<pl_core::context::ContextRecord>,
    pub initial_extensions: BTreeMap<String, OpaquePayload>,
    pub store: FileResourceStore,
    pub workspace_usage: Option<crate::studio::WorkspaceUsageLease>,
    pub persistence: crate::studio::storage::thread_writer::ThreadStorageSink,
}

/// Whether the role's already-selected route should open a Native model binding.
pub(super) enum NativeModelAvailability {
    Bind,
    LeaveUnbound,
}

impl StudioThreadFactory {
    pub(super) async fn reserve_native_workspace(
        &self,
        thread_id: &str,
        root_thread_id: &str,
        project: &crate::studio::WorkspaceRecord,
        owner: &crate::thread_assembler::WorkspacePreparationOwner,
    ) -> Result<crate::studio::WorkspaceUsageLease, ThreadAssemblyError> {
        let usage = self
            .reserve_thread_workspace_use(thread_id, root_thread_id, project)
            .await
            .map_err(Self::workspace_usage_error)?;
        owner.retain(&usage);
        Ok(usage)
    }

    /// Blocking project-root resolution used by root activation and cold child restore.
    ///
    /// New-child preparation keeps its own join-error mapping and only blocks when the
    /// root is not already a bot or review assignment.
    pub(super) async fn resolve_canonical_project_root(
        project: crate::studio::WorkspaceRecord,
        bot_root: Option<std::path::PathBuf>,
        context: &'static str,
    ) -> Result<std::path::PathBuf, ThreadAssemblyError> {
        tokio::task::spawn_blocking(move || {
            let project_root = match bot_root {
                Some(root) => root,
                None => crate::studio::agent_host::workspace_preparation::resolved_project_root(
                    &project,
                )?,
            };
            Ok::<_, anyhow::Error>(project_root)
        })
        .await?
        .map_err(|error| resource_error(context, error))
    }

    pub(super) async fn assign_native_workspace(
        &self,
        usage: &crate::studio::WorkspaceUsageLease,
        project: &crate::studio::WorkspaceRecord,
        root: &std::path::Path,
    ) -> Result<(), ThreadAssemblyError> {
        self.assign_workspace_use(usage, project, root)
            .await
            .map_err(Self::workspace_usage_error)
    }

    pub(super) fn open_session_resources(
        &self,
        workspace_id: &str,
        thread_id: &str,
        context: &'static str,
    ) -> Result<FileResourceStore, ThreadAssemblyError> {
        Ok(FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(workspace_id, thread_id)
                .map_err(|error| resource_error(context, error))?,
        ))
    }

    pub(super) async fn bind_native_tools(
        &self,
        binding: NativeToolBinding<'_>,
    ) -> Result<PreparedThreadTools, ThreadAssemblyError> {
        let NativeToolBinding {
            workspace_usage,
            thread_id,
            cancellation,
            config,
            route,
            project,
            root_thread_id,
            workspace,
            store,
            assignment,
        } = binding;
        self.prepare_thread_tools(
            ThreadToolAssembly {
                workspace_usage,
                thread_id,
                cancellation,
                config,
                route,
                project,
                root_thread_id,
                workspace,
                store,
            },
            assignment,
        )
        .await
    }

    pub(super) fn encode_frozen_project(
        project: &crate::studio::WorkspaceRecord,
        encode_context: &'static str,
        freeze_context: &'static str,
    ) -> Result<OpaquePayload, ThreadAssemblyError> {
        OpaquePayload::new(
            "pl.studio.project",
            1,
            serde_json::to_string(project)
                .map_err(|error| resource_error(encode_context, error))?,
        )
        .map_err(|error| resource_error(freeze_context, error))
    }

    pub(super) async fn open_native_persistence(
        &self,
        thread: crate::Thread,
        context: &'static str,
    ) -> Result<crate::studio::storage::thread_writer::ThreadStorageSink, ThreadAssemblyError> {
        crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            thread,
        )
        .await
        .map_err(|error| resource_error(context, error))
    }

    pub(super) async fn open_native_export_history(
        &self,
        thread_id: &str,
    ) -> Result<crate::history::HistoryReader, ThreadAssemblyError> {
        Ok(self
            .services
            .store
            .history(thread_id)
            .await
            .map_err(|error| resource_error("open export history", error))?
            .reader())
    }

    /// Binds an account route the role has already accepted.
    ///
    /// `LeaveUnbound` drops the hosted tools without calling the model binder. That is
    /// the saved-route failure path: the role has already chosen a placeholder and must
    /// not replace it here.
    pub(super) fn bind_native_model(
        &self,
        route: &ResolvedModelRoute,
        config: &crate::config::StudioConfig,
        hosted: Vec<pl_model::runtime::HostedTool>,
        availability: NativeModelAvailability,
    ) -> Result<Option<pl_core::thread::RuntimeModel>, ThreadAssemblyError> {
        match availability {
            NativeModelAvailability::LeaveUnbound => {
                drop(hosted);
                Ok(None)
            }
            NativeModelAvailability::Bind => crate::studio::model_binding::configured_model(
                route,
                config,
                self.services.thread_modes.clone(),
                hosted,
            )
            .map(Some)
            .map_err(|error| resource_error("prepare Native model binding", error)),
        }
    }

    pub(super) fn compose_native_spec(parts: NativeSpecParts<'_>) -> StudioThreadSpec {
        StudioThreadSpec {
            workspace_usage: parts.workspace_usage,
            preparation_guard: parts.preparation_guard,
            agent_controls: parts.agent_controls,
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: parts.max_model_steps,
            },
            id: parts.id,
            parent_id: parts.parent_id,
            route: parts.route,
            model: parts.model,
            current: parts.current,
            initial_context: parts.initial_context,
            initial_runtime_facts: super::session_files::session_files_fact(parts.workspace)
                .into_iter()
                .collect(),
            initial_extensions: parts.initial_extensions,
            tools: Vec::new(),
            resources: ResourceAccess::new(parts.store),
            capacity: Default::default(),
            history_sink: Some(parts.persistence),
        }
    }

    pub(super) async fn confirm_native_worktree(
        &self,
        lease: &crate::studio::agent_host::worktree_lease::WorktreeLease,
        usage: &crate::studio::WorkspaceUsageLease,
        owner: &impl crate::thread_assembler::WorkspaceBindingAdmission,
        context: &'static str,
    ) -> Result<(), ThreadAssemblyError> {
        self.confirm_worktree_binding(lease, usage, owner)
            .await
            .map_err(|error| resource_error(context, error))
    }

    /// Returns the export coordinator only when this root is already enrolled.
    ///
    /// Callers construct `NewMemberRegistration` after this check so an unenrolled run
    /// does not clone member identity or take the history reader.
    pub(super) fn enrolled_exporter(
        &self,
        root_thread_id: &str,
    ) -> Option<&std::sync::Arc<crate::studio::runtime::run_export::RunExportCoordinator>> {
        self.services
            .run_export
            .as_ref()
            .filter(|exporter| exporter.is_enrolled_root(root_thread_id))
    }

    pub(super) async fn publish_enrolled_member(
        exporter: &crate::studio::runtime::run_export::RunExportCoordinator,
        root_thread_id: &str,
        thread_id: &str,
        registration: crate::studio::runtime::run_export::NewMemberRegistration,
        catalog: Option<&pl_tool::skill::FrozenSkillCatalog>,
    ) {
        Box::pin(exporter.register_member(registration)).await;
        if let Some(catalog) = catalog {
            Box::pin(exporter.record_skills_discovered(root_thread_id, thread_id, catalog)).await;
        }
    }
}
