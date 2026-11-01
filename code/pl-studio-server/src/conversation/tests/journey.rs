//! Real loopback routes and the existing wire provider. No user credentials or
//! execution resources outside the temporary project are used.
use std::{collections::HashSet, pin::Pin};

use anyhow::{Context, Result, bail, ensure};
use axum::body::Bytes;
use futures::{Stream, StreamExt};
use pl_protocol::{
    ChatBatch, ChatMessage, ChatPlacement, ChatScope, ContentManifestPage, ContentOwner,
    ContentTarget, ContentWindow, CurrentCollectionPage, CurrentContentRole, CurrentProjection,
    PayloadData, ReadDemand, ThreadNotification, ThreadSubscriptionRequest,
    ThreadSubscriptionUpdate, ThreadWorkspaceMode,
    studio::{
        CreateThreadRequest, NewThreadModelRoute, StudioError, StudioPromptInput,
        SubmitPromptRequest,
    },
};
use pl_provider_fixture::{
    FixtureServer, Protocol, ReplyStage, Step, responses_authoritative_final,
    responses_reasoning_text, responses_text, responses_text_chunks,
};
use pl_studio_runtime::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
use serde::{Serialize, de::DeserializeOwned};
use serde_json::{Value, json};
use tokio::{net::TcpListener, task::JoinHandle};
use tokio_util::sync::CancellationToken;

use super::super::{CONVERSATION_HEADER, ReadLease};
use super::{ACCOUNT, AppState, DEADLINE, MODEL, configure};

const FIRST: &str = "http-first";
const NEXT: &str = "http-next";
const SHUTDOWN: &str = "http-shutdown";

fn demand(items: u32) -> ReadDemand {
    ReadDemand {
        max_items: items,
        max_bytes: 256 * 1024,
    }
}

struct Environment {
    _temp: tempfile::TempDir,
    runtime: StudioRuntime,
    provider: FixtureServer,
    state: AppState,
    base: String,
    server: JoinHandle<std::io::Result<()>>,
    client: reqwest::Client,
    project: String,
}

impl Environment {
    async fn start(steps: Vec<Step>) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let project = temp.path().join("project");
        std::fs::create_dir(&project)?;
        let home = temp.path().join("home");
        let provider = FixtureServer::start(steps).await?;
        let prepared: Result<StudioRuntime> = async {
            configure(&home, provider.base_url())?;
            let mut options = StudioRuntimeOptions::http_server(Some(home));
            options.host = StudioHostKind::Test;
            Box::pin(StudioRuntime::initialize(options))
                .await
                .map_err(Into::into)
        }
        .await;
        let runtime = match prepared {
            Ok(runtime) => runtime,
            Err(error) => {
                let cleanup = provider.finish().await;
                return Err(error.context(format!("provider cleanup: {cleanup:?}")));
            }
        };
        let setup = async {
            let project = runtime.open_project(project).await?.id;
            let listener = TcpListener::bind("127.0.0.1:0").await?;
            let base = format!("http://{}", listener.local_addr()?);
            let client = reqwest::Client::builder().no_proxy().build()?;
            Ok::<_, anyhow::Error>((project, listener, base, client))
        }
        .await;
        let (project, listener, base, client) = match setup {
            Ok(setup) => setup,
            Err(error) => {
                let shutdown = runtime.shutdown_runtime().await;
                let fixture = provider.finish().await;
                return Err(error.context(format!(
                    "cleanup: runtime={shutdown:?}; provider={fixture:?}"
                )));
            }
        };
        let state = AppState::new(runtime.clone(), CancellationToken::new());
        let app = crate::router(state.clone());
        let cancel = state.shutdown.clone();
        let server = tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(cancel.cancelled_owned())
                .await
        });
        Ok(Self {
            _temp: temp,
            runtime,
            provider,
            state,
            base,
            server,
            client,
            project,
        })
    }

    async fn finish(self, result: Result<()>) -> Result<()> {
        self.state.shutdown.cancel();
        let owners = tokio::time::timeout(DEADLINE, self.state.conversations.shutdown()).await;
        let mut server = self.server;
        let socket = match tokio::time::timeout(DEADLINE, &mut server).await {
            Ok(Ok(result)) => result.map_err(anyhow::Error::from),
            Ok(Err(error)) => Err(error.into()),
            Err(error) => {
                // Reap even a failing test's stuck connection rather than
                // leaking a listener into the next test.
                server.abort();
                let _ = server.await;
                Err(error.into())
            }
        };
        let runtime = self.runtime.shutdown_runtime().await;
        let provider = self.provider.finish().await;
        result.with_context(|| format!(
            "cleanup: owners={owners:?}; socket={socket:?}; runtime={runtime:?}; provider={provider:?}"
        ))?;
        owners.context("HTTP owner join")?;
        socket?;
        runtime?;
        provider?;
        ensure!(self.state.streams.available_permits() == crate::MAX_STREAMS);
        Ok(())
    }

    async fn create(&self) -> Result<String> {
        let reply = Box::pin(self.runtime.create_thread_command(
            self.project.clone(),
            CreateThreadRequest {
                title: Some("HTTP conversation journey".into()),
                input: input(FIRST),
                mode: pl_protocol::ThreadModeId::simple().to_string(),
                route: NewThreadModelRoute {
                    account_id: ACCOUNT.into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                delegation_preference: None,
                workspace_mode: ThreadWorkspaceMode::Local,
            },
            None,
        ))
        .await?;
        Ok(reply.thread.id)
    }

    async fn submit(&self, thread: &str, prompt: &str) -> Result<()> {
        let snapshot = self.runtime.thread_snapshot(thread).await?;
        self.runtime
            .submit_prompt_command(
                thread.into(),
                SubmitPromptRequest {
                    input: input(prompt),
                    expected_model_route_revision: snapshot
                        .model_route
                        .as_ref()
                        .context("model route")?
                        .revision,
                },
            )
            .await?;
        Ok(())
    }

    async fn open(
        &self,
        thread: &str,
        parent: Option<&str>,
        items: u32,
    ) -> Result<(String, SseBody)> {
        let mut url = url::Url::parse(&format!("{}/api/v1/threads/{thread}/events", self.base))?;
        {
            let mut query = url.query_pairs_mut();
            query.append_pair("maxItems", &items.to_string());
            query.append_pair("maxBytes", &demand(items).max_bytes.to_string());
            if let Some(parent) = parent {
                query.append_pair("parentId", parent);
            }
        }
        let request = self
            .client
            .get(url)
            .header("last-event-id", "timeline:obsolete:999");
        let response = tokio::time::timeout(DEADLINE, request.send())
            .await??
            .error_for_status()?;
        let id = response
            .headers()
            .get(CONVERSATION_HEADER)
            .context("missing original capability")?
            .to_str()?
            .to_owned();
        Ok((id, SseBody::network(response)))
    }

    async fn post(
        &self,
        thread: &str,
        capability: &str,
        path: &str,
        request: &impl Serialize,
    ) -> Result<reqwest::Response> {
        tokio::time::timeout(
            DEADLINE,
            self.client
                .post(format!("{}/api/v1/threads/{thread}/{path}", self.base))
                .header(CONVERSATION_HEADER, capability)
                .json(request)
                .send(),
        )
        .await?
        .map_err(Into::into)
    }

    async fn query<T: DeserializeOwned>(
        &self,
        thread: &str,
        capability: &str,
        path: &str,
        request: &impl Serialize,
    ) -> Result<T> {
        let response = self.post(thread, capability, path, request).await?;
        let status = response.status();
        let bytes = response.bytes().await?;
        ensure!(
            status.is_success(),
            "{path}: {status}: {}",
            String::from_utf8_lossy(&bytes)
        );
        serde_json::from_slice(&bytes).map_err(Into::into)
    }

    fn lease(&self, thread: &str, id: &str) -> Result<ReadLease> {
        let mut headers = axum::http::HeaderMap::new();
        headers.insert(CONVERSATION_HEADER, id.parse()?);
        self.state
            .conversations
            .borrow(thread, &headers, &self.state.shutdown)
            .map_err(|error| anyhow::anyhow!("{}", error.0))
    }
}

fn input(text: &str) -> StudioPromptInput {
    StudioPromptInput {
        input_id: format!("input-{text}"),
        text: text.into(),
        attachment_draft_ids: vec![],
    }
}

type ByteStream = Pin<Box<dyn Stream<Item = Result<Bytes>> + Send>>;

struct SseBody {
    bytes: ByteStream,
    buffered: Vec<u8>,
}

impl SseBody {
    fn network(response: reqwest::Response) -> Self {
        Self {
            bytes: Box::pin(
                response
                    .bytes_stream()
                    .map(|result| result.map_err(Into::into)),
            ),
            buffered: vec![],
        }
    }

    fn handler(body: axum::body::Body) -> Self {
        Self {
            bytes: Box::pin(
                body.into_data_stream()
                    .map(|result| result.map_err(Into::into)),
            ),
            buffered: vec![],
        }
    }

    async fn event(&mut self) -> Result<Option<(String, Value)>> {
        tokio::time::timeout(DEADLINE, async {
            loop {
                if let Some(end) = self.buffered.windows(2).position(|bytes| bytes == b"\n\n") {
                    let frame = self.buffered.drain(..end + 2).collect::<Vec<_>>();
                    let text = std::str::from_utf8(&frame)?;
                    let event = text.lines().find_map(|line| line.strip_prefix("event: "));
                    let data = text.lines().find_map(|line| line.strip_prefix("data: "));
                    if let (Some(event), Some(data)) = (event, data) {
                        return Ok(Some((event.into(), serde_json::from_str(data)?)));
                    }
                    continue; // Comment heartbeats carry no application data.
                }
                let Some(bytes) = self.bytes.next().await else {
                    ensure!(self.buffered.is_empty(), "truncated SSE frame");
                    return Ok(None);
                };
                self.buffered.extend(bytes?);
                ensure!(
                    self.buffered.len() <= 2 * 256 * 1024,
                    "unbounded SSE test buffer"
                );
            }
        })
        .await
        .context("SSE event deadline")?
    }

    async fn chat(&mut self) -> Result<ChatBatch> {
        loop {
            let (event, value) = self.event().await?.context("SSE ended before Chat")?;
            if event == "chat" {
                return serde_json::from_value(value).map_err(Into::into);
            }
            ensure!(
                event != "error" && event != "closed",
                "unexpected {event}: {value}"
            );
        }
    }

    async fn window(&mut self) -> Result<ContentWindow> {
        let (event, value) = self.event().await?.context("watch ended before window")?;
        ensure!(
            event == "content",
            "unexpected watch event {event}: {value}"
        );
        serde_json::from_value(value).map_err(Into::into)
    }

    async fn end(&mut self) -> Result<()> {
        while let Some((event, value)) = self.event().await? {
            ensure!(
                event == "closed",
                "unexpected terminal watch event {event}: {value}"
            );
        }
        Ok(())
    }
}

async fn complete(
    runtime: &StudioRuntime,
    thread: &str,
    stage: &ReplyStage,
    prompt: &str,
) -> Result<()> {
    let mut events = runtime
        .subscribe_thread(ThreadSubscriptionRequest {
            thread_id: thread.into(),
        })
        .await?;
    stage.release();
    tokio::time::timeout(DEADLINE, async {
        while let Some(update) = events.recv().await? {
            if let ThreadSubscriptionUpdate::Notification { notification } = update
                && let ThreadNotification::TurnCompleted { turn } = notification.notification
                && turn.input_id.as_deref() == Some(&format!("input-{prompt}"))
            {
                return Ok(());
            }
        }
        bail!("Thread ended before completed fixture input")
    })
    .await?
}

async fn payload(
    env: &Environment,
    thread: &str,
    capability: &str,
    message: &ChatMessage,
) -> Result<Value> {
    let bytes = match &message.payload {
        PayloadData::Inline { bytes } => bytes.clone(),
        PayloadData::Deferred {
            reference,
            byte_length,
        } => {
            let mut bytes = Vec::new();
            while (bytes.len() as u64) < *byte_length {
                let window: ContentWindow = env.query(thread, capability, "contents/read", &json!({
                    "reference": reference, "range": {"offset": bytes.len(), "maxBytes": 16384},
                })).await?;
                ensure!(
                    window.sealed
                        && window.offset == bytes.len() as u64
                        && !window.bytes.is_empty()
                );
                bytes.extend(window.bytes);
            }
            ensure!(bytes.len() as u64 == *byte_length);
            bytes
        }
    };
    let value: Value = serde_json::from_slice(&bytes)?;
    ensure!(value["contract"] == "anywork.chat/1");
    Ok(value)
}

async fn all_history(
    env: &Environment,
    thread: &str,
    capability: &str,
    first: ChatBatch,
) -> Result<Vec<ChatMessage>> {
    let mut messages = first.messages;
    let mut before = first.before;
    for _ in 0..32 {
        let Some(cursor) = before else {
            let ids = messages
                .iter()
                .map(|message| &message.id)
                .collect::<HashSet<_>>();
            ensure!(ids.len() == messages.len(), "duplicate completed item");
            return Ok(messages);
        };
        let batch: ChatBatch = env
            .query(
                thread,
                capability,
                "chat/older",
                &json!({"before": cursor, "demand": demand(3)}),
            )
            .await?;
        ensure!(batch.placement == ChatPlacement::Prepend && batch.current.is_none());
        ensure!(
            batch.before.as_ref() != Some(&cursor),
            "nonadvancing cursor"
        );
        messages.splice(0..0, batch.messages);
        before = batch.before;
    }
    bail!("fixture history did not reach EOF within its finite budget")
}

async fn current_with_response(body: &mut SseBody, first: ChatBatch) -> Result<CurrentProjection> {
    let mut batch = first;
    for _ in 0..64 {
        if let Some(current) = batch.current
            && current
                .previews
                .iter()
                .any(|preview| preview.role == CurrentContentRole::Response)
        {
            return Ok(current);
        }
        batch = body.chat().await?;
        ensure!(batch.placement == ChatPlacement::Append);
    }
    bail!("fixture response did not appear in current")
}

#[tokio::test]
async fn real_http_nonempty_history_independent_queries_and_watch_lifecycle() -> Result<()> {
    let first_stage = ReplyStage::new();
    let growing = ReplyStage::new();
    let sealing = ReplyStage::new();
    let stopping = ReplyStage::new();
    let old_text = "已完成的历史正文📖 ".repeat(600);
    let frames = responses_reasoning_text(
        &["private activity member"],
        &[&old_text],
        "first-response",
        MODEL,
    );
    let first_delta = frames
        .iter()
        .position(|frame| frame["type"] == "response.output_text.delta")
        .context("first response delta")?
        + 1;
    let live_frames = responses_text_chunks(&["live α", " +β"], "next-response", MODEL);
    let corrected = "authoritative corrected response";
    let (_, authoritative) =
        responses_authoritative_final("live α +β", corrected, "next-response", MODEL);
    let stop_frames = responses_text(
        "still executing while HTTP closes",
        "shutdown-response",
        MODEL,
    );
    let env = Environment::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            FIRST,
            0,
            first_stage.gated(
                frames[..first_delta].to_vec(),
                frames[first_delta..].to_vec(),
            ),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            NEXT,
            1,
            pl_provider_fixture::ReplyStage::staged(
                vec![
                    live_frames[..3].to_vec(),
                    live_frames[3..4].to_vec(),
                    authoritative,
                ],
                &[&growing, &sealing],
            ),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            SHUTDOWN,
            2,
            stopping.gated(stop_frames[..3].to_vec(), stop_frames[3..].to_vec()),
        ),
    ])
    .await?;
    let result = async {
        let thread = env.create().await?;
        tokio::time::timeout(DEADLINE, first_stage.wait_reached()).await?;
        complete(&env.runtime, &thread, &first_stage, FIRST).await?;
        let (capability, mut main) = env.open(&thread, None, 1).await?;
        let first = main.chat().await?;
        ensure!(first.placement == ChatPlacement::Set && !first.messages.is_empty());
        first.validate_for(&ChatScope::Main)?;
        let original = env.lease(&thread, &capability)?;
        ensure!(original.owner.reader.subscription_id() == capability);
        drop(original);
        let history = all_history(&env, &thread, &capability, first.clone()).await?;
        ensure!(
            history.len() > first.messages.len(),
            "older never returned real completed history"
        );
        let mut parent = None;
        let mut completed_body = None;
        for message in &history {
            let value = payload(&env, &thread, &capability, message).await?;
            ensure!(
                !matches!(value["type"].as_str(), Some("thinking" | "inference")),
                "activity item leaked to Main"
            );
            if value["type"] == "turn" {
                parent = Some((
                    value["data"]["childrenParentId"]
                        .as_str()
                        .context("frozen Turn children parent")?
                        .to_owned(),
                    value["turnId"]
                        .as_str()
                        .context("frozen Turn identity")?
                        .to_owned(),
                ));
            }
            let manifest: ContentManifestPage = env
                .query(
                    &thread,
                    &capability,
                    "contents/manifest",
                    &json!({"itemId": message.id, "continuation": null, "demand": demand(8)}),
                )
                .await?;
            if value["type"] == "text"
                && let Some(entry) = manifest.entries.first()
            {
                completed_body = Some(entry.reference.clone());
            }
        }
        let reference = completed_body.context("real completed response manifest")?;
        let window: ContentWindow = env
            .query(
                &thread,
                &capability,
                "contents/read",
                &json!({
                    "reference": reference, "range": {"offset": 3, "maxBytes": 31},
                }),
            )
            .await?;
        ensure!(window.sealed && window.offset == 3 && window.bytes == old_text.as_bytes()[3..34]);
        ensure!(window.available_through == old_text.len() as u64);
        let (parent, turn_id) = parent.context("completed Turn parent and identity")?;
        let (child_cap, mut children) = env.open(&thread, Some(&parent), 1).await?;
        let child_set = children.chat().await?;
        ensure!(child_set.placement == ChatPlacement::Set && child_set.current.is_none());
        let child_messages = all_history(&env, &thread, &child_cap, child_set).await?;
        ensure!(
            !child_messages.is_empty(),
            "Children did not return the real reasoning member"
        );
        let main_ids = history
            .iter()
            .map(|message| &message.id)
            .collect::<HashSet<_>>();
        ensure!(
            child_messages
                .iter()
                .all(|message| !main_ids.contains(&message.id)),
            "Main and Children mixed"
        );
        let mut thinking = 0;
        let mut inferences = 0;
        for message in &child_messages {
            let value = payload(&env, &thread, &child_cap, message).await?;
            ensure!(
                value["turnId"].as_str() == Some(turn_id.as_str()),
                "another Turn's item leaked to Children: {}",
                value["turnId"]
            );
            ensure!(
                value["data"]["outcome"]["kind"] == "completed",
                "Children returned a member without its completed frozen outcome"
            );
            match value["type"].as_str() {
                Some("thinking") => thinking += 1,
                Some("inference") => inferences += 1,
                kind => bail!("unexpected member from this finite reasoning response: {kind:?}"),
            }
        }
        ensure!(
            thinking == 1 && inferences == 1,
            "missing or repeated completed response member"
        );
        env.submit(&thread, NEXT).await?;
        tokio::time::timeout(DEADLINE, growing.wait_reached()).await?;
        let next = main.chat().await?;
        ensure!(next.placement == ChatPlacement::Append);
        let current = current_with_response(&mut main, next).await?;
        let response_ref = current
            .previews
            .iter()
            .find(|preview| preview.role == CurrentContentRole::Response)
            .context("response preview")?
            .reference
            .clone();

        // Use a real handler body here to prove server backpressure; a TCP
        // receive buffer could keep draining a supposedly paused socket client.
        let response = super::open(&env.state, &thread).await?;
        let paused_cap = response.headers()[CONVERSATION_HEADER].to_str()?.to_owned();
        let mut paused = SseBody::handler(response.into_body());
        let paused_first = paused.chat().await?;
        ensure!(paused_first.placement == ChatPlacement::Set && paused_first.before.is_some());
        let paused_current = paused_first.current.as_ref().context("paused current")?;
        let collection = paused_current
            .collections
            .iter()
            .find(|reference| reference.collection == "members")
            .context("real current members collection")?;
        let page: CurrentCollectionPage = env
            .query(
                &thread,
                &paused_cap,
                "current/page",
                &json!({
                    "reference": collection, "continuation": null, "demand": demand(8),
                }),
            )
            .await?;
        ensure!(page.revision == collection.revision && !page.entries.is_empty());
        let older: ChatBatch = env
            .query(
                &thread,
                &paused_cap,
                "chat/older",
                &json!({
                    "before": paused_first.before, "demand": demand(8),
                }),
            )
            .await?;
        ensure!(
            older.placement == ChatPlacement::Prepend
                && !older.messages.is_empty()
                && older.current.is_none()
        );
        let active_id = match &response_ref.target {
            ContentTarget::Body {
                owner: ContentOwner::Item { item_id },
                ..
            } => item_id.clone(),
            _ => bail!("active response did not retain Item ownership"),
        };
        let manifest: ContentManifestPage = env
            .query(
                &thread,
                &paused_cap,
                "contents/manifest",
                &json!({
                    "itemId": active_id, "continuation": null, "demand": demand(8),
                }),
            )
            .await?;
        ensure!(
            manifest
                .entries
                .iter()
                .any(|entry| entry.reference == response_ref)
        );
        let request = json!({"reference": response_ref, "range": {"offset": 0, "maxBytes": 128}});
        let live: ContentWindow = env
            .query(&thread, &paused_cap, "contents/read", &request)
            .await?;
        ensure!(!live.sealed && live.bytes == "live α".as_bytes());
        let watch = env
            .post(&thread, &paused_cap, "contents/watch", &request)
            .await?
            .error_for_status()?;
        let mut watch = SseBody::network(watch);
        ensure!(watch.window().await? == live);
        // Closing one watch leaves the original lease and execution alive.
        let detached = env
            .post(&thread, &paused_cap, "contents/watch", &request)
            .await?
            .error_for_status()?;
        let mut detached = SseBody::network(detached);
        ensure!(detached.window().await? == live);
        drop(detached);
        let again: ContentWindow = env
            .query(&thread, &paused_cap, "contents/read", &request)
            .await?;
        ensure!(again == live);

        growing.release();
        tokio::time::timeout(DEADLINE, sealing.wait_reached()).await?;
        let updated = watch.window().await?;
        ensure!(!updated.sealed && updated.bytes == "live α +β".as_bytes());
        ensure!(
            updated.generation == live.generation
                && updated.available_through > live.available_through
        );
        // The paused SSE body has not been polled through these valid POSTs.
        let still_independent: ContentWindow = env
            .query(&thread, &paused_cap, "contents/read", &request)
            .await?;
        ensure!(still_independent == updated);
        complete(&env.runtime, &thread, &sealing, NEXT).await?;
        let mut sealed = watch.window().await?;
        for _ in 0..8 {
            if sealed.sealed {
                break;
            }
            sealed = watch.window().await?;
        }
        ensure!(
            sealed.sealed
                && sealed.bytes == corrected.as_bytes()
                && sealed.generation != live.generation
        );
        watch.end().await?;
        // Completion appends the same owned response, then retires current.
        let mut appended = HashSet::new();
        let mut response_seen = false;
        let mut retired = false;
        for _ in 0..64 {
            let batch = main.chat().await?;
            ensure!(batch.placement == ChatPlacement::Append && batch.before.is_none());
            for message in &batch.messages {
                ensure!(!main_ids.contains(&message.id) && appended.insert(message.id.clone()));
                if message.id == active_id {
                    response_seen = true;
                }
            }
            if batch
                .current
                .as_ref()
                .is_some_and(|current| current.active_turn.is_none())
            {
                ensure!(response_seen, "current retired before response completion");
                retired = true;
                break;
            }
        }
        ensure!(retired && response_seen);
        // Compare two real producer-encoded Turn parents after both completed.
        // A made-up string is an invalid ChatKey, not an empty Children scope.
        let (latest_cap, mut latest) = env.open(&thread, None, 1).await?;
        let latest_set = latest.chat().await?;
        ensure!(latest_set.placement == ChatPlacement::Set);
        let terminal = latest_set
            .messages
            .last()
            .context("latest completed Turn")?;
        let terminal = payload(&env, &thread, &latest_cap, terminal).await?;
        ensure!(
            terminal["type"] == "turn" && terminal["data"]["inputId"] == format!("input-{NEXT}")
        );
        let next_parent = terminal["data"]["childrenParentId"]
            .as_str()
            .context("second frozen children parent")?;
        let next_turn = terminal["turnId"]
            .as_str()
            .context("second frozen Turn identity")?;
        ensure!(next_parent != parent && next_turn != turn_id);
        let (next_cap, mut next_children) = env.open(&thread, Some(next_parent), 1).await?;
        let next_set = next_children.chat().await?;
        ensure!(next_set.placement == ChatPlacement::Set && next_set.current.is_none());
        let next_members = all_history(&env, &thread, &next_cap, next_set).await?;
        ensure!(
            next_members.len() == 1,
            "the second response must own exactly one inference"
        );
        let first_members = child_messages
            .iter()
            .map(|message| &message.id)
            .collect::<HashSet<_>>();
        for message in &next_members {
            ensure!(
                !first_members.contains(&message.id)
                    && !main_ids.contains(&message.id)
                    && !appended.contains(&message.id),
                "another parent or Main item leaked to the second Children scope"
            );
            let value = payload(&env, &thread, &next_cap, message).await?;
            ensure!(
                value["type"] == "inference"
                    && value["turnId"] == next_turn
                    && value["data"]["outcome"]["kind"] == "completed",
                "second Children scope lost its frozen membership or terminal outcome"
            );
        }
        let next_lease = env.lease(&thread, &next_cap)?;
        drop(next_children);
        tokio::time::timeout(DEADLINE, next_lease.owner.cancel.cancelled()).await?;
        drop(next_lease);
        drop(latest);
        // Typed stale content, rather than a fabricated empty window.
        let mut stale = collection.clone();
        stale.revision = stale.revision.saturating_add(1_000_000);
        let error = env
            .post(
                &thread,
                &capability,
                "current/page",
                &json!({
                    "reference": stale, "continuation": null, "demand": demand(4),
                }),
            )
            .await?;
        ensure!(error.status() == reqwest::StatusCode::CONFLICT);
        ensure!(error.json::<StudioError>().await?.reason() == Some("staleContent"));
        let cross = env
            .post("different-thread", &capability, "contents/read", &request)
            .await?;
        ensure!(cross.status() == reqwest::StatusCode::CONFLICT);
        ensure!(cross.json::<StudioError>().await?.reason() == Some("staleReadScope"));

        // Disconnect the paused original owner with a watch still attached.
        let detached_watch = env
            .post(&thread, &paused_cap, "contents/watch", &request)
            .await?
            .error_for_status()?;
        let mut detached_watch = SseBody::network(detached_watch);
        let _ = detached_watch.window().await?;
        let lease = env.lease(&thread, &paused_cap)?;
        drop(paused);
        tokio::time::timeout(DEADLINE, lease.owner.cancel.cancelled()).await?;
        let stale = env
            .post(
                &thread,
                &paused_cap,
                "chat/older",
                &json!({
                    "before": first.before, "demand": demand(4),
                }),
            )
            .await?;
        ensure!(stale.status() == reqwest::StatusCode::CONFLICT);
        ensure!(stale.json::<StudioError>().await?.reason() == Some("staleReadScope"));
        drop(lease);
        drop(detached_watch);
        drop(children);
        drop(main);
        // Exercise server shutdown with a genuinely pending watch, rather than
        // one which already reached sealed EOF.
        env.submit(&thread, SHUTDOWN).await?;
        tokio::time::timeout(DEADLINE, stopping.wait_reached()).await?;
        let (shutdown_cap, mut shutdown_body) = env.open(&thread, None, 1).await?;
        let initial = shutdown_body.chat().await?;
        let shutdown_current = current_with_response(&mut shutdown_body, initial).await?;
        let shutdown_ref = &shutdown_current
            .previews
            .iter()
            .find(|preview| preview.role == CurrentContentRole::Response)
            .context("shutdown response preview")?
            .reference;
        let response = env
            .post(
                &thread,
                &shutdown_cap,
                "contents/watch",
                &json!({
                    "reference": shutdown_ref, "range": {"offset": 0, "maxBytes": 128},
                }),
            )
            .await?
            .error_for_status()?;
        let mut shutdown_watch = SseBody::network(response);
        ensure!(!shutdown_watch.window().await?.sealed);
        let admitted = env.lease(&thread, &shutdown_cap)?;
        env.state.shutdown.cancel();
        let join = env.state.conversations.shutdown();
        tokio::pin!(join);
        ensure!(
            matches!(futures::poll!(join.as_mut()), std::task::Poll::Pending),
            "shutdown ignored the admitted query lease"
        );
        ensure!(env.lease(&thread, &shutdown_cap).is_err());
        shutdown_watch.end().await?;
        drop(admitted);
        tokio::time::timeout(DEADLINE, join).await?;
        ensure!(env.state.streams.available_permits() == crate::MAX_STREAMS);
        drop(shutdown_body);
        // Closing transports did not cancel the shared execution.
        complete(&env.runtime, &thread, &stopping, SHUTDOWN).await?;
        Ok(())
    }
    .await;
    first_stage.release();
    growing.release();
    sealing.release();
    stopping.release();
    env.finish(result).await
}
