use pl_model_openai_wire::error::decode_openai_error;
use pl_model_wire::provider_error::{
    ClassifiedProviderError, ErrorDecodeError, ProviderErrorInput, ProviderErrorPolicy,
    ProviderFailureKind as Kind,
};

#[derive(Debug)]
pub(crate) struct GlmErrorPolicy;

impl ProviderErrorPolicy for GlmErrorPolicy {
    fn decode_error(
        &self,
        input: ProviderErrorInput<'_>,
    ) -> Result<Option<ClassifiedProviderError>, ErrorDecodeError> {
        let Some(error) = decode_openai_error(&input)? else {
            return Ok(None);
        };
        let fallback =
            ClassifiedProviderError::from_http_status(input.failure_status(error.http_status));
        let (kind, retryable) = if let Some(kind) = error.terminal_kind {
            (kind, false)
        } else {
            match error.code.as_deref() {
                Some(
                    "1113" | "1308" | "1309" | "1310" | "1316" | "1317" | "1318" | "1319" | "1320"
                    | "1321",
                ) => (Kind::Quota, false),
                Some("1311" | "1313" | "1314" | "1315") => (Kind::Authorization, false),
                Some("1302") => (Kind::RateLimit, true),
                Some("1305") => (Kind::ServiceBusy, true),
                // Domestic and international documentation disagree. The existing
                // adapter has no explicit international error-contract selection.
                Some("1234") => (Kind::Unknown, false),
                _ => (fallback.kind, fallback.retryable),
            }
        };
        Ok(Some(error.classify(kind, retryable)))
    }
}
