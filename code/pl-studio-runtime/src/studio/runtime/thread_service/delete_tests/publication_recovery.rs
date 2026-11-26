//! Publication retries consume the durable deletion transaction after directory removal.
use super::*;
use crate::studio::thread_factory::mcp::tests::install_failed_watcher;
use crate::thread_assembler::test_support::CorruptCurrentAfterLoad;
use std::sync::Arc;

async fn publication_retry(restart: bool) -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let mut runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("s2-delete-root", &project.id, "delete publication")
        .await?;
    runtime.store.database().execute_unprepared(
        "CREATE TRIGGER reject_delete_publication BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='published'
         BEGIN SELECT RAISE(FAIL, 'delete publication rejected'); END",
    ).await?;
    let error = runtime
        .delete_thread("first-delete".into(), root.id.clone())
        .await
        .unwrap_err();
    assert!(format!("{error:#}").contains("delete publication rejected"));
    assert!(runtime.store.read_thread(&root.id).await?.is_none());
    assert!(
        runtime
            .agent_facility
            .product_events
            .agent_execution_identity(&root.id)
            .is_none()
    );
    let unfinished = runtime
        .store
        .thread_delete(&root.id)
        .await?
        .context("durable deletion survives publication failure")?;
    assert_eq!(unfinished.phase, DeletePhase::DataDeleted);
    assert!(
        !unfinished.members.is_empty(),
        "original frozen responsibility must remain until Published"
    );
    if restart {
        runtime.shutdown_runtime().await?;
        drop(runtime);
        runtime = StudioRuntime::initialize(options(&home)).await?;
        assert!(runtime.store.read_thread(&root.id).await?.is_none());
        assert!(
            runtime
                .agent_facility
                .product_events
                .agent_execution_identity(&root.id)
                .is_none()
        );
    }
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER reject_delete_publication")
        .await?;
    let completed = runtime
        .delete_thread("retry-delete".into(), root.id.clone())
        .await?
        .context("unfinished deletion must publish")?;
    assert_eq!(completed.result.deleted_root_id, root.id);
    assert!(completed.result.deleted_thread_ids.contains(&root.id));
    assert_eq!(
        runtime.store.thread_delete(&root.id).await?.unwrap().phase,
        DeletePhase::Published
    );
    assert!(
        runtime
            .delete_thread("already-published".into(), root.id.clone())
            .await?
            .is_none()
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn delete_publication_retries_after_directory_removal() -> Result<()> {
    tokio::time::timeout(std::time::Duration::from_secs(30), publication_retry(false)).await?
}

#[tokio::test]
async fn delete_publication_recovers_after_directory_removal_and_restart() -> Result<()> {
    tokio::time::timeout(std::time::Duration::from_secs(30), publication_retry(true)).await?
}

struct FailedRestoreFactory {
    native: crate::studio::thread_factory::StudioThreadFactory,
    store: crate::studio::StudioStore,
}

impl std::fmt::Debug for FailedRestoreFactory {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FailedRestoreFactory")
            .finish_non_exhaustive()
    }
}

impl crate::thread_assembler::StudioActivationFactory for FailedRestoreFactory {
    async fn prepare_execution(
        &self,
        identity: &crate::thread_assembler::ThreadActivation,
    ) -> std::result::Result<
        (
            Option<crate::DelegationSettings>,
            Option<pl_core::thread::current::ThreadCurrent>,
        ),
        crate::thread_assembler::ThreadAssemblyError,
    > {
        self.native.prepare_execution(identity).await
    }

    async fn prepare(
        &self,
        request: crate::thread_assembler::ThreadPreparation,
    ) -> std::result::Result<
        crate::thread_assembler::StudioThreadSpec,
        crate::thread_assembler::ThreadAssemblyError,
    > {
        use crate::thread_assembler::ThreadAssemblyError;
        let id = request.identity.id().to_owned();
        let expected = request
            .current
            .as_ref()
            .expect("real cold restoration supplied its checkpoint");
        let expected = serde_json::to_vec(expected).expect("encode fixture checkpoint");
        let spec = self.native.prepare(request).await?;
        let prepared = serde_json::to_vec(spec.current.as_ref().expect("prepared checkpoint"))
            .expect("encode prepared checkpoint");
        assert!(
            prepared == expected,
            "assembly changed the complete canonical checkpoint"
        );
        let scope = self.native.resource_scope(&id).expect("real Native scope");
        let mcp = scope.mcp.lock().unwrap().clone().expect("real MCP owner");
        install_failed_watcher(&mcp, "cold restoration MCP watcher failed")
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "prepare failed watcher fixture",
                source: source.into_boxed_dyn_error(),
            })?;
        drop(spec);
        self.store
            .thread_persistence()
            .history_channel(&id)
            .stop_and_join()
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join failed cold History preparation",
                source: source.into_boxed_dyn_error(),
            })?;
        Err(ThreadAssemblyError::Resource {
            operation: "restore after physical preparation",
            source: Box::new(std::io::Error::other("injected cold restoration failure")),
        })
    }
}

#[tokio::test]
async fn delete_waits_for_failed_only_cold_preparation() -> Result<()> {
    tokio::time::timeout(std::time::Duration::from_secs(30), async {
        use crate::thread_assembler::ThreadAssemblyError;

        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("s2-failed-cold-root", &project.id, "failed cold restore")
            .await?;
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        let identity = runtime.thread_factory.activation(&root.id)?;
        let session = runtime
            .sessions
            .get(&identity.agent.session_id)
            .context("real typed Session")?;
        // A normal preserving member close produces a deterministic cold fixture without
        // racing the idle admission check against asynchronous observation/storage work.
        session.close(&root.id).await?;
        assert!(session.observed_thread(&root.id).is_none());
        assert!(
            runtime
                .store
                .thread_preparation(&root.id)
                .await?
                .unwrap()
                .published
        );
        let resumed = session
            .activate(
                identity.clone(),
                CorruptCurrentAfterLoad::with_pending_model_input(
                    runtime.thread_factory.clone(),
                    &runtime.store,
                    &root.id,
                )
                .await?,
            )
            .await?;
        assert!(
            session
                .thread(&root.id)
                .is_some_and(|owner| owner.same_instance(&resumed))
        );
        CorruptCurrentAfterLoad::assert_recovered_model_input(&resumed).await?;
        session.close(&root.id).await?;
        assert!(session.observed_thread(&root.id).is_none());
        let restore = session
            .activate(
                identity,
                FailedRestoreFactory {
                    native: runtime.thread_factory.clone(),
                    store: runtime.store.clone(),
                },
            )
            .await
            .expect_err("cold preparation must fail and retain its owner");
        let ThreadAssemblyError::ActivationFailed(failure) = restore else {
            anyhow::bail!("unexpected cold activation error: {restore:?}");
        };
        let ThreadAssemblyError::Cleanup { cleanup, .. } = failure.as_ref() else {
            anyhow::bail!("cold activation did not retain a cleanup error: {failure:?}");
        };
        assert!(
            format!("{cleanup:?}").contains("cold restoration MCP watcher failed"),
            "{cleanup:?}"
        );
        assert!(session.observed_thread(&root.id).is_none());
        assert!(session.s2_has_failed_preparation(&root.id));
        let scope = runtime
            .thread_factory
            .resource_scope(&root.id)
            .context("retained failed Native scope")?;
        let mcp = scope
            .mcp
            .lock()
            .unwrap()
            .clone()
            .context("retained MCP owner")?;
        // The restoration close already consumed its failed watcher. The next attempt needs its
        // own recoverable failure to exercise deletion through the same retained resources.
        install_failed_watcher(&mcp, "failed-only deletion MCP watcher failed").await?;
        let original = runtime.store.thread_preparation(&root.id).await?.unwrap();
        let error = runtime
            .delete_thread("failed-only-delete".into(), root.id.clone())
            .await
            .unwrap_err();
        assert!(
            format!("{error:#}").contains("failed-only deletion MCP watcher failed"),
            "{error:#}"
        );
        assert_eq!(
            runtime.store.thread_delete(&root.id).await?.unwrap().phase,
            DeletePhase::Sealed
        );
        assert!(runtime.store.read_thread(&root.id).await?.is_some());
        assert!(session.s2_has_failed_preparation(&root.id));
        assert!(Arc::ptr_eq(
            scope
                .mcp
                .lock()
                .unwrap()
                .as_ref()
                .context("MCP owner retained after delete failure")?,
            &mcp,
        ));
        let retained = runtime.store.thread_preparation(&root.id).await?.unwrap();
        assert_eq!(retained.save, original.save);
        assert!(session.observed_thread(&root.id).is_none());
        runtime
            .delete_thread("failed-only-retry".into(), root.id.clone())
            .await?
            .context("delete retry")?;
        assert_eq!(
            runtime.store.thread_delete(&root.id).await?.unwrap().phase,
            DeletePhase::Published
        );
        assert!(!session.s2_has_failed_preparation(&root.id));
        assert!(scope.mcp.lock().unwrap().is_none());
        assert!(session.observed_thread(&root.id).is_none());
        runtime.shutdown_runtime().await?;
        Ok::<_, anyhow::Error>(())
    })
    .await?
}
