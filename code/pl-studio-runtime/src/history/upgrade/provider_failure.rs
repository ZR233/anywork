//! Frozen product Turn failures from before schema 26 maintenance revision 2.

use sea_orm::ConnectionTrait;
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::history::{
    BODY_CHUNK_BYTES, HistoryBodyManifestEntry, HistoryError, HistoryEventBodyRef, HistoryTurnHead,
    INLINE_BODY_MAX_BYTES, INLINE_EVENT_MAX_BYTES, Result,
    db::{self, statement},
};
use crate::{Turn, TurnState};

use super::{LEGACY_EVENT_PREFIX, v25_to_v26::insert_migrated_inline_blob};

const TURN_DETAIL: &str = "turn_detail";
const MIGRATED_TURN_DETAIL: &str = "turn_detail.v2";

fn rewrite_failed_state(state: &mut Value) -> Result<bool> {
    if state.get("kind").and_then(Value::as_str) != Some("failed") {
        return Ok(false);
    }
    let failure = state
        .pointer_mut("/data/failure")
        .and_then(Value::as_object_mut)
        .ok_or_else(|| HistoryError::Integrity("failed Turn has no failure object".into()))?;
    let mut changed = false;
    if let Some(kind) = failure.get_mut("providerKind")
        && matches!(kind.as_str(), Some("capacity" | "configuration"))
    {
        // The frozen value does not establish quota, capacity limits, or busy service.
        // The pre-upgrade backup (and any original stored body) retains the exact kind.
        *kind = Value::String("unknown".into());
        changed = true;
    }
    if let Some(retry) = failure.get_mut("retry").and_then(Value::as_object_mut) {
        changed |= rewrite_retry_wait(retry)?;
    }
    if let Some(wait) = failure
        .get_mut("recovery")
        .and_then(|recovery| recovery.get_mut("effectiveWaitMillis"))
    {
        changed |= decimal_wait(wait, "Turn recovery.effectiveWaitMillis")?;
    }
    Ok(changed)
}

fn rewrite_retry_wait(retry: &mut serde_json::Map<String, Value>) -> Result<bool> {
    let old_wait = retry.remove("retry_after_ms");
    if old_wait.is_none() && !retry.contains_key("retryAfterMs") {
        return Ok(false);
    }
    if retry.get("kind").and_then(Value::as_str) != Some("retryable") {
        return Err(HistoryError::Integrity(
            "historical Turn retry wait requires a retryable disposition".into(),
        ));
    }
    let changed = match retry.get_mut("retryAfterMs") {
        Some(wait) => decimal_wait(wait, "Turn retryAfterMs")?,
        None => false,
    };
    let Some(mut old_wait) = old_wait else {
        return Ok(changed);
    };
    decimal_wait(&mut old_wait, "Turn retry_after_ms")?;
    if retry
        .get("retryAfterMs")
        .is_some_and(|wait| wait != &old_wait)
    {
        return Err(HistoryError::Integrity(
            "conflicting historical Turn retry wait".into(),
        ));
    }
    retry.insert("retryAfterMs".into(), old_wait);
    Ok(true)
}

fn decimal_wait(wait: &mut Value, field: &str) -> Result<bool> {
    match wait {
        Value::Null => return Ok(false),
        Value::Number(number) => {
            // `as_u64` accepts only a JSON integer stored exactly in the unsigned range.
            if let Some(value) = number.as_u64() {
                *wait = Value::String(value.to_string());
                return Ok(true);
            }
        }
        Value::String(text) => {
            if text
                .parse::<u64>()
                .is_ok_and(|value| value.to_string() == *text)
            {
                return Ok(false);
            }
        }
        _ => {}
    }
    Err(HistoryError::Integrity(format!(
        "invalid {field}: expected an exact u64 wait"
    )))
}

/// Schema 24 import needs a typed Turn to build its head. The original bytes are
/// still imported so revision 2 can publish the current detail from the same input.
pub(super) fn decode_turn(bytes: &[u8]) -> Result<(Turn, Option<String>)> {
    let mut value: Value = serde_json::from_slice(bytes)?;
    let changed = match value.get_mut("state") {
        Some(state) => rewrite_failed_state(state)?,
        None => false,
    };
    let current = changed.then(|| serde_json::to_string(&value)).transpose()?;
    Ok((serde_json::from_value(value)?, current))
}

async fn read_detail(
    db: &impl ConnectionTrait,
    database_id: &str,
    event_id: &str,
    entry: &HistoryBodyManifestEntry,
) -> Result<Vec<u8>> {
    let length = usize::try_from(entry.byte_length).map_err(|_| {
        HistoryError::Integrity("Turn detail length exceeds the platform address space".into())
    })?;
    match (&entry.inline_text, &entry.reference) {
        (Some(text), None) if text.len() == length => Ok(text.as_bytes().to_vec()),
        (None, Some(reference)) => {
            let body = db::body(db, &reference.body_id).await?.ok_or_else(|| {
                HistoryError::Integrity(format!("missing Turn body {}", reference.body_id))
            })?;
            if reference.database_id != database_id
                || reference.owner_event_id != event_id
                || reference.byte_start != 0
                || reference.byte_length != entry.byte_length
                || body.owner != event_id
                || body.key != reference.body_key
                || body.length != entry.byte_length
                || body.role.as_str() != entry.role
            {
                return Err(HistoryError::Integrity(
                    "Turn detail reference differs from its body".into(),
                ));
            }
            validate_chunk_layout(db, &body).await?;
            let mut bytes = Vec::new();
            while bytes.len() < length {
                let chunk =
                    db::window(db, &body, bytes.len() as u64, BODY_CHUNK_BYTES as u32).await?;
                bytes.try_reserve(chunk.len()).map_err(|error| {
                    HistoryError::Integrity(format!("cannot allocate Turn detail: {error}"))
                })?;
                bytes.extend(chunk);
            }
            if Sha256::digest(&bytes)[..] != body.digest {
                return Err(HistoryError::Integrity(
                    "Turn detail body digest differs from its bytes".into(),
                ));
            }
            Ok(bytes)
        }
        _ => Err(HistoryError::Integrity(
            "invalid Turn detail manifest entry".into(),
        )),
    }
}

async fn validate_chunk_layout(db: &impl ConnectionTrait, body: &db::Body) -> Result<()> {
    let chunk_size = BODY_CHUNK_BYTES as u64;
    let chunk_count = body.length.div_ceil(chunk_size);
    let final_chunk = chunk_count.saturating_sub(1);
    let final_size = body.length - final_chunk * chunk_size;
    // Range reads can end inside a chunk. Check the complete persisted layout first so
    // a matching digest over just the declared range cannot hide trailing bytes.
    let layout = db
        .query_one_raw(statement(
            "SELECT count(*) AS chunks, coalesce(sum(length(data)),0) AS bytes,
                count(CASE WHEN chunk_no<0 OR chunk_no>=? OR typeof(data)<>'blob'
                      OR length(data)<>CASE WHEN chunk_no=? THEN ? ELSE ? END
                      THEN 1 END) AS malformed
         FROM history_body_chunks WHERE body_id=?",
            vec![
                db::number(chunk_count)?.into(),
                db::number(final_chunk)?.into(),
                db::number(final_size)?.into(),
                db::number(chunk_size)?.into(),
                body.id.clone().into(),
            ],
        ))
        .await?
        .ok_or_else(|| {
            HistoryError::Integrity("Turn detail chunk layout summary is missing".into())
        })?;
    // The body id and chunk number form the primary key, so count plus range
    // validates continuity without reading the BLOBs into a second buffer.
    if layout.try_get::<i64>("", "chunks")? != db::number(chunk_count)?
        || layout.try_get::<i64>("", "bytes")? != db::number(body.length)?
        || layout.try_get::<i64>("", "malformed")? != 0
    {
        return Err(HistoryError::Integrity(format!(
            "Turn detail chunk layout differs from body {}",
            body.id
        )));
    }
    Ok(())
}

async fn replace_detail(
    db: &impl ConnectionTrait,
    database_id: &str,
    event_id: &str,
    entry: &mut HistoryBodyManifestEntry,
    text: String,
    other_inline_bytes: usize,
) -> Result<()> {
    let bytes = text.as_bytes();
    entry.byte_length = bytes.len() as u64;
    if entry.inline_text.is_some()
        && bytes.len() <= INLINE_BODY_MAX_BYTES
        && other_inline_bytes.saturating_add(bytes.len()) <= INLINE_EVENT_MAX_BYTES
    {
        entry.inline_text = Some(text);
        return Ok(());
    }
    let ordinal = db.query_one_raw(statement(
        "SELECT coalesce(max(ordinal)+1, 0) AS ordinal FROM history_bodies WHERE owner_event_id=?",
        vec![event_id.into()],
    )).await?.ok_or_else(|| HistoryError::Integrity("Turn body ordinal is missing".into()))?;
    let ordinal = super::db_u64(ordinal.try_get("", "ordinal")?, "Turn body ordinal")?;
    let body_id = insert_migrated_inline_blob(
        db,
        event_id,
        ordinal,
        MIGRATED_TURN_DETAIL,
        &entry.role,
        entry.media_type.as_deref(),
        bytes,
    )
    .await?;
    entry.inline_text = None;
    entry.reference = Some(HistoryEventBodyRef {
        database_id: database_id.into(),
        owner_event_id: event_id.into(),
        body_key: MIGRATED_TURN_DETAIL.into(),
        body_id,
        byte_start: 0,
        byte_length: entry.byte_length,
    });
    Ok(())
}

async fn rewrite_turn_detail(
    db: &impl ConnectionTrait,
    database_id: &str,
    event_id: &str,
    value: &mut Value,
) -> Result<bool> {
    let head: HistoryTurnHead = serde_json::from_value(
        value
            .get("head")
            .cloned()
            .ok_or_else(|| HistoryError::Integrity("Turn row has no head".into()))?,
    )?;
    let bodies = match value.get("bodies") {
        None => &[][..],
        Some(bodies) => bodies
            .as_array()
            .ok_or_else(|| {
                HistoryError::Integrity("Turn detail bodies must be a manifest array".into())
            })?
            .as_slice(),
    };
    let legacy_import = event_id.starts_with(LEGACY_EVENT_PREFIX);
    let mut candidates = bodies.iter().enumerate().filter(|(_, entry)| {
        matches!(entry.get("key").and_then(Value::as_str), Some(TURN_DETAIL))
            || legacy_import
                && entry.get("key").and_then(Value::as_str) == Some("canonical_payload")
    });
    let Some((index, entry)) = candidates.next() else {
        if head.detail_event_id.as_deref() == Some(event_id) {
            return Err(HistoryError::Integrity(
                "Turn detail is absent from its manifest".into(),
            ));
        }
        return Ok(false);
    };
    if candidates.next().is_some() {
        return Err(HistoryError::Integrity(
            "event has multiple Turn details".into(),
        ));
    }
    let mut entry: HistoryBodyManifestEntry = serde_json::from_value(entry.clone())?;
    if entry.role != "canonical_payload" {
        return Err(HistoryError::Integrity(
            "Turn detail has an invalid body role".into(),
        ));
    }
    let from_schema24 = entry.key == "canonical_payload";
    let bytes = read_detail(db, database_id, event_id, &entry).await?;
    let (turn, rewritten) = decode_turn(&bytes)?;
    if head.turn_id != turn.id {
        return Err(HistoryError::Integrity(
            "Turn detail identity differs from its head".into(),
        ));
    }
    if !from_schema24 && rewritten.is_none() {
        return Ok(false);
    }
    if let Some(rewritten) = rewritten {
        let other_inline_bytes = bodies
            .iter()
            .enumerate()
            .filter(|(pos, _)| *pos != index)
            .filter_map(|(_, body)| body.get("inlineText").and_then(Value::as_str))
            .map(str::len)
            .fold(0_usize, usize::saturating_add);
        replace_detail(
            db,
            database_id,
            event_id,
            &mut entry,
            rewritten,
            other_inline_bytes,
        )
        .await?;
    }
    if from_schema24 {
        let head = value
            .get_mut("head")
            .and_then(Value::as_object_mut)
            .ok_or_else(|| HistoryError::Integrity("schema 24 Turn detail has no head".into()))?;
        head.insert("detailEventId".into(), Value::String(event_id.into()));
        entry.key = TURN_DETAIL.into();
    }
    value["bodies"][index] = serde_json::to_value(entry)?;
    Ok(true)
}

pub(super) async fn migrate(db: &impl ConnectionTrait, database_id: &str) -> Result<u64> {
    let mut after = 0i64;
    let mut rewritten = 0u64;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT seq,event_id,payload_schema,payload_json FROM history_events
             WHERE seq>? AND ((row_scope='turn' AND payload_schema='anywork.turn/1') OR (
                payload_schema='anywork.event/1' AND json_extract(payload_json,'$.contract')='anywork.event/1'
                AND json_extract(payload_json,'$.type')='turn'
                AND json_extract(payload_json,'$.data.outcome.kind')='failed'))
             ORDER BY seq LIMIT 128",
            vec![after.into()],
        )).await?;
        if rows.is_empty() {
            return Ok(rewritten);
        }
        for row in rows {
            after = row.try_get("", "seq")?;
            let event_id: String = row.try_get("", "event_id")?;
            let schema: String = row.try_get("", "payload_schema")?;
            let payload: String = row.try_get("", "payload_json")?;
            let mut value: Value = serde_json::from_str(&payload)?;
            let result = if schema == "anywork.turn/1" {
                rewrite_turn_detail(db, database_id, &event_id, &mut value).await
            } else {
                let outcome = value.pointer_mut("/data/outcome").ok_or_else(|| {
                    HistoryError::Integrity("failed Turn receipt has no outcome".into())
                })?;
                rewrite_failed_state(outcome).and_then(|changed| {
                    serde_json::from_value::<TurnState>(outcome.clone())?;
                    Ok(changed)
                })
            };
            if result.map_err(|error| {
                HistoryError::Integrity(format!(
                    "migrate Turn failure for event {event_id}: {error}"
                ))
            })? {
                db.execute_raw(statement(
                    "UPDATE history_events SET payload_json=? WHERE event_id=?",
                    vec![serde_json::to_string(&value)?.into(), event_id.into()],
                ))
                .await?;
                rewritten += 1;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn historical_turn_wait_requires_an_exact_u64() -> Result<()> {
        for (source, expected, changed) in [
            (r#"{"kind":"retryable"}"#, r#"{"kind":"retryable"}"#, false),
            (
                r#"{"kind":"retryable","retry_after_ms":null}"#,
                r#"{"kind":"retryable","retryAfterMs":null}"#,
                true,
            ),
            (
                r#"{"kind":"retryable","retry_after_ms":0,"retryAfterMs":"0"}"#,
                r#"{"kind":"retryable","retryAfterMs":"0"}"#,
                true,
            ),
            (
                r#"{"kind":"retryable","retryAfterMs":"18446744073709551615"}"#,
                r#"{"kind":"retryable","retryAfterMs":"18446744073709551615"}"#,
                false,
            ),
        ] {
            let mut retry = serde_json::from_str(source)?;
            assert_eq!(rewrite_retry_wait(&mut retry)?, changed, "{source}");
            let expected: serde_json::Map<String, Value> = serde_json::from_str(expected)?;
            assert_eq!(retry, expected, "{source}");
        }
        for invalid in [
            "-1",
            "1.5",
            "1e3",
            "18446744073709551616",
            r#""01""#,
            "true",
        ] {
            let mut wait = serde_json::from_str(invalid)?;
            assert!(
                matches!(
                    decimal_wait(&mut wait, "Turn retryAfterMs"),
                    Err(HistoryError::Integrity(_))
                ),
                "{invalid}"
            );
        }
        Ok(())
    }
}
