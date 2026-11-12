//! Preserve the transport's close failure which RMCP otherwise only logs.
//!
//! Framing, protocol and close scheduling remain entirely owned by RMCP.

use std::{error::Error, fmt, sync::Arc};

use rmcp::{
    RoleClient,
    model::{ClientJsonRpcMessage, ServerJsonRpcMessage},
    transport::Transport,
};

use super::ConnectionIdentity;

#[derive(Clone, Debug)]
pub(super) struct TransportError(Arc<dyn Error + Send + Sync>);

impl TransportError {
    fn new(error: impl Error + Send + Sync + 'static) -> Self {
        Self(Arc::new(error))
    }
}

impl fmt::Display for TransportError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

impl Error for TransportError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(self.0.as_ref())
    }
}

pub(super) struct ObservedTransport<T> {
    inner: T,
    identity: Arc<ConnectionIdentity>,
}

impl<T> ObservedTransport<T> {
    pub(super) fn new(inner: T, identity: Arc<ConnectionIdentity>) -> Self {
        Self { inner, identity }
    }
}

impl<T: Transport<RoleClient>> Transport<RoleClient> for ObservedTransport<T> {
    type Error = TransportError;

    fn send(
        &mut self,
        item: ClientJsonRpcMessage,
    ) -> impl Future<Output = Result<(), Self::Error>> + Send + 'static {
        let send = self.inner.send(item);
        async move { send.await.map_err(TransportError::new) }
    }

    async fn receive(&mut self) -> Option<ServerJsonRpcMessage> {
        self.inner.receive().await
    }

    async fn close(&mut self) -> Result<(), Self::Error> {
        self.inner.close().await.map_err(|error| {
            let error = TransportError::new(error);
            *self
                .identity
                .close_error
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(error.clone());
            error
        })
    }
}
