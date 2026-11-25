use super::*;
use std::sync::Arc;
use tracing::{Subscriber, field::Visit, span};

#[derive(Clone, Default)]
struct CapturedCallLog(Arc<Mutex<Vec<String>>>);

impl Visit for CapturedCallLog {
    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        self.0
            .lock()
            .unwrap()
            .push(format!("{}={value}", field.name()));
    }

    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        self.0
            .lock()
            .unwrap()
            .push(format!("{}={value:?}", field.name()));
    }
}

impl Subscriber for CapturedCallLog {
    fn enabled(&self, _: &tracing::Metadata<'_>) -> bool {
        true
    }

    fn new_span(&self, attributes: &span::Attributes<'_>) -> span::Id {
        attributes.record(&mut self.clone());
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        span::Id::from_u64(NEXT.fetch_add(1, Ordering::Relaxed))
    }

    fn record(&self, _: &span::Id, values: &span::Record<'_>) {
        values.record(&mut self.clone());
    }

    fn record_follows_from(&self, _: &span::Id, _: &span::Id) {}

    fn event(&self, event: &tracing::Event<'_>) {
        event.record(&mut self.clone());
    }

    fn enter(&self, _: &span::Id) {}

    fn exit(&self, _: &span::Id) {}
}

#[tokio::test]
async fn permanent_delete_calls_removes_all_body_revisions_and_preserves_neighbor_after_restart()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("calls.sqlite");
    let store = CallsStore::open(&path).await?;
    store.record_effect(&attempt_effect("deleted", "first", 1));
    store.record_effect(&attempt_effect("neighbor", "retained", 1));
    let mut progress = store.subscribe_materials();
    wait_material_ticket(&mut progress, store.admitted_ticket()).await?;
    store.writer.log.lock().await.close();
    // The same identity has a historical body that is no longer in the locator index.
    store.record_effect(&attempt_effect("deleted", "first", 2));
    wait_material_ticket(&mut progress, store.admitted_ticket()).await?;
    {
        let mut log = store.writer.log.lock().await;
        let now = crate::studio::unix_seconds();
        let (line, _) = event::encode_record(&CallLogRecord {
            version: event::CALL_LOG_RECORD_VERSION,
            kind: "attempt".into(),
            thread_id: "unindexed-child".into(),
            root_thread_id: Some("deleted".into()),
            call_id: "orphan-child-body".into(),
            recorded_at: now,
            ..Default::default()
        })?;
        // A complete orphan append must also be deleted by its root identity.
        log.append(event::record_day(now), now, &line).await?;
        log.sync_pending().await?;
        log.close();
    }
    store.record_effect(&attempt_effect("neighbor", "retained", 2));
    wait_material_ticket(&mut progress, store.admitted_ticket()).await?;
    let before = indexed_bodies(&store).await?;
    assert!(before.iter().any(|record| record.thread_id == "neighbor"));
    store.delete_threads(&["deleted".into()]).await?;
    let retained = indexed_bodies(&store).await?;
    assert_eq!(retained.len(), 1);
    assert_eq!(retained[0].thread_id, "neighbor");
    assert_eq!(retained[0].revision, 2);
    // A late producer uses the original writer; its stale fact must not recreate a body.
    store.record_effect(&attempt_effect("deleted", "late", 3));
    store.record_effect(&attempt_effect("neighbor", "new", 3));
    store.close().await?;
    let reopened = CallsStore::open(&path).await?;
    let rows = reopened
        .writer
        .db
        .query_all_raw(statement(
            "SELECT thread_id,call_id FROM call_log_index",
            vec![],
        ))
        .await?;
    assert_eq!(rows.len(), 2);
    assert!(
        rows.iter()
            .all(|row| row.try_get::<String>("", "thread_id").unwrap() == "neighbor")
    );
    assert_eq!(indexed_bodies(&reopened).await?.len(), 2);
    let mut logs = tokio::fs::read_dir(temp.path().join("logs")).await?;
    while let Some(entry) = logs.next_entry().await? {
        let text = tokio::fs::read_to_string(entry.path()).await?;
        assert!(!text.contains("\"threadId\":\"deleted\""));
        assert!(!text.contains("\"callId\":\"late\""));
        assert!(!text.contains("orphan-child-body"));
    }
    reopened.close().await?;
    Ok(())
}

/// Exercise actual byte offsets and hashes, rather than only counting locator rows.
async fn indexed_bodies(store: &CallsStore) -> Result<Vec<CallLogRecord>> {
    let rows = store
        .writer
        .db
        .query_all_raw(statement("SELECT * FROM call_log_index", vec![]))
        .await?;
    let dir = store.writer.log.lock().await.root_dir().join("logs");
    let mut records = Vec::new();
    for row in rows {
        let segment: String = row.try_get("", "segment")?;
        let offset = usize::try_from(row.try_get::<i64>("", "offset")?)?;
        let length = usize::try_from(row.try_get::<i64>("", "length")?)?;
        let bytes = tokio::fs::read(dir.join(segment)).await?;
        let text = std::str::from_utf8(&bytes[offset..offset + length])?;
        let record = event::decode_record(text)?;
        assert_eq!(record.thread_id, row.try_get::<String>("", "thread_id")?);
        assert_eq!(record.call_id, row.try_get::<String>("", "call_id")?);
        assert_eq!(record.revision, row.try_get::<i64>("", "revision")?);
        assert_eq!(
            pl_core::context::content_hash(text.as_bytes()),
            row.try_get::<String>("", "content_hash")?
        );
        records.push(record);
    }
    Ok(records)
}

#[tokio::test]
async fn permanent_delete_calls_preserves_unrelated_segments_and_performance_samples() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let (_, failures, deferred) = apply_batch(
        &store.writer,
        &batch(vec![billing("deleted")?, billing("neighbor")?]),
    )
    .await?;
    assert!(failures.is_empty() && deferred.is_none());
    store.writer.log.lock().await.close();
    let (_, failures, deferred) =
        apply_batch(&store.writer, &batch(vec![billing("unrelated")?])).await?;
    assert!(failures.is_empty() && deferred.is_none());
    let row = store
        .writer
        .db
        .query_one_raw(statement(
            "SELECT segment FROM call_log_index WHERE thread_id='unrelated'",
            vec![],
        ))
        .await?
        .unwrap();
    let segment: String = row.try_get("", "segment")?;
    let path = temp.path().join("logs").join(segment);
    let before = tokio::fs::read(&path).await?;
    let modified = tokio::fs::metadata(&path).await?.modified()?;
    store
        .writer
        .db
        .execute_unprepared(
            "UPDATE performance_samples SET output_tokens=1234 WHERE thread_id='neighbor';
         CREATE TRIGGER forbid_unrelated_delete BEFORE DELETE ON call_log_index
         WHEN OLD.thread_id='unrelated' BEGIN SELECT RAISE(ABORT,'unrelated locator deleted'); END;
         CREATE TRIGGER forbid_unrelated_insert BEFORE INSERT ON call_log_index
         WHEN NEW.thread_id='unrelated' BEGIN SELECT RAISE(ABORT,'unrelated locator replayed'); END;
         CREATE TRIGGER forbid_unrelated_update BEFORE UPDATE ON call_log_index
         WHEN OLD.thread_id='unrelated' BEGIN SELECT RAISE(ABORT,'unrelated locator updated'); END;
         CREATE TRIGGER forbid_sample_insert BEFORE INSERT ON performance_samples
         BEGIN SELECT RAISE(ABORT,'performance replayed'); END;
         CREATE TRIGGER forbid_sample_update BEFORE UPDATE ON performance_samples
         BEGIN SELECT RAISE(ABORT,'performance updated'); END;",
        )
        .await?;
    store.delete_threads(&["deleted".into()]).await?;
    // The second deletion is an idempotent retry after all bodies have gone.
    store.delete_threads(&["deleted".into()]).await?;
    assert_eq!(tokio::fs::read(&path).await?, before);
    assert_eq!(tokio::fs::metadata(path).await?.modified()?, modified);
    let records = indexed_bodies(&store).await?;
    assert_eq!(records.len(), 2);
    assert!(records.iter().all(|record| record.thread_id != "deleted"));
    let samples = store.recent_performance_samples(100).await?;
    assert_eq!(samples.len(), 2);
    let row = store
        .writer
        .db
        .query_one_raw(statement(
            "SELECT output_tokens FROM performance_samples WHERE thread_id='neighbor'",
            vec![],
        ))
        .await?
        .unwrap();
    assert_eq!(row.try_get::<i64>("", "output_tokens")?, 1234);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_uses_identity_without_decoding_unrelated_diagnostic_body() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let (_, failures, deferred) = apply_batch(
        &store.writer,
        &batch(vec![billing("deleted")?, billing("neighbor")?]),
    )
    .await?;
    assert!(failures.is_empty() && deferred.is_none());
    store.writer.log.lock().await.close();
    let row = store
        .writer
        .db
        .query_one_raw(statement(
            "SELECT segment FROM call_log_index WHERE thread_id='neighbor'",
            vec![],
        ))
        .await?
        .unwrap();
    let segment: String = row.try_get("", "segment")?;
    let path = temp.path().join("logs").join(&segment);
    let original = tokio::fs::read_to_string(&path).await?;
    let mut changed = String::new();
    let mut expected = String::new();
    for line in original.lines() {
        let mut value: serde_json::Value = serde_json::from_str(line)?;
        if value["threadId"] == "neighbor" {
            // Valid identity, deliberately incompatible disposable diagnostic and usage.
            value["diagnostic"] = serde_json::json!({"futureBody": true});
            value["usage"] = serde_json::json!("unreadable diagnostic projection");
            let line = serde_json::to_string(&value)?;
            assert!(event::decode_record(&line).is_err());
            expected.push_str(&line);
            expected.push('\n');
            changed.push_str(&line);
        } else {
            changed.push_str(line);
        }
        changed.push('\n');
    }
    tokio::fs::write(&path, changed).await?;
    store.delete_threads(&["deleted".into()]).await?;
    assert_eq!(tokio::fs::read_to_string(&path).await?, expected);
    let rows = store
        .writer
        .db
        .query_all_raw(statement(
            "SELECT thread_id,offset,length,content_hash FROM call_log_index WHERE segment=?",
            vec![segment.into()],
        ))
        .await?;
    assert!(!rows.is_empty());
    let bytes = expected.as_bytes();
    for row in rows {
        assert_eq!(row.try_get::<String>("", "thread_id")?, "neighbor");
        let offset = row.try_get::<i64>("", "offset")? as usize;
        let length = row.try_get::<i64>("", "length")? as usize;
        assert_eq!(
            row.try_get::<String>("", "content_hash")?,
            pl_core::context::content_hash(&bytes[offset..offset + length])
        );
    }
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_skips_unidentifiable_records_and_recovers_after_restart() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("calls.sqlite");
    let store = CallsStore::prepare(&path).await?;
    let (_, failures, deferred) = apply_batch(
        &store.writer,
        &batch(vec![billing("deleted")?, billing("neighbor")?]),
    )
    .await?;
    assert!(failures.is_empty() && deferred.is_none());
    store.writer.log.lock().await.close();
    let row = store
        .writer
        .db
        .query_one_raw(statement(
            "SELECT segment FROM call_log_index WHERE thread_id='neighbor'",
            vec![],
        ))
        .await?
        .unwrap();
    let segment: String = row.try_get("", "segment")?;
    let log_path = temp.path().join("logs").join(&segment);
    let original = tokio::fs::read(&log_path).await?;
    let mut expected = Vec::new();
    for line in original.split_inclusive(|byte| *byte == b'\n') {
        let text = std::str::from_utf8(&line[..line.len() - 1])?;
        let value: serde_json::Value = serde_json::from_str(text)?;
        if value["threadId"] != "deleted" {
            expected.extend_from_slice(line);
        }
    }

    let secret = b"synthetic-secret-must-not-be-logged";
    let malformed = [b"{\"diagnostic\":\"".as_slice(), secret, b"\",INVALID}\n"].concat();
    let empty_identity = b"{\"threadId\":\"\",\"callId\":\"unknown\",\"kind\":\"attempt\"}\n";
    let incomplete = [b"{\"threadId\":\"".as_slice(), secret].concat();
    let mut on_disk = original;
    on_disk.extend_from_slice(&malformed);
    on_disk.extend_from_slice(empty_identity);
    on_disk.extend_from_slice(&incomplete);
    expected.extend_from_slice(&malformed);
    expected.extend_from_slice(empty_identity);
    expected.extend_from_slice(&incomplete);
    tokio::fs::write(&log_path, on_disk).await?;

    // Keep a second, inactive dispatch alive while capturing. Otherwise
    // tracing-core 0.1.36 can cache Interest::never when another test first
    // registers this callsite without a subscriber (tokio-rs/tracing#3611).
    let _callsite_interest_guard = tracing::Dispatch::new(tracing::subscriber::NoSubscriber::new());
    let captured = CapturedCallLog::default();
    let dispatch = tracing::Dispatch::new(captured.clone());
    let _capture = tracing::dispatcher::set_default(&dispatch);
    store.delete_threads(&["deleted".into()]).await?;
    let records = captured.0.lock().unwrap().join("\n");
    for expected_field in [
        "reason=json_syntax",
        "decision=preserve_and_skip_index",
        "segment=",
        "line=",
        "offset=",
    ] {
        assert!(
            records.contains(expected_field),
            "missing {expected_field} in {records}"
        );
    }
    assert!(
        !records.contains(std::str::from_utf8(secret)?),
        "raw malformed record leaked into call-log diagnostics"
    );
    assert_eq!(tokio::fs::read(&log_path).await?, expected);
    let rows = store
        .writer
        .db
        .query_all_raw(statement(
            "SELECT thread_id,offset,length,content_hash FROM call_log_index WHERE segment=?",
            vec![segment.clone().into()],
        ))
        .await?;
    assert!(!rows.is_empty());
    for row in rows {
        assert_eq!(row.try_get::<String>("", "thread_id")?, "neighbor");
        let offset = row.try_get::<i64>("", "offset")? as usize;
        let length = row.try_get::<i64>("", "length")? as usize;
        assert_eq!(
            row.try_get::<String>("", "content_hash")?,
            pl_core::context::content_hash(&expected[offset..offset + length])
        );
    }
    store.close().await?;

    let reopened = CallsStore::open(&path).await?;
    reopened.delete_threads(&["deleted".into()]).await?;
    let remaining = indexed_bodies(&reopened).await?;
    assert!(!remaining.is_empty());
    assert!(
        remaining
            .iter()
            .all(|record| record.thread_id == "neighbor")
    );
    assert_eq!(tokio::fs::read(&log_path).await?, expected);
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_preserves_incomplete_tail_across_index_failure_restart_and_append()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("calls.sqlite");
    let store = CallsStore::prepare(&path).await?;
    let pending = batch(vec![billing("deleted")?, billing("neighbor")?]);
    let (_, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert!(failures.is_empty() && deferred.is_none());
    store.writer.log.lock().await.close();

    let row = store
        .writer
        .db
        .query_one_raw(statement(
            "SELECT segment FROM call_log_index WHERE thread_id='neighbor'",
            vec![],
        ))
        .await?
        .unwrap();
    let segment: String = row.try_get("", "segment")?;
    let log_dir = temp.path().join("logs");
    let log_path = log_dir.join(&segment);
    let incomplete = b"{unknown-tail-with-secret-bytes";
    let mut bytes = tokio::fs::read(&log_path).await?;
    bytes.extend_from_slice(incomplete);
    tokio::fs::write(&log_path, bytes).await?;

    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE tail_repair_parent(id INTEGER PRIMARY KEY);
         CREATE TABLE tail_repair_probe(parent INTEGER REFERENCES tail_repair_parent(id)
             DEFERRABLE INITIALLY DEFERRED);
         CREATE TRIGGER reject_tail_locator_repair AFTER INSERT ON call_log_index
         WHEN NEW.thread_id='neighbor' BEGIN
             INSERT INTO tail_repair_probe VALUES(1);
         END;",
        )
        .await?;
    let error = store.delete_threads(&["deleted".into()]).await.unwrap_err();
    assert!(error.to_string().contains("FOREIGN KEY constraint failed"));
    assert!(tokio::fs::read(&log_path).await?.ends_with(incomplete));
    let mut entries = tokio::fs::read_dir(&log_dir).await?;
    let mut segments = Vec::new();
    while let Some(entry) = entries.next_entry().await? {
        segments.push(entry.path());
    }
    assert_eq!(
        segments.len(),
        2,
        "a durable later segment must seal the bad tail"
    );
    let barrier = segments
        .into_iter()
        .find(|candidate| candidate != &log_path)
        .expect("the segment barrier exists");
    assert_eq!(tokio::fs::metadata(barrier).await?.len(), 0);

    store
        .writer
        .db
        .execute_unprepared("DROP TRIGGER reject_tail_locator_repair")
        .await?;
    store.close().await?;

    let reopened = CallsStore::prepare(&path).await?;
    assert!(tokio::fs::read(&log_path).await?.ends_with(incomplete));
    let recovered = indexed_bodies(&reopened).await?;
    assert_eq!(recovered.len(), 1);
    assert_eq!(recovered[0].thread_id, "neighbor");
    reopened.delete_threads(&["deleted".into()]).await?;

    let mut materials = reopened.subscribe_materials();
    reopened.record_effect(&attempt_effect("neighbor", "append-after-restart", 3));
    reopened.start().await;
    wait_material_ticket(&mut materials, reopened.admitted_ticket()).await?;
    assert!(tokio::fs::read(&log_path).await?.ends_with(incomplete));
    let recovered = indexed_bodies(&reopened).await?;
    assert!(
        recovered
            .iter()
            .all(|record| record.thread_id == "neighbor")
    );
    assert!(
        recovered
            .iter()
            .any(|record| record.call_id == "append-after-restart")
    );
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_clears_database_when_log_directory_is_missing() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let (_, failures, deferred) = apply_batch(
        &store.writer,
        &batch(vec![billing("deleted")?, billing("neighbor")?]),
    )
    .await?;
    assert!(failures.is_empty() && deferred.is_none());
    store.writer.log.lock().await.close();
    let log_dir = temp.path().join("logs");
    tokio::fs::remove_dir_all(&log_dir).await?;

    // See the scoped-subscriber workaround in the malformed-record test above.
    let _callsite_interest_guard = tracing::Dispatch::new(tracing::subscriber::NoSubscriber::new());
    let captured = CapturedCallLog::default();
    let dispatch = tracing::Dispatch::new(captured.clone());
    let _capture = tracing::dispatcher::set_default(&dispatch);
    store.delete_threads(&["deleted".into()]).await?;
    let records = captured.0.lock().unwrap().join("\n");
    for expected in [
        "reason=log_directory_missing",
        "decision=treat_missing_directory_as_empty",
    ] {
        assert!(
            records.contains(expected),
            "missing {expected} in {records}"
        );
    }
    let rows = store
        .writer
        .db
        .query_all_raw(statement(
            "SELECT thread_id FROM call_log_index ORDER BY thread_id",
            vec![],
        ))
        .await?;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].try_get::<String>("", "thread_id")?, "neighbor");
    assert!(!tokio::fs::try_exists(&log_dir).await?);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_calls_failed_segment_repair_retries_before_next_write() -> Result<()> {
    permanent_delete_calls_failed_segment_repair(false).await
}

#[tokio::test]
async fn permanent_delete_calls_failed_segment_repair_recovers_after_restart() -> Result<()> {
    permanent_delete_calls_failed_segment_repair(true).await
}

#[tokio::test]
async fn failed_locator_repair_does_not_starve_absolute_accounting() -> Result<()> {
    assert_failed_locator_repair_does_not_starve_absolute_accounting(
        "injected persistent locator failure",
    )
    .await
}

#[tokio::test]
async fn busy_locator_repair_does_not_starve_absolute_accounting() -> Result<()> {
    assert_failed_locator_repair_does_not_starve_absolute_accounting("database is busy").await
}

async fn assert_failed_locator_repair_does_not_starve_absolute_accounting(
    message: &str,
) -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let pending = batch(vec![billing("deleted")?, billing("neighbor")?]);
    let (_, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert!(failures.is_empty() && deferred.is_none());
    store
        .writer
        .db
        .execute_unprepared(&format!(
            "CREATE TRIGGER reject_locator_repair BEFORE INSERT ON call_log_index
         WHEN NEW.thread_id='neighbor' BEGIN
             SELECT RAISE(ABORT,'{message}');
         END;"
        ))
        .await?;
    assert!(
        store
            .delete_threads(&["deleted".into()])
            .await
            .unwrap_err()
            .to_string()
            .contains(message)
    );
    assert!(indexed_bodies(&store).await?.is_empty());

    let mut materials = store.subscribe_materials();
    // Queue diagnostics before the reliable projection so the test exercises the
    // real writer's mixed-batch error isolation and receipt publication.
    store.record_effect(&attempt_effect("another-session", "blocked-diagnostic", 1));
    let mut projection = SessionUsageProjection {
        root_thread_id: "another-root".into(),
        thread_id: "another-session".into(),
        revision: 9,
        has_unpriced_usage: false,
        purpose_costs: vec![PurposeUsageProjection {
            purpose: None,
            estimated_costs: vec![RuntimeCostAmount {
                currency: "USD".into(),
                amount: 4.25,
            }],
        }],
    };
    store.replace_session_usage(projection.clone())?;
    store.start().await;
    wait_material_ticket(&mut materials, store.admitted_ticket()).await?;
    assert!(store.statistics_gap());
    assert!(store.last_error().unwrap().contains(message));
    assert_eq!(materials.borrow().versions.costs, 1);
    assert_eq!(materials.borrow().versions.performance, 1);
    assert_eq!(
        store.session_cost_rollups().await?[0].estimated_costs[0].amount,
        4.25
    );
    assert!(indexed_bodies(&store).await?.is_empty());

    // The fault remains enabled for a second, Summary-only batch.
    projection.revision = 10;
    projection.purpose_costs[0].estimated_costs[0].amount = 6.5;
    store.replace_session_usage(projection)?;
    wait_material_ticket(&mut materials, store.admitted_ticket()).await?;
    let row = store
        .writer
        .db
        .query_one_raw(statement(
            "SELECT amount,revision FROM call_usage_summary WHERE thread_id='another-session'",
            vec![],
        ))
        .await?
        .unwrap();
    assert_eq!(row.try_get::<f64>("", "amount")?, 6.5);
    assert_eq!(row.try_get::<i64>("", "revision")?, 10);
    assert_eq!(materials.borrow().versions.costs, 2);
    assert!(
        store
            .writer
            .log
            .lock()
            .await
            .repair_pending_index(&store.writer.db)
            .await
            .unwrap_err()
            .to_string()
            .contains(message)
    );

    store
        .writer
        .db
        .execute_unprepared(
            "DROP TRIGGER reject_locator_repair;
         CREATE TRIGGER forbid_sample_replay BEFORE INSERT ON performance_samples
         BEGIN SELECT RAISE(ABORT,'performance replayed'); END;",
        )
        .await?;
    let CallMutation::Billing(neighbor) = &pending[1].mutation else {
        unreachable!()
    };
    let retry = batch(vec![CallMutation::Billing(Box::new(PreparedRecord::new(
        neighbor.record.clone(),
    )?))]);
    let (completed, failures, deferred) = apply_batch(&store.writer, &retry).await?;
    assert_eq!(completed, 1);
    assert!(failures.is_empty() && deferred.is_none(), "{failures:?}");
    let records = indexed_bodies(&store).await?;
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].thread_id, "neighbor");
    assert_eq!(materials.borrow().versions.costs, 2);
    assert_eq!(materials.borrow().versions.performance, 1);
    store.delete_threads(&["deleted".into()]).await?;
    assert_eq!(store.recent_performance_samples(100).await?.len(), 1);
    store.close().await?;
    Ok(())
}

async fn permanent_delete_calls_failed_segment_repair(restart: bool) -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("calls.sqlite");
    let store = CallsStore::prepare(&path).await?;
    let pending = batch(vec![billing("deleted")?, billing("neighbor")?]);
    let (_, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert!(failures.is_empty() && deferred.is_none());
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE repair_parent(id INTEGER PRIMARY KEY);
         CREATE TABLE repair_probe(parent INTEGER REFERENCES repair_parent(id)
             DEFERRABLE INITIALLY DEFERRED);
         CREATE TRIGGER reject_locator_repair AFTER INSERT ON call_log_index
         WHEN NEW.thread_id='neighbor' BEGIN INSERT INTO repair_probe VALUES(1); END;",
        )
        .await?;
    let error = store.delete_threads(&["deleted".into()]).await.unwrap_err();
    assert!(error.to_string().contains("FOREIGN KEY constraint failed"));
    // Replacement completed, but no old offset is allowed to survive a failed commit.
    assert!(indexed_bodies(&store).await?.is_empty());
    let mut entries = tokio::fs::read_dir(temp.path().join("logs")).await?;
    while let Some(entry) = entries.next_entry().await? {
        assert!(
            !tokio::fs::read_to_string(entry.path())
                .await?
                .contains("\"threadId\":\"deleted\"")
        );
    }
    store
        .writer
        .db
        .execute_unprepared("DROP TRIGGER reject_locator_repair")
        .await?;
    let store = if restart {
        store.close().await?;
        CallsStore::prepare(&path).await?
    } else {
        store
    };
    // Deletion itself repairs an already-replaced segment without a later writer.
    if !restart {
        store.delete_threads(&["deleted".into()]).await?;
        let recovered = indexed_bodies(&store).await?;
        assert_eq!(recovered.len(), 1);
        assert_eq!(recovered[0].thread_id, "neighbor");
    }
    // Repair precedes identity deduplication: retrying the same neighbor billing must
    // not append it again or replay its performance sample.
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TRIGGER forbid_sample_replay BEFORE INSERT ON performance_samples
         BEGIN SELECT RAISE(ABORT,'performance replayed'); END;",
        )
        .await?;
    let CallMutation::Billing(neighbor) = &pending[1].mutation else {
        unreachable!()
    };
    let retry = batch(vec![CallMutation::Billing(Box::new(PreparedRecord::new(
        neighbor.record.clone(),
    )?))]);
    let (_, failures, deferred) = apply_batch(&store.writer, &retry).await?;
    assert!(failures.is_empty() && deferred.is_none(), "{failures:?}");
    assert_eq!(indexed_bodies(&store).await?.len(), 1);
    store.delete_threads(&["deleted".into()]).await?;
    assert_eq!(store.recent_performance_samples(100).await?.len(), 1);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_calls_invalidation_failure_preserves_original_locators() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let (_, failures, deferred) = apply_batch(
        &store.writer,
        &batch(vec![billing("deleted")?, billing("neighbor")?]),
    )
    .await?;
    assert!(failures.is_empty() && deferred.is_none());
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE invalidation_parent(id INTEGER PRIMARY KEY);
         CREATE TABLE invalidation_probe(parent INTEGER REFERENCES invalidation_parent(id)
             DEFERRABLE INITIALLY DEFERRED);
         CREATE TRIGGER reject_invalidation AFTER DELETE ON call_log_index
         BEGIN INSERT INTO invalidation_probe VALUES(1); END;",
        )
        .await?;
    let error = store.delete_threads(&["deleted".into()]).await.unwrap_err();
    assert!(error.to_string().contains("FOREIGN KEY constraint failed"));
    // The invalidation commit failed, so replacement must not have started.
    assert_eq!(indexed_bodies(&store).await?.len(), 2);
    store
        .writer
        .db
        .execute_unprepared("DROP TRIGGER reject_invalidation")
        .await?;
    store.delete_threads(&["deleted".into()]).await?;
    let records = indexed_bodies(&store).await?;
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].thread_id, "neighbor");
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_calls_cancellation_keeps_replacement_and_index_serialized() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let (_, failures, deferred) = apply_batch(
        &store.writer,
        &batch(vec![billing("deleted")?, billing("neighbor")?]),
    )
    .await?;
    assert!(failures.is_empty() && deferred.is_none());
    store
        .writer
        .db
        .execute_unprepared("CREATE TABLE deletion_blocker(value INTEGER)")
        .await?;
    let blocker = store.writer.db.begin().await?;
    blocker
        .execute_unprepared("INSERT INTO deletion_blocker VALUES(1)")
        .await?;
    let deleting = store.clone();
    let caller = tokio::spawn(async move { deleting.delete_threads(&["deleted".into()]).await });
    // The SQLite write lock holds the deletion inside its mutation task.
    tokio::time::timeout(Duration::from_secs(2), async {
        while store.writer.log.try_lock().is_ok() {
            tokio::task::yield_now().await;
        }
    })
    .await?;
    caller.abort();
    assert!(caller.await.unwrap_err().is_cancelled());
    blocker.rollback().await?;
    // Queue behind the owned deletion task, rather than racing its blocking file write.
    drop(store.writer.log.lock().await);
    let records = indexed_bodies(&store).await?;
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].thread_id, "neighbor");
    assert_eq!(store.recent_performance_samples(100).await?.len(), 1);
    store.close().await?;
    Ok(())
}

fn billing(thread: &str) -> Result<CallMutation> {
    Ok(CallMutation::Billing(Box::new(PreparedRecord::new(
        CallLogRecord {
            version: event::CALL_LOG_RECORD_VERSION,
            kind: "billing".into(),
            thread_id: thread.into(),
            call_id: "call".into(),
            status: "committed".into(),
            recorded_at: crate::studio::unix_seconds(),
            account_id: Some("account".into()),
            model_id: Some("model".into()),
            usage: Some(event::CallUsageRecord {
                output_tokens: Some(10),
                ..Default::default()
            }),
            usage_status: Some(pl_core::usage::UsageStatus::Partial),
            timing: Some(event::CallTimingRecord {
                first_output_source: crate::FirstOutputSource::Unobserved,
                response_millis: Some(100),
                ..Default::default()
            }),
            throughput_epoch: event::THROUGHPUT_EPOCH,
            ..Default::default()
        },
    )?)))
}

fn batch(mutations: Vec<CallMutation>) -> VecDeque<QueuedCallMutation> {
    mutations
        .into_iter()
        .enumerate()
        .map(|(index, mutation)| QueuedCallMutation {
            ticket: index as u64 + 1,
            accepted_at: tokio::time::Instant::now(),
            bytes: mutation.estimated_bytes(),
            mutation,
        })
        .collect()
}

#[test]
fn prepared_billing_binds_one_analysis_to_jsonl_and_sql() -> Result<()> {
    use pl_core::usage::UsageStatus;

    let CallMutation::Billing(base) = billing("thread")? else {
        unreachable!()
    };
    let mut invalid_cache = base.record.clone();
    invalid_cache.usage.as_mut().unwrap().input_tokens = Some(1);
    invalid_cache.usage.as_mut().unwrap().cache_read_tokens = Some(2);
    let mut invalid_total = base.record.clone();
    invalid_total.usage.as_mut().unwrap().input_tokens = Some(1);
    invalid_total.usage.as_mut().unwrap().total_tokens = Some(99);
    let mut unknown = base.record.clone();
    unknown.usage = Some(event::CallUsageRecord::default());
    let mut zero = base.record.clone();
    zero.usage.as_mut().unwrap().output_tokens = Some(0);
    let mut reported_zero = zero.clone();
    reported_zero.usage.as_mut().unwrap().input_tokens = Some(0);
    reported_zero.usage.as_mut().unwrap().cache_read_tokens = Some(0);
    reported_zero.usage.as_mut().unwrap().total_tokens = Some(0);
    let mut forged_invalid = base.record.clone();
    forged_invalid.usage_status = Some(UsageStatus::Invalid);
    let mut rejected = base.record.clone();
    rejected.status = CallStatus::Rejected.as_str().into();
    let mut inconsistent_timing = base.record.clone();
    inconsistent_timing.timing.as_mut().unwrap().ttft_millis = Some(1);
    let mut missing_timing = base.record.clone();
    missing_timing.timing = None;
    for (record, status, valid) in [
        (base.record.clone(), UsageStatus::Partial, true),
        (forged_invalid, UsageStatus::Partial, true),
        (invalid_cache, UsageStatus::Invalid, false),
        (invalid_total, UsageStatus::Invalid, false),
        (unknown, UsageStatus::Missing, false),
        (zero, UsageStatus::Partial, false),
        (reported_zero, UsageStatus::Reported, false),
        (rejected, UsageStatus::Partial, false),
        (inconsistent_timing, UsageStatus::Partial, false),
        (missing_timing, UsageStatus::Partial, false),
    ] {
        let analyses = std::cell::Cell::new(0);
        let prepared = PreparedRecord::with_usage_analysis(record, |report| {
            analyses.set(analyses.get() + 1);
            pl_model::model::usage::analyze(report)
        })?;
        let sample = performance::sample_from_prepared(&prepared).unwrap();
        assert_eq!(analyses.get(), 1);
        assert_eq!(prepared.usage_status, Some(status));
        assert_eq!(sample.usage_status, status);
        assert_eq!(sample.throughput_valid, valid);
        let decoded = event::decode_record(&prepared.line)?;
        assert_eq!(decoded.usage_status, Some(status));
        assert_eq!(decoded.usage, prepared.usage);
        assert_eq!(decoded.throughput_sample().is_some(), valid);
        assert_eq!(
            prepared.hash,
            pl_core::context::content_hash(prepared.line.as_bytes())
        );
        assert_eq!(
            prepared.retained_bytes(),
            prepared.line.len() + 1 + std::mem::size_of::<bool>()
        );
    }
    let mut legacy = base.record.clone();
    legacy.usage_status = Some(UsageStatus::LegacyUnknown);
    let mut absent = base.record;
    absent.usage = None;
    absent.usage_status = None;
    for record in [legacy, absent] {
        let expected_status = record.usage_status;
        let prepared = PreparedRecord::with_usage_analysis(record, |_| {
            panic!("absent or legacy raw usage cannot supply a current analysis")
        })?;
        let sample = performance::sample_from_prepared(&prepared).unwrap();
        assert_eq!(prepared.usage_status, expected_status);
        assert!(!sample.throughput_valid);
    }
    Ok(())
}

#[test]
fn truncated_billing_drops_the_original_bound_throughput_fact() -> Result<()> {
    let CallMutation::Billing(base) = billing("thread")? else {
        unreachable!()
    };
    let mut record = base.record;
    record.retention = Some(CallRetention::Internal.as_str().into());
    record.diagnostic = Some("x".repeat(event::CALL_LOG_RECORD_MAX_BYTES));
    let analyses = std::cell::Cell::new(0);
    let prepared = PreparedRecord::with_usage_analysis(record, |report| {
        analyses.set(analyses.get() + 1);
        pl_model::model::usage::analyze(report)
    })?;
    assert_eq!(analyses.get(), 1);
    assert!(prepared.truncated);
    assert!(prepared.usage.is_none());
    assert!(prepared.timing.is_none());
    assert_eq!(
        prepared.usage_status,
        Some(pl_core::usage::UsageStatus::Partial),
        "fallback keeps the explanatory status without claiming retained raw counters"
    );
    assert_eq!(
        prepared.retention.as_deref(),
        Some(CallRetention::Internal.as_str())
    );
    let sample = performance::sample_from_prepared(&prepared).unwrap();
    assert!(!sample.throughput_valid);
    assert_eq!(sample.output_tokens, None);
    let decoded = event::decode_record(&prepared.line)?;
    assert!(
        !performance::sample_from_record(&decoded)
            .unwrap()
            .throughput_valid
    );
    assert_eq!(serde_json::to_string(&decoded)?, prepared.line);
    assert!(prepared.line.len() < event::CALL_LOG_RECORD_MAX_BYTES);
    assert_eq!(
        prepared.hash,
        pl_core::context::content_hash(prepared.line.as_bytes())
    );
    let bytes = prepared.retained_bytes();
    assert_eq!(
        CallMutation::Billing(Box::new(prepared)).estimated_bytes(),
        bytes
    );
    Ok(())
}

#[tokio::test]
async fn queued_and_durable_billing_use_the_same_complete_identity_hash() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let record: InferenceBillingRecord = serde_json::from_value(serde_json::json!({
        "inferenceId": "call", "accounting": crate::InferenceAccounting::default(),
        "recordedAt": crate::studio::unix_seconds(),
    }))?;
    let ticket = store.admit_billing(
        "root",
        "thread",
        &record,
        CallStatus::Committed,
        CallRetention::Turn,
    )?;
    assert_eq!(
        store.admit_billing(
            "root",
            "thread",
            &record,
            CallStatus::Committed,
            CallRetention::Turn
        )?,
        ticket
    );
    let queued = store.metrics();
    let bytes = queued.pending_bytes;
    assert_eq!(queued.pending_operations, 1);
    let variants = [
        ("other-root", CallStatus::Committed, CallRetention::Turn),
        ("root", CallStatus::Rejected, CallRetention::Turn),
        ("root", CallStatus::Committed, CallRetention::Internal),
    ];
    for (root, status, retention) in variants {
        assert!(
            store
                .admit_billing(root, "thread", &record, status, retention)
                .is_err()
        );
    }
    let drained = drain_batch(&store.writer);
    assert_eq!(store.metrics().pending_bytes, 0);
    requeue(&store.writer, drained.into());
    assert_eq!(store.metrics().pending_bytes, bytes);
    let pending = drain_batch(&store.writer).into();
    let (_, failures, _) = apply_batch(&store.writer, &pending).await?;
    assert!(failures.is_empty());
    for (root, status, retention) in variants {
        let changed = event::billing_record(root, "thread", retention, &record, status);
        let pending = batch(vec![CallMutation::Billing(Box::new(PreparedRecord::new(
            changed,
        )?))]);
        let (_, failures, _) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(
            failures.len(),
            1,
            "durable checks reject the same conflicts as admission"
        );
    }
    store.admit_billing(
        "root",
        "another-thread",
        &record,
        CallStatus::Committed,
        CallRetention::Turn,
    )?;
    let (_, failures, _) = apply_batch(&store.writer, &drain_batch(&store.writer).into()).await?;
    assert!(
        failures.is_empty(),
        "thread identity is not a global call-id deduplication key"
    );
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn billing_sample_failure_rolls_back_locator_and_preserves_other_items() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE sample_probe(thread_id TEXT);
         CREATE TRIGGER reject_sample BEFORE INSERT ON performance_samples
         WHEN NEW.thread_id='bad' BEGIN
           INSERT INTO sample_probe VALUES(NEW.thread_id);
           SELECT RAISE(FAIL,'injected sample failure');
         END;",
        )
        .await?;
    let pending = batch(vec![billing("first")?, billing("bad")?, billing("last")?]);
    let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(completed, 3);
    assert_eq!(failures.len(), 1);
    assert!(deferred.is_none());
    let rows = store
        .writer
        .db
        .query_all_raw(statement(
            "SELECT thread_id FROM call_log_index ORDER BY thread_id",
            vec![],
        ))
        .await?;
    let ids = rows
        .iter()
        .map(|row| row.try_get::<String>("", "thread_id"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(ids, ["first", "last"]);
    assert_eq!(store.recent_performance_samples(100).await?.len(), 2);
    assert!(
        store
            .writer
            .db
            .query_all_raw(statement("SELECT * FROM sample_probe", vec![]))
            .await?
            .is_empty()
    );
    assert_eq!(store.subscribe_materials().borrow().versions.performance, 1);
    assert_eq!(
        store.processed_ticket(),
        0,
        "the batch never confirms receipts itself"
    );
    // The failed savepoint can leave a complete isolated line, but not partial SQL.
    let mut segments = tokio::fs::read_dir(temp.path().join("logs")).await?;
    let file = segments.next_entry().await?.unwrap();
    let text = tokio::fs::read_to_string(file.path()).await?;
    assert_eq!(text.lines().count(), 3);
    for line in text.lines() {
        event::decode_record(line)?;
    }
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn file_barrier_failure_cannot_publish_sql_or_material_success() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let materials = store.subscribe_materials();
    struct FailingSync;
    impl log::SegmentSync for FailingSync {
        async fn sync_data(&self, _: &tokio::fs::File) -> Result<()> {
            bail!("injected call log sync failure")
        }
    }
    let pending = batch(vec![billing("thread")?]);
    assert_eq!(
        apply_batch_with_sync(&store.writer, &pending, FailingSync)
            .await
            .err()
            .map(|error| error.to_string())
            .as_deref(),
        Some("injected call log sync failure")
    );
    assert!(store.recent_performance_samples(100).await?.is_empty());
    assert!(!materials.has_changed()?);
    assert_eq!(store.processed_ticket(), 0);
    let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(
        completed,
        1,
        "failures={failures:?}, deferred={:?}",
        deferred.as_ref().map(|failure| &failure.message)
    );
    assert!(failures.is_empty());
    assert!(deferred.is_none());
    assert_eq!(materials.borrow().versions.performance, 1);
    assert_eq!(store.recent_performance_samples(100).await?.len(), 1);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn outer_commit_failure_cannot_publish_material_success() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let materials = store.subscribe_materials();
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE commit_parent(id INTEGER PRIMARY KEY);
         CREATE TABLE commit_probe(parent INTEGER REFERENCES commit_parent(id)
             DEFERRABLE INITIALLY DEFERRED);
         CREATE TRIGGER reject_commit AFTER INSERT ON performance_samples BEGIN
             INSERT INTO commit_probe VALUES(1);
         END;",
        )
        .await?;
    let pending = batch(vec![billing("thread")?]);
    assert!(
        apply_batch(&store.writer, &pending).await.is_err(),
        "the deferred constraint fails at the outer commit, not its savepoint"
    );
    assert!(store.recent_performance_samples(100).await?.is_empty());
    assert!(!materials.has_changed()?);
    assert_eq!(store.processed_ticket(), 0);
    store
        .writer
        .db
        .execute_unprepared("DROP TRIGGER reject_commit")
        .await?;
    let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(completed, 1);
    assert!(failures.is_empty());
    assert!(deferred.is_none());
    assert_eq!(materials.borrow().versions.performance, 1);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn statistics_reads_do_not_wait_for_the_jsonl_lease() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let lease = store.writer.log.lock().await;
    let read = tokio::time::timeout(
        Duration::from_secs(2),
        store.read_statistics(StatisticsReadRequest {
            costs: true,
            performance: true,
        }),
    )
    .await??;
    assert!(read.costs.unwrap().is_empty());
    assert!(read.history.unwrap().is_empty());
    assert!(read.summary.unwrap().is_empty());
    let read = store
        .read_statistics(StatisticsReadRequest {
            costs: true,
            performance: false,
        })
        .await?;
    assert!(read.history.is_none());
    assert!(read.summary.is_none());
    drop(lease);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn acp_text_performance_is_durable_and_stays_out_of_native_summary() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let path = directory.path().join("calls.sqlite");
    let store = CallsStore::open(&path).await?;
    let mut progress = store.subscribe_materials();
    for _ in 0..2 {
        store.record_acp_performance(AcpPerformanceObservation {
            thread_id: "text-thread".into(),
            call_id: "acp:generation:1".into(),
            account_id: "agy".into(),
            account_name: "Agy".into(),
            model: Some("gemini".into()),
            effort: None,
            performance: crate::AcpTextPerformance {
                estimated_output_tokens: 50,
                response_millis: 2_000,
            },
        });
    }
    wait_material_ticket(&mut progress, store.admitted_ticket()).await?;
    store.close().await?;

    let reopened = CallsStore::open(&path).await?;
    let statistics = reopened
        .read_statistics(StatisticsReadRequest {
            costs: true,
            performance: true,
        })
        .await?;
    let history = statistics.history.unwrap();
    assert_eq!(history.len(), 1);
    assert_eq!(
        history[0].purpose.as_deref(),
        Some(performance::ACP_TEXT_ESTIMATE)
    );
    assert_eq!(history[0].completion_tokens, Some(50));
    assert_eq!(history[0].response_millis, Some(2_000));
    assert!(history[0].has_throughput_sample);
    assert!(statistics.summary.unwrap().is_empty());
    assert!(statistics.costs.unwrap().is_empty());
    reopened.close().await?;
    Ok(())
}

async fn wait_material_ticket(
    progress: &mut watch::Receiver<CallsMaterialProgress>,
    ticket: u64,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if progress.borrow_and_update().processed_ticket >= ticket {
                return Ok::<_, anyhow::Error>(());
            }
            progress.changed().await?;
        }
    })
    .await?
}

fn attempt_effect(thread: &str, call: &str, sequence: u64) -> ThreadEffectBatch {
    ThreadEffectBatch {
        thread_id: thread.into(),
        sequence,
        committed_at: crate::studio::unix_seconds(),
        attempt: Some(AttemptUpdate {
            request_metadata: None,
            usage_binding: None,
            tool_projection: None,
            turn_id: "turn".into(),
            attempt_id: call.into(),
            retry_of: None,
            input_revision: sequence,
            tools: Default::default(),
            outcome: AttemptOutcome::Running,
            input_estimate: None,
        }),
        ..Default::default()
    }
}

fn assert_empty_effect_unchanged(store: &CallsStore) -> Result<()> {
    let materials = store.subscribe_materials();
    let progress = materials.borrow().clone();
    let admitted = store.admitted_ticket();
    let processed = store.processed_ticket();
    let pressure = queue_pressure(&store.writer);
    let error = store.last_error();
    for sequence in [0, 1, u64::MAX] {
        store.record_effect(&ThreadEffectBatch {
            thread_id: "empty".into(),
            sequence,
            ..Default::default()
        });
    }
    assert_eq!(store.admitted_ticket(), admitted);
    assert_eq!(store.processed_ticket(), processed);
    let after = queue_pressure(&store.writer);
    assert_eq!(after.mutations, pressure.mutations);
    assert_eq!(after.bytes, pressure.bytes);
    assert_eq!(after.oldest_accepted_at, pressure.oldest_accepted_at);
    assert_eq!(*materials.borrow(), progress);
    assert!(!materials.has_changed()?);
    assert_eq!(store.last_error(), error);
    Ok(())
}

#[tokio::test]
async fn empty_material_is_noop_while_healthy_full_or_stopping() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    assert_empty_effect_unchanged(&store)?;
    assert_eq!(store.admitted_ticket(), 0);
    assert_eq!(store.metrics().pending_operations, 0);
    for index in 0..MAX_QUEUE_MUTATIONS {
        store.record_effect(&attempt_effect("thread", &format!("call-{index}"), 1));
    }
    assert_eq!(
        store.metrics().pending_operations,
        MAX_QUEUE_MUTATIONS as u64
    );
    assert_empty_effect_unchanged(&store)?;
    assert!(!store.statistics_gap());
    store.record_effect(&attempt_effect("thread", "overflow", 1));
    assert!(store.statistics_gap());
    assert_eq!(store.admitted_ticket(), MAX_QUEUE_MUTATIONS as u64);
    assert_empty_effect_unchanged(&store)?;
    store.stop_best_effort();
    assert_empty_effect_unchanged(&store)?;
    store.record_effect(&attempt_effect("thread", "stopped", 1));
    assert!(store.last_error().unwrap().contains("stopping"));
    assert_empty_effect_unchanged(&store)?;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn attempt_and_delivery_revisions_are_idempotent_without_effect_fences() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    store
        .writer
        .db
        .execute_unprepared(
            "INSERT INTO legacy_call_fences VALUES('thread',99,98);
         CREATE TRIGGER forbid_fence_insert BEFORE INSERT ON legacy_call_fences
         BEGIN SELECT RAISE(ABORT,'production fence insert'); END;
         CREATE TRIGGER forbid_fence_update BEFORE UPDATE ON legacy_call_fences
         BEGIN SELECT RAISE(ABORT,'production fence update'); END;",
        )
        .await?;
    let mut effect = attempt_effect("thread", "shared-id", 1);
    effect.deliveries = vec![pl_core::thread::ToolDelivery {
        target: Default::default(),
        call_id: "shared-id".into(),
        tool_id: "tool".into(),
        output: pl_core::tool::ToolOutput::new(
            pl_core::context::OpaquePayload::text("result"),
            vec![],
        ),
        delivered_context: vec![],
        outcome: pl_core::thread::ToolOutcome::Succeeded,
    }]
    .into();
    for sequence in [1, 1, 3, 2, 3] {
        effect.sequence = sequence;
        store.record_effect(&effect);
    }
    let pending = drain_batch(&store.writer).into();
    let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(completed, 5);
    assert!(failures.is_empty());
    assert!(deferred.is_none());
    let rows = store
        .writer
        .db
        .query_all_raw(statement(
            "SELECT kind,revision FROM call_log_index ORDER BY kind",
            vec![],
        ))
        .await?;
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0].try_get::<String>("", "kind")?, "attempt");
    assert_eq!(rows[1].try_get::<String>("", "kind")?, "tool");
    for row in rows {
        assert_eq!(row.try_get::<i64>("", "revision")?, 3);
    }
    let fence = store.writer.db.query_one_raw(statement(
        "SELECT admitted_write_seq,durable_write_seq FROM legacy_call_fences WHERE thread_id='thread'",
        vec![],
    )).await?.unwrap();
    assert_eq!(fence.try_get::<i64>("", "admitted_write_seq")?, 99);
    assert_eq!(fence.try_get::<i64>("", "durable_write_seq")?, 98);
    let mut entries = tokio::fs::read_dir(temp.path().join("logs")).await?;
    let mut lines = 0;
    while let Some(entry) = entries.next_entry().await? {
        lines += tokio::fs::read_to_string(entry.path())
            .await?
            .lines()
            .count();
    }
    assert_eq!(lines, 4, "duplicates and older revisions append no JSONL");
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn records_retry_keeps_committed_prefix_and_recovers_without_duplicates() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("calls.sqlite");
    let store = CallsStore::prepare(&path).await?;
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE busy_gate(enabled INTEGER NOT NULL);
         INSERT INTO busy_gate VALUES(1);
         CREATE TRIGGER busy_record BEFORE INSERT ON call_log_index
         WHEN NEW.call_id='retry' AND (SELECT enabled FROM busy_gate)=1 BEGIN
             SELECT RAISE(FAIL,'database is busy');
         END;",
        )
        .await?;
    for (index, call) in ["first", "retry", "last"].into_iter().enumerate() {
        store.record_effect(&attempt_effect("thread", call, index as u64 + 1));
    }
    let mut materials = store.subscribe_materials();
    store.start().await;
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let progress = materials.borrow_and_update().clone();
            if progress
                .last_error
                .as_deref()
                .is_some_and(|error| error.contains("database is busy"))
            {
                break;
            }
            materials.changed().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await??;
    assert_eq!(materials.borrow().processed_ticket, 1);
    assert_eq!(materials.borrow().versions.status, 2); // one committed prefix, one error
    assert!(!materials.borrow().statistics_gap);
    let rows = store
        .writer
        .db
        .query_all_raw(statement(
            "SELECT call_id FROM call_log_index ORDER BY call_id",
            vec![],
        ))
        .await?;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].try_get::<String>("", "call_id")?, "first");
    store
        .writer
        .db
        .execute_unprepared("UPDATE busy_gate SET enabled=0")
        .await?;
    store.writer.retry_notify.notify_one();
    wait_material_ticket(&mut materials, 3).await?;
    assert!(!store.statistics_gap());
    assert!(store.last_error().is_none());
    store.close().await?;
    let reopened = CallsStore::open(&path).await?;
    assert_eq!(
        reopened
            .writer
            .db
            .query_all_raw(statement("SELECT call_id FROM call_log_index", vec![],))
            .await?
            .len(),
        3
    );
    reopened.close().await?;
    Ok(())
}

async fn assert_busy_recovery_preserves_gap(prior_rejection: bool) -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE busy_gate(enabled INTEGER NOT NULL);
         INSERT INTO busy_gate VALUES(1);
         CREATE TRIGGER busy_effect BEFORE INSERT ON call_log_index
         WHEN NEW.call_id='retry' AND (SELECT enabled FROM busy_gate)=1 BEGIN
            SELECT RAISE(FAIL,'database is busy');
         END;
         CREATE TRIGGER rejected_effect BEFORE INSERT ON call_log_index
         WHEN NEW.call_id='rejected' BEGIN
            SELECT RAISE(FAIL,'injected rejected fact');
         END;",
        )
        .await?;
    let mut materials = store.subscribe_materials();
    store.start().await;
    if prior_rejection {
        store.record_effect(&attempt_effect("thread", "rejected", 1));
        wait_material_ticket(&mut materials, store.admitted_ticket()).await?;
        assert!(materials.borrow().statistics_gap);
        assert_eq!(materials.borrow().versions.performance, 0);
        assert_eq!(materials.borrow().versions.costs, 0);
        assert_empty_effect_unchanged(&store)?;
    }
    store.record_effect(&attempt_effect("thread", "retry", 2));
    let ticket = store.admitted_ticket();
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            if materials
                .borrow_and_update()
                .last_error
                .as_deref()
                .is_some_and(|error| error.contains("database is busy"))
            {
                return Ok::<_, anyhow::Error>(());
            }
            materials.changed().await?;
        }
    })
    .await??;
    assert_eq!(materials.borrow().statistics_gap, prior_rejection);
    assert!(
        materials
            .borrow()
            .last_error
            .as_deref()
            .unwrap()
            .contains("database is busy")
    );
    store
        .writer
        .db
        .execute_unprepared("UPDATE busy_gate SET enabled=0")
        .await?;
    store.writer.retry_notify.notify_one();
    wait_material_ticket(&mut materials, ticket).await?;
    assert_eq!(store.processed_ticket(), ticket);
    assert!(materials.borrow().last_error.is_none());
    assert_eq!(materials.borrow().statistics_gap, prior_rejection);
    assert_eq!(store.statistics_gap(), prior_rejection);
    store.close().await?;
    assert_eq!(store.statistics_gap(), prior_rejection);
    Ok(())
}

#[tokio::test]
async fn transient_busy_retry_succeeds_without_creating_statistics_gaps() -> Result<()> {
    assert_busy_recovery_preserves_gap(false).await
}

#[tokio::test]
async fn successful_busy_retry_preserves_prior_rejection_gaps() -> Result<()> {
    assert_busy_recovery_preserves_gap(true).await
}

#[tokio::test]
async fn summary_alone_notifies_costs_and_rejects_same_revision_conflicts() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
    let mut materials = store.subscribe_materials();
    let projection = SessionUsageProjection {
        root_thread_id: "root".into(),
        thread_id: "thread".into(),
        revision: 1,
        has_unpriced_usage: false,
        purpose_costs: vec![],
    };
    store.replace_session_usage(projection.clone())?;
    let mut conflict = projection.clone();
    conflict.has_unpriced_usage = true;
    assert!(store.replace_session_usage(conflict.clone()).is_err());
    store.start().await;
    tokio::time::timeout(Duration::from_secs(2), async {
        loop {
            let progress = materials.borrow_and_update().clone();
            if progress.versions.costs == 1 && progress.processed_ticket == 1 {
                break;
            }
            materials.changed().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await??;
    assert_eq!(materials.borrow().versions.performance, 0);
    let pending = batch(vec![CallMutation::Summary(PreparedSummary::new(conflict)?)]);
    let (_, failures, _) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(failures.len(), 1);
    assert_eq!(materials.borrow().versions.costs, 1);
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn unwritable_diagnostics_do_not_starve_absolute_accounting() -> Result<()> {
    let temp = tempfile::tempdir()?;
    tokio::fs::write(temp.path().join("logs"), b"blocked directory").await?;
    let store = CallsStore::open(&temp.path().join("calls.sqlite")).await?;
    let record = CallLogRecord {
        version: event::CALL_LOG_RECORD_VERSION,
        kind: "billing".into(),
        thread_id: "thread".into(),
        call_id: "call".into(),
        status: "committed".into(),
        recorded_at: crate::studio::unix_seconds(),
        ..Default::default()
    };
    let mutations = [
        CallMutation::Billing(Box::new(PreparedRecord::new(record)?)),
        CallMutation::Summary(PreparedSummary::new(SessionUsageProjection {
            root_thread_id: "thread".into(),
            thread_id: "thread".into(),
            revision: 7,
            has_unpriced_usage: false,
            purpose_costs: vec![PurposeUsageProjection {
                purpose: None,
                estimated_costs: vec![RuntimeCostAmount {
                    currency: "USD".into(),
                    amount: 3.0,
                }],
            }],
        })?),
    ];
    let pending = mutations
        .into_iter()
        .enumerate()
        .map(|(index, mutation)| QueuedCallMutation {
            ticket: index as u64 + 1,
            accepted_at: tokio::time::Instant::now(),
            bytes: mutation.estimated_bytes(),
            mutation,
        })
        .collect();
    let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(completed, 2);
    assert_eq!(failures.len(), 1);
    assert!(deferred.is_none());
    assert!(
        !store.statistics_gap(),
        "unavailable diagnostics alone did not discard an accounting fact"
    );
    for failure in &failures {
        fail_mutation(&store.writer, failure);
    }
    assert!(store.statistics_gap());
    assert_eq!(
        store.session_cost_rollups().await?[0].estimated_costs[0].amount,
        3.0
    );
    store.stop_best_effort();
    Ok(())
}

#[tokio::test]
async fn batch_savepoint_failure_preserves_other_calls_and_commits_before_receipts() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp.path().join("calls.sqlite");
    let store = CallsStore::prepare(&path).await?;
    store
        .writer
        .db
        .execute_unprepared(
            "CREATE TABLE failure_probe(thread_id TEXT NOT NULL);
             CREATE TRIGGER reject_one BEFORE INSERT ON call_log_index
             WHEN NEW.thread_id='rejected' BEGIN
               INSERT INTO failure_probe VALUES(NEW.thread_id);
               SELECT RAISE(FAIL,'injected invalid call');
             END;",
        )
        .await?;
    for thread in ["first", "rejected", "last"] {
        store.record_effect(&attempt_effect(thread, "call", 1));
    }
    let pending = drain_batch(&store.writer).into();
    let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
    assert_eq!(completed, 3);
    assert_eq!(failures.len(), 1);
    assert!(failures[0].contains("injected invalid call"));
    assert!(deferred.is_none());
    // An independent connection observes both committed facts before a receipt is advanced.
    let reader = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::ReadOnly,
            |options| options,
        )
        .await?,
    )
    .await?;
    let rows = reader
        .query_all_raw(statement(
            "SELECT thread_id FROM call_log_index ORDER BY thread_id",
            vec![],
        ))
        .await?;
    let ids = rows
        .iter()
        .map(|row| row.try_get::<String>("", "thread_id"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(ids, ["first", "last"]);
    // RAISE(FAIL) preserves earlier trigger writes unless the mutation's savepoint rolls back.
    let failed_writes = reader
        .query_all_raw(statement("SELECT thread_id FROM failure_probe", vec![]))
        .await?;
    assert!(failed_writes.is_empty());
    assert_eq!(*store.writer.processed_ticket.borrow(), 0);
    store.close().await?;
    reader.close().await?;
    Ok(())
}
