//! One-shot legacy history upgrade to schema 25.
//!
//! This module is intentionally outside normal history reads and writes. It pins one writer,
//! first publishes a self-contained current file and a logical backup, and only then lets the
//! SeaORM migration transaction transform the database in one Immediate transaction.

mod input;
pub(super) mod schema26_manifest;
mod v25_schema;
mod v25_to_v26;

pub(in crate::history) use v25_schema::{
    HistoryEntityHeadV25, HistoryEventKindV25, HistoryEventV25, HistoryRowHeadV25,
    insert_v25_event, validate_v25_event,
};
pub(super) use v25_to_v26::migrate_v25_to_v26;

use super::{
    BODY_CHUNK_BYTES, HEAD_MAX_BYTES, HistoryBody, HistoryBodyRole, HistoryError,
    HistoryEventBodyRef, HistorySingleVisibility, HistorySource, HistoryTurnState, HistoryWaitHead,
    HistoryWaitIntentHead, Result,
    db::{self, statement},
    import::{
        HistoryBodySource, HistoryImport, HistoryImportBody, V24Body, V24BodyReader,
        V24HistorySource,
    },
    schema,
};
use crate::studio::storage::history::schema::{
    initialize as prepare_schema24,
    v24_presentation::{DisplayHeader, DisplayMemberWrite},
    v24_presentation_types as v24_display,
};
use crate::{
    ChatAtom, ChatAtomLifecycle, ChatSourceLifecycle, ContentOwner, ContentRef, ContentTarget,
    PayloadData, Turn,
};
use input::{INPUT_FACT_BODY_KEY, InputAdmission, InputFact, input_event};
use pl_core::{
    context::OpaquePayload,
    thread::current::{RuntimeEpoch, ThreadCurrent, ThreadCurrentState},
};
use sea_orm::{ConnectionTrait, DatabaseConnection};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
#[cfg(test)]
use std::sync::Mutex;
use std::{
    collections::BTreeMap,
    fs::File,
    io::Write,
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};
use v25_schema::{
    HistoryEntityHeadV25 as HistoryEntityHead, HistoryEventKindV25 as HistoryEventKind,
    HistoryEventV25 as HistoryEvent, HistoryObservationV25 as HistoryObservation,
    HistoryRowHeadV25 as HistoryRowHead, HistoryWorkHeadV25 as HistoryWorkHead,
};

mod payload;
use payload::{
    StagedPayload, copy_planned_bodies, create_staging as create_payload_staging,
    drop_staging as drop_payload_staging, plan_content_reference,
    reference_plan as payload_reference, render_rewritten_atom,
};

const LEGACY_EVENT_PREFIX: &str = "legacy:v24:";
const LEGACY_BODY_PREFIX: &str = "legacy:v24:body:";
const BACKUP_ROOT: &str = "migration-backups/history-24-to-25";
const BACKUP_ROOT_V25_TO_V26: &str = "migration-backups/history-25-to-26";
const PENDING_REPORT_FILE: &str = "pending-upgrade-report.json";
#[cfg(test)]
static FAIL_NEXT_IMPORT_THREAD: Mutex<Option<String>> = Mutex::new(None);
#[cfg(test)]
static FAIL_NEXT_BACKUP_PUBLISH_THREAD: Mutex<Option<String>> = Mutex::new(None);
#[cfg(test)]
static FAIL_NEXT_CURRENT_PUBLISH: Mutex<Option<(String, bool)>> = Mutex::new(None);
#[cfg(test)]
static FAIL_NEXT_DDL_THREAD: Mutex<Option<String>> = Mutex::new(None);
#[cfg(test)]
static FAIL_NEXT_REPORT_THREAD: Mutex<Option<String>> = Mutex::new(None);

const LEGACY_SOURCE_TABLES: &[&str] = &[
    "history_meta",
    "timeline_records",
    "conversation_items",
    "conversation_contents",
    "conversation_content_chunks",
    "execution_lifecycle",
    "history_turns",
    "conversation_sources",
    "conversation_display_blocks",
    "conversation_display_members",
    "history_tool_tasks",
    "history_input_identities",
    "history_message_identities",
    "history_fact_receipts",
    "session_costs",
    "session_checkpoint",
    "current_context",
    "completion_boundary_archive_view_state",
    "completion_boundary_archive_view_entries",
    "completion_boundary_archive_timeline_items",
    "completion_boundary_archive_timeline_members",
    "completion_boundary_archive_projection_state",
    "completion_boundary_archive_contents",
    "completion_boundary_archive_content_chunks",
];

// The legacy WorkSnapshots migration created these archives only when it upgraded
// an existing display. Its canonical output is in the conversation_display_* tables.
const LEGACY_WORK_SNAPSHOT_ARCHIVES: &[&str] = &[
    "work_snapshot_migration_headers",
    "work_snapshot_migration_members",
];

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpgradeReport {
    pub operation_id: String,
    pub thread_id: String,
    pub database_id: String,
    pub status: UpgradeStatus,
    pub backup: Option<PathBuf>,
    pub current_original_backup: Option<PathBuf>,
    pub source_table_rows: BTreeMap<String, u64>,
    pub imported_categories: BTreeMap<String, u64>,
    pub backup_only_categories: BTreeMap<String, u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UpgradeStatus {
    Upgraded,
    AlreadySchema26,
}

#[derive(Debug, PartialEq, Eq)]
enum SourceFormat {
    Legacy(i64),
    Schema25,
    Schema26,
}

#[derive(PartialEq, Eq)]
struct LegacyIdentity {
    version: i64,
    database_id: String,
    thread_id: String,
    watermark: u64,
}

#[derive(Debug, Clone, Default)]
pub(super) struct ImportCounts {
    imported: BTreeMap<String, u64>,
    backup_only: BTreeMap<String, u64>,
}

impl ImportCounts {
    fn imported(&mut self, category: &str, amount: u64) {
        *self.imported.entry(category.to_owned()).or_default() += amount;
    }

    fn backup_only(&mut self, category: &str, amount: u64) {
        *self.backup_only.entry(category.to_owned()).or_default() += amount;
    }
}

struct WriterLease {
    _file: File,
}

/// The caller holds its maintenance admission gate while deciding whether
/// existing writers must retire. Reading an already current store never does.
pub(crate) async fn requires_history_upgrade(path: &Path, thread_id: &str) -> Result<bool> {
    let read = schema::connect(path, true, false).await?;
    let required = match classify_source(&read).await? {
        SourceFormat::Legacy(24) => {
            legacy_identity(&read, thread_id).await?;
            true
        }
        SourceFormat::Legacy(_) => {
            crate::studio::storage::history::validate_layout_source(&read, thread_id).await?;
            true
        }
        SourceFormat::Schema25 => {
            schema25_identity(&read, thread_id).await?;
            true
        }
        SourceFormat::Schema26 => {
            schema::identity(&read, thread_id).await?;
            schema26_manifest::repair_needed(&read).await?
        }
    };
    read.close().await?;
    Ok(required)
}

pub async fn upgrade_history(
    history_path: impl AsRef<Path>,
    thread_id: &str,
    session_dir: impl AsRef<Path>,
) -> Result<UpgradeReport> {
    let history_path = history_path.as_ref().to_path_buf();
    let session_dir = session_dir.as_ref().to_path_buf();
    if thread_id.is_empty() {
        return Err(HistoryError::InvalidEvent(
            "Thread identity is empty".into(),
        ));
    }
    if !preserved_file_exists(&history_path)? {
        return Err(HistoryError::NotFound(history_path.display().to_string()));
    }
    let pending_v24 = session_dir.join(BACKUP_ROOT).join(PENDING_REPORT_FILE);
    let pending_v25 = session_dir
        .join(BACKUP_ROOT_V25_TO_V26)
        .join(PENDING_REPORT_FILE);
    let read = schema::connect(&history_path, true, false).await?;
    if classify_source(&read).await? == SourceFormat::Schema26
        && !pending_v24.try_exists()?
        && !pending_v25.try_exists()?
    {
        let (database_id, _) = schema::identity(&read, thread_id).await?;
        return finish_schema26(
            &history_path,
            read,
            &pending_v24,
            thread_id,
            database_id,
            "history.v24.sqlite",
            false,
        )
        .await;
    }
    read.close().await?;
    let _lease = acquire_writer_lease(&history_path).await?;
    let read = schema::connect(&history_path, true, false).await?;
    let format = classify_source(&read).await?;
    match format {
        SourceFormat::Schema26 => {
            let (database_id, _) = schema::identity(&read, thread_id).await?;
            if pending_v25.try_exists()? {
                if pending_v24.try_exists()? {
                    read.close().await?;
                    return Err(HistoryError::Conflict(
                        "conflicting v24 and v25 pending upgrade reports exist".into(),
                    ));
                }
                return finish_schema26(
                    &history_path,
                    read,
                    &pending_v25,
                    thread_id,
                    database_id,
                    "history.v25.sqlite",
                    true,
                )
                .await;
            }
            return finish_schema26(
                &history_path,
                read,
                &pending_v24,
                thread_id,
                database_id,
                "history.v24.sqlite",
                true,
            )
            .await;
        }
        SourceFormat::Schema25 => {
            let database_id = schema25_identity(&read, thread_id).await?;
            read.close().await?;
            if pending_v24.try_exists()? {
                return Err(HistoryError::Conflict(
                    "schema 25 history has a pending schema 24 report".into(),
                ));
            }
            return upgrade_v25_to_v26(
                &history_path,
                thread_id,
                &session_dir,
                &database_id,
                &pending_v25,
            )
            .await;
        }
        SourceFormat::Legacy(_) => {}
    }
    if pending_v25.try_exists()? {
        return Err(HistoryError::Conflict(
            "pre-schema 25 history has a pending schema 25 -> 26 report".into(),
        ));
    }
    crate::studio::storage::history::validate_layout_source(&read, thread_id).await?;
    let original_identity = read_legacy_identity(&read).await?;
    read.close().await?;

    let operation_id = uuid::Uuid::new_v4().to_string();
    let operation_dir = session_dir.join(BACKUP_ROOT).join(&operation_id);
    let identity = if original_identity.version == 24 {
        let identity = original_identity.into_schema24(thread_id)?;
        discard_rolled_back_pending_report(&pending_v24, thread_id, &identity.0)?;
        prepare_directory(&session_dir, &operation_dir)?;
        identity
    } else {
        if pending_v24.try_exists()? {
            return Err(HistoryError::Conflict(
                "pre-schema 24 history has a pending schema 25 report".into(),
            ));
        }
        prepare_directory(&session_dir, &operation_dir)?;
        prepare_older_history(&history_path, &operation_dir, thread_id, original_identity).await?
    };
    let (backup_path, backup_counts) = make_backup(
        &history_path,
        &operation_dir,
        thread_id,
        &identity.0,
        identity.1,
    )
    .await?;

    let source = V24HistorySource::open(&history_path, thread_id).await?;
    let counts = source_table_rows(&source).await?;
    if counts != backup_counts {
        source.close().await?;
        return Err(HistoryError::Integrity(
            "schema 24 source changed while its logical backup was prepared".into(),
        ));
    }
    let current_backup = prepare_current(&source, thread_id, &session_dir, &operation_dir).await?;

    let writer = schema::connect_for_migration(&history_path).await?;
    crate::studio::storage::history::validate_layout_source(&writer, thread_id).await?;
    let database_id = identity.0.clone();
    let report_thread_id = thread_id.to_owned();
    let stage_path = pending_v24.clone();
    let stage_report: schema::StageUpgradeReport = Box::new(move |imported| {
        let mut backup_only_categories = imported.backup_only;
        let archived_rows = LEGACY_SOURCE_TABLES
            .iter()
            .filter(|table| table.starts_with("completion_boundary_archive_"))
            .try_fold(0u64, |total, table| {
                let rows = counts.get(*table).copied().ok_or_else(|| {
                    HistoryError::Integrity(format!("source row count for {table} is missing"))
                })?;
                total
                    .checked_add(rows)
                    .ok_or_else(|| HistoryError::Integrity("archive row count overflow".into()))
            })?;
        backup_only_categories.insert("completion_boundary_archive_*".into(), archived_rows);
        for &table in LEGACY_WORK_SNAPSHOT_ARCHIVES {
            if let Some(&rows) = counts.get(table) {
                backup_only_categories.insert(table.into(), rows);
            }
        }
        let report = UpgradeReport {
            operation_id,
            thread_id: report_thread_id,
            database_id,
            status: UpgradeStatus::Upgraded,
            backup: Some(backup_path),
            current_original_backup: current_backup,
            source_table_rows: counts,
            imported_categories: imported.imported,
            backup_only_categories,
        };
        stage_pending_report(&stage_path, &report)
    });
    match schema::run_upgrade_v24(
        &writer,
        thread_id,
        &identity.0,
        identity.1,
        source.clone(),
        stage_report,
    )
    .await
    {
        Ok(()) => {}
        Err(error) => {
            return Err(error);
        }
    }
    let (database_id, _) = schema::identity(&writer, thread_id).await?;
    writer.close().await?;
    source.close().await?;
    complete_pending_report(&pending_v24, thread_id, &database_id, "history.v24.sqlite")
}

async fn upgrade_v25_to_v26(
    history_path: &Path,
    thread_id: &str,
    session_dir: &Path,
    database_id: &str,
    pending_report: &Path,
) -> Result<UpgradeReport> {
    if pending_report.try_exists()? {
        let bytes = std::fs::read(pending_report)?;
        let report: UpgradeReport = serde_json::from_slice(&bytes)?;
        if report.thread_id != thread_id || report.database_id != database_id {
            return Err(HistoryError::Conflict(
                "rolled-back schema 25 -> 26 report does not match this history".into(),
            ));
        }
        let op_dir = report_operation_dir(pending_report, &report)?;
        let uncommitted = op_dir.join("uncommitted-report.json");
        if !uncommitted.try_exists()? {
            backup_exact_bytes(&uncommitted, &bytes)?;
        }
        std::fs::remove_file(pending_report)?;
        sync_parent(pending_report)?;
    }

    let operation_id = uuid::Uuid::new_v4().to_string();
    let operation_dir = session_dir.join(BACKUP_ROOT_V25_TO_V26).join(&operation_id);
    prepare_directory(session_dir, &operation_dir)?;

    let temporary = vacuum_backup_candidate(history_path, &operation_dir, 25).await?;
    let backup_read = schema::connect(&temporary, true, false).await?;
    if schema25_identity(&backup_read, thread_id).await? != database_id {
        return Err(HistoryError::Integrity(
            "schema 25 backup identity differs".into(),
        ));
    }
    quick_check(&backup_read).await?;
    let source_table_rows = v25_table_rows(&backup_read).await?;
    backup_read.close().await?;
    let backup_path = operation_dir.join("history.v25.sqlite");
    publish_backup(&temporary, &backup_path, thread_id)?;

    let writer = schema::connect_for_migration(history_path).await?;
    let report_thread_id = thread_id.to_owned();
    let report_db_id = database_id.to_owned();
    let stage_path = pending_report.to_path_buf();
    let stage_v25_report: Box<dyn FnOnce(u64) -> Result<()> + Send> = Box::new(move |migrated| {
        let mut imported_categories = BTreeMap::new();
        imported_categories.insert("history_events_v26".into(), migrated);
        let report = UpgradeReport {
            operation_id,
            thread_id: report_thread_id,
            database_id: report_db_id,
            status: UpgradeStatus::Upgraded,
            backup: Some(backup_path),
            current_original_backup: None,
            source_table_rows,
            imported_categories,
            backup_only_categories: BTreeMap::new(),
        };
        stage_pending_report(&stage_path, &report)
    });
    schema::run_upgrade_v25(&writer, thread_id, stage_v25_report).await?;
    let (confirmed_db_id, _) = schema::identity(&writer, thread_id).await?;
    writer.close().await?;
    complete_pending_report(
        pending_report,
        thread_id,
        &confirmed_db_id,
        "history.v25.sqlite",
    )
}

async fn schema25_identity(db: &DatabaseConnection, thread_id: &str) -> Result<String> {
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("schema 25 identity missing".into()))?;
    if row.try_get::<i64>("", "schema_version")? != 25
        || row.try_get::<String>("", "thread_id")? != thread_id
    {
        return Err(HistoryError::Integrity(
            "schema 25 database or Thread identity differs".into(),
        ));
    }
    let database_id: String = row.try_get("", "database_id")?;
    if database_id.is_empty() {
        return Err(HistoryError::Integrity(
            "schema 25 database_id is empty".into(),
        ));
    }
    Ok(database_id)
}

async fn v25_table_rows(db: &DatabaseConnection) -> Result<BTreeMap<String, u64>> {
    let mut counts = BTreeMap::new();
    for table in ["history_events", "history_bodies", "history_body_chunks"] {
        let row = db
            .query_one_raw(statement(
                &format!("SELECT COUNT(*) AS c FROM {table}"),
                vec![],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity(format!("failed counting {table}")))?;
        counts.insert(table.into(), db_u64(row.try_get::<i64>("", "c")?, table)?);
    }
    Ok(counts)
}

async fn acquire_writer_lease(history_path: &Path) -> Result<WriterLease> {
    // HistoryStore and this one-shot upgrade must contend on the same physical path. The caller
    // still owns the Thread maintenance/ownership gate and must stop the old writer before this
    // entry is invoked; this lease only prevents a second process from entering either path.
    let lock_path = writer_lock_path(history_path);
    let file = File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(&lock_path)?;
    fs4::FileExt::try_lock(&file)
        .map_err(|error| HistoryError::Conflict(format!("history writer lease: {error}")))?;
    Ok(WriterLease { _file: file })
}

fn writer_lock_path(history_path: &Path) -> PathBuf {
    let mut lock_path = history_path.as_os_str().to_os_string();
    lock_path.push(".writer.lock");
    PathBuf::from(lock_path)
}

async fn classify_source(db: &DatabaseConnection) -> Result<SourceFormat> {
    let old = table_exists(db, "history_meta").await?;
    let new = table_exists(db, "history_store_meta").await?;
    match (old, new) {
        (true, false) => {
            let row = db
                .query_one_raw(statement(
                    "SELECT schema_version FROM history_meta WHERE id=1",
                    vec![],
                ))
                .await?
                .ok_or_else(|| {
                    HistoryError::Integrity("legacy history identity is missing".into())
                })?;
            Ok(SourceFormat::Legacy(row.try_get_by_index(0)?))
        }
        (false, true) => {
            let row = db
                .query_one_raw(statement(
                    "SELECT schema_version FROM history_store_meta WHERE singleton=1",
                    vec![],
                ))
                .await?
                .ok_or_else(|| {
                    HistoryError::Integrity("history_store_meta identity is missing".into())
                })?;
            match row.try_get_by_index::<i64>(0)? {
                25 => Ok(SourceFormat::Schema25),
                26 => Ok(SourceFormat::Schema26),
                other => Err(HistoryError::Integrity(format!(
                    "unsupported history schema version {other}"
                ))),
            }
        }
        (true, true) => Err(HistoryError::Integrity(
            "database contains both legacy and current identity tables".into(),
        )),
        (false, false) => Err(HistoryError::Integrity(
            "database has no recognizable history identity table".into(),
        )),
    }
}

async fn table_exists(db: &DatabaseConnection, table: &str) -> Result<bool> {
    Ok(db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
            vec![table.into()],
        ))
        .await?
        .is_some())
}

fn db_u64(value: i64, field: &str) -> Result<u64> {
    u64::try_from(value)
        .map_err(|_| HistoryError::Integrity(format!("negative database integer for {field}")))
}

async fn legacy_identity(db: &DatabaseConnection, thread_id: &str) -> Result<(String, u64)> {
    read_legacy_identity(db).await?.into_schema24(thread_id)
}

async fn read_legacy_identity(db: &DatabaseConnection) -> Result<LegacyIdentity> {
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,database_id,applied_write_seq,thread_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("legacy history identity is missing".into()))?;
    Ok(LegacyIdentity {
        version: row.try_get("", "schema_version")?,
        database_id: row.try_get("", "database_id")?,
        thread_id: row.try_get("", "thread_id")?,
        watermark: db_u64(
            row.try_get::<i64>("", "applied_write_seq")?,
            "history_meta.applied_write_seq",
        )?,
    })
}

impl LegacyIdentity {
    fn into_schema24(self, thread_id: &str) -> Result<(String, u64)> {
        if self.version != 24 || self.database_id.is_empty() || self.thread_id != thread_id {
            return Err(HistoryError::Integrity(
                "schema 24 database identity differs".into(),
            ));
        }
        Ok((self.database_id, self.watermark))
    }
}

fn prepare_directory(anchor: &Path, target: &Path) -> Result<()> {
    if !target.starts_with(anchor) {
        return Err(HistoryError::Integrity(
            "upgrade directory escapes its session".into(),
        ));
    }
    std::fs::create_dir_all(target)?;
    #[cfg(unix)]
    {
        let mut current = target;
        loop {
            let handle = File::open(current)?;
            handle.sync_all()?;
            if current == anchor {
                break;
            }
            current = current.parent().ok_or_else(|| {
                HistoryError::Integrity("upgrade directory has no session parent".into())
            })?;
        }
    }
    Ok(())
}

async fn make_backup(
    history_path: &Path,
    operation_dir: &Path,
    thread_id: &str,
    database_id: &str,
    watermark: u64,
) -> Result<(PathBuf, BTreeMap<String, u64>)> {
    let temporary = vacuum_backup_candidate(history_path, operation_dir, 24).await?;
    let backup_read = schema::connect(&temporary, true, false).await?;
    crate::studio::storage::history::validate_layout_source(&backup_read, thread_id).await?;
    if legacy_identity(&backup_read, thread_id).await? != (database_id.to_owned(), watermark) {
        return Err(HistoryError::Integrity(
            "schema 24 backup identity or watermark differs".into(),
        ));
    }
    quick_check(&backup_read).await?;
    let counts = database_table_rows(&backup_read).await?;
    backup_read.close().await?;
    let target = operation_dir.join("history.v24.sqlite");
    publish_backup(&temporary, &target, thread_id)?;
    Ok((target, counts))
}

async fn prepare_older_history(
    history_path: &Path,
    operation_dir: &Path,
    thread_id: &str,
    original: LegacyIdentity,
) -> Result<(String, u64)> {
    let version = original.version;
    let temporary = vacuum_backup_candidate(history_path, operation_dir, version).await?;
    let backup = schema::connect(&temporary, true, false).await?;
    crate::studio::storage::history::validate_layout_source(&backup, thread_id).await?;
    if read_legacy_identity(&backup).await? != original {
        return Err(HistoryError::Integrity(
            "pre-schema 24 backup identity or watermark differs".into(),
        ));
    }
    quick_check(&backup).await?;
    backup.close().await?;
    let target = operation_dir.join(format!("history.v{version}.sqlite"));
    publish_backup(&temporary, &target, thread_id)?;

    // The outer upgrade holds the same writer lease across both format changes.
    let writer = schema::connect(history_path, false, false).await?;
    prepare_schema24(&writer, thread_id).await?;
    let schema24 = legacy_identity(&writer, thread_id).await?;
    writer.close().await?;
    if !original.database_id.is_empty() && schema24.0 != original.database_id {
        return Err(HistoryError::Integrity(
            "preparation changed the legacy database identity".into(),
        ));
    }
    Ok(schema24)
}

async fn vacuum_backup_candidate(
    history_path: &Path,
    operation_dir: &Path,
    version: i64,
) -> Result<PathBuf> {
    let db = schema::connect(history_path, false, false).await?;
    db.execute_raw(statement("PRAGMA synchronous=FULL", Vec::new()))
        .await?;
    // Match sqlite_file_options: keep the native canonical prefix for deep Windows
    // session paths, including when SQLite opens the VACUUM target itself.
    let temporary = std::fs::canonicalize(operation_dir)?.join(format!(
        ".history-v{version}-{}.sqlite",
        uuid::Uuid::new_v4().simple()
    ));
    let temporary_sql = temporary
        .to_str()
        .ok_or_else(|| HistoryError::Storage(anyhow::anyhow!("backup path is not valid UTF-8")))?;
    db.execute_raw(statement(
        "VACUUM INTO ?",
        vec![temporary_sql.to_owned().into()],
    ))
    .await?;
    db.close().await?;
    Ok(temporary)
}

fn publish_backup(temporary: &Path, target: &Path, thread_id: &str) -> Result<()> {
    // Windows FlushFileBuffers requires a writable handle; opening does not truncate.
    File::options().write(true).open(temporary)?.sync_all()?;
    fail_backup_publish_once(thread_id)?;
    pl_tool::workspace::move_owned_path(temporary, target)?;
    sync_parent(target)
}

async fn quick_check(db: &DatabaseConnection) -> Result<()> {
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", Vec::new()))
        .await?
    {
        if row.try_get_by_index::<String>(0)? != "ok" {
            return Err(HistoryError::Integrity(
                "schema 24 backup integrity check failed".into(),
            ));
        }
    }
    Ok(())
}

async fn source_table_rows(source: &V24HistorySource) -> Result<BTreeMap<String, u64>> {
    let mut rows = BTreeMap::new();
    for table in LEGACY_SOURCE_TABLES
        .iter()
        .chain(LEGACY_WORK_SNAPSHOT_ARCHIVES)
    {
        if LEGACY_WORK_SNAPSHOT_ARCHIVES.contains(table)
            && source
                .query_one(
                    "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
                    vec![(*table).into()],
                )
                .await?
                .is_none()
        {
            continue;
        }
        let row = source
            .query_one(
                &format!("SELECT count(*) AS count FROM {table}"),
                Vec::new(),
            )
            .await?
            .ok_or_else(|| HistoryError::Integrity(format!("legacy table {table} vanished")))?;
        rows.insert(
            (*table).to_owned(),
            db_u64(row.try_get::<i64>("", "count")?, "legacy table row count")?,
        );
    }
    Ok(rows)
}

async fn database_table_rows(db: &DatabaseConnection) -> Result<BTreeMap<String, u64>> {
    let mut rows = BTreeMap::new();
    for table in LEGACY_SOURCE_TABLES
        .iter()
        .chain(LEGACY_WORK_SNAPSHOT_ARCHIVES)
    {
        if LEGACY_WORK_SNAPSHOT_ARCHIVES.contains(table) && !table_exists(db, table).await? {
            continue;
        }
        let row = db
            .query_one_raw(statement(
                &format!("SELECT count(*) AS count FROM {table}"),
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity(format!("legacy table {table} vanished")))?;
        rows.insert(
            (*table).to_owned(),
            db_u64(row.try_get::<i64>("", "count")?, "backup table row count")?,
        );
    }
    Ok(rows)
}

async fn prepare_current(
    source: &V24HistorySource,
    thread_id: &str,
    session_dir: &Path,
    operation_dir: &Path,
) -> Result<Option<PathBuf>> {
    let current_path = session_dir.join("current.json");
    if current_path.is_file() {
        let (_, bytes) = crate::studio::storage::read_for_upgrade(session_dir, thread_id).await?;
        File::options()
            .write(true)
            .open(&current_path)?
            .sync_all()?;
        sync_parent(&current_path)?;
        let backup = operation_dir.join("current.original.json");
        backup_exact_bytes(&backup, &bytes)?;
        return Ok(Some(backup));
    }
    if current_path.exists() {
        return Err(HistoryError::Integrity(
            "current path exists but is not a file".into(),
        ));
    }
    let Some(checkpoint) = source.checkpoint(thread_id).await? else {
        return Ok(None);
    };
    let current = build_current(source, checkpoint, thread_id, session_dir).await?;
    crate::studio::storage::verify_for_upgrade(session_dir, thread_id, &current).await?;
    let bytes = serde_json::to_vec(&current)?;
    fail_current_publish_once(thread_id, false)?;
    pl_tool::workspace::write_file_atomically(&current_path, &bytes)?;
    fail_current_publish_once(thread_id, true)?;
    let (restored, restored_bytes) =
        crate::studio::storage::read_for_upgrade(session_dir, thread_id).await?;
    if restored.thread_id != thread_id || restored_bytes != bytes {
        return Err(HistoryError::Integrity("published current changed".into()));
    }
    Ok(None)
}

async fn build_current(
    source: &V24HistorySource,
    mut checkpoint: Box<pl_core::thread::ThreadCheckpoint>,
    thread_id: &str,
    session_dir: &Path,
) -> Result<ThreadCurrent> {
    materialize_checkpoint_bodies(session_dir, &mut checkpoint).await?;
    verify_saved_pending_originals(source, &checkpoint).await?;
    verify_pending_identities(source, &checkpoint).await?;
    let epoch = RuntimeEpoch::new();
    let state = ThreadCurrentState::from_snapshot(&checkpoint.state, epoch)
        .map_err(|error| HistoryError::Storage(error.into()))?;
    let mut current = ThreadCurrent::new(thread_id.to_owned(), epoch);
    current.state = state;
    current.saved_at = unix_milliseconds()?;
    current.model_call = None;
    Ok(current)
}

async fn materialize_checkpoint_bodies(
    session_dir: &Path,
    checkpoint: &mut pl_core::thread::ThreadCheckpoint,
) -> Result<()> {
    while let Some(entry) = checkpoint.pending_body().cloned() {
        let path = checkpoint_blob_path(session_dir, entry.reference.digest())?;
        let bytes = tokio::fs::read(&path).await.map_err(|error| {
            HistoryError::Storage(anyhow::anyhow!(
                "read checkpoint body {}: {error}",
                path.display()
            ))
        })?;
        checkpoint
            .materialize_body(&entry.reference, &bytes)
            .map_err(|error| {
                HistoryError::Storage(anyhow::anyhow!(
                    "materialize checkpoint body {}: {error}",
                    path.display()
                ))
            })?;
    }
    Ok(())
}

fn checkpoint_blob_path(session_dir: &Path, digest: &str) -> Result<PathBuf> {
    let hex = digest.strip_prefix("sha256:").ok_or_else(|| {
        HistoryError::Integrity("checkpoint body digest is not a SHA-256 address".into())
    })?;
    if hex.len() != 64 || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(HistoryError::Integrity(
            "checkpoint body digest is not a SHA-256 address".into(),
        ));
    }
    Ok(session_dir
        .join("blobs")
        .join("checkpoint")
        .join(&hex[..2])
        .join(hex))
}

async fn verify_saved_pending_originals(
    source: &V24HistorySource,
    checkpoint: &pl_core::thread::ThreadCheckpoint,
) -> Result<()> {
    for resident in checkpoint.state.tasks.values() {
        let row = source
            .query_one(
                "SELECT revision,task_payload FROM history_tool_tasks WHERE call_id=?",
                vec![resident.call_id.clone().into()],
            )
            .await?
            .ok_or_else(|| {
                HistoryError::Integrity("resident task has no durable schema 24 original".into())
            })?;
        let durable: pl_core::thread::task::TaskRecord =
            serde_json::from_str(&row.try_get::<String>("", "task_payload")?)?;
        if durable != *resident
            || durable.revision
                != db_u64(
                    row.try_get::<i64>("", "revision")?,
                    "history_tool_tasks.revision",
                )?
        {
            return Err(HistoryError::Integrity(
                "resident task differs from its durable schema 24 original".into(),
            ));
        }
    }
    for resident in checkpoint.state.deliveries.iter() {
        let row = source
            .query_one(
                "SELECT delivery_payload FROM history_tool_tasks WHERE call_id=?",
                vec![resident.call_id.clone().into()],
            )
            .await?
            .ok_or_else(|| {
                HistoryError::Integrity(
                    "resident delivery has no durable schema 24 original".into(),
                )
            })?;
        let payload = row
            .try_get::<Option<String>>("", "delivery_payload")?
            .ok_or_else(|| {
                HistoryError::Integrity("resident delivery has no durable schema 24 payload".into())
            })?;
        let durable: pl_core::thread::ToolDelivery = serde_json::from_str(&payload)?;
        let durable_json = serde_json::to_value(&durable)?;
        let resident_json = serde_json::to_value(resident)?;
        if durable_json != resident_json {
            return Err(HistoryError::Integrity(
                "resident delivery differs from its durable schema 24 original".into(),
            ));
        }
    }
    Ok(())
}

async fn verify_pending_identities(
    source: &V24HistorySource,
    checkpoint: &pl_core::thread::ThreadCheckpoint,
) -> Result<()> {
    for input in checkpoint.state.inputs.iter() {
        let row = source
            .query_one(
                "SELECT payload FROM history_input_identities WHERE item_id=?",
                vec![input.input.id.clone().into()],
            )
            .await?
            .ok_or_else(|| {
                HistoryError::Integrity("resident input has no durable schema 24 original".into())
            })?;
        let durable = decode_legacy_input_identity(&row.try_get::<String>("", "payload")?)?;
        if durable.id != input.input.id
            || durable.digest != input.input.digest()
            || durable.delivery != input.delivery
            || durable.purpose != input.input.purpose
            || durable.ordinal != input.ordinal
            || durable.revision != input.revision
            || durable.state != input.state
            || durable.accepted_sequence != input.accepted_sequence
        {
            return Err(HistoryError::Integrity(
                "resident input differs from its durable schema 24 original".into(),
            ));
        }
    }
    for message in checkpoint.state.inbox.iter() {
        let row = source
            .query_one(
                "SELECT item_id,sequence,digest FROM history_message_identities WHERE message_id=?",
                vec![message.message.id.clone().into()],
            )
            .await?;
        let row = match row {
            Some(row) => row,
            None => {
                return Err(HistoryError::Integrity(
                    "resident inbox message has no durable schema 24 identity".into(),
                ));
            }
        };
        if row.try_get::<String>("", "item_id")?.is_empty() {
            return Err(HistoryError::Integrity(
                "resident inbox message has no durable schema 24 identity".into(),
            ));
        }
        let sequence = db_u64(
            row.try_get::<i64>("", "sequence")?,
            "history_message_identities.sequence",
        )?;
        let digest = row.try_get::<Option<String>>("", "digest")?;
        if sequence != message.sequence
            || digest
                .as_deref()
                .is_some_and(|digest| digest != message.message.digest())
        {
            return Err(HistoryError::Integrity(
                "resident inbox message differs from its durable schema 24 identity".into(),
            ));
        }
    }
    Ok(())
}

fn backup_exact_bytes(target: &Path, bytes: &[u8]) -> Result<()> {
    let parent = target
        .parent()
        .ok_or_else(|| HistoryError::Storage(anyhow::anyhow!("backup has no parent")))?;
    let parent = std::fs::canonicalize(parent)?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".upgrade-copy-")
        .tempfile_in(&parent)?;
    temporary.write_all(bytes)?;
    temporary.as_file().sync_all()?;
    let (file, temporary_path) = temporary.keep().map_err(|error| error.error)?;
    drop(file);
    pl_tool::workspace::move_owned_path(&temporary_path, target)?;
    sync_parent(target)?;
    Ok(())
}

fn stage_pending_report(pending_report: &Path, report: &UpgradeReport) -> Result<()> {
    if pending_report.try_exists()? {
        return Err(HistoryError::Conflict(
            "another schema 24 upgrade report is already pending".into(),
        ));
    }
    let target = report_operation_dir(pending_report, report)?.join("upgrade-report.json");
    if target.try_exists()? {
        return Err(HistoryError::Conflict(
            "the schema 25 upgrade report already exists".into(),
        ));
    }
    let bytes = serde_json::to_vec_pretty(report)?;
    backup_exact_bytes(pending_report, &bytes)
}

async fn finish_schema26(
    history_path: &Path,
    read: DatabaseConnection,
    pending_report: &Path,
    thread_id: &str,
    database_id: String,
    expected_backup_name: &str,
    lease_held: bool,
) -> Result<UpgradeReport> {
    let needed = match schema26_manifest::repair_needed(&read).await {
        Ok(needed) => {
            read.close().await?;
            needed
        }
        Err(error) => {
            let _ = read.close().await;
            return Err(error);
        }
    };
    if !needed {
        return complete_schema26_entry(
            pending_report,
            thread_id,
            database_id,
            expected_backup_name,
        );
    }
    // upgrade_history may already hold this file lease. try_lock is not reentrant.
    let _lease = if lease_held {
        None
    } else {
        Some(acquire_writer_lease(history_path).await?)
    };
    let writer = schema::connect(history_path, false, false).await?;
    let repaired = schema26_manifest::repair(&writer).await;
    let closed = writer.close().await;
    repaired?;
    closed?;
    complete_schema26_entry(pending_report, thread_id, database_id, expected_backup_name)
}

fn complete_schema26_entry(
    pending_report: &Path,
    thread_id: &str,
    database_id: String,
    expected_backup_name: &str,
) -> Result<UpgradeReport> {
    if !pending_report.try_exists()? {
        return Ok(UpgradeReport {
            operation_id: "already-schema-26".into(),
            thread_id: thread_id.to_owned(),
            database_id,
            status: UpgradeStatus::AlreadySchema26,
            backup: None,
            current_original_backup: None,
            source_table_rows: BTreeMap::new(),
            imported_categories: BTreeMap::new(),
            backup_only_categories: BTreeMap::new(),
        });
    }
    let mut report = complete_pending_report(
        pending_report,
        thread_id,
        &database_id,
        expected_backup_name,
    )?;
    report.status = UpgradeStatus::AlreadySchema26;
    Ok(report)
}

fn report_operation_dir(pending_report: &Path, report: &UpgradeReport) -> Result<PathBuf> {
    let operation_id = uuid::Uuid::parse_str(&report.operation_id).map_err(|error| {
        HistoryError::Integrity(format!("pending upgrade operation is invalid: {error}"))
    })?;
    if operation_id.get_version_num() != 4 || operation_id.to_string() != report.operation_id {
        return Err(HistoryError::Integrity(
            "pending upgrade operation is not a canonical version 4 UUID".into(),
        ));
    }
    Ok(pending_report
        .parent()
        .ok_or_else(|| HistoryError::Integrity("pending upgrade report has no parent".into()))?
        .join(&report.operation_id))
}

fn preserved_file_exists(path: &Path) -> Result<bool> {
    match std::fs::metadata(path) {
        Ok(metadata) => Ok(metadata.is_file()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

fn complete_pending_report(
    pending_report: &Path,
    thread_id: &str,
    database_id: &str,
    expected_backup_name: &str,
) -> Result<UpgradeReport> {
    let bytes = std::fs::read(pending_report)?;
    let report: UpgradeReport = serde_json::from_slice(&bytes)?;
    let operation_dir = report_operation_dir(pending_report, &report)?;
    let expected_backup = operation_dir.join(expected_backup_name);
    let expected_current_backup = operation_dir.join("current.original.json");
    let current_backup_matches = match &report.current_original_backup {
        None => true,
        Some(path) => path == &expected_current_backup,
    };
    if report.thread_id != thread_id
        || report.database_id != database_id
        || report.status != UpgradeStatus::Upgraded
        || report.backup.as_ref() != Some(&expected_backup)
        || !current_backup_matches
    {
        return Err(HistoryError::Conflict(
            "pending schema 25 upgrade report does not match this history".into(),
        ));
    }
    if !preserved_file_exists(&expected_backup)?
        || match &report.current_original_backup {
            Some(path) => !preserved_file_exists(path)?,
            None => false,
        }
    {
        return Err(HistoryError::Integrity(
            "pending schema 25 upgrade report is missing its preserved inputs".into(),
        ));
    }
    let target = operation_dir.join("upgrade-report.json");
    if target.try_exists()? {
        let existing = std::fs::read(&target)?;
        if existing != bytes {
            return Err(HistoryError::Conflict(
                "the schema 25 upgrade report conflicts with its pending copy".into(),
            ));
        }
    } else {
        fail_report_publish_once(thread_id)?;
        backup_exact_bytes(&target, &bytes)?;
    }
    std::fs::remove_file(pending_report)?;
    sync_parent(pending_report)?;
    Ok(report)
}

fn discard_rolled_back_pending_report(
    pending_report: &Path,
    thread_id: &str,
    database_id: &str,
) -> Result<()> {
    if !pending_report.try_exists()? {
        return Ok(());
    }
    let bytes = std::fs::read(pending_report)?;
    let report: UpgradeReport = serde_json::from_slice(&bytes)?;
    if report.thread_id != thread_id
        || report.database_id != database_id
        || report.status != UpgradeStatus::Upgraded
    {
        return Err(HistoryError::Conflict(
            "rolled-back schema 24 upgrade report does not match this history".into(),
        ));
    }
    let operation_dir = report_operation_dir(pending_report, &report)?;
    let expected_backup = operation_dir.join("history.v24.sqlite");
    let expected_current_backup = operation_dir.join("current.original.json");
    let current_backup_matches = match &report.current_original_backup {
        None => true,
        Some(path) => path == &expected_current_backup,
    };
    if report.backup.as_ref() != Some(&expected_backup)
        || !current_backup_matches
        || !preserved_file_exists(&expected_backup)?
        || match &report.current_original_backup {
            Some(path) => !preserved_file_exists(path)?,
            None => false,
        }
        || operation_dir.join("upgrade-report.json").try_exists()?
    {
        return Err(HistoryError::Conflict(
            "rolled-back schema 24 upgrade report has conflicting artifacts".into(),
        ));
    }
    let uncommitted = operation_dir.join("uncommitted-report.json");
    if uncommitted.try_exists()? {
        if std::fs::read(&uncommitted)? != bytes {
            return Err(HistoryError::Conflict(
                "rolled-back upgrade report conflicts with its preserved copy".into(),
            ));
        }
    } else {
        backup_exact_bytes(&uncommitted, &bytes)?;
    }
    std::fs::remove_file(pending_report)?;
    sync_parent(pending_report)?;
    Ok(())
}

fn sync_parent(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        let parent = path
            .parent()
            .ok_or_else(|| HistoryError::Storage(anyhow::anyhow!("path has no parent")))?;
        File::open(parent)?.sync_all()?;
    }
    #[cfg(not(unix))]
    let _ = path;
    Ok(())
}

fn unix_milliseconds() -> Result<i64> {
    let elapsed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| HistoryError::Storage(error.into()))?;
    i64::try_from(elapsed.as_millis()).map_err(|_| {
        HistoryError::Integrity("system clock exceeds the current millisecond range".into())
    })
}

fn opaque_payload(format: &str, content: String) -> Result<OpaquePayload> {
    OpaquePayload::new(format, 1, content)
        .map_err(|error| HistoryError::Storage(anyhow::anyhow!(error)))
}

#[cfg(test)]
fn fail_backup_publish_once(thread_id: &str) -> Result<()> {
    let mut fail = FAIL_NEXT_BACKUP_PUBLISH_THREAD
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if fail.as_deref() == Some(thread_id) {
        fail.take();
        return Err(HistoryError::Integrity(
            "injected schema 24 backup publication failure".into(),
        ));
    }
    Ok(())
}

#[cfg(not(test))]
fn fail_backup_publish_once(_thread_id: &str) -> Result<()> {
    Ok(())
}

#[cfg(test)]
fn fail_current_publish_once(thread_id: &str, after_write: bool) -> Result<()> {
    let mut fail = FAIL_NEXT_CURRENT_PUBLISH
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let selected = fail
        .as_ref()
        .is_some_and(|(id, after)| id == thread_id && *after == after_write);
    if selected {
        fail.take();
        return Err(HistoryError::Integrity(if after_write {
            "injected current publication verification failure".into()
        } else {
            "injected current publication failure".into()
        }));
    }
    Ok(())
}

#[cfg(not(test))]
fn fail_current_publish_once(_thread_id: &str, _after_write: bool) -> Result<()> {
    Ok(())
}

#[cfg(test)]
fn fail_ddl_once(thread_id: &str) -> Result<()> {
    let mut fail = FAIL_NEXT_DDL_THREAD
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if fail.as_deref() == Some(thread_id) {
        fail.take();
        return Err(HistoryError::Integrity(
            "injected schema 24 destructive DDL failure".into(),
        ));
    }
    Ok(())
}

#[cfg(not(test))]
fn fail_ddl_once(_thread_id: &str) -> Result<()> {
    Ok(())
}

#[cfg(test)]
fn fail_report_publish_once(thread_id: &str) -> Result<()> {
    let mut fail = FAIL_NEXT_REPORT_THREAD
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if fail.as_deref() == Some(thread_id) {
        fail.take();
        return Err(HistoryError::Integrity(
            "injected upgrade report publication failure".into(),
        ));
    }
    Ok(())
}

#[cfg(not(test))]
fn fail_report_publish_once(_thread_id: &str) -> Result<()> {
    Ok(())
}

pub(super) async fn import_database(
    tx: &impl ConnectionTrait,
    source: &V24HistorySource,
    database_id: &str,
    thread_id: &str,
    source_watermark: u64,
) -> Result<ImportCounts> {
    create_payload_staging(tx).await?;
    let result =
        import_database_with_staging(tx, source, database_id, thread_id, source_watermark).await;
    let cleanup = drop_payload_staging(tx).await;
    let counts = match result {
        Ok(counts) => counts,
        Err(error) => return Err(error),
    };
    cleanup?;
    Ok(counts)
}

async fn import_database_with_staging(
    tx: &impl ConnectionTrait,
    source: &V24HistorySource,
    database_id: &str,
    thread_id: &str,
    source_watermark: u64,
) -> Result<ImportCounts> {
    let identity = source
        .query_one(
            "SELECT schema_version,database_id,thread_id,applied_write_seq FROM history_meta WHERE id=1",
            Vec::new(),
        )
        .await?
        .ok_or_else(|| HistoryError::Integrity("schema 24 identity vanished".into()))?;
    if identity.try_get::<i64>("", "schema_version")? != 24
        || identity.try_get::<String>("", "database_id")? != database_id
        || identity.try_get::<String>("", "thread_id")? != thread_id
        || db_u64(
            identity.try_get::<i64>("", "applied_write_seq")?,
            "history_meta.applied_write_seq",
        )? != source_watermark
    {
        return Err(HistoryError::Integrity(
            "schema 24 source changed before migration".into(),
        ));
    }
    assert_known_source_tables(source).await?;
    let recorded_at = unix_milliseconds()?;
    let mut import = HistoryImport::new(tx, database_id.to_owned()).await?;
    let mut counts = ImportCounts::default();
    let canonical = import_originals(
        tx,
        &mut import,
        source,
        database_id,
        recorded_at,
        &mut counts,
    )
    .await?;
    // Published schema 24 retains the earlier completed-record container too.
    // Its identities were adopted by conversation_items in schema 12; preserve
    // the old container verbatim in the backup without importing originals twice.
    let orphan = source.query_one(
        "SELECT old.record_id FROM timeline_records old LEFT JOIN conversation_items current ON current.item_id=old.record_id WHERE current.item_id IS NULL LIMIT 1",
        Vec::new(),
    ).await?;
    if orphan.is_some() {
        return Err(HistoryError::Integrity(
            "schema 24 timeline_records contains an original absent from conversation_items".into(),
        ));
    }
    let old_records = source
        .query_one("SELECT count(*) AS count FROM timeline_records", Vec::new())
        .await?
        .ok_or_else(|| {
            HistoryError::Integrity("legacy completed record count is missing".into())
        })?;
    counts.backup_only(
        "timeline_records",
        db_u64(old_records.try_get("", "count")?, "timeline_records count")?,
    );
    import_supplements(
        &mut import,
        source,
        database_id,
        thread_id,
        recorded_at,
        &mut counts,
    )
    .await?;
    import_display(
        tx,
        &mut import,
        source,
        database_id,
        recorded_at,
        &mut counts,
    )
    .await?;
    import.finish().await?;
    verify_import(tx, source, database_id, canonical).await?;
    #[cfg(test)]
    {
        let mut fail = FAIL_NEXT_IMPORT_THREAD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if fail.as_deref() == Some(thread_id) {
            fail.take();
            return Err(HistoryError::Integrity(
                "injected schema 24 to 25 import failure".into(),
            ));
        }
    }
    drop_legacy_tables(tx, thread_id).await?;
    counts.backup_only("history_meta", 1);
    Ok(counts)
}

async fn assert_known_source_tables(source: &V24HistorySource) -> Result<()> {
    let rows = source
        .query_all(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            Vec::new(),
        )
        .await?;
    for row in rows {
        let name: String = row.try_get("", "name")?;
        if !LEGACY_SOURCE_TABLES.contains(&name.as_str())
            && !LEGACY_WORK_SNAPSHOT_ARCHIVES.contains(&name.as_str())
            && name != "seaql_migrations"
            && ![
                "history_store_meta",
                "history_events",
                "history_bodies",
                "history_body_chunks",
            ]
            .contains(&name.as_str())
        {
            return Err(HistoryError::Integrity(format!(
                "unknown schema 24 table {name}; original database preserved"
            )));
        }
    }
    Ok(())
}

fn deterministic_event_id(table: &str, keys: &[serde_json::Value], role: &str) -> String {
    format!(
        "{LEGACY_EVENT_PREFIX}{}",
        canonical_digest([
            serde_json::Value::String(table.to_owned()),
            serde_json::Value::Array(keys.to_vec()),
            serde_json::Value::String(role.to_owned()),
        ])
    )
}

fn deterministic_body_id(owner: &str, body_key: &str) -> String {
    format!(
        "{LEGACY_BODY_PREFIX}{}",
        canonical_digest([owner.into(), body_key.into()])
    )
}

fn canonical_digest(values: impl IntoIterator<Item = serde_json::Value>) -> String {
    let value = serde_json::Value::Array(values.into_iter().collect());
    hex::encode(Sha256::digest(
        serde_json::to_vec(&value).expect("canonical JSON"),
    ))
}

struct VecSource {
    bytes: Vec<u8>,
}
impl HistoryBodySource for VecSource {
    fn byte_length(&self) -> u64 {
        self.bytes.len() as u64
    }
    async fn read(&self, offset: u64, max_bytes: u32) -> Result<Vec<u8>> {
        let offset = offset as usize;
        let end = offset
            .saturating_add(max_bytes as usize)
            .min(self.bytes.len());
        if offset > self.bytes.len() {
            return Err(HistoryError::InvalidDemand("legacy vector range".into()));
        }
        Ok(self.bytes[offset..end].to_vec())
    }
}

async fn import_originals<C: ConnectionTrait>(
    connection: &C,
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    database_id: &str,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<u64> {
    let mut after = 0;
    let mut count = 0;
    loop {
        let page = source.originals_page(after, 128).await?;
        if page.is_empty() {
            break;
        }
        for original in page {
            after = original.seq;
            let metadata = read_product_container(
                source
                    .body(V24Body::Metadata {
                        item_id: original.item_id.clone(),
                    })
                    .await?,
            )
            .await?;
            let mut atom: ChatAtom = serde_json::from_slice(&metadata)?;
            if atom
                .completion_item_id
                .as_ref()
                .is_some_and(|id| id.as_str() != original.item_id.as_str())
            {
                return Err(HistoryError::Integrity(
                    "canonical original points at another completion".into(),
                ));
            }
            let mut entity = HistoryEntityHead::from_atom(&atom, None)?;
            entity.detail_event_id = Some(original.item_id.clone());
            entity.input_manifest_event_id = Some(original.item_id.clone());
            entity.body_manifest_event_id = Some(original.item_id.clone());
            fit_entity_head(import, &mut entity, &original.item_id, database_id, 3).await?;

            let mut staged_payload =
                StagedPayload::from_item(connection, &original.item_id).await?;
            staged_payload
                .rewrite_declarations(source, database_id, &original.item_id, atom.source_order)
                .await?;
            if let Some(PayloadData::Deferred { reference, .. }) = &atom.payload {
                plan_content_reference(
                    connection,
                    source,
                    database_id,
                    &original.item_id,
                    reference,
                )
                .await?;
            }
            plan_and_rewrite_atom_references(connection, &mut atom, database_id, &original.item_id)
                .await?;
            let payload_id = deterministic_body_id(&original.item_id, "canonical_payload");
            import
                .copy_body(
                    HistoryImportBody {
                        body_id: payload_id,
                        owner_event_id: original.item_id.clone(),
                        ordinal: 0,
                        body_key: "canonical_payload".into(),
                        role: HistoryBodyRole::CanonicalPayload,
                        media_type: None,
                    },
                    &staged_payload,
                )
                .await?;

            copy_vector_body(
                import,
                &original.item_id,
                "canonical_metadata",
                HistoryBodyRole::CanonicalMetadata,
                1,
                serde_json::to_vec(&entity)?,
            )
            .await?;
            copy_vector_body(
                import,
                &original.item_id,
                "legacy_metadata",
                HistoryBodyRole::Other {
                    name: "legacy_metadata".into(),
                },
                2,
                serde_json::to_vec(&entity)?,
            )
            .await?;
            copy_planned_bodies(connection, import, source).await?;

            let mut event =
                HistoryEvent::new(original.item_id.clone(), canonical_kind(&atom), recorded_at);
            event.header.entity_id = Some(atom.id.clone());
            event.header.turn_id = atom.turn_id.clone();
            event.header.attempt_id = atom.attempt_id.clone();
            event.header.source = Some(atom.source.clone());
            event.header.call_id = atom.tool.as_ref().map(|tool| tool.call_id.clone());
            event.header.occurred_at = event_time(&atom)?;
            event.header.original = Some(super::HistoryOriginalInfo {
                query_class: original.query_class.clone(),
                parent_id: original.parent_id.clone(),
                original_kind: atom.kind,
                tool_name: atom.tool.as_ref().map(|tool| tool.name.clone()),
            });
            event.payload_body_id = Some(deterministic_body_id(
                &original.item_id,
                "canonical_payload",
            ));
            import.insert_event(event).await?;
            count += 1;
            counts.imported("canonical_originals", 1);
        }
    }
    Ok(count)
}

fn canonical_kind(atom: &ChatAtom) -> HistoryEventKind {
    if atom.attempt_id.is_some() {
        return HistoryEventKind::LegacyObserved;
    }
    match (&atom.kind, &atom.lifecycle) {
        (crate::ChatAtomKind::Input, ChatAtomLifecycle::Terminal { .. }) => {
            HistoryEventKind::InputAccepted
        }
        (_, ChatAtomLifecycle::Terminal { .. }) => HistoryEventKind::EntityEnded,
        _ => HistoryEventKind::LegacyObserved,
    }
}

fn event_time(atom: &ChatAtom) -> Result<Option<i64>> {
    milliseconds(atom.finished_at.or(atom.started_at))
}

async fn read_product_container(reader: V24BodyReader) -> Result<Vec<u8>> {
    // This is the bounded typed product envelope, never a producer body. Its existing protocol
    // read budget is shared with normal detail reads; historical payloads remain range-copied.
    let length = usize::try_from(reader.byte_length())
        .map_err(|_| HistoryError::Integrity("legacy metadata length exceeds usize".into()))?;
    if length > pl_core::chat::MAX_READ_BYTES {
        return Err(HistoryError::Integrity(
            "schema 24 typed metadata exceeds the existing detail read budget".into(),
        ));
    }
    let mut bytes = Vec::with_capacity(length);
    let mut offset = 0;
    while offset < reader.byte_length() {
        let length = (reader.byte_length() - offset).min(BODY_CHUNK_BYTES as u64) as u32;
        bytes.extend_from_slice(&reader.read(offset, length).await?);
        offset += length as u64;
    }
    Ok(bytes)
}

async fn copy_vector_body<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    owner: &str,
    key: &str,
    role: HistoryBodyRole,
    ordinal: u64,
    bytes: Vec<u8>,
) -> Result<()> {
    import
        .copy_body(
            HistoryImportBody {
                body_id: deterministic_body_id(owner, key),
                owner_event_id: owner.to_owned(),
                ordinal,
                body_key: key.to_owned(),
                role,
                media_type: None,
            },
            &VecSource { bytes },
        )
        .await?;
    Ok(())
}

async fn fit_entity_head<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    head: &mut HistoryEntityHead,
    event_id: &str,
    database_id: &str,
    wait_ordinal: u64,
) -> Result<u64> {
    if serde_json::to_vec(head)?.len() <= HEAD_MAX_BYTES {
        return Ok(wait_ordinal);
    }
    let Some(HistoryWaitHead::Inline { presentation }) = head.wait.take() else {
        return Err(HistoryError::Integrity(
            "typed history head exceeds 16 KiB without a movable wait presentation".into(),
        ));
    };
    let intent = match presentation.intent() {
        crate::ThreadWaitIntent::Events {
            targets,
            timeout_ms,
        } => HistoryWaitIntentHead::Events {
            target_count: targets.len() as u64,
            timeout_ms: *timeout_ms,
        },
        crate::ThreadWaitIntent::Timer { duration_ms } => HistoryWaitIntentHead::Timer {
            duration_ms: *duration_ms,
        },
    };
    let body_id = deterministic_body_id(event_id, "wait_presentation");
    let bytes = serde_json::to_vec(&presentation)?;
    head.wait = Some(HistoryWaitHead::Deferred {
        intent,
        state: presentation.state(),
        messages_ready: presentation.messages_ready(),
        presentation: HistoryEventBodyRef {
            database_id: database_id.to_owned(),
            owner_event_id: event_id.to_owned(),
            body_key: "wait_presentation".into(),
            body_id,
            byte_start: 0,
            byte_length: bytes.len() as u64,
        },
    });
    if serde_json::to_vec(head)?.len() > HEAD_MAX_BYTES {
        return Err(HistoryError::Integrity(
            "typed history head remains over 16 KiB after moving wait presentation".into(),
        ));
    }
    copy_vector_body(
        import,
        event_id,
        "wait_presentation",
        HistoryBodyRole::WaitPresentation,
        wait_ordinal,
        bytes,
    )
    .await?;
    wait_ordinal
        .checked_add(1)
        .ok_or_else(|| HistoryError::Integrity("history body ordinal exhausted".into()))
}

async fn plan_and_rewrite_atom_references(
    connection: &impl ConnectionTrait,
    atom: &mut ChatAtom,
    database_id: &str,
    fallback_owner: &str,
) -> Result<serde_json::Value> {
    for content in &atom.contents {
        validate_typed_reference(&content.reference, database_id)?;
    }
    if let Some(PayloadData::Deferred { reference, .. }) = &atom.payload {
        validate_typed_reference(reference, database_id)?;
    }
    render_rewritten_atom(connection, atom, database_id, fallback_owner).await
}

fn validate_typed_reference(reference: &ContentRef, database_id: &str) -> Result<()> {
    if reference.database_id != database_id {
        return Err(HistoryError::Integrity(
            "schema 24 typed reference points at another database".into(),
        ));
    }
    Ok(())
}

fn plan_identity(
    target: &ContentTarget,
    fallback_owner: &str,
) -> Result<(String, String, HistoryBodyRole)> {
    Ok(match target {
        ContentTarget::ItemPayload { item_id } => (
            item_id.clone(),
            "canonical_payload".to_owned(),
            HistoryBodyRole::CanonicalPayload,
        ),
        ContentTarget::Body { owner, key } => match owner {
            ContentOwner::Item { item_id } => (
                item_id.clone(),
                format!("legacy-content:{key}"),
                legacy_content_role(key),
            ),
            ContentOwner::Current {
                domain,
                id,
                revision,
            } => (
                fallback_owner.to_owned(),
                format!(
                    "legacy-current:{}:{key}",
                    canonical_digest([
                        domain.clone().into(),
                        id.clone().into(),
                        (*revision).into(),
                    ])
                ),
                legacy_content_role(key),
            ),
            ContentOwner::DisplayObservation {
                block_id,
                member_key,
            } => (
                display_member_event_id(block_id, member_key),
                format!("legacy-display:{key}"),
                legacy_content_role(key),
            ),
        },
    })
}

fn legacy_content_role(key: &str) -> HistoryBodyRole {
    if key == "body"
        || key.starts_with("part.outputText.")
        || key.starts_with("part.reasoningText.")
    {
        HistoryBodyRole::Body
    } else if key.starts_with("part.summaryText.") {
        HistoryBodyRole::ReasoningSummary
    } else if key == "tool.arguments" {
        HistoryBodyRole::ToolArguments
    } else if key == "tool.result" {
        HistoryBodyRole::ToolOutput
    } else {
        HistoryBodyRole::Other {
            name: "legacy_content".into(),
        }
    }
}

fn display_member_event_id(block_id: &str, member_key: &str) -> String {
    deterministic_event_id(
        "conversation_display_members",
        &[block_id.into(), member_key.into()],
        "boundary",
    )
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LifecycleRow {
    identity: String,
    kind: crate::ChatAtomKind,
    source_kind: String,
    source_identity: String,
    turn_id: Option<String>,
    attempt_id: Option<String>,
    call_id: Option<String>,
    tool_name: Option<String>,
    text_channel: Option<crate::ThreadTextChannel>,
    delivery: crate::ChatDeliveryKind,
    source_order: Option<u64>,
    execution_order: Option<u64>,
    started: Option<crate::ChatFactPosition>,
    ended: Option<crate::ChatFactPosition>,
    started_at: Option<i64>,
    finished_at: Option<i64>,
    outcome: Option<crate::ChatTerminalOutcome>,
    completion_item_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct TurnRow {
    turn_id: String,
    turn_order: u64,
    payload: Turn,
    context_disposition: crate::ThreadContextDisposition,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SourceRow {
    source_key: String,
    started_effect: Option<i64>,
    ended_effect: Option<i64>,
    active_observed: Option<u64>,
    outcome: Option<crate::ChatTerminalOutcome>,
}

const LEGACY_INPUT_IDENTITY_FIELDS: &[&str] = &[
    "digest",
    "continuation",
    "delivery",
    "id",
    "purpose",
    "expectedModelRouteRevision",
    "continuationAdmissionRevision",
    "ordinal",
    "revision",
    "state",
    "acceptedSequence",
];

/// Decodes the frozen schema-24 input identity without admitting unknown user content.
///
/// The old row type intentionally tolerates fields added over its lifetime, so the migration
/// boundary checks the key set before decoding that type. Newer unknown fields stop the upgrade
/// instead of being silently copied or discarded.
fn decode_legacy_input_identity(
    payload: &str,
) -> Result<crate::studio::storage::state::InputIdentityEntry> {
    let value: serde_json::Value = serde_json::from_str(payload)?;
    let object = value.as_object().ok_or_else(|| {
        HistoryError::Integrity("schema 24 input identity payload is not an object".into())
    })?;
    if let Some(unknown) = object
        .keys()
        .find(|key| !LEGACY_INPUT_IDENTITY_FIELDS.contains(&key.as_str()))
    {
        return Err(HistoryError::Integrity(format!(
            "schema 24 input identity contains unsupported field {unknown}"
        )));
    }
    Ok(serde_json::from_value(value)?)
}

async fn read_legacy_product_blob(
    source: &V24HistorySource,
    table: &'static str,
    key_column: &'static str,
    key_value: &str,
    column: &'static str,
) -> Result<Vec<u8>> {
    if !matches!(
        (table, key_column, column),
        ("conversation_display_blocks", "block_id", "header")
            | ("conversation_display_members", "member_key", "metadata")
    ) {
        return Err(HistoryError::InvalidDemand(
            "unsupported legacy product blob".into(),
        ));
    }
    let length = source
        .query_one(
            &format!(
                "SELECT length(CAST({column} AS BLOB)) AS bytes FROM {table} WHERE {key_column}=?"
            ),
            vec![key_value.into()],
        )
        .await?
        .ok_or_else(|| HistoryError::NotFound(key_value.to_owned()))?
        .try_get::<i64>("", "bytes")?;
    let length = db_u64(length, "typed product blob length")?;
    if length > pl_core::chat::MAX_READ_BYTES as u64 {
        return Err(HistoryError::Integrity(
            "schema 24 typed display record exceeds the existing detail read budget".into(),
        ));
    }
    source
        .query_one(
            &format!("SELECT {column} AS bytes FROM {table} WHERE {key_column}=?"),
            vec![key_value.into()],
        )
        .await?
        .ok_or_else(|| HistoryError::NotFound(key_value.to_owned()))?
        .try_get::<Vec<u8>>("", "bytes")
        .map_err(HistoryError::from)
}

fn source_from_parts(kind: &str, identity: String) -> Result<HistorySource> {
    Ok(match kind {
        "foregroundTurn" => HistorySource::ForegroundTurn { turn_id: identity },
        "input" => HistorySource::Input { input_id: identity },
        "inboxMessage" => {
            let (source_id, message_id) = serde_json::from_str(&identity)?;
            HistorySource::InboxMessage {
                source_id,
                message_id,
            }
        }
        "backgroundResult" => HistorySource::BackgroundResult {
            message_id: identity,
        },
        "operation" => HistorySource::Operation {
            operation_id: identity,
        },
        "receipt" => HistorySource::Receipt {
            receipt_id: identity,
        },
        _ => {
            return Err(HistoryError::Integrity(format!(
                "unsupported schema 24 source kind {kind}"
            )));
        }
    })
}

async fn import_supplements<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    database_id: &str,
    thread_id: &str,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    import_lifecycle(import, source, recorded_at, counts).await?;
    import_turns(import, source, recorded_at, counts).await?;
    import_sources(import, source, recorded_at, counts).await?;
    import_tool_tasks(import, source, recorded_at, counts).await?;
    import_input_identities(import, source, recorded_at, counts).await?;
    import_message_identities(source, counts).await?;
    import_fact_receipts(import, source, thread_id, recorded_at, counts).await?;
    import_costs(import, source, recorded_at, counts).await?;
    import_accounting(import, source, database_id, thread_id, recorded_at, counts).await?;
    Ok(())
}

async fn import_lifecycle<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = source
            .query_all(
                "SELECT identity,kind,source_kind,source_identity,turn_id,attempt_id,call_id,tool_name,text_channel,delivery,source_order,execution_order,started_effect,started_suborder,ended_effect,ended_suborder,started_at,finished_at,outcome,completion_item_id FROM execution_lifecycle WHERE identity>? ORDER BY identity LIMIT 128",
                vec![after.clone().into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let optional_u64 = |name: &str| -> Result<Option<u64>> {
                row.try_get::<Option<i64>>("", name)?
                    .map(|value| db_u64(value, name))
                    .transpose()
            };
            let position = |prefix: &str| -> Result<Option<crate::ChatFactPosition>> {
                let effect = optional_u64(&format!("{prefix}_effect"))?;
                let suborder = row.try_get::<Option<i64>>("", &format!("{prefix}_suborder"))?;
                match (effect, suborder) {
                    (Some(effect), Some(suborder)) => Ok(Some(crate::ChatFactPosition {
                        effect_seq: effect,
                        suborder: u32::try_from(suborder).map_err(|_| {
                            HistoryError::Integrity("schema 24 lifecycle suborder overflows".into())
                        })?,
                    })),
                    (None, None) => Ok(None),
                    (Some(_), None) | (None, Some(_)) => Err(HistoryError::Integrity(
                        "schema 24 lifecycle position is incomplete".into(),
                    )),
                }
            };
            let value = LifecycleRow {
                identity: row.try_get("", "identity")?,
                kind: serde_json::from_str(&row.try_get::<String>("", "kind")?)?,
                source_kind: row.try_get("", "source_kind")?,
                source_identity: row.try_get("", "source_identity")?,
                turn_id: row.try_get("", "turn_id")?,
                attempt_id: row.try_get("", "attempt_id")?,
                call_id: row.try_get("", "call_id")?,
                tool_name: row.try_get("", "tool_name")?,
                text_channel: row
                    .try_get::<Option<String>>("", "text_channel")?
                    .map(|value| serde_json::from_str(&value))
                    .transpose()?,
                delivery: serde_json::from_str(&row.try_get::<String>("", "delivery")?)?,
                source_order: optional_u64("source_order")?,
                execution_order: optional_u64("execution_order")?,
                started: position("started")?,
                ended: position("ended")?,
                started_at: row.try_get("", "started_at")?,
                finished_at: row.try_get("", "finished_at")?,
                outcome: row
                    .try_get::<Option<String>>("", "outcome")?
                    .map(|value| serde_json::from_str(&value))
                    .transpose()?,
                completion_item_id: row.try_get("", "completion_item_id")?,
            };
            after = value.identity.clone();
            if value.completion_item_id.is_some() {
                counts.backup_only("execution_lifecycle_covered_by_original", 1);
                continue;
            }
            let source_id = source_from_parts(&value.source_kind, value.source_identity.clone())?;
            let id = deterministic_event_id(
                "execution_lifecycle",
                &[value.identity.clone().into()],
                "observation",
            );
            // Schema 24 did not persist the runtime epoch that qualifies an
            // attempt. Retain its real evidence in an explicit legacy event
            // rather than inventing a run or publishing an unqualified event.
            let kind = if value.attempt_id.is_some() {
                HistoryEventKind::LegacyObserved
            } else if value.ended.is_some()
                || value.outcome.is_some()
                || value.finished_at.is_some()
            {
                HistoryEventKind::EntityEnded
            } else if value.started.is_some() || value.started_at.is_some() {
                HistoryEventKind::EntityStarted
            } else {
                HistoryEventKind::BoundaryObserved
            };
            let mut event = HistoryEvent::new(id.clone(), kind, recorded_at);
            event.header.entity_id = Some(value.identity.clone());
            event.header.turn_id = value.turn_id.clone();
            event.header.attempt_id = value.attempt_id.clone();
            event.header.source = Some(source_id.clone());
            event.header.call_id = value.call_id.clone();
            event.header.occurred_at = milliseconds(value.finished_at.or(value.started_at))?;
            copy_vector_body(
                import,
                &id,
                "canonical_payload",
                HistoryBodyRole::CanonicalPayload,
                0,
                serde_json::to_vec(&value)?,
            )
            .await?;
            event.payload_body_id = Some(deterministic_body_id(&id, "canonical_payload"));
            import.insert_event(event).await?;
            counts.imported("execution_lifecycle", 1);
        }
    }
    Ok(())
}

fn milliseconds(seconds: Option<i64>) -> Result<Option<i64>> {
    seconds
        .map(|seconds| {
            seconds.checked_mul(1000).ok_or_else(|| {
                HistoryError::Integrity(
                    "schema 24 timestamp overflows the millisecond range".into(),
                )
            })
        })
        .transpose()
}

async fn import_turns<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = 0;
    loop {
        let rows = source
            .query_all(
                "SELECT turn_id,turn_order,length(CAST(payload AS BLOB)) AS payload_bytes,context_disposition FROM history_turns WHERE turn_order>? ORDER BY turn_order LIMIT 128",
                vec![db::number(after)?.into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let payload_bytes = db_u64(
                row.try_get::<i64>("", "payload_bytes")?,
                "history_turns.payload length",
            )?;
            if payload_bytes > pl_core::chat::MAX_READ_BYTES as u64 {
                return Err(HistoryError::Integrity(
                    "schema 24 Turn payload exceeds the existing detail read budget".into(),
                ));
            }
            let turn_id: String = row.try_get("", "turn_id")?;
            let payload = source
                .query_one(
                    "SELECT payload FROM history_turns WHERE turn_id=?",
                    vec![turn_id.clone().into()],
                )
                .await?
                .ok_or_else(|| HistoryError::NotFound(turn_id.clone()))?
                .try_get::<String>("", "payload")?;
            let turn = TurnRow {
                turn_id,
                turn_order: db_u64(
                    row.try_get::<i64>("", "turn_order")?,
                    "history_turns.turn_order",
                )?,
                payload: serde_json::from_str(&payload)?,
                context_disposition: serde_json::from_str(
                    &row.try_get::<String>("", "context_disposition")?,
                )?,
            };
            after = turn.turn_order;
            if turn.turn_id != turn.payload.id {
                return Err(HistoryError::Integrity(
                    "schema 24 Turn identity differs from its payload".into(),
                ));
            }
            let id =
                deterministic_event_id("history_turns", &[turn.turn_id.clone().into()], "anchor");
            let rolled_back =
                turn.context_disposition == crate::ThreadContextDisposition::RolledBack;
            let head = HistoryRowHead::Turn(super::HistoryTurnHead {
                turn_id: turn.payload.id.clone(),
                input_id: turn.payload.input_id.clone(),
                run_id: None,
                state: history_turn_state(&turn.payload.state),
                phase: turn.payload.state.phase(),
                context_disposition: turn.context_disposition,
                queued_at: milliseconds(
                    matches!(turn.payload.state, crate::TurnState::Queued(_))
                        .then_some(turn.payload.updated_at),
                )?,
                started_at: milliseconds(turn.payload.started_at())?,
                finished_at: milliseconds(turn.payload.completed_at())?,
                updated_at: milliseconds(Some(turn.payload.updated_at))?.unwrap_or_default(),
                detail_event_id: None,
            });
            let mut event = HistoryEvent::new(
                id.clone(),
                if rolled_back {
                    HistoryEventKind::TurnRolledBack
                } else {
                    HistoryEventKind::LegacyObserved
                },
                recorded_at,
            );
            event.header.turn_id = Some(turn.payload.id.clone());
            event.header.row_key = Some(format!("turn:{}", turn.payload.id));
            event.is_anchor = true;
            event.head = Some(head);
            copy_column_body(
                import,
                source,
                ColumnBodyRead {
                    table: "history_turns",
                    key_columns: &["turn_id"],
                    key_values: &[&turn.turn_id],
                    column: "payload",
                },
                &id,
                "canonical_payload",
                HistoryBodyRole::CanonicalPayload,
            )
            .await?;
            event.payload_body_id = Some(deterministic_body_id(&id, "canonical_payload"));
            import.insert_event(event).await?;
            counts.imported("turns", 1);
        }
    }
    Ok(())
}

fn history_turn_state(state: &crate::TurnState) -> HistoryTurnState {
    match state {
        crate::TurnState::Queued(_) => HistoryTurnState::Queued,
        crate::TurnState::Running(_) => HistoryTurnState::Running,
        crate::TurnState::Completed(_) => HistoryTurnState::Completed,
        crate::TurnState::Cancelled(_) => HistoryTurnState::Cancelled,
        crate::TurnState::Failed(_) => HistoryTurnState::Failed,
        crate::TurnState::BudgetLimited(_) => HistoryTurnState::BudgetLimited,
    }
}

async fn import_sources<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = source
            .query_all(
                "SELECT source_key,started_effect,ended_effect,active_observed,ended_observed,outcome FROM conversation_sources WHERE source_key>? ORDER BY source_key LIMIT 128",
                vec![after.clone().into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let source_row = SourceRow {
                source_key: row.try_get("", "source_key")?,
                started_effect: row.try_get("", "started_effect")?,
                ended_effect: row.try_get("", "ended_effect")?,
                active_observed: row
                    .try_get::<Option<i64>>("", "active_observed")?
                    .map(|value| db_u64(value, "conversation_sources.active_observed"))
                    .transpose()?,
                outcome: row
                    .try_get::<Option<String>>("", "outcome")?
                    .map(|value| serde_json::from_str(&value))
                    .transpose()?,
            };
            after = source_row.source_key.clone();
            let source_id: HistorySource = serde_json::from_str(&source_row.source_key)?;
            let lifecycle = if let Some(outcome) = source_row.outcome {
                ChatSourceLifecycle::Ended { outcome }
            } else if source_row.started_effect.is_some() || source_row.active_observed.is_some() {
                ChatSourceLifecycle::Active
            } else {
                ChatSourceLifecycle::Unknown
            };
            let kind = match (
                &lifecycle,
                source_row.started_effect,
                source_row.ended_effect,
            ) {
                (ChatSourceLifecycle::Ended { .. }, _, Some(_)) => HistoryEventKind::SourceEnded,
                (ChatSourceLifecycle::Active, Some(_), _) => HistoryEventKind::SourceStarted,
                _ => HistoryEventKind::LegacyObserved,
            };
            let head = HistoryRowHead::Source(super::HistorySourceHead {
                source: source_id.clone(),
                lifecycle,
                // The frozen table stores effect positions, never wall-clock times.
                started_at: None,
                ended_at: None,
                observed_at: None,
                detail_event_id: None,
            });
            let id = deterministic_event_id(
                "conversation_sources",
                &[source_row.source_key.clone().into()],
                "anchor",
            );
            let mut event = HistoryEvent::new(id, kind, recorded_at);
            event.header.source = Some(source_id.clone());
            event.header.row_key = Some(format!("source:{}", serde_json::to_string(&source_id)?));
            event.is_anchor = true;
            event.head = Some(head);
            import.insert_event(event).await?;
            counts.imported("sources", 1);
        }
    }
    Ok(())
}

struct ColumnBodyRead<'a> {
    table: &'static str,
    key_columns: &'static [&'static str],
    key_values: &'a [&'a str],
    column: &'static str,
}

async fn copy_column_body<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    read: ColumnBodyRead<'_>,
    event_id: &str,
    body_key: &str,
    role: HistoryBodyRole,
) -> Result<()> {
    let reader = source
        .column_body(
            read.table,
            read.key_columns,
            read.key_values
                .iter()
                .map(|value| (*value).to_owned())
                .collect(),
            read.column,
        )
        .await?;
    import
        .copy_body(
            HistoryImportBody {
                body_id: deterministic_body_id(event_id, body_key),
                owner_event_id: event_id.to_owned(),
                ordinal: 0,
                body_key: body_key.to_owned(),
                role,
                media_type: None,
            },
            &reader,
        )
        .await?;
    Ok(())
}

async fn import_tool_tasks<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = source
            .query_all(
                "SELECT call_id,revision,task_payload,delivery_payload FROM history_tool_tasks WHERE call_id>? ORDER BY call_id LIMIT 128",
                vec![after.clone().into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let call_id: String = row.try_get("", "call_id")?;
            after = call_id.clone();
            let revision = db_u64(
                row.try_get::<i64>("", "revision")?,
                "history_tool_tasks.revision",
            )?;
            let task: pl_core::thread::task::TaskRecord =
                serde_json::from_str(&row.try_get::<String>("", "task_payload")?)?;
            if task.revision != revision || task.call_id != call_id {
                return Err(HistoryError::Integrity(
                    "schema 24 task row differs from its payload".into(),
                ));
            }
            let delivery = row
                .try_get::<Option<String>>("", "delivery_payload")?
                .map(|payload| serde_json::from_str::<pl_core::thread::ToolDelivery>(&payload))
                .transpose()?;
            let turn_id = task.turn_id.clone();
            if let Some(delivery) = delivery {
                let mut references = BTreeMap::new();
                for reference in crate::studio::thread_projection::resource_references(&delivery)
                    .map_err(|error| HistoryError::Storage(error.into()))?
                {
                    if references
                        .insert(reference.id().to_owned(), reference.clone())
                        .is_some_and(|previous| previous != reference)
                    {
                        return Err(HistoryError::Integrity(
                            "schema 24 tool delivery repeats one resource with conflicting metadata"
                                .into(),
                        ));
                    }
                }
                for reference in references.values() {
                    import_tool_resource_observation(
                        import,
                        reference,
                        &call_id,
                        &turn_id,
                        revision,
                        recorded_at,
                        counts,
                    )
                    .await?;
                }
                let canonical = source
                    .query_one(
                        "SELECT item_id FROM conversation_items \
                         WHERE json_extract(CAST(metadata AS TEXT),'$.tool.callId')=? LIMIT 1",
                        vec![call_id.clone().into()],
                    )
                    .await?;
                if canonical.is_some() {
                    counts.backup_only("history_tool_tasks_covered_by_original", 1);
                    continue;
                }
                let delivery_id = deterministic_event_id(
                    "history_tool_tasks",
                    &[call_id.clone().into()],
                    "delivery",
                );
                let mut delivery_event = HistoryEvent::new(
                    delivery_id.clone(),
                    HistoryEventKind::BackgroundDeliveryRecorded,
                    recorded_at,
                );
                delivery_event.header.entity_id = Some(delivery.call_id.clone());
                delivery_event.header.turn_id = Some(turn_id.clone());
                delivery_event.header.call_id = Some(call_id.clone());
                match &delivery.target {
                    pl_core::thread::ToolDeliveryTarget::CallResult => {
                        delivery_event.header.source =
                            Some(HistorySource::ForegroundTurn { turn_id });
                    }
                    pl_core::thread::ToolDeliveryTarget::Inbox { message_id } => {
                        delivery_event.header.message_id = Some(message_id.clone());
                    }
                    pl_core::thread::ToolDeliveryTarget::Nested { .. } => {}
                }
                copy_column_body(
                    import,
                    source,
                    ColumnBodyRead {
                        table: "history_tool_tasks",
                        key_columns: &["call_id"],
                        key_values: &[&call_id],
                        column: "delivery_payload",
                    },
                    &delivery_id,
                    "canonical_payload",
                    HistoryBodyRole::CanonicalPayload,
                )
                .await?;
                delivery_event.payload_body_id =
                    Some(deterministic_body_id(&delivery_id, "canonical_payload"));
                import.insert_event(delivery_event).await?;
                counts.imported("tool_deliveries", 1);
            } else {
                counts.backup_only("history_tool_tasks", 1);
            }
        }
    }
    Ok(())
}

async fn import_tool_resource_observation<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    reference: &pl_core::context::ResourceReference,
    call_id: &str,
    turn_id: &str,
    effect: u64,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let event_id = deterministic_event_id(
        "history_tool_tasks",
        &[call_id.into(), effect.into(), reference.id().into()],
        "resource",
    );
    // This preserves proof already present in a legacy task; migration does
    // not observe a new business mutation in the current runtime.
    let mut event = HistoryEvent::new(
        event_id.clone(),
        HistoryEventKind::LegacyObserved,
        recorded_at,
    );
    event.header.entity_id = Some(reference.id().into());
    event.header.call_id = Some(call_id.into());
    event.header.turn_id = Some(turn_id.into());
    let payload = opaque_payload(
        "pl.studio.retained-tool-resource",
        serde_json::to_string(reference)?,
    )?;
    import
        .copy_body(
            HistoryImportBody {
                body_id: deterministic_body_id(&event_id, "resource"),
                owner_event_id: event_id.clone(),
                ordinal: 0,
                body_key: "resource".into(),
                role: HistoryBodyRole::CanonicalPayload,
                media_type: Some("application/json".into()),
            },
            &VecSource {
                bytes: serde_json::to_vec(&payload)?,
            },
        )
        .await?;
    event.payload_body_id = Some(deterministic_body_id(&event_id, "resource"));
    import.insert_event(event).await?;
    counts.imported("tool_resources", 1);
    Ok(())
}

async fn import_input_identities<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = source
            .query_all(
                "SELECT item_id,ordinal,revision,digest,presentation,request_digest,payload FROM history_input_identities WHERE item_id>? ORDER BY item_id LIMIT 128",
                vec![after.clone().into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let item_id: String = row.try_get("", "item_id")?;
            after = item_id.clone();
            let ordinal = db_u64(
                row.try_get::<i64>("", "ordinal")?,
                "history_input_identities.ordinal",
            )?;
            let revision = db_u64(
                row.try_get::<i64>("", "revision")?,
                "history_input_identities.revision",
            )?;
            let digest: String = row.try_get("", "digest")?;
            let request_digest: Option<String> = row.try_get("", "request_digest")?;
            let durable = decode_legacy_input_identity(&row.try_get::<String>("", "payload")?)?;
            if durable.id != item_id
                || durable.digest != digest
                || durable.ordinal != ordinal
                || durable.revision != revision
            {
                return Err(HistoryError::Integrity(
                    "schema 24 input identity row conflicts with its payload".into(),
                ));
            }
            let admission = InputAdmission {
                id: durable.id,
                digest: durable.digest,
                request_digest,
                continuation: durable.continuation,
                delivery: durable.delivery,
                purpose: durable.purpose,
                ordinal: durable.ordinal,
                accepted_sequence: durable.accepted_sequence,
                admission_revision: durable.continuation_admission_revision,
                expected_model_route_revision: durable.expected_model_route_revision,
                revision: durable.revision,
                state: durable.state,
            };
            let event_id = format!("legacy:v24:input:{item_id}:accepted");
            let body_id = deterministic_body_id(&event_id, INPUT_FACT_BODY_KEY);
            let (mut event, body) = input_event(
                event_id,
                None,
                recorded_at,
                &InputFact::Admission(admission),
                body_id,
            )?;
            event.bodies.clear();
            let HistoryBody {
                body_id,
                body_key,
                role,
                media_type,
                bytes,
            } = body;
            import
                .copy_body(
                    HistoryImportBody {
                        body_id,
                        owner_event_id: event.header.event_id.clone(),
                        ordinal: 0,
                        body_key,
                        role,
                        media_type,
                    },
                    &VecSource {
                        bytes: bytes.as_ref().to_vec(),
                    },
                )
                .await?;
            import.insert_event(event).await?;
            counts.imported("history_input_identities", 1);
        }
    }
    Ok(())
}

async fn import_message_identities(
    source: &V24HistorySource,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = source
            .query_all(
                "SELECT message_id,item_id FROM history_message_identities WHERE message_id>? ORDER BY message_id LIMIT 128",
                vec![after.clone().into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let message_id: String = row.try_get("", "message_id")?;
            after = message_id.clone();
            let item_id: String = row.try_get("", "item_id")?;
            let covered = source
                .query_one(
                    "SELECT 1 FROM conversation_items WHERE item_id=?",
                    vec![item_id.clone().into()],
                )
                .await?
                .is_some();
            if covered {
                counts.backup_only("history_message_identities_covered_by_original", 1);
            } else {
                counts.backup_only("history_message_identities_identity_only", 1);
            }
        }
    }
    Ok(())
}

async fn import_fact_receipts<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    thread_id: &str,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut pending_reviews = BTreeMap::new();
    if let Some(checkpoint) = source.checkpoint(thread_id).await? {
        for (extension_id, record) in &checkpoint.state.extensions {
            if record.payload.format() != crate::thread_assembler::review_delivery::FACT_FORMAT {
                continue;
            }
            let fact = crate::thread_assembler::review_delivery::ReviewDeliveryFact::decode(
                &record.payload,
            )?;
            if fact.extension_id() != *extension_id
                || pending_reviews
                    .insert(
                        fact.message.id.clone(),
                        pl_core::context::content_hash(record.payload.content().as_bytes()),
                    )
                    .is_some()
            {
                return Err(HistoryError::Integrity(
                    "schema 24 checkpoint has conflicting review delivery obligations".into(),
                ));
            }
        }
    }

    let mut after = (String::new(), 0);
    loop {
        let rows = source
            .query_all(
                "SELECT item_id,revision,kind,digest,payload FROM history_fact_receipts WHERE (item_id,revision)>(?,?) ORDER BY item_id,revision LIMIT 128",
                vec![after.0.clone().into(), db::number(after.1)?.into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let item_id: String = row.try_get("", "item_id")?;
            let revision = db_u64(
                row.try_get::<i64>("", "revision")?,
                "history_fact_receipts.revision",
            )?;
            after = (item_id.clone(), revision);
            let kind: String = row.try_get("", "kind")?;
            let payload = row.try_get::<String>("", "payload")?;
            if pl_core::context::content_hash(payload.as_bytes())
                != row.try_get::<String>("", "digest")?
            {
                return Err(HistoryError::Integrity(
                    "schema 24 fact receipt digest differs from its payload".into(),
                ));
            }
            match kind.as_str() {
                "interaction" | "permission" => {}
                "reviewDeliveryException" => {
                    let durable: crate::thread_assembler::review_delivery::ReviewDeliveryFact =
                        serde_json::from_str(&payload)?;
                    if durable.message.id != item_id {
                        return Err(HistoryError::Integrity(
                            "schema 24 review exception identity differs".into(),
                        ));
                    }
                    let Some(expected_digest) = pending_reviews.get(&item_id) else {
                        counts.backup_only(
                            "history_fact_receipts_review_delivery_already_acknowledged",
                            1,
                        );
                        continue;
                    };
                    if expected_digest != &pl_core::context::content_hash(payload.as_bytes()) {
                        return Err(HistoryError::Integrity(
                            "schema 24 pending review exception differs from its receipt".into(),
                        ));
                    }
                    let id = format!("review_delivery:{item_id}");
                    let opaque = opaque_payload("pl.studio.review-delivery", payload)?;
                    let mut event = HistoryEvent::new(
                        id.clone(),
                        HistoryEventKind::BackgroundDeliveryRecorded,
                        recorded_at,
                    );
                    event.header.entity_id = Some(durable.message.id.clone());
                    event.header.message_id = Some(durable.message.id);
                    event.header.source = Some(crate::studio::history_delivery::source(
                        thread_id,
                        "review_delivery",
                    ));
                    copy_vector_body(
                        import,
                        &id,
                        "business_fact",
                        HistoryBodyRole::CanonicalPayload,
                        0,
                        serde_json::to_vec(&opaque)?,
                    )
                    .await?;
                    event.payload_body_id = Some(deterministic_body_id(&id, "business_fact"));
                    import.insert_event(event).await?;
                    counts.imported("review_deliveries", 1);
                    continue;
                }
                "legacy_execution_record" => {
                    counts.backup_only("history_fact_receipts_legacy_execution_record", 1);
                    continue;
                }
                "displayDelta" => {
                    counts.backup_only("history_fact_receipts_display_delta", 1);
                    continue;
                }
                "digest" => {
                    counts.backup_only("history_fact_receipts_digest", 1);
                    continue;
                }
                "parentReport" => {
                    counts.backup_only("history_fact_receipts_parent_report", 1);
                    continue;
                }
                _ => {
                    counts.backup_only("history_fact_receipts_unsupported", 1);
                    continue;
                }
            }
            let business_id = match kind.as_str() {
                "interaction" => {
                    let durable: pl_core::thread::interactions::InteractionRecord =
                        serde_json::from_str(&payload)?;
                    durable.request.id
                }
                "permission" => {
                    let durable: pl_core::thread::permissions::PermissionRecord =
                        serde_json::from_str(&payload)?;
                    durable.id
                }
                _ => unreachable!("review receipts continue before business import"),
            };
            if business_id.is_empty() {
                return Err(HistoryError::Integrity(
                    "schema 24 business receipt identity is empty".into(),
                ));
            }
            if source
                .query_one(
                    "SELECT 1 FROM conversation_items \
                     WHERE json_extract(CAST(metadata AS TEXT),'$.id')=? LIMIT 1",
                    vec![business_id.clone().into()],
                )
                .await?
                .is_some()
            {
                counts.backup_only("history_fact_receipts_covered_by_original", 1);
                continue;
            }
            let id = deterministic_event_id(
                "history_fact_receipts",
                &[item_id.clone().into(), revision.into()],
                &kind,
            );
            let mut event =
                HistoryEvent::new(id.clone(), HistoryEventKind::LegacyObserved, recorded_at);
            event.header.entity_id = Some(business_id);
            event.header.source = Some(HistorySource::Receipt {
                receipt_id: item_id.clone(),
            });
            copy_column_body(
                import,
                source,
                ColumnBodyRead {
                    table: "history_fact_receipts",
                    key_columns: &["item_id", "revision"],
                    key_values: &[&item_id, &revision.to_string()],
                    column: "payload",
                },
                &id,
                "canonical_payload",
                HistoryBodyRole::CanonicalPayload,
            )
            .await?;
            event.payload_body_id = Some(deterministic_body_id(&id, "canonical_payload"));
            import.insert_event(event).await?;
            counts.imported(
                match kind.as_str() {
                    "interaction" => "interaction_facts",
                    "permission" => "permission_facts",
                    _ => unreachable!("review receipts continue before business import"),
                },
                1,
            );
        }
    }
    Ok(())
}

async fn import_costs<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = (String::new(), String::new());
    loop {
        let rows = source
            .query_all(
                "SELECT purpose,currency,amount FROM session_costs WHERE (purpose,currency)>(?,?) ORDER BY purpose,currency LIMIT 128",
                vec![after.0.clone().into(), after.1.clone().into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let purpose_json: String = row.try_get("", "purpose")?;
            let currency: String = row.try_get("", "currency")?;
            after = (purpose_json.clone(), currency.clone());
            let amount = row.try_get::<f64>("", "amount")?;
            if !amount.is_finite() || amount < 0.0 {
                return Err(HistoryError::Integrity("invalid schema 24 cost".into()));
            }
            let purpose: Option<String> = serde_json::from_str(&purpose_json)?;
            let head = super::HistoryCostHead {
                purpose: purpose.clone(),
                currency: currency.clone(),
                cost_delta: None,
                cost_total: amount,
                cache_savings_delta: None,
                cache_savings_total: None,
                updated_at: 0,
                detail_event_id: None,
            };
            let row_key = head.row_key()?;
            let id = deterministic_event_id(
                "session_costs",
                &[purpose_json.into(), currency.clone().into()],
                "total",
            );
            let mut event = HistoryEvent::new(id, HistoryEventKind::LegacyObserved, recorded_at);
            event.header.row_key = Some(row_key);
            event.is_anchor = true;
            event.head = Some(HistoryRowHead::Cost(head));
            import.insert_event(event).await?;
            counts.imported("costs", 1);
        }
    }
    Ok(())
}

async fn import_accounting<C: ConnectionTrait>(
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    _database_id: &str,
    thread_id: &str,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let Some(checkpoint) = source.checkpoint(thread_id).await? else {
        return Ok(());
    };
    let summary = checkpoint.state.usage_summary.clone();
    let head = super::HistoryAccountingHead {
        prompt_tokens: summary.totals.prompt_tokens,
        completion_tokens: summary.totals.completion_tokens,
        cached_prompt_tokens: summary.totals.cached_prompt_tokens,
        cache_write_tokens: summary.totals.cache_write_tokens,
        reasoning_tokens: summary.totals.reasoning_tokens,
        inference_count: summary.totals.inference_count,
        total_tokens: summary.totals.total_tokens,
        cache_usage: super::CacheUsageSummary {
            sample_count: summary.cache.sample_count,
            legacy_sample_count_unknown: false,
            input_tokens: summary.cache.input_tokens,
            cache_read_tokens: summary.cache.read_tokens,
            hit_rate: None,
            has_incomplete_usage: summary.cache.incomplete,
        },
        has_incomplete_usage: summary.has_incomplete_usage(),
        has_unpriced_usage: summary.pricing.incomplete,
        updated_at: 0,
        detail_event_id: None,
    };
    let id = deterministic_event_id("session_checkpoint", &["accounting".into()], "anchor");
    let mut event = HistoryEvent::new(id, HistoryEventKind::LegacyObserved, recorded_at);
    event.header.row_key = Some("accounting:session".into());
    event.is_anchor = true;
    event.head = Some(HistoryRowHead::Accounting(head));
    import.insert_event(event).await?;
    counts.imported("accounting", 1);
    Ok(())
}

async fn import_display<C: ConnectionTrait>(
    connection: &C,
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    database_id: &str,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = 0;
    loop {
        let rows = source
            .query_all(
                "SELECT block_id,block_order,sealed FROM conversation_display_blocks WHERE block_order>? ORDER BY block_order LIMIT 128",
                vec![db::number(after)?.into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let block_id: String = row.try_get("", "block_id")?;
            let block_order = db_u64(
                row.try_get::<i64>("", "block_order")?,
                "conversation_display_blocks.block_order",
            )?;
            after = block_order;
            let header_bytes = read_legacy_product_blob(
                source,
                "conversation_display_blocks",
                "block_id",
                &block_id,
                "header",
            )
            .await?;
            let header: DisplayHeader = serde_json::from_slice(&header_bytes)?;
            if header.version != 5
                || header.id != block_id
                || header.block_order.get() != block_order
            {
                return Err(HistoryError::Integrity(
                    "schema 24 display block identity differs".into(),
                ));
            }
            match header.body {
                v24_display::DisplayBlockBody::Work { timing, .. } => {
                    let member_count = source
                        .query_one(
                            "SELECT count(*) AS count FROM conversation_display_members WHERE block_id=?",
                            vec![block_id.clone().into()],
                        )
                        .await?
                        .ok_or_else(|| HistoryError::Integrity("display member count failed".into()))?;
                    let member_count = db_u64(
                        member_count.try_get::<i64>("", "count")?,
                        "conversation_display_members count",
                    )?;
                    let execution_present = source
                        .query_one(
                            "SELECT 1 FROM conversation_display_members WHERE block_id=? AND json_extract(metadata,'$.head.record.atom.kind') IN ('toolCall','inference','reasoning') LIMIT 1",
                            vec![block_id.clone().into()],
                        )
                        .await?
                        .is_some();
                    let head = HistoryWorkHead {
                        group_id: block_id.clone(),
                        run_id: None,
                        started_at: milliseconds(timing.started_at)?,
                        boundary_at: milliseconds(timing.finished_at)?,
                        closed: header.sealed,
                        member_count,
                        unfinished_count: header.unfinished,
                        execution_present,
                        summary: None,
                    };
                    let id = deterministic_event_id(
                        "conversation_display_blocks",
                        &[block_id.clone().into()],
                        "work-anchor",
                    );
                    let mut event =
                        HistoryEvent::new(id, HistoryEventKind::LegacyObserved, recorded_at);
                    event.header.group_id = Some(block_id.clone());
                    event.header.row_key = Some(format!("work:{block_id}"));
                    event.is_anchor = true;
                    event.head = Some(HistoryRowHead::Work(head));
                    import.insert_event(event).await?;
                    counts.imported("display_work_anchors", 1);
                    import_work_members(
                        connection,
                        import,
                        source,
                        database_id,
                        &block_id,
                        recorded_at,
                        counts,
                    )
                    .await?;
                }
                v24_display::DisplayBlockBody::Single { record, visibility } => {
                    let members = source
                        .query_all(
                            "SELECT member_order,member_key FROM conversation_display_members WHERE block_id=? LIMIT 2",
                            vec![block_id.clone().into()],
                        )
                        .await?;
                    match members.as_slice() {
                        [] => {}
                        [row] => {
                            let member = read_display_member(source, &block_id, row).await?;
                            if &member.head.record != record.as_ref() {
                                return Err(HistoryError::Integrity(
                                    "schema 24 Single member differs from its display record"
                                        .into(),
                                ));
                            }
                            counts.backup_only("display_single_members", 1);
                        }
                        _ => {
                            return Err(HistoryError::Integrity(
                                "schema 24 Single has more than one member".into(),
                            ));
                        }
                    }
                    let id = deterministic_event_id(
                        "conversation_display_blocks",
                        &[block_id.clone().into()],
                        "single-anchor",
                    );
                    import_entity_anchor(
                        connection,
                        import,
                        EntityAnchorImport {
                            source,
                            database_id,
                            event_id: &id,
                            group_id: None,
                            atom: record.atom,
                            visibility: Some(visibility),
                            content_source: record.content_source,
                            recorded_at,
                        },
                        counts,
                    )
                    .await?;
                }
            }
        }
    }
    Ok(())
}

async fn import_work_members<C: ConnectionTrait>(
    connection: &C,
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
    database_id: &str,
    block_id: &str,
    recorded_at: i64,
    counts: &mut ImportCounts,
) -> Result<()> {
    let mut after = 0;
    loop {
        let rows = source
            .query_all(
                "SELECT member_order,member_key FROM conversation_display_members WHERE block_id=? AND member_order>? ORDER BY member_order LIMIT 128",
                vec![block_id.into(), db::number(after)?.into()],
            )
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let member = read_display_member(source, block_id, &row).await?;
            after = member.head.member_order;
            let expected_id = display_member_event_id(block_id, &member.head.member_key);
            import_entity_anchor(
                connection,
                import,
                EntityAnchorImport {
                    source,
                    database_id,
                    event_id: &expected_id,
                    group_id: Some(block_id),
                    atom: member.head.record.atom,
                    visibility: None,
                    content_source: member.head.record.content_source,
                    recorded_at,
                },
                counts,
            )
            .await?;
        }
    }
    Ok(())
}

async fn read_display_member(
    source: &V24HistorySource,
    block_id: &str,
    row: &sea_orm::QueryResult,
) -> Result<DisplayMemberWrite> {
    let member_order = db_u64(
        row.try_get::<i64>("", "member_order")?,
        "conversation_display_members.member_order",
    )?;
    let member_key: String = row.try_get("", "member_key")?;
    let member_bytes = read_legacy_product_blob(
        source,
        "conversation_display_members",
        "member_key",
        &member_key,
        "metadata",
    )
    .await?;
    let member: DisplayMemberWrite = serde_json::from_slice(&member_bytes)?;
    if member.block_id != block_id
        || member.head.member_key != member_key
        || member.head.member_order != member_order
        || member.association_key.is_empty()
        || member.terminal
            != matches!(
                &member.head.record.atom.lifecycle,
                ChatAtomLifecycle::Terminal { .. }
            )
    {
        return Err(HistoryError::Integrity(
            "schema 24 display member identity or order differs".into(),
        ));
    }
    Ok(member)
}

struct EntityAnchorImport<'a> {
    source: &'a V24HistorySource,
    database_id: &'a str,
    event_id: &'a str,
    group_id: Option<&'a str>,
    atom: ChatAtom,
    visibility: Option<v24_display::SingleVisibility>,
    content_source: v24_display::DisplayContentSource,
    recorded_at: i64,
}

async fn import_entity_anchor<C: ConnectionTrait>(
    connection: &C,
    import: &mut HistoryImport<'_, C>,
    import_plan: EntityAnchorImport<'_>,
    counts: &mut ImportCounts,
) -> Result<()> {
    let EntityAnchorImport {
        source,
        database_id,
        event_id,
        group_id,
        atom,
        visibility,
        content_source,
        recorded_at,
    } = import_plan;
    let observation = match &content_source {
        v24_display::DisplayContentSource::CompletedOriginal { .. } => HistoryObservation::Original,
        v24_display::DisplayContentSource::FrozenObservation {
            captured_at,
            available: true,
        } => HistoryObservation::Boundary {
            captured_at: milliseconds(*captured_at)?,
        },
        v24_display::DisplayContentSource::FrozenObservation {
            captured_at,
            available: false,
        } => HistoryObservation::UnavailableLegacy {
            captured_at: milliseconds(*captured_at)?,
        },
        v24_display::DisplayContentSource::CurrentAtom => {
            // A live atom is not a captured history body. Its references can
            // outlive the draft that owned them.
            counts.backup_only("display_current_atom_material", 1);
            HistoryObservation::UnavailableLegacy { captured_at: None }
        }
    };
    let frozen_payload = matches!(
        &content_source,
        v24_display::DisplayContentSource::FrozenObservation {
            available: true,
            ..
        }
    );
    if frozen_payload {
        let Some(PayloadData::Deferred { reference, .. }) = &atom.payload else {
            return Err(HistoryError::Integrity(
                "schema 24 frozen observation has no captured payload".into(),
            ));
        };
        validate_typed_reference(reference, database_id)?;
        let ContentTarget::Body {
            owner:
                ContentOwner::DisplayObservation {
                    block_id,
                    member_key,
                },
            key,
        } = &reference.target
        else {
            return Err(HistoryError::Integrity(
                "schema 24 frozen observation payload is not display-owned".into(),
            ));
        };
        let expected_event = display_member_event_id(block_id, member_key);
        if expected_event != event_id
            || group_id.is_some_and(|actual| actual != block_id.as_str())
            || key != "display.payload"
        {
            return Err(HistoryError::Integrity(
                "schema 24 frozen observation payload owner differs".into(),
            ));
        }
        let owner_key = crate::studio::content_owner_key(&ContentOwner::DisplayObservation {
            block_id: block_id.clone(),
            member_key: member_key.clone(),
        })
        .map_err(|error| HistoryError::Storage(error.into()))?;
        let mut staged_payload = StagedPayload::from_body(
            connection,
            source,
            V24Body::Content {
                owner_key: owner_key.as_str().to_owned(),
                content_key: key.clone(),
            },
        )
        .await?;
        staged_payload
            .rewrite_declarations(source, database_id, event_id, None)
            .await?;
        for content in &atom.contents {
            validate_typed_reference(&content.reference, database_id)?;
            payload_reference(connection, &content.reference, database_id, event_id).await?;
        }
        import
            .copy_body(
                HistoryImportBody {
                    body_id: deterministic_body_id(event_id, "canonical_payload"),
                    owner_event_id: event_id.to_owned(),
                    ordinal: 0,
                    body_key: "canonical_payload".into(),
                    role: HistoryBodyRole::CanonicalPayload,
                    media_type: Some("application/json".into()),
                },
                &staged_payload,
            )
            .await?;
    }
    let completed = atom.completion_item_id.clone();
    let original_completion = match &content_source {
        v24_display::DisplayContentSource::CompletedOriginal { completion_id } => {
            Some(completion_id.clone())
        }
        _ => None,
    };
    if let (Some(atom_id), Some(source_id)) = (&completed, &original_completion)
        && atom_id != source_id
    {
        return Err(HistoryError::Integrity(
            "schema 24 display original names another completion".into(),
        ));
    }
    let entity_turn_id = atom.turn_id.clone();
    let mut head = HistoryEntityHead::from_atom(&atom, None)?;
    if matches!(
        content_source,
        v24_display::DisplayContentSource::CurrentAtom
    ) && matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
    {
        // A tool can have finished producing a draft while its plan still awaits a decision.
        head.finished_at = None;
    }
    let boundary_observation = matches!(&observation, HistoryObservation::Boundary { .. });
    head.observation = observation;
    match &head.observation {
        HistoryObservation::Original => {
            let completion = original_completion.ok_or_else(|| {
                HistoryError::Integrity(
                    "schema 24 completed display source has no completion identity".into(),
                )
            })?;
            head.detail_event_id = Some(completion.clone());
            head.input_manifest_event_id = Some(completion.clone());
            head.body_manifest_event_id = Some(completion);
        }
        HistoryObservation::Boundary { .. } => {
            head.detail_event_id = Some(event_id.to_owned());
            head.input_manifest_event_id = None;
            head.body_manifest_event_id = Some(event_id.to_owned());
        }
        HistoryObservation::UnavailableLegacy { .. } => {
            head.detail_event_id = Some(event_id.to_owned());
            head.input_manifest_event_id = None;
            head.body_manifest_event_id = None;
        }
    }
    head.single_visibility = visibility.map(single_visibility);
    let first_content_ordinal = u64::from(frozen_payload);
    fit_entity_head(
        import,
        &mut head,
        event_id,
        database_id,
        first_content_ordinal,
    )
    .await?;
    if frozen_payload {
        copy_planned_bodies(connection, import, source).await?;
        for content in &atom.contents {
            let plan =
                payload_reference(connection, &content.reference, database_id, event_id).await?;
            import.validate_body_reference(&plan).await?;
        }
    }
    let kind = match &head.observation {
        HistoryObservation::UnavailableLegacy { .. } | HistoryObservation::Original => {
            HistoryEventKind::LegacyObserved
        }
        HistoryObservation::Boundary { .. } => HistoryEventKind::BoundaryObserved,
    };
    let mut event = HistoryEvent::new(event_id.to_owned(), kind, recorded_at);
    event.header.run_id = head.run_id.clone();
    event.header.attempt_id = head.attempt_id.clone();
    event.header.entity_id = Some(head.entity_id.clone());
    event.header.turn_id = entity_turn_id;
    event.header.source = Some(head.source.clone());
    event.header.call_id = head.tool.as_ref().map(|tool| tool.call_id.clone());
    event.header.occurred_at = event_time(&atom)?;
    event.header.group_id = group_id.map(str::to_owned);
    // Separate published observations can share the same logical entity.
    // The legacy anchor ID is derived from the original block and member identities.
    event.header.row_key = Some(event_id.to_owned());
    event.is_anchor = true;
    event.head = Some(if group_id.is_some() {
        HistoryRowHead::Member(head)
    } else {
        HistoryRowHead::Single(head)
    });
    event.payload_body_id =
        frozen_payload.then(|| deterministic_body_id(event_id, "canonical_payload"));
    import.insert_event(event).await?;
    if group_id.is_some() {
        counts.imported("display_member_anchors", 1);
    } else {
        counts.imported("display_single_anchors", 1);
    }
    if boundary_observation {
        counts.imported("display_boundary_observations", 1);
    }
    Ok(())
}

fn single_visibility(value: v24_display::SingleVisibility) -> HistorySingleVisibility {
    match value {
        v24_display::SingleVisibility::Content => HistorySingleVisibility::Content,
        v24_display::SingleVisibility::FinalEmptyAfterContent => {
            HistorySingleVisibility::FinalEmptyAfterContent
        }
    }
}

async fn verify_import(
    tx: &impl ConnectionTrait,
    source: &V24HistorySource,
    database_id: &str,
    canonical_count: u64,
) -> Result<()> {
    let row = tx
        .query_one_raw(statement(
            "SELECT count(*) AS count FROM history_events WHERE query_class IS NOT NULL",
            Vec::new(),
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("canonical count failed".into()))?;
    if db_u64(
        row.try_get::<i64>("", "count")?,
        "canonical history_events count",
    )? != canonical_count
    {
        return Err(HistoryError::Integrity(
            "canonical original count differs after import".into(),
        ));
    }

    let mut source_after = 0;
    let mut target_after = 0;
    loop {
        let source_page = source.originals_page(source_after, 128).await?;
        let target_page = canonical_event_page(tx, target_after, 128).await?;
        if source_page.len() != target_page.len() {
            return Err(HistoryError::Integrity(
                "canonical original page count or order differs".into(),
            ));
        }
        if source_page.is_empty() {
            break;
        }
        for (original, imported) in source_page.iter().zip(&target_page) {
            if original.item_id != imported.1 {
                return Err(HistoryError::Integrity(
                    "canonical original identity or order differs".into(),
                ));
            }
        }
        source_after = source_page.last().expect("nonempty page").seq;
        target_after = target_page.last().expect("nonempty page").0;
    }
    verify_display_order(tx, source).await?;

    let invalid_directory = tx
        .query_one_raw(statement(
            "SELECT owner_event_id FROM history_bodies GROUP BY owner_event_id HAVING count(*)<>max(ordinal)+1 OR min(ordinal)<>0 LIMIT 1",
            Vec::new(),
        ))
        .await?;
    if invalid_directory.is_some() {
        return Err(HistoryError::Integrity(
            "imported body directory has gaps".into(),
        ));
    }
    let invalid_chunk = tx
        .query_one_raw(statement(
            "SELECT body_id FROM history_body_chunks GROUP BY body_id HAVING count(*)<>max(chunk_no)+1 OR min(chunk_no)<>0 LIMIT 1",
            Vec::new(),
        ))
        .await?;
    if invalid_chunk.is_some() {
        return Err(HistoryError::Integrity(
            "imported body chunks have gaps".into(),
        ));
    }
    let invalid_chunk_length = tx
        .query_one_raw(statement(
            "SELECT c.body_id FROM history_body_chunks AS c JOIN history_bodies AS b ON b.body_id=c.body_id WHERE c.chunk_no*65536>=b.byte_length OR length(c.data)<>min(65536,b.byte_length-c.chunk_no*65536) LIMIT 1",
            Vec::new(),
        ))
        .await?;
    if invalid_chunk_length.is_some() {
        return Err(HistoryError::Integrity(
            "imported body chunk lengths differ from their body headers".into(),
        ));
    }
    let missing_chunks = tx
        .query_one_raw(statement(
            "SELECT body_id FROM history_bodies AS b WHERE byte_length>0 AND NOT EXISTS(SELECT 1 FROM history_body_chunks AS c WHERE c.body_id=b.body_id) LIMIT 1",
            Vec::new(),
        ))
        .await?;
    if missing_chunks.is_some() {
        return Err(HistoryError::Integrity(
            "nonempty imported body has no chunks".into(),
        ));
    }

    verify_row_heads(tx, database_id).await?;
    verify_canonical_metadata(tx, database_id).await?;
    verify_legacy_metadata(tx, database_id).await?;
    for check in ["PRAGMA quick_check", "PRAGMA foreign_key_check"] {
        let rows = tx.query_all_raw(statement(check, Vec::new())).await?;
        if check == "PRAGMA quick_check" {
            for row in rows {
                if row.try_get_by_index::<String>(0)? != "ok" {
                    return Err(HistoryError::Integrity(
                        "imported history quick_check failed".into(),
                    ));
                }
            }
        } else if !rows.is_empty() {
            return Err(HistoryError::Integrity(
                "imported history foreign keys differ".into(),
            ));
        }
    }
    Ok(())
}

async fn canonical_event_page(
    tx: &impl ConnectionTrait,
    after: u64,
    limit: u32,
) -> Result<Vec<(u64, String)>> {
    tx
        .query_all_raw(statement(
            "SELECT seq,event_id FROM history_events WHERE query_class IS NOT NULL AND seq>? ORDER BY seq LIMIT ?",
            vec![db::number(after)?.into(), i64::from(limit).into()],
        ))
        .await?
        .into_iter()
        .map(|row| {
            Ok::<(u64, String), HistoryError>((
                db_u64(row.try_get::<i64>("", "seq")?, "history_events.seq")?,
                row.try_get("", "event_id")?,
            ))
        })
        .collect::<std::result::Result<Vec<_>, _>>()
}

async fn verify_display_order(tx: &impl ConnectionTrait, source: &V24HistorySource) -> Result<()> {
    let mut source_after = 0;
    let mut target_after = 0;
    let mut source_members = 0u64;
    loop {
        let source_page = source
            .query_all(
                "SELECT block_id,block_order,json_extract(header,'$.body.kind') AS body_kind FROM conversation_display_blocks WHERE block_order>? ORDER BY block_order LIMIT 128",
                vec![db::number(source_after)?.into()],
            )
            .await?;
        let target_page = tx
            .query_all_raw(statement(
                "SELECT seq,event_id FROM history_events WHERE is_anchor=1 AND row_scope IN ('work','single') AND seq>? ORDER BY seq LIMIT 128",
                vec![db::number(target_after)?.into()],
            ))
            .await?;
        if source_page.len() != target_page.len() {
            return Err(HistoryError::Integrity(
                "main display anchor count or order differs".into(),
            ));
        }
        if source_page.is_empty() {
            break;
        }
        for (row, target) in source_page.iter().zip(&target_page) {
            let block_order = db_u64(
                row.try_get::<i64>("", "block_order")?,
                "conversation_display_blocks.block_order",
            )?;
            source_after = block_order;
            let block_id: String = row.try_get("", "block_id")?;
            let body_kind: String = row.try_get("", "body_kind")?;
            let role = if body_kind == "work" {
                "work-anchor"
            } else {
                if body_kind != "single" {
                    return Err(HistoryError::Integrity(
                        "schema 24 display block has an unsupported body kind".into(),
                    ));
                }
                "single-anchor"
            };
            let expected_main = deterministic_event_id(
                "conversation_display_blocks",
                &[block_id.clone().into()],
                role,
            );
            if target.try_get::<String>("", "event_id")? != expected_main {
                return Err(HistoryError::Integrity(
                    "main display anchor identity or order differs".into(),
                ));
            }
            if body_kind != "work" {
                continue;
            }
            let expected = verify_member_order(tx, source, &block_id).await?;
            source_members = source_members
                .checked_add(expected)
                .ok_or_else(|| HistoryError::Integrity("member count overflow".into()))?;
        }
        target_after = db_u64(
            target_page
                .last()
                .expect("nonempty page")
                .try_get::<i64>("", "seq")?,
            "history_events.seq",
        )?;
    }
    let target_members = db_u64(
        tx.query_one_raw(statement(
            "SELECT count(*) AS count FROM history_events WHERE is_anchor=1 AND row_scope='member'",
            Vec::new(),
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("imported member total failed".into()))?
        .try_get::<i64>("", "count")?,
        "imported member count",
    )?;
    let orphan = source
        .query_one(
            "SELECT 1 FROM conversation_display_members member
             LEFT JOIN conversation_display_blocks block ON block.block_id=member.block_id
             WHERE block.block_id IS NULL LIMIT 1",
            Vec::new(),
        )
        .await?;
    if orphan.is_some() || source_members != target_members {
        return Err(HistoryError::Integrity(
            "member display anchors contain a missing or extra group".into(),
        ));
    }
    Ok(())
}

async fn verify_member_order(
    tx: &impl ConnectionTrait,
    source: &V24HistorySource,
    block_id: &str,
) -> Result<u64> {
    let mut source_after = 0;
    let mut target_after = 0;
    let mut count = 0u64;
    loop {
        let source_page = source
            .query_all(
                "SELECT member_order,member_key FROM conversation_display_members WHERE block_id=? AND member_order>? ORDER BY member_order LIMIT 128",
                vec![block_id.into(), db::number(source_after)?.into()],
            )
            .await?;
        let target_page = tx
            .query_all_raw(statement(
                "SELECT seq,event_id FROM history_events WHERE is_anchor=1 AND row_scope='member' AND group_id=? AND seq>? ORDER BY seq LIMIT 128",
                vec![block_id.into(), db::number(target_after)?.into()],
            ))
            .await?;
        if source_page.len() != target_page.len() {
            return Err(HistoryError::Integrity(
                "member display anchor count or order differs".into(),
            ));
        }
        if source_page.is_empty() {
            break;
        }
        for (source_row, target_row) in source_page.iter().zip(&target_page) {
            source_after = db_u64(
                source_row.try_get::<i64>("", "member_order")?,
                "conversation_display_members.member_order",
            )?;
            target_after = db_u64(target_row.try_get::<i64>("", "seq")?, "history_events.seq")?;
            let member_key: String = source_row.try_get("", "member_key")?;
            if target_row.try_get::<String>("", "event_id")?
                != display_member_event_id(block_id, &member_key)
            {
                return Err(HistoryError::Integrity(
                    "member display anchor identity or order differs".into(),
                ));
            }
            count = count
                .checked_add(1)
                .ok_or_else(|| HistoryError::Integrity("member count overflow".into()))?;
        }
    }
    Ok(count)
}

async fn verify_row_heads(tx: &impl ConnectionTrait, database_id: &str) -> Result<()> {
    let mut after = 0;
    loop {
        let rows = tx
            .query_all_raw(statement(
                "SELECT seq,head_json FROM history_events WHERE head_json IS NOT NULL AND seq>? ORDER BY seq LIMIT 128",
                vec![db::number(after)?.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = db_u64(row.try_get::<i64>("", "seq")?, "history_events.seq")?;
            let head: HistoryRowHead =
                serde_json::from_str(&row.try_get::<String>("", "head_json")?)?;
            verify_row_head(tx, database_id, &head).await?;
        }
    }
    Ok(())
}

async fn verify_canonical_metadata(tx: &impl ConnectionTrait, database_id: &str) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = tx
            .query_all_raw(statement(
                "SELECT owner_event_id,body_id,byte_length FROM history_bodies WHERE role='canonical_metadata' AND owner_event_id>? ORDER BY owner_event_id LIMIT 128",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "owner_event_id")?;
            let body_id: String = row.try_get("", "body_id")?;
            let length = db_u64(
                row.try_get::<i64>("", "byte_length")?,
                "history_bodies.byte_length",
            )?;
            if length > HEAD_MAX_BYTES as u64 {
                return Err(HistoryError::Integrity(
                    "canonical typed metadata exceeds the history head limit".into(),
                ));
            }
            let bytes = read_body_at_most(tx, &body_id, length, HEAD_MAX_BYTES).await?;
            let head: HistoryEntityHead = serde_json::from_slice(&bytes)?;
            verify_entity_head(tx, database_id, &head).await?;
        }
    }
    Ok(())
}

async fn verify_legacy_metadata(tx: &impl ConnectionTrait, database_id: &str) -> Result<()> {
    let mut after = String::new();
    loop {
        let rows = tx
            .query_all_raw(statement(
                "SELECT body_id,byte_length FROM history_bodies WHERE role='legacy_metadata' AND body_id>? ORDER BY body_id LIMIT 128",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            after = row.try_get("", "body_id")?;
            let body_id: String = after.clone();
            let length = db_u64(
                row.try_get::<i64>("", "byte_length")?,
                "history_bodies.byte_length",
            )?;
            let bytes =
                read_body_at_most(tx, &body_id, length, pl_core::chat::MAX_READ_BYTES).await?;
            let head: HistoryEntityHead = serde_json::from_slice(&bytes)?;
            verify_entity_head(tx, database_id, &head).await?;
        }
    }
    Ok(())
}

async fn read_body_at_most(
    tx: &impl ConnectionTrait,
    body_id: &str,
    length: u64,
    max_length: usize,
) -> Result<Vec<u8>> {
    if length > max_length as u64 {
        return Err(HistoryError::Integrity(
            "typed history body exceeds its product-container budget".into(),
        ));
    }
    let chunks = length.div_ceil(BODY_CHUNK_BYTES as u64);
    let capacity = usize::try_from(length)
        .map_err(|_| HistoryError::Integrity("head body length exceeds usize".into()))?;
    let mut bytes = Vec::with_capacity(capacity);
    for offset in 0..chunks {
        let chunk = tx
            .query_one_raw(statement(
                "SELECT data FROM history_body_chunks WHERE body_id=? AND chunk_no=?",
                vec![body_id.into(), db::number(offset)?.into()],
            ))
            .await?
            .ok_or_else(|| {
                HistoryError::Integrity(format!("head body {body_id} has a chunk gap"))
            })?;
        let data: Vec<u8> = chunk.try_get("", "data")?;
        bytes.extend_from_slice(&data);
    }
    if bytes.len() != capacity {
        return Err(HistoryError::Integrity(
            "head body chunks exceed their declared length".into(),
        ));
    }
    Ok(bytes)
}

async fn verify_row_head(
    tx: &impl ConnectionTrait,
    database_id: &str,
    head: &HistoryRowHead,
) -> Result<()> {
    match head {
        HistoryRowHead::Single(head) | HistoryRowHead::Member(head) => {
            verify_entity_head(tx, database_id, head).await
        }
        HistoryRowHead::Turn(head) => {
            verify_optional_event(tx, head.detail_event_id.as_deref()).await
        }
        HistoryRowHead::Source(head) => {
            verify_optional_event(tx, head.detail_event_id.as_deref()).await
        }
        HistoryRowHead::Cost(head) => {
            verify_optional_event(tx, head.detail_event_id.as_deref()).await
        }
        HistoryRowHead::Accounting(head) => {
            verify_optional_event(tx, head.detail_event_id.as_deref()).await
        }
        HistoryRowHead::Work(_) => Ok(()),
    }
}

async fn verify_entity_head(
    tx: &impl ConnectionTrait,
    database_id: &str,
    head: &HistoryEntityHead,
) -> Result<()> {
    for id in [
        head.detail_event_id.as_deref(),
        head.input_manifest_event_id.as_deref(),
        head.body_manifest_event_id.as_deref(),
    ]
    .into_iter()
    .flatten()
    {
        verify_optional_event(tx, Some(id)).await?;
    }
    if let Some(HistoryWaitHead::Deferred { presentation, .. }) = &head.wait {
        verify_body_reference(tx, database_id, presentation).await?;
    }
    Ok(())
}

async fn verify_optional_event(tx: &impl ConnectionTrait, event_id: Option<&str>) -> Result<()> {
    let Some(event_id) = event_id else {
        return Ok(());
    };
    if tx
        .query_one_raw(statement(
            "SELECT 1 FROM history_events WHERE event_id=?",
            vec![event_id.into()],
        ))
        .await?
        .is_none()
    {
        return Err(HistoryError::Integrity(format!(
            "display head references missing event {event_id}"
        )));
    }
    Ok(())
}

async fn verify_body_reference(
    tx: &impl ConnectionTrait,
    database_id: &str,
    reference: &HistoryEventBodyRef,
) -> Result<()> {
    let row = tx
        .query_one_raw(statement(
            "SELECT owner_event_id,body_key,byte_length FROM history_bodies WHERE body_id=?",
            vec![reference.body_id.clone().into()],
        ))
        .await?
        .ok_or_else(|| {
            HistoryError::Integrity(format!(
                "typed head references missing body {}",
                reference.body_id
            ))
        })?;
    let body_length = db_u64(
        row.try_get::<i64>("", "byte_length")?,
        "history_bodies.byte_length",
    )?;
    if reference.database_id != database_id
        || row.try_get::<String>("", "owner_event_id")? != reference.owner_event_id
        || row.try_get::<String>("", "body_key")? != reference.body_key
        || reference.byte_start != 0
        || reference
            .byte_start
            .checked_add(reference.byte_length)
            .is_none_or(|end| end > body_length)
    {
        return Err(HistoryError::Integrity(
            "typed head body reference differs from its immutable body".into(),
        ));
    }
    Ok(())
}

async fn verify_display_tables_are_gone(tx: &impl ConnectionTrait) -> Result<()> {
    for table in [
        "conversation_display_blocks",
        "conversation_display_members",
        "conversation_items",
        "conversation_contents",
        "conversation_content_chunks",
        "history_meta",
        "session_checkpoint",
        "current_context",
    ] {
        if tx
            .query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
                vec![table.into()],
            ))
            .await?
            .is_some()
        {
            return Err(HistoryError::Integrity(format!(
                "retired history table {table} survived migration"
            )));
        }
    }
    Ok(())
}

async fn drop_legacy_tables(tx: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    for (index, table) in [
        "conversation_display_members",
        "conversation_display_blocks",
        "conversation_content_chunks",
        "conversation_contents",
        "conversation_items",
        "timeline_records",
        "completion_boundary_archive_content_chunks",
        "completion_boundary_archive_contents",
        "completion_boundary_archive_view_entries",
        "completion_boundary_archive_view_state",
        "completion_boundary_archive_timeline_members",
        "completion_boundary_archive_timeline_items",
        "completion_boundary_archive_projection_state",
        "execution_lifecycle",
        "history_turns",
        "conversation_sources",
        "history_tool_tasks",
        "history_input_identities",
        "history_message_identities",
        "history_fact_receipts",
        "session_costs",
        "current_context",
        "session_checkpoint",
        "history_meta",
    ]
    .into_iter()
    .chain(LEGACY_WORK_SNAPSHOT_ARCHIVES.iter().copied())
    .enumerate()
    {
        tx.execute_raw(statement(
            &format!("DROP TABLE IF EXISTS {table}"),
            Vec::new(),
        ))
        .await?;
        if index == 0 {
            fail_ddl_once(thread_id)?;
        }
    }
    verify_display_tables_are_gone(tx).await?;
    let rows = tx
        .query_all_raw(statement(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            Vec::new(),
        ))
        .await?;
    for row in rows {
        let name: String = row.try_get("", "name")?;
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
                "unknown table {name} survived migration"
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn schema26_read_coexists_with_its_live_history_writer() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = crate::history::HistoryStore::open(
            &path,
            "live-writer",
            crate::history::HistoryLimits::default(),
        )
        .await?;
        let report = upgrade_history(&path, "live-writer", directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::AlreadySchema26);
        assert_eq!(report.database_id, store.database_id());
        assert!(!directory.path().join(BACKUP_ROOT).try_exists()?);
        assert!(!directory.path().join(BACKUP_ROOT_V25_TO_V26).try_exists()?);
        assert!(!directory.path().join("current.json").try_exists()?);

        let reader = store.reader();
        let page = reader
            .timeline_page(None, None, crate::history::HistoryDemand::default())
            .await?;
        assert!(page.items.is_empty());
        reader.close().await;
        let accepted = store
            .accept_batch(&[crate::history::HistoryEvent::new(
                "run-still-writable",
                crate::history::HistoryEventKind::RunStarted,
                crate::history::HistoryTimelineRole::Hidden,
                1,
            )])
            .await?;
        assert_eq!(accepted, [1]);
        store.flush().await?;
        store.close().await?;
        Ok(())
    }

    #[test]
    fn millisecond_conversion_rejects_overflow() {
        assert_eq!(milliseconds(Some(2)).unwrap(), Some(2_000));
        assert!(milliseconds(Some(i64::MAX)).is_err());
        assert_eq!(milliseconds(None).unwrap(), None);
    }
}

#[cfg(test)]
mod migration_tests {
    use std::sync::Arc;

    use super::*;
    use crate::history::{
        HistoryBusinessRowHead, HistoryDelivery, HistoryEntityKind, HistoryEntityState,
        HistoryEventKind as CurrentHistoryEventKind, HistoryTimelineItem, HistoryToolIdentity,
        body, decode_event_envelope, read_event_body_bytes,
    };
    use crate::studio::storage::history::schema::v24_presentation::BlockOrder;
    use crate::studio::storage::history::schema::v24_presentation_types as v24_display;
    use crate::thread_assembler::{
        agent_review::review_message_id,
        review_delivery::{
            DeliveryExceptionOutcome, DeliveryExceptionReason, DeliveryObservation,
            ReviewDeliveryException, ReviewDeliveryFact,
        },
    };
    use crate::{
        AttachmentModality, ChatAtom, ChatAtomContent, ChatClassFilter, ChatContentRole, ChatScope,
        ChatSourceId, ContentOwner, PayloadData, ThreadContentLifecycle, ThreadContextDisposition,
        ThreadTextChannel, ThreadTextItem, Turn,
    };
    use crate::{
        ExecutionItem, ExecutionShape,
        history::{
            HistoryDemand, HistoryEventsQuery, HistoryLimits, HistoryStore as CurrentHistoryStore,
        },
        resource_store::FileResourceStore,
    };
    use pl_core::{
        context::{
            ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
            content_hash,
        },
        thread::{
            ThreadCheckpoint, ThreadLifecycle, ThreadSnapshot, ToolDelivery, ToolDeliveryTarget,
            ToolOutcome,
            extensions::ExtensionRecord,
            task::{TaskRecord, TaskStatus},
        },
        tool::ToolOutput,
    };
    use sea_orm::ConnectionTrait;

    const INLINE_BODY: &[u8] = b"legacy inline body\x00\xff";

    struct V24Fixture {
        database_id: String,
        large_id: String,
        empty_id: String,
        large_body: Vec<u8>,
        empty_body: Vec<u8>,
        host_body: Vec<u8>,
        resource_id: String,
        resource_body: Vec<u8>,
        pending_review_id: Option<String>,
        acknowledged_review_id: Option<String>,
        canonical_payloads: BTreeMap<String, Vec<u8>>,
    }

    fn text_item(thread_id: &str, id: &str, ordinal: u64, body: &str) -> ExecutionItem {
        ExecutionItem::new(
            id.into(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Borrowed("turn-1"),
                ordinal,
                revision: 1,
                created_at: 1,
                updated_at: 2,
            },
            ExecutionShape::Text(ThreadTextItem::new(
                ThreadTextChannel::Final,
                body.into(),
                vec![],
                ThreadContentLifecycle::completed(2),
            )),
        )
    }

    async fn write_v24_fixture(
        history_path: &Path,
        thread_id: &str,
        include_checkpoint_and_display: bool,
    ) -> Result<V24Fixture> {
        let large_text = format!("large-{}-{}", "正文".repeat(BODY_CHUNK_BYTES), "tail");
        let large_body = large_text.clone().into_bytes();
        let empty_body = Vec::new();
        let host_body = (0..=255u8)
            .cycle()
            .take(BODY_CHUNK_BYTES + 123)
            .collect::<Vec<_>>();
        let items = [
            text_item(thread_id, "original-large", 1, &large_text),
            text_item(thread_id, "original-empty", 2, ""),
        ];
        // The published schema-24 preparer still owns table shape. Completions are
        // frozen in memory and inserted directly, so this fixture does not open the
        // retired HistoryStore or run its effect writer.
        let db = schema::connect(history_path, false, true).await?;
        let (database_id, _) = crate::studio::storage::history::schema::initialize(&db, thread_id)
            .await
            .map_err(HistoryError::Storage)?;
        let completions = items
            .iter()
            .enumerate()
            .map(|(index, item)| {
                let draft = crate::studio::runtime::chat_item::completion_draft(
                    item,
                    1,
                    &database_id,
                    None,
                )?;
                let append_seq = u64::try_from(index)
                    .ok()
                    .and_then(|offset| offset.checked_add(1))
                    .ok_or_else(|| {
                        HistoryError::Integrity("fixture completion sequence overflow".into())
                    })?;
                Ok(Arc::new(pl_core::chat::ChatItem::complete(
                    draft, append_seq,
                )))
            })
            .collect::<Result<Vec<_>>>()?;
        let execution_order = items.iter().map(|item| item.ordinal).max().unwrap_or(0);
        for completion in &completions {
            let header = &completion.header;
            db.execute_raw(statement(
                "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(?,?,?,?,?,?)",
                vec![
                    db::number(header.append_seq)?.into(),
                    header.item_id.clone().into(),
                    header.query_class.clone().into(),
                    header
                        .parent_id
                        .as_ref()
                        .map(|key| key.as_str().to_owned())
                        .into(),
                    completion.payload.to_vec().into(),
                    header.metadata.to_vec().into(),
                ],
            ))
            .await?;
        }
        db.execute_raw(statement(
            "UPDATE history_meta SET applied_write_seq=?,execution_order=MAX(execution_order,?) WHERE id=1",
            vec![
                db::number(1)?.into(),
                db::number(execution_order)?.into(),
            ],
        ))
        .await?;
        if completions.len() != items.len() {
            return Err(HistoryError::Integrity(
                "legacy fixture completion count differs".into(),
            ));
        }
        let metadata = db
            .query_one_raw(statement(
                "SELECT schema_version,database_id,applied_write_seq FROM history_meta WHERE id=1",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("fixture identity is missing".into()))?;
        if metadata.try_get::<i64>("", "schema_version")? != 24 {
            return Err(HistoryError::Integrity(
                "legacy fixture did not stop at schema 24".into(),
            ));
        }
        let database_id: String = metadata.try_get("", "database_id")?;
        // The published format keeps its pre-schema-12 container alongside
        // adopted canonical originals. This is independent frozen input data.
        let old_payload = serde_json::to_string(&serde_json::json!({
            "itemId":"original-large", "appendSeq":1, "turnId":"turn-1",
            "sourceEffectSeq":null, "sealedAt":null,
            "meta":serde_json::to_vec(&serde_json::json!({
                "id":"original-large", "threadId":thread_id, "turnId":"turn-1",
                "descriptor":{"kind":"text","data":{"legacyOpaque":"保留原容器"}}
            }))?,
            "fields":[{"identity":{"kind":"body"},"text":large_text}]
        }))?;
        db.execute_raw(statement(
            "INSERT INTO timeline_records(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload) VALUES(1,'original-large','turn-1',NULL,NULL,'text',?)",
            vec![old_payload.into()],
        )).await?;
        let applied = db_u64(
            metadata.try_get::<i64>("", "applied_write_seq")?,
            "history_meta.applied_write_seq",
        )?;
        if applied != 1 {
            return Err(HistoryError::Integrity(
                "legacy fixture watermark differs".into(),
            ));
        }

        let resource_body = b"retained resource bytes".to_vec();
        let resources = FileResourceStore::new(
            history_path
                .parent()
                .ok_or_else(|| HistoryError::NotFound("fixture parent".into()))?
                .join("resources"),
        );
        let resource = resources
            .retain_bytes(
                Arc::from(resource_body.as_slice()),
                "application/octet-stream",
            )
            .await
            .map_err(|error| HistoryError::Storage(error.into()))?;
        let attached =
            pl_model::runtime::attachment_content(resource.clone(), AttachmentModality::Image)
                .map_err(|error| HistoryError::Storage(error.into()))?;
        let resource_task = TaskRecord {
            id: "task:resource-call".into(),
            parent_call_id: None,
            invocation: None,
            call_id: "resource-call".into(),
            tool_id: "resource-tool".into(),
            turn_id: "turn-1".into(),
            revision: 1,
            status: TaskStatus::Succeeded,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(1),
        };
        let resource_delivery = ToolDelivery {
            target: ToolDeliveryTarget::CallResult,
            call_id: "resource-call".into(),
            tool_id: "resource-tool".into(),
            output: ToolOutput::new(OpaquePayload::text("resource result"), Vec::new()),
            delivered_context: vec![attached],
            outcome: ToolOutcome::Succeeded,
        };
        db.execute_raw(statement(
            "INSERT INTO history_tool_tasks(
                call_id,revision,task_payload,delivery_payload,last_write_seq
             ) VALUES(?,?,?,?,?)",
            vec![
                resource_task.call_id.clone().into(),
                db::number(resource_task.revision)?.into(),
                serde_json::to_string(&resource_task)?.into(),
                serde_json::to_string(&resource_delivery)?.into(),
                db::number(applied)?.into(),
            ],
        ))
        .await?;
        let backup_only_task = TaskRecord {
            id: "task:task-only".into(),
            parent_call_id: None,
            invocation: None,
            call_id: "task-only".into(),
            tool_id: "task-only-tool".into(),
            turn_id: "turn-1".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(2),
        };
        db.execute_raw(statement(
            "INSERT INTO history_tool_tasks(
                call_id,revision,task_payload,delivery_payload,last_write_seq
             ) VALUES(?,?,?,NULL,?)",
            vec![
                backup_only_task.call_id.clone().into(),
                db::number(backup_only_task.revision)?.into(),
                serde_json::to_string(&backup_only_task)?.into(),
                db::number(applied)?.into(),
            ],
        ))
        .await?;

        let (pending_review, pending_review_id, acknowledged_review_id): (
            Option<ReviewDeliveryFact>,
            Option<String>,
            Option<String>,
        ) = if include_checkpoint_and_display {
            let pending = ReviewDeliveryException {
                reviewer_id: thread_id.into(),
                turn_id: "review-turn-pending".into(),
                input_id: None,
                terminal_sequence: 5,
                target_agent_id: "parent".into(),
                feedback_message_id: review_message_id(thread_id, "review-turn-pending", 5),
                observation: DeliveryObservation::Reconciliation,
                outcome: DeliveryExceptionOutcome::Rejected {
                    reason: DeliveryExceptionReason::IdentityConflict,
                },
            }
            .into_fact()?;
            let acknowledged = ReviewDeliveryException {
                reviewer_id: thread_id.into(),
                turn_id: "review-turn-acknowledged".into(),
                input_id: None,
                terminal_sequence: 6,
                target_agent_id: "parent".into(),
                feedback_message_id: review_message_id(thread_id, "review-turn-acknowledged", 6),
                observation: DeliveryObservation::Reconciliation,
                outcome: DeliveryExceptionOutcome::Rejected {
                    reason: DeliveryExceptionReason::IdentityConflict,
                },
            }
            .into_fact()?;
            for fact in [&pending, &acknowledged] {
                let payload = serde_json::to_string(fact)?;
                db.execute_raw(statement(
                    "INSERT INTO history_fact_receipts(
                        item_id,revision,kind,digest,payload,last_write_seq
                     ) VALUES(?,1,'reviewDeliveryException',?,?,?)",
                    vec![
                        fact.message.id.clone().into(),
                        content_hash(payload.as_bytes()).into(),
                        payload.into(),
                        db::number(applied)?.into(),
                    ],
                ))
                .await?;
            }
            (
                Some(pending.clone()),
                Some(pending.message.id),
                Some(acknowledged.message.id),
            )
        } else {
            (None, None, None)
        };

        let mut canonical_payloads = BTreeMap::new();
        let mut atoms = BTreeMap::new();
        let bodies = BTreeMap::from([
            ("original-large".to_owned(), large_body.as_slice()),
            ("original-empty".to_owned(), empty_body.as_slice()),
        ]);
        for completion in &completions {
            let item_id = completion.header.item_id.clone();
            let body = *bodies
                .get(&item_id)
                .ok_or_else(|| HistoryError::NotFound(item_id.clone()))?;
            let owner = ContentOwner::Item {
                item_id: item_id.clone(),
            };
            let owner_key = crate::studio::content_owner_key(&owner)
                .map_err(|error| HistoryError::Storage(error.into()))?;
            let manifest = serde_json::to_vec(&serde_json::json!({
                "byteLength": body.len() as u64,
                "generation": 1,
                "sealed": true,
                "mediaType": "text/plain"
            }))?;
            db.execute_raw(statement(
                "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key='body'",
                vec![owner_key.as_str().into()],
            ))
            .await?;
            db.execute_raw(statement(
                "INSERT INTO conversation_contents(owner_key,content_key,payload) VALUES(?,'body',?)
                 ON CONFLICT(owner_key,content_key) DO UPDATE SET payload=excluded.payload",
                vec![owner_key.as_str().into(), manifest.into()],
            ))
            .await?;
            // Deliberately differ from the new 64 KiB writer boundary.
            for (index, chunk) in body.chunks(4_099).enumerate() {
                db.execute_raw(statement(
                    "INSERT INTO conversation_content_chunks(owner_key,content_key,byte_offset,data)
                     VALUES(?,'body',?,?)",
                    vec![
                        owner_key.as_str().into(),
                        i64::try_from(index * 4_099).map_err(|_| {
                            HistoryError::Integrity("fixture chunk offset overflow".into())
                        })?.into(),
                        chunk.to_vec().into(),
                    ],
                ))
                .await?;
            }

            let source_payload = if item_id == "original-large" {
                let host_manifest = serde_json::to_vec(&serde_json::json!({
                    "byteLength": host_body.len() as u64,
                    "generation": 1,
                    "sealed": true,
                    "mediaType": "application/octet-stream"
                }))?;
                db.execute_raw(statement(
                    "DELETE FROM conversation_content_chunks \
                     WHERE owner_key=? AND content_key='tool.output-artifacts'",
                    vec![owner_key.as_str().into()],
                ))
                .await?;
                db.execute_raw(statement(
                    "INSERT INTO conversation_contents(owner_key,content_key,payload) \
                     VALUES(?,'tool.output-artifacts',?) \
                     ON CONFLICT(owner_key,content_key) DO UPDATE SET payload=excluded.payload",
                    vec![owner_key.as_str().into(), host_manifest.into()],
                ))
                .await?;
                for (index, chunk) in host_body.chunks(4_099).enumerate() {
                    db.execute_raw(statement(
                        "INSERT INTO conversation_content_chunks(\
                             owner_key,content_key,byte_offset,data\
                         ) VALUES(?,'tool.output-artifacts',?,?)",
                        vec![
                            owner_key.as_str().into(),
                            i64::try_from(index * 4_099)
                                .map_err(|_| {
                                    HistoryError::Integrity("fixture offset overflow".into())
                                })?
                                .into(),
                            chunk.to_vec().into(),
                        ],
                    ))
                    .await?;
                }
                let host_reference = crate::ContentRef {
                    database_id: database_id.clone(),
                    target: crate::ContentTarget::Body {
                        owner: owner.clone(),
                        key: "tool.output-artifacts".into(),
                    },
                };
                let mut payload: serde_json::Value = serde_json::from_slice(&completion.payload)?;
                payload["bodies"]
                    .as_array_mut()
                    .ok_or_else(|| HistoryError::Integrity("fixture payload has no bodies".into()))?
                    .extend([
                        serde_json::json!({
                            "key": "tool.output-artifacts",
                            "byteLength": host_body.len(),
                            "reference": host_reference
                        }),
                        serde_json::json!({
                            "key": "inline-preview",
                            "byteLength": INLINE_BODY.len(),
                            "inline": INLINE_BODY
                        }),
                    ]);
                serde_json::to_vec(&payload)?
            } else {
                completion.payload.to_vec()
            };

            let mut atom: ChatAtom = serde_json::from_slice(&completion.header.metadata)?;
            atom.content_present = Some(true);
            atom.source_order = Some(if item_id == "original-large" { 1 } else { 2 });
            atom.contents = vec![ChatAtomContent {
                role: ChatContentRole::Body,
                reference: crate::ContentRef {
                    database_id: database_id.clone(),
                    target: crate::ContentTarget::Body {
                        owner: owner.clone(),
                        key: "body".into(),
                    },
                },
            }];
            db.execute_raw(statement(
                "UPDATE conversation_items SET payload=?,metadata=? WHERE item_id=?",
                vec![
                    source_payload.clone().into(),
                    serde_json::to_vec(&atom)?.into(),
                    item_id.clone().into(),
                ],
            ))
            .await?;
            canonical_payloads.insert(item_id.clone(), source_payload);
            atoms.insert(item_id, atom);
        }

        db.execute_raw(statement(
            "DELETE FROM history_turns WHERE turn_id='turn-rollback'",
            Vec::new(),
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO history_turns(
                turn_id,turn_order,admitted_effect,updated_effect,terminal_effect,payload,context_disposition
             ) VALUES(?,?,NULL,NULL,NULL,?,?)",
            vec![
                "turn-rollback".into(),
                50i64.into(),
                serde_json::to_string(&Turn::queued("turn-rollback", thread_id, 1))?.into(),
                serde_json::to_string(&ThreadContextDisposition::RolledBack)?.into(),
            ],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO session_costs(purpose,currency,amount) VALUES(?,?,?)",
            vec![
                serde_json::to_string(&Some("chat"))?.into(),
                "USD".into(),
                1.25f64.into(),
            ],
        ))
        .await?;

        if include_checkpoint_and_display {
            let context_record = ContextRecord {
                id: "context-1".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![ContextContent::Text {
                    text: Arc::from("cold context"),
                }],
                tool_calls: Vec::new(),
            };
            let mut state = ThreadSnapshot {
                commit_sequence: applied,
                context: ContextSnapshot {
                    revision: 1,
                    records: Vec::<ContextRecord>::new().into(),
                },
                ..Default::default()
            };
            if let Some(fact) = &pending_review {
                state.extensions.insert(
                    fact.extension_id(),
                    ExtensionRecord {
                        revision: 1,
                        payload: fact.encode()?,
                    },
                );
                state.extension_sequence = 1;
            }
            let checkpoint = ThreadCheckpoint {
                schema_version: ThreadCheckpoint::SCHEMA_VERSION,
                thread_id: thread_id.into(),
                state_revision: applied,
                history_fence: applied,
                saved_at: 1,
                external_bodies: Vec::new(),
                state,
            };
            let checkpoint_payload = serde_json::to_string(&checkpoint)?;
            db.execute_raw(statement("DELETE FROM session_checkpoint", Vec::new()))
                .await?;
            db.execute_raw(statement("DELETE FROM current_context", Vec::new()))
                .await?;
            db.execute_raw(statement(
                "INSERT INTO session_checkpoint(
                    id,revision,context_revision,context_count,payload,payload_hash
                 ) VALUES(1,?,?,1,?,?)",
                vec![
                    db::number(applied)?.into(),
                    1i64.into(),
                    checkpoint_payload.clone().into(),
                    content_hash(checkpoint_payload.as_bytes()).into(),
                ],
            ))
            .await?;
            let context_payload = serde_json::to_string(&context_record)?;
            db.execute_raw(statement(
                "INSERT INTO current_context(ordinal,record_id,payload,payload_hash)
                 VALUES(0,?,?,?)",
                vec![
                    context_record.id.clone().into(),
                    context_payload.clone().into(),
                    content_hash(context_payload.as_bytes()).into(),
                ],
            ))
            .await?;

            let block_id = "work-1";
            let source = ChatSourceId::ForegroundTurn {
                turn_id: "turn-1".into(),
            };
            let header = serde_json::to_vec(&DisplayHeader {
                version: 5,
                id: block_id.into(),
                source: source.clone(),
                block_order: BlockOrder::try_from(1)?,
                boundary: None,
                first_content_at: None,
                sealed: true,
                unfinished: 0,
                next_member: 3,
                revision: 1,
                thinking_summary: None,
                body: v24_display::DisplayBlockBody::Work {
                    timing: v24_display::WorkTiming {
                        started_at: Some(1),
                        finished_at: Some(2),
                    },
                    members: v24_display::DisplayBlockRef {
                        database_id: database_id.clone(),
                        block_id: block_id.into(),
                    },
                },
            })?;
            db.execute_raw(statement(
                "INSERT INTO conversation_display_blocks(
                    block_id,source_key,block_order,sealed,updated_effect,header
                 ) VALUES(?,?,1,1,1,?)",
                vec![
                    block_id.into(),
                    serde_json::to_string(&source)?.into(),
                    header.into(),
                ],
            ))
            .await?;

            let mut frozen_atom = atoms["original-large"].clone();
            frozen_atom.completion_item_id = None;
            frozen_atom.completion_seq = None;
            let observation_owner = ContentOwner::DisplayObservation {
                block_id: block_id.into(),
                member_key: "member-1".into(),
            };
            let observation_owner_key = crate::studio::content_owner_key(&observation_owner)
                .map_err(|error| HistoryError::Storage(error.into()))?;
            let observation_body = b"frozen body \xF0\x9F\xA6\x80";
            let body_reference = crate::ContentRef {
                database_id: database_id.clone(),
                target: crate::ContentTarget::Body {
                    owner: observation_owner.clone(),
                    key: "body".into(),
                },
            };
            let observation_payload = serde_json::to_vec(&serde_json::json!({
                "contract":"anywork.chat/1",
                "type":"text",
                "data":{"kind":"text","data":{"text":"frozen"}},
                "capturedAt":2,
                "turnId":"turn-1",
                "bodies":[{
                    "key":"body",
                    "byteLength":observation_body.len() as u64,
                    "reference":body_reference
                }]
            }))?;
            for (content_key, bytes) in [
                ("body", observation_body.to_vec()),
                ("display.payload", observation_payload.clone()),
            ] {
                let manifest = serde_json::to_vec(&serde_json::json!({
                    "byteLength": bytes.len() as u64,
                    "generation": 1,
                    "sealed": true,
                    "mediaType": if content_key == "body" {
                        "application/octet-stream"
                    } else {
                        "application/json"
                    }
                }))?;
                db.execute_raw(statement(
                    "INSERT INTO conversation_contents(owner_key,content_key,payload)
                     VALUES(?,?,?)",
                    vec![
                        observation_owner_key.as_str().into(),
                        content_key.into(),
                        manifest.into(),
                    ],
                ))
                .await?;
                for (index, chunk) in bytes.chunks(4_099).enumerate() {
                    db.execute_raw(statement(
                        "INSERT INTO conversation_content_chunks(
                             owner_key,content_key,byte_offset,data
                         ) VALUES(?,?,?,?)",
                        vec![
                            observation_owner_key.as_str().into(),
                            content_key.into(),
                            i64::try_from(index * 4_099)
                                .map_err(|_| {
                                    HistoryError::Integrity("fixture offset overflow".into())
                                })?
                                .into(),
                            chunk.to_vec().into(),
                        ],
                    ))
                    .await?;
                }
            }
            frozen_atom.contents = vec![ChatAtomContent {
                role: ChatContentRole::Body,
                reference: body_reference,
            }];
            frozen_atom.payload = Some(PayloadData::Deferred {
                reference: crate::ContentRef {
                    database_id: database_id.clone(),
                    target: crate::ContentTarget::Body {
                        owner: observation_owner,
                        key: "display.payload".into(),
                    },
                },
                byte_length: observation_payload.len() as u64,
            });
            let records = [
                (
                    "member-1",
                    1i64,
                    None::<String>,
                    v24_display::DisplayContentSource::FrozenObservation {
                        captured_at: Some(2),
                        available: true,
                    },
                    frozen_atom,
                ),
                (
                    "member-2",
                    2i64,
                    Some("original-empty".into()),
                    v24_display::DisplayContentSource::CompletedOriginal {
                        completion_id: "original-empty".into(),
                    },
                    atoms["original-empty"].clone(),
                ),
            ];
            for (member_key, member_order, completion_id, content_source, atom) in records {
                let head = v24_display::DisplayMemberHead {
                    member_key: member_key.into(),
                    member_order: u64::try_from(member_order).map_err(|_| {
                        HistoryError::Integrity("fixture member order is negative".into())
                    })?,
                    record: v24_display::DisplayRecord {
                        atom,
                        start_fact: None,
                        end_fact: None,
                        content_source,
                    },
                };
                let metadata = serde_json::to_vec(&DisplayMemberWrite {
                    block_id: block_id.into(),
                    association_key: member_key.into(),
                    terminal: true,
                    head,
                })?;
                db.execute_raw(statement(
                    "INSERT INTO conversation_display_members(
                        terminal,completion_id,association_key,updated_effect,metadata,
                        block_id,member_order,member_key
                     ) VALUES(1,?,?,1,?,?,?,?)",
                    vec![
                        completion_id.into(),
                        member_key.into(),
                        metadata.into(),
                        block_id.into(),
                        member_order.into(),
                        member_key.into(),
                    ],
                ))
                .await?;
            }
        }
        db.close().await?;
        Ok(V24Fixture {
            database_id,
            large_id: "original-large".into(),
            empty_id: "original-empty".into(),
            large_body,
            empty_body,
            host_body,
            resource_id: resource.id().to_owned(),
            resource_body,
            pending_review_id,
            acknowledged_review_id,
            canonical_payloads,
        })
    }

    async fn read_all_body(
        reader: &crate::history::HistoryReader,
        reference: HistoryEventBodyRef,
    ) -> Result<Vec<u8>> {
        let mut bytes = Vec::new();
        let mut offset = 0;
        while offset < reference.byte_length {
            let window = reader
                .read_body(reference.clone(), offset, BODY_CHUNK_BYTES as u32)
                .await?;
            if window.bytes.is_empty() {
                return Err(HistoryError::Integrity(
                    "history body stopped before its declared length".into(),
                ));
            }
            offset += window.bytes.len() as u64;
            bytes.extend_from_slice(&window.bytes);
        }
        Ok(bytes)
    }

    async fn schema_version(path: &Path) -> Result<i64> {
        let db = schema::connect(path, true, false).await?;
        let version = db
            .query_one_raw(statement(
                "SELECT schema_version FROM history_meta WHERE id=1",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("source identity was lost".into()))?
            .try_get::<i64>("", "schema_version")?;
        db.close().await?;
        Ok(version)
    }

    async fn event_count(path: &Path) -> Result<i64> {
        let db = schema::connect(path, true, false).await?;
        let count = db
            .query_one_raw(statement(
                "SELECT count(*) AS count FROM history_events",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("history event count failed".into()))?
            .try_get::<i64>("", "count")?;
        db.close().await?;
        Ok(count)
    }

    async fn upgrade_published_snapshot(version: i64, fail_once: bool) -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "published-snapshot";
        let record = ContextRecord {
            id: "saved-user-input".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![ContextContent::Text {
                text: Arc::from("Preserve the saved context"),
            }],
            tool_calls: Vec::new(),
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            context: ContextSnapshot {
                revision: 1,
                records: vec![record].into(),
            },
            ..Default::default()
        };
        let checkpoint = ThreadCheckpoint::capture(thread_id.into(), 1, state.clone())
            .map_err(|error| HistoryError::Storage(error.into()))?;
        let db = schema::connect(&path, false, true).await?;
        crate::studio::storage::history::schema::seed_pre24_fixture(&db, version, &checkpoint)
            .await
            .map_err(HistoryError::Storage)?;
        let identity = read_legacy_identity(&db).await?;
        assert_eq!(identity.version, version);
        if fail_once {
            let before = db
                .query_one_raw(statement("SELECT payload FROM session_checkpoint", vec![]))
                .await?
                .unwrap()
                .try_get::<String>("", "payload")?;
            db.execute_unprepared(
                "CREATE TRIGGER reject_schema24 BEFORE UPDATE OF schema_version ON history_meta
                 WHEN NEW.schema_version=24 BEGIN SELECT RAISE(ABORT,'reject schema24'); END;",
            )
            .await?;
            let error = upgrade_history(&path, thread_id, directory.path())
                .await
                .unwrap_err();
            assert!(format!("{error:#}").contains("reject schema24"));
            assert!(read_legacy_identity(&db).await? == identity);
            let after = db
                .query_one_raw(statement("SELECT payload FROM session_checkpoint", vec![]))
                .await?
                .unwrap()
                .try_get::<String>("", "payload")?;
            assert_eq!(after, before);
            assert!(!directory.path().join("current.json").exists());
            db.execute_unprepared("DROP TRIGGER reject_schema24")
                .await?;
        }
        db.close().await?;

        let report = upgrade_history(&path, thread_id, directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::Upgraded);
        assert_eq!(report.database_id, identity.database_id);
        let current = ThreadCurrent::from_json(
            &tokio::fs::read(directory.path().join("current.json")).await?,
            thread_id,
        )
        .map_err(|error| HistoryError::Storage(error.into()))?;
        assert_eq!(current.state.context, state.context);
        assert!(current.state.execution.is_none());
        let store = CurrentHistoryStore::open(&path, thread_id, HistoryLimits::default()).await?;
        assert_eq!(store.reader().database_id(), identity.database_id);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn published_schema_eight_restores_through_schema26() -> Result<()> {
        upgrade_published_snapshot(8, false).await
    }

    #[tokio::test]
    async fn published_schema_seventeen_restores_through_schema26() -> Result<()> {
        upgrade_published_snapshot(17, false).await
    }

    #[tokio::test]
    async fn published_schema_twenty_three_restores_through_schema26() -> Result<()> {
        upgrade_published_snapshot(23, false).await
    }

    #[tokio::test]
    async fn published_schema_twenty_three_rolls_back_before_retry() -> Result<()> {
        upgrade_published_snapshot(23, true).await
    }

    #[tokio::test]
    async fn unadopted_legacy_original_stops_upgrade_without_discarding_its_bytes() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-unadopted-original";
        write_v24_fixture(&history_path, thread_id, false).await?;
        let payload = serde_json::to_string(&serde_json::json!({
            "itemId":"unadopted-original", "appendSeq":2, "turnId":"turn-1",
            "sourceEffectSeq":null, "sealedAt":null,
            "meta":serde_json::to_vec(&serde_json::json!({
                "id":"unadopted-original", "threadId":thread_id, "turnId":"turn-1",
                "descriptor":{"kind":"text","data":{}}
            }))?,
            "fields":[{"identity":{"kind":"body"},"text":"unique original bytes"}]
        }))?;
        let db = schema::connect(&history_path, false, false).await?;
        db.execute_raw(statement(
            "INSERT INTO timeline_records(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload) VALUES(2,'unadopted-original','turn-1',NULL,NULL,'text',?)",
            vec![payload.clone().into()],
        )).await?;
        db.close().await?;
        let error = upgrade_history(&history_path, thread_id, directory.path())
            .await
            .expect_err("an original without a canonical adoption cannot be discarded");
        assert!(error.to_string().contains("absent from conversation_items"));
        assert_eq!(schema_version(&history_path).await?, 24);
        let source = schema::connect(&history_path, true, false).await?;
        let original = source
            .query_one_raw(statement(
                "SELECT payload FROM timeline_records WHERE record_id='unadopted-original'",
                Vec::new(),
            ))
            .await?
            .expect("original container is retained");
        assert_eq!(original.try_get::<String>("", "payload")?, payload);
        source.close().await?;
        Ok(())
    }

    async fn write_live_single_fixture(db: &DatabaseConnection, database_id: &str) -> Result<()> {
        let bytes: Vec<u8> = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_items WHERE item_id='original-large'",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get_by_index(0)?;
        let mut atom: ChatAtom = serde_json::from_slice(&bytes)?;
        atom.id = "draft-plan".into();
        atom.completion_item_id = None;
        atom.completion_seq = None;
        atom.kind = crate::ChatAtomKind::Plan;
        atom.lifecycle = ChatAtomLifecycle::Active {
            started: None,
            status: crate::ChatActiveStatus::Waiting,
        };
        atom.finished_at = Some(2);
        atom.payload = None;
        atom.contents = vec![ChatAtomContent {
            role: ChatContentRole::ToolArguments,
            reference: ContentRef {
                database_id: database_id.into(),
                target: ContentTarget::Body {
                    owner: ContentOwner::Item {
                        item_id: atom.id.clone(),
                    },
                    key: "tool.arguments".into(),
                },
            },
        }];
        let record = v24_display::DisplayRecord {
            atom,
            start_fact: None,
            end_fact: None,
            content_source: v24_display::DisplayContentSource::CurrentAtom,
        };
        for (order, block_id) in [(2, "single-plan"), (3, "later-plan-observation")] {
            let header = DisplayHeader {
                version: 5,
                id: block_id.into(),
                source: record.atom.source.clone(),
                block_order: BlockOrder::try_from(order)?,
                boundary: None,
                first_content_at: None,
                sealed: false,
                unfinished: 1,
                next_member: 1,
                revision: 1,
                thinking_summary: None,
                body: v24_display::DisplayBlockBody::Single {
                    record: Box::new(record.clone()),
                    visibility: v24_display::SingleVisibility::Content,
                },
            };
            let member = DisplayMemberWrite {
                block_id: header.id.clone(),
                association_key: block_id.into(),
                terminal: false,
                head: v24_display::DisplayMemberHead {
                    member_key: block_id.into(),
                    member_order: 1,
                    record: record.clone(),
                },
            };
            db.execute_raw(statement(
                "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,sealed,updated_effect,header)
                 VALUES(?,?,?,0,1,?)",
                vec![
                    block_id.into(),
                    serde_json::to_string(&header.source)?.into(),
                    db::number(order)?.into(),
                    serde_json::to_vec(&header)?.into(),
                ],
            ))
            .await?;
            db.execute_raw(statement(
                "INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata)
                 VALUES(?1,1,?1,?1,0,NULL,1,?2)",
                vec![block_id.into(), serde_json::to_vec(&member)?.into()],
            ))
            .await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn real_schema24_upgrade_preserves_canonical_current_and_display_facts() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-integration";
        let fixture = write_v24_fixture(&history_path, thread_id, true).await?;
        let source = schema::connect(&history_path, false, false).await?;
        write_live_single_fixture(&source, &fixture.database_id).await?;
        let source_key = serde_json::to_string(&ChatSourceId::ForegroundTurn {
            turn_id: "legacy-source".into(),
        })?;
        source
            .execute_raw(statement(
                "INSERT INTO conversation_sources(source_key,active_observed) VALUES(?,1)",
                vec![source_key.clone().into()],
            ))
            .await?;
        source
            .execute_unprepared(
                "CREATE TABLE work_snapshot_migration_headers AS SELECT * FROM conversation_display_blocks;
                 CREATE TABLE work_snapshot_migration_members AS SELECT * FROM conversation_display_members;",
            )
            .await?;
        let source_counts = database_table_rows(&source).await?;
        source.close().await?;

        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::Upgraded);
        assert_eq!(report.database_id, fixture.database_id);
        assert_eq!(report.backup_only_categories["timeline_records"], 1);
        assert_eq!(
            report.backup_only_categories["work_snapshot_migration_headers"],
            3
        );
        assert_eq!(
            report.backup_only_categories["work_snapshot_migration_members"],
            4
        );
        assert_eq!(report.backup_only_categories["display_single_members"], 2);
        assert_eq!(
            report.backup_only_categories["display_current_atom_material"],
            2
        );
        let backup = schema::connect(report.backup.as_deref().unwrap(), true, false).await?;
        assert_eq!(database_table_rows(&backup).await?, source_counts);
        backup.close().await?;
        assert_eq!(report.imported_categories["canonical_originals"], 2);
        assert_eq!(report.imported_categories["turns"], 1);
        assert_eq!(report.imported_categories["sources"], 1);
        assert_eq!(report.imported_categories["costs"], 1);
        assert_eq!(report.imported_categories["tool_resources"], 1);
        assert_eq!(report.imported_categories["tool_deliveries"], 1);
        assert_eq!(report.backup_only_categories["history_tool_tasks"], 1);
        assert_eq!(report.imported_categories["review_deliveries"], 1);
        assert_eq!(
            report.backup_only_categories["history_fact_receipts_review_delivery_already_acknowledged"],
            1
        );
        assert_eq!(report.imported_categories["display_work_anchors"], 1);
        assert_eq!(report.imported_categories["display_member_anchors"], 2);
        assert_eq!(
            report.imported_categories["display_boundary_observations"],
            1
        );

        let current_bytes = tokio::fs::read(directory.path().join("current.json")).await?;
        let current = ThreadCurrent::from_json(&current_bytes, thread_id)
            .map_err(|error| HistoryError::Storage(error.into()))?;
        assert!(current.state.execution.is_none());
        assert_eq!(current.state.lifecycle, ThreadLifecycle::Open);
        assert!(current.state.context.records.iter().any(|record| {
            record.content.iter().any(|content| {
                matches!(content, ContextContent::Text { text } if text.as_ref() == "cold context")
            })
        }));

        let store =
            CurrentHistoryStore::open(&history_path, thread_id, HistoryLimits::default()).await?;
        let reader = store.reader();
        let source_event = reader
            .read_event(
                deterministic_event_id("conversation_sources", &[source_key.into()], "anchor"),
                HistoryDemand::default(),
            )
            .await?;
        assert!(matches!(
            body::decode_business_head_from_record(&source_event)?,
            HistoryBusinessRowHead::Source(head) if head.lifecycle == ChatSourceLifecycle::Active
        ));
        let resources = FileResourceStore::new(directory.path().join("resources"));
        assert_eq!(
            crate::studio::history_resources::read(&reader, &resources, &fixture.resource_id)
                .await?,
            fixture.resource_body.as_slice()
        );
        let pending_review = fixture
            .pending_review_id
            .as_deref()
            .ok_or_else(|| HistoryError::NotFound("pending review id".into()))?;
        assert!(
            reader
                .read_event(
                    format!("review_delivery:{pending_review}"),
                    HistoryDemand {
                        max_rows: 1,
                        max_bytes: 64 * 1024
                    }
                )
                .await
                .is_ok()
        );
        let acknowledged_review = fixture
            .acknowledged_review_id
            .as_deref()
            .ok_or_else(|| HistoryError::NotFound("acknowledged review id".into()))?;
        assert!(matches!(
            reader
                .read_event(
                    format!("review_delivery:{acknowledged_review}"),
                    HistoryDemand {
                        max_rows: 1,
                        max_bytes: 64 * 1024
                    }
                )
                .await,
            Err(HistoryError::NotFound(_))
        ));
        let originals = reader
            .events_page(
                HistoryEventsQuery::Originals {
                    scope: ChatScope {
                        query_class: ChatClassFilter::All {},
                        parent_id: None,
                    },
                },
                None,
                None,
                HistoryDemand::default(),
            )
            .await?;
        assert_eq!(originals.entries.len(), 2);
        let mut inline_body_verified = false;
        for (item_id, expected) in &fixture.canonical_payloads {
            let event = originals
                .entries
                .iter()
                .find(|entry| entry.event_id == *item_id)
                .ok_or_else(|| HistoryError::NotFound(item_id.clone()))?;
            let actual = decode_event_envelope(event)?;
            let expected: serde_json::Value = serde_json::from_slice(expected)?;
            assert_eq!(actual.contract, "anywork.event/1");
            assert_eq!(Some(actual.item_type.as_str()), expected["type"].as_str());
            assert_eq!(actual.data, expected["data"]);
            assert_eq!(
                actual.source_order,
                Some(if item_id == "original-large" { 1 } else { 2 })
            );
            for body in &actual.bodies {
                if let Some(reference) = &body.reference {
                    assert_eq!(reference.byte_length, body.byte_length);
                } else {
                    assert!(body.inline_text.is_some() || body.byte_length == 0);
                }
                if body.key == "inline-preview" {
                    let bytes = read_event_body_bytes(&reader, event, "inline-preview", None)
                        .await?
                        .expect("inline preview body readable");
                    assert_eq!(bytes, INLINE_BODY);
                    inline_body_verified = true;
                }
            }
        }
        assert!(inline_body_verified);

        let target = schema::connect(&history_path, true, false).await?;
        for (item_id, expected) in [
            (&fixture.large_id, fixture.large_body.as_slice()),
            (&fixture.empty_id, fixture.empty_body.as_slice()),
        ] {
            let row = target
                .query_one_raw(statement(
                    "SELECT body_id,byte_length FROM history_bodies
                     WHERE owner_event_id=? AND body_key='legacy-content:body'",
                    vec![item_id.clone().into()],
                ))
                .await?
                .ok_or_else(|| HistoryError::NotFound(item_id.clone()))?;
            let reference = HistoryEventBodyRef {
                database_id: fixture.database_id.clone(),
                owner_event_id: item_id.clone(),
                body_key: "legacy-content:body".into(),
                body_id: row.try_get("", "body_id")?,
                byte_start: 0,
                byte_length: db_u64(row.try_get("", "byte_length")?, "history body length")?,
            };
            assert_eq!(read_all_body(&reader, reference).await?, expected);
        }
        let host_row = target
            .query_one_raw(statement(
                "SELECT body_id,byte_length FROM history_bodies \
                 WHERE owner_event_id=? AND body_key='legacy-content:tool.output-artifacts'",
                vec![fixture.large_id.clone().into()],
            ))
            .await?
            .ok_or_else(|| HistoryError::NotFound("host artifact body".into()))?;
        let host_reference = HistoryEventBodyRef {
            database_id: fixture.database_id.clone(),
            owner_event_id: fixture.large_id.clone(),
            body_key: "legacy-content:tool.output-artifacts".into(),
            body_id: host_row.try_get("", "body_id")?,
            byte_start: 0,
            byte_length: db_u64(
                host_row.try_get::<i64>("", "byte_length")?,
                "host artifact body length",
            )?,
        };
        assert_eq!(
            read_all_body(&reader, host_reference).await?,
            fixture.host_body
        );
        let metadata_row = target
            .query_one_raw(statement(
                "SELECT body_id,byte_length FROM history_bodies \
                 WHERE owner_event_id=? AND role='legacy_metadata'",
                vec![fixture.large_id.clone().into()],
            ))
            .await?
            .ok_or_else(|| HistoryError::NotFound("legacy metadata body".into()))?;
        let metadata_reference = HistoryEventBodyRef {
            database_id: fixture.database_id.clone(),
            owner_event_id: fixture.large_id.clone(),
            body_key: "legacy_metadata".into(),
            body_id: metadata_row.try_get("", "body_id")?,
            byte_start: 0,
            byte_length: db_u64(
                metadata_row.try_get::<i64>("", "byte_length")?,
                "legacy metadata body length",
            )?,
        };
        let metadata: HistoryEntityHead =
            serde_json::from_slice(&read_all_body(&reader, metadata_reference).await?)?;
        assert_eq!(metadata.entity_id, "original-large");
        let boundary_event = display_member_event_id("work-1", "member-1");
        let row = target
            .query_one_raw(statement(
                "SELECT body_id,byte_length FROM history_bodies \
                 WHERE owner_event_id=? AND body_key='legacy-display:body'",
                vec![boundary_event.clone().into()],
            ))
            .await?
            .ok_or_else(|| HistoryError::NotFound("frozen observation body".into()))?;
        let boundary_reference = HistoryEventBodyRef {
            database_id: fixture.database_id.clone(),
            owner_event_id: boundary_event,
            body_key: "legacy-display:body".into(),
            body_id: row.try_get("", "body_id")?,
            byte_start: 0,
            byte_length: db_u64(row.try_get::<i64>("", "byte_length")?, "frozen body length")?,
        };
        assert_eq!(
            read_all_body(&reader, boundary_reference).await?,
            b"frozen body \xF0\x9F\xA6\x80".to_vec()
        );
        target.close().await?;

        let main = reader
            .timeline_page(None, None, HistoryDemand::default())
            .await?;
        let draft_divs: Vec<_> = main
            .items
            .iter()
            .filter_map(|item| match item {
                HistoryTimelineItem::Divider(rec) => Some(rec),
                _ => None,
            })
            .filter_map(|rec| body::decode_event_envelope(rec).ok().map(|env| (rec, env)))
            .filter(|(_, env)| {
                env.meta.entity_id == "draft-plan"
                    && env.data["legacyUnavailable"] == serde_json::Value::Bool(true)
                    && env.meta.finished_at.is_none()
                    && env.meta.content_present == Some(false)
            })
            .collect();
        assert_eq!(draft_divs.len(), 2);

        let work_range = main
            .items
            .iter()
            .find_map(|item| match item {
                HistoryTimelineItem::WorkRange(range) => Some(range.clone()),
                _ => None,
            })
            .ok_or_else(|| HistoryError::NotFound("work range".into()))?;
        assert_eq!(work_range.event_count, 2);
        let members = reader
            .work_range_page(
                work_range.after_seq,
                work_range.before_seq,
                None,
                None,
                HistoryDemand::default(),
            )
            .await?;
        assert_eq!(members.events.len(), 2);
        let boundary_event = display_member_event_id("work-1", "member-1");
        let boundary_rec = members
            .events
            .iter()
            .find(|ev| ev.event_id == boundary_event)
            .ok_or_else(|| HistoryError::NotFound("frozen observation".into()))?;
        let observation: serde_json::Value = serde_json::from_str(&boundary_rec.payload_json)?;
        assert_eq!(observation["contract"], "anywork.event/1");
        assert_eq!(observation["capturedAt"], 2);
        assert_eq!(
            observation["bodies"][0]["reference"]["ownerEventId"],
            boundary_event
        );
        let original_member_event = display_member_event_id("work-1", "member-2");
        let original_member_rec = members
            .events
            .iter()
            .find(|ev| ev.event_id == original_member_event)
            .ok_or_else(|| HistoryError::NotFound("completed original member".into()))?;
        assert_ne!(
            original_member_rec.kind,
            CurrentHistoryEventKind::LegacyObserved
        );
        assert_eq!(original_member_rec.payload_schema, "anywork.event/1");
        let m2_env = body::decode_event_envelope(original_member_rec)?;
        assert!(m2_env.captured_at.is_none());
        assert!(m2_env.bodies.iter().all(|b| b.role != "legacy_metadata"));
        let mut seen_m2_keys = std::collections::BTreeSet::new();
        for entry in &m2_env.bodies {
            assert!(
                seen_m2_keys.insert(entry.key.clone()),
                "duplicate lifted body key {} on migrated member",
                entry.key
            );
        }
        assert_eq!(
            body::read_event_body_bytes(&reader, original_member_rec, "body", None)
                .await?
                .as_deref(),
            Some(fixture.empty_body.as_slice())
        );

        let costs = reader
            .costs_page(None, None, HistoryDemand::default())
            .await?;
        assert_eq!(costs.entries.len(), 1);
        assert!(matches!(
            &costs.entries[0].head,
            HistoryBusinessRowHead::Cost(head) if head.cost_total == 1.25 && head.cost_delta.is_none()
        ));
        let turn = reader
            .events_page(
                HistoryEventsQuery::Turn {
                    turn_id: "turn-rollback".into(),
                },
                None,
                None,
                HistoryDemand::default(),
            )
            .await?;
        assert_eq!(turn.entries.len(), 1);
        assert_eq!(
            turn.entries[0].kind,
            CurrentHistoryEventKind::TurnRolledBack
        );
        assert!(matches!(
            body::decode_business_head_from_record(&turn.entries[0])?,
            HistoryBusinessRowHead::Turn(head)
                if head.context_disposition == ThreadContextDisposition::RolledBack
        ));
        reader.close().await;
        store.close().await?;
        let committed_events = event_count(&history_path).await?;
        let observed = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(observed.status, UpgradeStatus::AlreadySchema26);
        assert_eq!(
            event_count(&history_path).await?,
            committed_events,
            "a fresh post-commit observation must not append the upgrade twice"
        );
        Ok(())
    }

    #[tokio::test]
    async fn lifecycle_migration_uses_actual_evidence_and_preserves_unknown_times() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-lifecycle-evidence";
        write_v24_fixture(&history_path, thread_id, false).await?;
        let cases = [
            (
                "ended-with-attempt",
                Some("actual-attempt"),
                true,
                true,
                Some(crate::ChatTerminalOutcome::Cancelled),
                None,
                HistoryEventKind::LegacyObserved,
            ),
            (
                "started-without-attempt",
                None,
                true,
                false,
                None,
                None,
                HistoryEventKind::EntityStarted,
            ),
            (
                "attempt-association-only",
                Some("actual-attempt"),
                false,
                false,
                None,
                None,
                HistoryEventKind::LegacyObserved,
            ),
            (
                "ended-known-time",
                None,
                false,
                false,
                Some(crate::ChatTerminalOutcome::Completed),
                Some(12i64),
                HistoryEventKind::EntityEnded,
            ),
        ];
        let db = schema::connect(&history_path, false, false).await?;
        for (id, attempt, started, ended, outcome, finished_at, _) in &cases {
            db.execute_raw(statement(
                "INSERT INTO execution_lifecycle(identity,kind,source_kind,source_identity,turn_id,attempt_id,call_id,tool_name,delivery,started_effect,started_suborder,ended_effect,ended_suborder,started_at,finished_at,outcome,last_write_seq) VALUES(?,?,'operation',?,'turn-1',?,?,'fixture-tool',?,?,?,?,?,NULL,?,?,1)",
                vec![
                    (*id).into(),
                    serde_json::to_string(&crate::ChatAtomKind::ToolCall)?.into(),
                    format!("operation:{id}").into(),
                    (*attempt).into(),
                    (*id).into(),
                    serde_json::to_string(&crate::ChatDeliveryKind::Foreground)?.into(),
                    started.then_some(1i64).into(),
                    started.then_some(0i64).into(),
                    ended.then_some(1i64).into(),
                    ended.then_some(1i64).into(),
                    (*finished_at).into(),
                    outcome.as_ref().map(serde_json::to_string).transpose()?.into(),
                ],
            )).await?;
        }
        db.close().await?;
        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(report.imported_categories["execution_lifecycle"], 4);
        let store =
            CurrentHistoryStore::open(&history_path, thread_id, HistoryLimits::default()).await?;
        let reader = store.reader();
        for (id, attempt, started, ended, outcome, finished_at, expected_kind) in &cases {
            let page = reader
                .events_page(
                    HistoryEventsQuery::Entity {
                        entity_id: (*id).into(),
                    },
                    None,
                    None,
                    HistoryDemand::default(),
                )
                .await?;
            assert_eq!(
                page.entries.len(),
                1,
                "one real lifecycle observation for {id}"
            );
            let event = &page.entries[0];
            assert_eq!(event.kind.as_str(), expected_kind.as_str(), "{id}");
            assert_eq!(event.attempt_id.as_deref(), *attempt);
            assert!(event.run_id.is_none(), "{id}: no invented runtime epoch");
            assert_eq!(event.occurred_at, finished_at.map(|at| at * 1000), "{id}");
            let payload_bytes = read_event_body_bytes(&reader, event, "canonical_payload", None)
                .await?
                .expect("lifecycle payload");
            let payload: serde_json::Value = serde_json::from_slice(&payload_bytes)?;
            assert_eq!(payload["attemptId"], serde_json::to_value(attempt)?, "{id}");
            assert_eq!(payload["started"].is_object(), *started, "{id}");
            assert_eq!(payload["ended"].is_object(), *ended, "{id}");
            assert!(
                payload["startedAt"].is_null(),
                "{id}: no invented start time"
            );
            assert_eq!(payload["finishedAt"], serde_json::to_value(finished_at)?);
            assert_eq!(payload["outcome"], serde_json::to_value(outcome)?);
        }
        reader.close().await;
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn identity_receipts_become_input_facts_and_unknown_user_content_stops_upgrade()
    -> Result<()> {
        for unknown_content in [false, true] {
            let directory = tempfile::tempdir()?;
            let history_path = directory.path().join("history.sqlite");
            let thread_id = format!("migration-input-receipt-{unknown_content}");
            write_v24_fixture(&history_path, &thread_id, false).await?;
            let mut payload = serde_json::json!({
                "digest": "sha256:identity-only",
                "continuation": {"pointId":"point-1", "sourceTurnId":"turn-1"},
                "delivery": {"kind":"currentTurn", "value":{"turnId":"turn-1"}},
                "id":"identity-only", "ordinal":3, "purpose":"continuation",
                "expectedModelRouteRevision":7, "continuationAdmissionRevision":2,
                "revision":3, "state":{"kind":"discarded"}, "acceptedSequence":5,
            });
            if unknown_content {
                payload["userBody"] = serde_json::json!("unique user text must not be discarded");
            }
            let original = serde_json::to_string(&payload)?;
            let db = schema::connect(&history_path, false, false).await?;
            db.execute_raw(statement(
                "INSERT INTO history_input_identities(item_id,ordinal,revision,digest,request_digest,presentation,payload,last_write_seq) VALUES('identity-only',3,3,'sha256:identity-only','sha256:request','visible',?,1)",
                vec![original.clone().into()],
            )).await?;
            db.close().await?;
            let result = upgrade_history(&history_path, &thread_id, directory.path()).await;
            if unknown_content {
                assert!(
                    result.is_err(),
                    "unsupported user content must stop migration"
                );
                assert_eq!(schema_version(&history_path).await?, 24);
            } else {
                result?;
                let store =
                    CurrentHistoryStore::open(&history_path, &thread_id, HistoryLimits::default())
                        .await?;
                let reader = store.reader();
                let detail = reader
                    .read_event(
                        "legacy:v24:input:identity-only:accepted".into(),
                        crate::history::HistoryDemand {
                            max_rows: 1,
                            max_bytes: 16 * 1024,
                        },
                    )
                    .await?;
                let body =
                    read_event_body_bytes(&reader, &detail, INPUT_FACT_BODY_KEY, Some(16 * 1024))
                        .await?
                        .expect("preserved admission body");
                let saved: pl_core::context::OpaquePayload = serde_json::from_slice(&body)?;
                let saved: serde_json::Value = serde_json::from_str(saved.content())?;
                assert_eq!(saved["kind"], "admission");
                let value = &saved["value"];
                assert_eq!(value["id"], "identity-only");
                assert_eq!(value["digest"], "sha256:identity-only");
                assert_eq!(value["requestDigest"], "sha256:request");
                assert_eq!(value["continuation"]["pointId"], "point-1");
                assert_eq!(value["acceptedSequence"], 5);
                assert_eq!(value["admissionRevision"], 2);
                assert_eq!(value["state"]["kind"], "discarded");
                reader.close().await;
                store.close().await?;
            }
            let operations = std::fs::read_dir(directory.path().join(BACKUP_ROOT))?
                .map(|entry| entry.map(|entry| entry.path()))
                .collect::<std::io::Result<Vec<_>>>()?;
            let operation = operations
                .iter()
                .find(|path| path.is_dir())
                .expect("preserved operation");
            let backup =
                schema::connect(&operation.join("history.v24.sqlite"), true, false).await?;
            let row = backup
                .query_one_raw(statement(
                    "SELECT payload FROM history_input_identities WHERE item_id='identity-only'",
                    vec![],
                ))
                .await?
                .expect("the exact receipt is preserved");
            assert_eq!(row.try_get::<String>("", "payload")?, original);
            backup.close().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn cold_current_reader_prepares_schema24_before_history_is_opened() -> anyhow::Result<()>
    {
        use crate::runtime_test_support::{Environment, current_demand};
        let mut env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread = env
                .runtime
                .create_thread(&env.project.id, "legacy current")
                .await?;
            let paths = crate::studio::paths::StudioPaths::from_home(env.home.clone())
                .session_paths(&thread.workspace_id, &thread.id)?;
            env.runtime.shutdown_runtime().await?;
            // create_thread seeds current-format storage. Replace only this isolated
            // test session after its owners have joined, then install the frozen v24 input.
            for path in [paths.history_database(), paths.current_file()] {
                if path.exists() {
                    std::fs::remove_file(path)?;
                }
            }
            std::fs::create_dir_all(paths.root())?;
            write_v24_fixture(&paths.history_database(), &thread.id, true).await?;
            assert!(!paths.current_file().exists());
            env.restart().await?;
            assert!(!paths.current_file().exists());
            let reader = env
                .runtime
                .open_current_reader(
                    &thread.id,
                    crate::CURRENT_PROTOCOL_VERSION,
                    current_demand(),
                )
                .await?;
            let view = reader.snapshot(current_demand()).await?;
            assert!(!view.projection.execution_present);
            assert!(paths.current_file().is_file());
            reader.close().await?;
            assert!(env.root_provider.recorded().is_empty());
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn existing_current_bytes_are_not_rewritten_by_upgrade() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-current-bytes";
        write_v24_fixture(&history_path, thread_id, false).await?;

        let mut current = ThreadCurrent::new(thread_id.into(), RuntimeEpoch::new());
        current.saved_at = 123;
        let original = serde_json::to_vec_pretty(&current)?;
        std::fs::write(directory.path().join("current.json"), &original)?;

        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(
            tokio::fs::read(directory.path().join("current.json")).await?,
            original
        );
        let backup = report
            .current_original_backup
            .ok_or_else(|| HistoryError::NotFound("current backup".into()))?;
        assert_eq!(std::fs::read(backup)?, original);
        Ok(())
    }

    #[tokio::test]
    async fn backup_preparation_failure_preserves_schema24_and_does_not_publish_current()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-backup-failure";
        write_v24_fixture(&history_path, thread_id, true).await?;
        std::fs::write(
            directory.path().join("migration-backups"),
            b"not a directory",
        )?;

        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        assert_eq!(schema_version(&history_path).await?, 24);
        assert!(!directory.path().join("current.json").exists());
        Ok(())
    }

    #[tokio::test]
    async fn backup_publish_failure_leaves_only_an_unpublished_temporary_copy() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-backup-publish";
        write_v24_fixture(&history_path, thread_id, true).await?;
        *FAIL_NEXT_BACKUP_PUBLISH_THREAD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(thread_id.into());

        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        assert_eq!(schema_version(&history_path).await?, 24);
        assert!(!directory.path().join("current.json").exists());
        let operations = directory.path().join(BACKUP_ROOT);
        let operation = std::fs::read_dir(&operations)?
            .next()
            .transpose()?
            .ok_or_else(|| HistoryError::NotFound("backup operation directory".into()))?;
        assert!(!operation.path().join("history.v24.sqlite").exists());
        assert!(
            std::fs::read_dir(operation.path())?.any(|entry| {
                entry
                    .ok()
                    .and_then(|entry| entry.file_name().into_string().ok())
                    .is_some_and(|name| name.starts_with(".history-v24-"))
            }),
            "validated temporary backup remains unpublished"
        );
        Ok(())
    }

    #[tokio::test]
    async fn current_publish_failures_never_migrate_database_or_rewrite_published_bytes()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-current-publish";
        write_v24_fixture(&history_path, thread_id, true).await?;

        *FAIL_NEXT_CURRENT_PUBLISH
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some((thread_id.into(), false));
        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        assert_eq!(schema_version(&history_path).await?, 24);
        assert!(!directory.path().join("current.json").exists());

        *FAIL_NEXT_CURRENT_PUBLISH
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some((thread_id.into(), true));
        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        assert_eq!(schema_version(&history_path).await?, 24);
        let published = tokio::fs::read(directory.path().join("current.json")).await?;
        ThreadCurrent::from_json(&published, thread_id)
            .map_err(|error| HistoryError::Storage(error.into()))?;

        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::Upgraded);
        assert_eq!(
            tokio::fs::read(directory.path().join("current.json")).await?,
            published
        );
        Ok(())
    }

    #[tokio::test]
    async fn destructive_ddl_failure_rolls_back_partial_table_drops() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-ddl-rollback";
        write_v24_fixture(&history_path, thread_id, true).await?;
        *FAIL_NEXT_DDL_THREAD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(thread_id.into());

        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        assert_eq!(schema_version(&history_path).await?, 24);
        let source = schema::connect(&history_path, true, false).await?;
        for table in ["conversation_display_members", "history_store_meta"] {
            let exists = source
                .query_one_raw(statement(
                    "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
                    vec![table.into()],
                ))
                .await?
                .is_some();
            assert_eq!(
                exists,
                table == "conversation_display_members",
                "partial DDL rollback must restore {table} exactly"
            );
        }
        source.close().await?;
        assert!(directory.path().join("current.json").is_file());

        let retried = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(retried.status, UpgradeStatus::Upgraded);
        let target = schema::connect(&history_path, true, false).await?;
        let counts = target
            .query_one_raw(statement(
                "SELECT count(*) AS total,count(DISTINCT event_id) AS unique_count FROM history_events",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("retry event count failed".into()))?;
        assert_eq!(
            counts.try_get::<i64>("", "total")?,
            counts.try_get::<i64>("", "unique_count")?
        );
        target.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn schema24_retry_archives_its_uncommitted_report_and_preserves_inputs() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-uncommitted-report";
        let fixture = write_v24_fixture(&history_path, thread_id, false).await?;
        let operation_id = uuid::Uuid::new_v4().to_string();
        let operation = directory.path().join(BACKUP_ROOT).join(&operation_id);
        prepare_directory(directory.path(), &operation)?;
        let (backup, rows) = make_backup(
            &history_path,
            &operation,
            thread_id,
            &fixture.database_id,
            1,
        )
        .await?;
        let backup_bytes = std::fs::read(&backup)?;
        let preserved_note = operation.join("preserved-note.txt");
        std::fs::write(&preserved_note, b"keep this operation's other material")?;
        let staged = UpgradeReport {
            operation_id: operation_id.clone(),
            thread_id: thread_id.into(),
            database_id: fixture.database_id,
            status: UpgradeStatus::Upgraded,
            backup: Some(backup.clone()),
            current_original_backup: None,
            source_table_rows: rows,
            imported_categories: BTreeMap::from([("canonical_originals".into(), 2)]),
            backup_only_categories: BTreeMap::new(),
        };
        let staged_bytes = serde_json::to_vec_pretty(&staged)?;
        let pending = directory.path().join(BACKUP_ROOT).join(PENDING_REPORT_FILE);
        std::fs::write(&pending, &staged_bytes)?;
        assert_eq!(schema_version(&history_path).await?, 24);

        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::Upgraded);
        assert_ne!(report.operation_id, operation_id);
        assert_eq!(report.imported_categories["canonical_originals"], 2);
        assert_eq!(
            std::fs::read(operation.join("uncommitted-report.json"))?,
            staged_bytes
        );
        assert_eq!(std::fs::read(backup)?, backup_bytes);
        assert_eq!(
            std::fs::read(preserved_note)?,
            b"keep this operation's other material"
        );
        assert!(!pending.try_exists()?);
        assert!(!operation.join("upgrade-report.json").try_exists()?);
        Ok(())
    }

    #[tokio::test]
    async fn lost_result_after_commit_preserves_report_and_never_appends_again() -> Result<()> {
        for report_state in ["missing", "published", "conflict"] {
            let directory = tempfile::tempdir()?;
            let history_path = directory.path().join("history.sqlite");
            let thread_id = format!("migration-lost-report-{report_state}");
            let fixture = write_v24_fixture(&history_path, &thread_id, true).await?;
            *FAIL_NEXT_REPORT_THREAD
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(thread_id.clone());

            assert!(
                upgrade_history(&history_path, &thread_id, directory.path())
                    .await
                    .is_err(),
                "{report_state}: caller must observe the report publication failure"
            );
            let current_bytes = std::fs::read(directory.path().join("current.json"))?;
            let committed_events = event_count(&history_path).await?;
            let pending_path = directory.path().join(BACKUP_ROOT).join(PENDING_REPORT_FILE);
            let staged_bytes = std::fs::read(&pending_path)?;
            let staged: UpgradeReport = serde_json::from_slice(&staged_bytes)?;
            assert_eq!(staged.status, UpgradeStatus::Upgraded);
            assert_eq!(staged.database_id, fixture.database_id);
            assert_eq!(staged.imported_categories["canonical_originals"], 2);
            assert_eq!(staged.imported_categories["display_member_anchors"], 2);
            assert_eq!(staged.imported_categories["costs"], 1);
            let backup = staged.backup.as_ref().expect("preserved v24 backup");
            let backup_bytes = std::fs::read(backup)?;
            let report_path = directory
                .path()
                .join(BACKUP_ROOT)
                .join(&staged.operation_id)
                .join("upgrade-report.json");
            match report_state {
                "missing" => assert!(!report_path.try_exists()?),
                "published" => std::fs::write(&report_path, &staged_bytes)?,
                "conflict" => {
                    let conflicting_bytes = b"preserve the conflicting report";
                    std::fs::write(&report_path, conflicting_bytes)?;
                    assert!(matches!(
                        upgrade_history(&history_path, &thread_id, directory.path()).await,
                        Err(HistoryError::Conflict(_))
                    ));
                    assert_eq!(std::fs::read(&report_path)?, conflicting_bytes);
                    assert_eq!(std::fs::read(&pending_path)?, staged_bytes);
                    assert_eq!(event_count(&history_path).await?, committed_events);
                    std::fs::remove_file(&report_path)?;
                }
                _ => unreachable!(),
            }

            let observed = upgrade_history(&history_path, &thread_id, directory.path()).await?;
            let mut expected = staged;
            expected.status = UpgradeStatus::AlreadySchema26;
            assert_eq!(
                serde_json::to_value(&observed)?,
                serde_json::to_value(&expected)?
            );
            assert_eq!(std::fs::read(&report_path)?, staged_bytes);
            assert!(!pending_path.try_exists()?);
            assert_eq!(
                event_count(&history_path).await?,
                committed_events,
                "{report_state}: report recovery must not append migration events"
            );
            assert_eq!(
                std::fs::read(directory.path().join("current.json"))?,
                current_bytes
            );
            assert_eq!(
                std::fs::read(expected.backup.as_ref().expect("preserved backup"))?,
                backup_bytes
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn corrupt_existing_current_is_never_overwritten() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-corrupt-current";
        write_v24_fixture(&history_path, thread_id, true).await?;
        let original = b"{not valid current json".to_vec();
        std::fs::write(directory.path().join("current.json"), &original)?;

        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        assert_eq!(
            tokio::fs::read(directory.path().join("current.json")).await?,
            original
        );
        assert_eq!(
            schema::connect(&history_path, true, false)
                .await?
                .query_one_raw(statement(
                    "SELECT schema_version FROM history_meta WHERE id=1",
                    Vec::new()
                ))
                .await?
                .ok_or_else(|| HistoryError::Integrity("source identity was lost".into()))?
                .try_get::<i64>("", "schema_version")?,
            24
        );
        Ok(())
    }

    #[tokio::test]
    async fn failed_import_rolls_back_schema_and_retry_does_not_duplicate_events() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "migration-rollback-retry";
        write_v24_fixture(&history_path, thread_id, true).await?;
        *FAIL_NEXT_IMPORT_THREAD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(thread_id.into());

        assert!(
            upgrade_history(&history_path, thread_id, directory.path())
                .await
                .is_err()
        );
        let source = schema::connect(&history_path, true, false).await?;
        let version = source
            .query_one_raw(statement(
                "SELECT schema_version FROM history_meta WHERE id=1",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("source identity was lost".into()))?
            .try_get::<i64>("", "schema_version")?;
        assert_eq!(version, 24);
        assert!(
            source
                .query_one_raw(statement(
                    "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_events'",
                    Vec::new(),
                ))
                .await?
                .is_none()
        );
        source.close().await?;
        assert!(directory.path().join("current.json").is_file());

        let retried = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(retried.status, UpgradeStatus::Upgraded);
        assert_eq!(retried.imported_categories["canonical_originals"], 2);
        let target = schema::connect(&history_path, true, false).await?;
        let canonical = target
            .query_one_raw(statement(
                "SELECT count(*) AS count FROM history_events WHERE query_class IS NOT NULL",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("canonical count failed".into()))?
            .try_get::<i64>("", "count")?;
        assert_eq!(canonical, 2);
        target.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn upgrades_schema25_in_place_without_copying_bodies_and_repairs_known_active_rows()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "schema25-to-26-thread";
        let db_id = uuid::Uuid::new_v4().to_string();

        let db = schema::connect(&history_path, false, true).await?;
        db.execute_unprepared(include_str!("upgrade/schema_v25.sql"))
            .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS seaql_migrations (version TEXT PRIMARY KEY NOT NULL, applied_at INTEGER NOT NULL)",
        )
        .await?;
        db.execute_raw(statement(
            "INSERT INTO seaql_migrations(version,applied_at) VALUES(?,1)",
            vec![schema::MIGRATION_V25.into()],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,?)",
            vec![db_id.clone().into(), thread_id.into()],
        ))
        .await?;

        // 1. group_opened (derived group anchor, no bodies -> must be dropped)
        let group_head = HistoryRowHead::Work(HistoryWorkHead {
            group_id: "grp-1".into(),
            run_id: Some("run-1".into()),
            started_at: Some(1_000),
            boundary_at: None,
            closed: false,
            member_count: 1,
            unfinished_count: 1,
            execution_present: true,
            summary: None,
        });
        db.execute_raw(statement(
            "INSERT INTO history_events(seq,event_id,kind,run_id,group_id,row_scope,row_key,is_anchor,occurred_at,recorded_at,head_json) \
             VALUES(1,'grp-open-1','group_opened','run-1','grp-1','work','work:grp-1',1,1000,1000,?)",
            vec![serde_json::to_string(&group_head)?.into()],
        ))
        .await?;

        // 2. KnownActive exec backgroundStarted with NULL payload_body_id (bug case!)
        let active_exec = HistoryRowHead::Member(HistoryEntityHead {
            entity_id: "tool-background:call_bg_1".into(),
            run_id: Some("run-1".into()),
            attempt_id: None,
            source: HistorySource::ForegroundTurn {
                turn_id: "turn-1".into(),
            },
            kind: HistoryEntityKind::ToolCall,
            delivery: HistoryDelivery::BackgroundHandoff,
            state: HistoryEntityState::KnownActive {
                status: crate::ChatActiveStatus::Running,
            },
            started_at: Some(2_000),
            finished_at: None,
            text_channel: None,
            tool: Some(HistoryToolIdentity {
                call_id: "call_bg_1".into(),
                name: "exec".into(),
            }),
            wait: None,
            content_present: Some(false),
            single_visibility: None,
            observation: HistoryObservation::Original,
            presentation_contract: Some("builtin.exec@1".into()),
            detail_event_id: None,
            input_manifest_event_id: None,
            body_manifest_event_id: None,
        });
        db.execute_raw(statement(
            "INSERT INTO history_events(seq,event_id,kind,run_id,entity_id,turn_id,call_id,group_id,row_scope,row_key,is_anchor,occurred_at,recorded_at,head_json) \
             VALUES(2,'bg-start-call-1','entity_started','run-1','tool-background:call_bg_1','turn-1','call_bg_1','grp-1','member','member:bg-1',1,2000,2000,?)",
            vec![serde_json::to_string(&active_exec)?.into()],
        ))
        .await?;

        // 3. Divider text event with a > 64 KiB chunked body in history_bodies/chunks (must remain zero-copy)
        let big_text = "x".repeat(70 * 1024);
        let big_bytes = big_text.as_bytes().to_vec();
        let body_id = "existing-big-body-id";
        let payload_body_id = "existing-payload-body-id";
        let text_head = HistoryRowHead::Single(HistoryEntityHead {
            entity_id: "completion:turn-1:final".into(),
            run_id: Some("run-1".into()),
            attempt_id: Some("att-1".into()),
            source: HistorySource::ForegroundTurn {
                turn_id: "turn-1".into(),
            },
            kind: HistoryEntityKind::Text,
            delivery: HistoryDelivery::Independent,
            state: HistoryEntityState::KnownTerminal {
                outcome: crate::ChatTerminalOutcome::Completed,
            },
            started_at: Some(3_000),
            finished_at: Some(3_500),
            text_channel: Some(crate::ThreadTextChannel::Final),
            tool: None,
            wait: None,
            content_present: Some(true),
            single_visibility: Some(HistorySingleVisibility::Content),
            observation: HistoryObservation::Original,
            presentation_contract: None,
            detail_event_id: Some("completion:turn-1:final".into()),
            input_manifest_event_id: Some("completion:turn-1:final".into()),
            body_manifest_event_id: Some("completion:turn-1:final".into()),
        });
        use sea_orm::TransactionTrait as _;
        let tx = db.begin().await?;
        tx.execute_raw(statement(
            "INSERT INTO history_events(seq,event_id,kind,run_id,attempt_id,entity_id,turn_id,row_scope,row_key,is_anchor,occurred_at,recorded_at,head_json,payload_body_id) \
             VALUES(3,'completion:turn-1:final','entity_ended','run-1','att-1','completion:turn-1:final','turn-1','single','single:final-1',1,3500,3500,?,?)",
            vec![serde_json::to_string(&text_head)?.into(), payload_body_id.into()],
        ))
        .await?;
        let canonical_payload = serde_json::to_vec(&serde_json::json!({
            "contract": "anywork.chat/1",
            "type": "text",
            "data": { "channel": "final", "attachments": [] },
            "bodies": [{
                "key": "body",
                "byteLength": big_bytes.len(),
                "reference": {
                    "databaseId": db_id,
                    "ownerEventId": "completion:turn-1:final",
                    "bodyKey": "body",
                    "bodyId": body_id,
                    "byteStart": 0,
                    "byteLength": big_bytes.len()
                }
            }]
        }))?;
        super::v25_schema::insert_v25_body(
            &tx,
            "completion:turn-1:final",
            0,
            &HistoryBody {
                body_id: payload_body_id.into(),
                body_key: "canonical_payload".into(),
                role: HistoryBodyRole::CanonicalPayload,
                media_type: Some("application/json".into()),
                bytes: canonical_payload.into(),
            },
        )
        .await?;
        super::v25_schema::insert_v25_body(
            &tx,
            "completion:turn-1:final",
            1,
            &HistoryBody {
                body_id: body_id.into(),
                body_key: "body".into(),
                role: HistoryBodyRole::Body,
                media_type: Some("text/plain; charset=utf-8".into()),
                bytes: big_bytes.clone().into(),
            },
        )
        .await?;
        tx.commit().await?;
        db.close().await?;

        assert!(super::requires_history_upgrade(&history_path, thread_id).await?);
        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::Upgraded);
        assert_eq!(report.database_id, db_id);
        let backup = report.backup.as_ref().expect("v25 backup path");
        assert!(backup.starts_with(directory.path().join(BACKUP_ROOT_V25_TO_V26)));
        assert!(backup.is_file());
        assert!(!super::requires_history_upgrade(&history_path, thread_id).await?);

        // Second call returns AlreadySchema26 cleanly
        let second = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(second.status, UpgradeStatus::AlreadySchema26);

        // Open as live Schema 26 store and verify timeline, repaired KnownActive row, and zero-copy blob
        let store = crate::history::HistoryStore::open(
            &history_path,
            thread_id,
            crate::history::HistoryLimits::default(),
        )
        .await?;
        let reader = store.reader();
        let timeline = reader
            .timeline_page(None, None, crate::history::HistoryDemand::default())
            .await?;
        assert_eq!(timeline.items.len(), 2);
        let HistoryTimelineItem::Divider(div) = &timeline.items[0] else {
            panic!("expected final divider first");
        };
        let HistoryTimelineItem::WorkRange(range) = &timeline.items[1] else {
            panic!("expected work range for background exec");
        };
        assert_eq!(range.event_count, 1);

        let work = reader
            .work_range_page(
                range.after_seq,
                range.before_seq,
                Some(timeline.cut.clone()),
                None,
                crate::history::HistoryDemand::default(),
            )
            .await?;
        assert_eq!(work.events.len(), 1);
        assert_eq!(
            work.events[0].kind,
            CurrentHistoryEventKind::ToolBackgrounded
        );
        assert_eq!(work.events[0].call_id.as_deref(), Some("call_bg_1"));
        assert_eq!(work.events[0].tool_name.as_deref(), Some("exec"));
        assert_eq!(work.events[0].payload_schema, "anywork.event/1");
        let exec_env = body::decode_event_envelope(&work.events[0])?;
        assert_eq!(exec_env.item_type, "tool");
        assert_eq!(exec_env.data["state"]["kind"], "backgroundStarted");

        let read_big = body::read_event_body_bytes(&reader, div, "body", None)
            .await?
            .expect("zero-copy big body readable");
        assert_eq!(read_big, big_bytes);

        reader.close().await;
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn v25_to_v26_lifts_legacy_display_detail_event_payloads_and_kinds() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let thread_id = "v25-legacy-detail-lift";
        let db_id = "db-v25-legacy-lift";

        let db = schema::connect(&history_path, false, true).await?;
        db.execute_unprepared(include_str!("upgrade/schema_v25.sql"))
            .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS seaql_migrations (version TEXT PRIMARY KEY NOT NULL, applied_at INTEGER NOT NULL)",
        )
        .await?;
        db.execute_raw(statement(
            "INSERT INTO seaql_migrations(version,applied_at) VALUES(?,1)",
            vec![schema::MIGRATION_V25.into()],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,?)",
            vec![db_id.into(), thread_id.into()],
        ))
        .await?;

        use sea_orm::TransactionTrait as _;
        let tx = db.begin().await?;
        let mut next_seq: i64 = 1;

        struct CanonicalFixture<'a> {
            event_id: &'a str,
            row_kind: &'a str,
            original_kind: &'a str,
            tool_name: Option<&'a str>,
            call_id: Option<&'a str>,
            entity_id: &'a str,
            head: HistoryEntityHead,
            payload: serde_json::Value,
            bodies: Vec<(&'a str, &'a str, HistoryBodyRole, Vec<u8>)>,
        }

        let make_head =
            |entity_id: &str,
             kind: HistoryEntityKind,
             text_channel: Option<crate::ThreadTextChannel>,
             tool: Option<(&str, &str)>,
             detail_id: &str,
             observation: HistoryObservation| HistoryEntityHead {
                entity_id: entity_id.into(),
                run_id: None,
                attempt_id: Some("att-1".into()),
                source: if kind == HistoryEntityKind::Input {
                    HistorySource::Input {
                        input_id: entity_id.into(),
                    }
                } else {
                    HistorySource::ForegroundTurn {
                        turn_id: "turn-1".into(),
                    }
                },
                kind,
                delivery: if kind == HistoryEntityKind::Input || kind == HistoryEntityKind::Text {
                    HistoryDelivery::Independent
                } else {
                    HistoryDelivery::Foreground
                },
                state: HistoryEntityState::KnownTerminal {
                    outcome: crate::ChatTerminalOutcome::Completed,
                },
                started_at: Some(1_000),
                finished_at: Some(2_000),
                text_channel,
                tool: tool.map(|(cid, name)| HistoryToolIdentity {
                    call_id: cid.into(),
                    name: name.into(),
                }),
                wait: None,
                content_present: None,
                single_visibility: (kind == HistoryEntityKind::Input
                    || kind == HistoryEntityKind::Text
                    || kind == HistoryEntityKind::Plan)
                    .then_some(HistorySingleVisibility::Content),
                observation,
                presentation_contract: tool.map(|_| "builtin.exec@2".into()),
                detail_event_id: Some(detail_id.into()),
                input_manifest_event_id: Some(detail_id.into()),
                body_manifest_event_id: Some(detail_id.into()),
            };

        let make_ref = |owner: &str, body_key: &str, body_id: &str, len: usize| {
            serde_json::json!({
                "databaseId": db_id,
                "ownerEventId": owner,
                "bodyKey": body_key,
                "bodyId": body_id,
                "byteStart": 0,
                "byteLength": len,
            })
        };

        let canonical_fixtures = vec![
            CanonicalFixture {
                event_id: "orig-input-1",
                row_kind: "input_accepted",
                original_kind: "input",
                tool_name: None,
                call_id: None,
                entity_id: "app-1",
                head: make_head(
                    "app-1",
                    HistoryEntityKind::Input,
                    Some(crate::ThreadTextChannel::User),
                    None,
                    "orig-input-1",
                    HistoryObservation::Original,
                ),
                payload: serde_json::json!({
                    "contract": "anywork.chat/1",
                    "type": "text",
                    "data": { "channel": "user", "attachments": [] },
                    "bodies": [{
                        "key": "body",
                        "byteLength": b"hello user prompt".len(),
                        "reference": make_ref("orig-input-1", "legacy-content:body", "b-input-body", b"hello user prompt".len()),
                    }],
                }),
                bodies: vec![(
                    "b-input-body",
                    "legacy-content:body",
                    HistoryBodyRole::Body,
                    b"hello user prompt".to_vec(),
                )],
            },
            CanonicalFixture {
                event_id: "orig-reason-1",
                row_kind: "entity_ended",
                original_kind: "reasoning",
                tool_name: None,
                call_id: None,
                entity_id: "reason-1",
                head: make_head(
                    "reason-1",
                    HistoryEntityKind::Reasoning,
                    None,
                    None,
                    "orig-reason-1",
                    HistoryObservation::Original,
                ),
                payload: serde_json::json!({
                    "contract": "anywork.chat/1",
                    "type": "thinking",
                    "data": { "outcome": { "kind": "completed" } },
                    "bodies": [{
                        "key": "part.summaryText.0",
                        "byteLength": b"thinking summary".len(),
                        "reference": make_ref("orig-reason-1", "legacy-content:part.summaryText.0", "b-reason-sum", b"thinking summary".len()),
                    }],
                }),
                bodies: vec![(
                    "b-reason-sum",
                    "legacy-content:part.summaryText.0",
                    HistoryBodyRole::ReasoningSummary,
                    b"thinking summary".to_vec(),
                )],
            },
            CanonicalFixture {
                event_id: "orig-tool-1",
                row_kind: "entity_ended",
                original_kind: "toolCall",
                tool_name: Some("exec"),
                call_id: Some("call-1"),
                entity_id: "tool-1",
                head: make_head(
                    "tool-1",
                    HistoryEntityKind::ToolCall,
                    None,
                    Some(("call-1", "exec")),
                    "orig-tool-1",
                    HistoryObservation::Original,
                ),
                payload: serde_json::json!({
                    "contract": "anywork.chat/1",
                    "type": "tool",
                    "data": {
                        "invocation": {
                            "toolCallId": "call-1",
                            "callId": "call-1",
                            "name": "exec",
                            "presentationContract": "builtin.exec@2"
                        },
                        "state": { "kind": "succeeded", "startedAt": 1, "finishedAt": 2 }
                    },
                    "bodies": [
                        {
                            "key": "tool.arguments",
                            "byteLength": b"{\"cmd\":\"ls\"}".len(),
                            "reference": make_ref("orig-tool-1", "legacy-content:tool.arguments", "b-tool-args", b"{\"cmd\":\"ls\"}".len()),
                        },
                        {
                            "key": "tool.result",
                            "byteLength": b"ok output".len(),
                            "reference": make_ref("orig-tool-1", "legacy-content:tool.result", "b-tool-res", b"ok output".len()),
                        }
                    ],
                }),
                bodies: vec![
                    (
                        "b-tool-args",
                        "legacy-content:tool.arguments",
                        HistoryBodyRole::ToolArguments,
                        b"{\"cmd\":\"ls\"}".to_vec(),
                    ),
                    (
                        "b-tool-res",
                        "legacy-content:tool.result",
                        HistoryBodyRole::ToolOutput,
                        b"ok output".to_vec(),
                    ),
                ],
            },
            CanonicalFixture {
                event_id: "orig-plan-1",
                row_kind: "entity_ended",
                original_kind: "plan",
                tool_name: None,
                call_id: Some("call-plan-1"),
                entity_id: "plan-1",
                head: make_head(
                    "plan-1",
                    HistoryEntityKind::Plan,
                    None,
                    Some(("call-plan-1", "plan")),
                    "orig-plan-1",
                    HistoryObservation::Original,
                ),
                payload: serde_json::json!({
                    "contract": "anywork.chat/1",
                    "type": "plan",
                    "data": { "decision": "approved", "documentVersion": 1 },
                    "bodies": [{
                        "key": "plan.document",
                        "byteLength": b"# Step 1".len(),
                        "reference": make_ref("orig-plan-1", "legacy-content:plan.document", "b-plan-doc", b"# Step 1".len()),
                    }],
                }),
                bodies: vec![(
                    "b-plan-doc",
                    "legacy-content:plan.document",
                    HistoryBodyRole::Other {
                        name: "legacy_content".into(),
                    },
                    b"# Step 1".to_vec(),
                )],
            },
            CanonicalFixture {
                event_id: "orig-text-1",
                row_kind: "entity_ended",
                original_kind: "text",
                tool_name: None,
                call_id: None,
                entity_id: "text-1",
                head: make_head(
                    "text-1",
                    HistoryEntityKind::Text,
                    Some(crate::ThreadTextChannel::Final),
                    None,
                    "orig-text-1",
                    HistoryObservation::Original,
                ),
                payload: serde_json::json!({
                    "contract": "anywork.chat/1",
                    "type": "text",
                    "data": { "channel": "final", "attachments": [] },
                    "bodies": [{
                        "key": "body",
                        "byteLength": b"final assistant reply".len(),
                        "reference": make_ref("orig-text-1", "legacy-content:body", "b-text-body", b"final assistant reply".len()),
                    }],
                }),
                bodies: vec![(
                    "b-text-body",
                    "legacy-content:body",
                    HistoryBodyRole::Body,
                    b"final assistant reply".to_vec(),
                )],
            },
        ];

        for item in &canonical_fixtures {
            let pbid = format!("{}:cp", item.event_id);
            tx.execute_raw(statement(
                "INSERT INTO history_events(seq,event_id,kind,attempt_id,entity_id,turn_id,call_id,query_class,original_kind,tool_name,occurred_at,recorded_at,payload_body_id) \
                 VALUES(?,?,?,?,?,'turn-1',?,'conversation',?,?,2000,2000,?)",
                vec![
                    next_seq.into(),
                    item.event_id.into(),
                    item.row_kind.into(),
                    "att-1".into(),
                    item.entity_id.into(),
                    item.call_id.into(),
                    item.original_kind.into(),
                    item.tool_name.into(),
                    pbid.clone().into(),
                ],
            ))
            .await?;
            next_seq += 1;

            super::v25_schema::insert_v25_body(
                &tx,
                item.event_id,
                0,
                &HistoryBody {
                    body_id: pbid,
                    body_key: "canonical_payload".into(),
                    role: HistoryBodyRole::CanonicalPayload,
                    media_type: Some("application/json".into()),
                    bytes: serde_json::to_vec(&item.payload)?.into(),
                },
            )
            .await?;
            super::v25_schema::insert_v25_body(
                &tx,
                item.event_id,
                1,
                &HistoryBody {
                    body_id: format!("{}:cm", item.event_id),
                    body_key: "canonical_metadata".into(),
                    role: HistoryBodyRole::CanonicalMetadata,
                    media_type: Some("application/json".into()),
                    bytes: serde_json::to_vec(&item.head)?.into(),
                },
            )
            .await?;
            super::v25_schema::insert_v25_body(
                &tx,
                item.event_id,
                2,
                &HistoryBody {
                    body_id: format!("{}:lm", item.event_id),
                    body_key: "legacy_metadata".into(),
                    role: HistoryBodyRole::Other {
                        name: "legacy_metadata".into(),
                    },
                    media_type: Some("application/json".into()),
                    bytes: serde_json::to_vec(&item.head)?.into(),
                },
            )
            .await?;
            for (idx, (bid, bkey, role, bytes)) in item.bodies.iter().enumerate() {
                super::v25_schema::insert_v25_body(
                    &tx,
                    item.event_id,
                    (3 + idx) as u64,
                    &HistoryBody {
                        body_id: (*bid).into(),
                        body_key: (*bkey).into(),
                        role: role.clone(),
                        media_type: Some("text/plain; charset=utf-8".into()),
                        bytes: bytes.clone().into(),
                    },
                )
                .await?;
            }
        }

        // Insert legacy_observed display rows (payload_body_id = NULL, detail_event_id -> canonical row)
        // in an interleaved / later order so earlier canonical rows have already been scanned.
        let display_rows = [
            (
                "legacy:v24:single-input",
                "single",
                "single:input-1",
                None::<&str>,
                make_head(
                    "app-1",
                    HistoryEntityKind::Input,
                    Some(crate::ThreadTextChannel::User),
                    None,
                    "orig-input-1",
                    HistoryObservation::Original,
                ),
            ),
            (
                "legacy:v24:member-reason",
                "member",
                "member:reason-1",
                Some("work-1"),
                make_head(
                    "reason-1",
                    HistoryEntityKind::Reasoning,
                    None,
                    None,
                    "orig-reason-1",
                    HistoryObservation::Original,
                ),
            ),
            (
                "legacy:v24:member-tool",
                "member",
                "member:tool-1",
                Some("work-1"),
                make_head(
                    "tool-1",
                    HistoryEntityKind::ToolCall,
                    None,
                    Some(("call-1", "exec")),
                    "orig-tool-1",
                    HistoryObservation::Original,
                ),
            ),
            (
                "legacy:v24:member-unavail",
                "member",
                "member:unavail-1",
                Some("work-1"),
                make_head(
                    "unavail-1",
                    HistoryEntityKind::Reasoning,
                    None,
                    None,
                    "legacy:v24:member-unavail",
                    HistoryObservation::UnavailableLegacy {
                        captured_at: Some(9_000),
                    },
                ),
            ),
            (
                "legacy:v24:single-plan",
                "single",
                "single:plan-1",
                None::<&str>,
                make_head(
                    "plan-1",
                    HistoryEntityKind::Plan,
                    None,
                    Some(("call-plan-1", "plan")),
                    "orig-plan-1",
                    HistoryObservation::Original,
                ),
            ),
            (
                "legacy:v24:single-text",
                "single",
                "single:text-1",
                None::<&str>,
                make_head(
                    "text-1",
                    HistoryEntityKind::Text,
                    Some(crate::ThreadTextChannel::Final),
                    None,
                    "orig-text-1",
                    HistoryObservation::Original,
                ),
            ),
        ];

        for (eid, scope, rkey, gid, mut head) in display_rows {
            head.attempt_id = None;
            let row_head = if scope == "single" {
                HistoryRowHead::Single(head.clone())
            } else {
                HistoryRowHead::Member(head.clone())
            };
            tx.execute_raw(statement(
                "INSERT INTO history_events(seq,event_id,kind,entity_id,turn_id,call_id,tool_name,group_id,row_scope,row_key,is_anchor,occurred_at,recorded_at,head_json,payload_body_id) \
                 VALUES(?,?,'legacy_observed',?,'turn-1',?,NULL,?,?,?,1,2000,2000,?,NULL)",
                vec![
                    next_seq.into(),
                    eid.into(),
                    head.entity_id.clone().into(),
                    head.tool.as_ref().map(|t| t.call_id.clone()).into(),
                    gid.into(),
                    scope.into(),
                    rkey.into(),
                    serde_json::to_string(&row_head)?.into(),
                ],
            ))
            .await?;
            next_seq += 1;
        }
        tx.commit().await?;

        let pre_body_count = db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS c FROM history_bodies",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "c")?;
        let pre_chunk_count = db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS c FROM history_body_chunks",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "c")?;
        db.close().await?;

        let report = upgrade_history(&history_path, thread_id, directory.path()).await?;
        assert_eq!(report.status, UpgradeStatus::Upgraded);

        let verify_conn = schema::connect(&history_path, true, false).await?;
        let post_body_count = verify_conn
            .query_one_raw(statement(
                "SELECT COUNT(*) AS c FROM history_bodies",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "c")?;
        let post_chunk_count = verify_conn
            .query_one_raw(statement(
                "SELECT COUNT(*) AS c FROM history_body_chunks",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<i64>("", "c")?;
        assert_eq!(post_body_count, pre_body_count);
        assert_eq!(post_chunk_count, pre_chunk_count);
        verify_conn.close().await?;

        let store = crate::history::HistoryStore::open(
            &history_path,
            thread_id,
            crate::history::HistoryLimits::default(),
        )
        .await?;
        let reader = store.reader();
        let timeline = reader
            .timeline_page(None, None, crate::history::HistoryDemand::default())
            .await?;
        // Newest-first dividers + 1 work range: single-text, single-plan, work, single-input
        assert_eq!(timeline.items.len(), 4);

        let HistoryTimelineItem::Divider(text_div) = &timeline.items[0] else {
            panic!("expected single-text divider");
        };
        assert_eq!(text_div.kind, CurrentHistoryEventKind::TextCompleted);
        let text_env = body::decode_event_envelope(text_div)?;
        assert_eq!(text_env.item_type, "text");
        assert!(text_env.bodies.iter().all(|b| b.role != "legacy_metadata"));
        assert_eq!(
            body::read_event_body_bytes(&reader, text_div, "body", None).await?,
            Some(b"final assistant reply".to_vec())
        );

        let HistoryTimelineItem::Divider(plan_div) = &timeline.items[1] else {
            panic!("expected single-plan divider");
        };
        assert_eq!(plan_div.kind, CurrentHistoryEventKind::PlanResolved);
        let plan_env = body::decode_event_envelope(plan_div)?;
        assert_eq!(plan_env.item_type, "plan");
        assert_eq!(
            body::read_event_body_bytes(&reader, plan_div, "plan.document", None).await?,
            Some(b"# Step 1".to_vec())
        );

        let HistoryTimelineItem::WorkRange(range) = &timeline.items[2] else {
            panic!("expected work range");
        };
        let work = reader
            .work_range_page(
                range.after_seq,
                range.before_seq,
                Some(timeline.cut.clone()),
                None,
                crate::history::HistoryDemand::default(),
            )
            .await?;
        assert_eq!(work.events.len(), 3);
        let reason_ev = &work.events[0];
        let tool_ev = &work.events[1];
        let unavail_ev = &work.events[2];

        assert_eq!(reason_ev.kind, CurrentHistoryEventKind::ReasoningCompleted);
        assert_eq!(
            body::read_event_body_bytes(&reader, reason_ev, "part.summaryText.0", None).await?,
            Some(b"thinking summary".to_vec())
        );

        assert_eq!(tool_ev.kind, CurrentHistoryEventKind::ToolCompleted);
        assert_eq!(
            body::read_event_body_bytes(&reader, tool_ev, "tool.arguments", None).await?,
            Some(b"{\"cmd\":\"ls\"}".to_vec())
        );
        assert_eq!(
            body::read_event_body_bytes(&reader, tool_ev, "tool.result", None).await?,
            Some(b"ok output".to_vec())
        );

        assert_eq!(unavail_ev.kind, CurrentHistoryEventKind::LegacyObserved);
        let unavail_env = body::decode_event_envelope(unavail_ev)?;
        assert_eq!(unavail_env.captured_at, Some(9_000));
        assert_eq!(unavail_env.data["legacyUnavailable"], true);

        let HistoryTimelineItem::Divider(input_div) = &timeline.items[3] else {
            panic!("expected single-input divider");
        };
        assert_eq!(input_div.kind, CurrentHistoryEventKind::InputAccepted);
        assert_eq!(
            body::read_event_body_bytes(&reader, input_div, "body", None).await?,
            Some(b"hello user prompt".to_vec())
        );

        reader.close().await;
        store.close().await?;
        Ok(())
    }
}
