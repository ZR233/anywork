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

use crate::protocol::WireApi;
use crate::runtime::openai::sse;

use crate::stream::event::ModelStreamEvent;
use crate::stream::tagged_output::{TaggedOutputDiagnostics, TaggedVisibleOutputAdapter};

pub(crate) type CompletionEventStream = BoxStream<'static, Result<ModelStreamEvent>>;
pub(crate) type OpenAiRawEventStream = BoxStream<'static, Result<sse::SseStreamEvent>>;

pub(crate) fn decode_wire_stream(
    decoder: Box<dyn WireStreamDecoder>,
    stream: BoxStream<'static, Result<RawSseFrame>>,
    visible_output_protocol: VisibleOutputProtocol,
    close_on_terminal: bool,
    trace: Option<crate::completion::CompletionTraceContext>,
) -> CompletionEventStream {
    let state = WireStreamDecodeState {
        stream: Some(stream),
        trace,
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
                    Some(Err(error)) => return Some((Err(error), state)),
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

            let redact = |text: &str| frame.diagnostics.redact_text(text);
            let decoded = match state.decoder.decode_frame(
                &frame.data,
                frame.request_id.as_deref(),
                &redact,
            ) {
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

pub(crate) fn decode_raw_event_stream(
    api: WireApi,
    stream: OpenAiRawEventStream,
    trace: Option<crate::completion::CompletionTraceContext>,
) -> CompletionEventStream {
    let visible_output_protocol = VisibleOutputProtocol::of(api);
    let state = ProviderStreamDecodeState {
        stream,
        trace,
        decoder: sse::OpenAiStreamDecoder::new(visible_output_protocol),
        visible_output: VisibleOutputDecoder::new(visible_output_protocol),
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
            let sse_event = match state.stream.next().await {
                Some(Ok(event)) => event,
                Some(Err(error)) => return Some((Err(error), state)),
                None => {
                    state.stream_finished = true;
                    for event in state.decoder.finish() {
                        state.pending.extend(state.visible_output.decode(event));
                    }
                    state.visible_output.record_diagnostics();
                    continue;
                }
            };

            if let Err(error) =
                crate::runtime::wire_capture::capture_usage(&sse_event, state.trace.as_ref()).await
            {
                return Some((Err(error), state));
            }
            for stream_event in state.decoder.decode(&sse_event) {
                state
                    .pending
                    .extend(state.visible_output.decode(stream_event));
            }
        }
    })
    .boxed()
}

struct WireStreamDecodeState {
    stream: Option<BoxStream<'static, Result<RawSseFrame>>>,
    trace: Option<crate::completion::CompletionTraceContext>,
    decoder: Box<dyn WireStreamDecoder>,
    visible_output: VisibleOutputDecoder,
    close_on_terminal: bool,
    pending: VecDeque<ModelStreamEvent>,
    stream_finished: bool,
}

struct ProviderStreamDecodeState {
    stream: OpenAiRawEventStream,
    trace: Option<crate::completion::CompletionTraceContext>,
    decoder: sse::OpenAiStreamDecoder,
    visible_output: VisibleOutputDecoder,
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
