use std::{path::Path, sync::Arc};

use anyhow::Result;
use pl_tool::workspace::resolve_workspace_root;

use super::super::StudioRuntime;
use super::state::{LspOperation, execution_endpoint, health};

impl StudioRuntime {
    pub async fn read_lsp_state(&self) -> crate::StudioLspStateSnapshot {
        self.external_runtimes.lsp_state.read().await
    }

    /// Reads the already-published LSP association projection for a known Thread.
    pub async fn read_thread_lsp_state(
        &self,
        thread_id: &str,
    ) -> Result<crate::protocol::StudioThreadLspStateSnapshot> {
        self.read_protocol_thread(thread_id).await?;
        Ok(self.external_runtimes.lsp_state.read_thread(thread_id))
    }

    /// Resets one server through the current Thread binding and returns its new published cut.
    pub async fn reset_thread_lsp_server(
        &self,
        request: crate::ThreadLspResetRequest,
    ) -> Result<crate::protocol::StudioThreadLspStateSnapshot> {
        self.read_protocol_thread(&request.thread_id).await?;
        let stale = || {
            anyhow::Error::new(
                crate::StudioError::new(
                    crate::StudioErrorCode::Conflict,
                    "The Thread LSP binding is no longer current",
                    false,
                )
                .with_reason(
                    crate::StudioErrorReason::StaleLspBinding,
                    serde_json::json!({}),
                ),
            )
        };
        let (gate, cancellation) = match self.thread_factory.tool_operation(&request.thread_id) {
            Ok(operation) => operation,
            Err(crate::thread_assembler::ThreadAssemblyError::Thread(
                pl_core::thread::ThreadError::Closed,
            )) => return Err(stale()),
            Err(error) => return Err(anyhow::Error::from(error)),
        };
        let _operation = tokio::select! {
            biased;
            () = cancellation.cancelled() => return Err(stale()),
            guard = gate.lock() => guard,
        };
        let binding = self
            .thread_factory
            .binding_snapshot(&request.thread_id)
            .ok_or_else(stale)?;
        let lease = binding
            .lsp_lease
            .as_ref()
            .filter(|lease| !lease.is_closed());
        if !Arc::ptr_eq(&gate, &binding.lifetime.gate)
            || binding.lifetime.target_invalidated()
            || !binding.authorization.is_active()
            || binding.lifetime.cancellation.is_cancelled()
            || binding.lsp_binding_id.as_deref() != Some(&request.binding_id)
            || lease.is_none()
        {
            return Err(stale());
        }
        let lease = lease.expect("checked active lease");
        let endpoint = execution_endpoint(binding.project.ssh_alias.as_deref());
        let registry = self.external_runtimes.lsp.execution_scope(&endpoint);
        let root = lease.workspace_root().to_path_buf();
        let members = registry.snapshots_for_workspace(&root).await;
        if cancellation.is_cancelled()
            || self
                .thread_factory
                .binding_snapshot(&request.thread_id)
                .is_none_or(|current| {
                    !Arc::ptr_eq(&current.incarnation, &binding.incarnation)
                        || current.lsp_binding_id.as_deref() != Some(&request.binding_id)
                        || current.lifetime.target_invalidated()
                        || !current.authorization.is_active()
                        || current.lifetime.cancellation.is_cancelled()
                        || current
                            .lsp_lease
                            .as_ref()
                            .is_none_or(pl_lsp::runtime::LspWorkspaceLease::is_closed)
                })
        {
            return Err(stale());
        }
        if !members.iter().any(|server| server.id == request.server_id) {
            return Err(anyhow::Error::new(crate::StudioError::not_found(
                "LSP server",
            )));
        }
        registry
            .reset_lsp(pl_lsp::runtime::LspScope::Server {
                workspace_root: root,
                server_id: request.server_id,
            })
            .await?;
        self.refresh_thread_lsp_states().await;
        Ok(self
            .external_runtimes
            .lsp_state
            .read_thread(&request.thread_id))
    }

    pub async fn probe_lsp_server(&self, workspace_id: &str) -> Result<()> {
        let project = self.project_record(workspace_id).await?;
        let lsp = self
            .external_runtimes
            .lsp
            .execution_scope(&execution_endpoint(project.ssh_alias.as_deref()));
        let (workspace_root, host, defaults) = if let Some(alias) = &project.ssh_alias {
            let host = self
                .ssh_manager
                .open_workspace_binding(alias, project.path.clone())
                .await?;
            (
                std::path::PathBuf::from(host.files().canonical_path()),
                Some(Arc::new(pl_lsp::host::ExecutorLspHost::new(
                    host.files().executor().clone(),
                    host.files().canonical_path(),
                )?) as Arc<dyn pl_lsp::host::LspHostBackend>),
                None,
            )
        } else {
            let root = resolve_workspace_root(Path::new(&project.path))?;
            let host = self.local_lsp_host(&root);
            (root, host, Some(self.store.paths().home().join("lsp/host")))
        };
        let _command = self.external_runtimes.lsp_state.command().await;
        self.external_runtimes
            .lsp_state
            .begin(LspOperation::Probe)
            .await?;
        let result = async {
            let lease = lsp
                .acquire_workspace(&workspace_root, host, defaults)
                .await?;
            lsp.retry_workspace_configuration(&workspace_root).await;
            let initialized = lease.wait_initialized().await;
            let closed = lease.close().await;
            initialized?;
            closed
        }
        .await;
        if let Err(error) = result {
            let error = anyhow::Error::from(error);
            self.external_runtimes.lsp_state.failed(&error).await?;
            return Err(error);
        }
        let health = health(
            &self.external_runtimes.lsp,
            self.read_lsp_state().await.state.value(),
        )
        .await;
        self.external_runtimes.lsp_state.ready(health, true).await?;
        Ok(())
    }

    async fn reset_lsp(
        &self,
        lsp: pl_lsp::runtime::LspRuntimeRegistry,
        scope: pl_lsp::runtime::LspScope,
    ) -> Result<()> {
        let _command = self.external_runtimes.lsp_state.command().await;
        self.external_runtimes
            .lsp_state
            .begin(LspOperation::Reset)
            .await?;
        let result = lsp.reset_lsp(scope).await.map_err(anyhow::Error::from);
        match result {
            Ok(()) => {
                let health = health(
                    &self.external_runtimes.lsp,
                    self.read_lsp_state().await.state.value(),
                )
                .await;
                self.external_runtimes
                    .lsp_state
                    .ready(health, false)
                    .await?;
                Ok(())
            }
            Err(error) => {
                self.external_runtimes.lsp_state.failed(&error).await?;
                Err(error)
            }
        }
    }

    /// Resolves transport-neutral Project identities into an internal LSP reset scope.
    pub async fn reset_lsp_request(&self, request: crate::LspResetRequest) -> Result<()> {
        use crate::LspResetRequest;
        use pl_lsp::runtime::LspScope;

        let Some(workspace_id) = (match &request {
            LspResetRequest::Server { workspace_id, .. }
            | LspResetRequest::Workspace { workspace_id } => Some(workspace_id),
            LspResetRequest::All => None,
        }) else {
            self.reset_lsp(self.external_runtimes.lsp.clone(), LspScope::All)
                .await?;
            self.refresh_thread_lsp_states().await;
            return Ok(());
        };
        let project = self.project_record(workspace_id).await?;
        let endpoint = execution_endpoint(project.ssh_alias.as_deref());
        let workspace_root = if project.ssh_alias.is_some() {
            std::path::PathBuf::from(project.path)
        } else {
            resolve_workspace_root(Path::new(&project.path))?
        };
        let scope = match request {
            LspResetRequest::Server { server_id, .. } => LspScope::Server {
                workspace_root,
                server_id,
            },
            LspResetRequest::Workspace { .. } => LspScope::Workspace { workspace_root },
            LspResetRequest::All => unreachable!("All is resolved without a workspace"),
        };
        self.reset_lsp(self.external_runtimes.lsp.execution_scope(&endpoint), scope)
            .await?;
        self.refresh_thread_lsp_states().await;
        Ok(())
    }

    fn local_lsp_host(&self, root: &Path) -> Option<Arc<dyn pl_lsp::host::LspHostBackend>> {
        let root = root.to_str()?;
        pl_lsp::host::ExecutorLspHost::new(self.thread_factory.local_executor(), root)
            .map(|host| Arc::new(host) as Arc<dyn pl_lsp::host::LspHostBackend>)
            .map_err(|error| tracing::warn!(%error, "LSP host preparation failed"))
            .ok()
    }
}
