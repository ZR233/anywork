//! Producer-owned, inert observation of one transport generation.
//!
//! This is not a resumable accumulator or model input. In particular, tool input remains a string
//! until the ordinary completion path validates it; decoding this view grants no execution rights.

use std::collections::BTreeMap;

use crate::completion::{
    InferenceModelObservation, ResponsesContextItem, ToolCallCaller, ToolCallKind,
};
use crate::model::UsageReport;
use pl_core::{context::OpaquePayload, model::ObservedPartIdentity};
use serde::{Deserialize, Serialize};

use crate::completion::{CompletionPresentationItem, CompletionPresentationPartKind, ToolCall};
use crate::runtime::ModelMemberState;

pub const MODEL_STREAM_CURRENT_FORMAT: &str = "pl.model.stream-current";
pub const MODEL_STREAM_CURRENT_VERSION: u32 = 1;

/// A complete accepted view of one producer, never a UI preview or a stream event log.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamCurrent {
    pub attempt_id: String,
    pub generation: u32,
    /// Sealed failed transport generations, never concatenated into this generation's response.
    #[serde(default)]
    pub previous_generations: Vec<ModelStreamCurrent>,
    pub state: ModelStreamCurrentState,
    pub response_id: Option<String>,
    pub model_observation: Option<InferenceModelObservation>,
    pub reported_model_is_terminal: bool,
    pub content_parts: Vec<ModelStreamContentPart>,
    pub blocks: Vec<ModelStreamBlock>,
    pub reasoning_summary_parts: Vec<String>,
    pub raw_reasoning_parts: Vec<String>,
    pub tool_inputs: Vec<ModelStreamToolInput>,
    pub tool_calls: Vec<ToolCall>,
    pub tool_call_callers: BTreeMap<String, ToolCallCaller>,
    pub call_bindings: Vec<ModelCallIdentity>,
    pub responses_context_items: Vec<ResponsesContextItem>,
    pub replay: ModelStreamReplay,
    pub presentation_items: Vec<CompletionPresentationItem>,
    pub members: Vec<ModelStreamMember>,
    pub presentation_states: BTreeMap<String, ModelMemberState>,
    pub final_usage: Option<UsageReport>,
    pub usage_is_terminal: bool,
}

impl ModelStreamCurrent {
    /// Encodes only logical data; live handles, trace sinks and derived indices are absent.
    pub fn encode(&self) -> Result<OpaquePayload, serde_json::Error> {
        Ok(OpaquePayload::new(
            MODEL_STREAM_CURRENT_FORMAT,
            MODEL_STREAM_CURRENT_VERSION,
            serde_json::to_string(self)?,
        )
        .expect("static stream-current format"))
    }

    /// Decodes an observation for paused display, not for execution or provider continuation.
    pub fn decode(payload: &OpaquePayload) -> pl_protocol::Result<Self> {
        if payload.format() != MODEL_STREAM_CURRENT_FORMAT
            || payload.version() != MODEL_STREAM_CURRENT_VERSION
        {
            return Err(pl_protocol::PureError::Protocol(
                "unsupported model stream current".into(),
            ));
        }
        Ok(serde_json::from_str(payload.content())?)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ModelStreamCurrentState {
    Open,
    Completed,
    Failed { message: String },
}

/// One complete merged part, including open commentary and separate reasoning sections.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamContentPart {
    pub block_id: String,
    pub content_index: u32,
    pub identity: ObservedPartIdentity,
    pub kind: CompletionPresentationPartKind,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamBlock {
    pub id: String,
    pub kind: CompletionPresentationPartKind,
    pub channel: Option<crate::trace::TraceTextChannel>,
    pub provider_item_id: Option<String>,
    pub provider_metadata: Option<serde_json::Value>,
    pub closed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamMember {
    pub identity: ObservedPartIdentity,
    pub content_available: bool,
}

/// Explicit provider-to-Core identity binding. The encoding is injective for arbitrary strings;
/// allocation of the attempt identity remains exclusively with Core.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelCallIdentity {
    pub attempt_id: String,
    pub provider_call_id: String,
    pub provider_item_id: String,
    pub call_id: String,
}

impl ModelCallIdentity {
    pub(crate) fn new(attempt_id: &str, provider_call_id: &str, provider_item_id: &str) -> Self {
        Self {
            attempt_id: attempt_id.into(),
            provider_call_id: provider_call_id.into(),
            provider_item_id: provider_item_id.into(),
            call_id: scoped_call_id(attempt_id, provider_call_id),
        }
    }
}

pub(crate) fn scoped_call_id(attempt_id: &str, provider_call_id: &str) -> String {
    format!(
        "model-call:{}:{}:{}:{}",
        attempt_id.len(),
        attempt_id,
        provider_call_id.len(),
        provider_call_id
    )
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamToolInput {
    pub stream_id: Option<String>,
    pub item_id: String,
    pub provider_call_id: Option<String>,
    pub call_id: String,
    pub name: String,
    pub kind: ToolCallKind,
    pub input: String,
    pub phase: ModelStreamToolInputPhase,
    pub stream_aliases: Vec<String>,
    pub item_aliases: Vec<String>,
    pub call_aliases: Vec<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ModelStreamToolInputPhase {
    Started,
    Streaming,
    InputCompleted,
}

/// Raw native output keeps unknown fields and signatures. Pending items are explicitly distinct
/// from completed items and are never passed to `AssistantReplay::semantic_input`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamReplay {
    pub pending_items: Vec<ModelStreamReplayItem>,
    pub items: Vec<ModelStreamReplayItem>,
    pub terminal: Option<Vec<serde_json::Value>>,
    pub chat: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelStreamReplayItem {
    pub index: Option<u32>,
    pub item: serde_json::Value,
}
