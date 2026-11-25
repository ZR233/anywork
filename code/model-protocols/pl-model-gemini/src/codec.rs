use pl_model_wire::completion::{CompletionRequest, ModelContextItem};
use pl_model_wire::model::ModelDefinition;
use pl_model_wire::protocol::{ProtocolEndpoint, WireApi};
use pl_model_wire::wire_codec::{
    EncodeHttpRequestInput, ParsedHttpError, PreparedHttpRequest, WireCodec, WireStreamDecoder,
};
use pl_protocol::{PureError, Result};

use crate::error::parse_google_http_error;
use crate::request::build_http_request;
use crate::sse::GeminiStreamDecoder;

pub static GEMINI_WIRE_CODEC: GeminiWireCodec = GeminiWireCodec;

#[derive(Debug, Clone, Copy, Default)]
pub struct GeminiWireCodec;

impl WireCodec for GeminiWireCodec {
    fn supports_wire_api(&self, api: WireApi) -> bool {
        api == WireApi::GeminiGenerateContent
    }

    fn validate_context_items(&self, api: WireApi, items: &[ModelContextItem]) -> Result<()> {
        if api != WireApi::GeminiGenerateContent {
            return Err(PureError::ConfigError(
                "Gemini codec requires gemini_generate_content wire API".into(),
            ));
        }
        for item in items {
            if matches!(
                item,
                ModelContextItem::Compaction { .. } | ModelContextItem::Native { .. }
            ) {
                return Err(PureError::ConfigError(
                    "session history contains native OpenAI Responses context that a Gemini model cannot consume"
                        .into(),
                ));
            }
        }
        Ok(())
    }

    fn validate_context(
        &self,
        _endpoint: &ProtocolEndpoint,
        model: &ModelDefinition,
        isolation: &str,
        request: &CompletionRequest,
    ) -> Result<()> {
        self.validate_context_items(model.extra.binding.transport.protocol, &request.input)?;
        if request.replay_spans.iter().any(|span| {
            span.source_isolation
                .as_deref()
                .is_some_and(|source| source != isolation)
                && span.output.iter().any(|part| {
                    ["thoughtSignature", "thought_signature"]
                        .into_iter()
                        .any(|key| {
                            part.get(key)
                                .and_then(serde_json::Value::as_str)
                                .is_some_and(|sig| !sig.is_empty())
                        })
                })
        }) {
            return Err(PureError::ConfigError(
                "this request cannot replay Gemini thoughtSignature state from a different credential owner"
                    .into(),
            ));
        }
        Ok(())
    }

    fn encode_http_request(
        &self,
        input: EncodeHttpRequestInput<'_>,
    ) -> Result<PreparedHttpRequest> {
        if input.is_compaction || input.compaction_body.is_some() {
            return Err(PureError::ConfigError(
                "Gemini generateContent does not support remote compaction".into(),
            ));
        }
        build_http_request(input.request, input.model)
    }

    fn new_stream_decoder(&self, _api: WireApi) -> Box<dyn WireStreamDecoder> {
        Box::new(GeminiStreamDecoder::new())
    }

    fn parse_http_error(&self, body: &[u8]) -> Option<ParsedHttpError> {
        parse_google_http_error(body)
    }
}
