use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotConversationPage, BotConversationThreadReply, BotMessagePage, BotSendResult,
    BotsCommandReply, BotsStateSnapshot, CancelBotRegistrationRequest,
    CreateBotConversationThreadRequest, HealthResponse, ListBotConversationsRequest,
    ReadBotMessagesRequest, ResolveInteractionRequest, SaveBotRequest, SendBotMessageRequest,
    SetBotEnabledRequest, SetBotTrustedChatRequest, SetBotTrustedUserRequest,
    StartBotRegistrationRequest, StudioError,
};
use pl_studio_runtime::ProjectRecord;
use pl_studio_runtime::StudioThreadDirectoryPage;
use reqwest::StatusCode;
use reqwest::redirect::Policy as RedirectPolicy;
use serde::Serialize;
use serde::de::DeserializeOwned;
use std::time::{Duration, Instant};

pub(crate) const PREDICATE_TIMEOUT: Duration = Duration::from_secs(45);
pub(crate) const POLL: Duration = Duration::from_millis(50);
pub(crate) const ACK_BUDGET: Duration = Duration::from_secs(3);
pub(crate) const SEND_UNKNOWN_TIMEOUT: Duration = Duration::from_secs(25);

#[derive(Clone)]
pub(crate) struct StudioHttp {
    client: reqwest::Client,
    send_client: reqwest::Client,
    command_client: reqwest::Client,
    base: String,
}

impl StudioHttp {
    pub fn new(listen: std::net::SocketAddr) -> Result<Self> {
        ensure!(
            listen.ip().is_loopback(),
            "observe HTTP must stay on loopback"
        );
        ensure!(
            listen.port() != 1420 && listen.port() != 1421,
            "observe HTTP must not use reserved ports 1420/1421"
        );
        Ok(Self {
            client: reqwest::Client::builder()
                .no_proxy()
                .redirect(RedirectPolicy::none())
                .connect_timeout(Duration::from_secs(2))
                .timeout(Duration::from_secs(10))
                .build()
                .context("failed to build observe HTTP client")?,
            send_client: reqwest::Client::builder()
                .no_proxy()
                .redirect(RedirectPolicy::none())
                .timeout(SEND_UNKNOWN_TIMEOUT)
                .build()
                .context("failed to build observe send HTTP client")?,
            command_client: reqwest::Client::builder()
                .no_proxy()
                .redirect(RedirectPolicy::none())
                .connect_timeout(Duration::from_secs(2))
                .timeout(PREDICATE_TIMEOUT)
                .build()
                .context("failed to build observe command HTTP client")?,
            base: format!("http://{listen}"),
        })
    }

    pub fn origin(&self) -> &str {
        &self.base
    }

    pub async fn wait_health(&self) -> Result<()> {
        wait_until(PREDICATE_TIMEOUT, || async {
            Ok(self.wait_health_once().await.is_ok())
        })
        .await
        .context("studio server did not become ready on /health")
    }

    pub async fn wait_health_once(&self) -> Result<()> {
        let health = self.get_json::<HealthResponse>("/health").await?;
        ensure!(health.status == "ok", "health status was {}", health.status);
        Ok(())
    }

    pub async fn open_project(&self, path: &str) -> Result<ProjectRecord> {
        self.post_json(
            "/api/v1/projects",
            &pl_protocol::studio::OpenProjectRequest {
                path: path.to_owned(),
            },
        )
        .await
    }

    pub async fn read_bots(&self) -> Result<BotsStateSnapshot> {
        self.get_json("/api/v1/bots").await
    }

    pub async fn list_threads_page(
        &self,
        cursor: Option<&str>,
        limit: u32,
    ) -> Result<StudioThreadDirectoryPage> {
        let mut url = reqwest::Url::parse(&format!("{}/api/v1/threads", self.base))
            .context("thread list URL")?;
        {
            let mut query = url.query_pairs_mut();
            query.append_pair("limit", &limit.to_string());
            if let Some(cursor) = cursor {
                query.append_pair("cursor", cursor);
            }
        }
        let path = format!(
            "{}{}",
            url.path(),
            url.query()
                .map(|query| format!("?{query}"))
                .unwrap_or_default()
        );
        self.get_json(&path).await
    }

    pub async fn start_registration_result(
        &self,
        request: &StartBotRegistrationRequest,
    ) -> Result<std::result::Result<BotsCommandReply, StudioError>> {
        self.post_json_or_error_with("/api/v1/bots/registration", request, &self.command_client)
            .await
    }

    pub async fn cancel_registration_result(
        &self,
        request: &CancelBotRegistrationRequest,
    ) -> Result<std::result::Result<BotsCommandReply, StudioError>> {
        self.post_json_or_error_with(
            "/api/v1/bots/registration/cancel",
            request,
            &self.command_client,
        )
        .await
    }

    pub async fn save_bot(&self, request: &SaveBotRequest) -> Result<BotsCommandReply> {
        self.post_json("/api/v1/bots", request).await
    }

    pub async fn save_bot_result(
        &self,
        request: &SaveBotRequest,
    ) -> Result<std::result::Result<BotsCommandReply, StudioError>> {
        self.post_json_or_error("/api/v1/bots", request).await
    }

    pub async fn set_enabled(&self, request: &SetBotEnabledRequest) -> Result<BotsCommandReply> {
        self.post_json("/api/v1/bots/enabled", request).await
    }

    pub async fn set_trusted_user(
        &self,
        request: &SetBotTrustedUserRequest,
    ) -> Result<BotsCommandReply> {
        self.post_json("/api/v1/bots/trusted-users", request).await
    }

    pub async fn set_trusted_chat(
        &self,
        request: &SetBotTrustedChatRequest,
    ) -> Result<BotsCommandReply> {
        self.post_json("/api/v1/bots/trusted-chats", request).await
    }

    pub async fn list_conversations(
        &self,
        request: &ListBotConversationsRequest,
    ) -> Result<BotConversationPage> {
        self.post_json("/api/v1/bots/conversations", request).await
    }

    pub async fn read_messages(&self, request: &ReadBotMessagesRequest) -> Result<BotMessagePage> {
        self.post_json("/api/v1/bots/messages", request).await
    }

    /// Explicit local conversation-Thread creation. Uses the command client
    /// so a parked network-preparation phase stays inside the shared bound.
    pub async fn create_conversation_thread(
        &self,
        request: &CreateBotConversationThreadRequest,
    ) -> Result<std::result::Result<BotConversationThreadReply, StudioError>> {
        self.post_json_or_error_with(
            "/api/v1/bots/conversations/thread",
            request,
            &self.command_client,
        )
        .await
    }

    pub async fn send_message(&self, request: &SendBotMessageRequest) -> Result<BotSendResult> {
        match self
            .post_json_or_error_with("/api/v1/bots/messages/send", request, &self.send_client)
            .await?
        {
            Ok(value) => Ok(value),
            Err(error) => bail!(
                "/api/v1/bots/messages/send: {} ({:?})",
                error.message,
                error.code
            ),
        }
    }

    pub async fn send_message_result(
        &self,
        request: &SendBotMessageRequest,
    ) -> Result<std::result::Result<BotSendResult, StudioError>> {
        self.post_json_or_error_with("/api/v1/bots/messages/send", request, &self.send_client)
            .await
    }

    /// Resolves one interaction over the public endpoint. The request body is
    /// fully typed by the frozen protocol; the reply projection is still owned
    /// by the in-flight reply rework, so only transport success plus the typed
    /// error channel is asserted here.
    pub async fn resolve_interaction(
        &self,
        interaction_id: &str,
        request: &ResolveInteractionRequest,
    ) -> Result<()> {
        let path = format!("/api/v1/interactions/{interaction_id}/resolution");
        let response = self
            .command_client
            .put(format!("{}{}", self.base, path))
            .json(request)
            .send()
            .await
            .with_context(|| format!("PUT {path}"))?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        if !status.is_success() {
            let error = serde_json::from_str::<StudioError>(&text).unwrap_or_else(|_| {
                StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Internal,
                    format!("{status}: {}", crate::env::redact(&text)),
                    false,
                )
            });
            bail!("{path}: {} ({:?})", error.message, error.code);
        }
        Ok(())
    }

    async fn get_json<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let (status, body) = self.get_raw(path).await?;
        decode_json(status, &body, path)
    }

    async fn post_json<T: DeserializeOwned, B: Serialize>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T> {
        match self.post_json_or_error(path, body).await? {
            Ok(value) => Ok(value),
            Err(error) => bail!("{}: {} ({:?})", path, error.message, error.code),
        }
    }

    async fn post_json_or_error<T: DeserializeOwned, B: Serialize>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<std::result::Result<T, StudioError>> {
        self.post_json_or_error_with(path, body, &self.client).await
    }

    async fn post_json_or_error_with<T: DeserializeOwned, B: Serialize>(
        &self,
        path: &str,
        body: &B,
        client: &reqwest::Client,
    ) -> Result<std::result::Result<T, StudioError>> {
        let (status, text) = self.post_raw_with(client, path, body).await?;
        if status.is_success() {
            let value = serde_json::from_str(&text).with_context(|| {
                format!("failed to decode {path}: {}", crate::env::redact(&text))
            })?;
            Ok(Ok(value))
        } else {
            let error = serde_json::from_str::<StudioError>(&text).unwrap_or_else(|_| {
                StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Internal,
                    format!("{status}: {}", crate::env::redact(&text)),
                    false,
                )
            });
            Ok(Err(error))
        }
    }

    async fn get_raw(&self, path: &str) -> Result<(StatusCode, String)> {
        let response = self
            .client
            .get(format!("{}{path}", self.base))
            .send()
            .await
            .with_context(|| format!("GET {path}"))?;
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        Ok((status, body))
    }

    async fn post_raw_with<B: Serialize>(
        &self,
        client: &reqwest::Client,
        path: &str,
        body: &B,
    ) -> Result<(StatusCode, String)> {
        let response = client
            .post(format!("{}{path}", self.base))
            .json(body)
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        Ok((status, text))
    }
}

fn decode_json<T: DeserializeOwned>(status: StatusCode, body: &str, path: &str) -> Result<T> {
    if !status.is_success() {
        let redacted = crate::env::redact(body);
        if let Ok(error) = serde_json::from_str::<StudioError>(body) {
            bail!("{path}: {} ({:?})", error.message, error.code);
        }
        bail!("{path} failed with {status}: {redacted}");
    }
    serde_json::from_str(body)
        .with_context(|| format!("failed to decode {path}: {}", crate::env::redact(body)))
}

pub(crate) async fn wait_until<F, Fut>(timeout: Duration, mut predicate: F) -> Result<()>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<bool>>,
{
    let deadline = Instant::now() + timeout;
    loop {
        let last = match predicate().await {
            Ok(true) => return Ok(()),
            Ok(false) => "predicate false".to_owned(),
            Err(error) => error.to_string(),
        };
        if Instant::now() >= deadline {
            bail!("timed out after {timeout:?}: {last}");
        }
        tokio::time::sleep(POLL).await;
    }
}

/// Bounded barrier used when a negative condition must remain true for a whole
/// ACK/idle window. This is not a success sleep: callers still assert the
/// condition after the window.
pub(crate) async fn hold_for(duration: Duration) {
    tokio::time::sleep(duration).await;
}
