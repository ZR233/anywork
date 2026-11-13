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

pub(in super::super) mod sources;

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

#[cfg(test)]
mod run_read_tests {
    use super::*;
    use pl_core::chat::{ChatDraft, ChatQuery, ReadDemand};
    use pl_protocol::{ChatAtom, ChatAtomKind, ChatSourceId};
    use sea_orm::TransactionTrait;

    fn atom(id: &str, kind: ChatAtomKind, source: &str) -> ChatAtom {
        let mut atom: ChatAtom = serde_json::from_slice(&super::tests::metadata(id)).unwrap();
        atom.kind = kind;
        atom.source = ChatSourceId::ForegroundTurn {
            turn_id: source.into(),
        };
        atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
        atom
    }

    fn record(seq: u64, atom: ChatAtom, run: Option<(u64, u64)>) -> ChatItem {
        let mut draft = ChatDraft::new(
            &atom.id,
            "conversation",
            Arc::from(&b"{\"original\":true}"[..]),
        );
        draft.parent_id = Some(ChatKey::new("turn", "real-parent").unwrap());
        draft.read_hint =
            crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &atom);
        draft.metadata = serde_json::to_vec(&atom).unwrap().into();
        ChatItem::complete(
            draft,
            seq,
            run.map(|(start_seq, ordinal)| ChatRunPosition { start_seq, ordinal }),
        )
    }

    fn request(
        selection: ChatSelection,
        ceiling: u64,
        before: Option<u64>,
        max_items: usize,
    ) -> ChatHistoryRequest {
        let mut query = ChatQuery::new("conversation", None);
        query.selection = selection;
        ChatHistoryRequest {
            query: Some(query),
            after: 0,
            before,
            ceiling,
            demand: ReadDemand::new(max_items, 256 * 1024),
        }
    }

    #[tokio::test]
    async fn heads_skip_hidden_and_whole_runs_at_fixed_cut_and_children_keep_real_parent()
    -> Result<()> {
        let (_dir, db) = super::tests::fixture().await?;
        let records = [
            record(1, atom("one", ChatAtomKind::ToolCall, "F"), Some((1, 1))),
            record(2, atom("hidden", ChatAtomKind::Inference, "F"), None),
            record(3, atom("three", ChatAtomKind::Reasoning, "F"), Some((1, 2))),
            record(4, atom("text", ChatAtomKind::Text, "F"), Some((4, 1))),
            record(5, atom("five", ChatAtomKind::ToolCall, "F"), Some((5, 1))),
            record(6, atom("six", ChatAtomKind::Skill, "F"), Some((5, 2))),
        ];
        append_records(&db, records.iter(), true).await?;
        let heads = page(
            &db,
            &request(ChatSelection::RunHeads, 5, None, 2),
            &super::tests::Budget,
            false,
        )
        .await?;
        assert_eq!(
            heads
                .items
                .iter()
                .map(|i| i.header.append_seq)
                .collect::<Vec<_>>(),
            [4, 5]
        );
        assert!(matches!(
            heads.items[1].payload,
            PayloadData::Deferred { .. }
        ));
        assert!(matches!(heads.items[0].payload, PayloadData::Inline(_)));
        let older = page(
            &db,
            &request(ChatSelection::RunHeads, 5, Some(4), 2),
            &super::tests::Budget,
            false,
        )
        .await?;
        assert_eq!(older.items.len(), 1);
        assert_eq!(older.items[0].header.append_seq, 3);
        assert_eq!(
            older.items[0].header.run,
            Some(ChatRunPosition {
                start_seq: 1,
                ordinal: 2
            })
        );
        let members = page(
            &db,
            &request(ChatSelection::Run { start_seq: 1 }, 6, None, 8),
            &super::tests::Budget,
            false,
        )
        .await?;
        assert_eq!(
            members
                .items
                .iter()
                .map(|i| i.header.append_seq)
                .collect::<Vec<_>>(),
            [1, 3]
        );
        assert!(
            members
                .items
                .iter()
                .all(|i| matches!(i.payload, PayloadData::Inline(_)))
        );
        let mut children = request(ChatSelection::Records, 6, None, 8);
        children.query.as_mut().unwrap().parent_id = Some(ChatKey::new("turn", "real-parent")?);
        let children = page(&db, &children, &super::tests::Budget, false).await?;
        assert_eq!(children.items.len(), 6);
        assert_eq!(children.items[1].header.read_hint, ChatReadHint::Hidden);
        let seed = publication_seed(&db).await?;
        assert_eq!(seed.head_seq, 6);
        assert_eq!(
            seed.last_visible.unwrap().position,
            ChatRunPosition {
                start_seq: 5,
                ordinal: 2
            }
        );
        Ok(())
    }

    #[tokio::test]
    async fn lost_ack_replay_compares_run_hint_and_bytes_and_transaction_failure_rolls_back()
    -> Result<()> {
        let (_dir, db) = super::tests::fixture().await?;
        let one = record(1, atom("one", ChatAtomKind::ToolCall, "F"), Some((1, 1)));
        append_records(&db, [&one], true).await?;
        append_records(&db, [&one], false).await?;
        let mut conflict = one.clone();
        conflict.header.run.as_mut().unwrap().ordinal = 2;
        assert!(append_records(&db, [&conflict], false).await.is_err());
        conflict = one.clone();
        conflict.payload = Arc::from(&b"{\"changed!\":true}"[..]);
        assert!(append_records(&db, [&conflict], false).await.is_err());
        let two = record(2, atom("two", ChatAtomKind::Skill, "F"), Some((1, 2)));
        let three = record(3, atom("three", ChatAtomKind::Text, "F"), Some((3, 1)));
        db.execute_unprepared(
            "CREATE TRIGGER fail_three BEFORE INSERT ON conversation_items
        WHEN NEW.seq=3 BEGIN SELECT RAISE(ABORT,'injected middle failure'); END;",
        )
        .await?;
        let tx = db.begin().await?;
        assert!(append_records(&tx, [&two, &three], true).await.is_err());
        tx.rollback().await?;
        assert_eq!(latest_append_seq(&db).await?, 1);
        assert!(read_item(&db, "two").await?.is_none());
        assert_eq!(read_item(&db, "one").await?.unwrap(), one);
        Ok(())
    }

    #[tokio::test]
    async fn hundred_thousand_members_use_index_seeks_and_never_inline_work_payload() -> Result<()>
    {
        let init_started = std::time::Instant::now();
        let (_dir, db) = super::tests::fixture().await?;
        let init_us = init_started.elapsed().as_micros();
        let seed_started = std::time::Instant::now();
        // Nineteen distinct single-member WORK runs, plus one long work run at seq=20.
        // All are Adjacent/ForegroundWork, including ordinal=1: none is a Native Single which
        // would legitimately be allowed to inline its own small payload.
        let seeds = (1..=20)
            .map(|seq| {
                record(
                    seq,
                    atom(
                        &format!("work-{seq}"),
                        ChatAtomKind::ToolCall,
                        &format!("foreground-{seq}"),
                    ),
                    Some((seq, 1)),
                )
            })
            .collect::<Vec<_>>();
        append_records(&db, seeds.iter(), true).await?;
        let seed_us = seed_started.elapsed().as_micros();
        let mut previous_size = 1u64;
        let mut baseline = None;
        for size in [1u64, 100, 10_000, 100_000] {
            let setup_started = std::time::Instant::now();
            let inserted = if size == 1 { 20 } else { size - previous_size };
            if size > previous_size {
                db.execute_raw(statement(
                "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
                 INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata,display_run_start,display_run_ordinal)
                 SELECT i,'work-'||i,query_class,parent_id,payload,
                        CAST(json_set(metadata,'$.id','work-'||i,'$.completionItemId','work-'||i) AS BLOB),
                        20,i-19
                 FROM n CROSS JOIN conversation_items WHERE seq=20",
                vec![integer(previous_size + 20)?.into(), integer(size + 19)?.into()],
            )).await?;
            }
            previous_size = size;
            let total = size + 19;
            let count = db
                .query_one_raw(statement(
                    "SELECT COUNT(*) AS records FROM conversation_items",
                    vec![],
                ))
                .await?
                .context("scale fixture record count")?
                .try_get::<i64>("", "records")?;
            assert_eq!(u64::try_from(count)?, total);
            let setup_us =
                setup_started.elapsed().as_micros() + if size == 1 { seed_us } else { 0 };
            let request = request(ChatSelection::RunHeads, total, None, 20);
            let sampler = sqlite_work::Sampler::install(&db).await?;
            let outcome = page(&db, &request, &super::tests::Budget, false).await;
            // Always join/unregister the native callbacks, including a failed production query,
            // before propagating the original query result or checking any assertions.
            let work = sampler.finish(&db).await?;
            let heads = outcome?;
            assert_eq!(heads.items.len(), 20);
            assert_eq!(work.candidates, 20);
            assert!(
                heads
                    .items
                    .iter()
                    .all(|item| matches!(item.header.read_hint, ChatReadHint::Adjacent { .. }))
            );
            assert_eq!(
                heads.items[19].header.run,
                Some(ChatRunPosition {
                    start_seq: 20,
                    ordinal: size
                })
            );
            let payload_bytes: usize = heads
                .items
                .iter()
                .map(|item| match &item.payload {
                    PayloadData::Inline(bytes) => bytes.len(),
                    PayloadData::Deferred { .. } => 0,
                })
                .sum();
            assert_eq!(payload_bytes, 0);
            assert_eq!(
                work.denied_reads, 0,
                "Main tried to read a protected body/media column"
            );
            assert_eq!(work.reference_rows, u64::from(size > 1));
            assert_eq!(work.statements, 1 + u64::from(size > 1));
            if let Some((vm, scan)) = baseline {
                assert!(work.vm_steps <= vm + 256, "{work:?}");
                assert!(work.head_fullscan_steps <= scan + 20, "{work:?}");
            } else {
                baseline = Some((work.vm_steps, work.head_fullscan_steps));
            }
            eprintln!(
                "I15 {}",
                serde_json::json!({
                    "members":size, "total_records":total, "candidates":work.candidates,
                    "returned":heads.items.len(), "inline_payload_bytes":payload_bytes,
                    "statements":work.statements, "reference_rows":work.reference_rows,
                    "vm_steps":work.vm_steps, "run_heads_vm_steps":work.head_vm_steps,
                    "fullscan_steps":work.fullscan_steps, "run_heads_fullscan_steps":work.head_fullscan_steps,
                    "payload_length_column_authorizations":work.payload_column_authorizations,
                    "denied_main_body_reads":work.denied_reads,
                    "init_us":init_us, "setup_inserted_rows":inserted, "setup_us":setup_us,
                })
            );
        }
        let plan = db
            .query_all_raw(statement(
                &format!("EXPLAIN QUERY PLAN {}", run_read::RUN_HEADS_SQL),
                vec![100_019i64.into(), 20i64.into(), 0i64.into()],
            ))
            .await?;
        let plan = plan
            .iter()
            .map(|row| row.try_get::<String>("", "detail"))
            .collect::<std::result::Result<Vec<_>, _>>()?
            .join("\n");
        assert!(
            plan.contains("conversation_items_visible_seq") && plan.contains("seq<?"),
            "{plan}"
        );
        assert!(!plan.contains("SCAN conversation_items"), "{plan}");
        assert!(!plan.contains("(rowid>?)"), "{plan}");
        assert!(!plan.contains("GROUP BY"), "{plan}");
        eprintln!("RunHeads EXPLAIN QUERY PLAN:\n{plan}");

        // A production admission error still takes the explicit locked cleanup path.
        let sampler = sqlite_work::Sampler::install(&db).await?;
        let lifetime = sampler.lifetime();
        let mut rejected = request(ChatSelection::RunHeads, 100_019, None, 20);
        rejected.query.as_mut().unwrap().parent_id = Some(ChatKey::new("turn", "invalid-on-main")?);
        let outcome = page(&db, &rejected, &super::tests::Budget, false).await;
        let work = sampler.finish(&db).await?;
        assert!(outcome.is_err());
        assert_eq!(work.statements, 0);
        assert!(!lifetime.is_alive());

        // Cancel a suspended sampling scope after native registration. Its Rust observer drops,
        // but the driver's ownership keeps the context live until every hook/connection is closed.
        let sampler = sqlite_work::Sampler::install(&db).await?;
        let lifetime = sampler.lifetime();
        let mut cancelled = Box::pin(async move {
            std::future::pending::<()>().await;
            drop(sampler);
        });
        std::future::poll_fn(|cx| {
            assert!(std::future::Future::poll(cancelled.as_mut(), cx).is_pending());
            std::task::Poll::Ready(())
        })
        .await;
        drop(cancelled);
        assert!(lifetime.is_alive());
        db.close().await?;
        assert!(!lifetime.is_alive());
        eprintln!(
            "I15 sampler lifecycle: normal/error unregistered; cancelled context retained until connection close; released=true"
        );
        Ok(())
    }

    #[tokio::test]
    async fn explicit_item_detail_obeys_cut_and_budget_without_reading_contents() -> Result<()> {
        let (_dir, db) = super::tests::fixture().await?;
        let one = record(1, atom("one", ChatAtomKind::ToolCall, "F"), Some((1, 1)));
        append_records(&db, [&one], true).await?;
        // The publication-only item port would fail here: a detail read must not load a manifest.
        db.execute_unprepared(
            "DROP TABLE conversation_content_chunks; DROP TABLE conversation_contents",
        )
        .await?;
        let mut detail = pl_core::chat::ChatHistoryItemRequest {
            item_id: "one".into(),
            ceiling: 0,
            demand: ReadDemand::new(1, 4096),
        };
        assert!(
            read_selected_item(&db, &detail, &super::tests::Budget)
                .await?
                .is_none()
        );
        detail.ceiling = 1;
        let full = read_selected_item(&db, &detail, &super::tests::Budget)
            .await?
            .unwrap();
        assert_eq!(full.header, one.header);
        assert!(matches!(full.payload, PayloadData::Inline(bytes) if bytes == one.payload));
        detail.demand.max_bytes = 64;
        assert!(matches!(
            read_selected_item(&db, &detail, &super::tests::Budget)
                .await?
                .unwrap()
                .payload,
            PayloadData::Deferred { .. }
        ));
        detail.demand.max_bytes = 63;
        assert!(
            read_selected_item(&db, &detail, &super::tests::Budget)
                .await
                .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn execution_recovery_pages_real_unfinished_starts_including_independent_compaction()
    -> Result<()> {
        use pl_protocol::{
            ChatActiveStatus, ChatAtomLifecycle, ChatDeliveryKind, ChatTerminalOutcome,
        };
        let dir = tempfile::tempdir()?;
        let store =
            super::super::HistoryStore::open(&dir.path().join("history.sqlite"), "recovery-starts")
                .await?;
        store.prepare_write().await?;
        let mut a = atom("a", ChatAtomKind::ToolCall, "F");
        a.completion_item_id = None;
        a.lifecycle = ChatAtomLifecycle::Active {
            started: None,
            status: ChatActiveStatus::Running,
        };
        let mut b = a.clone();
        b.id = "b".into();
        b.kind = ChatAtomKind::Compaction;
        b.delivery = ChatDeliveryKind::Independent;
        b.source = ChatSourceId::Operation {
            operation_id: "compression".into(),
        };
        let mut c = a.clone();
        c.id = "c".into();
        let connection = store.writer().await?;
        facts::apply(&connection.db, &[a.clone(), b.clone(), c.clone()], 1).await?;
        a.lifecycle = ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: ChatTerminalOutcome::Completed,
        };
        facts::apply(&connection.db, &[a], 2).await?;
        let first = store.recovery_atom_starts(None, 1).await?;
        assert_eq!(first, [b.clone()]);
        assert_eq!(store.recovery_atom_starts(Some(&b.id), 1).await?, [c]);
        assert!(store.recovery_atom_starts(Some("c"), 1).await?.is_empty());
        assert!(
            store
                .cold_current_state()
                .await?
                .unwrap()
                .projection()
                .atoms
                .is_empty()
        );
        assert!(store.recovery_atom_starts(None, 129).await.is_err());
        store.close_for_deletion().await?;
        Ok(())
    }

    pub(in crate::studio::storage::history::conversation) mod sqlite_work {
        //! Test-only observations of the SQLx connection used by the real production page.
        //! No alternate SQL implementation or database is involved.
        use super::*;
        use std::{
            ffi::{CStr, c_char, c_int, c_uint, c_void},
            sync::{
                Weak,
                atomic::{AtomicBool, AtomicU64, Ordering::Relaxed},
            },
        };

        #[derive(Clone, Copy, Default)]
        enum Scope {
            #[default]
            CompletionHeads,
            DisplayHeads,
            DisplayMembers,
        }

        #[derive(Default)]
        struct State {
            scope: Scope,
            candidates: AtomicU64,
            member_rows: AtomicU64,
            reference_rows: AtomicU64,
            statements: AtomicU64,
            vm_steps: AtomicU64,
            head_vm_steps: AtomicU64,
            fullscan_steps: AtomicU64,
            head_fullscan_steps: AtomicU64,
            payload_column_authorizations: AtomicU64,
            denied_reads: AtomicU64,
            unexpected_statements: AtomicU64,
            invalid_counter: AtomicBool,
            budget_exceeded: AtomicBool,
            trace_removed: AtomicBool,
            authorizer_removed: AtomicBool,
        }

        #[derive(Debug)]
        pub(in crate::studio::storage::history::conversation) struct Work {
            pub candidates: u64,
            pub member_rows: u64,
            pub reference_rows: u64,
            pub statements: u64,
            pub vm_steps: u64,
            pub head_vm_steps: u64,
            pub fullscan_steps: u64,
            pub head_fullscan_steps: u64,
            pub payload_column_authorizations: u64,
            pub denied_reads: u64,
        }

        pub(in crate::studio::storage::history::conversation) struct Lifetime(Weak<State>);
        impl Lifetime {
            pub fn is_alive(&self) -> bool {
                self.0.strong_count() != 0
            }
        }

        pub(in crate::studio::storage::history::conversation) struct Sampler {
            state: Arc<State>,
        }

        // SQLx 0.9 owns this value in its progress-handler closure. In ConnectionState::drop it first
        // clears statements, then removes progress handlers, and only afterwards drops ConnectionHandle.
        // Thus this destructor runs either under LockedSqliteHandle or under the worker's exclusive
        // ConnectionState ownership, with no SQLite call/callback in flight and a still-live handle.
        // It removes BOTH native callbacks before releasing their Arc context. If the test future is
        // cancelled, dropping Sampler cannot free that context: the driver still owns this registration.
        struct Registration {
            handle_address: usize,
            state: Arc<State>,
        }

        impl Registration {
            fn interrupt_at_budget(&self) -> bool {
                // A PROFILE VM_STEP value is defined only up to i32::MAX. Interrupt an unexpectedly
                // expensive statement around one million operations, well below that counter limit.
                // This callback is also the driver-owned lifetime anchor; it is not the work sampler.
                self.state.budget_exceeded.store(true, Relaxed);
                false
            }
        }

        impl Drop for Registration {
            fn drop(&mut self) {
                // SAFETY: handle_address is the exposed address obtained from LockedSqliteHandle during
                // installation. The SQLx-owned closure can only be dropped while the same native handle
                // is exclusive and still open (see the ownership/drop order above). No Rust reference is
                // made from this address. Unregistering cannot overlap a native callback, and the context
                // Arc below remains alive until after both calls return. Neither operation invokes SQL.
                let (trace, authorizer) = unsafe {
                    let handle = self.handle_address as *mut libsqlite3_sys::sqlite3;
                    (
                        libsqlite3_sys::sqlite3_trace_v2(handle, 0, None, std::ptr::null_mut()),
                        libsqlite3_sys::sqlite3_set_authorizer(handle, None, std::ptr::null_mut()),
                    )
                };
                self.state
                    .trace_removed
                    .store(trace == libsqlite3_sys::SQLITE_OK, Relaxed);
                self.state
                    .authorizer_removed
                    .store(authorizer == libsqlite3_sys::SQLITE_OK, Relaxed);
            }
        }

        impl Sampler {
            pub async fn install(db: &sea_orm::DatabaseConnection) -> Result<Self> {
                Self::install_scope(db, Scope::CompletionHeads).await
            }

            pub async fn display_heads(db: &sea_orm::DatabaseConnection) -> Result<Self> {
                Self::install_scope(db, Scope::DisplayHeads).await
            }

            pub async fn display_members(db: &sea_orm::DatabaseConnection) -> Result<Self> {
                Self::install_scope(db, Scope::DisplayMembers).await
            }

            async fn install_scope(db: &sea_orm::DatabaseConnection, scope: Scope) -> Result<Self> {
                let pool = db.get_sqlite_connection_pool();
                ensure!(
                    pool.options().get_max_connections() == 1,
                    "sampling requires this test fixture's single physical connection"
                );
                let state = Arc::new(State {
                    scope,
                    ..State::default()
                });
                {
                    let mut connection = pool.acquire().await?;
                    let mut handle = connection.lock_handle().await?;
                    let raw = handle.as_raw_handle().as_ptr();
                    let registration = Registration {
                        handle_address: raw as usize,
                        state: state.clone(),
                    };
                    // Install ownership before publishing any context pointer to SQLite. There is no
                    // await between the three registrations, so partial installation is synchronous.
                    handle.set_progress_handler(1_000_000, move || {
                        registration.interrupt_at_budget()
                    });
                    // SAFETY: raw is protected by LockedSqliteHandle. Arc::as_ptr is aligned and stable;
                    // the driver-owned registration above retains its strong reference until it removes
                    // the callbacks. Callbacks access only shared atomics, not a mutable State reference.
                    // This fresh, private fixture has no previous trace/authorizer/progress subscriber.
                    let (trace, authorizer) = unsafe {
                        let context = Arc::as_ptr(&state).cast_mut().cast::<c_void>();
                        (
                            libsqlite3_sys::sqlite3_trace_v2(
                                raw,
                                (libsqlite3_sys::SQLITE_TRACE_PROFILE
                                    | libsqlite3_sys::SQLITE_TRACE_ROW)
                                    as c_uint,
                                Some(trace_callback),
                                context,
                            ),
                            libsqlite3_sys::sqlite3_set_authorizer(raw, Some(authorize), context),
                        )
                    };
                    if trace != libsqlite3_sys::SQLITE_OK || authorizer != libsqlite3_sys::SQLITE_OK
                    {
                        handle.remove_progress_handler();
                        anyhow::bail!("native sampling registration failed: {trace}/{authorizer}");
                    }
                }
                let sampler = Self { state };
                // Prove the column guard is active before the measured request. Preparing this forbidden
                // read fails even though the fixture's content table is empty. Exclude the probe from Main.
                let mut probes = vec!["SELECT data FROM conversation_content_chunks LIMIT 1"];
                if !matches!(scope, Scope::CompletionHeads) {
                    probes.push("SELECT payload FROM conversation_items LIMIT 1");
                }
                if matches!(scope, Scope::DisplayHeads) {
                    probes.push("SELECT metadata FROM conversation_display_members LIMIT 1");
                }
                for (index, sql) in probes.iter().enumerate() {
                    let probe = db.query_all_raw(statement(sql, vec![])).await;
                    if probe.is_ok() || sampler.state.denied_reads.load(Relaxed) != index as u64 + 1
                    {
                        sampler.finish(db).await?;
                        anyhow::bail!("body/original/member authorizer probe was not denied");
                    }
                }
                sampler.state.denied_reads.store(0, Relaxed);
                Ok(sampler)
            }

            pub fn lifetime(&self) -> Lifetime {
                Lifetime(Arc::downgrade(&self.state))
            }

            pub async fn finish(self, db: &sea_orm::DatabaseConnection) -> Result<Work> {
                {
                    let mut connection = db.get_sqlite_connection_pool().acquire().await?;
                    let mut handle = connection.lock_handle().await?;
                    // Reacquiring the worker's native lock joins any in-flight step/profile callback.
                    // SQLx removes its progress callback before dropping Registration, whose destructor
                    // unregisters trace/authorizer before the final native-owned State Arc is released.
                    handle.remove_progress_handler();
                }
                let s = &self.state;
                ensure!(
                    s.trace_removed.load(Relaxed) && s.authorizer_removed.load(Relaxed),
                    "native callbacks were not unregistered"
                );
                ensure!(
                    Arc::strong_count(s) == 1,
                    "native callback context is still retained"
                );
                ensure!(
                    !s.budget_exceeded.load(Relaxed),
                    "statement exceeded the VM counter safety budget"
                );
                ensure!(
                    !s.invalid_counter.load(Relaxed),
                    "invalid SQLite statement counter"
                );
                ensure!(
                    s.unexpected_statements.load(Relaxed) == 0,
                    "production read executed SQL outside the selected sampling scope"
                );
                Ok(Work {
                    candidates: s.candidates.load(Relaxed),
                    member_rows: s.member_rows.load(Relaxed),
                    reference_rows: s.reference_rows.load(Relaxed),
                    statements: s.statements.load(Relaxed),
                    vm_steps: s.vm_steps.load(Relaxed),
                    head_vm_steps: s.head_vm_steps.load(Relaxed),
                    fullscan_steps: s.fullscan_steps.load(Relaxed),
                    head_fullscan_steps: s.head_fullscan_steps.load(Relaxed),
                    payload_column_authorizations: s.payload_column_authorizations.load(Relaxed),
                    denied_reads: s.denied_reads.load(Relaxed),
                })
            }
        }

        fn contains(sql: &[u8], needle: &[u8]) -> bool {
            !needle.is_empty() && sql.windows(needle.len()).any(|window| window == needle)
        }

        enum Kind {
            Heads,
            Members,
            Reference,
            Unexpected,
        }

        fn kind(sql: &[u8], scope: Scope) -> Kind {
            let sql = sql.trim_ascii();
            if !matches!(scope, Scope::CompletionHeads) {
                if sql.starts_with(b"SELECT block_id,source_key,block_order,history_pos,sealed,updated_effect,header FROM conversation_display_blocks WHERE ") {
            return Kind::Heads;
        }
                if matches!(scope, Scope::DisplayMembers) {
                    if sql == b"SELECT 1 FROM conversation_display_blocks WHERE block_id=?" {
                        return Kind::Reference;
                    }
                    if sql == b"SELECT block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata FROM conversation_display_members WHERE block_id=? AND member_order<=? ORDER BY member_order DESC LIMIT ?" {
                return Kind::Members;
            }
                }
                return Kind::Unexpected;
            }
            if sql == run_read::RUN_HEADS_SQL.as_bytes().trim_ascii() {
                Kind::Heads
            } else if sql.starts_with(b"SELECT ")
                && sql.ends_with(b"FROM conversation_items WHERE seq=?")
                && contains(sql, b"length(payload)")
                && sql
                    .windows(b"payload".len())
                    .filter(|w| *w == b"payload")
                    .count()
                    == 1
            {
                // Permit the production run-start validation point read, but never a raw payload select.
                Kind::Reference
            } else {
                Kind::Unexpected
            }
        }

        unsafe extern "C" fn trace_callback(
            event: c_uint,
            context: *mut c_void,
            statement: *mut c_void,
            _: *mut c_void,
        ) -> c_int {
            if context.is_null() || statement.is_null() {
                return 0;
            }
            // SAFETY: registration owns the State Arc until native callbacks are removed; SQLite passes
            // its live sqlite3_stmt for PROFILE/ROW synchronously on the exclusive SQLx worker thread.
            // sqlite3_sql's NUL-terminated bytes remain valid for this call and are never retained.
            let (state, stmt, sql) = unsafe {
                let state = &*context.cast::<State>();
                let stmt = statement.cast::<libsqlite3_sys::sqlite3_stmt>();
                let sql = libsqlite3_sys::sqlite3_sql(stmt);
                if sql.is_null() {
                    state.invalid_counter.store(true, Relaxed);
                    return 0;
                }
                (state, stmt, CStr::from_ptr(sql).to_bytes())
            };
            let kind = kind(sql, state.scope);
            if event == libsqlite3_sys::SQLITE_TRACE_ROW as c_uint {
                match kind {
                    Kind::Heads => {
                        state.candidates.fetch_add(1, Relaxed);
                    }
                    Kind::Reference => {
                        state.reference_rows.fetch_add(1, Relaxed);
                    }
                    Kind::Members => {
                        state.member_rows.fetch_add(1, Relaxed);
                    }
                    Kind::Unexpected => {}
                }
            } else if event == libsqlite3_sys::SQLITE_TRACE_PROFILE as c_uint {
                // SAFETY: this is the same live statement, at completion, under SQLite's worker
                // exclusivity. Reset=1 isolates executions of cached statements between samples.
                let (vm, fullscan) = unsafe {
                    (
                        libsqlite3_sys::sqlite3_stmt_status(
                            stmt,
                            libsqlite3_sys::SQLITE_STMTSTATUS_VM_STEP,
                            1,
                        ),
                        libsqlite3_sys::sqlite3_stmt_status(
                            stmt,
                            libsqlite3_sys::SQLITE_STMTSTATUS_FULLSCAN_STEP,
                            1,
                        ),
                    )
                };
                if vm < 0 || fullscan < 0 {
                    state.invalid_counter.store(true, Relaxed);
                    return 0;
                }
                state.statements.fetch_add(1, Relaxed);
                state.vm_steps.fetch_add(vm as u64, Relaxed);
                state.fullscan_steps.fetch_add(fullscan as u64, Relaxed);
                match kind {
                    Kind::Heads => {
                        state.head_vm_steps.fetch_add(vm as u64, Relaxed);
                        state
                            .head_fullscan_steps
                            .fetch_add(fullscan as u64, Relaxed);
                    }
                    Kind::Reference | Kind::Members => {}
                    Kind::Unexpected => {
                        state.unexpected_statements.fetch_add(1, Relaxed);
                    }
                }
            }
            // No allocation, locks, panicking operations, SQL execution or retained SQLite pointers.
            0
        }

        unsafe extern "C" fn authorize(
            context: *mut c_void,
            action: c_int,
            table: *const c_char,
            column: *const c_char,
            _: *const c_char,
            _: *const c_char,
        ) -> c_int {
            if action != libsqlite3_sys::SQLITE_READ || context.is_null() || table.is_null() {
                return libsqlite3_sys::SQLITE_OK;
            }
            // SAFETY: SQLite supplies live NUL-terminated action arguments for this synchronous callback.
            // The context has the same driver-owned Arc lifetime as the trace callback.
            let (state, table) =
                unsafe { (&*context.cast::<State>(), CStr::from_ptr(table).to_bytes()) };
            if !matches!(state.scope, Scope::CompletionHeads) {
                let allowed = table == b"conversation_display_blocks"
                    || (matches!(state.scope, Scope::DisplayMembers)
                        && table == b"conversation_display_members");
                if !allowed {
                    state.denied_reads.fetch_add(1, Relaxed);
                    return libsqlite3_sys::SQLITE_DENY;
                }
            }
            if table == b"conversation_contents" || table == b"conversation_content_chunks" {
                state.denied_reads.fetch_add(1, Relaxed);
                return libsqlite3_sys::SQLITE_DENY;
            }
            // SAFETY: short-circuit evaluation proves column is non-null before this conversion;
            // SQLite's column argument has the same synchronous callback lifetime as table.
            if table == b"conversation_items"
                && !column.is_null()
                && unsafe { CStr::from_ptr(column) }.to_bytes() == b"payload"
            {
                // SQLite authorizers cannot distinguish length(payload) from payload. Permit the
                // header length access, and separately reject any non-header SQL in the trace audit.
                state.payload_column_authorizations.fetch_add(1, Relaxed);
            }
            libsqlite3_sys::SQLITE_OK
        }
    }
}

#[cfg(test)]
pub(in crate::studio::storage::history) mod tests {
    use super::*;
    use pl_core::chat::{
        ChatContent, ChatContentKey, ChatContents, ChatDraft, ChatError, ChatQuery, ContentData,
        ContentDescriptor, ContentReadRequest, ContentRef, ReadDemand, TimelineEpoch,
    };
    use sea_orm::{Database, DatabaseConnection};

    pub(super) struct Budget;
    impl ChatBudget for Budget {
        fn fixed_bytes(&self) -> usize {
            0
        }
        fn item_bytes(&self, h: &ChatItemHeader, mode: PayloadMode) -> usize {
            match mode {
                PayloadMode::Inline => 64 + h.byte_length as usize,
                PayloadMode::Deferred => 64,
            }
        }
        fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
            128
        }
    }

    pub(super) async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
        let dir = tempfile::tempdir()?;
        let path = dir.path().join("history.sqlite");
        let mut options =
            sea_orm::ConnectOptions::new(format!("sqlite://{}?mode=rwc", path.display()));
        options
            .max_connections(1)
            .min_connections(1)
            .sqlx_logging(false);
        let db = Database::connect(options).await?;
        db.execute_unprepared(
            "CREATE TABLE history_meta(id INTEGER PRIMARY KEY,applied_write_seq INTEGER NOT NULL);
         INSERT INTO history_meta VALUES(1,0);",
        )
        .await?;
        db.execute_unprepared(migration::CREATE_SCHEMA).await?;
        db.execute_unprepared(
            "ALTER TABLE conversation_items ADD COLUMN metadata BLOB NOT NULL DEFAULT X''",
        )
        .await?;
        db.execute_unprepared(sources::CREATE_SCHEMA).await?;
        db.execute_unprepared(super::super::schema::immutable_completion_runs::CREATE)
            .await?;
        Ok((dir, db))
    }

    fn item(seq: u64, class: &str, payload: &[u8]) -> ChatItem {
        let mut draft = ChatDraft::new(format!("item:{seq}"), class, Arc::from(payload));
        draft.metadata = metadata(&draft.item_id);
        let atom = serde_json::from_slice(&draft.metadata).unwrap();
        draft.read_hint = crate::studio::runtime::chat_item::native_read_hint_v1(class, &atom);
        let run = (draft.read_hint != ChatReadHint::Hidden).then_some(ChatRunPosition {
            start_seq: seq,
            ordinal: 1,
        });
        ChatItem::complete(draft, seq, run)
    }

    pub(in crate::studio::storage::history) fn metadata(id: &str) -> Arc<[u8]> {
        serde_json::to_vec(&pl_protocol::ChatAtom {
            id: id.into(),
            completion_item_id: Some(id.into()),
            content_present: None,
            completion_seq: None,
            source_state: None,
            source: pl_protocol::ChatSourceId::Receipt {
                receipt_id: id.into(),
            },
            source_order: None,
            kind: pl_protocol::ChatAtomKind::Unknown,
            delivery: pl_protocol::ChatDeliveryKind::Independent,
            lifecycle: pl_protocol::ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: pl_protocol::ChatTerminalOutcome::Completed,
            },
            turn_id: None,
            attempt_id: None,
            tool: None,
            wait: None,
            text_channel: None,
            started_at: None,
            finished_at: None,
            contents: vec![],
            payload: None,
        })
        .unwrap()
        .into()
    }

    #[tokio::test]
    async fn metadata_budget_deferred_keyset_and_immutable_blob_conflicts() -> Result<()> {
        struct MetadataBudget;
        impl ChatBudget for MetadataBudget {
            fn fixed_bytes(&self) -> usize {
                0
            }
            fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
                header.metadata.len()
                    + match mode {
                        PayloadMode::Inline => 64 + header.byte_length as usize,
                        PayloadMode::Deferred => 64,
                    }
            }
            fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
                unreachable!()
            }
        }
        let (_dir, db) = fixture().await?;
        let mut first = item(1, "conversation", &[255; 256 * 1024]);
        first.header.metadata = metadata("item:1");
        let mut second = item(2, "conversation", b"opaque neighbour");
        second.header.metadata = metadata("item:2");
        append_records(&db, [&first, &second], true).await?;
        append_records(&db, [&first, &second], false).await?;
        let mut changed = first.clone();
        changed.header.metadata = Arc::from(b"same payload, different metadata".as_slice());
        assert!(append_records(&db, [&changed], false).await.is_err());
        let exact = MetadataBudget.item_bytes(&first.header, PayloadMode::Deferred);
        let request = ChatHistoryRequest {
            query: Some(ChatQuery::new("conversation", None)),
            after: 0,
            before: Some(2),
            ceiling: 2,
            demand: ReadDemand::new(2, exact),
        };
        let selected = page(&db, &request, &MetadataBudget, false).await?;
        assert!(selected.exhausted);
        assert_eq!(selected.items.len(), 1);
        assert_eq!(selected.items[0].header, first.header);
        assert!(matches!(
            selected.items[0].payload,
            PayloadData::Deferred {
                byte_length: 262144,
                ..
            }
        ));
        let under = ChatHistoryRequest {
            demand: ReadDemand::new(2, exact - 1),
            ..request.clone()
        };
        let selected = page(&db, &under, &MetadataBudget, false).await?;
        assert!(selected.items.is_empty());
        assert!(!selected.exhausted, "byte truncation is not EOF");
        let remaining = ChatHistoryRequest {
            after: 1,
            before: None,
            demand: ReadDemand::new(2, 4096),
            ..request
        };
        let selected = page(&db, &remaining, &MetadataBudget, true).await?;
        assert_eq!(selected.items.len(), 1);
        assert_eq!(selected.items[0].header.metadata, second.header.metadata);
        assert!(
            matches!(&selected.items[0].payload, PayloadData::Inline(bytes) if bytes.as_ref()==b"opaque neighbour")
        );
        Ok(())
    }

    #[tokio::test]
    async fn demand_selects_indexed_scope_and_defers_oversized_payload() -> Result<()> {
        let (_dir, db) = fixture().await?;
        let a = item(1, "conversation", b"small");
        let mut b = item(2, "conversation", &vec![b'x'; 128 * 1024]);
        b.header.parent_id = Some(ChatKey::new("turn", "id:with:colons")?);
        let c = item(3, "diagnostic", &vec![b'y'; 128 * 1024]);
        append_records(&db, [&a, &b, &c], true).await?;
        let request = ChatHistoryRequest {
            query: Some(ChatQuery::new("conversation", None)),
            after: 0,
            before: None,
            ceiling: 3,
            demand: ReadDemand::new(2, 200),
        };
        let selected_page = page(&db, &request, &Budget, false).await?;
        assert_eq!(
            selected_page
                .items
                .iter()
                .map(|item| item.header.append_seq)
                .collect::<Vec<_>>(),
            [1, 2]
        );
        assert!(matches!(
            selected_page.items[0].payload,
            PayloadData::Inline(_)
        ));
        assert!(matches!(
            selected_page.items[1].payload,
            PayloadData::Deferred { .. }
        ));
        assert!(
            !selected_page.exhausted,
            "exact demand does not issue an extra existence probe"
        );
        let children = ChatHistoryRequest {
            query: Some(ChatQuery::new(
                "conversation",
                Some(ChatKey::new("turn", "id:with:colons")?),
            )),
            demand: ReadDemand::new(4, 200),
            ..request.clone()
        };
        let selected = page(&db, &children, &Budget, false).await?;
        assert_eq!(selected.items.len(), 1);
        assert_eq!(selected.items[0].header.item_id, "item:2");
        assert!(selected.exhausted);
        let capped = ChatHistoryRequest {
            ceiling: 1,
            ..request
        };
        assert_eq!(
            page(&db, &capped, &Budget, false).await?.items[0]
                .header
                .append_seq,
            1
        );
        Ok(())
    }

    #[tokio::test]
    async fn cold_scope_budget_fits_completions_without_reserving_state() -> Result<()> {
        let dir = tempfile::tempdir()?;
        let store =
            super::super::HistoryStore::open(&dir.path().join("history.sqlite"), "cold-budget")
                .await?;
        store.prepare_write().await?;
        let record = Arc::new(item(1, "conversation", &[255; 2048]));
        let current = super::super::test_current(1);
        store
            .commit_effect(
                1,
                super::super::EffectCommit {
                    items: &[],
                    completions: std::slice::from_ref(&record),
                    current: &current,
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let mut query = ChatQuery::new("conversation", None);
        query.selection = ChatSelection::RunHeads;
        let exact = store
            .cold_conversation(query.clone(), ReadDemand::new(1, 64), &Budget)
            .await?
            .unwrap();
        assert_eq!(exact.page.items.len(), 1);
        assert_eq!(exact.page.items[0].header, record.header);
        assert!(matches!(
            exact.page.items[0].payload,
            PayloadData::Deferred { .. }
        ));
        assert!(
            store
                .cold_conversation(query, ReadDemand::new(1, 63), &Budget)
                .await
                .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn payload_and_body_ranges_cross_chunks_without_reading_whole_values() -> Result<()> {
        let (_dir, db) = fixture().await?;
        let bytes: Arc<[u8]> = Arc::from((0..200_000).map(|i| (i % 251) as u8).collect::<Vec<_>>());
        let mut record = item(1, "conversation", &bytes);
        let key = ChatContentKey {
            owner: ChatKey::new("item", "item:1")?,
            key: "body".into(),
        };
        record.contents = Arc::new(ChatContents::from([(
            key.clone(),
            Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: key.clone(),
                    byte_length: bytes.len() as u64,
                    generation: 7,
                    media_type: None,
                },
                data: ContentData::Bytes(bytes.clone()),
            }),
        )]));
        append_records(&db, [&record], true).await?;
        let manifest = list_contents(
            &db,
            &pl_core::chat::ContentManifestRequest {
                epoch: TimelineEpoch::new("test")?,
                item_id: "item:1".into(),
                after: None,
                demand: ReadDemand::new(4, 512),
            },
            &Budget,
        )
        .await?;
        assert_eq!(manifest.entries.len(), 1);
        assert_eq!(manifest.entries[0].key, key);
        assert_eq!(manifest.entries[0].generation, 7);
        assert!(manifest.next.is_none());
        for reference in [
            ContentRef::ItemPayload("item:1".into()),
            ContentRef::Body(key.clone()),
        ] {
            let request = ContentReadRequest {
                epoch: TimelineEpoch::new("test")?,
                reference,
                offset: 65_531,
                max_bytes: 17,
                generation: None,
            };
            let window = read_content(&db, &request).await?;
            assert_eq!(window.bytes.as_bytes(), &bytes[65_531..65_548]);
            assert_eq!(window.offset, request.offset);
            assert_eq!(window.available_through, bytes.len() as u64);
            let eof = read_content(
                &db,
                &ContentReadRequest {
                    offset: bytes.len() as u64,
                    ..request.clone()
                },
            )
            .await?;
            assert!(eof.bytes.as_bytes().is_empty());
        }
        let stale = ContentReadRequest {
            epoch: TimelineEpoch::new("test")?,
            reference: ContentRef::Body(key.clone()),
            offset: 0,
            max_bytes: 1,
            generation: Some(6),
        };
        assert!(
            matches!(
                read_content(&db, &stale)
                    .await
                    .unwrap_err()
                    .downcast_ref::<ChatError>(),
                Some(ChatError::StaleContent)
            ),
            "stale generation must not succeed"
        );
        Ok(())
    }

    #[tokio::test]
    async fn body_chunk_loss_is_not_eof_and_item_missing_is_not_empty() -> Result<()> {
        let (_dir, db) = fixture().await?;
        let missing = ContentReadRequest {
            epoch: TimelineEpoch::new("test")?,
            reference: ContentRef::ItemPayload("missing".into()),
            offset: 0,
            max_bytes: 1,
            generation: None,
        };
        let error = read_content(&db, &missing).await.unwrap_err();
        assert!(matches!(
            error.downcast_ref::<ChatError>(),
            Some(ChatError::NotFound(_))
        ));
        let key = ChatContentKey {
            owner: ChatKey::new("item", "item:1")?,
            key: "body".into(),
        };
        let mut record = item(1, "conversation", b"item");
        record.contents = Arc::new(ChatContents::from([(
            key.clone(),
            Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: key.clone(),
                    byte_length: 70_000,
                    generation: 1,
                    media_type: None,
                },
                data: ContentData::Bytes(Arc::from(vec![b'x'; 70_000])),
            }),
        )]));
        append_records(&db, [&record], true).await?;
        db.execute_unprepared("DELETE FROM conversation_content_chunks WHERE byte_offset=65536")
            .await?;
        let lost = ContentReadRequest {
            reference: ContentRef::Body(key),
            offset: 65_535,
            max_bytes: 3,
            ..missing
        };
        assert!(
            read_content(&db, &lost).await.is_err(),
            "missing boundary chunk must not become EOF"
        );
        Ok(())
    }

    fn legacy(id: &str, seq: u64, kind: &str, data: serde_json::Value) -> Result<String> {
        Ok(serde_json::to_string(&serde_json::json!({
            "itemId":id, "appendSeq":seq, "turnId":"turn:full:id",
            "sourceEffectSeq":4, "sealedAt":15,
            "meta":serde_json::to_vec(&serde_json::json!({
                "id":id,"threadId":"thread","turnId":"turn:full:id",
                "descriptor":{"kind":kind,"data":data}
            }))?,
            "fields":[{"identity":{"kind":"host","value":"tool.result"},"text":"opaque 🦀"}]
        }))?)
    }

    #[test]
    fn published_field_identities_use_the_normal_codec_body_keys() -> Result<()> {
        use crate::studio::runtime::chat_item::BodyKey;
        use pl_core::chat::PresentationPart;
        let fields = [
            (serde_json::json!({"kind":"body"}), BodyKey::Body),
            (
                serde_json::json!({"kind":"outputText","value":2}),
                BodyKey::Part(PresentationPart::OutputText(2)),
            ),
            (
                serde_json::json!({"kind":"reasoningText","value":3}),
                BodyKey::Part(PresentationPart::ReasoningText(3)),
            ),
            (
                serde_json::json!({"kind":"summaryText","value":4}),
                BodyKey::Part(PresentationPart::SummaryText(4)),
            ),
            (
                serde_json::json!({"kind":"host","value":"tool.result"}),
                BodyKey::host("tool.result"),
            ),
        ];
        let mut stored: serde_json::Value = serde_json::from_str(&legacy(
            "keys",
            1,
            "tool",
            serde_json::json!({"unknown":"preserved"}),
        )?)?;
        stored["fields"] = serde_json::Value::Array(fields.iter().enumerate().map(|(position, (identity, _))|
        serde_json::json!({"identity":identity,"text":format!("body-{position} 🦀")})
    ).collect());
        let original = serde_json::to_string(&stored)?;
        let item = migration::convert(
            migration::LegacyCompletion {
                id: "keys",
                seq: 1,
                kind: "tool",
                turn: Some("turn:full:id"),
                source: Some(4),
                sealed_at: Some(15),
                original: &original,
            },
            "thread",
            "database",
        )?;
        let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
        let actual = payload["bodies"]
            .as_array()
            .unwrap()
            .iter()
            .take(fields.len())
            .map(|body| body["key"].as_str().unwrap().to_owned())
            .collect::<Vec<_>>();
        assert_eq!(
            actual,
            fields
                .iter()
                .map(|(_, key)| key.as_key())
                .collect::<Vec<_>>()
        );
        for (position, (_, key)) in fields.iter().enumerate() {
            let content = item
                .contents
                .values()
                .find(|content| content.descriptor.key.key == key.as_key())
                .unwrap();
            let expected = format!("body-{position} 🦀");
            assert_eq!(
                content.data.range(0, expected.len())?.as_bytes(),
                expected.as_bytes()
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn unknown_tool_descriptor_and_public_bytes_survive_without_current_decoder() -> Result<()>
    {
        let source = legacy(
            "old",
            1,
            "tool",
            serde_json::json!({
                "invocation":{"name":"unknown.old.tool","arguments":{"future":"unchanged"}},
                "state":{"kind":"obsolete","value":"do not interpret"}
            }),
        )?;
        let item = migration::convert(
            migration::LegacyCompletion {
                id: "old",
                seq: 1,
                kind: "tool",
                turn: Some("turn:full:id"),
                source: Some(4),
                sealed_at: Some(15),
                original: &source,
            },
            "thread",
            "database",
        )?;
        assert_eq!(item.header.query_class, "activity");
        assert_eq!(
            item.header.parent_id,
            Some(ChatKey::new("turn", "turn:full:id")?)
        );
        let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
        assert_eq!(payload["data"]["state"]["kind"], "obsolete");
        assert!(payload["data"].get("presentationContract").is_none());
        assert_eq!(
            item.contents
                .values()
                .find(|content| content.descriptor.key.key == "tool.result")
                .unwrap()
                .data
                .range(0, 100)?
                .as_bytes(),
            "opaque 🦀".as_bytes()
        );
        let mut corrupt: serde_json::Value = serde_json::from_str(&source)?;
        corrupt["meta"] = serde_json::json!([255, 0, 254]);
        let original = serde_json::to_string(&corrupt)?;
        let unsupported = migration::convert(
            migration::LegacyCompletion {
                id: "old",
                seq: 1,
                kind: "tool",
                turn: Some("turn:full:id"),
                source: Some(4),
                sealed_at: Some(15),
                original: &original,
            },
            "thread",
            "database",
        )?;
        assert_eq!(
            unsupported
                .contents
                .values()
                .next()
                .unwrap()
                .data
                .range(0, original.len())?
                .as_bytes(),
            original.as_bytes()
        );
        assert!(
            migration::convert(
                migration::LegacyCompletion {
                    id: "wrong",
                    seq: 1,
                    kind: "tool",
                    turn: Some("turn:full:id"),
                    source: Some(4),
                    sealed_at: Some(15),
                    original: &source,
                },
                "thread",
                "database"
            )
            .is_err()
        );
        Ok(())
    }

    /// Component-level proof of the pinned framework's transaction contract using the actual DDL and
    /// backfill implementation. The final production migration additionally owns checkpoint/current
    /// seeding and the existing format/identity preflight.
    struct TransactionProbe;
    impl sea_orm_migration::MigrationName for TransactionProbe {
        fn name(&self) -> &str {
            "storage_243_transaction_probe"
        }
    }
    #[sea_orm_migration::async_trait::async_trait]
    impl sea_orm_migration::MigrationTrait for TransactionProbe {
        fn use_transaction(&self) -> Option<bool> {
            Some(true)
        }
        async fn up(
            &self,
            manager: &sea_orm_migration::SchemaManager,
        ) -> Result<(), sea_orm::DbErr> {
            let db = manager.get_connection();
            db.execute_unprepared(migration::CREATE_SCHEMA).await?;
            migration::backfill(db, "thread")
                .await
                .map_err(|error| sea_orm::DbErr::Migration(format!("{error:#}")))?;
            db.execute_unprepared("UPDATE history_meta SET schema_version=12")
                .await?;
            Ok(())
        }
    }
    struct ProbeMigrator;
    impl sea_orm_migration::MigratorTraitSelf for ProbeMigrator {
        fn migrations(&self) -> Vec<Box<dyn sea_orm_migration::MigrationTrait>> {
            vec![Box::new(TransactionProbe)]
        }
    }

    #[tokio::test]
    async fn actual_backfill_ddl_marker_and_seaorm_receipt_rollback_then_retry() -> Result<()> {
        use sea_orm_migration::MigratorTraitSelf;
        let dir = tempfile::tempdir()?;
        let mut options = sea_orm::ConnectOptions::new(format!(
            "sqlite://{}?mode=rwc",
            dir.path().join("history.sqlite").display()
        ));
        options
            .max_connections(1)
            .min_connections(1)
            .sqlx_logging(false);
        let db = Database::connect(options).await?;
        db.execute_unprepared(
        "CREATE TABLE history_meta(id INTEGER PRIMARY KEY,schema_version INTEGER,database_id TEXT);
         INSERT INTO history_meta VALUES(1,11,'database');
         CREATE TABLE timeline_records(append_seq INTEGER PRIMARY KEY,record_id TEXT UNIQUE,
             turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,kind TEXT,payload TEXT);",
    )
    .await?;
        let first = legacy("one", 1, "tool", serde_json::json!({"old":"opaque"}))?;
        let second = legacy("two", 2, "text", serde_json::json!({"future":"retained"}))?;
        for (seq, id, kind, payload) in [
            (1, "one", "tool", first.as_str()),
            (2, "wrong-index-id", "text", second.as_str()),
        ] {
            db.execute_raw(statement(
                "INSERT INTO timeline_records VALUES(?,?,?,4,15,?,?)",
                vec![
                    seq.into(),
                    id.into(),
                    "turn:full:id".into(),
                    kind.into(),
                    payload.into(),
                ],
            ))
            .await?;
        }
        assert!(ProbeMigrator.up(&db, None).await.is_err());
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name='conversation_items'",
                vec![],
            ))
            .await?
            .is_none(),
            "DDL must roll back on the real migration transaction"
        );
        assert_eq!(
            db.query_one_raw(statement("SELECT schema_version FROM history_meta", vec![]))
                .await?
                .unwrap()
                .try_get::<i64>("", "schema_version")?,
            11
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version='storage_243_transaction_probe'",
                vec![],
            ))
            .await?
            .is_none()
        );
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM timeline_records WHERE append_seq=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "payload")?,
            first
        );
        db.execute_unprepared("UPDATE timeline_records SET record_id='two' WHERE append_seq=2")
            .await?;
        ProbeMigrator.up(&db, None).await?;
        assert_eq!(latest_append_seq(&db).await?, 2);
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version='storage_243_transaction_probe'",
                vec![],
            ))
            .await?
            .is_some()
        );
        ProbeMigrator.up(&db, None).await?;
        assert_eq!(latest_append_seq(&db).await?, 2);
        Ok(())
    }
}
