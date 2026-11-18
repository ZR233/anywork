use super::InferenceTimer;
use crate::completion::stream::event::{ModelStreamEvent, ToolInputDeltaPayload};
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
    use crate::completion::stream::{
        CompletionEventStream, StreamCollectContext,
        collect_completion_event_stream_with_idle_timeout,
    };
    use pl_protocol::PureError;
    use tokio_util::sync::CancellationToken;

    for ending in ["error", "eof", "timeout", "cancel"] {
        let mut timer = InferenceTimer::start();
        let cancellation = CancellationToken::new();
        let tail: CompletionEventStream = match ending {
            "error" => {
                stream::once(async { Err(PureError::Protocol("direct transport failure".into())) })
                    .boxed()
            }
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
        model::{ModelInfo, ModelTransportProfile},
        protocol::ProtocolEndpoint,
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    use std::future::{Future, poll_fn};
    use std::task::Poll;
    use tokio_util::sync::CancellationToken;

    let mut events = responses_text("observed output", "failed-attempt", "retry-model");
    events.pop();
    events.push(serde_json::json!({
        "type": "error", "error": {
            "code": "server_error", "message": "retry later", "retry_after_ms": 30000
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
    let mut model = ModelInfo::compatible("retry-model");
    model
        .binding
        .set_transport(ModelTransportProfile::responses_websocket());
    let runner = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model,
    )
    .unwrap();
    let session = ModelSession::default();
    let cancellation = CancellationToken::new();
    let progress = pl_core::model::ModelProgressSender::detached(1024 * 1024);
    let invocation = runner.complete_inner(
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
        ModelInvocationContext::new(session.clone())
            .with_progress(Some(progress.clone()))
            .with_cancellation(Some(cancellation.clone())),
        None,
    );
    tokio::pin!(invocation);
    tokio::time::timeout(
        Duration::from_secs(10),
        poll_fn(|cx| {
            assert!(invocation.as_mut().poll(cx).is_pending());
            if progress.latest().observation().generation == 1 {
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
