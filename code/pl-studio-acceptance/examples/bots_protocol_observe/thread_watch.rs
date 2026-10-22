//! Thread-state SSE watch for the reply observe cases.
//!
//! Decodes `/api/v1/threads/{id}/events` with the workspace `eventsource-stream`
//! crate and the public `pl_protocol` thread DTOs. The first `snapshot` frame is
//! the authoritative interaction projection (wire interaction IDs and scope);
//! later `notification` frames only update typed state. This is not a general
//! SSE client and never re-implements the model line adapter.

use anyhow::{Context, Result, anyhow, bail, ensure};
use eventsource_stream::{Event, EventStreamError, Eventsource};
use futures::{StreamExt, stream::BoxStream};
use pl_protocol::{
    InteractionRequest, InteractionStatus, ThreadNotification, ThreadSnapshot,
    ThreadSubscriptionUpdate,
};
use reqwest::redirect::Policy as RedirectPolicy;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

const MAX_BYTES: u64 = 4 * 1024 * 1024;
const MAX_EVENTS: u32 = 256;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);
const HEADER_BUDGET: Duration = Duration::from_secs(5);

type SseItem = Result<Event, EventStreamError<anyhow::Error>>;

pub(crate) struct ThreadWatch {
    stream: BoxStream<'static, SseItem>,
    bytes: Arc<AtomicU64>,
    events: u32,
    thread_id: String,
    interactions: Vec<InteractionRequest>,
    revision: Option<u64>,
    saw_snapshot: bool,
}

impl ThreadWatch {
    /// Opens the public thread event stream. The first adopted frame must be a
    /// `snapshot`; without `Last-Event-ID` the server never replays.
    pub async fn connect(origin: &str, thread_id: &str) -> Result<Self> {
        ensure!(
            origin.starts_with("http://127.0.0.1:"),
            "thread SSE must stay on loopback"
        );
        let client = reqwest::Client::builder()
            .no_proxy()
            .redirect(RedirectPolicy::none())
            .connect_timeout(CONNECT_TIMEOUT)
            .build()
            .context("failed to build thread SSE client")?;
        let request = client
            .get(format!("{origin}/api/v1/threads/{thread_id}/events"))
            .header(reqwest::header::ACCEPT, "text/event-stream");
        let response = match tokio::time::timeout(HEADER_BUDGET, request.send()).await {
            Ok(Ok(response)) => response,
            Ok(Err(error)) => {
                return Err(error).context("thread SSE request failed before headers");
            }
            Err(_) => bail!("thread SSE headers timed out"),
        };
        ensure!(
            response.status().is_success(),
            "thread SSE HTTP {}",
            response.status()
        );
        let bytes = Arc::new(AtomicU64::new(0));
        let counted = bytes.clone();
        let stream = response
            .bytes_stream()
            .map(move |chunk| match chunk {
                Err(error) => Err(anyhow!("thread SSE transport: {error:#}")),
                Ok(chunk) => {
                    let total = counted.fetch_add(chunk.len() as u64, Ordering::Relaxed)
                        + chunk.len() as u64;
                    if total > MAX_BYTES {
                        Err(anyhow!("thread SSE exceeded 4MiB before a complete event"))
                    } else {
                        Ok(chunk)
                    }
                }
            })
            .eventsource()
            .boxed();
        Ok(Self {
            stream,
            bytes,
            events: 0,
            thread_id: thread_id.to_owned(),
            interactions: Vec::new(),
            revision: None,
            saw_snapshot: false,
        })
    }

    /// Waits for the authoritative first snapshot and returns it.
    pub async fn wait_snapshot(&mut self, budget: Duration) -> Result<ThreadSnapshot> {
        let deadline = Instant::now() + budget;
        loop {
            let frame = self.next_frame(deadline).await?;
            if let WatchFrame::Snapshot(snapshot) = frame {
                return Ok(*snapshot);
            }
            ensure!(
                self.saw_snapshot,
                "thread SSE delivered a notification before the snapshot"
            );
        }
    }

    /// Waits for an interaction matching `predicate`, starting from the adopted
    /// snapshot projection and continuing over typed `InteractionChanged`
    /// notifications. Fails closed on lag or stream errors.
    pub async fn wait_interaction(
        &mut self,
        budget: Duration,
        predicate: impl Fn(&InteractionRequest) -> bool,
        phase: &'static str,
    ) -> Result<InteractionRequest> {
        let deadline = Instant::now() + budget;
        loop {
            if let Some(found) = self.interactions.iter().find(|item| predicate(item)) {
                return Ok(found.clone());
            }
            let frame = self
                .next_frame(deadline)
                .await
                .map_err(|error| anyhow!("{phase}: {error:#}"))?;
            if let WatchFrame::Interaction(interaction) = frame
                && predicate(&interaction)
            {
                return Ok(*interaction);
            }
        }
    }

    async fn next_frame(&mut self, deadline: Instant) -> Result<WatchFrame> {
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                bail!(
                    "thread {} SSE timed out at revision={:?} events={} bytes={} interactions={}",
                    self.thread_id,
                    self.revision,
                    self.events,
                    self.bytes.load(Ordering::Relaxed),
                    self.interactions.len()
                );
            }
            let item = tokio::time::timeout(remaining, self.stream.next())
                .await
                .map_err(|_| {
                    anyhow!(
                        "thread {} SSE timed out at revision={:?} events={} bytes={}",
                        self.thread_id,
                        self.revision,
                        self.events,
                        self.bytes.load(Ordering::Relaxed)
                    )
                })?;
            let Some(item) = item else {
                bail!(
                    "thread {} SSE closed before the expected state",
                    self.thread_id
                );
            };
            self.events = self.events.saturating_add(1);
            ensure!(
                self.events <= MAX_EVENTS,
                "thread {} SSE exceeded {MAX_EVENTS} events",
                self.thread_id
            );
            let event = match item {
                Ok(event) => event,
                Err(error) => return Err(map_stream_error(error)),
            };
            match event.event.as_str() {
                "snapshot" => {
                    let update: ThreadSubscriptionUpdate = decode(&event.data, "snapshot")?;
                    let ThreadSubscriptionUpdate::Snapshot { snapshot } = update else {
                        bail!("thread SSE snapshot frame carried a different update");
                    };
                    ensure!(
                        snapshot.thread.id == self.thread_id,
                        "thread SSE snapshot belonged to another Thread"
                    );
                    ensure!(
                        !self.saw_snapshot,
                        "thread SSE delivered a second snapshot without a reconnect"
                    );
                    self.saw_snapshot = true;
                    self.revision = Some(snapshot.revision);
                    self.interactions = snapshot.interactions.clone();
                    return Ok(WatchFrame::Snapshot(snapshot));
                }
                "notification" | "lagged" => {
                    let lagged = event.event.as_str() == "lagged";
                    let update: ThreadSubscriptionUpdate = decode(&event.data, "notification")?;
                    let ThreadSubscriptionUpdate::Notification { notification } = update else {
                        bail!("thread SSE notification frame carried a different update");
                    };
                    if notification.thread_id != self.thread_id {
                        continue;
                    }
                    if let Some(mark) = self.revision
                        && notification.revision < mark
                    {
                        continue;
                    }
                    self.revision = Some(notification.revision);
                    if lagged {
                        bail!(
                            "thread {} SSE lagged before the expected interaction; \
                             discovery evidence is incomplete and cannot be claimed",
                            self.thread_id
                        );
                    }
                    match notification.notification {
                        ThreadNotification::InteractionChanged { interaction } => {
                            let interaction = *interaction;
                            ensure!(
                                interaction.scope.thread_id == self.thread_id,
                                "thread SSE interaction belonged to another Thread"
                            );
                            match self
                                .interactions
                                .iter_mut()
                                .find(|item| item.interaction_id == interaction.interaction_id)
                            {
                                Some(existing) => *existing = interaction.clone(),
                                None => self.interactions.push(interaction.clone()),
                            }
                            return Ok(WatchFrame::Interaction(Box::new(interaction)));
                        }
                        _ => continue,
                    }
                }
                "stale" => bail!(
                    "thread {} SSE delivered stale although no Last-Event-ID was sent",
                    self.thread_id
                ),
                "error" => {
                    let message = event.data.lines().next().unwrap_or_default().to_owned();
                    bail!(
                        "thread {} SSE error frame: {}",
                        self.thread_id,
                        crate::env::redact(&message)
                    );
                }
                "closed" => bail!(
                    "thread {} SSE closed before the expected state",
                    self.thread_id
                ),
                "" | "message" => continue,
                _ => bail!(
                    "thread {} SSE delivered an unsupported event kind",
                    self.thread_id
                ),
            }
        }
    }
}

enum WatchFrame {
    Snapshot(Box<ThreadSnapshot>),
    Interaction(Box<InteractionRequest>),
}

fn decode<T: serde::de::DeserializeOwned>(data: &str, kind: &str) -> Result<T> {
    serde_json::from_str(data).map_err(|error| {
        anyhow!(
            "thread SSE {kind} JSON failed at {}:{}",
            error.line(),
            error.column()
        )
    })
}

fn map_stream_error(error: EventStreamError<anyhow::Error>) -> anyhow::Error {
    match error {
        EventStreamError::Utf8(_) => anyhow!("thread SSE was not valid UTF-8"),
        EventStreamError::Parser(_) => anyhow!("thread SSE framing failed"),
        EventStreamError::Transport(error) => error,
    }
}

/// Safe typed summary used in case evidence lines.
pub(crate) fn interaction_line(interaction: &InteractionRequest) -> String {
    format!(
        "id={} status={} scope.thread={} scope.turn={} questions={}",
        interaction.interaction_id,
        interaction_status_line(interaction),
        interaction.scope.thread_id,
        interaction.scope.turn_id,
        interaction_questions_line(interaction)
    )
}

pub(crate) fn interaction_status_line(interaction: &InteractionRequest) -> &'static str {
    match interaction.status() {
        InteractionStatus::Pending => "pending",
        InteractionStatus::Resolved => "resolved",
        InteractionStatus::Cancelled => "cancelled",
        InteractionStatus::Expired => "expired",
    }
}

fn interaction_questions_line(interaction: &InteractionRequest) -> usize {
    match &interaction.content {
        pl_protocol::InteractionContent::UserInput(value) => value.questions().len(),
        pl_protocol::InteractionContent::ToolApproval(_) => 0,
    }
}
