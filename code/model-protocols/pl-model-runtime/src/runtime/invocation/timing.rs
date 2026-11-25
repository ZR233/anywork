use crate::completion::InferenceTiming;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Debug, Clone)]
pub(super) struct InferenceTimer {
    started_at: tokio::time::Instant,
    observation: Arc<Mutex<TimingObservation>>,
}

#[derive(Debug, Default)]
struct TimingObservation {
    first_output: Option<(u64, pl_protocol::FirstOutputSource)>,
    terminal_millis: Option<u64>,
}

impl InferenceTimer {
    pub(super) fn start() -> Self {
        Self {
            started_at: tokio::time::Instant::now(),
            observation: Arc::new(Mutex::new(TimingObservation::default())),
        }
    }

    pub(super) fn observe(&self, event: &crate::stream::event::ModelStreamEvent) {
        // Time and provenance publish as one observation, including across cloned stream owners.
        let mut observation = self
            .observation
            .lock()
            .expect("timing observation poisoned");
        if observation.terminal_millis.is_some() {
            return;
        }
        if matches!(
            event,
            crate::stream::event::ModelStreamEvent::Completed { .. }
                | crate::stream::event::ModelStreamEvent::Failed { .. }
        ) {
            observation.terminal_millis = Some(duration_millis(self.started_at.elapsed()));
            return;
        }
        if observation.first_output.is_none()
            && let Some(source) = event.first_output_source()
        {
            observation.first_output = Some((duration_millis(self.started_at.elapsed()), source));
        }
    }

    /// 本 attempt 起点到当前时刻（已到终态则到终态）的单调总响应耗时。
    pub(super) fn response_millis(&self) -> u64 {
        self.observation
            .lock()
            .expect("timing observation poisoned")
            .terminal_millis
            .unwrap_or_else(|| duration_millis(self.started_at.elapsed()))
    }

    /// Freeze non-event termination before failure projection, tracing or retry backoff.
    pub(super) fn mark_terminal(&self) {
        self.observation
            .lock()
            .expect("timing observation poisoned")
            .terminal_millis
            .get_or_insert_with(|| duration_millis(self.started_at.elapsed()));
    }

    /// 归一化终态到达后的耗时事实；未观察到首内容只让首字相关字段保持未知。
    ///
    /// 总响应耗时始终是消费方确认的终态边界，因此它不依赖首字；仅当首字晚于已记录的终态值
    /// 这类不一致边界出现时，才把首字整组视为未知，而不是伪造负的首字后耗时。
    pub(super) fn finish(&self) -> Option<InferenceTiming> {
        let observation = self
            .observation
            .lock()
            .expect("timing observation poisoned");
        let response_millis = observation.terminal_millis?;
        let (ttft_millis, decode_millis, first_output_source) = match observation.first_output {
            Some((first, source)) if first <= response_millis => {
                (Some(first), Some(response_millis - first), source)
            }
            _ => (None, None, pl_protocol::FirstOutputSource::Unobserved),
        };
        Some(InferenceTiming {
            first_output_source,
            ttft_millis,
            decode_millis,
            response_millis,
        })
    }
}

fn duration_millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::InferenceTimer;
    use crate::stream::event::{ModelStreamEvent, ToolInputDeltaPayload};
    use futures::{StreamExt, stream};
    use pl_protocol::FirstOutputSource;
    use std::time::Duration;

    fn tool_event(ready: bool, text: Option<&str>) -> ModelStreamEvent {
        let payload = text.map(|text| ToolInputDeltaPayload::FunctionArguments(text.into()));
        if ready {
            ModelStreamEvent::ToolCallReady {
                stream_id: None,
                item_id: "tool".into(),
                call_id: None,
                name: Some("query".into()),
                payload,
            }
        } else {
            ModelStreamEvent::ToolInputCompleted {
                stream_id: None,
                item_id: "tool".into(),
                call_id: None,
                name: Some("query".into()),
                payload,
            }
        }
    }

    #[test]
    fn complete_tool_input_observes_once_and_keeps_time_and_source_paired() {
        for ready in [false, true] {
            let timer = InferenceTimer::start();
            assert_eq!(timer.finish(), None);
            timer.observe(&tool_event(ready, Some("{\"q\":1}")));
            let first = timer.observation.lock().unwrap().first_output;
            timer
                .clone()
                .observe(&tool_event(!ready, Some("{\"q\":1}")));
            timer.observe(&ModelStreamEvent::ReasoningRawDelta {
                id: "reasoning".into(),
                content_index: 0,
                delta: "later".into(),
                provider: None,
            });
            assert_eq!(timer.observation.lock().unwrap().first_output, first);
            timer.observe(&ModelStreamEvent::Completed { response_id: None });
            let timing = timer.finish().unwrap();
            assert_eq!(
                timing.first_output_source,
                FirstOutputSource::CompletedToolInput
            );
            assert_eq!(timing.ttft_millis, first.map(|(millis, _)| millis));
            assert_eq!(
                timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
                timing.response_millis
            );
            timer.observe(&tool_event(ready, Some("ignored after terminal")));
            assert_eq!(timer.finish(), Some(timing));
        }
    }

    #[test]
    fn incremental_input_wins_over_completion_and_metadata_never_starts_output() {
        let timer = InferenceTimer::start();
        for ready in [false, true] {
            timer.observe(&tool_event(ready, None));
            timer.observe(&tool_event(ready, Some("")));
        }
        timer.observe(&ModelStreamEvent::text_completed(
            "text".into(),
            crate::completion::ModelTextChannel::Final,
            None,
            None,
        ));
        timer.observe(&ModelStreamEvent::ReasoningRawDelta {
            id: "reasoning".into(),
            content_index: 0,
            delta: String::new(),
            provider: None,
        });
        assert_eq!(timer.observation.lock().unwrap().first_output, None);
        timer.observe(&ModelStreamEvent::ToolInputDelta {
            stream_id: None,
            item_id: "tool".into(),
            call_id: None,
            name: None,
            payload_delta: ToolInputDeltaPayload::CustomInput("query".into()),
        });
        timer.observe(&tool_event(true, Some("query")));
        timer.observe(&ModelStreamEvent::Completed { response_id: None });
        assert_eq!(
            timer.finish().unwrap().first_output_source,
            FirstOutputSource::Incremental
        );

        let empty = InferenceTimer::start();
        empty.observe(&ModelStreamEvent::Completed { response_id: None });
        let timing = empty.finish().unwrap();
        assert_eq!(timing.first_output_source, FirstOutputSource::Unobserved);
        assert_eq!((timing.ttft_millis, timing.decode_millis), (None, None));
    }

    #[tokio::test]
    async fn non_event_stream_end_preserves_content_timing_and_freezes_once() {
        use crate::completion::ModelTextChannel;
        use crate::stream::{
            CompletionEventStream, StreamCollectContext,
            collect_completion_event_stream_with_idle_timeout,
        };
        use pl_protocol::PureError;
        use tokio_util::sync::CancellationToken;

        for ending in ["error", "eof", "timeout", "cancel"] {
            let mut timer = InferenceTimer::start();
            let cancellation = CancellationToken::new();
            let tail: CompletionEventStream = match ending {
                "error" => stream::once(async {
                    Err(PureError::Protocol("direct transport failure".into()))
                })
                .boxed(),
                "eof" => stream::empty().boxed(),
                _ => stream::pending().boxed(),
            };
            let events = stream::iter([
                Ok(ModelStreamEvent::text_started(
                    "text".into(),
                    ModelTextChannel::Final,
                    None,
                )),
                Ok(ModelStreamEvent::text_delta(
                    "text".into(),
                    ModelTextChannel::Final,
                    "observed content".into(),
                    None,
                )),
            ])
            .chain(tail)
            .inspect({
                let timer = timer.clone();
                let cancellation = cancellation.clone();
                move |event| {
                    if let Ok(event) = event {
                        timer.observe(event);
                        if ending == "cancel" && event.first_output_source().is_some() {
                            cancellation.cancel();
                        }
                    }
                }
            })
            .boxed();
            let on_stream_end = || timer.mark_terminal();
            let failure = collect_completion_event_stream_with_idle_timeout(
                events,
                StreamCollectContext {
                    observer: None,
                    trace: None,

                    cancellation: Some(cancellation),
                    model_observation: None,
                    on_stream_end: &on_stream_end,
                    members: None,
                    generation: 0,
                },
                Some(Duration::from_millis(1)),
                None,
                None,
            )
            .await
            .expect_err("the stream has no terminal event");
            assert_eq!(failure.is_cancelled(), ending == "cancel", "{ending}");
            if ending == "error" {
                assert!(failure.to_string().contains("direct transport failure"));
            } else if ending == "eof" {
                assert!(failure.to_string().contains("ended before completion"));
            } else if ending == "timeout" {
                assert!(failure.to_string().contains("idle timeout"));
            }
            let timing = timer.finish().expect("actual collector end must be timed");
            assert_eq!(timing.first_output_source, FirstOutputSource::Incremental);
            assert_eq!(
                timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
                timing.response_millis,
                "{ending}"
            );
            // Deterministically make a later observation differ, without a machine-speed bound.
            timer.started_at -= Duration::from_secs(1);
            timer.mark_terminal();
            assert_eq!(timer.finish(), Some(timing), "{ending}");
        }
    }

    #[tokio::test]
    async fn cancellation_at_ready_retry_deadline_keeps_last_attempt_without_sending_again() {
        use crate::runtime::{ModelInvocationContext, ModelRuntime, ModelSession};
        use crate::{
            completion::{CompletionRequest, Message, MessageContent, MessageRole},
            model::{ModelDefinition, ModelTransportProfile},
        };
        use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
        use std::future::{Future, poll_fn};
        use std::task::Poll;
        use tokio_util::sync::CancellationToken;

        let mut events = responses_text("observed output", "failed-attempt", "retry-model");
        events.pop();
        events.push(serde_json::json!({
            "type": "error", "error": {
                "code": "upstream_error", "message": "retry later", "retry_after_ms": 180000
            }
        }));
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesWebSocket,
            "cancel at retry boundary",
            0,
            Reply::WebSocket(events),
        )])
        .await
        .unwrap();
        let mut model = ModelDefinition::compatible("retry-model");
        model
            .extra
            .binding
            .set_transport(ModelTransportProfile::responses_websocket());
        let runner = ModelRuntime::bind(
            "fixture",
            pl_model_openai::endpoint::compatible_endpoint("fixture", fixture.base_url()),
            model,
            &pl_model_openai_wire::OPENAI_WIRE_CODEC,
            pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
            None,
        )
        .unwrap();
        let session = ModelSession::default();
        let cancellation = CancellationToken::new();
        let progress = pl_core::model::ModelProgressSender::detached(1024 * 1024);
        let invocation = runner.complete(
            CompletionRequest::builder()
                .messages(vec![Message {
                    role: MessageRole::User,
                    content: MessageContent::text("cancel at retry boundary"),
                    presentation: Default::default(),
                    reasoning_content: None,
                    tool_calls: None,
                    tool_result: None,
                    metadata: Default::default(),
                }])
                .build(),
            ModelInvocationContext::in_memory(session.clone())
                .with_progress(Some(progress.clone()))
                .with_cancellation(Some(cancellation.clone())),
        );
        tokio::pin!(invocation);
        tokio::time::timeout(
            Duration::from_secs(10),
            poll_fn(|cx| {
                assert!(invocation.as_mut().poll(cx).is_pending());
                if progress
                    .latest()
                    .observation()
                    .recovery
                    .is_some_and(|status| {
                        status.phase == pl_core::model::ModelRecoveryPhase::Waiting
                    })
                {
                    Poll::Ready(())
                } else {
                    Poll::Pending
                }
            }),
        )
        .await
        .unwrap();
        // Own and stop polling the invocation while both readiness conditions are established.
        // Neither the wall clock nor a scheduler race decides when the second request is sent.
        tokio::time::pause();
        tokio::time::advance(Duration::from_secs(31)).await;
        assert!(futures::poll!(invocation.as_mut()).is_pending());
        assert_eq!(
            fixture.recorded().len(),
            1,
            "the provider wait exceeds 30 seconds"
        );
        tokio::time::advance(Duration::from_secs(150)).await;
        cancellation.cancel();
        let failure = invocation.await.unwrap_err();
        tokio::time::resume();
        assert!(failure.is_cancelled());
        let timing = failure.timing.expect("last finished attempt remains timed");
        assert_eq!(timing.first_output_source, FirstOutputSource::Incremental);
        assert_eq!(
            timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
            timing.response_millis
        );
        assert!(
            timing.response_millis < 30_000,
            "backoff is not response time"
        );
        assert_eq!(fixture.recorded().len(), 1, "no second request was sent");
        session.close().await.unwrap();
        assert_eq!(fixture.finish().await.unwrap().len(), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn first_output_and_terminal_boundaries_use_one_attempt_clock() {
        for (first, tail) in [(150, 1000), (500, 8)] {
            let timer = InferenceTimer::start();
            tokio::time::advance(Duration::from_millis(first)).await;
            timer.observe(&tool_event(true, Some("{}")));
            tokio::time::advance(Duration::from_millis(tail)).await;
            timer.observe(&ModelStreamEvent::Completed { response_id: None });
            let timing = timer.finish().unwrap();
            assert_eq!(
                (
                    timing.ttft_millis,
                    timing.decode_millis,
                    timing.response_millis
                ),
                (Some(first), Some(tail), first + tail)
            );
            let usage = crate::model::UsageReport {
                input_tokens: Some(1),
                output_tokens: Some(25),
                ..Default::default()
            };
            assert_eq!(
                crate::model::usage::throughput_output_tokens(timing, &usage),
                Some(25)
            );
            // Downstream consumers run after the terminal boundary.
            tokio::time::advance(Duration::from_millis(700)).await;
            timer.mark_terminal();
            assert_eq!(timer.finish(), Some(timing));
            assert_eq!(timer.response_millis(), first + tail);
        }
    }

    #[tokio::test(start_paused = true)]
    async fn metadata_only_and_retried_attempts_keep_independent_response_windows() {
        let failed = InferenceTimer::start();
        tokio::time::advance(Duration::from_secs(3)).await;
        failed.mark_terminal();
        tokio::time::advance(Duration::from_secs(5)).await;
        let success = InferenceTimer::start();
        tokio::time::advance(Duration::from_millis(200)).await;
        success.observe(&tool_event(true, Some("{}")));
        tokio::time::advance(Duration::from_millis(400)).await;
        success.observe(&ModelStreamEvent::Completed { response_id: None });
        let timing = success.finish().unwrap();
        assert_eq!(
            (
                timing.ttft_millis,
                timing.decode_millis,
                timing.response_millis
            ),
            (Some(200), Some(400), 600)
        );
        assert_eq!(failed.finish().unwrap().response_millis, 3000);
        let metadata = InferenceTimer::start();
        tokio::time::advance(Duration::from_millis(120)).await;
        metadata.observe(&ModelStreamEvent::Completed { response_id: None });
        let timing = metadata.finish().unwrap();
        assert_eq!(
            (
                timing.first_output_source,
                timing.ttft_millis,
                timing.decode_millis,
                timing.response_millis
            ),
            (FirstOutputSource::Unobserved, None, None, 120)
        );
        for (usage, expected) in [
            (
                crate::model::UsageReport {
                    input_tokens: Some(4),
                    output_tokens: Some(6),
                    ..Default::default()
                },
                Some(6),
            ),
            (
                crate::model::UsageReport {
                    input_tokens: Some(1),
                    output_tokens: Some(2),
                    total_tokens: Some(9),
                    ..Default::default()
                },
                None,
            ),
            (
                crate::model::UsageReport {
                    input_tokens: Some(4),
                    ..Default::default()
                },
                None,
            ),
        ] {
            assert_eq!(
                crate::model::usage::throughput_output_tokens(timing, &usage),
                expected
            );
        }
    }

    #[tokio::test]
    async fn successful_retry_excludes_the_failed_attempt_and_backoff() {
        use crate::runtime::{ModelInvocationContext, ModelRuntime, ModelSession};
        use crate::{
            completion::{CompletionRequest, Message, MessageContent, MessageRole},
            model::{ModelDefinition, ModelTransportProfile},
        };
        use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
        use std::{
            future::{Future, poll_fn},
            task::Poll,
        };

        let mut first = responses_text("discarded", "failed", "retry-model");
        first.pop();
        let fixture = FixtureServer::start(vec![
            Step::prompt(
                Protocol::ResponsesHttp,
                "retry timing",
                0,
                Reply::Sse(first),
            ),
            Step::prompt(
                Protocol::ResponsesHttp,
                "retry timing",
                1,
                Reply::Sse(responses_text("accepted", "success", "retry-model")),
            ),
        ])
        .await
        .unwrap();
        let mut model = ModelDefinition::compatible("retry-model");
        model
            .extra
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        let runner = ModelRuntime::bind(
            "fixture",
            pl_model_openai::endpoint::compatible_endpoint("fixture", fixture.base_url()),
            model,
            &pl_model_openai_wire::OPENAI_WIRE_CODEC,
            pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
            None,
        )
        .unwrap();
        let progress = pl_core::model::ModelProgressSender::detached(1024 * 1024);
        let run = runner.complete(
            CompletionRequest::builder()
                .messages(vec![Message {
                    role: MessageRole::User,
                    content: MessageContent::text("retry timing"),
                    presentation: Default::default(),
                    reasoning_content: None,
                    tool_calls: None,
                    tool_result: None,
                    metadata: Default::default(),
                }])
                .build(),
            ModelInvocationContext::in_memory(ModelSession::default())
                .with_progress(Some(progress.clone())),
        );
        tokio::pin!(run);
        tokio::time::timeout(
            Duration::from_secs(5),
            poll_fn(|cx| {
                assert!(run.as_mut().poll(cx).is_pending());
                if progress
                    .latest()
                    .observation()
                    .recovery
                    .is_some_and(|status| {
                        status.phase == pl_core::model::ModelRecoveryPhase::Waiting
                    })
                {
                    Poll::Ready(())
                } else {
                    Poll::Pending
                }
            }),
        )
        .await
        .expect("the failed attempt reached the retry boundary");
        // Keep the invocation unpolled while crossing its real backoff deadline.
        tokio::time::pause();
        tokio::time::advance(Duration::from_secs(60)).await;
        tokio::time::resume();
        let result = tokio::time::timeout(Duration::from_secs(5), run)
            .await
            .unwrap()
            .unwrap();
        assert_eq!(result.content.as_deref(), Some("accepted"));
        let timing = result.timing.unwrap();
        assert_eq!(timing.first_output_source, FirstOutputSource::Incremental);
        assert_eq!(
            timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
            timing.response_millis
        );
        assert!(
            timing.response_millis < 60_000,
            "retry backoff leaked into the successful attempt"
        );
        assert_eq!(progress.latest().observation().generation, 1);
        assert_eq!(fixture.finish().await.unwrap().len(), 2);
    }

    #[tokio::test(start_paused = true)]
    async fn terminal_collection_sees_the_already_frozen_response_time() {
        use crate::stream::{
            StreamCollectContext, collect_completion_event_stream_with_idle_timeout,
        };
        use std::sync::Mutex;

        let timer = InferenceTimer::start();
        let observations = Mutex::new(Vec::new());
        tokio::time::advance(Duration::from_millis(100)).await;
        let events = stream::iter([
            Ok(ModelStreamEvent::ToolInputDelta {
                stream_id: Some("0".into()),
                item_id: "tool".into(),
                call_id: Some("call".into()),
                name: Some("noop".into()),
                payload_delta: ToolInputDeltaPayload::FunctionArguments("{}".into()),
            }),
            Ok(ModelStreamEvent::Completed { response_id: None }),
        ])
        .inspect({
            let timer = timer.clone();
            move |event| {
                if let Ok(event) = event {
                    timer.observe(event);
                }
            }
        })
        .boxed();
        let on_stream_end = || {
            observations.lock().unwrap().push(timer.finish());
            timer.mark_terminal();
        };
        let result = collect_completion_event_stream_with_idle_timeout(
            events,
            StreamCollectContext {
                observer: None,
                trace: None,
                cancellation: None,
                model_observation: None,
                on_stream_end: &on_stream_end,
                members: None,
                generation: 0,
            },
            None,
            None,
            None,
        )
        .await
        .unwrap();
        assert_eq!(result.tool_calls.len(), 1);
        assert_eq!(result.tool_calls[0].name, "noop");
        let timing = timer.finish().unwrap();
        assert_eq!(observations.into_inner().unwrap(), [Some(timing)]);
        assert_eq!(timing.response_millis, 100);
        tokio::time::advance(Duration::from_millis(700)).await;
        timer.mark_terminal();
        assert_eq!(timer.finish(), Some(timing));
    }
}
