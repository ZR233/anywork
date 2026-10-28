//! 任务索引的离线回填、事务失败与独立按身份读取。
#![cfg(feature = "sqlite")]
mod support;

use pl_core::{
    context::OpaquePayload,
    persistence::{SqliteSessionOptions, SqliteSessionStore, migration},
    thread::{
        ThreadEffectBatch, ThreadHandle, ToolDelivery, ToolOutcome,
        cold::ColdStore,
        task::{TaskRecord, TaskStatus},
    },
    tool::ToolOutput,
};
use pretty_assertions::assert_eq;
use sea_orm::{ConnectionTrait, Database, DatabaseBackend, Statement};
use std::sync::Arc;

async fn seed() -> (tempfile::TempDir, SqliteSessionOptions) {
    let root = tempfile::tempdir().unwrap();
    let options = SqliteSessionOptions {
        path: root.path().join("history.sqlite"),
    };
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    for sequence in 1..=5 {
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
    // A storage-history head also includes independent resources, so it is not an effect sequence.
    store
        .register_resource(
            "owner",
            "zz-independent",
            OpaquePayload::text("saved metadata"),
        )
        .unwrap();
    store.flush().await.unwrap();
    store.shutdown().await.unwrap();
    (root, options)
}

async fn database(options: &SqliteSessionOptions) -> sea_orm::DatabaseConnection {
    Database::connect(format!("sqlite://{}?mode=rw", options.path.display()))
        .await
        .unwrap()
}

async fn seed_checkpoint() -> (tempfile::TempDir, SqliteSessionOptions) {
    let root = tempfile::tempdir().unwrap();
    let options = SqliteSessionOptions {
        path: root.path().join("checkpoint.sqlite"),
    };
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    let (model, _) = support::ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("owner".into(), pl_core::model::DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(store.clone()))
        .await
        .unwrap();
    thread.run_turn(support::turn("saved-turn")).await.unwrap();
    thread.close().await.unwrap();
    store.shutdown().await.unwrap();
    (root, options)
}

async fn assert_source_rejected_without_changes(options: &SqliteSessionOptions) {
    let before = tokio::fs::read(&options.path).await.unwrap();
    assert!(SqliteSessionStore::open(options.clone()).await.is_err());
    assert_eq!(tokio::fs::read(&options.path).await.unwrap(), before);
    assert!(
        migration::migrate_to_current(options.clone(), |_| Ok(()))
            .await
            .is_err()
    );
    assert_eq!(tokio::fs::read(&options.path).await.unwrap(), before);
    let db = database(options).await;
    assert!(
        db.query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT name FROM sqlite_schema WHERE type='table' AND name='seaql_migrations'",
        ))
        .await
        .unwrap()
        .is_none(),
        "invalid source must not acquire a migration ledger"
    );
    db.close().await.unwrap();
}

#[tokio::test]
async fn schema_preflight_refuses_invalid_takeover_without_writing_migration_records() {
    for damage in [
        "PRAGMA user_version=11; DROP TABLE session_history_heads",
        "PRAGMA user_version=11; ALTER TABLE session_entries RENAME COLUMN envelope TO unknown_envelope",
        "ALTER TABLE thread_checkpoints RENAME COLUMN history_fence TO unknown_fence",
        "ALTER TABLE thread_tool_tasks RENAME COLUMN task_hash TO unknown_hash",
    ] {
        let (_root, options) = seed().await;
        let db = database(&options).await;
        // This database has real saved effects but predates the official migration ledger. A bad
        // source shape must be refused before even an otherwise no-op migration is registered.
        db.execute_unprepared("DROP TABLE seaql_migrations")
            .await
            .unwrap();
        db.execute_unprepared(damage).await.unwrap();
        db.close().await.unwrap();
        assert_source_rejected_without_changes(&options).await;
    }
}

#[tokio::test]
async fn checkpoint_preflight_rejects_corruption_before_adopting_the_migration_ledger() {
    for damage in [
        "UPDATE thread_checkpoints SET payload_hash='damaged'",
        "UPDATE thread_checkpoints SET thread_id='foreign-owner'",
        "UPDATE thread_checkpoints SET schema_version=4",
        "UPDATE thread_checkpoints SET state_revision=state_revision+1",
        "UPDATE thread_checkpoints SET history_fence=history_fence+1",
        "UPDATE session_entries SET payload_hash='damaged' WHERE id=(SELECT MAX(id) FROM session_entries)",
    ] {
        let (_root, options) = seed_checkpoint().await;
        let db = database(&options).await;
        db.execute_unprepared("DROP TABLE seaql_migrations")
            .await
            .unwrap();
        db.execute_unprepared(damage).await.unwrap();
        db.close().await.unwrap();
        assert_source_rejected_without_changes(&options).await;
    }
}

#[tokio::test]
async fn v11_task_index_migration_is_atomic_and_preserves_source_effects() {
    let (_root, options) = seed().await;
    let db = database(&options).await;
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
        migration::migrate_to_current(options.clone(), |_| Ok(()))
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
    migration::migrate_to_current(options.clone(), |_| Ok(()))
        .await
        .unwrap();
    migration::migrate_to_current(options.clone(), |_| Ok(()))
        .await
        .unwrap();
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    for sequence in 1..=5 {
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
    for damage in ["first", "middle", "tail", "empty", "checkpoint-only"] {
        let (_root, options) = if matches!(damage, "empty" | "checkpoint-only") {
            seed_checkpoint().await
        } else {
            seed().await
        };
        let db = database(&options).await;
        db.execute_unprepared("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; DROP TABLE seaql_migrations; PRAGMA user_version=11")
            .await
            .unwrap();
        // The middle fault leaves both endpoints and the complete immutable history untouched.
        // A late backfill rejection is not enough: the shared assertion also forbids ledger writes.
        let sql = match damage {
            "first" => {
                "DELETE FROM session_entries WHERE id='pl.resource.thread-commit.00000000000000000001'"
            }
            "middle" => {
                "DELETE FROM session_entries WHERE id='pl.resource.thread-commit.00000000000000000004'"
            }
            "tail" => {
                "DELETE FROM session_entries WHERE id='pl.resource.thread-commit.00000000000000000005'"
            }
            "empty" => "DELETE FROM session_entries WHERE session_id='owner'",
            "checkpoint-only" => {
                "DELETE FROM session_entries WHERE session_id='owner'; DELETE FROM session_entry_history WHERE session_id='owner'; DELETE FROM session_history_heads WHERE session_id='owner'"
            }
            _ => unreachable!(),
        };
        db.execute_unprepared(sql).await.unwrap();
        db.close().await.unwrap();
        assert_source_rejected_without_changes(&options).await;
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
        assert!(
            db.query_all_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "SELECT name FROM sqlite_schema WHERE name IN ('thread_tool_tasks','thread_tool_task_resources')",
            ))
            .await
            .unwrap()
            .is_empty(),
            "a missing effect cannot publish a partial task index"
        );
        db.close().await.unwrap();
    }
}
