use super::*;
use crate::studio::paths::SqliteFileMode;
use crate::studio::storage::history::{HistoryStore, connect};
use crate::studio::thread_projection::order;
use anyhow::{Context, Result};
use pl_core::thread::{ToolDelivery, ToolDeliveryTarget, ToolOutcome};
use pl_core::tool::ToolOutput;
use sea_orm::DatabaseConnection;
use serde_json::json;

const THREAD: &str = "synthetic-upgrade";
const CALL: &str = "synthetic-call";
const MESSAGE: &str = "task-result:synthetic";

/// v6.36.0 (ae7951a8) wrote metering-only history 10. Published checkpoints
/// 13 and 14 remain frozen inputs; the first timeline migration normalizes them.
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
                    | SOURCE_CLASSIFICATION
                    | COMPLETION_BOUNDARY
            )
        })
        .filter(|step| !is_lifecycle_migration(step.name()))
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
        let rows = db.query_one_raw(statement(
            "SELECT COUNT(*) AS n FROM timeline_items WHERE kind='workGroup' AND json_extract(metadata,'$.source.kind')='backgroundResult'",
            vec![],
        )).await?.unwrap();
        assert_eq!(rows.try_get::<i64>("", "n")?, 1);
        db.close().await?;
    }
    Ok(())
}
