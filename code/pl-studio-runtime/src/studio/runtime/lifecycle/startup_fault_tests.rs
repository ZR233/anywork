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

async fn seed(home: &Path) -> Result<StudioPaths> {
    let runtime = StudioRuntime::initialize(options(home)).await?;
    runtime.shutdown_runtime().await?;
    let paths = StudioPaths::resolve(Some(home.to_owned()))?;
    for (path, bytes) in [
        (home.join("agents/preserved.bin"), b"agent bytes".as_slice()),
        (
            paths.thread_blobs_dir("cold").join("attachment"),
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
                    .join(paths.thread_blobs_dir("cold").strip_prefix(&home)?)
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
    let cold = paths.thread_storage_dir("cold").join("history.sqlite");
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
        std::fs::read(paths.thread_blobs_dir("cold").join("attachment"))?,
        b"attachment bytes"
    );
    assert_eq!(
        std::fs::read(home.join("sessions/old/checkpoint"))?,
        b"old session"
    );
    Ok(())
}
