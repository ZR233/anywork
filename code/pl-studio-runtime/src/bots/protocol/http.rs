use super::TENANT_TOKEN_PATH;
use super::endpoint::EndpointPolicy;
use super::error::{FeishuError, FeishuErrorKind};
use reqwest::{Client, Method, redirect::Policy as RedirectPolicy};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use url::Url;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Clone)]
pub struct FeishuHttp {
    client: Client,
    policy: EndpointPolicy,
}

#[derive(Debug, Deserialize)]
struct OpenApiEnvelope<T> {
    #[serde(default)]
    code: i64,
    #[serde(default)]
    msg: Option<String>,
    data: Option<T>,
}

#[derive(Debug)]
pub struct FormResponse<T> {
    pub status: reqwest::StatusCode,
    pub body: T,
}

impl FeishuHttp {
    pub fn new(policy: EndpointPolicy) -> Result<Self, FeishuError> {
        let client = Client::builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .timeout(REQUEST_TIMEOUT)
            .redirect(RedirectPolicy::none())
            .build()
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Transport,
                    format!("failed to build Feishu HTTP client: {error}"),
                    true,
                    None,
                )
            })?;
        Ok(Self { client, policy })
    }

    pub fn client(&self) -> &Client {
        &self.client
    }

    pub fn open_api(&self) -> &Url {
        &self.policy.open_api
    }

    pub fn accounts(&self) -> &Url {
        &self.policy.accounts
    }

    pub fn policy(&self) -> &EndpointPolicy {
        &self.policy
    }

    pub async fn post_form<T: DeserializeOwned>(
        &self,
        url: Url,
        form: &[(&str, &str)],
    ) -> Result<FormResponse<T>, FeishuError> {
        let encoded = url::form_urlencoded::Serializer::new(String::new())
            .extend_pairs(form.iter().copied())
            .finish();
        let response = self
            .client
            .request(Method::POST, url)
            .header("content-type", "application/x-www-form-urlencoded")
            .body(encoded)
            .send()
            .await
            .map_err(transport)?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(transport)?;
        if !(status.is_success() || status.as_u16() == 400) {
            return Err(classify_http_status(status));
        }
        let body = parse_json(&bytes, status)?;
        Ok(FormResponse { status, body })
    }

    pub async fn open_json<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        query: &[(&str, &str)],
        body: Option<&B>,
    ) -> Result<T, FeishuError> {
        let envelope: OpenApiEnvelope<T> =
            self.open_typed(method, path, token, query, body).await?;
        if envelope.code != 0 {
            return Err(classify_open_api(envelope.code, envelope.msg.as_deref()));
        }
        envelope.data.ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "Feishu response missing data",
                false,
                Some(envelope.code.to_string()),
            )
        })
    }

    pub async fn open_typed<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        query: &[(&str, &str)],
        body: Option<&B>,
    ) -> Result<T, FeishuError> {
        let mut url = self
            .policy
            .open_api
            .join(path.trim_start_matches('/'))
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    format!("invalid Feishu path {path}: {error}"),
                    false,
                    None,
                )
            })?;
        if !query.is_empty() {
            url.query_pairs_mut().extend_pairs(query.iter().copied());
        }
        let mut request = self.client.request(method, url);
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request.json(body);
        }
        let response = request.send().await.map_err(transport)?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(transport)?;
        if !status.is_success() {
            return Err(classify_http_status(status));
        }
        parse_json(&bytes, status)
    }

    pub async fn tenant_access_token(
        &self,
        app_id: &str,
        app_secret: &str,
    ) -> Result<super::token::TenantAccessToken, FeishuError> {
        #[derive(Serialize)]
        struct RequestBody<'a> {
            app_id: &'a str,
            app_secret: &'a str,
        }
        #[derive(Deserialize)]
        struct ResponseBody {
            code: i64,
            #[serde(default)]
            msg: Option<String>,
            #[serde(default)]
            tenant_access_token: Option<String>,
            #[serde(default)]
            expire: Option<i64>,
        }
        let url = self
            .policy
            .open_api
            .join(TENANT_TOKEN_PATH.trim_start_matches('/'))
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    format!("invalid tenant token path: {error}"),
                    false,
                    None,
                )
            })?;
        let response = self
            .client
            .request(Method::POST, url)
            .json(&RequestBody { app_id, app_secret })
            .send()
            .await
            .map_err(transport)?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(transport)?;
        if !status.is_success() {
            return Err(classify_http_status(status));
        }
        let parsed: ResponseBody = parse_json(&bytes, status)?;
        if parsed.code != 0 {
            return Err(classify_open_api(parsed.code, parsed.msg.as_deref()));
        }
        let token = parsed.tenant_access_token.filter(|value| !value.is_empty());
        let expire = parsed.expire.filter(|value| *value > 0);
        match (token, expire) {
            (Some(token), Some(expire)) => Ok(super::token::TenantAccessToken { token, expire }),
            _ => Err(FeishuError::new(
                FeishuErrorKind::Auth,
                "tenant access token missing expire or value",
                true,
                Some(parsed.code.to_string()),
            )),
        }
    }
}

fn transport(error: reqwest::Error) -> FeishuError {
    let kind = if error.is_timeout() {
        FeishuErrorKind::Timeout
    } else {
        FeishuErrorKind::Transport
    };
    FeishuError::new(kind, "Feishu HTTP request failed", true, None)
}

pub(crate) fn classify_open_api(code: i64, msg: Option<&str>) -> FeishuError {
    let _ = msg;
    let (kind, retryable) = match code {
        99991663 | 99991664 | 1000040343 => (FeishuErrorKind::Auth, false),
        99991672 | 230002 | 232009 => (FeishuErrorKind::Permission, false),
        99991400 | 230001 => (FeishuErrorKind::Rejected, false),
        99991404 => (FeishuErrorKind::NotFound, false),
        1 | 99991429 => (FeishuErrorKind::Unavailable, true),
        _ => (FeishuErrorKind::Unavailable, code > 0 && code < 100),
    };
    let message = match kind {
        FeishuErrorKind::Auth => "Feishu authentication was rejected",
        FeishuErrorKind::Permission => "Feishu permission was denied",
        FeishuErrorKind::Rejected => "Feishu rejected the request",
        FeishuErrorKind::NotFound => "Feishu resource was not found",
        _ => "Feishu API rejected the request",
    };
    FeishuError::new(kind, message, retryable, Some(code.to_string()))
}

fn parse_json<T: DeserializeOwned>(
    bytes: &[u8],
    status: reqwest::StatusCode,
) -> Result<T, FeishuError> {
    serde_json::from_slice(bytes).map_err(|error| json_protocol_error(status, error))
}

fn json_protocol_error(status: reqwest::StatusCode, error: serde_json::Error) -> FeishuError {
    let line = error.line();
    let column = error.column();
    let category = match error.classify() {
        serde_json::error::Category::Io => "io",
        serde_json::error::Category::Syntax => "syntax",
        serde_json::error::Category::Data => "data",
        serde_json::error::Category::Eof => "eof",
    };
    FeishuError::new(
        FeishuErrorKind::Protocol,
        format!("invalid Feishu JSON ({category} at {line}:{column})"),
        status.is_server_error(),
        None,
    )
}

fn classify_http_status(status: reqwest::StatusCode) -> FeishuError {
    let code = status.as_u16();
    let (kind, retryable, message) = match code {
        401 => (
            FeishuErrorKind::Auth,
            false,
            "Feishu HTTP authentication was rejected",
        ),
        403 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu HTTP permission was denied",
        ),
        404 => (
            FeishuErrorKind::NotFound,
            false,
            "Feishu HTTP resource was not found",
        ),
        429 => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu HTTP rate limit was reached",
        ),
        400..=499 => (
            FeishuErrorKind::Rejected,
            false,
            "Feishu HTTP request was rejected",
        ),
        500..=599 => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu HTTP service is unavailable",
        ),
        _ => (
            FeishuErrorKind::Unavailable,
            false,
            "Feishu HTTP request failed",
        ),
    };
    FeishuError::new(kind, message, retryable, Some(code.to_string()))
}
