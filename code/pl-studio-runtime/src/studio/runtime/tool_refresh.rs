//! Event-driven catalog replacement preserves the active owner and physical process leases.
use super::{
    StudioRuntime,
    background_task::{self, BackgroundTask},
};
use crate::protocol::StudioProductEventKind;
use anyhow::Context;
use pl_core::thread::{ThreadHandle, ThreadLifecycle, ToolOutcome};
use std::collections::BTreeMap;

#[derive(Clone, Default)]
struct CatalogSources(BTreeMap<String, String>);
impl CatalogSources {
    fn for_project(&self, project: Option<&crate::studio::ProjectRecord>) -> Self {
        let key = project
            .and_then(|project| project.ssh_alias.as_ref())
            .map(|server| format!("ssh-ready:{server}"));
        let skill_key = project.map(|project| format!("skills:{}", project.id));
        let project_key = project.map(|project| format!("project:{}", project.id));
        Self(
            self.0
                .iter()
                .filter(|(name, _)| {
                    if name.starts_with("ssh-ready:") {
                        key.as_ref() == Some(name)
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
                format!("skills:{}", value.project_id),
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
                        .map(|server| (&server.id, &server.extensions, &server.language_ids))
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
            StudioProductEventKind::ThreadDirectoryChanged(_)
            | StudioProductEventKind::AgentDirectoryChanged(_)
            | StudioProductEventKind::SettingsConfigStateChanged(_)
            | StudioProductEventKind::McpStateChanged(_)
            | StudioProductEventKind::AccountUsageStateChanged(_)
            | StudioProductEventKind::ModelPerformanceStateChanged(_)
            | StudioProductEventKind::SessionCostsChanged(_)
            | StudioProductEventKind::UpdaterStateChanged(_)
            | StudioProductEventKind::PersistenceStateChanged(_)
            | StudioProductEventKind::PersistenceQueueStateChanged(_)
            | StudioProductEventKind::AgentProfilesStateChanged(_)
            | StudioProductEventKind::AcpAuthStateChanged(_)
            | StudioProductEventKind::AcpInstallStateChanged(_)
            | StudioProductEventKind::BotsStateChanged(_) => None,
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
        let mut mcp = self.external_runtimes.mcp.subscribe();
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
            let mut mcp_changed = true;
            loop {
                if stopping.is_cancelled() {
                    break;
                }
                if mcp_changed {
                    let generation = match runtime.external_runtimes.mcp.acquire_turn_lease().await
                    {
                        Ok(lease) => lease.generation().0.to_string(),
                        Err(error) => format!("unavailable:{error}"),
                    };
                    sources.0.insert("mcp".into(), generation);
                    mcp_changed = false;
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
                    .threads
                    .observed_threads()
                    .into_iter()
                    .filter(|(id, thread)| {
                        runtime
                            .threads
                            .thread(id)
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
                    let selected = sources.for_project(project.as_ref());
                    if let Some((_, updates)) = workers.get(&id) {
                        updates.send_replace(selected);
                        continue;
                    }
                    let (updates, mut receiver) = tokio::sync::watch::channel(selected);
                    workers.insert(id.clone(), (thread.clone(), updates));
                    let runtime = runtime.clone();
                    let stopping = stopping.clone();
                    tasks.spawn(async move {
                        let Ok((_, lifetime)) = runtime.thread_factory.tool_operation(&id) else { return; };
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
                            if cleanup_was_pending && thread.snapshot().tool_cleanup.pending == 0 { continue; }
                            tokio::select! {
                                () = stopping.cancelled() => break,
                                () = lifetime.cancelled() => break,
                                changed = receiver.changed() => if changed.is_err() { break; },
                                _ = snapshots.next(), if thread.snapshot().tool_cleanup.pending > 0 => {},
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
                    changed = mcp.recv() => {
                        if matches!(changed, Err(tokio::sync::broadcast::error::RecvError::Closed)) { break; }
                        mcp_changed = true;
                    },
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
            let Ok((gate, cancellation)) = self.thread_factory.tool_operation(&id) else {
                continue;
            };
            let _installation = tokio::select! {
                biased;
                () = stopping.cancelled() => continue,
                () = cancellation.cancelled() => continue,
                guard = gate.lock_owned() => guard,
            };
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
            if snapshot.tool_cleanup.pending > 0 && !authority_invalidated {
                continue;
            }
            let mut facts = Vec::new();
            if let Some(fact) = self.thread_factory.session_files_fact(&id, &snapshot) {
                facts.push(fact);
            }
            if let Some(fact) = self.thread_factory.skill_catalog_fact(&id, &snapshot) {
                facts.push(fact);
            }
            if !facts.is_empty()
                && let Err(error) = thread.queue_runtime_facts(facts).await
                && !matches!(error, pl_core::thread::ThreadError::Closed)
            {
                tracing::warn!(thread_id = %id, %error, "could not queue refreshed host facts");
            }
            if snapshot.lifecycle != ThreadLifecycle::Open {
                continue;
            }
            let project = self.thread_factory.tool_project(&id);
            let fingerprint =
                catalog_fingerprint(&sources.for_project(project.as_ref()), &snapshot);
            if attempted.get(&id).is_some_and(|(previous, key)| {
                previous.same_instance(&thread) && key == &fingerprint
            }) {
                continue;
            }
            let result = self
                .install_refreshed_tools(
                    &id,
                    &thread,
                    &snapshot,
                    cancellation.clone(),
                    sources,
                    latest,
                )
                .await;
            let result = match result {
                Err(error) => match error.downcast::<pl_core::thread::ThreadError>() {
                    Ok(pl_core::thread::ThreadError::RejectedTools(resources)) => {
                        tracing::warn!(thread_id = %id, error = %resources, "retaining rejected candidate cleanup owner");
                        self.rejected_tools.retain(thread.clone(), resources);
                        // Retry the original owner once promptly. Persistent failure waits for a source event
                        // or shutdown; no new candidates accumulate while cleanup remains pending.
                        self.tool_catalog_updates.notify_one();
                        continue;
                    }
                    Ok(error) => Err(anyhow::Error::new(error)),
                    Err(error) => Err(error),
                },
                Ok(()) => Ok(()),
            };
            if result.as_ref().err().is_some_and(|error| {
                matches!(
                    error.downcast_ref::<pl_core::thread::ThreadError>(),
                    Some(pl_core::thread::ThreadError::ExtensionSequenceConflict { .. })
                )
            }) {
                // The stale candidate was closed by the transfer API. Reprepare against the
                // new producer state; never mark this fingerprint attempted or clear its tools.
                self.tool_catalog_updates.notify_one();
                continue;
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
            action: crate::studio::StudioRecoveryIssueAction::Retry,
            project_id: None,
            thread_id: Some(id.to_string()),
            worktree: None,
            message: crate::studio::recovery_registry::diagnostic::bounded(&format!(
                "Tool catalog refresh failed: {}",
                crate::studio::recovery_registry::diagnostic::failure(error.as_ref())
            )),
        });
        self.recovery.update_if_current(&issue_id, issue, || {
            self.threads.thread(id).is_some_and(|current| {
                current.same_instance(thread)
                    && current.snapshot().lifecycle == ThreadLifecycle::Open
            })
        });
    }

    async fn install_refreshed_tools(
        &self,
        id: &str,
        thread: &ThreadHandle,
        snapshot: &pl_core::thread::ThreadSnapshot,
        cancellation: tokio_util::sync::CancellationToken,
        sources: &CatalogSources,
        latest: &tokio::sync::watch::Receiver<CatalogSources>,
    ) -> anyhow::Result<()> {
        if self.thread_factory.tool_authority_invalidated(id)? {
            thread
                .register_tools_if_extensions(snapshot.extension_sequence, Vec::new())
                .await?;
        }
        let prepared = self
            .thread_factory
            .refresh_thread_tools(id, snapshot, cancellation.clone())
            .await;
        let (tools, exposure, binding) = match prepared {
            Ok(prepared) => prepared,
            Err(error) => {
                if matches!(
                    error,
                    crate::thread_assembler::ThreadAssemblyError::InvalidatedBinding(_)
                ) {
                    thread
                        .register_tools_if_extensions(snapshot.extension_sequence, Vec::new())
                        .await?;
                }
                return Err(error.into());
            }
        };
        let mut registrations = tools.into_registrations();
        let controls = (|| -> anyhow::Result<_> {
            let profile_revision = match exposure {
                crate::thread_assembler::AgentControlExposure::Enabled => {
                    let profiles = self.config_runtime.agent_profiles_snapshot()?;
                    let expected = profiles.revision.to_string();
                    if sources.0.get("agent-profiles") != Some(&expected) {
                        return Err(pl_core::thread::ThreadError::Cancelled.into());
                    }
                    let selection = crate::studio::delegation::saved(snapshot)?
                        .context("Thread has no frozen delegation selection")?;
                    registrations.extend(self.threads.agent_control_tools(&profiles, selection)?);
                    Some(profiles.revision)
                }
                crate::thread_assembler::AgentControlExposure::Disabled => None,
            };
            // A configuration publication may beat the source watch forwarder. Check the
            // canonical generation too, before transferring this candidate to the Thread.
            let stale_profiles = match profile_revision {
                Some(revision) => {
                    self.config_runtime.agent_profiles_snapshot()?.revision != revision
                }
                None => false,
            };
            if cancellation.is_cancelled() || sources.0 != latest.borrow().0 || stale_profiles {
                return Err(pl_core::thread::ThreadError::Cancelled.into());
            }
            Ok(())
        })();
        if let Err(error) = controls {
            // This includes catalog/schema errors: the complete physical candidate must enter
            // the existing retirement owner rather than being dropped on an early `?`.
            thread.retire_tools(registrations).await?;
            return Err(error);
        }
        thread
            .register_tools_if_extensions(snapshot.extension_sequence, registrations)
            .await?;
        self.publish_tool_binding(id, thread, snapshot.extension_sequence, binding)
            .await?;
        let snapshot = thread.snapshot();
        let mut facts = Vec::new();
        if let Some(fact) = self.thread_factory.session_files_fact(id, &snapshot) {
            facts.push(fact);
        }
        if let Some(fact) = self.thread_factory.skill_catalog_fact(id, &snapshot) {
            facts.push(fact);
        }
        if !facts.is_empty() {
            thread.queue_runtime_facts(facts).await?;
        }
        Ok(())
    }

    // The refresh loop serializes installations. An extension change can still
    // supersede this catalog, so rollback uses the same producer sequence guard.
    async fn publish_tool_binding(
        &self,
        id: &str,
        thread: &ThreadHandle,
        extension_sequence: u64,
        binding: crate::studio::thread_factory::RefreshedToolBinding,
    ) -> anyhow::Result<()> {
        if thread.snapshot().lifecycle != ThreadLifecycle::Open {
            return Err(pl_core::thread::ThreadError::Closed.into());
        }
        if let Err(error) = self.thread_factory.commit_refreshed_binding(id, binding) {
            if self.thread_factory.tool_authority_invalidated(id)? {
                thread
                    .register_tools_if_extensions(extension_sequence, Vec::new())
                    .await?;
            }
            return Err(error.into());
        }
        Ok(())
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
    let mutation = snapshot
        .deliveries
        .iter()
        .rev()
        .find(|delivery| {
            delivery.tool_id == "skill_manage"
                && delivery.output.payload().format() == "pl.tool.skill-mutation"
                && matches!(delivery.outcome, ToolOutcome::Succeeded)
        })
        .map(|delivery| &delivery.call_id);
    crate::hash::canonical_json_hash(&serde_json::json!({
        "sources": sources.0,
        "skillMutation": mutation,
        "mode": snapshot.extensions.get("studio.mode"),
        "modelRoute": snapshot.extensions.get(crate::studio::model_route::MODEL_ROUTE_EXTENSION),
        "agentProfile": snapshot.extensions.get(crate::studio::model_route::AGENT_PROFILE_EXTENSION),
    }))
}
