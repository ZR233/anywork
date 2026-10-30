//! schema 11→12：在维护租约与单事务内，从不可变 effect 回填任务身份索引。
use sea_orm::ConnectionTrait;

use super::{SessionStoreError, effect_migration, sqlite, tool_task_index};

/// Converts saved checkpoint envelopes to schema 5, in one transaction.
///
/// Only rows whose indexed version differs from 5 are
/// rewritten, and each is converted through the explicit legacy reader, so an already current envelope
/// is neither re-encoded nor renumbered.
pub(super) async fn convert_checkpoints(
    tx: &impl ConnectionTrait,
) -> Result<(), SessionStoreError> {
    // This named migration has a fixed target; future formats require a new migration.
    let current = 5i64;
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
            let indexed: i64 = row.try_get("", "schema_version")?;
            if indexed == 6 {
                super::thread_checkpoint::decode_checkpoint(row, &thread_id)?;
                continue;
            }
            if indexed == current {
                super::thread_checkpoint::decode_checkpoint_at_schema(row, &thread_id, 5)?;
                continue;
            }
            let envelope: String = row.try_get("", "envelope")?;
            let hash: String = row.try_get("", "payload_hash")?;
            if crate::context::content_hash(envelope.as_bytes()) != hash {
                return Err(SessionStoreError::Invalid(format!(
                    "Thread {thread_id} checkpoint integrity check failed"
                )));
            }
            let header: serde_json::Value = serde_json::from_str(&envelope)?;
            if header
                .get("schemaVersion")
                .and_then(serde_json::Value::as_i64)
                != Some(indexed)
            {
                return Err(SessionStoreError::Invalid(
                    "checkpoint schema index/envelope mismatch".into(),
                ));
            }
            let checkpoint =
                crate::thread::ThreadCheckpoint::decode_legacy(&envelope).map_err(|error| {
                    SessionStoreError::Invalid(format!(
                        "Thread {thread_id} legacy checkpoint conversion failed: {error}"
                    ))
                })?;
            if checkpoint.thread_id != thread_id
                || i64::try_from(checkpoint.state_revision).ok()
                    != Some(row.try_get::<i64>("", "state_revision")?)
                || i64::try_from(checkpoint.history_fence).ok()
                    != Some(row.try_get::<i64>("", "history_fence")?)
                || checkpoint.state_revision != checkpoint.state.commit_sequence
                || checkpoint.history_fence > checkpoint.state_revision
                || checkpoint.state.usage_summary.applied_sequence > checkpoint.state_revision
                || !checkpoint.external_bodies.is_empty()
            {
                return Err(SessionStoreError::Invalid(
                    "checkpoint ownership or fence mismatch".into(),
                ));
            }
            let encoded = if indexed >= 4 {
                // Schema 5 only adds fields with explicit defaults. Preserve every saved field,
                // including producer extensions, instead of reserializing through a moving model.
                let mut migrated = header;
                migrated["schemaVersion"] = serde_json::json!(5);
                serde_json::to_string(&migrated)?
            } else {
                let mut migrated = serde_json::to_value(&checkpoint)?;
                migrated["schemaVersion"] = serde_json::json!(5);
                // The named schema-5 step must retain its fixed flat usage target.
                migrated["state"]["usageSummary"] = header["state"]
                    .get("usageSummary")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}));
                serde_json::to_string(&migrated)?
            };
            let encoded_hash = crate::context::content_hash(encoded.as_bytes());
            tx.execute_raw(sqlite::statement(
                "UPDATE thread_checkpoints SET schema_version=?,envelope=?,payload_hash=? WHERE thread_id=?",
                vec![
                    current.into(),
                    encoded.into(),
                    encoded_hash.into(),
                    thread_id.into(),
                ],
            ))
            .await?;
        }
    }
    Ok(())
}

pub(super) async fn backfill_task_index(
    tx: &impl ConnectionTrait,
) -> Result<(), SessionStoreError> {
    tx.execute_unprepared(include_str!("task_index_v12.sql"))
        .await?;
    let mut after_thread = String::new();
    loop {
        let sessions = tx.query_all_raw(sqlite::statement(
                "SELECT DISTINCT session_id FROM session_entries WHERE session_id>? ORDER BY session_id LIMIT 128",
                vec![after_thread.clone().into()],
            )).await?;
        if sessions.is_empty() {
            break;
        }
        for session in sessions {
            let thread_id: String = session.try_get("", "session_id")?;
            after_thread.clone_from(&thread_id);
            let mut after = "pl.resource.thread-commit.".to_owned();
            let mut expected_sequence = 1;
            loop {
                let rows = tx.query_all_raw(sqlite::statement(
                        "SELECT * FROM session_entries WHERE session_id=? AND id>? AND id<? ORDER BY id LIMIT 128",
                        vec![thread_id.clone().into(), after.clone().into(), "pl.resource.thread-commit/".into()],
                    )).await?;
                if rows.is_empty() {
                    break;
                }
                for row in rows {
                    let effect = effect_migration::decode_effect(row, &thread_id)?;
                    if effect.sequence != expected_sequence {
                        return Err(SessionStoreError::Invalid(format!(
                            "Thread {thread_id} effect 链在 {expected_sequence} 处不连续"
                        )));
                    }
                    expected_sequence = effect
                        .sequence
                        .checked_add(1)
                        .ok_or_else(|| SessionStoreError::Invalid("effect 序号溢出".into()))?;
                    after = format!("pl.resource.thread-commit.{:020}", effect.sequence);
                    tool_task_index::apply(tx, &effect).await?;
                }
            }
        }
    }
    Ok(())
}
