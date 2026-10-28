//! `calls.sqlite` 的当前 schema、启动清理与 旧调用结构 → 当前结构 的保源迁移。
//!
//! 迁移只做加法并保持可重入：先把旧 `model_calls` 的累计费用保全为摘要，再把保留期内的正文按批
//! 转换成 JSONL 日志记录（按 `(thread_id, call_id, kind)` 幂等去重），最后才删除旧表并清理无引用的
//! blobs 目录。旧结构的耗时列不构成当前统计口径的样本，因此旧性能统计直接丢弃、不迁移；原始日志、
//! 账单与费用保留。导出失败保留旧格式及源表；最终事务提交后，blobs 清理失败保留待清理标记，
//! 下次打开继续。旧版本（v1）的数据根不在本模块触碰范围内。

use super::*;
use sea_orm_migration::{
    DbErr, MigrationName, MigrationStatus, MigrationTrait, MigratorTrait, MigratorTraitSelf,
    SchemaManager,
};

mod source;

/// 旧格式可能写入的内联/引用列；迁移前补齐，读取端只按固定列名访问。
const LEGACY_MODEL_COLUMNS: &[(&str, &str)] = &[
    ("body_ref", "TEXT"),
    ("billing_ref", "TEXT"),
    ("root_thread_id", "TEXT"),
    ("turn_id", "TEXT"),
    ("attempt_id", "TEXT"),
    ("retry_of", "TEXT"),
    ("retention", "TEXT"),
    ("revision", "INTEGER NOT NULL DEFAULT 0"),
    ("admitted_at", "INTEGER NOT NULL DEFAULT 0"),
    ("started_at", "INTEGER NOT NULL DEFAULT 0"),
    ("finished_at", "INTEGER"),
    ("status", "TEXT"),
    ("terminal", "INTEGER NOT NULL DEFAULT 0"),
    ("purpose", "TEXT"),
    ("provider_instance_id", "TEXT"),
    ("provider_display_name", "TEXT"),
    ("configured_model", "TEXT"),
    ("sent_model", "TEXT"),
    ("reported_model", "TEXT"),
    ("reasoning_effort", "TEXT"),
    ("input_tokens", "INTEGER"),
    ("output_tokens", "INTEGER"),
    ("cache_read_tokens", "INTEGER"),
    ("cache_write_tokens", "INTEGER"),
    ("reasoning_tokens", "INTEGER"),
    ("total_tokens", "INTEGER"),
    ("ttft_millis", "INTEGER"),
    ("decode_millis", "INTEGER"),
    ("response_millis", "INTEGER"),
    ("cost_currency", "TEXT"),
    ("cost_amount", "REAL"),
    ("has_unpriced_usage", "INTEGER NOT NULL DEFAULT 0"),
];

/// 每批迁移读取的旧行数。
const LEGACY_MIGRATION_BATCH: i64 = 256;
/// 迁移后待清理的 blobs 目录名。
const LEGACY_BLOBS_DIR_NAME: &str = "blobs";

/// Validate an existing file before opening a writer or touching its companion logs.
pub(super) async fn inspect_existing(path: &Path) -> Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::ReadOnly,
        |options| options,
    )
    .await?;
    let db = Database::connect(options).await?;
    let result = preflight(&db, PathBuf::new())
        .await
        .map(|_| ())
        .map_err(|error| crate::studio::startup::migration_error("calls", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

pub(super) async fn initialize(db: &DatabaseConnection, root_dir: &Path) -> Result<()> {
    let migrator = preflight(db, root_dir.join(super::CALL_LOG_DIR_NAME))
        .await
        .map_err(|error| crate::studio::startup::migration_error("calls", "preflight", error))?;
    if let Err(error) = migrator.up(db, None).await {
        let pending = migrator
            .get_pending_migrations_read_only(db)
            .await
            .unwrap_or_default();
        let step = pending
            .first()
            .map_or("migration bookkeeping", |migration| migration.name());
        return Err(crate::studio::startup::migration_error(
            "calls", step, error,
        ));
    }
    retry_pending_cleanup(db, root_dir).await.map_err(|error| {
        crate::studio::startup::migration_error("calls", "legacy blob cleanup", error)
    })?;
    Ok(())
}
async fn preflight(db: &DatabaseConnection, log_dir: PathBuf) -> Result<Migrator> {
    let (migrator, prefix) = Migrator::recorded(db, log_dir).await?;
    source::validate(db, prefix).await?;
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "calls database integrity check failed"
        );
    }
    Ok(migrator)
}
async fn format_version(db: &impl ConnectionTrait) -> Result<i64, DbErr> {
    db.query_one_raw(statement(
        "SELECT schema_version FROM calls_meta WHERE id=1",
        vec![],
    ))
    .await?
    .ok_or_else(|| DbErr::Migration("missing calls format; existing data preserved".into()))?
    .try_get("", "schema_version")
}
fn conversion(error: anyhow::Error) -> DbErr {
    match error.downcast::<DbErr>() {
        Ok(error) => error,
        Err(error) => DbErr::Migration(format!("{error:#}")),
    }
}
enum Migrator {
    Main { log_dir: PathBuf },
    Atomic { log_dir: PathBuf },
}
impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        let export: Box<dyn MigrationTrait> = match self {
            Self::Main { log_dir } => Box::new(ExportLog {
                log_dir: log_dir.clone(),
            }),
            Self::Atomic { log_dir } => Box::new(AtomicExportLog {
                log_dir: log_dir.clone(),
            }),
        };
        vec![
            Box::new(CallsSchema),
            Box::new(LegacySummary),
            export,
            Box::new(FinalizeLegacy),
            Box::new(ThroughputEpoch),
        ]
    }
}

// A read-only vocabulary for the official records API, never an executable lineage.
struct Catalog;
impl MigratorTrait for Catalog {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        let mut steps = Migrator::Main {
            log_dir: PathBuf::new(),
        }
        .migrations();
        steps.push(Box::new(AtomicExportLog {
            log_dir: PathBuf::new(),
        }));
        steps
    }
}

impl Migrator {
    async fn recorded(db: &impl ConnectionTrait, log_dir: PathBuf) -> Result<(Self, usize)> {
        // The catalog also rejects unknown names before any schema or log write.
        let applied = <Catalog as MigratorTrait>::get_applied_migrations_read_only(db).await?;
        let old_step = ExportLog {
            log_dir: PathBuf::new(),
        };
        let atomic_step = AtomicExportLog {
            log_dir: PathBuf::new(),
        };
        let old_export = applied.iter().any(|step| step.name() == old_step.name());
        let atomic_export = applied.iter().any(|step| step.name() == atomic_step.name());
        ensure!(
            !(old_export && atomic_export),
            "mixed calls migration lineages; existing data preserved"
        );
        let migrator = if old_export {
            Self::Main { log_dir }
        } else {
            Self::Atomic { log_dir }
        };
        // Official statuses follow migrations(), not applied_at or name sorting. A later
        // applied step after any pending step is not a supported resumable prefix.
        let statuses = migrator.get_migration_with_status_read_only(db).await?;
        let mut pending_seen = false;
        let mut prefix = 0;
        for step in statuses {
            match step.status() {
                MigrationStatus::Pending => pending_seen = true,
                MigrationStatus::Applied => {
                    ensure!(
                        !pending_seen,
                        "calls migration records are not an ordered prefix; existing data preserved"
                    );
                    prefix += 1;
                }
            }
        }
        // Main can only be selected by a real, completed old export. In particular, the
        // common first two steps are inherited by Atomic without fabricating old step 3.
        ensure!(
            old_export || atomic_export || prefix <= 2,
            "calls export lineage is missing; existing data preserved"
        );
        Ok((migrator, prefix))
    }
}

struct CallsSchema;
impl MigrationName for CallsSchema {
    fn name(&self) -> &str {
        "m20261026_000001_calls_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CallsSchema {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        rename_performance_identity_columns(db)
            .await
            .map_err(conversion)?;
        ensure_schema(db).await.map_err(conversion)?;
        db.execute_raw(statement("INSERT OR IGNORE INTO calls_meta(id,schema_version,database_id,pending_cleanup,throughput_epoch) VALUES(1,?,?,0,?)",
            vec![7i64.into(), crate::studio::new_id("calls-db").into(), 1i64.into()])).await?;
        db.execute_raw(statement("UPDATE calls_meta SET database_id=? WHERE id=1 AND (database_id IS NULL OR database_id='')", vec![crate::studio::new_id("calls-db").into()])).await?;
        if format_version(db).await? < 5
            && table_exists(db, "model_calls").await.map_err(conversion)?
        {
            ensure_columns(db, "model_calls", LEGACY_MODEL_COLUMNS)
                .await
                .map_err(conversion)?;
        }
        Ok(())
    }
}

struct LegacySummary;
impl MigrationName for LegacySummary {
    fn name(&self) -> &str {
        "m20261026_000002_calls_legacy_summary"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for LegacySummary {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if format_version(db).await? < 5
            && table_exists(db, "model_calls").await.map_err(conversion)?
        {
            summary::migrate_from_legacy(db).await.map_err(conversion)?;
            db.execute_unprepared("INSERT OR REPLACE INTO legacy_auxiliary_usage(thread_id,payload)
                SELECT thread_id,json_object('inferenceCount',COUNT(*),'promptTokens',COALESCE(SUM(input_tokens),0),
                'completionTokens',COALESCE(SUM(output_tokens),0),'cachedPromptTokens',COALESCE(SUM(cache_read_tokens),0),
                'cacheWriteTokens',COALESCE(SUM(cache_write_tokens),0),'reasoningTokens',COALESCE(SUM(reasoning_tokens),0),
                'totalTokens',COALESCE(SUM(total_tokens),0),'hasIncompleteUsage',json('true'),'cacheIncomplete',json('true'),
                'hasUnpricedUsage',json(CASE WHEN MAX(has_unpriced_usage)>0 THEN 'true' ELSE 'false' END))
                FROM model_calls WHERE terminal=1 AND purpose IN ('title','review') GROUP BY thread_id").await?;
        }
        Ok(())
    }
}

struct ExportLog {
    log_dir: PathBuf,
}
impl MigrationName for ExportLog {
    fn name(&self) -> &str {
        "m20261026_000003_calls_export_log"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ExportLog {
    // JSONL durability and the bounded SQLite index batches are separate resources.
    fn use_transaction(&self) -> Option<bool> {
        Some(false)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let sea_orm_migration::SchemaManagerConnection::Connection(db) = manager.get_connection()
        else {
            return Err(DbErr::Migration(
                "call log export requires its owning connection outside a transaction".into(),
            ));
        };
        if format_version(*db).await? >= 5 {
            return Ok(());
        }
        let mut log = CallLog::prepare(self.log_dir.clone())
            .await
            .map_err(conversion)?;
        // A durable append may precede a failed index commit; recover it before any retry.
        log.rebuild_index(db).await.map_err(conversion)?;
        if table_exists(*db, "model_calls").await.map_err(conversion)? {
            convert_legacy_rows(db, &mut log)
                .await
                .map_err(conversion)?;
        }
        if table_exists(*db, "tool_calls").await.map_err(conversion)? {
            convert_legacy_tools(*db, &mut log)
                .await
                .map_err(conversion)?;
        }
        Ok(())
    }
}

struct AtomicExportLog {
    log_dir: PathBuf,
}
impl MigrationName for AtomicExportLog {
    fn name(&self) -> &str {
        "m20261026_100003_calls_export_log_atomic"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AtomicExportLog {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if format_version(db).await? >= 5 {
            return Ok(());
        }
        let mut log = CallLog::prepare(self.log_dir.clone())
            .await
            .map_err(conversion)?;
        // A durable JSONL append survives SQL rollback. Recover it inside this same
        // framework transaction before examining either legacy source for export.
        log.rebuild_index_in_transaction(db)
            .await
            .map_err(conversion)?;
        // The pre-v3 additive upgrader explicitly supported these absent watermark
        // columns. Repair them here without changing a published step's conversion.
        ensure_columns(
            db,
            "call_watermarks",
            &[
                ("admitted_write_seq", "INTEGER NOT NULL DEFAULT 0"),
                ("durable_write_seq", "INTEGER NOT NULL DEFAULT 0"),
            ],
        )
        .await
        .map_err(conversion)?;
        convert_legacy_rows_in_transaction(db, &mut log)
            .await
            .map_err(conversion)?;
        convert_legacy_tools(db, &mut log)
            .await
            .map_err(conversion)?;
        source::validate(db, 3).await.map_err(conversion)?;
        Ok(())
    }
}

struct FinalizeLegacy;
impl MigrationName for FinalizeLegacy {
    fn name(&self) -> &str {
        "m20261026_000004_calls_finalize_legacy"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for FinalizeLegacy {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let version = format_version(db).await?;
        if version < 7 {
            detach_legacy_performance(db).await.map_err(conversion)?;
            if version < 5 {
                db.execute_unprepared("DROP TABLE IF EXISTS model_calls; DROP TABLE IF EXISTS tool_calls; DROP TABLE IF EXISTS call_bodies; UPDATE calls_meta SET pending_cleanup=1 WHERE id=1;").await?;
            }
            db.execute_unprepared("UPDATE calls_meta SET schema_version=7 WHERE id=1")
                .await?;
        }
        Ok(())
    }
}

struct ThroughputEpoch;
impl MigrationName for ThroughputEpoch {
    fn name(&self) -> &str {
        "m20261026_000005_calls_throughput_epoch"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ThroughputEpoch {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        reset_legacy_throughput_samples(manager.get_connection())
            .await
            .map_err(conversion)
    }
}

/// 一次性丢弃旧统计口径的性能样本，不换算、不回填。
///
/// 口径切换只作废派生的速度投影：累计费用、执行幂等身份、原始调用日志与会话历史都保持原样。
/// 标记存在 `calls_meta.throughput_epoch`，因此重启、日志重建和后续升级都不会重复清空，
/// 也不会把旧 JSONL 重新投影成旧口径样本。
async fn reset_legacy_throughput_samples(db: &impl ConnectionTrait) -> Result<()> {
    let row = db
        .query_one_raw(statement(
            "SELECT throughput_epoch FROM calls_meta WHERE id=1",
            vec![],
        ))
        .await?;
    let epoch = row
        .map(|row| row.try_get::<i64>("", "throughput_epoch"))
        .transpose()?
        .unwrap_or(0);
    if epoch >= 1 {
        return Ok(());
    }
    db.execute_unprepared("DELETE FROM performance_samples")
        .await?;
    db.execute_raw(statement(
        "UPDATE calls_meta SET throughput_epoch=? WHERE id=1",
        vec![1i64.into()],
    ))
    .await?;
    tracing::info!(
        epoch = 1,
        "discarded previous throughput samples after the statistics epoch change"
    );
    Ok(())
}

/// 重试迁移遗留的 blobs 目录清理；失败保留标记，下次打开或周期维护再试。
pub(super) async fn retry_pending_cleanup(db: &DatabaseConnection, root_dir: &Path) -> Result<()> {
    let row = db
        .query_one_raw(statement(
            "SELECT pending_cleanup FROM calls_meta WHERE id=1",
            vec![],
        ))
        .await?;
    let pending = row
        .map(|row| row.try_get::<i64>("", "pending_cleanup"))
        .transpose()?
        .unwrap_or(0)
        != 0;
    if !pending {
        return Ok(());
    }
    let blobs_dir = root_dir.join(LEGACY_BLOBS_DIR_NAME);
    match tokio::fs::remove_dir_all(&blobs_dir).await {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            tracing::warn!(error = %error, path = %blobs_dir.display(), "调用库正文目录清理失败，稍后重试");
            return Ok(());
        }
    }
    db.execute_raw(statement(
        "UPDATE calls_meta SET pending_cleanup=0 WHERE id=1",
        vec![],
    ))
    .await?;
    Ok(())
}

async fn ensure_schema(db: &impl ConnectionTrait) -> Result<()> {
    db.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS calls_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL,
            database_id TEXT NOT NULL,
            pending_cleanup INTEGER NOT NULL DEFAULT 0,
            throughput_epoch INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS legacy_auxiliary_usage (thread_id TEXT PRIMARY KEY, payload TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS call_watermarks (
            thread_id TEXT PRIMARY KEY,
            admitted_write_seq INTEGER NOT NULL,
            durable_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS call_log_index (
            thread_id TEXT NOT NULL,
            call_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL,
            content_hash TEXT,
            segment TEXT NOT NULL,
            offset INTEGER NOT NULL,
            length INTEGER NOT NULL,
            truncated INTEGER NOT NULL DEFAULT 0,
            recorded_at INTEGER NOT NULL,
            PRIMARY KEY(thread_id, call_id, kind)
        );
        CREATE INDEX IF NOT EXISTS call_log_index_by_segment
            ON call_log_index(segment);
        CREATE TABLE IF NOT EXISTS call_usage_summary (
            root_thread_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            purpose TEXT NOT NULL DEFAULT '',
            cost_currency TEXT NOT NULL DEFAULT '',
            amount REAL NOT NULL DEFAULT 0,
            has_unpriced_usage INTEGER NOT NULL DEFAULT 0,
            revision INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(root_thread_id, thread_id, purpose, cost_currency)
        );
        CREATE INDEX IF NOT EXISTS call_usage_summary_by_root
            ON call_usage_summary(root_thread_id);
        CREATE TABLE IF NOT EXISTS performance_samples (
            thread_id TEXT NOT NULL,
            call_id TEXT NOT NULL,
            completed_at INTEGER NOT NULL,
            account_id TEXT,
            account_display_name TEXT,
            model_id TEXT,
            sent_model TEXT,
            reported_model TEXT,
            effort TEXT,
            output_tokens INTEGER,
            ttft_millis INTEGER,
            decode_millis INTEGER,
            response_millis INTEGER,
            PRIMARY KEY(thread_id,call_id)
        );
        CREATE INDEX IF NOT EXISTS performance_samples_by_completion
            ON performance_samples(completed_at DESC,thread_id DESC,call_id DESC);",
    )
    .await?;
    ensure_columns(
        db,
        "calls_meta",
        &[
            ("schema_version", "INTEGER NOT NULL DEFAULT 0"),
            ("database_id", "TEXT"),
            ("pending_cleanup", "INTEGER NOT NULL DEFAULT 0"),
            ("throughput_epoch", "INTEGER NOT NULL DEFAULT 0"),
        ],
    )
    .await?;
    ensure_columns(
        db,
        "performance_samples",
        &[
            ("account_id", "TEXT"),
            ("account_display_name", "TEXT"),
            ("model_id", "TEXT"),
            ("sent_model", "TEXT"),
            ("reported_model", "TEXT"),
            ("effort", "TEXT"),
            ("output_tokens", "INTEGER"),
            ("ttft_millis", "INTEGER"),
            ("decode_millis", "INTEGER"),
            ("response_millis", "INTEGER"),
        ],
    )
    .await?;
    Ok(())
}

/// Keep the performance projection independent of retired source tables. This also
/// repairs schema 5 databases whose parent was already dropped; log replay refills
/// any samples erased by the old cascading delete, without touching billing totals.
async fn detach_legacy_performance(tx: &impl ConnectionTrait) -> Result<()> {
    let foreign_keys = tx
        .query_all_raw(statement(
            "PRAGMA foreign_key_list(performance_samples)",
            vec![],
        ))
        .await?;
    if foreign_keys.is_empty() {
        return Ok(());
    }
    ensure!(
        foreign_keys.iter().all(|row| row
            .try_get::<String>("", "table")
            .is_ok_and(|table| table == "model_calls")),
        "unexpected performance sample foreign key; existing data preserved"
    );
    tx.execute_unprepared(
        "CREATE TABLE performance_samples_detached (
            thread_id TEXT NOT NULL, call_id TEXT NOT NULL, completed_at INTEGER NOT NULL,
            account_id TEXT, account_display_name TEXT, model_id TEXT,
            sent_model TEXT, reported_model TEXT, effort TEXT, output_tokens INTEGER,
            ttft_millis INTEGER, decode_millis INTEGER, response_millis INTEGER,
            PRIMARY KEY(thread_id,call_id));
         INSERT INTO performance_samples_detached
            SELECT thread_id,call_id,completed_at,account_id,account_display_name,
                   model_id,sent_model,reported_model,effort,output_tokens,
                   ttft_millis,decode_millis,response_millis FROM performance_samples;
         DROP TABLE performance_samples;
         ALTER TABLE performance_samples_detached RENAME TO performance_samples;
         CREATE INDEX performance_samples_by_completion
            ON performance_samples(completed_at DESC,thread_id DESC,call_id DESC);",
    )
    .await?;
    Ok(())
}

/// 按 rowid 分批把保留期内的旧调用转换进日志。
async fn convert_legacy_rows(db: &DatabaseConnection, log: &mut CallLog) -> Result<()> {
    let now = crate::studio::unix_seconds();
    let mut last_rowid = 0i64;
    let columns = migration_columns(db, "model_calls").await?;
    loop {
        let rows = db
            .query_all_raw(statement(
                &format!("SELECT rowid AS row_id,{columns} FROM model_calls WHERE rowid > ? ORDER BY rowid LIMIT ?"),
                vec![last_rowid.into(), LEGACY_MIGRATION_BATCH.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        let tx = db.begin().await?;
        for row in &rows {
            last_rowid = row.try_get("", "row_id")?;
            let mut record = legacy_record(row)?;
            if !is_retained(record.recorded_at, now) {
                continue;
            }
            if indexed(&tx, &record).await? {
                continue;
            }
            record = checked_legacy_model_record(db, &log.root_dir(), row, record).await?;
            append_record(&tx, log, &record, now).await?;
        }
        tx.commit().await?;
    }
    Ok(())
}

/// The new lineage keeps bounded reads, but all writes use the framework's current
/// connection. Only the historical exporter above owns per-batch transactions.
async fn convert_legacy_rows_in_transaction(
    db: &impl ConnectionTrait,
    log: &mut CallLog,
) -> Result<()> {
    let now = crate::studio::unix_seconds();
    let mut last_rowid = 0i64;
    let columns = migration_columns(db, "model_calls").await?;
    loop {
        let rows = db
            .query_all_raw(statement(
                &format!("SELECT rowid AS row_id,{columns} FROM model_calls WHERE rowid > ? ORDER BY rowid LIMIT ?"),
                vec![last_rowid.into(), LEGACY_MIGRATION_BATCH.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            last_rowid = row.try_get("", "row_id")?;
            let record = legacy_record(row)?;
            if !is_retained(record.recorded_at, now) {
                continue;
            }
            let record = checked_legacy_model_record(db, &log.root_dir(), row, record).await?;
            if !indexed(db, &record).await? {
                append_record(db, log, &record, now).await?;
            }
        }
    }
    Ok(())
}

async fn checked_legacy_model_record(
    db: &impl ConnectionTrait,
    root: &Path,
    row: &QueryResult,
    mut record: CallLogRecord,
) -> Result<CallLogRecord> {
    if let Some(body) = legacy_payload(
        db,
        root,
        row,
        "body_ref",
        &["body", "body_text", "body_json"],
    )
    .await?
    {
        let attempt: AttemptUpdate = serde_json::from_slice(&body)?;
        ensure!(
            attempt.attempt_id == record.call_id
                && attempt.turn_id.as_str() == record.turn_id.as_deref().unwrap_or_default(),
            "legacy call body identity mismatch"
        );
        let (diagnostic, truncated) = event::diagnostic(&attempt.outcome);
        record.diagnostic = Some(diagnostic);
        record.truncated = truncated;
        record.input_revision = Some(attempt.input_revision);
    }
    if let Some(body) = legacy_payload(
        db,
        root,
        row,
        "billing_ref",
        &["billing_body", "billing_json"],
    )
    .await?
    {
        let _: InferenceBillingRecord = serde_json::from_slice(&body)?;
    }
    Ok(record)
}

fn is_retained(recorded_at: i64, now: i64) -> bool {
    now.saturating_sub(recorded_at) <= log::LOG_RETENTION_SECONDS
}

async fn indexed(db: &impl ConnectionTrait, record: &CallLogRecord) -> Result<bool> {
    let row = db
        .query_one_raw(statement(
            "SELECT 1 AS present FROM call_log_index WHERE thread_id=? AND call_id=? AND kind=?",
            vec![
                record.thread_id.clone().into(),
                record.call_id.clone().into(),
                record.kind.clone().into(),
            ],
        ))
        .await?;
    Ok(row.is_some())
}

pub(super) fn legacy_record(row: &QueryResult) -> Result<CallLogRecord> {
    let started_at: i64 = row.try_get("", "started_at")?;
    let finished_at: Option<i64> = row.try_get("", "finished_at")?;
    let admitted_at: i64 = row.try_get("", "admitted_at")?;
    let recorded_at = finished_at.unwrap_or(started_at).max(admitted_at).max(0);
    let status: Option<String> = row.try_get("", "status")?;
    let terminal: i64 = row.try_get("", "terminal")?;
    let revision: i64 = row.try_get("", "revision")?;
    let cost = match (
        row.try_get::<Option<String>>("", "cost_currency")?,
        row.try_get::<Option<f64>>("", "cost_amount")?,
    ) {
        (Some(currency), Some(amount)) if !currency.is_empty() => {
            Some(RuntimeCostAmount { currency, amount })
        }
        _ => None,
    };
    let timing = match (
        row.try_get::<Option<i64>>("", "ttft_millis")?,
        row.try_get::<Option<i64>>("", "decode_millis")?,
        row.try_get::<Option<i64>>("", "response_millis")?,
    ) {
        (None, None, None) => None,
        // 旧结构的耗时列不可证明属于当前统计口径，因此只保留为诊断事实。
        (ttft, decode, response) => Some(event::CallTimingRecord::legacy(
            ttft.and_then(non_negative),
            decode.and_then(non_negative),
            response.and_then(non_negative),
        )),
    };
    Ok(CallLogRecord {
        version: event::CALL_LOG_RECORD_VERSION,
        kind: event::CALL_LOG_KIND_MIGRATED.to_owned(),
        thread_id: row.try_get("", "thread_id")?,
        call_id: row.try_get("", "call_id")?,
        root_thread_id: row.try_get("", "root_thread_id")?,
        turn_id: row.try_get("", "turn_id")?,
        retry_of: row.try_get("", "retry_of")?,
        status: status.unwrap_or_else(|| CallStatus::Committed.as_str().to_owned()),
        terminal: terminal != 0,
        revision,
        recorded_at,
        retention: row.try_get("", "retention")?,
        purpose: row.try_get("", "purpose")?,
        // 旧调用库的 provider 实例列即当前账号身份；缺失时保持未知。
        account_id: row.try_get("", "provider_instance_id")?,
        account_display_name: row.try_get("", "provider_display_name")?,
        // 旧库的 configured_model 才是冻结的目录配置模型；不用发送模型冒充。
        model_id: row.try_get("", "configured_model")?,
        sent_model: row.try_get("", "sent_model")?,
        reported_model: row.try_get("", "reported_model")?,
        effort: row.try_get("", "reasoning_effort")?,
        usage: Some(event::CallUsageRecord {
            input_tokens: opt_u64(row, "input_tokens")?,
            output_tokens: opt_u64(row, "output_tokens")?,
            cache_read_tokens: opt_u64(row, "cache_read_tokens")?,
            cache_write_tokens: opt_u64(row, "cache_write_tokens")?,
            reasoning_tokens: opt_u64(row, "reasoning_tokens")?,
            total_tokens: opt_u64(row, "total_tokens")?,
        }),
        cost,
        has_unpriced_usage: row.try_get::<i64>("", "has_unpriced_usage")? != 0,
        timing,
        // 旧调用结构没有当前口径的计时事实，不能成为速度样本。
        throughput_epoch: 0,
        truncated: false,
        input_revision: None,
        diagnostic: None,
    })
}

fn non_negative(value: i64) -> Option<u64> {
    u64::try_from(value).ok()
}

fn opt_u64(row: &QueryResult, column: &str) -> Result<Option<u64>> {
    Ok(row
        .try_get::<Option<i64>>("", column)?
        .and_then(non_negative))
}

async fn table_exists(db: &impl ConnectionTrait, table: &str) -> Result<bool> {
    let row = db
        .query_one_raw(statement(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            vec![table.into()],
        ))
        .await?;
    Ok(row.is_some())
}

/// 把 v6 的性能样本身份列改名为账号/配置模型/推理强度语义。
///
/// 改名在 `ensure_schema` 之前完成，因此不会出现"先按新列名补齐空列、再与旧列并存"的
/// 半迁移状态；旧值与主键、完成时间、用量和时延一律保留。已改名的库上是幂等空操作。
async fn rename_performance_identity_columns(db: &impl ConnectionTrait) -> Result<()> {
    if !table_exists(db, "performance_samples").await? {
        return Ok(());
    }
    let mut columns = table_columns(db, "performance_samples").await?;
    for (old, new) in [
        ("provider_instance_id", "account_id"),
        ("provider_display_name", "account_display_name"),
        ("configured_model", "model_id"),
        ("reasoning_effort", "effort"),
    ] {
        if !columns.contains(old) || columns.contains(new) {
            continue;
        }
        db.execute_raw(statement(
            &format!("ALTER TABLE performance_samples RENAME COLUMN {old} TO {new}"),
            vec![],
        ))
        .await?;
        columns.remove(old);
        columns.insert(new.to_string());
    }
    Ok(())
}

/// 补齐缺失的列并返回迁移后的列集合；列/表名都是编译期常量，不做动态 SQL 拼接注入面。
async fn ensure_columns(
    db: &impl ConnectionTrait,
    table: &str,
    specs: &[(&str, &str)],
) -> Result<BTreeSet<String>> {
    let mut columns = table_columns(db, table).await?;
    for (column, declaration) in specs {
        if !columns.contains(*column) {
            db.execute_unprepared(&format!(
                "ALTER TABLE {table} ADD COLUMN {column} {declaration}"
            ))
            .await?;
            columns.insert((*column).to_string());
        }
    }
    Ok(columns)
}

// Explicit columns keep statement result metadata stable across schema refreshes on pooled
// SQLite connections. SELECT * may be automatically re-prepared after ALTER with a new width.
async fn migration_columns(db: &impl ConnectionTrait, table: &str) -> Result<String> {
    Ok(table_columns(db, table)
        .await?
        .iter()
        .map(|column| format!("\"{}\"", column.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(","))
}

async fn table_columns(db: &impl ConnectionTrait, table: &str) -> Result<BTreeSet<String>> {
    let rows = db
        .query_all_raw(statement(&format!("PRAGMA table_info({table})"), vec![]))
        .await?;
    rows.iter()
        .map(|row| row.try_get::<String>("", "name").map_err(Into::into))
        .collect()
}

/// 测试用：在目标路径上建立一个旧 schema（v4 表结构）数据库。
#[cfg(test)]
pub(super) async fn seed_legacy_for_test(path: &Path, seed_sql: &str) -> Result<()> {
    let mut options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::Create,
        |options| options,
    )
    .await?;
    options.sqlx_logging(false);
    let db = Database::connect(options).await?;
    db.execute_unprepared(LEGACY_SCHEMA_SQL).await?;
    db.execute_unprepared(seed_sql).await?;
    db.close().await?;
    Ok(())
}

/// 测试用：旧版本使用指定结构，当前版本补齐其余规范表。
#[cfg(test)]
pub(super) async fn seed_version_for_test(
    path: &Path,
    schema_version: i64,
    seed_sql: &str,
) -> Result<()> {
    let mut options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::Create,
        |options| options,
    )
    .await?;
    options.sqlx_logging(false);
    let db = Database::connect(options).await?;
    db.execute_unprepared(
        "CREATE TABLE calls_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL,
            database_id TEXT NOT NULL,
            pending_cleanup INTEGER NOT NULL DEFAULT 0,
            throughput_epoch INTEGER NOT NULL DEFAULT 0
        );",
    )
    .await?;
    db.execute_unprepared(&format!(
        "INSERT INTO calls_meta(id,schema_version,database_id,pending_cleanup) VALUES(1,{schema_version},'test',0);"
    ))
    .await?;
    // Fixtures for published JSONL formats still need their full authoritative schema.
    // The caller supplies the historical performance table, including v6 identity names.
    ensure_schema(&db).await?;
    db.execute_unprepared("DROP TABLE performance_samples")
        .await?;
    db.execute_unprepared(seed_sql).await?;
    db.execute_unprepared("CREATE INDEX performance_samples_by_completion ON performance_samples(completed_at DESC,thread_id DESC,call_id DESC)").await?;
    db.close().await?;
    Ok(())
}

#[cfg(test)]
const LEGACY_SCHEMA_SQL: &str = "
CREATE TABLE calls_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    schema_version INTEGER NOT NULL,
    database_id TEXT NOT NULL
);
INSERT INTO calls_meta(id,schema_version,database_id) VALUES(1,3,'legacy');
CREATE TABLE call_watermarks (
    thread_id TEXT PRIMARY KEY,
    admitted_write_seq INTEGER NOT NULL,
    durable_write_seq INTEGER NOT NULL
);
CREATE TABLE model_calls (
    thread_id TEXT NOT NULL,
    call_id TEXT NOT NULL,
    root_thread_id TEXT,
    turn_id TEXT NOT NULL,
    attempt_id TEXT NOT NULL,
    retry_of TEXT,
    revision INTEGER NOT NULL,
    admitted_at INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    finished_at INTEGER,
    status TEXT NOT NULL,
    terminal INTEGER NOT NULL,
    retention TEXT,
    purpose TEXT,
    provider_instance_id TEXT,
    provider_display_name TEXT,
    configured_model TEXT,
    sent_model TEXT,
    reported_model TEXT,
    reasoning_effort TEXT,
    input_tokens INTEGER,
    output_tokens INTEGER,
    cache_read_tokens INTEGER,
    cache_write_tokens INTEGER,
    reasoning_tokens INTEGER,
    total_tokens INTEGER,
    ttft_millis INTEGER,
    decode_millis INTEGER,
    response_millis INTEGER,
    cost_currency TEXT,
    cost_amount REAL,
    has_unpriced_usage INTEGER NOT NULL DEFAULT 0,
    body_ref TEXT,
    billing_ref TEXT,
    PRIMARY KEY(thread_id, call_id)
);
CREATE TABLE tool_calls (
    thread_id TEXT NOT NULL,
    call_id TEXT NOT NULL,
    body_ref TEXT,
    PRIMARY KEY(thread_id, call_id)
);
CREATE TABLE performance_samples (
    thread_id TEXT NOT NULL,
    call_id TEXT NOT NULL,
    completed_at INTEGER NOT NULL,
    PRIMARY KEY(thread_id,call_id),
    FOREIGN KEY(thread_id,call_id) REFERENCES model_calls(thread_id,call_id) ON DELETE CASCADE
);
CREATE TABLE call_bodies (
    body_ref TEXT PRIMARY KEY,
    byte_length INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);
";

async fn legacy_body(root: &Path, reference: &str) -> Result<Vec<u8>> {
    let name = reference
        .strip_prefix("sha256:")
        .filter(|name| name.len() == 64 && name.bytes().all(|b| b.is_ascii_hexdigit()))
        .ok_or_else(|| anyhow::anyhow!("invalid legacy call body reference"))?;
    let bytes = tokio::fs::read(root.join("blobs").join(name)).await?;
    ensure!(
        pl_core::context::content_hash(&bytes) == reference,
        "legacy call body checksum mismatch"
    );
    Ok(bytes)
}

async fn legacy_payload(
    db: &impl ConnectionTrait,
    root: &Path,
    row: &QueryResult,
    reference_column: &str,
    inline_columns: &[&str],
) -> Result<Option<Vec<u8>>> {
    let reference = row
        .try_get::<Option<String>>("", reference_column)
        .ok()
        .flatten();
    let inline = inline_columns
        .iter()
        .find_map(|column| row.try_get::<Option<String>>("", column).ok().flatten());
    if let Some(reference) = reference {
        if let Some(inline) = inline {
            ensure!(
                pl_core::context::content_hash(inline.as_bytes()) == reference,
                "legacy inline body checksum mismatch"
            );
            return Ok(Some(inline.into_bytes()));
        }
        match legacy_body(root, &reference).await {
            Ok(body) => return Ok(Some(body)),
            Err(original) => {
                if table_exists(db, "call_bodies").await?
                    && let Some(body_row) = db
                        .query_one_raw(statement(
                            "SELECT * FROM call_bodies WHERE body_ref=?",
                            vec![reference.clone().into()],
                        ))
                        .await?
                {
                    for column in ["body", "body_text", "body_json"] {
                        if let Some(body) = body_row
                            .try_get::<Option<String>>("", column)
                            .ok()
                            .flatten()
                        {
                            ensure!(
                                pl_core::context::content_hash(body.as_bytes()) == reference,
                                "legacy body checksum mismatch"
                            );
                            return Ok(Some(body.into_bytes()));
                        }
                    }
                }
                if original
                    .downcast_ref::<std::io::Error>()
                    .is_some_and(|error| error.kind() == std::io::ErrorKind::NotFound)
                {
                    return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                        "referenced legacy call body is missing"
                    )));
                }
                return Err(original);
            }
        }
    }
    Ok(inline.map(String::into_bytes))
}

async fn convert_legacy_tools(db: &impl ConnectionTrait, log: &mut CallLog) -> Result<()> {
    ensure_columns(
        db,
        "tool_calls",
        &[
            ("body_ref", "TEXT"),
            ("turn_id", "TEXT"),
            ("revision", "INTEGER NOT NULL DEFAULT 0"),
            ("started_at", "INTEGER NOT NULL DEFAULT 0"),
            ("finished_at", "INTEGER"),
        ],
    )
    .await?;
    let now = crate::studio::unix_seconds();
    let mut cursor = 0_i64;
    let columns = migration_columns(db, "tool_calls").await?;
    loop {
        let rows = db
            .query_all_raw(statement(
                &format!("SELECT rowid AS row_id,{columns} FROM tool_calls WHERE rowid>? ORDER BY rowid LIMIT ?"),
                vec![cursor.into(), LEGACY_MIGRATION_BATCH.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            cursor = row.try_get("", "row_id")?;
            let at = row
                .try_get::<Option<i64>>("", "finished_at")?
                .unwrap_or(row.try_get("", "started_at")?);
            if !is_retained(at, now) {
                continue;
            }
            if let Some(body) = legacy_payload(
                db,
                &log.root_dir(),
                &row,
                "body_ref",
                &["body", "body_text", "body_json"],
            )
            .await?
            {
                // Older running rows contained arguments; terminal rows contained a delivery.
                #[derive(serde::Deserialize)]
                #[serde(untagged)]
                enum LegacyToolBody {
                    Delivery(Box<pl_core::thread::ToolDelivery>),
                    Arguments(pl_core::context::OpaquePayload),
                }
                let thread: String = row.try_get("", "thread_id")?;
                let call_id: String = row.try_get("", "call_id")?;
                let record = match serde_json::from_slice::<LegacyToolBody>(&body)? {
                    LegacyToolBody::Delivery(delivery) => {
                        ensure!(delivery.call_id == call_id, "legacy tool identity mismatch");
                        event::tool_record(
                            &thread,
                            row.try_get("", "turn_id")?,
                            row.try_get("", "revision")?,
                            at,
                            &delivery,
                        )
                    }
                    LegacyToolBody::Arguments(arguments) => {
                        ensure!(
                            row.try_get::<Option<i64>>("", "finished_at")?.is_none(),
                            "terminal legacy tool has only arguments"
                        );
                        let (diagnostic, truncated) = event::diagnostic(&arguments);
                        CallLogRecord {
                            version: event::CALL_LOG_RECORD_VERSION,
                            kind: "tool".into(),
                            thread_id: thread,
                            call_id,
                            turn_id: row.try_get("", "turn_id")?,
                            revision: row.try_get("", "revision")?,
                            status: "running".into(),
                            recorded_at: at,
                            diagnostic: Some(diagnostic),
                            truncated,
                            ..Default::default()
                        }
                    }
                };
                if !indexed(db, &record).await? {
                    append_record(db, log, &record, now).await?;
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;

    #[tokio::test]
    async fn published_v5_repairs_foreign_key_and_replays_lost_samples_without_rebilling()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        seed_legacy_for_test(
            &path,
            "UPDATE calls_meta SET schema_version=5; DROP TABLE model_calls;",
        )
        .await?;
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        ensure_schema(&db).await?;
        let tx = db.begin().await?;
        summary::replace(
            &tx,
            &SessionUsageProjection {
                root_thread_id: "thread".into(),
                thread_id: "thread".into(),
                revision: 7,
                has_unpriced_usage: false,
                purpose_costs: vec![PurposeUsageProjection {
                    purpose: None,
                    estimated_costs: vec![RuntimeCostAmount {
                        currency: "USD".into(),
                        amount: 3.0,
                    }],
                }],
            },
        )
        .await?;
        tx.commit().await?;
        db.close().await?;
        let mut log = CallLog::open(temp.path().join("logs")).await?;
        let record = CallLogRecord {
            version: event::CALL_LOG_RECORD_VERSION,
            kind: "billing".into(),
            thread_id: "thread".into(),
            call_id: "lost-sample".into(),
            status: "committed".into(),
            terminal: true,
            recorded_at: crate::studio::unix_seconds(),
            account_id: Some("provider".into()),
            // 冻结的目录配置模型：性能汇总的顶层身份需要它，发送模型不能替代。
            model_id: Some("model".into()),
            sent_model: Some("model".into()),
            usage: Some(event::CallUsageRecord {
                output_tokens: Some(41),
                ..Default::default()
            }),
            timing: Some(event::CallTimingRecord {
                ttft_millis: Some(2_700),
                decode_millis: Some(278),
                response_millis: Some(2_978),
            }),
            throughput_epoch: event::THROUGHPUT_EPOCH,
            ..Default::default()
        };
        let (line, _) = event::encode_record(&record)?;
        log.append(
            event::record_day(record.recorded_at),
            record.recorded_at,
            &line,
        )
        .await?;
        drop(log);
        let store = CallsStore::open(&path).await?;
        assert!(!store.statistics_gap());
        assert_eq!(store.recent_performance_samples(10).await?.len(), 1);
        assert_eq!(
            store.performance_summary_rows().await?[0].completion_tokens,
            41
        );
        // A fresh successful call must also insert into the repaired table.
        let mut next = record;
        next.call_id = "new-sample".into();
        let tx = store.writer.db.begin().await?;
        apply_billing(&mut *store.writer.log.lock().await, &tx, &next).await?;
        tx.commit().await?;
        assert_eq!(store.performance_summary_rows().await?[0].sample_count, 2);
        assert_eq!(
            store.session_cost_rollups().await?[0].estimated_costs[0].amount,
            3.0
        );
        store.stop_best_effort();
        let reopened = CallsStore::open(&path).await?;
        assert!(!reopened.statistics_gap());
        assert_eq!(
            reopened.performance_summary_rows().await?[0].sample_count,
            2
        );
        assert_eq!(
            reopened.session_cost_rollups().await?[0].estimated_costs[0].amount,
            3.0
        );
        reopened.stop_best_effort();
        Ok(())
    }

    #[tokio::test]
    async fn legacy_running_tool_arguments_and_review_billing_survive_migration() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let now = crate::studio::unix_seconds();
        let body = serde_json::to_vec(&pl_core::context::OpaquePayload::text("tool arguments"))?;
        let hash = pl_core::context::content_hash(&body);
        seed_legacy_for_test(&path, &format!("ALTER TABLE tool_calls ADD COLUMN started_at INTEGER NOT NULL DEFAULT 0;
            INSERT INTO tool_calls(thread_id,call_id,body_ref,started_at) VALUES('thread','tool','{hash}',{now});
            INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,purpose,input_tokens,output_tokens,total_tokens,cost_currency,cost_amount,root_thread_id)
            VALUES('thread','review','turn','review',1,{now},{now},'committed',1,'review',10,5,15,'USD',4.0,'thread');")).await?;
        tokio::fs::create_dir_all(temp.path().join("blobs")).await?;
        tokio::fs::write(
            temp.path()
                .join("blobs")
                .join(hash.strip_prefix("sha256:").unwrap()),
            body,
        )
        .await?;
        let store = CallsStore::open(&path).await?;
        assert_eq!(
            store.legacy_auxiliary_usage("thread").await?.total_tokens,
            15
        );
        assert_eq!(
            store.session_cost_rollups().await?[0].estimated_costs[0].amount,
            4.0
        );
        // 旧结构的调用只进入原始日志；它没有当前口径的计时事实，因此不产生速度样本。
        assert!(store.recent_performance_samples(100).await?.is_empty());
        let rows = store
            .writer
            .db
            .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
            .await?;
        assert_eq!(rows.len(), 2);
        store.stop_best_effort();
        let reopened = CallsStore::open(&path).await?;
        assert!(reopened.recent_performance_samples(100).await?.is_empty());
        reopened.stop_best_effort();
        Ok(())
    }

    #[tokio::test]
    async fn legacy_body_missing_preserves_source_then_retries_and_reclaims_orphans() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let attempt = AttemptUpdate {
            request_metadata: None,
            usage_binding: None,
            tool_projection: None,
            turn_id: "turn".into(),
            attempt_id: "call".into(),
            retry_of: None,
            input_revision: 7,
            tools: Default::default(),
            outcome: AttemptOutcome::Running,
            input_estimate: None,
        };
        let body = serde_json::to_vec(&attempt)?;
        let hash = pl_core::context::content_hash(&body);
        let now = crate::studio::unix_seconds();
        seed_legacy_for_test(&path, &format!("INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,body_ref) VALUES('thread','call','turn','call',1,{now},{now},'running',0,'{hash}');")).await?;
        let missing_error = match CallsStore::open(&path).await {
            Ok(_) => anyhow::bail!("missing legacy call body was accepted"),
            Err(error) => error,
        };
        assert!(format!("{missing_error:#}").contains("m20261026_100003_calls_export_log_atomic"));
        assert_eq!(
            crate::studio::startup::StudioStartupError::input("calls test", missing_error).kind,
            crate::studio::startup::StudioStartupErrorKind::Migration,
            "migration failure must not become PersistentData recovery/reset"
        );
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        assert!(table_exists(&db, "model_calls").await?);
        assert_eq!(
            db.query_one_raw(statement("SELECT schema_version FROM calls_meta", vec![]))
                .await?
                .unwrap()
                .try_get::<i64>("", "schema_version")?,
            3
        );
        tokio::fs::create_dir_all(temp.path().join("blobs")).await?;
        let blob = temp
            .path()
            .join("blobs")
            .join(hash.strip_prefix("sha256:").unwrap());
        tokio::fs::write(&blob, b"damaged body").await?;
        let checksum_error = match CallsStore::prepare(&path).await {
            Ok(_) => anyhow::bail!("damaged legacy body was accepted"),
            Err(error) => error,
        };
        assert!(format!("{checksum_error:#}").contains("checksum mismatch"));
        let mut mismatched = attempt;
        mismatched.attempt_id = "different-call".into();
        let mismatched = serde_json::to_vec(&mismatched)?;
        let mismatched_hash = pl_core::context::content_hash(&mismatched);
        tokio::fs::write(
            temp.path()
                .join("blobs")
                .join(mismatched_hash.strip_prefix("sha256:").unwrap()),
            mismatched,
        )
        .await?;
        db.execute_raw(statement(
            "UPDATE model_calls SET body_ref=?",
            vec![mismatched_hash.into()],
        ))
        .await?;
        let identity_error = match CallsStore::prepare(&path).await {
            Ok(_) => anyhow::bail!("mismatched legacy body identity was accepted"),
            Err(error) => error,
        };
        assert!(format!("{identity_error:#}").contains("legacy call body identity mismatch"));
        assert_eq!(format_version(&db).await?, 3);
        assert_eq!(
            <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                .await?
                .len(),
            2
        );
        assert!(
            db.query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                .await?
                .is_empty()
        );
        db.execute_raw(statement(
            "UPDATE model_calls SET body_ref=?",
            vec![hash.clone().into()],
        ))
        .await?;
        tokio::fs::write(
            temp.path()
                .join("blobs")
                .join(hash.strip_prefix("sha256:").unwrap()),
            body,
        )
        .await?;
        tokio::fs::write(temp.path().join("blobs/unregistered-orphan"), b"orphan").await?;
        let store = CallsStore::open(&path).await?;
        assert!(!table_exists(&db, "model_calls").await?);
        assert!(!tokio::fs::try_exists(temp.path().join("blobs")).await?);
        let row = db
            .query_one_raw(statement(
                "SELECT segment,offset,length FROM call_log_index WHERE call_id='call'",
                vec![],
            ))
            .await?
            .unwrap();
        let text = tokio::fs::read_to_string(
            temp.path()
                .join("logs")
                .join(row.try_get::<String>("", "segment")?),
        )
        .await?;
        let record = event::decode_record(text.trim_end())?;
        assert_eq!(record.input_revision, Some(7));
        assert!(record.diagnostic.is_some());
        db.execute_unprepared("DELETE FROM call_log_index").await?;
        store.close().await?;
        let reopened = CallsStore::open(&path).await?;
        assert!(
            db.query_one_raw(statement(
                "SELECT call_id FROM call_log_index WHERE call_id='call'",
                vec![]
            ))
            .await?
            .is_some()
        );
        reopened.close().await?;
        db.close().await?;
        Ok(())
    }
    #[tokio::test]
    async fn durable_export_rebuilds_its_index_before_retry_without_duplicate_logs_or_costs()
    -> Result<()> {
        // The second fault is in SeaORM's own record insertion, after up has succeeded.
        // Both must roll back the index replacement and leave only the legal prefix 1/2.
        for trigger in [
            "CREATE TRIGGER reject_export BEFORE INSERT ON call_log_index BEGIN SELECT RAISE(ABORT,'injected export index failure'); END",
            "CREATE TRIGGER reject_export BEFORE INSERT ON seaql_migrations WHEN NEW.version='m20261026_100003_calls_export_log_atomic' BEGIN SELECT RAISE(ABORT,'injected export completion failure'); END",
        ] {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            let now = crate::studio::unix_seconds();
            seed_legacy_for_test(&path, &format!("INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,root_thread_id,revision,admitted_at,started_at,status,terminal,cost_currency,cost_amount) VALUES('thread','call','turn','call','thread',1,{now},{now},'committed',1,'USD',3.5)")).await?;
            let db = connect_existing(&path).await?;
            Migrator::Atomic {
                log_dir: temp.path().join("logs"),
            }
            .up(&db, Some(2))
            .await?;
            db.execute_unprepared("INSERT INTO call_log_index(thread_id,call_id,kind,revision,segment,offset,length,recorded_at) VALUES('stale','stale','model',1,'stale.jsonl',0,1,0)").await?;
            db.execute_unprepared(trigger).await?;
            db.close().await?;
            let error = match CallsStore::prepare(&path).await {
                Ok(_) => anyhow::bail!("injected export failure was ignored"),
                Err(error) => error,
            };
            assert!(format!("{error:#}").contains("m20261026_100003_calls_export_log_atomic"));
            assert!(format!("{error:#}").contains("injected export"));
            let db = connect_existing(&path).await?;
            assert!(table_exists(&db, "model_calls").await?);
            assert_eq!(format_version(&db).await?, 3);
            let rows = db
                .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                .await?;
            assert_eq!(rows.len(), 1);
            assert_eq!(
                rows[0].try_get::<String>("", "call_id")?,
                "stale",
                "the index DELETE must roll back too"
            );
            assert_eq!(
                <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                    .await?
                    .len(),
                2
            );
            let lines = log_lines(&temp.path().join("logs")).await?;
            assert_eq!(
                lines.len(),
                1,
                "JSONL must already be durable when SQL fails"
            );
            assert_eq!(event::decode_record(&lines[0])?.call_id, "call");
            db.execute_unprepared("DROP TRIGGER reject_export").await?;
            db.close().await?;
            for _ in 0..2 {
                let store = CallsStore::prepare(&path).await?;
                assert_eq!(
                    store.session_cost_rollups().await?[0].estimated_costs[0].amount,
                    3.5
                );
                let rows = store
                    .writer
                    .db
                    .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                    .await?;
                assert_eq!(rows.len(), 1);
                assert_eq!(rows[0].try_get::<String>("", "call_id")?, "call");
                assert!(!table_exists(&store.writer.db, "model_calls").await?);
                store.close().await?;
            }
            assert_eq!(
                log_lines(&temp.path().join("logs")).await?.len(),
                1,
                "recover the durable append instead of exporting it twice"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn completed_published_export_at_legacy_format_only_runs_its_successors() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let now = crate::studio::unix_seconds();
        let body = serde_json::to_vec(&pl_core::context::OpaquePayload::text(
            "published tool arguments",
        ))?;
        let hash = pl_core::context::content_hash(&body);
        seed_legacy_for_test(&path, &format!("ALTER TABLE tool_calls ADD COLUMN started_at INTEGER NOT NULL DEFAULT 0;
            INSERT INTO tool_calls(thread_id,call_id,body_ref,started_at) VALUES('thread','tool','{hash}',{now})")).await?;
        tokio::fs::create_dir_all(temp.path().join("blobs")).await?;
        let blob = temp
            .path()
            .join("blobs")
            .join(hash.strip_prefix("sha256:").unwrap());
        tokio::fs::write(&blob, body).await?;
        let db = connect_existing(&path).await?;
        // Produce a real historical prefix with the published, non-transactional exporter.
        Migrator::Main {
            log_dir: temp.path().join("logs"),
        }
        .up(&db, Some(3))
        .await?;
        assert_eq!(format_version(&db).await?, 3);
        db.close().await?;
        // Re-exporting tools would try to read this body again, even with a recovered index.
        tokio::fs::remove_file(blob).await?;
        let store = CallsStore::prepare(&path).await?;
        let (lineage, prefix) = Migrator::recorded(&store.writer.db, PathBuf::new()).await?;
        assert!(matches!(lineage, Migrator::Main { .. }));
        assert_eq!(prefix, 5);
        assert_eq!(
            format_version(&store.writer.db).await?,
            CALLS_SCHEMA_VERSION
        );
        assert!(!table_exists(&store.writer.db, "tool_calls").await?);
        assert_eq!(log_lines(&temp.path().join("logs")).await?.len(), 1);
        assert_eq!(
            store
                .writer
                .db
                .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                .await?
                .len(),
            1
        );
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn second_batch_sql_and_tool_payload_failures_roll_back_the_whole_atomic_export()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let now = crate::studio::unix_seconds();
        let count = LEGACY_MIGRATION_BATCH + 1;
        let body = serde_json::to_vec(&pl_core::context::OpaquePayload::text(
            "recovered tool arguments",
        ))?;
        let hash = pl_core::context::content_hash(&body);
        seed_legacy_for_test(&path, &format!("WITH RECURSIVE calls(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM calls WHERE n<{count})
            INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,root_thread_id,revision,admitted_at,started_at,status,terminal,cost_currency,cost_amount)
            SELECT 'thread',printf('call-%03d',n),'turn',printf('call-%03d',n),'thread',1,{now},{now},'committed',1,'USD',1.0 FROM calls;
            ALTER TABLE tool_calls ADD COLUMN started_at INTEGER NOT NULL DEFAULT 0;
            INSERT INTO tool_calls(thread_id,call_id,body_ref,started_at) VALUES('thread','tool','{hash}',{now});")).await?;
        let db = connect_existing(&path).await?;
        Migrator::Atomic {
            log_dir: temp.path().join("logs"),
        }
        .up(&db, Some(2))
        .await?;
        db.execute_unprepared(&format!("CREATE TRIGGER reject_second_batch BEFORE INSERT ON call_log_index WHEN NEW.call_id='call-{count:03}' BEGIN SELECT RAISE(ABORT,'injected second batch failure'); END")).await?;
        db.close().await?;
        for expected in [
            "injected second batch failure",
            "referenced legacy call body is missing",
        ] {
            let error = match CallsStore::prepare(&path).await {
                Ok(_) => anyhow::bail!("{expected} was ignored"),
                Err(error) => error,
            };
            assert!(format!("{error:#}").contains(expected), "{error:#}");
            assert!(format!("{error:#}").contains("m20261026_100003_calls_export_log_atomic"));
            let db = connect_existing(&path).await?;
            assert_eq!(format_version(&db).await?, 3);
            assert_eq!(
                db.query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                    .await?
                    .len(),
                0
            );
            assert_eq!(
                db.query_all_raw(statement("SELECT call_id FROM model_calls", vec![]))
                    .await?
                    .len() as i64,
                count
            );
            assert_eq!(
                <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                    .await?
                    .len(),
                2
            );
            assert_eq!(
                summary::read_rollups(&db).await?[0].estimated_costs[0].amount,
                count as f64
            );
            assert_eq!(
                log_lines(&temp.path().join("logs")).await?.len() as i64,
                count
            );
            if expected == "injected second batch failure" {
                db.execute_unprepared("DROP TRIGGER reject_second_batch")
                    .await?;
            }
            db.close().await?;
        }
        tokio::fs::create_dir_all(temp.path().join("blobs")).await?;
        tokio::fs::write(
            temp.path()
                .join("blobs")
                .join(hash.strip_prefix("sha256:").unwrap()),
            body,
        )
        .await?;
        let store = CallsStore::prepare(&path).await?;
        assert_eq!(
            store.session_cost_rollups().await?[0].estimated_costs[0].amount,
            count as f64
        );
        assert_eq!(
            store
                .writer
                .db
                .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                .await?
                .len() as i64,
            count + 1
        );
        assert_eq!(
            log_lines(&temp.path().join("logs")).await?.len() as i64,
            count + 1
        );
        assert!(!table_exists(&store.writer.db, "model_calls").await?);
        assert!(!table_exists(&store.writer.db, "tool_calls").await?);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn unrecorded_supported_formats_preserve_sources_and_published_additive_defaults()
    -> Result<()> {
        for version in 1..=CALLS_SCHEMA_VERSION {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            let now = crate::studio::unix_seconds();
            if version <= 2 {
                let db = Database::connect(
                    crate::studio::paths::sqlite_file_options(
                        &path,
                        crate::studio::paths::SqliteFileMode::Create,
                        |options| options,
                    )
                    .await?,
                )
                .await?;
                // The old additive upgrader explicitly filled the absent identity, watermark
                // and call columns. Inline payloads still carry their original hash/identity.
                db.execute_unprepared(&format!("CREATE TABLE calls_meta(id INTEGER PRIMARY KEY CHECK(id=1),schema_version INTEGER NOT NULL);
                    INSERT INTO calls_meta VALUES(1,{version});
                    CREATE TABLE call_watermarks(thread_id TEXT PRIMARY KEY);
                    INSERT INTO call_watermarks VALUES('thread');
                    CREATE TABLE model_calls(thread_id TEXT NOT NULL,call_id TEXT NOT NULL,root_thread_id TEXT,started_at INTEGER NOT NULL,terminal INTEGER NOT NULL,cost_currency TEXT,cost_amount REAL,body TEXT,PRIMARY KEY(thread_id,call_id));
                    CREATE TABLE tool_calls(thread_id TEXT NOT NULL,call_id TEXT NOT NULL,started_at INTEGER NOT NULL,body TEXT,PRIMARY KEY(thread_id,call_id));
                    CREATE TABLE call_bodies(body_ref TEXT PRIMARY KEY,byte_length INTEGER NOT NULL,created_at INTEGER NOT NULL);")).await?;
                if version == 2 {
                    db.execute_unprepared("ALTER TABLE calls_meta ADD COLUMN database_id TEXT;
                        ALTER TABLE call_watermarks ADD COLUMN admitted_write_seq INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE call_watermarks ADD COLUMN durable_write_seq INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE model_calls ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE model_calls ADD COLUMN admitted_at INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE tool_calls ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE tool_calls ADD COLUMN admitted_at INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE tool_calls ADD COLUMN terminal INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE tool_calls ADD COLUMN cancel_requested INTEGER NOT NULL DEFAULT 0;
                        ALTER TABLE tool_calls ADD COLUMN turn_id TEXT;
                        ALTER TABLE tool_calls ADD COLUMN tool_id TEXT;
                        ALTER TABLE tool_calls ADD COLUMN status TEXT;").await?;
                }
                let attempt = AttemptUpdate {
                    request_metadata: None,
                    usage_binding: None,
                    tool_projection: None,
                    turn_id: String::new(),
                    attempt_id: "call".into(),
                    retry_of: None,
                    input_revision: 7,
                    tools: Default::default(),
                    outcome: AttemptOutcome::Running,
                    input_estimate: None,
                };
                db.execute_raw(statement("INSERT INTO model_calls(thread_id,call_id,root_thread_id,started_at,terminal,cost_currency,cost_amount,body) VALUES('thread','call','thread',?,1,'USD',3.5,?)", vec![now.into(), serde_json::to_string(&attempt)?.into()])).await?;
                db.execute_raw(statement("INSERT INTO tool_calls(thread_id,call_id,started_at,body) VALUES('thread','tool',?,?)", vec![now.into(), serde_json::to_string(&pl_core::context::OpaquePayload::text("inline arguments"))?.into()])).await?;
                db.close().await?;
            } else if version < 5 {
                let performance = if version == 3 {
                    "DROP TABLE performance_samples;"
                } else {
                    "CREATE INDEX performance_samples_by_completion ON performance_samples(completed_at DESC,thread_id DESC,call_id DESC);"
                };
                let id = if version == 3 { "" } else { "legacy" };
                seed_legacy_for_test(&path, &format!("UPDATE calls_meta SET schema_version={version},database_id='{id}'; {performance}
                    INSERT INTO model_calls(thread_id,call_id,root_thread_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,cost_currency,cost_amount)
                    VALUES('thread','call','thread','turn','call',1,{now},{now},'committed',1,'USD',3.5);")).await?;
            } else {
                let identities = if version == 7 {
                    "account_id TEXT,account_display_name TEXT,model_id TEXT,sent_model TEXT,reported_model TEXT,effort TEXT"
                } else {
                    "provider_instance_id TEXT,provider_display_name TEXT,configured_model TEXT,sent_model TEXT,reported_model TEXT,reasoning_effort TEXT"
                };
                seed_version_for_test(&path, version, &format!("CREATE TABLE performance_samples(
                    thread_id TEXT NOT NULL,call_id TEXT NOT NULL,completed_at INTEGER NOT NULL,{identities},
                    output_tokens INTEGER,ttft_millis INTEGER,decode_millis INTEGER,response_millis INTEGER,PRIMARY KEY(thread_id,call_id));
                    INSERT INTO performance_samples VALUES('thread','sample',{now},'account','Account','catalog-model','sent-alias','reported','high',17,1,2,3);
                    INSERT INTO call_usage_summary VALUES('thread','thread','','USD',3.5,0,9);
                    UPDATE calls_meta SET throughput_epoch={};", i64::from(version == 7))).await?;
            }
            let db = connect_existing(&path).await?;
            assert!(
                <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                    .await?
                    .is_empty()
            );
            if version == 6 {
                // Assert rename identity before the independent epoch step discards old samples.
                Migrator::Atomic {
                    log_dir: temp.path().join("logs"),
                }
                .up(&db, Some(1))
                .await?;
                let row = db.query_one_raw(statement("SELECT account_id,account_display_name,model_id,effort,sent_model FROM performance_samples", vec![])).await?.unwrap();
                assert_eq!(row.try_get::<String>("", "account_id")?, "account");
                assert_eq!(
                    row.try_get::<String>("", "account_display_name")?,
                    "Account"
                );
                assert_eq!(row.try_get::<String>("", "model_id")?, "catalog-model");
                assert_eq!(row.try_get::<String>("", "effort")?, "high");
                assert_eq!(row.try_get::<String>("", "sent_model")?, "sent-alias");
                assert!(
                    !table_columns(&db, "performance_samples")
                        .await?
                        .contains("configured_model")
                );
                assert_eq!(format_version(&db).await?, 6);
            }
            db.close().await?;
            let store = CallsStore::prepare(&path).await?;
            let row = store
                .writer
                .db
                .query_one_raw(statement(
                    "SELECT database_id FROM calls_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .unwrap();
            let id: String = row.try_get("", "database_id")?;
            if version == 4 {
                assert_eq!(id, "legacy");
            } else if version >= 5 {
                assert_eq!(id, "test");
            } else {
                assert!(!id.is_empty());
            }
            assert_eq!(
                store.session_cost_rollups().await?[0].estimated_costs[0].amount,
                3.5,
                "format {version}"
            );
            let (lineage, prefix) = Migrator::recorded(&store.writer.db, PathBuf::new()).await?;
            assert!(matches!(lineage, Migrator::Atomic { .. }));
            assert_eq!(prefix, 5);
            if version <= 2 {
                let row = store.writer.db.query_one_raw(statement("SELECT admitted_write_seq,durable_write_seq FROM call_watermarks WHERE thread_id='thread'", vec![])).await?.unwrap();
                assert_eq!(row.try_get::<i64>("", "admitted_write_seq")?, 0);
                assert_eq!(row.try_get::<i64>("", "durable_write_seq")?, 0);
                let records: Vec<_> = log_lines(&temp.path().join("logs"))
                    .await?
                    .iter()
                    .map(|line| event::decode_record(line))
                    .collect::<Result<_>>()?;
                assert_eq!(records.len(), 2);
                assert_eq!(
                    records
                        .iter()
                        .find(|record| record.call_id == "call")
                        .unwrap()
                        .input_revision,
                    Some(7)
                );
                assert!(records.iter().all(|record| record.diagnostic.is_some()));
            }
            store.close().await?;
            let reopened = CallsStore::prepare(&path).await?;
            assert_eq!(
                reopened.session_cost_rollups().await?[0].estimated_costs[0].amount,
                3.5
            );
            let row = reopened
                .writer
                .db
                .query_one_raw(statement(
                    "SELECT database_id FROM calls_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(row.try_get::<String>("", "database_id")?, id);
            reopened.close().await?;
        }
        // A store normalized from v1/v2 retains ALTER defaults at format3/4. Its
        // nullable text ALTER columns also remain legal; no inference of fresh-only
        // constraints is allowed merely because its numeric version has advanced.
        for version in [3, 4] {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            let ddl = LEGACY_SCHEMA_SQL
                .replace(
                    "schema_version INTEGER NOT NULL",
                    "schema_version INTEGER NOT NULL DEFAULT 0",
                )
                .replace(
                    "admitted_write_seq INTEGER NOT NULL",
                    "admitted_write_seq INTEGER NOT NULL DEFAULT 0",
                )
                .replace(
                    "durable_write_seq INTEGER NOT NULL",
                    "durable_write_seq INTEGER NOT NULL DEFAULT 0",
                )
                .replace(
                    "revision INTEGER NOT NULL",
                    "revision INTEGER NOT NULL DEFAULT 0",
                )
                .replace(
                    "admitted_at INTEGER NOT NULL",
                    "admitted_at INTEGER NOT NULL DEFAULT 0",
                )
                .replace(
                    "started_at INTEGER NOT NULL",
                    "started_at INTEGER NOT NULL DEFAULT 0",
                )
                .replace(
                    "terminal INTEGER NOT NULL",
                    "terminal INTEGER NOT NULL DEFAULT 0",
                )
                .replace("turn_id TEXT NOT NULL", "turn_id TEXT")
                .replace("attempt_id TEXT NOT NULL", "attempt_id TEXT")
                .replace("status TEXT NOT NULL", "status TEXT");
            let db = constraint_source_fixture(&path, &ddl, &format!("UPDATE calls_meta SET schema_version={version};
                ALTER TABLE tool_calls ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE tool_calls ADD COLUMN admitted_at INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE tool_calls ADD COLUMN started_at INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE tool_calls ADD COLUMN terminal INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE tool_calls ADD COLUMN cancel_requested INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE tool_calls ADD COLUMN turn_id TEXT;
                ALTER TABLE tool_calls ADD COLUMN tool_id TEXT;
                ALTER TABLE tool_calls ADD COLUMN status TEXT;
                CREATE INDEX performance_samples_by_completion ON performance_samples(completed_at DESC,thread_id DESC,call_id DESC);")).await?;
            let _ = preflight(&db, temp.path().join("logs")).await?;
            db.close().await?;
            let store = CallsStore::prepare(&path).await?;
            assert!(store.session_cost_rollups().await?.is_empty());
            assert_eq!(log_lines(&temp.path().join("logs")).await?.len(), 1);
            store.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn malformed_lineages_and_physical_sources_are_rejected_before_writing() -> Result<()> {
        // Corrupt real official records to model unsupported sources. These are rejection
        // fixtures, never fabricated completion records for a successful migration.
        for (mutation, expected) in [
            (
                "DELETE FROM seaql_migrations WHERE version='m20261026_000001_calls_schema'",
                "ordered prefix",
            ),
            (
                "DELETE FROM seaql_migrations WHERE version='m20261026_000002_calls_legacy_summary'",
                "ordered prefix",
            ),
            (
                "DELETE FROM seaql_migrations WHERE version='m20261026_100003_calls_export_log_atomic'",
                "ordered prefix",
            ),
            (
                "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261026_000003_calls_export_log',0)",
                "mixed calls migration",
            ),
            (
                "UPDATE seaql_migrations SET version='unknown_calls_step' WHERE version='m20261026_100003_calls_export_log_atomic'",
                "unknown_calls_step",
            ),
            (
                "UPDATE calls_meta SET schema_version=6",
                "conflicts with finalized",
            ),
            (
                "UPDATE calls_meta SET throughput_epoch=0",
                "conflicts with completed",
            ),
            (
                "UPDATE calls_meta SET schema_version=8",
                "unsupported calls schema",
            ),
            ("DROP TABLE calls_meta", "unversioned nonempty"),
            (
                "DROP TABLE call_usage_summary",
                "call_usage_summary is missing",
            ),
            (
                "ALTER TABLE performance_samples ADD COLUMN configured_model TEXT",
                "mixed calls performance identity",
            ),
            (
                "DROP TABLE call_log_index; CREATE TABLE call_log_index(thread_id TEXT NOT NULL,call_id TEXT NOT NULL,kind TEXT NOT NULL,revision INTEGER NOT NULL,content_hash TEXT,segment TEXT NOT NULL,offset INTEGER NOT NULL,length INTEGER NOT NULL,truncated INTEGER NOT NULL DEFAULT 0,recorded_at INTEGER NOT NULL,PRIMARY KEY(call_id,thread_id,kind)); CREATE INDEX call_log_index_by_segment ON call_log_index(segment)",
                "unknown primary key",
            ),
            (
                "DROP TABLE call_log_index; CREATE TABLE call_log_index(thread_id TEXT COLLATE NOCASE NOT NULL,call_id TEXT NOT NULL,kind TEXT NOT NULL,revision INTEGER NOT NULL,content_hash TEXT,segment TEXT NOT NULL,offset INTEGER NOT NULL,length INTEGER NOT NULL,truncated INTEGER NOT NULL DEFAULT 0,recorded_at INTEGER NOT NULL,PRIMARY KEY(thread_id,call_id,kind)); CREATE INDEX call_log_index_by_segment ON call_log_index(segment)",
                "primary key semantics",
            ),
            (
                "DROP INDEX call_log_index_by_segment; CREATE INDEX call_log_index_by_segment ON call_log_index(call_id)",
                "unknown calls source index order",
            ),
            (
                "CREATE TABLE sqlitex_unknown_authority(payload TEXT NOT NULL); INSERT INTO sqlitex_unknown_authority VALUES('unrecognized user authority')",
                "unknown calls source table sqlitex_unknown_authority",
            ),
        ] {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            let store = CallsStore::prepare(&path).await?;
            store.close().await?;
            let db = open_wal_fixture(&path).await?;
            db.execute_unprepared(mutation).await?;
            assert_preserved_rejection(&path, expected).await?;
            if table_exists(&db, "sqlitex_unknown_authority").await? {
                let row = db
                    .query_one_raw(statement(
                        "SELECT payload FROM sqlitex_unknown_authority",
                        vec![],
                    ))
                    .await?
                    .unwrap();
                assert_eq!(
                    row.try_get::<String>("", "payload")?,
                    "unrecognized user authority"
                );
                assert_eq!(
                    <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                        .await?
                        .len(),
                    5
                );
            }
            db.close().await?;
        }
        for source in [
            "CREATE TABLE unrelated(payload TEXT); INSERT INTO unrelated VALUES('preserve me');",
            // LIKE 'sqlite_%' incorrectly hides this user table: '_' is a wildcard.
            "CREATE TABLE sqlitex_unknown_authority(payload TEXT NOT NULL); INSERT INTO sqlitex_unknown_authority VALUES('unrecognized user authority');",
            // Known old format cannot be mistaken for a new database or repaired with an
            // empty authoritative source table, even when all official records are absent.
            "CREATE TABLE calls_meta(id INTEGER PRIMARY KEY CHECK(id=1),schema_version INTEGER NOT NULL,database_id TEXT NOT NULL); INSERT INTO calls_meta VALUES(1,3,'old'); CREATE TABLE call_watermarks(thread_id TEXT PRIMARY KEY,admitted_write_seq INTEGER NOT NULL,durable_write_seq INTEGER NOT NULL);",
        ] {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            let db = open_wal_fixture(&path).await?;
            db.execute_unprepared(source).await?;
            assert_preserved_rejection(&path, "existing data preserved").await?;
            assert!(!tokio::fs::try_exists(temp.path().join("logs")).await?);
            assert!(!table_exists(&db, "seaql_migrations").await?);
            if table_exists(&db, "sqlitex_unknown_authority").await? {
                let row = db
                    .query_one_raw(statement(
                        "SELECT payload FROM sqlitex_unknown_authority",
                        vec![],
                    ))
                    .await?
                    .unwrap();
                assert_eq!(
                    row.try_get::<String>("", "payload")?,
                    "unrecognized user authority"
                );
            }
            db.close().await?;
        }
        // Also reject sqlitex_ user authority in a valid, unopened legacy source:
        // no logs or official migration rows exist before adding the unknown object.
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let db = constraint_source_fixture(&path, LEGACY_SCHEMA_SQL, "").await?;
        let _ = preflight(&db, temp.path().join("logs")).await?;
        db.execute_unprepared("CREATE TABLE sqlitex_unknown_authority(payload TEXT NOT NULL); INSERT INTO sqlitex_unknown_authority VALUES('unrecognized user authority')").await?;
        assert_preserved_rejection(
            &path,
            "unknown calls source table sqlitex_unknown_authority",
        )
        .await?;
        assert!(!tokio::fs::try_exists(temp.path().join("logs")).await?);
        assert!(!table_exists(&db, "seaql_migrations").await?);
        assert_eq!(format_version(&db).await?, 3);
        let row = db
            .query_one_raw(statement(
                "SELECT payload FROM sqlitex_unknown_authority",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(
            row.try_get::<String>("", "payload")?,
            "unrecognized user authority"
        );
        db.close().await?;
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let now = crate::studio::unix_seconds();
        let db = open_wal_fixture(&path).await?;
        db.execute_unprepared(LEGACY_SCHEMA_SQL).await?;
        db.execute_unprepared(&format!("ALTER TABLE model_calls ADD COLUMN body TEXT;
            INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,body)
            VALUES('thread','call','turn','call',1,{now},{now},'running',0,x'ff');")).await?;
        assert_preserved_rejection(&path, "invalid legacy calls payload storage").await?;
        assert!(!tokio::fs::try_exists(temp.path().join("logs")).await?);
        db.close().await?;

        // Existing bad constraints are not missing-column compatibility. Keep a real
        // writer alive so these fixtures include valid committed WAL content throughout
        // the read-only rejection, not just a closed/checkpointed main database file.
        let mut variants = Vec::new();
        for field in [
            "admitted_write_seq",
            "durable_write_seq",
            "revision",
            "admitted_at",
            "started_at",
            "terminal",
        ] {
            for replacement in [
                format!("{field} INTEGER"),
                format!("{field} INTEGER NOT NULL DEFAULT 9"),
            ] {
                let original = format!("{field} INTEGER NOT NULL");
                let table = if field.ends_with("write_seq") {
                    "call_watermarks"
                } else {
                    "model_calls"
                };
                let reason = if replacement.contains("DEFAULT") {
                    "has an unsupported DEFAULT"
                } else {
                    "lacks its NOT NULL constraint"
                };
                variants.push((
                    LEGACY_SCHEMA_SQL.replacen(&original, &replacement, 1),
                    String::new(),
                    format!("{table}.{field} {reason}"),
                ));
            }
        }
        for field in [
            "revision",
            "admitted_at",
            "started_at",
            "terminal",
            "cancel_requested",
        ] {
            for declaration in ["INTEGER", "INTEGER NOT NULL DEFAULT 9"] {
                let reason = if declaration.contains("DEFAULT") {
                    "has an unsupported DEFAULT"
                } else {
                    "lacks its NOT NULL constraint"
                };
                variants.push((
                    LEGACY_SCHEMA_SQL.to_owned(),
                    format!("ALTER TABLE tool_calls ADD COLUMN {field} {declaration};"),
                    format!("tool_calls.{field} {reason}"),
                ));
            }
        }
        variants.push((
            LEGACY_SCHEMA_SQL.replace(
                "has_unpriced_usage INTEGER NOT NULL DEFAULT 0",
                "has_unpriced_usage INTEGER NOT NULL DEFAULT 9",
            ),
            String::new(),
            "model_calls.has_unpriced_usage has an unsupported DEFAULT".into(),
        ));
        variants.push((
            LEGACY_SCHEMA_SQL.replace(
                "schema_version INTEGER NOT NULL",
                "schema_version INTEGER NOT NULL DEFAULT 9",
            ),
            String::new(),
            "calls_meta.schema_version has an unsupported DEFAULT".into(),
        ));
        for (ddl, extra, expected) in variants {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            let db = constraint_source_fixture(&path, &ddl, &extra).await?;
            assert!(
                tokio::fs::read(wal_path(&path)).await?.len() > 32,
                "fixture must retain committed WAL frames"
            );
            assert!(
                <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                    .await?
                    .is_empty()
            );
            assert_preserved_rejection(&path, &expected).await?;
            assert!(
                !table_exists(&db, "seaql_migrations").await?,
                "preflight must not install/commit steps 1/2"
            );
            assert!(
                <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
                    .await?
                    .is_empty()
            );
            assert!(
                db.query_one_raw(statement(
                    "SELECT call_id FROM model_calls WHERE call_id='call'",
                    vec![]
                ))
                .await?
                .is_some()
            );
            assert!(!tokio::fs::try_exists(temp.path().join("logs")).await?);
            db.close().await?;
        }
        // The same existing-column rule also applies after a real shared prefix 1.
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let db = constraint_source_fixture(&path, LEGACY_SCHEMA_SQL, "").await?;
        Migrator::Atomic {
            log_dir: temp.path().join("logs"),
        }
        .up(&db, Some(1))
        .await?;
        db.execute_unprepared("ALTER TABLE call_watermarks RENAME TO previous_watermarks;
            CREATE TABLE call_watermarks(thread_id TEXT PRIMARY KEY,admitted_write_seq INTEGER,durable_write_seq INTEGER NOT NULL);
            INSERT INTO call_watermarks SELECT * FROM previous_watermarks;
            DROP TABLE previous_watermarks;").await?;
        let before: Vec<_> = <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
            .await?
            .into_iter()
            .map(|step| step.name().to_owned())
            .collect();
        assert_eq!(before.len(), 1);
        assert_preserved_rejection(
            &path,
            "call_watermarks.admitted_write_seq lacks its NOT NULL constraint",
        )
        .await?;
        let after: Vec<_> = <Catalog as MigratorTrait>::get_applied_migrations_read_only(&db)
            .await?
            .into_iter()
            .map(|step| step.name().to_owned())
            .collect();
        assert_eq!(after, before);
        assert!(!tokio::fs::try_exists(temp.path().join("logs")).await?);
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn current_formats_keep_legal_legacy_remnants_without_reexporting_or_rebilling()
    -> Result<()> {
        for version in [5, 6, 7] {
            let temp = tempfile::tempdir()?;
            let path = temp.path().join("calls.sqlite");
            seed_legacy_for_test(&path, &format!("UPDATE calls_meta SET schema_version={version};
                INSERT INTO model_calls(thread_id,call_id,root_thread_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,cost_currency,cost_amount)
                VALUES('thread','retained-source','thread','turn','retained-source',1,0,0,'committed',1,'USD',999.0);")).await?;
            let db = connect_existing(&path).await?;
            ensure_schema(&db).await?;
            if version >= 6 {
                detach_legacy_performance(&db).await?;
            }
            db.execute_unprepared(
                "INSERT INTO call_usage_summary VALUES('thread','thread','','USD',3.5,0,9)",
            )
            .await?;
            db.close().await?;
            let store = CallsStore::prepare(&path).await?;
            let rows = store
                .writer
                .db
                .query_all_raw(statement(
                    "SELECT call_id,cost_amount FROM model_calls",
                    vec![],
                ))
                .await?;
            assert_eq!(rows.len(), 1);
            assert_eq!(rows[0].try_get::<String>("", "call_id")?, "retained-source");
            assert_eq!(rows[0].try_get::<f64>("", "cost_amount")?, 999.0);
            assert!(table_exists(&store.writer.db, "tool_calls").await?);
            assert!(table_exists(&store.writer.db, "call_bodies").await?);
            assert_eq!(
                store.session_cost_rollups().await?[0].estimated_costs[0].amount,
                3.5
            );
            assert!(log_lines(&temp.path().join("logs")).await?.is_empty());
            store.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn empty_and_memory_databases_use_the_atomic_lineage_and_reopen_idempotently()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let db = Database::connect("sqlite::memory:").await?;
        initialize(&db, temp.path()).await?;
        let before = db
            .query_one_raw(statement(
                "SELECT database_id FROM calls_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "database_id")?;
        for _ in 0..2 {
            initialize(&db, temp.path()).await?;
            let (lineage, prefix) = Migrator::recorded(&db, PathBuf::new()).await?;
            assert!(matches!(lineage, Migrator::Atomic { .. }));
            assert_eq!(prefix, 5);
            assert_eq!(format_version(&db).await?, CALLS_SCHEMA_VERSION);
            assert_eq!(
                db.query_one_raw(statement(
                    "SELECT database_id FROM calls_meta WHERE id=1",
                    vec![]
                ))
                .await?
                .unwrap()
                .try_get::<String>("", "database_id")?,
                before
            );
        }
        db.close().await?;
        let path = temp.path().join("calls.sqlite");
        let empty = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        empty.close().await?;
        let store = CallsStore::prepare(&path).await?;
        store.close().await?;
        let reopened = CallsStore::prepare(&path).await?;
        let (lineage, prefix) = Migrator::recorded(&reopened.writer.db, PathBuf::new()).await?;
        assert!(matches!(lineage, Migrator::Atomic { .. }));
        assert_eq!(prefix, 5);
        assert!(reopened.session_cost_rollups().await?.is_empty());
        reopened.close().await?;
        Ok(())
    }

    async fn assert_preserved_rejection(path: &Path, expected: &str) -> Result<()> {
        let before = tokio::fs::read(path).await?;
        // Every rejection fixture retains its writer and committed frames. A closed,
        // checkpointed fixture has no committed WAL to protect, and SQLite may create
        // an empty sidecar on a read-only open; that is not this preservation proof.
        let wal_before = tokio::fs::read(wal_path(path)).await?;
        assert!(
            wal_before.len() > 32,
            "bad-source fixture must retain committed WAL frames: {expected}"
        );
        let root = path.parent().unwrap();
        tokio::fs::create_dir_all(root.join("blobs")).await?;
        tokio::fs::write(root.join("blobs/source-sentinel"), b"preserve this source").await?;
        let blobs_before = blob_snapshot(&root.join("blobs")).await?;
        let error = match CallsStore::prepare(path).await {
            Ok(_) => anyhow::bail!("invalid calls source was accepted: {expected}"),
            Err(error) => error,
        };
        assert!(format!("{error:#}").contains(expected), "{error:#}");
        assert!(
            format!("{error:#}").contains("calls SQLite migration step preflight"),
            "{error:#}"
        );
        assert_eq!(
            crate::studio::startup::StudioStartupError::input("calls test", error).kind,
            crate::studio::startup::StudioStartupErrorKind::Migration
        );
        assert_eq!(
            tokio::fs::read(path).await?,
            before,
            "source bytes must be unchanged"
        );
        assert_eq!(
            tokio::fs::read(wal_path(path)).await?,
            wal_before,
            "committed WAL bytes must be unchanged: {expected}"
        );
        assert_eq!(
            tokio::fs::read(root.join("blobs/source-sentinel")).await?,
            b"preserve this source"
        );
        assert_eq!(blob_snapshot(&root.join("blobs")).await?, blobs_before);
        Ok(())
    }

    async fn constraint_source_fixture(
        path: &Path,
        ddl: &str,
        extra: &str,
    ) -> Result<DatabaseConnection> {
        let db = open_wal_fixture(path).await?;
        db.execute_unprepared(ddl).await?;
        if !extra.is_empty() {
            db.execute_unprepared(extra).await?;
        }
        let now = crate::studio::unix_seconds();
        let body = serde_json::to_vec(&AttemptUpdate {
            request_metadata: None,
            usage_binding: None,
            tool_projection: None,
            turn_id: "turn".into(),
            attempt_id: "call".into(),
            retry_of: None,
            input_revision: 7,
            tools: Default::default(),
            outcome: AttemptOutcome::Running,
            input_estimate: None,
        })?;
        let hash = pl_core::context::content_hash(&body);
        let blobs = path.parent().unwrap().join("blobs");
        tokio::fs::create_dir_all(&blobs).await?;
        tokio::fs::write(blobs.join(hash.strip_prefix("sha256:").unwrap()), &body).await?;
        db.execute_raw(statement(
            "INSERT INTO call_bodies(body_ref,byte_length,created_at) VALUES(?,?,?)",
            vec![
                hash.clone().into(),
                i64::try_from(body.len())?.into(),
                now.into(),
            ],
        ))
        .await?;
        db.execute_unprepared("INSERT INTO call_watermarks VALUES('thread',31,29)")
            .await?;
        db.execute_raw(statement("INSERT INTO model_calls(thread_id,call_id,root_thread_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,cost_currency,cost_amount,body_ref)
            VALUES('thread','call','thread','turn','call',1,?,?,'running',0,'USD',3.5,?)", vec![now.into(), now.into(), hash.into()])).await?;
        Ok(db)
    }

    async fn open_wal_fixture(path: &Path) -> Result<DatabaseConnection> {
        let mut options = crate::studio::paths::sqlite_file_options(
            path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?;
        options.max_connections(1).min_connections(1);
        let db = Database::connect(options).await?;
        db.execute_unprepared("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
            .await?;
        Ok(db)
    }

    fn wal_path(path: &Path) -> PathBuf {
        let mut wal = path.as_os_str().to_os_string();
        wal.push("-wal");
        PathBuf::from(wal)
    }

    async fn blob_snapshot(path: &Path) -> Result<Vec<(std::ffi::OsString, Vec<u8>)>> {
        let mut files = tokio::fs::read_dir(path).await?;
        let mut snapshot = Vec::new();
        while let Some(file) = files.next_entry().await? {
            snapshot.push((file.file_name(), tokio::fs::read(file.path()).await?));
        }
        snapshot.sort_by(|(left, _), (right, _)| left.cmp(right));
        Ok(snapshot)
    }

    async fn connect_existing(path: &Path) -> Result<DatabaseConnection> {
        Ok(Database::connect(
            crate::studio::paths::sqlite_file_options(
                path,
                crate::studio::paths::SqliteFileMode::ReadWrite,
                |options| options,
            )
            .await?,
        )
        .await?)
    }

    async fn log_lines(dir: &Path) -> Result<Vec<String>> {
        let mut entries = tokio::fs::read_dir(dir).await?;
        let mut lines = Vec::new();
        while let Some(entry) = entries.next_entry().await? {
            if entry.path().extension().is_some_and(|ext| ext == "jsonl") {
                lines.extend(
                    tokio::fs::read_to_string(entry.path())
                        .await?
                        .lines()
                        .map(str::to_owned),
                );
            }
        }
        Ok(lines)
    }
}
