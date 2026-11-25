use pl_model_openai_wire::error::{OpenAiError, StringOrNumber, decode_openai_error};
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorEntry, ProviderErrorInput,
    ProviderErrorPolicy, ProviderFailureKind as Kind, ProviderRecovery,
};
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug)]
pub(crate) struct OpenAiErrorPolicy;

#[derive(Debug)]
pub(crate) struct CompatibleErrorPolicy;

impl ProviderErrorPolicy for OpenAiErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        if let Some(error) = decode_openai_error(&input)? {
            let status = input.failure_status(error.http_status);
            let code = error.code.as_deref();
            let recovery = match (code, error.param.as_deref(), input.entry, status) {
                (Some("file_not_found" | "file_expired"), _, _, _) => {
                    ProviderRecovery::RefreshAttachments
                }
                (
                    Some(
                        "previous_response_not_found"
                        | "previous_response_id_not_found"
                        | "invalid_previous_response_id",
                    ),
                    _,
                    ProviderErrorEntry::WebSocket,
                    _,
                )
                | (
                    Some("not_found" | "invalid_request_error"),
                    Some("previous_response_id"),
                    ProviderErrorEntry::WebSocket,
                    None | Some(400 | 404),
                ) => ProviderRecovery::FullContext,
                _ => ProviderRecovery::None,
            };
            let mut classified = ClassifiedProviderError::from(OfficialError { error, status });
            classified.recovery = recovery;
            return Ok(Some(classified));
        }
        if input
            .endpoint
            .is_some_and(|endpoint| endpoint.authorization.is_some())
            && let Some(payload) = input.payload
            && let Some(error) = delegated_error(payload, input.http_status)?
        {
            return Ok(Some(error));
        }
        Ok(input
            .http_status
            .filter(|status| *status >= 400)
            .map(openai_http_fallback))
    }
}

struct OfficialError {
    error: OpenAiError,
    status: Option<u16>,
}

impl From<OfficialError> for ClassifiedProviderError {
    fn from(OfficialError { error, status }: OfficialError) -> Self {
        let code = error.code.as_deref();
        let error_type = error.error_type.as_deref();
        // A specific permanent subtype wins over the generic rate-limit and server categories.
        let permanent = [code, error_type]
            .into_iter()
            .flatten()
            .find_map(|value| match value {
                "insufficient_quota"
                | "usage_limit_reached"
                | "credit_balance_exhausted"
                | "billing_hard_limit_reached"
                | "billing_not_active" => Some(Kind::Quota),
                "invalid_api_key" | "authentication_error" | "invalid_authentication" => {
                    Some(Kind::Authentication)
                }
                "permission_denied" | "insufficient_permissions" => Some(Kind::Authorization),
                "context_length_exceeded" | "context_window_exceeded" => Some(Kind::ContextLimit),
                "content_filter" | "content_policy_violation" => Some(Kind::ContentBlocked),
                "max_output_tokens" => Some(Kind::OutputLimit),
                "model_not_found"
                | "unsupported_model"
                | "file_not_found"
                | "file_expired"
                | "previous_response_not_found"
                | "previous_response_id_not_found"
                | "invalid_previous_response_id" => Some(Kind::InvalidRequest),
                _ => None,
            });
        let fallback = status.map_or_else(|| Self::from_http_status(None), openai_http_fallback);
        let (kind, retryable) = if let Some(kind) = error.terminal_kind.or(permanent) {
            (kind, false)
        } else if code == Some("websocket_connection_limit_reached") {
            // This is the documented connection lifetime limit, not provider overload.
            (Kind::Transport, true)
        } else if matches!(
            fallback.kind,
            Kind::Authentication | Kind::Authorization | Kind::InvalidRequest
        ) {
            (fallback.kind, false)
        } else if code == Some("invalid_request_error")
            || error_type == Some("invalid_request_error")
        {
            (Kind::InvalidRequest, false)
        } else {
            [code, error_type]
                .into_iter()
                .flatten()
                .find_map(|reason| match reason {
                    "rate_limit_exceeded" => Some((Kind::RateLimit, true)),
                    "server_error"
                    | "server_is_overloaded"
                    | "slow_down"
                    | "upstream_error"
                    | "temporarily_unavailable"
                    | "service_unavailable" => Some((Kind::ServiceBusy, true)),
                    "request_timeout" => Some((Kind::Transport, true)),
                    _ => None,
                })
                .unwrap_or((fallback.kind, fallback.retryable))
        };
        error.classify(kind, retryable)
    }
}

fn openai_http_fallback(status: u16) -> ClassifiedProviderError {
    let mut result = ClassifiedProviderError::from_http_status(Some(status));
    if status == 408 {
        result.kind = Kind::Transport;
        result.retryable = true;
    }
    result
}

#[derive(Deserialize)]
struct DelegatedError {
    success: bool,
    code: StringOrNumber,
    msg: String,
}

impl From<DelegatedError> for ClassifiedProviderError {
    fn from(error: DelegatedError) -> Self {
        let code = String::from(error.code);
        let mut result = Self::new(
            if code == "1000" {
                Kind::Authentication
            } else {
                Kind::Unknown
            },
            false,
            error.msg,
        );
        result.code = Some(code);
        result
    }
}

fn delegated_error(
    payload: &Value,
    status: Option<u16>,
) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
    if payload.get("success").and_then(Value::as_bool) == Some(false) {
        let error: DelegatedError = serde_json::from_value(payload.clone())?;
        debug_assert!(!error.success);
        let mut result = ClassifiedProviderError::from(error);
        if result.kind == Kind::Unknown {
            let fallback = ClassifiedProviderError::from_http_status(status);
            result.kind = fallback.kind;
            result.retryable = fallback.retryable;
        }
        return Ok(Some(result));
    }
    Ok(payload.get("detail").and_then(Value::as_str).map(|detail| {
        let mut error = ClassifiedProviderError::from_http_status(status);
        error.message = detail.to_owned();
        error
    }))
}

impl ProviderErrorPolicy for CompatibleErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        let Some(error) = decode_openai_error(&input)? else {
            return Ok(None);
        };
        let fallback =
            ClassifiedProviderError::from_http_status(input.failure_status(error.http_status));
        let code = error.code.as_deref();
        let error_type = error.error_type.as_deref();
        let (kind, retryable) = if let Some(kind) = error.terminal_kind {
            (kind, false)
        } else if matches!(
            fallback.kind,
            Kind::Authentication | Kind::Authorization | Kind::InvalidRequest
        ) {
            (fallback.kind, false)
        } else if error_type == Some("invalid_request_error")
            || code == Some("invalid_request_error")
        {
            (Kind::InvalidRequest, false)
        } else if code == Some("upstream_error") {
            (Kind::ServiceBusy, true)
        } else {
            (fallback.kind, fallback.retryable)
        };
        Ok(Some(error.classify(kind, retryable)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_model_wire::completion::stream::event::ModelStreamEvent;
    use pl_model_wire::protocol::WireApi;
    use pl_model_wire::provider_error::{
        ErrorObservedAt, ErrorPolicyBinding, ObservedRetry, ProviderErrorContext,
        StreamFrameContext,
    };
    use pl_model_wire::transport::{RequestDiagnostics, response_failure};
    use pl_protocol::{ProviderFailureStage, RetryDisposition};
    use reqwest::header::{HeaderMap, HeaderValue};
    use serde_json::json;
    use std::time::Duration;

    #[test]
    fn official_http_quota_reason_overrides_429_and_redacts_metadata() {
        let observed_at = ErrorObservedAt::now();
        let mut sensitive = HeaderValue::from_static("Bearer synthetic.provider.credential");
        sensitive.set_sensitive(true);
        let mut headers = HeaderMap::new();
        headers.insert("authorization", sensitive);
        let diagnostics = RequestDiagnostics::from_headers(&headers);
        let redact = |text: &str| diagnostics.redact_text(text);
        let body = br#"{"error":{"type":"insufficient_quota","code":"billing_hard_limit_reached","message":"account limit for synthetic.provider.credential"}}"#;
        let context = ProviderErrorContext {
            stage: ProviderFailureStage::Request,
            request_id: Some("req-429"),
            http_status: Some(429),
            observed_at,
            header_retry: ObservedRetry::Absent,
            redact: &redact,
        };
        let official = response_failure(
            Some(ErrorPolicyBinding {
                policy: crate::adapter::ADAPTER.error_policy,
                wire_api: WireApi::ChatCompletions,
                endpoint: None,
            }),
            body,
            &context,
        );

        assert_eq!(official.kind, Kind::Quota);
        assert_eq!(official.code.as_deref(), Some("billing_hard_limit_reached"));
        assert_eq!(official.error_type.as_deref(), Some("insufficient_quota"));
        assert_eq!(official.context.request_id.as_deref(), Some("req-429"));
        assert_eq!(official.http_status, Some(429));
        assert_eq!(official.retry, RetryDisposition::Permanent);
        assert_eq!(official.message, "account limit for [REDACTED_CREDENTIAL]");

        let compatible = response_failure(
            Some(ErrorPolicyBinding {
                policy: crate::adapter::COMPATIBLE_ADAPTER.error_policy,
                wire_api: WireApi::ChatCompletions,
                endpoint: None,
            }),
            body,
            &context,
        );
        assert_eq!(compatible.kind, Kind::Unknown);
        assert!(compatible.retry.is_retryable());
    }

    #[test]
    fn responses_failure_uses_payload_status_and_preserves_usage_before_terminal() {
        let adapter = &crate::adapter::ADAPTER;
        let observed_at = ErrorObservedAt::now();
        let context = StreamFrameContext {
            policy: adapter.error_policy,
            entry: ProviderErrorEntry::WebSocket,
            event_name: None,
            wire_api: WireApi::Responses,
            endpoint: None,
            failure: ProviderErrorContext {
                stage: ProviderFailureStage::Stream,
                request_id: Some("req-stream"),
                http_status: None,
                observed_at,
                header_retry: ObservedRetry::Absent,
                redact: &str::to_owned,
            },
        };
        for (value, kind, code) in [
            (
                json!({"error":{"code":1305,"type":"rate_limit_exceeded","status_code":429,"retry_after_ms":45000}}),
                Kind::RateLimit,
                "1305",
            ),
            (
                json!({"type":"response.incomplete","response":{"status":"incomplete","status_code":400,"incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":5,"output_tokens":7}}}),
                Kind::OutputLimit,
                "max_output_tokens",
            ),
            (
                json!({"type":"response.failed","response":{"status":"failed","status_code":400,"error":{"code":"billing_hard_limit_reached"},"usage":{"input_tokens":5,"output_tokens":7}}}),
                Kind::Quota,
                "billing_hard_limit_reached",
            ),
        ] {
            let mut decoder = adapter.codec.new_stream_decoder(WireApi::Responses);
            let decoded = decoder.decode_frame(&value.to_string(), &context).unwrap();
            let Some(ModelStreamEvent::Failed { failure }) = decoded.events.last() else {
                panic!("missing terminal failure: {:?}", decoded.events);
            };
            assert!(decoded.reached_terminal);
            assert_eq!(failure.kind, kind);
            assert_eq!(failure.code.as_deref(), Some(code));
            assert_eq!(failure.context.request_id.as_deref(), Some("req-stream"));
            if kind == Kind::RateLimit {
                assert_eq!(failure.http_status, Some(429));
                assert_eq!(
                    failure.retry_deadline(),
                    Some(observed_at.monotonic + Duration::from_secs(45))
                );
            } else {
                assert_eq!(failure.http_status, Some(400));
                assert!(matches!(
                    decoded.events.first(),
                    Some(ModelStreamEvent::Usage { usage, terminal: true })
                        if usage.input_tokens == Some(5) && usage.output_tokens == Some(7)
                ));
                assert!(decoded.usage_capture.is_some());
            }
            assert!(decoder.finish().is_empty());
        }
        for (outer, inner, expected) in [
            (json!({}), json!({"input_tokens":7}), Some(7)),
            (json!({"input_tokens":8}), Value::Null, Some(8)),
            (
                json!({"input_tokens":8}),
                json!({"input_tokens":9}),
                Some(9),
            ),
            (json!({"input_tokens":8}), json!({}), Some(8)),
            (
                json!({"input_tokens":"bad"}),
                json!({"input_tokens":7}),
                Some(7),
            ),
            (
                json!({"input_tokens":8}),
                json!({"input_tokens":"bad"}),
                Some(8),
            ),
            (Value::Null, json!({"input_tokens":0}), Some(0)),
            (Value::Null, Value::Null, None),
        ] {
            let mut decoder = adapter.codec.new_stream_decoder(WireApi::Responses);
            let completed = json!({"type":"response.completed","usage":outer,"response":{"id":"complete","usage":inner}});
            let decoded = decoder
                .decode_frame(&completed.to_string(), &context)
                .unwrap();
            assert!(decoded.reached_terminal);
            assert!(matches!(
                decoded.events.last(),
                Some(ModelStreamEvent::Completed { .. })
            ));
            let reports = decoded
                .events
                .iter()
                .filter_map(|event| match event {
                    ModelStreamEvent::Usage { usage, terminal } => {
                        Some((usage.input_tokens, usage.output_tokens, *terminal))
                    }
                    _ => None,
                })
                .collect::<Vec<_>>();
            assert_eq!(
                reports,
                expected
                    .map(|input| (Some(input), None, true))
                    .into_iter()
                    .collect::<Vec<_>>(),
                "{completed}"
            );
            assert_eq!(
                decoded
                    .usage_capture
                    .and_then(|capture| capture.usage["input_tokens"].as_u64()),
                expected
            );
        }
    }

    #[test]
    fn chat_output_limit_drains_trailing_usage_before_failure() {
        let adapter = &crate::adapter::ADAPTER;
        let context = StreamFrameContext {
            policy: adapter.error_policy,
            entry: ProviderErrorEntry::Sse,
            event_name: None,
            wire_api: WireApi::ChatCompletions,
            endpoint: None,
            failure: ProviderErrorContext {
                stage: ProviderFailureStage::Stream,
                request_id: Some("req-chat"),
                http_status: None,
                observed_at: ErrorObservedAt::now(),
                header_retry: ObservedRetry::Absent,
                redact: &str::to_owned,
            },
        };
        let mut decoder = adapter.codec.new_stream_decoder(WireApi::ChatCompletions);
        let partial = decoder.decode_frame(
            r#"{"id":"chat-1","choices":[{"delta":{"content":"partial"},"finish_reason":""}],"usage":{"prompt_tokens":5,"completion_tokens":2}}"#,
            &context,
        ).unwrap();
        assert!(partial.events.iter().any(
            |event| matches!(event, ModelStreamEvent::Usage { usage, terminal: false }
            if usage.input_tokens == Some(5) && usage.output_tokens == Some(2))
        ));
        let stopped = decoder.decode_frame(
            r#"{"id":"chat-1","choices":[{"delta":{"content":" text"},"finish_reason":"length"}],"usage":{"prompt_tokens":5,"completion_tokens":6}}"#,
            &context,
        ).unwrap();
        assert!(!stopped.reached_terminal);
        assert!(stopped.events.iter().any(
            |event| matches!(event, ModelStreamEvent::Usage { usage, terminal: true }
            if usage.input_tokens == Some(5) && usage.output_tokens == Some(6))
        ));
        let decoded = decoder.decode_frame(
            r#"{"id":"chat-1","choices":[],"usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12}}"#,
            &context,
        ).unwrap();
        assert!(decoded.reached_terminal);
        assert!(decoded.usage_capture.is_some());
        let (terminal, before_terminal) = decoded.events.split_last().unwrap();
        assert!(
            matches!(terminal, ModelStreamEvent::Failed { failure } if failure.kind == Kind::OutputLimit)
        );
        assert!(before_terminal.iter().any(
            |event| matches!(event, ModelStreamEvent::Usage { usage, terminal: true }
                if usage.input_tokens == Some(5) && usage.output_tokens == Some(7))
        ));
        assert!(
            !decoded
                .events
                .iter()
                .any(|event| matches!(event, ModelStreamEvent::Completed { .. }))
        );
    }

    #[test]
    fn decoder_preserves_usage_and_first_failure_at_stream_boundaries() {
        let adapter = &crate::adapter::ADAPTER;
        for (api, frames, expected) in [
            (
                WireApi::ChatCompletions,
                vec![
                    (
                        r#"{"choices":[],"usage":{"prompt_tokens":3}}"#,
                        Some((3, false)),
                    ),
                    (r#"{"choices":[],"usage":{}}"#, None),
                    (
                        r#"{"choices":[{"delta":{},"finish_reason":"length"}]}"#,
                        None,
                    ),
                    (
                        r#"{"type":"error","error":{"code":"server_error"},"usage":{"prompt_tokens":5}}"#,
                        Some((5, true)),
                    ),
                ],
                Kind::OutputLimit,
            ),
            (
                WireApi::Responses,
                vec![
                    (
                        r#"{"type":"response.in_progress","response":{"id":"one","usage":{"input_tokens":4}}}"#,
                        Some((4, false)),
                    ),
                    (
                        r#"{"type":"response.completed","response":{"id":"one","status":"failed","error":{"code":"insufficient_quota"}}}"#,
                        None,
                    ),
                ],
                Kind::Quota,
            ),
            (
                WireApi::Responses,
                vec![(
                    r#"{"type":"response.completed","response":{"id":"one","status":42}}"#,
                    None,
                )],
                Kind::Protocol,
            ),
        ] {
            let mut decoder = adapter.codec.new_stream_decoder(api);
            let context = StreamFrameContext {
                policy: adapter.error_policy,
                entry: ProviderErrorEntry::Sse,
                event_name: None,
                wire_api: api,
                endpoint: None,
                failure: ProviderErrorContext {
                    stage: ProviderFailureStage::Stream,
                    request_id: Some("req-boundary"),
                    http_status: None,
                    observed_at: ErrorObservedAt::now(),
                    header_retry: ObservedRetry::Absent,
                    redact: &str::to_owned,
                },
            };
            let mut failed = None;
            for (data, usage_expected) in frames {
                let mut reports = Vec::new();
                match decoder.decode_frame(data, &context) {
                    Ok(frame) => {
                        for event in frame.events {
                            match event {
                                ModelStreamEvent::Usage { usage, terminal } => {
                                    reports.push((usage.input_tokens.unwrap(), terminal))
                                }
                                ModelStreamEvent::Failed { failure } => failed = Some(failure),
                                ModelStreamEvent::Completed { .. } => {
                                    panic!("invalid completion was accepted: {data}")
                                }
                                _ => {}
                            }
                        }
                    }
                    Err(error) => failed = error.provider_failure_ref().cloned(),
                }
                assert_eq!(
                    reports,
                    usage_expected.into_iter().collect::<Vec<_>>(),
                    "{data}"
                );
            }
            let failure = failed.unwrap();
            assert_eq!(failure.kind, expected);
            assert!(!failure.retry.is_retryable());
        }
    }
}
