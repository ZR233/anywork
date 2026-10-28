//! Revision exhaustion must be rejected before a tool batch becomes impossible to settle.
mod support;

use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};
use std::time::Duration;

use pl_core::{
    context::{ContextRecord, ContextSnapshot, ContextSource, OpaquePayload},
    model::DynModelSession,
    thread::{
        AttemptOutcome, ModelOutputViolation, ModelStepLimit, ThreadCheckpoint, ThreadEffectBatch,
        ThreadError, ThreadHandle, ThreadSnapshot, TurnOutcome, TurnState,
        cold::{
            ColdStore, ColdStoreError, ColdStoreHandle, StorageExecutionPhase, StoragePressure,
            ThreadWrite,
        },
        input::{InputExecution, InputPurpose, InputState, QueuedTurn, ThreadInput},
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, Tool, ToolError},
    },
};
use tokio::sync::watch;

/// A synchronous recording backend; optional retained-cache pressure holds tool admission after
/// the model's call batch is committed. It never decides which model outputs are admissible.
#[derive(Debug, Clone)]
struct RecordingStore {
    writes: Arc<Mutex<Vec<ThreadWrite>>>,
    hold_calls: bool,
    held: Arc<AtomicBool>,
    changed: watch::Sender<()>,
}

impl RecordingStore {
    fn new(hold_calls: bool) -> Self {
        Self {
            writes: Arc::new(Mutex::new(Vec::new())),
            hold_calls,
            held: Arc::new(AtomicBool::new(false)),
            changed: watch::channel(()).0,
        }
    }

    async fn model_outcome(&self) -> ThreadEffectBatch {
        let mut changed = self.changed.subscribe();
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let effect = self.writes.lock().unwrap().iter().find_map(|write| {
                    write.effect.attempt.as_ref().and_then(|attempt| {
                        (!matches!(&attempt.outcome, AttemptOutcome::Running))
                            .then(|| write.effect.clone())
                    })
                });
                if let Some(effect) = effect {
                    // Audit the real serialized effect, including the typed rejection and usage.
                    return ThreadEffectBatch::decode(&effect.encode().unwrap()).unwrap();
                }
                changed.changed().await.unwrap();
            }
        })
        .await
        .expect("the model outcome must be recorded")
    }
}

impl ColdStore for RecordingStore {
    fn admit(&self, _thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if self.hold_calls
            && write.effect.attempt.as_ref().is_some_and(|attempt| {
                matches!(&attempt.outcome, AttemptOutcome::Committed(output) if !output.tool_calls.is_empty())
            })
        {
            self.held.store(true, Ordering::SeqCst);
        }
        self.writes.lock().unwrap().push(write);
        self.changed.send_replace(());
        Ok(())
    }

    fn pressure(&self, _thread_id: &str) -> StoragePressure {
        StoragePressure {
            // Writes complete synchronously and this backend owns no output reservations.
            has_uncommitted_work: false,
            thread_bytes: if self.held.load(Ordering::SeqCst) {
                64 * 1024 * 1024
            } else {
                0
            },
            durable_sequence: self
                .writes
                .lock()
                .unwrap()
                .last()
                .map_or(0, |write| write.effect.sequence),
            ..Default::default()
        }
    }

    fn subscribe_pressure(&self, _thread_id: &str) -> Option<watch::Receiver<()>> {
        Some(self.changed.subscribe())
    }

    async fn flush(&self, thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        assert!(sequence <= self.pressure(thread_id).durable_sequence);
        Ok(())
    }
}

#[derive(Debug)]
struct CountedTool(Arc<AtomicUsize>);

impl Tool for CountedTool {
    async fn execute(
        &self,
        input: OpaquePayload,
        _context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.0.fetch_add(1, Ordering::SeqCst);
        Ok(ToolOutput::new(input, vec![support::text("tool result")]))
    }
}

fn tools(executions: &Arc<AtomicUsize>) -> Vec<Registration> {
    ["first", "second"]
        .into_iter()
        .map(|id| {
            Registration::new(
                id.into(),
                OpaquePayload::text(id),
                CountedTool(executions.clone()),
            )
            .unwrap()
            .foreground_coexisting()
        })
        .collect()
}

#[derive(Clone, Copy)]
enum Expected {
    Rejected,
    Cancelled,
    Completed,
    StepLimit,
}

#[tokio::test]
async fn model_batches_leave_revision_space_for_results_and_cancellation() {
    for (name, input_revision, calls, expected) in [
        ("text", u64::MAX - 1, &[][..], Expected::Completed),
        (
            "no-result-slot",
            u64::MAX - 1,
            &["first"][..],
            Expected::Rejected,
        ),
        (
            "only-one-result-slot",
            u64::MAX - 2,
            &["first", "second"][..],
            Expected::Rejected,
        ),
        (
            "last-slot-cancellation",
            u64::MAX - 2,
            &["first"][..],
            Expected::Cancelled,
        ),
        (
            "two-results",
            u64::MAX - 3,
            &["first", "second"][..],
            Expected::StepLimit,
        ),
    ] {
        let context = ContextSnapshot {
            revision: input_revision.checked_sub(1).unwrap(),
            records: Arc::from([ContextRecord {
                id: "existing-input".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![support::text("existing context")],
                tool_calls: Vec::new(),
            }]),
        };
        let checkpoint = ThreadCheckpoint::capture(
            name.into(),
            0,
            ThreadSnapshot {
                context,
                ..Default::default()
            },
        );
        let store =
            RecordingStore::new(matches!(expected, Expected::Rejected | Expected::Cancelled));
        let executions = Arc::new(AtomicUsize::new(0));
        let (mut model, requests) = support::ScriptedModel::new(calls);
        model.usage.input_tokens = Some(11);
        model.usage.output_tokens = Some(7);
        let thread =
            ThreadHandle::resume(name.into(), DynModelSession::new(model), Some(checkpoint))
                .unwrap();
        thread
            .attach_storage(ColdStoreHandle::new(store.clone()))
            .await
            .unwrap();
        thread.register_tools(tools(&executions)).await.unwrap();
        thread
            .submit_input(ThreadInput {
                id: "input".into(),
                purpose: InputPurpose::Message,
                payload: OpaquePayload::text("original input"),
                context: vec![support::text("original input")],
            })
            .await
            .unwrap();
        let mut runner = tokio::spawn({
            let thread = thread.clone();
            async move {
                let mut turn = support::turn("boundary-turn");
                if matches!(expected, Expected::StepLimit) {
                    turn.max_model_steps = ModelStepLimit::Limited(1.try_into().unwrap());
                }
                thread
                    .run_next_input(QueuedTurn {
                        turn_id: turn.turn_id,
                        attempt_prefix: turn.attempt_prefix,
                        max_model_steps: turn.max_model_steps,
                        cancellation: turn.cancellation,
                    })
                    .await
            }
        });
        let effect = store.model_outcome().await;
        // A regressed unsafe admission is also held and cancelled, exposing the actual old failure
        // path rather than letting a mutant hang or execute tool side effects.
        if store.hold_calls
            && matches!(
                &effect.attempt.as_ref().unwrap().outcome,
                AttemptOutcome::Committed(_)
            )
        {
            let mut snapshots = thread.subscribe();
            tokio::time::timeout(Duration::from_secs(10), async {
                loop {
                    let snapshot = snapshots.next().await.unwrap();
                    if snapshot.persistence.execution_phase
                        == StorageExecutionPhase::PausedForStorage
                    {
                        assert_eq!(executions.load(Ordering::SeqCst), 0);
                        assert!(!snapshot.context.pending_calls().unwrap().is_empty());
                        assert!(
                            thread
                                .interrupt_execution(
                                    snapshot.execution.as_ref().unwrap().id.clone()
                                )
                                .await
                                .unwrap()
                        );
                        break;
                    }
                }
            })
            .await
            .expect("tool admission must be held before cancellation");
        }
        let result = tokio::time::timeout(Duration::from_secs(10), &mut runner)
            .await
            .unwrap()
            .unwrap();

        // No close, flush or extra owner commit can repair the checkpoint before these assertions.
        let last = store.writes.lock().unwrap().last().unwrap().clone();
        assert_eq!(
            last.checkpoint.state_revision,
            thread.snapshot().commit_sequence
        );
        assert!(last.checkpoint.state.execution.is_none());
        assert!(
            last.checkpoint
                .state
                .context
                .pending_calls()
                .unwrap()
                .is_empty()
        );
        last.checkpoint.state.context.validate_complete().unwrap();
        let terminal = last
            .checkpoint
            .state
            .turns
            .iter()
            .find(|turn| turn.turn_id == "boundary-turn")
            .unwrap();
        assert_ne!(terminal.state, TurnState::Running);
        assert!(terminal.elapsed_ms.is_some());
        assert_eq!(terminal.model_steps, 1);
        assert_eq!(requests.lock().unwrap().len(), 1);
        let admitted = requests.lock().unwrap()[0].clone();
        assert_eq!(admitted.revision, input_revision);
        assert!(
            last.checkpoint
                .state
                .context
                .records
                .starts_with(&admitted.records)
        );
        let input = last
            .checkpoint
            .state
            .terminal_inputs
            .iter()
            .find(|input| input.id == "input")
            .unwrap();
        assert!(matches!(input.state, InputState::Consumed { .. }));
        let audit = effect.attempt.as_ref().unwrap();
        let output = match &audit.outcome {
            AttemptOutcome::Committed(output) | AttemptOutcome::Rejected { output, .. } => output,
            other => panic!("unexpected model audit: {other:?}"),
        };
        assert_eq!(output.usage.input_tokens, Some(11));
        assert_eq!(output.usage.output_tokens, Some(7));
        assert_eq!(output.tool_calls.len(), calls.len());
        match expected {
            Expected::Rejected => {
                assert!(matches!(
                    &audit.outcome,
                    AttemptOutcome::Rejected {
                        reason: ModelOutputViolation::ContextRevisionExhausted { revision },
                        ..
                    } if *revision == input_revision
                ));
                assert!(matches!(
                    result,
                    Err(ThreadError::ModelOutput(ModelOutputViolation::ContextRevisionExhausted { revision }))
                        if revision == input_revision
                ));
                assert!(matches!(
                    terminal.state,
                    TurnState::Failed {
                        model_failure: None,
                        ..
                    }
                ));
                assert_eq!(last.checkpoint.state.context, admitted);
                assert_eq!(executions.load(Ordering::SeqCst), 0);
            }
            Expected::Cancelled => {
                assert!(matches!(result, Err(ThreadError::Cancelled)));
                assert_eq!(terminal.state, TurnState::Interrupted);
                assert_eq!(last.checkpoint.state.context.revision, u64::MAX);
                assert_eq!(executions.load(Ordering::SeqCst), 0);
            }
            Expected::Completed | Expected::StepLimit => {
                let outcome = if matches!(expected, Expected::Completed) {
                    TurnOutcome::Completed
                } else {
                    TurnOutcome::StepLimit
                };
                assert_eq!(result.unwrap().unwrap().outcome, outcome);
                assert_eq!(terminal.state, TurnState::Finished(outcome));
                assert_eq!(last.checkpoint.state.context.revision, u64::MAX);
                assert_eq!(executions.load(Ordering::SeqCst), calls.len());
            }
        }

        let serialized = serde_json::to_vec(&last.checkpoint.pruned()).unwrap();
        let (model, resumed_requests) = support::ScriptedModel::new(calls);
        let resumed = ThreadHandle::resume(
            name.into(),
            DynModelSession::new(model),
            Some(serde_json::from_slice(&serialized).unwrap()),
        )
        .expect("the saved terminal checkpoint must remain recoverable");
        resumed.register_tools(tools(&executions)).await.unwrap();
        assert!(matches!(
            resumed.snapshot().input_execution,
            InputExecution::Paused
        ));
        assert!(
            resumed
                .snapshot()
                .context
                .pending_calls()
                .unwrap()
                .is_empty()
        );
        assert!(resumed_requests.lock().unwrap().is_empty());
        let expected_executions = if matches!(expected, Expected::StepLimit) {
            calls.len()
        } else {
            0
        };
        assert_eq!(executions.load(Ordering::SeqCst), expected_executions);
        resumed.close().await.unwrap();
        thread.close().await.unwrap();
    }
}
