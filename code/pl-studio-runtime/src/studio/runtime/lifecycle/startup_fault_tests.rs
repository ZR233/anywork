//! Startup data migration and recovery fault scenarios, using isolated product roots.
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;

use super::super::StudioRuntime;
use crate::studio::paths::StudioPaths;
use crate::{StudioHostKind, StudioRuntimeOptions, StudioStartupErrorKind, StudioStartupStage};

fn options(home: &Path) -> StudioRuntimeOptions {
    StudioRuntimeOptions {
        studio_home: Some(home.to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    }
}

fn cold_session(paths: &StudioPaths) -> Result<crate::studio::paths::SessionPaths> {
    paths.session_paths("project-cold", "cold")
}

#[test]
fn agent_declaration_invariant_errors_are_internal_and_never_data_recovery_inputs() {
    let config_error = crate::ConfigRuntimeError::BundledAgentCatalog(anyhow::Error::new(
        crate::agent::catalog::AgentCatalogError::invalid("declaration invariant failure"),
    ));
    let input = crate::studio::startup::input_error(config_error);
    let startup = crate::studio::startup::StudioStartupError::input("prepare_configuration", input);
    assert_eq!(startup.kind, StudioStartupErrorKind::Internal);
}

#[tokio::test]
async fn canonical_project_without_sqlite_mirror_accepts_and_restores_new_thread() -> Result<()> {
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;
    use sea_orm::EntityTrait;

    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    // This storage scenario creates a real Thread on the second startup. Give all three
    // startups one durable anonymous route, not a vendor default that needs external credentials.
    let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
    let account_id = AccountId::new("storage-fixture")?;
    let route = ModelRouteConfig {
        account_id: account_id.clone(),
        model_id: "storage-model".into(),
        effort: None,
    };
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id,
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible(
                "Storage fixture",
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
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    // Model a stop between canonical publication and its asynchronous SQLite mirror.
    runtime
        .store
        .persist_directory_summaries(&DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: "project-published".into(),
            name: "Published".into(),
            path: workspace.to_string_lossy().into_owned(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        }))
        .await?;
    runtime.shutdown_runtime().await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let thread = runtime
        .create_thread("project-published", "incoming message")
        .await?;
    let flushed = runtime.flush_persistence().await;
    let shutdown = runtime.shutdown_runtime().await;
    flushed?;
    shutdown?;

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let mirrored = crate::studio::entity::thread::Entity::find_by_id(&thread.id)
        .one(runtime.store.database())
        .await?
        .expect("Thread mirror survived restart");
    assert_eq!(mirrored.project_id, "project-published");
    assert!(
        runtime
            .store
            .paths()
            .session_paths("project-published", &thread.id)?
            .history_database()
            .exists()
    );
    assert!(runtime.runtime_snapshot().await?.startup_recovery.is_none());
    runtime.shutdown_runtime().await?;
    endpoint.set_nonblocking(true)?;
    assert!(
        matches!(
            endpoint.accept(),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock
        ),
        "storage-only startup must not discover or invoke the model endpoint"
    );
    Ok(())
}

async fn seed(home: &Path) -> Result<StudioPaths> {
    let runtime = StudioRuntime::initialize(options(home)).await?;
    let store = runtime.store.clone();
    let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
        crate::studio::store::directory::ProjectDirectoryRecord {
            id: "project-cold".into(),
            name: "Cold".into(),
            path: "/tmp/project-cold".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        },
    );
    let (thread_delta, _) = crate::studio::store::directory::DirectoryDelta::register_root_thread(
        "cold".into(),
        "project-cold",
        "cold",
        pl_protocol::ThreadModeId::simple(),
        pl_protocol::ThreadWorkspaceMode::Local,
        "/tmp/project-cold".into(),
    );
    delta.thread_upserts = thread_delta.thread_upserts;
    store.persist_directory_summaries(&delta).await?;
    runtime.shutdown_runtime().await?;
    let paths = StudioPaths::resolve(Some(home.to_owned()))?;
    let session = cold_session(&paths)?;
    for (path, bytes) in [
        (home.join("agents/preserved.bin"), b"agent bytes".as_slice()),
        (
            session.blobs_dir().join("attachment"),
            b"attachment bytes".as_slice(),
        ),
        (
            home.join("sessions/old/checkpoint"),
            b"old session".as_slice(),
        ),
        (home.join("studio/studio.sqlite"), b"old product".as_slice()),
    ] {
        std::fs::create_dir_all(path.parent().expect("seed parent"))?;
        std::fs::write(path, bytes)?;
    }
    Ok(paths)
}

/// The v2 key had no verifiable credential/query binding. Preserve its exact bytes through a
/// durable load migration and restart rather than claiming those balances belong to today's query.
#[tokio::test]
async fn account_usage_v2_load_migration_preserves_unbound_money_and_survives_restart() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let paths = seed(&home).await?;
    let legacy = r#"{"state":{"kind":"ready","data":{"revision":19,"updatedAt":22,"lastCheckedAt":22,"value":{"configFingerprint":"legacy-inputs","usages":[{"accountId":"legacy-balance","revision":9,"updatedAt":22,"lastOperationId":"legacy-check","state":{"kind":"ready","data":{"data":{"kind":"deepSeekBalance","data":{"is_available":true,"balances":[{"currency":"USD","total_balance":"1.000001","granted_balance":"0.000001","topped_up_balance":"1.000000"},{"currency":"CNY","total_balance":"7.25","granted_balance":"2.00","topped_up_balance":"5.25"}]}}}}}]}}}}"#;
    let store = crate::StudioStore::open(paths.database()).await?;
    store
        .save_setting("observed:accountUsage:v2", legacy)
        .await?;
    store.close().await?;

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert!(runtime.runtime_snapshot().await?.startup_recovery.is_none());
    let upgraded = runtime
        .store
        .load_setting("observed:accountUsage:v2")
        .await?
        .expect("migrated setting");
    let document: serde_json::Value = serde_json::from_str(&upgraded)?;
    assert_eq!(document["formatVersion"], 3);
    assert_eq!(document["legacyUnbound"].as_str(), Some(legacy));
    assert_eq!(
        runtime
            .store
            .read_project("project-cold")
            .await?
            .expect("existing project survived")
            .id,
        "project-cold"
    );
    runtime.shutdown_runtime().await?;

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert!(runtime.runtime_snapshot().await?.startup_recovery.is_none());
    assert_eq!(
        runtime
            .store
            .load_setting("observed:accountUsage:v2")
            .await?,
        Some(upgraded)
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn account_usage_future_cache_version_fails_migration_without_resetting_user_data()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let paths = seed(&home).await?;
    let future = r#"{"formatVersion":999,"futurePayload":"preserve exactly"}"#;
    let catalog = std::fs::read(paths.catalog_file())?;
    let store = crate::StudioStore::open(paths.database()).await?;
    store
        .save_setting("observed:accountUsage:v2", future)
        .await?;
    store.close().await?;
    let error = match StudioRuntime::initialize(options(&home)).await {
        Ok(runtime) => {
            runtime.shutdown_runtime().await?;
            anyhow::bail!("future usage cache must refuse startup");
        }
        Err(error) => error,
    };
    assert_eq!(error.kind, StudioStartupErrorKind::Migration);
    let store = crate::StudioStore::open(paths.database()).await?;
    assert_eq!(
        store.load_setting("observed:accountUsage:v2").await?,
        Some(future.into())
    );
    store.close().await?;
    assert_eq!(std::fs::read(paths.catalog_file())?, catalog);
    assert_eq!(
        std::fs::read(home.join("agents/preserved.bin"))?,
        b"agent bytes"
    );
    Ok(())
}

#[tokio::test]
async fn corrupted_global_inputs_backup_once_and_preserve_external_data() -> Result<()> {
    for fault in [
        "config",
        "product",
        "calls",
        "log",
        "cache",
        "agent",
        "catalog",
        "settings",
        "workspaces",
    ] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let paths = seed(&home).await?;
        let workspace = temp.path().join("workspace");
        std::fs::create_dir_all(&workspace)?;
        std::fs::write(workspace.join("work.txt"), b"user work")?;
        let broken = match fault {
            "config" => home.join("config.toml"),
            "product" => paths.database(),
            "calls" => paths.calls_database(),
            "log" => paths.calls_dir().join("logs/calls-0000020000-000001.jsonl"),
            "agent" => home.join("agents/user.toml"),
            "catalog" => paths.catalog_file(),
            "settings" => paths.settings_file(),
            "workspaces" => paths.workspaces_file(),
            "cache" => {
                let store = crate::StudioStore::open(paths.database()).await?;
                store
                    .save_setting("observed:accountUsage:v2", "invalid json")
                    .await?;
                store.close().await?;
                paths.settings_file()
            }
            _ => unreachable!(),
        };
        if fault != "cache" {
            std::fs::create_dir_all(broken.parent().expect("fault parent"))?;
            std::fs::write(&broken, b"invalid persistent data\n")?;
        }
        let original = std::fs::read(&broken)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let snapshot = runtime.runtime_snapshot().await?;
        assert!(snapshot.state.is_ready(), "{fault}");
        let report = snapshot.startup_recovery.expect("fault triggered recovery");
        let backup = Path::new(&report.backup_path).join("original");
        assert_eq!(
            std::fs::read(backup.join(broken.strip_prefix(&home)?))?,
            original,
            "{fault}"
        );
        assert_eq!(
            std::fs::read(backup.join("agents/preserved.bin"))?,
            b"agent bytes"
        );
        assert_eq!(
            std::fs::read(
                backup
                    .join(cold_session(&paths)?.blobs_dir().strip_prefix(&home)?)
                    .join("attachment")
            )?,
            b"attachment bytes"
        );
        assert_eq!(
            std::fs::read(home.join("sessions/old/checkpoint"))?,
            b"old session"
        );
        assert_eq!(
            std::fs::read(home.join("studio/studio.sqlite"))?,
            b"old product"
        );
        assert_eq!(std::fs::read(workspace.join("work.txt"))?, b"user work");
        assert!(!home.join("startup-recovery.toml").exists());
        assert!(runtime.store.catalog().entries().is_empty());
        runtime.shutdown_runtime().await?;
        let reopened = StudioRuntime::initialize(options(&home)).await?;
        assert!(
            reopened
                .runtime_snapshot()
                .await?
                .startup_recovery
                .is_none()
        );
        assert_eq!(std::fs::read_dir(home.join("startup-backups"))?.count(), 1);
        reopened.shutdown_runtime().await?;
    }
    Ok(())
}

#[tokio::test]
async fn known_configuration_migration_and_cold_sessions_survive_initialization() -> Result<()> {
    use crate::studio::storage::calls::{
        CallsStore, PurposeUsageProjection, SessionUsageProjection,
    };
    let temp = tempfile::tempdir()?;
    let home = temp.path();
    let paths = seed(home).await?;
    let frozen_cost = pl_protocol::RuntimeCostAmount {
        currency: "USD".into(),
        amount: 3.25,
    };
    let calls = CallsStore::open(&paths.calls_database()).await?;
    calls.start().await;
    let mut durable = calls.subscribe_durable_ticket();
    calls.replace_session_usage(SessionUsageProjection {
        root_thread_id: "cold".into(),
        thread_id: "cold".into(),
        revision: 7,
        has_unpriced_usage: false,
        purpose_costs: vec![PurposeUsageProjection {
            purpose: Some("turn".into()),
            estimated_costs: vec![frozen_cost.clone()],
        }],
    })?;
    let ticket = calls.admitted_ticket();
    drop(
        tokio::time::timeout(
            Duration::from_secs(5),
            durable.wait_for(|&watermark| watermark >= ticket),
        )
        .await??,
    );
    calls.close().await?;
    let store = crate::config::ConfigStore::new(paths.config_paths());
    let mut config = crate::config::StudioConfig::default_config().expect("bundled defaults");
    config.instructions.user = "preserved user instructions".into();
    store.save(&config)?;
    let mut value: toml::Value =
        toml::from_str(&std::fs::read_to_string(home.join("config.toml"))?)?;
    let routes = value
        .as_table_mut()
        .expect("config table")
        .remove("mode_model_routes")
        .expect("mode routes");
    value["models"]["routes"]
        .as_table_mut()
        .expect("role routes")
        .insert("planner".into(), routes["mode.simple"].clone());
    value["schema_version"] = 18.into();
    std::fs::write(home.join("config.toml"), toml::to_string(&value)?)?;
    let cold = cold_session(&paths)?.history_database();
    std::fs::write(&cold, b"intentionally invalid cold history")?;
    let runtime = StudioRuntime::initialize(options(home)).await?;
    assert!(runtime.startup_recovery.is_none());
    assert_eq!(
        runtime.config_runtime.read()?.config.instructions.user,
        config.instructions.user
    );
    assert_eq!(std::fs::read(cold)?, b"intentionally invalid cold history");
    assert!(!home.join("startup-backups").exists());
    runtime.shutdown_runtime().await?;
    for _ in 0..2 {
        let calls = CallsStore::open(&paths.calls_database()).await?;
        let rollups = calls.session_cost_rollups().await?;
        assert_eq!(rollups.len(), 1);
        assert_eq!(rollups[0].root_thread_id, "cold");
        assert_eq!(
            rollups[0].estimated_costs.as_slice(),
            std::slice::from_ref(&frozen_cost)
        );
        calls.close().await?;
        let reopened = StudioRuntime::initialize(options(home)).await?;
        assert!(reopened.startup_recovery.is_none());
        reopened.shutdown_runtime().await?;
    }
    Ok(())
}

#[tokio::test]
async fn conflicting_model_id_migration_preserves_original_through_startup() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path();
    let paths = seed(home).await?;
    let mut config = crate::config::StudioConfig::default_config()?;
    let provider = config
        .models
        .accounts
        .get_mut(&pl_model::config::AccountId::new("deepseek")?)
        .expect("default provider");
    if let pl_model::config::AccountModelCatalogConfig::Bundled {
        additional_models, ..
    } = &mut provider.catalog
    {
        additional_models.push(pl_model::model::ModelInfo::compatible("current-id"));
    }
    crate::config::ConfigStore::new(paths.config_paths()).save(&config)?;
    let path = home.join("config.toml");
    let mut value: toml::Value = toml::from_str(&std::fs::read_to_string(&path)?)?;
    value["schema_version"] = 21.into();
    value["models"]["accounts"]["deepseek"]["catalog"]["additional_models"][0]
        .as_table_mut()
        .expect("model table")
        .insert("slug".into(), "conflicting-id".into());
    std::fs::write(&path, toml::to_string(&value)?)?;
    let original = std::fs::read(&path)?;
    for _ in 0..2 {
        let error = match StudioRuntime::initialize(options(home)).await {
            Ok(runtime) => {
                runtime.shutdown_runtime().await?;
                anyhow::bail!("migration conflict unexpectedly started Studio")
            }
            Err(error) => error,
        };
        assert_eq!(error.kind, StudioStartupErrorKind::Migration);
        let public = crate::studio_error_from_anyhow(error.into());
        assert!(public.message.contains("原文件已保留"));
        assert_eq!(std::fs::read(&path)?, original);
        assert!(!home.join("startup-backups").exists());
        assert!(!home.join("startup-recovery.toml").exists());
        assert_eq!(
            std::fs::read(home.join("sessions/old/checkpoint"))?,
            b"old session"
        );
    }
    Ok(())
}

#[tokio::test]
async fn parallel_environment_failure_blocks_reset_and_releases_instance_lock() -> Result<()> {
    use crate::StudioStartupError;
    use crate::studio::startup::{cleanup_error, data_error, input_error};
    for kind in [
        std::io::ErrorKind::PermissionDenied,
        std::io::ErrorKind::StorageFull,
        std::io::ErrorKind::ResourceBusy,
        std::io::ErrorKind::WouldBlock,
        std::io::ErrorKind::Other,
    ] {
        assert_eq!(
            StudioStartupError::input(
                "environment",
                input_error(std::io::Error::new(kind, "environment failure"))
            )
            .kind,
            StudioStartupErrorKind::Environment
        );
    }
    assert_eq!(
        StudioStartupError::input(
            "cleanup",
            cleanup_error(data_error(anyhow::anyhow!("damaged input")))
        )
        .kind,
        StudioStartupErrorKind::Environment
    );
    assert_eq!(
        StudioStartupError::input("invariant", anyhow::anyhow!("internal invariant")).kind,
        StudioStartupErrorKind::Internal
    );
    let temp = tempfile::tempdir()?;
    let paths = seed(temp.path()).await?;
    // Configuration has a data error, while storage encounters an environmental path failure.
    std::fs::write(temp.path().join("config.toml"), b"invalid")?;
    std::fs::remove_dir_all(paths.calls_dir().join("logs"))?;
    std::fs::write(paths.calls_dir().join("logs"), b"occupied path")?;
    let error = StudioRuntime::initialize(options(temp.path()))
        .await
        .err()
        .expect("startup failed");
    assert_eq!(error.kind, StudioStartupErrorKind::Environment);
    assert!(!temp.path().join("startup-backups").exists());
    let _lock = crate::studio::runtime_lock::RuntimeLock::acquire(
        &paths.runtime_lock(),
        StudioHostKind::Test,
    )?;
    assert_eq!(std::fs::read(temp.path().join("config.toml"))?, b"invalid");
    Ok(())
}

#[tokio::test]
async fn default_failure_does_not_create_a_second_backup() -> Result<()> {
    let temp = tempfile::tempdir()?;
    seed(temp.path()).await?;
    std::fs::write(temp.path().join("config.toml"), b"first failure")?;
    let home = temp.path().to_owned();
    let observer = Arc::new(move |stage| {
        if stage == StudioStartupStage::Resetting {
            std::fs::write(home.join("config.toml"), b"second failure")
                .expect("inject default failure");
        }
    });
    let error = StudioRuntime::initialize_with_observer(options(temp.path()), observer)
        .await
        .err()
        .expect("default failed");
    assert_eq!(error.kind, StudioStartupErrorKind::PersistentData);
    assert_eq!(
        std::fs::read_dir(temp.path().join("startup-backups"))?.count(),
        1
    );
    let runtime = StudioRuntime::initialize(options(temp.path())).await?;
    assert!(runtime.startup_recovery.is_some());
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn cancelled_parallel_preparation_closes_storage_before_releasing_lock() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let paths = seed(temp.path()).await?;
    let (reached, wait) = tokio::sync::oneshot::channel();
    let reached = std::sync::Mutex::new(Some(reached));
    let (release, blocked) = std::sync::mpsc::channel();
    let blocked = std::sync::Mutex::new(blocked);
    let observer = Arc::new(move |stage| {
        if stage == StudioStartupStage::WaitingForSteps {
            if let Some(reached) = reached.lock().expect("notification").take() {
                let _ = reached.send(());
            }
            blocked
                .lock()
                .expect("release")
                .recv()
                .expect("release preparation");
        }
    });
    let task = tokio::spawn(StudioRuntime::initialize_with_observer(
        options(temp.path()),
        observer,
    ));
    wait.await?;
    assert!(
        crate::studio::runtime_lock::RuntimeLock::acquire(
            &paths.runtime_lock(),
            StudioHostKind::Test
        )
        .is_err()
    );
    task.abort();
    let _ = task.await;
    release.send(())?;
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if let Ok(lock) = crate::studio::runtime_lock::RuntimeLock::acquire(
                &paths.runtime_lock(),
                StudioHostKind::Test,
            ) {
                return lock;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await?;
    assert!(!temp.path().join("startup-backups").exists());
    // A complete next initialization proves no lingering writer/file lease survives cancellation.
    let runtime = StudioRuntime::initialize(options(temp.path())).await?;
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn invalid_mode_files_stop_startup_without_resetting_configuration_or_sessions() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let paths = seed(&home).await?;
    let mode_path = home.join("modes/mode.broken.json");
    std::fs::create_dir_all(mode_path.parent().unwrap())?;
    std::fs::write(&mode_path, b"{ broken mode document")?;
    let original = std::fs::read(&mode_path)?;
    std::fs::write(
        home.join("config.toml"),
        toml::to_string_pretty(&crate::config::StudioConfig::default_config()?)?,
    )?;
    let config = std::fs::read(home.join("config.toml"))?;
    let result = StudioRuntime::initialize(options(&home)).await;
    let error = match result {
        Ok(runtime) => {
            runtime.shutdown_runtime().await?;
            anyhow::bail!("invalid Mode file unexpectedly initialized");
        }
        Err(error) => error,
    };
    assert_eq!(error.kind, StudioStartupErrorKind::Migration);
    assert_eq!(std::fs::read(&mode_path)?, original);
    assert_eq!(std::fs::read(home.join("config.toml"))?, config);
    assert_eq!(
        std::fs::read(cold_session(&paths)?.blobs_dir().join("attachment"))?,
        b"attachment bytes"
    );
    assert_eq!(
        std::fs::read(home.join("sessions/old/checkpoint"))?,
        b"old session"
    );
    Ok(())
}

async fn seed_legacy_layout_home() -> Result<(tempfile::TempDir, StudioPaths, std::path::PathBuf)> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().to_path_buf();
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let store = runtime.store.clone();
    let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
        crate::studio::store::directory::ProjectDirectoryRecord {
            id: "project-a".into(),
            name: "Layout".into(),
            path: "/tmp/layout".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        },
    );
    let (thread_delta, _) = crate::studio::store::directory::DirectoryDelta::register_root_thread(
        "thread-a".into(),
        "project-a",
        "layout",
        pl_protocol::ThreadModeId::simple(),
        pl_protocol::ThreadWorkspaceMode::Local,
        "/tmp/layout".into(),
    );
    delta.thread_upserts = thread_delta.thread_upserts;
    store.persist_directory_summaries(&delta).await?;
    runtime.shutdown_runtime().await?;
    let studio = StudioPaths::resolve(Some(home.clone()))?;
    let session = studio.session_paths("project-a", "thread-a")?;
    if tokio::fs::try_exists(session.root()).await? {
        tokio::fs::remove_dir_all(session.root()).await?;
    }
    for name in [
        "session-project-layout.toml",
        "session-project-layout.complete",
    ] {
        let path = studio.migrations_dir().join(name);
        match tokio::fs::remove_file(&path).await {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
    }
    let source = studio.legacy_thread_dir("thread-a")?;
    tokio::fs::create_dir_all(source.join("blobs/aa")).await?;
    tokio::fs::write(source.join("history.sqlite"), b"history-bytes").await?;
    tokio::fs::write(source.join("blobs/aa/blob"), b"blob-bytes").await?;
    Ok((temp, studio, source))
}

#[tokio::test]
async fn layout_attachment_toml_fault_does_not_reset_home() -> Result<()> {
    let (temp, paths, source) = seed_legacy_layout_home().await?;
    tokio::fs::write(source.join("attachments.toml"), b"not = [toml").await?;
    let original = tokio::fs::read(source.join("attachments.toml")).await?;
    let error = StudioRuntime::initialize(options(paths.home()))
        .await
        .err()
        .expect("layout toml fault must fail initialize");
    assert_eq!(error.kind, StudioStartupErrorKind::Migration);
    assert!(!temp.path().join("startup-backups").exists());
    let session = paths.session_paths("project-a", "thread-a")?;
    assert_eq!(
        tokio::fs::read(session.attachments_catalog()).await?,
        original
    );
    assert_eq!(
        tokio::fs::read(session.history_database()).await?,
        b"history-bytes"
    );
    tokio::fs::write(
        session.attachments_catalog(),
        toml::to_string(&crate::studio::store::attachment::AttachmentCatalog {
            schema_version: 1,
            thread_id: "thread-a".into(),
            records: Vec::new(),
        })?,
    )
    .await?;
    let runtime = StudioRuntime::initialize(options(paths.home())).await?;
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn layout_target_manifest_fault_does_not_reset_home() -> Result<()> {
    let (temp, paths, source) = seed_legacy_layout_home().await?;
    tokio::fs::write(
        source.join("attachments.toml"),
        toml::to_string(&crate::studio::store::attachment::AttachmentCatalog {
            schema_version: 1,
            thread_id: "thread-a".into(),
            records: Vec::new(),
        })?,
    )
    .await?;
    let session = paths.session_paths("project-a", "thread-a")?;
    tokio::fs::create_dir_all(session.root().parent().expect("parent")).await?;
    pl_tool::workspace::move_owned_path(&source, session.root())?;
    tokio::fs::write(session.session_manifest(), "schemaVersion = 99\nthreadId = \"thread-a\"\nprojectId = \"project-a\"\nrootThreadId = \"thread-a\"\nworkspaceMode = \"local\"\nworkspacePath = \"/tmp/layout\"\ncreatedAt = 1\n").await?;
    let journal = format!(
        "schemaVersion = 1\ncompleted = false\norphans = []\n\n[[moves]]\nthreadId = \"thread-a\"\nprojectId = \"project-a\"\nsourceKey = \"{source}\"\ntargetProjectKey = \"{project}\"\ntargetThreadKey = \"{source}\"\nphase = \"moved\"\n",
        source = crate::studio::paths::thread_storage_key("thread-a")?,
        project = crate::studio::paths::storage_key("project-a", "Project")?,
    );
    tokio::fs::create_dir_all(paths.migrations_dir()).await?;
    tokio::fs::write(
        paths.migrations_dir().join("session-project-layout.toml"),
        journal,
    )
    .await?;
    let original = tokio::fs::read(session.session_manifest()).await?;
    let error = StudioRuntime::initialize(options(paths.home()))
        .await
        .err()
        .expect("bad target manifest must fail initialize");
    assert_eq!(error.kind, StudioStartupErrorKind::Migration);
    assert!(!temp.path().join("startup-backups").exists());
    assert_eq!(tokio::fs::read(session.session_manifest()).await?, original);
    assert_eq!(
        tokio::fs::read(session.history_database()).await?,
        b"history-bytes"
    );
    Ok(())
}
