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
        page_rows(&db, &ChatScope::Main, None, 100, 1, 1, &[])
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
        page_rows(&db, &ChatScope::Main, None, 100, 2, 1, &[])
            .await?
            .is_empty()
    );
    projection.observe(&active("text", ChatAtomKind::Text, 3), None)?;
    persist(&db, &mut projection, 3).await?;
    let before = page_rows(&db, &ChatScope::Main, None, 100, 3, 1, &[]).await?;
    assert_eq!(before.len(), 1);
    let ChatEntry::Item(item) = &before[0].1 else {
        panic!("Main returned a member");
    };
    assert_eq!(item.kind, TimelineItemKind::WorkGroup);
    assert_eq!(item.summary.as_ref().unwrap().member_count, 1);
    assert!(item.payload.is_none());
    assert_eq!(item.outcome, None);
    // Replaying identical history must preserve the first committing effect,
    // not overwrite it with the sequence of a later idempotent call.
    save_item(&db, "db", item, 99).await?;
    let committed = db
        .query_one_raw(statement(
            "SELECT commit_seq,metadata FROM timeline_items WHERE item_id=?",
            vec![item.id.clone().into()],
        ))
        .await?
        .unwrap();
    assert_eq!(committed.try_get::<i64>("", "commit_seq")?, 3);
    let original_metadata: Vec<u8> = committed.try_get("", "metadata")?;
    let mut changed = item.as_ref().clone();
    changed.position = None;
    assert!(save_item(&db, "db", &changed, 100).await.is_err());
    changed = item.as_ref().clone();
    changed.summary.as_mut().unwrap().member_count += 1;
    assert!(save_item(&db, "db", &changed, 100).await.is_err());
    let unchanged = db
        .query_one_raw(statement(
            "SELECT commit_seq,metadata FROM timeline_items WHERE item_id=?",
            vec![item.id.clone().into()],
        ))
        .await?
        .unwrap();
    assert_eq!(unchanged.try_get::<i64>("", "commit_seq")?, 3);
    assert_eq!(
        unchanged.try_get::<Vec<u8>>("", "metadata")?,
        original_metadata
    );
    let members = page_rows(
        &db,
        &ChatScope::GroupMembers {
            reference: reference.clone(),
        },
        None,
        100,
        3,
        1,
        &[],
    )
    .await?;
    assert!(
        matches!(&members[0].1,ChatEntry::Atom(atom) if atom.completion_item_id.as_deref()==Some("original-completion") && matches!(atom.payload,Some(PayloadData::Deferred{..})))
    );
    let mut wrong = reference.clone();
    wrong.database_id = "another".into();
    assert!(
        validate_members_ref(&db, "db", &generation(&db).await?, &wrong)
            .await
            .is_err()
    );
    wrong = reference;
    wrong.projection_version += 1;
    assert!(
        validate_members_ref(&db, "db", &generation(&db).await?, &wrong)
            .await
            .is_err()
    );
    let tx = db.begin().await?;
    tx.execute_unprepared("DELETE FROM timeline_items;DELETE FROM timeline_item_members;DELETE FROM timeline_projection_state;").await?;
    rebuild(&tx, "db").await?;
    tx.commit().await?;
    let after = page_rows(&db, &ChatScope::Main, None, 100, 3, 1, &[]).await?;
    assert_eq!(logical(before.clone()), logical(after));
    let head = read_state(&db).await?.ok_or(ProjectionFault)?;
    let mut restored = TimelineProjection::new("db".into(), head.generation, head.next_position);
    restored.restore_recovery(&head.recovery)?;
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
    let before_failure = page_rows(&db, &ChatScope::Main, None, 100, 3, 1, &[]).await?;
    let before_generation = generation(&db).await?;
    let tx = db.begin().await?;
    tx.execute_unprepared("CREATE TRIGGER reject_timeline_rebuild BEFORE INSERT ON timeline_items BEGIN SELECT RAISE(ABORT,'injected rebuild failure'); END;").await?;
    assert!(rebuild(&tx, "db").await.is_err());
    tx.rollback().await?;
    assert_eq!(
        before_failure,
        page_rows(&db, &ChatScope::Main, None, 100, 3, 1, &[]).await?
    );
    assert_eq!(before_generation, generation(&db).await?);
    Ok(())
}

#[tokio::test]
async fn member_terminal_upsert_preserves_identity_and_rejects_regression() -> Result<()> {
    use pl_core::chat::{
        ChatContent, ChatContentKey, ChatContents, ChatDraft, ChatItem, ChatKey, ContentData,
        ContentDescriptor,
    };
    use std::sync::Arc;

    // Cover an active-to-terminal upsert and a terminal-only admission with no
    // completion reference. NULL completion is not evidence that a row is active.
    for completion in [Some("completion"), None] {
        let (_directory, db) = super::super::tests::fixture().await?;
        db.execute_unprepared(CREATE_SCHEMA).await?;
        db.execute_unprepared(CREATE_DERIVED_SCHEMA).await?;
        let mut projection = TimelineProjection::new("db".into(), "member-write".into(), 0);
        let start = active("member", ChatAtomKind::Reasoning, 1);
        projection.observe(&start, None)?;
        let active_update = projection.take_update()?;
        let scope = ChatScope::GroupMembers {
            reference: projection.current_items()[0].members.clone().unwrap(),
        };
        assert!(start.contents.is_empty());
        let body: Arc<[u8]> = Arc::from(b"saved reasoning summary".as_slice());
        let owner_id = completion.unwrap_or(&start.id);
        let key = ChatContentKey {
            owner: ChatKey::new("item", owner_id)?,
            key: "body".into(),
        };
        let content = Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: key.clone(),
                byte_length: body.len() as u64,
                generation: 2,
                media_type: None,
            },
            data: ContentData::Bytes(body.clone()),
        });
        let mut mutable = start.clone();
        mutable.lifecycle = ChatAtomLifecycle::Active {
            started: Some(at(1)),
            status: ChatActiveStatus::Waiting,
        };
        mutable.delivery = ChatDeliveryKind::BackgroundHandoff;
        mutable.content_present = Some(true);
        mutable.contents.push(ChatAtomContent {
            role: ChatContentRole::ReasoningSummary,
            reference: ContentRef {
                database_id: "db".into(),
                target: ContentTarget::Body {
                    owner: ContentOwner::Item {
                        item_id: owner_id.into(),
                    },
                    key: key.key.clone(),
                },
            },
        });
        projection.observe(&mutable, None)?;
        let mutable_update = projection.take_update()?;
        assert!(
            mutable_update.facts().is_empty(),
            "observe is not a second start"
        );
        assert_eq!(mutable_update.members().len(), 1);

        if completion.is_some() {
            for (update, effect) in [(&active_update, 1), (&mutable_update, 2)] {
                // Both initial admission and updates must reject each forged
                // completion field independently while the lifecycle is Active.
                for (field, value) in [
                    ("completionItemId", serde_json::json!("forged-completion")),
                    ("completionSeq", serde_json::json!(99)),
                ] {
                    let mut changed = serde_json::to_value(update)?;
                    changed["members"][0]["atom"][field] = value;
                    let changed = serde_json::from_value(changed)?;
                    assert!(
                        save_changes(&db, "db", &changed, &[], effect, false)
                            .await
                            .is_err(),
                        "active admission/update accepted {field}"
                    );
                }
                let tx = db.begin().await?;
                if effect == 2 {
                    super::super::content::write_content(&tx, &content, false).await?;
                }
                save_update(&tx, "db", update, &[], effect, true).await?;
                tx.commit().await?;
            }
            assert_eq!(read_state(&db).await?.unwrap().source_effect_seq, 2);
            assert_eq!(
                page_rows(&db, &scope, None, 100, 1, 10, std::slice::from_ref(&start)).await?,
                vec![(0, ChatEntry::Atom(Box::new(start.clone())))],
                "the effect-2 head must not leak contents or Waiting into cut 1"
            );
            assert_eq!(
                page_rows(&db, &scope, None, 100, 2, 10, &[]).await?,
                vec![(0, ChatEntry::Atom(Box::new(mutable.clone())))],
                "cut 2 must retain the admitted member's identity, order, active status and original body reference"
            );
            let facts = db
                .query_all_raw(statement(
                    "SELECT effect_seq,phase,metadata FROM conversation_atom_facts WHERE atom_id='member'",
                    vec![],
                ))
                .await?;
            assert_eq!(
                facts.len(),
                1,
                "active refresh must not allocate another fact"
            );
            assert_eq!(facts[0].try_get::<i64>("", "effect_seq")?, 1);
            assert_eq!(facts[0].try_get::<String>("", "phase")?, "start");
            assert_eq!(
                facts[0].try_get::<Vec<u8>>("", "metadata")?,
                serde_json::to_vec(&start)?,
                "the canonical start must not become the mutable head"
            );
            for (path, value) in [
                ("/id", serde_json::json!("another-member")),
                (
                    "/source",
                    serde_json::to_value(ChatSourceId::ForegroundTurn {
                        turn_id: "another-turn".into(),
                    })?,
                ),
                ("/sourceOrder", serde_json::json!(99)),
                ("/kind", serde_json::to_value(ChatAtomKind::ToolCall)?),
                ("/turnId", serde_json::json!("another-turn")),
                ("/attemptId", serde_json::json!("another-attempt")),
                (
                    "/tool",
                    serde_json::to_value(ChatToolIdentity {
                        call_id: "another-call".into(),
                        name: "exec".into(),
                    })?,
                ),
                (
                    "/textChannel",
                    serde_json::to_value(ThreadTextChannel::Commentary)?,
                ),
                ("/startedAt", serde_json::json!(99)),
                ("/lifecycle/started/effectSeq", serde_json::json!(99)),
                ("/lifecycle/started/suborder", serde_json::json!(1)),
            ] {
                let mut changed = serde_json::to_value(&mutable_update)?;
                *changed["members"][0]["atom"].pointer_mut(path).unwrap() = value;
                let changed = serde_json::from_value(changed)?;
                assert!(
                    save_changes(&db, "db", &changed, &[], 3, false)
                        .await
                        .is_err(),
                    "active member identity changed at {path}"
                );
            }
        }

        let mut terminal = mutable.clone();
        terminal.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(at(1)),
            ended: Some(at(3)),
            outcome: ChatTerminalOutcome::Completed,
        };
        terminal.completion_item_id = completion.map(str::to_owned);
        terminal.completion_seq = completion.map(|_| 1);
        terminal.finished_at = Some(3);
        projection.complete(terminal.clone(), 1, None)?;
        let terminal_update = projection.take_update()?;
        assert!(
            save_changes(&db, "db", &terminal_update, &[], 3, false)
                .await
                .is_err(),
            "terminal insert/upsert requires its canonical terminal"
        );
        save_fact(&db, &terminal, 3).await?;
        let mut changed = serde_json::to_value(&terminal_update)?;
        changed["members"][0]["atom"]["finishedAt"] = 99.into();
        let changed = serde_json::from_value(changed)?;
        assert!(
            save_changes(&db, "db", &changed, &[], 3, false)
                .await
                .is_err(),
            "terminal insert/upsert must match the same atom's canonical metadata"
        );
        let active_rows = db
            .query_all_raw(statement(
                "SELECT member_id,completion_item_id,admitted_effect,metadata
                 FROM timeline_item_members",
                vec![],
            ))
            .await?;
        assert_eq!(active_rows.len(), usize::from(completion.is_some()));
        if completion.is_some() {
            assert_eq!(active_rows[0].try_get::<String>("", "member_id")?, "member");
            assert_eq!(
                active_rows[0].try_get::<Option<String>>("", "completion_item_id")?,
                None
            );
            assert_eq!(active_rows[0].try_get::<i64>("", "admitted_effect")?, 1);
            assert_eq!(
                active_rows[0].try_get::<Vec<u8>>("", "metadata")?,
                serde_json::to_vec(&mutable)?,
                "accepted mutable metadata/contents/status must survive rejected writes"
            );
        }
        let tx = db.begin().await?;
        let terminal_payload = if let Some(id) = completion {
            // Publish a real completion and seal the same Item-owned body. The
            // member reader may defer this original payload, never invent one.
            let payload: Arc<[u8]> = serde_json::to_vec(&serde_json::json!({
                "contract": "anywork.chat/1",
                "type": "thinking",
                "data": {
                    "content": mutable.contents[0].reference,
                    "byteLength": body.len(),
                },
            }))?
            .into();
            let mut draft = ChatDraft::new(id, "conversation", payload.clone());
            draft.parent_id = Some(ChatKey::new("turn", "turn")?);
            let mut metadata = terminal.clone();
            metadata.completion_seq = None;
            draft.metadata = serde_json::to_vec(&metadata)?.into();
            draft.contents = Arc::new(ChatContents::from([(key, content)]));
            let record = ChatItem::complete(draft, 1);
            super::super::append_records(&tx, [&record], true).await?;
            Some(PayloadData::Deferred {
                reference: ContentRef {
                    database_id: "db".into(),
                    target: ContentTarget::ItemPayload { item_id: id.into() },
                },
                byte_length: payload.len() as u64,
            })
        } else {
            super::super::content::write_content(&tx, &content, false).await?;
            None
        };
        let mut saved_update = serde_json::to_value(&terminal_update)?;
        if let Some(PayloadData::Deferred { byte_length, .. }) = &terminal_payload {
            saved_update["members"][0]["payload_bytes"] = (*byte_length).into();
        }
        let terminal_update: TimelineUpdate = serde_json::from_value(saved_update)?;
        save_update(&tx, "db", &terminal_update, &[], 3, true).await?;
        tx.commit().await?;
        let mut delivered_terminal = terminal.clone();
        delivered_terminal.payload = terminal_payload;
        let terminal_rows = vec![(0, ChatEntry::Atom(Box::new(delivered_terminal)))];
        for cut in [1, 2] {
            let expected = if completion.is_some() {
                vec![(
                    0,
                    ChatEntry::Atom(Box::new(if cut == 1 {
                        start.clone()
                    } else {
                        mutable.clone()
                    })),
                )]
            } else {
                Vec::new()
            };
            assert_eq!(
                page_rows(
                    &db,
                    &scope,
                    None,
                    100,
                    cut,
                    10,
                    std::slice::from_ref(if cut == 1 { &start } else { &mutable })
                )
                .await?,
                expected,
                "cut {cut} must not expose the future terminal, completion or payload"
            );
        }
        assert_eq!(
            page_rows(&db, &scope, None, 100, 3, 10, &[]).await?,
            terminal_rows,
            "the terminal cut must return the exact terminal and original deferred payload"
        );
        let tx = db.begin().await?;
        save_update(&tx, "db", &terminal_update, &[], 4, true).await?;
        tx.commit().await?;
        assert_eq!(
            page_rows(&db, &scope, None, 100, 3, 10, &[]).await?,
            terminal_rows,
            "a later identical upsert must preserve the earlier canonical terminal cut"
        );
        let admitted_effect = if completion.is_some() { 1 } else { 3 };
        let before = db
            .query_one_raw(statement(
                "SELECT member_id,completion_item_id,admitted_effect,metadata
                 FROM timeline_item_members",
                vec![],
            ))
            .await?
            .unwrap();
        let original: Vec<u8> = before.try_get("", "metadata")?;
        assert_eq!(before.try_get::<String>("", "member_id")?, "member");
        assert_eq!(
            before.try_get::<i64>("", "admitted_effect")?,
            admitted_effect
        );
        assert_eq!(
            before.try_get::<Option<String>>("", "completion_item_id")?,
            completion.map(str::to_owned)
        );
        assert_eq!(original, serde_json::to_vec(&terminal)?);
        for update in [&active_update, &mutable_update] {
            assert!(
                save_changes(&db, "db", update, &[], 5, false)
                    .await
                    .is_err(),
                "terminal cannot regress even without a completion reference"
            );
        }
        for (path, value) in [
            ("/id", serde_json::json!("another-member")),
            ("/finishedAt", serde_json::json!(99)),
            (
                "/lifecycle/outcome",
                serde_json::to_value(ChatTerminalOutcome::Failed)?,
            ),
            ("/completionItemId", serde_json::json!("another-completion")),
            ("/completionSeq", serde_json::json!(99)),
        ] {
            let mut changed = serde_json::to_value(&terminal_update)?;
            *changed["members"][0]["atom"].pointer_mut(path).unwrap() = value;
            let changed = serde_json::from_value(changed)?;
            assert!(
                save_changes(&db, "db", &changed, &[], 5, false)
                    .await
                    .is_err(),
                "terminal metadata/completion changed at {path}"
            );
        }
        let after = db
            .query_one_raw(statement(
                "SELECT member_id,completion_item_id,admitted_effect,metadata
                 FROM timeline_item_members",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(after.try_get::<String>("", "member_id")?, "member");
        assert_eq!(
            after.try_get::<Option<String>>("", "completion_item_id")?,
            completion.map(str::to_owned)
        );
        assert_eq!(
            after.try_get::<i64>("", "admitted_effect")?,
            admitted_effect
        );
        assert_eq!(after.try_get::<Vec<u8>>("", "metadata")?, original);
        let facts = db
            .query_all_raw(statement(
                "SELECT effect_seq,phase,metadata FROM conversation_atom_facts
                 WHERE atom_id='member' ORDER BY effect_seq,suborder",
                vec![],
            ))
            .await?
            .iter()
            .map(|row| {
                Ok((
                    row.try_get::<i64>("", "effect_seq")?,
                    row.try_get::<String>("", "phase")?,
                    row.try_get::<Vec<u8>>("", "metadata")?,
                ))
            })
            .collect::<Result<Vec<_>>>()?;
        let mut expected_facts = Vec::new();
        if completion.is_some() {
            expected_facts.push((1, "start".to_owned(), serde_json::to_vec(&start)?));
        }
        expected_facts.push((3, "terminal".to_owned(), serde_json::to_vec(&terminal)?));
        assert_eq!(
            facts, expected_facts,
            "active updates and terminal retries must leave the original phase bytes and fact count unchanged"
        );

        let late = active("late-member", ChatAtomKind::ToolCall, 5);
        projection.observe(&late, None)?;
        let late_update = projection.take_update()?;
        let tx = db.begin().await?;
        save_update(&tx, "db", &late_update, &[], 5, true).await?;
        tx.commit().await?;
        assert_eq!(
            page_rows(&db, &scope, None, 100, 4, 10, &[]).await?,
            terminal_rows,
            "a member first admitted after the captured cut must remain invisible"
        );
        assert_eq!(
            page_rows(&db, &scope, None, 100, 5, 10, &[]).await?,
            vec![
                (1, ChatEntry::Atom(Box::new(late))),
                terminal_rows[0].clone()
            ],
            "new admission must preserve descending member order and the original terminal"
        );
    }
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
    let rows = page_rows(&db, &ChatScope::Main, None, 100, 3, 10, &[]).await?;
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
        &[],
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
    let rows = page_rows(&tx, &ChatScope::Main, None, 100, 300, 10, &[]).await?;
    assert_eq!(rows.len(), 2);
    let ChatEntry::Item(group) = &rows[1].1 else {
        panic!("group missing")
    };
    assert_eq!(group.summary.as_ref().unwrap().member_count, 257);
    assert_eq!(group.position, Some(0));
    assert!(
        read_state(&tx)
            .await?
            .ok_or(ProjectionFault)?
            .recovery
            .len()
            < 1024,
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
        page_rows(&tx, &ChatScope::Main, None, 100, 3, 10, &[])
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
