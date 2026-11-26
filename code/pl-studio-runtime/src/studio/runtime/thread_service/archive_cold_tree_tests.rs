//! Cold archive must not activate execution. Reading the archived current upgrades the
//! frozen schema-24 checkpoint to Schema 27.
use std::collections::BTreeMap;
use std::path::Path;

use anyhow::{Context, Result};
use crate::studio::storage::legacy_checkpoint::ThreadCheckpoint;
use pl_core::{
    context::{
        ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload, content_hash,
    },
    thread::{ThreadLifecycle, ThreadSnapshot, extensions::ExtensionRecord},
};
use sea_orm::{ConnectionTrait, Database, DatabaseBackend, Statement};

use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::studio::store::directory::DirectoryDelta;
use crate::{StudioHostKind, StudioRuntimeOptions};

const LEGACY_ROUTE: &str = r#"{"provider":"deepseek","model":"deepseek-flash","effort":"high"}"#;
const SCHEMA_27_MIGRATION: &str = "m20261125_000027_boundary_role_and_sparse_indexes";

#[tokio::test]
async fn archive_cold_tree_prepares_legacy_checkpoints_without_execution() -> Result<()> {
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::ModelDefinition,
    };
    use pl_tool::workspace::SessionFiles;

    let directory = tempfile::tempdir()?;
    let home = directory.path().join("home");
    let workspace = directory.path().join("workspace");
    tokio::fs::create_dir(&workspace).await?;
    let endpoint = pl_provider_fixture::FixtureServer::start(Vec::new()).await?;
    let account_id = AccountId::new("archive-fixture")?;
    let route = ModelRouteConfig {
        account_id: account_id.clone(),
        model_id: "archive-model".into(),
        effort: None,
    };
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id,
        AccountConfig::from_explicit_models(
            pl_model::protocol::providers::openai::compatible_endpoint(
                "Archive fixture",
                endpoint.base_url(),
            ),
            vec![ModelDefinition::compatible(&route.model_id)],
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
    let options = || StudioRuntimeOptions {
        studio_home: Some(home.clone()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    };
    let runtime = crate::StudioRuntime::initialize(options()).await?;
    let project = runtime.open_project(&workspace).await?;
    runtime.shutdown_runtime().await?;
    drop(runtime);

    let store = crate::studio::StudioStore::open(&home.join("data/studio.sqlite")).await?;
    let root_id = "archive-current-root";
    let mut members = Vec::new();
    for id in [root_id, "archive-legacy-envelope", "archive-legacy-route"] {
        let mut thread = bound_thread(id);
        thread.role = if id == root_id {
            crate::config::ROOT_AGENT_ROUTE_KEY.into()
        } else {
            "executor".into()
        };
        thread.workspace_id = project.id.clone();
        thread.workspace_path = project.path.clone();
        thread.root_thread_id = root_id.into();
        thread.parent_thread_id = (id != root_id).then(|| root_id.to_owned());
        let (session, member) = crate::studio::records::directory_facts_from_thread(&thread);
        let mut delta = DirectoryDelta {
            agent_upserts: vec![member],
            ..Default::default()
        };
        if let Some(session) = session {
            delta.session_upserts = vec![session];
        }
        store.persist_directory_summaries(&delta).await?;
        let session = store.session_paths(&project.id, id)?;
        let mut original = saved_state(BTreeMap::from([(
            "vendor.unknown".into(),
            record(6, "vendor.unknown", 7, "preserve opaque state")?,
        )]));
        original.lifecycle = ThreadLifecycle::Closed;
        if id == "archive-legacy-route" {
            // This saved route's account is no longer configured. Only its representation
            // may be migrated; archive must not resolve it for model execution.
            original.extensions.insert(
                "studio.model-route".into(),
                record(2, "pl.studio.model-route", 1, LEGACY_ROUTE)?,
            );
            crate::studio::model_route::migration::upgrade(&mut original)?;
        }
        seed_schema24_checkpoint(&session.history_database(), id, &original).await?;
        let files = SessionFiles::new(id);
        for temp in [session.temp_dir(), workspace.join(files.temp())] {
            tokio::fs::create_dir_all(&temp).await?;
            tokio::fs::write(temp.join("disposable"), b"temporary").await?;
        }
        tokio::fs::create_dir_all(workspace.join(files.artifacts())).await?;
        tokio::fs::write(workspace.join(files.artifacts()).join("delivery"), b"keep").await?;
        tokio::fs::create_dir_all(session.root().join("resources")).await?;
        tokio::fs::write(session.root().join("resources/reliable"), b"reliable").await?;
        members.push((thread, session, original));
    }
    drop(store);

    let runtime = crate::StudioRuntime::initialize(options()).await?;
    let result = async {
        let reply = runtime
            .archive_thread("archive-old-tree".into(), root_id.into())
            .await?
            .context("archive reply")?;
        assert_eq!(reply.result.removed_thread_ids.len(), members.len());
        for (thread, session, original) in &members {
            let snapshot = runtime.thread_snapshot(&thread.id).await?;
            assert!(snapshot.thread.archived);
            let saved = crate::studio::storage::state::StateStore::new(
                session.root().to_owned(),
                &thread.id,
            )
            .load_current()
            .await?
            .context("archived current")?;
            assert_eq!(saved.state.context, original.context);
            assert_eq!(
                saved.state.extensions["vendor.unknown"],
                original.extensions["vendor.unknown"]
            );
            if thread.id == "archive-legacy-route" {
                assert_eq!(
                    saved.state.extensions["studio.model-route"]
                        .payload
                        .version(),
                    2
                );
            }
            assert_schema26(&session.history_database()).await?;
            let files = SessionFiles::new(&thread.id);
            assert!(!session.temp_dir().exists());
            assert!(!workspace.join(files.temp()).exists());
            assert_eq!(
                tokio::fs::read(workspace.join(files.artifacts()).join("delivery")).await?,
                b"keep"
            );
            assert_eq!(
                tokio::fs::read(session.root().join("resources/reliable")).await?,
                b"reliable"
            );
        }
        anyhow::Ok(())
    }
    .await;
    let shutdown = runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    assert!(
        endpoint.finish().await?.is_empty(),
        "archiving must not send inference"
    );
    Ok(())
}

fn record(revision: u64, format: &str, version: u32, content: &str) -> Result<ExtensionRecord> {
    Ok(ExtensionRecord {
        revision,
        payload: OpaquePayload::new(format, version, content.to_owned())?,
    })
}

fn saved_state(extensions: BTreeMap<String, ExtensionRecord>) -> ThreadSnapshot {
    ThreadSnapshot {
        commit_sequence: 1,
        extension_sequence: 6,
        extensions,
        context: ContextSnapshot {
            revision: 1,
            records: vec![ContextRecord {
                id: "preserved-user-history".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![ContextContent::Text {
                    text: "必须保留的用户历史".into(),
                }],
                tool_calls: vec![],
            }]
            .into(),
        },
        ..Default::default()
    }
}

fn bound_thread(thread_id: &str) -> crate::Thread {
    let mut thread = crate::Thread::placeholder(thread_id);
    thread.workspace_id = "project-test".into();
    thread.agent_path = thread_id.to_owned();
    thread.root_thread_id = thread_id.to_owned();
    thread
}

async fn open_history(path: &Path) -> Result<sea_orm::DatabaseConnection> {
    use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
    let mut options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::Create,
        |options| {
            options
                .journal_mode(SqliteJournalMode::Wal)
                .synchronous(SqliteSynchronous::Full)
                .busy_timeout(std::time::Duration::from_secs(5))
                .foreign_keys(true)
        },
    )
    .await?;
    options
        .max_connections(1)
        .min_connections(1)
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}

async fn seed_schema24_checkpoint(
    path: &Path,
    thread_id: &str,
    state: &ThreadSnapshot,
) -> Result<()> {
    let db = open_history(path).await?;
    crate::studio::storage::history::schema::initialize(&db, thread_id).await?;
    let checkpoint =
        ThreadCheckpoint::capture(thread_id.to_owned(), state.commit_sequence, state.clone())?;
    let records = checkpoint.state.context.records.clone();
    let mut stored = checkpoint.clone();
    stored.state.context.records = Default::default();
    let payload = serde_json::to_string(&stored)?;
    db.execute_unprepared("DELETE FROM session_checkpoint")
        .await?;
    db.execute_unprepared("DELETE FROM current_context").await?;
    db.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "INSERT INTO session_checkpoint(
            id,revision,context_revision,context_count,payload,payload_hash
         ) VALUES(1,?,?,?,?,?)",
        vec![
            i64::try_from(checkpoint.state_revision)?.into(),
            i64::try_from(checkpoint.state.context.revision)?.into(),
            i64::try_from(records.len())?.into(),
            payload.clone().into(),
            content_hash(payload.as_bytes()).into(),
        ],
    ))
    .await?;
    for (ordinal, record) in records.iter().enumerate() {
        let context_payload = serde_json::to_string(record)?;
        db.execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "INSERT INTO current_context(ordinal,record_id,payload,payload_hash) VALUES(?,?,?,?)",
            vec![
                i64::try_from(ordinal)?.into(),
                record.id.clone().into(),
                context_payload.clone().into(),
                content_hash(context_payload.as_bytes()).into(),
            ],
        ))
        .await?;
    }
    db.execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "UPDATE history_meta SET applied_write_seq=? WHERE id=1",
        vec![i64::try_from(checkpoint.history_fence)?.into()],
    ))
    .await?;
    db.execute_unprepared("PRAGMA wal_checkpoint(TRUNCATE)")
        .await?;
    db.close().await?;
    Ok(())
}

async fn assert_schema26(path: &Path) -> Result<()> {
    let db = open_history(path).await?;
    let version = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT schema_version FROM history_store_meta WHERE singleton=1",
        ))
        .await?
        .context("schema 26 identity")?
        .try_get::<i64>("", "schema_version")?;
    assert_eq!(version, 27, "cold read must reach Schema 27");
    let migration = db
        .query_one_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT version FROM seaql_migrations WHERE version=?",
            vec![SCHEMA_27_MIGRATION.into()],
        ))
        .await?;
    assert!(
        migration.is_some(),
        "Schema 27 migration {SCHEMA_27_MIGRATION} must be recorded"
    );
    db.close().await?;
    Ok(())
}
