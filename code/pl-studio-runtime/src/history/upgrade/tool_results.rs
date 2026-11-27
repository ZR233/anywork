//! Schema 27 result-format maintenance. The event and body table layouts are unchanged.

use sea_orm::{ConnectionTrait, SqliteTransactionMode, TransactionOptions, TransactionTrait};

use super::{
    BTreeMap, ImportCounts, Path, PendingReport, UpgradeFiles, UpgradeReport, UpgradeStatus,
    complete_pending_report, discard_rolled_back_pending_report, history_table_rows,
    prepare_directory, publish_backup, quick_check, schema26_manifest, stage_pending_report,
    vacuum_backup_candidate,
};
use crate::history::{
    BODY_CHUNK_BYTES, HistoryBody, HistoryBodyRole, HistoryError, HistoryEventBodyRef,
    HistoryEventKind, HistoryEventRecord, Result,
    body::{committed_manifest_body, committed_named_body},
    db::{self, statement},
    schema,
    writer_lease::WriterLease,
};
use crate::studio::storage::tool_result_upgrade::{
    OUTPUT_ARTIFACTS_KEY, decode_delivery, upgrade_artifacts,
};
use crate::studio::storage::tool_task::{BODY_KEY, upgrade_v1_body};

pub(in crate::history) const REVISION: i64 = 3;
const BACKUP_ROOT: &str = "migration-backups/history-27-tool-result";
const OLD_KEY: &str = schema26_manifest::TOOL_TASK_KEY;
const DELIVERY_KEY: &str = "canonical_payload";
const MATCH_OLD_RECEIPT: &str = "instr(payload_json, '\"native.tool-task.v1\"') > 0 OR EXISTS(\
    SELECT 1 FROM history_bodies AS b WHERE b.owner_event_id=e.event_id AND b.body_key=?) \
    OR (e.tool_name IN ('show_files','get_tool_task') AND instr(payload_json, '\"tool.output-artifacts\"') > 0) \
    OR (e.kind='background_delivery_recorded' AND e.payload_schema='anywork.business/1' \
        AND instr(payload_json, '\"canonical_payload\"') > 0)";

#[cfg(test)]
pub(super) mod tests;

pub(in crate::history) async fn mark_current(
    db: &impl ConnectionTrait,
) -> std::result::Result<(), sea_orm::DbErr> {
    db.execute_unprepared(&format!("PRAGMA user_version={REVISION}"))
        .await?;
    Ok(())
}

pub(in crate::history) async fn upgrade_needed(db: &impl ConnectionTrait) -> Result<bool> {
    Ok(schema26_manifest::revision(db).await? != REVISION)
}

pub(in crate::history) async fn require_current(db: &impl ConnectionTrait) -> Result<()> {
    if upgrade_needed(db).await? {
        schema26_manifest::require_current(db).await?;
        return Err(HistoryError::Integrity(
            "history requires tool-result maintenance".into(),
        ));
    }
    Ok(())
}

pub(super) async fn upgrade(
    path: &Path,
    session_dir: &Path,
    thread_id: &str,
    database_id: &str,
    files: UpgradeFiles,
) -> Result<Option<UpgradeReport>> {
    let backup_root = session_dir.join(BACKUP_ROOT);
    let pending_path = backup_root.join(super::PENDING_REPORT_FILE);
    let pending = PendingReport {
        path: &pending_path,
        backup_name: "history.v27.sqlite",
    };
    let read = schema::connect(path, true, false).await?;
    let needs_upgrade = upgrade_needed(&read).await?;
    read.close().await?;
    if !needs_upgrade && !pending.path.try_exists()? {
        return Ok(None);
    }
    let _lease = WriterLease::acquire(path)?;
    let db = schema::connect(path, false, false).await?;
    if schema::identity(&db, thread_id).await?.0 != database_id {
        return Err(HistoryError::Integrity(
            "tool-result maintenance source identity differs".into(),
        ));
    }
    if !upgrade_needed(&db).await? {
        db.close().await?;
        return if pending.path.try_exists()? {
            complete_pending_report(
                pending.path,
                thread_id,
                database_id,
                pending.backup_name,
                files,
            )
            .map(Some)
        } else {
            Ok(None)
        };
    }
    schema26_manifest::require_current(&db).await?;
    discard_rolled_back_pending_report(&pending, thread_id, database_id, files)?;
    let has_old = db
        .query_one_raw(statement(
            &format!("SELECT 1 FROM history_events AS e WHERE {MATCH_OLD_RECEIPT} LIMIT 1"),
            vec![OLD_KEY.into()],
        ))
        .await?
        .is_some();
    if !has_old {
        mark_current(&db).await?;
        db.close().await?;
        return Ok(None);
    }

    let operation_id = uuid::Uuid::new_v4().to_string();
    let operation_dir = backup_root.join(&operation_id);
    prepare_directory(session_dir, &operation_dir)?;
    let temporary = vacuum_backup_candidate(path, &operation_dir, 27).await?;
    let backup = schema::connect(&temporary, true, false).await?;
    if schema::identity(&backup, thread_id).await?.0 != database_id
        || !upgrade_needed(&backup).await?
    {
        return Err(HistoryError::Integrity(
            "tool-result backup identity or revision differs".into(),
        ));
    }
    quick_check(&backup).await?;
    let source_table_rows = history_table_rows(&backup).await?;
    backup.close().await?;
    let backup_path = operation_dir.join(pending.backup_name);
    publish_backup(&temporary, &backup_path, files)?;

    let tx = db
        .begin_with_options(TransactionOptions {
            sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
            ..Default::default()
        })
        .await?;
    tx.execute_unprepared("DROP TRIGGER history_events_no_update")
        .await?;
    let rewritten = convert_receipts(&tx, database_id).await?;
    tx.execute_unprepared(schema26_manifest::RESTORE_EVENT_UPDATE_TRIGGER)
        .await?;
    mark_current(&tx).await?;
    stage_pending_report(
        pending.path,
        &UpgradeReport {
            operation_id,
            thread_id: thread_id.into(),
            database_id: database_id.into(),
            status: UpgradeStatus::Upgraded,
            backup: Some(backup_path),
            current_original_backup: None,
            source_table_rows,
            imported_categories: rewritten.imported,
            backup_only_categories: BTreeMap::new(),
        },
        files,
    )?;
    tx.commit().await?;
    db.close().await?;
    complete_pending_report(
        pending.path,
        thread_id,
        database_id,
        pending.backup_name,
        files,
    )
    .map(Some)
}

async fn convert_receipts(db: &impl ConnectionTrait, database_id: &str) -> Result<ImportCounts> {
    let mut after = 0;
    let mut rewritten = ImportCounts::default();
    loop {
        let rows = db
            .query_all_raw(statement(
                &format!(
                    "SELECT seq,event_id FROM history_events AS e WHERE seq>? AND \
                ({MATCH_OLD_RECEIPT}) ORDER BY seq LIMIT 128"
                ),
                vec![after.into(), OLD_KEY.into()],
            ))
            .await?;
        if rows.is_empty() {
            return Ok(rewritten);
        }
        for row in rows {
            after = row.try_get::<i64>("", "seq")?;
            let event_id: String = row.try_get("", "event_id")?;
            let mut record = db::event(db, &event_id)
                .await?
                .ok_or_else(|| HistoryError::Integrity("tool receipt event disappeared".into()))?
                .record;
            if let Some(old) = committed_named_body(db, database_id, &record, OLD_KEY).await? {
                let call_id = record.call_id.as_deref().ok_or_else(|| {
                    HistoryError::Integrity("legacy tool receipt has no call identity".into())
                })?;
                let converted = upgrade_v1_body(&old, call_id)?;
                replace_manifest_entry(db, database_id, &mut record, OLD_KEY, BODY_KEY, converted)
                    .await?;
                rewritten.imported("tool_receipts_upgraded", 1);
            } else if db
                .query_one_raw(statement(
                    "SELECT 1 FROM history_bodies WHERE owner_event_id=? AND body_key=?",
                    vec![event_id.into(), OLD_KEY.into()],
                ))
                .await?
                .is_some()
            {
                return Err(HistoryError::Integrity(
                    "legacy tool receipt has no body manifest".into(),
                ));
            }

            if let Some(tool) = record
                .tool_name
                .as_deref()
                .filter(|tool| matches!(*tool, "show_files" | "get_tool_task"))
                && let Some(old) =
                    committed_manifest_body(db, database_id, &record, OUTPUT_ARTIFACTS_KEY, false)
                        .await?
                && let Some(bytes) = upgrade_artifacts(tool, &old)?
            {
                let mut body = HistoryBody::new(
                    "tool.output-artifacts.v2",
                    HistoryBodyRole::Attachment,
                    bytes,
                );
                body.media_type = Some("application/json".into());
                replace_manifest_entry(
                    db,
                    database_id,
                    &mut record,
                    OUTPUT_ARTIFACTS_KEY,
                    OUTPUT_ARTIFACTS_KEY,
                    body,
                )
                .await?;
                rewritten.imported("tool_artifacts_upgraded", 1);
            }

            if record.kind == HistoryEventKind::BackgroundDeliveryRecorded
                && record.payload_schema == "anywork.business/1"
                && let Some(old) =
                    committed_manifest_body(db, database_id, &record, DELIVERY_KEY, false).await?
                && serde_json::from_slice::<serde_json::Value>(&old)?
                    .pointer("/output/payload")
                    .is_some()
            {
                let delivery = decode_delivery(&old)?;
                if record.call_id.as_deref() != Some(&delivery.call_id) {
                    return Err(HistoryError::Integrity(
                        "legacy delivery call identity mismatch".into(),
                    ));
                }
                let mut body = HistoryBody::new(
                    "native.tool-delivery.v2",
                    HistoryBodyRole::CanonicalPayload,
                    serde_json::to_vec(&delivery)?,
                );
                body.media_type = Some("application/json".into());
                replace_manifest_entry(
                    db,
                    database_id,
                    &mut record,
                    DELIVERY_KEY,
                    DELIVERY_KEY,
                    body,
                )
                .await?;
                rewritten.imported("tool_deliveries_upgraded", 1);
            }
        }
    }
}

async fn replace_manifest_entry(
    db: &impl ConnectionTrait,
    database_id: &str,
    event: &mut HistoryEventRecord,
    old_key: &str,
    logical_key: &str,
    converted: HistoryBody,
) -> Result<()> {
    let mut document: serde_json::Value = serde_json::from_str(&event.payload_json)?;
    let entries = document
        .get_mut("bodies")
        .and_then(serde_json::Value::as_array_mut)
        .ok_or_else(|| HistoryError::Integrity("tool receipt has no body list".into()))?;
    if old_key != logical_key
        && entries
            .iter()
            .any(|entry| entry.get("key").and_then(serde_json::Value::as_str) == Some(logical_key))
    {
        return Err(HistoryError::Integrity(
            "tool receipt contains both format versions".into(),
        ));
    }
    let old_entry = entries
        .iter_mut()
        .find(|entry| entry.get("key").and_then(serde_json::Value::as_str) == Some(old_key))
        .ok_or_else(|| HistoryError::Integrity("legacy tool receipt manifest changed".into()))?;
    let row = db.query_one_raw(statement(
        "SELECT COALESCE(MAX(ordinal),-1)+1 AS ordinal FROM history_bodies WHERE owner_event_id=?",
        vec![event.event_id.clone().into()],
    )).await?.ok_or_else(|| HistoryError::Integrity("tool receipt body ordinal is missing".into()))?;
    let ordinal = super::db_u64(row.try_get("", "ordinal")?, "tool receipt body ordinal")?;
    let digest = converted.digest();
    let header = db::Body {
        id: converted.body_id.clone(),
        owner: event.event_id.clone(),
        ordinal,
        key: converted.body_key,
        role: converted.role,
        length: converted.bytes.len() as u64,
        media_type: converted.media_type,
        digest,
    };
    db::insert_body_header(db, &header).await?;
    for (index, bytes) in converted.bytes.chunks(BODY_CHUNK_BYTES).enumerate() {
        db.execute_raw(statement(
            "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
            vec![
                header.id.clone().into(),
                db::number(index as u64)?.into(),
                bytes.to_vec().into(),
            ],
        ))
        .await?;
    }
    let reference = HistoryEventBodyRef {
        database_id: database_id.into(),
        owner_event_id: event.event_id.clone(),
        body_key: header.key.clone(),
        body_id: header.id,
        byte_start: 0,
        byte_length: header.length,
    };
    *old_entry = serde_json::to_value(crate::history::HistoryBodyManifestEntry {
        key: logical_key.into(),
        role: header.role.as_str().into(),
        byte_length: header.length,
        media_type: header.media_type,
        inline_text: None,
        reference: Some(reference),
    })?;
    event.payload_json = serde_json::to_string(&document)?;
    db.execute_raw(statement(
        "UPDATE history_events SET payload_json=? WHERE event_id=?",
        vec![
            event.payload_json.clone().into(),
            event.event_id.clone().into(),
        ],
    ))
    .await?;
    Ok(())
}
