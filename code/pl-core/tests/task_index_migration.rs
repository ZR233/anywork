//! 任务索引的离线回填、事务失败与独立按身份读取。
#![cfg(feature = "sqlite")]
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
    let root = tempfile::tempdir().unwrap();
    let options = SqliteSessionOptions {
        path: root.path().join("history.sqlite"),
    };
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    for sequence in 1..=2 {
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
    db.execute_unprepared("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; PRAGMA user_version=11;
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
    db.execute_unprepared("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; PRAGMA user_version=11;
        DELETE FROM session_entries WHERE id='pl.resource.thread-commit.00000000000000000001'").await.unwrap();
    db.close().await.unwrap();
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
    db.close().await.unwrap();
}
