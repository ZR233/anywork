use super::*;
use crate::completion::{
    CompletionFailure, CompletionPresentationItem, CompletionPresentationItemKind,
    CompletionPresentationPart, CompletionPresentationPartKind, UsageReport,
};
use crate::runtime::ModelMemberState;
use pl_core::{
    context::ContextContent,
    model::{
        DynModelSession, ModelError, ModelFailureKind, ModelRequest, ModelSession,
        PreparedModelCall,
    },
    thread::{
        ModelStepLimit, ThreadHandle, TurnInput,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, ThreadWrite},
    },
};
use std::sync::{
    Mutex,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

#[derive(Debug, Default)]
struct State {
    cancellation: Mutex<Option<CancellationToken>>,
    after_content: AtomicBool,
    cancellations: AtomicUsize,
    writes: Mutex<Vec<ThreadWrite>>,
}

#[derive(Debug)]
struct Storage(Arc<State>);

impl ColdStore for Storage {
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if !write.effect.model_member_content_available.is_empty() {
            self.0.after_content.store(true, Ordering::SeqCst);
        }
        self.0.writes.lock().unwrap().push(write);
        Ok(())
    }

    fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
        if self.0.after_content.swap(false, Ordering::SeqCst) {
            self.0.cancellations.fetch_add(1, Ordering::SeqCst);
            self.0
                .cancellation
                .lock()
                .unwrap()
                .as_ref()
                .unwrap()
                .cancel();
        }
        Ok(())
    }

    async fn flush(&self, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }
}

struct CollectorModel {
    state: Arc<State>,
    failure: Option<oneshot::Sender<CompletionFailure>>,
}

impl ModelSession for CollectorModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        *self.state.cancellation.lock().unwrap() = Some(request.cancellation.clone());
        let failure = self.failure.take().unwrap();
        Ok(PreparedModelCall::new(async move {
            let (events, _) = tokio::sync::broadcast::channel(16);
            let item = CompletionPresentationItem {
                provider_item_id: "complete-unsent".into(),
                output_index: Some(0),
                kind: CompletionPresentationItemKind::Reasoning,
                parts: vec![CompletionPresentationPart {
                    content_index: 0,
                    provider_part_id: None,
                    kind: CompletionPresentationPartKind::ReasoningText,
                    text: "full authoritative reasoning".into(),
                }],
            };
            let stream = futures::stream::iter([
                Ok(event::ModelStreamEvent::Usage(UsageReport {
                    input_tokens: Some(7),
                    output_tokens: Some(3),
                    ..Default::default()
                })),
                Ok(event::ModelStreamEvent::PresentationItem {
                    item,
                    state: Some(ModelMemberState::Completed),
                }),
            ])
            .boxed();
            let result = collect_completion_event_stream_with_idle_timeout(
                stream,
                StreamCollectContext {
                    event_tx: &events,
                    trace: None,
                    trace_sink: None,
                    cancellation: Some(request.cancellation),
                    model_observation: None,
                    on_stream_end: &|| {},
                    members: request.members,
                    generation: 0,
                },
                None,
            )
            .await;
            failure.send(result.unwrap_err()).unwrap();
            Err(ModelError {
                kind: ModelFailureKind::Cancelled,
                source: None,
                details: None,
                usage: Box::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn cancelled_unsent_completed_item_returns_original_presentation_and_accounting() {
    let state = Arc::new(State::default());
    let (failure, receiver) = oneshot::channel();
    let thread = ThreadHandle::start(
        "collector-cancel".into(),
        DynModelSession::new(CollectorModel {
            state: state.clone(),
            failure: Some(failure),
        }),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(state.clone())))
        .await
        .unwrap();
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        thread.run_turn(TurnInput {
            turn_id: "turn".into(),
            attempt_prefix: "attempt".into(),
            content: vec![ContextContent::Text {
                text: Arc::from("question"),
            }],
            max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
            cancellation: Default::default(),
        }),
    )
    .await
    .unwrap();
    assert!(result.is_err());
    let failure = receiver.await.unwrap();
    assert!(failure.is_cancelled());
    assert_eq!(failure.accounting.usage.input_tokens, Some(7));
    assert_eq!(failure.accounting.usage.output_tokens, Some(3));
    assert_eq!(failure.presentation_items.len(), 1);
    assert_eq!(
        failure.presentation_items[0].parts[0].text,
        "full authoritative reasoning"
    );
    assert_eq!(state.cancellations.load(Ordering::SeqCst), 1);
    {
        let writes = state.writes.lock().unwrap();
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_member_content_available.len())
                .sum::<usize>(),
            1
        );
        assert!(
            writes
                .iter()
                .all(|write| write.effect.model_members.is_empty())
        );
    }
    thread.close().await.unwrap();
}
