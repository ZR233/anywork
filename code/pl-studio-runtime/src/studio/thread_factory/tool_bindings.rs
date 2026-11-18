//! Frozen physical targets and weak command leases for one active Thread incarnation.
use super::{
    StudioThreadFactory,
    errors::resource_error,
    thread_tools::{CatalogPreparation, ThreadToolAssembly},
};
use crate::{
    studio::WorkspaceRecord,
    thread_assembler::{StudioThreadTools, ThreadAssemblyError, WeakCommandProcesses},
};
use pl_core::thread::ThreadSnapshot;
use pl_tool::workspace::ToolWorkspace;

#[derive(Clone)]
pub(crate) struct ToolBinding {
    pub assignment: Option<crate::AgentWorkspaceAssignmentSnapshot>,
    pub workspace_usage: crate::studio::agent_host::worktree_lease::WeakWorkspaceUsageLease,
    pub lifetime: std::sync::Arc<ThreadToolLifetime>,
    pub incarnation: std::sync::Arc<()>,
    pub authorization: pl_core::tool::opaque::ToolAuthorization,
    pub catalog: Option<std::sync::Arc<pl_tool::skill::FrozenSkillCatalog>>,
    pub initial_skill_prompt: String,
    pub policy_key: String,
    pub permission_mode: crate::approval::PermissionMode,
    pub policies:
        std::collections::BTreeMap<String, pl_core::tool::execution_policy::ExecutionPolicyHandle>,
    pub project: WorkspaceRecord,
    pub workspace: ToolWorkspace,
    pub commands: Option<WeakCommandProcesses>,
    pub remote: Option<pl_tool::remote::SshWorkspaceBinding>,
    pub lsp_lease: Option<pl_lsp::runtime::LspWorkspaceLease>,
    pub lsp_binding_id: Option<String>,
    pub ssh_profile: Option<pl_tool::remote::SshServerProfile>,
}

pub(crate) struct ThreadToolLifetime {
    pub(crate) gate: std::sync::Arc<tokio::sync::Mutex<()>>,
    pub(crate) cancellation: tokio_util::sync::CancellationToken,
    qualification_gate: std::sync::Mutex<()>,
    target_invalidated: std::sync::atomic::AtomicBool,
    lsp_binding_updates: std::sync::Arc<tokio::sync::Notify>,
}

impl ThreadToolLifetime {
    pub(crate) fn new(lsp_binding_updates: std::sync::Arc<tokio::sync::Notify>) -> Self {
        Self {
            gate: std::sync::Arc::new(tokio::sync::Mutex::new(())),
            cancellation: tokio_util::sync::CancellationToken::new(),
            qualification_gate: std::sync::Mutex::new(()),
            target_invalidated: std::sync::atomic::AtomicBool::new(false),
            lsp_binding_updates,
        }
    }

    pub(crate) fn cancel(&self) {
        let _qualification = self
            .qualification_gate
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.cancellation.cancel();
        self.lsp_binding_updates.notify_one();
    }

    pub(crate) fn target_invalidated(&self) -> bool {
        self.target_invalidated
            .load(std::sync::atomic::Ordering::Acquire)
    }

    fn invalidate_target(&self) {
        self.target_invalidated
            .store(true, std::sync::atomic::Ordering::Release);
        self.cancel();
    }

    pub(crate) fn qualification_guard(&self) -> std::sync::MutexGuard<'_, ()> {
        self.qualification_gate
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }
}

#[cfg(test)]
impl Default for ThreadToolLifetime {
    fn default() -> Self {
        Self::new(std::sync::Arc::new(tokio::sync::Notify::new()))
    }
}

struct PermissionModeObserver {
    scopes: std::sync::Weak<super::NativeResourceScopes>,
}

impl crate::config::SettingsCommitObserver for PermissionModeObserver {
    fn settings_committed(&self, settings: &crate::ConfigRuntimeSnapshot) {
        let Some(scopes) = self.scopes.upgrade() else {
            return;
        };
        let scopes = scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .filter_map(std::sync::Weak::upgrade)
            .collect::<Vec<_>>();
        let permission_mode = settings.config.runtime.permission_mode;
        for scope in scopes {
            let changed = scope.with_binding(|binding| {
                binding.is_some_and(|binding| {
                    if binding.permission_mode == permission_mode
                        || !binding.authorization.is_active()
                    {
                        return false;
                    }
                    binding.authorization.revoke();
                    true
                })
            });
            if changed {
                scope.authorization_changed();
            }
        }
    }
}

impl StudioThreadFactory {
    pub(crate) fn observe_permission_mode(&self) -> anyhow::Result<()> {
        self.services
            .config_runtime
            .install_settings_observer(std::sync::Arc::new(PermissionModeObserver {
                scopes: std::sync::Arc::downgrade(&self.scopes),
            }))?;
        Ok(())
    }

    pub(crate) fn binding_snapshots(&self) -> std::collections::BTreeMap<String, ToolBinding> {
        let scopes = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter_map(|(id, scope)| scope.upgrade().map(|scope| (id.clone(), scope)))
            .collect::<Vec<_>>();
        scopes
            .into_iter()
            .filter_map(|(id, scope)| scope.binding().map(|binding| (id, binding)))
            .collect()
    }

    pub(crate) fn binding_snapshot(&self, id: &str) -> Option<ToolBinding> {
        self.resource_scope(id)?.binding()
    }

    /// Reads the actual execution workspace from Core's current package.
    pub(super) fn actual_tool_workspace(
        &self,
        id: &str,
    ) -> Result<(ToolWorkspace, WorkspaceRecord), ThreadAssemblyError> {
        let binding = self
            .binding_snapshot(id)
            .ok_or(pl_core::thread::ThreadError::Closed)?;
        if binding.lifetime.cancellation.is_cancelled() || !binding.authorization.is_active() {
            return Err(ThreadAssemblyError::Closed);
        }
        Ok((binding.workspace, binding.project))
    }

    pub(crate) fn tool_operation(
        &self,
        id: &str,
    ) -> Result<
        (
            std::sync::Arc<tokio::sync::Mutex<()>>,
            tokio_util::sync::CancellationToken,
        ),
        ThreadAssemblyError,
    > {
        let binding = self
            .binding_snapshot(id)
            .ok_or(pl_core::thread::ThreadError::Closed)?;
        Ok((
            binding.lifetime.gate.clone(),
            binding.lifetime.cancellation.clone(),
        ))
    }

    pub(in crate::studio) fn tool_project(&self, id: &str) -> Option<WorkspaceRecord> {
        self.binding_snapshot(id)
            .as_ref()
            .map(|binding| binding.project.clone())
    }

    pub(crate) fn tool_authority_invalidated(&self, id: &str) -> anyhow::Result<bool> {
        let mode = self
            .services
            .config_runtime
            .read()?
            .config
            .runtime
            .permission_mode;
        Ok(self.binding_snapshot(id).is_some_and(|binding| {
            binding.permission_mode != mode || !binding.authorization.is_active()
        }))
    }

    pub(crate) fn revoke_tool_binding(&self, id: &str, binding: &ToolBinding) {
        binding.authorization.revoke();
        if let Some(scope) = self.resource_scope(id) {
            scope.authorization_changed();
        }
    }

    pub(crate) fn bundle_facts(
        binding: &ToolBinding,
        snapshot: &ThreadSnapshot,
    ) -> Vec<pl_core::thread::RuntimeFact> {
        let mut facts = Vec::new();
        if let Some(fact) = super::session_files::session_files_fact(&binding.workspace)
            && snapshot
                .runtime_facts
                .iter()
                .find(|current| current.source_id == fact.source_id)
                != Some(&fact)
        {
            facts.push(fact);
        }
        let prompt = binding
            .catalog
            .as_ref()
            .map(|catalog| pl_tool::skill::build_skills_prompt_from_catalog(catalog.snapshot()))
            .unwrap_or_default();
        if let Some(fact) = catalog_fact(prompt, &binding.initial_skill_prompt, snapshot) {
            facts.push(fact);
        }
        facts
    }

    pub(in crate::studio) fn skill_suggestions(
        &self,
        id: &str,
        query: &str,
        snapshot: &ThreadSnapshot,
    ) -> Option<String> {
        let catalog = self.binding_snapshot(id)?.catalog?;
        let loaded = snapshot
            .extensions
            .values()
            .filter_map(|record| pl_tool::skill::saved_skill_name(&record.payload).ok())
            .collect::<Vec<_>>();
        pl_tool::skill::build_skill_suggestions_from_catalog(catalog.snapshot(), query, &loaded)
    }

    pub(in crate::studio) fn invalidate_ssh_bindings(&self, server_id: &str) {
        for scope in self.resource_scopes() {
            if let Some(binding) = scope.binding()
                && binding.project.ssh_alias.as_deref() == Some(server_id)
            {
                binding.authorization.revoke();
                binding.lifetime.invalidate_target();
                scope.authorization_changed();
                if let Some(lease) = binding.lsp_lease {
                    drop(lease.close());
                }
            }
        }
    }

    pub(crate) async fn close_scope_tools(
        &self,
        id: &str,
        scope: &std::sync::Arc<crate::session::NativeResources>,
    ) -> anyhow::Result<()> {
        let lifetime =
            scope.with_binding(|binding| binding.map(|binding| binding.lifetime.clone()));
        if let Some(lifetime) = &lifetime {
            lifetime.cancel();
        }
        let _guard = match &lifetime {
            Some(lifetime) => Some(lifetime.gate.lock().await),
            None => None,
        };
        let lsp_lease =
            scope.with_binding(|binding| binding.and_then(|binding| binding.lsp_lease.clone()));
        let (mcp_result, lsp_result) = tokio::join!(self.shutdown_scope_mcp(scope), async {
            match lsp_lease {
                Some(lease) => lease.close().await.map_err(anyhow::Error::from),
                None => Ok(()),
            }
        });
        // Preserve the binding when either owner failed, so close can be retried.
        mcp_result?;
        lsp_result?;
        scope.release_binding();
        if lifetime.is_some() {
            self.notify_lsp_binding_changed();
        }
        if lifetime.is_some() && self.services.worktrees.get(id).is_none() {
            self.services
                .worktrees
                .release_stopped_runtime_resources(id);
        }
        Ok(())
    }
    pub(super) fn forget_tool_binding_if_current(
        &self,
        id: &str,
        lifetime: &std::sync::Arc<ThreadToolLifetime>,
    ) {
        if let Some(binding) = self.binding_snapshot(id)
            && std::sync::Arc::ptr_eq(&binding.lifetime, lifetime)
        {
            binding.lifetime.cancel();
            if let Some(lease) = &binding.lsp_lease {
                drop(lease.close());
            }
            self.notify_lsp_binding_changed();
        }
    }

    pub(in crate::studio) fn stop_all_tool_operations(&self) {
        for scope in self.resource_scopes() {
            if let Some(binding) = scope.binding() {
                binding.lifetime.cancel();
            }
        }
    }

    pub(crate) async fn refresh_thread_tools(
        &self,
        id: &str,
        snapshot: &ThreadSnapshot,
        config: &crate::StudioConfig,
        route: &pl_model::config::ResolvedModelRoute,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> Result<
        (
            StudioThreadTools,
            crate::thread_assembler::AgentControlExposure,
            ToolBinding,
        ),
        ThreadAssemblyError,
    > {
        let binding = self.binding_snapshot(id).ok_or_else(|| {
            ThreadAssemblyError::Identity(
                "Thread tool binding is unavailable; reactivate this Thread".into(),
            )
        })?;
        if binding.lifetime.target_invalidated() {
            return Err(ThreadAssemblyError::InvalidatedBinding(
                "SSH target or credentials changed; reactivate this Thread".into(),
            ));
        }
        let thread = self
            .services
            .product_events
            .thread_snapshot(id)
            .map_err(|error| super::errors::resource_error("read Native directory", error))?
            .map(crate::studio::ThreadRecord::from_directory_thread)
            .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?;
        let mut project = self
            .services
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == thread.workspace_id)
            .ok_or_else(|| {
                ThreadAssemblyError::InvalidatedBinding(
                    "project target disappeared; reactivate this Thread".into(),
                )
            })?;
        if let Some(bot) = self
            .services
            .bots
            .config_for_thread(&thread.root_thread_id)
            .await
            .map_err(|error| resource_error("read current bot owner", error))?
        {
            project.path = self
                .services
                .bots
                .workspace_root(&bot)
                .to_string_lossy()
                .into_owned();
            project.ssh_alias = None;
        }
        ensure_same_target(&binding.project, &project)?;
        ensure_frozen_ssh_profile(&self.services.ssh_manager, binding.ssh_profile.as_ref()).await?;
        let child = thread.parent_thread_id.is_some();
        let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)
            .map_err(|error| resource_error("decode workspace binding", error))?;
        if child {
            let (profile, _) = crate::studio::model_route::saved_profile(snapshot)
                .map_err(|error| resource_error("decode saved child Agent Profile", error))?
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity(
                        "child has no frozen Agent Profile; reactivate this Thread".into(),
                    )
                })?;
            if assignment
                .as_ref()
                .is_some_and(|assignment| assignment.mode != profile.workspace_mode)
            {
                return Err(ThreadAssemblyError::Identity(
                    "saved child Profile conflicts with its workspace assignment".into(),
                ));
            }
        }
        let resources = crate::resource_store::FileResourceStore::new(
            self.services
                .store
                .session_resources_dir_for(&thread.workspace_id, &thread.id)
                .map_err(|error| resource_error("resolve refreshed session resources", error))?,
        );
        let remote = match &project.ssh_alias {
            Some(server) => {
                // 身份比较在同一 POSIX 表示上进行：`canonical_path` 由远端 helper 返回
                // 恒为 POSIX，会话工作区根也必须归一化后比较，否则 Windows 宿主形态会被
                // 误判为「目标已改变」。
                let requested = pl_tool::remote::normalize_remote_absolute_path(
                    &binding.workspace.root().to_string_lossy(),
                )
                .map_err(|error| resource_error("normalize Thread remote workspace", error))?;
                let opening = self
                    .services
                    .ssh_manager
                    .open_workspace_binding(server, requested.clone());
                let host = tokio::select! {
                    biased;
                    _ = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Cancelled.into()),
                    result = opening => result.map_err(|error| resource_error("reopen Thread remote workspace", error))?,
                };
                if host.files().canonical_path() != requested.as_str() {
                    return Err(ThreadAssemblyError::InvalidatedBinding(
                        "remote workspace target changed; reactivate this Thread".into(),
                    ));
                }
                Some(host)
            }
            None => None,
        };
        let same_connection = match (&binding.remote, &remote) {
            (Some(previous), Some(current)) => {
                previous.execution.is_same_binding(&current.execution)
            }
            (None, None) => true,
            _ => false,
        };
        let policy_changed =
            binding.policy_key != super::thread_tools::approval_policy_key(config, route);
        if policy_changed || !same_connection {
            self.revoke_tool_binding(id, &binding);
        }
        let previous_commands = if binding.authorization.is_active() {
            binding.commands.clone()
        } else {
            None
        };
        let mut prepared = self
            .prepare_thread_tools_with(
                ThreadToolAssembly {
                    assignment: binding.assignment.as_ref(),
                    workspace_usage: binding
                        .workspace_usage
                        .upgrade()
                        .ok_or(pl_core::thread::ThreadError::Closed)?,
                    thread_id: id,
                    cancellation: &cancellation,
                    config,
                    route,
                    project: &project,
                    root_thread_id: &thread.root_thread_id,
                    workspace: binding.workspace.clone(),
                    store: resources,
                    helper_source: self.services.helper_source.clone(),
                },
                &binding.lifetime,
                CatalogPreparation::Refresh {
                    lsp_lease: binding.lsp_lease.clone(),
                    policy_key: binding.policy_key.clone(),
                    policies: binding.policies.clone(),
                    remote: remote.map(Box::new),
                    commands: previous_commands
                        .as_ref()
                        .and_then(WeakCommandProcesses::upgrade),
                },
            )
            .await
            .map_err(|error| {
                if policy_changed {
                    ThreadAssemblyError::InvalidatedBinding(format!(
                        "authorization policy changed; catalog preparation failed: {error:#}"
                    ))
                } else {
                    error
                }
            })?;
        if child {
            let (profile, _) = crate::studio::model_route::saved_profile(snapshot)
                .map_err(|error| resource_error("decode review role for tool refresh", error))?
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity("child has no frozen Profile".into())
                })?;
            if let Some(assignment) = &assignment {
                Self::configure_review_finish(&mut prepared.tools, id, &profile, assignment)?;
            }
        }
        let exposure = if child {
            crate::thread_assembler::AgentControlExposure::Disabled
        } else {
            crate::mode::saved_registered_mode(snapshot)
                .map_err(|error| resource_error("read Mode snapshot for tool refresh", error))?
                .ok_or_else(|| {
                    ThreadAssemblyError::Identity("current Mode snapshot is unavailable".into())
                })?;
            prepared.tools = prepared
                .tools
                .with_tools(crate::workflow_tool::workflow_registrations()?);
            crate::thread_assembler::AgentControlExposure::Enabled
        };
        let commands = prepared
            .tools
            .command_processes
            .as_ref()
            .map(|commands| commands.downgrade())
            .or(previous_commands);
        let next_lsp_lease = prepared.lsp_lease.clone();
        let next_lsp_binding_id = next_lsp_lease
            .as_ref()
            .filter(|lease| !lease.is_closed())
            .map(|lease| {
                let same_lease = binding.lsp_lease.as_ref().is_some_and(|previous| {
                    !previous.is_closed()
                        && previous.workspace_root() == lease.workspace_root()
                        && binding.project.ssh_alias == project.ssh_alias
                });
                if same_lease {
                    binding
                        .lsp_binding_id
                        .clone()
                        .unwrap_or_else(|| crate::studio::ids::new_id("lsp-binding"))
                } else {
                    crate::studio::ids::new_id("lsp-binding")
                }
            });
        let candidate = ToolBinding {
            lsp_lease: next_lsp_lease,
            lsp_binding_id: next_lsp_binding_id,
            incarnation: std::sync::Arc::new(()),
            authorization: if binding.authorization.is_active() {
                binding.authorization.clone()
            } else {
                pl_core::tool::opaque::ToolAuthorization::unique()
            },
            commands,
            remote: prepared.remote.clone(),
            catalog: prepared.catalog.clone(),
            policy_key: super::thread_tools::approval_policy_key(config, route),
            permission_mode: config.runtime.permission_mode,
            policies: prepared.tools.approval_policies.clone(),
            ..binding
        };
        Ok((prepared.tools, exposure, candidate))
    }
}

fn catalog_fact(
    prompt: String,
    initial: &str,
    snapshot: &ThreadSnapshot,
) -> Option<pl_core::thread::RuntimeFact> {
    let previous = snapshot
        .runtime_facts
        .iter()
        .find(|fact| fact.source_id == "studio.skills");
    if previous.is_none() && prompt == initial {
        return None;
    }
    let fact = pl_core::thread::RuntimeFact {
        source_id: "studio.skills".into(),
        content: if prompt.is_empty() {
            Vec::new()
        } else {
            vec![pl_core::context::ContextContent::Text {
                text: prompt.into(),
            }]
        },
    };
    (previous != Some(&fact)).then_some(fact)
}

pub(super) async fn ensure_frozen_ssh_profile(
    manager: &pl_tool::remote::SshManager,
    previous: Option<&pl_tool::remote::SshServerProfile>,
) -> Result<(), ThreadAssemblyError> {
    if let Some(previous) = previous {
        let current = manager
            .list_servers()
            .await
            .into_iter()
            .find(|entry| entry.profile.alias == previous.alias)
            .map(|entry| entry.profile);
        if current.as_ref() != Some(previous) {
            return Err(ThreadAssemblyError::InvalidatedBinding(
                "SSH target configuration changed; reactivate this Thread".into(),
            ));
        }
    }
    Ok(())
}

fn ensure_same_target(
    previous: &WorkspaceRecord,
    current: &WorkspaceRecord,
) -> Result<(), ThreadAssemblyError> {
    if previous.id != current.id
        || previous.path != current.path
        || previous.ssh_alias != current.ssh_alias
    {
        return Err(ThreadAssemblyError::InvalidatedBinding("physical workspace target changed; reactivate this Thread before accessing the new target".into()));
    }
    Ok(())
}
