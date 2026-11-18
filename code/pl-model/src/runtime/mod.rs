//! Model execution, physical session lifetime and Core adaptation.
pub use pl_core::{context::ContextContent, model::ModelError};

mod client;
mod clock;
mod compaction;
mod context;
mod host_call;
mod hosted;
pub use hosted::HostedTool;
mod attachments;
mod billing;
mod invocation;
mod invocation_context;
pub(crate) mod openai;
mod provider_error;
mod responses_websocket;
mod session;
mod summary;
pub(crate) mod transport;
pub use summary::{TextSummary, TextSummaryRequest};
pub(crate) mod transport_policy;
pub(crate) mod wire_capture;

pub use billing::model_attempt_billing;
pub use client::{ModelRuntime, NativeCompactionCheckpoint, RemoteCompaction};
pub use clock::InferenceClock;
pub use invocation_context::ModelInvocationContext;
pub(crate) use provider_error::provider_stream_failure;
pub use session::ModelSession;

pub use tokio_util::sync::CancellationToken;

pub use host_call::{ModelTurnClient, ModelTurnOptions, ModelTurnRequest};

mod cache_key;
pub(crate) mod current;
pub use cache_key::{PromptCacheScope, binding_cache_namespace, derive_prompt_cache_key};

mod prompt_diagnostics;
pub use prompt_diagnostics::{
    PromptCacheInput, PromptPrefixChangedReason, ThreadPromptMetadata, ThreadPromptSnapshot,
    prompt_diagnostics,
};

mod thread_model;
pub use thread_model::migration;
pub(crate) use thread_model::progress as model_part_identity;
pub use thread_model::{
    ModelCallBinding, ModelFailureReceipt, ModelMemberReceipt, ModelMemberState,
    ModelRequestReceipt, ModelResponseReceipt, TextCompactionBinding, ThreadCompaction,
    ThreadCompactionDecision, ThreadCompactionOptions, ThreadCompactionStrategy, ThreadModel,
    ToolAttachment, attachment_content, decode_attachment, migrate_legacy_compaction,
    model_failure_receipt, model_member_receipt, model_request_receipt, model_response_receipt,
    thread_tool_declaration, validate_attachment_content,
};

#[cfg(test)]
#[path = "tests/http_lifecycle.rs"]
mod http_lifecycle;
