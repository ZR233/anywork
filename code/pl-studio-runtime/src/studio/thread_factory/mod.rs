//! Product configuration and shared service leases used to construct core Threads.
mod bot_workspace;
mod child_resources;
mod close_child;
mod errors;
mod execution_admission;
mod execution_cleanup;
pub(crate) mod mcp;
mod mcp_reconnect_tool;
mod mcp_refresh_tool;
pub(crate) mod recovery;
mod restore_child;
mod worktree_close;
pub(crate) use execution_admission::ExecutionWorkspaceCheck;
pub(in crate::studio) use worktree_close::removal_definitely_refused as worktree_removal_definitely_refused;
#[cfg(test)]
mod review_archive_tests;
mod root_resources;
mod session_files;
mod thread_seed;
mod thread_tools;
pub(crate) mod tool_bindings;
mod workspace_validation;
pub(crate) use workspace_validation::VerifiedLocalResume;
pub(crate) use workspace_validation::{ReviewWorkspaceCheck, ReviewWorkspaceError};
mod workspace_usage;

pub(in crate::studio) use tool_bindings::RefreshedToolBinding;

use crate::studio::{ProductEventBus, StudioStore};
use std::sync::Arc;

pub(crate) struct LspProjectionBinding<'a> {
    pub incarnation: &'a Arc<()>,
    pub binding_id: Option<&'a str>,
    pub endpoint: Option<&'a str>,
    pub root: Option<&'a std::path::Path>,
}

/// Existing service owners, shared by lease; no mutable Thread/session state lives here.
#[derive(Clone)]
pub(in crate::studio) struct StudioThreadServices {
    pub store: StudioStore,
    pub worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    pub recovery: crate::studio::StudioRecoveryRegistry,
    pub product_events: ProductEventBus,
    pub config_runtime: crate::config::ConfigRuntime,
    pub mcp_connector: pl_tool::mcp::McpConnector,
    pub lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry,
    pub local_executor: pl_remote_helper::Executor,
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
    lsp_binding_updates: Arc<tokio::sync::Notify>,
    scopes: Arc<
        std::sync::Mutex<
            std::collections::BTreeMap<String, std::sync::Weak<crate::session::NativeResources>>,
        >,
    >,
    // Immutable assembly inputs admitted before a new directory identity is
    // published. Every concurrent activation sees the same frozen selector.
    initial_routes: Arc<
        std::sync::Mutex<std::collections::BTreeMap<String, pl_model::config::ModelRouteConfig>>,
    >,
}
impl StudioThreadFactory {
    pub(in crate::studio) fn local_executor(&self) -> pl_remote_helper::Executor {
        self.services.local_executor.clone()
    }

    fn directory_member(
        &self,
        id: &str,
    ) -> Result<crate::studio::records::DirectoryMember, crate::thread_assembler::ThreadAssemblyError>
    {
        self.services
            .product_events
            .directory_member(id)
            .and_then(|member| match member {
                Some(member) => Ok(Some(member)),
                None => self.services.store.directory_member(id),
            })
            .map_err(|error| errors::resource_error("read directory association", error))?
            .ok_or_else(|| crate::thread_assembler::ThreadAssemblyError::Identity(id.into()))
    }

    pub(crate) fn resource_scope(&self, id: &str) -> Option<Arc<crate::session::NativeResources>> {
        self.scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(std::sync::Weak::upgrade)
    }

    pub(crate) fn notify_lsp_binding_changed(&self) {
        self.lsp_binding_updates.notify_one();
    }

    /// Runs a synchronous projection commit while the current resource/binding and lifetime
    /// qualification are locked in the required order. `None` means a captured identity was
    /// replaced, or a retirement was superseded by a new binding.
    pub(crate) fn commit_lsp_projection<R>(
        &self,
        thread_id: &str,
        captured: Option<LspProjectionBinding<'_>>,
        commit: impl FnOnce(bool) -> R,
    ) -> Option<R> {
        let Some(scope) = self.resource_scope(thread_id) else {
            return captured.is_none().then(|| commit(false));
        };
        let bindings = scope
            .binding
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(binding) = bindings.as_ref() else {
            return captured.is_none().then(|| commit(false));
        };
        let LspProjectionBinding {
            incarnation,
            binding_id,
            endpoint,
            root,
        } = captured?;
        if !Arc::ptr_eq(&binding.incarnation, incarnation)
            || binding.lsp_binding_id.as_deref() != binding_id
        {
            return None;
        }
        let _qualification = binding.lifetime.qualification_guard();
        let lease = binding.lsp_lease.as_ref();
        let valid = binding_id.is_some()
            && !binding.target_invalidated
            && !binding.lifetime.cancellation.is_cancelled()
            && lease.is_some_and(|lease| {
                !lease.is_closed()
                    && Some(lease.workspace_root()) == root
                    && crate::studio::runtime::lsp_state::execution_endpoint(
                        binding.project.ssh_alias.as_deref(),
                    )
                    .as_str()
                        == endpoint.unwrap_or_default()
            });
        Some(commit(valid))
    }

    pub(crate) fn bind_resource_scope(
        &self,
        id: &str,
        scope: &Arc<crate::session::NativeResources>,
    ) -> Result<(), crate::thread_assembler::ThreadAssemblyError> {
        let mut scopes = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(previous) = scopes.get(id).and_then(std::sync::Weak::upgrade)
            && !Arc::ptr_eq(&previous, scope)
            && previous.has_obligations()
        {
            return Err(crate::thread_assembler::ThreadAssemblyError::Unpublished(
                id.into(),
            ));
        }
        scopes.insert(id.into(), Arc::downgrade(scope));
        Ok(())
    }

    pub(crate) fn resource_scopes(&self) -> Vec<Arc<crate::session::NativeResources>> {
        let mut scopes = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        scopes.retain(|_, scope| scope.strong_count() > 0);
        scopes
            .values()
            .filter_map(std::sync::Weak::upgrade)
            .collect()
    }

    /// Fresh allowance for each child Turn, including explicit continuation after a step limit.
    pub(crate) const CHILD_MODEL_STEP_LIMIT: pl_core::thread::ModelStepLimit =
        pl_core::thread::ModelStepLimit::Limited(
            std::num::NonZeroU32::new(256).expect("positive child step limit"),
        );

    pub(in crate::studio) fn new(services: StudioThreadServices) -> Self {
        Self {
            services,
            lsp_binding_updates: Arc::new(tokio::sync::Notify::new()),
            scopes: Default::default(),
            initial_routes: Default::default(),
        }
    }

    pub(crate) fn lsp_binding_updates(&self) -> Arc<tokio::sync::Notify> {
        self.lsp_binding_updates.clone()
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

    /// Resolves the directory owner's committed identity before assembly allocates resources.
    pub(crate) fn activation(
        &self,
        thread_id: &str,
    ) -> Result<
        crate::thread_assembler::ThreadActivation,
        crate::thread_assembler::ThreadAssemblyError,
    > {
        let (agent, binding, parent_thread_id) = self
            .services
            .product_events
            .agent_execution_identity(thread_id)
            .ok_or_else(|| {
                crate::thread_assembler::ThreadAssemblyError::Identity(thread_id.to_owned())
            })?;
        if matches!(&binding, pl_protocol::AgentBinding::Acp(_)) {
            return Err(
                crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend {
                    backend: pl_protocol::AgentBackendKind::Acp,
                },
            );
        }
        Ok(crate::thread_assembler::ThreadActivation {
            agent,
            parent_thread_id,
            binding,
        })
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
        if request.identity.parent_thread_id.is_some() {
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
        if let Some(record) = self
            .services
            .product_events
            .thread_snapshot(id)
            .map_err(|error| errors::resource_error("read Native association", error))?
        {
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
    ) -> Result<crate::studio::WorkspaceRecord, crate::thread_assembler::ThreadAssemblyError> {
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
