//! Frozen schema-24 conversation decoding for the explicit legacy migration boundary.

use super::{integer, statement};
use anyhow::{Context, Result, ensure};
#[cfg(test)]
use pl_core::chat::{
    ChatBudget, ChatHistoryPage, ChatHistoryRequest, ChatPageItem, ChatPublicationSeed,
    PayloadData, PayloadMode, select_payload,
};
use pl_core::chat::{ChatItem, ChatItemHeader, ChatKey};
#[cfg(test)]
use sea_orm::Value;
use sea_orm::{ConnectionTrait, QueryResult};
#[cfg(test)]
use std::collections::BTreeMap;
use std::sync::Arc;

/// Frozen schema-24 current/effect codec retained for explicit legacy imports.
#[cfg(test)]
pub(super) mod completed;
#[path = "conversation/content.rs"]
pub(in crate::studio::storage::history) mod content;
#[cfg(test)]
#[path = "conversation/current.rs"]
pub(in crate::studio) mod current;
pub(in crate::studio) mod display;
#[path = "conversation/migration.rs"]
pub(super) mod migration;

pub(super) use content::read_contents;
#[cfg(test)]
pub(super) use content::{list_contents, write_contents};
#[cfg(test)]
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
    };
    Ok(header)
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

#[cfg(test)]
pub(super) async fn publication_seed(db: &impl ConnectionTrait) -> Result<ChatPublicationSeed> {
    Ok(ChatPublicationSeed {
        head_seq: latest_append_seq(db).await?,
    })
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
    let header = header(&row)?;
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
#[cfg(test)]
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
                "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,payload
                 FROM conversation_items WHERE item_id=?", vec![h.item_id.clone().into()],
            )).await?.context("committed completion disappeared")?;
            ensure!(
                header(&old)? == *h
                    && old.try_get::<Vec<u8>>("", "payload")?.as_slice() == item.payload.as_ref(),
                "immutable completion payload conflict"
            );
            let owner = crate::studio::content_owner_key(&crate::ContentOwner::Item {
                item_id: h.item_id.clone(),
            })?;
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
        let seq = next.advance()?;
        ensure!(seq == h.append_seq, "completion sequence is not contiguous");
        db.execute_raw(statement(
            "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(?,?,?,?,?,?)",
            vec![integer(h.append_seq)?.into(), h.item_id.clone().into(), h.query_class.clone().into(),
                h.parent_id.as_ref().map(|key| key.as_str().to_owned()).into(),
                item.payload.to_vec().into(),h.metadata.to_vec().into()],
        )).await?;
        write_contents(db, &h.item_id, &item.contents).await?;
        *head = next;
    }
    Ok(())
}

/// Explicit detail demand: one indexed lightweight header, then only its budgeted payload.
/// Unlike the publication idempotency port this never reads a content manifest or body.
#[cfg(test)]
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
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length
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
    let mut page = materialize(db, &page_request, budget, true, &rows, true).await?;
    ensure!(
        !page.items.is_empty(),
        pl_core::chat::ChatError::InvalidDemand("item detail cannot fit demand".into())
    );
    Ok(page.items.pop())
}

/// First fetch only indexed headers and BLOB lengths. Deferred records never fetch their payload.
#[cfg(test)]
pub(super) async fn page(
    db: &impl ConnectionTrait,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
    ascending: bool,
) -> Result<ChatHistoryPage> {
    page_filtered(db, request, budget, ascending, false).await
}

#[cfg(test)]
pub(super) async fn page_filtered(
    db: &impl ConnectionTrait,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
    ascending: bool,
    text_only: bool,
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
        if let Some(class) = &query.query_class {
            ensure!(!class.is_empty(), "empty completion query class");
            sql.push_str(" AND query_class=?");
            values.push(class.clone().into());
        }
        if let Some(parent) = &query.parent_id {
            sql.push_str(" AND parent_id=?");
            values.push(parent.as_str().into());
        }
    }
    if text_only {
        sql.push_str(" AND json_extract(metadata,'$.kind') IN ('text','input')");
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
    materialize(db, request, budget, ascending, &rows, natural_end).await
}

#[cfg(test)]
async fn materialize(
    db: &impl ConnectionTrait,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
    ascending: bool,
    rows: &[QueryResult],
    natural_end: bool,
) -> Result<ChatHistoryPage> {
    let mut selected = Vec::with_capacity(rows.len());
    let mut bytes = request.demand.max_bytes;
    let mut exhausted = natural_end;
    let mut header_decodes = 0;
    for row in rows {
        header_decodes += 1;
        let h = header(row)?;
        let mode = select_payload(&h, bytes, budget);
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
pub(in crate::studio) mod record_read_tests {
    use super::*;
    use crate::{ChatAtom, ChatAtomKind, ChatSourceId};
    use pl_core::chat::{ChatDraft, ChatQuery, ReadDemand};
    use sea_orm::TransactionTrait;

    fn atom(id: &str, kind: ChatAtomKind, source: &str) -> ChatAtom {
        let mut atom: ChatAtom = serde_json::from_slice(&super::tests::metadata(id)).unwrap();
        atom.kind = kind;
        atom.source = ChatSourceId::ForegroundTurn {
            turn_id: source.into(),
        };
        atom.delivery = crate::ChatDeliveryKind::Foreground;
        atom
    }

    fn record(seq: u64, atom: ChatAtom) -> ChatItem {
        let mut draft = ChatDraft::new(
            &atom.id,
            "conversation",
            Arc::from(&b"{\"original\":true}"[..]),
        );
        draft.parent_id = Some(ChatKey::new("turn", "real-parent").unwrap());

        draft.metadata = serde_json::to_vec(&atom).unwrap().into();
        ChatItem::complete(draft, seq)
    }

    fn request(ceiling: u64, before: Option<u64>, max_items: usize) -> ChatHistoryRequest {
        let query = ChatQuery::new("conversation", None);
        ChatHistoryRequest {
            query: Some(query),
            after: 0,
            before,
            ceiling,
            demand: ReadDemand::new(max_items, 256 * 1024),
        }
    }

    #[tokio::test]
    async fn records_keep_every_kind_and_respect_real_parent_and_fixed_completion_cut() -> Result<()>
    {
        let (_dir, db) = super::tests::fixture().await?;
        let mut records = [
            record(1, atom("one", ChatAtomKind::ToolCall, "F")),
            record(2, atom("hidden", ChatAtomKind::Inference, "F")),
            record(3, atom("text", ChatAtomKind::Text, "F")),
        ];
        records[1].header.query_class = "execution".into();
        append_records(&db, records.iter(), true).await?;
        let mut query = request(2, None, 2);
        query.query.as_mut().unwrap().query_class = None;
        query.query.as_mut().unwrap().parent_id = Some(ChatKey::new("turn", "real-parent")?);
        let page = page(&db, &query, &super::tests::Budget, false).await?;
        assert_eq!(
            page.items
                .iter()
                .map(|item| item.header.append_seq)
                .collect::<Vec<_>>(),
            [1, 2]
        );
        assert_eq!(publication_seed(&db).await?.head_seq, 3);
        query.query.as_mut().unwrap().parent_id = Some(ChatKey::new("turn", "other")?);
        assert!(
            super::page(&db, &query, &super::tests::Budget, false)
                .await?
                .items
                .is_empty()
        );
        Ok(())
    }

    #[tokio::test]
    async fn lost_ack_replay_compares_identity_and_bytes_and_transaction_failure_rolls_back()
    -> Result<()> {
        let (_dir, db) = super::tests::fixture().await?;
        let one = record(1, atom("one", ChatAtomKind::ToolCall, "F"));
        append_records(&db, [&one], true).await?;
        append_records(&db, [&one], false).await?;
        let mut conflict = one.clone();
        conflict.header.parent_id = Some(ChatKey::new("turn", "changed-parent")?);
        assert!(append_records(&db, [&conflict], false).await.is_err());
        conflict = one.clone();
        conflict.payload = Arc::from(&b"{\"changed!\":true}"[..]);
        assert!(append_records(&db, [&conflict], false).await.is_err());
        let two = record(2, atom("two", ChatAtomKind::Skill, "F"));
        let three = record(3, atom("three", ChatAtomKind::Text, "F"));
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
    async fn explicit_item_detail_obeys_cut_and_budget_without_reading_contents() -> Result<()> {
        let (_dir, db) = super::tests::fixture().await?;
        let one = record(1, atom("one", ChatAtomKind::ToolCall, "F"));
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
        use crate::{ChatActiveStatus, ChatAtomLifecycle, ChatDeliveryKind, ChatTerminalOutcome};
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
        super::super::execution_lifecycle::apply(
            &connection.db,
            &[a.clone(), b.clone(), c.clone()]
                .iter()
                .map(|atom| {
                    super::super::execution_lifecycle::ExecutionLifecycle::from_atom(atom, 1)
                })
                .collect::<Result<Vec<_>>>()?,
        )
        .await?;
        a.lifecycle = ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: ChatTerminalOutcome::Completed,
        };
        super::super::execution_lifecycle::apply(
            &connection.db,
            &[super::super::execution_lifecycle::ExecutionLifecycle::from_atom(&a, 2)?],
        )
        .await?;
        let first = super::super::execution_lifecycle::active(&connection.db, None, 1).await?;
        assert_eq!(first, [b.clone()]);
        assert_eq!(
            super::super::execution_lifecycle::active(&connection.db, Some(&b.id), 1).await?,
            [c]
        );
        assert!(
            super::super::execution_lifecycle::active(&connection.db, Some("c"), 1)
                .await?
                .is_empty()
        );
        store.close_for_deletion().await?;
        Ok(())
    }
}

#[cfg(test)]
pub(in crate::studio::storage::history) mod tests {
    use super::*;
    use pl_core::chat::{ChatDraft, ChatQuery, ContentDescriptor, ReadDemand};
    use sea_orm::{Database, DatabaseConnection};

    pub(in crate::studio::storage::history) struct Budget;
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
        let store =
            super::super::HistoryStore::open(&dir.path().join("history.sqlite"), "record-fixture")
                .await?;
        store.prepare_write().await?;
        let db = store.writer().await?.db.clone();
        Ok((dir, db))
    }

    fn item(seq: u64, class: &str, payload: &[u8]) -> ChatItem {
        let mut draft = ChatDraft::new(format!("item:{seq}"), class, Arc::from(payload));
        draft.metadata = metadata(&draft.item_id);
        ChatItem::complete(draft, seq)
    }

    pub(in crate::studio::storage::history) fn metadata(id: &str) -> Arc<[u8]> {
        serde_json::to_vec(&crate::ChatAtom {
            id: id.into(),
            completion_item_id: Some(id.into()),
            content_present: None,
            completion_seq: None,
            source_state: None,
            source: crate::ChatSourceId::Receipt {
                receipt_id: id.into(),
            },
            source_order: None,
            kind: crate::ChatAtomKind::Unknown,
            delivery: crate::ChatDeliveryKind::Independent,
            lifecycle: crate::ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: crate::ChatTerminalOutcome::Completed,
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

    fn legacy(id: &str, seq: u64, kind: &str, data: serde_json::Value) -> Result<String> {
        Ok(serde_json::to_string(&serde_json::json!({
            "itemId": id, "appendSeq": seq, "turnId": "turn:full:id",
            "sourceEffectSeq": 4, "sealedAt": 15,
            "meta": serde_json::to_vec(&serde_json::json!({
                "id": id, "threadId": "thread", "turnId": "turn:full:id",
                "descriptor": {"kind": kind, "data": data}
            }))?,
            "fields": [{"identity": {"kind": "host", "value": "tool.result"}, "text": "opaque 🦀"}]
        }))?)
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
