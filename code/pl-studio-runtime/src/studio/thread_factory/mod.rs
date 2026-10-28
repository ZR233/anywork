//! Product configuration and shared service leases used to construct core Threads.
mod bot_workspace;
mod child_resources;
mod close_child;
mod errors;
mod execution_admission;
mod execution_cleanup;
pub(crate) mod recovery;
mod restore_child;
mod worktree_close;
pub(crate) use execution_admission::ExecutionWorkspaceCheck;
mod root_resources;
mod session_files;
mod thread_seed;
mod thread_tools;
mod tool_bindings;
mod workspace_validation;
pub(crate) use workspace_validation::VerifiedLocalResume;
pub(crate) use workspace_validation::{ReviewWorkspaceCheck, ReviewWorkspaceError};
mod workspace_usage;

pub(in crate::studio) use tool_bindings::RefreshedToolBinding;

use crate::studio::{ProductEventBus, StudioStore};
use std::sync::Arc;

/// Existing service owners, shared by lease; no mutable Thread/session state lives here.
#[derive(Clone)]
pub(in crate::studio) struct StudioThreadServices {
    pub store: StudioStore,
    pub worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    pub product_events: ProductEventBus,
    pub config_runtime: crate::config::ConfigRuntime,
    pub mcp_runtime: pl_tool::mcp::McpRuntimeHandle,
    pub lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry,
    pub skills: crate::studio::runtime::SkillCatalogRuntime,
    pub thread_modes: crate::mode::ThreadModeManager,
    pub ssh_manager: Arc<pl_tool::remote::SshManager>,
    pub helper_source: crate::worker_assets::RemoteHelperSource,
    pub bots: crate::bots::BotRuntime,
}

/// Assembles fresh model and tool instances from product inputs, without the old Turn engine.
#[derive(Clone)]
pub(crate) struct StudioThreadFactory {
    services: StudioThreadServices,
    bindings: Arc<std::sync::Mutex<std::collections::BTreeMap<String, tool_bindings::ToolBinding>>>,
    // Immutable assembly inputs admitted before a new directory identity is
    // published. Every concurrent activation sees the same frozen selector.
    initial_routes: Arc<
        std::sync::Mutex<std::collections::BTreeMap<String, pl_model::config::ModelRouteConfig>>,
    >,
}
impl StudioThreadFactory {
    /// Fresh allowance for each child Turn, including explicit continuation after a step limit.
    pub(crate) const CHILD_MODEL_STEP_LIMIT: pl_core::thread::ModelStepLimit =
        pl_core::thread::ModelStepLimit::Limited(
            std::num::NonZeroU32::new(256).expect("positive child step limit"),
        );

    pub(in crate::studio) fn new(services: StudioThreadServices) -> Self {
        Self {
            services,
            bindings: Default::default(),
            initial_routes: Default::default(),
        }
    }

    pub(in crate::studio) fn stage_initial_route(
        &self,
        id: &str,
        route: pl_model::config::ModelRouteConfig,
    ) {
        self.initial_routes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(id.to_owned(), route);
    }

    pub(in crate::studio) fn clear_initial_route(&self, id: &str) {
        self.initial_routes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(id);
    }

    fn initial_route(&self, id: &str) -> Option<pl_model::config::ModelRouteConfig> {
        self.initial_routes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .cloned()
    }
}
impl std::fmt::Debug for StudioThreadFactory {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StudioThreadFactory")
            .finish_non_exhaustive()
    }
}

impl crate::thread_assembler::StudioActivationFactory for StudioThreadFactory {
    async fn root_delegation(
        &self,
        identity: &crate::thread_assembler::ThreadActivation,
    ) -> Result<pl_protocol::DelegationSettings, crate::thread_assembler::ThreadAssemblyError> {
        self.resolve_root_delegation(identity).await
    }

    async fn prepare(
        &self,
        request: crate::thread_assembler::ThreadPreparation,
    ) -> Result<
        crate::thread_assembler::StudioThreadSpec,
        crate::thread_assembler::ThreadAssemblyError,
    > {
        if request.identity.parent_id.is_some() {
            self.prepare_restored_child(request).await
        } else {
            self.prepare_root_thread(request).await
        }
    }
}

impl StudioThreadFactory {
    async fn thread_record(
        &self,
        id: &str,
    ) -> Result<crate::studio::ThreadRecord, crate::thread_assembler::ThreadAssemblyError> {
        if let Some(record) = self.services.product_events.thread_snapshot(id) {
            return Ok(crate::studio::ThreadRecord::from_directory_thread(record));
        }
        self.services
            .store
            .read_thread(id)
            .await
            .map_err(|error| errors::resource_error("read Thread association", error))?
            .ok_or_else(|| crate::thread_assembler::ThreadAssemblyError::Identity(id.into()))
    }
    async fn project_record(
        &self,
        id: &str,
    ) -> Result<crate::studio::ProjectRecord, crate::thread_assembler::ThreadAssemblyError> {
        if let Some(record) = self
            .services
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|record| record.id == id)
        {
            return Ok(record);
        }
        self.services
            .store
            .read_project(id)
            .await
            .map_err(|error| errors::resource_error("read project association", error))?
            .ok_or_else(|| crate::thread_assembler::ThreadAssemblyError::Identity(id.into()))
    }
}
