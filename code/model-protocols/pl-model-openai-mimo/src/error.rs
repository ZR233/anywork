use pl_model_openai_wire::error::decode_openai_error;
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorInput, ProviderErrorPolicy,
    ProviderFailureKind as Kind,
};

#[derive(Debug)]
pub(crate) struct MiMoErrorPolicy;

impl ProviderErrorPolicy for MiMoErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        let error = decode_openai_error(&input)?;
        let status = input.failure_status(error.as_ref().and_then(|error| error.http_status));
        let mut fallback = ClassifiedProviderError::from_http_status(status);
        match status {
            Some(402) => fallback.kind = Kind::Quota,
            Some(421) => fallback.kind = Kind::ContentBlocked,
            // 429 can mean either short rate limiting or a depleted Token Plan. The
            // adapter has no documented stable subcode that disambiguates these.
            _ => {}
        }
        match error {
            Some(error) => {
                let (kind, retryable) = error
                    .terminal_kind
                    .map_or((fallback.kind, fallback.retryable), |kind| (kind, false));
                Ok(Some(error.classify(kind, retryable)))
            }
            None => Ok(status.filter(|status| *status >= 400).map(|_| fallback)),
        }
    }
}
