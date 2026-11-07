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

async fn recover_defaults(
    home: &Path,
    broken: &Path,
    original: &[u8],
) -> Result<std::path::PathBuf> {
    let runtime = StudioRuntime::initialize(options(home)).await?;
    let report = runtime
        .startup_recovery
        .as_ref()
        .expect("recovery reported");
    let archived = std::path::PathBuf::from(&report.backup_path).join("original");
    assert_eq!(
        std::fs::read(archived.join(broken.strip_prefix(home)?))?,
        original
    );
    assert!(runtime.store.catalog().sessions().is_empty());
    let config = crate::config::ConfigStore::new(crate::config::ConfigPaths::from_config_dir(home))
        .load()?;
    assert_eq!(
        config.schema_version,
        crate::config::STUDIO_CONFIG_SCHEMA_VERSION
    );
    runtime.shutdown_runtime().await?;
    let reopened = StudioRuntime::initialize(options(home)).await?;
    assert!(reopened.startup_recovery.is_none());
    reopened.shutdown_runtime().await?;
    assert_eq!(std::fs::read_dir(home.join("startup-backups"))?.count(), 1);
    assert!(!home.join("startup-recovery.toml").exists());
    Ok(archived)
}

// Startup assertions need a durable fence while the runtime remains writable.
// The production shutdown stage also stops the writer and cannot serve this role.
async fn flush_current_writes(runtime: &StudioRuntime) -> Result<()> {
    runtime.store.thread_persistence().wait_for_drain().await?;
    let repository = runtime.agent_facility.persistence.lock().await.clone();
    if let Some(repository) = repository {
        repository
            .flush()
            .await
            .map_err(|error| anyhow::anyhow!(error.to_string()))?;
    }
    Ok(())
}

fn cold_session(paths: &StudioPaths) -> Result<crate::studio::paths::SessionPaths> {
    paths.session_paths("project-cold", "cold")
}

fn write_account_usage_settings_fixture(paths: &StudioPaths, value: &str) -> Result<()> {
    #[derive(serde::Serialize)]
    #[serde(rename_all = "camelCase")]
    struct SettingEntryFixture {
        key: String,
        value: String,
        updated_at: i64,
    }

    #[derive(serde::Serialize)]
    #[serde(rename_all = "camelCase")]
    struct SettingsFixture {
        schema_version: u32,
        revision: u64,
        entries: Vec<SettingEntryFixture>,
    }

    let contents = toml::to_string(&SettingsFixture {
        schema_version: 1,
        revision: 2,
        entries: vec![SettingEntryFixture {
            key: "observed:accountUsage:v2".into(),
            value: value.into(),
            updated_at: 22,
        }],
    })?;
    std::fs::write(paths.settings_file(), contents)?;
    Ok(())
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
            kind: pl_protocol::studio::WorkspaceKind::Project,
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
    let flushed = flush_current_writes(&runtime).await;
    let shutdown = runtime.shutdown_runtime().await;
    flushed?;
    shutdown?;

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let persisted = runtime
        .store
        .catalog()
        .get_session(&thread.id)
        .expect("canonical Thread survived restart");
    assert_eq!(persisted.workspace_id, "project-published");
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

#[tokio::test]
async fn recovery_scope_and_execution_dependencies_survive_bot_materialization_and_scan_races()
-> Result<()> {
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::{StudioRecoveryImpact as Impact, StudioRecoveryIssueScope as Scope};
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let original = temp.path().join("original-project");
    tokio::fs::create_dir_all(&original).await?;
    let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
    let account = AccountId::new("recovery-fixture")?;
    let route = ModelRouteConfig {
        account_id: account.clone(),
        model_id: "recovery-model".into(),
        effort: None,
    };
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account,
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible(
                "Recovery fixture",
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
    config.runtime.tool_capabilities = pl_tool::workspace::ToolCapabilityConfig {
        exec: false,
        workspace_files: false,
        skills: false,
        mcp: false,
        lsp: false,
        ask_user: false,
        git: false,
    };
    config.skills.enabled = false;
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    super::super::background_task::finish(&runtime.recovery_task)
        .await
        .map_err(anyhow::Error::new)?;
    let project = runtime.open_project(&original).await?;
    let ordinary = runtime.create_thread(&project.id, "ordinary owner").await?;
    let bot_root_id = "bot-recovery-root";
    runtime
        .bots
        .install_workspace_migration_fixture("botR1234", bot_root_id, &project.id)
        .await?;
    let bot_root = runtime
        .create_thread_with_id(bot_root_id, &project.id, "bot owner")
        .await?;
    flush_current_writes(&runtime).await?;
    let managed = runtime
        .store
        .workspace_identity(bot_root_id)
        .await?
        .unwrap()
        .root;
    assert_ne!(managed, bot_root.workspace_path);
    let marker = Path::new(&managed)
        .join(pl_tool::workspace::SessionFiles::new(bot_root_id).root())
        .join(".migration-complete");
    let completion = tokio::fs::read(&marker).await?;
    tokio::fs::rename(&original, temp.path().join("original-offline")).await?;
    let before = runtime.store.catalog().sessions().len();
    // No scan has described this failure yet: actual new-root preparation must still reject it
    // before directory publication, and the hot ordinary owner cannot reuse a cached binding.
    assert!(
        runtime
            .create_thread(&project.id, "must not publish")
            .await
            .is_err()
    );
    assert_eq!(runtime.store.catalog().sessions().len(), before);
    let physical = runtime.ensure_thread_owner(&ordinary.id).await.unwrap_err();
    assert!(
        physical
            .chain()
            .any(|error| error.downcast_ref::<std::io::Error>().is_some())
    );
    runtime.retry_recovery().await?;
    super::super::background_task::finish(&runtime.recovery_task)
        .await
        .map_err(anyhow::Error::new)?;
    let issues = runtime.recovery_issues();
    assert!(issues.iter().any(|issue| issue.scope == Scope::Project
        && issue.workspace_id.as_deref() == Some(&project.id)
        && issue.impact == Impact::ExecutionBlocked));
    assert!(issues.iter().any(|issue| issue.scope == Scope::Thread
        && issue.thread_id.as_deref() == Some(&ordinary.id)
        && issue.impact == Impact::ExecutionBlocked));
    assert!(!issues.iter().any(|issue| issue.scope == Scope::Thread
        && issue.thread_id.as_deref() == Some(bot_root_id)
        && issue.impact != Impact::Advisory));
    assert!(
        runtime.ensure_thread_owner(bot_root_id).await.is_ok(),
        "completed healthy M does not inherit Project O failure"
    );
    assert!(
        runtime
            .create_thread_with_id(bot_root_id, &project.id, "same binding")
            .await
            .is_ok(),
        "existing identity is a Thread target, not new Project preparation"
    );
    assert!(
        runtime
            .create_thread(&project.id, "project gate remains blocked")
            .await
            .is_err()
    );
    assert_eq!(runtime.store.catalog().sessions().len(), before);
    assert!(
        runtime.thread_snapshot(&ordinary.id).await.is_ok(),
        "execution blockage preserves safe readonly history"
    );

    // Identity M is persisted before the copy completion ACK: losing that completion must make
    // the original source a real dependency again, rather than silently treating M as complete.
    tokio::fs::remove_file(&marker).await?;
    runtime.retry_recovery().await?;
    super::super::background_task::finish(&runtime.recovery_task)
        .await
        .map_err(anyhow::Error::new)?;
    assert!(runtime.ensure_thread_owner(bot_root_id).await.is_err());
    assert!(
        runtime
            .recovery_issues()
            .iter()
            .any(|issue| issue.thread_id.as_deref() == Some(bot_root_id)
                && issue.impact == Impact::ExecutionBlocked)
    );
    tokio::fs::write(&marker, completion).await?;
    runtime.retry_recovery().await?;
    super::super::background_task::finish(&runtime.recovery_task)
        .await
        .map_err(anyhow::Error::new)?;
    runtime.ensure_thread_owner(bot_root_id).await?;
    tokio::fs::rename(&managed, temp.path().join("managed-offline")).await?;
    assert!(
        runtime.ensure_thread_owner(bot_root_id).await.is_err(),
        "hot M resource loss is checked without another scan"
    );
    assert!(runtime.thread_snapshot(bot_root_id).await.is_ok());
    runtime.shutdown_runtime().await?;
    endpoint.set_nonblocking(true)?;
    assert!(
        matches!(endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock),
        "workspace admission must not call the model endpoint"
    );
    Ok(())
}

async fn seed(home: &Path) -> Result<StudioPaths> {
    let runtime = StudioRuntime::initialize(options(home)).await?;
    let store = runtime.store.clone();
    let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
        crate::studio::store::directory::ProjectDirectoryRecord {
            id: "project-cold".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Cold".into(),
            path: "/tmp/project-cold".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        },
    );
    let (thread_delta, _, _) = crate::studio::store::directory::DirectoryDelta::register_session(
        "cold".into(),
        "project-cold",
        "cold",
        pl_protocol::ThreadModeId::simple(),
        pl_protocol::ThreadWorkspaceMode::Local,
        "/tmp/project-cold".into(),
        crate::config::ROOT_AGENT_ROUTE_KEY,
    );
    delta.session_upserts = thread_delta.session_upserts;
    delta.agent_upserts = thread_delta.agent_upserts;
    store.persist_directory_summaries(&delta).await?;
    runtime.shutdown_runtime().await?;
    let paths = StudioPaths::resolve(Some(home.to_owned()))?;
    let session = cold_session(&paths)?;
    for (path, bytes) in [
        (home.join("agents/preserved.bin"), b"agent bytes".as_slice()),
        (
            session.resources_dir().join("attachment"),
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
async fn catalog_after_636_stale_child_modes_start_without_reset() -> Result<()> {
    let fixture = include_str!("../../../../tests/fixtures/migration-636/catalog-v4.toml");
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let paths = seed(&home).await?;
    let mut legacy: toml::Table = toml::from_str(fixture)?;
    legacy["schemaVersion"] = 5_i64.into();
    for entry in legacy["entries"].as_array_mut().expect("synthetic entries") {
        let table = entry.as_table_mut().expect("synthetic entry");
        let workspace = table
            .remove("projectId")
            .expect("published project identity");
        table.insert("workspaceId".into(), workspace);
    }
    tokio::fs::write(paths.catalog_file(), toml::to_string(&legacy)?).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert!(
        runtime.startup_recovery.is_none(),
        "valid old mode copies must not reset the product"
    );
    let catalog = runtime.store.catalog();
    assert_eq!(catalog.sessions().len(), 1);
    assert_eq!(catalog.agents().len(), 2);
    let session = catalog.get_session("cold").expect("original root");
    assert_eq!(session.root_agent_id, "cold");
    assert_eq!(session.mode, pl_protocol::ThreadModeId::simple());
    let child = catalog
        .get_agent("synthetic-child")
        .expect("original child");
    assert_eq!(child.parent_agent_id.as_deref(), Some("cold"));
    assert_eq!(child.session_id, "cold");
    assert_eq!(
        child.frozen_model().expect("frozen model").model_id,
        "synthetic-model"
    );
    assert!(
        runtime.threads.observed_threads().is_empty(),
        "directory migration stays cold"
    );
    runtime.shutdown_runtime().await?;
    let upgraded = tokio::fs::read(paths.catalog_file()).await?;
    let reopened = StudioRuntime::initialize(options(&home)).await?;
    assert!(reopened.startup_recovery.is_none());
    assert_eq!(reopened.store.catalog().agents().len(), 2);
    reopened.shutdown_runtime().await?;
    assert_eq!(tokio::fs::read(paths.catalog_file()).await?, upgraded);
    assert!(!home.join("startup-backups").exists());
    Ok(())
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
    write_account_usage_settings_fixture(&paths, legacy)?;

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert!(runtime.runtime_snapshot().await?.startup_recovery.is_none());
    let upgraded = runtime
        .store
        .load_setting("observed:accountUsage:v2")
        .await?
        .expect("migrated setting");
    let document: serde_json::Value = serde_json::from_str(&upgraded)?;
    assert!(document.get("formatVersion").is_none());
    assert_eq!(document["legacyUnbound"].as_str(), Some(legacy));
    let current_settings: toml::Table =
        toml::from_str(&std::fs::read_to_string(paths.settings_file())?)?;
    assert_eq!(current_settings["schemaVersion"].as_integer(), Some(2));
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
async fn account_usage_future_cache_is_backed_up_before_default_startup() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let paths = seed(&home).await?;
    let future = r#"{"formatVersion":999,"futurePayload":"preserve exactly"}"#;
    let catalog = std::fs::read(paths.catalog_file())?;
    write_account_usage_settings_fixture(&paths, future)?;
    let original_settings = std::fs::read(paths.settings_file())?;
    let archived = recover_defaults(&home, &paths.settings_file(), &original_settings).await?;
    assert_eq!(std::fs::read(archived.join("data/catalog.toml"))?, catalog);
    assert_eq!(
        std::fs::read(archived.join("agents/preserved.bin"))?,
        b"agent bytes"
    );
    Ok(())
}

#[tokio::test]
async fn canonical_toml_document_faults_are_backed_up_before_default_startup() -> Result<()> {
    for name in ["catalog", "settings", "workspaces"] {
        for (case, bytes) in [
            ("future-version", b"schemaVersion = 99\n".as_slice()),
            ("malformed", b"schemaVersion = [\n".as_slice()),
        ] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let paths = seed(&home).await?;
            let path = match name {
                "catalog" => paths.catalog_file(),
                "settings" => paths.settings_file(),
                "workspaces" => paths.workspaces_file(),
                _ => unreachable!(),
            };
            std::fs::write(&path, bytes)?;
            let original = std::fs::read(&path)?;
            recover_defaults(&home, &path, &original)
                .await
                .unwrap_or_else(|error| panic!("{name} {case}: {error:#}"));
        }
    }
    Ok(())
}

#[tokio::test]
async fn configuration_agent_and_cache_migration_faults_preserve_originals() -> Result<()> {
    for fault in ["config", "agent", "cache"] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let paths = seed(&home).await?;
        let broken = match fault {
            "config" => home.join("config.toml"),
            "agent" => home.join("agents/user.toml"),
            "cache" => {
                write_account_usage_settings_fixture(&paths, "invalid json")?;
                paths.settings_file()
            }
            _ => unreachable!(),
        };
        if fault != "cache" {
            std::fs::create_dir_all(broken.parent().expect("fault parent"))?;
            std::fs::write(&broken, b"invalid persistent data\n")?;
        }
        let original = std::fs::read(&broken)?;
        recover_defaults(&home, &broken, &original)
            .await
            .unwrap_or_else(|error| panic!("{fault}: {error:#}"));
    }
    Ok(())
}

#[tokio::test]
async fn unsupported_layout_archives_sources_staging_and_configuration_before_defaults()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path();
    seed(home).await?;
    let journal = home.join("storage-migration.toml");
    let unknown = b"schemaVersion = 99\noperationId = 'future-layout'\n";
    std::fs::write(&journal, unknown)?;
    let materials = [
        "migration-backups/future-layout/v2/history.sqlite-wal",
        "migration-backups/future-layout/current-home/data/staged.bin",
        "modes/custom.toml",
        "mcp/host/unknown.toml",
    ];
    for name in materials {
        let path = home.join(name);
        std::fs::create_dir_all(path.parent().expect("fixture parent"))?;
        std::fs::write(path, name.as_bytes())?;
    }
    let archived = recover_defaults(home, &journal, unknown).await?;
    for name in materials {
        assert_eq!(std::fs::read(archived.join(name))?, name.as_bytes());
    }
    Ok(())
}

#[tokio::test]
async fn corrupted_current_storage_is_archived_and_preserves_external_data() -> Result<()> {
    for fault in ["product", "calls", "log"] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let paths = seed(&home).await?;
        let workspace = temp.path().join("workspace");
        std::fs::create_dir_all(&workspace)?;
        std::fs::write(workspace.join("work.txt"), b"user work")?;
        let broken = match fault {
            "product" => paths.database(),
            "calls" => paths.calls_database(),
            "log" => paths.calls_dir().join("logs/calls-0000020000-000001.jsonl"),
            _ => unreachable!(),
        };
        std::fs::create_dir_all(broken.parent().expect("fault parent"))?;
        std::fs::write(&broken, b"invalid persistent data\n")?;
        let original = std::fs::read(&broken)?;
        let archived = recover_defaults(&home, &broken, &original).await?;
        assert_eq!(
            std::fs::read(
                archived
                    .join(cold_session(&paths)?.resources_dir().strip_prefix(&home)?)
                    .join("attachment")
            )?,
            b"attachment bytes"
        );
        assert_eq!(
            std::fs::read(archived.join("agents/preserved.bin"))?,
            b"agent bytes"
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
    }
    Ok(())
}

#[tokio::test]
async fn known_configuration_migration_and_cold_sessions_survive_initialization() -> Result<()> {
    use crate::studio::storage::calls::{
        CallsStore, PurposeUsageProjection, SessionUsageProjection,
    };
    use anyhow::Context as _;
    let temp = tempfile::tempdir()?;
    let home = temp.path();
    let paths = seed(home).await?;
    let frozen_cost = pl_protocol::RuntimeCostAmount {
        currency: "USD".into(),
        amount: 3.25,
    };
    let calls = CallsStore::open(&paths.calls_database()).await?;
    calls.start().await;
    let mut processed = calls.subscribe_processed_ticket();
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
            processed.wait_for(|&watermark| watermark >= ticket),
        )
        .await??,
    );
    calls.close().await?;
    let store = crate::config::ConfigStore::new(paths.config_paths());
    // seed() used today's startup to establish the cold directory. Schema 18
    // predates the separate MCP documents that this fresh startup created.
    // Remove only this TempDir's byte-verified defaults, never unknown documents.
    let host_mcp = paths.config_paths().mcp_host_dir();
    let seeded_mcp = crate::config::McpFileV1::default_host_builtins()
        .into_iter()
        .map(|document| {
            let path = host_mcp.join(crate::config::canonical_mcp_filename(&document.id)?);
            Ok((path, document))
        })
        .collect::<Result<Vec<_>>>()?;
    let expected_paths = seeded_mcp
        .iter()
        .map(|(path, _)| path.clone())
        .collect::<std::collections::BTreeSet<_>>();
    let actual_paths = std::fs::read_dir(&host_mcp)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<std::io::Result<std::collections::BTreeSet<_>>>()?;
    assert_eq!(actual_paths, expected_paths, "unexpected seeded MCP files");
    for (path, document) in &seeded_mcp {
        assert!(std::fs::symlink_metadata(path)?.file_type().is_file());
        assert_eq!(std::fs::read(path)?, document.encode()?.as_bytes());
    }
    for (path, _) in &seeded_mcp {
        std::fs::remove_file(path)?;
    }
    std::fs::remove_dir(&host_mcp)?;
    assert!(!host_mcp.exists());
    let migration_cwd = std::env::current_dir()?
        .to_str()
        .context("MCP migration fixture needs a UTF-8 cwd")?
        .to_owned();
    let migrated_mcp = seeded_mcp
        .into_iter()
        .map(|(path, document)| {
            let cwd = (document.id == crate::config::mcp::ZHIPU_VISION_MCP_ID)
                .then(|| migration_cwd.clone());
            let expected =
                crate::config::McpFileV1::new_builtin(document.id, true, cwd).encode()?;
            Ok((path, expected))
        })
        .collect::<Result<Vec<_>>>()?;
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
    // Schema 18 predates the explicit account authentication field.
    for (_, account) in value["models"]["accounts"]
        .as_table_mut()
        .expect("account table")
        .iter_mut()
    {
        account
            .as_table_mut()
            .expect("account")
            .remove("authentication")
            .expect("current account authentication");
    }
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
    for (path, expected) in &migrated_mcp {
        assert_eq!(std::fs::read(path)?, expected.as_bytes());
    }
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
        for (path, expected) in &migrated_mcp {
            assert_eq!(std::fs::read(path)?, expected.as_bytes());
        }
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
    recover_defaults(home, &path, &original).await?;
    assert_eq!(
        std::fs::read(home.join("sessions/old/checkpoint"))?,
        b"old session"
    );
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
    // An already-authorized recovery operation may predate this layout upgrade. A failed
    // unpublished attempt must resume that operation, never start a second backup/reset.
    crate::studio::startup::StartupBackup::begin(temp.path(), "existing recovery".into())?;
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
    assert_eq!(error.kind, StudioStartupErrorKind::Migration);
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
async fn invalid_mode_files_are_archived_before_default_startup() -> Result<()> {
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
    let archived = recover_defaults(&home, &mode_path, &original).await?;
    assert_eq!(std::fs::read(archived.join("config.toml"))?, config);
    assert_eq!(
        std::fs::read(
            archived.join(
                cold_session(&paths)?
                    .resources_dir()
                    .join("attachment")
                    .strip_prefix(&home)?
            )
        )?,
        b"attachment bytes"
    );
    assert_eq!(
        std::fs::read(home.join("sessions/old/checkpoint"))?,
        b"old session"
    );
    Ok(())
}

/// A passive Chat open prepares supported old v2 content through the Storage migration barrier,
/// preserving public bytes without activating execution or requiring caller-side preparation.
#[tokio::test]
async fn cold_v2_history_supports_passive_chat_content_without_activation() -> Result<()> {
    use crate::studio::storage::history::HistoryStore;
    use anyhow::Context;
    use sea_orm::{ConnectionTrait, Database};

    let temp = tempfile::tempdir()?;
    let paths = seed(temp.path()).await?;
    let path = cold_session(&paths)?.history_database();
    let history = HistoryStore::open(&path, "cold").await?;
    let mut item = pl_protocol::ThreadItem::completed_user_message(
        "input-detail-first".into(),
        "cold".into(),
        "".into(),
        "preserved detail 中文\n".into(),
        vec![],
        17,
    );
    item.ordinal = 1;
    item.revision = 1;
    history.commit(1, std::slice::from_ref(&item), &[]).await?;
    drop(history);
    let db = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
    let facts = db
        .query_one_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT COUNT(*) AS count FROM conversation_atom_facts",
        ))
        .await?
        .expect("fixture fact count");
    assert_eq!(
        facts.try_get::<i64>("", "count")?,
        0,
        "downgrade fixture must not discard real canonical inputs"
    );
    db.execute_unprepared(
        "DROP TABLE seaql_migrations;
         DROP TABLE IF EXISTS timeline_item_members;
         DROP TABLE IF EXISTS timeline_items;
         DROP TABLE IF EXISTS timeline_projection_state;
         DROP TABLE conversation_atom_facts;
         DROP TABLE IF EXISTS timeline_records;
         DROP TABLE conversation_content_chunks;
         DROP TABLE conversation_contents;
         DROP TABLE conversation_items;
         DROP TABLE conversation_sources;
         DROP TABLE conversation_view_entries;
         DROP TABLE conversation_view_state;
         ALTER TABLE history_input_identities DROP COLUMN request_digest;
         ALTER TABLE history_meta DROP COLUMN model_route_json;
         ALTER TABLE history_meta DROP COLUMN model_route_hash;
         UPDATE history_meta SET schema_version=8",
    )
    .await?;
    db.close().await?;
    let runtime = StudioRuntime::initialize(options(temp.path())).await?;
    assert!(runtime.threads.observed_thread("cold").is_none());
    let demand = pl_protocol::ReadDemand {
        max_items: 1,
        max_bytes: 64 * 1024,
    };
    let mut feed = runtime
        .open_conversation_feed("cold", pl_protocol::ChatScope::Main, demand)
        .await?;
    let reader = feed.reader().clone();
    let manifest = reader.list_contents(&item.id, None, demand).await?;
    let reference = &manifest
        .entries
        .first()
        .context("preserved manifest")?
        .reference;
    let detail = reader
        .read_content(
            reference,
            pl_protocol::ContentRange {
                offset: 0,
                max_bytes: 128,
            },
        )
        .await?;
    assert_eq!(detail.bytes, "preserved detail 中文\n".as_bytes());
    assert!(detail.sealed);
    assert!(runtime.threads.observed_thread("cold").is_none());
    feed.close().await?;
    reader.close().await?;
    runtime.shutdown_runtime().await?;
    Ok(())
}
