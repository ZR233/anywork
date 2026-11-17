//! Typed Current observation for reply cases that wait on interactions.
//!
//! The previous thread State SSE route is not a current product port. Every wait opens a public
//! CurrentReader, consumes ordered CurrentFrame values, reads complete interaction resources through
//! their typed collection references, and closes the capability before returning.

use anyhow::{Context, Result, ensure};
use pl_studio_runtime::{
    CurrentFrame, CurrentView, InteractionRequest, InteractionStatus, ThreadBusinessRefs,
    ThreadNotification, ThreadSnapshot,
};
use std::time::{Duration, Instant};

use crate::http::{CurrentRead, StudioHttp};
use crate::support::{
    HISTORY_OBSERVATION_BYTES, charge_history_bytes, current_demand, current_payload_bytes,
};

const MAX_EVENTS: usize = 256;

pub(crate) struct ThreadWatch {
    http: StudioHttp,
    thread_id: String,
}

impl ThreadWatch {
    /// Prepares a public Current reader target. No history or State SSE is opened here.
    pub(crate) fn connect(http: StudioHttp, thread_id: &str) -> Result<Self> {
        ensure!(
            http.origin().starts_with("http://127.0.0.1:"),
            "Current observation must stay on loopback"
        );
        Ok(Self {
            http,
            thread_id: thread_id.to_owned(),
        })
    }

    /// Waits for the first Current Reset and returns its complete State snapshot.
    pub(crate) async fn wait_snapshot(&mut self, budget: Duration) -> Result<ThreadSnapshot> {
        let deadline = Instant::now() + budget;
        let current = self.open().await?;
        let observed = async {
            let mut watch = current.watch(None, current_demand()).await?;
            let mut events = 0usize;
            loop {
                let frame = next_frame(&mut watch, &mut events, deadline).await?;
                match frame {
                    CurrentFrame::Reset { view } => {
                        validate_view(&view, &self.thread_id)?;
                        return Ok(*view.state);
                    }
                    CurrentFrame::Notification { .. } | CurrentFrame::Projection { .. } => {
                        anyhow::bail!("Current watch delivered a frame before Reset")
                    }
                }
            }
        }
        .await;
        finish_current(current, observed).await
    }

    /// Waits for State business references, starting from the Current Reset baseline.
    pub(crate) async fn wait_business_refs(
        &mut self,
        budget: Duration,
        predicate: impl Fn(&ThreadBusinessRefs) -> bool,
        phase: &'static str,
    ) -> Result<ThreadBusinessRefs> {
        let deadline = Instant::now() + budget;
        let current = self.open().await?;
        let observed = async {
            let mut watch = current.watch(None, current_demand()).await?;
            let mut events = 0usize;
            let mut saw_reset = false;
            loop {
                let frame = next_frame(&mut watch, &mut events, deadline).await?;
                match frame {
                    CurrentFrame::Reset { view } => {
                        validate_view(&view, &self.thread_id)?;
                        saw_reset = true;
                        if predicate(&view.state.business_refs) {
                            return Ok(view.state.business_refs.clone());
                        }
                    }
                    CurrentFrame::Notification { notification, .. } => {
                        ensure!(saw_reset, "{phase}: notification arrived before Reset");
                        if let ThreadNotification::BusinessRefsChanged { references } =
                            notification.notification
                        {
                            validate_business_refs(&references)?;
                            if predicate(&references) {
                                return Ok(references);
                            }
                        }
                    }
                    CurrentFrame::Projection { .. } => {}
                }
            }
        }
        .await;
        finish_current(current, observed).await
    }

    /// Waits for an interaction from Reset/Current notifications or its typed collection resource.
    pub(crate) async fn wait_interaction(
        &mut self,
        budget: Duration,
        predicate: impl Fn(&InteractionRequest) -> bool,
        phase: &'static str,
    ) -> Result<InteractionRequest> {
        let deadline = Instant::now() + budget;
        let current = self.open().await?;
        let observed = async {
            let mut watch = current.watch(None, current_demand()).await?;
            let mut events = 0usize;
            let mut saw_reset = false;
            loop {
                let frame = next_frame(&mut watch, &mut events, deadline).await?;
                match frame {
                    CurrentFrame::Reset { view } => {
                        validate_view(&view, &self.thread_id)?;
                        saw_reset = true;
                        if let Some(found) =
                            view.state.interactions.iter().find(|item| predicate(item))
                        {
                            return Ok(found.clone());
                        }
                        if let Some(found) = find_referenced_interaction(
                            &current,
                            &view.state.business_refs,
                            &self.thread_id,
                            &predicate,
                            deadline,
                        )
                        .await?
                        {
                            return Ok(found);
                        }
                    }
                    CurrentFrame::Notification { notification, .. } => {
                        ensure!(saw_reset, "{phase}: notification arrived before Reset");
                        match notification.notification {
                            ThreadNotification::InteractionChanged { interaction }
                                if predicate(&interaction) =>
                            {
                                ensure!(
                                    interaction.scope.thread_id == self.thread_id,
                                    "{phase}: interaction belonged to another Thread"
                                );
                                return Ok(*interaction);
                            }
                            ThreadNotification::BusinessRefsChanged { references } => {
                                validate_business_refs(&references)?;
                                if let Some(found) = find_referenced_interaction(
                                    &current,
                                    &references,
                                    &self.thread_id,
                                    &predicate,
                                    deadline,
                                )
                                .await?
                                {
                                    return Ok(found);
                                }
                            }
                            _ => {}
                        }
                    }
                    CurrentFrame::Projection { .. } => {}
                }
            }
        }
        .await;
        finish_current(current, observed).await
    }

    async fn open(&self) -> Result<CurrentRead> {
        self.http
            .open_current(&self.thread_id, current_demand())
            .await
    }
}

async fn next_frame(
    watch: &mut crate::http::CurrentWatchStream,
    events: &mut usize,
    deadline: Instant,
) -> Result<CurrentFrame> {
    *events = (*events)
        .checked_add(1)
        .context("Current event count overflow")?;
    ensure!(
        *events <= MAX_EVENTS,
        "Current watch exceeded {MAX_EVENTS} events"
    );
    watch
        .next(deadline)
        .await?
        .context("Current watch ended before the expected frame")
}

fn validate_view(view: &CurrentView, thread_id: &str) -> Result<()> {
    ensure!(
        view.state.schema_version == pl_studio_runtime::THREAD_SCHEMA_VERSION
            && view.state.thread.id == thread_id,
        "Current Reset belonged to another Thread or schema"
    );
    validate_business_refs(&view.state.business_refs)?;
    ensure!(
        view.state
            .interactions
            .iter()
            .all(|interaction| interaction.scope.thread_id == thread_id),
        "Current Reset interaction belonged to another Thread"
    );
    ensure!(
        !view.revision.owner_id.is_empty(),
        "Current Reset omitted its owner identity"
    );
    Ok(())
}

async fn find_referenced_interaction(
    current: &CurrentRead,
    references: &ThreadBusinessRefs,
    thread_id: &str,
    predicate: &impl Fn(&InteractionRequest) -> bool,
    deadline: Instant,
) -> Result<Option<InteractionRequest>> {
    let Some(reference) = references.interactions.as_ref() else {
        return Ok(None);
    };
    let mut remaining = HISTORY_OBSERVATION_BYTES;
    let mut continuation = None;
    let mut seen = std::collections::HashSet::new();
    for page_index in 0..256 {
        let page = tokio::time::timeout_at(
            tokio::time::Instant::from_std(deadline),
            current.page_current(reference, continuation.as_deref(), current_demand()),
        )
        .await
        .context("Current interaction page exceeded its deadline")??;
        ensure!(
            page.revision == reference.revision,
            "Current interaction page revision changed"
        );
        charge_history_bytes(serde_json::to_vec(&page)?.len(), &mut remaining)?;
        for entry in &page.entries {
            let bytes =
                current_payload_bytes(current, &entry.payload, &mut remaining, deadline).await?;
            let interaction: InteractionRequest =
                serde_json::from_slice(&bytes).context("invalid Current interaction payload")?;
            ensure!(
                entry.id == interaction.interaction_id && interaction.scope.thread_id == thread_id,
                "Current interaction entry identity or scope mismatch"
            );
            if predicate(&interaction) {
                return Ok(Some(interaction));
            }
        }
        let Some(next) = page.continuation else {
            return Ok(None);
        };
        ensure!(
            page_index + 1 < 256 && seen.insert(next.clone()),
            "Current interaction collection exceeded its page budget or repeated a cursor"
        );
        continuation = Some(next);
    }
    anyhow::bail!("Current interaction collection exceeded its page budget")
}

async fn finish_current<T>(current: CurrentRead, observed: Result<T>) -> Result<T> {
    let closed = current.close().await;
    match (observed, closed) {
        (Ok(value), Ok(())) => Ok(value),
        (Err(error), Ok(())) | (Ok(_), Err(error)) => Err(error),
        (Err(error), Err(close_error)) => {
            Err(error.context(format!("Current close also failed: {close_error:#}")))
        }
    }
}

fn validate_business_refs(references: &ThreadBusinessRefs) -> Result<()> {
    if let Some(interactions) = &references.interactions {
        ensure!(
            !interactions.owner_id.is_empty() && interactions.collection == "interactions",
            "Current interaction reference is not a canonical interactions collection"
        );
    }
    if let Some(plan) = &references.plan
        && let Some(document) = &plan.document
    {
        ensure!(
            !document.owner_id.is_empty()
                && document.domain == "plan"
                && document.entity_id == "document"
                && document.content_key == "document"
                && !document.generation.is_empty(),
            "Current Plan reference did not match its exact current document version"
        );
    }
    Ok(())
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
