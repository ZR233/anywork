//! Connection selection and opening HTTP/SSE or Responses WebSocket streams.
use super::{AttemptDispatch, OpenAiTransport, OpenedCompletionStream};
use crate::completion::CompletionTraceContext;
use crate::protocol::{ConnectionMode, WireApi};
use crate::runtime::invocation_context::InvocationPurpose;
use crate::runtime::transport_policy::RESPONSES_WEBSOCKET_IDLE_TIMEOUT;
use crate::runtime::{ModelRuntime, ModelSession, responses_websocket, wire_capture};
use pl_model_wire::provider_error::{ErrorPolicyBinding, ProviderErrorEntry};
use pl_model_wire::wire_codec::PreparedHttpRequest;
use pl_protocol::{PureError, Result};

impl ModelRuntime {
    pub(super) fn active_transport(
        &self,
        session: &ModelSession,
        purpose: &InvocationPurpose,
    ) -> OpenAiTransport {
        let transport = &self.model.extra.binding.transport;
        let connection_key = self.connection_fingerprint();
        if matches!(purpose, InvocationPurpose::Completion)
            && transport.protocol == WireApi::Responses
            && transport.default_connection_mode == ConnectionMode::WebSocket
            && !session.uses_responses_http_fallback(connection_key)
        {
            return OpenAiTransport::ResponsesWebSocket;
        }
        OpenAiTransport::Http
    }
    pub(super) fn supports_http_fallback(&self) -> bool {
        self.model
            .extra
            .binding
            .transport
            .supported_connection_modes
            .contains(&ConnectionMode::Http)
    }
    pub(super) fn stream_events(
        &self,
        prepared: PreparedHttpRequest,
        session: ModelSession,
        trace: Option<CompletionTraceContext>,
        purpose: &InvocationPurpose,
        cancellation: tokio_util::sync::CancellationToken,
        dispatch: &AttemptDispatch<'_>,
    ) -> impl std::future::Future<Output = Result<OpenedCompletionStream>> + Send {
        let http_client = self.http_client.clone();
        let api_base = self.resolve_base_url();
        let endpoint = self.endpoint.clone();
        let codec = self.codec;
        let error_policy = self.error_policy;
        let model_headers = match purpose {
            InvocationPurpose::Completion => self.model.extra.binding.request.headers.clone(),
            InvocationPurpose::RemoteCompaction { headers, .. } => headers.clone(),
        };
        let wire_api = self.model.extra.binding.transport.protocol;
        let connection_key = self.connection_fingerprint();
        let transport = self.active_transport(&session, purpose);
        async move {
            let expected_sent_model = prepared.sent_model.clone();
            if endpoint.authorization.is_some()
                && (transport != OpenAiTransport::Http || wire_api != WireApi::Responses)
            {
                return Err(PureError::ConfigError(
                    "the delegated credential requires Responses over HTTP".into(),
                ));
            }
            let token = endpoint.resolve_bearer_token().await?;
            let binding = ErrorPolicyBinding {
                policy: error_policy,
                wire_api,
                endpoint: Some(&endpoint),
            };
            if transport == OpenAiTransport::ResponsesWebSocket {
                if wire_api != WireApi::Responses {
                    return Err(PureError::ConfigError(
                        "web_socket connection mode requires the Responses API".to_string(),
                    ));
                }
                let opened = responses_websocket::stream_responses(
                    responses_websocket::StreamResponsesInput {
                        api_base,
                        token,
                        provider_headers: endpoint.http_headers.as_ref(),
                        model_headers: &model_headers,
                        connection_key,
                        model_session: session,
                        body: prepared.body,
                        expected_sent_model,
                        trace,
                        endpoint: &endpoint,
                        error_policy,
                        decoder: codec.new_stream_decoder(wire_api),
                        visible_output: prepared.visible_output,
                        cancellation,
                        dispatch,
                    },
                )
                .await?;
                return Ok(OpenedCompletionStream {
                    events: opened.events,
                    sent_model: opened.sent_model,
                    idle_timeout: Some(RESPONSES_WEBSOCKET_IDLE_TIMEOUT),
                });
            }
            let capture = wire_capture::capture_http(&prepared, trace.as_ref()).await?;
            let headers = endpoint.request_headers(token.as_deref(), &model_headers)?;
            let request = http_client
                .post(format!("{api_base}{}", prepared.path_and_query))
                .json(&prepared.body)
                .headers(headers)
                .header("accept", "text/event-stream")
                .build()
                .map_err(crate::runtime::transport::reqwest_error_to_pure)?;
            if cancellation.is_cancelled() {
                return Err(PureError::LlmError(
                    "model invocation cancelled before HTTP send".into(),
                ));
            }
            dispatch.submitting();
            let stream = match crate::runtime::transport::sse_frames(
                reqwest::RequestBuilder::from_parts(http_client, request),
                prepared.sse_content_type,
                Some(binding),
            )
            .await
            {
                Ok(stream) => {
                    if let Some(capture) = &capture {
                        capture.record_stage("streamOpened").await?;
                    }
                    stream
                }
                Err(error) => {
                    if let Some(capture) = &capture {
                        capture.record_stage("streamOpenFailed").await?;
                    }
                    return Err(error);
                }
            };

            let raw_stream = wire_capture::observe_http_stream(stream, capture);
            Ok(OpenedCompletionStream {
                events: crate::stream::decode_wire_stream(
                    codec.new_stream_decoder(wire_api),
                    raw_stream,
                    prepared.visible_output,
                    prepared.close_on_terminal,
                    trace,
                    crate::stream::StreamErrorBinding {
                        entry: ProviderErrorEntry::Sse,
                        api: wire_api,
                        endpoint,
                        policy: error_policy,
                    },
                ),
                sent_model: prepared.sent_model,
                idle_timeout: None,
            })
        }
    }
}
