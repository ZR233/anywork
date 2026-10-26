//! schema 11→12：在维护租约与单事务内，从不可变 effect 回填任务身份索引。
use sea_orm::ConnectionTrait;

use super::{SessionStoreError, sqlite, thread_history, tool_task_index};

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
            if indexed == current {
                super::thread_checkpoint::decode_checkpoint_at_schema(row, &thread_id, 5)?;
                continue;
            }
            let envelope: String = row.try_get("", "envelope")?;
            let checkpoint = super::thread_checkpoint::decode_migration_checkpoint(row, &thread_id)?;
            let encoded = if indexed == 4 {
                // Schema 5 only adds fields with explicit defaults. Preserve every saved field,
                // including producer extensions, instead of reserializing through a moving model.
                let mut migrated: serde_json::Value = serde_json::from_str(&envelope)?;
                migrated["schemaVersion"] = serde_json::json!(5);
                serde_json::to_string(&migrated)?
            } else {
                serde_json::to_string(&checkpoint)?
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
    // Earlier named steps have converted entries and backfilled usage. Recheck the complete source
    // inside this atomic step as well as before ledger adoption, including checkpoint-only Threads.
    super::migration_source::validate(tx, super::SESSION_SCHEMA_VERSION).await?;
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
                    let effect = thread_history::decode_effect(row, &thread_id)?;
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
