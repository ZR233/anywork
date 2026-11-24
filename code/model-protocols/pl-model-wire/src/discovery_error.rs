use pl_protocol::ProviderFailureKind;
use thiserror::Error;
/// Safe diagnostic categories; never includes URLs, headers, response text or credentials.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ModelCatalogQueryError {
    #[error("model discovery could not authorize the endpoint")]
    Authentication,
    #[error(transparent)]
    Definition(#[from] crate::model::ModelDefinitionError),
    #[error("model discovery is not supported by this adapter/catalog source")]
    Unsupported,
    #[error("model discovery endpoint or headers are invalid")]
    Configuration,
    #[error("model discovery timed out")]
    Timeout,
    #[error("model discovery transport failed ({kind:?})")]
    Transport {
        kind: ProviderFailureKind,
        http_status: Option<u16>,
    },
    #[error("model discovery returned HTTP {status}")]
    Http { status: u16 },
    #[error("model discovery response exceeded 4 MiB")]
    TooLarge,
    #[error("model discovery returned an invalid declaration")]
    Protocol,
    #[error("model discovery cache does not belong to this query")]
    CacheIdentity,
    #[error("model discovery returned 304 without a same-identity successful cache")]
    UnexpectedNotModified,
}
