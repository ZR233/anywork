//! One-time Schema 26 maintenance. Schema major stays 26.
//!
//! Already-imported usage rows may still name their billing body `canonical_payload`, and
//! native tool receipts may exist only as `history_bodies` rows. Readers now look up
//! `payload_json.bodies[]` and do not scan those legacy keys. This pass rewrites the manifest
//! before upgrading typed product Turn failures. Both passes keep existing body rows and chunks,
//! and the append-only trigger is restored before commit.

use sea_orm::{
    ConnectionTrait, DatabaseConnection, SqliteTransactionMode, TransactionOptions,
    TransactionTrait,
};

use super::super::{HistoryError, Result, db::statement};

pub(super) const LEGACY_USAGE_KEY: &str = "canonical_payload";
pub(super) const ACCOUNTING_KEY: &str = "accounting";
pub(super) const TOOL_TASK_KEY: &str = "native.tool-task.v1";

// The schema major remains in history_store_meta; user_version records this maintenance.
const MANIFEST_REVISION: i64 = 1;
const CURRENT_REVISION: i64 = 2;

const RESTORE_EVENT_UPDATE_TRIGGER: &str = "\
CREATE TRIGGER history_events_no_update
BEFORE UPDATE ON history_events BEGIN
    SELECT RAISE(ABORT, 'history events are append-only');
END;";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct StoredBody {
    pub body_id: String,
    pub body_key: String,
    pub role: String,
    pub byte_length: u64,
    pub media_type: Option<String>,
}

pub(super) fn rewrite_payload(
    payload_json: &str,
    accounting: bool,
    database_id: &str,
    event_id: &str,
    stored: &[StoredBody],
) -> Result<Option<String>> {
    let mut value: serde_json::Value = serde_json::from_str(payload_json).map_err(|error| {
        HistoryError::Integrity(format!("payload_json is not valid JSON: {error}"))
    })?;
    if !value.is_object() {
        return Err(HistoryError::Integrity(
            "payload_json must be a JSON object".into(),
        ));
    }
    let mut changed = false;
    if accounting {
        changed |= rename_usage_keys(&mut value)?;
    }
    changed |= index_missing(accounting, database_id, event_id, stored, &mut value)?;
    if !changed {
        return Ok(None);
    }
    Ok(Some(serde_json::to_string(&value)?))
}

pub(in crate::history) async fn repair_needed(db: &impl ConnectionTrait) -> Result<bool> {
    Ok(revision(db).await? != CURRENT_REVISION)
}

pub(in crate::history) async fn require_current(db: &impl ConnectionTrait) -> Result<()> {
    if repair_needed(db).await? {
        return Err(HistoryError::Integrity(
            "history requires schema 26 maintenance".into(),
        ));
    }
    Ok(())
}

async fn revision(db: &impl ConnectionTrait) -> Result<i64> {
    let row = db
        .query_one_raw(statement("PRAGMA user_version", vec![]))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history maintenance revision is missing".into()))?;
    let version: i64 = row.try_get("", "user_version")?;
    match version {
        0 | MANIFEST_REVISION | CURRENT_REVISION => Ok(version),
        _ => Err(HistoryError::Integrity(format!(
            "unsupported history maintenance revision {version}"
        ))),
    }
}

pub(in crate::history) async fn mark_current(
    db: &impl ConnectionTrait,
) -> std::result::Result<(), sea_orm::DbErr> {
    db.execute_unprepared(&format!("PRAGMA user_version={CURRENT_REVISION}"))
        .await?;
    Ok(())
}

pub(super) async fn repair(
    db: &DatabaseConnection,
    database_id: &str,
    stage_report: impl FnOnce(u64) -> Result<()>,
) -> Result<()> {
    let tx = db
        .begin_with_options(TransactionOptions {
            sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
            ..Default::default()
        })
        .await?;
    require_schema26(&tx).await?;
    let revision = revision(&tx).await?;
    if revision == CURRENT_REVISION {
        return Err(HistoryError::Conflict(
            "history maintenance revision already changed".into(),
        ));
    }
    stage_report(repair_in_transaction(&tx, database_id, revision == 0).await?)?;
    tx.commit().await?;
    Ok(())
}

// The v25 upgrade already indexed bodies while lifting the events. Its caller holds the outer
// migration transaction and the original backup, just as the schema 26 maintenance entry does.
pub(super) async fn repair_in_transaction(
    db: &impl ConnectionTrait,
    database_id: &str,
    repair_manifest: bool,
) -> Result<u64> {
    db.execute_unprepared("DROP TRIGGER history_events_no_update")
        .await?;
    if repair_manifest {
        rewrite_open_events(db, database_id).await?;
    }
    let rewritten = super::provider_failure::migrate(db, database_id).await?;
    db.execute_unprepared(RESTORE_EVENT_UPDATE_TRIGGER).await?;
    mark_current(db).await?;
    Ok(rewritten)
}

fn rename_usage_keys(value: &mut serde_json::Value) -> Result<bool> {
    let Some(bodies) = value
        .get_mut("bodies")
        .and_then(serde_json::Value::as_array_mut)
    else {
        return Ok(false);
    };
    let mut changed = false;
    let mut accounting_keys = 0usize;
    for entry in bodies.iter_mut() {
        let Some(key) = entry.get("key").and_then(serde_json::Value::as_str) else {
            continue;
        };
        if key == LEGACY_USAGE_KEY {
            entry
                .as_object_mut()
                .ok_or_else(|| {
                    HistoryError::Integrity("body manifest entry must be an object".into())
                })?
                .insert(
                    String::from("key"),
                    serde_json::Value::String(ACCOUNTING_KEY.into()),
                );
            changed = true;
        }
        if entry.get("key").and_then(serde_json::Value::as_str) == Some(ACCOUNTING_KEY) {
            accounting_keys += 1;
        }
    }
    if accounting_keys > 1 {
        return Err(HistoryError::Integrity(
            "accounting event has more than one billing body".into(),
        ));
    }
    Ok(changed)
}

fn index_missing(
    accounting: bool,
    database_id: &str,
    event_id: &str,
    stored: &[StoredBody],
    value: &mut serde_json::Value,
) -> Result<bool> {
    let mut additions = Vec::new();
    for body in stored {
        let Some(lookup_key) = lookup_key(accounting, &body.body_key) else {
            continue;
        };
        if referenced(value, &body.body_id) {
            continue;
        }
        if has_key(value, lookup_key) {
            return Err(HistoryError::Integrity(format!(
                "event {event_id} already indexes {lookup_key} under a different body"
            )));
        }
        if database_id.is_empty() {
            return Err(HistoryError::Integrity(
                "history database identity is required to index an existing body".into(),
            ));
        }
        additions.push(reference_entry(lookup_key, database_id, event_id, body));
    }
    if additions.is_empty() {
        return Ok(false);
    }
    let bodies = bodies_mut(value)?;
    bodies.extend(additions);
    Ok(true)
}

fn lookup_key(accounting: bool, body_key: &str) -> Option<&'static str> {
    if body_key == TOOL_TASK_KEY {
        Some(TOOL_TASK_KEY)
    } else if accounting && body_key == LEGACY_USAGE_KEY {
        Some(ACCOUNTING_KEY)
    } else {
        None
    }
}

fn referenced(value: &serde_json::Value, body_id: &str) -> bool {
    value
        .get("bodies")
        .and_then(serde_json::Value::as_array)
        .is_some_and(|bodies| {
            bodies.iter().any(|entry| {
                entry
                    .pointer("/reference/bodyId")
                    .and_then(serde_json::Value::as_str)
                    == Some(body_id)
            })
        })
}

fn has_key(value: &serde_json::Value, key: &str) -> bool {
    value
        .get("bodies")
        .and_then(serde_json::Value::as_array)
        .is_some_and(|bodies| {
            bodies
                .iter()
                .any(|entry| entry.get("key").and_then(serde_json::Value::as_str) == Some(key))
        })
}

fn bodies_mut(value: &mut serde_json::Value) -> Result<&mut Vec<serde_json::Value>> {
    let object = value
        .as_object_mut()
        .ok_or_else(|| HistoryError::Integrity("payload_json must be a JSON object".into()))?;
    let entry = object
        .entry(String::from("bodies"))
        .or_insert_with(|| serde_json::Value::Array(Vec::new()));
    entry
        .as_array_mut()
        .ok_or_else(|| HistoryError::Integrity("payload bodies must be an array".into()))
}

fn reference_entry(
    key: &str,
    database_id: &str,
    event_id: &str,
    body: &StoredBody,
) -> serde_json::Value {
    let mut entry = serde_json::json!({
        "key": key,
        "role": body.role,
        "byteLength": body.byte_length,
        "reference": {
            "databaseId": database_id,
            "ownerEventId": event_id,
            "bodyKey": body.body_key,
            "bodyId": body.body_id,
            "byteStart": 0,
            "byteLength": body.byte_length,
        }
    });
    if let Some(media_type) = &body.media_type {
        entry
            .as_object_mut()
            .expect("manifest entry is an object")
            .insert(
                String::from("mediaType"),
                serde_json::Value::String(media_type.clone()),
            );
    }
    entry
}

async fn require_schema26(db: &impl ConnectionTrait) -> Result<()> {
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history identity is missing".into()))?;
    if row.try_get::<i64>("", "schema_version")? != 26 {
        return Err(HistoryError::Integrity(
            "schema 26 manifest repair requires schema 26".into(),
        ));
    }
    Ok(())
}

async fn rewrite_open_events(db: &impl ConnectionTrait, database_id: &str) -> Result<()> {
    let mut after = 0i64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT e.seq, e.event_id, e.row_scope, e.payload_json
                 FROM history_events AS e
                 WHERE e.seq > ? AND (e.row_scope = 'accounting' OR EXISTS (
                     SELECT 1 FROM history_bodies AS b
                     WHERE b.owner_event_id = e.event_id AND b.body_key = 'native.tool-task.v1'
                 ))
                 ORDER BY e.seq LIMIT 128",
                vec![after.into()],
            ))
            .await?;
        if rows.is_empty() {
            return Ok(());
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let event_id: String = row.try_get("", "event_id")?;
            let scope: Option<String> = row.try_get("", "row_scope")?;
            let payload: String = row.try_get("", "payload_json")?;
            let stored = stored_bodies(db, &event_id).await?;
            if let Some(payload) = rewrite_payload(
                &payload,
                scope.as_deref() == Some("accounting"),
                database_id,
                &event_id,
                &stored,
            )? {
                db.execute_raw(statement(
                    "UPDATE history_events SET payload_json=? WHERE event_id=?",
                    vec![payload.into(), event_id.into()],
                ))
                .await?;
            }
        }
    }
}

#[cfg(test)]
async fn database_id(db: &impl ConnectionTrait) -> Result<String> {
    let row = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history identity is missing".into()))?;
    let database_id: String = row.try_get("", "database_id")?;
    if database_id.is_empty() {
        return Err(HistoryError::Integrity(
            "invalid history database identity".into(),
        ));
    }
    Ok(database_id)
}

#[cfg(test)]
async fn payload_json(db: &impl ConnectionTrait, event_id: &str) -> Result<String> {
    let row = db
        .query_one_raw(statement(
            "SELECT payload_json FROM history_events WHERE event_id=?",
            vec![event_id.into()],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity(format!("manifest repair lost event {event_id}")))?;
    Ok(row.try_get("", "payload_json")?)
}

async fn stored_bodies(db: &impl ConnectionTrait, event_id: &str) -> Result<Vec<StoredBody>> {
    let rows = db
        .query_all_raw(statement(
            "SELECT body_id, body_key, role, byte_length, media_type
             FROM history_bodies
             WHERE owner_event_id=?
               AND body_key IN ('canonical_payload', 'native.tool-task.v1')
             ORDER BY ordinal ASC",
            vec![event_id.into()],
        ))
        .await?;
    rows.into_iter()
        .map(|row| {
            let byte_length = u64::try_from(row.try_get::<i64>("", "byte_length")?)
                .map_err(|_| HistoryError::Integrity("negative history body length".into()))?;
            Ok(StoredBody {
                body_id: row.try_get("", "body_id")?,
                body_key: row.try_get("", "body_key")?,
                role: row.try_get("", "role")?,
                byte_length,
                media_type: row.try_get("", "media_type")?,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::history::{HistoryBusinessRowHead, HistoryDemand, HistoryLimits, HistoryStore};
    use crate::{ProviderFailureKind, TurnState};
    use serde_json::json;
    use sha2::Digest;

    fn legacy_failed_turn(thread_id: &str, kind: &str) -> serde_json::Value {
        json!({
            "id": "turn-old", "threadId": thread_id, "revision": 2, "updatedAt": 20,
            "state": {"kind": "failed", "data": {
                "startedAt": 10, "completedAt": 20, "failure": {
                    "category": if kind == "capacity" { "providerCapacity" } else { "provider" },
                    "providerKind": kind,
                    "code": "old-provider-code", "httpStatus": 429, "message": "old diagnostic",
                    "retry": {"kind": "retryable", "retry_after_ms": u64::MAX}
                }
            }}
        })
    }

    #[tokio::test]
    async fn schema26_migrates_legacy_provider_failure_turns() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let schema = super::super::super::schema::connect(&path, false, true).await?;
        let thread_id = "legacy-provider-failures";
        super::super::super::schema::initialize(&schema, thread_id).await?;
        schema.execute_unprepared("PRAGMA user_version=1").await?;

        let turn = legacy_failed_turn(thread_id, "capacity").to_string();
        let detail = json!({
            "head": {
                "turnId": "turn-old", "state": "failed",
                "contextDisposition": "active", "updatedAt": 20000, "detailEventId": "detail"
            },
            "bodies": [{"key": "turn_detail", "role": "canonical_payload",
                        "byteLength": turn.len(), "inlineText": turn}]
        });
        insert_event(
            &schema,
            1,
            "detail",
            Some(("turn", "turn:turn-old")),
            &detail.to_string(),
            "anywork.turn/1",
        )
        .await?;
        let timeline = json!({
            "contract": "anywork.event/1", "type": "turn",
            "meta": {
                "entityId": "receipt", "entityKind": "turnReceipt", "delivery": "foreground",
                "state": {"kind":"knownTerminal","outcome":"failed"},
                "startedAt": 10000, "finishedAt": 20000
            },
            "data": { "outcome": legacy_failed_turn(thread_id, "configuration")["state"] }
        });
        insert_event(
            &schema,
            2,
            "receipt",
            None,
            &timeline.to_string(),
            "anywork.event/1",
        )
        .await?;
        let mut raw = timeline.clone();
        raw["type"] = json!("raw");
        let raw = raw.to_string();
        insert_event(&schema, 3, "unrelated", None, &raw, "anywork.event/1").await?;
        let database = database_id(&schema).await?;
        let original = insert_chunked_turn(&schema, &database, thread_id).await?;
        schema.close().await?;
        let Err(rejected) =
            HistoryStore::open_reader(&path, thread_id, HistoryLimits::default()).await
        else {
            panic!("ordinary reader accepted an unmaintained database");
        };
        assert!(
            rejected
                .to_string()
                .contains("requires schema 26 maintenance")
        );

        let report = super::super::upgrade_history(&path, thread_id, directory.path()).await?;
        assert_eq!(report.status, super::super::UpgradeStatus::Upgraded);
        assert_eq!(report.imported_categories["turn_payloads_rewritten"], 3);
        let backup =
            super::super::super::schema::connect(report.backup.as_ref().unwrap(), true, false)
                .await?;
        assert_eq!(payload_json(&backup, "detail").await?, detail.to_string());
        assert_eq!(
            payload_json(&backup, "receipt").await?,
            timeline.to_string()
        );
        assert_eq!(revision(&backup).await?, 1);
        backup.close().await?;

        let reader = HistoryStore::open_reader(&path, thread_id, HistoryLimits::default()).await?;
        let turns = reader
            .turns_page(None, None, HistoryDemand::default())
            .await?;
        assert_eq!(turns.entries.len(), 2);
        let original_chunked: crate::Turn = {
            let mut expected: serde_json::Value = serde_json::from_str(&original)?;
            let failure = &mut expected["state"]["data"]["failure"];
            failure["retry"]["retryAfterMs"] = json!("18446744073709551615");
            failure["recovery"]["effectiveWaitMillis"] = json!("18446744073709551615");
            serde_json::from_value(expected)?
        };
        let mut states = Vec::new();
        for entry in turns.entries {
            let HistoryBusinessRowHead::Turn(head) = entry.head else {
                panic!("expected a Turn row")
            };
            let turn = crate::studio::runtime::history_turn(&reader, head).await?;
            if turn.id == "turn-chunked" {
                assert_eq!(turn, original_chunked);
            } else {
                states.push(turn.state);
            }
        }
        let receipt = reader
            .read_event("receipt".into(), HistoryDemand::default())
            .await?;
        let receipt = crate::history::decode_event_envelope(&receipt)?;
        let receipt_retry = &receipt.data["outcome"]["data"]["failure"]["retry"];
        assert_eq!(
            receipt_retry["retryAfterMs"].as_str(),
            Some("18446744073709551615")
        );
        assert!(receipt_retry.get("retry_after_ms").is_none());
        states.push(serde_json::from_value::<TurnState>(
            receipt.data["outcome"].clone(),
        )?);
        for state in states {
            let TurnState::Failed(state) = state else {
                panic!("expected a failed Turn")
            };
            let failure = state.failure();
            assert_eq!(failure.provider_kind, Some(ProviderFailureKind::Unknown));
            assert_eq!(failure.retry.retry_after_ms(), Some(u64::MAX));
            assert_eq!(failure.code.as_deref(), Some("old-provider-code"));
            assert_eq!(failure.http_status, Some(429));
            assert_eq!(failure.message, "old diagnostic");
            assert!(failure.recovery.is_none());
        }
        assert_eq!(
            reader
                .read_event("unrelated".into(), HistoryDemand::default())
                .await?
                .payload_json,
            raw
        );
        let chunked = reader
            .read_event("chunked".into(), HistoryDemand::default())
            .await?;
        let migrated =
            crate::history::read_event_body_bytes(&reader, &chunked, "turn_detail", None)
                .await?
                .unwrap();
        let chunked_turn: serde_json::Value = serde_json::from_slice(&migrated)?;
        let chunked_failure = &chunked_turn["state"]["data"]["failure"];
        assert_eq!(
            chunked_failure["retry"]["retryAfterMs"].as_str(),
            Some("18446744073709551615")
        );
        assert_eq!(
            chunked_failure["recovery"]["effectiveWaitMillis"].as_str(),
            Some("18446744073709551615")
        );
        let manifest: serde_json::Value = serde_json::from_str(&chunked.payload_json)?;
        let reference: crate::history::HistoryEventBodyRef =
            serde_json::from_value(manifest["bodies"][0]["reference"].clone())?;
        assert_eq!(manifest["bodies"][0]["byteLength"], migrated.len());
        assert_eq!(reference.byte_length, migrated.len() as u64);
        assert_ne!(reference.body_id, "old-body");
        reader.close().await;

        let second = super::super::upgrade_history(&path, thread_id, directory.path()).await?;
        assert_eq!(second.status, super::super::UpgradeStatus::AlreadySchema26);
        assert!(second.backup.is_none());
        let reader = HistoryStore::open_reader(&path, thread_id, HistoryLimits::default()).await?;
        assert_eq!(
            reader
                .read_event("chunked".into(), HistoryDemand::default())
                .await?
                .payload_json,
            chunked.payload_json
        );
        reader.close().await;

        let db = super::super::super::schema::connect(&path, true, false).await?;
        assert_eq!(revision(&db).await?, CURRENT_REVISION);
        let original_chunks = db
            .query_all_raw(statement(
                "SELECT data FROM history_body_chunks WHERE body_id='old-body' ORDER BY chunk_no",
                vec![],
            ))
            .await?;
        assert_eq!(original_chunks.len(), 2);
        let mut original_bytes = Vec::new();
        for chunk in original_chunks {
            original_bytes.extend(chunk.try_get::<Vec<u8>>("", "data")?);
        }
        assert_eq!(original_bytes, original.as_bytes());
        let body = super::super::super::db::body(&db, &reference.body_id)
            .await?
            .unwrap();
        assert_eq!(body.digest, sha2::Sha256::digest(&migrated).to_vec());
        assert_eq!(
            super::super::history_table_rows(&db).await?["history_bodies"],
            2
        );
        db.close().await?;
        Ok(())
    }

    async fn insert_chunked_turn(
        db: &impl ConnectionTrait,
        database_id: &str,
        thread_id: &str,
    ) -> Result<String> {
        let mut turn = legacy_failed_turn(thread_id, "unknown");
        turn["id"] = json!("turn-chunked");
        let failure = &mut turn["state"]["data"]["failure"];
        failure["message"] = json!("旧诊断".repeat(8_000));
        failure["retry"] = json!({"kind":"retryable","retryAfterMs":u64::MAX});
        failure["recovery"] = json!({"effectiveWaitMillis":u64::MAX});
        let turn = turn.to_string();
        let detail = json!({
            "head": {"turnId":"turn-chunked","state":"failed","contextDisposition":"active",
                     "updatedAt":20000,"detailEventId":"chunked"},
            "bodies": [{"key":"turn_detail","role":"canonical_payload","byteLength":turn.len(),
                        "reference": {"databaseId":database_id,"ownerEventId":"chunked","bodyId":"old-body",
                                      "bodyKey":"turn_detail","byteStart":0,"byteLength":turn.len()}}]
        });
        insert_event(
            db,
            4,
            "chunked",
            Some(("turn", "turn:turn-chunked")),
            &detail.to_string(),
            "anywork.turn/1",
        )
        .await?;
        insert_body(
            db,
            "old-body",
            "chunked",
            "turn_detail",
            "canonical_payload",
            turn.as_bytes(),
        )
        .await?;
        Ok(turn)
    }

    #[tokio::test]
    async fn schema26_backup_publish_failure_preserves_crashed_wal() -> Result<()> {
        use super::super::{
            BACKUP_ROOT_SCHEMA26, SCHEMA26_BACKUP_NAME, UpgradeFiles,
            migration_tests::move_with_target_conflict, upgrade_history,
            upgrade_history_with_files,
        };
        use crate::history::schema;
        use std::io;

        const THREAD: &str = "schema26-backup-crashed-wal";
        const CHILD_PATH: &str = "ANYWORK_TEST_SCHEMA26_BACKUP_CRASH_DB";
        if let Some(path) = std::env::var_os(CHILD_PATH) {
            let db = schema::connect(std::path::Path::new(&path), false, false).await?;
            db.execute_unprepared("PRAGMA wal_autocheckpoint=0").await?;
            insert_chunked_turn(&db, &database_id(&db).await?, THREAD).await?;
            // Leave the committed WAL behind without running SQLite's last-close checkpoint.
            std::process::exit(0);
        }

        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let wal_path = path.with_extension("sqlite-wal");
        let db = schema::connect(&path, false, true).await?;
        schema::initialize(&db, THREAD).await?;
        db.execute_unprepared("PRAGMA user_version=1").await?;
        db.close().await?;
        let original_main = std::fs::read(&path)?;
        assert!(!wal_path.exists());

        let test_name = concat!(
            module_path!(),
            "::schema26_backup_publish_failure_preserves_crashed_wal"
        );
        let (_, test_name) = test_name.split_once("::").unwrap();
        let mut child = tokio::process::Command::new(std::env::current_exe()?)
            .args(["--exact", test_name, "--nocapture"])
            .env(CHILD_PATH, &path)
            .kill_on_drop(true)
            .spawn()?;
        let result = tokio::time::timeout(std::time::Duration::from_secs(60), child.wait()).await;
        let status = match result {
            Ok(status) => status?,
            Err(error) => {
                child.kill().await?;
                return Err(HistoryError::Storage(error.into()));
            }
        };
        assert!(status.success(), "WAL fixture child returned {status}");
        let original_wal = std::fs::read(&wal_path)?;
        assert!(original_wal.len() > 32, "WAL fixture has no frames");
        assert!(
            std::fs::read(&path)? == original_main,
            "fixture already checkpointed"
        );

        let files = UpgradeFiles {
            move_owned_path: |source, target| {
                move_with_target_conflict(source, target, SCHEMA26_BACKUP_NAME)
            },
            ..UpgradeFiles::DISK
        };
        let error = upgrade_history_with_files(&path, THREAD, directory.path(), files)
            .await
            .unwrap_err();
        assert!(
            matches!(error, HistoryError::Io(ref error) if error.kind() == io::ErrorKind::AlreadyExists),
            "{error:#}"
        );
        let operation = std::fs::read_dir(directory.path().join(BACKUP_ROOT_SCHEMA26))?
            .next()
            .unwrap()?
            .path();
        assert!(!operation.join(SCHEMA26_BACKUP_NAME).exists());
        let files = std::fs::read_dir(&operation)?.collect::<std::io::Result<Vec<_>>>()?;
        assert_eq!(files.len(), 1);
        let backup = schema::connect(&files[0].path(), true, false).await?;
        assert_eq!(revision(&backup).await?, 1);
        let wal_only = payload_json(&backup, "chunked").await?;
        let wal_counts = super::super::history_table_rows(&backup).await?;
        assert_eq!(wal_counts["history_bodies"], 1);
        assert_eq!(wal_counts["history_body_chunks"], 2);
        backup.close().await?;

        assert!(
            std::fs::read(&path)? == original_main,
            "backup changed the main database before publication"
        );
        assert!(
            std::fs::read(&wal_path)? == original_wal,
            "backup changed the uncheckpointed WAL before publication"
        );

        let report = upgrade_history(&path, THREAD, directory.path()).await?;
        let backup = schema::connect(report.backup.as_deref().unwrap(), true, false).await?;
        assert_eq!(payload_json(&backup, "chunked").await?, wal_only);
        assert_eq!(super::super::history_table_rows(&backup).await?, wal_counts);
        backup.close().await?;
        let reader = HistoryStore::open_reader(&path, THREAD, HistoryLimits::default()).await?;
        let turns = reader
            .turns_page(None, None, HistoryDemand::default())
            .await?;
        let HistoryBusinessRowHead::Turn(head) = &turns.entries[0].head else {
            panic!("expected a Turn row")
        };
        let turn = crate::studio::runtime::history_turn(&reader, head.clone()).await?;
        assert_eq!(turn.id, "turn-chunked");
        reader.close().await;
        Ok(())
    }

    #[tokio::test]
    async fn schema26_turn_migration_rejects_oversized_final_chunk() -> Result<()> {
        schema26_turn_migration_rejects_chunks(
            "UPDATE history_body_chunks SET data=CAST(data || X'01' AS BLOB) \
             WHERE body_id='old-body' AND chunk_no=1",
        )
        .await
    }

    #[tokio::test]
    async fn schema26_turn_migration_rejects_extra_chunk() -> Result<()> {
        schema26_turn_migration_rejects_chunks(
            "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES('old-body',2,X'01')",
        )
        .await
    }

    async fn schema26_turn_migration_rejects_chunks(corruption: &str) -> Result<()> {
        use super::super::{BACKUP_ROOT_SCHEMA26, PENDING_REPORT_FILE, upgrade_history};
        use crate::history::schema;

        const THREAD: &str = "schema26-invalid-turn-chunks";
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let db = schema::connect(&path, false, true).await?;
        schema::initialize(&db, THREAD).await?;
        db.execute_unprepared("PRAGMA user_version=1").await?;
        let earlier = json!({
            "contract":"anywork.event/1", "type":"turn",
            "data": {"outcome":legacy_failed_turn(THREAD,"configuration")["state"]}
        })
        .to_string();
        insert_event(&db, 1, "earlier-receipt", None, &earlier, "anywork.event/1").await?;
        insert_chunked_turn(&db, &database_id(&db).await?, THREAD).await?;
        let original = payload_json(&db, "chunked").await?;
        let trigger: String = db
            .query_one_raw(statement(
                "SELECT sql FROM sqlite_schema WHERE name='history_body_chunks_no_update'",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "sql")?;
        db.execute_unprepared("DROP TRIGGER history_body_chunks_no_update")
            .await?;
        db.execute_unprepared(corruption).await?;
        db.execute_unprepared(&trigger).await?;
        let before_counts = super::super::history_table_rows(&db).await?;
        db.close().await?;

        let result = upgrade_history(&path, THREAD, directory.path()).await;
        assert!(
            matches!(&result, Err(HistoryError::Integrity(message))
                if message.contains("event chunked") && message.contains("chunk layout")),
            "{result:?}"
        );
        let backups = directory.path().join(BACKUP_ROOT_SCHEMA26);
        assert!(!backups.join(PENDING_REPORT_FILE).exists());
        let operation = std::fs::read_dir(backups)?.next().unwrap()?.path();
        assert!(!operation.join("upgrade-report.json").exists());
        assert!(operation.join(super::super::SCHEMA26_BACKUP_NAME).is_file());
        let db = schema::connect(&path, false, false).await?;
        assert_eq!(revision(&db).await?, 1);
        assert_eq!(payload_json(&db, "chunked").await?, original);
        assert_eq!(payload_json(&db, "earlier-receipt").await?, earlier);
        assert_eq!(super::super::history_table_rows(&db).await?, before_counts);
        let error = db
            .execute_unprepared("UPDATE history_events SET recorded_at=recorded_at")
            .await
            .unwrap_err();
        assert!(error.to_string().contains("append-only"), "{error}");
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn schema26_maintenance_failure_preserves_original_events_and_bodies() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "maintenance-rollback";
        let db = super::super::super::schema::connect(&path, false, true).await?;
        super::super::super::schema::initialize(&db, thread_id).await?;
        db.execute_unprepared("PRAGMA user_version=1").await?;
        let database = database_id(&db).await?;
        insert_chunked_turn(&db, &database, thread_id).await?;
        let original = payload_json(&db, "chunked").await?;
        let mut malformed = legacy_failed_turn(thread_id, "capacity");
        malformed["state"]["data"]["failure"]["retry"]["retryAfterMs"] = json!(4000);
        let malformed = json!({"contract":"anywork.event/1", "type":"turn", "data":{"outcome":malformed["state"]}}).to_string();
        insert_event(&db, 5, "malformed", None, &malformed, "anywork.event/1").await?;
        db.close().await?;

        let backups = directory.path().join(super::super::BACKUP_ROOT_SCHEMA26);
        std::fs::create_dir_all(backups.parent().unwrap())?;
        std::fs::write(&backups, "prevent the backup directory from being created")?;
        let error = super::super::upgrade_history(&path, thread_id, directory.path())
            .await
            .unwrap_err();
        assert!(matches!(error, HistoryError::Io(_)), "{error}");
        let db = super::super::super::schema::connect(&path, true, false).await?;
        assert_eq!(payload_json(&db, "chunked").await?, original);
        assert_eq!(revision(&db).await?, 1);
        db.close().await?;

        std::fs::remove_file(&backups)?;
        let error = super::super::upgrade_history(&path, thread_id, directory.path())
            .await
            .unwrap_err();
        assert!(
            matches!(&error, HistoryError::Integrity(message)
                if message.contains("event malformed")
                    && message.contains("conflicting historical Turn retry wait")),
            "{error}"
        );
        assert!(!backups.join(super::super::PENDING_REPORT_FILE).exists());
        let operation = std::fs::read_dir(backups)?.next().unwrap()?.path();
        assert!(!operation.join("upgrade-report.json").exists());
        let preserved = operation.join(super::super::SCHEMA26_BACKUP_NAME);
        let backup = super::super::super::schema::connect(&preserved, true, false).await?;
        assert_eq!(payload_json(&backup, "malformed").await?, malformed);
        backup.close().await?;
        let db = super::super::super::schema::connect(&path, false, false).await?;
        assert_eq!(revision(&db).await?, 1);
        assert_eq!(payload_json(&db, "chunked").await?, original);
        assert_eq!(payload_json(&db, "malformed").await?, malformed);
        assert_eq!(
            super::super::history_table_rows(&db).await?["history_bodies"],
            1
        );
        let error = db
            .execute_unprepared("UPDATE history_events SET recorded_at=recorded_at")
            .await
            .unwrap_err();
        assert!(error.to_string().contains("append-only"), "{error}");
        db.close().await?;
        Ok(())
    }

    fn usage_payload(database_id: &str) -> String {
        serde_json::json!({
            "head": { "inferenceCount": 1 },
            "bodies": [{
                "key": LEGACY_USAGE_KEY,
                "role": "canonical_payload",
                "byteLength": 2,
                "reference": {
                    "databaseId": database_id,
                    "ownerEventId": "usage-1",
                    "bodyKey": LEGACY_USAGE_KEY,
                    "bodyId": "body-usage",
                    "byteStart": 0,
                    "byteLength": 2
                }
            }]
        })
        .to_string()
    }

    #[test]
    fn schema26_manifest_renames_usage_key_and_keeps_body_identity() {
        let rewritten = rewrite_payload(&usage_payload("db-1"), true, "db-1", "usage-1", &[])
            .unwrap()
            .unwrap();
        let value: serde_json::Value = serde_json::from_str(&rewritten).unwrap();
        assert_eq!(value["head"]["inferenceCount"], 1);
        assert_eq!(value["bodies"][0]["key"], ACCOUNTING_KEY);
        assert_eq!(value["bodies"][0]["reference"]["bodyId"], "body-usage");
        assert_eq!(value["bodies"][0]["reference"]["bodyKey"], LEGACY_USAGE_KEY);
        assert!(
            rewrite_payload(&rewritten, true, "db-1", "usage-1", &[])
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn schema26_manifest_leaves_non_accounting_canonical_payload() {
        let payload = usage_payload("db-1");
        assert!(
            rewrite_payload(&payload, false, "db-1", "chat-1", &[])
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn schema26_manifest_indexes_unlisted_tool_task_without_copying_bytes() {
        let stored = StoredBody {
            body_id: "body-task".into(),
            body_key: TOOL_TASK_KEY.into(),
            role: "native_tool_task".into(),
            byte_length: 4,
            media_type: Some("application/json".into()),
        };
        let rewritten = rewrite_payload(
            r#"{"contract":"anywork.event/1","type":"tool"}"#,
            false,
            "db-1",
            "tool-1",
            &[stored],
        )
        .unwrap()
        .unwrap();
        let value: serde_json::Value = serde_json::from_str(&rewritten).unwrap();
        assert_eq!(value["contract"], "anywork.event/1");
        assert_eq!(value["bodies"][0]["key"], TOOL_TASK_KEY);
        assert_eq!(value["bodies"][0]["reference"]["bodyId"], "body-task");
        assert_eq!(value["bodies"][0]["reference"]["bodyKey"], TOOL_TASK_KEY);
        assert!(value["bodies"][0].get("inlineText").is_none());
    }

    #[tokio::test]
    async fn schema26_manifest_repair_keeps_identity_and_append_only_trigger() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history_path = directory.path().join("history.sqlite");
        let db = super::super::super::schema::connect(&history_path, false, true).await?;
        super::super::super::schema::initialize(&db, "thread-1").await?;
        db.execute_unprepared("PRAGMA user_version=0").await?;
        let database_id = database_id(&db).await?;
        seed_legacy_rows(&db, &database_id).await?;
        db.close().await?;

        assert!(super::super::requires_history_upgrade(&history_path, "thread-1").await?);
        let report =
            super::super::upgrade_history(&history_path, "thread-1", directory.path()).await?;
        assert_eq!(report.status, super::super::UpgradeStatus::Upgraded);
        assert_eq!(report.database_id, database_id);
        assert!(!super::super::requires_history_upgrade(&history_path, "thread-1").await?);

        let db = super::super::super::schema::connect(&history_path, false, false).await?;
        let usage = payload_json(&db, "usage-1").await?;
        let usage: serde_json::Value = serde_json::from_str(&usage)?;
        assert_eq!(usage["bodies"][0]["key"], ACCOUNTING_KEY);
        assert_eq!(usage["bodies"][0]["reference"]["bodyId"], "body-usage");
        assert_eq!(usage["bodies"][0]["reference"]["bodyKey"], LEGACY_USAGE_KEY);

        let tool = payload_json(&db, "tool-1").await?;
        let tool: serde_json::Value = serde_json::from_str(&tool)?;
        assert_eq!(tool["bodies"][0]["reference"]["bodyId"], "body-task");
        assert_eq!(tool["type"], "tool");

        let chat = payload_json(&db, "chat-1").await?;
        assert!(chat.contains(LEGACY_USAGE_KEY));
        assert!(!chat.contains(ACCOUNTING_KEY));

        let body_key: String = db
            .query_one_raw(statement(
                "SELECT body_key FROM history_bodies WHERE body_id='body-usage'",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "body_key")?;
        assert_eq!(body_key, LEGACY_USAGE_KEY);
        let seq: i64 = db
            .query_one_raw(statement(
                "SELECT seq FROM history_events WHERE event_id='usage-1'",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "seq")?;
        assert_eq!(seq, 1);
        let version: i64 = db
            .query_one_raw(statement(
                "SELECT schema_version FROM history_store_meta WHERE singleton=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "schema_version")?;
        assert_eq!(version, 26);

        let rejected = db
            .execute_unprepared("UPDATE history_events SET recorded_at = recorded_at")
            .await;
        let Err(rejected) = rejected else {
            panic!("append-only trigger allowed an event update");
        };
        let rejected = rejected.to_string();
        assert!(
            rejected.contains("append-only"),
            "trigger error did not preserve the append-only failure: {rejected}"
        );
        let bodies_rejected = db
            .execute_unprepared("UPDATE history_bodies SET role = role")
            .await;
        let Err(bodies_rejected) = bodies_rejected else {
            panic!("body immutability trigger allowed an update");
        };
        let bodies_rejected = bodies_rejected.to_string();
        assert!(
            bodies_rejected.contains("immutable"),
            "trigger error did not preserve the body immutability failure: {bodies_rejected}"
        );
        db.close().await?;

        let second =
            super::super::upgrade_history(&history_path, "thread-1", directory.path()).await?;
        assert_eq!(second.status, super::super::UpgradeStatus::AlreadySchema26);
        Ok(())
    }

    async fn seed_legacy_rows(db: &impl ConnectionTrait, database_id: &str) -> Result<()> {
        insert_event(
            db,
            1,
            "usage-1",
            Some(("accounting", "accounting:session")),
            &usage_payload(database_id),
            "anywork.accounting/1",
        )
        .await?;
        insert_body(
            db,
            "body-usage",
            "usage-1",
            LEGACY_USAGE_KEY,
            "canonical_payload",
            b"{}",
        )
        .await?;
        insert_event(
            db,
            2,
            "tool-1",
            None,
            r#"{"contract":"anywork.event/1","type":"tool"}"#,
            "anywork.event/1",
        )
        .await?;
        insert_body(
            db,
            "body-task",
            "tool-1",
            TOOL_TASK_KEY,
            "native_tool_task",
            b"task",
        )
        .await?;
        insert_event(
            db,
            3,
            "chat-1",
            None,
            &usage_payload(database_id).replace("usage-1", "chat-1"),
            "anywork.event/1",
        )
        .await?;
        Ok(())
    }

    async fn insert_event(
        db: &impl ConnectionTrait,
        seq: i64,
        event_id: &str,
        anchor: Option<(&str, &str)>,
        payload_json: &str,
        payload_schema: &str,
    ) -> Result<()> {
        let (row_scope, row_key) = anchor.unzip();
        let is_anchor = i64::from(anchor.is_some());
        db.execute_raw(statement(
            "INSERT INTO history_events(
                seq,event_id,kind,timeline_role,recorded_at,row_scope,row_key,is_anchor,
                payload_schema,payload_json
             ) VALUES(?,?,?,?,?,?,?,?,?,?)",
            vec![
                seq.into(),
                event_id.into(),
                "usage_recorded".into(),
                "hidden".into(),
                1_i64.into(),
                row_scope.map(str::to_owned).into(),
                row_key.map(str::to_owned).into(),
                is_anchor.into(),
                payload_schema.into(),
                payload_json.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    async fn insert_body(
        db: &impl ConnectionTrait,
        body_id: &str,
        owner: &str,
        body_key: &str,
        role: &str,
        bytes: &[u8],
    ) -> Result<()> {
        let digest = sha2::Sha256::digest(bytes).to_vec();
        db.execute_raw(statement(
            "INSERT INTO history_bodies(
                body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest
             ) VALUES(?,?,0,?,?,?,NULL,?)",
            vec![
                body_id.into(),
                owner.into(),
                body_key.into(),
                role.into(),
                i64::try_from(bytes.len()).unwrap().into(),
                digest.into(),
            ],
        ))
        .await?;
        for (chunk, bytes) in bytes.chunks(crate::history::BODY_CHUNK_BYTES).enumerate() {
            db.execute_raw(statement(
                "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
                vec![
                    body_id.into(),
                    i64::try_from(chunk).unwrap().into(),
                    bytes.to_vec().into(),
                ],
            ))
            .await?;
        }
        Ok(())
    }
}
