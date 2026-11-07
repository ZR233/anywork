//! Real SQLite content protocol work, deliberately below the full effect writer.
use super::*;
use serde::Serialize;
use std::{cell::RefCell, collections::BTreeMap, sync::Mutex, time::Instant};

#[derive(Default, Clone, Serialize)]
struct BodyWork {
    materialized_old_rows: u64,
    materialized_old_bytes: u64,
    written_chunk_rows: u64,
    written_chunk_bytes: u64,
}
thread_local! {
    // These tests use Tokio's current-thread runtime. No body bytes are retained here.
    static WORK: RefCell<Option<BodyWork>> = const { RefCell::new(None) };
}
pub(super) fn materialized(bytes: usize) {
    WORK.with_borrow_mut(|work| {
        if let Some(work) = work {
            work.materialized_old_rows += 1;
            work.materialized_old_bytes += bytes as u64;
        }
    });
}
pub(super) fn written(bytes: usize) {
    WORK.with_borrow_mut(|work| {
        if let Some(work) = work {
            work.written_chunk_rows += 1;
            work.written_chunk_bytes += bytes as u64;
        }
    });
}
#[derive(Default, Serialize)]
struct SqlWork {
    calls: u64,
    elapsed_micros: u64,
    failed: u64,
}
#[derive(Serialize)]
struct Phase {
    slices: usize,
    phase: &'static str,
    elapsed_micros: u64,
    body: BodyWork,
    sql: BTreeMap<String, SqlWork>,
}

#[tokio::test]
#[ignore = "explicit save baseline evidence; writes report to SAVE_WORK_REPORT"]
async fn sqlite_content_append_seal_replay_work() -> Result<()> {
    measure(false).await
}

#[tokio::test]
#[ignore = "explicit incremental comparison; writes report to SAVE_WORK_REPORT"]
async fn sqlite_incremental_append_seal_replay_work() -> Result<()> {
    measure(true).await
}

async fn measure(incremental: bool) -> Result<()> {
    let report = std::env::var("SAVE_WORK_REPORT")?;
    let mut phases = Vec::new();
    for slices in [4, 16, 64] {
        let (_dir, mut db) = super::super::tests::fixture().await?;
        let capture = Arc::new(Mutex::new(None::<BTreeMap<String, SqlWork>>));
        let metrics = capture.clone();
        // Install on the actual wrapper: cloning DatabaseConnection loses its callback.
        db.set_metric_callback(move |info| {
            if let Some(sql) = metrics.lock().unwrap().as_mut() {
                assert!(sql.len() < 32 && info.statement.sql.len() < 8192);
                let entry = sql.entry(info.statement.sql.clone()).or_default();
                entry.calls += 1;
                entry.elapsed_micros += info.elapsed.as_micros() as u64;
                entry.failed += u64::from(info.failed);
            }
        });
        let key = ChatContentKey {
            owner: ChatKey::new("item", "synthetic-save-work")?,
            key: "body".into(),
        };
        let make = |length| ChatContent {
            descriptor: ContentDescriptor {
                key: key.clone(),
                byte_length: length as u64,
                generation: 1,
                media_type: Some("text/plain".into()),
            },
            data: ContentData::Bytes(Arc::from(vec![b'x'; length])),
        };
        let initial = make(64 * 1024);
        if incremental {
            write_operation(&db, &initial, false, &CurrentContentOperation::Create, None).await?;
        } else {
            write_content(&db, &initial, false).await?;
        }
        for phase in ["append", "seal", "durableReplay"] {
            WORK.set(Some(BodyWork::default()));
            *capture.lock().unwrap() = Some(BTreeMap::new());
            let start = Instant::now();
            if phase == "append" {
                for slice in 1..=slices {
                    let length = 64 * 1024 + (1024 * 1024 - 64 * 1024) * slice / slices;
                    if incremental {
                        let prior = 64 * 1024 + (1024 * 1024 - 64 * 1024) * (slice - 1) / slices;
                        let content = make(length);
                        let mut expected = CurrentContentState::new(&content.descriptor, false);
                        expected.byte_length = prior as u64;
                        write_operation(
                            &db,
                            &content,
                            false,
                            &CurrentContentOperation::Append(expected),
                            None,
                        )
                        .await?;
                    } else {
                        write_content(&db, &make(length), false).await?;
                    }
                }
            } else if incremental && phase == "seal" {
                let content = make(1024 * 1024);
                write_operation(
                    &db,
                    &content,
                    true,
                    &CurrentContentOperation::Seal(CurrentContentState::new(
                        &content.descriptor,
                        false,
                    )),
                    None,
                )
                .await?;
            } else {
                write_content(&db, &make(1024 * 1024), phase == "seal").await?;
            }
            let elapsed_micros = start.elapsed().as_micros() as u64;
            let body = WORK.take().unwrap();
            let sql = capture.lock().unwrap().take().unwrap();
            assert!(sql.values().all(|sample| sample.failed == 0));
            if phase == "append" {
                assert_eq!(body.written_chunk_bytes, 960 * 1024);
                if incremental {
                    assert_eq!(body.materialized_old_bytes, 0);
                    assert_eq!(body.materialized_old_rows, 0);
                } else {
                    assert!(body.materialized_old_bytes > 0);
                }
            } else {
                assert_eq!(body.materialized_old_bytes, 1024 * 1024);
                assert_eq!(body.written_chunk_bytes, 0);
            }
            phases.push(Phase {
                slices,
                phase,
                elapsed_micros,
                body,
                sql,
            });
        }
    }
    std::fs::write(
        report,
        serde_json::to_vec_pretty(&serde_json::json!({
            "scope": "real SQLite low-level content protocol; not full effect writer or physical IO",
            "mode": if incremental { "prepared delta operations" } else { "original full snapshot validation" },
            "startBytes": 65536, "endBytes": 1048576, "phases": phases
        }))?,
    )?;
    Ok(())
}
