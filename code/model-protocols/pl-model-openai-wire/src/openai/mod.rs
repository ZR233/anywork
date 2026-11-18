use crate::completion::CompletionRequest;
use crate::model::info::ModelInfo;
use crate::protocol::{InstructionWireRole, WireApi};
use pl_protocol::Result;

mod identity;
mod request;
pub mod sse;
pub mod usage;

use request::build_openai_request_body;
pub use request::chatgpt::validate_request as validate_chatgpt_request;
pub use request::{OpenAiRequestBody, sent_model_from_wire_body};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VisibleOutputProtocol {
    NativePhases,
    TaggedText,
}

impl VisibleOutputProtocol {
    pub fn of(api: WireApi) -> Self {
        match api {
            WireApi::Responses => Self::NativePhases,
            WireApi::ChatCompletions => Self::TaggedText,
        }
    }
}

pub fn build_request(
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
