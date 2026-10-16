//! 手工测量冷任务按身份读取随历史规模的变化，不把时间断言放进常规测试。
//! cargo run --release --locked -p pl-core --features sqlite --example task_lookup_scaling
#[cfg(feature = "sqlite")]
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
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
    use std::{sync::Arc, time::Instant};
    let store = SqliteSessionStore::open_memory().await?;
    let task = TaskRecord {
        id: "task:old".into(),
        call_id: "old".into(),
        tool_id: "exec".into(),
        turn_id: "turn".into(),
        revision: 2,
        status: TaskStatus::Succeeded,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: Some(1),
    };
    let first = ThreadEffectBatch {
        thread_id: "bench".into(),
        sequence: 1,
        tasks: Arc::from([task.clone()]),
        deliveries: Arc::from([ToolDelivery {
            target: ToolDeliveryTarget::CallResult,
            call_id: "old".into(),
            tool_id: "exec".into(),
            output: ToolOutput::new(OpaquePayload::text("result"), vec![]),
            delivered_context: vec![],
            outcome: ToolOutcome::Succeeded,
        }]),
        ..Default::default()
    };
    store.register_resource(
        "bench",
        "thread-commit.00000000000000000001",
        first.encode()?,
    )?;
    let mut sequence = 2;
    for size in [1_000, 10_000, 100_000] {
        let write_start = Instant::now();
        while sequence <= size {
            let effect = ThreadEffectBatch {
                thread_id: "bench".into(),
                sequence,
                // 代表同一会话中与目标任务无关的 1 KiB 业务事实。
                runtime_facts: Some(Arc::from([pl_core::thread::RuntimeFact {
                    source_id: "bench".into(),
                    content: vec![pl_core::context::ContextContent::Text {
                        text: Arc::from("x".repeat(1024)),
                    }],
                }])),
                ..Default::default()
            };
            store.register_resource(
                "bench",
                &format!("thread-commit.{sequence:020}"),
                effect.encode()?,
            )?;
            if sequence % 512 == 0 {
                store.flush().await?;
            }
            sequence += 1;
        }
        store.flush().await?;
        let write_ms = write_start.elapsed().as_secs_f64() * 1000.0;
        for id in ["task:old", "task:missing"] {
            let mut samples = Vec::new();
            for _ in 0..7 {
                let start = Instant::now();
                let found = ColdStore::read_tool_task(&store, "bench", id).await?;
                assert_eq!(found.is_some(), id == "task:old");
                samples.push(start.elapsed().as_secs_f64() * 1000.0);
            }
            samples.sort_by(f64::total_cmp);
            println!(
                "{}",
                serde_json::json!({"effects":size,"task":id,"median_ms":samples[3],"max_ms":samples[6],"samples_ms":samples,"write_ms":write_ms})
            );
        }
    }
    store.shutdown().await?;
    Ok(())
}

#[cfg(not(feature = "sqlite"))]
fn main() {
    eprintln!("此手工测量入口需要 --features sqlite");
    std::process::exit(2);
}
