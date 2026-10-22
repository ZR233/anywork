use super::REGISTRATION_PATH;
use super::addons::encode_registration_addons;
use super::error::{FeishuError, FeishuErrorKind};
use super::http::{FeishuHttp, FormResponse};
use serde::Deserialize;
use url::Url;

pub struct RegistrationClient {
    http: FeishuHttp,
}

pub struct BeginRegistration {
    pub device_code: String,
    pub verification_url: String,
    pub interval_seconds: u32,
    pub expires_in: u32,
}

impl std::fmt::Debug for BeginRegistration {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BeginRegistration")
            .field("device_code", &"<redacted>")
            .field("verification_url", &"<redacted>")
            .field("interval_seconds", &self.interval_seconds)
            .field("expires_in", &self.expires_in)
            .finish()
    }
}

#[derive(Clone)]
pub enum PollRegistrationOutcome {
    Pending,
    SlowDown,
    Completed(PollRegistration),
    Denied { message: String },
    Expired,
    Failed { code: String, message: String },
}

impl std::fmt::Debug for PollRegistrationOutcome {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Pending => formatter.write_str("Pending"),
            Self::SlowDown => formatter.write_str("SlowDown"),
            Self::Completed(result) => formatter.debug_tuple("Completed").field(result).finish(),
            Self::Denied { message } => formatter
                .debug_struct("Denied")
                .field("message", message)
                .finish(),
            Self::Expired => formatter.write_str("Expired"),
            Self::Failed { code, message } => formatter
                .debug_struct("Failed")
                .field("code", code)
                .field("message", message)
                .finish(),
        }
    }
}

#[derive(Clone)]
pub struct PollRegistration {
    pub client_id: String,
    pub client_secret: String,
    pub open_id: Option<String>,
}

impl std::fmt::Debug for PollRegistration {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PollRegistration")
            .field("client_id", &self.client_id)
            .field("client_secret", &"<redacted>")
            .field("open_id", &self.open_id)
            .finish()
    }
}

#[derive(Debug, Deserialize)]
struct BeginResponse {
    device_code: Option<String>,
    verification_uri_complete: Option<String>,
    interval: Option<u32>,
    expires_in: Option<u32>,
    error: Option<String>,
    #[serde(default, rename = "error_description")]
    _error_description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct PollResponse {
    client_id: Option<String>,
    client_secret: Option<String>,
    user_info: Option<UserInfo>,
    error: Option<String>,
    #[serde(default, rename = "error_description")]
    _error_description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UserInfo {
    open_id: Option<String>,
    tenant_brand: Option<String>,
}

impl RegistrationClient {
    pub fn new(http: FeishuHttp) -> Self {
        Self { http }
    }

    pub async fn begin(&self, source: &str) -> Result<BeginRegistration, FeishuError> {
        let url = registration_url(&self.http)?;
        let FormResponse {
            status,
            body: response,
        }: FormResponse<BeginResponse> = self
            .http
            .post_form(
                url,
                &[
                    ("action", "begin"),
                    ("archetype", "PersonalAgent"),
                    ("auth_method", "client_secret"),
                    ("request_user_info", "open_id"),
                ],
            )
            .await?;
        if let Some(error) = response.error {
            return Err(begin_http_error(status, Some(&error)));
        }
        if !status.is_success() {
            return Err(begin_http_error(status, None));
        }
        let device_code = response
            .device_code
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "registration begin missing device_code",
                    true,
                    None,
                )
            })?;
        let verification = response
            .verification_uri_complete
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "registration begin missing verification url",
                    true,
                    None,
                )
            })?;
        let mut qr = self
            .http
            .policy()
            .validate_verification_url(&verification)?;
        qr.query_pairs_mut()
            .append_pair("from", "sdk")
            .append_pair("source", source)
            .append_pair("tp", "sdk")
            .append_pair("createOnly", "true")
            .append_pair("addons", &encode_registration_addons()?);
        Ok(BeginRegistration {
            device_code,
            verification_url: qr.to_string(),
            interval_seconds: response.interval.unwrap_or(5).max(1),
            expires_in: response.expires_in.unwrap_or(600).max(1),
        })
    }

    pub async fn poll(&self, device_code: &str) -> Result<PollRegistrationOutcome, FeishuError> {
        let url = registration_url(&self.http)?;
        let FormResponse {
            status,
            body: response,
        }: FormResponse<PollResponse> = self
            .http
            .post_form(url, &[("action", "poll"), ("device_code", device_code)])
            .await?;
        let status_code = status.as_u16();
        if let Some(outcome) = poll_business_outcome(status_code, response.error.as_deref()) {
            return Ok(outcome);
        }
        if (200..300).contains(&status_code) {
            reject_lark_tenant(response.user_info.as_ref())?;
            let client_id = response.client_id.filter(|value| !value.is_empty());
            let client_secret = response.client_secret.filter(|value| !value.is_empty());
            return match (client_id, client_secret) {
                (Some(client_id), Some(client_secret)) => {
                    Ok(PollRegistrationOutcome::Completed(PollRegistration {
                        client_id,
                        client_secret,
                        open_id: response
                            .user_info
                            .and_then(|info| info.open_id)
                            .filter(|value| !value.is_empty()),
                    }))
                }
                _ => Err(FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "registration poll missing credentials",
                    false,
                    None,
                )),
            };
        }
        if status_code == 400 {
            return Ok(PollRegistrationOutcome::Failed {
                code: "unknown".to_string(),
                message: "registration failed".to_string(),
            });
        }
        Err(FeishuError::new(
            FeishuErrorKind::Unavailable,
            "registration poll HTTP request failed",
            matches!(status_code, 429 | 500..=599),
            Some(status_code.to_string()),
        ))
    }
}

fn poll_business_outcome(status: u16, error: Option<&str>) -> Option<PollRegistrationOutcome> {
    if !(status == 400 || (200..300).contains(&status)) {
        return None;
    }
    match error {
        Some("authorization_pending") => Some(PollRegistrationOutcome::Pending),
        Some("slow_down") => Some(PollRegistrationOutcome::SlowDown),
        Some("access_denied") => Some(PollRegistrationOutcome::Denied {
            message: "registration denied".to_string(),
        }),
        Some("expired_token") => Some(PollRegistrationOutcome::Expired),
        Some(_) if status == 400 => Some(PollRegistrationOutcome::Failed {
            code: "unknown".to_string(),
            message: "registration failed".to_string(),
        }),
        _ => None,
    }
}

fn reject_lark_tenant(user_info: Option<&UserInfo>) -> Result<(), FeishuError> {
    match user_info.and_then(|info| info.tenant_brand.as_deref()) {
        None => Ok(()),
        Some(brand) if brand.eq_ignore_ascii_case("feishu") => Ok(()),
        Some(brand) if brand.eq_ignore_ascii_case("lark") => Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "Lark international tenants are not supported",
            false,
            None,
        )),
        Some(_) => Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "registration tenant brand is not supported",
            false,
            None,
        )),
    }
}

fn registration_url(http: &FeishuHttp) -> Result<Url, FeishuError> {
    http.accounts()
        .join(REGISTRATION_PATH.trim_start_matches('/'))
        .map_err(|_| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "invalid registration url",
                false,
                None,
            )
        })
}

fn begin_http_error(status: reqwest::StatusCode, error: Option<&str>) -> FeishuError {
    let code = match (status.as_u16(), error) {
        (400, Some("authorization_pending")) => "authorization_pending",
        (400, Some("slow_down")) => "slow_down",
        (400, Some("access_denied")) => "access_denied",
        (400, Some("expired_token")) => "expired_token",
        (_, Some(_)) => "unknown",
        (status, None) => return classify_begin_status(status),
    };
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "registration begin failed",
        matches!(status.as_u16(), 429 | 500..=599),
        Some(code.to_string()),
    )
}

fn classify_begin_status(status: u16) -> FeishuError {
    let (kind, retryable, message) = match status {
        401 => (
            FeishuErrorKind::Auth,
            false,
            "registration HTTP authentication was rejected",
        ),
        403 => (
            FeishuErrorKind::Permission,
            false,
            "registration HTTP permission was denied",
        ),
        429 => (
            FeishuErrorKind::Unavailable,
            true,
            "registration HTTP rate limit was reached",
        ),
        400..=499 => (
            FeishuErrorKind::Rejected,
            false,
            "registration HTTP request was rejected",
        ),
        500..=599 => (
            FeishuErrorKind::Unavailable,
            true,
            "registration HTTP service is unavailable",
        ),
        _ => (
            FeishuErrorKind::Unavailable,
            false,
            "registration HTTP request failed",
        ),
    };
    FeishuError::new(kind, message, retryable, Some(status.to_string()))
}
