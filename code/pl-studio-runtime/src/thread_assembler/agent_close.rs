//! Explicit close may restore saved shutdown facts, but never model/tool/workspace execution.
use super::{Entry, StudioChildResources, StudioThreadAssembler, agent_services::AgentServices};
use anyhow::{Context, Result, ensure};
use pl_core::thread::{ThreadHandle, ThreadLifecycle};
use pl_tool::collaboration::thread::AgentWorkspaceDisposition;
use std::{collections::BTreeMap, sync::Arc};

impl AgentServices {
    pub(super) async fn close_child_tree(
        &self,
        owner: StudioThreadAssembler,
        caller: String,
        target: String,
        disposition: AgentWorkspaceDisposition,
        root_operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<()> {
        owner.ensure_agent_admission_open(&caller)?;
        ensure!(caller != target, "close target must be a strict descendant");
        self.authorize(&caller, &target).await?;
        let root = self.record(&caller).await?;
        ensure!(
            root.parent_thread_id.is_none() && root.root_thread_id == caller,
            "close caller must be an active root"
        );
        let target_record = self.record(&target).await?;
        ensure!(
            !target_record.archived,
            "archived child cannot be closed for execution"
        );
        // Root admission orders all earlier spawn preparations before this final directory scope.
        // This loads only lightweight rows; checkpoint reads are limited to the selected subtree.
        let mut records = self
            .store
            .list_threads_for_root(&caller)
            .await?
            .into_iter()
            .map(|record| (record.id.clone(), pl_protocol::Thread::from(record)))
            .collect::<BTreeMap<_, _>>();
        // Membership is canonical in the catalog before a child is published; no history scan or
        // second directory source is needed after the root preparation permit has been acquired.
        records.insert(target.clone(), target_record);
        let mut targets = Vec::new();
        for record in records.values() {
            let path = self.authorize(&caller, &record.id).await?;
            if path.iter().any(|id| id.as_str() == target) {
                targets.push((path.len(), record.id.clone()));
            }
        }
        targets.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        let _seals = owner.seal_agent_close(&targets, disposition).await?;
        // No close or activation below re-enters the root permit. Global/root close can now join
        // this owned operation without waiting for a worker that still needs that same root gate.
        drop(root_operation);
        for (_, id) in targets {
            self.close_saved_child(
                &owner,
                records.get(&id).context("close scope lost its record")?,
                disposition,
            )
            .await?;
        }
        Ok(())
    }

    async fn close_saved_child(
        &self,
        owner: &StudioThreadAssembler,
        record: &pl_protocol::Thread,
        disposition: AgentWorkspaceDisposition,
    ) -> Result<()> {
        let _operation = owner.agent_operation(&record.id).await;
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
                thread.flush().await?;
                owner.drain_observation(&record.id).await?;
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
            {
                // Only the durable Studio marker proves explicit closure. A normal shutdown's
                // Closed checkpoint must first acquire that marker through the storage owner.
                let projection = self
                    .factory
                    .project_child_close(record, &checkpoint.state)
                    .await;
                self.factory
                    .close_published(&record.id, disposition)
                    .await?;
                projection?;
                return Ok(());
            }
            let persistence = self
                .factory
                .child_close_storage(record, &checkpoint)
                .await?;
            let thread = ThreadHandle::resume_without_model(record.id.clone(), Some(checkpoint))?;
            self.events.warm_thread_index(vec![record.clone()]);
            // A previous failed resource close can leave a physically Closed entry. Retain its
            // cleanup ownership and frozen policy while replacing only its ended core incarnation.
            let previous = owner.0.state().entries.remove(&record.id);
            owner.0.state().entries.insert(
                record.id.clone(),
                Entry {
                    close_storage: Some(persistence),
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
            // Register before the first async owner command, retaining the same sink and any
            // previously committed policy. A new request remains private until its flush succeeds.
            owner.publish_observation(&record.id, &thread);
        }
        owner.attach_close_storage(&record.id).await?;
        let thread = owner
            .observed_thread(&record.id)
            .context("closing child owner is missing")?;
        crate::studio::agent_close::commit(&thread).await?;
        owner.freeze_agent_close_disposition(&record.id, disposition)?;
        let projection = self
            .factory
            .project_child_close(record, &thread.snapshot())
            .await;
        // The durable seal is now independent of cleanup/projection failures or caller cancellation.
        owner
            .close_with_permit(
                &record.id,
                super::PublishedWorkspaceRetirement::ApplyExplicitClose,
            )
            .await?;
        projection?;
        Ok(())
    }
}
