use std::{collections::BTreeSet, sync::Arc};

use sea_orm::{ConnectionTrait, DatabaseBackend, QueryResult, Statement, Value};
use sha2::{Digest, Sha256};

use super::{types::source_key, *};

pub(super) fn statement(sql: &str, values: Vec<Value>) -> Statement {
    Statement::from_sql_and_values(DatabaseBackend::Sqlite, sql, values)
}

pub(super) fn number(value: u64) -> Result<i64> {
    i64::try_from(value)
        .map_err(|_| HistoryError::InvalidEvent("history integer exceeds SQLite range".into()))
}

const COLUMNS: &str = "seq,event_id,kind,timeline_role,occurred_at,recorded_at,run_id,turn_id,attempt_id,call_id,entity_id,message_id,tool_name,source_id,query_class,parent_id,original_kind,row_scope,row_key,is_anchor,payload_schema,payload_json";
const D_COLUMNS: &str = "d.seq,d.event_id,d.kind,d.timeline_role,d.occurred_at,d.recorded_at,d.run_id,d.turn_id,d.attempt_id,d.call_id,d.entity_id,d.message_id,d.tool_name,d.source_id,d.query_class,d.parent_id,d.original_kind,d.row_scope,d.row_key,d.is_anchor,d.payload_schema,d.payload_json";

#[derive(Debug, Clone, PartialEq)]
pub(super) struct DirectTimelineRow {
    pub record: Record,
    pub has_folded_after: bool,
    pub tail_folded_ended_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub(super) struct Record {
    pub record: HistoryEventRecord,
    pub is_anchor: bool,
}

impl Record {
    pub fn from_event(event: &HistoryEvent) -> Self {
        Self {
            record: event.to_record(),
            is_anchor: event.is_anchor,
        }
    }
}

pub(super) fn decode_row(row: QueryResult) -> Result<Record> {
    let seq = u64::try_from(row.try_get::<i64>("", "seq")?)
        .map_err(|_| HistoryError::Integrity("negative event sequence".into()))?;
    let event_id: String = row.try_get("", "event_id")?;
    let kind: String = row.try_get("", "kind")?;
    let timeline_role_int: i64 = row.try_get("", "timeline_role")?;
    let timeline_role = HistoryTimelineRole::from_db_int(timeline_role_int).ok_or_else(|| {
        HistoryError::Integrity(format!("unknown timeline_role {timeline_role_int}"))
    })?;
    let source_id: Option<String> = row.try_get("", "source_id")?;
    let source = source_id
        .map(|raw| serde_json::from_str::<HistorySource>(&raw))
        .transpose()?;
    let tool_name: Option<String> = row.try_get("", "tool_name")?;
    let query_class: Option<String> = row.try_get("", "query_class")?;
    let original = if let Some(query_class) = query_class {
        let orig_kind_str: String = row.try_get("", "original_kind")?;
        let original_kind: HistoryEntityKind =
            serde_json::from_value(serde_json::Value::String(orig_kind_str))
                .unwrap_or(HistoryEntityKind::Unknown);
        Some(HistoryOriginalInfo {
            query_class,
            parent_id: row.try_get("", "parent_id")?,
            original_kind,
            tool_name: tool_name.clone(),
        })
    } else {
        None
    };
    let row_scope_str: Option<String> = row.try_get("", "row_scope")?;
    let row_scope = row_scope_str
        .as_deref()
        .map(|s| {
            HistoryBusinessRowScope::from_db(s)
                .ok_or_else(|| HistoryError::Integrity(format!("unknown row_scope {s}")))
        })
        .transpose()?;
    let row_key: Option<String> = row.try_get("", "row_key")?;
    if row_scope.is_some() != row_key.is_some() {
        return Err(HistoryError::Integrity(
            "indexed row_scope and row_key presence differ".into(),
        ));
    }

    Ok(Record {
        record: HistoryEventRecord {
            seq,
            event_id,
            kind: kind.into(),
            timeline_role,
            occurred_at: row.try_get("", "occurred_at")?,
            recorded_at: row.try_get("", "recorded_at")?,
            run_id: row.try_get("", "run_id")?,
            turn_id: row.try_get("", "turn_id")?,
            attempt_id: row.try_get("", "attempt_id")?,
            call_id: row.try_get("", "call_id")?,
            entity_id: row.try_get("", "entity_id")?,
            message_id: row.try_get("", "message_id")?,
            tool_name,
            source,
            original,
            row_scope,
            row_key,
            payload_schema: row.try_get("", "payload_schema")?,
            payload_json: row.try_get("", "payload_json")?,
        },
        is_anchor: row.try_get::<i64>("", "is_anchor")? == 1,
    })
}

pub(super) async fn event(db: &impl ConnectionTrait, id: &str) -> Result<Option<Record>> {
    db.query_one_raw(statement(
        &format!("SELECT {COLUMNS} FROM history_events WHERE event_id=?"),
        vec![id.into()],
    ))
    .await
    .inspect(|_| {
        tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
    })?
    .map(decode_row)
    .transpose()
}

pub(super) async fn event_head(db: &impl ConnectionTrait) -> Result<u64> {
    let row = db
        .query_one_raw(statement(
            "SELECT COALESCE(MAX(seq),0) AS seq FROM history_events",
            vec![],
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?
        .ok_or_else(|| HistoryError::Integrity("history head query returned no row".into()))?;
    u64::try_from(row.try_get::<i64>("", "seq")?)
        .map_err(|_| HistoryError::Integrity("negative history head".into()))
}

pub(super) fn direct_timeline_sql() -> &'static str {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    SQL.get_or_init(|| {
        format!(
            "SELECT {D_COLUMNS}, \
                    EXISTS ( \
                        SELECT 1 FROM history_events w \
                        WHERE w.timeline_role=1 \
                          AND w.seq>d.seq \
                          AND w.seq<COALESCE( \
                              (SELECT n.seq FROM history_events n \
                               WHERE n.timeline_role=2 AND n.seq>d.seq AND n.seq<? \
                               ORDER BY n.seq ASC LIMIT 1), \
                              ? \
                          ) \
                    ) AS has_folded_after, \
                    CASE \
                        WHEN ?=1 AND NOT EXISTS ( \
                            SELECT 1 FROM history_events n2 \
                            WHERE n2.timeline_role=2 AND n2.seq>d.seq AND n2.seq<? \
                        ) THEN ( \
                            SELECT COALESCE(w2.occurred_at, w2.recorded_at) \
                            FROM history_events w2 \
                            WHERE w2.timeline_role=1 AND w2.seq>d.seq AND w2.seq<? \
                            ORDER BY w2.seq DESC LIMIT 1 \
                        ) \
                        ELSE NULL \
                    END AS tail_folded_ended_at \
             FROM history_events d \
             WHERE d.timeline_role=2 AND d.seq<=? \
             ORDER BY d.seq DESC \
             LIMIT ?"
        )
    })
}

pub(super) async fn direct_timeline_entries_at_or_before(
    db: &impl ConnectionTrait,
    upper_seq: u64,
    upper_excl: u64,
    include_tail_end: bool,
    limit: usize,
) -> Result<Vec<DirectTimelineRow>> {
    if upper_seq == 0 || limit == 0 {
        return Ok(Vec::new());
    }
    let upper_excl_i64 = number(upper_excl)?;
    let limit_u64 = u64::try_from(limit).map_err(|_| {
        HistoryError::InvalidDemand("direct timeline prefetch limit overflow".into())
    })?;
    let rows = db
        .query_all_raw(statement(
            direct_timeline_sql(),
            vec![
                upper_excl_i64.into(),
                upper_excl_i64.into(),
                i64::from(include_tail_end).into(),
                upper_excl_i64.into(),
                upper_excl_i64.into(),
                number(upper_seq)?.into(),
                number(limit_u64)?.into(),
            ],
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?;
    rows.into_iter()
        .map(|row| {
            let has_folded_after = row.try_get::<i64>("", "has_folded_after")? != 0;
            let tail_folded_ended_at: Option<i64> = row.try_get("", "tail_folded_ended_at")?;
            let record = decode_row(row)?;
            Ok(DirectTimelineRow {
                record,
                has_folded_after,
                tail_folded_ended_at,
            })
        })
        .collect()
}

pub(super) async fn has_work_in_range(
    db: &impl ConnectionTrait,
    lower_excl: u64,
    upper_excl: u64,
) -> Result<bool> {
    if lower_excl.saturating_add(1) >= upper_excl {
        return Ok(false);
    }
    let row = db
        .query_one_raw(statement(
            "SELECT EXISTS(SELECT 1 FROM history_events WHERE timeline_role=1 AND seq>? AND seq<?) AS present",
            vec![number(lower_excl)?.into(), number(upper_excl)?.into()],
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?
        .ok_or_else(|| HistoryError::Integrity("has_work_in_range returned no row".into()))?;
    Ok(row.try_get::<i64>("", "present")? != 0)
}

pub(super) async fn work_range_events(
    db: &impl ConnectionTrait,
    after_excl: u64,
    upper_incl: u64,
    limit: usize,
) -> Result<Vec<Record>> {
    if after_excl >= upper_incl || limit == 0 {
        return Ok(Vec::new());
    }
    let rows = db
        .query_all_raw(statement(
            &format!(
                "SELECT {COLUMNS} FROM history_events \
                 WHERE timeline_role=1 AND seq>? AND seq<=? \
                 ORDER BY seq ASC LIMIT ?"
            ),
            vec![
                number(after_excl)?.into(),
                number(upper_incl)?.into(),
                number(limit as u64)?.into(),
            ],
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?;
    rows.into_iter().map(decode_row).collect()
}

pub(super) async fn original_by_entity(
    db: &impl ConnectionTrait,
    entity: &str,
    through: u64,
) -> Result<Option<Record>> {
    db.query_one_raw(statement(
        &format!(
            "SELECT {COLUMNS} FROM history_events \
             WHERE entity_id=? AND query_class IS NOT NULL AND seq<=? ORDER BY seq DESC LIMIT 1"
        ),
        vec![entity.into(), number(through)?.into()],
    ))
    .await
    .inspect(|_| {
        tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
    })?
    .map(decode_row)
    .transpose()
}

pub(super) async fn head(db: &impl ConnectionTrait, row: &str, cut: u64) -> Result<Option<Record>> {
    db.query_one_raw(statement(
        &format!(
            "SELECT {COLUMNS} FROM history_events WHERE row_key=? AND seq<=? ORDER BY seq DESC LIMIT 1"
        ),
        vec![row.into(), number(cut)?.into()],
    ))
    .await
    .inspect(|_| {
        tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
    })?
    .map(decode_row)
    .transpose()
}

pub(super) async fn anchor(db: &impl ConnectionTrait, row: &str) -> Result<Option<Record>> {
    db.query_one_raw(statement(
        &format!("SELECT {COLUMNS} FROM history_events WHERE row_key=? AND is_anchor=1"),
        vec![row.into()],
    ))
    .await
    .inspect(|_| {
        tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
    })?
    .map(decode_row)
    .transpose()
}

pub(super) async fn business_anchors(
    db: &impl ConnectionTrait,
    scope: HistoryBusinessRowScope,
    through: u64,
    before: Option<u64>,
    limit: usize,
) -> Result<Vec<(String, u64)>> {
    if limit == 0 {
        return Ok(Vec::new());
    }
    let upper = before.map_or(through, |b| b.saturating_sub(1).min(through));
    let rows = db
        .query_all_raw(statement(
            "SELECT row_key, seq FROM history_events \
             WHERE is_anchor=1 AND row_scope=? AND seq<=? \
             ORDER BY seq DESC LIMIT ?",
            vec![
                scope.as_str().into(),
                number(upper)?.into(),
                number(limit as u64)?.into(),
            ],
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?;
    let mut anchors = Vec::with_capacity(rows.len());
    for row in rows {
        let key: String = row.try_get("", "row_key")?;
        let seq = u64::try_from(row.try_get::<i64>("", "seq")?)
            .map_err(|_| HistoryError::Integrity("negative anchor sequence".into()))?;
        anchors.push((key, seq));
    }
    Ok(anchors)
}

pub(super) fn event_filter(query: &HistoryEventsQuery) -> Result<(String, Vec<Value>)> {
    Ok(match query {
        HistoryEventsQuery::AllEvents => ("1=1".into(), vec![]),
        HistoryEventsQuery::Entity { entity_id } => {
            ("entity_id=?".into(), vec![entity_id.clone().into()])
        }
        HistoryEventsQuery::Turn { turn_id } => ("turn_id=?".into(), vec![turn_id.clone().into()]),
        HistoryEventsQuery::Source { source } => {
            ("source_id=?".into(), vec![source_key(source)?.into()])
        }
        HistoryEventsQuery::Call { call_id } => ("call_id=?".into(), vec![call_id.clone().into()]),
        HistoryEventsQuery::Originals { scope } => {
            let mut clauses = vec!["query_class IS NOT NULL".to_owned()];
            let mut values = Vec::new();
            match &scope.query_class {
                crate::ChatClassFilter::All {} => {}
                crate::ChatClassFilter::Class { value: query_class } => {
                    clauses.push("query_class=?".into());
                    values.push(query_class.clone().into());
                }
            }
            if let Some(parent) = &scope.parent_id {
                clauses.push("parent_id=?".into());
                values.push(parent.as_str().to_owned().into());
            }
            (clauses.join(" AND "), values)
        }
        HistoryEventsQuery::TextOriginals => (
            "query_class IS NOT NULL AND original_kind IN ('text','input')".into(),
            vec![],
        ),
    })
}

pub(super) async fn events_filtered(
    db: &impl ConnectionTrait,
    query: &HistoryEventsQuery,
    min_excl: u64,
    max_incl: u64,
    ascending: bool,
    limit: usize,
) -> Result<Vec<Record>> {
    if min_excl >= max_incl || limit == 0 {
        return Ok(Vec::new());
    }
    let (predicate, mut values) = event_filter(query)?;
    values.push(number(min_excl)?.into());
    values.push(number(max_incl)?.into());
    values.push(number(limit as u64)?.into());
    let order = if ascending { "ASC" } else { "DESC" };
    let rows = db
        .query_all_raw(statement(
            &format!(
                "SELECT {COLUMNS} FROM history_events \
                 WHERE {predicate} AND seq>? AND seq<=? \
                 ORDER BY seq {order} LIMIT ?"
            ),
            values,
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?;
    rows.into_iter().map(decode_row).collect()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Body {
    pub id: String,
    pub owner: String,
    pub ordinal: u64,
    pub key: String,
    pub role: HistoryBodyRole,
    pub length: u64,
    pub media_type: Option<String>,
    pub digest: Vec<u8>,
}

impl Body {
    pub fn from_event(event: &HistoryEvent, ordinal: usize) -> Self {
        let body = &event.bodies[ordinal];
        Self {
            id: body.body_id.clone(),
            owner: event.event_id.clone(),
            ordinal: ordinal as u64,
            key: body.body_key.clone(),
            role: body.role.clone(),
            length: body.bytes.len() as u64,
            media_type: body.media_type.clone(),
            digest: body.digest(),
        }
    }

    pub fn reference(&self, database: &str) -> HistoryEventBodyRef {
        HistoryEventBodyRef {
            database_id: database.into(),
            owner_event_id: self.owner.clone(),
            body_key: self.key.clone(),
            body_id: self.id.clone(),
            byte_start: 0,
            byte_length: self.length,
        }
    }

    pub fn entry(&self, database: &str) -> HistoryBodyEntry {
        HistoryBodyEntry {
            ordinal: self.ordinal,
            body_key: self.key.clone(),
            role: self.role.clone(),
            reference: self.reference(database),
            media_type: self.media_type.clone(),
        }
    }
}

fn decode_body(row: QueryResult) -> Result<Body> {
    let role: String = row.try_get("", "role")?;
    let ordinal = u64::try_from(row.try_get::<i64>("", "ordinal")?)
        .map_err(|_| HistoryError::Integrity("negative body ordinal".into()))?;
    let length = u64::try_from(row.try_get::<i64>("", "byte_length")?)
        .map_err(|_| HistoryError::Integrity("negative body byte_length".into()))?;
    let digest: Vec<u8> = row.try_get("", "digest")?;
    if digest.len() != 32 {
        return Err(HistoryError::Integrity("invalid body digest length".into()));
    }
    Ok(Body {
        id: row.try_get("", "body_id")?,
        owner: row.try_get("", "owner_event_id")?,
        ordinal,
        key: row.try_get("", "body_key")?,
        role: HistoryBodyRole::from_string(role),
        length,
        media_type: row.try_get("", "media_type")?,
        digest,
    })
}

pub(super) async fn body(db: &impl ConnectionTrait, id: &str) -> Result<Option<Body>> {
    db.query_one_raw(statement(
        "SELECT body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest \
         FROM history_bodies WHERE body_id=?",
        vec![id.into()],
    ))
    .await
    .inspect(|_| {
        tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
    })?
    .map(decode_body)
    .transpose()
}

pub(super) async fn bodies(
    db: &impl ConnectionTrait,
    owner: &str,
    after: Option<u64>,
    limit: usize,
) -> Result<Vec<Body>> {
    if limit == 0 {
        return Ok(Vec::new());
    }
    let (filter, mut values) = if let Some(after) = after {
        (
            "owner_event_id=? AND ordinal>?",
            vec![owner.into(), number(after)?.into()],
        )
    } else {
        ("owner_event_id=?", vec![owner.into()])
    };
    values.push(number(limit as u64)?.into());
    let rows = db
        .query_all_raw(statement(
            &format!(
                "SELECT body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest \
                 FROM history_bodies WHERE {filter} ORDER BY ordinal ASC LIMIT ?"
            ),
            values,
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?;
    rows.into_iter().map(decode_body).collect()
}

pub(super) async fn window(
    db: &impl ConnectionTrait,
    body: &Body,
    offset: u64,
    length: u32,
) -> Result<Vec<u8>> {
    if offset > body.length {
        return Err(HistoryError::InvalidDemand(
            "body read offset exceeds body length".into(),
        ));
    }
    let want = (body.length - offset).min(length.min(BODY_CHUNK_BYTES as u32) as u64) as usize;
    if want == 0 {
        return Ok(Vec::new());
    }
    let first_chunk = offset / BODY_CHUNK_BYTES as u64;
    let last_chunk = (offset + want as u64 - 1) / BODY_CHUNK_BYTES as u64;
    let rows = db
        .query_all_raw(statement(
            "SELECT chunk_no, data FROM history_body_chunks \
             WHERE body_id=? AND chunk_no>=? AND chunk_no<=? ORDER BY chunk_no ASC",
            vec![
                body.id.clone().into(),
                number(first_chunk)?.into(),
                number(last_chunk)?.into(),
            ],
        ))
        .await
        .inspect(|_| {
            tracing::debug!(target: "conversation_work", history_sql_read = 1u64, "history SQL read completed");
        })?;
    let mut expected_chunk = first_chunk;
    let mut assembled = Vec::with_capacity(want);
    let mut loaded_bytes: u64 = 0;
    let mut chunk_start = (offset % BODY_CHUNK_BYTES as u64) as usize;
    for row in rows {
        let chunk_no = u64::try_from(row.try_get::<i64>("", "chunk_no")?)
            .map_err(|_| HistoryError::Integrity("negative chunk index".into()))?;
        if chunk_no != expected_chunk {
            return Err(HistoryError::Integrity(format!(
                "body {} has chunk gap before {}",
                body.id, expected_chunk
            )));
        }
        let data: Vec<u8> = row.try_get("", "data")?;
        loaded_bytes = loaded_bytes.saturating_add(data.len() as u64);
        if chunk_start >= data.len() {
            return Err(HistoryError::Integrity(format!(
                "body {} chunk {} truncated before offset",
                body.id, chunk_no
            )));
        }
        let remaining = want - assembled.len();
        let end = (chunk_start + remaining).min(data.len());
        assembled.extend_from_slice(&data[chunk_start..end]);
        chunk_start = 0;
        expected_chunk += 1;
    }
    if expected_chunk <= last_chunk || assembled.len() != want {
        return Err(HistoryError::Integrity(format!(
            "body {} truncated while reading window",
            body.id
        )));
    }
    tracing::debug!(
        target: "conversation_work",
        history_body_bytes_read = loaded_bytes,
        history_body_returned_bytes = assembled.len() as u64,
        "history body window read"
    );
    Ok(assembled)
}

pub(super) async fn insert(db: &impl ConnectionTrait, event: &HistoryEvent) -> Result<()> {
    insert_event(db, event).await?;
    for ordinal in 0..event.bodies.len() {
        let header = Body::from_event(event, ordinal);
        insert_body_header(db, &header).await?;
        let raw = &event.bodies[ordinal].bytes;
        let expected_digest = Sha256::digest(raw);
        if expected_digest.as_slice() != header.digest.as_slice() {
            return Err(HistoryError::Integrity(
                "history body digest mismatch on insert".into(),
            ));
        }
        for (chunk_no, chunk) in raw.chunks(BODY_CHUNK_BYTES).enumerate() {
            db.execute_raw(statement(
                "INSERT OR IGNORE INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
                vec![
                    header.id.clone().into(),
                    number(chunk_no as u64)?.into(),
                    chunk.to_vec().into(),
                ],
            ))
            .await?;
            tracing::debug!(target: "conversation_work", history_sql_write = 1u64, "history SQL chunk write completed");
        }
    }
    Ok(())
}

pub(super) async fn insert_event(db: &impl ConnectionTrait, event: &HistoryEvent) -> Result<()> {
    let source_id = event.source.as_ref().map(source_key).transpose()?;
    let (query_class, parent_id, original_kind) = match &event.original {
        Some(original) => {
            let kind = match serde_json::to_value(original.original_kind)? {
                serde_json::Value::String(text) => text,
                _ => {
                    return Err(HistoryError::InvalidEvent(
                        "original kind did not serialize as string".into(),
                    ));
                }
            };
            (
                Some(original.query_class.clone()),
                original.parent_id.clone(),
                Some(kind),
            )
        }
        None => (None, None, None),
    };
    let row_scope = event.row_scope.map(|scope| scope.as_str().to_owned());
    db.execute_raw(statement(
        &format!(
            "INSERT OR IGNORE INTO history_events({COLUMNS}) \
             VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
        ),
        vec![
            number(event.seq)?.into(),
            event.event_id.clone().into(),
            event.kind.as_str().to_owned().into(),
            event.timeline_role.as_db_int().into(),
            event.occurred_at.into(),
            event.recorded_at.into(),
            event.run_id.clone().into(),
            event.turn_id.clone().into(),
            event.attempt_id.clone().into(),
            event.call_id.clone().into(),
            event.entity_id.clone().into(),
            event.message_id.clone().into(),
            event.tool_name.clone().into(),
            source_id.into(),
            query_class.into(),
            parent_id.into(),
            original_kind.into(),
            row_scope.into(),
            event.row_key.clone().into(),
            i64::from(event.is_anchor).into(),
            event.payload_schema.clone().into(),
            event.payload_json.clone().into(),
        ],
    ))
    .await?;
    tracing::debug!(target: "conversation_work", history_sql_write = 1u64, "history SQL event write completed");
    Ok(())
}

pub(super) async fn insert_body_header(db: &impl ConnectionTrait, body: &Body) -> Result<()> {
    db.execute_raw(statement(
        "INSERT OR IGNORE INTO history_bodies(body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest) \
         VALUES(?,?,?,?,?,?,?,?)",
        vec![
            body.id.clone().into(),
            body.owner.clone().into(),
            number(body.ordinal)?.into(),
            body.key.clone().into(),
            body.role.as_str().to_owned().into(),
            number(body.length)?.into(),
            body.media_type.clone().into(),
            body.digest.clone().into(),
        ],
    ))
    .await?;
    tracing::debug!(target: "conversation_work", history_sql_write = 1u64, "history SQL body header write completed");
    Ok(())
}

pub(super) fn dedup_records_desc(
    database: Vec<Record>,
    pending: Vec<&Arc<pending::Accepted>>,
    limit: usize,
) -> Vec<Record> {
    let mut seen_seq = BTreeSet::new();
    let mut merged: Vec<Record> = Vec::with_capacity(database.len() + pending.len());
    for accepted in pending {
        if seen_seq.insert(accepted.event.seq) {
            merged.push(Record::from_event(&accepted.event));
        }
    }
    for row in database {
        if seen_seq.insert(row.record.seq) {
            merged.push(row);
        }
    }
    merged.sort_by_key(|a| std::cmp::Reverse(a.record.seq));
    merged.truncate(limit);
    merged
}

pub(super) struct KnownBodyMeta {
    pub(super) owner: String,
    pub(super) key: String,
    pub(super) length: u64,
}

#[derive(Default)]
pub(super) struct KnownIndex {
    pub(super) events: std::collections::HashSet<String>,
    pub(super) anchors: std::collections::HashSet<String>,
    pub(super) bodies: std::collections::HashMap<String, KnownBodyMeta>,
    pub(super) latest_accounting: Option<HistoryAccountingHead>,
    pub(super) latest_costs: std::collections::BTreeMap<String, HistoryCostHead>,
}

pub(super) async fn load_known_index(db: &impl ConnectionTrait) -> Result<KnownIndex> {
    let mut index = KnownIndex::default();
    let event_rows = db
        .query_all_raw(statement(
            "SELECT event_id, is_anchor, row_scope, row_key, seq, payload_schema, payload_json FROM history_events ORDER BY seq ASC",
            vec![],
        ))
        .await?;
    for row in event_rows {
        let event_id: String = row.try_get("", "event_id")?;
        index.events.insert(event_id);
        let is_anchor: i64 = row.try_get("", "is_anchor")?;
        let row_key: Option<String> = row.try_get("", "row_key")?;
        if is_anchor == 1
            && let Some(row_key) = &row_key
        {
            index.anchors.insert(row_key.clone());
        }
        let row_scope: Option<String> = row.try_get("", "row_scope")?;
        if matches!(row_scope.as_deref(), Some("accounting" | "cost"))
            && let Some(row_key) = row_key
        {
            let schema: String = row.try_get("", "payload_schema")?;
            let json_str: String = row.try_get("", "payload_json")?;
            if schema == "anywork.accounting/1" {
                if let Ok(env) = serde_json::from_str::<
                    super::body::BusinessEnvelope<HistoryAccountingHead>,
                >(&json_str)
                {
                    index.latest_accounting = Some(env.head);
                }
            } else if schema == "anywork.cost/1"
                && let Ok(env) = serde_json::from_str::<
                    super::body::BusinessEnvelope<HistoryCostHead>,
                >(&json_str)
            {
                index.latest_costs.insert(row_key, env.head);
            }
        }
    }
    let body_rows = db
        .query_all_raw(statement(
            "SELECT body_id, owner_event_id, body_key, byte_length FROM history_bodies",
            vec![],
        ))
        .await?;
    for row in body_rows {
        let body_id: String = row.try_get("", "body_id")?;
        let owner: String = row.try_get("", "owner_event_id")?;
        let key: String = row.try_get("", "body_key")?;
        let length = u64::try_from(row.try_get::<i64>("", "byte_length")?)
            .map_err(|_| HistoryError::Integrity("negative history body length".into()))?;
        index
            .bodies
            .insert(body_id, KnownBodyMeta { owner, key, length });
    }
    Ok(index)
}

pub(super) fn dedup_records_asc(
    database: Vec<Record>,
    pending: Vec<&Arc<pending::Accepted>>,
    limit: usize,
) -> Vec<Record> {
    let mut seen_seq = BTreeSet::new();
    let mut merged: Vec<Record> = Vec::with_capacity(database.len() + pending.len());
    for row in database {
        if seen_seq.insert(row.record.seq) {
            merged.push(row);
        }
    }
    for accepted in pending {
        if seen_seq.insert(accepted.event.seq) {
            merged.push(Record::from_event(&accepted.event));
        }
    }
    merged.sort_by_key(|a| a.record.seq);
    merged.truncate(limit);
    merged
}
