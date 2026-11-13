use super::*;
use crate::studio::paths::SqliteFileMode;
use crate::studio::storage::history::{HistoryStore, connect};
use anyhow::{Context, Result};
use pl_core::thread::{ToolDelivery, ToolDeliveryTarget, ToolOutcome};
use pl_core::tool::ToolOutput;
use pl_protocol::*;
use sea_orm::DatabaseConnection;
use serde_json::json;

const THREAD: &str = "synthetic-upgrade";
const CALL: &str = "synthetic-call";
const MESSAGE: &str = "task-result:synthetic";

/// v6.36.0 (ae7951a8) wrote metering-only history 10. Later checkpoints 13–15
/// are frozen inputs too; none may silently run the new correction while being seeded.
struct Published(i64);

impl MigratorTraitSelf for Published {
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
                    | VISIBLE_TAIL_WORKGROUPS
            )
        })
        .filter(|step| !is_lifecycle_migration(step.name()) && step.name() != BACKGROUND_RESULTS)
        .filter(|step| match self.0 {
            10 => !matches!(
                step.name(),
                ATOMIC_TIMELINE
                    | COMBINED_CONTENT
                    | DEMAND_CONVERSATION
                    | MODEL_ROUTE_HEAD
                    | ATOM_METADATA
                    | TIMELINE_ITEMS
            ),
            13 => !matches!(step.name(), ATOM_METADATA | TIMELINE_ITEMS),
            14 => step.name() != TIMELINE_ITEMS,
            15 => true,
            _ => unreachable!("only v6.36.0 and later published inputs"),
        })
        .collect()
    }
}

fn payload(background: bool) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(&json!({
        "contract":"anywork.chat/1","type":"tool","turnId":"synthetic-turn",
        "sealedAt":12,
        "data":{"invocation":{"toolCallId":CALL,"name":"exec"},
            "state":{"kind":if background {"backgroundStarted"} else {"completed"}},
            "opaque":{"original":[0,255,37],"text":"合成结果，保留原文"}}
    }))?)
}

async fn fixture(format: i64, handoff: bool) -> Result<(tempfile::TempDir, std::path::PathBuf)> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let db = connect(&path, SqliteFileMode::Create).await?;
    let initial = if format == 10 { 10 } else { 13 };
    Published(initial).up(&db, None).await?;
    assert_eq!(version(&db).await?, initial);
    let item = order::tool_id(CALL);
    if format == 10 {
        let store = HistoryStore::open(&path, THREAD).await?;
        store
            .upsert_item(
                &db,
                7,
                ThreadItem::new(
                    item.clone(),
                    THREAD.into(),
                    "synthetic-turn".into(),
                    1,
                    1,
                    10,
                    12,
                    ThreadItemState::Tool(ThreadToolItem::new(
                        ThreadToolInvocation::new(CALL.into(), "exec".into(), "{}".into()),
                        ThreadToolState::Succeeded(SucceededThreadTool::new(
                            12,
                            ThreadToolOutput::new(
                                "合成结果，保留原文".into(),
                                vec![],
                                vec![],
                                Some(0),
                            ),
                        )),
                    )),
                ),
            )
            .await?;
    } else {
        db.execute_raw(statement(
            "INSERT INTO history_items VALUES(1,?,'synthetic-turn','tool',1,'terminal',10,12,'{\"original\":true}',7)",
            vec![item.clone().into()],
        )).await?;
        for (seq, id, bytes) in if handoff {
            vec![
                (
                    1_i64,
                    order::tool_background_started_id(CALL),
                    payload(true)?,
                ),
                (2, item.clone(), payload(false)?),
            ]
        } else {
            vec![(1_i64, item.clone(), payload(false)?)]
        } {
            db.execute_raw(statement(
                "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload) VALUES(?,?,'activity',NULL,?)",
                vec![seq.into(), id.into(), bytes.into()],
            )).await?;
        }
    }
    // Exercise the actual persisted enum shape: Inbox serializes message_id, not messageId.
    let delivery = ToolDelivery {
        target: ToolDeliveryTarget::Inbox {
            message_id: MESSAGE.into(),
        },
        call_id: CALL.into(),
        tool_id: "exec".into(),
        output: ToolOutput::new(
            pl_core::context::OpaquePayload::text("合成结果，保留原文"),
            vec![],
        ),
        delivered_context: vec![],
        outcome: ToolOutcome::Succeeded,
    };
    db.execute_raw(statement(
        "INSERT INTO history_tool_tasks VALUES(?,1,'{\"originalTask\":true}',?,7)",
        vec![CALL.into(), serde_json::to_string(&delivery)?.into()],
    ))
    .await?;
    db.execute_raw(statement(
        "INSERT INTO history_message_identities(message_id,item_id,sequence,digest,last_write_seq) VALUES(?,?,23,'original-digest',7)",
        vec![MESSAGE.into(), order::message_id(MESSAGE).into()],
    )).await?;
    if format > 13 {
        Published(format).up(&db, None).await?;
    }
    assert_eq!(version(&db).await?, format);
    db.close().await?;
    Ok((directory, path))
}

async fn originals(db: &DatabaseConnection, completions: bool) -> Result<Vec<String>> {
    let mut values = Vec::new();
    for sql in [
        "SELECT json_array(ordinal,item_id,payload,last_write_seq) AS original FROM history_items ORDER BY ordinal",
        "SELECT json_array(call_id,revision,task_payload,delivery_payload,last_write_seq) AS original FROM history_tool_tasks ORDER BY call_id",
        "SELECT json_array(message_id,item_id,sequence,digest,last_write_seq) AS original FROM history_message_identities ORDER BY message_id",
    ] {
        for row in db.query_all_raw(statement(sql, vec![])).await? {
            values.push(row.try_get("", "original")?);
        }
    }
    if completions {
        // query_class is derived and the published 13→14 step legitimately reclassifies it.
        for row in db.query_all_raw(statement(
            "SELECT json_array(seq,item_id,parent_id,hex(payload)) AS original FROM conversation_items ORDER BY seq",
            vec![],
        )).await? {
            values.push(row.try_get("", "original")?);
        }
    }
    Ok(values)
}

async fn metadata(db: &impl ConnectionTrait, id: &str) -> Result<ChatAtom> {
    let row = db
        .query_one_raw(statement(
            "SELECT metadata FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        ))
        .await?
        .context("original completion")?;
    Ok(serde_json::from_slice(
        &row.try_get::<Vec<u8>>("", "metadata")?,
    )?)
}

#[tokio::test]
async fn background_results_migrate_from_636_and_interrupted_13_14_without_losing_completions()
-> Result<()> {
    for format in [10, 13, 14] {
        let (_directory, path) = fixture(format, format != 10).await?;
        let db = connect(&path, SqliteFileMode::ReadWrite).await?;
        let before = originals(&db, format >= 13).await?;
        db.close().await?;
        let store = HistoryStore::open(&path, THREAD).await?;
        store.prepare_conversation_read().await?;
        store.close_for_deletion().await?;
        let db = connect(&path, SqliteFileMode::ReadWrite).await?;
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert!(!needs_content_preparation(&db, THREAD).await?);
        let result = metadata(&db, &order::tool_id(CALL)).await?;
        assert_eq!(result.id, order::message_id(MESSAGE));
        assert_eq!(
            result.source,
            ChatSourceId::BackgroundResult {
                message_id: MESSAGE.into()
            }
        );
        assert_eq!(result.delivery, ChatDeliveryKind::Independent);
        assert_eq!(result.source_order, Some(23));
        assert_eq!(
            result.completion_item_id.as_deref(),
            Some(order::tool_id(CALL).as_str())
        );
        if format != 10 {
            let handoff = metadata(&db, &order::tool_background_started_id(CALL)).await?;
            assert_eq!(handoff.id, order::tool_id(CALL));
            assert_eq!(handoff.delivery, ChatDeliveryKind::BackgroundHandoff);
        }
        assert_eq!(originals(&db, format >= 13).await?, before);
        let run = db.query_one_raw(statement(
            "SELECT seq,display_run_start,display_run_ordinal FROM conversation_items WHERE item_id=?",
            vec![order::tool_id(CALL).into()],
        )).await?.context("background completion")?;
        assert_eq!(
            run.try_get::<i64>("", "display_run_start")?,
            run.try_get::<i64>("", "seq")?
        );
        assert_eq!(run.try_get::<i64>("", "display_run_ordinal")?, 1);
        db.close().await?;
    }
    Ok(())
}

async fn snapshot(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    let completed = completion_boundary::applied(db).await?;
    let mut values = Vec::new();
    for sql in [
        "SELECT json_array(seq,item_id,hex(metadata)) AS value FROM conversation_items ORDER BY seq",
        "SELECT json_array(effect_seq,suborder,atom_id,phase,fact_order,hex(metadata)) AS value FROM conversation_atom_facts ORDER BY atom_id,phase",
        "SELECT json_array(item_id,kind,location,position,commit_seq,hex(metadata)) AS value FROM timeline_items ORDER BY item_id",
        "SELECT json_array(item_id,member_order,member_id,completion_item_id,hex(metadata)) AS value FROM timeline_item_members ORDER BY item_id,member_order",
        "SELECT json_array(projection_generation,hex(recovery),source_effect_seq,next_position) AS value FROM timeline_projection_state",
        "SELECT hex(payload) AS value FROM conversation_view_state",
        "SELECT json_array(version,applied_at) AS value FROM seaql_migrations ORDER BY version",
    ] {
        let sql = if completed {
            sql.replace("kind,location,position", "kind,'history',position")
                .replace(
                    "FROM timeline_items ",
                    "FROM completion_boundary_archive_timeline_items ",
                )
                .replace(
                    "FROM timeline_item_members ",
                    "FROM completion_boundary_archive_timeline_members ",
                )
                .replace(
                    "FROM timeline_projection_state",
                    "FROM completion_boundary_archive_projection_state",
                )
                .replace(
                    "FROM conversation_view_state",
                    "FROM completion_boundary_archive_view_state",
                )
        } else {
            sql.to_owned()
        };
        for row in db.query_all_raw(statement(&sql, vec![])).await? {
            values.push(row.try_get("", "value")?);
        }
    }
    Ok(values)
}

async fn unrelated_facts(db: &impl ConnectionTrait) -> Result<Vec<String>> {
    db.query_all_raw(statement(
        "SELECT json_array(effect_seq,suborder,atom_id,phase,fact_order,hex(metadata)) AS value FROM conversation_atom_facts WHERE atom_id='unrelated-live' ORDER BY phase",
        vec![],
    )).await?.into_iter().map(|row| row.try_get("", "value").map_err(Into::into)).collect()
}

#[tokio::test]
async fn existing_15_correction_preserves_live_facts_rolls_back_and_reopens_without_rewrite()
-> Result<()> {
    let (_directory, path) = fixture(15, false).await?;
    let db = connect(&path, SqliteFileMode::ReadWrite).await?;
    let mut atom = metadata(&db, &order::tool_id(CALL)).await?;
    atom.id = "unrelated-live".into();
    atom.source = ChatSourceId::Receipt {
        receipt_id: "independent-operation".into(),
    };
    atom.source_order = Some(42);
    atom.kind = ChatAtomKind::Receipt;
    atom.delivery = ChatDeliveryKind::Independent;
    atom.completion_item_id = None;
    atom.completion_seq = None;
    atom.contents.clear();
    atom.tool = None;
    atom.finished_at = None;
    let start = ChatFactPosition {
        effect_seq: 42,
        suborder: 1,
    };
    atom.lifecycle = ChatAtomLifecycle::Active {
        started: Some(start),
        status: ChatActiveStatus::Running,
    };
    db.execute_raw(statement(
        "INSERT INTO conversation_atom_facts VALUES(42,1,'unrelated-live','start',42,?)",
        vec![serde_json::to_vec(&atom)?.into()],
    ))
    .await?;
    atom.lifecycle = ChatAtomLifecycle::Terminal {
        started: Some(start),
        ended: Some(ChatFactPosition {
            effect_seq: 42,
            suborder: 2,
        }),
        outcome: ChatTerminalOutcome::Completed,
    };
    atom.completion_seq = Some(42);
    db.execute_raw(statement(
        "INSERT INTO conversation_atom_facts VALUES(42,2,'unrelated-live','terminal',42,?)",
        vec![serde_json::to_vec(&atom)?.into()],
    ))
    .await?;
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=42;
        UPDATE conversation_view_state SET payload=CAST(json_set(payload,'$.sourceEffectSeq',42) AS BLOB);").await?;
    // Freeze the independently committed predecessor before faulting the
    // original background correction's own Applied transaction.
    Migrator {
        thread_id: THREAD.into(),
        execution_identity: None,
        bot_root: None,
    }
    .up(&db, Some(1))
    .await?;
    let live = unrelated_facts(&db).await?;
    let before = snapshot(&db).await?;
    db.execute_unprepared(&format!(
        "CREATE TRIGGER reject_correction_receipt BEFORE INSERT ON seaql_migrations
         WHEN NEW.version='{BACKGROUND_RESULTS}' BEGIN SELECT RAISE(ABORT,'synthetic commit fault'); END;"
    )).await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    let failure = store
        .prepare_conversation_read()
        .await
        .expect_err("new content migration must run even at format 15");
    assert!(
        format!("{failure:#}").contains("synthetic commit fault"),
        "{failure:#}"
    );
    store.close_for_deletion().await?;
    let db = connect(&path, SqliteFileMode::ReadWrite).await?;
    assert_eq!(
        snapshot(&db).await?,
        before,
        "metadata, facts, derived state and Applied roll back together"
    );
    db.execute_unprepared("DROP TRIGGER reject_correction_receipt")
        .await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    store.prepare_conversation_read().await?;
    store.close_for_deletion().await?;
    let db = connect(&path, SqliteFileMode::ReadWrite).await?;
    assert_eq!(
        unrelated_facts(&db).await?,
        live,
        "preserve real start/end positions and frozen bytes"
    );
    assert_eq!(
        metadata(&db, &order::tool_id(CALL)).await?.id,
        order::message_id(MESSAGE)
    );
    let corrected = snapshot(&db).await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_repeat_metadata BEFORE UPDATE ON conversation_items BEGIN SELECT RAISE(ABORT,'repeat correction'); END;
         CREATE TRIGGER reject_repeat_facts BEFORE UPDATE ON conversation_atom_facts BEGIN SELECT RAISE(ABORT,'repeat correction'); END;
         CREATE TRIGGER reject_repeat_rebuild BEFORE DELETE ON completion_boundary_archive_timeline_items BEGIN SELECT RAISE(ABORT,'repeat rebuild'); END;
         CREATE TRIGGER reject_repeat_current BEFORE UPDATE ON completion_boundary_archive_view_state BEGIN SELECT RAISE(ABORT,'repeat current'); END;"
    ).await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    store.prepare_conversation_read().await?;
    store.close_for_deletion().await?;
    let db = connect(&path, SqliteFileMode::ReadWrite).await?;
    assert_eq!(snapshot(&db).await?, corrected);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn pending_correction_does_not_reapply_missing_earlier_content_steps() -> Result<()> {
    let (_directory, path) = fixture(15, false).await?;
    let db = connect(&path, SqliteFileMode::ReadWrite).await?;
    assert_eq!(
        db.execute_raw(statement(
            "DELETE FROM seaql_migrations WHERE version=?",
            vec![InputPresentation.name().into()],
        ))
        .await?
        .rows_affected(),
        1
    );
    let before = snapshot(&db).await?;
    let source = originals(&db, true).await?;
    db.close().await?;
    let store = HistoryStore::open(&path, THREAD).await?;
    let failure = store
        .prepare_conversation_read()
        .await
        .expect_err("reject an incomplete earlier ledger");
    assert!(
        format!("{failure:#}").contains("pending earlier content migrations"),
        "{failure:#}"
    );
    store.close_for_deletion().await?;
    let db = connect(&path, SqliteFileMode::ReadWrite).await?;
    assert_eq!(snapshot(&db).await?, before);
    assert_eq!(originals(&db, true).await?, source);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn absent_or_conflicting_background_message_identity_preserves_the_old_metadata() -> Result<()>
{
    for corruption in [
        "DELETE FROM history_message_identities",
        "UPDATE history_message_identities SET item_id='another-message'",
    ] {
        let (_directory, path) = fixture(14, true).await?;
        let db = connect(&path, SqliteFileMode::ReadWrite).await?;
        db.execute_unprepared(corruption).await?;
        let before = originals(&db, true).await?;
        let metadata_before = db
            .query_all_raw(statement(
                "SELECT metadata FROM conversation_items ORDER BY seq",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<Vec<u8>>("", "metadata"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        db.close().await?;
        let store = HistoryStore::open(&path, THREAD).await?;
        assert!(store.prepare_conversation_read().await.is_err());
        store.close_for_deletion().await?;
        let db = connect(&path, SqliteFileMode::ReadWrite).await?;
        assert_eq!(version(&db).await?, 14);
        assert_eq!(originals(&db, true).await?, before);
        let after = db
            .query_all_raw(statement(
                "SELECT metadata FROM conversation_items ORDER BY seq",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<Vec<u8>>("", "metadata"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(after, metadata_before);
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![BACKGROUND_RESULTS.into()]
            ))
            .await?
            .is_none()
        );
        db.close().await?;
    }
    Ok(())
}
