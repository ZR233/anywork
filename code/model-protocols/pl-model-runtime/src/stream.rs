//! Canonical 流式补全：收集编排与子状态机入口。
//!
//! [`decode_raw_event_stream`] 把 provider 原始流解码为 canonical 事件流，
//! [`collect_completion_event_stream_with_idle_timeout`] 驱动 [`StreamCompletionAccumulator`]
//! 累积出 `CompletionResponse`。生命周期合法性（`lifecycle`）、工具调用增量
//! （`tool_stream`）与标签式可见输出（`tagged_output`）按各自职责维护。

mod accumulator;
use pl_model_wire::completion::stream::chat_presentation;
pub(crate) use pl_model_wire::completion::stream::current;

pub(crate) mod decode;
pub(crate) use pl_model_wire::completion::stream::event;
mod lifecycle;
pub(crate) use pl_model_wire::completion::stream::replay;
use pl_model_wire::completion::stream::tagged_output;
mod tool_identity;
mod tool_stream;

use std::time::Duration;

use futures::StreamExt;
use tracing::Instrument;

use pl_protocol::PureError;

use crate::completion::CompletionTraceContext;

pub(crate) use accumulator::StreamCompletionAccumulator;
pub(crate) use decode::{
    CompletionEventStream, OpenAiRawEventStream, decode_raw_event_stream, decode_wire_stream,
};
pub(crate) use tool_stream::ToolStream;

pub(crate) const MAX_COMPLETION_OUTPUT_BYTES: usize = 16 * 1024 * 1024;

#[derive(Debug, thiserror::Error)]
enum StreamAdmissionError {
    #[error(transparent)]
    Completion(#[from] PureError),
    #[error(transparent)]
    Member(#[from] pl_core::model::ModelMemberError),
}

/// 流收集期间的诊断身份、可靠成员端口与取消信号。
pub(crate) struct StreamCollectContext<'a> {
    pub(crate) trace: Option<CompletionTraceContext>,
    pub(crate) observer: Option<&'a crate::runtime::StreamObserver>,
    pub(crate) cancellation: Option<tokio_util::sync::CancellationToken>,
    pub(crate) model_observation: Option<crate::completion::InferenceModelObservation>,
    pub(crate) on_stream_end: &'a (dyn Fn() + Send + Sync),
    pub(crate) members: Option<pl_core::model::ModelMemberSender>,
    pub(crate) generation: u32,
    pub(crate) pending_reconnect: Option<(
        pl_core::model::ModelConnectionFact,
        std::time::Instant,
        &'a mut bool,
    )>,
}

#[tracing::instrument(
    skip_all,
    fields(
        thread_id = context.trace.as_ref().map(|trace| trace.session_id.as_str()),
        request_id = context.trace.as_ref().map(|trace| trace.inference_id.as_str()),
        generation = context.generation,
    )
)]
pub(crate) async fn collect_completion_event_stream_with_idle_timeout(
    mut stream: CompletionEventStream,
    context: StreamCollectContext<'_>,
    idle_timeout: Option<Duration>,
    accumulator: Option<StreamCompletionAccumulator>,
    mut current: Option<&mut crate::runtime::current::CurrentProducer>,
) -> std::result::Result<crate::completion::CompletionResponse, crate::completion::CompletionFailure>
{
    let StreamCollectContext {
        observer,
        trace: _,
        cancellation,
        model_observation,
        on_stream_end,
        members,
        generation,
        mut pending_reconnect,
    } = context;
    let mut accumulator =
        accumulator.unwrap_or_else(|| StreamCompletionAccumulator::new(model_observation));

    loop {
        let next_event = async {
            match idle_timeout {
                Some(timeout) => tokio::time::timeout(timeout, stream.next()).await,
                None => Ok(stream.next().await),
            }
        }
        .instrument(tracing::debug_span!(
            "model_wait",
            stage = "provider_read",
            stage_started_at = ?std::time::Instant::now(),
        ));
        let waiting = async {
            match cancellation.as_ref() {
                Some(token) => {
                    tokio::select! {
                        event = next_event => Ok(event),
                        _ = token.cancelled() => Err(()),
                    }
                }
                None => Ok(next_event.await),
            }
        };
        let next_event = if let Some(current) = current.as_deref_mut() {
            current.wait(waiting, Some(&accumulator)).await
        } else {
            waiting.await
        };
        let next_event = match next_event {
            Err(()) => {
                on_stream_end();
                accumulator.cancel_attempt("model invocation cancelled");
                if let Some(current) = current.as_deref_mut() {
                    current.freeze(&accumulator);
                }
                let mut failure = crate::completion::CompletionFailure::cancelled(
                    PureError::LlmError("model invocation cancelled".to_string()),
                    Box::new(accumulator.accounting()),
                )
                .with_optional_model_observation(accumulator.model_observation());
                failure.presentation_items = accumulator.take_presentation_items();
                return Err(failure);
            }
            Ok(event) => event,
        };
        let event = match next_event {
            Ok(Some(event)) => event,
            Ok(None) => {
                on_stream_end();
                break;
            }
            Err(_) => {
                on_stream_end();
                let error = PureError::transient_model_transport(
                    "stream error: idle timeout waiting for provider event",
                );
                accumulator.fail_attempt(&error);
                if let Some(current) = current.as_deref_mut() {
                    current.freeze(&accumulator);
                }
                return Err(crate::completion::CompletionFailure {
                    source: Box::new(error),
                    accounting: Box::new(accumulator.accounting()),
                    timing: None,
                    model_observation: accumulator.model_observation().map(Box::new),
                    presentation_items: accumulator.take_presentation_items(),
                    partial_progress: None,
                    cancelled: false,
                });
            }
        };
        let event = match event {
            Ok(event) => event,
            Err(error) => {
                on_stream_end();
                accumulator.fail_attempt(&error);
                if let Some(current) = current.as_deref_mut() {
                    current.freeze(&accumulator);
                }
                return Err(crate::completion::CompletionFailure {
                    source: Box::new(error),
                    accounting: Box::new(accumulator.accounting()),
                    timing: None,
                    model_observation: accumulator.model_observation().map(Box::new),
                    presentation_items: accumulator.take_presentation_items(),
                    partial_progress: None,
                    cancelled: false,
                });
            }
        };
        let admission = async {
            if let Some((mut fact, disconnected_at, reconnected)) = pending_reconnect.take() {
                *reconnected = true;
                if let Some(sender) = members.as_ref() {
                    fact.duration_ms = Some(
                        u64::try_from(disconnected_at.elapsed().as_millis()).unwrap_or(u64::MAX),
                    );
                    let admission = sender.connection(fact, cancellation.as_ref());
                    if let Some(current) = current.as_deref_mut() {
                        current.wait(admission, Some(&accumulator)).await?;
                    } else {
                        admission.await?;
                    }
                }
            }
            for event in accumulator.normalize(event)? {
                if let Some(observer) = observer {
                    observer.observe(generation, &event);
                }
                accumulator.apply_normalized(event)?;
                if let Some(current) = current.as_deref_mut() {
                    current.mark_dirty();
                }
                for identity in accumulator.take_started_members() {
                    if let Some(sender) = members.as_ref() {
                        let admission = sender.start(generation, identity, cancellation.as_ref());
                        if let Some(current) = current.as_deref_mut() {
                            current.wait(admission, Some(&accumulator)).await?;
                        } else {
                            admission.await?;
                        }
                    }
                }
                for identity in accumulator.take_content_available_members() {
                    if let Some(sender) = members.as_ref() {
                        // Preserve the reliable first-content position before the next normalized
                        // event, even if progress coalesces or cancellation arrives while awaiting.
                        let admission =
                            sender.content_available(generation, identity, cancellation.as_ref());
                        if let Some(current) = current.as_deref_mut() {
                            current.wait(admission, Some(&accumulator)).await?;
                        } else {
                            admission.await?;
                        }
                    }
                }
                if let Some((item, state)) = accumulator.take_completed_member()
                    && let Some(sender) = members.as_ref()
                {
                    let payload = crate::runtime::ModelMemberReceipt::encode(item, state)
                        .map_err(|error| PureError::LlmError(error.to_string()))?;
                    let provider_item_id = item.provider_item_id.clone();
                    // No cancellation select here: a fact already sent belongs to this original call
                    // until the owner's explicit admission reply. Do not poll another provider event.
                    let admission =
                        sender.submit(generation, provider_item_id, payload, cancellation.as_ref());
                    if let Some(current) = current.as_deref_mut() {
                        current.wait(admission, Some(&accumulator)).await?;
                    } else {
                        admission.await?;
                    }
                }
            }
            Ok::<(), StreamAdmissionError>(())
        }
        .await;
        if let Err(error) = admission {
            on_stream_end();
            if matches!(
                error,
                StreamAdmissionError::Member(pl_core::model::ModelMemberError::Cancelled)
            ) {
                accumulator.cancel_attempt("model invocation cancelled");
                if let Some(current) = current.as_deref_mut() {
                    current.freeze(&accumulator);
                }
                let mut failure = crate::completion::CompletionFailure::cancelled(
                    PureError::LlmError("model invocation cancelled".to_string()),
                    Box::new(accumulator.accounting()),
                )
                .with_optional_model_observation(accumulator.model_observation());
                // take_completed_member removes only its notification cursor. The immutable
                // item remains in the original presentation vector until this failure takes it.
                failure.presentation_items = accumulator.take_presentation_items();
                return Err(failure);
            }
            let error = match error {
                StreamAdmissionError::Completion(error) => error,
                StreamAdmissionError::Member(error) => PureError::LlmError(error.to_string()),
            };
            accumulator.fail_attempt(&error);
            if let Some(current) = current.as_deref_mut() {
                current.freeze(&accumulator);
            }
            return Err(crate::completion::CompletionFailure {
                source: Box::new(error),
                accounting: Box::new(accumulator.accounting()),
                timing: None,
                model_observation: accumulator.model_observation().map(Box::new),
                presentation_items: accumulator.take_presentation_items(),
                partial_progress: None,
                cancelled: false,
            });
        }
    }

    let accounting = accumulator.accounting();
    let model_observation = accumulator.model_observation();
    if let Some(current) = current.as_deref_mut() {
        current.freeze(&accumulator);
    }
    accumulator.finish().map_err(|source| {
        if let Some(current) = current.as_deref_mut() {
            current.fail_snapshot(source.to_string());
        }
        crate::completion::CompletionFailure {
            source: Box::new(source),
            accounting: Box::new(accounting),
            timing: None,
            model_observation: model_observation.map(Box::new),
            presentation_items: accumulator.take_presentation_items(),
            partial_progress: None,
            cancelled: false,
        }
    })
}

#[cfg(test)]
mod admission_tests {
    use super::*;
    use crate::completion::{
        CompletionFailure, CompletionPresentationItem, CompletionPresentationItemKind,
        CompletionPresentationPart, CompletionPresentationPartKind,
    };
    use crate::model::UsageReport;
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
    use std::sync::Arc;
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
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            *self.state.cancellation.lock().unwrap() = Some(request.cancellation.clone());
            let failure = self.failure.take().unwrap();
            Ok(PreparedModelCall::new(async move {
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
                        observer: None,
                        trace: None,

                        cancellation: Some(request.cancellation),
                        model_observation: None,
                        on_stream_end: &|| {},
                        members: request.members,
                        generation: 0,
                        pending_reconnect: None,
                    },
                    None,
                    None,
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
}
