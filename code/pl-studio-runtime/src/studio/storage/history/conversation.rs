//! Current completed-history model. Payloads are opaque; only indexed headers drive reads.

use super::{integer, statement};
use anyhow::{Context, Result, ensure};
use pl_core::chat::{
    ChatBudget, ChatHistoryPage, ChatHistoryRequest, ChatItem, ChatItemHeader, ChatKey,
    ChatPageItem, ChatPublicationSeed, ChatReadHint, ChatRunPosition, ChatRunSeed, ChatSelection,
    PayloadData, PayloadMode, select_payload,
};
use sea_orm::{ConnectionTrait, QueryResult, Value};
use std::{collections::BTreeMap, sync::Arc};

pub(in crate::studio) mod completed;
#[path = "conversation/content.rs"]
pub(in crate::studio::storage::history) mod content;
#[path = "conversation/current.rs"]
pub(in crate::studio) mod current;
pub(in crate::studio) mod display;
mod facts;
#[path = "conversation/migration.rs"]
pub(super) mod migration;
#[path = "conversation/range.rs"]
mod range;
mod run_read;
#[cfg(test)]
mod run_read_tests;
pub(in super::super) mod sources;
#[cfg(test)]
#[path = "conversation/tests.rs"]
pub(in crate::studio::storage::history) mod tests;
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
    let metadata: Arc<[u8]> = Arc::from(row.try_get::<Vec<u8>>("", "metadata")?);
    let query_class: String = row.try_get("", "query_class")?;
    let atom: pl_protocol::ChatAtom = serde_json::from_slice(&metadata)
        .context("invalid completed Native metadata; original history preserved")?;
    let read_hint = crate::studio::runtime::chat_item::native_read_hint_v1(&query_class, &atom);
    let start: Option<i64> = row.try_get("", "display_run_start")?;
    let ordinal: Option<i64> = row.try_get("", "display_run_ordinal")?;
    let run = match (start, ordinal) {
        (None, None) => None,
        (Some(start), Some(ordinal)) => Some(ChatRunPosition {
            start_seq: u64::try_from(start)?,
            ordinal: u64::try_from(ordinal)?,
        }),
        _ => anyhow::bail!("incomplete immutable run position; original history preserved"),
    };
    let header = ChatItemHeader {
        append_seq: u64::try_from(row.try_get::<i64>("", "seq")?)?,
        item_id: row.try_get("", "item_id")?,
        query_class,
        parent_id: row
            .try_get::<Option<String>>("", "parent_id")?
            .map(ChatKey::from_encoded)
            .transpose()?,
        byte_length: u64::try_from(row.try_get::<i64>("", "byte_length")?)?,
        metadata,
        read_hint,
        run,
    };
    header.validate_run()?;
    Ok(header)
}

/// Check only a selected header's indexed reference. Applied corruption never causes a rebuild
/// or an all-history scan, and the run's original payload remains untouched.
async fn validate_run_reference(db: &impl ConnectionTrait, h: &ChatItemHeader) -> Result<()> {
    let Some(run) = h.run.filter(|run| run.start_seq != h.append_seq) else {
        return Ok(());
    };
    let row = db
        .query_one_raw(statement(
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,
                display_run_start,display_run_ordinal FROM conversation_items WHERE seq=?",
            vec![integer(run.start_seq)?.into()],
        ))
        .await?
        .context("immutable run start is missing; original history preserved")?;
    let start = header(&row)?;
    ensure!(
        start.run
            == Some(ChatRunPosition {
                start_seq: run.start_seq,
                ordinal: 1
            })
            && start.read_hint == h.read_hint,
        "immutable run start differs; original history preserved"
    );
    Ok(())
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

pub(super) async fn publication_seed(db: &impl ConnectionTrait) -> Result<ChatPublicationSeed> {
    let head_seq = latest_append_seq(db).await?;
    let last = db
        .query_one_raw(statement(
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,
                display_run_start,display_run_ordinal
         FROM conversation_items INDEXED BY conversation_items_visible_seq
         WHERE display_run_start IS NOT NULL ORDER BY seq DESC LIMIT 1",
            vec![],
        ))
        .await?
        .map(|row| header(&row))
        .transpose()?;
    let last_visible = if let Some(h) = last {
        validate_run_reference(db, &h).await?;
        Some(ChatRunSeed {
            seq: h.append_seq,
            hint: h.read_hint,
            position: h.run.context("visible completion has no run")?,
        })
    } else {
        None
    };
    let seed = ChatPublicationSeed {
        head_seq,
        last_visible,
    };
    seed.validate()?;
    Ok(seed)
}

/// This complete read is for publication idempotency, not normal pages or range reads.
pub(super) async fn read_item(db: &impl ConnectionTrait, id: &str) -> Result<Option<ChatItem>> {
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,payload,
                    display_run_start,display_run_ordinal
         FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        ))
        .await?
    else {
        return Ok(None);
    };
    let header = header(&row)?;
    validate_run_reference(db, &header).await?;
    Ok(Some(ChatItem {
        header,
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
    let mut head = publication_seed(db).await?;
    append_records_at_head(db, records, allow_new, &mut head).await
}

/// The owning transaction reads its append baseline once and advances it locally.
/// New suffix rows use SQLite's identity constraints; only actual replay reads old bytes.
pub(super) async fn append_records_at_head<'a>(
    db: &impl ConnectionTrait,
    records: impl IntoIterator<Item = &'a ChatItem>,
    allow_new: bool,
    head: &mut ChatPublicationSeed,
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
        h.validate_run()?;
        let atom: pl_protocol::ChatAtom = serde_json::from_slice(&h.metadata)?;
        ensure!(
            crate::studio::runtime::chat_item::native_read_hint_v1(&h.query_class, &atom)
                == h.read_hint,
            "completion hint differs from Native metadata"
        );
        let rows = if h.append_seq <= head.head_seq {
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
                "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,payload,
                        display_run_start,display_run_ordinal
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
        let mut next = head.clone();
        let (seq, run) = next.advance(&h.read_hint)?;
        ensure!(
            seq == h.append_seq && run == h.run,
            "completion sequence/run is not contiguous"
        );
        db.execute_raw(statement(
            "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata,display_run_start,display_run_ordinal) VALUES(?,?,?,?,?,?,?,?)",
            vec![integer(h.append_seq)?.into(), h.item_id.clone().into(), h.query_class.clone().into(),
                h.parent_id.as_ref().map(|key| key.as_str().to_owned()).into(),
                item.payload.to_vec().into(),h.metadata.to_vec().into(),
                h.run.map(|run| integer(run.start_seq)).transpose()?.into(),
                h.run.map(|run| integer(run.ordinal)).transpose()?.into()],
        )).await?;
        write_contents(db, &h.item_id, &item.contents).await?;
        *head = next;
    }
    Ok(())
}

/// Explicit detail demand: one indexed lightweight header, then only its budgeted payload.
/// Unlike the publication idempotency port this never reads a content manifest or body.
pub(super) async fn read_selected_item(
    db: &impl ConnectionTrait,
    request: &pl_core::chat::ChatHistoryItemRequest,
    budget: &dyn ChatBudget,
) -> Result<Option<ChatPageItem>> {
    request.demand.validate()?;
    ensure!(
        !request.item_id.is_empty() && request.demand.max_items == 1,
        pl_core::chat::ChatError::InvalidDemand("invalid item detail demand".into())
    );
    let rows = db
        .query_all_raw(statement(
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,
                display_run_start,display_run_ordinal
         FROM conversation_items WHERE item_id=? AND seq<=?",
            vec![
                request.item_id.clone().into(),
                integer(request.ceiling)?.into(),
            ],
        ))
        .await?;
    if rows.is_empty() {
        return Ok(None);
    }
    let page_request = ChatHistoryRequest {
        query: None,
        after: 0,
        before: None,
        ceiling: request.ceiling,
        demand: request.demand,
    };
    let mut page = materialize(db, &page_request, budget, true, &rows, true, false).await?;
    ensure!(
        !page.items.is_empty(),
        pl_core::chat::ChatError::InvalidDemand("item detail cannot fit demand".into())
    );
    Ok(page.items.pop())
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
    if request
        .query
        .as_ref()
        .is_some_and(|query| query.selection != ChatSelection::Records)
    {
        return run_read::page(db, request, budget, ascending).await;
    }
    let mut sql = String::from(
        "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,
                display_run_start,display_run_ordinal
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
    materialize(db, request, budget, ascending, &rows, natural_end, false).await
}

async fn materialize(
    db: &impl ConnectionTrait,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
    ascending: bool,
    rows: &[QueryResult],
    natural_end: bool,
    run_heads: bool,
) -> Result<ChatHistoryPage> {
    let mut selected = Vec::with_capacity(rows.len());
    let mut bytes = request.demand.max_bytes;
    let mut exhausted = natural_end;
    let mut header_decodes = 0;
    for row in rows {
        header_decodes += 1;
        let h = header(row)?;
        validate_run_reference(db, &h).await?;
        let mode = if run_heads && matches!(h.read_hint, ChatReadHint::Adjacent { .. }) {
            (budget.item_bytes(&h, PayloadMode::Deferred) <= bytes).then_some(PayloadMode::Deferred)
        } else {
            select_payload(&h, bytes, budget)
        };
        let Some(mode) = mode else {
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
