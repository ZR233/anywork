//! Event-driven catalog replacement preserves the active owner and physical process leases.
use super::{
    StudioRuntime,
    background_task::{self, BackgroundTask},
};
use crate::protocol::StudioProductEventKind;
use crate::studio::model_binding::{NativeBundleOwner, NativeModelConfiguration};
use pl_core::thread::{ThreadError, ThreadHandle, ThreadLifecycle, task::TaskStatus};
use std::collections::BTreeMap;

#[derive(Clone, Default)]
struct CatalogSources(BTreeMap<String, String>);
impl CatalogSources {
    fn for_project(
        &self,
        project: Option<&crate::studio::WorkspaceRecord>,
        thread_id: &str,
    ) -> Self {
        let key = project
            .and_then(|project| project.ssh_alias.as_ref())
            .map(|server| format!("ssh-ready:{server}"));
        let mcp_ssh_key = project
            .and_then(|project| project.ssh_alias.as_ref())
            .map(|server| format!("mcp-catalog:ssh:{server}"));
        let thread_mcp_key = format!("thread-mcp:{thread_id}");
        let skill_key = project.map(|project| format!("skills:{}", project.id));
        let project_key = project.map(|project| format!("project:{}", project.id));
        Self(
            self.0
                .iter()
                .filter(|(name, _)| {
                    if name.starts_with("ssh-ready:") {
                        key.as_ref() == Some(name)
                    } else if name.starts_with("mcp-catalog:ssh:") {
                        mcp_ssh_key.as_ref() == Some(name)
                    } else if name.starts_with("thread-mcp:") {
                        *name == &thread_mcp_key
                    } else if name.starts_with("skills:") {
                        skill_key.as_ref() == Some(name)
                    } else if name.starts_with("project:") {
                        project_key.as_ref() == Some(name)
                    } else {
                        true
                    }
                })
                .map(|(name, value)| (name.clone(), value.clone()))
                .collect(),
        )
    }

    fn observe(&mut self, event: StudioProductEventKind) {
        let entry = match event {
            StudioProductEventKind::ProjectDirectoryChanged(value) => {
                self.0.retain(|key, _| !key.starts_with("project:"));
                if let Some(data) = value.state.value() {
                    for project in &data.projects {
                        self.0.insert(
                            format!("project:{}", project.id),
                            crate::hash::canonical_json_hash(&serde_json::json!((
                                &project.path,
                                &project.ssh_alias
                            ))),
                        );
                    }
                }
                None
            }
            StudioProductEventKind::SkillsStateChanged(value) => Some((
                format!("skills:{}", value.workspace_id),
                serde_json::json!(
                    (value
                        .state
                        .value()
                        .map(|data| (&data.config_fingerprint, data.catalog_revision)))
                ),
            )),
            StudioProductEventKind::LspStateChanged(value) => Some((
                "lsp".into(),
                serde_json::json!(value.state.value().map(|data| {
                    data.lsp_servers
                        .iter()
                        .map(|server| {
                            (
                                &server.id,
                                &server.extensions,
                                &server.language_ids,
                                &server.phase,
                            )
                        })
                        .collect::<Vec<_>>()
                })),
            )),
            StudioProductEventKind::ThreadModeCatalogChanged(value) => {
                Some(("modes".into(), serde_json::json!(value)))
            }
            StudioProductEventKind::ModelCatalogStateChanged(value) => Some((
                "model-catalogs".into(),
                model_catalog_witness(value.as_ref()),
            )),
            StudioProductEventKind::McpCatalogChanged(value) => {
                let key = match &value.scope {
                    crate::McpScope::Host => "mcp-catalog:host".to_owned(),
                    crate::McpScope::Ssh { ssh_alias } => {
                        format!("mcp-catalog:ssh:{ssh_alias}")
                    }
                };
                Some((key, serde_json::json!(value.revision)))
            }
            StudioProductEventKind::ThreadMcpStateChanged(value) => Some((
                format!("thread-mcp:{}", value.thread_id),
                serde_json::json!(value.generation),
            )),
            StudioProductEventKind::ThreadLspStateChanged(value) => Some((
                format!("thread-lsp:{}", value.thread_id),
                serde_json::json!(value.revision),
            )),
            StudioProductEventKind::ThreadDirectoryChanged(_)
            | StudioProductEventKind::AgentDirectoryChanged(_)
            | StudioProductEventKind::SettingsConfigStateChanged(_)
            | StudioProductEventKind::RecoveryStateChanged(_)
            | StudioProductEventKind::AccountUsageStateChanged(_)
            | StudioProductEventKind::ModelPerformanceStateChanged(_)
            | StudioProductEventKind::SessionCostsChanged(_)
            | StudioProductEventKind::UpdaterStateChanged(_)
            | StudioProductEventKind::PersistenceStateChanged(_)
            | StudioProductEventKind::PersistenceQueueStateChanged(_)
            | StudioProductEventKind::AgentProfilesStateChanged(_)
            | StudioProductEventKind::AcpAuthStateChanged(_)
            | StudioProductEventKind::AcpInstallStateChanged(_)
            | StudioProductEventKind::AcpLocalDetectionStateChanged(_)
            | StudioProductEventKind::BotsStateChanged(_)
            | StudioProductEventKind::ChildInteractionsChanged(_) => None,
        };
        if let Some((key, value)) = entry {
            self.0.insert(key, crate::hash::canonical_json_hash(&value));
        }
    }
}

/// Secret-free identity of one published model directory observation.
///
/// The witness carries only directory facts that can change tool availability: account ids, the
/// effective chat catalog slugs and whether the inventory behind them was replaced. Service-only
/// slugs stay out of the effective chat catalog, so the inventory success watermark is what moves
/// when a new observation replaces the cached one. Probe progress, status timestamps and failure
/// text are excluded: they change without changing any installed tool, and a published directory
/// that is unchanged must not replan the catalog again. No endpoint, header or credential enters
/// the witness.
fn model_catalog_witness(
    value: &crate::protocol::StudioModelCatalogStateSnapshot,
) -> serde_json::Value {
    let accounts = value.state.value().map(|snapshot| {
        snapshot
            .accounts
            .iter()
            .map(|account| {
                let mut models = account
                    .effective_models
                    .iter()
                    .map(|model| model.model_id.as_str())
                    .collect::<Vec<_>>();
                models.sort_unstable();
                let facts = serde_json::json!({
                    "models": models,
                    "supported": account.model_catalog.supported,
                    "source": account.model_catalog.source,
                    "inventorySuccessAt": account.model_catalog.last_success_at,
                });
                (account.account_id.clone(), facts)
            })
            .collect::<BTreeMap<_, _>>()
    });
    serde_json::json!({ "accounts": accounts })
}

impl StudioRuntime {
    pub(super) async fn start_tool_refresh(&self) {
        let mut slot = self.tool_refresh.lock().await;
        if slot.as_ref().is_some_and(|task| !task.is_finished()) {
            return;
        }
        let stopping = self.rejected_tools.start();
        let mut settings = self.settings_updates.subscribe();
        let mut profiles = self.config_runtime.subscribe_agent_profiles();
        let mut events = self.agent_facility.product_events.subscribe_internal();
        let mut ssh_ready = self.ssh_manager.subscribe_ready();
        let runtime = self.clone();
        *slot = Some(BackgroundTask::new(tokio::spawn(async move {
            let mut sources = CatalogSources::default();
            let mut workers: BTreeMap<
                String,
                (ThreadHandle, tokio::sync::watch::Sender<CatalogSources>),
            > = BTreeMap::new();
            let mut tasks = tokio::task::JoinSet::new();
            loop {
                if stopping.is_cancelled() {
                    break;
                }
                sources.0.insert(
                    "settings".into(),
                    settings.borrow_and_update().revision.to_string(),
                );
                profiles.borrow_and_update();
                let profile_generation = match runtime.config_runtime.agent_profiles_snapshot() {
                    Ok(snapshot) => snapshot.revision.to_string(),
                    Err(error) => format!("unavailable:{error}"),
                };
                sources
                    .0
                    .insert("agent-profiles".into(), profile_generation);
                for (server, revision) in ssh_ready.borrow_and_update().iter() {
                    sources
                        .0
                        .insert(format!("ssh-ready:{server}"), revision.to_string());
                }
                let active = runtime
                    .sessions
                    .observed_threads()
                    .into_iter()
                    .filter(|(id, thread)| {
                        runtime
                            .session_of(id)
                            .and_then(|session| session.thread(id))
                            .is_some_and(|current| current.same_instance(thread))
                    })
                    .collect::<Vec<_>>();
                workers.retain(|id, (owner, _)| {
                    active.iter().any(|(current_id, current)| {
                        current_id == id && current.same_instance(owner)
                    })
                });
                for (id, thread) in active {
                    let project = runtime.thread_factory.tool_project(&id);
                    let selected = sources.for_project(project.as_ref(), &id);
                    if let Some((_, updates)) = workers.get(&id) {
                        updates.send_if_modified(|previous| {
                            if previous.0 == selected.0 {
                                return false;
                            }
                            *previous = selected;
                            true
                        });
                        continue;
                    }
                    let (updates, mut receiver) = tokio::sync::watch::channel(selected);
                    workers.insert(id.clone(), (thread.clone(), updates));
                    let runtime = runtime.clone();
                    let stopping = stopping.clone();
                    tasks.spawn(async move {
                        let Ok((_, lifetime)) = runtime.thread_factory.tool_operation(&id) else {
                            return;
                        };
                        let mut snapshots = thread.subscribe();
                        let mut attempted = BTreeMap::new();
                        loop {
                            if stopping.is_cancelled() || lifetime.is_cancelled() {
                                break;
                            }
                            let sources = receiver.borrow_and_update().clone();
                            let cleanup_was_pending = thread.snapshot().tool_cleanup.pending > 0;
                            runtime
                                .refresh_selected_catalogs(
                                    &sources,
                                    &mut attempted,
                                    vec![(id.clone(), thread.clone())],
                                    &stopping,
                                    &receiver,
                                )
                                .await;
                            if cleanup_was_pending && thread.snapshot().tool_cleanup.pending == 0 {
                                continue;
                            }
                            tokio::select! {
                                () = stopping.cancelled() => break,
                                () = lifetime.cancelled() => break,
                                changed = receiver.changed() => if changed.is_err() { break; },
                                // Command writes do not pass through the file backend's LSP
                                // notification. Observe their deliveries even without pending
                                // cleanup; the fingerprint below filters unrelated snapshots.
                                snapshot = snapshots.next() => if snapshot.is_none() { break; },
                            }
                        }
                    });
                }
                tokio::select! {
                    () = stopping.cancelled() => break,
                    finished = tasks.join_next(), if !tasks.is_empty() => {
                        if let Some(Err(error)) = finished { tracing::error!(%error, "tool refresh worker failed"); }
                        workers.retain(|_, (_, updates)| !updates.is_closed());
                    },
                    () = runtime.tool_catalog_updates.notified() => {
                        let revision = sources.0.get("refresh").and_then(|value| value.parse::<u64>().ok()).unwrap_or_default().saturating_add(1);
                        sources.0.insert("refresh".into(), revision.to_string());
                    },
                    changed = settings.changed() => if changed.is_err() { break; },
                    changed = profiles.changed() => if changed.is_err() { break; },
                    changed = ssh_ready.changed() => if changed.is_err() { break; },
                    event = events.recv() => match event {
                        Ok(event) => sources.observe(event.kind),
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => { sources.0.insert("lag".into(), runtime.agent_facility.product_events.current_sequence().to_string()); },
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                    },
                }
            }
            drop(workers);
            while let Some(result) = tasks.join_next().await {
                if let Err(error) = result {
                    tracing::error!(%error, "tool refresh worker failed during shutdown");
                }
            }
        })));
    }

    async fn refresh_selected_catalogs(
        &self,
        sources: &CatalogSources,
        attempted: &mut BTreeMap<String, (ThreadHandle, String)>,
        active: Vec<(String, ThreadHandle)>,
        stopping: &tokio_util::sync::CancellationToken,
        latest: &tokio::sync::watch::Receiver<CatalogSources>,
    ) {
        let ids: std::collections::BTreeSet<_> = active.iter().map(|(id, _)| id.clone()).collect();
        attempted.retain(|id, _| ids.contains(id));
        for (id, thread) in active {
            let Some(resources_scope) = self
                .session_of(&id)
                .and_then(|session| session.native_resources(&thread).ok())
            else {
                continue;
            };
            let Ok((gate, cancellation)) = self.thread_factory.tool_operation(&id) else {
                continue;
            };
            let _installation = tokio::select! {
                biased;
                () = stopping.cancelled() => continue,
                () = cancellation.cancelled() => continue,
                guard = gate.lock_owned() => guard,
            };
            tracing::debug!(target: "thread_preparation", thread_id = %id, stage = "catalog_refresh", "starting");
            let cleanup = tokio::time::timeout(
                std::time::Duration::from_secs(5),
                self.rejected_tools.retry(Some(&thread)),
            )
            .await;
            if !matches!(cleanup, Ok(Ok(()))) {
                tracing::warn!(thread_id = %id, error = ?cleanup, "candidate cleanup remains pending");
                continue;
            }
            let snapshot = thread.snapshot();
            let authority_invalidated = match self.thread_factory.tool_authority_invalidated(&id) {
                Ok(invalidated) => invalidated,
                Err(error) => {
                    self.publish_tool_refresh_result(&id, &thread, Some(&error));
                    continue;
                }
            };
            if authority_invalidated
                && let Some(binding) = self.thread_factory.binding_snapshot(&id)
            {
                self.thread_factory.revoke_tool_binding(&id, &binding);
            }
            if snapshot.tool_cleanup.pending > 0 && !authority_invalidated {
                continue;
            }
            if snapshot.lifecycle != ThreadLifecycle::Open {
                continue;
            }
            let project = self.thread_factory.tool_project(&id);
            let fingerprint =
                catalog_fingerprint(&sources.for_project(project.as_ref(), &id), &snapshot);
            if attempted.get(&id).is_some_and(|(previous, key)| {
                previous.same_instance(&thread) && key == &fingerprint
            }) {
                continue;
            }
            let attempt = cancellation.child_token();
            let result = {
                let desired = sources.clone();
                let latest_revision = latest.clone();
                let preparation = async {
                    let session = self.require_session(&id)?;
                    let configuration =
                        NativeModelConfiguration::resolve(&self.config_runtime, &snapshot)?;
                    let identity = format!("{}:{fingerprint}", configuration.desired()).into();
                    configuration
                        .prepare_bundle(
                            NativeBundleOwner {
                                id: &id,
                                session: &session,
                                factory: &self.thread_factory,
                                config: &self.config_runtime,
                                thread: &thread,
                                snapshot: &snapshot,
                            },
                            attempt.clone(),
                            identity,
                            move || latest_revision.borrow().0 == desired.0,
                        )
                        .await
                };
                tokio::pin!(preparation);
                let mut changes = latest.clone();
                tokio::select! {
                    result = &mut preparation => result,
                    _ = changes.changed() => {
                        attempt.cancel();
                        preparation.await
                    },
                    () = stopping.cancelled() => {
                        attempt.cancel();
                        preparation.await
                    },
                }
            };
            // Release the producer permit after handing off the candidate. The old package
            // remains available for input, including write_stdin, while Core defers its swap.
            let transfer = match result {
                Ok(candidate) => {
                    resources_scope
                        .candidates
                        .stage_runtime_bundle(thread.clone(), candidate)
                        .await
                }
                Err(error) => Err(error),
            };
            drop(_installation);
            let result = match transfer {
                Ok(receipt) => {
                    let mut changed = latest.clone();
                    tokio::select! {
                        biased;
                        () = stopping.cancelled() => continue,
                        () = cancellation.cancelled() => continue,
                        _ = changed.changed() => continue,
                        result = receipt.installed() => result.map(|_| ()).map_err(anyhow::Error::new),
                    }
                }
                Err(error) => Err(error),
            };
            if let Err(error) = &result
                && error.chain().any(|cause| {
                    let error = cause.downcast_ref::<ThreadError>().or_else(|| {
                        cause
                            .downcast_ref::<std::sync::Arc<ThreadError>>()
                            .map(std::sync::Arc::as_ref)
                    });
                    matches!(
                        error,
                        Some(ThreadError::StaleRuntimeBundle | ThreadError::ContextConflict { .. })
                    )
                })
            {
                // A fresher snapshot or source superseded the candidate after preparation.
                // Its resources remain under the original installation owner's cleanup.
                continue;
            }
            if result.is_ok() {
                self.thread_factory.notify_lsp_binding_changed();
                tracing::debug!(target: "thread_preparation", thread_id = id, stage = "catalog_install", "completed");
            }
            // Cache attempts, including failures, until an input revision changes.
            // Recovery issues remain visible; only successful transfer commits a binding.
            if stopping.is_cancelled()
                || cancellation.is_cancelled()
                || sources.0 != latest.borrow().0
                || thread.snapshot().lifecycle != ThreadLifecycle::Open
            {
                continue;
            }
            attempted.insert(id.clone(), (thread.clone(), fingerprint));
            self.publish_tool_refresh_result(&id, &thread, result.as_ref().err());
        }
    }

    pub(in crate::studio::runtime) fn publish_tool_refresh_result(
        &self,
        id: &str,
        thread: &ThreadHandle,
        error: Option<&anyhow::Error>,
    ) {
        let issue_id = format!("tool-refresh:{id}");
        let issue = error.map(|error| crate::studio::StudioRecoveryIssue {
            id: issue_id.clone(),
            scope: crate::studio::StudioRecoveryIssueScope::Thread,
            category: crate::studio::StudioRecoveryIssueCategory::ToolCatalog,
            impact: crate::studio::StudioRecoveryImpact::Advisory,
            action: crate::studio::StudioRecoveryIssueAction::Retry,
            workspace_id: None,
            thread_id: Some(id.to_string()),
            worktree: None,
            message: format!("Tool catalog refresh failed: {error:#}"),
        });
        self.recovery.update_if_current(
            &issue_id,
            issue,
            || {
                self.session_of(id)
                    .and_then(|session| session.thread(id))
                    .is_some_and(|current| {
                        current.same_instance(thread)
                            && current.snapshot().lifecycle == ThreadLifecycle::Open
                    })
            },
            |issues| {
                self.agent_facility
                    .product_events
                    .emit_recovery_state(issues);
            },
        );
    }

    pub(super) async fn stop_tool_refresh(&self) -> anyhow::Result<()> {
        self.rejected_tools.stop();
        self.thread_factory.stop_all_tool_operations();
        background_task::finish(&self.tool_refresh)
            .await
            .map_err(anyhow::Error::new)?;
        self.rejected_tools.retry(None).await
    }
}

fn catalog_fingerprint(
    sources: &CatalogSources,
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> String {
    // Completed deliveries are handed to history before snapshots are published.
    // Their bounded terminal task identities remain observable without retaining
    // tool output bodies or depending on an intermediate snapshot.
    let mutation = snapshot
        .terminal_tasks
        .iter()
        .rev()
        .find(|task| task.tool_id == "skill_manage" && task.status == TaskStatus::Succeeded)
        .map(|task| &task.call_id);
    // Commands can write configuration without going through the filesystem backend.
    // Their completed delivery is a safe opportunity to re-scan the bound workspace;
    // unchanged content does not restart a language server.
    let workspace_mutation = snapshot
        .terminal_tasks
        .iter()
        .rev()
        .find(|task| {
            matches!(
                task.tool_id.as_str(),
                "exec_command"
                    | "write_stdin"
                    | "write_file"
                    | "apply_patch"
                    | "copy_path"
                    | "move_path"
                    | "delete_path"
            )
        })
        .map(|task| &task.call_id);
    crate::hash::canonical_json_hash(&serde_json::json!({
        "sources": sources.0,
        "skillMutation": mutation,
        "workspaceMutation": workspace_mutation,
        "mode": snapshot.extensions.get("studio.mode"),
        "modelRoute": snapshot.extensions.get(crate::studio::model_route::MODEL_ROUTE_EXTENSION),
        "agentProfile": snapshot.extensions.get(crate::studio::model_route::AGENT_PROFILE_EXTENSION),
    }))
}
