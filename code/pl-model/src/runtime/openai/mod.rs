use crate::completion::stream::{CompletionEventStream, OpenAiRawEventStream};
use crate::completion::{CompletionRequest, CompletionTraceContext};
use crate::model::info::ModelInfo;
use crate::protocol::{InstructionWireRole, WireApi};
use pl_protocol::Result;

mod identity;
mod request;
pub(crate) mod sse;
pub(crate) mod usage;

use request::build_openai_request_body;
pub(crate) use request::{OpenAiRequestBody, sent_model_from_wire_body};

/// OpenAI 协议族的两种 wire API。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum OpenAiEndpoint {
    Responses,
    ChatCompletions,
}

impl OpenAiEndpoint {
    fn of(api: WireApi) -> Self {
        match api {
            WireApi::Responses => Self::Responses,
            WireApi::ChatCompletions => Self::ChatCompletions,
        }
    }
}

/// 可复用的 OpenAI base 编解码器。
///
/// 各厂商协议适配组合这个 base 获得 Chat/Responses 请求准备与事件解码；厂商自己的
/// 请求选项、目录解释和原生能力留在适配边界，不复制 SSE/HTTP/WS 实现。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct OpenAiBase;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum VisibleOutputProtocol {
    NativePhases,
    TaggedText,
}

impl VisibleOutputProtocol {
    pub(crate) fn of(api: WireApi) -> Self {
        match api {
            WireApi::Responses => Self::NativePhases,
            WireApi::ChatCompletions => Self::TaggedText,
        }
    }
}

impl OpenAiBase {
    pub(crate) fn build_request(
        &self,
        api: WireApi,
        instruction_role: InstructionWireRole,
        request: &CompletionRequest,
        model: &ModelInfo,
        prompt_cache_key: Option<&str>,
    ) -> Result<OpenAiRequestBody> {
        build_openai_request_body(
            OpenAiEndpoint::of(api),
            instruction_role,
            request,
            model,
            prompt_cache_key,
        )
    }

    /// 每次调用创建独立的解码状态；解码器不跨调用共享可变状态。
    pub(crate) fn decode_stream(
        &self,
        api: WireApi,
        stream: OpenAiRawEventStream,
        trace: Option<CompletionTraceContext>,
    ) -> CompletionEventStream {
        crate::completion::stream::decode_raw_event_stream(stream, api, trace)
    }
}
