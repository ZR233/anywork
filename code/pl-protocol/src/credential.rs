//! A delegated credential for a bound endpoint.
use std::{future::Future, pin::Pin, sync::Arc};

/// Supplies a fresh bearer token at request time without exposing refresh credentials.
pub trait BearerCredential: Send + Sync {
    fn registration_id(&self) -> &str;
    fn workspace_id(&self) -> Option<&str>;
    fn token<'a>(&'a self, resource: &'a str) -> TokenFuture<'a>;
}

pub type TokenFuture<'a> = Pin<Box<dyn Future<Output = crate::Result<String>> + Send + 'a>>;

/// Keeps a live credential binding while cloning endpoint configuration.
#[derive(Clone)]
pub struct EndpointAuthorization(Arc<dyn BearerCredential>);

impl EndpointAuthorization {
    pub fn new(credential: impl BearerCredential + 'static) -> Self {
        Self(Arc::new(credential))
    }

    pub fn registration_id(&self) -> &str {
        self.0.registration_id()
    }

    pub fn workspace_id(&self) -> Option<&str> {
        self.0.workspace_id()
    }

    pub async fn token(&self, resource: &str) -> crate::Result<String> {
        self.0.token(resource).await
    }
}

impl std::fmt::Debug for EndpointAuthorization {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("EndpointAuthorization(<redacted>)")
    }
}

impl PartialEq for EndpointAuthorization {
    fn eq(&self, other: &Self) -> bool {
        self.registration_id() == other.registration_id()
    }
}

impl Eq for EndpointAuthorization {}
