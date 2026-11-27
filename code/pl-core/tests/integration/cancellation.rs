use crate::support;

use std::sync::Mutex;

use pl_core::context::OpaquePayload;
use pl_core::model::{
    DynModelSession, ModelError, ModelFailureKind, ModelRequest, ModelSession, PreparedModelCall,
};
use pl_core::thread::{ThreadError, ThreadHandle, ToolOutcome, TurnState};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};
use tokio::sync::oneshot;

use support::turn;

#[derive(Debug)]
struct CancellationAwareTool {
    entered: Mutex<Option<oneshot::Sender<()>>>,
}

impl pl_agent_tool::Tool for CancellationAwareTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text(
                    "CancellationAwareTool",
                    "Text tool for core runtime tests",
                )
                .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        _input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if let Some(entered) = self.entered.lock().unwrap().take() {
            entered.send(()).expect("receiver must still exist");
        }
        context.cancellation.cancelled().await;
        Ok(ToolOutput::from_data(
            serde_json::Value::String("observed after cancellation".into()),
            vec![support::text(
                "tool result must not be delivered as success",
            )],
        ))
    }
}

struct BlockingModelCall {
    entered: Option<oneshot::Sender<()>>,
}

impl ModelSession for BlockingModelCall {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let entered = self.entered.take().expect("one model invocation");
        Ok(PreparedModelCall::new(async move {
            entered.send(()).expect("receiver must still exist");
            request.cancellation.cancelled().await;
            Err(ModelError {
                context_recovery: None,
                details: None,
                kind: ModelFailureKind::Cancelled,
                usage: Default::default(),
                source: None,
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn cancelling_an_active_turn_returns_cancelled_and_commits_termination() {
    let (entered, waiting) = oneshot::channel();
    let thread = ThreadHandle::start(
        "cancelled-thread".into(),
        DynModelSession::new(BlockingModelCall {
            entered: Some(entered),
        }),
    )
    .unwrap();
    let input = turn("cancel-me");
    let cancellation = input.cancellation.clone();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(input).await }
    });
    waiting.await.expect("model invocation started");
    cancellation.cancel();
    assert!(matches!(runner.await.unwrap(), Err(ThreadError::Cancelled)));
    assert!(thread.effects().await.unwrap().iter().any(|effect| {
        effect
            .turn
            .as_ref()
            .is_some_and(|turn| turn.turn_id == "cancel-me" && turn.state == TurnState::Cancelled)
    }));

    thread.close().await.unwrap();
}

#[tokio::test]
async fn cancelling_a_running_tool_retains_its_result_as_a_cancelled_delivery() {
    let (model, _) = support::ScriptedModel::new(&["slow"]);
    let thread = ThreadHandle::start("tool-thread".into(), DynModelSession::new(model)).unwrap();
    let (entered, waiting) = oneshot::channel();
    thread
        .register_tools(vec![
            Registration::prepare("slow".into(), OpaquePayload::text("Slow tool"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(
                    CancellationAwareTool {
                        entered: Mutex::new(Some(entered)),
                    },
                ))
                .foreground_coexisting(),
        ])
        .await
        .unwrap();
    let input = turn("interrupt-tool");
    let cancellation = input.cancellation.clone();
    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(input).await }
    });
    waiting.await.expect("tool invocation started");
    cancellation.cancel();
    assert!(matches!(runner.await.unwrap(), Err(ThreadError::Cancelled)));

    let deliveries: Vec<_> = thread
        .effects()
        .await
        .unwrap()
        .into_iter()
        .flat_map(|effect| effect.deliveries.to_vec())
        .collect();
    assert_eq!(deliveries.len(), 1);
    assert!(matches!(deliveries[0].outcome, ToolOutcome::Cancelled));
    assert_eq!(
        deliveries[0]
            .output
            .data()
            .and_then(serde_json::Value::as_str),
        Some("observed after cancellation")
    );
    assert_ne!(
        deliveries[0].delivered_context.as_slice(),
        deliveries[0].output.content()
    );
    thread.close().await.unwrap();
}

#[cfg(unix)]
mod nested_cancel {
    use super::*;
    use pl_agent_tool::{Tool, ToolDefinition};
    use pl_core::thread::{
        ToolCompletion, ToolDeliveryTarget, extensions::ExtensionMutation, task,
    };
    use pl_core::tool::opaque::RuntimeTool;
    use std::{io, process::Stdio, sync::Arc, time::Duration};
    use tokio::{
        io::{AsyncBufReadExt, BufReader},
        process::Command,
        sync::Notify,
    };

    const PARTIAL: &str = "partial child output\n";

    #[derive(Debug)]
    enum Probe {
        Parent {
            reply: Mutex<Option<oneshot::Sender<Result<ToolCompletion, ThreadError>>>>,
            release: Arc<Notify>,
        },
        Child {
            started: Mutex<Option<oneshot::Sender<String>>>,
        },
    }

    impl Tool for Probe {
        type Input = OpaquePayload;
        type Context = CallContext;
        type Output = ToolOutput;
        type Error = ToolError;

        fn definition(&self) -> &ToolDefinition {
            static DEFINITION: std::sync::LazyLock<ToolDefinition> =
                std::sync::LazyLock::new(|| {
                    ToolDefinition::text("probe", "Nested cancellation probe").unwrap()
                });
            &DEFINITION
        }

        async fn execute(
            &self,
            _: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            let tasks = context.tasks.unwrap();
            match self {
                Self::Parent { reply, release } => {
                    let result = tasks
                        .call_nested(
                            "child".into(),
                            OpaquePayload::text(""),
                            context.cancellation.clone(),
                        )
                        .await;
                    reply.lock().unwrap().take().unwrap().send(result).unwrap();
                    release.notified().await;
                    Ok(ToolOutput::text("parent continued".into()))
                }
                Self::Child { started } => {
                    let mut process = Command::new("sh")
                        .args([
                            "-c",
                            "printf '%s\\n' 'partial child output'; IFS= read -r line",
                        ])
                        .stdin(Stdio::piped())
                        .stdout(Stdio::piped())
                        .kill_on_drop(true)
                        .spawn()
                        .map_err(ToolError::new)?;
                    let mut output = String::new();
                    BufReader::new(process.stdout.take().unwrap())
                        .read_line(&mut output)
                        .await
                        .map_err(ToolError::new)?;
                    assert_eq!(output, PARTIAL);
                    started
                        .lock()
                        .unwrap()
                        .take()
                        .unwrap()
                        .send(tasks.current_task_id().into())
                        .unwrap();
                    context.cancellation.cancelled().await;
                    process.kill().await.map_err(ToolError::new)?;
                    assert!(
                        process.try_wait().map_err(ToolError::new)?.is_some(),
                        "child process was reaped before completion"
                    );
                    let output = ToolOutput::text(output)
                        .ending_turn()
                        .with_extension_mutations(vec![ExtensionMutation::Put {
                            id: "child-control".into(),
                            expected_revision: None,
                            payload: OpaquePayload::text("must not commit"),
                        }]);
                    Err(
                        ToolError::new(io::Error::other("child stopped with observed output"))
                            .with_output(output),
                    )
                }
            }
        }
    }

    #[tokio::test]
    async fn cancelling_only_a_nested_task_returns_its_observed_output() {
        let (model, requests) = support::ScriptedModel::new(&["parent"]);
        let thread =
            ThreadHandle::start("nested-cancel".into(), DynModelSession::new(model)).unwrap();
        let (started, child_started) = oneshot::channel();
        let (reply, child_finished) = oneshot::channel();
        let release = Arc::new(Notify::new());
        thread
            .register_tools(vec![
                Registration::prepare("parent".into(), OpaquePayload::text("parent"))
                    .unwrap()
                    .attach(RuntimeTool::new(Probe::Parent {
                        reply: Mutex::new(Some(reply)),
                        release: release.clone(),
                    }))
                    .with_nested_calls()
                    .foreground(),
                Registration::prepare("child".into(), OpaquePayload::text("child"))
                    .unwrap()
                    .attach(RuntimeTool::new(Probe::Child {
                        started: Mutex::new(Some(started)),
                    }))
                    .with_extension_updates()
                    .nested(false),
            ])
            .await
            .unwrap();
        let running = tokio::spawn({
            let thread = thread.clone();
            async move { thread.run_turn(turn("nested-cancel")).await }
        });
        let id = tokio::time::timeout(Duration::from_secs(10), child_started)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(
            thread.cancel_task(id.clone()).await.unwrap(),
            task::TaskCancellationReceipt::Requested
        );
        let result = tokio::time::timeout(Duration::from_secs(10), child_finished)
            .await
            .unwrap()
            .unwrap();

        let snapshot = thread.snapshot();
        assert_eq!(
            snapshot.tasks["task:nested-cancel-parent"].status,
            task::TaskStatus::Running
        );
        assert!(!snapshot.extensions.contains_key("child-control"));
        assert!(
            snapshot
                .terminal_tasks
                .iter()
                .any(|task| task.id == id && task.status == task::TaskStatus::Cancelled)
        );
        let delivery = thread.effects().await.unwrap().iter().flat_map(|effect| effect.deliveries.iter())
            .find(|delivery| matches!(&delivery.target, ToolDeliveryTarget::Nested { parent_call_id } if parent_call_id == "nested-cancel-parent")).unwrap().clone();
        assert_eq!(format!("task:{}", delivery.call_id), id);
        assert!(matches!(delivery.outcome, ToolOutcome::Cancelled));
        assert_eq!(delivery.output.data(), Some(&serde_json::json!(PARTIAL)));
        let completion = result.expect("the running parent receives the committed completion");
        assert!(matches!(completion.outcome(), ToolOutcome::Cancelled));
        assert_eq!(completion.output(), Some(&delivery.output));
        let source = &completion.error().expect("original typed source").source;
        assert_eq!(
            source.downcast_ref::<io::Error>().unwrap().to_string(),
            "child stopped with observed output"
        );
        let encoded = serde_json::to_value(&delivery).unwrap();
        assert_eq!(
            encoded["cancellationCause"],
            serde_json::json!({
                "kind": "invocation",
                "source": ["child stopped with observed output"],
            })
        );
        assert!(std::ptr::eq(
            completion.error().unwrap(),
            delivery.cancellation_cause.as_deref().unwrap()
        ));
        let restored: pl_core::thread::ToolDelivery =
            serde_json::from_value(encoded.clone()).unwrap();
        assert!(matches!(restored.outcome, ToolOutcome::Cancelled));
        assert_eq!(restored.output.data(), delivery.output.data());
        let cause = restored.cancellation_cause.unwrap();
        assert_eq!(cause.kind(), pl_core::tool::ToolFailureKind::Invocation);
        assert_eq!(cause.to_string(), "child stopped with observed output");
        assert!(cause.observed_output().is_none());

        let mut older = encoded;
        older.as_object_mut().unwrap().remove("cancellationCause");
        let older: pl_core::thread::ToolDelivery = serde_json::from_value(older).unwrap();
        assert!(older.cancellation_cause.is_none());
        assert!(
            serde_json::to_value(older)
                .unwrap()
                .get("cancellationCause")
                .is_none()
        );

        release.notify_one();
        running.await.unwrap().unwrap();
        assert_eq!(
            requests.lock().unwrap().len(),
            2,
            "cancelled child did not end its parent's Turn"
        );
        thread.close().await.unwrap();
    }
}
