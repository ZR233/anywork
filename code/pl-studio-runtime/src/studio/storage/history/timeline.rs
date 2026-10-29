//! Immutable completion storage. Execution ordinals are consulted only at the migration boundary.

use super::*;
use crate::studio::runtime::{
    chat_item::{decode_record, encode_record, legacy_completion_drafts},
    timeline_content::meta::TimelineMeta,
};
use pl_core::chat::ChatItemParts;
use pl_protocol::TimelineDescriptor;

/// The indexed facts and the canonical, current-codec payload of one immutable completion.
/// All columns are checked against the decoded record before it leaves storage.
struct TimelineRecord {
    append_seq: i64,
    record_id: String,
    turn_id: Option<String>,
    source_effect_seq: Option<i64>,
    sealed_at: Option<i64>,
    kind: String,
    payload: String,
}

impl TimelineRecord {
    fn from_row(row: sea_orm::QueryResult) -> Result<Self> {
        Ok(Self {
            append_seq: row.try_get("", "append_seq")?,
            record_id: row.try_get("", "record_id")?,
            turn_id: row.try_get("", "turn_id")?,
            source_effect_seq: row.try_get("", "source_effect_seq")?,
            sealed_at: row.try_get("", "sealed_at")?,
            kind: row.try_get("", "kind")?,
            payload: row.try_get("", "payload")?,
        })
    }

    fn decode(self, thread_id: &str) -> Result<ChatItem> {
        let item = decode_record(&self.payload)?;
        validate_record(&item, thread_id)?;
        ensure!(
            integer(item.append_seq)? == self.append_seq
                && item.item_id == self.record_id
                && item.turn_id == self.turn_id
                && item.source_effect_seq.map(integer).transpose()? == self.source_effect_seq
                && item.sealed_at == self.sealed_at
                && record_kind(&item)? == self.kind,
            "timeline record payload differs from its indexed identity or provenance"
        );
        Ok(item)
    }
}

fn record_kind(item: &ChatItem) -> Result<&'static str> {
    Ok(match TimelineMeta::for_item(item)?.descriptor {
        TimelineDescriptor::Text(_) => "text",
        TimelineDescriptor::Thinking(_) => "thinking",
        TimelineDescriptor::Tool(_) => "tool",
        TimelineDescriptor::Raw(_) => "raw",
        TimelineDescriptor::Agent(_) => "agent",
        TimelineDescriptor::Turn(_) => "turn",
        TimelineDescriptor::Inference(_) => "inference",
        TimelineDescriptor::Skill(_) => "skill",
        TimelineDescriptor::File(_) => "file",
        TimelineDescriptor::ContextCompaction(_) => "contextCompaction",
        TimelineDescriptor::Plan(_) => "plan",
    })
}

fn validate_record(item: &ChatItem, thread_id: &str) -> Result<()> {
    ensure!(
        !item.item_id.is_empty() && item.append_seq > 0,
        "timeline record requires a stable identity and positive append sequence"
    );
    integer(item.append_seq)?;
    if let Some(source) = item.source_effect_seq {
        ensure!(
            source > 0,
            "timeline source effect sequence must be positive"
        );
        integer(source)?;
    }
    ensure!(
        item.turn_id.as_ref().is_none_or(|turn| !turn.is_empty()),
        "unknown timeline Turn identity must be absent, not empty"
    );
    ensure!(
        item.fields.values().all(|field| field.is_complete()),
        "timeline persistence requires complete content, not a bounded preview"
    );
    ensure!(
        TimelineMeta::for_item(item)?.thread_id == thread_id,
        "timeline record belongs to another Thread"
    );
    Ok(())
}

pub(super) async fn latest_append_seq(db: &impl ConnectionTrait) -> Result<u64> {
    let row = db
        .query_one_raw(statement(
            "SELECT MAX(append_seq) AS head FROM timeline_records",
            vec![],
        ))
        .await?
        .context("timeline head query returned no row")?;
    Ok(u64::try_from(
        row.try_get::<Option<i64>>("", "head")?.unwrap_or(0),
    )?)
}

/// The caller owns the writer/migration transaction. This function never commits independently.
/// On an effect retry, `allow_new=false` proves every supplied completion was already committed.
pub(super) async fn append_records(
    db: &impl ConnectionTrait,
    thread_id: &str,
    records: &[ChatItem],
    allow_new: bool,
) -> Result<()> {
    let mut head = latest_append_seq(db).await?;
    for item in records {
        validate_record(item, thread_id)?;
        let rows = db
            .query_all_raw(statement(
                "SELECT append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload
                 FROM timeline_records WHERE append_seq=? OR record_id=?",
                vec![
                    integer(item.append_seq)?.into(),
                    item.item_id.clone().into(),
                ],
            ))
            .await?;
        ensure!(
            rows.len() <= 1,
            "timeline identity and append sequence name different records"
        );
        if let Some(row) = rows.into_iter().next() {
            let old = TimelineRecord::from_row(row)?.decode(thread_id)?;
            ensure!(old == *item, "immutable timeline record conflict");
            continue;
        }
        ensure!(allow_new, "committed effect is missing its timeline record");
        ensure!(
            head.checked_add(1) == Some(item.append_seq),
            "timeline append sequence is not contiguous"
        );
        let payload = encode_record(item)?;
        // The same codec must be lossless before an irreversible completion is accepted.
        ensure!(
            decode_record(&payload)? == *item,
            "timeline record codec did not preserve complete content"
        );
        db.execute_raw(statement(
            "INSERT INTO timeline_records
             (append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload)
             VALUES(?,?,?,?,?,?,?)",
            vec![
                integer(item.append_seq)?.into(),
                item.item_id.clone().into(),
                item.turn_id.clone().into(),
                item.source_effect_seq.map(integer).transpose()?.into(),
                item.sealed_at.into(),
                record_kind(item)?.into(),
                payload.into(),
            ],
        ))
        .await?;
        head = item.append_seq;
    }
    Ok(())
}

pub(super) async fn read_item(
    db: &impl ConnectionTrait,
    thread_id: &str,
    item_id: &str,
) -> Result<Option<ChatItem>> {
    db.query_one_raw(statement(
        "SELECT append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload
         FROM timeline_records WHERE record_id=?",
        vec![item_id.into()],
    ))
    .await?
    .map(|row| TimelineRecord::from_row(row)?.decode(thread_id))
    .transpose()
}

pub(super) fn validate_page(ceiling: u64, limit: usize) -> Result<()> {
    integer(ceiling)?;
    ensure!(
        (1..=pl_core::chat::MAX_PAGE_ITEMS).contains(&limit),
        ChatError::InvalidArgument("timeline page limit must be in 1..=100".into())
    );
    Ok(())
}

pub(super) async fn page(
    db: &impl ConnectionTrait,
    thread_id: &str,
    before: Option<&ChatCursor>,
    ceiling: u64,
    limit: usize,
) -> Result<ChatHistoryPage> {
    validate_page(ceiling, limit)?;
    if let Some(cursor) = before {
        ensure!(
            cursor.append_seq > 0 && !cursor.item_id.is_empty(),
            ChatError::InvalidArgument(
                "timeline cursor requires a positive sequence and identity".into()
            )
        );
        if let Some(row) = db
            .query_one_raw(statement(
                "SELECT record_id FROM timeline_records WHERE append_seq=?",
                vec![integer(cursor.append_seq)?.into()],
            ))
            .await?
        {
            ensure!(
                row.try_get::<String>("", "record_id")? == cursor.item_id,
                ChatError::InvalidArgument(
                    "timeline cursor sequence names a different identity".into()
                )
            );
        }
    }
    let (sql, values) = match before {
        Some(cursor) => (
            "SELECT append_seq,record_id FROM timeline_records
             WHERE append_seq<=? AND append_seq<? ORDER BY append_seq DESC LIMIT ?",
            vec![
                integer(ceiling)?.into(),
                integer(cursor.append_seq)?.into(),
                integer(limit + 1)?.into(),
            ],
        ),
        None => (
            "SELECT append_seq,record_id FROM timeline_records
             WHERE append_seq<=? ORDER BY append_seq DESC LIMIT ?",
            vec![integer(ceiling)?.into(), integer(limit + 1)?.into()],
        ),
    };
    read_page(db, thread_id, sql, values, limit, true).await
}

pub(super) async fn page_after(
    db: &impl ConnectionTrait,
    thread_id: &str,
    after: u64,
    ceiling: u64,
    limit: usize,
) -> Result<ChatHistoryPage> {
    validate_page(ceiling, limit)?;
    read_page(
        db,
        thread_id,
        "SELECT append_seq,record_id FROM timeline_records
         WHERE append_seq>? AND append_seq<=? ORDER BY append_seq ASC LIMIT ?",
        vec![
            integer(after)?.into(),
            integer(ceiling)?.into(),
            integer(limit + 1)?.into(),
        ],
        limit,
        false,
    )
    .await
}

async fn read_page(
    db: &impl ConnectionTrait,
    thread_id: &str,
    sql: &str,
    values: Vec<Value>,
    limit: usize,
    reverse: bool,
) -> Result<ChatHistoryPage> {
    // Probe only identities. The extra row never brings an unrequested full body into memory.
    let mut rows = db.query_all_raw(statement(sql, values)).await?;
    let has_more = rows.len() > limit;
    rows.truncate(limit);
    if reverse {
        rows.reverse();
    }
    let mut items = Vec::with_capacity(rows.len());
    for row in rows {
        let id: String = row.try_get("", "record_id")?;
        let seq: i64 = row.try_get("", "append_seq")?;
        let item = read_item(db, thread_id, &id)
            .await?
            .context("timeline page record disappeared within its read transaction")?;
        ensure!(
            integer(item.append_seq)? == seq,
            "timeline page record changed sequence"
        );
        items.push(item);
    }
    Ok(ChatHistoryPage { items, has_more })
}

pub(super) async fn migrate(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    // No IF NOT EXISTS: a pre-existing output table is a contradictory migration state.
    db.execute_unprepared(
        "CREATE TABLE timeline_records (
            append_seq INTEGER PRIMARY KEY CHECK (append_seq > 0),
            record_id TEXT NOT NULL UNIQUE CHECK (length(record_id) > 0),
            turn_id TEXT CHECK (turn_id IS NULL OR length(turn_id) > 0),
            source_effect_seq INTEGER CHECK (source_effect_seq IS NULL OR source_effect_seq > 0),
            sealed_at INTEGER,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload))
        )",
    )
    .await?;
    let mut ordinal = None;
    let mut append_seq = 0u64;
    loop {
        let (sql, values) = match ordinal {
            Some(ordinal) => (
                "SELECT ordinal,item_id,payload FROM history_items
                 WHERE ordinal>? ORDER BY ordinal ASC LIMIT 128",
                vec![Value::BigInt(Some(ordinal))],
            ),
            None => (
                "SELECT ordinal,item_id,payload FROM history_items ORDER BY ordinal ASC LIMIT 128",
                vec![],
            ),
        };
        let rows = db.query_all_raw(statement(sql, values)).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let source_ordinal: i64 = row.try_get("", "ordinal")?;
            ensure!(
                source_ordinal > 0,
                "legacy history ordinal must be positive"
            );
            ordinal = Some(source_ordinal);
            let id: String = row.try_get("", "item_id")?;
            let payload: String = row.try_get("", "payload")?;
            let item: ThreadItem = serde_json::from_str(&payload)?;
            ensure!(
                item.thread_id == thread_id
                    && item.id == id
                    && integer(item.ordinal)? == source_ordinal,
                "legacy history payload differs from its indexed identity"
            );
            // The one Runtime codec owns reliable completion selection and stable part order;
            // running/pending facts remain solely in history_items for execution recovery.
            for draft in legacy_completion_drafts(&item)? {
                append_seq = append_seq
                    .checked_add(1)
                    .filter(|seq| *seq <= i64::MAX as u64)
                    .context("migrated timeline append sequence overflow")?;
                let record = ChatItem::complete(ChatItemParts {
                    item_id: draft.item_id,
                    turn_id: draft.turn_id,
                    append_seq,
                    // v9 stored a last-write fence and mutable timestamps, not the first
                    // immutable completion publication. Neither proves completion provenance.
                    source_effect_seq: None,
                    sealed_at: None,
                    fields: draft.fields,
                    meta: draft.meta,
                });
                append_records(db, thread_id, std::slice::from_ref(&record), true).await?;
            }
        }
    }
    ensure!(
        latest_append_seq(db).await? == append_seq,
        "atomic timeline backfill count does not match its completed prefix"
    );
    Ok(())
}
