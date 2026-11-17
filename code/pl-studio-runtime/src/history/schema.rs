use std::{
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};

use sea_orm::{
    ConnectionTrait, Database, DatabaseConnection, SqliteTransactionMode, TransactionOptions,
    TransactionTrait,
};
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

use super::{HistoryError, Result, db::statement};

const MIGRATION: &str = "m20261116_000001_append_only_history";
fn known_legacy_versions() -> &'static std::collections::BTreeSet<String> {
    static VERSIONS: std::sync::OnceLock<std::collections::BTreeSet<String>> =
        std::sync::OnceLock::new();
    VERSIONS.get_or_init(|| {
        crate::studio::storage::history::frozen_v24_migrations("migration-ledger")
            .into_iter()
            .map(|step| step.name().to_owned())
            .collect()
    })
}

/// Registers only the source ledger's already-applied definitions. No legacy migration is run
/// during 24→25, including optional product preparation phases that were never applied.
async fn legacy_versions(db: &DatabaseConnection) -> Result<Vec<String>> {
    let rows = db
        .query_all_raw(statement(
            "SELECT version FROM seaql_migrations ORDER BY version",
            vec![],
        ))
        .await?;
    let mut versions = Vec::with_capacity(rows.len());
    for row in rows {
        let version: String = row.try_get("", "version")?;
        if !known_legacy_versions().contains(&version) {
            return Err(HistoryError::Integrity(format!(
                "unknown schema 24 migration {version}"
            )));
        }
        versions.push(version);
    }
    Ok(versions)
}

struct Migration {
    thread_id: String,
    database_id: String,
    source: Option<super::import::V24HistorySource>,
    source_watermark: Option<u64>,
    counts: Option<Arc<Mutex<Option<super::upgrade::ImportCounts>>>>,
}
impl MigrationName for Migration {
    fn name(&self) -> &str {
        MIGRATION
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for Migration {
    fn use_transaction(&self) -> Option<bool> {
        Some(false)
    }
    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(include_str!("schema.sql")).await?;
        db.execute_raw(statement(
            "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,?)",
            vec![self.database_id.clone().into(), self.thread_id.clone().into()],
        )).await?;
        if let Some(source) = self.source.as_ref() {
            let counts = super::upgrade::import_database(
                db,
                source,
                &self.database_id,
                &self.thread_id,
                self.source_watermark.ok_or_else(|| {
                    DbErr::Migration("schema 24 source watermark is missing".into())
                })?,
            )
            .await
            .map_err(|error| DbErr::Migration(format!("{error:#}")))?;
            if let Some(slot) = &self.counts {
                *slot
                    .lock()
                    .map_err(|_| DbErr::Migration("import count lock poisoned".into()))? =
                    Some(counts);
            }
        }
        Ok(())
    }
}
struct Migrator {
    thread_id: String,
    legacy_versions: Vec<String>,
    migration: Option<(String, super::import::V24HistorySource, u64)>,
    counts: Option<Arc<Mutex<Option<super::upgrade::ImportCounts>>>>,
}
impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        let (database_id, source, source_watermark) = self.migration.as_ref().map_or_else(
            || (uuid::Uuid::new_v4().to_string(), None, None),
            |(database_id, source, source_watermark)| {
                (
                    database_id.clone(),
                    Some(source.clone()),
                    Some(*source_watermark),
                )
            },
        );
        let mut migrations = if self.legacy_versions.is_empty() {
            Vec::new()
        } else {
            crate::studio::storage::history::frozen_v24_migrations(&self.thread_id)
                .into_iter()
                .filter(|step| {
                    self.legacy_versions
                        .iter()
                        .any(|version| version == step.name())
                })
                .collect()
        };
        migrations.push(Box::new(Migration {
            thread_id: self.thread_id.clone(),
            database_id,
            source,
            source_watermark,
            counts: self.counts.clone(),
        }));
        migrations
    }
}

pub(super) async fn connect(
    path: &Path,
    read_only: bool,
    create: bool,
) -> Result<DatabaseConnection> {
    use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
    use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
    let mode = if read_only {
        SqliteFileMode::ReadOnly
    } else if create {
        SqliteFileMode::Create
    } else {
        SqliteFileMode::ReadWrite
    };
    let mut options = sqlite_file_options(path, mode, move |options| {
        let options = options
            .foreign_keys(true)
            .busy_timeout(Duration::from_secs(5));
        if read_only {
            options
        } else {
            options
                .journal_mode(SqliteJournalMode::Wal)
                .synchronous(SqliteSynchronous::Full)
        }
    })
    .await?;
    options
        .max_connections(if read_only { 4 } else { 1 })
        .min_connections(1)
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}

pub(super) async fn initialize(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    run_immediate(
        Migrator {
            thread_id: thread_id.into(),
            legacy_versions: Vec::new(),
            migration: None,
            counts: None,
        },
        db,
    )
    .await?;
    Ok(())
}

pub(super) async fn run_upgrade(
    db: &DatabaseConnection,
    thread_id: &str,
    database_id: &str,
    source_watermark: u64,
    source: super::import::V24HistorySource,
) -> Result<super::upgrade::ImportCounts> {
    let counts = Arc::new(Mutex::new(None));
    run_immediate(
        Migrator {
            thread_id: thread_id.into(),
            legacy_versions: legacy_versions(db).await?,
            migration: Some((database_id.to_owned(), source, source_watermark)),
            counts: Some(counts.clone()),
        },
        db,
    )
    .await?;
    let imported = counts
        .lock()
        .map_err(|_| HistoryError::Integrity("import count lock poisoned".into()))?
        .take()
        .ok_or_else(|| HistoryError::Integrity("migration import counts are missing".into()))?;
    Ok(imported)
}

async fn run_immediate(migrator: Migrator, db: &DatabaseConnection) -> Result<()> {
    // sea-orm-migration 2.0.4 has no transaction-mode hook. Keep the official runner as the
    // sole migration executor/recorder, pass its manager this explicit Immediate transaction,
    // and keep use_transaction()=false so the runner cannot open a nested transaction.
    let thread_id = migrator.thread_id.clone();
    let tx = db
        .begin_with_options(TransactionOptions {
            sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
            ..Default::default()
        })
        .await?;
    migrator.up(&tx, None).await?;
    match tx.commit().await {
        Ok(()) => Ok(()),
        Err(commit_error) => {
            // A lost COMMIT acknowledgement is not proof that the new format was not published.
            // Observe the committed identity through a fresh pooled connection before deciding
            // whether a retry would append a second migration.
            match identity(db, &thread_id).await {
                Ok(_) => Ok(()),
                Err(_) => Err(commit_error.into()),
            }
        }
    }
}

pub(super) async fn identity(db: &DatabaseConnection, thread_id: &str) -> Result<(String, u64)> {
    let tx = db.begin().await?;
    for table in tx
        .query_all_raw(statement(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            vec![],
        ))
        .await?
    {
        let name: String = table.try_get("", "name")?;
        if ![
            "history_store_meta",
            "history_events",
            "history_bodies",
            "history_body_chunks",
            "seaql_migrations",
        ]
        .contains(&name.as_str())
        {
            return Err(HistoryError::Integrity(format!(
                "unexpected table in schema 25 history: {name}"
            )));
        }
    }
    let row = tx
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history identity is missing".into()))?;
    if row.try_get::<i64>("", "schema_version")? != 25
        || row.try_get::<String>("", "thread_id")? != thread_id
    {
        return Err(HistoryError::Integrity(
            "history schema or Thread identity differs".into(),
        ));
    }
    let database_id: String = row.try_get("", "database_id")?;
    if uuid::Uuid::parse_str(&database_id).is_err() {
        return Err(HistoryError::Integrity(
            "invalid history database identity".into(),
        ));
    }
    let migration = tx
        .query_all_raw(statement("SELECT version FROM seaql_migrations", vec![]))
        .await?;
    let mut found = false;
    for row in &migration {
        let version: String = row.try_get("", "version")?;
        if version != MIGRATION && !known_legacy_versions().contains(&version) {
            return Err(HistoryError::Integrity(format!(
                "unknown history migration {version}"
            )));
        }
        if version == MIGRATION {
            found = true;
        }
    }
    if !found {
        return Err(HistoryError::Integrity(
            "unsupported history migration state".into(),
        ));
    }
    // Validate the executable format without scanning business rows or opening a current file.
    for (kind, names) in [
        (
            "table",
            &["history_events", "history_bodies", "history_body_chunks"][..],
        ),
        (
            "trigger",
            &[
                "history_events_no_update",
                "history_events_no_delete",
                "history_bodies_no_update",
                "history_bodies_no_delete",
                "history_body_chunks_no_update",
                "history_body_chunks_no_delete",
            ][..],
        ),
        (
            "index",
            &[
                "history_one_anchor",
                "history_row_head",
                "history_main_anchors",
                "history_member_anchors",
                "history_business_anchors",
                "history_entity_events",
                "history_turn_events",
                "history_source_events",
                "history_call_events",
                "history_message_events",
                "history_attempt_events",
                "history_originals_class",
                "history_originals_all",
                "history_originals_parent",
                "history_originals_parent_class",
                "history_originals_text",
                "history_originals_tool",
            ][..],
        ),
    ] {
        for name in names {
            if tx
                .query_one_raw(statement(
                    "SELECT 1 FROM sqlite_schema WHERE type=? AND name=?",
                    vec![kind.into(), (*name).into()],
                ))
                .await?
                .is_none()
            {
                return Err(HistoryError::Integrity(format!(
                    "history {kind} {name} is missing"
                )));
            }
        }
    }
    let max = tx
        .query_one_raw(statement(
            "SELECT COALESCE(MAX(seq),0) AS seq FROM history_events",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history sequence is unavailable".into()))?;
    let head = u64::try_from(max.try_get::<i64>("", "seq")?)
        .map_err(|_| HistoryError::Integrity("negative history sequence".into()))?;
    tx.commit().await?;
    Ok((database_id, head))
}
