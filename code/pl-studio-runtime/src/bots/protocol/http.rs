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
    code: i64,
    #[serde(default)]
    msg: Option<String>,
    data: Option<T>,
}

/// Fully built request: all local serialization, MIME and input checks precede stage admission.
pub struct PreparedPost(reqwest::Request);

/// Only the HTTP boundary can distinguish an explicit rejection from a lost/unreadable response.
pub enum PostFailure {
    Rejected(FeishuError),
    Unknown(FeishuError),
}

impl PostFailure {
    fn map_error(self, map: impl FnOnce(FeishuError) -> FeishuError) -> Self {
        match self {
            Self::Rejected(error) => Self::Rejected(map(error)),
            Self::Unknown(error) => Self::Unknown(map(error)),
        }
    }
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

    /// Reads a message-owned original under the caller's remaining batch budget. The resource
    /// identity is bound to one message; no sender-provided URL is followed.
    pub async fn download_message_resource(
        &self,
        token: &str,
        message_id: &str,
        key: &str,
        kind: &str,
        remaining_bytes: u64,
    ) -> Result<Vec<u8>, FeishuError> {
        if !matches!(kind, "image" | "file") {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "unsupported message resource type",
                false,
                None,
            ));
        }
        let mut url = self.open_api().clone();
        url.path_segments_mut()
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "invalid resource API base",
                    false,
                    None,
                )
            })?
            .pop_if_empty()
            .extend([
                "open-apis",
                "im",
                "v1",
                "messages",
                message_id,
                "resources",
                key,
            ]);
        url.query_pairs_mut().append_pair("type", kind);
        let mut response = self
            .client
            .get(url)
            .bearer_auth(token)
            .send()
            .await
            .map_err(transport)?;
        if !response.status().is_success() {
            let status = response.status();
            // Error bodies are not user resources. Their budget/transfer failure cannot hide a
            // known 429/5xx (or a definite HTTP rejection) behind a local attachment-limit error.
            return Err(match bounded_response(&mut response, 64 * 1024).await {
                Ok(bytes) => open_api_failure(status, &bytes),
                Err(_) => classify_http_status(status),
            });
        }
        let limit = remaining_bytes.min(pl_protocol::studio::ATTACHMENT_MAX_FILE_BYTES);
        let declared = response.content_length();
        if declared.is_some_and(|length| length > limit) {
            return Err(resource_too_large());
        }
        let bytes = bounded_response(
            &mut response,
            usize::try_from(limit).map_err(|_| resource_too_large())?,
        )
        .await?;
        if declared.is_some_and(|length| length != bytes.len() as u64) {
            return Err(FeishuError::new(
                FeishuErrorKind::Transport,
                "message resource transfer was incomplete",
                true,
                None,
            ));
        }
        Ok(bytes)
    }

    pub fn prepare_file_upload(
        &self,
        token: &str,
        filename: &str,
        mime: &str,
        bytes: std::sync::Arc<[u8]>,
    ) -> Result<PreparedPost, FeishuError> {
        use reqwest::multipart::{Form, Part};
        if bytes.is_empty() || bytes.len() > super::FILE_UPLOAD_LIMIT_BYTES {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "file upload requires 1..=30,000,000 bytes",
                false,
                None,
            ));
        }
        // The caller reserves the retained read plus this multipart-owned copy. reqwest owns
        // framing/streaming; there is no hand-written multipart codec or temporary upload file.
        let file = Part::bytes(bytes.to_vec())
            .file_name(filename.to_owned())
            .mime_str(mime)
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "invalid upload media type",
                    false,
                    None,
                )
            })?;
        let form = Form::new()
            .text("file_type", "stream")
            .text("file_name", filename.to_owned())
            .part("file", file);
        let url = self
            .open_api()
            .join(super::IM_FILES_PATH.trim_start_matches('/'))
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "invalid file API path",
                    false,
                    None,
                )
            })?;
        self.client
            .post(url)
            .bearer_auth(token)
            .multipart(form)
            .build()
            .map(PreparedPost)
            .map_err(transport)
    }

    pub fn prepare_json_post<B: Serialize>(
        &self,
        path: &str,
        token: &str,
        query: &[(&str, &str)],
        body: &B,
    ) -> Result<PreparedPost, FeishuError> {
        let mut url = self
            .open_api()
            .join(path.trim_start_matches('/'))
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "invalid message API path",
                    false,
                    None,
                )
            })?;
        url.query_pairs_mut().extend_pairs(query.iter().copied());
        self.client
            .post(url)
            .bearer_auth(token)
            .json(body)
            .build()
            .map(PreparedPost)
            .map_err(transport)
    }

    pub async fn upload_file(&self, prepared: PreparedPost) -> Result<String, PostFailure> {
        #[derive(Deserialize)]
        struct UploadedFile {
            file_key: String,
        }
        let file: UploadedFile = self
            .execute_post(prepared)
            .await
            .map_err(|error| error.map_error(upload_permission))?;
        if file.file_key.is_empty() {
            return Err(PostFailure::Unknown(FeishuError::new(
                FeishuErrorKind::Protocol,
                "file upload response missing file_key",
                false,
                None,
            )));
        }
        Ok(file.file_key)
    }

    pub async fn execute_post<T: DeserializeOwned>(
        &self,
        prepared: PreparedPost,
    ) -> Result<T, PostFailure> {
        let mut response = self
            .client
            .execute(prepared.0)
            .await
            .map_err(|error| PostFailure::Unknown(transport(error)))?;
        let status = response.status();
        // A local response budget after POST cannot establish that the remote side rejected it.
        let bytes = bounded_response(&mut response, 64 * 1024)
            .await
            .map_err(|error| {
                PostFailure::Unknown(if error.kind() == FeishuErrorKind::Rejected {
                    FeishuError::new(
                        FeishuErrorKind::Protocol,
                        "Feishu POST response exceeds the local body budget; result is unconfirmed",
                        false,
                        None,
                    )
                } else {
                    error
                })
            })?;
        if !status.is_success() {
            #[derive(Deserialize)]
            struct Failure {
                code: i64,
            }
            if let Ok(failure) = serde_json::from_slice::<Failure>(&bytes)
                && failure.code != 0
            {
                return Err(PostFailure::Rejected(classify_open_api(failure.code, None)));
            }
            let error = classify_http_status(status);
            return Err(if status.is_client_error() {
                PostFailure::Rejected(error)
            } else {
                PostFailure::Unknown(error)
            });
        }
        let envelope: OpenApiEnvelope<T> =
            parse_json(&bytes, status).map_err(PostFailure::Unknown)?;
        if envelope.code != 0 {
            return Err(PostFailure::Rejected(classify_open_api(
                envelope.code,
                None,
            )));
        }
        envelope.data.ok_or_else(|| {
            PostFailure::Unknown(FeishuError::new(
                FeishuErrorKind::Protocol,
                "Feishu POST response missing data; result is unconfirmed",
                false,
                None,
            ))
        })
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
            #[derive(Deserialize)]
            struct Failure {
                code: i64,
            }
            if let Ok(failure) = serde_json::from_slice::<Failure>(&bytes)
                && failure.code != 0
            {
                return Err(classify_open_api(failure.code, None));
            }
            return Err(classify_http_status(status));
        }
        parse_json(&bytes, status)
    }

    pub async fn tenant_access_token(
        &self,
        app_id: &str,
        app_secret: &str,
    ) -> Result<super::token::TenantAccessToken, FeishuError> {
        #[derive(Deserialize)]
        struct ResponseBody {
            code: i64,
            #[serde(default)]
            access_token: Option<String>,
            #[serde(default)]
            expires_in: Option<i64>,
            #[serde(default)]
            token_type: Option<String>,
        }
        let url = self
            .policy
            .accounts
            .join(TENANT_TOKEN_PATH.trim_start_matches('/'))
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    format!("invalid tenant token path: {error}"),
                    false,
                    None,
                )
            })?;
        let encoded = url::form_urlencoded::Serializer::new(String::new())
            .extend_pairs([
                ("grant_type", "client_credentials"),
                ("client_id", app_id),
                ("client_secret", app_secret),
            ])
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
        // OAuth business failures use HTTP 400/500. Decode before classifying so
        // the platform code survives; never expose error_description or secrets.
        let parsed: ResponseBody = match serde_json::from_slice(&bytes) {
            Ok(parsed) => parsed,
            Err(error) if status.is_success() => return Err(json_protocol_error(status, error)),
            Err(_) => return Err(classify_http_status(status)),
        };
        if parsed.code != 0 {
            return Err(classify_oauth(parsed.code, status));
        }
        if !status.is_success() {
            return Err(classify_http_status(status));
        }
        let token = parsed.access_token.filter(|value| !value.is_empty());
        let expires_in = parsed.expires_in.filter(|value| *value > 0);
        let bearer = parsed
            .token_type
            .is_some_and(|value| value.eq_ignore_ascii_case("Bearer"));
        match (token, expires_in, bearer) {
            (Some(token), Some(expires_in), true) => {
                Ok(super::token::TenantAccessToken { token, expires_in })
            }
            _ => Err(FeishuError::new(
                FeishuErrorKind::Protocol,
                "invalid Feishu OAuth token response",
                false,
                Some(parsed.code.to_string()),
            )),
        }
    }
}

fn classify_oauth(code: i64, status: reqwest::StatusCode) -> FeishuError {
    let (kind, retryable, message) = match code {
        20002 | 20048 | 20130 | 20140 => (
            FeishuErrorKind::Auth,
            false,
            "Feishu application authentication was rejected",
        ),
        20009 | 20069 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu application is not installed or enabled",
        ),
        20068 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu application scopes were denied",
        ),
        20001 | 20036 | 20063 | 20067 | 20070 => (
            FeishuErrorKind::Rejected,
            false,
            "Feishu OAuth request parameters were rejected",
        ),
        20050 => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu OAuth service is unavailable",
        ),
        21001 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu OAuth access control policy denied the token request",
        ),
        _ if status.is_server_error() || status == reqwest::StatusCode::TOO_MANY_REQUESTS => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu OAuth service is unavailable",
        ),
        _ => return classify_open_api(code, None),
    };
    FeishuError::new(kind, message, retryable, Some(code.to_string()))
}

fn resource_too_large() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Rejected,
        "消息资源超过单文件或批次字节预算",
        false,
        None,
    )
}

async fn bounded_response(
    response: &mut reqwest::Response,
    limit: usize,
) -> Result<Vec<u8>, FeishuError> {
    let mut result = Vec::new();
    while let Some(chunk) = response.chunk().await.map_err(transport)? {
        if result
            .len()
            .checked_add(chunk.len())
            .is_none_or(|len| len > limit)
        {
            return Err(resource_too_large());
        }
        result.extend_from_slice(&chunk);
    }
    Ok(result)
}

fn open_api_failure(status: reqwest::StatusCode, bytes: &[u8]) -> FeishuError {
    #[derive(Deserialize)]
    struct Failure {
        code: i64,
    }
    if let Ok(failure) = serde_json::from_slice::<Failure>(bytes)
        && failure.code != 0
    {
        return classify_open_api(failure.code, None);
    }
    classify_http_status(status)
}

fn upload_permission(error: FeishuError) -> FeishuError {
    if error.kind() == FeishuErrorKind::Permission {
        FeishuError::new(
            error.kind(),
            "飞书文件上传被拒绝；请应用管理员开通应用身份 im:resource:upload 权限，完成审批并发布应用；不会切换用户身份",
            false,
            error.platform_code().map(str::to_owned),
        )
    } else {
        error
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
        21001 | 99991672 | 230002 | 230006 | 230013 | 230018 | 230027 | 230035 | 230038
        | 230053 | 230073 => (FeishuErrorKind::Permission, false),
        99991400 | 230001 => (FeishuErrorKind::Rejected, false),
        99991404 | 230019 | 230110 | 232009 => (FeishuErrorKind::NotFound, false),
        200740 | 200750 => (FeishuErrorKind::NotFound, false),
        200770 | 300317 => (FeishuErrorKind::Conflict, false),
        200810 | 200850 | 200860 | 300302 | 300309 | 300310 => (FeishuErrorKind::Rejected, false),
        300311 => (FeishuErrorKind::Permission, false),
        1 | 99991429 | 230020 => (FeishuErrorKind::Unavailable, true),
        _ => (FeishuErrorKind::Unavailable, code > 0 && code < 100),
    };
    let message = match (code, kind) {
        (21001, _) => "Feishu access control policy denied the request",
        (230002, _) => "Feishu bot is not a member of this chat",
        (230006, _) => "Feishu application bot capability is not enabled",
        (230013, _) => "Feishu bot is not available to this user",
        (230053, _) => "Feishu user has stopped receiving bot messages",
        (200740, _) => "CardKit card does not exist",
        (200750, _) => "CardKit card has expired; replacement is not automatic",
        (200770, _) => "CardKit operation UUID conflicts with an earlier operation",
        (200810, _) => "CardKit rejected the card interaction configuration",
        (200850, _) => "CardKit streaming timed out (200850)",
        (200860, _) => "CardKit card exceeds the platform size bound",
        (300302, _) => "CardKit card requires update_multi=true",
        (300309, _) => "CardKit streaming is closed (300309)",
        (300310, _) => "CardKit target element is not a Markdown text element",
        (300311, _) => "CardKit permission denied; administrator must grant cardkit:card:write",
        (300317, _) => "CardKit sequence was rejected",
        (_, FeishuErrorKind::Auth) => "Feishu authentication was rejected",
        (_, FeishuErrorKind::Permission) => "Feishu permission was denied",
        (_, FeishuErrorKind::Rejected) => "Feishu rejected the request",
        (_, FeishuErrorKind::NotFound) => "Feishu resource was not found",
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
