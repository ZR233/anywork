//! Explicit offline migrations, ordered and committed by SeaORM.
use super::{SessionStoreError, SqliteSessionOptions, sqlite};
use sea_orm::{ConnectionTrait, Database, DatabaseConnection, DbErr};
use sea_orm_migration::{MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

/// Minimal view of a stored checkpoint the usage backfill needs.
///
/// It deliberately omits the resident attempts so a schema-1/2 envelope decodes without the current
/// read path, which no longer interprets that layout; the attempt bodies stay byte-for-byte intact
/// for the later conversion step.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct UsageBackfillEnvelope {
    thread_id: String,
    state_revision: u64,
    history_fence: u64,
    #[serde(default)]
    external_bodies: Vec<serde_json::Value>,
    state: UsageBackfillState,
}

/// The two checkpoint state facts the usage backfill reads and rewrites.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct UsageBackfillState {
    commit_sequence: u64,
    #[serde(default)]
    usage_summary: crate::thread::checkpoint_usage::LegacyUsageSummary,
}

/// Upgrades an existing database while holding its exclusive maintenance lease.
/// Each official migration commits independently; failures preserve source data for retry.
/// # Errors
/// Rejects missing or active databases, unsupported formats, invalid facts and storage failures.
pub async fn migrate_to_current(options: SqliteSessionOptions) -> Result<(), SessionStoreError> {
    if !tokio::fs::try_exists(&options.path).await? {
        return Err(SessionStoreError::Invalid(
            "session database does not exist".into(),
        ));
    }
    let _lease = sqlite::acquire_database_lock(options.path.clone()).await?;
    inspect_existing(&options.path, true).await?;
    let mut url = url::Url::parse("sqlite:///")
        .map_err(|error| SessionStoreError::Invalid(error.to_string()))?;
    url.set_path(
        options
            .path
            .to_str()
            .ok_or_else(|| SessionStoreError::Invalid("non-UTF8 database path".into()))?,
    );
    url.set_query(Some("mode=rw"));
    let db = Database::connect(url.to_string()).await?;
    let result = async {
        preflight(&db, true).await?;
        let migrator = Migrator;
        if let Err(error) = migrator.up(&db, None).await {
            let pending = migrator
                .get_pending_migrations_read_only(&db)
                .await
                .unwrap_or_default();
            let step = pending
                .first()
                .map_or("migration bookkeeping", |migration| migration.name());
            return Err(SessionStoreError::Migration {
                step: step.into(),
                source: Box::new(error),
            });
        }
        Ok(())
    }
    .await;
    match (result, db.close().await) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(error)) => Err(error.into()),
        (Err(initialization), Err(cleanup)) => Err(SessionStoreError::InitializationCleanup {
            initialization: Box::new(initialization),
            cleanup: Box::new(cleanup),
        }),
    }
}

pub(super) async fn initialize(db: &DatabaseConnection) -> Result<(), SessionStoreError> {
    preflight(db, false).await?;
    let migrator = Migrator;
    if let Err(error) = migrator.up(db, None).await {
        let pending = migrator
            .get_pending_migrations_read_only(db)
            .await
            .unwrap_or_default();
        let step = pending
            .first()
            .map_or("migration bookkeeping", |migration| migration.name());
        return Err(SessionStoreError::Migration {
            step: step.into(),
            source: Box::new(error),
        });
    }
    Ok(())
}

pub(super) async fn inspect_existing(
    path: &std::path::Path,
    allow_upgrade: bool,
) -> Result<(), SessionStoreError> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let mut url = url::Url::parse("sqlite:///")
        .map_err(|error| SessionStoreError::Invalid(error.to_string()))?;
    url.set_path(
        path.to_str()
            .ok_or_else(|| SessionStoreError::Invalid("non-UTF8 database path".into()))?,
    );
    url.set_query(Some("mode=ro"));
    let mut options = sea_orm::ConnectOptions::new(url.to_string());
    options.max_connections(1);
    let db = Database::connect(options).await?;
    let result = preflight(&db, allow_upgrade).await;
    match (result, db.close().await) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(error)) => Err(error.into()),
        (Err(initialization), Err(cleanup)) => Err(SessionStoreError::InitializationCleanup {
            initialization: Box::new(initialization),
            cleanup: Box::new(cleanup),
        }),
    }
}

async fn version(db: &impl ConnectionTrait) -> Result<i64, SessionStoreError> {
    Ok(db
        .query_one_raw(sqlite::statement("PRAGMA user_version", vec![]))
        .await?
        .ok_or_else(|| SessionStoreError::Invalid("missing session format".into()))?
        .try_get_by_index(0)?)
}
async fn preflight(db: &DatabaseConnection, allow_upgrade: bool) -> Result<(), SessionStoreError> {
    let found = version(db).await?;
    if found == 0 {
        if allow_upgrade || db.query_one_raw(sqlite::statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_some() {
            return Err(SessionStoreError::UnsupportedSchema { found, supported: super::SESSION_SCHEMA_VERSION });
        }
    } else if !(7..=super::SESSION_SCHEMA_VERSION).contains(&found)
        || (!allow_upgrade && found != super::SESSION_SCHEMA_VERSION)
    {
        return Err(SessionStoreError::UnsupportedSchema {
            found,
            supported: super::SESSION_SCHEMA_VERSION,
        });
    }
    if SchemaManager::new(db).has_table("thread_checkpoints").await?
        && db.query_one_raw(sqlite::statement(
            "SELECT 1 FROM thread_checkpoints WHERE schema_version NOT BETWEEN 1 AND 6 OR json_extract(envelope,'$.schemaVersion') NOT BETWEEN 1 AND 6 LIMIT 1", vec![]
        )).await?.is_some()
    {
        return Err(SessionStoreError::Invalid("unsupported checkpoint schema; existing data preserved".into()));
    }
    if found >= 12 {
        let manager = SchemaManager::new(db);
        for table in [
            "session_entries",
            "session_entry_history",
            "session_history_heads",
            "thread_checkpoints",
            "thread_tool_tasks",
            "thread_tool_task_resources",
        ] {
            if !manager.has_table(table).await? {
                return Err(SessionStoreError::Invalid(format!(
                    "current session table {table} is missing; existing data preserved"
                )));
            }
        }
    }
    for row in db
        .query_all_raw(sqlite::statement("PRAGMA quick_check", vec![]))
        .await?
    {
        if row.try_get_by_index::<String>(0)? != "ok" {
            return Err(SessionStoreError::Invalid(
                "session database integrity check failed".into(),
            ));
        }
    }
    if !allow_upgrade
        && found != 0
        && db
            .query_one_raw(sqlite::statement(
                "SELECT 1 FROM thread_checkpoints WHERE schema_version<>? LIMIT 1",
                vec![i64::from(crate::thread::ThreadCheckpoint::SCHEMA_VERSION).into()],
            ))
            .await?
            .is_some()
    {
        return Err(SessionStoreError::MigrationRequired);
    }
    let migrator = Migrator;
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    if pending.is_empty() && found != super::SESSION_SCHEMA_VERSION {
        return Err(SessionStoreError::Invalid(
            "session format conflicts with completed migrations; existing data preserved".into(),
        ));
    }
    if found == 0
        && !migrator
            .get_applied_migrations_read_only(db)
            .await?
            .is_empty()
    {
        return Err(SessionStoreError::Invalid(
            "session schema is missing; existing data preserved".into(),
        ));
    }
    Ok(())
}

struct Migrator;
impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(InitialSchema),
            Box::new(CurrentEntries),
            Box::new(CheckpointTable),
            Box::new(UsageSummary),
            Box::new(AttemptIdentity),
            Box::new(TaskIndex),
            Box::new(CheckpointV5),
            Box::new(CurrentEffects),
            Box::new(CheckpointV6),
        ]
    }
}
fn conversion(error: SessionStoreError) -> DbErr {
    match error {
        SessionStoreError::Database(source) => match source.downcast::<DbErr>() {
            Ok(error) => *error,
            Err(error) => DbErr::Migration(error.to_string()),
        },
        error => DbErr::Migration(error.to_string()),
    }
}

struct InitialSchema;
impl MigrationName for InitialSchema {
    fn name(&self) -> &str {
        "m20261026_000001_core_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InitialSchema {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? == 0 {
            db.execute_unprepared(
        "CREATE TABLE session_entries (
            session_id TEXT NOT NULL, id TEXT NOT NULL, type_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL, turn_id TEXT, envelope TEXT NOT NULL CHECK(json_valid(envelope)), payload_hash TEXT NOT NULL,
            PRIMARY KEY(session_id,id));
         CREATE INDEX session_entries_kind ON session_entries(session_id,type_id,ordinal,id);
         CREATE INDEX session_entries_turn ON session_entries(session_id,turn_id,type_id,ordinal);
         CREATE TABLE session_entry_history (
            session_id TEXT NOT NULL, sequence INTEGER NOT NULL,
            envelope TEXT NOT NULL, payload_hash TEXT NOT NULL,
            PRIMARY KEY(session_id,sequence));
         CREATE TABLE session_history_heads (
            session_id TEXT PRIMARY KEY, sequence INTEGER NOT NULL, payload_hash TEXT NOT NULL);
         CREATE TABLE thread_checkpoints (
            thread_id TEXT PRIMARY KEY, schema_version INTEGER NOT NULL,
            state_revision INTEGER NOT NULL, history_fence INTEGER NOT NULL,
            envelope TEXT NOT NULL CHECK(json_valid(envelope)), payload_hash TEXT NOT NULL);"
    ).await?;
            db.execute_unprepared(include_str!("task_index_v12.sql"))
                .await?;
            db.execute_unprepared("PRAGMA user_version=12").await?;
        }
        Ok(())
    }
}

// Preserve this published ledger identity, but never read or convert pre-v2 journals.
struct CurrentEntries;
impl MigrationName for CurrentEntries {
    fn name(&self) -> &str {
        "m20261026_000002_core_entries_v7"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CurrentEntries {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        if version(manager.get_connection())
            .await
            .map_err(conversion)?
            < 7
        {
            return Err(DbErr::Migration(
                "pre-v2 session formats are unsupported".into(),
            ));
        }
        Ok(())
    }
}

struct CheckpointTable;
impl MigrationName for CheckpointTable {
    fn name(&self) -> &str {
        "m20261026_000003_core_checkpoint_table"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CheckpointTable {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? < 8 {
            create_checkpoint_table(db).await.map_err(conversion)?;
            db.execute_unprepared("PRAGMA user_version=8").await?;
        }
        Ok(())
    }
}

struct UsageSummary;
impl MigrationName for UsageSummary {
    fn name(&self) -> &str {
        "m20261026_000004_core_usage_summary"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for UsageSummary {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? < 9 {
            backfill_usage(db).await.map_err(conversion)?;
            db.execute_unprepared("PRAGMA user_version=9").await?;
        }
        Ok(())
    }
}

struct AttemptIdentity;
impl MigrationName for AttemptIdentity {
    fn name(&self) -> &str {
        "m20261026_000005_core_attempt_identity"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AttemptIdentity {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? < 10 {
            backfill_attempt_identity(db).await.map_err(conversion)?;
            db.execute_unprepared("PRAGMA user_version=10").await?;
        }
        Ok(())
    }
}

struct TaskIndex;
impl MigrationName for TaskIndex {
    fn name(&self) -> &str {
        "m20261026_000006_core_task_index"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for TaskIndex {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? < 12 {
            super::task_index_migration::backfill_task_index(db)
                .await
                .map_err(conversion)?;
            db.execute_unprepared("PRAGMA user_version=12").await?;
        }
        Ok(())
    }
}

struct CheckpointV5;
impl MigrationName for CheckpointV5 {
    fn name(&self) -> &str {
        "m20261026_000007_core_checkpoint_v5"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CheckpointV5 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        super::task_index_migration::convert_checkpoints(manager.get_connection())
            .await
            .map_err(conversion)
    }
}

struct CurrentEffects;
impl MigrationName for CurrentEffects {
    fn name(&self) -> &str {
        "m20261026_000008_core_effect_batch_v1"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CurrentEffects {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? < 13 {
            super::effect_migration::convert_effects(db)
                .await
                .map_err(conversion)?;
            db.execute_unprepared("PRAGMA user_version=13").await?;
        }
        Ok(())
    }
}

struct CheckpointV6;
impl MigrationName for CheckpointV6 {
    fn name(&self) -> &str {
        "m20261026_000009_core_checkpoint_v6"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CheckpointV6 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        super::usage_migration::convert_checkpoints(db)
            .await
            .map_err(conversion)?;
        db.execute_unprepared("PRAGMA user_version=14").await?;
        Ok(())
    }
}

async fn create_checkpoint_table(tx: &impl ConnectionTrait) -> Result<(), SessionStoreError> {
    let base = tx
            .query_one_raw(sqlite::statement(
                "SELECT COUNT(*) AS present FROM sqlite_schema WHERE type='table' AND name IN ('session_entries','session_entry_history','session_history_heads')",
                vec![],
            ))
            .await?
            .ok_or_else(|| SessionStoreError::Invalid("missing schema probe".into()))?
            .try_get::<i64>("", "present")?;
    if base != 3 {
        return Err(SessionStoreError::Invalid(
            "session base tables are missing".into(),
        ));
    }
    tx.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS thread_checkpoints (
                thread_id TEXT PRIMARY KEY, schema_version INTEGER NOT NULL,
                state_revision INTEGER NOT NULL, history_fence INTEGER NOT NULL,
                envelope TEXT NOT NULL CHECK(json_valid(envelope)), payload_hash TEXT NOT NULL);",
    )
    .await?;
    Ok(())
}

async fn backfill_usage(tx: &impl ConnectionTrait) -> Result<(), SessionStoreError> {
    let mut after: Option<String> = None;
    loop {
        let rows = match &after {
                Some(after) => {
                    tx.query_all_raw(sqlite::statement(
                        "SELECT * FROM thread_checkpoints WHERE thread_id>? ORDER BY thread_id LIMIT 128",
                        vec![after.clone().into()],
                    ))
                    .await?
                }
                None => {
                    tx.query_all_raw(sqlite::statement(
                        "SELECT * FROM thread_checkpoints ORDER BY thread_id LIMIT 128",
                        vec![],
                    ))
                    .await?
                }
            };
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let thread_id: String = row.try_get("", "thread_id")?;
            after = Some(thread_id.clone());
            // A schema-8 database still stores checkpoints in the schema-1/2 attempt layout,
            // which this build no longer interprets on its normal read path. The backfill only
            // needs the usage summary and revision, so it reifies exactly those facts and writes
            // the summary back into the original envelope: every other byte, including the
            // resident attempt bodies, is preserved for the step that converts the layout.
            let envelope: String = row.try_get("", "envelope")?;
            let stored_hash: String = row.try_get("", "payload_hash")?;
            let state_revision = row.try_get::<i64>("", "state_revision")?;
            let state_revision = u64::try_from(state_revision)
                .map_err(|_| SessionStoreError::Invalid("negative revision".into()))?;
            let history_fence = row.try_get::<i64>("", "history_fence")?;
            let history_fence = u64::try_from(history_fence)
                .map_err(|_| SessionStoreError::Invalid("negative fence".into()))?;
            if crate::context::content_hash(envelope.as_bytes()) != stored_hash {
                return Err(SessionStoreError::Invalid(format!(
                    "Thread {thread_id} checkpoint integrity check failed"
                )));
            }
            let mut value: serde_json::Value = serde_json::from_str(&envelope)?;
            let header: UsageBackfillEnvelope = serde_json::from_value(value.clone())?;
            if header.thread_id != thread_id
                || header.state_revision != state_revision
                || header.history_fence != history_fence
                || header.state_revision != header.state.commit_sequence
                || !header.external_bodies.is_empty()
                || header.state.usage_summary.applied_sequence > header.state_revision
            {
                return Err(SessionStoreError::Invalid(format!(
                    "Thread {thread_id} checkpoint is inconsistent with its fence"
                )));
            }
            if value["state"].get("usageSummary").is_some() {
                // Existing accounting is authoritative, even if a historical writer left its
                // watermark behind. Never replay history over a saved cumulative fact.
                continue;
            }
            let mut summary = crate::thread::UsageSummary::from(header.state.usage_summary);
            let mut expected = summary.applied_sequence + 1;
            let upper = format!("pl.resource.thread-commit.{:020}", header.state_revision);
            while expected <= header.state_revision {
                let lower = format!("pl.resource.thread-commit.{expected:020}");
                let effects = tx
                        .query_all_raw(sqlite::statement(
                            "SELECT * FROM session_entries WHERE session_id=? AND id>=? AND id<=? ORDER BY id LIMIT 256",
                            vec![thread_id.clone().into(), lower.into(), upper.clone().into()],
                        ))
                        .await?;
                if effects.is_empty() {
                    return Err(SessionStoreError::Invalid(format!(
                        "Thread {thread_id} usage history has a sequence gap at {expected}"
                    )));
                }
                for effect_row in effects {
                    let effect = super::effect_migration::decode_effect(effect_row, &thread_id)?;
                    if effect.sequence != expected {
                        return Err(SessionStoreError::Invalid(format!(
                            "Thread {thread_id} usage history has a sequence gap at {expected}"
                        )));
                    }
                    crate::thread::usage::fold_effect(&mut summary, &effect);
                    expected += 1;
                }
            }
            value["state"]["usageSummary"] = serde_json::to_value(
                crate::thread::checkpoint_usage::LegacyUsageSummary::from(summary),
            )?;
            let envelope = serde_json::to_string(&value)?;
            let hash = crate::context::content_hash(envelope.as_bytes());
            tx.execute_raw(sqlite::statement(
                "UPDATE thread_checkpoints SET envelope=?,payload_hash=? WHERE thread_id=?",
                vec![envelope.into(), hash.into(), thread_id.into()],
            ))
            .await?;
        }
    }
    Ok(())
}

async fn backfill_attempt_identity(tx: &impl ConnectionTrait) -> Result<(), SessionStoreError> {
    let mut after = String::new();
    loop {
        let rows = tx
            .query_all_raw(sqlite::statement(
                "SELECT * FROM thread_checkpoints WHERE thread_id>? ORDER BY thread_id LIMIT 128",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let thread_id: String = row.try_get("", "thread_id")?;
            after.clone_from(&thread_id);
            let stored_schema: i64 = row.try_get("", "schema_version")?;
            let envelope: String = row.try_get("", "envelope")?;
            let hash: String = row.try_get("", "payload_hash")?;
            if crate::context::content_hash(envelope.as_bytes()) != hash {
                return Err(SessionStoreError::Invalid(format!(
                    "Thread {thread_id} checkpoint integrity check failed"
                )));
            }
            let mut header: serde_json::Value = serde_json::from_str(&envelope)?;
            if header
                .get("schemaVersion")
                .and_then(serde_json::Value::as_i64)
                != Some(stored_schema)
            {
                return Err(SessionStoreError::Invalid(
                    "checkpoint schema index/envelope mismatch".into(),
                ));
            }
            let checkpoint: UsageBackfillEnvelope = serde_json::from_value(header.clone())?;
            let mut attempts = header["state"]
                .get("attemptIds")
                .cloned()
                .unwrap_or_else(|| serde_json::json!({}));
            let mut calls = header["state"]
                .get("liveCalls")
                .cloned()
                .unwrap_or_else(|| serde_json::json!({}));
            if !attempts.is_object() || !calls.is_object() {
                return Err(SessionStoreError::Invalid(
                    "invalid saved identity maps".into(),
                ));
            }
            if checkpoint.thread_id != thread_id {
                return Err(SessionStoreError::Invalid(
                    "Thread checkpoint ownership mismatch".into(),
                ));
            }
            if checkpoint.state_revision
                != u64::try_from(row.try_get::<i64>("", "state_revision")?)
                    .map_err(|_| SessionStoreError::Invalid("negative revision".into()))?
                || checkpoint.history_fence
                    != u64::try_from(row.try_get::<i64>("", "history_fence")?)
                        .map_err(|_| SessionStoreError::Invalid("negative fence".into()))?
                || checkpoint.state_revision != checkpoint.state.commit_sequence
                || checkpoint.history_fence > checkpoint.state_revision
                || !checkpoint.external_bodies.is_empty()
            {
                return Err(SessionStoreError::Invalid(
                    "checkpoint index/envelope fence mismatch".into(),
                ));
            }
            // Compaction may have removed every old call from the current context. Rebuild
            // identities from the reliable history, without retaining its request/result bodies.
            let mut expected = 1;
            let upper = format!("pl.resource.thread-commit.{:020}", checkpoint.history_fence);
            while expected <= checkpoint.history_fence {
                let lower = format!("pl.resource.thread-commit.{expected:020}");
                let effects = tx.query_all_raw(sqlite::statement(
                    "SELECT * FROM session_entries WHERE session_id=? AND id>=? AND id<=? ORDER BY id LIMIT 256",
                    vec![thread_id.clone().into(), lower.into(), upper.clone().into()],
                )).await?;
                if effects.is_empty() {
                    return Err(SessionStoreError::Invalid(format!(
                        "Thread {thread_id} identity history has a sequence gap at {expected}"
                    )));
                }
                for row in effects {
                    let effect = super::effect_migration::decode_effect(row, &thread_id)?;
                    if effect.sequence != expected {
                        return Err(SessionStoreError::Invalid(format!(
                            "Thread {thread_id} identity history has a sequence gap at {expected}"
                        )));
                    }
                    if let Some(attempt) = &effect.attempt {
                        attempts[&attempt.attempt_id] = attempt.turn_id.clone().into();
                        if let crate::thread::AttemptOutcome::Committed(output) = &attempt.outcome {
                            for call in output.tool_calls.iter() {
                                calls[&call.call_id] = attempt.turn_id.clone().into();
                            }
                        }
                    }
                    expected += 1;
                }
            }
            header["state"]["attemptIds"] = attempts;
            header["state"]["liveCalls"] = calls;
            let encoded = serde_json::to_string(&header)?;
            let encoded_hash = crate::context::content_hash(encoded.as_bytes());
            tx.execute_raw(sqlite::statement(
                "UPDATE thread_checkpoints SET envelope=?,payload_hash=? WHERE thread_id=?",
                vec![encoded.into(), encoded_hash.into(), thread_id.into()],
            ))
            .await?;
        }
    }
    Ok(())
}
