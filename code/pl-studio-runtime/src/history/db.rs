use sea_orm::{ConnectionTrait, DatabaseBackend, QueryResult, Statement, Value};
use sha2::{Digest, Sha256};

use super::{token::Query, types::source_key, *};

pub(super) fn statement(sql: &str, values: Vec<Value>) -> Statement {
    Statement::from_sql_and_values(DatabaseBackend::Sqlite, sql, values)
}
pub(super) fn number(value: u64) -> Result<i64> {
    i64::try_from(value)
        .map_err(|_| HistoryError::InvalidEvent("history integer exceeds SQLite range".into()))
}

const COLUMNS: &str = "seq,event_id,kind,run_id,attempt_id,entity_id,turn_id,source_kind,source_id,call_id,message_id,query_class,parent_id,original_kind,tool_name,group_id,row_scope,row_key,is_anchor,occurred_at,recorded_at,head_json,payload_body_id";

#[derive(Debug, Clone, PartialEq)]
pub(super) struct Record {
    pub header: HistoryEventHeader,
    pub head: Option<HistoryRowHead>,
    pub is_anchor: bool,
    pub payload_body_id: Option<String>,
}
impl Record {
    pub fn from_event(event: &HistoryEvent) -> Self {
        Self {
            header: event.header.clone(),
            head: event.head.clone(),
            is_anchor: event.is_anchor,
            payload_body_id: event.payload_body_id.clone(),
        }
    }
}

fn decode(row: QueryResult) -> Result<Record> {
    let kind: String = row.try_get("", "kind")?;
    let source: Option<String> = row.try_get("", "source_id")?;
    let class: Option<String> = row.try_get("", "query_class")?;
    let head: Option<String> = row.try_get("", "head_json")?;
    let original = if let Some(query_class) = class {
        let kind: String = row.try_get("", "original_kind")?;
        Some(HistoryOriginalInfo {
            query_class,
            parent_id: row.try_get("", "parent_id")?,
            original_kind: serde_json::from_value(serde_json::Value::String(kind))?,
            tool_name: row.try_get("", "tool_name")?,
        })
    } else {
        None
    };
    let record = Record {
        header: HistoryEventHeader {
            seq: u64::try_from(row.try_get::<i64>("", "seq")?)
                .map_err(|_| HistoryError::Integrity("negative event sequence".into()))?,
            event_id: row.try_get("", "event_id")?,
            kind: kind.into(),
            run_id: row.try_get("", "run_id")?,
            attempt_id: row.try_get("", "attempt_id")?,
            entity_id: row.try_get("", "entity_id")?,
            turn_id: row.try_get("", "turn_id")?,
            source: source
                .map(|source| serde_json::from_str(&source))
                .transpose()?,
            call_id: row.try_get("", "call_id")?,
            message_id: row.try_get("", "message_id")?,
            group_id: row.try_get("", "group_id")?,
            row_key: row.try_get("", "row_key")?,
            original,
            occurred_at: row.try_get("", "occurred_at")?,
            recorded_at: row.try_get("", "recorded_at")?,
        },
        head: head.map(|head| serde_json::from_str(&head)).transpose()?,
        is_anchor: row.try_get::<i64>("", "is_anchor")? == 1,
        payload_body_id: row.try_get("", "payload_body_id")?,
    };
    if record.head.as_ref().map(|head| head.scope())
        != row.try_get::<Option<String>>("", "row_scope")?.as_deref()
    {
        return Err(HistoryError::Integrity(
            "row head and indexed scope differ".into(),
        ));
    }
    if let Some(source) = &record.header.source
        && Some(source_key(source)?.0) != row.try_get::<Option<String>>("", "source_kind")?
    {
        return Err(HistoryError::Integrity(
            "source identity differs from its indexed kind".into(),
        ));
    }
    Ok(record)
}

pub(super) async fn event(db: &impl ConnectionTrait, id: &str) -> Result<Option<Record>> {
    db.query_one_raw(statement(
        &format!("SELECT {COLUMNS} FROM history_events WHERE event_id=?"),
        vec![id.into()],
    ))
    .await?
    .map(decode)
    .transpose()
}
pub(super) async fn head(db: &impl ConnectionTrait, row: &str, cut: u64) -> Result<Option<Record>> {
    db.query_one_raw(statement(&format!("SELECT {COLUMNS} FROM history_events WHERE row_key=? AND seq<=? ORDER BY seq DESC LIMIT 1"), vec![row.into(), number(cut)?.into()])).await?.map(decode).transpose()
}
pub(super) async fn anchor(db: &impl ConnectionTrait, row: &str) -> Result<Option<Record>> {
    db.query_one_raw(statement(
        &format!("SELECT {COLUMNS} FROM history_events WHERE row_key=? AND is_anchor=1"),
        vec![row.into()],
    ))
    .await?
    .map(decode)
    .transpose()
}

pub(super) fn selection(query: &Query) -> Result<(String, Vec<Value>)> {
    Ok(match query {
        Query::Main => (
            "is_anchor=1 AND row_scope IN ('work','single')".into(),
            vec![],
        ),
        Query::Group(id) => (
            "is_anchor=1 AND row_scope='member' AND group_id=?".into(),
            vec![id.clone().into()],
        ),
        Query::Rows(scope) => (
            "is_anchor=1 AND row_scope=?".into(),
            vec![scope.clone().into()],
        ),
        Query::Events(query) => match query {
            HistoryEventsQuery::AllEvents => ("1=1".into(), vec![]),
            HistoryEventsQuery::Entity { entity_id } => {
                ("entity_id=?".into(), vec![entity_id.clone().into()])
            }
            HistoryEventsQuery::Turn { turn_id } => {
                ("turn_id=?".into(), vec![turn_id.clone().into()])
            }
            HistoryEventsQuery::Call { call_id } => {
                ("call_id=?".into(), vec![call_id.clone().into()])
            }
            HistoryEventsQuery::Message { message_id } => {
                ("message_id=?".into(), vec![message_id.clone().into()])
            }
            HistoryEventsQuery::Source { source } => {
                let (kind, id) = source_key(source)?;
                (
                    "source_kind=? AND source_id=?".into(),
                    vec![kind.into(), id.into()],
                )
            }
            HistoryEventsQuery::Attempt { run_id, attempt_id } => (
                "run_id=? AND attempt_id=?".into(),
                vec![run_id.clone().into(), attempt_id.clone().into()],
            ),
            HistoryEventsQuery::TextOriginals => (
                "query_class IS NOT NULL AND original_kind IN ('text','input')".into(),
                vec![],
            ),
            HistoryEventsQuery::Originals { scope } => {
                if !scope.is_valid() {
                    return Err(HistoryError::InvalidDemand(
                        "invalid canonical scope".into(),
                    ));
                }
                match (scope.query_class(), scope.parent_id()) {
                    (None, None) => ("query_class IS NOT NULL".into(), vec![]),
                    (Some(class), None) => ("query_class=?".into(), vec![class.into()]),
                    (None, Some(parent)) => (
                        "query_class IS NOT NULL AND parent_id=?".into(),
                        vec![parent.into()],
                    ),
                    (Some(class), Some(parent)) => (
                        "query_class=? AND parent_id=?".into(),
                        vec![class.into(), parent.into()],
                    ),
                }
            }
        },
    })
}

pub(super) async fn candidates(
    db: &impl ConnectionTrait,
    query: &Query,
    cut: u64,
    before: Option<u64>,
    limit: usize,
) -> Result<Vec<Record>> {
    let (sql, values) = candidate_sql(query, cut, before, limit, COLUMNS)?;
    db.query_all_raw(statement(&sql, values))
        .await?
        .into_iter()
        .map(decode)
        .collect()
}

fn candidate_sql(
    query: &Query,
    cut: u64,
    before: Option<u64>,
    limit: usize,
    columns: &str,
) -> Result<(String, Vec<Value>)> {
    let (condition, mut values) = selection(query)?;
    // These are fixed protocol queries over named partial indexes. SQLite otherwise may prefer
    // a competing index and sort or filter the complete matching prefix. INDEXED BY makes
    // the required access path executable and fails if the format no longer provides it.
    let table = match query {
        Query::Main => "history_events INDEXED BY history_main_anchors",
        Query::Group(_) => "history_events INDEXED BY history_member_anchors",
        Query::Rows(_) => "history_events INDEXED BY history_business_anchors",
        Query::Events(HistoryEventsQuery::Originals { scope }) => {
            match (scope.query_class(), scope.parent_id()) {
                (None, None) => "history_events INDEXED BY history_originals_all",
                (Some(_), None) => "history_events INDEXED BY history_originals_class",
                (None, Some(_)) => "history_events INDEXED BY history_originals_parent",
                (Some(_), Some(_)) => "history_events INDEXED BY history_originals_parent_class",
            }
        }
        Query::Events(HistoryEventsQuery::TextOriginals) => {
            "history_events INDEXED BY history_originals_text"
        }
        Query::Events(_) => "history_events",
    };
    let mut sql = format!("SELECT {columns} FROM {table} WHERE {condition} AND seq<=?");
    values.push(number(cut)?.into());
    if let Some(before) = before {
        sql.push_str(" AND seq<?");
        values.push(number(before)?.into());
    }
    sql.push_str(" ORDER BY seq DESC LIMIT ?");
    values.push((limit as i64).into());
    Ok((sql, values))
}

pub(super) async fn anchors(
    db: &impl ConnectionTrait,
    query: &Query,
    cut: u64,
    before: Option<u64>,
    limit: usize,
) -> Result<Vec<(u64, String)>> {
    let (sql, values) = candidate_sql(query, cut, before, limit, "seq,row_key")?;
    db.query_all_raw(statement(&sql, values))
        .await?
        .into_iter()
        .map(|row| {
            Ok((
                u64::try_from(row.try_get::<i64>("", "seq")?)
                    .map_err(|_| HistoryError::Integrity("negative anchor sequence".into()))?,
                row.try_get("", "row_key")?,
            ))
        })
        .collect()
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
            owner: event.header.event_id.clone(),
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
    let body = Body {
        id: row.try_get("", "body_id")?,
        owner: row.try_get("", "owner_event_id")?,
        ordinal: u64::try_from(row.try_get::<i64>("", "ordinal")?)
            .map_err(|_| HistoryError::Integrity("negative body ordinal".into()))?,
        key: row.try_get("", "body_key")?,
        role: HistoryBodyRole::from_string(row.try_get("", "role")?),
        length: u64::try_from(row.try_get::<i64>("", "byte_length")?)
            .map_err(|_| HistoryError::Integrity("negative body length".into()))?,
        media_type: row.try_get("", "media_type")?,
        digest: row.try_get("", "digest")?,
    };
    if body.digest.len() != 32 {
        return Err(HistoryError::Integrity("invalid body digest".into()));
    }
    Ok(body)
}
pub(super) async fn body(db: &impl ConnectionTrait, id: &str) -> Result<Option<Body>> {
    db.query_one_raw(statement(
        "SELECT * FROM history_bodies WHERE body_id=?",
        vec![id.into()],
    ))
    .await?
    .map(decode_body)
    .transpose()
}
pub(super) async fn bodies(
    db: &impl ConnectionTrait,
    owner: &str,
    after: Option<u64>,
    limit: usize,
) -> Result<Vec<Body>> {
    let mut values = vec![owner.into()];
    let mut sql = "SELECT * FROM history_bodies WHERE owner_event_id=?".to_owned();
    if let Some(after) = after {
        sql.push_str(" AND ordinal>?");
        values.push(number(after)?.into());
    }
    sql.push_str(" ORDER BY ordinal LIMIT ?");
    values.push((limit as i64).into());
    db.query_all_raw(statement(&sql, values))
        .await?
        .into_iter()
        .map(decode_body)
        .collect()
}

pub(super) async fn window(
    db: &impl ConnectionTrait,
    body: &Body,
    start: u64,
    length: usize,
) -> Result<Vec<u8>> {
    let end = start
        .checked_add(length as u64)
        .filter(|end| *end <= body.length)
        .ok_or_else(|| {
            HistoryError::InvalidDemand("body range exceeds its immutable slice".into())
        })?;
    if length == 0 {
        return Ok(Vec::new());
    }
    let first = start / BODY_CHUNK_BYTES as u64;
    let last = (end - 1) / BODY_CHUNK_BYTES as u64;
    let rows = db.query_all_raw(statement("SELECT chunk_no,data FROM history_body_chunks WHERE body_id=? AND chunk_no BETWEEN ? AND ? ORDER BY chunk_no", vec![body.id.clone().into(), number(first)?.into(), number(last)?.into()])).await?;
    if rows.len() as u64 != last - first + 1 {
        return Err(HistoryError::Integrity("body chunk is missing".into()));
    }
    let mut bytes = Vec::with_capacity(length);
    for (index, row) in rows.into_iter().enumerate() {
        let chunk = first + index as u64;
        let data: Vec<u8> = row.try_get("", "data")?;
        let offset = chunk * BODY_CHUNK_BYTES as u64;
        let expected = (body.length - offset).min(BODY_CHUNK_BYTES as u64) as usize;
        if number(chunk)? != row.try_get::<i64>("", "chunk_no")? || data.len() != expected {
            return Err(HistoryError::Integrity(
                "invalid body chunk length or order".into(),
            ));
        }
        let lower = start.saturating_sub(offset) as usize;
        let upper = (end - offset).min(data.len() as u64) as usize;
        bytes.extend_from_slice(&data[lower..upper]);
    }
    if start == 0 && end == body.length && Sha256::digest(&bytes).as_slice() != body.digest {
        return Err(HistoryError::Integrity("body digest differs".into()));
    }
    Ok(bytes)
}

pub(super) async fn insert(
    db: &impl ConnectionTrait,
    event: &HistoryEvent,
    headers: &[Body],
) -> Result<()> {
    insert_event(db, event).await?;
    for (ordinal, body) in event.bodies.iter().enumerate() {
        insert_body_header(db, &headers[ordinal]).await?;
        for (chunk, data) in body.bytes.chunks(BODY_CHUNK_BYTES).enumerate() {
            db.execute_raw(statement(
                "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
                vec![
                    body.body_id.clone().into(),
                    (chunk as i64).into(),
                    data.to_vec().into(),
                ],
            ))
            .await?;
        }
    }
    Ok(())
}
pub(super) async fn insert_event(db: &impl ConnectionTrait, event: &HistoryEvent) -> Result<()> {
    let h = &event.header;
    let source = h.source.as_ref().map(source_key).transpose()?;
    let original = h.original.as_ref();
    let kind = original
        .map(|original| serde_json::to_value(original.original_kind))
        .transpose()?
        .and_then(|value| value.as_str().map(str::to_owned));
    db.execute_raw(statement(
        &format!(
            "INSERT INTO history_events({COLUMNS}) VALUES({})",
            vec!["?"; 23].join(",")
        ),
        vec![
            number(h.seq)?.into(),
            h.event_id.clone().into(),
            h.kind.as_str().into(),
            h.run_id.clone().into(),
            h.attempt_id.clone().into(),
            h.entity_id.clone().into(),
            h.turn_id.clone().into(),
            source.as_ref().map(|s| s.0.clone()).into(),
            source.map(|s| s.1).into(),
            h.call_id.clone().into(),
            h.message_id.clone().into(),
            original.map(|o| o.query_class.clone()).into(),
            original.and_then(|o| o.parent_id.clone()).into(),
            kind.into(),
            original.and_then(|o| o.tool_name.clone()).into(),
            h.group_id.clone().into(),
            event
                .head
                .as_ref()
                .map(|head| head.scope().to_owned())
                .into(),
            h.row_key.clone().into(),
            i64::from(event.is_anchor).into(),
            h.occurred_at.into(),
            h.recorded_at.into(),
            event
                .head
                .as_ref()
                .map(serde_json::to_string)
                .transpose()?
                .into(),
            event.payload_body_id.clone().into(),
        ],
    ))
    .await?;
    Ok(())
}
pub(super) async fn insert_body_header(db: &impl ConnectionTrait, body: &Body) -> Result<()> {
    db.execute_raw(statement("INSERT INTO history_bodies(body_id,owner_event_id,ordinal,body_key,role,byte_length,media_type,digest) VALUES(?,?,?,?,?,?,?,?)", vec![body.id.clone().into(), body.owner.clone().into(), number(body.ordinal)?.into(), body.key.clone().into(), body.role.as_str().into(), number(body.length)?.into(), body.media_type.clone().into(), body.digest.clone().into()])).await?;
    Ok(())
}

pub(super) async fn review_finish(
    db: &impl ConnectionTrait,
    turn: &str,
    cut: u64,
) -> Result<Option<Record>> {
    db.query_one_raw(statement(&format!("SELECT {COLUMNS} FROM history_events WHERE query_class IS NOT NULL AND tool_name=? AND turn_id=? AND seq<=? ORDER BY seq DESC LIMIT 1"), vec![pl_tool::finish_turn::TOOL_FINISH_TURN.into(), turn.into(), number(cut)?.into()])).await?.map(decode).transpose()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn actual_page_sql_seeks_anchors_and_business_indexes_at_deep_cursors() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            directory.path().join("h.sqlite"),
            "plans",
            HistoryLimits::default(),
        )
        .await?;
        let cases = [
            (Query::Main, "history_main_anchors"),
            (Query::Group("group".into()), "history_member_anchors"),
            (Query::Rows("cost".into()), "history_business_anchors"),
            (
                Query::Events(HistoryEventsQuery::Entity {
                    entity_id: "entity".into(),
                }),
                "history_entity_events",
            ),
            (
                Query::Events(HistoryEventsQuery::Turn {
                    turn_id: "turn".into(),
                }),
                "history_turn_events",
            ),
            (
                Query::Events(HistoryEventsQuery::Call {
                    call_id: "call".into(),
                }),
                "history_call_events",
            ),
            (
                Query::Events(HistoryEventsQuery::Message {
                    message_id: "message".into(),
                }),
                "history_message_events",
            ),
            (
                Query::Events(HistoryEventsQuery::Attempt {
                    run_id: "run".into(),
                    attempt_id: "attempt".into(),
                }),
                "history_attempt_events",
            ),
            (
                Query::Events(HistoryEventsQuery::Source {
                    source: HistorySource::Input {
                        input_id: "input".into(),
                    },
                }),
                "history_source_events",
            ),
            (
                Query::Events(HistoryEventsQuery::Originals {
                    scope: ChatScope::conversation(None),
                }),
                "history_originals_class",
            ),
            (
                Query::Events(HistoryEventsQuery::Originals {
                    scope: ChatScope {
                        query_class: crate::ChatClassFilter::All {},
                        parent_id: None,
                    },
                }),
                "history_originals_all",
            ),
            (
                Query::Events(HistoryEventsQuery::Originals {
                    scope: ChatScope {
                        query_class: crate::ChatClassFilter::All {},
                        parent_id: Some("parent".into()),
                    },
                }),
                "history_originals_parent",
            ),
            (
                Query::Events(HistoryEventsQuery::Originals {
                    scope: ChatScope::conversation(Some("parent".into())),
                }),
                "history_originals_parent_class",
            ),
            (
                Query::Events(HistoryEventsQuery::TextOriginals),
                "history_originals_text",
            ),
        ];
        for (query, index) in cases {
            for before in [None, Some(100)] {
                let columns = if matches!(query, Query::Events(_)) {
                    COLUMNS
                } else {
                    "seq,row_key"
                };
                let (sql, values) = candidate_sql(&query, 10_000, before, 64, columns)?;
                let plan = store
                    .inner
                    .reader
                    .query_all_raw(statement(&format!("EXPLAIN QUERY PLAN {sql}"), values))
                    .await?;
                let plan = plan
                    .into_iter()
                    .map(|row| row.try_get::<String>("", "detail"))
                    .collect::<std::result::Result<Vec<_>, _>>()?
                    .join("\n");
                assert!(plan.contains(index), "{query:?}: {plan}");
                assert!(!plan.contains("USE TEMP B-TREE"), "{query:?}: {plan}");
            }
        }
        store.close().await?;
        Ok(())
    }
}
