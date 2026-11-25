use super::TENANT_TOKEN_PATH;
use super::classify::{
    classify_http_status, classify_oauth, json_protocol_error, require_open_http_success, transport,
};
pub(super) use super::classify::{parse_json, require_open_success};
use super::download::{LocalResourceFiles, ResourceFiles};
use super::endpoint::EndpointPolicy;
use super::error::{FeishuError, FeishuErrorKind};
use reqwest::{Client, Method, redirect::Policy as RedirectPolicy};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use url::Url;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Clone)]
pub struct FeishuHttp {
    client: Client,
    policy: EndpointPolicy,
    pub(super) resource_files: Arc<dyn ResourceFiles>,
}

#[derive(Debug, Deserialize)]
pub(super) struct OpenApiEnvelope<T> {
    pub(super) code: i64,
    #[serde(default)]
    pub(super) msg: Option<String>,
    pub(super) data: Option<T>,
}

#[derive(Debug)]
pub struct FormResponse<T> {
    pub status: reqwest::StatusCode,
    pub body: T,
}

impl FeishuHttp {
    pub fn new(policy: EndpointPolicy) -> Result<Self, FeishuError> {
        Self::with_transport(policy, REQUEST_TIMEOUT, Arc::new(LocalResourceFiles))
    }

    pub(in crate::bots) fn with_transport(
        policy: EndpointPolicy,
        timeout: Duration,
        resource_files: Arc<dyn ResourceFiles>,
    ) -> Result<Self, FeishuError> {
        let client = Client::builder()
            .connect_timeout(CONNECT_TIMEOUT)
            .timeout(timeout)
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
            resource_files,
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

    pub async fn post_form<T: DeserializeOwned>(
        &self,
        url: Url,
        form: &[(&str, &str)],
    ) -> Result<FormResponse<T>, FeishuError> {
        let response = self.post_form_raw(url, form).await?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(transport)?;
        if !(status.is_success() || status.as_u16() == 400) {
            return Err(classify_http_status(status));
        }
        let body = parse_json(&bytes, status)?;
        Ok(FormResponse { status, body })
    }

    async fn post_form_raw(
        &self,
        url: Url,
        form: &[(&str, &str)],
    ) -> Result<reqwest::Response, FeishuError> {
        let encoded = url::form_urlencoded::Serializer::new(String::new())
            .extend_pairs(form.iter().copied())
            .finish();
        self.client
            .request(Method::POST, url)
            .header("content-type", "application/x-www-form-urlencoded")
            .body(encoded)
            .send()
            .await
            .map_err(transport)
    }

    pub(super) async fn open_envelope<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        query: &[(&str, &str)],
        body: Option<&B>,
    ) -> Result<Option<T>, FeishuError> {
        let envelope: OpenApiEnvelope<T> =
            self.open_typed(method, path, token, query, body).await?;
        require_open_success(envelope.code, envelope.msg.as_deref())?;
        Ok(envelope.data)
    }

    pub(super) async fn open_unit<B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: &str,
        body: &B,
    ) -> Result<(), FeishuError> {
        self.open_envelope::<serde::de::IgnoredAny, B>(method, path, Some(token), &[], Some(body))
            .await?;
        Ok(())
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
        open_data(envelope)
    }

    pub async fn open_multipart<T: DeserializeOwned>(
        &self,
        path: &str,
        token: &str,
        form: reqwest::multipart::Form,
    ) -> Result<T, FeishuError> {
        let url = self
            .open_api()
            .join(path.trim_start_matches('/'))
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    format!("invalid upload path: {error}"),
                    false,
                    None,
                )
            })?;
        let response = self
            .client
            .post(url)
            .bearer_auth(token)
            .multipart(form)
            .send()
            .await
            .map_err(transport)?;
        let status = response.status();
        let bytes = response.bytes().await.map_err(transport)?;
        require_open_http_success(status, &bytes)?;
        open_data(parse_json(&bytes, status)?)
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
        require_open_http_success(status, &bytes)?;
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
            .accounts()
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
            .post_form_raw(
                url,
                &[
                    ("grant_type", "client_credentials"),
                    ("client_id", app_id),
                    ("client_secret", app_secret),
                ],
            )
            .await?;
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

fn open_data<T>(envelope: OpenApiEnvelope<T>) -> Result<T, FeishuError> {
    require_open_success(envelope.code, envelope.msg.as_deref())?;
    envelope.data.ok_or_else(|| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            "Feishu response missing data",
            false,
            Some(envelope.code.to_string()),
        )
    })
}
