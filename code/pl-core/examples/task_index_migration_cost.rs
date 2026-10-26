//! 隔离文件库上的离线索引回填与 SQLite 查询计划手工测量。
#[cfg(feature = "sqlite")]
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
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
    use sea_orm::{ConnectionTrait, Database, DatabaseBackend, Statement};
    use std::{sync::Arc, time::Instant};
    let root = tempfile::tempdir()?;
    let options = SqliteSessionOptions {
        path: root.path().join("migration.sqlite"),
    };
    let store = SqliteSessionStore::open(options.clone()).await?;
    for sequence in 1..=5000 {
        let mut effect = ThreadEffectBatch {
            thread_id: "migration-bench".into(),
            sequence,
            ..Default::default()
        };
        if sequence % 10 == 0 {
            let call_id = format!("call-{sequence}");
            effect.tasks = Arc::from([TaskRecord {
                id: format!("task:{call_id}"),
                call_id: call_id.clone(),
                tool_id: "exec".into(),
                turn_id: "turn".into(),
                revision: 2,
                status: TaskStatus::Succeeded,
                cancel_requested: false,
                acknowledgement: None,
                started_sequence: Some(sequence),
            }]);
            effect.deliveries = Arc::from([ToolDelivery {
                call_id,
                tool_id: "exec".into(),
                target: Default::default(),
                outcome: ToolOutcome::Succeeded,
                output: ToolOutput::new(OpaquePayload::text("x".repeat(1024)), vec![]),
                delivered_context: vec![],
            }]);
        }
        store.register_resource(
            "migration-bench",
            &format!("thread-commit.{sequence:020}"),
            effect.encode()?,
        )?;
        if sequence % 128 == 0 {
            store.flush().await?;
        }
    }
    store.flush().await?;
    store.shutdown().await?;
    drop(store);
    let url = format!("sqlite://{}?mode=rw", options.path.display());
    let db = Database::connect(url.clone()).await?;
    db.execute_unprepared("DROP TABLE thread_tool_task_resources; DROP TABLE thread_tool_tasks; DROP TABLE IF EXISTS seaql_migrations; PRAGMA user_version=11").await?;
    db.close().await?;
    let start = Instant::now();
    migration::migrate_to_current(options.clone(), |_| Ok(())).await?;
    let migration_ms = start.elapsed().as_secs_f64() * 1000.0;
    let db = Database::connect(url).await?;
    let plan = db
        .query_all_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "EXPLAIN QUERY PLAN SELECT * FROM thread_tool_tasks WHERE thread_id=? AND task_id=?",
            vec!["migration-bench".into(), "task:call-10".into()],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get::<String>("", "detail"))
        .collect::<Result<Vec<_>, _>>()?;
    let tasks = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT COUNT(*) AS n FROM thread_tool_tasks",
        ))
        .await?
        .unwrap()
        .try_get::<i64>("", "n")?;
    assert_eq!(tasks, 500);
    db.close().await?;
    let store = SqliteSessionStore::open(options.clone()).await?;
    for id in ["task:call-10", "task:call-5000"] {
        assert!(
            ColdStore::read_tool_task(&store, "migration-bench", id)
                .await?
                .is_some()
        );
    }
    store.shutdown().await?;
    println!(
        "{}",
        serde_json::json!({"effects":5000,"tasks":tasks,"migration_ms":migration_ms,
        "database_bytes":std::fs::metadata(options.path)?.len(),"task_query_plan":plan})
    );
    Ok(())
}

#[cfg(not(feature = "sqlite"))]
fn main() {
    eprintln!("此手工入口需要 --features sqlite");
    std::process::exit(2);
}
