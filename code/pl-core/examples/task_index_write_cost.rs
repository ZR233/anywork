//! 手工测量任务索引的增量写入成本与离线迁移；时间不作为测试断言。
#[cfg(feature = "sqlite")]
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    use pl_core::{
        context::OpaquePayload,
        persistence::SqliteSessionStore,
        thread::{
            ThreadEffectBatch, ToolDelivery, ToolOutcome,
            task::{TaskRecord, TaskStatus},
        },
        tool::ToolOutput,
    };
    use std::{sync::Arc, time::Instant};
    for with_task in [false, true] {
        let mut samples = Vec::new();
        for sample in 0..10 {
            let store = SqliteSessionStore::open_memory().await?;
            let start = Instant::now();
            for sequence in 1..=200 {
                let mut effect = ThreadEffectBatch {
                    thread_id: "write-bench".into(),
                    sequence,
                    ..Default::default()
                };
                if with_task {
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
                } else {
                    effect.runtime_facts = Some(Arc::from([pl_core::thread::RuntimeFact {
                        source_id: "bench".into(),
                        content: vec![pl_core::context::ContextContent::Text {
                            text: Arc::from("x".repeat(1024)),
                        }],
                    }]));
                }
                store.register_resource(
                    "write-bench",
                    &format!("thread-commit.{sequence:020}"),
                    effect.encode()?,
                )?;
                if sequence % 64 == 0 {
                    store.flush().await?;
                }
            }
            store.flush().await?;
            let per_effect_us = start.elapsed().as_secs_f64() * 1_000_000.0 / 200.0;
            store.shutdown().await?;
            if sample > 0 {
                samples.push(per_effect_us);
            }
        }
        samples.sort_by(f64::total_cmp);
        println!(
            "{}",
            serde_json::json!({"terminal_task_per_effect":with_task,"effects_per_sample":200,
            "samples_us_per_effect":samples,"median_us_per_effect":samples[samples.len()/2]})
        );
    }
    Ok(())
}

#[cfg(not(feature = "sqlite"))]
fn main() {
    eprintln!("此手工入口需要 --features sqlite");
    std::process::exit(2);
}
