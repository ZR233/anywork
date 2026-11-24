//! Shared HTTP/SSE wire codec and stream decoder traits across protocol families.

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::completion::CompletionRequest;
use crate::completion::stream::event::ModelStreamEvent;
use crate::model::ModelInfo;
use crate::protocol::{ProtocolEndpoint, WireApi};
use crate::transport::SseContentTypePolicy;
use pl_protocol::{ProviderFailureKind, Result, RetryDisposition};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VisibleOutputProtocol {
    NativePhases,
    TaggedText,
}

impl VisibleOutputProtocol {
    pub fn of(api: WireApi) -> Self {
        match api {
            WireApi::Responses | WireApi::GeminiGenerateContent => Self::NativePhases,
            WireApi::ChatCompletions => Self::TaggedText,
        }
    }
}

pub struct EncodeHttpRequestInput<'a> {
    pub endpoint: &'a ProtocolEndpoint,
    pub model: &'a ModelInfo,
    pub request: &'a CompletionRequest,
    pub prompt_cache_key: Option<&'a str>,
    pub compaction_body: Option<&'a Map<String, Value>>,
    pub is_compaction: bool,
}

#[derive(Debug, Clone)]
pub struct PreparedHttpRequest {
    pub path_and_query: String,
    pub body: Map<String, Value>,
    pub sent_model: String,
    pub capture_protocol: &'static str,
    pub sse_content_type: SseContentTypePolicy,
    pub visible_output: VisibleOutputProtocol,
    pub close_on_terminal: bool,
}

#[derive(Debug, Clone)]
pub struct DecodedSseFrame {
    pub events: Vec<ModelStreamEvent>,
    pub usage_capture: Option<CapturedUsageObservation>,
    pub reached_terminal: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CapturedUsageObservation {
    pub response_id: Option<String>,
    pub model: Option<String>,
    pub service_tier: Option<String>,
    /// Numeric-only provider usage payload for wire capture receipts.
    pub usage: Value,
}

#[derive(Debug, Clone, Default)]
pub struct ParsedHttpError {
    pub code: Option<String>,
    pub message: Option<String>,
    /// Some compatible providers report auth failure inside an HTTP 200 JSON body.
    pub business_auth_failure: bool,
    pub force_kind: Option<ProviderFailureKind>,
    pub force_retry: Option<RetryDisposition>,
}

/// Protocol-family HTTP/SSE wire codec contract.
pub trait WireCodec: Send + Sync + std::fmt::Debug {
    fn supports_wire_api(&self, api: WireApi) -> bool;

    fn validate_context_items(
        &self,
        api: WireApi,
        items: &[crate::completion::ModelContextItem],
    ) -> Result<()>;

    fn validate_context(
        &self,
        endpoint: &ProtocolEndpoint,
        model: &ModelInfo,
        isolation: &str,
        request: &CompletionRequest,
    ) -> Result<()>;

    fn encode_http_request(&self, input: EncodeHttpRequestInput<'_>) -> Result<PreparedHttpRequest>;

    fn new_stream_decoder(&self, api: WireApi) -> Box<dyn WireStreamDecoder>;

    fn parse_http_error(&self, body: &[u8]) -> Option<ParsedHttpError>;
}

/// Stateful per-attempt SSE frame decoder producing canonical stream events.
pub trait WireStreamDecoder: Send {
    fn decode_frame(
        &mut self,
        data: &str,
        request_id: Option<&str>,
        redact: &dyn Fn(&str) -> String,
    ) -> Result<DecodedSseFrame>;

    fn finish(&mut self) -> Vec<ModelStreamEvent>;
}
