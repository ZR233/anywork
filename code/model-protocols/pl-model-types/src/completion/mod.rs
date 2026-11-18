//! Canonical completion 请求、响应、事件、工具与 Web Search 类型。
//!
//! 按域拆分:`request` 承载请求构造与能力校验,`response` 承载响应与 trace 上下文,
//! `tool_call`/`tool_schema` 承载工具调用与 schema,`compaction` 承载远程压缩,
//! `usage` 承载 token 用量与 reasoning 配置,`stream`/`tool_arguments`/
//! `visible_text`/`web_search` 为既有子域。
//!
//! 本域公共类型字段与公共方法签名中出现的 `pl-protocol` 类型在下方精确重导出，
//! 消费方只需依赖 `pl-model` 即可命名完整签名。

mod attachment;
mod billing;
pub mod compaction;
mod context_item;
mod message;
pub mod replay;
pub mod request;
pub mod response;
pub mod stream;
mod tool;
pub mod tool_arguments;
pub mod tool_call;
pub mod tool_projection;
pub mod tool_schema;
pub mod usage;
mod visible_text;
pub use attachment::{AttachmentInput, AttachmentSource, ResourceAccess, ResourceReference};
pub use billing::*;
pub use compaction::*;
pub use context_item::*;
pub use message::*;
pub use pl_protocol::{FirstOutputSource, PureError, Result};
pub use replay::{AssistantReplay, Value};
pub use request::*;
pub use response::*;
pub use stream::current::*;
pub use tool::*;
pub use tool_call::*;
pub use usage::*;

mod snapshot;
pub use snapshot::{
    CompletionResponseFunctionCallSnapshot, CompletionResponseOutputSnapshot,
    CompletionResponseSnapshot, completion_response_message_text, completion_response_snapshot,
};

pub use pl_agent_tool::ToolDefinition;
pub use tool_schema::{ToolCallPolicy, tool_definition_to_spec};

mod stable_schema;
pub use stable_schema::stable_tool_schemas;

mod summary;
pub use summary::summary_request;

mod estimate;
pub use estimate::estimate_text_input_tokens;

// Channel vocabulary used directly in completion signatures.
pub use pl_core::model::ModelTextChannel;
