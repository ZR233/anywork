//! Bots product-topic SSE watch for this observe example only.
//!
//! Decodes with workspace `eventsource-stream`. This is not a general SSE
//! client and does not copy `pl-model`'s private line adapter.

use anyhow::{Context, Result, anyhow, bail, ensure};
use eventsource_stream::{Event, EventStreamError, Eventsource};
use futures::{StreamExt, stream::BoxStream};
use pl_protocol::studio::{
    BotConnectionState, BotRegistrationStatus, BotSnapshot, BotsStateSnapshot,
};
use pl_studio_runtime::{
    StudioProductBaseline, StudioProductBaselineState, StudioProductEventEnvelope,
    StudioProductEventKind, StudioProductTopic,
};
use reqwest::redirect::Policy as RedirectPolicy;
use serde::Deserialize;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use super::env;

const MAX_BYTES: u64 = 4 * 1024 * 1024;
const MAX_EVENTS: u32 = 256;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(2);
const HEADER_BUDGET: Duration = Duration::from_secs(5);

type SseItem = Result<Event, EventStreamError<anyhow::Error>>;

/// How this watcher treats a lagged-subscriber `stale` frame.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Resync {
    /// Re-read the product state from `/api/v1/state/product` and continue.
    /// Existing observations keep this behaviour.
    Readback,
    /// Refuse instead of reading product state back, so an observation can
    /// prove the expected capability change arrived as an active publication
    /// and was not synthesized by a read-back.
    Refuse,
}

#[derive(Debug, Clone)]
pub(crate) struct TopicHit {
    pub revision: u64,
    pub bot_id: String,
    pub connection: BotConnectionState,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct StaleFrame {
    reason: String,
    #[serde(default)]
    dropped: Option<u64>,
    resync: String,
}

pub(crate) struct BotsTopicWatch {
    stream: BoxStream<'static, SseItem>,
    bytes: Arc<AtomicU64>,
    events: u32,
    watermark: Option<u64>,
    last_snapshot: Option<BotsStateSnapshot>,
    resynced: bool,
    saw_baseline: bool,
    origin: String,
}

impl BotsTopicWatch {
    pub async fn connect(origin: &str) -> Result<Self> {
        ensure!(
            origin.starts_with("http://127.0.0.1:"),
            "bots topic SSE must stay on loopback"
        );
        let client = reqwest::Client::builder()
            .no_proxy()
            .redirect(RedirectPolicy::none())
            .connect_timeout(CONNECT_TIMEOUT)
            .build()
            .context("failed to build bots topic SSE client")?;
        let request = client
            .get(format!("{origin}/api/v1/events/product?topic=bots"))
            .header(reqwest::header::ACCEPT, "text/event-stream");
        let response = match tokio::time::timeout(HEADER_BUDGET, request.send()).await {
            Ok(Ok(response)) => response,
            Ok(Err(error)) => {
                return Err(error).context("bots topic SSE request failed before headers");
            }
            Err(_) => {
                bail!("bots topic SSE headers timed out")
            }
        };
        ensure!(
            response.status().is_success(),
            "bots topic SSE HTTP {}",
            response.status()
        );
        let bytes = Arc::new(AtomicU64::new(0));
        let counted = bytes.clone();
        let stream = response
            .bytes_stream()
            .map(move |chunk| match chunk {
                Err(error) => Err(anyhow!("sse transport: {error:#}")),
                Ok(chunk) => {
                    let total = counted.fetch_add(chunk.len() as u64, Ordering::Relaxed)
                        + chunk.len() as u64;
                    if total > MAX_BYTES {
                        Err(anyhow!(
                            "bots topic SSE exceeded 4MiB before a complete event"
                        ))
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
            watermark: None,
            last_snapshot: None,
            resynced: false,
            saw_baseline: false,
            origin: origin.to_owned(),
        })
    }

    pub async fn wait_baseline(
        &mut self,
        bot_id: &str,
        budget: Duration,
    ) -> Result<BotsStateSnapshot> {
        let deadline = Instant::now() + budget;
        match self.next_adopted(deadline, Resync::Readback).await? {
            Adopted::Baseline(snapshot) => {
                ensure!(
                    snapshot.bots.iter().any(|bot| bot.id == bot_id),
                    "bots topic baseline did not include bot {bot_id}"
                );
                Ok(snapshot)
            }
            Adopted::Event { .. } => {
                bail!("bots topic delivered an event before a baseline")
            }
        }
    }

    pub async fn wait_bot(
        &mut self,
        bot_id: &str,
        budget: Duration,
        predicate: impl Fn(&BotSnapshot) -> bool,
        phase: &'static str,
    ) -> Result<TopicHit> {
        self.wait_bot_with(bot_id, budget, predicate, phase, Resync::Readback)
            .await
    }

    /// Same typed bots-topic wait, but a `stale` frame (or a replayed baseline)
    /// fails the observation instead of reading product state back. Used where
    /// the point is to prove an *active* publication.
    pub async fn wait_bot_strict(
        &mut self,
        bot_id: &str,
        budget: Duration,
        predicate: impl Fn(&BotSnapshot) -> bool,
        phase: &'static str,
    ) -> Result<TopicHit> {
        self.wait_bot_with(bot_id, budget, predicate, phase, Resync::Refuse)
            .await
    }

    async fn wait_bot_with(
        &mut self,
        bot_id: &str,
        budget: Duration,
        predicate: impl Fn(&BotSnapshot) -> bool,
        phase: &'static str,
        resync: Resync,
    ) -> Result<TopicHit> {
        let deadline = Instant::now() + budget;
        loop {
            let adopted = self.next_adopted(deadline, resync).await.map_err(|error| {
                anyhow!(
                    "{phase}: {error:#}; last={}",
                    self.last_snapshot
                        .as_ref()
                        .and_then(|snapshot| snapshot.bots.iter().find(|bot| bot.id == bot_id))
                        .map(|bot| redact_connection(&bot.connection))
                        .unwrap_or_else(|| "missing".into())
                )
            })?;
            match adopted {
                Adopted::Baseline(_) => continue,
                Adopted::Event { snapshot } => {
                    let Some(bot) = snapshot.bots.iter().find(|bot| bot.id == bot_id) else {
                        continue;
                    };
                    if predicate(bot) {
                        return Ok(TopicHit {
                            revision: snapshot.revision,
                            bot_id: bot_id.to_owned(),
                            connection: bot.connection.clone(),
                        });
                    }
                }
            }
        }
    }

    pub async fn wait_snapshot_baseline(&mut self, budget: Duration) -> Result<BotsStateSnapshot> {
        let deadline = Instant::now() + budget;
        match self.next_adopted(deadline, Resync::Readback).await? {
            Adopted::Baseline(snapshot) => Ok(snapshot),
            Adopted::Event { .. } => {
                bail!("bots topic delivered an event before a baseline")
            }
        }
    }

    pub async fn wait_snapshot(
        &mut self,
        budget: Duration,
        predicate: impl Fn(&BotsStateSnapshot) -> bool,
        phase: &'static str,
    ) -> Result<BotsStateSnapshot> {
        let deadline = Instant::now() + budget;
        loop {
            let adopted = self
                .next_adopted(deadline, Resync::Readback)
                .await
                .map_err(|error| {
                    anyhow!(
                        "{phase}: {error:#}; last={}",
                        self.last_snapshot
                            .as_ref()
                            .map(redact_snapshot)
                            .unwrap_or_else(|| "none".into())
                    )
                })?;
            match adopted {
                Adopted::Baseline(_) => continue,
                Adopted::Event { snapshot } => {
                    if predicate(&snapshot) {
                        return Ok(snapshot);
                    }
                }
            }
        }
    }

    async fn next_adopted(&mut self, deadline: Instant, resync: Resync) -> Result<Adopted> {
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                bail!(
                    "bots topic SSE timed out after watermark={:?} events={} bytes={}",
                    self.watermark,
                    self.events,
                    self.bytes.load(Ordering::Relaxed)
                );
            }
            let item = tokio::time::timeout(remaining, self.stream.next())
                .await
                .map_err(|_| {
                    anyhow!(
                        "bots topic SSE timed out after watermark={:?} events={} bytes={}",
                        self.watermark,
                        self.events,
                        self.bytes.load(Ordering::Relaxed)
                    )
                })?;
            let Some(item) = item else {
                bail!("bots topic SSE closed before the expected state");
            };
            self.events = self.events.saturating_add(1);
            ensure!(
                self.events <= MAX_EVENTS,
                "bots topic SSE exceeded {MAX_EVENTS} events"
            );
            let event = match item {
                Ok(event) => event,
                Err(error) => return Err(map_stream_error(error)),
            };
            match event.event.as_str() {
                "baseline" => {
                    if resync == Resync::Refuse && self.saw_baseline {
                        bail!(
                            "bots topic replayed a baseline after the initial one; a strict \
                             observation refuses the resync instead of adopting it"
                        );
                    }
                    if let Some(snapshot) = self.apply_baseline(&event.data)? {
                        return Ok(Adopted::Baseline(snapshot));
                    }
                }
                "event" => {
                    if let Some(snapshot) = self.apply_event(&event.data)? {
                        return Ok(Adopted::Event { snapshot });
                    }
                }
                "stale" => match resync {
                    Resync::Readback => self.handle_stale(&event.data).await?,
                    Resync::Refuse => bail!(
                        "bots topic delivered a stale/resync frame before the expected \
                         publication; a strict observation does not read product state back"
                    ),
                },
                "closed" => bail!("bots topic SSE closed before the expected state"),
                "" | "message" => {
                    // Keep-alive / unnamed frames carry no product snapshot.
                }
                _ => bail!("bots topic SSE delivered an unsupported event kind"),
            }
        }
    }

    fn apply_baseline(&mut self, data: &str) -> Result<Option<BotsStateSnapshot>> {
        let baseline: StudioProductBaseline = decode_json(data, "baseline")?;
        ensure!(
            baseline.topic == StudioProductTopic::Bots,
            "bots topic baseline belonged to another topic"
        );
        let StudioProductBaselineState::Bots(snapshot) = baseline.state else {
            bail!("bots topic baseline payload was not Bots");
        };
        ensure!(
            snapshot.revision == baseline.revision,
            "bots topic baseline revision disagreed with payload"
        );
        self.saw_baseline = true;
        self.accept_snapshot(*snapshot)
    }

    fn apply_event(&mut self, data: &str) -> Result<Option<BotsStateSnapshot>> {
        if !self.saw_baseline {
            bail!("bots topic delivered an event before a baseline");
        }
        let envelope: StudioProductEventEnvelope = decode_json(data, "event")?;
        let StudioProductEventKind::BotsStateChanged(snapshot) = envelope.kind else {
            bail!("bots topic event was not BotsStateChanged");
        };
        self.accept_snapshot(snapshot)
    }

    fn accept_snapshot(
        &mut self,
        snapshot: BotsStateSnapshot,
    ) -> Result<Option<BotsStateSnapshot>> {
        if let Some(mark) = self.watermark {
            if snapshot.revision < mark {
                return Ok(None);
            }
            if snapshot.revision == mark {
                if let Some(previous) = &self.last_snapshot {
                    ensure!(
                        previous == &snapshot,
                        "bots topic repeated watermark {mark} with a different snapshot"
                    );
                }
                return Ok(None);
            }
        }
        self.watermark = Some(snapshot.revision);
        self.last_snapshot = Some(snapshot.clone());
        Ok(Some(snapshot))
    }

    async fn handle_stale(&mut self, data: &str) -> Result<()> {
        let stale: StaleFrame = decode_json(data, "stale")?;
        let _ = stale.reason;
        let _ = stale.dropped;
        ensure!(
            stale.resync == "/api/v1/state/product?topic=bots",
            "bots topic stale pointed at an unexpected resync path"
        );
        ensure!(
            !self.resynced,
            "bots topic delivered a second stale after one resync"
        );
        let baseline = read_baseline(&self.origin).await?;
        self.resynced = true;
        self.saw_baseline = true;
        let _ = self.accept_snapshot(baseline)?;
        Ok(())
    }
}

enum Adopted {
    Baseline(BotsStateSnapshot),
    Event { snapshot: BotsStateSnapshot },
}

fn decode_json<T: serde::de::DeserializeOwned>(data: &str, kind: &str) -> Result<T> {
    serde_json::from_str(data).map_err(|error| {
        anyhow!(
            "bots topic {kind} JSON failed at {}:{}",
            error.line(),
            error.column()
        )
    })
}

fn map_stream_error(error: EventStreamError<anyhow::Error>) -> anyhow::Error {
    match error {
        EventStreamError::Utf8(_) => anyhow!("bots topic SSE was not valid UTF-8"),
        EventStreamError::Parser(_) => anyhow!("bots topic SSE framing failed"),
        EventStreamError::Transport(error) => error,
    }
}

async fn read_baseline(origin: &str) -> Result<BotsStateSnapshot> {
    let client = reqwest::Client::builder()
        .no_proxy()
        .redirect(RedirectPolicy::none())
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(Duration::from_secs(10))
        .build()
        .context("failed to build bots topic resync client")?;
    let response = client
        .get(format!("{origin}/api/v1/state/product?topic=bots"))
        .send()
        .await
        .context("GET /api/v1/state/product?topic=bots")?;
    ensure!(
        response.status().is_success(),
        "bots topic resync HTTP {}",
        response.status()
    );
    let text = response.text().await.unwrap_or_default();
    let baseline: StudioProductBaseline = decode_json(&text, "resync")?;
    let StudioProductBaselineState::Bots(snapshot) = baseline.state else {
        bail!("bots topic resync payload was not Bots");
    };
    Ok(*snapshot)
}

pub(crate) fn connection_kind(state: &BotConnectionState) -> &'static str {
    match state {
        BotConnectionState::Disabled => "disabled",
        BotConnectionState::Connecting => "connecting",
        BotConnectionState::Connected => "connected",
        BotConnectionState::Reconnecting { .. } => "reconnecting",
        BotConnectionState::Failed { .. } => "failed",
    }
}

pub(crate) fn redact_connection(state: &BotConnectionState) -> String {
    match state {
        BotConnectionState::Failed {
            code,
            message,
            retryable,
            platform_code,
        } => format!(
            "failed code={code} retryable={retryable} platform={platform_code:?} message={}",
            env::redact(message)
        ),
        other => connection_kind(other).to_owned(),
    }
}

pub(crate) fn registration_kind(status: &BotRegistrationStatus) -> &'static str {
    match status {
        BotRegistrationStatus::Idle => "idle",
        BotRegistrationStatus::Preparing { .. } => "preparing",
        BotRegistrationStatus::Waiting { .. } => "waiting",
        BotRegistrationStatus::SlowDown { .. } => "slowDown",
        BotRegistrationStatus::Completed { .. } => "completed",
        BotRegistrationStatus::Committing { .. } => "committing",
        BotRegistrationStatus::Denied { .. } => "denied",
        BotRegistrationStatus::Expired { .. } => "expired",
        BotRegistrationStatus::Cancelled { .. } => "cancelled",
        BotRegistrationStatus::Failed { .. } => "failed",
    }
}

fn redact_snapshot(snapshot: &BotsStateSnapshot) -> String {
    let registration = snapshot
        .registration
        .as_ref()
        .map(|attempt| {
            format!(
                "attempt={} status={}{} completedBotId={:?} bots={}",
                attempt.attempt_id,
                registration_kind(&attempt.status),
                failed_status_fields(&attempt.status),
                attempt.completed_bot_id.as_deref(),
                snapshot.bots.len()
            )
        })
        .unwrap_or_else(|| format!("none bots={}", snapshot.bots.len()));
    format!("rev={} {registration}", snapshot.revision)
}

fn failed_status_fields(status: &BotRegistrationStatus) -> String {
    match status {
        BotRegistrationStatus::Failed {
            code, retryable, ..
        } => format!(" code={code} retryable={retryable}"),
        _ => String::new(),
    }
}
