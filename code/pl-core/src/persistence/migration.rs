//! Explicit offline migrations, ordered and committed by SeaORM.
use super::{SessionStoreError, SqliteSessionOptions, history, sqlite, thread_history};
use crate::{
    context::OpaquePayload,
    storage::{SessionEntry, SessionEntryChange},
    thread::ThreadEffectBatch,
};
use sea_orm::{ConnectionTrait, Database, DatabaseConnection, DbErr, TransactionTrait};
use sea_orm_migration::{MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};
use std::sync::Arc;

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
    usage_summary: crate::thread::UsageSummary,
}

/// Upgrades an existing database while holding its exclusive maintenance lease.
/// Each official migration commits independently; failures preserve source data for retry.
/// The callback is owned by the migration and must have no external side effects.
/// # Errors
/// Rejects missing or active databases, unsupported formats, invalid facts and storage failures.
pub async fn migrate_to_current(
    options: SqliteSessionOptions,
    transform: impl Fn(&mut ThreadEffectBatch) -> Result<(), SessionStoreError> + Send + Sync + 'static,
) -> Result<(), SessionStoreError> {
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
        let migrator = Migrator {
            transform: Arc::new(transform),
        };
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
    let migrator = Migrator {
        transform: Arc::new(|_: &mut ThreadEffectBatch| Ok(())),
    };
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
    allow_legacy: bool,
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
    let result = preflight(&db, allow_legacy).await;
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
async fn preflight(db: &DatabaseConnection, allow_legacy: bool) -> Result<(), SessionStoreError> {
    let found = version(db).await?;
    if found == 0 {
        if allow_legacy || db.query_one_raw(sqlite::statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_some() {
            return Err(SessionStoreError::UnsupportedSchema { found, supported: super::SESSION_SCHEMA_VERSION });
        }
    } else if !(6..=super::SESSION_SCHEMA_VERSION).contains(&found)
        || (!allow_legacy && found != super::SESSION_SCHEMA_VERSION)
    {
        return Err(SessionStoreError::UnsupportedSchema {
            found,
            supported: super::SESSION_SCHEMA_VERSION,
        });
    }
    validate_existing_tables(db, found).await?;
    if SchemaManager::new(db).has_table("thread_checkpoints").await?
        && db.query_one_raw(sqlite::statement(
            "SELECT 1 FROM thread_checkpoints WHERE schema_version NOT BETWEEN 1 AND 5 OR json_extract(envelope,'$.schemaVersion') NOT BETWEEN 1 AND 5 LIMIT 1", vec![]
        )).await?.is_some()
    {
        return Err(SessionStoreError::Invalid("unsupported checkpoint schema; existing data preserved".into()));
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
    if !allow_legacy
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
    let migrator = Migrator {
        transform: Arc::new(|_: &mut ThreadEffectBatch| Ok(())),
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    if found != 0 && (allow_legacy || !pending.is_empty()) {
        // Fully adopted ordinary opens retain their existing lazy read-validation boundary. Any
        // adoption or actual migration must verify the complete source before `up` can write a ledger.
        let tx = db.begin().await?;
        super::migration_source::validate(&tx, found).await?;
        tx.commit().await?;
    }
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

/// Checks the minimum source shape before SeaORM creates any migration bookkeeping.
///
/// Legacy versions only describe the source we are taking over, not a second migration schedule.
/// The fixed column lists make SQLite validate names without reading or decoding stored bodies.
async fn validate_existing_tables(
    db: &DatabaseConnection,
    found: i64,
) -> Result<(), SessionStoreError> {
    let manager = SchemaManager::new(db);
    for (introduced, table, columns) in [
        (
            6,
            "session_entries",
            "session_id,id,type_id,ordinal,turn_id,envelope,payload_hash",
        ),
        (
            6,
            "session_entry_history",
            "session_id,sequence,envelope,payload_hash",
        ),
        (
            6,
            "session_history_heads",
            "session_id,sequence,payload_hash",
        ),
        (
            8,
            "thread_checkpoints",
            "thread_id,schema_version,state_revision,history_fence,envelope,payload_hash",
        ),
        (
            12,
            "thread_tool_tasks",
            "thread_id,task_id,call_id,task_envelope,task_hash,delivery_sequence,delivery_position",
        ),
        (
            12,
            "thread_tool_task_resources",
            "thread_id,call_id,reference_hash,reference_envelope",
        ),
    ] {
        if found < introduced {
            continue;
        }
        if !manager.has_table(table).await? {
            return Err(SessionStoreError::Invalid(format!(
                "session format {found} table {table} is missing; existing data preserved"
            )));
        }
        db.query_all_raw(sqlite::statement(
            &format!("SELECT {columns} FROM {table} LIMIT 0"),
            vec![],
        ))
        .await?;
    }
    Ok(())
}

struct Migrator<F> {
    transform: Arc<F>,
}
impl<F> MigratorTraitSelf for Migrator<F>
where
    F: Fn(&mut ThreadEffectBatch) -> Result<(), SessionStoreError> + Send + Sync + 'static,
{
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(InitialSchema),
            Box::new(CurrentEntries {
                transform: self.transform.clone(),
            }),
            Box::new(CheckpointTable),
            Box::new(UsageSummary),
            Box::new(AttemptIdentity),
            Box::new(TaskIndex),
            Box::new(CheckpointV5),
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

struct CurrentEntries<F> {
    transform: Arc<F>,
}
impl<F> MigrationName for CurrentEntries<F> {
    fn name(&self) -> &str {
        "m20261026_000002_core_entries_v7"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl<F> MigrationTrait for CurrentEntries<F>
where
    F: Fn(&mut ThreadEffectBatch) -> Result<(), SessionStoreError> + Send + Sync + 'static,
{
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await.map_err(conversion)? < 7 {
            convert_entries(db, self.transform.as_ref())
                .await
                .map_err(conversion)?;
            db.execute_unprepared("PRAGMA user_version=7").await?;
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

async fn convert_entries(
    tx: &impl ConnectionTrait,
    transform: &impl Fn(&mut ThreadEffectBatch) -> Result<(), SessionStoreError>,
) -> Result<(), SessionStoreError> {
    let sessions = tx.query_all_raw(sqlite::statement("SELECT session_id FROM session_history_heads UNION SELECT session_id FROM session_entries UNION SELECT session_id FROM session_entry_history", vec![])).await?;
    for row in sessions {
        let id: String = row.try_get("", "session_id")?;
        let mut history = history::read(tx, &id, None).await?;
        let mut current = sqlite::entries(tx, &id, None).await?;
        let sort = |entries: &mut Vec<SessionEntry>| entries.sort_by(|a, b| a.id.cmp(&b.id));
        sort(&mut current);
        let mut replay = crate::storage::replay_entries(&history)?;
        sort(&mut replay);
        if replay != current {
            return Err(SessionStoreError::Invalid(
                "history and current entries disagree".into(),
            ));
        }
        for batch in &mut history {
            for change in &mut batch.changes {
                if let SessionEntryChange::Put { entry } = change {
                    convert(entry, transform)?;
                }
            }
            let encoded = serde_json::to_string(batch)?;
            let hash = crate::context::content_hash(encoded.as_bytes());
            tx.execute_raw(sqlite::statement("UPDATE session_entry_history SET envelope=?,payload_hash=? WHERE session_id=? AND sequence=?", vec![encoded.into(), hash.clone().into(), id.clone().into(), (batch.sequence as i64).into()])).await?;
            tx.execute_raw(sqlite::statement(
                "UPDATE session_history_heads SET payload_hash=? WHERE session_id=? AND sequence=?",
                vec![
                    hash.into(),
                    id.clone().into(),
                    (batch.sequence as i64).into(),
                ],
            ))
            .await?;
        }
        for entry in &mut current {
            convert(entry, transform)?;
            let encoded = serde_json::to_string(entry)?;
            let hash = crate::context::content_hash(encoded.as_bytes());
            tx.execute_raw(sqlite::statement(
                "UPDATE session_entries SET envelope=?,payload_hash=? WHERE session_id=? AND id=?",
                vec![
                    encoded.into(),
                    hash.into(),
                    id.clone().into(),
                    entry.id.clone().into(),
                ],
            ))
            .await?;
        }
        let mut replay = crate::storage::replay_entries(&history)?;
        sort(&mut replay);
        if replay != current {
            return Err(SessionStoreError::Invalid(
                "migration changed current/history equivalence".into(),
            ));
        }
        let mut commits = Vec::new();
        for entry in &current {
            if entry.id.starts_with("pl.resource.thread-commit.") {
                let payload = OpaquePayload::new(
                    entry.type_id.clone(),
                    entry.schema_version,
                    entry.payload.clone(),
                )
                .map_err(|e| SessionStoreError::Invalid(e.to_string()))?;
                let commit = ThreadEffectBatch::decode(&payload)
                    .map_err(|e| SessionStoreError::Invalid(e.to_string()))?;
                if commit.thread_id != id
                    || entry.id != format!("pl.resource.thread-commit.{:020}", commit.sequence)
                {
                    return Err(SessionStoreError::Invalid(
                        "commit ownership mismatch".into(),
                    ));
                }
                commits.push(Arc::new(commit));
            }
        }
        crate::thread::journal::legacy_migration::replay(&commits)
            .map_err(|e| SessionStoreError::Invalid(e.to_string()))?;
    }
    Ok(())
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
            let mut summary = header.state.usage_summary;
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
                    let effect = thread_history::decode_effect(effect_row, &thread_id)?;
                    if effect.sequence != expected {
                        return Err(SessionStoreError::Invalid(format!(
                            "Thread {thread_id} usage history has a sequence gap at {expected}"
                        )));
                    }
                    crate::thread::usage::fold_effect(&mut summary, &effect);
                    expected += 1;
                }
            }
            value["state"]["usageSummary"] = serde_json::to_value(&summary)?;
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
                    let effect = thread_history::decode_effect(row, &thread_id)?;
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

pub(super) fn convert(
    entry: &mut SessionEntry,
    transform: &impl Fn(&mut ThreadEffectBatch) -> Result<(), SessionStoreError>,
) -> Result<(), SessionStoreError> {
    if entry.type_id != "pl.core.thread-commit" {
        return Ok(());
    }
    if entry.schema_version != 2 {
        return Err(SessionStoreError::Invalid(
            "unsupported migration commit version".into(),
        ));
    }
    let mut value: serde_json::Value = serde_json::from_str(&entry.payload)?;
    if let Some(state) = value.get_mut("turn").and_then(|turn| turn.get_mut("state"))
        && state.get("kind").and_then(|v| v.as_str()) == Some("finished")
        && state.get("value").and_then(|v| v.as_str()) == Some("toolCompleted")
    {
        state["value"] = "completed".into();
    }
    let mut commit: ThreadEffectBatch = serde_json::from_value(value)?;
    transform(&mut commit)?;
    entry.schema_version = 3;
    entry.payload = serde_json::to_string(&commit)?;
    Ok(())
}
