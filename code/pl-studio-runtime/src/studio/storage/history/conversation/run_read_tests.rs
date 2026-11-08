use super::*;
use pl_core::chat::{ChatDraft, ChatQuery, ReadDemand};
use pl_protocol::{ChatAtom, ChatAtomKind, ChatSourceId};
use sea_orm::TransactionTrait;

#[path = "run_read_tests/sqlite_work.rs"]
mod sqlite_work;

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
    draft.read_hint = crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &atom);
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
async fn heads_skip_hidden_and_whole_runs_at_fixed_cut_and_children_keep_real_parent() -> Result<()>
{
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
async fn hundred_thousand_members_use_index_seeks_and_never_inline_work_payload() -> Result<()> {
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
        let setup_us = setup_started.elapsed().as_micros() + if size == 1 { seed_us } else { 0 };
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
    use pl_protocol::{ChatActiveStatus, ChatAtomLifecycle, ChatDeliveryKind, ChatTerminalOutcome};
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
