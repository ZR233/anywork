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
        Ok(PreparedModelCall::new(async move {
            if first {
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
    if revoke {
        assert!(
            matches!(
                result,
                Err(ThreadError::ModelOutput(
                    ModelOutputViolation::ToolPermissionRevoked
                ))
            ),
            "revoked authority must be a hard failure, got {result:?}"
        );
        assert_eq!(requests.load(Ordering::SeqCst), 1);
    } else {
        assert_eq!(result.unwrap().model_steps, 2);
        assert_eq!(requests.load(Ordering::SeqCst), 2);
    }
    assert!(log.lock().unwrap().is_empty());
    let effects = thread.effects().await.unwrap();
    let (output, reason) = effects
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
    if revoke {
        assert_eq!(*reason, ModelOutputViolation::ToolPermissionRevoked);
    }
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
async fn revoked_authorization_cannot_be_hidden_by_unknown_name() {
    authorization_change_during_response(unknown("unknown"), true).await;
}

#[tokio::test]
async fn revoked_authorization_cannot_be_hidden_by_invalid_arguments() {
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
async fn consistency_and_authorization_errors_cannot_be_hidden_by_recoverable_calls() {
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
        (
            vec![unknown("bad"), call("forbidden", "unregistered", None)],
            ModelOutputViolation::UnknownTool {
                tool_id: "unregistered".into(),
                call_id: "forbidden".into(),
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
async fn solo_unknown_and_argument_rejections_share_two_corrections() {
    let (thread, requests, log) = start(
        vec![
            vec![call("solo", "solo", None), call("other", "record", None)],
            vec![unknown("bad")],
            vec![invalid("invalid")],
        ],
        false,
    )
    .await;
    // Foreground registrations are Solo; keep the existing coexisting tool in this replacement.
    thread
        .register_tools(vec![
            tool_support::tool("record", &log),
            pl_core::tool::opaque::Registration::new(
                "solo".into(),
                OpaquePayload::text("solo"),
                Solo,
            )
            .unwrap()
            .foreground(),
        ])
        .await
        .unwrap();
    let mut input = support::turn("limit");
    input.max_model_steps = ModelStepLimit::Limited(10.try_into().unwrap());
    assert!(matches!(
        thread.run_turn(input).await,
        Err(ThreadError::ModelOutput(
            ModelOutputViolation::ToolCallRejected {
                rejection: ModelToolCallRejection::InvalidArguments { .. },
                ..
            }
        ))
    ));
    assert_eq!(requests.lock().unwrap().len(), 3);
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
async fn absent_rejection_facts_do_not_infer_recoverable_unknown_calls() {
    let legacy_call = serde_json::json!({
        "callId": "old-call", "toolId": "",
        "arguments": OpaquePayload::new("pl.model.invalid-call", 1, " original ").unwrap(),
    });
    let decoded: ModelToolCall = serde_json::from_value(legacy_call.clone()).unwrap();
    assert_eq!(decoded.rejection, None);
    assert_eq!(serde_json::to_value(decoded).unwrap(), legacy_call);
    let (model, requests) = support::ScriptedModel::new(&[""]);
    let thread = ThreadHandle::start("legacy".into(), DynModelSession::new(model)).unwrap();
    assert!(matches!(
        thread.run_turn(support::turn("legacy")).await,
        Err(ThreadError::ModelOutput(
            ModelOutputViolation::UnknownTool { .. }
        ))
    ));
    assert_eq!(requests.lock().unwrap().len(), 1);
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct Solo;
impl pl_core::tool::opaque::Tool for Solo {
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
