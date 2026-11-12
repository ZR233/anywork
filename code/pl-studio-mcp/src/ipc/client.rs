use std::{fmt, sync::Arc};

use bytes::Bytes;
use futures::{FutureExt, future::Shared};
use http::{HeaderValue, Request};
use tokio_util::sync::CancellationToken;

use super::{platform, wire};
use crate::{HostCatalog, HostError, HostInvocation, HostResult, HostTools};

type Completion = Shared<futures::future::BoxFuture<'static, Result<(), HostError>>>;

struct Connection {
    sender: h2::client::SendRequest<Bytes>,
    capability: HeaderValue,
    cancellation: CancellationToken,
    stopped: CancellationToken,
    // The shared future owns the ORIGINAL join, not merely a completion notification.
    completion: Completion,
}

impl Drop for Connection {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

#[derive(Clone)]
pub struct IpcClient {
    connection: Arc<Connection>,
}

impl fmt::Debug for IpcClient {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.debug_struct("IpcClient").finish_non_exhaustive()
    }
}

impl IpcClient {
    pub async fn connect(endpoint: String, capability: String) -> Result<Self, HostError> {
        let mut capability =
            HeaderValue::from_str(&capability).map_err(|_| HostError::Unauthorized)?;
        capability.set_sensitive(true);
        let io = platform::connect(&endpoint)
            .await
            .map_err(|_| HostError::Transport)?;
        let (sender, driver) = h2::client::handshake(io)
            .await
            .map_err(|_| HostError::Transport)?;
        let cancellation = CancellationToken::new();
        let stopped = CancellationToken::new();
        let task_cancel = cancellation.clone();
        let stop_guard = stopped.clone().drop_guard();
        let join = tokio::spawn(async move {
            let _stop_guard = stop_guard;
            tokio::select! {
                _ = task_cancel.cancelled() => Ok(()),
                result = driver => result.map_err(|_| HostError::Transport),
            }
        });
        let completion = async move { join.await.map_err(|_| HostError::Transport)? }
            .boxed()
            .shared();
        Ok(Self {
            connection: Arc::new(Connection {
                sender,
                capability,
                cancellation,
                stopped,
                completion,
            }),
        })
    }

    pub async fn close(&self) -> Result<(), HostError> {
        self.connection.cancellation.cancel();
        self.connection.completion.clone().await
    }

    /// Driver termination only. Use `close` to collect the original task's join result.
    pub async fn closed(&self) {
        self.connection.stopped.cancelled().await;
    }

    async fn request<T: serde::de::DeserializeOwned>(
        &self,
        path: &'static str,
        envelope: wire::Envelope,
        cancellation: CancellationToken,
    ) -> Result<T, HostError> {
        if self.connection.cancellation.is_cancelled() || self.connection.stopped.is_cancelled() {
            return Err(HostError::Closed);
        }
        let request = async {
            let mut sender = self
                .connection
                .sender
                .clone()
                .ready()
                .await
                .map_err(|_| HostError::Transport)?;
            let mut request = Request::builder()
                .method("POST")
                .uri(path)
                .body(())
                .map_err(|_| HostError::InvalidRequest)?;
            request
                .headers_mut()
                .insert(wire::CAPABILITY_HEADER, self.connection.capability.clone());
            let (response, stream) = sender
                .send_request(request, false)
                .map_err(|_| HostError::Transport)?;
            let mut stream = wire::ResetOnDrop(stream);
            wire::send(&mut stream.0, envelope).await?;
            let response = response.await.map_err(|_| HostError::Transport)?;
            // ResetOnDrop's reset on a fully closed stream is a no-op in h2.
            wire::receive(&mut response.into_body()).await?.value()
        };
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => Err(HostError::Closed),
            _ = self.connection.cancellation.cancelled() => Err(HostError::Closed),
            result = request => result,
        }
    }
}

impl HostTools for IpcClient {
    async fn catalog(&self) -> Result<HostCatalog, HostError> {
        self.request(
            "/catalog",
            wire::Envelope::default(),
            CancellationToken::new(),
        )
        .await
    }

    async fn invoke(
        &self,
        request: HostInvocation,
        cancellation: CancellationToken,
    ) -> Result<HostResult, HostError> {
        self.request("/invoke", wire::Envelope::json(&request)?, cancellation)
            .await
    }
}
