//! Reproducible owner timing evidence. Virtual time measures scheduling, not provider throughput.
use crate::support;

use std::sync::{Arc, Mutex};
use std::time::Duration;

use pl_core::context::OpaquePayload;
use pl_core::model::{DynModelSession, ModelError, ModelRequest, ModelSession, PreparedModelCall};
use pl_core::thread::{ContextCapacity, ThreadError, ThreadHandle};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, RuntimeTool, ToolError},
};
use tokio::time::Instant;

#[derive(Debug)]
struct TimedTool {
    starts: Arc<Mutex<Vec<Instant>>>,
    started: tokio::sync::mpsc::UnboundedSender<()>,
}

impl pl_agent_tool::Tool for TimedTool {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("TimedTool", "Scheduling evidence").unwrap()
            });
        &DEFINITION
    }

    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        self.starts.lock().unwrap().push(Instant::now());
        self.started.send(()).unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        Ok(ToolOutput::new(input, vec![]))
    }
}

struct TimedModel {
    inner: support::ScriptedModel,
    calls: Arc<Mutex<Vec<Instant>>>,
}

impl ModelSession for TimedModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.calls.lock().unwrap().push(Instant::now());
        self.inner.prepare(request).await
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

struct SettlingModel(tokio::sync::mpsc::UnboundedSender<()>);

impl ModelSession for SettlingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let started = self.0.clone();
        Ok(PreparedModelCall::new(async move {
            started.send(()).unwrap();
            request.cancellation.cancelled().await;
            tokio::time::sleep(Duration::from_millis(40)).await;
            Err(ModelError {
                context_recovery: None,
                kind: pl_core::model::ModelFailureKind::Cancelled,
                details: None,
                usage: Box::default(),
                source: None,
            })
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test(start_paused = true)]
async fn owner_loop_latency() {
    let (inner, requests) = support::ScriptedModel::new(&["first", "second"]);
    let calls = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "latency".into(),
        DynModelSession::new(TimedModel {
            inner,
            calls: calls.clone(),
        }),
    )
    .unwrap();
    let starts = Arc::new(Mutex::new(Vec::new()));
    let (started, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    thread
        .register_tools(
            ["first", "second"]
                .map(|id| {
                    Registration::prepare(id.into(), OpaquePayload::text(id))
                        .unwrap()
                        .attach(RuntimeTool::new(TimedTool {
                            starts: starts.clone(),
                            started: started.clone(),
                        }))
                })
                .into_iter()
                .collect(),
        )
        .await
        .unwrap();
    let run = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(support::turn("batch")).await })
    };
    receiver.recv().await.unwrap();
    let control_at = Instant::now();
    thread
        .set_capacity(ContextCapacity::default())
        .await
        .unwrap();
    let control_apply_latency = control_at.elapsed();
    run.await.unwrap().unwrap();
    assert_eq!(requests.lock().unwrap().len(), 2);
    let spread = {
        let starts = starts.lock().unwrap();
        assert_eq!(starts.len(), 2);
        starts[1] - starts[0]
    };
    let next_request_gap = {
        let calls = calls.lock().unwrap();
        calls[1] - calls[0]
    };
    thread.close().await.unwrap();

    let (started, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    let thread = ThreadHandle::start(
        "stop-latency".into(),
        DynModelSession::new(SettlingModel(started)),
    )
    .unwrap();
    let run = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(support::turn("stop")).await })
    };
    receiver.recv().await.unwrap();
    let execution = thread.snapshot().execution.as_ref().unwrap().id.clone();
    let stop_at = Instant::now();
    assert!(thread.interrupt_execution(execution).await.unwrap());
    assert!(
        thread.snapshot().execution.is_some(),
        "cancellation request is not physical completion"
    );
    assert!(matches!(run.await.unwrap(), Err(ThreadError::Cancelled)));
    let stop_settle_latency = stop_at.elapsed();
    assert!(thread.snapshot().execution.is_none());
    thread.close().await.unwrap();
    println!(
        "control_apply_latency_ms={} stop_settle_latency_ms={} next_request_gap_ms={} tool_batch_start_spread_ms={}",
        control_apply_latency.as_millis(),
        stop_settle_latency.as_millis(),
        next_request_gap.as_millis(),
        spread.as_millis()
    );
}
