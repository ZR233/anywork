//! OpenAI Chat Completions and Responses wire codecs.
pub mod codec;
pub mod error;
pub mod openai;

pub use codec::{OPENAI_WIRE_CODEC, OpenAiWireCodec};
pub use openai::{
    OpenAiRequestBody, build_request, sent_model_from_wire_body, sse, usage,
    validate_chatgpt_request,
};
pub use pl_model_wire::wire_codec::VisibleOutputProtocol;

pub(crate) use pl_model_wire::{completion, model, protocol};
