use super::*;
use crate::history::{
    HistoryDemand, HistoryEvent, HistoryLimits, HistoryStore, HistoryTimelineRole, PendingBody,
    pack_bodies, read_event_body_bytes,
};
use crate::studio::storage::tool_task;
use serde_json::{Value, json};

const THREAD: &str = "saved-tool-results";
const PROJECTION: &str = "旧模型看到的原文";

#[derive(Clone, Copy, Debug)]
enum ChunkDamage {
    OversizedFinalChunk,
    ExtraTailChunk,
}

const CHUNK_DAMAGE_CASES: [ChunkDamage; 2] = [
    ChunkDamage::OversizedFinalChunk,
    ChunkDamage::ExtraTailChunk,
];

// Frozen e2c935021 encoding, independent of the current ToolOutput and ToolDelivery serializers.
pub(in crate::history::upgrade) fn old_receipt(call: &str, tool: &str, payload: &Value) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "task": {
            "id": format!("task:{call}"), "callId": call, "toolId": tool, "turnId": "saved-turn",
            "revision": 2, "status": "succeeded", "cancelRequested": false,
            "startedSequence": 1,
        },
        "delivery": {
            "target": {"kind": "callResult"}, "callId": call, "toolId": tool,
            "output": {"payload": payload, "context": [{"kind": "text", "text": PROJECTION}]},
            "deliveredContext": [], "outcome": {"kind": "succeeded"},
        },
    }))
    .unwrap()
}

fn make_event(
    store: &HistoryStore,
    call: &str,
    tool: &str,
    payload: &Value,
    stored_call: &str,
) -> HistoryEvent {
    let mut event = HistoryEvent::new(
        format!("tool:{}:{call}", call.len()),
        HistoryEventKind::ToolCompleted,
        HistoryTimelineRole::Hidden,
        1,
    );
    event.call_id = Some(call.to_owned());
    event.tool_name = Some(tool.to_owned());
    let mut pending = vec![PendingBody::new(
        OLD_KEY,
        HistoryBodyRole::Other {
            name: "native_tool_task".into(),
        },
        Some("application/json".into()),
        old_receipt(stored_call, tool, payload),
    )];
    if matches!(tool, "show_files" | "get_tool_task") {
        pending.push(PendingBody::new(
            OUTPUT_ARTIFACTS_KEY,
            HistoryBodyRole::Attachment,
            Some("application/json".into()),
            serde_json::to_vec(&json!([
                {"kind":"opaque", "payload": payload}, {"unchanged": "artifact"}
            ]))
            .unwrap(),
        ));
    }
    let bodies = pack_bodies(&mut event, pending, store.reader().database_id()).unwrap();
    event.payload_json = json!({"bodies": bodies}).to_string();
    event
}

async fn freeze_revision_2(
    path: &Path,
    store: HistoryStore,
    events: &[HistoryEvent],
) -> Result<()> {
    store.accept_batch(events).await?;
    store.flush().await?;
    store.close().await?;
    let db = schema::connect(path, false, false).await?;
    db.execute_unprepared("PRAGMA user_version=2").await?;
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn tool_result_history_upgrades_originals_and_artifacts() -> Result<()> {
    use pl_core::context::ContextContent;
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
    let command_body = json!({"taskId":"task:command", "exitCode":0,
        "stdout":{"content":"原始字节🧭".repeat(16_000), "wasTruncated":false},
        "stderr":{"content":"", "wasTruncated":false}})
    .to_string();
    let command = json!({"format": "pl.tool.exec", "version": 2, "content": command_body});
    let file = json!({"format": "pl.tool.files", "version": 1, "content":
        "{\"caption\":\"原文件\",\"files\":[{\"status\":\"failed\",\"filename\":\"notes.txt\",\"message\":\"original error\"}]}"});
    let query = json!({"format": "pl.tool.task", "version": 1, "content":
        "{\"task\":{\"id\":\"task:command\"},\"result\":{\"format\":\"pl.tool.exec\",\"version\":2,\"content\":\"prefix\",\"nextCursor\":8192,\"totalBytes\":20100}}"});
    let command_event = make_event(&store, "command", "exec", &command, "command");
    let file_event = make_event(&store, "files", "show_files", &file, "files");
    let query_event = make_event(&store, "query", "get_tool_task", &query, "query");
    freeze_revision_2(
        &path,
        store,
        &[
            command_event.clone(),
            file_event.clone(),
            query_event.clone(),
        ],
    )
    .await?;
    assert!(
        HistoryStore::open_reader(&path, THREAD, HistoryLimits::default())
            .await
            .is_err()
    );

    let report = super::super::upgrade_history(&path, THREAD, directory.path()).await?;
    assert_eq!(report.imported_categories["tool_receipts_upgraded"], 3);
    assert_eq!(report.imported_categories["tool_artifacts_upgraded"], 2);
    let backup = schema::connect(report.backup.as_deref().unwrap(), true, false).await?;
    let original = db::event(&backup, &command_event.event_id)
        .await?
        .unwrap()
        .record;
    assert_eq!(original.payload_json, command_event.payload_json);
    backup.close().await?;
    assert!(
        HistoryStore::open_reader(&path, "foreign-thread", HistoryLimits::default())
            .await
            .is_err()
    );

    let reader = HistoryStore::open_reader(&path, THREAD, HistoryLimits::default()).await?;
    let saved = tool_task::read(&reader, "task:command").await?.unwrap();
    assert_eq!(saved.task.call_id, "command");
    assert_eq!(saved.task.revision, 2);
    let delivery = saved.delivery.unwrap();
    assert!(delivery.cancellation_cause.is_none());
    assert!(delivery.delivered_context.is_empty());
    assert_eq!(delivery.output.data(), None);
    assert_eq!(delivery.output.details().unwrap()["legacyPayload"], command);
    assert_eq!(
        delivery.output.content(),
        [ContextContent::Text {
            text: PROJECTION.into()
        }]
    );

    for (event, expected) in [
        (
            file_event,
            json!({"fileDisplay": {"caption":"原文件", "files":
            [{"status":"failed", "filename":"notes.txt", "message":"original error"}]}}),
        ),
        (query_event, json!({"legacyToolTask": query})),
    ] {
        let saved = reader
            .read_event(
                event.event_id,
                HistoryDemand {
                    max_rows: 1,
                    max_bytes: 32 * 1024,
                },
            )
            .await?;
        let bytes = read_event_body_bytes(&reader, &saved, OUTPUT_ARTIFACTS_KEY, Some(8192))
            .await?
            .unwrap();
        assert_eq!(
            serde_json::from_slice::<Value>(&bytes)?,
            json!([expected, {"unchanged":"artifact"}])
        );
    }
    assert!(tool_task::read(&reader, "task:missing").await?.is_none());
    reader.close().await;

    // Damage a stored chunk without changing its length. The reader must surface corruption
    // instead of treating this committed task as an unknown task or returning a modified page.
    let db = schema::connect(&path, false, false).await?;
    db.execute_unprepared("DROP TRIGGER history_body_chunks_no_update")
        .await?;
    db.execute_raw(statement(
        "UPDATE history_body_chunks SET data=zeroblob(length(data)) WHERE chunk_no=0 AND body_id IN \
         (SELECT body_id FROM history_bodies WHERE owner_event_id=? AND body_key=?)",
        vec![command_event.event_id.into(), BODY_KEY.into()],
    )).await?;
    db.execute_unprepared(
        "CREATE TRIGGER history_body_chunks_no_update BEFORE UPDATE ON history_body_chunks \
        BEGIN SELECT RAISE(ABORT, 'history body chunks are append-only'); END;",
    )
    .await?;
    db.close().await?;
    let reader = HistoryStore::open_reader(&path, THREAD, HistoryLimits::default()).await?;
    assert!(matches!(
        tool_task::read(&reader, "command").await,
        Err(HistoryError::Integrity(_))
    ));
    reader.close().await;
    Ok(())
}

#[tokio::test]
async fn tool_result_history_rolls_back_a_corrupt_receipt() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("history.sqlite");
    let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
    let payload = json!({"format":"text/plain", "version":1, "content":"a result"});
    let good = make_event(&store, "good", "exec", &payload, "good");
    let bad = make_event(&store, "bad", "exec", &payload, "different-call");
    freeze_revision_2(&path, store, &[good.clone(), bad]).await?;

    let error = super::super::upgrade_history(&path, THREAD, directory.path())
        .await
        .unwrap_err();
    assert!(matches!(error, HistoryError::Integrity(_)), "{error}");
    let db = schema::connect(&path, false, false).await?;
    assert_eq!(schema26_manifest::revision(&db).await?, 2);
    assert_eq!(
        db::event(&db, &good.event_id)
            .await?
            .unwrap()
            .record
            .payload_json,
        good.payload_json
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM history_bodies WHERE body_key=?",
            vec![BODY_KEY.into()]
        ))
        .await?
        .is_none()
    );
    assert!(
        db.execute_unprepared("UPDATE history_events SET payload_json=payload_json WHERE seq=1")
            .await
            .is_err()
    );
    db.close().await?;
    let backups = std::fs::read_dir(directory.path().join(BACKUP_ROOT))?;
    assert!(
        backups
            .into_iter()
            .filter_map(std::result::Result::ok)
            .any(|entry| entry.path().join("history.v27.sqlite").is_file())
    );
    Ok(())
}

#[tokio::test]
async fn tool_result_history_cold_read_rejects_invalid_receipt_chunk_layout() -> Result<()> {
    for damage in CHUNK_DAMAGE_CASES {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
        let event = make_event(&store, "saved", "exec", &large_payload(), "saved");
        freeze_revision_2(&path, store, std::slice::from_ref(&event)).await?;
        super::super::upgrade_history(&path, THREAD, directory.path()).await?;

        let reader = HistoryStore::open_reader(&path, THREAD, HistoryLimits::default()).await?;
        assert_eq!(
            tool_task::read(&reader, "task:saved")
                .await?
                .unwrap()
                .task
                .call_id,
            "saved"
        );
        reader.close().await;

        let db = schema::connect(&path, false, false).await?;
        damage_receipt(&db, &event.event_id, BODY_KEY, damage).await?;
        db.close().await?;
        let reader = HistoryStore::open_reader(&path, THREAD, HistoryLimits::default()).await?;
        let error = tool_task::read(&reader, "task:saved").await.unwrap_err();
        assert_chunk_layout_error(&error, damage);
        reader.close().await;
    }
    Ok(())
}

#[tokio::test]
async fn tool_result_history_rolls_back_invalid_receipt_chunk_layout() -> Result<()> {
    for damage in CHUNK_DAMAGE_CASES {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let store = HistoryStore::open(&path, THREAD, HistoryLimits::default()).await?;
        let payload = large_payload();
        let good = make_event(&store, "good", "exec", &payload, "good");
        let bad = make_event(&store, "bad", "exec", &payload, "bad");
        let events = [good, bad];
        freeze_revision_2(&path, store, &events).await?;

        let db = schema::connect(&path, false, false).await?;
        let good_chunks = receipt_chunks(&db, &events[0].event_id, OLD_KEY).await?;
        damage_receipt(&db, &events[1].event_id, OLD_KEY, damage).await?;
        let bad_chunks = receipt_chunks(&db, &events[1].event_id, OLD_KEY).await?;
        db.close().await?;

        let error = super::super::upgrade_history(&path, THREAD, directory.path())
            .await
            .unwrap_err();
        assert_chunk_layout_error(&error, damage);

        let backups = std::fs::read_dir(directory.path().join(BACKUP_ROOT))?
            .map(|entry| entry.map(|entry| entry.path().join("history.v27.sqlite")))
            .collect::<std::io::Result<Vec<_>>>()?;
        let [backup] = backups.as_slice() else {
            panic!("expected one published backup for {damage:?}");
        };
        assert!(backup.is_file());
        for (database_path, read_only) in [(&path, false), (backup, true)] {
            let db = schema::connect(database_path, read_only, false).await?;
            assert_eq!(schema26_manifest::revision(&db).await?, 2);
            assert!(
                db.query_one_raw(statement(
                    "SELECT 1 FROM history_bodies WHERE body_key=?",
                    vec![BODY_KEY.into()],
                ))
                .await?
                .is_none()
            );
            for (event, chunks) in events.iter().zip([&good_chunks, &bad_chunks]) {
                let record = db::event(&db, &event.event_id).await?.unwrap().record;
                assert_eq!(record.payload_json, event.payload_json);
                assert_eq!(
                    &receipt_chunks(&db, &event.event_id, OLD_KEY).await?,
                    chunks
                );
            }
            if !read_only {
                assert!(
                    db.execute_unprepared(
                        "UPDATE history_events SET payload_json=payload_json WHERE seq=1"
                    )
                    .await
                    .is_err()
                );
            }
            db.close().await?;
        }
    }
    Ok(())
}

fn large_payload() -> Value {
    json!({"format":"text/plain", "version":1, "content":"x".repeat(BODY_CHUNK_BYTES + 32)})
}

fn assert_chunk_layout_error(error: &HistoryError, damage: ChunkDamage) {
    assert!(
        matches!(error, HistoryError::Integrity(message) if message.contains("stored body chunk layout")),
        "{damage:?}: {error}"
    );
}

async fn receipt_chunks(
    db: &impl ConnectionTrait,
    event_id: &str,
    key: &str,
) -> Result<Vec<(i64, Vec<u8>)>> {
    db.query_all_raw(statement(
        "SELECT c.chunk_no, c.data FROM history_body_chunks c JOIN history_bodies b USING(body_id) \
         WHERE b.owner_event_id=? AND b.body_key=? ORDER BY c.chunk_no",
        vec![event_id.into(), key.into()],
    ))
    .await?
    .into_iter()
    .map(|row| Ok((row.try_get("", "chunk_no")?, row.try_get("", "data")?)))
    .collect()
}

async fn damage_receipt(
    db: &impl ConnectionTrait,
    event_id: &str,
    key: &str,
    damage: ChunkDamage,
) -> Result<()> {
    let (last_no, mut last) = receipt_chunks(db, event_id, key)
        .await?
        .pop()
        .expect("receipt must have a stored final chunk");
    assert!(last_no > 0 && last.len() < BODY_CHUNK_BYTES);
    match damage {
        ChunkDamage::OversizedFinalChunk => {
            last.push(0xa5);
            let trigger = db
                .query_one_raw(statement(
                    "SELECT sql FROM sqlite_schema WHERE name='history_body_chunks_no_update'",
                    vec![],
                ))
                .await?
                .unwrap()
                .try_get::<String>("", "sql")?;
            db.execute_unprepared("DROP TRIGGER history_body_chunks_no_update")
                .await?;
            let updated = db
                .execute_raw(statement(
                    "UPDATE history_body_chunks SET data=? WHERE chunk_no=? AND body_id=( \
                 SELECT body_id FROM history_bodies WHERE owner_event_id=? AND body_key=?)",
                    vec![last.into(), last_no.into(), event_id.into(), key.into()],
                ))
                .await?;
            assert_eq!(updated.rows_affected(), 1);
            db.execute_unprepared(&trigger).await?;
        }
        ChunkDamage::ExtraTailChunk => {
            let inserted = db
                .execute_raw(statement(
                    "INSERT INTO history_body_chunks(body_id,chunk_no,data) \
                 SELECT body_id,?,? FROM history_bodies WHERE owner_event_id=? AND body_key=?",
                    vec![
                        (last_no + 1).into(),
                        vec![0xa5_u8].into(),
                        event_id.into(),
                        key.into(),
                    ],
                ))
                .await?;
            assert_eq!(inserted.rows_affected(), 1);
        }
    }
    Ok(())
}
