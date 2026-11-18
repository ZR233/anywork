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
pub(crate) use request::chatgpt::validate_request as validate_chatgpt_request;
pub(crate) use request::{OpenAiRequestBody, sent_model_from_wire_body};

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

pub(crate) fn build_request(
    api: WireApi,
    instruction_role: InstructionWireRole,
    request: &CompletionRequest,
    model: &ModelInfo,
    prompt_cache_key: Option<&str>,
    chatgpt: bool,
) -> Result<OpenAiRequestBody> {
    build_openai_request_body(
        api,
        instruction_role,
        request,
        model,
        prompt_cache_key,
        chatgpt,
    )
}

/// 每次调用创建独立的解码状态；解码器不跨调用共享可变状态。
pub(crate) fn decode_stream(
    api: WireApi,
    stream: OpenAiRawEventStream,
    trace: Option<CompletionTraceContext>,
) -> CompletionEventStream {
    crate::completion::stream::decode_raw_event_stream(stream, api, trace)
}
