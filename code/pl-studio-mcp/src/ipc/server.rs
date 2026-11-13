use std::{fmt, io};

use bytes::Bytes;
use futures::future::poll_fn;
use h2::server::SendResponse;
use http::{HeaderValue, Request, Response};
use tokio::{task::JoinHandle, task::JoinSet};
use tokio_util::sync::CancellationToken;

use super::{platform, wire};
use crate::{HostError, HostInvocation, HostTools};

pub struct IpcServer {
    endpoint: String,
    capability: String,
    cancellation: CancellationToken,
    driver: Option<JoinHandle<io::Result<()>>>,
    lease: Option<platform::Lease>,
}

impl fmt::Debug for IpcServer {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.debug_struct("IpcServer").finish_non_exhaustive()
    }
}

impl IpcServer {
    pub async fn bind<B: HostTools>(
        backend: B,
        cancellation: CancellationToken,
    ) -> io::Result<Self> {
        let (listener, lease, endpoint) = platform::bind().await?;
        let capability = uuid::Uuid::new_v4().to_string();
        let mut header = HeaderValue::from_str(&capability)
            .map_err(|_| io::Error::other("host IPC authentication setup failed"))?;
        header.set_sensitive(true);
        let cancellation = cancellation.child_token();
        let task_cancel = cancellation.clone();
        let driver = tokio::spawn(async move {
            let mut connections = JoinSet::new();
            let mut result = Ok(());
            loop {
                tokio::select! {
                    biased;
                    _ = task_cancel.cancelled() => break,
                    joined = connections.join_next(), if !connections.is_empty() => {
                        if joined.is_some_and(|r| !matches!(r, Ok(Ok(())))) {
                            result = Err(io::Error::other("host IPC connection task failed"));
                            break;
                        }
                    }
                    accepted = listener.accept() => {
                        match accepted {
                            Ok(io) => {
                                let backend = backend.clone();
                                let header = header.clone();
                                let cancellation = task_cancel.child_token();
                                connections.spawn(serve_connection(io, backend, header, cancellation));
                            }
                            Err(_) => {
                                result = Err(io::Error::other("host IPC listener failed"));
                                break;
                            }
                        }
                    }
                }
            }
            // Stop acceptance first, then cancel and join every original connection.
            drop(listener);
            task_cancel.cancel();
            while let Some(joined) = connections.join_next().await {
                if !matches!(joined, Ok(Ok(()))) {
                    result = Err(io::Error::other("host IPC connection task failed"));
                }
            }
            result
        });
        Ok(Self {
            endpoint,
            capability,
            cancellation,
            driver: Some(driver),
            lease: Some(lease),
        })
    }

    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    pub fn capability(&self) -> &str {
        &self.capability
    }

    pub async fn close(&mut self) -> io::Result<()> {
        self.cancellation.cancel();
        if let Some(driver) = &mut self.driver {
            // Await by reference: cancelling close retains the ORIGINAL join in self.
            let result = driver.await;
            self.driver = None;
            result.map_err(|_| io::Error::other("host IPC server task failed"))??;
        }
        if let Some(lease) = &mut self.lease {
            lease.close()?;
        }
        self.lease = None;
        Ok(())
    }
}

impl Drop for IpcServer {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

async fn serve_connection<B: HostTools>(
    io: platform::Stream,
    backend: B,
    capability: HeaderValue,
    cancellation: CancellationToken,
) -> io::Result<()> {
    let connection = tokio::select! {
        biased;
        _ = cancellation.cancelled() => return Ok(()),
        result = h2::server::handshake(io) => result,
    };
    let Ok(mut connection) = connection else {
        return Ok(());
    };
    let mut streams = JoinSet::new();
    let mut result = Ok(());
    let mut owner_shutdown = false;
    loop {
        tokio::select! {
            biased;
            _ = cancellation.cancelled() => {
                owner_shutdown = true;
                break;
            },
            joined = streams.join_next(), if !streams.is_empty() => {
                if joined.is_some_and(|r| r.is_err()) {
                    result = Err(io::Error::other("host IPC request task failed"));
                    break;
                }
            }
            accepted = connection.accept() => {
                match accepted {
                    Some(Ok((request, response))) => {
                        streams.spawn(serve_stream(
                            backend.clone(), capability.clone(), request, response,
                            cancellation.child_token(),
                        ));
                    }
                    _ => break,
                }
            }
        }
    }
    cancellation.cancel();
    // Every request observes cancellation without requiring further peer I/O.
    // Join these original tasks before closing their connection driver.
    while let Some(joined) = streams.join_next().await {
        if joined.is_err() {
            result = Err(io::Error::other("host IPC request task failed"));
        }
    }
    if owner_shutdown {
        // Do not turn normal owner shutdown into an unexplained wire EOF.
        // All observation tasks have finished, so no stream may delay shutdown.
        // This official API flushes GOAWAY then closes, without the extra
        // peer round-trip of graceful_shutdown or any operation replay.
        connection.abrupt_shutdown(h2::Reason::NO_ERROR);
        let _ = poll_fn(|cx| connection.poll_closed(cx)).await;
    }
    result
}

async fn serve_stream<B: HostTools>(
    backend: B,
    capability: HeaderValue,
    request: Request<h2::RecvStream>,
    mut response: SendResponse<Bytes>,
    cancellation: CancellationToken,
) {
    let _cancel_on_drop = cancellation.clone().drop_guard();
    let action = async {
        if request.headers().get(wire::CAPABILITY_HEADER) != Some(&capability) {
            return Err(HostError::Unauthorized);
        }
        if request.method() != http::Method::POST {
            return Err(HostError::InvalidRequest);
        }
        let (parts, mut body) = request.into_parts();
        let envelope = wire::receive(&mut body).await?;
        match parts.uri.path_and_query().map(|path| path.as_str()) {
            Some("/catalog") if envelope.error == 0 && envelope.payload.is_empty() => {
                wire::Envelope::json(&backend.catalog().await?)
            }
            Some("/invoke") => {
                let request: HostInvocation = envelope.value()?;
                let result = backend.invoke(request, cancellation.clone()).await?;
                wire::Envelope::json(&result)
            }
            _ => Err(HostError::InvalidRequest),
        }
    };
    let envelope = tokio::select! {
        biased;
        _ = cancellation.cancelled() => return,
        _ = poll_fn(|cx| response.poll_reset(cx)) => {
            cancellation.cancel();
            return;
        },
        result = action => result.unwrap_or_else(wire::Envelope::failure),
    };
    let Ok(mut stream) = response.send_response(Response::new(()), false) else {
        return;
    };
    tokio::select! {
        biased;
        _ = cancellation.cancelled() => stream.send_reset(h2::Reason::CANCEL),
        result = wire::send(&mut stream, envelope) => {
            if result.is_err() {
                stream.send_reset(h2::Reason::CANCEL);
            }
        }
    }
}
