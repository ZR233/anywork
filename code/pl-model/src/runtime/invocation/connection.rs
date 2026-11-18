//! Connection selection and opening HTTP/SSE or Responses WebSocket streams.
use super::{OpenAiTransport, OpenedCompletionStream};
use crate::completion::CompletionTraceContext;
use crate::protocol::{ConnectionMode, WireApi};
use crate::runtime::invocation_context::InvocationPurpose;
use crate::runtime::openai::OpenAiRequestBody;
use crate::runtime::transport_policy::RESPONSES_WEBSOCKET_IDLE_TIMEOUT;
use crate::runtime::{ModelRuntime, ModelSession, responses_websocket, wire_capture};
use futures::StreamExt;
use pl_protocol::{PureError, Result};

impl ModelRuntime {
    pub(super) fn active_transport(
        &self,
        session: &ModelSession,
        purpose: &InvocationPurpose,
    ) -> OpenAiTransport {
        let transport = &self.model.binding.transport;
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
            .binding
            .transport
            .supported_connection_modes
            .contains(&ConnectionMode::Http)
    }
    pub(super) fn stream_events(
        &self,
        body: OpenAiRequestBody,
        session: ModelSession,
        trace: Option<CompletionTraceContext>,
        purpose: &InvocationPurpose,
    ) -> impl std::future::Future<Output = Result<OpenedCompletionStream>> + Send {
        let http_client = self.http_client.clone();
        let api_base = self.resolve_base_url();
        let endpoint = self.endpoint.clone();
        let model_headers = match purpose {
            InvocationPurpose::Completion => self.model.binding.request.headers.clone(),
            InvocationPurpose::RemoteCompaction { headers, .. } => headers.clone(),
        };
        let wire_api = self.model.binding.transport.protocol;
        let connection_key = self.connection_fingerprint();
        let transport = self.active_transport(&session, purpose);
        async move {
            let expected_sent_model = body.sent_model()?;
            if endpoint.chatgpt_session.is_some()
                && (transport != OpenAiTransport::Http || wire_api != WireApi::Responses)
            {
                return Err(PureError::ConfigError(
                    pl_model_auth::chatgpt::ChatGptAuthError::UnsupportedResource.to_string(),
                ));
            }
            let token = endpoint.resolve_bearer_token().await?;
            if transport == OpenAiTransport::ResponsesWebSocket {
                let OpenAiRequestBody::Responses(body) = body else {
                    return Err(PureError::ConfigError(
                        "web_socket connection mode requires the Responses API".to_string(),
                    ));
                };
                let raw_stream = responses_websocket::stream_responses(
                    responses_websocket::StreamResponsesInput {
                        api_base,
                        token,
                        provider_headers: endpoint.http_headers.as_ref(),
                        model_headers: &model_headers,
                        connection_key,
                        model_session: session,
                        body,
                        expected_sent_model,
                        trace: trace.clone(),
                    },
                )
                .await?;
                return Ok(OpenedCompletionStream {
                    events: crate::runtime::openai::decode_stream(
                        wire_api,
                        raw_stream.stream,
                        trace,
                    ),
                    sent_model: raw_stream.sent_model,
                    idle_timeout: Some(RESPONSES_WEBSOCKET_IDLE_TIMEOUT),
                });
            }
            let capture = wire_capture::capture_http(&body, trace.as_ref()).await?;
            let headers = endpoint.request_headers(token.as_deref(), &model_headers)?;
            let request = match body {
                OpenAiRequestBody::Responses(body) => http_client
                    .post(format!("{api_base}/responses"))
                    .json(&body),
                OpenAiRequestBody::Chat(body) => http_client
                    .post(format!("{api_base}/chat/completions"))
                    .json(&body),
            };
            // Resource and credential validation above must complete before granting this
            // narrow official-session exception. Other routes keep strict media validation.
            let content_type_policy = if endpoint.chatgpt_session.is_some() {
                crate::runtime::transport::SseContentTypePolicy::AllowMissingForChatGpt
            } else {
                crate::runtime::transport::SseContentTypePolicy::Required
            };
            let stream = match crate::runtime::transport::sse(
                request
                    .headers(headers)
                    .header("accept", "text/event-stream"),
                content_type_policy,
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

            let raw_stream = stream;
            let raw_stream = wire_capture::observe_http_stream(raw_stream, capture);
            let raw_stream = if wire_api == WireApi::Responses {
                // HTTP has no continuation lease; close the body after the terminal response.
                // WebSocket sources must still be fully drained so their lease can commit.
                futures::stream::unfold((raw_stream, false), |(mut stream, ended)| async move {
                    if ended {
                        return None;
                    }
                    let event = stream.next().await?;
                    let ended = event.as_ref().is_ok_and(|event| {
                        matches!(
                            event.kind.as_str(),
                            "response.completed" | "response.failed" | "response.incomplete"
                        )
                    });
                    Some((event, (stream, ended)))
                })
                .boxed()
            } else {
                raw_stream
            };
            Ok(OpenedCompletionStream {
                events: crate::runtime::openai::decode_stream(wire_api, raw_stream, trace),
                sent_model: expected_sent_model,
                idle_timeout: None,
            })
        }
    }
}
