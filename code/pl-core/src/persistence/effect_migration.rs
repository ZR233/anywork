//! One-way v2 effect normalization. Legacy tags never escape this migration boundary.
use std::collections::BTreeSet;

use sea_orm::{ConnectionTrait, QueryResult};

use super::{SessionStoreError, history, sqlite, thread_checkpoint};
use crate::{
    context::OpaquePayload,
    storage::{SessionEntry, SessionEntryChange, validate_changes},
    thread::ThreadEffectBatch,
};

const PREFIX: &str = "pl.resource.thread-commit.";

/// Earlier v2 steps need effects before the final tag-normalization step has committed.
pub(super) fn decode_effect(
    row: QueryResult,
    thread_id: &str,
) -> Result<ThreadEffectBatch, SessionStoreError> {
    decode_entry(&sqlite::decode_row(row)?, thread_id)
}

fn decode_entry(
    entry: &SessionEntry,
    thread_id: &str,
) -> Result<ThreadEffectBatch, SessionStoreError> {
    let payload = OpaquePayload::new(
        entry.type_id.clone(),
        entry.schema_version,
        entry.payload.clone(),
    )
    .map_err(|error| SessionStoreError::Invalid(error.to_string()))?;
    let effect = match (payload.format(), payload.version()) {
        ("pl.core.thread-commit", 3) => serde_json::from_str(payload.content())?,
        _ => ThreadEffectBatch::decode(&payload)
            .map_err(|error| SessionStoreError::Invalid(error.to_string()))?,
    };
    if entry.session_id != thread_id
        || effect.thread_id != thread_id
        || effect.sequence == 0
        || entry.id != format!("{PREFIX}{:020}", effect.sequence)
    {
        return Err(SessionStoreError::Invalid(
            "Thread effect ownership or sequence key mismatch".into(),
        ));
    }
    Ok(effect)
}

fn normalize(entry: &mut SessionEntry, thread_id: &str) -> Result<bool, SessionStoreError> {
    if !entry.id.starts_with(PREFIX)
        && entry.type_id != "pl.core.thread-commit"
        && entry.type_id != "pl.core.thread-effect-batch"
    {
        return Ok(false);
    }
    decode_entry(entry, thread_id)?;
    if entry.type_id == "pl.core.thread-commit" {
        // Both supported tags describe the identical v2 body. Do not reserialize it: nested opaque
        // producer bytes and unrecognized extension fields must survive exactly as stored.
        entry.type_id = "pl.core.thread-effect-batch".into();
        entry.schema_version = 1;
        return Ok(true);
    }
    Ok(false)
}

pub(super) async fn convert_effects(tx: &impl ConnectionTrait) -> Result<(), SessionStoreError> {
    // A SQLite-managed projection bounds Rust memory by a page/commit, not by history length or
    // current body volume. It is private to this connection and disappears on rollback/close.
    tx.execute_unprepared(
        "CREATE TEMP TABLE core_effect_projection(id TEXT PRIMARY KEY,envelope TEXT NOT NULL)",
    )
    .await?;
    let mut after: Option<String> = None;
    loop {
        let sessions = tx.query_all_raw(sqlite::statement(
            "SELECT session_id FROM (SELECT session_id FROM session_entries UNION SELECT session_id FROM session_entry_history UNION SELECT session_id FROM session_history_heads UNION SELECT thread_id AS session_id FROM thread_checkpoints) WHERE (? IS NULL OR session_id>?) ORDER BY session_id LIMIT 128",
            vec![after.clone().into(), after.clone().into()],
        )).await?;
        if sessions.is_empty() {
            break;
        }
        for session in sessions {
            let id: String = session.try_get("", "session_id")?;
            if id.is_empty() {
                return Err(invalid("empty session identity"));
            }
            after = Some(id.clone());
            convert_session(tx, &id).await?;
            tx.execute_unprepared("DELETE FROM core_effect_projection")
                .await?;
        }
    }
    tx.execute_unprepared("DROP TABLE core_effect_projection")
        .await?;
    Ok(())
}

async fn convert_session(tx: &impl ConnectionTrait, id: &str) -> Result<(), SessionStoreError> {
    let head = tx
        .query_one_raw(sqlite::statement(
            "SELECT sequence,payload_hash FROM session_history_heads WHERE session_id=?",
            vec![id.into()],
        ))
        .await?;
    let head = head
        .map(|row| {
            Ok::<_, SessionStoreError>((
                row.try_get::<i64>("", "sequence")?,
                row.try_get::<String>("", "payload_hash")?,
            ))
        })
        .transpose()?;
    let mut sequence = 0u64;
    let mut last_original_hash = None;
    let mut last_new_hash = None;
    loop {
        let after = (sequence != 0).then(|| integer(sequence)).transpose()?;
        let rows = tx.query_all_raw(sqlite::statement(
            "SELECT sequence,envelope,payload_hash FROM session_entry_history WHERE session_id=? AND (? IS NULL OR sequence>?) ORDER BY sequence LIMIT 128",
            vec![id.into(), after.into(), after.into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            last_original_hash = Some(row.try_get::<String>("", "payload_hash")?);
            let expected = sequence
                .checked_add(1)
                .ok_or_else(|| invalid("history sequence overflow"))?;
            let mut batch = history::decode_commit(row, id, expected)?;
            sequence = batch.sequence;
            project_changes(tx, &batch.changes).await?;
            let mut changed = false;
            for change in &mut batch.changes {
                if let SessionEntryChange::Put { entry } = change {
                    changed |= normalize(entry, id)?;
                }
            }
            last_new_hash = last_original_hash.clone();
            if changed {
                let envelope = serde_json::to_string(&batch)?;
                let hash = crate::context::content_hash(envelope.as_bytes());
                tx.execute_raw(sqlite::statement(
                    "UPDATE session_entry_history SET envelope=?,payload_hash=? WHERE session_id=? AND sequence=?",
                    vec![envelope.into(), hash.clone().into(), id.into(), integer(sequence)?.into()],
                )).await?;
                last_new_hash = Some(hash);
            }
        }
    }
    if head.as_ref().map(|head| head.0) != (sequence != 0).then_some(integer(sequence)?)
        || head.as_ref().map(|head| &head.1) != last_original_hash.as_ref()
    {
        return Err(invalid("history head sequence or digest mismatch"));
    }
    convert_current(tx, id).await?;
    if let Some(hash) = last_new_hash {
        tx.execute_raw(sqlite::statement(
            "UPDATE session_history_heads SET payload_hash=? WHERE session_id=?",
            vec![hash.into(), id.into()],
        ))
        .await?;
    }
    validate_checkpoint(tx, id).await
}

async fn project_changes(
    tx: &impl ConnectionTrait,
    changes: &[SessionEntryChange],
) -> Result<(), SessionStoreError> {
    let mut present = BTreeSet::new();
    for change in changes {
        if let SessionEntryChange::Delete { entry_id } = change
            && tx
                .query_one_raw(sqlite::statement(
                    "SELECT 1 FROM core_effect_projection WHERE id=?",
                    vec![entry_id.clone().into()],
                ))
                .await?
                .is_some()
        {
            present.insert(entry_id.as_str());
        }
    }
    // Share the generic entry-history invariants with ReplayState; no Thread execution is rebuilt.
    validate_changes(changes, |id| present.contains(id))?;
    for change in changes {
        match change {
            SessionEntryChange::Put { entry } => {
                tx.execute_raw(sqlite::statement(
                    "INSERT INTO core_effect_projection(id,envelope) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET envelope=excluded.envelope",
                    vec![entry.id.clone().into(), serde_json::to_string(entry)?.into()],
                )).await?;
            }
            SessionEntryChange::Delete { entry_id } => {
                tx.execute_raw(sqlite::statement(
                    "DELETE FROM core_effect_projection WHERE id=?",
                    vec![entry_id.clone().into()],
                ))
                .await?;
            }
        }
    }
    Ok(())
}

async fn convert_current(tx: &impl ConnectionTrait, id: &str) -> Result<(), SessionStoreError> {
    let mut after: Option<String> = None;
    let mut count = 0i64;
    let mut expected_effect = 1u64;
    loop {
        let rows = tx.query_all_raw(sqlite::statement(
            "SELECT * FROM session_entries WHERE session_id=? AND (? IS NULL OR id>?) ORDER BY id LIMIT 128",
            vec![id.into(), after.clone().into(), after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let mut entry = sqlite::decode_row(row)?;
            after = Some(entry.id.clone());
            let projected = tx
                .query_one_raw(sqlite::statement(
                    "SELECT envelope FROM core_effect_projection WHERE id=?",
                    vec![entry.id.clone().into()],
                ))
                .await?
                .ok_or_else(|| invalid("current entry is missing from history"))?;
            let encoded: String = projected.try_get("", "envelope")?;
            let original: SessionEntry = serde_json::from_str(&encoded)?;
            if entry != original {
                return Err(invalid("history and current entries disagree"));
            }
            count = count
                .checked_add(1)
                .ok_or_else(|| invalid("entry count overflow"))?;
            if entry.id.starts_with(PREFIX) {
                let effect = decode_entry(&entry, id)?;
                if effect.sequence != expected_effect {
                    return Err(invalid("Thread effect history is not contiguous"));
                }
                expected_effect = expected_effect
                    .checked_add(1)
                    .ok_or_else(|| invalid("effect sequence overflow"))?;
            }
            if normalize(&mut entry, id)? {
                let envelope = serde_json::to_string(&entry)?;
                let hash = crate::context::content_hash(envelope.as_bytes());
                tx.execute_raw(sqlite::statement(
                    "UPDATE session_entries SET type_id=?,envelope=?,payload_hash=? WHERE session_id=? AND id=?",
                    vec![entry.type_id.into(), envelope.into(), hash.into(), id.into(), entry.id.into()],
                )).await?;
            }
        }
    }
    let projected = tx
        .query_one_raw(sqlite::statement(
            "SELECT COUNT(*) AS count FROM core_effect_projection",
            vec![],
        ))
        .await?
        .ok_or_else(|| invalid("missing history projection count"))?;
    if count != projected.try_get::<i64>("", "count")? {
        return Err(invalid(
            "history contains entries absent from current state",
        ));
    }
    Ok(())
}

async fn validate_checkpoint(tx: &impl ConnectionTrait, id: &str) -> Result<(), SessionStoreError> {
    let row = tx
        .query_one_raw(sqlite::statement(
            "SELECT * FROM thread_checkpoints WHERE thread_id=?",
            vec![id.into()],
        ))
        .await?;
    if let Some(row) = row {
        let checkpoint = thread_checkpoint::decode_checkpoint_at_schema(row, id, 5)?;
        if checkpoint.state.usage_summary.applied_sequence != checkpoint.state_revision {
            return Err(invalid("checkpoint usage summary is behind its revision"));
        }
        let row = tx
            .query_one_raw(sqlite::statement(
                "SELECT * FROM session_entries WHERE session_id=? AND id=?",
                vec![
                    id.into(),
                    format!("{PREFIX}{:020}", checkpoint.history_fence).into(),
                ],
            ))
            .await?
            .ok_or_else(|| invalid("checkpoint fence has no saved effect"))?;
        decode_effect(row, id)?;
    }
    Ok(())
}

fn integer(value: u64) -> Result<i64, SessionStoreError> {
    i64::try_from(value).map_err(|_| invalid("sequence exceeds SQLite integer range"))
}

fn invalid(message: &str) -> SessionStoreError {
    SessionStoreError::Invalid(message.into())
}
