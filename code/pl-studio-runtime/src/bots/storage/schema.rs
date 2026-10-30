//! SQLite ledger initialization and legacy import owned by the official migrator.
use super::*;
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTrait, SchemaManager};

pub(super) async fn inspect_existing(path: &Path) -> anyhow::Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let options = sqlite_file_options(path, SqliteFileMode::ReadOnly, |options| options).await?;
    let db = Database::connect(options).await?;
    let result = preflight(&db)
        .await
        .map_err(|error| crate::studio::startup::migration_error("bot ledger", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

pub(super) async fn initialize(db: &DatabaseConnection) -> anyhow::Result<()> {
    preflight(db).await.map_err(|error| {
        crate::studio::startup::migration_error("bot ledger", "preflight", error)
    })?;
    if let Err(error) = Migrator::up(db, None).await {
        return Err(crate::studio::startup::migration_error(
            "bot ledger",
            "m20261026_000001_bot_ledger_schema",
            error,
        ));
    }
    Ok(())
}

async fn preflight(db: &DatabaseConnection) -> anyhow::Result<()> {
    let manager = SchemaManager::new(db);
    if manager.has_table("bot_meta").await? {
        let row = db
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .ok_or_else(|| anyhow::anyhow!("missing bot ledger format; existing data preserved"))?;
        let version: i64 = row.try_get("", "schema_version")?;
        anyhow::ensure!(
            (1..=BOT_STATE_SCHEMA_VERSION).contains(&version),
            "unsupported bot state schema {version}; existing data preserved"
        );
        if version == BOT_STATE_SCHEMA_VERSION {
            for table in [
                "inbound_identities",
                "inbound_work",
                "thread_bindings",
                "observed_directs",
                "pairing_requests",
                "send_operations",
                "binding_operations",
                "bot_card_streams",
            ] {
                anyhow::ensure!(
                    manager.has_table(table).await?,
                    "current bot ledger table {table} is missing; existing data preserved"
                );
            }
            for table in ["inbound_work", "thread_bindings"] {
                anyhow::ensure!(
                    manager.has_column(table, "workspace_id").await?
                        && !manager.has_column(table, "project_id").await?,
                    "current bot ledger ownership columns are invalid; existing data preserved"
                );
            }
        }
    } else {
        anyhow::ensure!(db.query_one_raw(statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_none(),
            "unversioned nonempty bot ledger; existing data preserved");
        anyhow::ensure!(
            Migrator::get_applied_migrations_read_only(db)
                .await?
                .is_empty(),
            "bot ledger schema is missing; existing data preserved"
        );
    }
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        anyhow::ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "bot ledger integrity check failed"
        );
    }
    if Migrator::get_pending_migrations_read_only(db)
        .await?
        .is_empty()
    {
        let row = db
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .ok_or_else(|| anyhow::anyhow!("missing bot ledger format"))?;
        anyhow::ensure!(
            row.try_get::<i64>("", "schema_version")? == BOT_STATE_SCHEMA_VERSION,
            "bot ledger format conflicts with completed migrations; existing data preserved"
        );
    }
    Ok(())
}

struct Migrator;
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(LedgerSchema), Box::new(WorkspaceOwnership)]
    }
}
struct LedgerSchema;
impl MigrationName for LedgerSchema {
    fn name(&self) -> &str {
        "m20261026_000001_bot_ledger_schema"
    }
}

/// The published v6 ledger remains a migration input, never a runtime fallback.
struct WorkspaceOwnership;

impl MigrationName for WorkspaceOwnership {
    fn name(&self) -> &str {
        "m20261030_000002_bot_workspace_ownership"
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for WorkspaceOwnership {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let row = db
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .ok_or_else(|| DbErr::Migration("missing bot ledger version".into()))?;
        if row.try_get::<i64>("", "schema_version")? != 6 {
            return Err(DbErr::Migration(
                "workspace ownership requires the published v6 ledger".into(),
            ));
        }
        for table in ["inbound_work", "thread_bindings"] {
            if !manager.has_column(table, "project_id").await?
                || manager.has_column(table, "workspace_id").await?
            {
                return Err(DbErr::Migration(
                    "invalid source bot ownership columns; source preserved".into(),
                ));
            }
            db.execute_unprepared(&format!(
                "ALTER TABLE {table} RENAME COLUMN project_id TO workspace_id"
            ))
            .await?;
        }
        db.execute_unprepared("UPDATE bot_meta SET schema_version=7 WHERE id=1")
            .await?;
        Ok(())
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for LedgerSchema {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS bot_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS inbound_identities (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL,
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            admitted_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS inbound_work (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL DEFAULT '',
            content_hash TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL DEFAULT '',
            open_id TEXT NOT NULL DEFAULT '',
            chat_kind TEXT NOT NULL DEFAULT '',
            generation INTEGER NOT NULL DEFAULT 0,
            app_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '',
            creation_id TEXT NOT NULL DEFAULT '',
            binding_revision INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            diagnostic TEXT NOT NULL,
            claimed_by TEXT NOT NULL DEFAULT '',
            claimed_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS thread_bindings (
            chat_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'bound',
            creation_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '',
            revision INTEGER NOT NULL DEFAULT 0,
            generation INTEGER NOT NULL DEFAULT 0,
            diagnostic TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS observed_directs (
            chat_id TEXT PRIMARY KEY,
            open_id TEXT NOT NULL,
            name TEXT NOT NULL,
            last_observed_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS pairing_requests (
            request_id TEXT PRIMARY KEY,
            open_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            created_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS send_operations (
            operation_id TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            status TEXT NOT NULL,
            platform_message_ids TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS binding_operations (
            operation_id TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL,
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            expected_revision INTEGER NOT NULL,
            creation_id TEXT NOT NULL,
            thread_id TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL
        )",
        )
        .await?;
        adopt_legacy_ledger(db)
            .await
            .map_err(|error| match error.downcast::<DbErr>() {
                Ok(error) => error,
                Err(error) => DbErr::Migration(format!("{error:#}")),
            })?;
        Ok(())
    }
}

async fn adopt_legacy_ledger<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let version = db
        .query_one_raw(statement(
            "SELECT schema_version FROM bot_meta WHERE id=1",
            vec![],
        ))
        .await?;
    if let Some(version) = version {
        let version: i64 = version.try_get("", "schema_version")?;
        anyhow::ensure!(version <= 6, "unsupported future bot state schema");
    }
    create_card_streams_v6(db).await?;
    db.execute_unprepared(
        "CREATE UNIQUE INDEX IF NOT EXISTS pairing_open_id ON pairing_requests(open_id)",
    )
    .await?;
    ensure_column(
        db,
        "inbound_identities",
        "bot_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(db, "inbound_work", "bot_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "chat_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "message_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "content_hash",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(db, "inbound_work", "text", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "attachments",
        "TEXT NOT NULL DEFAULT '[]'",
    )
    .await?;
    ensure_column(db, "inbound_work", "open_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "chat_kind", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "generation",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "inbound_work", "app_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "project_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "creation_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "binding_revision",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "inbound_work", "claimed_by", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "claimed_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "watch_input",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "attempt_count",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "next_attempt_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "status",
        "TEXT NOT NULL DEFAULT 'bound'",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "creation_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "project_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "revision",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "generation",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "diagnostic",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "updated_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "send_operations", "bot_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "send_operations",
        "segment_facts",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    // 旧 pending 与“creating 但缺创建身份”的行一律规范为 needs_attention：
    // 不从 thread_id 反推创建身份，运行时也不再重新兼容这两种值。
    db.execute_unprepared(
        "UPDATE thread_bindings
         SET status='needs_attention',
             diagnostic='legacy pending binding requires local recreate',
             revision=CASE WHEN revision=0 THEN 1 ELSE revision END
         WHERE thread_id='pending' OR status='pending' OR (status='creating' AND creation_id='')",
    )
    .await?;
    db.execute_unprepared(
        "UPDATE inbound_work
         SET status='needs_attention',
             diagnostic='legacy inbound lacks frozen binding identity'
         WHERE status IN ('pending','claimed','failed')
           AND (creation_id='' OR app_id='' OR project_id='')",
    )
    .await?;
    db.execute_unprepared(
        "UPDATE thread_bindings SET revision=1, generation=1 WHERE revision=0 AND status='bound'",
    )
    .await?;
    db.execute_raw(statement(
        "INSERT INTO bot_meta(id, schema_version) VALUES(1, ?)
         ON CONFLICT(id) DO UPDATE SET schema_version=excluded.schema_version",
        vec![6i64.into()],
    ))
    .await?;
    Ok(())
}

async fn ensure_column<C: ConnectionTrait>(
    db: &C,
    table: &str,
    column: &str,
    decl: &str,
) -> anyhow::Result<()> {
    let columns = db
        .query_all_raw(statement(&format!("PRAGMA table_info({table})"), vec![]))
        .await?;
    let present = columns
        .iter()
        .any(|row| row.try_get::<String>("", "name").ok().as_deref() == Some(column));
    if !present {
        db.execute_unprepared(&format!("ALTER TABLE {table} ADD COLUMN {column} {decl}"))
            .await?;
    }
    Ok(())
}

async fn create_card_streams_v6<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    db.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS bot_card_streams (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL, chat_id TEXT NOT NULL, message_id TEXT NOT NULL,
            thread_id TEXT NOT NULL, original_input TEXT NOT NULL,
            watch_input TEXT NOT NULL, turn_id TEXT NOT NULL,
            version INTEGER NOT NULL CHECK(version>0), state_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )",
    )
    .await?;
    Ok(())
}
