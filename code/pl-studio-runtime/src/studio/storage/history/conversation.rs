//! Current completed-history model. Payloads are opaque; only indexed headers drive reads.

use super::{integer, statement};
use anyhow::{Context, Result, ensure};
use pl_core::chat::{
    ChatBudget, ChatHistoryPage, ChatHistoryRequest, ChatItem, ChatItemHeader, ChatKey,
    ChatPageItem, PayloadData, PayloadMode, select_payload,
};
use sea_orm::{ConnectionTrait, QueryResult, Value};
use std::{collections::BTreeMap, sync::Arc};

pub(in crate::studio) mod completed;
#[path = "conversation/content.rs"]
pub(in crate::studio::storage::history) mod content;
#[path = "conversation/current.rs"]
pub(in crate::studio) mod current;
#[path = "conversation/migration.rs"]
pub(super) mod migration;
#[path = "conversation/range.rs"]
mod range;
pub(in super::super) mod sources;
#[cfg(test)]
#[path = "conversation/tests.rs"]
mod tests;
#[path = "conversation/timeline.rs"]
pub(in crate::studio) mod timeline;
pub(super) use content::{list_contents, read_contents, write_contents};
pub(super) use range::read_content;

pub(super) async fn validate_content(
    db: &impl ConnectionTrait,
    content: &pl_core::chat::ChatContent,
) -> Result<()> {
    content::validate_content(db, content).await?;
    Ok(())
}

fn header(row: &QueryResult) -> Result<ChatItemHeader> {
    Ok(ChatItemHeader {
        append_seq: u64::try_from(row.try_get::<i64>("", "seq")?)?,
        item_id: row.try_get("", "item_id")?,
        query_class: row.try_get("", "query_class")?,
        parent_id: row
            .try_get::<Option<String>>("", "parent_id")?
            .map(ChatKey::from_encoded)
            .transpose()?,
        byte_length: u64::try_from(row.try_get::<i64>("", "byte_length")?)?,
        metadata: Arc::from(row.try_get::<Vec<u8>>("", "metadata")?),
    })
}

pub(super) async fn latest_append_seq(db: &impl ConnectionTrait) -> Result<u64> {
    let row = db
        .query_one_raw(statement(
            "SELECT seq FROM conversation_items ORDER BY seq DESC LIMIT 1",
            vec![],
        ))
        .await?;
    row.map(|row| Ok(u64::try_from(row.try_get::<i64>("", "seq")?)?))
        .unwrap_or(Ok(0))
}

/// This complete read is for publication idempotency, not normal pages or range reads.
pub(super) async fn read_item(db: &impl ConnectionTrait, id: &str) -> Result<Option<ChatItem>> {
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,payload
         FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        ))
        .await?
    else {
        return Ok(None);
    };
    Ok(Some(ChatItem {
        header: header(&row)?,
        payload: Arc::from(row.try_get::<Vec<u8>>("", "payload")?),
        contents: Arc::new(read_contents(db, id).await?),
    }))
}

/// Caller owns the effect transaction. Frozen Arcs are borrowed, never cloned as whole records.
#[cfg(test)]
pub(super) async fn append_records<'a>(
    db: &impl ConnectionTrait,
    records: impl IntoIterator<Item = &'a ChatItem>,
    allow_new: bool,
) -> Result<()> {
    let mut head = latest_append_seq(db).await?;
    append_records_at_head(db, records, allow_new, &mut head).await
}

/// The owning transaction reads its append baseline once and advances it locally.
/// New suffix rows use SQLite's identity constraints; only actual replay reads old bytes.
pub(super) async fn append_records_at_head<'a>(
    db: &impl ConnectionTrait,
    records: impl IntoIterator<Item = &'a ChatItem>,
    allow_new: bool,
    head: &mut u64,
) -> Result<()> {
    for item in records {
        let h = &item.header;
        ensure!(
            h.append_seq > 0 && !h.item_id.is_empty() && !h.query_class.is_empty(),
            "completion requires positive sequence, identity and query class"
        );
        ensure!(
            h.byte_length == item.payload.len() as u64,
            "completion payload length differs"
        );
        let rows = if h.append_seq <= *head {
            db.query_all_raw(statement(
                "SELECT seq,item_id FROM conversation_items WHERE seq=? OR item_id=?",
                vec![integer(h.append_seq)?.into(), h.item_id.clone().into()],
            ))
            .await?
        } else {
            Vec::new()
        };
        ensure!(
            rows.len() <= 1,
            "completion identity and sequence name different rows"
        );
        if let Some(row) = rows.first() {
            ensure!(
                row.try_get::<i64>("", "seq")? == integer(h.append_seq)?
                    && row.try_get::<String>("", "item_id")? == h.item_id,
                "immutable completion identity conflict"
            );
            let old = db.query_one_raw(statement(
                "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,payload
                 FROM conversation_items WHERE item_id=?", vec![h.item_id.clone().into()],
            )).await?.context("committed completion disappeared")?;
            ensure!(
                header(&old)? == *h
                    && old.try_get::<Vec<u8>>("", "payload")?.as_slice() == item.payload.as_ref(),
                "immutable completion payload conflict"
            );
            let owner = crate::studio::conversation_identity::content_owner_key(
                &pl_protocol::ContentOwner::Item {
                    item_id: h.item_id.clone(),
                },
            )?;
            let manifest = db
                .query_all_raw(statement(
                    "SELECT content_key FROM conversation_contents WHERE owner_key=?",
                    vec![owner.as_str().into()],
                ))
                .await?;
            ensure!(
                manifest.len() == item.contents.len(),
                "immutable completion manifest changed"
            );
            for content in item.contents.values() {
                let stored = content::validate_content(db, content)
                    .await?
                    .context("committed completion content is missing")?;
                ensure!(stored.sealed, "committed completion has unsealed content");
            }
            continue;
        }
        ensure!(
            allow_new,
            "retried effect is missing a committed completion"
        );
        ensure!(
            head.checked_add(1) == Some(h.append_seq),
            "completion sequence is not contiguous"
        );
        db.execute_raw(statement(
            "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(?,?,?,?,?,?)",
            vec![integer(h.append_seq)?.into(), h.item_id.clone().into(), h.query_class.clone().into(),
                h.parent_id.as_ref().map(|key| key.as_str().to_owned()).into(),
                item.payload.to_vec().into(),h.metadata.to_vec().into()],
        )).await?;
        write_contents(db, &h.item_id, &item.contents).await?;
        *head = h.append_seq;
    }
    Ok(())
}

/// First fetch only indexed headers and BLOB lengths. Deferred records never fetch their payload.
pub(super) async fn page(
    db: &impl ConnectionTrait,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
    ascending: bool,
) -> Result<ChatHistoryPage> {
    request.demand.validate()?;
    integer(request.ceiling)?;
    integer(request.after)?;
    let mut sql = String::from(
        "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length
         FROM conversation_items WHERE seq<=? AND seq>?",
    );
    let mut values = vec![
        integer(request.ceiling)?.into(),
        integer(request.after)?.into(),
    ];
    if let Some(before) = request.before {
        sql.push_str(" AND seq<?");
        values.push(integer(before)?.into());
    }
    if let Some(query) = &request.query {
        ensure!(
            !query.query_class.is_empty(),
            "empty completion query class"
        );
        sql.push_str(" AND query_class=?");
        values.push(query.query_class.clone().into());
        if let Some(parent) = &query.parent_id {
            sql.push_str(" AND parent_id=?");
            values.push(parent.as_str().into());
        }
    }
    sql.push_str(if ascending {
        " ORDER BY seq ASC LIMIT ?"
    } else {
        " ORDER BY seq DESC LIMIT ?"
    });
    values.push(integer(request.demand.max_items)?.into());
    let rows = db.query_all_raw(statement(&sql, values)).await?;
    tracing::debug!(
        target: "conversation_work",
        sql_candidates = rows.len(),
        "SQL header selection"
    );
    let natural_end = rows.len() < request.demand.max_items;
    let mut selected = Vec::with_capacity(rows.len());
    let mut bytes = request.demand.max_bytes;
    let mut exhausted = natural_end;
    let mut header_decodes = 0;
    for row in &rows {
        header_decodes += 1;
        let h = header(row)?;
        let Some(mode) = select_payload(&h, bytes, budget) else {
            exhausted = false;
            break;
        };
        bytes -= budget.item_bytes(&h, mode);
        selected.push((h, mode));
    }

    // Bounded batches avoid SQLite variable limits even for the largest allowed demand.
    let inline: Vec<_> = selected
        .iter()
        .filter(|(_, mode)| *mode == PayloadMode::Inline)
        .map(|(h, _)| h.append_seq)
        .collect();
    let mut payloads = BTreeMap::new();
    for batch in inline.chunks(256) {
        let placeholders = vec!["?"; batch.len()].join(",");
        let rows = db
            .query_all_raw(statement(
                &format!(
                    "SELECT seq,payload FROM conversation_items WHERE seq IN ({placeholders})"
                ),
                batch
                    .iter()
                    .map(|seq| integer(*seq).map(Value::from))
                    .collect::<Result<_>>()?,
            ))
            .await?;
        for row in rows {
            payloads.insert(
                u64::try_from(row.try_get::<i64>("", "seq")?)?,
                Arc::<[u8]>::from(row.try_get::<Vec<u8>>("", "payload")?),
            );
        }
    }
    let mut items = Vec::with_capacity(selected.len());
    for (h, mode) in selected {
        let payload = match mode {
            PayloadMode::Inline => {
                let bytes = payloads
                    .remove(&h.append_seq)
                    .context("selected completion disappeared")?;
                ensure!(
                    bytes.len() as u64 == h.byte_length,
                    "selected completion changed length"
                );
                PayloadData::Inline(bytes)
            }
            PayloadMode::Deferred => PayloadData::Deferred {
                item_id: h.item_id.clone(),
                byte_length: h.byte_length,
            },
        };
        items.push(ChatPageItem { header: h, payload });
    }
    if !ascending {
        items.reverse();
    }
    tracing::debug!(
        target: "conversation_work",
        sql_returned = items.len(),
        payload_bytes = items.iter().map(|item| match &item.payload {
            PayloadData::Inline(bytes) => bytes.len(),
            PayloadData::Deferred { .. } => 0,
        }).sum::<usize>(),
        header_decodes,
        "SQL page completed"
    );
    Ok(ChatHistoryPage { items, exhausted })
}
