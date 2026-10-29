//! `calls.sqlite` 的当前 schema、启动清理与 旧调用结构 → 当前结构 的保源迁移。
//!
//! 迁移只做加法并保持可重入：先把旧 `model_calls` 的累计费用保全为摘要，再把保留期内的正文按批
//! 转换成 JSONL 日志记录（按 `(thread_id, call_id, kind)` 幂等去重），最后才删除旧表并清理无引用的
//! blobs 目录。旧结构的耗时列不构成当前统计口径的样本，因此旧性能统计直接丢弃、不迁移；原始日志、
//! 账单与费用保留。导出失败保留旧格式及源表；最终事务提交后，blobs 清理失败保留待清理标记，
//! 下次打开继续。旧版本（v1）的数据根不在本模块触碰范围内。

use super::*;
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

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
    let result = preflight(&db)
        .await
        .map_err(|error| crate::studio::startup::migration_error("calls", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

pub(super) async fn initialize(db: &DatabaseConnection, root_dir: &Path) -> Result<()> {
    preflight(db)
        .await
        .map_err(|error| crate::studio::startup::migration_error("calls", "preflight", error))?;
    let migrator = Migrator {
        log_dir: root_dir.join(super::CALL_LOG_DIR_NAME),
    };
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
async fn preflight(db: &DatabaseConnection) -> Result<()> {
    let manager = SchemaManager::new(db);
    if manager.has_table("calls_meta").await? {
        let version = format_version(db).await?;
        ensure!(
            (1..=CALLS_SCHEMA_VERSION).contains(&version),
            "unsupported calls schema {version}; existing data preserved"
        );
        if version >= 7 {
            for table in [
                "call_watermarks",
                "call_log_index",
                "call_usage_summary",
                "performance_samples",
            ] {
                ensure!(
                    manager.has_table(table).await?,
                    "current calls table {table} is missing; existing data preserved"
                );
            }
        }
    } else {
        ensure!(db.query_one_raw(statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_none(), "unversioned nonempty calls database; existing data preserved");
        ensure!(
            Migrator {
                log_dir: PathBuf::new()
            }
            .get_applied_migrations_read_only(db)
            .await?
            .is_empty(),
            "calls schema is missing; existing data preserved"
        );
    }
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "calls database integrity check failed"
        );
    }
    let pending = Migrator {
        log_dir: PathBuf::new(),
    }
    .get_pending_migrations_read_only(db)
    .await?;
    if pending.is_empty() {
        ensure!(
            format_version(db).await? == CALLS_SCHEMA_VERSION,
            "calls format conflicts with completed migrations; existing data preserved"
        );
    }
    Ok(())
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
struct Migrator {
    log_dir: PathBuf,
}
impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(CallsSchema),
            Box::new(LegacySummary),
            Box::new(ExportLog {
                log_dir: self.log_dir.clone(),
            }),
            Box::new(FinalizeLegacy),
            Box::new(ThroughputEpoch),
            Box::new(MaterialProvenance),
        ]
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
            convert_legacy_tools(db, &mut log)
                .await
                .map_err(conversion)?;
        }
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

struct MaterialProvenance;
impl MigrationName for MaterialProvenance {
    fn name(&self) -> &str {
        "m20261026_000006_calls_material_provenance"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MaterialProvenance {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        ensure_columns(
            db,
            "performance_samples",
            &[
                ("purpose", "TEXT"),
                ("usage_status", "TEXT NOT NULL DEFAULT 'legacyUnknown'"),
                (
                    "first_output_source",
                    "TEXT NOT NULL DEFAULT 'legacyUnknown'",
                ),
                ("throughput_valid", "INTEGER NOT NULL DEFAULT 0"),
            ],
        )
        .await
        .map_err(conversion)?;
        ensure_columns(db, "call_usage_summary", &[("content_hash", "TEXT")])
            .await
            .map_err(conversion)?;
        upgrade_auxiliary_usage(db).await.map_err(conversion)?;
        db.execute_unprepared(
            "CREATE INDEX IF NOT EXISTS call_usage_summary_by_thread ON call_usage_summary(thread_id,revision DESC);
             UPDATE calls_meta SET schema_version=8 WHERE id=1;"
        ).await?;
        Ok(())
    }
}

/// Exact flat payload emitted by the retired calls aggregation migration. It is
/// deliberately not accepted by the normal UsageSummary reader, nor default-filled.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyAuxiliaryUsage {
    inference_count: u64,
    prompt_tokens: u64,
    completion_tokens: u64,
    cached_prompt_tokens: u64,
    cache_write_tokens: u64,
    reasoning_tokens: u64,
    total_tokens: u64,
    has_incomplete_usage: bool,
    cache_incomplete: bool,
    has_unpriced_usage: bool,
}

async fn upgrade_auxiliary_usage(db: &impl ConnectionTrait) -> Result<()> {
    for row in db
        .query_all_raw(statement(
            "SELECT thread_id,payload FROM legacy_auxiliary_usage",
            vec![],
        ))
        .await?
    {
        let old: LegacyAuxiliaryUsage =
            serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        let current = pl_core::thread::UsageSummary {
            totals: pl_core::usage::UsageTotals {
                inference_count: old.inference_count,
                prompt_tokens: old.prompt_tokens,
                completion_tokens: old.completion_tokens,
                cached_prompt_tokens: old.cached_prompt_tokens,
                cache_write_tokens: old.cache_write_tokens,
                reasoning_tokens: old.reasoning_tokens,
                total_tokens: old.total_tokens,
            },
            cache: pl_core::usage::UsageCacheSummary {
                incomplete: old.cache_incomplete,
                ..Default::default()
            },
            diagnostics: pl_core::usage::UsageDiagnostics {
                legacy_unknown: true,
                legacy_incomplete: old.has_incomplete_usage,
                ..Default::default()
            },
            pricing: pl_core::thread::UsagePricingSummary {
                incomplete: old.has_unpriced_usage,
                ..Default::default()
            },
            ..Default::default()
        };
        db.execute_raw(statement(
            "UPDATE legacy_auxiliary_usage SET payload=? WHERE thread_id=?",
            vec![
                serde_json::to_string(&current)?.into(),
                row.try_get::<String>("", "thread_id")?.into(),
            ],
        ))
        .await?;
    }
    Ok(())
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
            if let Some(body) = legacy_payload(
                db,
                &log.root_dir(),
                row,
                "body_ref",
                &["body", "body_text", "body_json"],
            )
            .await?
            {
                let attempt: AttemptUpdate = serde_json::from_slice(&body)?;
                ensure!(
                    attempt.attempt_id == record.call_id
                        && attempt.turn_id.as_str()
                            == record.turn_id.as_deref().unwrap_or_default(),
                    "legacy call body identity mismatch"
                );
                let (diagnostic, truncated) = event::diagnostic(&attempt.outcome);
                record.diagnostic = Some(diagnostic);
                record.truncated = truncated;
                record.input_revision = Some(attempt.input_revision);
            }
            if let Some(body) = legacy_payload(
                db,
                &log.root_dir(),
                row,
                "billing_ref",
                &["billing_body", "billing_json"],
            )
            .await?
            {
                validate_legacy_billing(&body)?;
            }
            append_record(&tx, log, &PreparedRecord::new(record)?, now).await?;
        }
        log.sync_pending().await?;
        tx.commit().await?;
    }
    Ok(())
}

fn is_retained(recorded_at: i64, now: i64) -> bool {
    now.saturating_sub(recorded_at) <= log::LOG_RETENTION_SECONDS
}

/// Only the retired blob boundary accepts timing without a first-content provenance.
/// This validates in memory; neither historical blob bytes nor JSONL records are rewritten.
fn validate_legacy_billing(body: &[u8]) -> Result<()> {
    let mut value: serde_json::Value = serde_json::from_slice(body)?;
    if let Some(timing) = value
        .get_mut("timing")
        .and_then(serde_json::Value::as_object_mut)
    {
        timing
            .entry("firstOutputSource")
            .or_insert_with(|| serde_json::json!("legacyUnknown"));
    }
    let _: InferenceBillingRecord = serde_json::from_value(value)?;
    Ok(())
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
        usage_status: Some(pl_core::usage::UsageStatus::LegacyUnknown),
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
async fn migration_columns(db: &DatabaseConnection, table: &str) -> Result<String> {
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
    db.execute_unprepared(seed_sql).await?;
    if schema_version >= 7 {
        ensure_schema(&db).await?;
    }
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
    db: &DatabaseConnection,
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

async fn convert_legacy_tools(db: &DatabaseConnection, log: &mut CallLog) -> Result<()> {
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
                    let tx = db.begin().await?;
                    append_record(&tx, log, &PreparedRecord::new(record)?, now).await?;
                    log.sync_pending().await?;
                    tx.commit().await?;
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;

    #[test]
    fn legacy_billing_timing_is_adapted_only_at_the_retired_blob_boundary() -> Result<()> {
        let body = serde_json::to_vec(&serde_json::json!({
            "inferenceId": "legacy", "accounting": pl_protocol::InferenceAccounting::default(),
            "recordedAt": 10, "timing": {
                "ttftMillis": 5, "decodeMillis": 95, "responseMillis": 100
            },
        }))?;
        assert!(
            serde_json::from_slice::<InferenceBillingRecord>(&body).is_err(),
            "normal runtime decoding still requires an explicit source"
        );
        validate_legacy_billing(&body)?;
        assert!(
            !serde_json::from_slice::<serde_json::Value>(&body)?["timing"]
                .as_object()
                .unwrap()
                .contains_key("firstOutputSource")
        );
        Ok(())
    }

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
        ensure_columns(&db, "call_usage_summary", &[("content_hash", "TEXT")]).await?;
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
            "test-summary",
            #[cfg(feature = "benchmarks")]
            None,
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
                first_output_source: pl_protocol::FirstOutputSource::Incremental,
                ttft_millis: Some(2_700),
                decode_millis: Some(278),
                response_millis: Some(2_978),
            }),
            usage_status: Some(pl_core::usage::UsageStatus::Partial),
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
        log.sync_pending().await?;
        drop(log);
        let store = CallsStore::open(&path).await?;
        assert!(!store.statistics_gap());
        assert_eq!(store.recent_performance_samples(10).await?.len(), 1);
        assert_eq!(
            store
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")[0]
                .completion_tokens,
            41
        );
        // A fresh successful call must also insert into the repaired table.
        let mut next = record;
        next.call_id = "new-sample".into();
        let tx = store.writer.db.begin().await?;
        let mut log = store.writer.log.lock().await;
        apply_billing(&mut log, &tx, &PreparedRecord::new(next)?).await?;
        log.sync_pending().await?;
        tx.commit().await?;
        drop(log);
        assert_eq!(
            store
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")[0]
                .sample_count,
            2
        );
        assert_eq!(
            store.session_cost_rollups().await?[0].estimated_costs[0].amount,
            3.0
        );
        store.stop_best_effort();
        let reopened = CallsStore::open(&path).await?;
        assert!(!reopened.statistics_gap());
        assert_eq!(
            reopened
                .read_statistics(StatisticsReadRequest {
                    costs: false,
                    performance: true,
                })
                .await?
                .summary
                .expect("performance summary requested")[0]
                .sample_count,
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
        seed_legacy_for_test(&path, &format!("ALTER TABLE tool_calls ADD COLUMN started_at INTEGER;
            INSERT INTO tool_calls(thread_id,call_id,body_ref,started_at) VALUES('thread','tool','{hash}',{now});
            INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,revision,admitted_at,started_at,status,terminal,purpose,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,reasoning_tokens,total_tokens,has_unpriced_usage,cost_currency,cost_amount,root_thread_id)
            VALUES('thread','review','turn','review',1,{now},{now},'committed',1,'review',10,5,2,1,3,15,1,'USD',4.0,'thread');")).await?;
        tokio::fs::create_dir_all(temp.path().join("blobs")).await?;
        tokio::fs::write(
            temp.path()
                .join("blobs")
                .join(hash.strip_prefix("sha256:").unwrap()),
            body,
        )
        .await?;
        let store = CallsStore::open(&path).await?;
        let usage = store.legacy_auxiliary_usage("thread").await?;
        assert_eq!(
            usage.totals,
            pl_core::usage::UsageTotals {
                inference_count: 1,
                prompt_tokens: 10,
                completion_tokens: 5,
                cached_prompt_tokens: 2,
                cache_write_tokens: 1,
                reasoning_tokens: 3,
                total_tokens: 15,
            }
        );
        assert!(usage.cache.incomplete);
        assert!(usage.diagnostics.legacy_unknown);
        assert!(usage.diagnostics.legacy_incomplete);
        assert!(usage.pricing.incomplete);
        assert_eq!(
            usage.diagnostics.incomplete_calls, 0,
            "legacy flags do not prove per-call diagnostic counts"
        );
        assert_eq!(
            usage.cache.sample_count, 0,
            "legacy totals do not prove cache sample counts"
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
        assert_eq!(reopened.legacy_auxiliary_usage("thread").await?, usage);
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
        assert!(CallsStore::open(&path).await.is_err());
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
        store.stop_best_effort();
        let reopened = CallsStore::open(&path).await?;
        assert!(
            db.query_one_raw(statement(
                "SELECT call_id FROM call_log_index WHERE call_id='call'",
                vec![]
            ))
            .await?
            .is_some()
        );
        reopened.stop_best_effort();
        Ok(())
    }
    #[tokio::test]
    async fn durable_export_rebuilds_its_index_before_retry_without_duplicate_logs_or_costs()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let now = crate::studio::unix_seconds();
        seed_legacy_for_test(&path, &format!("INSERT INTO model_calls(thread_id,call_id,turn_id,attempt_id,root_thread_id,revision,admitted_at,started_at,status,terminal,cost_currency,cost_amount) VALUES('thread','call','turn','call','thread',1,{now},{now},'committed',1,'USD',3.5)")).await?;
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::ReadWrite,
                |options| options,
            )
            .await?,
        )
        .await?;
        ensure_schema(&db).await?;
        db.execute_unprepared("CREATE TRIGGER reject_export_index BEFORE INSERT ON call_log_index BEGIN SELECT RAISE(ABORT,'injected export index failure'); END").await?;
        db.close().await?;
        let error = match CallsStore::prepare(&path).await {
            Ok(_) => anyhow::bail!("injected index failure was ignored"),
            Err(error) => error,
        };
        assert!(format!("{error:#}").contains("m20261026_000003_calls_export_log"));
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::ReadWrite,
                |options| options,
            )
            .await?,
        )
        .await?;
        assert!(table_exists(&db, "model_calls").await?);
        assert_eq!(
            db.query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                .await?
                .len(),
            0
        );
        assert!(db.query_one_raw(statement("SELECT version FROM seaql_migrations WHERE version='m20261026_000003_calls_export_log'", vec![])).await?.is_none());
        db.execute_unprepared("DROP TRIGGER reject_export_index")
            .await?;
        db.close().await?;
        for _ in 0..2 {
            let store = CallsStore::prepare(&path).await?;
            assert_eq!(
                store.session_cost_rollups().await?[0].estimated_costs[0].amount,
                3.5
            );
            assert_eq!(
                store
                    .writer
                    .db
                    .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![]))
                    .await?
                    .len(),
                1
            );
            assert!(!table_exists(&store.writer.db, "model_calls").await?);
            store.close().await?;
        }
        let mut entries = tokio::fs::read_dir(temp.path().join("logs")).await?;
        let mut lines = 0;
        while let Some(entry) = entries.next_entry().await? {
            if entry.path().extension().is_some_and(|ext| ext == "jsonl") {
                lines += tokio::fs::read_to_string(entry.path())
                    .await?
                    .lines()
                    .count();
            }
        }
        assert_eq!(
            lines, 1,
            "the durable append must be recovered rather than duplicated"
        );
        Ok(())
    }
}
