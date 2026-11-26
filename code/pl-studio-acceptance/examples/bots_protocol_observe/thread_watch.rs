//! Typed `ConversationFeed` observation for reply cases that wait on interactions and Plan state.

use anyhow::{Context, Result, ensure};
use pl_studio_runtime::timeline::{ConversationEvent, SessionMetaSnapshot};
use pl_studio_runtime::{InteractionRequest, InteractionStatus};
use std::time::{Duration, Instant};

use crate::http::{FeedEventStream, FeedRead, StudioHttp};

const MAX_EVENTS: usize = 512;

pub(crate) struct ThreadWatch {
    http: StudioHttp,
    thread_id: String,
}

impl ThreadWatch {
    pub(crate) fn connect(http: StudioHttp, thread_id: &str) -> Result<Self> {
        ensure!(
            http.origin().starts_with("http://127.0.0.1:"),
            "Feed observation must stay on loopback"
        );
        Ok(Self {
            http,
            thread_id: thread_id.to_owned(),
        })
    }

    pub(crate) async fn wait_session_meta(&mut self, budget: Duration) -> Result<SessionMetaSnapshot> {
        let deadline = Instant::now() + budget;
        let feed = self.open().await?;
        let observed = tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), async {
            let meta = feed.initial_session_meta().clone();
            validate_meta(&meta, &self.thread_id)?;
            Ok::<_, anyhow::Error>(meta)
        })
        .await
        .context("Feed sessionMeta exceeded its deadline")?;
        finish_feed(feed, observed).await
    }

    pub(crate) async fn wait_session_meta_matching(
        &mut self,
        budget: Duration,
        predicate: impl Fn(&SessionMetaSnapshot) -> bool,
        phase: &'static str,
    ) -> Result<SessionMetaSnapshot> {
        let deadline = Instant::now() + budget;
        let feed = self.open().await?;
        let observed = async {
            let mut stream = feed.events().await?;
            let initial = feed.initial_session_meta().clone();
            validate_meta(&initial, &self.thread_id)?;
            if predicate(&initial) {
                return Ok(initial);
            }
            let mut events = 0usize;
            loop {
                match next_event(&mut stream, &mut events, deadline).await? {
                    ConversationEvent::SessionMeta(meta) => {
                        validate_meta(&meta, &self.thread_id)?;
                        if predicate(&meta) {
                            return Ok(meta);
                        }
                    }
                    ConversationEvent::ResyncRequired { reason } => {
                        anyhow::bail!("{phase}: feed required resync: {reason}");
                    }
                    _ => {}
                }
            }
        }
        .await;
        finish_feed(feed, observed).await
    }

    pub(crate) async fn wait_interaction(
        &mut self,
        budget: Duration,
        predicate: impl Fn(&InteractionRequest) -> bool,
        phase: &'static str,
    ) -> Result<InteractionRequest> {
        let meta = self
            .wait_session_meta_matching(
                budget,
                |meta| meta.interactions.iter().any(&predicate),
                phase,
            )
            .await?;
        let found = meta
            .interactions
            .into_iter()
            .find(|item| predicate(item))
            .with_context(|| format!("{phase}: matched interaction disappeared"))?;
        ensure!(
            found.scope.thread_id == self.thread_id,
            "{phase}: interaction belonged to another Thread"
        );
        Ok(found)
    }

    pub(crate) async fn interaction(&mut self, budget: Duration, question_id: &str) -> Result<InteractionRequest> {
        self.wait_interaction(
            budget,
            |item| {
                item.status() == InteractionStatus::Pending
                    && match &item.content {
                        pl_studio_runtime::InteractionContent::UserInput(value) => {
                            value.questions().iter().any(|q| q.id == question_id)
                        }
                        pl_studio_runtime::InteractionContent::ToolApproval(_) => false,
                    }
            },
            "wait pending question interaction",
        )
        .await
    }

    async fn open(&self) -> Result<FeedRead> {
        self.http.open_feed(&self.thread_id, Some(64)).await
    }
}

async fn next_event(
    stream: &mut FeedEventStream,
    events: &mut usize,
    deadline: Instant,
) -> Result<ConversationEvent> {
    *events = (*events)
        .checked_add(1)
        .context("Feed event count overflow")?;
    ensure!(
        *events <= MAX_EVENTS,
        "Feed event stream exceeded {MAX_EVENTS} events"
    );
    stream
        .next(deadline)
        .await?
        .context("Feed event stream ended before the expected event")
}

fn validate_meta(meta: &SessionMetaSnapshot, thread_id: &str) -> Result<()> {
    ensure!(
        meta.thread_id == thread_id,
        "Feed SessionMeta belonged to another Thread"
    );
    ensure!(
        meta.interactions
            .iter()
            .all(|interaction| interaction.scope.thread_id == thread_id),
        "Feed SessionMeta interaction belonged to another Thread"
    );
    Ok(())
}

async fn finish_feed<T>(feed: FeedRead, observed: Result<T>) -> Result<T> {
    let closed = feed.close().await;
    match (observed, closed) {
        (Ok(value), Ok(())) => Ok(value),
        (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(error),
        (Err(error), Err(close_error)) => {
            Err(error.context(format!("Feed close also failed: {close_error:#}")))
        }
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
        pl_studio_runtime::InteractionContent::UserInput(value) => value.questions().len(),
        pl_studio_runtime::InteractionContent::ToolApproval(_) => 0,
    }
}
