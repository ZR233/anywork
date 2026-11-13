//! Thread/Project 生命周期命令目录页：对外命令入口与 projects/threads 子模块组织。

mod archive;
mod archive_worktrees;
mod delete;
mod projects;

mod threads;

use anyhow::{Context, Result};

use super::{StudioRuntime, StudioStartNewThreadRequest, StudioStartNewThreadResponse};

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn thread_lifecycle_admission(
        &self,
    ) -> Result<tokio::sync::OwnedMutexGuard<()>> {
        // A bot operation can be awaited by shutdown while it is still queued for this lock.
        // The existing one-way latch wakes that unadmitted operation instead of creating a
        // lifecycle -> bot join -> lifecycle cycle. No accepted worker is cancelled here.
        let guard = tokio::select! {
            biased;
            () = self.shutdown_latch.committed() => anyhow::bail!("Studio runtime is closing"),
            guard = self.lifecycle_lock.clone().lock_owned() => guard,
        };
        anyhow::ensure!(!self.shutdown_committed(), "Studio runtime is closing");
        Ok(guard)
    }

    pub(in crate::studio::runtime) async fn run_thread_lifecycle_operation<T: Send + 'static>(
        &self,
        operation: impl std::future::Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        let lifecycle = self.thread_lifecycle_admission().await?;
        // Lifecycle admission also serializes slot replacement. Observe the previous completion
        // before replacing it; cancellation while joining leaves that same future retained.
        let joined = super::background_task::finish(&self.thread_lifecycle_task).await;
        self.thread_lifecycle_task.lock().await.take();
        joined.context("previous Thread lifecycle operation failed to join")?;
        let (publication, result) = tokio::sync::oneshot::channel();
        let mut slot = self.thread_lifecycle_task.lock().await;
        *slot = Some(super::background_task::BackgroundTask::new(tokio::spawn(
            async move {
                let _lifecycle = lifecycle;
                let outcome = operation.await;
                let _ = publication.send(outcome);
            },
        )));
        drop(slot);
        result
            .await
            .context("Thread lifecycle worker stopped without a conclusion")?
    }

    /// Creates a root Thread and accepts its first Turn from the shared API request.
    pub async fn create_thread_command(
        &self,
        workspace_id: String,
        request: pl_protocol::studio::CreateThreadRequest,
        preparation_observer: Option<super::ThreadPreparationObserver>,
    ) -> Result<StudioStartNewThreadResponse> {
        let mode = pl_protocol::ThreadModeId::from_label(request.mode.trim()).map_err(|_| {
            anyhow::Error::new(pl_protocol::studio::StudioError::invalid_argument(
                "mode must be an available mode.* id",
            ))
        })?;
        self.start_new_thread(StudioStartNewThreadRequest {
            workspace_id,
            title: request.title,
            input: request.input,
            mode,
            route: request.route,
            delegation_mode: request.delegation_mode,
            delegation_preference: request.delegation_preference,
            workspace_mode: request.workspace_mode,
            options: super::StudioSubmitPromptOptions::default(),
            preparation_observer,
        })
        .await
    }
}

#[cfg(test)]
mod s2_delete_recovery_tests {
    //! Publication retries consume the durable deletion transaction after directory removal.
    use super::super::StudioRuntime;
    use crate::{
        StudioHostKind, StudioRuntimeOptions,
        config::{ConfigPaths, ConfigStore, StudioConfig},
        studio::store::thread_delete::DeletePhase,
    };
    use anyhow::{Context, Result};
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::ModelInfo,
        protocol::ProtocolEndpoint,
    };
    use std::path::Path;

    fn options(home: &Path) -> StudioRuntimeOptions {
        StudioRuntimeOptions {
            studio_home: Some(home.to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        }
    }

    fn configure(home: &Path) -> Result<std::net::TcpListener> {
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account_id = AccountId::new("s2-delete-fixture")?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: "unused-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "S2 deletion fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![ModelInfo::compatible(&route.model_id)],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
        Ok(endpoint)
    }

    async fn publication_retry(restart: bool) -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let mut runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("s2-delete-root", &project.id, "delete publication")
            .await?;
        *runtime.s2_delete_publication_failure.lock().unwrap() = Some(root.id.clone());
        let error = runtime
            .delete_thread("first-delete".into(), root.id.clone())
            .await
            .unwrap_err();
        assert!(
            format!("{error:#}").contains("injected failure before delete Published persistence")
        );
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
    async fn s2_delete_publication_retries_after_directory_removal() -> Result<()> {
        tokio::time::timeout(std::time::Duration::from_secs(30), publication_retry(false)).await?
    }

    #[tokio::test]
    async fn s2_delete_publication_recovers_after_directory_removal_and_restart() -> Result<()> {
        tokio::time::timeout(std::time::Duration::from_secs(30), publication_retry(true)).await?
    }

    #[derive(Debug)]
    struct FailedRestoreFactory {
        native: crate::studio::thread_factory::StudioThreadFactory,
        fail: std::sync::Arc<std::sync::atomic::AtomicBool>,
    }

    impl crate::thread_assembler::StudioActivationFactory for FailedRestoreFactory {
        async fn root_delegation(
            &self,
            identity: &crate::thread_assembler::ThreadActivation,
        ) -> std::result::Result<
            pl_protocol::DelegationSettings,
            crate::thread_assembler::ThreadAssemblyError,
        > {
            self.native.root_delegation(identity).await
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
            let spec = self.native.prepare(request).await?;
            let scope = self.native.resource_scope(&id).expect("real Native scope");
            assert!(scope.mcp.lock().unwrap().is_some());
            *scope.s2_mcp_close_failure.lock().unwrap() = Some(self.fail.clone());
            drop(spec);
            Err(ThreadAssemblyError::Resource {
                operation: "restore after physical preparation",
                source: Box::new(std::io::Error::other("injected cold restoration failure")),
            })
        }
    }

    #[tokio::test]
    async fn s2_delete_waits_for_failed_only_cold_preparation() -> Result<()> {
        tokio::time::timeout(std::time::Duration::from_secs(30), async {
            use std::sync::{
                Arc,
                atomic::{AtomicBool, Ordering},
            };
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
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
            let fail = Arc::new(AtomicBool::new(true));
            assert!(
                session
                    .activate(
                        identity,
                        FailedRestoreFactory {
                            native: runtime.thread_factory.clone(),
                            fail: fail.clone(),
                        }
                    )
                    .await
                    .is_err()
            );
            assert!(session.observed_thread(&root.id).is_none());
            assert!(session.s2_has_failed_preparation(&root.id));
            let scope = runtime
                .thread_factory
                .resource_scope(&root.id)
                .context("retained failed Native scope")?;
            assert!(scope.mcp.lock().unwrap().is_some());
            let original = runtime.store.thread_preparation(&root.id).await?.unwrap();
            let error = runtime
                .delete_thread("failed-only-delete".into(), root.id.clone())
                .await
                .unwrap_err();
            assert!(
                format!("{error:#}").contains("injected failed preparation MCP close"),
                "{error:#}"
            );
            assert_eq!(
                runtime.store.thread_delete(&root.id).await?.unwrap().phase,
                DeletePhase::Sealed
            );
            assert!(runtime.store.read_thread(&root.id).await?.is_some());
            assert!(session.s2_has_failed_preparation(&root.id));
            assert!(scope.mcp.lock().unwrap().is_some());
            let retained = runtime.store.thread_preparation(&root.id).await?.unwrap();
            assert_eq!(retained.save, original.save);
            assert!(session.observed_thread(&root.id).is_none());
            fail.store(false, Ordering::SeqCst);
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
}
