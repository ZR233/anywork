use crate::discovery::ModelCatalogQueryError;
pub fn query_transport_error(error: reqwest::Error) -> ModelCatalogQueryError {
    if error.is_timeout() {
        return ModelCatalogQueryError::Timeout;
    }
    // Reuse the inference transport's classification/redaction, but never expose its diagnostic prose.
    match crate::transport::reqwest_error_to_pure(error) {
        pl_protocol::PureError::Provider(failure) => ModelCatalogQueryError::Transport {
            kind: failure.kind,
            http_status: failure.http_status,
        },
        _ => ModelCatalogQueryError::Configuration,
    }
}
