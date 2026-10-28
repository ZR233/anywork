//! Explicit close may restore saved shutdown facts, but never model/tool/workspace execution.
use super::{Entry, StudioThreadAssembler, agent_services::AgentServices};
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
        if owner
            .0
            .state()
            .unpublished_children
            .contains_key(&record.id)
        {
            // Failed assembly still belongs to its original unpublished compensation owner.
            // Do not attach a published-directory responsibility to that independent prefix.
            owner
                .close_with_permit(&record.id, super::PublishedWorkspaceRetirement::Retain)
                .await?;
        }
        let resident = owner.observed_thread(&record.id);
        let needs_storage_owner = match &resident {
            Some(thread) => {
                thread.snapshot().lifecycle != ThreadLifecycle::Open
                    && !crate::studio::agent_close::is_explicitly_closed(&thread.snapshot())?
            }
            None => true,
        };
        if needs_storage_owner {
            if resident.is_some() {
                // A Closing/Closed core cannot accept a new deferred model/intent mutation.
                // Settle its original Retain run first; neither its failure nor cleanup gate may
                // be replaced merely to acquire a writable storage-only incarnation.
                owner
                    .close_with_permit(&record.id, super::PublishedWorkspaceRetirement::Retain)
                    .await?;
            }
            ensure!(
                !owner.0.state().entries.contains_key(&record.id),
                "original closing child is still registered"
            );
            let checkpoint = crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                &self.store,
                record,
            )
            .await?
            .context("cold child has no saved checkpoint proving its shutdown state")?;
            self.factory
                .validate_child_close(record, &checkpoint.state)?;
            let persistence = self
                .factory
                .child_close_storage(record, &checkpoint)
                .await?;
            let thread = ThreadHandle::resume_without_model(record.id.clone(), Some(checkpoint))?;
            self.events.warm_thread_index(vec![record.clone()]);
            owner.0.state().entries.insert(
                record.id.clone(),
                Entry {
                    close_storage: Some(persistence),
                    published_resources_closed: false,
                    workspace_disposition: None,
                    directory_projection: None,
                    directory_projected: false,
                    cleanup: Default::default(),
                    execution: pl_core::thread::input::InputDriverOptions {
                        max_model_steps: crate::studio::StudioThreadFactory::CHILD_MODEL_STEP_LIMIT,
                    },
                    incarnation: Arc::new(()),
                    parent_id: record.parent_thread_id.clone(),
                    ready: false,
                    thread: thread.clone(),
                },
            );
            // Even a saved marker uses its own storage-only Entry, cleanup gate and phase run.
            // Registration precedes the first async owner command and retains this exact sink.
            owner.publish_observation(&record.id, &thread);
        }
        owner.attach_close_storage(&record.id).await?;
        let thread = owner
            .observed_thread(&record.id)
            .context("closing child owner is missing")?;
        crate::studio::agent_close::commit(&thread).await?;
        owner
            .freeze_agent_close_disposition(
                &record.id,
                &thread,
                disposition,
                super::published_resources::DirectoryProjection::new(
                    self.factory.clone(),
                    record.clone(),
                ),
            )
            .await?;
        // The durable seal is now independent of cleanup/projection failures or caller cancellation.
        owner
            .close_with_permit(
                &record.id,
                super::PublishedWorkspaceRetirement::ApplyExplicitClose,
            )
            .await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::test_support::{RuntimeFixture, git, sqlite};
    use crate::thread_assembler::{
        ConfiguredChildFactory, StudioChildFactory, ThreadAssemblyError,
    };
    use sea_orm::ConnectionTrait;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

    /// The wrapper controls only the external factory ACK. Real lease/factory/Thread algorithms
    /// still execute, and the filesystem fault is installed only after physical success.
    #[derive(Debug)]
    struct FactoryAck {
        inner: ConfiguredChildFactory<crate::studio::StudioThreadFactory>,
        calls: Arc<AtomicUsize>,
        block_projection: Arc<AtomicBool>,
        catalog: PathBuf,
    }
    impl StudioChildFactory for FactoryAck {
        async fn prepare(
            &self,
            request: crate::thread_assembler::ChildThreadRequest,
        ) -> Result<crate::thread_assembler::StudioThreadSpec, ThreadAssemblyError> {
            self.inner.prepare(request).await
        }
        async fn discard_unpublished(&self, id: &str) -> Result<(), ThreadAssemblyError> {
            self.inner.discard_unpublished(id).await
        }
        async fn close_published(
            &self,
            id: &str,
            disposition: AgentWorkspaceDisposition,
        ) -> Result<(), ThreadAssemblyError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            self.inner.close_published(id, disposition).await?;
            if self.block_projection.swap(false, Ordering::SeqCst) {
                std::fs::rename(&self.catalog, self.catalog.with_extension("retained.toml"))
                    .expect("retain fixture catalog");
                std::fs::create_dir(&self.catalog).expect("block original directory confirmation");
            }
            Ok(())
        }
    }

    fn install_factory(
        fixture: &RuntimeFixture,
        block_projection: bool,
    ) -> Result<Arc<AtomicUsize>> {
        let calls = Arc::new(AtomicUsize::new(0));
        fixture.assembler().set_child_factory(FactoryAck {
            inner: ConfiguredChildFactory::new(fixture.config(), fixture.factory()),
            calls: calls.clone(),
            block_projection: Arc::new(AtomicBool::new(block_projection)),
            catalog: fixture.store().paths().catalog_file(),
        })?;
        Ok(calls)
    }

    fn services(owner: &StudioThreadAssembler) -> AgentServices {
        owner
            .0
            .state()
            .agent_services
            .clone()
            .expect("original Studio services")
    }

    #[derive(Debug)]
    struct ToolCloseAck {
        recovered: Arc<AtomicBool>,
        calls: Arc<AtomicUsize>,
    }
    impl pl_core::tool::opaque::Tool for ToolCloseAck {
        async fn execute(
            &self,
            input: pl_core::context::OpaquePayload,
            _context: pl_core::tool::opaque::CallContext,
        ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
            Ok(pl_core::tool::ToolOutput::new(input, Vec::new()))
        }
        async fn close(&self) -> Result<(), pl_core::tool::opaque::ToolError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if !self.recovered.load(Ordering::SeqCst) {
                return Err(pl_core::tool::opaque::ToolError::new(
                    std::io::Error::other("external tool close ACK failed"),
                ));
            }
            Ok(())
        }
    }

    #[tokio::test]
    async fn explicit_close_finishes_retiring_core_before_cold_intent() -> Result<()> {
        use crate::thread_assembler::close_failure::{
            ThreadCloseFailure, ThreadClosePhase, source,
        };
        let fixture = RuntimeFixture::new().await?;
        let factory_calls = install_factory(&fixture, false)?;
        let owner = fixture.assembler();
        let (record, thread) = fixture.child().await?;
        let recovered = Arc::new(AtomicBool::new(false));
        let calls = Arc::new(AtomicUsize::new(0));
        thread
            .register_tools(vec![pl_core::tool::opaque::Registration::new(
                "retained-close-ack".into(),
                pl_core::context::OpaquePayload::text("external close ACK"),
                ToolCloseAck {
                    recovered: recovered.clone(),
                    calls: calls.clone(),
                },
            )?])
            .await?;
        let failure = owner.close(&record.id).await.unwrap_err();
        let original = source::<ThreadCloseFailure>(&failure)
            .expect("original CoreClose failure")
            .clone();
        assert_eq!(original.phase, ThreadClosePhase::CoreClose);
        assert_eq!(factory_calls.load(Ordering::SeqCst), 0);
        assert!(
            owner
                .observed_thread(&record.id)
                .is_some_and(|current| current.same_instance(&thread))
        );
        recovered.store(true, Ordering::SeqCst);
        services(&owner)
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await?;
        assert!(
            original.original_is_complete(),
            "the original run, not a replacement, must finish"
        );
        assert!(
            !crate::studio::agent_close::is_explicitly_closed(&thread.snapshot())?,
            "the ended original core is not rewritten to impersonate the new storage owner"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert_eq!(factory_calls.load(Ordering::SeqCst), 1);
        assert!(owner.observed_thread(&record.id).is_none());
        fixture.finish().await
    }

    #[tokio::test]
    async fn retained_close_cannot_retry_a_frozen_explicit_core_failure() -> Result<()> {
        use crate::thread_assembler::close_failure::{
            ThreadCloseFailure, ThreadClosePhase, source,
        };
        let fixture = RuntimeFixture::new().await?;
        let factory_calls = install_factory(&fixture, false)?;
        let owner = fixture.assembler();
        let (record, thread) = fixture.child().await?;
        let recovered = Arc::new(AtomicBool::new(false));
        let calls = Arc::new(AtomicUsize::new(0));
        thread
            .register_tools(vec![pl_core::tool::opaque::Registration::new(
                "explicit-close-ack".into(),
                pl_core::context::OpaquePayload::text("external close ACK"),
                ToolCloseAck {
                    recovered: recovered.clone(),
                    calls: calls.clone(),
                },
            )?])
            .await?;
        let services = services(&owner);
        let failure = services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await
            .unwrap_err();
        let original = source::<ThreadCloseFailure>(failure.as_ref())
            .expect("original explicit CoreClose failure")
            .clone();
        assert_eq!(original.phase, ThreadClosePhase::CoreClose);
        assert!(
            original.can_resume_original(),
            "the original explicit Tool failure remains recoverable"
        );
        assert!(crate::studio::agent_close::is_explicitly_closed(
            &thread.snapshot()
        )?);
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(factory_calls.load(Ordering::SeqCst), 0);

        // Recovery is already possible; an ordinary caller must still lack the explicit grant.
        recovered.store(true, Ordering::SeqCst);
        let retained = owner.close(&record.id).await.unwrap_err();
        let repeated =
            source::<ThreadCloseFailure>(&retained).expect("retained original CoreClose failure");
        assert_eq!(repeated.phase, original.phase);
        assert!(Arc::ptr_eq(&repeated.cause, &original.cause));
        assert!(
            !repeated.can_resume_original(),
            "Retain cannot grant any frozen explicit failure"
        );
        assert!(!original.original_is_complete());
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "Retain must not invoke Tool::close again"
        );
        assert_eq!(factory_calls.load(Ordering::SeqCst), 0);
        assert!(
            owner
                .observed_thread(&record.id)
                .is_some_and(|current| current.same_instance(&thread))
        );

        services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await?;
        assert!(
            original.original_is_complete(),
            "only the explicit request resumes the same run"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert_eq!(factory_calls.load(Ordering::SeqCst), 1);
        assert!(owner.observed_thread(&record.id).is_none());
        fixture.finish().await
    }

    #[tokio::test]
    async fn cold_marker_projection_retry_keeps_original_physical_success() -> Result<()> {
        use crate::thread_assembler::close_failure::{
            ThreadCloseFailure, ThreadClosePhase, source,
        };
        let fixture = RuntimeFixture::new().await?;
        let calls = install_factory(&fixture, true)?;
        let owner = fixture.assembler();
        let (record, thread) = fixture.child().await?;
        crate::studio::agent_close::commit(&thread).await?;
        owner.close(&record.id).await?;
        assert_eq!(
            calls.load(Ordering::SeqCst),
            0,
            "ordinary retirement cannot consume a marker as physical authorization"
        );
        let before = fixture.lease_revision(&record.id)?;
        let services = services(&owner);
        let failure = services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await
            .unwrap_err();
        let original =
            source::<ThreadCloseFailure>(failure.as_ref()).expect("retained close owner");
        assert_eq!(original.phase, ThreadClosePhase::DirectoryProjection);
        let retained = owner
            .observed_thread(&record.id)
            .expect("projection failure retains its Entry");
        assert!(
            !retained.same_instance(&thread),
            "cold closure has an independent storage-only incarnation"
        );
        assert_eq!(retained.snapshot().lifecycle, ThreadLifecycle::Closed);
        let preserved = fixture.lease_revision(&record.id)?;
        assert_eq!(preserved, before + 1);
        assert_eq!(calls.load(Ordering::SeqCst), 1);

        let retained_error = owner.close(&record.id).await.unwrap_err();
        let repeated = source::<ThreadCloseFailure>(&retained_error).expect("same phase failure");
        assert_eq!(repeated.phase, original.phase);
        assert!(
            Arc::ptr_eq(&repeated.cause, &original.cause),
            "Retain must not retry failed explicit work"
        );
        assert!(
            owner
                .observed_thread(&record.id)
                .is_some_and(|current| current.same_instance(&retained))
        );
        let catalog = fixture.store().paths().catalog_file();
        std::fs::remove_dir(&catalog)?;
        std::fs::rename(catalog.with_extension("retained.toml"), &catalog)?;
        services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await?;
        assert!(owner.observed_thread(&record.id).is_none());
        assert_eq!(
            fixture.lease_revision(&record.id)?,
            preserved,
            "projection retry must not preserve the lease a second time"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        fixture.finish().await
    }

    #[tokio::test]
    async fn failed_factory_resumes_original_owner_without_reinvoking_factory() -> Result<()> {
        use crate::thread_assembler::close_failure::{
            ThreadCloseFailure, ThreadClosePhase, source,
        };
        let fixture = RuntimeFixture::new().await?;
        let calls = install_factory(&fixture, false)?;
        let owner = fixture.assembler();
        let (record, thread) = fixture.child().await?;
        let assignment = crate::studio::workspace_receipt::from_snapshot(&thread.snapshot())
            .map_err(anyhow::Error::msg)?
            .context("assigned workspace")?;
        let git_dir = git(
            std::path::Path::new(&assignment.root),
            &["rev-parse", "--absolute-git-dir"],
        )
        .await?;
        let locked = PathBuf::from(String::from_utf8(git_dir)?.trim()).join("locked");
        tokio::fs::write(&locked, "fixture external Git lock").await?;
        let services = services(&owner);
        let failure = services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Cleanup)
            .await
            .unwrap_err();
        let original =
            source::<ThreadCloseFailure>(failure.as_ref()).expect("original factory failure");
        assert_eq!(original.phase, ThreadClosePhase::PublishedResources);
        assert!(
            source::<crate::studio::thread_factory::FactoryCloseFailure>(original.cause.as_ref())
                .is_some()
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        let retained = owner
            .observed_thread(&record.id)
            .expect("failed physical owner");
        assert_eq!(retained.snapshot().lifecycle, ThreadLifecycle::Closed);
        assert!(
            owner.close(&record.id).await.is_err(),
            "ordinary Retain cannot retry the failed physical stage"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        tokio::fs::remove_file(locked).await?;
        services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Cleanup)
            .await?;
        assert!(owner.observed_thread(&record.id).is_none());
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "original FactoryCloseFailure owns recovery"
        );
        assert!(!std::path::Path::new(&assignment.root).exists());
        fixture.finish().await
    }

    #[tokio::test]
    async fn closed_resident_must_finish_original_observation_before_new_storage_owner()
    -> Result<()> {
        use crate::thread_assembler::close_failure::{
            ThreadCloseFailure, ThreadClosePhase, source,
        };
        let fixture = RuntimeFixture::new().await?;
        let calls = install_factory(&fixture, false)?;
        let owner = fixture.assembler();
        let (record, thread) = fixture.child().await?;
        let db = sqlite(&fixture.store().paths().database()).await?;
        db.execute_unprepared("CREATE TRIGGER block_close_directory BEFORE UPDATE ON threads BEGIN SELECT RAISE(ABORT,'injected original directory ACK failure'); END").await?;
        let error = owner.close(&record.id).await.unwrap_err();
        let original = source::<ThreadCloseFailure>(&error)
            .expect("original retained observation failure")
            .clone();
        assert_eq!(original.phase, ThreadClosePhase::Observation);
        assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
        assert!(!crate::studio::agent_close::is_explicitly_closed(
            &thread.snapshot()
        )?);
        let services = services(&owner);
        assert!(
            services
                .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
                .await
                .is_err()
        );
        assert!(
            owner
                .observed_thread(&record.id)
                .is_some_and(|current| current.same_instance(&thread)),
            "a Closed core with an unresolved old run cannot be replaced"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        db.execute_unprepared("DROP TRIGGER block_close_directory")
            .await?;
        db.close().await?;
        fixture.retry_persistence_and_wait().await?;
        services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await?;
        assert!(
            original.original_is_complete(),
            "the old gate must really finish before cold ownership begins"
        );
        assert!(owner.observed_thread(&record.id).is_none());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        fixture.finish().await
    }

    #[tokio::test]
    async fn failed_intent_flush_never_publishes_physical_authorization() -> Result<()> {
        let fixture = RuntimeFixture::new().await?;
        let calls = install_factory(&fixture, false)?;
        let owner = fixture.assembler();
        let (record, thread) = fixture.child().await?;
        let path = fixture
            .store()
            .session_paths(&record.project_id, &record.id)?
            .history_database();
        let db = sqlite(&path).await?;
        db.execute_unprepared("CREATE TRIGGER block_close_intent BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'injected close intent ACK failure'); END").await?;
        let before = fixture.lease_revision(&record.id)?;
        let services = services(&owner);
        let history = fixture
            .store()
            .thread_persistence()
            .history_channel(&record.id);
        let mut history_status = history.subscribe();
        assert!(
            services
                .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Cleanup)
                .await
                .is_err()
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert_eq!(fixture.lease_revision(&record.id)?, before);
        {
            let state = owner.0.state();
            let entry = state
                .entries
                .get(&record.id)
                .expect("original owner still registered");
            assert!(entry.thread.same_instance(&thread));
            assert_eq!(entry.workspace_disposition, None);
            assert!(entry.directory_projection.is_none());
        }
        assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Open);
        // Explicit flush returns the backend failure directly; the idle Core need not have
        // mirrored it into a persistent fault generation. Recover the actual retained channel.
        let failed = history_status.borrow_and_update().clone();
        assert!(failed.error.is_some() && failed.fault.is_some());
        assert!(failed.fault_generation > 0);
        let generation = failed.fault_generation;
        db.execute_unprepared("DROP TRIGGER block_close_intent")
            .await?;
        db.close().await?;
        fixture
            .runtime
            .retry_thread_history(&record.id, generation)
            .await?;
        thread.flush().await?;
        services
            .close_saved_child(&owner, &record, AgentWorkspaceDisposition::Preserve)
            .await?;
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "a failed request cannot freeze its Cleanup choice"
        );
        fixture.finish().await
    }

    #[tokio::test]
    async fn archive_retirement_does_not_probe_or_clean_a_missing_child_site() -> Result<()> {
        let fixture = RuntimeFixture::new().await?;
        let calls = install_factory(&fixture, false)?;
        let (record, thread) = fixture.child().await?;
        let assignment = crate::studio::workspace_receipt::from_snapshot(&thread.snapshot())
            .map_err(anyhow::Error::msg)?
            .context("assigned workspace")?;
        let path = PathBuf::from(&assignment.root);
        let retained = path.with_extension("retained");
        tokio::fs::rename(&path, &retained).await?;
        let before = fixture.lease_revision(&record.id)?;
        fixture
            .runtime
            .archive_thread(
                "archive-without-probe".into(),
                record.root_thread_id.clone(),
            )
            .await?;
        assert_eq!(fixture.lease_revision(&record.id)?, before);
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert!(!crate::studio::agent_close::is_explicitly_closed(
            &thread.snapshot()
        )?);
        assert!(fixture.assembler().observed_thread(&record.id).is_none());
        tokio::fs::rename(retained, &path).await?;
        fixture.finish().await
    }
}
