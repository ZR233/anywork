//! Private scheduling and append-only history candidates over the original reliable queue.
//!
//! The queue still owns Core admission pressure and shutdown ordering. At a selected cut it
//! converts already-published immutable product facts to schema-25 events, accepts them in RAM,
//! then flushes that prefix. It never reads, fences, or acknowledges `current.json`.

use super::*;
use crate::history::{HistoryEvent, HistoryEventKind, HistoryRowHead, HistoryUsageFact};
use pl_core::usage::UsageOutcome;

/// Local acknowledgement of one durable append-only history cut.
pub(in crate::studio) struct CommittedBatch {
    database_id: String,
}

impl CommittedBatch {
    pub(in crate::studio) fn database_id(&self) -> &str {
        &self.database_id
    }
}

const WINDOW: Duration = Duration::from_millis(20);
const MAX_EFFECTS: usize = 64;
const MAX_BYTES: u64 = 1024 * 1024;

#[derive(Debug)]
pub(super) struct FrozenBatch {
    count: usize,
    first: u64,
    last: u64,
    usage: UsageSummary,
    accepted_steps: usize,
}

pub(super) struct Effect {
    pub(super) sequence: u64,
    pub(super) write: Arc<HistoryExport>,
    pub(super) prepared: Arc<PreparedEffect>,
    bytes: u64,
}

pub(super) enum Selection {
    Idle,
    Wait(Instant),
    Ready(Vec<Effect>),
}

pub(super) fn select(
    progress: &mut Progress,
    now: Instant,
    process_bytes: u64,
    resident_pressure: bool,
) -> Selection {
    let Some(head) = progress.effects.front() else {
        return Selection::Idle;
    };
    if head.prepared.is_none() {
        return Selection::Idle;
    }
    if progress.in_flight.is_none() {
        let mut count = 0;
        let mut bytes = 0_u64;
        let mut gap = false;
        let mut last = head.sequence;
        let flushing = progress.flush_target > progress.durable;
        for effect in &progress.effects {
            if effect.prepared.is_none()
                || (count > 0 && last.checked_add(1) != Some(effect.sequence))
            {
                gap = true;
                break;
            }
            if count > 0 && bytes.saturating_add(effect.bytes) > MAX_BYTES {
                break;
            }
            count += 1;
            bytes = bytes.saturating_add(effect.bytes);
            last = effect.sequence;
            if count == MAX_EFFECTS
                || bytes >= MAX_BYTES
                || (flushing && last >= progress.flush_target)
            {
                break;
            }
        }
        let deadline = head.admitted_at + WINDOW;
        let pressure = resident_pressure
            || progress.pressure_paused
            || progress.fault == Some(crate::HistoryFault::QueueFull)
            || progress.effects.len() >= MAX_HISTORY_BATCHES
            || progress.effect_bytes >= MAX_HISTORY_THREAD_BYTES
            || process_bytes >= MAX_HISTORY_PROCESS_BYTES;
        if !gap
            && count == progress.effects.len()
            && count < MAX_EFFECTS
            && bytes < MAX_BYTES
            && !flushing
            && !pressure
            && !progress.retry_requested
            && now < deadline
        {
            return Selection::Wait(deadline);
        }
        progress.in_flight = Some(FrozenBatch {
            count,
            first: head.sequence,
            last,
            usage: progress.usage.clone(),
            accepted_steps: 0,
        });
    }
    let frozen = progress.in_flight.as_ref().expect("selected a batch");
    let selected: Vec<_> = progress
        .effects
        .iter()
        .take(frozen.count)
        .map(|effect| Effect {
            sequence: effect.sequence,
            write: effect.write.clone(),
            prepared: effect
                .prepared
                .as_ref()
                .expect("frozen prepared prefix")
                .clone(),
            bytes: effect.bytes,
        })
        .collect();
    Selection::Ready(selected)
}

struct Candidate {
    summary: UsageSummary,
    revision: u64,
    pressure_paused: bool,
}

fn millis(at: i64) -> Result<i64> {
    crate::history::milliseconds_from_seconds(at)
        .map_err(|error| anyhow::anyhow!(error.to_string()))
}

fn turn_event(
    turn: &crate::history::HistoryTurnHead,
    detail: Option<&crate::Turn>,
    recorded_at: i64,
    anchor: bool,
) -> Result<HistoryEvent> {
    let terminal = matches!(
        turn.state,
        crate::history::HistoryTurnState::Completed
            | crate::history::HistoryTurnState::Cancelled
            | crate::history::HistoryTurnState::Failed
            | crate::history::HistoryTurnState::BudgetLimited
    );
    let mut event = HistoryEvent::new(
        format!("turn:{}:{}:{:?}", turn.turn_id, turn.updated_at, turn.state),
        if terminal {
            HistoryEventKind::TurnEnded
        } else if anchor && turn.started_at.is_some() {
            HistoryEventKind::TurnStarted
        } else {
            HistoryEventKind::TurnChanged
        },
        recorded_at,
    );
    event.header.run_id = turn.run_id.clone();
    event.header.turn_id = Some(turn.turn_id.clone());
    event.header.row_key = Some(format!("turn:{}", turn.turn_id));
    event.header.occurred_at = if terminal {
        turn.finished_at
    } else {
        turn.started_at
    };
    let mut head = turn.clone();
    if let Some(detail) = detail {
        head.detail_event_id = Some(event.header.event_id.clone());
        let mut body = crate::history::HistoryBody::new(
            "turn_detail",
            crate::history::HistoryBodyRole::CanonicalPayload,
            serde_json::to_vec(detail)?,
        );
        body.media_type = Some("application/json".into());
        event.payload_body_id = Some(body.body_id.clone());
        event.bodies.push(body);
    }
    event.head = Some(HistoryRowHead::Turn(head));
    event.is_anchor = anchor;
    Ok(event)
}

fn source_event(
    source: &crate::history::HistorySourceHead,
    recorded_at: i64,
    anchor: bool,
) -> Result<HistoryEvent> {
    let identity = serde_json::to_string(&source.source)?;
    let ended = matches!(&source.lifecycle, crate::ChatSourceLifecycle::Ended { .. });
    let mut event = HistoryEvent::new(
        format!("source:{identity}:{ended}:{recorded_at}"),
        if ended {
            HistoryEventKind::SourceEnded
        } else {
            HistoryEventKind::SourceStarted
        },
        recorded_at,
    );
    event.header.source = Some(source.source.clone());
    event.header.row_key = Some(format!("source:{identity}"));
    event.header.occurred_at = source.started_at.or(source.ended_at);
    event.head = Some(HistoryRowHead::Source(source.clone()));
    event.is_anchor = anchor;
    Ok(event)
}

fn run_event(run: &str, recorded_at: i64) -> HistoryEvent {
    let mut event = HistoryEvent::new(
        format!("run:{run}:started"),
        HistoryEventKind::RunStarted,
        recorded_at,
    );
    event.header.run_id = Some(run.to_owned());
    event
}

fn delivery_event(
    thread_id: &str,
    prefix: &str,
    message_id: &str,
    _source_id: &str,
    kind: &str,
    _revision: u64,
    payload: String,
    run: pl_core::thread::current::RuntimeEpoch,
    recorded_at: i64,
    anchor: bool,
) -> HistoryEvent {
    let mut event = HistoryEvent::new(
        format!("{prefix}:{message_id}"),
        HistoryEventKind::BackgroundDeliveryRecorded,
        recorded_at,
    );
    event.header.run_id = Some(run.to_string());
    event.header.message_id = Some(message_id.to_owned());
    event.header.source = Some(crate::studio::history_delivery::source(thread_id, prefix));
    let payload = pl_core::context::OpaquePayload::new(
        match kind {
            "parentReport" => "pl.studio.parent-report",
            _ => "pl.studio.review-delivery",
        },
        1,
        payload,
    )
    .expect("producer delivery is valid JSON");
    let mut body = crate::history::HistoryBody::new(
        "business_fact",
        crate::history::HistoryBodyRole::CanonicalPayload,
        serde_json::to_vec(&payload).expect("producer delivery is serializable"),
    );
    body.media_type = Some("application/json".into());
    event.payload_body_id = Some(body.body_id.clone());
    event.bodies.push(body);
    event.is_anchor = anchor;
    event
}

async fn record_classifier(
    inner: &Inner,
    history: &HistoryStore,
    change: &crate::history::HistoryEntityChange,
    inputs: &std::collections::BTreeMap<
        String,
        crate::studio::thread_projection::HistoryObservationInput,
    >,
) -> Result<()> {
    let run = change
        .entity
        .run_id
        .clone()
        .context("history entity has no runtime epoch")?;
    let mut classifier = {
        let shared = inner
            .channel
            .history_classifier
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match shared.as_ref() {
            Some(classifier) if classifier.run_matches(&run) => classifier.clone(),
            _ => crate::history::HistoryClassifier::from_run_id(&run)?,
        }
    };
    let mut change = change.clone();
    let visible_boundary = change.placement == crate::history::HistoryPlacement::Single
        && change.entity.content_present != Some(false)
        && !history
            .anchor_exists(&format!("single:{}", change.entity.entity_id))
            .await?;
    if visible_boundary {
        for entity in classifier.boundary_entities() {
            let observed = inputs
                .get(entity)
                .with_context(|| format!("boundary has no producer cut for {entity}"))?;
            change
                .boundary_observations
                .push(observed.freeze(&change.event, history.database_id())?);
        }
    }
    match classifier.record(history, &change).await {
        Ok(_) => {}
        Err(crate::history::HistoryError::Capacity) => {
            history.flush().await?;
            classifier.record(history, &change).await?;
        }
        Err(error) => return Err(error.into()),
    }
    *inner
        .channel
        .history_classifier
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(classifier);
    Ok(())
}

async fn accept_event(history: &HistoryStore, event: HistoryEvent) -> Result<()> {
    match history.accept_batch(std::slice::from_ref(&event)).await {
        Ok(_) => Ok(()),
        Err(crate::history::HistoryError::Capacity) => {
            history.flush().await?;
            history.accept_batch(std::slice::from_ref(&event)).await?;
            Ok(())
        }
        Err(error) => Err(error.into()),
    }
}

async fn run_started(history: &HistoryStore, run: &str, recorded_at: i64) -> Result<()> {
    let event = run_event(run, recorded_at);
    match history
        .reader()
        .read_event(
            event.header.event_id.clone(),
            crate::history::HistoryDemand {
                max_rows: 1,
                max_bytes: 4096,
            },
        )
        .await
    {
        Ok(existing) => {
            let mut expected = event.header;
            expected.seq = existing.header.seq;
            expected.recorded_at = existing.header.recorded_at;
            ensure!(
                existing.header == expected
                    && existing.payload_ref.is_none()
                    && existing.head.is_none()
                    && existing.owned_manifest_event_id.is_none(),
                "run start identity conflicts"
            );
            Ok(())
        }
        Err(crate::history::HistoryError::NotFound(_)) => accept_event(history, event).await,
        Err(error) => Err(error.into()),
    }
}

async fn accept_step<F: Future<Output = Result<()>>>(
    inner: &Inner,
    position: &mut usize,
    make: impl FnOnce() -> F,
) -> Result<()> {
    let step = *position;
    *position = position
        .checked_add(1)
        .context("history batch step overflow")?;
    {
        let progress = lock_progress(inner);
        let batch = progress
            .in_flight
            .as_ref()
            .context("history prefix was not selected")?;
        if step < batch.accepted_steps {
            return Ok(());
        }
        ensure!(
            step == batch.accepted_steps,
            "history prefix has a missing admission step"
        );
    }
    make().await?;
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("selected history prefix disappeared")?;
    ensure!(
        batch.accepted_steps == step,
        "concurrent history prefix admission"
    );
    batch.accepted_steps += 1;
    Ok(())
}

pub(super) async fn persist(inner: &Inner, effects: &[Effect]) -> Result<()> {
    ensure!(!effects.is_empty(), "cannot persist an empty history batch");
    let started = Instant::now();
    let mut summary = {
        let progress = lock_progress(inner);
        progress
            .in_flight
            .as_ref()
            .map_or_else(|| progress.usage.clone(), |batch| batch.usage.clone())
    };
    let mut candidates = Vec::with_capacity(effects.len());
    for effect in effects {
        let projected = &effect.prepared;
        ensure!(
            projected.sequence == effect.sequence
                && projected.accounting.sequence == effect.sequence
                && projected.accounting.thread_id == inner.thread.id,
            "prepared history batch {} has inconsistent handoff identities",
            effect.sequence
        );
        projected.accounting.fold_into(&mut summary);
        candidates.push(Candidate {
            summary: summary.clone(),
            revision: effect.write.effect.sequence,
            pressure_paused: effect.write.state.persistence.pressure_paused,
        });
    }
    {
        let mut progress = lock_progress(inner);
        progress.in_flight_bytes = effects.iter().map(|effect| effect.bytes).sum();
        progress.saving_revision = candidates.last().expect("nonempty batch").revision;
        report(inner, &progress);
    }

    let history = history_store(inner).await?;
    let database_id = history.database_id().to_owned();
    let mut step = 0;
    for effect in effects {
        let prepared = &effect.prepared;
        let recorded_at = millis(prepared.committed_at)?;
        let run = prepared.run_id.to_string();
        accept_step(inner, &mut step, || {
            run_started(&history, &run, recorded_at)
        })
        .await?;
        if let Some(report) = &prepared.parent_report {
            accept_step(inner, &mut step, || async {
                accept_event(
                    &history,
                    delivery_event(
                        &inner.thread.id,
                        "parent_report",
                        &report.id,
                        &report.source_id,
                        "parentReport",
                        prepared.sequence,
                        serde_json::to_string(report)?,
                        prepared.run_id,
                        recorded_at,
                        false,
                    ),
                )
                .await
            })
            .await?;
        }
        for fact in prepared.review_delivery.iter() {
            accept_step(inner, &mut step, || async {
                accept_event(
                    &history,
                    delivery_event(
                        &inner.thread.id,
                        "review_delivery",
                        &fact.message.id,
                        &fact.message.source_id,
                        "reviewDeliveryException",
                        prepared.sequence,
                        serde_json::to_string(fact)?,
                        prepared.run_id,
                        recorded_at,
                        false,
                    ),
                )
                .await
            })
            .await?;
        }
        for fact in prepared.retained_resources.iter() {
            accept_step(inner, &mut step, || async {
                accept_event(
                    &history,
                    crate::studio::history_resources::observed_event(
                        &fact.reference,
                        &run,
                        &fact.call_id,
                        fact.turn_id.as_deref(),
                        prepared.sequence,
                        recorded_at,
                    )?,
                )
                .await
            })
            .await?;
        }
        for turn in prepared.history_turns.iter() {
            accept_step(inner, &mut step, || async {
                let row = format!("turn:{}", turn.turn_id);
                let mut event = turn_event(
                    turn,
                    prepared.history_turn_details.get(&turn.turn_id),
                    recorded_at,
                    !history.anchor_exists(&row).await?,
                )?;
                event.header.event_id =
                    format!("turn:{}:{}:{}", run, turn.turn_id, prepared.sequence);
                if let Some(HistoryRowHead::Turn(head)) = &mut event.head {
                    if head.detail_event_id.is_some() {
                        head.detail_event_id = Some(event.header.event_id.clone());
                    }
                }
                accept_event(&history, event).await
            })
            .await?;
        }
        for source in prepared.history_sources.iter() {
            accept_step(inner, &mut step, || async {
                let identity = serde_json::to_string(&source.source)?;
                let row = format!("source:{identity}");
                accept_event(
                    &history,
                    source_event(source, recorded_at, !history.anchor_exists(&row).await?)?,
                )
                .await
            })
            .await?;
        }
        for change in prepared.history_changes.iter() {
            accept_step(inner, &mut step, || {
                record_classifier(inner, &history, change, &prepared.boundary_inputs)
            })
            .await?;
        }
        for fact in prepared.accounting.facts.iter() {
            accept_step(inner, &mut step, || async {
                let outcome = match fact.status {
                    crate::studio::storage::calls::CallStatus::Committed => UsageOutcome::Succeeded,
                    crate::studio::storage::calls::CallStatus::Rejected => UsageOutcome::Rejected,
                    crate::studio::storage::calls::CallStatus::Cancelled => UsageOutcome::Cancelled,
                    crate::studio::storage::calls::CallStatus::Interrupted => {
                        UsageOutcome::Interrupted
                    }
                    crate::studio::storage::calls::CallStatus::Failed => UsageOutcome::Failed,
                    crate::studio::storage::calls::CallStatus::Running => {
                        anyhow::bail!("running accounting fact cannot enter history")
                    }
                };
                let usage = HistoryUsageFact {
                    event_id: format!("usage:{}:{}", run, fact.record.inference_id),
                    runtime_epoch: prepared.run_id,
                    turn_id: prepared.accounting.primary_turn_id().map(str::to_owned),
                    outcome,
                    record: fact.record.clone(),
                };
                match history.record_usage(&usage).await {
                    Ok(_) => Ok(()),
                    Err(crate::history::HistoryError::Capacity) => {
                        history.flush().await?;
                        history.record_usage(&usage).await?;
                        Ok(())
                    }
                    Err(error) => Err(error.into()),
                }
            })
            .await?;
        }
    }

    let database_started = Instant::now();
    lock_progress(inner).enter_stage(Some(HistoryStage::SqlCommit), database_started);
    let committed = history.flush().await.map_err(anyhow::Error::new);
    let database_elapsed_us = database_started.elapsed().as_micros() as u64;
    {
        let mut progress = lock_progress(inner);
        if let Err(error) = &committed {
            inner.channel.diagnose(
                &progress,
                Instant::now(),
                "history_store",
                crate::HistoryFault::WriteFailed,
                &safe_error_reasons(error),
            );
        }
        progress.saving_revision = 0;
        progress.enter_stage(Some(HistoryStage::WriterQueue), Instant::now());
    }
    if let Err(error) = committed {
        tracing::debug!(
            target: "conversation_work",
            thread_id = inner.thread.id,
            batch_effects = effects.len(),
            prepared_elapsed_us = database_started.duration_since(started).as_micros() as u64,
            database_elapsed_us,
            success = false,
            error = %error,
            "append-only history batch"
        );
        return Err(error.into());
    }

    let confirmation_started = Instant::now();
    inner
        .conversation
        .confirm_committed(&CommittedBatch { database_id })?;
    for (effect, candidate) in effects.iter().zip(candidates) {
        super::super::state::clear_checkpoint_recovery(&inner.thread.id);
        inner.store.calls().record_effect(&effect.write.effect);
        let mut progress = lock_progress(inner);
        if candidate.summary.applied_sequence >= progress.usage.applied_sequence {
            inner
                .store
                .thread_persistence()
                .set_usage(&inner.thread.id, candidate.summary.clone());
            progress.usage = candidate.summary;
        }
        if candidate.revision >= progress.published_revision {
            progress.pressure_paused = candidate.pressure_paused;
        }
        progress.published_revision = progress.published_revision.max(candidate.revision);
    }
    inner
        .channel
        .order_index
        .confirm_saved(effects.last().expect("nonempty batch").sequence);
    let mut progress = lock_progress(inner);
    progress.in_flight_bytes = 0;
    report(inner, &progress);
    tracing::debug!(
        target: "conversation_work",
        thread_id = inner.thread.id,
        batch_effects = effects.len(),
        first_effect = effects.first().expect("nonempty batch").sequence,
        last_effect = effects.last().expect("nonempty batch").sequence,
        prepared_elapsed_us = database_started.duration_since(started).as_micros() as u64,
        database_elapsed_us,
        confirmation_elapsed_us = confirmation_started.elapsed().as_micros() as u64,
        success = true,
        "append-only history batch"
    );
    Ok(())
}

#[cfg(test)]
pub(super) async fn persist_one(
    inner: &Inner,
    sequence: u64,
    write: &HistoryExport,
    prepared: &PreparedEffect,
    bytes: u64,
) -> Result<()> {
    persist(
        inner,
        &[Effect {
            sequence,
            write: Arc::new(write.clone()),
            prepared: Arc::new(prepared.clone()),
            bytes,
        }],
    )
    .await
}
