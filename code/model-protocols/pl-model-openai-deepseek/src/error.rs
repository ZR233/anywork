use pl_model_openai_wire::error::decode_openai_error;
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorInput, ProviderErrorPolicy,
    ProviderFailureKind as Kind, ProviderRecovery,
};

#[derive(Debug)]
pub(crate) struct DeepSeekErrorPolicy;

impl ProviderErrorPolicy for DeepSeekErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        let error = decode_openai_error(&input)?;
        let status = input.failure_status(error.as_ref().and_then(|error| error.http_status));
        let mut fallback = ClassifiedProviderError::from_http_status(status);
        match status {
            Some(402) => fallback.kind = Kind::Quota,
            Some(429) => fallback.kind = Kind::RateLimit,
            _ => {}
        }
        let Some(error) = error else {
            return Ok(status.filter(|status| *status >= 400).map(|_| fallback));
        };
        let code = error.code.as_deref();
        let attachment_expired = matches!(code, Some("file_not_found" | "file_expired"));
        let (kind, retryable) = if let Some(kind) = error.terminal_kind {
            (kind, false)
        } else if attachment_expired {
            (Kind::InvalidRequest, false)
        } else {
            [code, error.error_type.as_deref()]
                .into_iter()
                .flatten()
                .find_map(|reason| match reason {
                    "insufficient_balance" | "insufficient_quota" => Some((Kind::Quota, false)),
                    "context_length_exceeded" => Some((Kind::ContextLimit, false)),
                    "authentication_error" | "invalid_api_key" => {
                        Some((Kind::Authentication, false))
                    }
                    "invalid_request_error" if matches!(status, None | Some(400 | 413 | 422)) => {
                        Some((Kind::InvalidRequest, false))
                    }
                    _ => None,
                })
                .unwrap_or((fallback.kind, fallback.retryable))
        };
        let mut failure = error.classify(kind, retryable);
        if attachment_expired {
            failure.recovery = ProviderRecovery::RefreshAttachments;
        }
        Ok(Some(failure))
    }
}
