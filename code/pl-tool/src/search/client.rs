use std::collections::HashMap;
use std::time::Duration;

use super::standalone::SearchRequest;
use pl_protocol::{PureError, Result};
use pl_tool_search::tools::web_search::Response;
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use secrecy::{ExposeSecret, SecretString};

const WEB_SEARCH_REQUEST_TIMEOUT: Duration = Duration::from_secs(60);

#[derive(Debug, thiserror::Error)]
pub enum WebSearchError {
    #[error("web search request failed: {0}")]
    Transport(#[source] reqwest::Error),
    #[error("web search request returned {status}: {body}")]
    Status {
        status: reqwest::StatusCode,
        body: String,
    },
    #[error("invalid web search response: {0}")]
    Response(#[source] reqwest::Error),
}

/// Explicit standalone search transport parameters. Credentials are supplied by the host.
#[derive(Default)]
pub struct SearchEndpoint {
    pub base_url: String,
    pub bearer_token: Option<String>,
    pub http_headers: Option<HashMap<String, String>>,
}

impl std::fmt::Debug for SearchEndpoint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SearchEndpoint").finish_non_exhaustive()
    }
}

/// 只负责兼容 `/alpha/search` dialect 的 HTTP 客户端。
#[derive(Debug, Clone)]
pub struct WebSearchClient {
    client: reqwest::Client,
    endpoint: String,
    bearer_token: SecretString,
    headers: HeaderMap,
}

impl WebSearchClient {
    /// Builds the standalone `/alpha/search` client from a provider endpoint.
    pub fn new(provider: &SearchEndpoint) -> Result<Self> {
        Self::with_timeout(provider, WEB_SEARCH_REQUEST_TIMEOUT)
    }

    fn with_timeout(provider: &SearchEndpoint, timeout: Duration) -> Result<Self> {
        let token = provider
            .bearer_token
            .as_deref()
            .filter(|token| !token.trim().is_empty())
            .ok_or_else(|| {
                PureError::ConfigError(
                    "standalone web search requires a non-empty bearer token".to_string(),
                )
            })?;
        // Never follow redirects (credentialed requests must not be replayed to another host)
        // and never retry implicitly; a failed standalone search is reported to the caller.
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .build()
            .map_err(|error| {
                PureError::ConfigError(format!("failed to build web search client: {error}"))
            })?;
        Ok(Self {
            client,
            endpoint: format!("{}/alpha/search", provider.base_url.trim_end_matches('/')),
            bearer_token: SecretString::from(token.to_string()),
            headers: configured_headers(provider.http_headers.as_ref())?,
        })
    }

    pub(super) async fn search(
        &self,
        request: &SearchRequest,
    ) -> std::result::Result<Response, WebSearchError> {
        let response = self
            .client
            .post(&self.endpoint)
            .headers(self.headers.clone())
            .bearer_auth(self.bearer_token.expose_secret())
            .json(request)
            .send()
            .await
            .map_err(WebSearchError::Transport)?;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.map_err(WebSearchError::Response)?;
            let message = body.chars().take(1000).collect::<String>();
            return Err(WebSearchError::Status {
                status,
                body: message,
            });
        }
        response
            .json::<Response>()
            .await
            .map_err(WebSearchError::Response)
    }
}

fn configured_headers(headers: Option<&HashMap<String, String>>) -> Result<HeaderMap> {
    let mut result = HeaderMap::new();
    for (name, value) in headers.into_iter().flatten() {
        if name.eq_ignore_ascii_case("authorization") {
            continue;
        }
        let name = HeaderName::from_bytes(name.as_bytes()).map_err(|error| {
            PureError::ConfigError(format!("invalid provider header name `{name}`: {error}"))
        })?;
        let value = HeaderValue::from_str(value).map_err(|error| {
            PureError::ConfigError(format!(
                "invalid provider header value for `{name}`: {error}"
            ))
        })?;
        result.insert(name, value);
    }
    Ok(result)
}
