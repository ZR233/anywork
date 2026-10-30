use super::TENANT_TOKEN_PATH;
use super::endpoint::EndpointPolicy;
use super::error::{FeishuError, FeishuErrorKind};
use reqwest::{Client, Method, redirect::Policy as RedirectPolicy};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio_util::sync::CancellationToken;
use url::Url;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

#[cfg(test)]
#[path = "resource_tests.rs"]
mod resource_tests;

#[derive(Clone)]
pub struct FeishuHttp {
    client: Client,
    policy: EndpointPolicy,
    #[cfg(test)]
    resource_control: std::sync::Arc<std::sync::Mutex<Option<resource_tests::ResourceControl>>>,
}

#[derive(Debug, Deserialize)]
struct OpenApiEnvelope<T> {
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
        Ok(Self {
            client,
            policy,
            #[cfg(test)]
            resource_control: Default::default(),
        })
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

    /// Streams a message-owned resource to an atomically published file. Credentials stay in
    /// the Authorization header; path segments cannot change the configured API origin.
    pub async fn download_message_resource(
        &self,
        token: &str,
        message_id: &str,
        key: &str,
        kind: &str,
        destination: &std::path::Path,
        cancel: &CancellationToken,
    ) -> Result<(), FeishuError> {
        use tokio::io::AsyncWriteExt;
        let mut url = self.open_api().clone();
        #[cfg(test)]
        let control = self.resource_control.lock().unwrap().clone();
        #[cfg(test)]
        if let Some(control) = &control {
            url = control.base_url.clone();
            if control.gate.destination == destination {
                let _ = control.gate.cancellation.set(cancel.clone());
            }
        }
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
        let request = self.client.get(url).bearer_auth(token).send();
        let mut response = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Err(resource_cancelled()),
            response = request => response.map_err(transport)?,
        };
        if !response.status().is_success() {
            return Err(classify_http_status(response.status()));
        }
        let limit = if kind == "image" {
            20 * 1024 * 1024
        } else {
            50 * 1024 * 1024
        };
        if response
            .content_length()
            .is_some_and(|length| length > limit)
        {
            return Err(resource_too_large());
        }
        let parent = destination
            .parent()
            .ok_or_else(|| resource_io("resource parent missing"))?
            .to_owned();
        if cancel.is_cancelled() {
            return Err(resource_cancelled());
        }
        // Once started, neither this setup nor publication may be dropped on
        // cancellation: spawn_blocking and Tokio fs work are not abortable I/O.
        #[cfg(test)]
        let setup_control = control.clone();
        #[cfg(test)]
        let setup_destination = destination.to_owned();
        let temporary = tokio::task::spawn_blocking(move || {
            std::fs::create_dir_all(&parent)?;
            #[cfg(test)]
            let _operation = setup_control.as_ref().and_then(|control| {
                control
                    .gate
                    .enter(resource_tests::FileStage::Setup, &setup_destination)
            });
            tempfile::NamedTempFile::new_in(parent)
        })
        .await
        .map_err(resource_io)?
        .map_err(resource_io)?;
        let mut file = tokio::fs::File::from_std(temporary.reopen().map_err(resource_io)?);
        let transferred = async {
            let mut total = 0u64;
            loop {
                // Network reads have no file operation to drain; cancellation
                // stops producing new writes, but never abandons an old write.
                let chunk = tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return Err(resource_cancelled()),
                    chunk = response.chunk() => chunk.map_err(transport)?,
                };
                let Some(bytes) = chunk else {
                    return Ok(());
                };
                total = total
                    .checked_add(bytes.len() as u64)
                    .ok_or_else(resource_too_large)?;
                if total > limit {
                    return Err(resource_too_large());
                }
                file.write_all(&bytes).await.map_err(resource_io)?;
            }
        }
        .await;
        // write_all may only have filled Tokio's buffer. Drain even on network,
        // limit, write-error and cancellation exits, before removing the temp.
        let flushed = file.flush().await.map_err(resource_io);
        let synced = if transferred.is_ok() && flushed.is_ok() && !cancel.is_cancelled() {
            file.sync_all().await.map_err(resource_io)
        } else {
            Ok(())
        };
        // into_std also waits for in-flight work if flush reported an error.
        drop(file.into_std().await);
        if let Err(error) = transferred {
            if let Err(flush_error) = flushed {
                tracing::warn!(%flush_error, "resource flush failed while draining a failed download");
            }
            return Err(error);
        }
        flushed?;
        synced?;
        if cancel.is_cancelled() {
            return Err(resource_cancelled());
        }
        let destination = destination.to_owned();
        tokio::task::spawn_blocking(move || {
            #[cfg(test)]
            let _operation = control.as_ref().and_then(|control| {
                control
                    .gate
                    .enter(resource_tests::FileStage::Persist, &destination)
            });
            temporary.persist(destination)
        })
        .await
        .map_err(resource_io)?
        .map_err(resource_io)?;
        if cancel.is_cancelled() {
            return Err(resource_cancelled());
        }
        Ok(())
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
        let accounts = self.policy.accounts.clone();
        #[cfg(test)]
        let accounts = self
            .resource_control
            .lock()
            .unwrap()
            .as_ref()
            .map_or(accounts, |control| control.base_url.clone());
        let url = accounts
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

fn resource_io(error: impl std::fmt::Display) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("message resource storage: {error}"),
        true,
        None,
    )
}

fn resource_cancelled() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "message resource download cancelled after draining file work",
        true,
        None,
    )
}

fn resource_too_large() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Rejected,
        "消息附件超过支持的大小（图片 20 MiB，文件 50 MiB）",
        false,
        None,
    )
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
