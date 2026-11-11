//! Cancellation boundary around rmcp's official reqwest backend.

use std::{collections::HashMap, future::Future, sync::Arc};

use futures::{StreamExt, stream::BoxStream};
use reqwest::header::{HeaderName, HeaderValue};
use rmcp::model::ClientJsonRpcMessage;
use rmcp::transport::streamable_http_client::{
    SseError, StreamableHttpClient, StreamableHttpClientTransport,
    StreamableHttpClientTransportConfig, StreamableHttpClientWorker, StreamableHttpError,
    StreamableHttpPostResponse,
};
use rmcp::transport::worker::WorkerTransport;
use sse_stream_rmcp::Sse;
use tokio_util::sync::CancellationToken;

pub(super) fn transport(
    config: StreamableHttpClientTransportConfig,
) -> Result<StreamableHttpClientTransport<HostHttpClient>, reqwest::Error> {
    let cancel = CancellationToken::new();
    // rmcp 3.9's default client is private. Preserve its pooling and redirect
    // policy when injecting the cancellation-aware backend.
    let client = reqwest::Client::builder()
        .pool_max_idle_per_host(0)
        .redirect(reqwest::redirect::Policy::custom(|attempt| {
            let Some(origin) = attempt.previous().first() else {
                return attempt.stop();
            };
            if !matches!(
                attempt.status(),
                reqwest::StatusCode::TEMPORARY_REDIRECT | reqwest::StatusCode::PERMANENT_REDIRECT
            ) || attempt.url().origin() != origin.origin()
            {
                return attempt.stop();
            }
            if attempt.previous().len() > 10 {
                return attempt.error("exceeded 10 redirects");
            }
            tracing::debug!(
                status = %attempt.status(),
                from = attempt.previous().last().map(|url| url.path()).unwrap_or_default(),
                to = attempt.url().path(),
                "following same-origin redirect"
            );
            attempt.follow()
        }))
        .build()?;
    // Transport drop/close cancels this same token. rmcp's worker does not
    // poll it while awaiting the startup POST or draining startup SSE, so
    // the backend must release those I/O owners before the worker can exit.
    Ok(WorkerTransport::spawn_with_ct(
        StreamableHttpClientWorker::new(
            HostHttpClient {
                client,
                cancel: cancel.clone(),
            },
            config,
        ),
        cancel,
    ))
}

#[derive(Clone)]
pub(super) struct HostHttpClient {
    client: reqwest::Client,
    cancel: CancellationToken,
}

impl HostHttpClient {
    async fn until_cancelled<T>(
        &self,
        operation: impl Future<Output = Result<T, StreamableHttpError<reqwest::Error>>>,
    ) -> Result<T, StreamableHttpError<reqwest::Error>> {
        tokio::select! {
            biased;
            () = self.cancel.cancelled() => Err(StreamableHttpError::TransportChannelClosed),
            result = operation => result,
        }
    }

    fn cancellable_stream(
        &self,
        stream: BoxStream<'static, Result<Sse, SseError>>,
    ) -> BoxStream<'static, Result<Sse, SseError>> {
        stream
            .take_until(self.cancel.clone().cancelled_owned())
            .boxed()
    }

    fn cancellable_response(
        &self,
        response: StreamableHttpPostResponse,
    ) -> StreamableHttpPostResponse {
        match response {
            StreamableHttpPostResponse::Sse(stream, session) => {
                StreamableHttpPostResponse::Sse(self.cancellable_stream(stream), session)
            }
            response => response,
        }
    }
}

impl StreamableHttpClient for HostHttpClient {
    type Error = reqwest::Error;

    async fn post_message(
        &self,
        uri: Arc<str>,
        message: ClientJsonRpcMessage,
        session_id: Option<Arc<str>>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
    ) -> Result<StreamableHttpPostResponse, StreamableHttpError<Self::Error>> {
        let response = self
            .until_cancelled(self.client.post_message(
                uri,
                message,
                session_id,
                auth_header,
                custom_headers,
            ))
            .await?;
        Ok(self.cancellable_response(response))
    }

    async fn post_message_with_max_sse_event_size(
        &self,
        uri: Arc<str>,
        message: ClientJsonRpcMessage,
        session_id: Option<Arc<str>>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
        max_sse_event_size: usize,
    ) -> Result<StreamableHttpPostResponse, StreamableHttpError<Self::Error>> {
        // Delegate parsing, limits, auth and protocol errors to rmcp, including
        // reads of a JSON body after the response headers have arrived.
        let response = self
            .until_cancelled(self.client.post_message_with_max_sse_event_size(
                uri,
                message,
                session_id,
                auth_header,
                custom_headers,
                max_sse_event_size,
            ))
            .await?;
        // Bootstrap SSE is drained inside rmcp before its normal cancellation
        // select starts, so the returned stream must share the worker's token.
        Ok(self.cancellable_response(response))
    }

    async fn get_stream(
        &self,
        uri: Arc<str>,
        session_id: Option<Arc<str>>,
        last_event_id: Option<String>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
    ) -> Result<BoxStream<'static, Result<Sse, SseError>>, StreamableHttpError<Self::Error>> {
        let stream = self
            .until_cancelled(self.client.get_stream(
                uri,
                session_id,
                last_event_id,
                auth_header,
                custom_headers,
            ))
            .await?;
        Ok(self.cancellable_stream(stream))
    }

    async fn get_stream_with_max_sse_event_size(
        &self,
        uri: Arc<str>,
        session_id: Option<Arc<str>>,
        last_event_id: Option<String>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
        max_sse_event_size: usize,
    ) -> Result<BoxStream<'static, Result<Sse, SseError>>, StreamableHttpError<Self::Error>> {
        let stream = self
            .until_cancelled(self.client.get_stream_with_max_sse_event_size(
                uri,
                session_id,
                last_event_id,
                auth_header,
                custom_headers,
                max_sse_event_size,
            ))
            .await?;
        Ok(self.cancellable_stream(stream))
    }

    async fn delete_session(
        &self,
        uri: Arc<str>,
        session_id: Arc<str>,
        auth_header: Option<String>,
        custom_headers: HashMap<HeaderName, HeaderValue>,
    ) -> Result<(), StreamableHttpError<Self::Error>> {
        // rmcp runs DELETE after cancelling the worker and already bounds it
        // with SESSION_CLEANUP_TIMEOUT. Do not cancel away session cleanup.
        self.client
            .delete_session(uri, session_id, auth_header, custom_headers)
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Router, body::Body, routing::post};
    use rmcp::transport::Transport;
    use std::{convert::Infallible, time::Duration};

    #[tokio::test]
    async fn host_http_close_joins_worker_draining_bootstrap_sse() -> anyhow::Result<()> {
        let released = CancellationToken::new();
        let app = Router::new().route(
            "/mcp",
            post({
                let released = released.clone();
                move || {
                    let guard = released.clone().drop_guard();
                    async move {
                        let body = futures::stream::once(async move {
                            let _guard = guard;
                            std::future::pending::<Result<axum::body::Bytes, Infallible>>().await
                        });
                        (
                            [(axum::http::header::CONTENT_TYPE, "text/event-stream")],
                            Body::from_stream(body),
                        )
                    }
                }
            }),
        );
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let uri = format!("http://{}/mcp", listener.local_addr()?);
        let stop = CancellationToken::new();
        let server = tokio::spawn(
            axum::serve(listener, app)
                .with_graceful_shutdown(stop.clone().cancelled_owned())
                .into_future(),
        );
        let mut transport = transport(StreamableHttpClientTransportConfig::with_uri(uri))?;
        let discover = serde_json::from_value(serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": {}
        }))?;
        // rmcp acknowledges startup send only after POST returned response
        // headers. The worker is now draining bootstrap SSE, not awaiting send().
        tokio::time::timeout(Duration::from_secs(2), transport.send(discover)).await??;
        tokio::time::timeout(Duration::from_secs(2), transport.close()).await??;
        let disconnected = tokio::time::timeout(Duration::from_secs(2), released.cancelled()).await;
        stop.cancel();
        tokio::time::timeout(Duration::from_secs(2), server).await???;
        disconnected?;
        Ok(())
    }
}
