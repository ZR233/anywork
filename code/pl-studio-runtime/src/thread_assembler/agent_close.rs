//! Managed final child close: permanent execution seal, real joins/save ACKs, one owned worktree.
use super::{
    CloseStorage, EntryPurpose, SessionRuntime, ThreadAssemblyError, agent_services::AgentServices,
};
use crate::studio::agent_close::state_error;
use anyhow::{Context, Result, ensure};
use pl_core::thread::{ThreadHandle, ThreadLifecycle, current::ThreadCurrent};
use pl_tool::collaboration::control::{AgentCloseOutcome, AgentCloseResult, AgentWorktreeCleanup};
use pl_tool::collaboration::thread::{AgentCloseOptions, WorkspaceRelease};
use std::{collections::BTreeMap, sync::Arc};

impl AgentServices {
    pub(super) async fn close_child_tree(
        &self,
        owner: SessionRuntime,
        caller: String,
        target: String,
        options: AgentCloseOptions,
        root_operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<AgentCloseOutcome> {
        owner.ensure_agent_admission_open(&caller)?;
        ensure!(caller != target, "close target must be a strict descendant");
        self.authorize(&caller, &target).await?;
        let root = self.identity(&caller)?;
        let target_identity = self.identity(&target)?;
        ensure!(
            root.parent_agent_id.is_none(),
            "close caller must be an active root"
        );
        if self
            .events
            .agent_execution_identity(&target)
            .is_some_and(|(_, binding, _)| matches!(binding, crate::AgentBinding::Acp(_)))
        {
            let operation = owner.agent_operation(&target).await;
            let _seal = owner.seal_agent_operation(&target);
            let mut result = self
                .factory
                .begin_acp_child_close(&target, options.force)
                .await?;
            // The original ACP result-delivery join may need the Native parent's inbox gate.
            drop(root_operation);
            let close = owner.close_with_permit(&target, operation).await;
            let error = match close {
                Ok(()) => match self.factory.finish_acp_child_close(&target).await {
                    Ok((fact, failure)) => {
                        result = fact;
                        failure
                    }
                    Err(failure) => {
                        self.factory
                            .record_child_close_error(&target, &failure)
                            .await?;
                        Some(state_error(&failure))
                    }
                },
                Err(failure) => {
                    let failure = anyhow::Error::new(failure);
                    self.factory
                        .record_child_close_error(&target, &failure)
                        .await?;
                    Some(state_error(&failure))
                }
            };
            result.agent_id = target_identity.agent_id.to_string();
            return Ok(AgentCloseOutcome {
                target: target_identity.agent_id.to_string(),
                agents: vec![result],
                error,
            });
        }
        let target_record = self.record(&target).await?;
        let mut records = BTreeMap::new();
        for (member, _) in self.factory.directory_rows_for_root(&caller).await? {
            // Select by public directory identity before reading a Native record. An ACP
            // root or sibling has no Native projection and is outside this close scope.
            if !matches!(member.backend, crate::AgentBackend::Native { .. }) {
                continue;
            }
            let path = self.authorize(&caller, &member.thread_id).await?;
            if path.contains(&target_identity.agent_id) {
                records.insert(
                    member.thread_id.clone(),
                    self.record(&member.thread_id).await?,
                );
            }
        }
        records.insert(target.clone(), target_record);
        let mut targets = Vec::new();
        for record in records.values() {
            let path = self.authorize(&caller, &record.id).await?;
            if path.contains(&target_identity.agent_id) {
                targets.push((path.len(), record.id.clone()));
            }
        }
        targets.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        let member_ids = targets
            .iter()
            .map(|(_, id)| Ok((id.clone(), self.identity(id)?.agent_id)))
            .collect::<Result<BTreeMap<_, _>>>()?;
        // Generic resource release is always Preserve. Only the close domain below may remove Git.
        let _seals = owner
            .seal_agent_close(&targets, WorkspaceRelease::Preserve)
            .await?;
        let mut failures = Vec::new();
        let mut facts = targets
            .iter()
            .map(|(_, id)| {
                (
                    id.clone(),
                    AgentCloseResult {
                        agent_id: id.clone(),
                        execution_closed: false,
                        worktree_cleanup: AgentWorktreeCleanup::Pending,
                    },
                )
            })
            .collect::<BTreeMap<_, _>>();
        for (_, id) in &targets {
            let record = records.get(id).context("close scope lost its record")?;
            let result = async {
                let state = if self.store.agent_close(id).await?.is_some() {
                    None
                } else {
                    match owner.observed_thread(id) {
                        Some(thread) => Some(thread.snapshot()),
                        None => Some(
                            crate::studio::thread_factory::recovery::load_current_for_recovery(
                                &self.store,
                                record,
                            )
                            .await?
                            .context("saved child has no canonical current")?
                            .state
                            .to_paused_snapshot(),
                        ),
                    }
                };
                self.factory
                    .begin_child_close(record, state.as_ref(), options.force)
                    .await
            }
            .await;
            match result {
                Ok(record) => {
                    facts.insert(id.clone(), record.result());
                }
                Err(error) => {
                    if let Err(save) = self.factory.record_child_close_error(id, &error).await {
                        failures.push(format!("{id}: close error save failed: {save:#}"));
                    }
                    failures.push(format!("{id}: {error:#}"));
                }
            }
        }
        drop(root_operation);
        let ordered = targets
            .iter()
            .map(|(_, id)| records.get(id).cloned().context("close record is missing"))
            .collect::<Result<Vec<_>>>()?;
        failures.extend(self.join_closed_children(&owner, &ordered).await);
        for (_, id) in &targets {
            match self.store.agent_close(id).await {
                Ok(Some(record)) => {
                    if let Some(fact) = facts.get_mut(id) {
                        fact.execution_closed |= record.execution_closed;
                        if matches!(fact.worktree_cleanup, AgentWorktreeCleanup::Pending)
                            || (!fact.worktree_cleanup.is_terminal()
                                && record.worktree_cleanup.is_terminal())
                        {
                            fact.worktree_cleanup = record.worktree_cleanup;
                        }
                    }
                }
                Ok(None) => {}
                Err(error) => failures.push(format!("{id}: close result read failed: {error:#}")),
            }
        }
        if failures.is_empty()
            && facts
                .values()
                .any(|fact| !fact.execution_closed || !fact.worktree_cleanup.is_terminal())
        {
            failures.push("child close has unfinished execution or worktree cleanup".into());
        }
        Ok(AgentCloseOutcome {
            target: target_identity.agent_id.to_string(),
            agents: targets
                .iter()
                .filter_map(|(_, id)| {
                    facts.remove(id).map(|mut fact| {
                        fact.agent_id = member_ids[id].to_string();
                        fact
                    })
                })
                .collect(),
            error: (!failures.is_empty())
                .then(|| state_error(&anyhow::anyhow!("{}", failures.join("; ")))),
        })
    }

    /// Shared Native close progress for explicit and recovered intents. Every resident owner is
    /// interrupted first, each saved child's owners are then joined through `close_saved_child`,
    /// and only a child whose durable intent is execution-closed proceeds to owned-worktree
    /// removal. Returns per-child diagnostics; the caller owns admission, sealing and outcome.
    pub(super) async fn join_closed_children(
        &self,
        owner: &SessionRuntime,
        targets: &[crate::Thread],
    ) -> Vec<String> {
        let mut failures = Vec::new();
        for record in targets {
            if let Some(thread) = owner.observed_thread(&record.id) {
                thread.interrupt();
            }
        }
        for record in targets {
            match self.store.agent_close(&record.id).await {
                Ok(Some(_)) => {}
                Ok(None) => continue,
                Err(error) => {
                    failures.push(format!(
                        "{}: close intent read failed: {error:#}",
                        record.id
                    ));
                    continue;
                }
            }
            if let Err(error) = self.close_saved_child(owner, record).await {
                if let Err(save) = self
                    .factory
                    .record_child_close_error(&record.id, &error)
                    .await
                {
                    failures.push(format!("{}: close error save failed: {save:#}", record.id));
                }
                failures.push(format!("{}: {error:#}", record.id));
            }
        }
        // All selected real borrowers are joined before any selected worktree may be removed.
        for record in targets {
            match self.store.agent_close(&record.id).await {
                Ok(Some(intent)) if intent.execution_closed => {}
                Ok(_) => continue,
                Err(error) => {
                    failures.push(format!(
                        "{}: close intent read failed: {error:#}",
                        record.id
                    ));
                    continue;
                }
            }
            match self.factory.finish_child_worktree_cleanup(record).await {
                Ok((_, Some(error))) => {
                    failures.push(format!("{}: {}", record.id, error.message));
                }
                Err(error) => failures.push(format!("{}: {error:#}", record.id)),
                Ok((_, None)) => {}
            }
        }
        failures
    }

    pub(super) async fn close_saved_child(
        &self,
        owner: &SessionRuntime,
        record: &crate::Thread,
    ) -> Result<()> {
        let intent = self
            .store
            .agent_close(&record.id)
            .await?
            .context("child has no close intent")?;
        let closing = owner
            .0
            .state()
            .members
            .entries
            .get_mut(&record.id)
            .and_then(|entry| {
                let native = entry.native_mut().ok()?;
                Some({
                    native.ready = false;
                    native.thread.clone()
                })
            });
        if let Some(thread) = closing {
            drop(owner.prepare_close(&record.id, &thread));
        }
        let operation = owner.agent_operation(&record.id).await;
        let receiver = owner
            .0
            .state()
            .members
            .entries
            .get(&record.id)
            .and_then(|entry| {
                (entry.native().ok()?.purpose == EntryPurpose::ReportReceiver)
                    .then_some(entry.native().ok()?.incarnation.clone())
            });
        if let Some(incarnation) = receiver {
            // A parent selected for final close may itself retain a failed report receiver.
            // Settle that exact temporary core before replacing or closing its canonical owner.
            owner
                .release_report_receiver(&record.id, &incarnation)
                .await?;
        }
        if intent.execution_closed {
            return Ok(());
        }
        let resident = owner.observed_thread(&record.id);
        let needs_storage_owner = match &resident {
            Some(thread) => {
                thread.snapshot().lifecycle == ThreadLifecycle::Closed
                    && !crate::studio::agent_close::is_explicitly_closed(&thread.snapshot())?
            }
            None => true,
        };
        if needs_storage_owner {
            if let Some(thread) = resident {
                if owner.close_storage_binding(&record.id)?.is_some() {
                    owner.close_storage_core(&record.id).await?;
                }
                thread.flush().await?;
                owner.drain_observation(&record.id).await?;
                owner.join_close_storage(&record.id).await?;
            }
            let current = crate::studio::thread_factory::recovery::load_current_for_recovery(
                &self.store,
                record,
            )
            .await?
            .context("cold child has no saved current proving its shutdown state")?;
            let state = current.state.to_paused_snapshot();
            self.factory.validate_child_close(record, &state)?;
            // The paused Core view deliberately reopens lifecycle; the saved Current itself
            // carries the original producer's completed resource-close observation.
            if current.state.lifecycle == ThreadLifecycle::Closed
                && crate::studio::agent_close::is_explicitly_closed(&state)?
                && owner.observed_thread(&record.id).is_none()
            {
                self.factory.project_child_close(record, &state).await?;
                owner.acknowledge_parent_reports(record).await?;
                return self.factory.finish_child_execution(record).await;
            }
            self.install_storage_owner(owner, record, current, EntryPurpose::CloseStorage)?;
        }
        owner.attach_close_storage(&record.id).await?;
        let thread = owner
            .observed_thread(&record.id)
            .context("closing child owner is missing")?;
        crate::studio::agent_close::commit(&thread).await?;
        owner.freeze_agent_close_disposition(&record.id, WorkspaceRelease::Preserve)?;
        let projection = self
            .factory
            .project_child_close(record, &thread.snapshot())
            .await;
        owner.close_with_permit(&record.id, operation).await?;
        owner.acknowledge_parent_reports(record).await?;
        projection?;
        self.factory.finish_child_execution(record).await
    }

    /// The caller holds this identity's operation permit. A normal activation can reserve before
    /// taking that permit, so adjudicate its reservation and install the retained owner atomically.
    /// Replacing a closed owner additionally requires the caller to have drained its observation
    /// and joined its retained binding; Attached alone is not a release acknowledgement.
    pub(super) fn install_storage_owner(
        &self,
        owner: &SessionRuntime,
        record: &crate::Thread,
        current: ThreadCurrent,
        purpose: EntryPurpose,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        let (identity, binding, parent_thread) =
            self.events
                .agent_execution_identity(&record.id)
                .ok_or_else(|| ThreadAssemblyError::Identity(record.id.clone()))?;
        if &identity.session_id != owner.id()
            || parent_thread.as_ref().map(crate::ThreadId::as_str)
                != record.parent_thread_id.as_deref()
        {
            return Err(ThreadAssemblyError::Identity(record.id.clone()));
        }
        if matches!(binding, crate::AgentBinding::Acp(_)) {
            return Err(ThreadAssemblyError::UnsupportedBackend {
                backend: crate::AgentBackendKind::Acp,
            });
        }
        if current.thread_id != record.id {
            return Err(ThreadAssemblyError::Identity(record.id.clone()));
        }
        let thread = ThreadHandle::restore_current(current.clone(), None)?;
        let mut state = owner.0.state();
        if state
            .activation
            .creating
            .get(&record.id)
            .is_some_and(|preparation| preparation.settlement.is_none())
        {
            return Err(ThreadAssemblyError::Preparing(record.id.clone()));
        }
        if let Some(entry) = state.members.entries.get(&record.id)
            && (purpose == EntryPurpose::ReportReceiver
                || entry.native()?.thread.snapshot().lifecycle != ThreadLifecycle::Closed
                || !matches!(
                    entry.native()?.close_storage.as_ref(),
                    None | Some(CloseStorage::Attached(_))
                        | Some(CloseStorage::Execution { joined: true, .. })
                ))
        {
            return Err(ThreadAssemblyError::Unpublished(record.id.clone()));
        }
        let previous = state.members.remove_entry(&record.id);
        let cleanup = previous
            .as_ref()
            .map(|entry| entry.native().map(|native| native.cleanup.clone()))
            .transpose()?
            .unwrap_or_default();
        state.members.insert_entry(
            record.id.clone(),
            crate::session::AgentInstance {
                identity,
                binding,
                runtime: crate::session::AgentRuntime::Native(Box::new(
                    crate::session::NativeThreadRuntime {
                        resources: previous
                            .as_ref()
                            .and_then(|entry| {
                                let native = entry.native().ok()?;
                                Some(native.resources.clone())
                            })
                            .unwrap_or_default(),
                        purpose,
                        workspace_usage: previous
                            .as_ref()
                            .and_then(|entry| entry.native().ok()?.workspace_usage.clone()),
                        close_storage: Some(CloseStorage::Pending {
                            record: Box::new(record.clone()),
                            current: Box::new(current),
                        }),
                        published_resources_closed: previous.as_ref().is_some_and(|entry| {
                            entry
                                .native()
                                .is_ok_and(|native| native.published_resources_closed)
                        }),
                        workspace_disposition: previous
                            .as_ref()
                            .and_then(|entry| entry.native().ok()?.workspace_disposition),
                        cleanup,
                        execution: pl_core::thread::input::InputDriverOptions {
                            max_model_steps:
                                crate::studio::StudioThreadFactory::CHILD_MODEL_STEP_LIMIT,
                        },
                        incarnation: Arc::new(()),
                        parent_id: record.parent_thread_id.clone(),
                        ready: false,
                        thread: thread.clone(),
                    },
                )),
            },
        );
        drop(state);
        Ok(thread)
    }
}
