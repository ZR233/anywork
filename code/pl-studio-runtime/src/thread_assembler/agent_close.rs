//! Managed final child close: permanent execution seal, real joins/save ACKs, one owned worktree.
use super::{
    CloseStorage, Entry, EntryPurpose, StudioThreadAssembler, ThreadAssemblyError,
    agent_services::AgentServices,
};
use crate::studio::agent_close::{
    AgentCloseOutcome, AgentCloseResult, AgentWorktreeCleanup, state_error,
};
use anyhow::{Context, Result, ensure};
use pl_core::thread::{ThreadHandle, ThreadLifecycle};
use pl_tool::collaboration::thread::{AgentCloseOptions, WorkspaceRelease};
use std::{collections::BTreeMap, sync::Arc};

impl AgentServices {
    pub(super) async fn close_child_tree(
        &self,
        owner: StudioThreadAssembler,
        caller: String,
        target: String,
        options: AgentCloseOptions,
        root_operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<AgentCloseOutcome> {
        owner.ensure_agent_admission_open(&caller)?;
        ensure!(caller != target, "close target must be a strict descendant");
        self.authorize(&caller, &target).await?;
        let root = self.record(&caller).await?;
        ensure!(
            root.parent_thread_id.is_none() && root.root_thread_id == caller,
            "close caller must be an active root"
        );
        let target_record = self.record(&target).await?;
        let mut records = self
            .store
            .list_threads_for_root(&caller)
            .await?
            .into_iter()
            .map(|record| (record.id.clone(), pl_protocol::Thread::from(record)))
            .collect::<BTreeMap<_, _>>();
        records.insert(target.clone(), target_record);
        let mut targets = Vec::new();
        for record in records.values() {
            let path = self.authorize(&caller, &record.id).await?;
            if path.iter().any(|id| id.as_str() == target) {
                targets.push((path.len(), record.id.clone()));
            }
        }
        targets.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
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
                            crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                                &self.store,
                                record,
                            )
                            .await?
                            .context("saved child has no canonical checkpoint")?
                            .state,
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
        for (_, id) in &targets {
            match self.store.agent_close(id).await {
                Ok(Some(record)) => {
                    facts.insert(id.clone(), record.result());
                    if let Some(thread) = owner.observed_thread(id) {
                        thread.interrupt();
                    }
                }
                Ok(None) => {}
                Err(error) => failures.push(format!("{id}: close intent read failed: {error:#}")),
            }
        }
        for (_, id) in &targets {
            match self.store.agent_close(id).await {
                Ok(None) => continue,
                Err(error) => {
                    failures.push(format!("{id}: close intent read failed: {error:#}"));
                    continue;
                }
                Ok(Some(record)) => {
                    facts.insert(id.clone(), record.result());
                }
            }
            match self
                .close_saved_child(&owner, records.get(id).context("close record is missing")?)
                .await
            {
                Ok(()) => {
                    if let Some(fact) = facts.get_mut(id) {
                        fact.execution_closed = true;
                    }
                }
                Err(error) => {
                    if let Err(save) = self.factory.record_child_close_error(id, &error).await {
                        failures.push(format!("{id}: close error save failed: {save:#}"));
                    }
                    failures.push(format!("{id}: {error:#}"));
                }
            }
        }
        // All selected real borrowers are joined before any selected worktree may be removed.
        for (_, id) in &targets {
            if !facts.get(id).is_some_and(|fact| fact.execution_closed) {
                continue;
            }
            match self
                .factory
                .finish_child_worktree_cleanup(records.get(id).context("close record is missing")?)
                .await
            {
                Ok((result, error)) => {
                    facts.insert(id.clone(), result);
                    if let Some(error) = error {
                        failures.push(format!("{id}: {}", error.message));
                    }
                }
                Err(error) => failures.push(format!("{id}: {error:#}")),
            }
        }
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
            target,
            agents: targets
                .iter()
                .filter_map(|(_, id)| facts.remove(id))
                .collect(),
            error: (!failures.is_empty())
                .then(|| state_error(&anyhow::anyhow!("{}", failures.join("; ")))),
        })
    }

    pub(super) async fn close_saved_child(
        &self,
        owner: &StudioThreadAssembler,
        record: &pl_protocol::Thread,
    ) -> Result<()> {
        let operation = owner.agent_operation(&record.id).await;
        let receiver = owner.0.state().entries.get(&record.id).and_then(|entry| {
            (entry.purpose == EntryPurpose::ReportReceiver).then(|| entry.incarnation.clone())
        });
        if let Some(incarnation) = receiver {
            // A parent selected for final close may itself retain a failed report receiver.
            // Settle that exact temporary core before replacing or closing its canonical owner.
            owner
                .release_report_receiver(&record.id, &incarnation)
                .await?;
        }
        let intent = self
            .store
            .agent_close(&record.id)
            .await?
            .context("child has no close intent")?;
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
            let checkpoint = crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                &self.store,
                record,
            )
            .await?
            .context("cold child has no saved checkpoint proving its shutdown state")?;
            self.factory
                .validate_child_close(record, &checkpoint.state)?;
            if checkpoint.state.lifecycle == ThreadLifecycle::Closed
                && crate::studio::agent_close::is_explicitly_closed(&checkpoint.state)?
                && owner.observed_thread(&record.id).is_none()
            {
                self.factory
                    .project_child_close(record, &checkpoint.state)
                    .await?;
                owner
                    .acknowledge_parent_reports(&self.store, record)
                    .await?;
                return self.factory.finish_child_execution(record).await;
            }
            self.install_storage_owner(owner, record, checkpoint, EntryPurpose::CloseStorage)?;
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
        owner
            .acknowledge_parent_reports(&self.store, record)
            .await?;
        projection?;
        self.factory.finish_child_execution(record).await
    }

    /// The caller holds this identity's operation permit. A normal activation can reserve before
    /// taking that permit, so adjudicate its reservation and install the retained owner atomically.
    /// Replacing a closed owner additionally requires the caller to have drained its observation
    /// and joined its retained binding; Attached alone is not a release acknowledgement.
    pub(super) fn install_storage_owner(
        &self,
        owner: &StudioThreadAssembler,
        record: &pl_protocol::Thread,
        checkpoint: pl_core::thread::ThreadCheckpoint,
        purpose: EntryPurpose,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        let mut state = owner.0.state();
        if state.creating.contains_key(&record.id) {
            return Err(ThreadAssemblyError::Preparing(record.id.clone()));
        }
        if let Some(entry) = state.entries.get(&record.id)
            && (purpose == EntryPurpose::ReportReceiver
                || entry.thread.snapshot().lifecycle != ThreadLifecycle::Closed
                || !matches!(
                    entry.close_storage.as_ref(),
                    None | Some(CloseStorage::Attached(_))
                ))
        {
            return Err(ThreadAssemblyError::Unpublished(record.id.clone()));
        }
        let thread =
            ThreadHandle::resume_without_model(record.id.clone(), Some(checkpoint.clone()))?;
        let previous = state.entries.remove(&record.id);
        state.entries.insert(
            record.id.clone(),
            Entry {
                purpose,
                workspace_usage: previous
                    .as_ref()
                    .and_then(|entry| entry.workspace_usage.clone()),
                close_storage: Some(CloseStorage::Pending {
                    record: Box::new(record.clone()),
                    checkpoint: Box::new(checkpoint),
                }),
                published_resources_closed: previous
                    .as_ref()
                    .is_some_and(|entry| entry.published_resources_closed),
                workspace_disposition: previous
                    .as_ref()
                    .and_then(|entry| entry.workspace_disposition),
                cleanup: previous.map_or_else(Default::default, |entry| entry.cleanup),
                execution: pl_core::thread::input::InputDriverOptions {
                    max_model_steps: crate::studio::StudioThreadFactory::CHILD_MODEL_STEP_LIMIT,
                },
                incarnation: Arc::new(()),
                parent_id: record.parent_thread_id.clone(),
                ready: false,
                thread: thread.clone(),
            },
        );
        drop(state);
        self.events.warm_thread_index(vec![record.clone()]);
        Ok(thread)
    }
}
