//! Batch admission, bounded recovery and historical facts through the public Thread API.
mod support;
#[path = "support/tool.rs"]
mod tool_support;

use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        ModelToolCallRejection, PreparedModelCall,
    },
    thread::{
        AttemptOutcome, ModelOutputViolation, ModelStepLimit, ThreadError, ThreadHandle,
        context_preparation::{
            ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
        },
    },
};
use pretty_assertions::assert_eq;
use std::{
    collections::VecDeque,
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};

struct GatedResponse {
    gate_preparation: bool,
    calls: Vec<ModelToolCall>,
    started: Arc<tokio::sync::Notify>,
    release: Arc<tokio::sync::Notify>,
    requests: Arc<AtomicUsize>,
    returned: Arc<Mutex<Option<ModelStepOutput>>>,
}

impl ModelSession for GatedResponse {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let first = self.requests.fetch_add(1, Ordering::SeqCst) == 0;
        let calls = if first { self.calls.clone() } else { vec![] };
        let started = self.started.clone();
        let release = self.release.clone();
        let returned = self.returned.clone();
        let gate_preparation = self.gate_preparation;
        if first && gate_preparation {
            started.notify_one();
            release.notified().await;
        }
        Ok(PreparedModelCall::new(async move {
            if first && !gate_preparation {
                started.notify_one();
                release.notified().await;
            }
            let mut output = support::response(&request, calls);
            output.content = vec![support::text(
                "real provider response after authorization change",
            )];
            output.private_context = Some(OpaquePayload::text("uncommitted provider continuation"));
            output.usage.input_tokens = Some(13);
            output.usage.output_tokens = Some(7);
            if first {
                *returned.lock().unwrap() = Some(output.clone());
            }
            Ok(output)
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

async fn authorization_change_during_response(rejected: ModelToolCall, revoke: bool) {
    let started = Arc::new(tokio::sync::Notify::new());
    let release = Arc::new(tokio::sync::Notify::new());
    let requests = Arc::new(AtomicUsize::new(0));
    let returned = Arc::new(Mutex::new(None));
    let calls = vec![rejected, call("valid-but-unexecuted", "record", None)];
    let log = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "authorization-change".into(),
        DynModelSession::new(GatedResponse {
            gate_preparation: false,
            calls: calls.clone(),
            started: started.clone(),
            release: release.clone(),
            requests: requests.clone(),
            returned: returned.clone(),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![tool_support::tool("record", &log)])
        .await
        .unwrap();
    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(support::turn("authorization-change")).await })
    };
    started.notified().await;
    // The prepared execution is suspended while the owner processes and acknowledges this change.
    // The non-revoking case replaces the executor and adds a tool without changing its authority.
    thread
        .register_tools(if revoke {
            vec![]
        } else {
            vec![
                tool_support::tool("record", &log),
                tool_support::tool("added", &log),
            ]
        })
        .await
        .unwrap();
    release.notify_one();
    let result = runner.await.unwrap();
    assert_eq!(result.unwrap().model_steps, 2);
    assert_eq!(requests.load(Ordering::SeqCst), 2);
    assert!(log.lock().unwrap().is_empty());
    let effects = thread.effects().await.unwrap();
    let (output, _) = effects
        .iter()
        .filter_map(|effect| effect.attempt.as_ref())
        .find_map(|attempt| {
            if let AttemptOutcome::Rejected { output, reason } = &attempt.outcome {
                Some((output, reason))
            } else {
                None
            }
        })
        .expect("returned response must remain in rejected attempt facts");
    assert_eq!(output.tool_calls, calls);
    assert_eq!(output.usage.input_tokens, Some(13));
    assert_eq!(output.usage.output_tokens, Some(7));
    assert_eq!(
        serde_json::to_value(output).unwrap(),
        serde_json::to_value(returned.lock().unwrap().as_ref().unwrap()).unwrap()
    );
    assert!(
        !thread.snapshot().context.records.iter().any(|record| {
            record.source == ContextSource::Assistant && record.tool_calls == calls
        })
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn parent_and_guard_revocation_deliver_call_failure_and_continue() {
    use pl_core::tool::opaque::ToolAuthorization;
    for revoke_guard in [false, true] {
        let parent = ToolAuthorization::unique();
        let guard = ToolAuthorization::unique();
        let authorization = parent.scoped(7).guarded_by(&guard);
        let same_identity = authorization.clone();
        let started = Arc::new(tokio::sync::Notify::new());
        let release = Arc::new(tokio::sync::Notify::new());
        let log = Arc::new(Mutex::new(Vec::new()));
        let thread = ThreadHandle::start(
            "revoked-frozen".into(),
            DynModelSession::new(GatedResponse {
                gate_preparation: false,
                calls: vec![call("never-executed", "record", None)],
                started: started.clone(),
                release: release.clone(),
                requests: Arc::new(AtomicUsize::new(0)),
                returned: Arc::new(Mutex::new(None)),
            }),
        )
        .unwrap();
        thread
            .register_tools(vec![
                tool_support::tool("record", &log).with_authorization(authorization.clone()),
            ])
            .await
            .unwrap();
        let runner = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.run_turn(support::turn("revoked-frozen")).await })
        };
        started.notified().await;
        if revoke_guard {
            guard.revoke();
        } else {
            parent.revoke();
        }
        assert_eq!(authorization, same_identity);
        assert!(!authorization.is_active());
        release.notify_one();
        assert_eq!(runner.await.unwrap().unwrap().model_steps, 2);
        assert!(log.lock().unwrap().is_empty());
        let snapshot = thread.snapshot();
        let effects = thread.effects().await.unwrap();
        let delivery = effects
            .iter()
            .flat_map(|e| e.deliveries.iter())
            .find(|d| d.call_id == "never-executed")
            .unwrap();
        assert!(
            matches!(&delivery.outcome, pl_core::thread::ToolOutcome::Failed(error)
            if matches!(error.source.downcast_ref::<ThreadError>(), Some(ThreadError::ToolPermissionRevoked)))
        );
        assert!(snapshot.context.records.iter().any(|r| matches!(&r.source,
            ContextSource::ToolResult { call_id, .. } if call_id == "never-executed")));
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn revoked_catalog_and_unknown_name_are_correctable_without_execution() {
    authorization_change_during_response(unknown("unknown"), true).await;
}

#[tokio::test]
async fn catalog_removal_only_denies_the_affected_call() {
    for (call_removed_tool, gate_preparation) in
        [(false, false), (true, false), (false, true), (true, true)]
    {
        let started = Arc::new(tokio::sync::Notify::new());
        let release = Arc::new(tokio::sync::Notify::new());
        let requests = Arc::new(AtomicUsize::new(0));
        let log = Arc::new(Mutex::new(Vec::new()));
        let mut calls = vec![call("healthy-call", "record", None)];
        if call_removed_tool {
            calls.insert(0, call("removed-call", "query", None));
        }
        let thread = ThreadHandle::start(
            "catalog-removal".into(),
            DynModelSession::new(GatedResponse {
                gate_preparation,
                calls,
                started: started.clone(),
                release: release.clone(),
                requests: requests.clone(),
                returned: Arc::new(Mutex::new(None)),
            }),
        )
        .unwrap();
        thread
            .register_tools(vec![
                tool_support::tool("record", &log),
                tool_support::tool("query", &log),
            ])
            .await
            .unwrap();
        let runner = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.run_turn(support::turn("catalog-removal")).await })
        };
        started.notified().await;
        thread
            .register_tools(vec![tool_support::tool("record", &log)])
            .await
            .unwrap();
        release.notify_one();
        assert_eq!(runner.await.unwrap().unwrap().model_steps, 2);
        assert_eq!(*log.lock().unwrap(), vec!["healthy-call"]);
        assert_eq!(requests.load(Ordering::SeqCst), 2);
        let effects = thread.effects().await.unwrap();
        let deliveries = effects
            .iter()
            .flat_map(|e| e.deliveries.iter())
            .collect::<Vec<_>>();
        assert_eq!(deliveries.len(), if call_removed_tool { 2 } else { 1 });
        if call_removed_tool {
            assert!(deliveries.iter().any(|d| d.call_id == "removed-call"
                && matches!(&d.outcome, pl_core::thread::ToolOutcome::Failed(error)
                    if matches!(error.source.downcast_ref::<ThreadError>(), Some(ThreadError::ToolPermissionRevoked)))));
        }
        thread.close().await.unwrap();
    }
}

#[derive(Debug)]
struct FailingDuringStop {
    entered: Arc<tokio::sync::Notify>,
    wait_for_stop: bool,
}

impl pl_agent_tool::Tool for FailingDuringStop {
    type Input = OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        Solo.definition()
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        context: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        self.entered.notify_one();
        if self.wait_for_stop {
            context.cancellation.cancelled().await;
        }
        Err(Self::Error::new(std::io::Error::other(
            "language server disconnected",
        )))
    }
}

#[tokio::test]
async fn tool_error_during_interrupt_does_not_poison_input_driver() {
    let entered = Arc::new(tokio::sync::Notify::new());
    let (thread, _, _) = start(vec![vec![call("failing", "query", None)], vec![]], false).await;
    thread
        .register_tools(vec![
            pl_core::tool::opaque::Registration::prepare(
                "query".into(),
                OpaquePayload::text("query"),
            )
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(FailingDuringStop {
                entered: entered.clone(),
                wait_for_stop: true,
            }))
            .foreground_coexisting(),
        ])
        .await
        .unwrap();
    thread
        .resume_inputs(pl_core::thread::input::InputDriverOptions {
            max_model_steps: ModelStepLimit::Unlimited,
        })
        .await
        .unwrap();
    let runner = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(support::turn("stop-error")).await })
    };
    entered.notified().await;
    thread.interrupt();
    assert!(matches!(runner.await.unwrap(), Err(ThreadError::Cancelled)));
    assert!(matches!(
        thread.snapshot().input_execution,
        pl_core::thread::input::InputExecution::Ready
    ));
    assert_eq!(
        thread
            .run_turn(support::turn("after-stop"))
            .await
            .unwrap()
            .model_steps,
        1
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn tool_internal_error_is_delivered_before_next_model_request() {
    let (model, requests) = support::ScriptedModel::new(&["query"]);
    let thread = ThreadHandle::start("internal-error".into(), DynModelSession::new(model)).unwrap();
    thread
        .register_tools(vec![
            pl_core::tool::opaque::Registration::prepare(
                "query".into(),
                OpaquePayload::text("query"),
            )
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(FailingDuringStop {
                entered: Default::default(),
                wait_for_stop: false,
            }))
            .foreground_coexisting(),
        ])
        .await
        .unwrap();
    assert_eq!(
        thread
            .run_turn(support::turn("internal-error"))
            .await
            .unwrap()
            .model_steps,
        2
    );
    assert!(requests.lock().unwrap()[1].records.iter().any(|record| {
        matches!(&record.source, ContextSource::ToolResult { tool_id, .. } if tool_id == "query")
            && record.content.iter().any(|content| matches!(content, ContextContent::Text { text } if text.contains("language server disconnected")))
    }));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn revoked_catalog_and_invalid_arguments_are_correctable_without_execution() {
    authorization_change_during_response(invalid("invalid"), true).await;
}

#[tokio::test]
async fn tool_addition_and_executor_reconnection_keep_correction_authorized() {
    authorization_change_during_response(unknown("unknown"), false).await;
}

struct Sequence {
    batches: VecDeque<Vec<ModelToolCall>>,
    requests: Arc<Mutex<Vec<ModelRequest>>>,
    cancel_response: bool,
}
impl ModelSession for Sequence {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests.lock().unwrap().push(request.clone());
        let calls = self
            .batches
            .pop_front()
            .expect("unexpected extra model request");
        let cancel = self.cancel_response;
        Ok(PreparedModelCall::new(async move {
            if cancel {
                request.cancellation.cancel();
            }
            let mut output = support::response(&request, calls);
            output.private_context = Some(OpaquePayload::text(request.attempt_id.as_str()));
            output.usage.output_tokens = Some(7);
            Ok(output)
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

fn call(id: &str, tool: &str, rejection: Option<ModelToolCallRejection>) -> ModelToolCall {
    ModelToolCall {
        presentation_contract: None,
        call_id: id.into(),
        tool_id: tool.into(),
        arguments: OpaquePayload::text(" raw arguments\n"),
        rejection,
    }
}
fn unknown(id: &str) -> ModelToolCall {
    // A rejected name can equal a registered stable ID, but it still cannot execute.
    call(
        id,
        "",
        Some(ModelToolCallRejection::UnknownTool {
            name: "record".into(),
        }),
    )
}
fn invalid(id: &str) -> ModelToolCall {
    call(
        id,
        "record",
        Some(ModelToolCallRejection::InvalidArguments {
            name: "wire-record".into(),
            reason: "missing field `input`".into(),
        }),
    )
}
async fn start(
    batches: Vec<Vec<ModelToolCall>>,
    cancel_response: bool,
) -> (
    ThreadHandle,
    Arc<Mutex<Vec<ModelRequest>>>,
    Arc<Mutex<Vec<String>>>,
) {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let log = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "correction".into(),
        DynModelSession::new(Sequence {
            batches: batches.into(),
            requests: requests.clone(),
            cancel_response,
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![
            tool_support::tool("record", &log),
            tool_support::tool("hidden", &log),
        ])
        .await
        .unwrap();
    (thread, requests, log)
}

#[derive(Debug)]
struct RestrictCorrections {
    cancel: bool,
}
impl ContextPreparationHook for RestrictCorrections {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        let correcting = request.model.context.records.iter().any(|record| {
            record.source
                == ContextSource::Runtime {
                    source_id: "model-output-correction".into(),
                }
        });
        if correcting && self.cancel {
            request.model.cancellation.cancel();
        }
        ContextPreparation::Prepared {
            expected_extension_sequence: request.extension_sequence,
            rejected_mutations: vec![],
            replacement: None,
            facts: vec![],
            mutations: vec![],
            excluded_tool_ids: if correcting {
                vec!["hidden".into()]
            } else {
                vec![]
            },
        }
    }
}

#[tokio::test]
async fn corrected_batches_keep_rejection_facts_but_commit_only_valid_calls() {
    let first = vec![unknown("unknown"), call("not-executed", "record", None)];
    let second = vec![invalid("invalid")];
    let (thread, requests, log) = start(
        vec![
            vec![call("completed-before-rejection", "record", None)],
            first.clone(),
            second.clone(),
            vec![call("executed-once", "record", None)],
            vec![],
        ],
        false,
    )
    .await;
    thread
        .set_context_preparation(Some(ContextPreparer::new(RestrictCorrections {
            cancel: false,
        })))
        .await
        .unwrap();
    let mut input = support::turn("recover");
    input.max_model_steps = ModelStepLimit::Limited(5.try_into().unwrap());
    assert_eq!(thread.run_turn(input).await.unwrap().model_steps, 5);
    assert_eq!(
        *log.lock().unwrap(),
        vec!["completed-before-rejection", "executed-once"]
    );
    let effects = thread.effects().await.unwrap();
    let terminal = effects
        .iter()
        .filter_map(|effect| effect.attempt.as_ref())
        .filter(|fact| {
            matches!(
                fact.outcome,
                AttemptOutcome::Rejected { .. } | AttemptOutcome::Committed(_)
            )
        })
        .collect::<Vec<_>>();
    assert_eq!(terminal.len(), 5);
    assert_eq!(terminal[2].retry_of.as_deref(), Some("attempt-recover:1"));
    assert_eq!(terminal[3].retry_of.as_deref(), Some("attempt-recover:2"));
    assert_eq!(terminal[4].retry_of, None);
    let rejected = effects
        .iter()
        .filter_map(|effect| effect.attempt.as_ref())
        .filter_map(|fact| {
            if let AttemptOutcome::Rejected { output, .. } = &fact.outcome {
                Some(output)
            } else {
                None
            }
        })
        .collect::<Vec<_>>();
    assert_eq!(rejected.len(), 2);
    for (output, expected) in rejected.into_iter().zip([first, second]) {
        assert_eq!(output.tool_calls, expected);
        assert_eq!(output.usage.output_tokens, Some(7));
        // The actual recorded output, not a synthetic payload, survives persistence encoding.
        let decoded: pl_core::model::ModelStepOutput =
            serde_json::from_str(&serde_json::to_string(output).unwrap()).unwrap();
        assert_eq!(decoded.tool_calls, output.tool_calls);
    }
    {
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 5);
        assert_eq!(requests[0].tools.len(), 2);
        for request in &requests[2..] {
            assert_eq!(
                request
                    .tools
                    .iter()
                    .map(|t| t.tool_id.as_str())
                    .collect::<Vec<_>>(),
                vec!["record"]
            );
            assert!(
                !request
                    .context
                    .records
                    .iter()
                    .flat_map(|r| &r.tool_calls)
                    .any(|call| {
                        ["unknown", "not-executed", "invalid"].contains(&call.call_id.as_str())
                    })
            );
        }
        for request in &requests[1..4] {
            assert_eq!(
                request.committed_private_context,
                Some(OpaquePayload::text("attempt-recover:0"))
            );
        }
        assert_eq!(
            requests[4].committed_private_context,
            Some(OpaquePayload::text("attempt-recover:3"))
        );
        let feedback = requests[3]
            .context
            .records
            .iter()
            .flat_map(|r| &r.content)
            .filter_map(|c| {
                if let ContextContent::Text { text } = c {
                    Some(text.as_ref())
                } else {
                    None
                }
            })
            .collect::<Vec<_>>()
            .join("\n");
        assert!(
            feedback.contains("wire-record")
                && feedback.contains("invalid")
                && feedback.contains("missing field `input`")
        );
        assert!(
            feedback.contains("no tool side effects")
                && feedback.contains("declarations in this request")
        );
        assert!(!feedback.contains("Tool hidden"));
    }
    #[cfg(feature = "sqlite")]
    let directory = tempfile::tempdir().unwrap();
    #[cfg(feature = "sqlite")]
    let options = pl_core::persistence::SqliteSessionOptions {
        path: directory.path().join("rejections.sqlite"),
    };
    #[cfg(feature = "sqlite")]
    let store = pl_core::persistence::SqliteSessionStore::open(options.clone())
        .await
        .unwrap();
    #[cfg(feature = "sqlite")]
    {
        thread
            .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(store.clone()))
            .await
            .unwrap();
        thread.flush().await.unwrap();
    }
    thread.close().await.unwrap();
    #[cfg(feature = "sqlite")]
    {
        store.shutdown().await.unwrap();
        let reopened = pl_core::persistence::SqliteSessionStore::open(options)
            .await
            .unwrap();
        for effect in &effects {
            if effect
                .attempt
                .as_ref()
                .is_some_and(|a| matches!(a.outcome, AttemptOutcome::Rejected { .. }))
            {
                let stored = reopened
                    .read_thread_effect("correction", effect.sequence)
                    .await
                    .unwrap()
                    .unwrap();
                assert_eq!(
                    serde_json::to_value(stored).unwrap(),
                    serde_json::to_value(effect).unwrap()
                );
            }
        }
        reopened.shutdown().await.unwrap();
    }
}

#[tokio::test]
async fn cancellation_during_correction_preparation_prevents_model_dispatch() {
    let (thread, requests, log) = start(vec![vec![unknown("bad")]], false).await;
    thread
        .set_context_preparation(Some(ContextPreparer::new(RestrictCorrections {
            cancel: true,
        })))
        .await
        .unwrap();
    assert!(matches!(
        thread.run_turn(support::turn("cancel-correction")).await,
        Err(ThreadError::Cancelled)
    ));
    assert_eq!(requests.lock().unwrap().len(), 1);
    assert!(log.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}

#[tokio::test]
async fn identity_errors_cannot_be_hidden_by_recoverable_calls() {
    for (batch, expected) in [
        (
            vec![unknown("bad"), call("", "record", None)],
            ModelOutputViolation::EmptyCallIdentity,
        ),
        (
            vec![unknown("same"), call("same", "record", None)],
            ModelOutputViolation::DuplicateCallIdentity {
                call_id: "same".into(),
            },
        ),
    ] {
        let (thread, requests, log) = start(vec![batch], false).await;
        assert!(matches!(thread.run_turn(support::turn("hard-error")).await,
            Err(ThreadError::ModelOutput(reason)) if reason == expected));
        assert_eq!(requests.lock().unwrap().len(), 1);
        assert!(log.lock().unwrap().is_empty());
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn solo_unknown_and_argument_rejections_continue_beyond_two_corrections() {
    let (thread, requests, log) = start(
        vec![
            vec![call("solo", "solo", None), call("other", "record", None)],
            vec![unknown("bad")],
            vec![invalid("invalid")],
            vec![],
        ],
        false,
    )
    .await;
    // Foreground registrations are Solo; keep the existing coexisting tool in this replacement.
    thread
        .register_tools(vec![
            tool_support::tool("record", &log),
            pl_core::tool::opaque::Registration::prepare(
                "solo".into(),
                OpaquePayload::text("solo"),
            )
            .unwrap()
            .attach(pl_core::tool::opaque::RuntimeTool::new(Solo))
            .foreground(),
        ])
        .await
        .unwrap();
    let mut input = support::turn("limit");
    input.max_model_steps = ModelStepLimit::Limited(10.try_into().unwrap());
    assert_eq!(thread.run_turn(input).await.unwrap().model_steps, 4);
    assert_eq!(requests.lock().unwrap().len(), 4);
    assert!(log.lock().unwrap().is_empty());
    assert!(thread.effects().await.unwrap().iter().any(|effect| {
        matches!(
            effect.attempt.as_ref().map(|a| &a.outcome),
            Some(AttemptOutcome::Rejected {
                reason: ModelOutputViolation::SoloBatch { .. },
                ..
            })
        )
    }));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn absent_rejection_facts_preserve_unknown_identity_and_allow_correction() {
    let legacy_call = serde_json::json!({
        "callId": "old-call", "toolId": "",
        "arguments": OpaquePayload::new("pl.model.invalid-call", 1, " original ").unwrap(),
    });
    let decoded: ModelToolCall = serde_json::from_value(legacy_call.clone()).unwrap();
    assert_eq!(decoded.rejection, None);
    assert_eq!(serde_json::to_value(&decoded).unwrap(), legacy_call);
    let (thread, requests, log) = start(
        vec![
            vec![decoded],
            vec![call("unregistered-call", "unregistered", None)],
            vec![],
        ],
        false,
    )
    .await;
    assert_eq!(
        thread
            .run_turn(support::turn("legacy"))
            .await
            .unwrap()
            .model_steps,
        3
    );
    assert_eq!(requests.lock().unwrap().len(), 3);
    assert!(log.lock().unwrap().is_empty());
    assert!(
        thread
            .effects()
            .await
            .unwrap()
            .iter()
            .any(|effect| matches!(
                effect.attempt.as_ref().map(|a| &a.outcome),
                Some(AttemptOutcome::Rejected {
                    reason: ModelOutputViolation::UnknownTool { .. },
                    ..
                })
            ))
    );
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct Solo;
impl pl_agent_tool::Tool for Solo {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("Solo", "Text tool for core runtime tests")
                    .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        _: pl_core::tool::opaque::CallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        panic!("rejected batch executed a tool")
    }
}

#[tokio::test]
async fn step_budget_and_cancellation_stop_correction_before_another_request() {
    for cancel in [false, true] {
        let (thread, requests, log) = start(vec![vec![unknown("bad")]], cancel).await;
        let mut input = support::turn("bounded");
        if !cancel {
            input.max_model_steps = ModelStepLimit::Limited(1.try_into().unwrap());
        }
        let error = thread.run_turn(input).await.unwrap_err();
        if cancel {
            assert!(matches!(error, ThreadError::Cancelled));
        } else {
            assert!(matches!(
                error,
                ThreadError::ModelOutput(ModelOutputViolation::ToolCallRejected { .. })
            ));
        }
        assert_eq!(requests.lock().unwrap().len(), 1);
        assert!(log.lock().unwrap().is_empty());
        thread.close().await.unwrap();
    }
}
