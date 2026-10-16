//! 手工比较同进程脚本模型的有/无 gate Turn 开销，报告数据，不使用时间断言。
use pl_core::{
    context::ContextContent,
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, PreparedModelCall,
    },
    thread::{ModelStepLimit, ThreadHandle, TurnInput, admission::TurnAdmissionGate},
};
use std::{hint::black_box, sync::Arc, time::Instant};
use tokio_util::sync::CancellationToken;

struct ImmediateModel;
impl ModelSession for ImmediateModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: Arc::from("done"),
                }],
                tool_calls: vec![],
                private_context: None,
                usage: Default::default(),
            })
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    const TURNS: usize = 200;
    let mut ungated = Vec::new();
    let mut gated = Vec::new();
    for sample in 0..12 {
        // 交错顺序，两个样本均从新 owner 开始并走同一个公开 run_turn 入口。
        for enabled in if sample % 2 == 0 {
            [false, true]
        } else {
            [true, false]
        } {
            let model = DynModelSession::new(ImmediateModel);
            let thread = if enabled {
                ThreadHandle::resume_with_turn_admission_gate(
                    "bench".into(),
                    Some(model),
                    None,
                    TurnAdmissionGate::new(),
                )?
            } else {
                ThreadHandle::start("bench".into(), model)?
            };
            let start = Instant::now();
            for n in 0..TURNS {
                black_box(
                    thread
                        .run_turn(TurnInput {
                            turn_id: format!("turn-{n}"),
                            attempt_prefix: format!("attempt-{n}"),
                            content: vec![ContextContent::Text {
                                text: Arc::from("input"),
                            }],
                            max_model_steps: ModelStepLimit::Limited(1.try_into()?),
                            cancellation: CancellationToken::new(),
                        })
                        .await?,
                );
            }
            let per_turn_us = start.elapsed().as_secs_f64() * 1_000_000.0 / TURNS as f64;
            thread.close().await?;
            if sample > 0 {
                if enabled {
                    gated.push(per_turn_us);
                } else {
                    ungated.push(per_turn_us);
                }
            }
        }
    }
    ungated.sort_by(f64::total_cmp);
    gated.sort_by(f64::total_cmp);
    let gate = TurnAdmissionGate::new();
    let start = Instant::now();
    for _ in 0..1_000_000 {
        drop(black_box(gate.try_admit().expect("open")));
    }
    println!(
        "{}",
        serde_json::json!({"turns_per_sample":TURNS,"samples":ungated.len(),
        "ungated_us":ungated,"gated_us":gated,
        "ungated_median_us":ungated[ungated.len()/2],"gated_median_us":gated[gated.len()/2],
        "permit_acquire_release_ns":start.elapsed().as_secs_f64()*1000.0})
    );
    Ok(())
}
