use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    BotConversationPage, BotConversationThreadReply, BotMessagePage, BotSendResult,
    BotsCommandReply, BotsStateSnapshot, CancelBotRegistrationRequest, ChangeBotThreadSyncReply,
    ChangeBotThreadSyncRequest, CreateBotConversationThreadRequest, HealthResponse,
    ListBotConversationsRequest, ReadBotMessagesRequest, ReadThreadAudienceItemsReply,
    ReadThreadAudienceItemsRequest, ReadThreadClosedAuthorizationsReply,
    ReadThreadClosedAuthorizationsRequest, ResolveInteractionRequest, SaveBotRequest,
    SendBotMessageRequest, SetBotEnabledRequest, SetBotTrustedChatRequest,
    SetBotTrustedUserRequest, StartBotRegistrationRequest, StudioError,
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

/// Public reply of one precise stop command (`POST /api/v1/threads/{id}/stop`).
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct StopThreadReply {
    pub thread_id: String,
    pub execution_id: String,
    /// The owner accepted the stop of exactly this execution; the execution still has
    /// to settle in its own stream before the stop is effective.
    pub stopped: bool,
    pub receipt: StopThreadReceipt,
}

/// The acknowledgement of a precise stop: accepted, but not yet effective.
#[derive(Debug, Clone, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct StopThreadReceipt {
    pub operation_id: String,
    pub disposition: String,
    pub targets: Vec<serde_json::Value>,
    pub effect: String,
    pub effective: bool,
    pub durable: bool,
    pub requires_identity_observation: bool,
}

/// Public prompt.submit acknowledgement (the response's canonical wire DTO).
#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct PromptReceipt {
    pub thread_id: String,
    pub input_id: String,
    pub cursor: u64,
}

/// Interrupt acknowledgement as the file-observation journeys read it.
///
/// Those journeys only assert the acknowledged Turn identity and the accepted
/// interrupt; the newer public reply with the Thread identity is
/// [`InterruptTurnReply`].
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct InterruptReply {
    pub turn_id: String,
    pub interrupted: bool,
}

/// One planned multipart part, streamed so a ceiling probe never buffers it.
#[derive(Clone)]
pub(crate) struct PatternUpload {
    pub filename: String,
    pub byte_len: u64,
    pub byte: u8,
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

    pub async fn create_thread(
        &self,
        project_id: &str,
        request: &pl_protocol::studio::CreateThreadRequest,
    ) -> Result<pl_studio_runtime::StudioStartNewThreadResponse> {
        let path = format!("/api/v1/projects/{project_id}/threads");
        let (status, body) = self
            .post_raw_with(&self.command_client, &path, request)
            .await?;
        decode_json(status, &body, &path)
    }

    pub async fn submit_prompt(
        &self,
        thread_id: &str,
        request: &pl_protocol::studio::SubmitPromptRequest,
    ) -> Result<PromptReceipt> {
        self.post_json(&format!("/api/v1/threads/{thread_id}/prompts"), request)
            .await
    }

    pub async fn set_thread_mode(
        &self,
        thread_id: &str,
        request: &pl_protocol::studio::SetThreadModeRequest,
    ) -> Result<pl_protocol::studio::ThreadModeCommandReply> {
        self.put_json(&format!("/api/v1/threads/{thread_id}/mode"), request)
            .await
    }

    pub async fn read_settings(&self) -> Result<pl_protocol::studio::SettingsStateResponse> {
        self.get_json("/api/v1/settings").await
    }

    pub async fn save_account(
        &self,
        request: &pl_protocol::studio::UpdateAccountRequest,
    ) -> Result<pl_protocol::studio::SettingsCommandReply> {
        self.put_json("/api/v1/settings/account", request).await
    }

    pub async fn update_settings_field(
        &self,
        request: &pl_protocol::studio::UpdateSettingsFieldRequest,
    ) -> Result<pl_protocol::studio::SettingsCommandReply> {
        self.put_json("/api/v1/settings/field", request).await
    }

    async fn put_json<T: DeserializeOwned, B: Serialize>(&self, path: &str, body: &B) -> Result<T> {
        let response = self
            .command_client
            .put(format!("{}{path}", self.base))
            .json(body)
            .send()
            .await
            .with_context(|| format!("PUT {path}"))?;
        let status = response.status();
        let text = response.text().await?;
        decode_json(status, &text, path)
    }

    pub async fn read_bots(&self) -> Result<BotsStateSnapshot> {
        self.get_json("/api/v1/bots").await
    }

    /// Canonical Thread snapshot (public projection, including the active Turn).
    pub async fn read_thread(&self, thread_id: &str) -> Result<pl_protocol::ThreadSnapshot> {
        self.get_json(&format!("/api/v1/threads/{thread_id}")).await
    }

    /// One page of the canonical Thread timeline (newest page by default).
    ///
    /// This is the same content source the GUI reads; previews carry per-field
    /// `total_bytes`, so a case can prove full local history without pulling a
    /// complete body into the report.
    pub async fn read_timeline(
        &self,
        thread_id: &str,
        limit: u32,
    ) -> Result<pl_protocol::TimelinePage> {
        self.get_json(&format!(
            "/api/v1/threads/{thread_id}/timeline?limit={limit}"
        ))
        .await
    }

    /// Thread snapshot under the name the file-observation journeys use.
    pub async fn thread(&self, thread_id: &str) -> Result<pl_protocol::ThreadSnapshot> {
        self.read_thread(thread_id).await
    }

    pub async fn timeline(&self, thread_id: &str) -> Result<Vec<pl_protocol::TimelineItem>> {
        let mut items = Vec::new();
        let mut before = None;
        for _ in 0..16 {
            let mut url = reqwest::Url::parse(&format!(
                "{}/api/v1/threads/{thread_id}/timeline",
                self.base
            ))?;
            url.query_pairs_mut().append_pair("limit", "100");
            if let Some(before) = before.as_deref() {
                url.query_pairs_mut().append_pair("before", before);
            }
            let path = format!("{}?{}", url.path(), url.query().unwrap_or_default());
            let page: pl_protocol::TimelinePage = self.get_json(&path).await?;
            ensure!(
                page.thread_id == thread_id,
                "timeline belongs to another Thread"
            );
            items.extend(page.items);
            if !page.has_older {
                return Ok(items);
            }
            let next = page.before.context("older timeline has no cursor")?;
            ensure!(
                before.as_ref() != Some(&next),
                "timeline cursor did not advance"
            );
            before = Some(next);
        }
        bail!("timeline exceeded the observer's 1600-item budget")
    }
    pub async fn attachment_bytes(&self, thread_id: &str, attachment_id: &str) -> Result<Vec<u8>> {
        let path = format!("/api/v1/threads/{thread_id}/attachments/{attachment_id}");
        let response = self
            .client
            .get(format!("{}{path}", self.base))
            .send()
            .await?;
        ensure!(
            response.status().is_success(),
            "reliable attachment {attachment_id}: {}",
            response.status()
        );
        let bytes = response.bytes().await?;
        ensure!(
            bytes.len() <= 50 * 1024 * 1024,
            "attachment response exceeded 50MiB"
        );
        Ok(bytes.to_vec())
    }

    /// Negative ownership oracle: transport/decode failures are not denials.
    pub async fn attachment_read_rejection(
        &self,
        thread_id: &str,
        resource_id: &str,
    ) -> Result<StudioError> {
        let response = self
            .client
            .get(format!(
                "{}/api/v1/threads/{thread_id}/attachments/{resource_id}",
                self.base
            ))
            .send()
            .await?;
        ensure!(
            !response.status().is_success(),
            "unowned or altered resource unexpectedly returned bytes"
        );
        response
            .json::<StudioError>()
            .await
            .context("attachment denial did not return a typed product error")
    }

    pub async fn upload_files(
        &self,
        context: &pl_protocol::studio::StudioAttachmentAdmissionContext,
        files: &[(String, Vec<u8>)],
    ) -> Result<pl_protocol::studio::AdmitAttachmentDraftsResponse> {
        let mut form =
            reqwest::multipart::Form::new().text("context", serde_json::to_string(context)?);
        for (name, bytes) in files {
            form = form.part(
                "file",
                reqwest::multipart::Part::bytes(bytes.clone()).file_name(name.clone()),
            );
        }
        let path = "/api/v1/attachments/drafts/upload";
        let response = self
            .command_client
            .post(format!("{}{path}", self.base))
            .multipart(form)
            .send()
            .await?;
        let status = response.status();
        let body = response.text().await?;
        decode_json(status, &body, path)
    }

    /// Streams real original bytes through the ordinary multipart endpoint.
    /// Large ceiling probes retain only one 64KiB producer chunk at a time.
    pub async fn upload_patterns_result(
        &self,
        context: &pl_protocol::studio::StudioAttachmentAdmissionContext,
        files: &[PatternUpload],
    ) -> Result<std::result::Result<pl_protocol::studio::AdmitAttachmentDraftsResponse, StudioError>>
    {
        let mut form =
            reqwest::multipart::Form::new().text("context", serde_json::to_string(context)?);
        for file in files {
            let byte = file.byte;
            let stream = futures::stream::unfold(file.byte_len, move |remaining| async move {
                if remaining == 0 {
                    return None;
                }
                let size = remaining.min(64 * 1024) as usize;
                Some((
                    Ok::<_, std::io::Error>(vec![byte; size]),
                    remaining - size as u64,
                ))
            });
            let body = reqwest::Body::wrap_stream(stream);
            form = form.part(
                "file",
                reqwest::multipart::Part::stream_with_length(body, file.byte_len)
                    .file_name(file.filename.clone()),
            );
        }
        let path = "/api/v1/attachments/drafts/upload";
        let response = self
            .command_client
            .post(format!("{}{path}", self.base))
            .multipart(form)
            .send()
            .await?;
        let status = response.status();
        let body = response.text().await?;
        if status.is_success() {
            Ok(Ok(
                serde_json::from_str(&body).context("invalid successful admission result")?
            ))
        } else {
            Ok(Err(serde_json::from_str(&body).with_context(|| {
                format!(
                    "untyped multipart rejection {status}: {}",
                    crate::env::redact(&body)
                )
            })?))
        }
    }

    pub async fn draft_bytes(&self, draft_id: &str) -> Result<Vec<u8>> {
        let response = self
            .command_client
            .get(format!(
                "{}/api/v1/attachments/drafts/{draft_id}",
                self.base
            ))
            .send()
            .await?;
        ensure!(
            response.status().is_success(),
            "draft GET {draft_id}: {}",
            response.status()
        );
        ensure!(
            response
                .content_length()
                .is_none_or(|size| size <= 50 * 1024 * 1024),
            "draft response exceeds original ceiling"
        );
        let bytes = response.bytes().await?;
        ensure!(
            bytes.len() <= 50 * 1024 * 1024,
            "draft response exceeds 50MiB"
        );
        Ok(bytes.to_vec())
    }

    pub async fn remove_draft(&self, draft_id: &str) -> Result<()> {
        let response = self
            .command_client
            .delete(format!(
                "{}/api/v1/attachments/drafts/{draft_id}",
                self.base
            ))
            .send()
            .await?;
        ensure!(
            response.status() == StatusCode::NO_CONTENT,
            "draft removal {draft_id}: {}",
            response.status()
        );
        Ok(())
    }
    pub async fn submit(
        &self,
        thread_id: &str,
        input: pl_protocol::studio::StudioPromptInput,
    ) -> Result<u64> {
        #[derive(serde::Deserialize)]
        #[serde(rename_all = "camelCase")]
        struct Receipt {
            thread_id: String,
            input_id: String,
            cursor: u64,
        }
        let input_id = input.input_id.clone();
        let snapshot = self.thread(thread_id).await?;
        let revision = snapshot
            .runtime
            .as_ref()
            .and_then(|runtime| runtime.model_route.as_ref())
            .context("Thread has no canonical model route")?
            .revision;
        let reply: Receipt = self
            .post_json(
                &format!("/api/v1/threads/{thread_id}/prompts"),
                &pl_protocol::studio::SubmitPromptRequest {
                    input,
                    expected_model_route_revision: revision,
                },
            )
            .await?;
        ensure!(
            reply.thread_id == thread_id && reply.input_id == input_id,
            "prompt admission returned another input's identity"
        );
        Ok(reply.cursor)
    }

    pub async fn interrupt(&self, thread_id: &str, turn_id: &str) -> Result<InterruptReply> {
        let path = format!("/api/v1/threads/{thread_id}/turns/{turn_id}");
        let response = self
            .command_client
            .delete(format!("{}{path}", self.base))
            .json(&pl_protocol::studio::StudioCommandRequest {
                operation_id: format!("observe-interrupt-{turn_id}"),
            })
            .send()
            .await?;
        let status = response.status();
        decode_json(status, &response.text().await?, &path)
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

    /// Explicit local audience command. The command client is used because a
    /// `PendingStart` answer is a real persisted receipt, not a parked call.
    pub async fn change_thread_sync(
        &self,
        request: &ChangeBotThreadSyncRequest,
    ) -> Result<std::result::Result<ChangeBotThreadSyncReply, StudioError>> {
        self.post_json_or_error_with("/api/v1/bots/threads/sync", request, &self.command_client)
            .await
    }

    /// Per-item canonical and delivery facts for one verified authorization.
    pub async fn read_thread_audience_items(
        &self,
        request: &ReadThreadAudienceItemsRequest,
    ) -> Result<std::result::Result<ReadThreadAudienceItemsReply, StudioError>> {
        self.post_json_or_error("/api/v1/bots/threads/audience-items", request)
            .await
    }

    /// Bounded closed-authorization history for one verified Thread.
    pub async fn read_thread_closed_authorizations(
        &self,
        request: &ReadThreadClosedAuthorizationsRequest,
    ) -> Result<std::result::Result<ReadThreadClosedAuthorizationsReply, StudioError>> {
        self.post_json_or_error("/api/v1/bots/threads/closed-authorizations", request)
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

    /// Public `POST /api/v1/threads/{thread_id}/stop`.
    ///
    /// The request names the execution the caller actually observed; a Turn id is
    /// never substituted for that identity. The reply is decoded by a local strict
    /// type, and acceptance asserts what this public route really acknowledged.
    pub async fn stop_thread(
        &self,
        thread_id: &str,
        execution_id: &str,
        operation_id: &str,
    ) -> Result<StopThreadReply> {
        let path = format!("/api/v1/threads/{thread_id}/stop");
        let response = self
            .command_client
            .post(format!("{}{path}", self.base))
            .json(&serde_json::json!({
                "operationId": operation_id,
                "expectedExecutionId": execution_id,
            }))
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        decode_json(status, &text, &path)
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
