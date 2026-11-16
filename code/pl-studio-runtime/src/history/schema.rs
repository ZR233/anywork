use std::{path::Path, time::Duration};

use sea_orm::{ConnectionTrait, Database, DatabaseConnection, TransactionTrait};
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

use super::{HistoryError, Result, db::statement};

const MIGRATION: &str = "m20261116_000001_append_only_history";

struct Migration {
    thread_id: String,
    database_id: String,
}
impl MigrationName for Migration {
    fn name(&self) -> &str {
        MIGRATION
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for Migration {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(include_str!("schema.sql")).await?;
        db.execute_raw(statement(
            "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,?)",
            vec![self.database_id.clone().into(), self.thread_id.clone().into()],
        )).await?;
        Ok(())
    }
}
struct Migrator {
    thread_id: String,
}
impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(Migration {
            thread_id: self.thread_id.clone(),
            database_id: uuid::Uuid::new_v4().to_string(),
        })]
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
    Migrator {
        thread_id: thread_id.into(),
    }
    .up(db, None)
    .await?;
    Ok(())
}

pub(super) async fn identity(db: &DatabaseConnection, thread_id: &str) -> Result<(String, u64)> {
    let tx = db.begin().await?;
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
    if migration.len() != 1 || migration[0].try_get::<String>("", "version")? != MIGRATION {
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
