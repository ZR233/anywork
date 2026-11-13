//! Canonical 流式补全：收集编排与子状态机入口。
//!
//! [`decode_raw_event_stream`] 把 provider 原始流解码为 canonical 事件流，
//! [`collect_completion_event_stream_with_idle_timeout`] 驱动 [`StreamCompletionAccumulator`]
//! 累积出 `CompletionResponse`。生命周期合法性（`lifecycle`）、工具调用增量
//! （`tool_stream`）、标签式可见输出（`tagged_output`）与 trace 投影
//! （`trace_projection`）是独立子状态机。

mod accumulator;

pub(super) mod chat_presentation;
pub(crate) mod decode;
pub(crate) mod event;
mod lifecycle;
pub(crate) mod replay;
mod state;
mod tagged_output;
mod tool_stream;
mod trace_projection;

use std::sync::Arc;
use std::time::Duration;

use futures::StreamExt;
use tracing::Instrument;

use pl_protocol::PureError;
use pl_protocol::trace::{AgentEventSender, TraceEventSink};

use crate::completion::CompletionTraceContext;

pub(crate) use accumulator::StreamCompletionAccumulator;
pub(crate) use decode::{CompletionEventStream, OpenAiRawEventStream, decode_raw_event_stream};
pub(crate) use tool_stream::ToolStream;

pub(crate) const MAX_COMPLETION_OUTPUT_BYTES: usize = 16 * 1024 * 1024;

#[derive(Debug, thiserror::Error)]
enum StreamAdmissionError {
    #[error(transparent)]
    Completion(#[from] PureError),
    #[error(transparent)]
    Member(#[from] pl_core::model::ModelMemberError),
}

/// 流收集期间的宿主上下文：事件输出、trace 目标与取消信号。
pub(crate) struct StreamCollectContext<'a> {
    pub(crate) event_tx: &'a AgentEventSender,
    pub(crate) trace: Option<CompletionTraceContext>,
    pub(crate) trace_sink: Option<Arc<dyn TraceEventSink>>,
    pub(crate) cancellation: Option<tokio_util::sync::CancellationToken>,
    pub(crate) model_observation: Option<pl_protocol::InferenceModelObservation>,
    pub(crate) on_stream_end: &'a (dyn Fn() + Send + Sync),
    pub(crate) members: Option<pl_core::model::ModelMemberSender>,
    pub(crate) generation: u32,
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
) -> std::result::Result<crate::completion::CompletionResponse, crate::completion::CompletionFailure>
{
    let StreamCollectContext {
        event_tx,
        trace,
        trace_sink,
        cancellation,
        model_observation,
        on_stream_end,
        members,
        generation,
    } = context;
    let mut accumulator =
        StreamCompletionAccumulator::with_model_observation(trace, trace_sink, model_observation);

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
        let next_event = match cancellation.as_ref() {
            Some(token) => {
                tokio::select! {
                    event = next_event => event,
                    _ = token.cancelled() => {
                        on_stream_end();
                        accumulator.cancel_attempt("model invocation cancelled", event_tx);
                        let mut failure = crate::completion::CompletionFailure::cancelled(
                            PureError::LlmError("model invocation cancelled".to_string()),
                            Box::new(accumulator.accounting()),
                        ).with_optional_model_observation(accumulator.model_observation());
                        failure.presentation_items = accumulator.take_presentation_items();
                        return Err(failure);
                    }
                }
            }
            None => next_event.await,
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
                accumulator.fail_attempt(&error, event_tx);
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
                accumulator.fail_attempt(&error, event_tx);
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
            for event in accumulator.normalize(event)? {
                accumulator.apply_normalized(event, event_tx)?;
                for identity in accumulator.take_started_members() {
                    if let Some(sender) = members.as_ref() {
                        sender
                            .start(generation, identity, cancellation.as_ref())
                            .await?;
                    }
                }
                for identity in accumulator.take_content_available_members() {
                    if let Some(sender) = members.as_ref() {
                        // Preserve the reliable first-content position before the next normalized
                        // event, even if progress coalesces or cancellation arrives while awaiting.
                        sender
                            .content_available(generation, identity, cancellation.as_ref())
                            .await?;
                    }
                }
                if let Some((item, state)) = accumulator.take_completed_member()
                    && let Some(sender) = members.as_ref()
                {
                    let payload = crate::runtime::ModelMemberReceipt::encode(item, state)
                        .map_err(|error| PureError::LlmError(error.to_string()))?;
                    // No cancellation select here: a fact already sent belongs to this original call
                    // until the owner's explicit admission reply. Do not poll another provider event.
                    sender
                        .submit(
                            generation,
                            item.provider_item_id.clone(),
                            payload,
                            cancellation.as_ref(),
                        )
                        .await?;
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
                accumulator.cancel_attempt("model invocation cancelled", event_tx);
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
            accumulator.fail_attempt(&error, event_tx);
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
    accumulator
        .finish(event_tx)
        .map_err(|source| crate::completion::CompletionFailure {
            source: Box::new(source),
            accounting: Box::new(accounting),
            timing: None,
            model_observation: model_observation.map(Box::new),
            presentation_items: accumulator.take_presentation_items(),
            partial_progress: None,
            cancelled: false,
        })
}

#[cfg(test)]
mod admission_tests {
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
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
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
}
