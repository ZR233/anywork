use super::*;
use crate::studio::storage::history::{connect, conversation};
use anyhow::Result;
use pl_core::{
    chat::{ChatContent, ChatContentKey, ChatItem, ContentData, ContentDescriptor},
    context::OpaquePayload,
    thread::{
        ThreadCheckpoint, ThreadSnapshot,
        extensions::ExtensionRecord,
        interactions::{InteractionRecord, InteractionRequest, InteractionState},
    },
};
use pl_protocol::*;
use std::sync::Arc;

const THREAD: &str = "completion-boundary-migration";
mod tool_restart;

struct Published16;
impl MigratorTraitSelf for Published16 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            bot_root: None,
            execution_identity: None,
        }
        .migrations()
        .into_iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .filter(|step| {
            !matches!(
                step.name(),
                COMPLETION_BOUNDARY
                    | IMMUTABLE_COMPLETION_RUNS
                    | DISPLAY_SNAPSHOTS
                    | DISPLAY_OBSERVATIONS
                    | TOOL_WORK
            )
        })
        .collect()
    }
}

struct Published17;
impl MigratorTraitSelf for Published17 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            bot_root: None,
            execution_identity: None,
        }
        .migrations()
        .into_iter()
        .take_while(|step| step.name() != IMMUTABLE_COMPLETION_RUNS)
        .collect()
    }
}

fn at(effect_seq: u64) -> ChatFactPosition {
    ChatFactPosition {
        effect_seq,
        suborder: 0,
    }
}

async fn seed(db: &impl ConnectionTrait) -> Result<(String, ChatAtom)> {
    use super::super::legacy_current::{CurrentContentWrite, LegacyCurrent};
    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("database")?
        .try_get("", "database_id")?;
    let item = ThreadItem::new(
        "A".into(),
        THREAD.into(),
        "turn".into(),
        1,
        1,
        1,
        2,
        ThreadItemState::Thinking(ThreadThinkingItem::new(
            vec!["完整摘要".into()],
            vec!["完整正文".into()],
            ThreadContentLifecycle::completed(2),
        )),
    );
    let mut draft = crate::studio::runtime::chat_item::completion_draft(&item, 2, &database)?;
    let mut a: ChatAtom = serde_json::from_slice(&draft.metadata)?;
    a.attempt_id = Some("attempt".into());
    a.source_order = Some(1);
    a.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(at(1)),
        ended: Some(at(2)),
        outcome: ChatTerminalOutcome::Completed,
    };
    a.completion_seq = Some(1);
    draft.metadata = serde_json::to_vec(&a)?.into();
    let record = ChatItem::complete(draft, 1, None);
    timeline::append_fixture(db, &record).await?;
    let mut start = a.clone();
    start.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(1)),
        status: ChatActiveStatus::Running,
    };
    start.completion_item_id = None;
    start.completion_seq = None;
    start.finished_at = None;
    start.contents.clear();
    start.content_present = None;
    let mut b = start.clone();
    b.id = "B".into();
    b.source_order = Some(2);
    b.lifecycle = ChatAtomLifecycle::Active {
        started: Some(at(3)),
        status: ChatActiveStatus::Running,
    };
    for (atom, phase, effect) in [(&start, "start", 1), (&a, "terminal", 2), (&b, "start", 3)] {
        db.execute_raw(statement(
            "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(?,0,?,?,?,?)",
            vec![effect.into(),atom.id.clone().into(),phase.into(),integer(atom.source_order.unwrap())?.into(),
                serde_json::to_vec(atom)?.into()],
        )).await?;
    }
    conversation::sources::apply(
        db,
        1,
        &[ChatSourceState {
            source: a.source.clone(),
            lifecycle: ChatSourceLifecycle::Active,
            started: Some(at(1)),
            ended: None,
        }],
    )
    .await?;
    let mut state = ThreadSnapshot {
        commit_sequence: 3,
        ..Default::default()
    };
    let mut plan = crate::plan_tool::state::AgentSessionPlanMachine::new(Default::default())?;
    plan.submit(crate::plan_tool::state::AgentSessionPlanSubmitCommand {
        expected_revision: 0,
        plan: "# 完整计划\n\n- 保全旧记录".into(),
        interaction_id: "plan-confirmation".into(),
        operation_id: "submit".into(),
        argument_hash: "plan-hash".into(),
        submitted_at: 1,
    });
    let plan = plan.into_state();
    state.extensions.insert(
        crate::plan_tool::PLAN_EXTENSION.into(),
        ExtensionRecord {
            revision: 1,
            payload: crate::plan_tool::encode_plan_state(&plan)?,
        },
    );
    let interaction = pl_core::tool::opaque::tool_interaction_id("question");
    state.interactions.insert(
        interaction.clone(),
        InteractionRecord {
            created_at: 1,
            updated_at: 1,
            continuation_id: None,
            revision: 1,
            state: InteractionState::Pending,
            extension_mutations: vec![],
            request: InteractionRequest {
                id: interaction,
                turn_id: "turn".into(),
                payload: OpaquePayload::new(
                    "pl.tool.user-input",
                    1,
                    serde_json::to_string(&vec![UserQuestion {
                        id: "choice".into(),
                        header: "选择".into(),
                        question: "保留吗？".into(),
                        is_other: true,
                        is_secret: false,
                        options: None,
                    }])?,
                )?,
            },
        },
    );
    let checkpoint = ThreadCheckpoint::capture(THREAD.into(), 3, state)?;
    checkpoint::write(db, &checkpoint, None, None).await?;
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=3 WHERE id=1")
        .await?;
    super::super::seed_current(db, THREAD).await?;
    let mut current = super::super::legacy_current::read(db).await?;
    let owner = ContentOwner::Item {
        item_id: "B".into(),
    };
    let reference = ContentRef {
        database_id: database.clone(),
        target: ContentTarget::Body {
            owner: owner.clone(),
            key: "body".into(),
        },
    };
    b.contents = vec![ChatAtomContent {
        role: ChatContentRole::ReasoningSummary,
        reference: reference.clone(),
    }];
    current.atoms = vec![b];
    current.previews = vec![CurrentContentPreview {
        id: "B".into(),
        role: CurrentContentRole::Reasoning,
        text_channel: None,
        text: "旧活动前缀".into(),
        reference,
    }];
    let bytes: Arc<[u8]> = Arc::from("旧活动前缀".repeat(4096).into_bytes());
    super::super::legacy_current::apply(
        db,
        3,
        &LegacyCurrent::new(
            crate::studio::storage::history::schema::legacy_timeline_types::FrozenCurrentProjection::new(current),
            Arc::from([]),
            vec![CurrentContentWrite {
                sealed: false,
                content: Arc::new(ChatContent {
                    descriptor: ContentDescriptor {
                        key: ChatContentKey {
                            owner: crate::studio::conversation_identity::content_owner_key(&owner)?,
                            key: "body".into(),
                        },
                        byte_length: bytes.len() as u64,
                        generation: 1,
                        media_type: Some("text/plain".into()),
                    },
                    data: ContentData::Bytes(bytes),
                }),
            }]
            .into(),
        ),
    )
    .await?;
    crate::studio::storage::history::schema::legacy_timeline_store::rebuild(db, &database).await?;
    Ok((database, a))
}

async fn rows(db: &impl ConnectionTrait, sql: &str) -> Result<Vec<String>> {
    db.query_all_raw(statement(sql, vec![]))
        .await?
        .into_iter()
        .map(|row| row.try_get("", "value").map_err(Into::into))
        .collect()
}

async fn originals(db: &impl ConnectionTrait) -> Result<Vec<Vec<String>>> {
    let completed = applied(db).await?;
    let mut values = vec![];
    for sql in [
        "SELECT json_array(seq,item_id,query_class,parent_id,hex(payload),hex(metadata)) AS value FROM conversation_items ORDER BY seq",
        "SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM conversation_contents ORDER BY owner_key,content_key",
        "SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM conversation_content_chunks ORDER BY owner_key,content_key,byte_offset",
        "SELECT json_array(effect_seq,suborder,atom_id,phase,fact_order,hex(metadata)) AS value FROM conversation_atom_facts ORDER BY effect_seq,suborder,atom_id,phase",
        "SELECT json_array(source_key,started_effect,started_suborder,ended_effect,ended_suborder,active_observed,ended_observed,outcome) AS value FROM conversation_sources ORDER BY source_key",
        "SELECT json_array(revision,context_revision,context_count,payload,payload_hash) AS value FROM session_checkpoint",
        "SELECT json_array(ordinal,record_id,payload,payload_hash) AS value FROM current_context ORDER BY ordinal",
        "SELECT json_array(thread_id,database_id,applied_write_seq) AS value FROM history_meta",
    ] {
        let sql = if completed {
            sql.replace("FROM conversation_contents ORDER BY", "FROM (SELECT * FROM conversation_contents UNION ALL SELECT * FROM completion_boundary_archive_contents) ORDER BY")
                .replace("FROM conversation_content_chunks ORDER BY", "FROM (SELECT * FROM conversation_content_chunks UNION ALL SELECT * FROM completion_boundary_archive_content_chunks) ORDER BY")
        } else {
            sql.to_owned()
        };
        values.push(rows(db, &sql).await?);
    }
    Ok(values)
}

#[tokio::test]
async fn nonempty_legacy_archive_rebuild_rollback_and_reopen_preserve_originals() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let db = connect(&path, crate::studio::paths::SqliteFileMode::Create).await?;
    Published16.up(&db, None).await?;
    let (database, a) = seed(&db).await?;
    let before = originals(&db).await?;
    let old_head = timeline::read_state(&db).await?.context("old head")?;
    let old_current = super::super::legacy_current::read(&db).await?;
    let old_group = old_current
        .items
        .iter()
        .find(|item| item.is_work_group())
        .context("old open group")?;
    let old_reference = old_group.members.as_ref().context("old members")?.clone();
    let old_view = rows(
        &db,
        "SELECT hex(payload) AS value FROM conversation_view_state",
    )
    .await?;
    let old_entries=rows(&db,"SELECT json_array(collection,position,entry_id,hex(payload)) AS value FROM conversation_view_entries ORDER BY collection,position,entry_id").await?;
    let old_members=rows(&db,"SELECT json_array(item_id,member_order,member_id,completion_item_id,hex(metadata)) AS value FROM timeline_item_members ORDER BY item_id,member_order").await?;
    // Failure occurs after archive DDL, while replay resolves a completion owner.
    let mut damaged = a.clone();
    damaged.completion_item_id = Some("missing".into());
    db.execute_raw(statement(
        "UPDATE conversation_atom_facts SET metadata=? WHERE atom_id='A' AND phase='terminal'",
        vec![serde_json::to_vec(&damaged)?.into()],
    ))
    .await?;
    let broken = originals(&db).await?;
    assert!(
        prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .is_err()
    );
    assert!(!applied(&db).await?);
    assert_eq!(originals(&db).await?, broken);
    assert_eq!(
        rows(
            &db,
            "SELECT hex(payload) AS value FROM conversation_view_state"
        )
        .await?,
        old_view
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_view_state'",
            vec![]
        ))
        .await?
        .is_none()
    );
    db.execute_raw(statement(
        "UPDATE conversation_atom_facts SET metadata=? WHERE atom_id='A' AND phase='terminal'",
        vec![serde_json::to_vec(&a)?.into()],
    ))
    .await?;
    Published17.up(&db, None).await?;
    assert!(applied(&db).await?);
    assert_eq!(originals(&db).await?, before);
    assert_eq!(
        rows(
            &db,
            "SELECT hex(payload) AS value FROM completion_boundary_archive_view_state"
        )
        .await?,
        old_view
    );
    assert_eq!(rows(&db,"SELECT json_array(collection,position,entry_id,hex(payload)) AS value FROM completion_boundary_archive_view_entries ORDER BY collection,position,entry_id").await?,old_entries);
    assert_eq!(rows(&db,"SELECT json_array(item_id,member_order,member_id,completion_item_id,hex(metadata)) AS value FROM completion_boundary_archive_timeline_members ORDER BY item_id,member_order").await?,old_members);
    let head = timeline::read_state(&db).await?.context("new head")?;
    assert_ne!(head.generation, old_head.generation);
    let cut: serde_json::Value = serde_json::from_slice(&head.recovery)?;
    assert!(cut.is_array());
    assert!(!String::from_utf8(head.recovery.clone())?.contains("旧活动前缀"));
    assert_ne!(head.generation, old_reference.projection_generation);
    assert!(
        rows(&db, "SELECT item_id AS value FROM timeline_items")
            .await?
            .is_empty()
    );
    assert!(
        rows(&db, "SELECT member_id AS value FROM timeline_item_members")
            .await?
            .is_empty()
    );
    let cold = conversation::completed::cold(&db).await?;
    assert!(cold.projection().previews.is_empty());
    assert!(!cold.projection().execution_present);
    assert_eq!(cold.interactions().len(), 1);
    assert!(
        cold.projection()
            .plan
            .as_ref()
            .and_then(|plan| plan.document.as_ref())
            .is_some()
    );
    assert!(
        cold.projection().atoms.is_empty(),
        "cold browsing does not restore legacy work groups"
    );
    // Ordinary reopen must neither rotate generation nor populate an open group.
    db.close().await?;
    let db = connect(&path, crate::studio::paths::SqliteFileMode::ReadWrite).await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert_eq!(
        timeline::archived_generation(&db).await?,
        old_head.generation
    );
    assert_eq!(originals(&db).await?, before);
    assert!(
        rows(&db, "SELECT name AS value FROM sqlite_schema WHERE name IN ('timeline_items','timeline_item_members','timeline_projection_state')")
            .await?
            .is_empty()
    );
    assert_eq!(
        database,
        rows(&db, "SELECT database_id AS value FROM history_meta").await?[0]
    );
    db.execute_unprepared("DROP TABLE completion_boundary_archive_timeline_members")
        .await?;
    assert!(
        prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .is_err()
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_timeline_members'",
            vec![]
        ))
        .await?
        .is_none()
    );
    assert!(applied(&db).await?);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn unfinished_completion_reference_or_incomplete_chunks_roll_back_relocation() -> Result<()> {
    for damage in [
        "UPDATE conversation_contents SET payload=CAST(json_set(CAST(payload AS TEXT),'$.sealed',json('false')) AS BLOB) WHERE owner_key='4:itemA'",
        "DELETE FROM conversation_content_chunks WHERE owner_key='4:itemB' AND byte_offset=0",
    ] {
        let dir = tempfile::tempdir()?;
        let db = connect(
            &dir.path().join("history.sqlite"),
            crate::studio::paths::SqliteFileMode::Create,
        )
        .await?;
        Published16.up(&db, None).await?;
        seed(&db).await?;
        db.execute_unprepared(damage).await?;
        let before = originals(&db).await?;
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert!(!applied(&db).await?);
        assert_eq!(originals(&db).await?, before);
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_contents'",
                vec![],
            ))
            .await?
            .is_none()
        );
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn cancelling_named_step_transaction_restores_original_keys_and_ddl() -> Result<()> {
    use sea_orm::TransactionTrait;
    let dir = tempfile::tempdir()?;
    let db = connect(
        &dir.path().join("history.sqlite"),
        crate::studio::paths::SqliteFileMode::Create,
    )
    .await?;
    Published16.up(&db, None).await?;
    seed(&db).await?;
    let before = originals(&db).await?;
    let (reached, observed) = tokio::sync::oneshot::channel();
    // Run the actual named step in its outer transaction, then cancel before the
    // framework could record Applied/commit. Dropping the transaction must undo
    // both key relocation and all DDL, not merely roll back the final index.
    {
        let work = async {
            let tx = db.begin().await?;
            CompletionBoundary.up(&SchemaManager::new(&tx)).await?;
            assert!(
                !rows(
                    &tx,
                    "SELECT owner_key AS value FROM completion_boundary_archive_contents"
                )
                .await?
                .is_empty()
            );
            reached
                .send(())
                .map_err(|_| anyhow::anyhow!("cancel observer gone"))?;
            std::future::pending::<()>().await;
            tx.commit().await?;
            Ok::<_, anyhow::Error>(())
        };
        tokio::pin!(work);
        tokio::select! {
            result=&mut work => { result?; anyhow::bail!("migration unexpectedly committed"); },
            result=observed => { result?; },
        }
    }
    assert!(!applied(&db).await?);
    assert_eq!(originals(&db).await?, before);
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE name='completion_boundary_archive_contents'",
            vec![],
        ))
        .await?
        .is_none()
    );
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert!(applied(&db).await?);
    db.close().await?;
    Ok(())
}
