use super::*;
use crate::studio::storage::history::schema::legacy_timeline_types::CurrentProjection;
use sea_orm::DatabaseConnection;

const THREAD: &str = "atom-migration";

// Inspect preserved migration material, never use it as a normal current source.
async fn archived_current(db: &impl ConnectionTrait) -> Result<CurrentProjection> {
    if !completion_boundary::applied(db).await? {
        return super::super::legacy_current::read(db).await;
    }
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM completion_boundary_archive_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("archived current")?;
    let mut current: CurrentProjection =
        serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
    current.execution_present = false;
    Ok(current)
}

struct Published13;
impl MigratorTraitSelf for Published13 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
        .migrations()
        .into_iter()
        .filter(|step| {
            !matches!(
                step.name(),
                BACKGROUND_RESULTS
                    | MEMBER_READ_METADATA
                    | TIMELINE_THINKING_SUMMARY
                    | TIMELINE_BACKGROUND_TAIL
                    | SOURCE_CLASSIFICATION
                    | COMPLETION_BOUNDARY
                    | IMMUTABLE_COMPLETION_RUNS
                    | DISPLAY_SNAPSHOTS
                    | DISPLAY_OBSERVATIONS
                    | TOOL_WORK
            )
        })
        .filter(|step| !matches!(step.name(), ATOM_METADATA | TIMELINE_ITEMS))
        .collect()
    }
}

async fn source() -> Result<(tempfile::TempDir, DatabaseConnection)> {
    let dir = tempfile::tempdir()?;
    let db = super::super::super::connect(
        &dir.path().join("history.sqlite"),
        crate::studio::paths::SqliteFileMode::Create,
    )
    .await?;
    let steps = Published13
        .migrations()
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    Published13.up(&db, Some(u32::try_from(steps)?)).await?;
    assert_eq!(version(&db).await?, 13);
    Ok((dir, db))
}

async fn insert(db: &DatabaseConnection, seq: i64, id: &str, kind: &str) -> Result<Vec<u8>> {
    let payload = if kind == "turn" {
        turn_payload(TurnState::Completed(CompletedTurnState::new(
            None,
            10,
            TurnCompletion::Normal,
        )))?
    } else {
        serde_json::to_vec(&json!({
            "contract":"anywork.chat/1","type":kind,"turnId":"turn",
            "data":{"invocation":{"toolCallId":"call","name":"shell"},
                "state":{"kind":"completed"},"original":{"opaque":[0,255,37]}}
        }))?
    };
    db.execute_raw(statement(
        "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload)
         VALUES(?,?,'activity',?,?)",
        vec![
            seq.into(),
            id.into(),
            ChatKey::new("turn", "turn")?.as_str().into(),
            payload.clone().into(),
        ],
    ))
    .await?;
    Ok(payload)
}

fn turn_payload(state: TurnState) -> Result<Vec<u8>> {
    let item = ThreadItem::new(
        "turn-receipt".into(),
        THREAD.into(),
        "turn".into(),
        1,
        1,
        1,
        10,
        ThreadItemState::Turn(ThreadTurnItem::new(state)),
    );
    Ok(
        crate::studio::runtime::chat_item::completion_draft(&item, 5, "fixture")?
            .payload
            .to_vec(),
    )
}

async fn seed_active_members(db: &DatabaseConnection, turn: &str) -> Result<CurrentProjection> {
    use crate::studio::storage::history::schema::legacy_current::{
        CurrentContentWrite, CurrentEntryChange, CurrentEntryWrite, LegacyCurrent,
    };
    use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
    use std::sync::Arc;
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    let mut current = CurrentProjection::empty(0, ThreadStatus::Running);
    current.collections.push(CurrentCollectionRef {
        database_id: database.clone(),
        collection: "members".into(),
        revision: 0,
    });
    let mut contents = Vec::new();
    let mut changes = Vec::new();
    for part in 1..=5_i64 {
        let id = format!("live-{part}");
        db.execute_raw(statement(
            "INSERT INTO history_items VALUES(?,? ,?,'text',1,'active',1,2,'{}',0)",
            vec![part.into(), id.clone().into(), turn.into()],
        ))
        .await?;
        let mut bodies = Vec::new();
        for index in 0..if part == 5 { 2 } else { 1 } {
            let key = format!("part.outputText.{index}");
            let reference = ContentRef {
                database_id: database.clone(),
                target: ContentTarget::Body {
                    owner: ContentOwner::Item {
                        item_id: id.clone(),
                    },
                    key: key.clone(),
                },
            };
            let bytes: Arc<[u8]> = format!("原始活动内容 {part}/{index} 🦀")
                .into_bytes()
                .into();
            bodies.push(json!({"reference":reference,"byteLength":bytes.len(),"generation":1}));
            if current.previews.len() < 4 {
                current.previews.push(CurrentContentPreview {
                    id: id.clone(),
                    role: CurrentContentRole::Response,
                    text_channel: Some(ThreadTextChannel::Final),
                    text: "window".into(),
                    reference: reference.clone(),
                });
            }
            contents.push(CurrentContentWrite {
                content: Arc::new(ChatContent {
                    descriptor: ContentDescriptor {
                        key: ChatContentKey {
                            owner: ChatKey::new("item", &id)?,
                            key,
                        },
                        byte_length: bytes.len() as u64,
                        generation: 1,
                        media_type: None,
                    },
                    data: ContentData::Bytes(bytes),
                }),
                sealed: false,
            });
        }
        changes.push(CurrentEntryChange::Put(CurrentEntryWrite {
            collection: "members".into(),
            position: part,
            entry_id: id,
            payload: serde_json::to_vec(&bodies)?.into(),
        }));
    }
    crate::studio::storage::history::schema::legacy_current::apply(
        db,
        0,
        &LegacyCurrent::new(
            crate::studio::storage::history::schema::legacy_timeline_types::FrozenCurrentProjection::new(current.clone()),
            changes.into(),
            contents.into(),
        ),
    )
    .await?;
    Ok(current)
}

async fn active_originals(db: &DatabaseConnection) -> Result<Vec<String>> {
    let entries = if completion_boundary::applied(db).await? {
        "completion_boundary_archive_view_entries"
    } else {
        "conversation_view_entries"
    };
    let manifests = if completion_boundary::applied(db).await? {
        "(SELECT * FROM conversation_contents UNION ALL SELECT * FROM completion_boundary_archive_contents)"
    } else {
        "conversation_contents"
    };
    let chunks = if completion_boundary::applied(db).await? {
        "(SELECT * FROM conversation_content_chunks UNION ALL SELECT * FROM completion_boundary_archive_content_chunks)"
    } else {
        "conversation_content_chunks"
    };
    db.query_all_raw(statement(
        &format!(
            "SELECT json_array(owner_key,content_key,hex(payload)) AS original FROM {manifests}
         UNION ALL SELECT json_array(owner_key,content_key,byte_offset,hex(data)) FROM {chunks}
         UNION ALL SELECT json_array(collection,position,entry_id,hex(payload)) FROM {entries}
         ORDER BY original"
        ),
        vec![],
    ))
    .await?
    .into_iter()
    .map(|row| row.try_get("", "original").map_err(Into::into))
    .collect()
}

#[tokio::test]
async fn complete_member_directory_survives_four_preview_limit_and_rolls_back_over_budget()
-> Result<()> {
    let (_dir, db) = source().await?;
    let old = seed_active_members(&db, "live-turn").await?;
    assert_eq!(old.previews.len(), 4);
    let originals = active_originals(&db).await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    let migrated = archived_current(&db).await?;
    assert_eq!(migrated.atoms.len(), 5);
    for part in 1..=5 {
        let atom = migrated
            .atoms
            .iter()
            .find(|atom| atom.id == format!("live-{part}"))
            .unwrap();
        assert_eq!(
            atom.source,
            ChatSourceId::ForegroundTurn {
                turn_id: "live-turn".into()
            }
        );
        assert_eq!(atom.source_order, Some(part));
        assert_eq!(atom.contents.len(), if part == 5 { 2 } else { 1 });
        for (index, content) in atom.contents.iter().enumerate() {
            assert_eq!(
                content.reference.target,
                ContentTarget::Body {
                    owner: ContentOwner::Item {
                        item_id: atom.id.clone()
                    },
                    key: format!("part.outputText.{index}")
                }
            );
        }
    }
    assert_eq!(
        active_originals(&db).await?,
        originals,
        "all body bytes, manifests and legacy member directory remain intact"
    );

    let (_dir, db) = source().await?;
    let old = seed_active_members(&db, "live-turn").await?;
    db.execute_unprepared("DELETE FROM history_items WHERE item_id='live-5'")
        .await?;
    let originals = active_originals(&db).await?;
    let error = prepare(&db, THREAD, Preparation::Schema, None)
        .await
        .unwrap_err();
    assert!(
        format!("{error:#}").contains("canonical checkpoint"),
        "{error:#}"
    );
    assert_eq!(version(&db).await?, 13);
    validate_source(&db).await?;
    assert_eq!(active_originals(&db).await?, originals);
    assert_eq!(archived_current(&db).await?, old);

    let (_dir, db) = source().await?;
    let old = seed_active_members(&db, &"t".repeat(CHAT_BATCH_MAX_BYTES as usize)).await?;
    let originals = active_originals(&db).await?;
    let error = prepare(&db, THREAD, Preparation::Schema, None)
        .await
        .unwrap_err();
    assert!(format!("{error:#}").contains("budget"), "{error:#}");
    assert_eq!(version(&db).await?, 13);
    validate_source(&db).await?;
    assert_eq!(active_originals(&db).await?, originals);
    assert_eq!(archived_current(&db).await?, old);
    Ok(())
}

#[tokio::test]
async fn real_turn_outcome_payloads_backfill_completed_failed_and_cancelled_sources() -> Result<()>
{
    for (state, expected) in [
        (
            TurnState::Completed(CompletedTurnState::new(None, 10, TurnCompletion::Normal)),
            ChatTerminalOutcome::Completed,
        ),
        (
            TurnState::Failed(FailedTurnState::new(
                None,
                10,
                TurnFailure::permanent(TurnFailureCategory::Internal, "original failure"),
            )),
            ChatTerminalOutcome::Failed,
        ),
        (
            TurnState::Cancelled(CancelledTurnState::new(
                None,
                9,
                10,
                TurnCancellationCause::UserRequested,
            )),
            ChatTerminalOutcome::Cancelled,
        ),
    ] {
        let (_dir, db) = source().await?;
        insert(&db, 1, "turn-receipt", "turn").await?;
        let payload = turn_payload(state)?;
        let frozen: Json = serde_json::from_slice(&payload)?;
        assert!(frozen.pointer("/data/state").is_none());
        assert!(frozen.pointer("/data/outcome/kind").is_some());
        db.execute_raw(statement(
            "UPDATE conversation_items SET payload=? WHERE item_id='turn-receipt'",
            vec![payload.clone().into()],
        ))
        .await?;
        db.execute_unprepared("UPDATE history_meta SET applied_write_seq=5")
            .await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let source = ChatSourceId::ForegroundTurn {
            turn_id: "turn".into(),
        };
        assert_eq!(
            sources::read(&db, std::slice::from_ref(&source), 4).await?[0].lifecycle,
            ChatSourceLifecycle::Unknown
        );
        let state = sources::read(&db, &[source], 5).await?.remove(0);
        assert_eq!(
            state.lifecycle,
            ChatSourceLifecycle::Ended { outcome: expected }
        );
        assert_eq!((state.started, state.ended), (None, None));
        assert_eq!(
            db.query_one_raw(statement(
                "SELECT payload FROM conversation_items WHERE item_id='turn-receipt'",
                vec![]
            ))
            .await?
            .unwrap()
            .try_get::<Vec<u8>>("", "payload")?,
            payload
        );
    }
    Ok(())
}

#[tokio::test]
async fn pending_timeline_fact_output_is_rejected_without_erasing_originals() -> Result<()> {
    let (_directory, db) = source().await?;
    let payload = insert(&db, 1, "original-tool", "tool").await?;
    // A table with the next step's output name is not proof of a completed migration.
    // Even an unrecognized shape with original bytes must be preserved, never adopted/dropped.
    db.execute_unprepared(
        "CREATE TABLE conversation_atom_facts(original BLOB NOT NULL);
         INSERT INTO conversation_atom_facts VALUES(X'00ff01')",
    )
    .await?;
    for _ in 0..2 {
        let failure = prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .expect_err("pending migration cannot adopt its pre-existing output");
        assert!(
            format!("{failure:#}").contains(
                "pending timeline migration has pre-existing output table conversation_atom_facts"
            ),
            "{failure:#}"
        );
        assert_eq!(version(&db).await?, 13);
        let original = db
            .query_one_raw(statement(
                "SELECT original FROM conversation_atom_facts",
                vec![],
            ))
            .await?
            .context("preserved conflicting output")?;
        assert_eq!(original.try_get::<Vec<u8>>("", "original")?, [0, 255, 1]);
        let completion = db
            .query_one_raw(statement(
                "SELECT payload FROM conversation_items WHERE item_id='original-tool'",
                vec![],
            ))
            .await?
            .context("preserved original completion")?;
        assert_eq!(completion.try_get::<Vec<u8>>("", "payload")?, payload);
        let boundary = db
            .query_one_raw(statement(
                "SELECT
                   (SELECT COUNT(*) FROM pragma_table_info('conversation_items')
                    WHERE name='metadata') AS metadata_columns,
                   (SELECT COUNT(*) FROM seaql_migrations WHERE version IN (?,?)) AS completed",
                vec![ATOM_METADATA.into(), TIMELINE_ITEMS.into()],
            ))
            .await?
            .context("unmodified migration boundary")?;
        assert_eq!(boundary.try_get::<i64>("", "metadata_columns")?, 0);
        assert_eq!(boundary.try_get::<i64>("", "completed")?, 0);
    }
    Ok(())
}

#[tokio::test]
async fn migration_preserves_completion_bytes_seq_parent_and_content_owners() -> Result<()> {
    let (_dir, db) = source().await?;
    let payload = insert(&db, 1, "tool", "tool").await?;
    let inference = insert(&db, 2, "diagnostic", "inference").await?;
    // Independent original execution/attachment/tool bytes must not be normalized by this step.
    db.execute_unprepared(
        "INSERT INTO history_items VALUES(7,'tool','turn','tool',1,'terminal',1,2,'{\"opaque\":true}',0);
         INSERT INTO history_items VALUES(8,'diagnostic','turn','inference',1,'terminal',1,2,'{\"diagnostic\":\"original\"}',0);
         INSERT INTO history_tool_tasks VALUES('call',1,'{\"originalTask\":true}',NULL,0);"
    ).await?;
    let owner = ChatKey::new("item", "tool")?;
    let manifest =
        br#"{"byteLength":4,"generation":7,"mediaType":"application/octet-stream","sealed":true}"#
            .to_vec();
    let body = vec![0u8, 255, 128, 39];
    db.execute_raw(statement(
        "INSERT INTO conversation_contents VALUES(?,'tool.result',?)",
        vec![owner.as_str().into(), manifest.clone().into()],
    ))
    .await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_content_chunks VALUES(?,'tool.result',0,?)",
        vec![owner.as_str().into(), body.clone().into()],
    ))
    .await?;

    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
    let tool = conversation::read_item(&db, "tool").await?;
    assert_eq!(
        tool.unwrap()
            .contents
            .values()
            .next()
            .unwrap()
            .data
            .range(0, 4)?
            .as_bytes(),
        body
    );
    for (id, seq, original, class) in [
        ("tool", 1_i64, payload, "conversation"),
        ("diagnostic", 2, inference, "diagnostic"),
    ] {
        let row = db.query_one_raw(statement(
            "SELECT seq,parent_id,payload,metadata,query_class FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        )).await?.unwrap();
        assert_eq!(row.try_get::<i64>("", "seq")?, seq);
        assert_eq!(
            row.try_get::<String>("", "parent_id")?,
            ChatKey::new("turn", "turn")?.as_str()
        );
        assert_eq!(row.try_get::<Vec<u8>>("", "payload")?, original);
        assert_eq!(row.try_get::<String>("", "query_class")?, class);
        let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        assert_eq!(atom.completion_item_id.as_deref(), Some(id));
        assert!(atom.source_state.is_none());
        assert!(
            serde_json::from_slice::<Json>(&row.try_get::<Vec<u8>>("", "metadata")?)?
                .get("sourceState")
                .is_none(),
            "read-cut annotation is not frozen into metadata"
        );
        assert_eq!(atom.completion_seq, None);
        assert!(atom.payload.is_none());
        assert_eq!(atom.source_order, Some(if id == "tool" { 7 } else { 8 }));
        assert!(matches!(
            atom.lifecycle,
            ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                ..
            }
        ));
        if id == "tool" {
            assert_eq!(
                atom.contents[0].reference.target,
                ContentTarget::Body {
                    owner: ContentOwner::Item { item_id: id.into() },
                    key: "tool.result".into()
                }
            );
        }
    }
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_contents WHERE owner_key=?",
            vec![owner.as_str().into()],
        ))
        .await?
        .unwrap();
    assert_eq!(row.try_get::<Vec<u8>>("", "payload")?, manifest);
    let row = db
        .query_one_raw(statement(
            "SELECT data FROM conversation_content_chunks WHERE owner_key=?",
            vec![owner.as_str().into()],
        ))
        .await?
        .unwrap();
    assert_eq!(row.try_get::<Vec<u8>>("", "data")?, body);
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT payload FROM history_items WHERE item_id='diagnostic'",
            vec![]
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "payload")?,
        "{\"diagnostic\":\"original\"}"
    );
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT task_payload FROM history_tool_tasks WHERE call_id='call'",
            vec![]
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "task_payload")?,
        "{\"originalTask\":true}"
    );
    Ok(())
}

#[tokio::test]
async fn unattributable_active_preview_rolls_back_ddl_data_marker_and_receipt() -> Result<()> {
    let (_dir, db) = source().await?;
    let original = insert(&db, 1, "old", "thinking").await?;
    let mut current = CurrentProjection::empty(0, ThreadStatus::Running);
    current.previews.push(CurrentContentPreview {
        id: "unattributable".into(),
        role: CurrentContentRole::Response,
        text_channel: None,
        reference: ContentRef {
            database_id: "unused".into(),
            target: ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: "unattributable".into(),
                },
                key: "body".into(),
            },
        },
        text: "bounded preview".into(),
    });
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    current.previews[0].reference.database_id = database;
    let current_bytes = serde_json::to_vec(&current)?;
    db.execute_raw(statement(
        "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
        vec![current_bytes.clone().into()],
    ))
    .await?;
    assert!(
        prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .is_err()
    );
    assert_eq!(version(&db).await?, 13);
    validate_source(&db).await?;
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT payload FROM conversation_items WHERE item_id='old'",
            vec![]
        ))
        .await?
        .unwrap()
        .try_get::<Vec<u8>>("", "payload")?,
        original
    );
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT query_class FROM conversation_items WHERE item_id='old'",
            vec![]
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "query_class")?,
        "activity"
    );
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![]
        ))
        .await?
        .unwrap()
        .try_get::<Vec<u8>>("", "payload")?,
        current_bytes
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![ATOM_METADATA.into()]
        ))
        .await?
        .is_none()
    );
    Ok(())
}

#[tokio::test]
async fn terminal_source_backfill_keeps_unknown_positions_and_requires_real_terminal_evidence()
-> Result<()> {
    let (_dir, db) = source().await?;
    insert(&db, 1, "thought", "thinking").await?;
    let receipt = insert(&db, 2, "turn-receipt", "turn").await?;
    db.execute_unprepared("UPDATE conversation_items SET payload=CAST('{\"contract\":\"anywork.chat/1\",\"type\":\"thinking\",\"turnId\":\"turn\",\"data\":{\"lifecycle\":{\"kind\":\"failed\"}}}' AS BLOB) WHERE item_id='thought'").await?;
    // Observation of an ended Turn proves its lifecycle, not when it started/ended.
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=5")
        .await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    let origin = ChatSourceId::ForegroundTurn {
        turn_id: "turn".into(),
    };
    let at4 = sources::read(&db, std::slice::from_ref(&origin), 4).await?;
    assert_eq!(at4[0].lifecycle, ChatSourceLifecycle::Unknown);
    let at5 = sources::read(&db, &[origin], 5).await?;
    assert_eq!(
        at5[0].lifecycle,
        ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Completed
        }
    );
    assert_eq!((at5[0].started, at5[0].ended), (None, None));
    let row = db
        .query_one_raw(statement(
            "SELECT payload,metadata FROM conversation_items WHERE item_id='turn-receipt'",
            vec![],
        ))
        .await?
        .unwrap();
    assert_eq!(row.try_get::<Vec<u8>>("", "payload")?, receipt);
    let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
    assert_eq!(
        atom.source_order, None,
        "a completion seq is not source order evidence"
    );
    let row = db
        .query_one_raw(statement(
            "SELECT metadata FROM conversation_items WHERE item_id='thought'",
            vec![],
        ))
        .await?
        .unwrap();
    let atom: ChatAtom = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
    assert!(matches!(
        atom.lifecycle,
        ChatAtomLifecycle::Terminal {
            outcome: ChatTerminalOutcome::Failed,
            started: None,
            ended: None
        }
    ));

    let (_dir, db) = source().await?;
    insert(&db, 1, "unsupported-turn", "turn").await?;
    db.execute_unprepared("UPDATE conversation_items SET payload=CAST('{\"contract\":\"anywork.chat/1\",\"type\":\"turn\",\"turnId\":\"turn\",\"data\":{\"unsupported\":true}}' AS BLOB)").await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert_eq!(
        sources::read(
            &db,
            &[ChatSourceId::ForegroundTurn {
                turn_id: "turn".into()
            }],
            99
        )
        .await?[0]
            .lifecycle,
        ChatSourceLifecycle::Unknown
    );
    Ok(())
}
