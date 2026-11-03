use super::*;
use anyhow::Result;
use pl_protocol::*;
use sea_orm::TransactionTrait;

fn at(effect: u64) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq: effect,
        suborder: 0,
    }
}
fn active(id: &str, kind: ChatAtomKind, effect: u64) -> ChatAtom {
    ChatAtom {
        id: id.into(),
        completion_item_id: None,
        completion_seq: None,
        source: ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        },
        source_state: None,
        source_order: Some(effect),
        kind,
        delivery: ChatDeliveryKind::Foreground,
        lifecycle: ChatAtomLifecycle::Active {
            started: Some(at(effect)),
            status: ChatActiveStatus::Running,
        },
        turn_id: Some("turn".into()),
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: None,
        started_at: Some(effect as i64),
        finished_at: None,
        content_present: None,
        contents: Vec::new(),
        payload: None,
    }
}
#[tokio::test]
async fn canonical_atom_phases_replay_exactly_and_reject_changed_start_or_terminal() -> Result<()> {
    let (_directory, db) = super::super::tests::fixture().await?;
    db.execute_unprepared(CREATE_SCHEMA).await?;
    let start = active("canonical-tool", ChatAtomKind::ToolCall, 1);
    let mut terminal = start.clone();
    terminal.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(1)),
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Completed,
    };
    terminal.finished_at = Some(2);
    terminal.completion_item_id = Some(start.id.clone());
    terminal.completion_seq = Some(1);
    for (phase, fact) in [("start", &start), ("terminal", &terminal)] {
        save_fact(&db, fact, 2).await?;
        // A later writer retry carries the same frozen identity and bytes. It cannot
        // relocate the phase to the retry's effect or allocate another fact identity.
        save_fact(&db, fact, 3).await?;
        let mut changed = fact.clone();
        changed.lifecycle = if phase == "start" {
            ChatAtomLifecycle::Active {
                started: Some(at(3)),
                status: ChatActiveStatus::Running,
            }
        } else {
            ChatAtomLifecycle::Terminal {
                started: Some(at(1)),
                ended: Some(at(2)),
                outcome: ChatTerminalOutcome::Failed,
            }
        };
        let error = save_fact(&db, &changed, 3)
            .await
            .expect_err("same identity cannot rewrite its canonical phase");
        assert!(error.to_string().contains("canonical atom phase changed"));
        let rows = db
            .query_all_raw(statement(
                "SELECT effect_seq,suborder,metadata FROM conversation_atom_facts
                 WHERE atom_id=? AND phase=?",
                vec![fact.id.clone().into(), phase.into()],
            ))
            .await?;
        assert_eq!(rows.len(), 1, "a retry must not allocate another fact");
        assert_eq!(
            rows[0].try_get::<i64>("", "effect_seq")?,
            if phase == "start" { 1 } else { 2 }
        );
        assert_eq!(rows[0].try_get::<i64>("", "suborder")?, 0);
        assert_eq!(
            rows[0].try_get::<Vec<u8>>("", "metadata")?,
            serde_json::to_vec(&lightweight(fact))?,
            "conflict rejection must preserve the exact original phase"
        );
    }
    Ok(())
}

async fn persist(
    db: &impl ConnectionTrait,
    projection: &mut TimelineProjection,
    effect: u64,
) -> Result<()> {
    projection.commit_ready()?;
    let committed = projection
        .take_committed()
        .into_iter()
        .map(|item| PreparedTimelineItem { item })
        .collect::<Vec<_>>();
    let update = projection.take_update()?;
    save_update(db, "db", &update, &committed, effect, true).await?;
    let mut current = CurrentProjection::empty(effect, ThreadStatus::Idle);
    current.items = projection.current_items();
    db.execute_raw(statement(
        "UPDATE history_meta SET applied_write_seq=? WHERE id=1",
        vec![integer(effect)?.into()],
    ))
    .await?;
    db.execute_raw(statement("INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?) ON CONFLICT(singleton_id) DO UPDATE SET payload=excluded.payload",vec![serde_json::to_vec(&current)?.into()])).await?;
    Ok(())
}

#[tokio::test]
async fn text_start_commits_group_without_new_atom_and_source_facts_rebuild_the_same_cut()
-> Result<()> {
    let (_directory, db) = super::super::tests::fixture().await?;
    db.execute_unprepared(CREATE_SCHEMA).await?;
    db.execute_unprepared(CREATE_DERIVED_SCHEMA).await?;
    let mut projection = TimelineProjection::new("db".into(), "test-generation".into(), 0);
    let work = active("z", ChatAtomKind::Reasoning, 1);
    projection.observe(&work, None)?;
    persist(&db, &mut projection, 1).await?;
    assert!(
        page_rows(&db, &ChatScope::Main, None, 100, 1, 1)
            .await?
            .is_empty()
    );
    let reference = projection.current_items()[0].members.clone().unwrap();
    let mut terminal = work.clone();
    terminal.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(1)),
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Completed,
    };
    terminal.completion_item_id = Some("original-completion".into());
    terminal.completion_seq = Some(1);
    terminal.finished_at = Some(2);
    // A deliberately opaque, malformed body proves folded Main and rebuild do
    // not need a JSON/payload decoder. The original bytes remain untouched.
    db.execute_raw(statement("INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(1,'original-completion','conversation',NULL,?,?)",vec![b"opaque original body".to_vec().into(),serde_json::to_vec(&terminal)?.into()])).await?;
    projection.complete(
        terminal,
        1,
        Some(PayloadData::Deferred {
            reference: ContentRef {
                database_id: "db".into(),
                target: ContentTarget::ItemPayload {
                    item_id: "original-completion".into(),
                },
            },
            byte_length: 20,
        }),
    )?;
    persist(&db, &mut projection, 2).await?;
    assert!(
        page_rows(&db, &ChatScope::Main, None, 100, 2, 1)
            .await?
            .is_empty()
    );
    projection.observe(&active("text", ChatAtomKind::Text, 3), None)?;
    persist(&db, &mut projection, 3).await?;
    let before = page_rows(&db, &ChatScope::Main, None, 100, 3, 1).await?;
    assert_eq!(before.len(), 1);
    let ChatEntry::Item(item) = &before[0].1 else {
        panic!("Main returned a member");
    };
    assert_eq!(item.kind, TimelineItemKind::WorkGroup);
    assert_eq!(item.summary.as_ref().unwrap().member_count, 1);
    assert!(item.payload.is_none());
    assert_eq!(item.outcome, None);
    let members = page_rows(
        &db,
        &ChatScope::GroupMembers {
            reference: reference.clone(),
        },
        None,
        100,
        3,
        1,
    )
    .await?;
    assert!(
        matches!(&members[0].1,ChatEntry::Atom(atom) if atom.completion_item_id.as_deref()==Some("original-completion") && matches!(atom.payload,Some(PayloadData::Deferred{..})))
    );
    let mut wrong = reference.clone();
    wrong.database_id = "another".into();
    assert!(validate_members_ref(&db, "db", &wrong).await.is_err());
    wrong = reference;
    wrong.projection_version += 1;
    assert!(validate_members_ref(&db, "db", &wrong).await.is_err());
    let tx = db.begin().await?;
    tx.execute_unprepared("DELETE FROM timeline_items;DELETE FROM timeline_item_members;DELETE FROM timeline_projection_state;").await?;
    rebuild(&tx, "db").await?;
    tx.commit().await?;
    let after = page_rows(&db, &ChatScope::Main, None, 100, 3, 1).await?;
    assert_eq!(logical(before.clone()), logical(after));
    let mut restored = TimelineProjection::new(
        "db".into(),
        generation(&db).await?,
        next_position(&db).await?,
    );
    restored.restore_recovery(&recovery(&db).await?)?;
    assert_eq!(
        logical_items(restored.current_items()),
        logical_items(projection.current_items())
    );
    let bytes: Vec<u8> = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_items WHERE seq=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "payload")?;
    assert_eq!(bytes, b"opaque original body");
    // An actual failed replacement transaction retains the complete old index,
    // not merely a use_transaction declaration.
    let before_failure = page_rows(&db, &ChatScope::Main, None, 100, 3, 1).await?;
    let before_generation = generation(&db).await?;
    let tx = db.begin().await?;
    tx.execute_unprepared("CREATE TRIGGER reject_timeline_rebuild BEFORE INSERT ON timeline_items BEGIN SELECT RAISE(ABORT,'injected rebuild failure'); END;").await?;
    assert!(rebuild(&tx, "db").await.is_err());
    tx.rollback().await?;
    assert_eq!(
        before_failure,
        page_rows(&db, &ChatScope::Main, None, 100, 3, 1).await?
    );
    assert_eq!(before_generation, generation(&db).await?);
    Ok(())
}

fn logical_items(mut items: Vec<TimelineItem>) -> Vec<TimelineItem> {
    for item in &mut items {
        if let Some(reference) = &mut item.members {
            reference.projection_generation = "logical".into();
        }
    }
    items
}
fn logical(mut rows: Vec<(u64, ChatEntry)>) -> Vec<(u64, ChatEntry)> {
    for (_, entry) in &mut rows {
        if let ChatEntry::Item(item) = entry
            && let Some(reference) = &mut item.members
        {
            reference.projection_generation = "logical".into();
        }
    }
    rows
}

#[tokio::test]
async fn legacy_ordinals_normalize_admission_without_fabricating_start_events_or_times()
-> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    db.execute_unprepared(CREATE_SCHEMA).await?;
    db.execute_unprepared(CREATE_DERIVED_SCHEMA).await?;
    let mut current = CurrentProjection::empty(3, ThreadStatus::Idle);
    current.execution_present = false;
    db.execute_raw(statement(
        "UPDATE history_meta SET applied_write_seq=3 WHERE id=1",
        vec![],
    ))
    .await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?)",
        vec![serde_json::to_vec(&current)?.into()],
    ))
    .await?;
    for (seq, id, kind, ordinal) in [
        (1, "text", ChatAtomKind::Text, 2),
        (2, "z", ChatAtomKind::Reasoning, 1),
        (3, "a", ChatAtomKind::ToolCall, 1),
    ] {
        let mut atom = active(id, kind, ordinal);
        atom.lifecycle = ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: ChatTerminalOutcome::Completed,
        };
        atom.started_at = None;
        atom.finished_at = None;
        atom.completion_item_id = Some(id.into());
        atom.completion_seq = None;
        db.execute_raw(statement("INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(?,?,'conversation',NULL,?,?)",
            vec![seq.into(),id.into(),b"opaque frozen bytes".to_vec().into(),serde_json::to_vec(&atom)?.into()])).await?;
    }
    let tx = db.begin().await?;
    normalize_legacy(&tx).await?;
    let starts = tx
        .query_one_raw(statement(
            "SELECT COUNT(*) AS n FROM conversation_atom_facts WHERE phase='start'",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get::<i64>("", "n")?;
    assert_eq!(starts, 0, "normalization invented reliable starts");
    rebuild(&tx, "db").await?;
    tx.commit().await?;
    let rows = page_rows(&db, &ChatScope::Main, None, 100, 3, 10).await?;
    assert_eq!(rows.len(), 2);
    let ChatEntry::Item(text) = &rows[0].1 else {
        panic!("text item missing");
    };
    assert_eq!(text.kind, TimelineItemKind::Text);
    assert_eq!(text.position, Some(1));
    assert_eq!(text.started_at, None);
    assert_eq!(text.finished_at, None);
    let ChatEntry::Item(group) = &rows[1].1 else {
        panic!("group item missing");
    };
    assert_eq!(group.summary.as_ref().unwrap().member_count, 2);
    assert_eq!(group.position, Some(0));
    assert_eq!(group.started_at, None);
    assert_eq!(group.finished_at, None);
    let members = page_rows(
        &db,
        &ChatScope::GroupMembers {
            reference: group.members.clone().unwrap(),
        },
        None,
        100,
        3,
        10,
    )
    .await?;
    assert!(matches!(&members[1],(0,ChatEntry::Atom(atom)) if atom.id=="z"));
    assert!(matches!(&members[0],(1,ChatEntry::Atom(atom)) if atom.id=="a"));
    let original = db
        .query_one_raw(statement(
            "SELECT item_id FROM conversation_items WHERE seq=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "item_id")?;
    assert_eq!(
        original, "text",
        "normalization rewrote original completion order"
    );
    Ok(())
}

#[tokio::test]
async fn legacy_long_completed_group_does_not_stage_all_members_as_active_recovery() -> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let tx = db.begin().await?;
    tx.execute_unprepared(CREATE_SCHEMA).await?;
    tx.execute_unprepared(CREATE_DERIVED_SCHEMA).await?;
    let current = CurrentProjection::empty(300, ThreadStatus::Idle);
    tx.execute_raw(statement(
        "UPDATE history_meta SET applied_write_seq=300 WHERE id=1",
        vec![],
    ))
    .await?;
    tx.execute_raw(statement(
        "INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?)",
        vec![serde_json::to_vec(&current)?.into()],
    ))
    .await?;
    for seq in 1..=258i64 {
        let (id, kind, ordinal) = if seq == 1 {
            ("text".to_owned(), ChatAtomKind::Text, 258)
        } else {
            (
                format!("work-{seq}"),
                ChatAtomKind::ToolCall,
                (seq - 1) as u64,
            )
        };
        let mut atom = active(&id, kind, ordinal);
        atom.lifecycle = ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: ChatTerminalOutcome::Completed,
        };
        atom.started_at = None;
        atom.finished_at = None;
        atom.completion_item_id = Some(id.clone());
        tx.execute_raw(statement("INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(?,?,'conversation',NULL,?,?)",
            vec![seq.into(),id.into(),b"opaque".to_vec().into(),serde_json::to_vec(&atom)?.into()])).await?;
    }
    normalize_legacy(&tx).await?;
    rebuild_batched(&tx, "db", 1).await?;
    let rows = page_rows(&tx, &ChatScope::Main, None, 100, 300, 10).await?;
    assert_eq!(rows.len(), 2);
    let ChatEntry::Item(group) = &rows[1].1 else {
        panic!("group missing")
    };
    assert_eq!(group.summary.as_ref().unwrap().member_count, 257);
    assert_eq!(group.position, Some(0));
    assert!(
        recovery(&tx).await?.len() < 1024,
        "completed members leaked into recovery"
    );
    tx.commit().await?;
    Ok(())
}

#[tokio::test]
async fn legacy_current_predecessor_blocks_already_completed_text_without_fabricated_start()
-> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let tx = db.begin().await?;
    tx.execute_unprepared(CREATE_SCHEMA).await?;
    tx.execute_unprepared(CREATE_DERIVED_SCHEMA).await?;
    let mut current = CurrentProjection::empty(3, ThreadStatus::Idle);
    let mut work = active("still-active", ChatAtomKind::Reasoning, 1);
    work.lifecycle = ChatAtomLifecycle::Active {
        started: None,
        status: ChatActiveStatus::Running,
    };
    work.started_at = None;
    current.atoms = vec![work];
    tx.execute_raw(statement(
        "UPDATE history_meta SET applied_write_seq=3 WHERE id=1",
        vec![],
    ))
    .await?;
    tx.execute_raw(statement(
        "INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?)",
        vec![serde_json::to_vec(&current)?.into()],
    ))
    .await?;
    let mut text = active("done-text", ChatAtomKind::Text, 2);
    text.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: None,
        outcome: ChatTerminalOutcome::Completed,
    };
    text.started_at = None;
    text.finished_at = None;
    text.completion_item_id = Some("done-text".into());
    tx.execute_raw(statement("INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(1,'done-text','conversation',NULL,?,?)",
        vec![b"opaque".to_vec().into(),serde_json::to_vec(&text)?.into()])).await?;
    normalize_legacy(&tx).await?;
    rebuild_batched(&tx, "db", 1).await?;
    assert!(
        page_rows(&tx, &ChatScope::Main, None, 100, 3, 10)
            .await?
            .is_empty()
    );
    let restored = super::super::current::read(&tx).await?;
    assert_eq!(restored.items.len(), 2);
    assert!(restored.items[0].admission_closed);
    assert_eq!(restored.items[0].summary.as_ref().unwrap().active_count, 1);
    assert_eq!(
        restored.items[1].outcome,
        Some(ChatTerminalOutcome::Completed)
    );
    let starts = tx
        .query_one_raw(statement(
            "SELECT COUNT(*) AS n FROM conversation_atom_facts WHERE phase='start'",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get::<i64>("", "n")?;
    assert_eq!(starts, 0);
    tx.commit().await?;
    Ok(())
}
