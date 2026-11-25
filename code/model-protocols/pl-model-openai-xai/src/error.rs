use pl_model_openai_wire::error::decode_openai_error;
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorInput, ProviderErrorPolicy,
    ProviderFailureKind as Kind,
};

#[derive(Debug)]
pub(crate) struct XaiErrorPolicy;

impl ProviderErrorPolicy for XaiErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        let error = decode_openai_error(&input)?;
        let status = input.failure_status(error.as_ref().and_then(|error| error.http_status));
        let mut fallback = ClassifiedProviderError::from_http_status(status);
        if status == Some(429) {
            fallback.kind = Kind::RateLimit;
        }
        match error {
            Some(error) => {
                let (kind, retryable) = if let Some(kind) = error.terminal_kind {
                    (kind, false)
                } else {
                    match error.error_type.as_deref() {
                        Some("invalid_request_error") => (Kind::InvalidRequest, false),
                        Some("authentication_error") => (Kind::Authentication, false),
                        Some("permission_error") => (Kind::Authorization, false),
                        _ => (fallback.kind, fallback.retryable),
                    }
                };
                Ok(Some(error.classify(kind, retryable)))
            }
            None => Ok(status.filter(|status| *status >= 400).map(|_| fallback)),
        }
    }
}
