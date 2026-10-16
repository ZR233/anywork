//! 通用 SQLite 冷存储必须独立于内存窗口保留任务完整结果。
#![cfg(feature = "sqlite")]
use pl_core::{
    context::OpaquePayload,
    persistence::SqliteSessionStore,
    thread::{
        ThreadEffectBatch, ToolDelivery, ToolDeliveryTarget, ToolOutcome,
        cold::ColdStore,
        task::{TaskRecord, TaskStatus},
    },
    tool::ToolOutput,
};
use pretty_assertions::assert_eq;
use std::sync::Arc;

#[tokio::test]
async fn sqlite_cold_store_reads_terminal_tool_payload_after_reopen() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("history.sqlite");
    let options = pl_core::persistence::SqliteSessionOptions { path };
    let store = SqliteSessionStore::open(options.clone()).await.unwrap();
    let mut task = TaskRecord {
        id: "task:call-exec".into(),
        call_id: "call-exec".into(),
        tool_id: "exec".into(),
        turn_id: "turn".into(),
        revision: 2,
        status: TaskStatus::Succeeded,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: Some(1),
    };
    let payload = OpaquePayload::new("pl.tool.exec", 1, "{\"stdout\":\"完整结果\"}").unwrap();
    let delivery = ToolDelivery {
        target: ToolDeliveryTarget::CallResult,
        call_id: task.call_id.clone(),
        tool_id: task.tool_id.clone(),
        output: ToolOutput::new(payload.clone(), vec![]),
        delivered_context: vec![],
        outcome: ToolOutcome::Succeeded,
    };
    let effect = ThreadEffectBatch {
        thread_id: "owner".into(),
        sequence: 1,
        tasks: Arc::from([task.clone()]),
        deliveries: Arc::from([delivery]),
        ..Default::default()
    };
    store
        .register_resource(
            "owner",
            "thread-commit.00000000000000000001",
            effect.encode().unwrap(),
        )
        .unwrap();
    // 最新任务修订与最初完整结果跨过一页，不能把窗口边界当作历史终点。
    for sequence in 2..=257 {
        let unrelated = TaskRecord {
            id: "task:unrelated".into(),
            call_id: "unrelated".into(),
            revision: sequence,
            status: TaskStatus::Running,
            ..task.clone()
        };
        let effect = ThreadEffectBatch {
            thread_id: "owner".into(),
            sequence,
            tasks: Arc::from([unrelated]),
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
    task.revision = 3;
    let latest = ThreadEffectBatch {
        thread_id: "owner".into(),
        sequence: 258,
        tasks: Arc::from([task.clone()]),
        ..Default::default()
    };
    store
        .register_resource(
            "owner",
            "thread-commit.00000000000000000258",
            latest.encode().unwrap(),
        )
        .unwrap();
    store.flush().await.unwrap();
    store.shutdown().await.unwrap();
    let reopened = SqliteSessionStore::open(options).await.unwrap();
    let found = ColdStore::read_tool_task(&reopened, "owner", &task.id)
        .await
        .unwrap()
        .expect("已落盘任务不能消失");
    assert_eq!(found.task, task);
    assert_eq!(found.delivery.unwrap().output.payload(), &payload);
    assert!(
        ColdStore::read_tool_task(&reopened, "different-owner", &task.id)
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        ColdStore::read_tool_task(&reopened, "owner", "task:missing")
            .await
            .unwrap()
            .is_none()
    );
    reopened.shutdown().await.unwrap();
}
