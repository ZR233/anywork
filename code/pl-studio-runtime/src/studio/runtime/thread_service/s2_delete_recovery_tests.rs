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
    assert!(format!("{error:#}").contains("injected failure before delete Published persistence"));
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
