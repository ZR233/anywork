//! 任务索引的离线回填、事务失败与独立按身份读取。
#![cfg(feature = "sqlite")]
#[path = "support/effect_fixture.rs"]
mod effect_fixture;

use pl_core::{
    context::OpaquePayload,
    persistence::{SqliteSessionOptions, SqliteSessionStore, migration},
    thread::{
        ThreadEffectBatch, ToolDelivery, ToolOutcome,
        cold::ColdStore,
        task::{TaskRecord, TaskStatus},
    },
    tool::ToolOutput,
};
use pretty_assertions::assert_eq;
use sea_orm::{ConnectionTrait, Database, DatabaseBackend, Statement};
use std::sync::Arc;

async fn seed() -> (tempfile::TempDir, SqliteSessionOptions) {
    seed_count(2).await
}

async fn seed_count(count: u64) -> (tempfile::TempDir, SqliteSessionOptions) {
    let root = tempfile::tempdir().unwrap();
    let options = SqliteSessionOptions {
        path: root.path().join("history.sqlite"),
    };
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    for sequence in 1..=count {
        let id = format!("call-{sequence}");
        let task = TaskRecord {
            id: format!("task:{id}"),
            call_id: id.clone(),
            tool_id: "exec".into(),
            turn_id: "turn".into(),
            revision: 2,
            status: TaskStatus::Succeeded,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(sequence),
        };
        let effect = ThreadEffectBatch {
            thread_id: "owner".into(),
            sequence,
            tasks: Arc::from([task]),
            deliveries: Arc::from([ToolDelivery {
                target: Default::default(),
                call_id: id,
                tool_id: "exec".into(),
                output: ToolOutput::new(OpaquePayload::text("complete result"), vec![]),
                delivered_context: vec![],
                outcome: ToolOutcome::Succeeded,
            }]),
            ..Default::default()
        };
        store
            .register_resource(
                "owner",
                &format!("thread-commit.{sequence:020}"),
                effect.encode().unwrap(),
            )
            .unwrap();
    }
    store.flush().await.unwrap();
    store.shutdown().await.unwrap();
    (root, options)
}

async fn database(options: &SqliteSessionOptions) -> sea_orm::DatabaseConnection {
    Database::connect(format!("sqlite://{}?mode=rw", options.path.display()))
        .await
        .unwrap()
}

#[tokio::test]
async fn v11_task_index_migration_is_atomic_and_preserves_source_effects() {
    let (_root, options) = seed().await;
    let db = database(&options).await;
    let original_history = stored_history(&db).await;
    let original = db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT envelope FROM session_entries ORDER BY id",
        ))
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.try_get::<String>("", "envelope").unwrap())
        .collect::<Vec<_>>();
    db.execute_unprepared("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; DROP TABLE IF EXISTS seaql_migrations; PRAGMA user_version=11;
        UPDATE session_entries SET payload_hash='damaged' WHERE id='pl.resource.thread-commit.00000000000000000002'").await.unwrap();
    db.close().await.unwrap();
    assert!(SqliteSessionStore::open(options.clone()).await.is_err());
    assert!(
        migration::migrate_to_current(options.clone())
            .await
            .is_err()
    );
    let db = database(&options).await;
    let version = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "PRAGMA user_version",
        ))
        .await
        .unwrap()
        .unwrap()
        .try_get::<i64>("", "user_version")
        .unwrap();
    assert_eq!(version, 11);
    let tables = db.query_all_raw(Statement::from_string(DatabaseBackend::Sqlite,
        "SELECT name FROM sqlite_schema WHERE name IN ('thread_tool_tasks','thread_tool_task_resources')")).await.unwrap();
    assert!(tables.is_empty(), "失败的回填不能留下半份索引");
    db.execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
        "UPDATE session_entries SET payload_hash=? WHERE id='pl.resource.thread-commit.00000000000000000002'",
        vec![pl_core::context::content_hash(original[1].as_bytes()).into()])).await.unwrap();
    db.close().await.unwrap();
    migration::migrate_to_current(options.clone())
        .await
        .unwrap();
    migration::migrate_to_current(options.clone())
        .await
        .unwrap();
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    for sequence in 1..=2 {
        let fact = ColdStore::read_tool_task(&store, "owner", &format!("task:call-{sequence}"))
            .await
            .unwrap()
            .unwrap();
        let effect = store
            .read_thread_effect("owner", sequence)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            serde_json::to_value((&fact.task, fact.delivery)).unwrap(),
            serde_json::to_value((&effect.tasks[0], Some(&effect.deliveries[0]))).unwrap()
        );
    }
    store.shutdown().await.unwrap();
    let db = database(&options).await;
    let after = db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT envelope FROM session_entries ORDER BY id",
        ))
        .await
        .unwrap()
        .into_iter()
        .map(|row| row.try_get::<String>("", "envelope").unwrap())
        .collect::<Vec<_>>();
    assert_eq!(after, original);
    assert_eq!(stored_history(&db).await, original_history);
    db.close().await.unwrap();
    assert!(
        SqliteSessionStore::delete_session(options.clone(), "owner")
            .await
            .unwrap()
    );
    let store = SqliteSessionStore::open(options).await.unwrap();
    assert!(
        ColdStore::read_tool_task(&store, "owner", "task:call-1")
            .await
            .unwrap()
            .is_none()
    );
    store.shutdown().await.unwrap();
}

#[tokio::test]
async fn by_id_task_read_is_independent_and_rejects_corrupt_index() {
    let (_root, options) = seed().await;
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    let db = database(&options).await;
    // 故障注入只损坏另一个 effect；目标定位不能依赖扫描整段历史。
    db.execute_unprepared("UPDATE session_entries SET payload_hash='damaged' WHERE id='pl.resource.thread-commit.00000000000000000002'").await.unwrap();
    db.close().await.unwrap();
    let task = ColdStore::read_tool_task(&store, "owner", "task:call-1")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(task.task.call_id, "call-1");
    assert!(
        ColdStore::read_tool_task(&store, "owner", "task:missing")
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        ColdStore::read_tool_task(&store, "different-thread", "task:call-1")
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        ColdStore::read_tool_task(&store, "owner", "task:call-2")
            .await
            .is_err()
    );
    let db = database(&options).await;
    db.execute_unprepared(
        "UPDATE thread_tool_tasks SET task_hash='damaged' WHERE task_id='task:call-1'",
    )
    .await
    .unwrap();
    db.close().await.unwrap();
    assert!(
        ColdStore::read_tool_task(&store, "owner", "task:call-1")
            .await
            .is_err(),
        "损坏的索引必须报错，不能回落原始历史读出成功"
    );
    store.shutdown().await.unwrap();
}

#[tokio::test]
async fn task_index_migration_rejects_an_effect_gap() {
    let (_root, options) = seed().await;
    let db = database(&options).await;
    db.execute_unprepared("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; DROP TABLE IF EXISTS seaql_migrations; PRAGMA user_version=11;
        DELETE FROM session_entries WHERE id='pl.resource.thread-commit.00000000000000000001'").await.unwrap();
    db.close().await.unwrap();
    assert!(
        migration::migrate_to_current(options.clone())
            .await
            .is_err()
    );
    let db = database(&options).await;
    let version = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "PRAGMA user_version",
        ))
        .await
        .unwrap()
        .unwrap()
        .try_get::<i64>("", "user_version")
        .unwrap();
    assert_eq!(version, 11);
    db.close().await.unwrap();
}

// Build a supported v2 fixture, not a pre-v2 Thread execution journal. Only the outer tag changes;
// unknown producer material remains a byte-preservation obligation of the actual migration.
fn legacy_tag(entry: &mut pl_core::storage::SessionEntry) {
    entry.type_id = "pl.core.thread-commit".into();
    entry.schema_version = 3;
    let mut body: serde_json::Value = serde_json::from_str(&entry.payload).unwrap();
    body["privateContext"] = serde_json::json!({
        "kind": "set",
        "value": OpaquePayload::new("unknown.vendor.context", 42, " {opaque bytes} ").unwrap(),
    });
    body["futureProducerField"] = serde_json::json!({"opaque": [null, {"value": "preserve"}]});
    entry.payload = serde_json::to_string_pretty(&body).unwrap();
}

async fn make_v2_effects(db: &sea_orm::DatabaseConnection) {
    effect_fixture::rewrite_effects(db, legacy_tag).await;
    // Retain every previously published migration identity, as a real SeaORM-upgraded v12 does.
    db.execute_unprepared("DELETE FROM seaql_migrations WHERE version IN ('m20261026_000008_core_effect_batch_v1','m20261026_000009_core_checkpoint_v6'); PRAGMA user_version=12").await.unwrap();
}

async fn stored_entries(db: &sea_orm::DatabaseConnection) -> Vec<pl_core::storage::SessionEntry> {
    db.query_all_raw(Statement::from_string(
        DatabaseBackend::Sqlite,
        "SELECT envelope FROM session_entries ORDER BY id",
    ))
    .await
    .unwrap()
    .into_iter()
    .map(|row| serde_json::from_str(&row.try_get::<String>("", "envelope").unwrap()).unwrap())
    .collect()
}

async fn stored_history(db: &sea_orm::DatabaseConnection) -> Vec<(String, String)> {
    db.query_all_raw(Statement::from_string(
        DatabaseBackend::Sqlite,
        "SELECT envelope,payload_hash FROM session_entry_history ORDER BY session_id,sequence",
    ))
    .await
    .unwrap()
    .into_iter()
    .map(|row| {
        (
            row.try_get("", "envelope").unwrap(),
            row.try_get("", "payload_hash").unwrap(),
        )
    })
    .collect()
}

#[test]
fn current_effect_codec_refuses_legacy_tags() {
    let current = ThreadEffectBatch {
        thread_id: "owner".into(),
        sequence: 1,
        ..Default::default()
    }
    .encode()
    .unwrap();
    assert!(ThreadEffectBatch::decode(&current).is_ok());
    for (format, version) in [
        ("pl.core.thread-commit", 3),
        ("pl.core.thread-commit", 2),
        ("pl.core.thread-effect-batch", 2),
    ] {
        let old = OpaquePayload::new(format, version, current.content()).unwrap();
        assert!(matches!(
            ThreadEffectBatch::decode(&old),
            Err(pl_core::thread::journal::JournalCodecError::Unsupported { .. })
        ));
    }
}

#[tokio::test]
async fn supported_v2_effects_normalize_both_copies_without_changing_facts() {
    for schema in [7, 8, 9, 10, 11, 12] {
        // Exercise both pagination boundaries, not just the first small fixture page.
        let count = if schema == 12 { 130 } else { 2 };
        let (_root, options) = seed_count(count).await;
        let db = database(&options).await;
        make_v2_effects(&db).await;
        if schema < 12 {
            db.execute_unprepared(&format!("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; DROP TABLE seaql_migrations; PRAGMA user_version={schema}")).await.unwrap();
        }
        if schema == 7 {
            db.execute_unprepared("DROP TABLE thread_checkpoints")
                .await
                .unwrap();
        }
        let mut expected = stored_entries(&db).await;
        for entry in &mut expected {
            entry.type_id = "pl.core.thread-effect-batch".into();
            entry.schema_version = 1;
        }
        db.close().await.unwrap();
        let before_open = tokio::fs::read(&options.path).await.unwrap();
        assert!(SqliteSessionStore::open(options.clone()).await.is_err());
        assert_eq!(tokio::fs::read(&options.path).await.unwrap(), before_open);
        migration::migrate_to_current(options.clone())
            .await
            .unwrap();
        let db = database(&options).await;
        assert_eq!(stored_entries(&db).await, expected);
        db.close().await.unwrap();
        let store = SqliteSessionStore::open(options.clone()).await.unwrap();
        // These public reads independently validate history digests, the committed head, ownership
        // and final projection. A migration updating only session_entries cannot satisfy them.
        assert_eq!(store.replay_entries("owner", None).await.unwrap(), expected);
        let history = store.read_entry_history("owner", None).await.unwrap();
        assert_eq!(history.len() as u64, count);
        for (index, batch) in history.iter().enumerate() {
            assert_eq!(batch.sequence(), index as u64 + 1);
            assert_eq!(
                batch.changes(),
                &[pl_core::storage::SessionEntryChange::Put {
                    entry: expected[index].clone()
                }]
            );
        }
        for sequence in [1, count] {
            let effect = store
                .read_thread_effect("owner", sequence)
                .await
                .unwrap()
                .unwrap();
            let task = ColdStore::read_tool_task(&store, "owner", &format!("task:call-{sequence}"))
                .await
                .unwrap()
                .unwrap();
            assert_eq!(task.task.call_id, effect.tasks[0].call_id);
            assert_eq!(
                effect.deliveries[0].output.payload().content(),
                "complete result"
            );
        }
        store.shutdown().await.unwrap();
        let before_retry = tokio::fs::read(&options.path).await.unwrap();
        migration::migrate_to_current(options.clone())
            .await
            .unwrap();
        assert_eq!(tokio::fs::read(&options.path).await.unwrap(), before_retry);
    }
}

#[tokio::test]
async fn pre_v2_databases_are_refused_without_rewriting() {
    for version in [0, 1, 6] {
        let (_root, options) = seed().await;
        let db = database(&options).await;
        db.execute_unprepared(&format!("PRAGMA user_version={version}"))
            .await
            .unwrap();
        db.close().await.unwrap();
        let before = tokio::fs::read(&options.path).await.unwrap();
        assert!(SqliteSessionStore::open(options.clone()).await.is_err());
        assert!(
            migration::migrate_to_current(options.clone())
                .await
                .is_err()
        );
        assert_eq!(tokio::fs::read(&options.path).await.unwrap(), before);
    }
}

#[tokio::test]
async fn effect_normalization_rolls_back_corruption_and_retries_from_source() {
    for fault in [
        "entry_hash",
        "history_hash",
        "head_hash",
        "gap",
        "zero_sequence",
        "owner",
        "format",
        "effect_gap",
        "disagreement",
        "missing_delete",
    ] {
        let (_root, options) = seed().await;
        let db = database(&options).await;
        make_v2_effects(&db).await;
        // Restore from the exact test-owned fixture after rejection, then retry the real migration.
        db.close().await.unwrap();
        let valid = tokio::fs::read(&options.path).await.unwrap();
        let db = database(&options).await;
        match fault {
            "entry_hash" => {
                db.execute_unprepared("UPDATE session_entries SET payload_hash='damaged' WHERE id='pl.resource.thread-commit.00000000000000000002'").await.unwrap();
            }
            "history_hash" => {
                db.execute_unprepared(
                    "UPDATE session_entry_history SET payload_hash='damaged' WHERE sequence=2",
                )
                .await
                .unwrap();
            }
            "head_hash" => {
                db.execute_unprepared("UPDATE session_history_heads SET payload_hash='damaged'")
                    .await
                    .unwrap();
            }
            "gap" => {
                db.execute_unprepared("DELETE FROM session_entry_history WHERE sequence=1")
                    .await
                    .unwrap();
            }
            "zero_sequence" => {
                db.execute_unprepared(
                    "UPDATE session_entry_history SET sequence=0 WHERE sequence=1",
                )
                .await
                .unwrap();
            }
            "owner" | "format" | "effect_gap" => {
                effect_fixture::rewrite_effects(&db, |entry| {
                    let mut body: serde_json::Value = serde_json::from_str(&entry.payload).unwrap();
                    if fault == "format" {
                        entry.schema_version = 99;
                    } else if fault == "owner" {
                        body["threadId"] = "wrong-owner".into();
                    } else {
                        // Keep generic entry history fully consistent while breaking only the
                        // effect chain. An entry-only ordering check cannot detect this fault.
                        let sequence = body["sequence"].as_u64().unwrap();
                        let next = if sequence == 2 { 3 } else { sequence };
                        body["sequence"] = next.into();
                        entry.id = format!("pl.resource.thread-commit.{next:020}");
                    }
                    entry.payload = serde_json::to_string(&body).unwrap();
                })
                .await;
            }
            "disagreement" => {
                let mut entries = stored_entries(&db).await;
                let entry = &mut entries[1];
                entry.revision += 1;
                let envelope = serde_json::to_string(entry).unwrap();
                db.execute_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "UPDATE session_entries SET envelope=?,payload_hash=? WHERE id=?",
                    vec![
                        envelope.clone().into(),
                        pl_core::context::content_hash(envelope.as_bytes()).into(),
                        entry.id.clone().into(),
                    ],
                ))
                .await
                .unwrap();
            }
            "missing_delete" => {
                let row = db
                    .query_one_raw(Statement::from_string(
                        DatabaseBackend::Sqlite,
                        "SELECT envelope FROM session_entry_history WHERE sequence=2",
                    ))
                    .await
                    .unwrap()
                    .unwrap();
                let mut batch: serde_json::Value =
                    serde_json::from_str(&row.try_get::<String>("", "envelope").unwrap()).unwrap();
                batch["changes"]
                    .as_array_mut()
                    .unwrap()
                    .push(serde_json::json!({"kind":"delete","entryId":"never-existed"}));
                let envelope = serde_json::to_string(&batch).unwrap();
                let hash = pl_core::context::content_hash(envelope.as_bytes());
                db.execute_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "UPDATE session_entry_history SET envelope=?,payload_hash=? WHERE sequence=2",
                    vec![envelope.into(), hash.clone().into()],
                ))
                .await
                .unwrap();
                db.execute_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "UPDATE session_history_heads SET payload_hash=?",
                    vec![hash.into()],
                ))
                .await
                .unwrap();
            }
            _ => unreachable!(),
        }
        db.close().await.unwrap();
        let corrupted = tokio::fs::read(&options.path).await.unwrap();
        assert!(
            migration::migrate_to_current(options.clone())
                .await
                .is_err(),
            "{fault}"
        );
        assert_eq!(
            tokio::fs::read(&options.path).await.unwrap(),
            corrupted,
            "{fault} must roll back all writes and ledger/version changes"
        );
        tokio::fs::write(&options.path, valid).await.unwrap();
        migration::migrate_to_current(options.clone())
            .await
            .unwrap();
        let store = SqliteSessionStore::open(options).await.unwrap();
        assert_eq!(store.replay_entries("owner", None).await.unwrap().len(), 2);
        store.shutdown().await.unwrap();
    }
}
