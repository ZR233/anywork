use anyhow::{Context, Result, bail, ensure};
use eventsource_stream::{Event, EventStreamError, Eventsource};
use futures::{StreamExt, stream::BoxStream};
use pl_studio_runtime::StudioThreadDirectoryPage;
use pl_studio_runtime::WorkspaceRecord;
use pl_studio_runtime::history::{
    HISTORY_PROTOCOL_VERSION, HistoryBodyWindow, HistoryBusinessPage, HistoryCut, HistoryDemand,
    HistoryEventBodyRef, HistoryEventRecord, HistoryEventsPage, HistoryEventsQuery,
    HistoryTimelinePage, HistoryWorkRangePage,
};
use pl_studio_runtime::{
    BotConversationPage, BotConversationThreadReply, BotMessagePage, BotSendResult,
    BotsCommandReply, BotsStateSnapshot, CancelBotRegistrationRequest,
    CreateBotConversationThreadRequest, HealthResponse, ListBotConversationsRequest,
    ReadBotMessagesRequest, ResolveInteractionRequest, SaveBotRequest, SendBotMessageRequest,
    SetBotEnabledRequest, SetBotTrustedChatRequest, SetBotTrustedUserRequest,
    StartBotRegistrationRequest, StudioError,
};
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ContentRange, ContentWindow, CurrentCollectionPage,
    CurrentCollectionRef, CurrentContentRef, CurrentFrame, CurrentRevision, CurrentView,
    ReadDemand,
};
use reqwest::StatusCode;
use reqwest::redirect::Policy as RedirectPolicy;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};

pub(crate) const PREDICATE_TIMEOUT: Duration = Duration::from_secs(45);
pub(crate) const POLL: Duration = Duration::from_millis(50);
pub(crate) const ACK_BUDGET: Duration = Duration::from_secs(3);
pub(crate) const SEND_UNKNOWN_TIMEOUT: Duration = Duration::from_secs(25);
const CONVERSATION_HEADER: &str = "x-anywork-conversation";

#[derive(Clone)]
pub(crate) struct StudioHttp {
    client: reqwest::Client,
    send_client: reqwest::Client,
    command_client: reqwest::Client,
    base: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OpenHistoryResponse {
    history_protocol_version: u32,
    reader_id: String,
}

/// One immutable-history read scope. Every page/body request carries the original reader capability.
#[derive(Clone)]
pub(crate) struct HistoryRead {
    http: StudioHttp,
    thread_id: String,
    capability: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct OpenCurrentResponse {
    current_protocol_version: u32,
    current_owner_id: String,
    reader_id: String,
}

/// One live-current read scope. It is independent of immutable history and does not replay it.
#[derive(Clone)]
pub(crate) struct CurrentRead {
    http: StudioHttp,
    thread_id: String,
    owner_id: String,
    capability: String,
}

/// Preserves the typed public failure for revision-qualified reads; callers must not parse text.
#[derive(Debug)]
pub(crate) struct StudioHttpFailure {
    pub status: StatusCode,
    pub path: String,
    pub error: StudioError,
}

impl std::fmt::Display for StudioHttpFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "{}: {} ({:?}, HTTP {})",
            self.path, self.error.message, self.error.code, self.status
        )
    }
}

impl std::error::Error for StudioHttpFailure {}

impl HistoryRead {
    pub async fn timeline_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryTimelinePage> {
        self.post(
            "history/timeline",
            &serde_json::json!({ "cut": cut, "cursor": cursor, "demand": demand }),
        )
        .await
    }
    pub async fn work_range_page(
        &self,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryWorkRangePage> {
        self.post(
            "history/work-range",
            &serde_json::json!({
                "afterSeq": after_seq, "beforeSeq": before_seq, "cut": cut, "cursor": cursor, "demand": demand
            }),
        )
        .await
    }
    pub async fn turns_page(
        &self,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryBusinessPage> {
        self.post(
            "history/turns",
            &serde_json::json!({ "cut": cut, "cursor": cursor, "demand": demand }),
        )
        .await
    }
    pub async fn events_page(
        &self,
        query: HistoryEventsQuery,
        cut: Option<HistoryCut>,
        cursor: Option<String>,
        demand: HistoryDemand,
    ) -> Result<HistoryEventsPage> {
        self.post(
            "history/events",
            &serde_json::json!({
                "query": query, "cut": cut, "cursor": cursor, "demand": demand
            }),
        )
        .await
    }
    pub async fn event(&self, event_id: &str, demand: HistoryDemand) -> Result<HistoryEventRecord> {
        self.post(
            "history/event",
            &serde_json::json!({ "eventId": event_id, "demand": demand }),
        )
        .await
    }
    pub async fn body(
        &self,
        reference: HistoryEventBodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<HistoryBodyWindow> {
        self.post(
            "history/body",
            &serde_json::json!({
                "reference": reference, "offset": offset, "maxBytes": max_bytes
            }),
        )
        .await
    }
    pub async fn close(&self) -> Result<()> {
        self.post_empty("history/close").await
    }
    async fn post<T: DeserializeOwned, B: Serialize>(&self, suffix: &str, body: &B) -> Result<T> {
        let path = format!("/api/v1/threads/{}/{suffix}", self.thread_id);
        let response = self
            .http
            .client
            .post(format!("{}{path}", self.http.base))
            .header(CONVERSATION_HEADER, &self.capability)
            .json(body)
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let text = response.text().await?;
        decode_json(status, &text, &path)
    }
    async fn post_empty(&self, suffix: &str) -> Result<()> {
        let path = format!("/api/v1/threads/{}/{suffix}", self.thread_id);
        let response = self
            .http
            .client
            .post(format!("{}{path}", self.http.base))
            .header(CONVERSATION_HEADER, &self.capability)
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        if status.is_success() {
            Ok(())
        } else {
            decode_json::<serde_json::Value>(status, &text, &path).map(|_| ())
        }
    }
}

impl CurrentRead {
    pub async fn snapshot(&self, demand: ReadDemand) -> Result<CurrentView> {
        self.post("current/snapshot", &serde_json::json!({ "demand": demand }))
            .await
    }
    pub async fn watch(
        &self,
        after: Option<CurrentRevision>,
        demand: ReadDemand,
    ) -> Result<CurrentWatchStream> {
        let path = format!("/api/v1/threads/{}/current/watch", self.thread_id);
        let client = reqwest::Client::builder()
            .no_proxy()
            .redirect(RedirectPolicy::none())
            .connect_timeout(Duration::from_secs(2))
            .build()?;
        let response = tokio::time::timeout(
            ACK_BUDGET,
            client
                .post(format!("{}{path}", self.http.base))
                .header(CONVERSATION_HEADER, &self.capability)
                .header(reqwest::header::ACCEPT, "text/event-stream")
                .json(&serde_json::json!({ "after": after, "demand": demand }))
                .send(),
        )
        .await
        .context("current watch headers timed out")??;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return match decode_json::<serde_json::Value>(status, &body, &path) {
                Err(error) => Err(error),
                Ok(_) => bail!("current watch returned a successful body with HTTP {status}"),
            };
        }
        ensure!(
            response
                .headers()
                .get(reqwest::header::CONTENT_TYPE)
                .and_then(|value| value.to_str().ok())
                .is_some_and(|value| value.starts_with("text/event-stream")),
            "current watch response is not text/event-stream"
        );
        let mut bytes = 0usize;
        let stream = response
            .bytes_stream()
            .map(move |chunk| -> Result<_> {
                let chunk = chunk?;
                bytes = bytes
                    .checked_add(chunk.len())
                    .context("current watch byte count overflow")?;
                ensure!(
                    bytes <= 4 * 1024 * 1024,
                    "current watch exceeded its cumulative byte budget"
                );
                Ok(chunk)
            })
            .eventsource()
            .boxed();
        Ok(CurrentWatchStream {
            stream,
            owner_id: self.owner_id.clone(),
            demand,
            saw_reset: false,
            revision: None,
        })
    }
    pub async fn page_current(
        &self,
        reference: &CurrentCollectionRef,
        continuation: Option<&str>,
        demand: ReadDemand,
    ) -> Result<CurrentCollectionPage> {
        let page: CurrentCollectionPage = self
            .post(
                "current/page",
                &serde_json::json!({
                    "reference": reference, "continuation": continuation, "demand": demand
                }),
            )
            .await?;
        ensure!(
            page.revision == reference.revision
                && page.entries.len() <= usize::try_from(demand.max_items)?
                && serde_json::to_vec(&page)?.len() <= usize::try_from(demand.max_bytes)?,
            "current collection response exceeded its qualified demand"
        );
        Ok(page)
    }

    pub async fn read_body(
        &self,
        reference: &CurrentContentRef,
        range: ContentRange,
    ) -> Result<ContentWindow> {
        self.post(
            "current/body/read",
            &serde_json::json!({ "reference": reference, "range": range }),
        )
        .await
    }
    pub async fn close(&self) -> Result<()> {
        self.post_empty("current/close").await
    }
    async fn post<T: DeserializeOwned, B: Serialize>(&self, suffix: &str, body: &B) -> Result<T> {
        let path = format!("/api/v1/threads/{}/{suffix}", self.thread_id);
        let response = self
            .http
            .client
            .post(format!("{}{path}", self.http.base))
            .header(CONVERSATION_HEADER, &self.capability)
            .json(body)
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let text = response.text().await?;
        decode_json(status, &text, &path)
    }
    async fn post_empty(&self, suffix: &str) -> Result<()> {
        let path = format!("/api/v1/threads/{}/{suffix}", self.thread_id);
        let response = self
            .http
            .client
            .post(format!("{}{path}", self.http.base))
            .header(CONVERSATION_HEADER, &self.capability)
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let text = response.text().await.unwrap_or_default();
        if status.is_success() {
            Ok(())
        } else {
            decode_json::<serde_json::Value>(status, &text, &path).map(|_| ())
        }
    }
}

type CurrentSseItem = Result<Event, EventStreamError<anyhow::Error>>;

pub(crate) struct CurrentWatchStream {
    stream: BoxStream<'static, CurrentSseItem>,
    owner_id: String,
    demand: ReadDemand,
    saw_reset: bool,
    revision: Option<u64>,
}

impl CurrentWatchStream {
    pub async fn next(&mut self, deadline: Instant) -> Result<Option<CurrentFrame>> {
        let event =
            tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), self.stream.next())
                .await
                .context("current watch exceeded observation deadline")?;
        let Some(event) = event else {
            return Ok(None);
        };
        let event = event?;
        ensure!(
            event.data.len() <= usize::try_from(self.demand.max_bytes)?,
            "current watch frame exceeded its byte demand"
        );
        match event.event.as_str() {
            "current" => {
                let frame: CurrentFrame = serde_json::from_str(&event.data)?;
                let (owner_id, revision) = match &frame {
                    CurrentFrame::Reset { view } => {
                        ensure!(
                            !view.revision.owner_id.is_empty(),
                            "current Reset has no owner"
                        );
                        self.saw_reset = true;
                        self.owner_id = view.revision.owner_id.clone();
                        self.revision = None;
                        (&view.revision.owner_id, view.revision.revision)
                    }
                    CurrentFrame::Notification { revision, .. }
                    | CurrentFrame::Projection { revision, .. } => {
                        ensure!(self.saw_reset, "current watch sent a frame before Reset");
                        (&revision.owner_id, revision.revision)
                    }
                };
                ensure!(
                    owner_id == &self.owner_id,
                    "current watch changed owner identity"
                );
                ensure!(
                    self.revision.is_none_or(|previous| revision >= previous),
                    "current watch revision moved backwards"
                );
                self.revision = Some(revision);
                Ok(Some(frame))
            }
            "error" => {
                let error: StudioError = serde_json::from_str(&event.data)?;
                bail!("current watch: {} ({:?})", error.message, error.code);
            }
            "closed" => Ok(None),
            other => bail!("unexpected current watch event {other}"),
        }
    }
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

    pub async fn open_project(&self, path: &str) -> Result<WorkspaceRecord> {
        self.post_json(
            "/api/v1/projects",
            &pl_studio_runtime::OpenProjectRequest {
                path: path.to_owned(),
            },
        )
        .await
    }

    pub async fn create_thread(
        &self,
        workspace_id: &str,
        request: &pl_studio_runtime::CreateThreadRequest,
    ) -> Result<pl_studio_runtime::StudioStartNewThreadResponse> {
        let path = format!("/api/v1/projects/{workspace_id}/threads");
        let (status, body) = self
            .post_raw_with(&self.command_client, &path, request)
            .await?;
        decode_json(status, &body, &path)
    }

    pub async fn submit_prompt(
        &self,
        thread_id: &str,
        request: &pl_studio_runtime::SubmitPromptRequest,
    ) -> Result<PromptReceipt> {
        self.post_json(&format!("/api/v1/threads/{thread_id}/prompts"), request)
            .await
    }

    pub async fn set_thread_mode(
        &self,
        thread_id: &str,
        request: &pl_studio_runtime::SetThreadModeRequest,
    ) -> Result<pl_studio_runtime::ThreadModeCommandReply> {
        self.put_json(&format!("/api/v1/threads/{thread_id}/mode"), request)
            .await
    }

    pub async fn read_settings(&self) -> Result<pl_studio_runtime::SettingsStateResponse> {
        self.get_json("/api/v1/settings").await
    }

    pub async fn patch_account(
        &self,
        request: &pl_studio_runtime::PatchAccountRequest,
    ) -> Result<pl_studio_runtime::SettingsCommandReply> {
        let path = "/api/v1/accounts";
        let response = self
            .command_client
            .patch(format!("{}{path}", self.base))
            .json(request)
            .send()
            .await
            .with_context(|| format!("PATCH {path}"))?;
        let status = response.status();
        let text = response.text().await?;
        decode_json(status, &text, path)
    }

    pub async fn set_model_connection(
        &self,
        request: &pl_studio_runtime::SetAccountModelConnectionRequest,
    ) -> Result<pl_studio_runtime::SettingsCommandReply> {
        self.put_json("/api/v1/accounts/model-connection", request)
            .await
    }

    pub async fn update_settings_field(
        &self,
        request: &pl_studio_runtime::UpdateSettingsFieldRequest,
    ) -> Result<pl_studio_runtime::SettingsCommandReply> {
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

    /// Opens one immutable-history owner. The returned capability is never shared with Current.
    pub async fn open_history(&self, thread_id: &str) -> Result<HistoryRead> {
        let path = format!("/api/v1/threads/{thread_id}/history/open");
        let response = self
            .client
            .post(format!("{}{path}", self.base))
            .json(&serde_json::json!({
                "historyProtocolVersion": HISTORY_PROTOCOL_VERSION
            }))
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let capability = response
            .headers()
            .get(CONVERSATION_HEADER)
            .map(|value| value.to_str().map(str::to_owned))
            .transpose()?;
        let text = response.text().await?;
        let opened: OpenHistoryResponse = decode_json(status, &text, &path)?;
        let capability = capability.context("history open omitted its reader capability")?;
        ensure!(
            opened.history_protocol_version == HISTORY_PROTOCOL_VERSION
                && opened.reader_id == capability
                && !capability.is_empty(),
            "history open returned inconsistent protocol or reader identity"
        );
        Ok(HistoryRead {
            http: self.clone(),
            thread_id: thread_id.to_owned(),
            capability,
        })
    }

    /// Opens one live-current owner. Its initial snapshot is bounded by the supplied demand.
    pub async fn open_current(&self, thread_id: &str, demand: ReadDemand) -> Result<CurrentRead> {
        let path = format!("/api/v1/threads/{thread_id}/current/open");
        let response = self
            .client
            .post(format!("{}{path}", self.base))
            .json(&serde_json::json!({
                "currentProtocolVersion": CURRENT_PROTOCOL_VERSION,
                "demand": demand,
            }))
            .send()
            .await
            .with_context(|| format!("POST {path}"))?;
        let status = response.status();
        let capability = response
            .headers()
            .get(CONVERSATION_HEADER)
            .map(|value| value.to_str().map(str::to_owned))
            .transpose()?;
        let text = response.text().await?;
        let opened: OpenCurrentResponse = decode_json(status, &text, &path)?;
        let capability = capability.context("current open omitted its reader capability")?;
        ensure!(
            opened.current_protocol_version == CURRENT_PROTOCOL_VERSION
                && opened.reader_id == capability
                && !capability.is_empty()
                && !opened.current_owner_id.is_empty(),
            "current open returned inconsistent protocol, owner, or reader identity"
        );
        Ok(CurrentRead {
            http: self.clone(),
            thread_id: thread_id.to_owned(),
            owner_id: opened.current_owner_id,
            capability,
        })
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
                    pl_studio_runtime::StudioErrorCode::Internal,
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
                    pl_studio_runtime::StudioErrorCode::Internal,
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
            return Err(StudioHttpFailure {
                status,
                path: path.to_owned(),
                error,
            }
            .into());
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
