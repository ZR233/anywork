//! Codex account usage contract, matching openai/codex's backend-client.
//! Only the selected credential owner supplies the bearer token and workspace.

use super::{ChatGptAuthError, ChatGptSession};
use futures::StreamExt;
use serde::Deserialize;

#[derive(Debug, Clone, PartialEq)]
pub struct CodexUsage {
    pub plan_type: Option<String>,
    pub windows: Vec<CodexQuotaWindow>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CodexQuotaWindow {
    pub name: String,
    pub duration_seconds: u64,
    pub used_percent: f64,
    pub reset_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum CodexUsageError {
    #[error(transparent)]
    Authentication(#[from] ChatGptAuthError),
    #[error("Codex usage request failed")]
    Network,
    #[error("Codex usage returned HTTP {status}")]
    Http { status: u16 },
    #[error("Codex usage response is invalid or belongs to another account")]
    InvalidResponse,
    #[error("This ChatGPT registration does not provide Codex usage")]
    Unsupported,
}

#[derive(Deserialize)]
struct Payload {
    plan_type: Option<String>,
    account_id: Option<String>,
    rate_limit: Option<Limits>,
    additional_rate_limits: Option<Vec<AdditionalLimits>>,
}

#[derive(Deserialize)]
struct AdditionalLimits {
    limit_name: String,
    metered_feature: String,
    rate_limit: Option<Limits>,
}

#[derive(Deserialize)]
struct Limits {
    primary_window: Option<Window>,
    secondary_window: Option<Window>,
}

#[derive(Deserialize)]
struct Window {
    used_percent: f64,
    limit_window_seconds: u64,
    reset_at: Option<i64>,
}

fn decode(bytes: &[u8], account_id: &str) -> Result<CodexUsage, CodexUsageError> {
    let payload: Payload =
        serde_json::from_slice(bytes).map_err(|_| CodexUsageError::InvalidResponse)?;
    if payload
        .account_id
        .as_deref()
        .is_some_and(|id| id != account_id)
    {
        return Err(CodexUsageError::InvalidResponse);
    }
    let mut windows = Vec::new();
    let groups = std::iter::once(("Codex".to_owned(), payload.rate_limit)).chain(
        payload
            .additional_rate_limits
            .into_iter()
            .flatten()
            .map(|group| {
                (
                    if group.limit_name.is_empty() {
                        group.metered_feature
                    } else {
                        group.limit_name
                    },
                    group.rate_limit,
                )
            }),
    );
    for (name, limits) in groups {
        for window in limits
            .into_iter()
            .flat_map(|limits| [limits.primary_window, limits.secondary_window])
            .flatten()
        {
            if !window.used_percent.is_finite()
                || window.used_percent < 0.0
                || window.limit_window_seconds == 0
                || window.reset_at.is_some_and(|at| at <= 0)
            {
                return Err(CodexUsageError::InvalidResponse);
            }
            windows.push(CodexQuotaWindow {
                name: name.clone(),
                duration_seconds: window.limit_window_seconds,
                used_percent: window.used_percent,
                reset_at: window.reset_at,
            });
        }
    }
    Ok(CodexUsage {
        plan_type: payload.plan_type,
        windows,
    })
}

impl ChatGptSession {
    /// One explicit, cancellable read; it does not start sign-in or replay a failed request.
    pub async fn query_usage(&self) -> Result<CodexUsage, CodexUsageError> {
        self.query_usage_at("https://chatgpt.com/backend-api/wham/usage")
            .await
    }

    async fn query_usage_at(&self, endpoint: &str) -> Result<CodexUsage, CodexUsageError> {
        let account = self.codex_account().ok_or(CodexUsageError::Unsupported)?;
        let token = self.access_token().await?;
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .timeout(std::time::Duration::from_secs(30))
            .build()
            .map_err(|_| CodexUsageError::Network)?;
        let response = client
            .get(endpoint)
            .bearer_auth(token)
            .header("chatgpt-account-id", &account.account_id)
            .header("originator", "anywork")
            .header("user-agent", concat!("anywork/", env!("CARGO_PKG_VERSION")))
            .send()
            .await
            .map_err(|_| CodexUsageError::Network)?;
        if !response.status().is_success() {
            return Err(CodexUsageError::Http {
                status: response.status().as_u16(),
            });
        }
        const LIMIT: usize = 1024 * 1024;
        if response
            .content_length()
            .is_some_and(|length| length > LIMIT as u64)
        {
            return Err(CodexUsageError::InvalidResponse);
        }
        let mut bytes = Vec::new();
        let mut body = response.bytes_stream();
        while let Some(chunk) = body.next().await {
            let chunk = chunk.map_err(|_| CodexUsageError::Network)?;
            if chunk.len() > LIMIT - bytes.len() {
                return Err(CodexUsageError::InvalidResponse);
            }
            bytes.extend_from_slice(&chunk);
        }
        decode(&bytes, &account.account_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::chatgpt::{
        CHATGPT_ISSUER, CODEX_CLIENT_ID, ChatGptCredentialRecord, ChatGptCredentialStorage,
    };
    use pl_protocol::studio::{ChatGptAccountInfo, CodexAccountInfo};
    use serde_json::json;
    use std::sync::Arc;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[test]
    fn preserves_windows_and_rejects_foreign_or_invalid_usage() {
        let payload = json!({
            "account_id": "selected-workspace", "plan_type": "plus",
            "rate_limit": {
                "primary_window": {"used_percent": 23, "limit_window_seconds": 18000, "reset_at": 1800000000},
                "secondary_window": {"used_percent": 101, "limit_window_seconds": 604800, "reset_at": 1800600000}
            },
            "additional_rate_limits": [{
                "limit_name": "Review", "metered_feature": "review",
                "rate_limit": {"primary_window": {"used_percent": 5, "limit_window_seconds": 3600}}
            }]
        });
        let result = decode(&serde_json::to_vec(&payload).unwrap(), "selected-workspace").unwrap();
        assert_eq!(result.plan_type.as_deref(), Some("plus"));
        assert_eq!(
            result
                .windows
                .iter()
                .map(|window| (
                    window.name.as_str(),
                    window.duration_seconds,
                    window.used_percent,
                    window.reset_at
                ))
                .collect::<Vec<_>>(),
            [
                ("Codex", 18000, 23.0, Some(1800000000)),
                ("Codex", 604800, 101.0, Some(1800600000)),
                ("Review", 3600, 5.0, None),
            ]
        );
        assert_eq!(
            decode(&serde_json::to_vec(&payload).unwrap(), "other-workspace"),
            Err(CodexUsageError::InvalidResponse)
        );
        assert!(
            decode(
                br#"{"plan_type":"enterprise","rate_limit":null}"#,
                "selected-workspace"
            )
            .unwrap()
            .windows
            .is_empty()
        );
        for invalid in [
            json!({"used_percent": -1, "limit_window_seconds": 18000}),
            json!({"used_percent": 50, "limit_window_seconds": 0}),
            json!({"used_percent": 50, "limit_window_seconds": 18000, "reset_at": -1}),
            json!({"limit_window_seconds": 18000}),
        ] {
            assert_eq!(
                decode(
                    &serde_json::to_vec(&json!({"rate_limit":{"primary_window":invalid}})).unwrap(),
                    "selected-workspace"
                ),
                Err(CodexUsageError::InvalidResponse)
            );
        }
    }

    struct Storage(ChatGptCredentialRecord);
    impl ChatGptCredentialStorage for Storage {
        fn load(&self) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
            Ok(self.0.clone())
        }
        fn persist(&self, _: &str, _: &ChatGptCredentialRecord) -> Result<(), ChatGptAuthError> {
            panic!("An unexpired quota read must not refresh or replace credentials");
        }
    }

    #[tokio::test]
    async fn quota_http_uses_only_the_selected_credential_owner() {
        let home = tempfile::tempdir().unwrap();
        let record = ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: "local-generation".into(),
            account: ChatGptAccountInfo {
                issuer: CHATGPT_ISSUER.into(),
                subject: "subject".into(),
                client_id: CODEX_CLIENT_ID.into(),
                email: None,
                plan_usage_enabled: true,
                codex: Some(CodexAccountInfo {
                    account_id: "selected-workspace".into(),
                    plan_type: None,
                }),
            },
            ext_agent_host_id: "urn:uuid:test".into(),
            access_token: "selected-token".into(),
            refresh_token: "must-not-refresh".into(),
            id_token: "verified-id".into(),
            scopes: vec![],
            expires_at: super::super::now() + 3600,
            earliest_refresh_at: None,
            refresh_in_flight: false,
        };
        let session = ChatGptSession::new(
            &record,
            Arc::new(Storage(record.clone())),
            home.path().join("credential.lock"),
        )
        .unwrap();
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let endpoint = format!(
            "http://{}/backend-api/wham/usage",
            listener.local_addr().unwrap()
        );
        let server = async {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut bytes = Vec::new();
            loop {
                let byte = socket.read_u8().await.unwrap();
                bytes.push(byte);
                if bytes.ends_with(b"\r\n\r\n") {
                    break;
                }
            }
            let request = String::from_utf8(bytes).unwrap().to_ascii_lowercase();
            assert!(request.starts_with("get /backend-api/wham/usage http/1.1\r\n"));
            assert!(request.contains("authorization: bearer selected-token\r\n"));
            assert!(request.contains("chatgpt-account-id: selected-workspace\r\n"));
            assert!(request.contains("originator: anywork\r\n"));
            let body = r#"{"account_id":"selected-workspace","plan_type":"plus","rate_limit":{"primary_window":{"used_percent":23,"limit_window_seconds":18000}}}"#;
            socket
                .write_all(
                    format!(
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    )
                    .as_bytes(),
                )
                .await
                .unwrap();
        };
        let (result, ()) = tokio::join!(session.query_usage_at(&endpoint), server);
        let usage = result.unwrap();
        assert_eq!(usage.windows[0].used_percent, 23.0);
        session.revoke();
        assert_eq!(
            session.query_usage_at(&endpoint).await,
            Err(CodexUsageError::Authentication(ChatGptAuthError::Revoked))
        );
    }
}
