//! Generic HTTP egress on the selected machine; protocol parsing belongs to consumers.
use crate::{ExecutionError, Executor, executor::ExecutorBackend, stream};
use bytes::Bytes;
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::{
    io,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};
use tokio::io::{AsyncRead, AsyncReadExt, ReadBuf};
use tokio_util::{
    io::{ReaderStream, StreamReader},
    sync::CancellationToken,
};

pub(crate) mod remote;

pub type HttpInput = Pin<Box<dyn AsyncRead + Send>>;

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum RedirectPolicy {
    None,
    SameOrigin307308 { max_hops: usize },
}
#[derive(Clone, Serialize, Deserialize)]
pub struct HttpHeader {
    pub name: String,
    pub value: Vec<u8>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct HttpRequest {
    pub method: String,
    pub url: String,
    pub headers: Vec<HttpHeader>,
    pub bearer_token_env_var: Option<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HttpResponseHead {
    pub status: u16,
    pub headers: Vec<HttpHeader>,
}
impl std::fmt::Debug for HttpHeader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpHeader")
            .field("name", &self.name)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Debug for HttpRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HttpRequest")
            .field("method", &self.method)
            .field("header_count", &self.headers.len())
            .finish_non_exhaustive()
    }
}
#[derive(Serialize, Deserialize)]
pub(crate) struct Exchange {
    pub request: HttpRequest,
    pub redirect: RedirectPolicy,
}

pub struct HttpResponse {
    pub head: HttpResponseHead,
    pub body: HttpBody,
}
/// Dropping a response cancels only this exchange, never the execution connection.
pub struct HttpBody {
    pub(crate) reader: HttpInput,
    pub(crate) cancel: CancellationToken,
    pub(crate) _executor: Executor,
}
impl Drop for HttpBody {
    fn drop(&mut self) {
        self.cancel.cancel();
    }
}
impl AsyncRead for HttpBody {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        output: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self._executor.is_closed() {
            return Poll::Ready(Err(io::ErrorKind::BrokenPipe.into()));
        }
        let before = output.filled().len();
        let capacity = output.remaining();
        let result = self.reader.as_mut().poll_read(cx, output);
        if matches!(&result, Poll::Ready(Err(_)))
            || (matches!(&result, Poll::Ready(Ok(())))
                && capacity != 0
                && output.filled().len() == before)
        {
            self.cancel.cancel();
        }
        result
    }
}
#[derive(Clone)]
pub struct HttpClient {
    executor: Executor,
    redirect: RedirectPolicy,
    native: Arc<tokio::sync::OnceCell<reqwest::Client>>,
}
impl Executor {
    pub fn http(&self) -> HttpClient {
        HttpClient {
            executor: self.clone(),
            redirect: match self.inner.backend {
                ExecutorBackend::Local => RedirectPolicy::SameOrigin307308 { max_hops: 10 },
                ExecutorBackend::Remote(_) => RedirectPolicy::None,
            },
            native: Default::default(),
        }
    }
}
impl HttpClient {
    pub fn redirect(mut self, policy: RedirectPolicy) -> Self {
        self.redirect = policy;
        self.native = Default::default();
        self
    }
    pub async fn execute(
        &self,
        request: HttpRequest,
        body: HttpInput,
    ) -> Result<HttpResponse, ExecutionError> {
        if self.executor.is_closed() {
            return Err(ExecutionError::Disconnected("executor is closed".into()));
        }
        match &self.executor.inner.backend {
            ExecutorBackend::Local => self.execute_native(request, body).await,
            ExecutorBackend::Remote(connection) => {
                connection
                    .http(
                        self.executor.clone(),
                        Exchange {
                            request,
                            redirect: self.redirect,
                        },
                        body,
                    )
                    .await
            }
        }
    }
    async fn execute_native(
        &self,
        request: HttpRequest,
        body: HttpInput,
    ) -> Result<HttpResponse, ExecutionError> {
        let url = reqwest::Url::parse(&request.url)
            .map_err(|_| ExecutionError::InvalidInput("invalid HTTP URL".into()))?;
        if !matches!(url.scheme(), "http" | "https") {
            return Err(ExecutionError::InvalidInput(
                "HTTP URL requires http or https".into(),
            ));
        }
        let method = ::http::Method::from_bytes(request.method.as_bytes())
            .map_err(|_| ExecutionError::InvalidInput("invalid HTTP method".into()))?;
        let mut headers = header_map(&request.headers, true)?;
        if !headers.contains_key(::http::header::AUTHORIZATION)
            && let Some(key) = request.bearer_token_env_var
        {
            let token = self
                .executor
                .inner
                .environment
                .get(std::ffi::OsStr::new(&key))
                .and_then(|value| value.to_str())
                .filter(|value| !value.trim().is_empty())
                .ok_or_else(|| {
                    ExecutionError::InvalidInput(format!(
                        "missing bearer token environment variable '{key}'"
                    ))
                })?;
            let value = ::http::HeaderValue::from_str(&format!("Bearer {}", token.trim()))
                .map_err(|_| ExecutionError::InvalidInput("invalid bearer token header".into()))?;
            headers.insert(::http::header::AUTHORIZATION, value);
        }
        let client = self
            .native
            .get_or_try_init(|| async {
                let policy = match self.redirect {
                    RedirectPolicy::None => reqwest::redirect::Policy::none(),
                    RedirectPolicy::SameOrigin307308 { max_hops } => {
                        reqwest::redirect::Policy::custom(move |attempt| {
                            let Some(origin) = attempt.previous().first() else {
                                return attempt.stop();
                            };
                            if !matches!(attempt.status().as_u16(), 307 | 308)
                                || attempt.url().origin() != origin.origin()
                            {
                                return attempt.stop();
                            }
                            if attempt.previous().len() > max_hops {
                                return attempt.error("HTTP redirect limit exceeded");
                            }
                            attempt.follow()
                        })
                    }
                };
                reqwest::Client::builder()
                    .pool_max_idle_per_host(0)
                    .redirect(policy)
                    .build()
                    .map_err(http_error)
            })
            .await?;
        let cancel = CancellationToken::new();
        let input = CancelReader {
            reader: body,
            cancel: Box::pin(cancel.clone().cancelled_owned()),
            closing: Box::pin(self.executor.inner.closing.clone().cancelled_owned()),
        };
        let response = tokio::select! {
            _ = self.executor.inner.closing.cancelled() => return Err(ExecutionError::Disconnected("executor is closed".into())),
            response = client.request(method, url).headers(headers).body(reqwest::Body::wrap_stream(ReaderStream::new(input))).send() => response.map_err(http_error)?,
        };
        let head = HttpResponseHead {
            status: response.status().as_u16(),
            headers: headers_vec(response.headers()),
        };
        let stream = response
            .bytes_stream()
            .map(|result| result.map_err(io::Error::other));
        Ok(HttpResponse {
            head,
            body: HttpBody {
                reader: Box::pin(StreamReader::new(Box::pin(stream))),
                cancel,
                _executor: self.executor.clone(),
            },
        })
    }
}
struct CancelReader {
    reader: HttpInput,
    cancel: Pin<Box<dyn std::future::Future<Output = ()> + Send>>,
    closing: Pin<Box<dyn std::future::Future<Output = ()> + Send>>,
}
impl AsyncRead for CancelReader {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        output: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        if self.cancel.as_mut().poll(cx).is_ready() || self.closing.as_mut().poll(cx).is_ready() {
            return Poll::Ready(Err(io::ErrorKind::Interrupted.into()));
        }
        self.reader.as_mut().poll_read(cx, output)
    }
}
fn http_error(error: reqwest::Error) -> ExecutionError {
    ExecutionError::Http(Arc::new(error))
}

pub(crate) fn header_map(
    headers: &[HttpHeader],
    strip_host: bool,
) -> Result<::http::HeaderMap, ExecutionError> {
    let mut result = ::http::HeaderMap::new();
    for header in headers {
        let name = ::http::HeaderName::from_bytes(header.name.as_bytes())
            .map_err(|_| ExecutionError::InvalidInput("invalid HTTP header name".into()))?;
        let value = ::http::HeaderValue::from_bytes(&header.value)
            .map_err(|_| ExecutionError::InvalidInput("invalid HTTP header value".into()))?;
        result.append(name, value);
    }
    let nominated: Vec<_> = result
        .get_all(::http::header::CONNECTION)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| {
            value
                .split(',')
                .map(|part| part.trim().to_ascii_lowercase())
        })
        .collect();
    for name in nominated
        .iter()
        .map(String::as_str)
        .chain([
            "connection",
            "keep-alive",
            "proxy-authenticate",
            "proxy-authorization",
            "te",
            "trailer",
            "transfer-encoding",
            "upgrade",
        ])
        .chain(strip_host.then_some("host"))
    {
        result.remove(name);
    }
    Ok(result)
}
pub(crate) fn headers_vec(headers: &::http::HeaderMap) -> Vec<HttpHeader> {
    let raw: Vec<_> = headers
        .iter()
        .map(|(name, value)| HttpHeader {
            name: name.as_str().into(),
            value: value.as_bytes().to_vec(),
        })
        .collect();
    // Already parsed HeaderMap can always be filtered again.
    header_map(&raw, false)
        .expect("valid response headers")
        .iter()
        .map(|(name, value)| HttpHeader {
            name: name.as_str().into(),
            value: value.as_bytes().to_vec(),
        })
        .collect()
}
