use super::*;
use crate::studio::thread_projection::presentation::PresentationState;

#[tokio::test]
async fn empty_text_removal_is_atomic_and_never_revives_on_cold_read() -> Result<()> {
    use pl_protocol::{
        ChatAtomKind, ChatAtomLifecycle, ChatFactPosition, ChatSourceId, ChatTerminalOutcome,
    };
    let (_dir, db) = super::super::super::schema::display_snapshots::tests::fixture().await?;
    super::super::super::schema::display_snapshots::upgrade(&db).await?;
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    let mut owner = PresentationState::default();
    owner.bind(&database)?;
    let mut started: pl_protocol::ChatAtom =
        serde_json::from_slice(&super::super::tests::metadata("empty-text"))?;
    started.kind = ChatAtomKind::Text;
    started.source = ChatSourceId::ForegroundTurn {
        turn_id: "turn".into(),
    };
    started.completion_item_id = None;
    started.lifecycle = ChatAtomLifecycle::Active {
        started: Some(ChatFactPosition {
            effect_seq: 1,
            suborder: 0,
        }),
        status: pl_protocol::ChatActiveStatus::Running,
    };
    let begin = owner.prepare(1, &[started.clone()], &[], &[])?;
    let tx = db.begin().await?;
    apply(&tx, &begin).await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
        .await?;
    tx.commit().await?;
    let block_id = begin.blocks[0].header.id.clone();
    let mut ended = started;
    ended.completion_item_id = Some("empty-text".into());
    ended.content_present = Some(false);
    ended.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(ChatFactPosition {
            effect_seq: 1,
            suborder: 0,
        }),
        ended: Some(ChatFactPosition {
            effect_seq: 2,
            suborder: 0,
        }),
        outcome: ChatTerminalOutcome::Completed,
    };
    let mut draft = pl_core::chat::ChatDraft::new(
        "empty-text",
        "conversation",
        Arc::<[u8]>::from(b"{}".as_slice()),
    );
    draft.metadata = serde_json::to_vec(&ended)?.into();
    draft.read_hint =
        crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &ended);
    let original = Arc::new(ChatItem::complete(draft, 1, None));
    let finish = owner.prepare(2, &[ended], &[], std::slice::from_ref(&original))?;
    assert_eq!(finish.remove_empty.len(), 1);
    assert_eq!(finish.published_through, 0);
    db.execute_unprepared(
        "CREATE TRIGGER reject_empty_delete BEFORE DELETE ON conversation_display_blocks
        BEGIN SELECT RAISE(ABORT,'empty deletion rejection'); END;",
    )
    .await?;
    let tx = db.begin().await?;
    super::super::append_records(&tx, [original.as_ref()], true).await?;
    assert!(apply(&tx, &finish).await.is_err());
    tx.rollback().await?;
    assert!(super::super::read_item(&db, "empty-text").await?.is_none());
    assert_eq!(member_page(&db, &block_id, None, 8).await?.len(), 1);
    assert_eq!(recovery(&db).await?.open.len(), 1);
    db.execute_unprepared("DROP TRIGGER reject_empty_delete")
        .await?;
    let tx = db.begin().await?;
    super::super::append_records(&tx, [original.as_ref()], true).await?;
    apply(&tx, &finish).await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
        .await?;
    tx.commit().await?;
    verify(&db, &finish).await?;
    assert!(super::super::read_item(&db, "empty-text").await?.is_some());
    assert!(history_heads(&db, 1, None, 8).await?.is_empty());
    assert!(recovery(&db).await?.open.is_empty());
    assert!(member_page(&db, &block_id, None, 8).await.is_err());
    Ok(())
}

#[tokio::test]
async fn display_delta_rolls_back_with_original_completion_and_exact_replay_has_a_receipt()
-> Result<()> {
    use sea_orm::TransactionTrait;
    let (_dir, db) = super::super::super::schema::display_snapshots::tests::fixture().await?;
    super::super::super::schema::display_snapshots::upgrade(&db).await?;
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    let mut owner = PresentationState::default();
    owner.bind(&database)?;
    let mut atom: pl_protocol::ChatAtom =
        serde_json::from_slice(&super::super::tests::metadata("original"))?;
    atom.lifecycle = pl_protocol::ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(pl_protocol::ChatFactPosition {
            effect_seq: 1,
            suborder: 0,
        }),
        outcome: pl_protocol::ChatTerminalOutcome::Completed,
    };
    let mut draft = pl_core::chat::ChatDraft::new(
        "original",
        "conversation",
        Arc::<[u8]>::from(b"saved original".as_slice()),
    );
    draft.metadata = serde_json::to_vec(&atom)?.into();
    draft.read_hint = crate::studio::runtime::chat_item::native_read_hint_v1("conversation", &atom);
    let item = Arc::new(ChatItem::complete(
        draft,
        1,
        Some(pl_core::chat::ChatRunPosition {
            start_seq: 1,
            ordinal: 1,
        }),
    ));
    let delta = owner.prepare(1, &[atom], &[], std::slice::from_ref(&item))?;
    db.execute_unprepared("CREATE TRIGGER reject_display BEFORE INSERT ON conversation_display_members BEGIN SELECT RAISE(ABORT,'display rejection'); END;").await?;
    let tx = db.begin().await?;
    super::super::append_records(&tx, [item.as_ref()], true).await?;
    assert!(apply(&tx, &delta).await.is_err());
    tx.rollback().await?;
    assert!(super::super::read_item(&db, "original").await?.is_none());
    assert!(history_heads(&db, 1, None, 8).await?.is_empty());
    assert_eq!(watermarks(&db).await?, (0, 0));
    db.execute_unprepared("DROP TRIGGER reject_display").await?;
    let tx = db.begin().await?;
    super::super::append_records(&tx, [item.as_ref()], true).await?;
    apply(&tx, &delta).await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
        .await?;
    tx.commit().await?;
    verify(&db, &delta).await?; // Lost local acknowledgement: no rewrite/recalculation.
    apply(&db, &delta).await?;
    let mut contradictory = delta.as_ref().clone();
    contradictory.published_through = 0;
    assert!(verify(&db, &contradictory).await.is_err());
    assert_eq!(watermarks(&db).await?, (1, 1));
    // Snapshot reads are independent of original payload tables.
    db.execute_unprepared("ALTER TABLE conversation_items RENAME TO originals_not_available")
        .await?;
    assert_eq!(history_heads(&db, 1, None, 8).await?.len(), 1);
    assert_eq!(
        member_page(&db, &delta.blocks[0].header.id, None, 8)
            .await?
            .len(),
        1
    );
    assert!(recovery(&db).await?.open.is_empty());
    Ok(())
}
