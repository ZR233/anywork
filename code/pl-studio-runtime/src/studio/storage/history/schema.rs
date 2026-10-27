//! Official, ordered history migrations. Format numbers are only legacy import markers.
use super::*;
mod conversion;
use conversion::{
    backfill_legacy_hidden_inputs, backfill_tool_user_input, migrate_context_sources,
    migrate_unconsumed_input_bindings,
};
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

struct Migrator {
    thread_id: String,
    execution_identity: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
}

impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(CreateHistory {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(InputPresentation),
            Box::new(InputBindings),
            Box::new(ContextSources {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ToolAnswers {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(CheckpointV5 {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ModelAccess {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(WorkspaceReceipt {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ExecutionIdentity {
                thread_id: self.thread_id.clone(),
                candidate: self.execution_identity.clone(),
            }),
        ]
    }
}

/// Lifecycle phases select how far to advance the one official sequence. SeaORM owns ordering,
/// pending-step detection, transactions and completion records for every phase.
pub(super) enum Preparation {
    Schema,
    ModelAccess,
    ExecutionIdentity,
}
const MODEL_ACCESS: &str = "m20261026_000007_history_model_access";
// Ordered between model-access and execution identity: cold close needs representation maintenance
// without requiring (or activating) a Mode/model/tool execution owner.
const WORKSPACE_RECEIPT: &str = "m20261026_000007a_history_workspace_receipt";
pub(super) const EXECUTION_IDENTITY: &str = "m20261026_000008_history_execution_identity";

pub(super) async fn prepare(
    db: &DatabaseConnection,
    thread_id: &str,
    phase: Preparation,
    execution_identity: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
) -> Result<()> {
    preflight(db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error))?;
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity,
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let steps = match phase {
        Preparation::Schema => pending
            .iter()
            .take_while(|step| step.name() < MODEL_ACCESS)
            .count(),
        Preparation::ModelAccess => pending
            .iter()
            .position(|step| step.name() == WORKSPACE_RECEIPT)
            .map_or(0, |index| index + 1),
        Preparation::ExecutionIdentity => pending.len(),
    };
    if let Err(error) = migrator.up(db, Some(u32::try_from(steps)?)).await {
        let pending = migrator
            .get_pending_migrations_read_only(db)
            .await
            .unwrap_or_default();
        let step = pending
            .first()
            .map_or("migration bookkeeping", |migration| migration.name());
        return Err(crate::studio::startup::migration_error(
            "history", step, error,
        ));
    }
    Ok(())
}

pub(super) async fn initialize(db: &DatabaseConnection, thread_id: &str) -> Result<String> {
    prepare(db, thread_id, Preparation::Schema, None).await?;
    Ok(db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("missing history identity after migration")?
        .try_get("", "database_id")?)
}

pub(super) async fn inspect_existing(path: &Path, thread_id: &str) -> Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let db = connect_read_only(path).await?;
    let result = preflight(&db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

async fn preflight(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity: None,
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let meta = db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_meta'",
            vec![],
        ))
        .await?;
    if meta.is_none() {
        ensure!(db.query_one_raw(statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_none(),
            "unversioned nonempty history database; existing data preserved");
        ensure!(
            migrator
                .get_applied_migrations_read_only(db)
                .await?
                .is_empty(),
            "history schema is missing; existing data preserved"
        );
        return Ok(());
    }
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,thread_id,database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("missing history identity; existing data preserved")?;
    let version: i64 = row.try_get("", "schema_version")?;
    ensure!(
        (1..=HISTORY_SCHEMA_VERSION).contains(&version),
        "unsupported history schema {version}; existing data preserved"
    );
    ensure!(
        !pending.is_empty() || version == HISTORY_SCHEMA_VERSION,
        "history format conflicts with completed migrations; existing data preserved"
    );
    ensure!(
        row.try_get::<String>("", "thread_id")? == thread_id,
        "history database belongs to another Thread"
    );
    ensure!(
        !row.try_get::<String>("", "database_id")?.is_empty(),
        "history database identity is empty"
    );
    if version == 8 {
        let manager = SchemaManager::new(db);
        for table in [
            "history_items",
            "history_turns",
            "history_input_identities",
            "history_fact_receipts",
            "history_message_identities",
            "session_checkpoint",
            "session_costs",
            "current_context",
            "history_tool_tasks",
        ] {
            ensure!(
                manager.has_table(table).await?,
                "current history table {table} is missing; existing data preserved"
            );
        }
    }
    if SchemaManager::new(db)
        .has_table("session_checkpoint")
        .await?
    {
        for row in db
            .query_all_raw(statement(
                "SELECT json_extract(payload,'$.schemaVersion') AS version FROM session_checkpoint",
                vec![],
            ))
            .await?
        {
            let checkpoint_version: i64 = row.try_get("", "version")?;
            ensure!(
                (1..=5).contains(&checkpoint_version),
                "unsupported checkpoint schema {checkpoint_version}; existing data preserved"
            );
        }
    }
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "history database integrity check failed"
        );
    }
    Ok(())
}

async fn version(db: &impl ConnectionTrait) -> Result<i64, DbErr> {
    db.query_one_raw(statement(
        "SELECT schema_version FROM history_meta WHERE id=1",
        vec![],
    ))
    .await?
    .ok_or_else(|| DbErr::Migration("missing history format".into()))?
    .try_get("", "schema_version")
}
async fn set_version(db: &impl ConnectionTrait, target: i64) -> Result<(), DbErr> {
    db.execute_raw(statement(
        "UPDATE history_meta SET schema_version=? WHERE id=1",
        vec![target.into()],
    ))
    .await?;
    Ok(())
}
fn conversion(error: anyhow::Error) -> DbErr {
    match error.downcast::<DbErr>() {
        Ok(error) => error,
        Err(error) => DbErr::Migration(format!("{error:#}")),
    }
}

struct CreateHistory {
    thread_id: String,
}
impl MigrationName for CreateHistory {
    fn name(&self) -> &str {
        "m20261026_000001_history_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CreateHistory {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS history_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL,
            database_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            applied_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_items (
            ordinal INTEGER PRIMARY KEY,
            item_id TEXT NOT NULL UNIQUE,
            turn_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL,
            lifecycle TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS history_items_by_turn
            ON history_items(turn_id, ordinal);
        -- 最新终态按 ordinal 排序；缺口恢复另按原始 write_seq 范围读取。
        CREATE INDEX IF NOT EXISTS history_items_by_kind_lifecycle
            ON history_items(kind, lifecycle, ordinal);
        CREATE INDEX IF NOT EXISTS history_terminal_turns_by_write_seq
            ON history_items(last_write_seq,ordinal) WHERE kind='turn' AND lifecycle='terminal';
        -- `agent_page` 的 text-only 稀疏过滤同样带 ordinal 方向，单独一条 (kind, ordinal) 索引
        -- 才能同时满足过滤与排序。
        CREATE INDEX IF NOT EXISTS history_items_by_kind
            ON history_items(kind, ordinal);
        CREATE TABLE IF NOT EXISTS history_turns (
            turn_id TEXT PRIMARY KEY,
            first_ordinal INTEGER NOT NULL,
            last_ordinal INTEGER NOT NULL,
            revision INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        -- Turn 页是 `last_ordinal` 上的 keyset 倒序扫描；没有这条索引时深翻页会退化成全表
        -- 扫描 + 排序。
        CREATE INDEX IF NOT EXISTS history_turns_by_last_ordinal
            ON history_turns(last_ordinal);
        CREATE TABLE IF NOT EXISTS history_input_identities (
            item_id TEXT PRIMARY KEY,
            ordinal INTEGER NOT NULL,
            revision INTEGER NOT NULL,
            digest TEXT NOT NULL,
            request_digest TEXT,
            presentation TEXT CHECK (presentation IN ('visible','hidden')),
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_fact_receipts (
            item_id TEXT NOT NULL,
            revision INTEGER NOT NULL,
            kind TEXT NOT NULL,
            digest TEXT NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL,
            PRIMARY KEY(item_id, revision)
        );
        -- 已受理消息的最小身份索引：原始消息 id、时间线条目身份、受理序号与正文摘要。
        -- `digest` 可空，只用于迁移回填留下的“身份已知、正文不可验证”行（读取方 fail-closed）。
        CREATE TABLE IF NOT EXISTS history_message_identities (
            message_id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            digest TEXT,
            last_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS session_checkpoint (
            id INTEGER PRIMARY KEY CHECK(id=1),
            revision INTEGER NOT NULL,
            context_revision INTEGER NOT NULL,
            context_count INTEGER NOT NULL,
            payload TEXT NOT NULL,
            payload_hash TEXT NOT NULL,
            legacy_cleanup INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS session_costs (
            purpose TEXT NOT NULL,
            currency TEXT NOT NULL,
            amount REAL NOT NULL,
            PRIMARY KEY(purpose,currency)
        );
        CREATE TABLE IF NOT EXISTS current_context (
            ordinal INTEGER PRIMARY KEY,
            record_id TEXT NOT NULL UNIQUE,
            payload TEXT NOT NULL,
            payload_hash TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_tool_tasks (
            call_id TEXT PRIMARY KEY,
            revision INTEGER NOT NULL,
            task_payload TEXT NOT NULL CHECK (json_valid(task_payload)),
            delivery_payload TEXT CHECK (delivery_payload IS NULL OR json_valid(delivery_payload)),
            last_write_seq INTEGER NOT NULL
        );",
        )
        .await?;

        if !manager
            .has_column("history_input_identities", "request_digest")
            .await?
        {
            db.execute_unprepared(
                "ALTER TABLE history_input_identities ADD COLUMN request_digest TEXT",
            )
            .await?;
        }
        db.execute_raw(statement("INSERT OR IGNORE INTO history_meta(id,schema_version,database_id,thread_id,applied_write_seq) VALUES(1,?,?,?,0)",
            vec![8i64.into(), crate::studio::new_id("history-db").into(), self.thread_id.clone().into()])).await?;
        Ok(())
    }
}

struct InputPresentation;
impl MigrationName for InputPresentation {
    fn name(&self) -> &str {
        "m20261026_000002_history_input_presentation"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InputPresentation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 3 {
            if !manager
                .has_column("history_input_identities", "presentation")
                .await?
            {
                db.execute_unprepared("ALTER TABLE history_input_identities ADD COLUMN presentation TEXT CHECK (presentation IN ('visible','hidden'))").await?;
            }
            backfill_legacy_hidden_inputs(db)
                .await
                .map_err(conversion)?;
            set_version(db, 3).await?;
        }
        Ok(())
    }
}

struct InputBindings;
impl MigrationName for InputBindings {
    fn name(&self) -> &str {
        "m20261026_000003_history_input_bindings"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InputBindings {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 4 {
            migrate_unconsumed_input_bindings(db)
                .await
                .map_err(conversion)?;
            set_version(db, 4).await?;
        }
        Ok(())
    }
}

struct ContextSources {
    thread_id: String,
}
impl MigrationName for ContextSources {
    fn name(&self) -> &str {
        "m20261026_000004_history_context_sources"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ContextSources {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 6 {
            migrate_context_sources(db, &self.thread_id)
                .await
                .map_err(conversion)?;
            set_version(db, 6).await?;
        }
        Ok(())
    }
}

struct ToolAnswers {
    thread_id: String,
}
impl MigrationName for ToolAnswers {
    fn name(&self) -> &str {
        "m20261026_000005_history_tool_answers"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ToolAnswers {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 8 {
            backfill_tool_user_input(db, &self.thread_id)
                .await
                .map_err(conversion)?;
            set_version(db, 8).await?;
        }
        Ok(())
    }
}

struct CheckpointV5 {
    thread_id: String,
}
impl MigrationName for CheckpointV5 {
    fn name(&self) -> &str {
        "m20261026_000006_history_checkpoint_v5"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CheckpointV5 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        checkpoint::migrate_envelope(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        Ok(())
    }
}

struct ModelAccess {
    thread_id: String,
}
impl MigrationName for ModelAccess {
    fn name(&self) -> &str {
        MODEL_ACCESS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ModelAccess {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        // Absence of explicit close remains absence; core Closed never invents Studio intent.
        crate::studio::agent_close::is_explicitly_closed(&migrated.state).map_err(conversion)?;
        crate::studio::model_route::migration::upgrade(&mut migrated.state).map_err(conversion)?;
        crate::studio::delegation::migrate(&mut migrated.state).map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct WorkspaceReceipt {
    thread_id: String,
}
impl MigrationName for WorkspaceReceipt {
    fn name(&self) -> &str {
        WORKSPACE_RECEIPT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for WorkspaceReceipt {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::workspace_receipt::migration::upgrade(&mut migrated.state)
            .map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct ExecutionIdentity {
    thread_id: String,
    candidate: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
}
impl MigrationName for ExecutionIdentity {
    fn name(&self) -> &str {
        EXECUTION_IDENTITY
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ExecutionIdentity {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let (original, migrated) = self.candidate.as_ref().ok_or_else(|| {
            DbErr::Migration("execution identity requires explicit recovery preparation".into())
        })?;
        let db = manager.get_connection();
        let current = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
            .ok_or_else(|| DbErr::Migration("recovery checkpoint is absent".into()))?;
        if serde_json::to_vec(&current).map_err(|error| DbErr::Migration(error.to_string()))?
            != serde_json::to_vec(original).map_err(|error| DbErr::Migration(error.to_string()))?
        {
            return Err(DbErr::Migration(
                "checkpoint changed during recovery migration; original data preserved".into(),
            ));
        }
        checkpoint::write_representation(db, original, migrated)
            .await
            .map_err(conversion)
    }
}
