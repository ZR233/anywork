//! Provider 原始 SSE 流到 canonical 事件流的解码链。
//!
//! `WireStreamDecoder`（或 WebSocket 上的 `OpenAiStreamDecoder`）先把 wire 事件归一为
//! `ModelStreamEvent`，`VisibleOutputDecoder` 再按模型的可见输出协议（原生 phases 或标签文本）
//! 适配为最终对外的事件。

use futures::StreamExt;
use futures::stream::BoxStream;
use std::collections::VecDeque;

use pl_model_wire::transport::RawSseFrame;
use pl_model_wire::wire_codec::{VisibleOutputProtocol, WireStreamDecoder};
use pl_protocol::Result;

use crate::protocol::{ProtocolEndpoint, WireApi};
use pl_model_wire::provider_error::{
    ProviderErrorContext, ProviderErrorEntry, ProviderErrorPolicy, StreamFrameContext,
};

use crate::stream::event::ModelStreamEvent;
use crate::stream::tagged_output::{TaggedOutputDiagnostics, TaggedVisibleOutputAdapter};

pub(crate) type CompletionEventStream = BoxStream<'static, Result<ModelStreamEvent>>;
pub(crate) struct StreamErrorBinding {
    pub entry: ProviderErrorEntry,
    pub api: WireApi,
    pub endpoint: ProtocolEndpoint,
    pub policy: &'static dyn ProviderErrorPolicy,
}

pub(crate) fn decode_wire_stream(
    decoder: Box<dyn WireStreamDecoder>,
    stream: BoxStream<'static, Result<RawSseFrame>>,
    visible_output_protocol: VisibleOutputProtocol,
    close_on_terminal: bool,
    trace: Option<crate::completion::CompletionTraceContext>,
    binding: StreamErrorBinding,
) -> CompletionEventStream {
    let state = WireStreamDecodeState {
        stream: Some(stream),
        trace,
        binding,
        decoder,
        visible_output: VisibleOutputDecoder::new(visible_output_protocol),
        close_on_terminal,
        pending: VecDeque::new(),
        stream_finished: false,
    };

    futures::stream::unfold(state, |mut state| async move {
        loop {
            if let Some(event) = state.pending.pop_front() {
                return Some((Ok(event), state));
            }

            if state.stream_finished {
                return None;
            }
            let frame = match state.stream.as_mut() {
                Some(stream) => match stream.next().await {
                    Some(Ok(frame)) => frame,
                    Some(Err(error)) => {
                        state.stream = None;
                        state.stream_finished = true;
                        if let Some(ModelStreamEvent::Failed { failure }) = state
                            .decoder
                            .finish()
                            .into_iter()
                            .find(|event| matches!(event, ModelStreamEvent::Failed { .. }))
                        {
                            state.pending.extend(state.visible_output.decode(
                                ModelStreamEvent::Failed {
                                    failure: failure.with_source(error),
                                },
                            ));
                            state.visible_output.record_diagnostics();
                            continue;
                        }
                        return Some((Err(error), state));
                    }
                    None => {
                        state.stream = None;
                        state.stream_finished = true;
                        for event in state.decoder.finish() {
                            state.pending.extend(state.visible_output.decode(event));
                        }
                        state.visible_output.record_diagnostics();
                        continue;
                    }
                },
                None => {
                    state.stream_finished = true;
                    continue;
                }
            };

            let decoded = {
                let redact = |text: &str| frame.diagnostics.redact_text(text);
                let context = StreamFrameContext {
                    policy: state.binding.policy,
                    entry: state.binding.entry,
                    wire_api: state.binding.api,
                    endpoint: Some(&state.binding.endpoint),
                    event_name: frame.event_name.as_deref(),
                    failure: ProviderErrorContext {
                        stage: pl_protocol::ProviderFailureStage::Stream,
                        request_id: frame.request_id.as_deref(),
                        http_status: None,
                        observed_at: frame.observed_at,
                        header_retry: frame.header_retry,
                        redact: &redact,
                    },
                };
                state.decoder.decode_frame(&frame.data, &context)
            };
            let decoded = match decoded {
                Ok(decoded) => decoded,
                Err(mut error) => {
                    frame.diagnostics.redact_error(&mut error);
                    return Some((Err(error), state));
                }
            };
            if let Some(usage) = decoded.usage_capture.as_ref()
                && let Err(error) = crate::runtime::wire_capture::capture_usage_observation(
                    usage,
                    state.trace.as_ref(),
                )
                .await
            {
                return Some((Err(error), state));
            }
            for stream_event in decoded.events {
                state
                    .pending
                    .extend(state.visible_output.decode(stream_event));
            }
            if state.close_on_terminal && decoded.reached_terminal {
                state.stream = None;
                state.stream_finished = true;
                for event in state.decoder.finish() {
                    state.pending.extend(state.visible_output.decode(event));
                }
                state.visible_output.record_diagnostics();
            }
        }
    })
    .boxed()
}

struct WireStreamDecodeState {
    stream: Option<BoxStream<'static, Result<RawSseFrame>>>,
    trace: Option<crate::completion::CompletionTraceContext>,
    binding: StreamErrorBinding,
    decoder: Box<dyn WireStreamDecoder>,
    visible_output: VisibleOutputDecoder,
    close_on_terminal: bool,
    pending: VecDeque<ModelStreamEvent>,
    stream_finished: bool,
}

pub(crate) enum VisibleOutputDecoder {
    NativePhases,
    TaggedText(TaggedVisibleOutputAdapter),
}

impl VisibleOutputDecoder {
    pub(crate) fn new(protocol: VisibleOutputProtocol) -> Self {
        match protocol {
            VisibleOutputProtocol::NativePhases => Self::NativePhases,
            VisibleOutputProtocol::TaggedText => {
                Self::TaggedText(TaggedVisibleOutputAdapter::default())
            }
        }
    }

    pub(crate) fn decode(&mut self, event: ModelStreamEvent) -> Vec<ModelStreamEvent> {
        match self {
            Self::NativePhases => vec![event],
            Self::TaggedText(decoder) => decoder.adapt(event),
        }
    }

    pub(crate) fn diagnostics(&self) -> TaggedOutputDiagnostics {
        match self {
            Self::NativePhases => TaggedOutputDiagnostics::default(),
            Self::TaggedText(decoder) => decoder.diagnostics(),
        }
    }

    fn record_diagnostics(&self) {
        let diagnostics = self.diagnostics();
        if diagnostics.untagged_visible_text_segments == 0 {
            return;
        }
        tracing::warn!(
            segments = diagnostics.untagged_visible_text_segments,
            chars = diagnostics.untagged_visible_text_chars,
            "tagged visible output contained untagged visible text; using fallback final text"
        );
    }
}
