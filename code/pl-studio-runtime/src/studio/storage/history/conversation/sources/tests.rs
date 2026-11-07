use super::*;
use sea_orm::{ConnectOptions, Database, TransactionTrait};
fn origin() -> ChatSourceId {
    ChatSourceId::ForegroundTurn {
        turn_id: "turn".into(),
    }
}
fn at(effect_seq: u64) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq,
        suborder: 0,
    }
}
async fn fixture() -> Result<sea_orm::DatabaseConnection> {
    let mut options = ConnectOptions::new("sqlite::memory:");
    options
        .max_connections(1)
        .min_connections(1)
        .sqlx_logging(false);
    let db = Database::connect(options).await?;
    db.execute_unprepared(CREATE_SCHEMA).await?;
    Ok(db)
}
#[tokio::test]
async fn late_writer_end_preserves_the_start_at_an_earlier_cut() -> Result<()> {
    let db = fixture().await?;
    let start = ChatSourceState {
        source: origin(),
        lifecycle: ChatSourceLifecycle::Active,
        started: Some(at(1)),
        ended: None,
    };
    apply(&db, 1, std::slice::from_ref(&start)).await?;
    let end = ChatSourceState {
        source: origin(),
        lifecycle: ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Failed,
        },
        started: Some(at(1)),
        ended: Some(at(3)),
    };
    apply(&db, 3, std::slice::from_ref(&end)).await?;
    assert_eq!(
        read(&db, &[origin()], 1).await?.as_slice(),
        std::slice::from_ref(&start)
    );
    assert_eq!(
        read(&db, &[origin()], 3).await?.as_slice(),
        std::slice::from_ref(&end)
    );
    assert!(matches!(
        read(&db, &[origin()], 0).await?[0].lifecycle,
        ChatSourceLifecycle::Unknown
    ));
    verify(&db, 1, &[start]).await?;
    verify(&db, 3, std::slice::from_ref(&end)).await?;
    let mut changed = end;
    changed.ended = Some(at(4));
    assert!(apply(&db, 4, &[changed]).await.is_err());
    assert!(matches!(
        read(
            &db,
            &[ChatSourceId::Receipt {
                receipt_id: "missing".into()
            }],
            99
        )
        .await?[0]
            .lifecycle,
        ChatSourceLifecycle::Unknown
    ));
    Ok(())
}
#[tokio::test]
async fn legacy_unknown_start_is_not_fabricated_and_source_transaction_rolls_back() -> Result<()> {
    let db = fixture().await?;
    let old = ChatSourceState {
        source: origin(),
        lifecycle: ChatSourceLifecycle::Active,
        started: None,
        ended: None,
    };
    apply(&db, 7, std::slice::from_ref(&old)).await?;
    let tx = db.begin().await?;
    apply(
        &tx,
        9,
        &[ChatSourceState {
            source: origin(),
            lifecycle: ChatSourceLifecycle::Ended {
                outcome: ChatTerminalOutcome::Cancelled,
            },
            started: None,
            ended: Some(at(9)),
        }],
    )
    .await?;
    tx.rollback().await?;
    assert_eq!(read(&db, &[origin()], 8).await?, [old]);
    assert!(matches!(
        read(&db, &[origin()], 6).await?[0].lifecycle,
        ChatSourceLifecycle::Unknown
    ));
    Ok(())
}

#[tokio::test]
async fn cold_selected_sources_share_current_page_snapshot_and_ignore_unselected_metadata()
-> Result<()> {
    use pl_core::chat::{ChatDraft, ChatItem, ChatQuery, ReadDemand};
    use pl_protocol::{CurrentProjection, ThreadStatus};
    let dir = tempfile::tempdir()?;
    let store = crate::studio::storage::history::HistoryStore::open(
        &dir.path().join("history.sqlite"),
        "source-snapshot",
    )
    .await?;
    assert!(store.conversation_current().await?.is_none());
    store.prepare_write().await?;
    let writer = store.writer().await?;
    let mut item = ChatItem::complete(
        ChatDraft::new("selected", "conversation", Arc::from([255; 8192])),
        1,
    );
    item.header.metadata = super::super::tests::metadata("selected");
    let parent = pl_core::chat::ChatKey::new("turn", "actual-parent")?;
    item.header.parent_id = Some(parent.clone());
    let mut skipped = ChatItem::complete(
        ChatDraft::new("not-selected", "diagnostic", Arc::from([])),
        2,
    );
    skipped.header.metadata = Arc::from(b"invalid unselected metadata".as_slice());
    let source = ChatSourceId::Receipt {
        receipt_id: "selected".into(),
    };
    let started = ChatSourceState {
        source: source.clone(),
        lifecycle: ChatSourceLifecycle::Active,
        started: Some(at(1)),
        ended: None,
    };
    let current_source = ChatSourceState {
        source: origin(),
        lifecycle: ChatSourceLifecycle::Active,
        started: Some(at(2)),
        ended: None,
    };
    let mut current = CurrentProjection::empty(2, ThreadStatus::Running);
    current.sources.push(current_source.clone());
    current.active_turn = Some(pl_protocol::CurrentTurnHead {
        id: "turn".into(),
        phase: pl_protocol::TurnPhase::Thinking,
    });
    let mut active: pl_protocol::ChatAtom =
        serde_json::from_slice(&super::super::tests::metadata("active-member"))?;
    active.completion_item_id = None;
    active.source = origin();
    active.lifecycle = pl_protocol::ChatAtomLifecycle::Active {
        started: Some(at(2)),
        status: pl_protocol::ChatActiveStatus::Running,
    };
    current.atoms.push(active);
    let tx = writer.db.begin().await?;
    super::super::append_records(&tx, [&item, &skipped], true).await?;
    super::super::completed::apply(&tx, 2, &{
        let mut prepared = super::super::current::PreparedCurrent::new(
            crate::studio::thread_projection::FrozenCurrentProjection::new(current.clone()),
            Arc::from([]),
        );
        prepared.source_changes = Arc::from([started.clone(), current_source.clone()]);
        prepared
    })
    .await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
        .await?;
    let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
        "source-snapshot".into(),
        2,
        pl_core::thread::ThreadSnapshot {
            commit_sequence: 2,
            turns: vec![pl_core::thread::TurnRecord {
                turn_id: "turn".into(),
                input_id: None,
                state: pl_core::thread::TurnState::Running,
                elapsed_ms: None,
                model_steps: 0,
            }]
            .into(),
            ..Default::default()
        },
    );
    // The running turn is an independent checkpoint fact, not a saved product current.
    super::super::super::checkpoint::write(&tx, &checkpoint, None, None).await?;
    tx.commit().await?;

    let reader = store.reader().await?.unwrap();
    let snapshot = reader.db.begin().await?;
    let captured = current.clone();
    let request = pl_core::chat::ChatHistoryRequest {
        query: Some(ChatQuery::new("conversation", None)),
        after: 0,
        before: None,
        ceiling: super::super::latest_append_seq(&snapshot).await?,
        demand: ReadDemand::new(10, 4096),
    };
    let page = super::super::page(&snapshot, &request, &super::super::tests::Budget, false).await?;
    let ended = ChatSourceState {
        source: source.clone(),
        lifecycle: ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Completed,
        },
        started: Some(at(1)),
        ended: Some(at(3)),
    };
    current.source_effect_seq = 3;
    let tx = writer.db.begin().await?;
    super::super::completed::apply(&tx, 3, &{
        let mut prepared = super::super::current::PreparedCurrent::new(
            crate::studio::thread_projection::FrozenCurrentProjection::new(current.clone()),
            Arc::from([]),
        );
        prepared.source_changes = Arc::from([ended.clone()]);
        prepared
    })
    .await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=3")
        .await?;
    tx.commit().await?;
    let old_states = read_selected(&snapshot, &page, &captured, true).await?;
    assert_eq!(old_states.len(), 2);
    assert!(old_states.contains(&started));
    assert!(old_states.contains(&current_source));
    assert_eq!(
        read_selected(&snapshot, &page, &captured, false)
            .await?
            .as_slice(),
        std::slice::from_ref(&started)
    );
    snapshot.commit().await?;
    let cold = store
        .cold_conversation(
            ChatQuery::new("conversation", None),
            ReadDemand::new(10, 4096),
            &super::super::tests::Budget,
        )
        .await?
        .unwrap();
    assert_eq!(cold.head, 2);
    assert_eq!(cold.current.source_effect_seq, 3);
    assert_eq!(
        store.conversation_current().await?,
        Some(cold.current.clone())
    );
    assert_eq!(cold.page.items.len(), 1);
    assert!(cold.sources.contains(&ended));
    assert!(cold.sources.contains(&current_source));
    assert_eq!(
        cold.sources.len(),
        2,
        "unselected sources must not expand the read"
    );
    // A malformed unrelated global lifecycle is observable if (and only if) it is queried.
    // Children must use the same captured current cut without reading this current-only row.
    writer.db.execute_raw(statement(
        "UPDATE conversation_sources SET ended_observed=3,outcome='invalid lifecycle JSON' WHERE source_key=?",
        vec![source_key(&origin())?.into()],
    )).await?;
    let children = store
        .cold_conversation(
            ChatQuery::new("conversation", Some(parent)),
            ReadDemand::new(10, 4096),
            &super::super::tests::Budget,
        )
        .await?
        .unwrap();
    assert_eq!(children.current.source_effect_seq, 3);
    assert_eq!(children.page.items.len(), 1);
    assert_eq!(children.sources.as_slice(), std::slice::from_ref(&ended));
    assert!(
        store
            .cold_conversation(
                ChatQuery::new("conversation", None),
                ReadDemand::new(10, 4096),
                &super::super::tests::Budget,
            )
            .await
            .is_err(),
        "Main still queries its real current-only lifecycle evidence"
    );
    assert_eq!(
        store
            .conversation_sources(&[source.clone(), source], 2)
            .await?,
        [started]
    );
    writer
        .db
        .execute_unprepared("DELETE FROM timeline_projection_state")
        .await?;
    assert!(
        store.conversation_current().await.is_err(),
        "missing recovery cut is not None or checkpoint fallback"
    );
    Ok(())
}

#[tokio::test]
async fn older_effect_retry_verifies_source_identity_position_and_lifecycle_after_later_end()
-> Result<()> {
    use crate::studio::storage::history::{EffectCommit, HistoryStore, test_current};
    fn commit<'a>(
        current: &'a super::super::current::PreparedCurrent,
        empty: &'a std::collections::BTreeSet<String>,
    ) -> EffectCommit<'a> {
        EffectCommit {
            items: &[],
            completions: &[],
            current,
            rolled_back_turns: empty,
            identities: &[],
            messages: &[],
            receipts: &[],
            tasks: &[],
            deliveries: &[],
            delivery_repairs: &[],
            attempt: None,
        }
    }
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(&dir.path().join("history.sqlite"), "old-source-retry").await?;
    let empty = std::collections::BTreeSet::new();
    let start = ChatSourceState {
        source: origin(),
        lifecycle: ChatSourceLifecycle::Active,
        started: Some(at(1)),
        ended: None,
    };
    let mut first = test_current(1);
    first.source_changes = Arc::from([start.clone()]);
    store.commit_effect(1, commit(&first, &empty)).await?;
    let end = ChatSourceState {
        source: origin(),
        lifecycle: ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Completed,
        },
        started: Some(at(1)),
        ended: Some(at(2)),
    };
    let mut second = test_current(2);
    second.source_changes = Arc::from([end.clone()]);
    store.commit_effect(2, commit(&second, &empty)).await?;
    store.commit_effect(1, commit(&first, &empty)).await?;
    let mut changed_identity = start.clone();
    changed_identity.source = ChatSourceId::ForegroundTurn {
        turn_id: "different".into(),
    };
    let mut changed_position = start.clone();
    changed_position.started.as_mut().unwrap().suborder = 9;
    let mut changed_lifecycle = start;
    changed_lifecycle.lifecycle = ChatSourceLifecycle::Unknown;
    for changed in [changed_identity, changed_position, changed_lifecycle] {
        let mut conflicting = first.clone();
        conflicting.source_changes = Arc::from([changed]);
        assert!(
            store
                .commit_effect(1, commit(&conflicting, &empty))
                .await
                .is_err()
        );
    }
    assert_eq!(store.watermark().await?, 2);
    assert_eq!(store.conversation_sources(&[origin()], 2).await?, [end]);
    Ok(())
}
