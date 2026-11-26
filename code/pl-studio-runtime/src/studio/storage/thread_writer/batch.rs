//! Private scheduling and append-only history candidates over the original reliable queue.
//!
//! The queue still owns Core admission pressure and shutdown ordering. At a selected cut it
//! converts already-published immutable product facts to schema-26 events, accepts each complete
//! `PreparedEffect` in RAM as one cut, then flushes that prefix. It never reads, fences, or
//! acknowledges `current.json`.

use super::*;
use crate::history::{HistoryEvent, HistoryUsageFact, PreparedHistoryUsage};
use pl_core::usage::UsageOutcome;
use std::collections::BTreeSet;

pub(crate) mod events;

pub(crate) use events::{
    BatchWriteContext, delivery_event, millis, run_event, source_event, turn_event,
};

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
    usage: UsageSummary,
    /// Complete `PreparedEffect`s whose atomic History acceptance already succeeded.
    accepted_effects: usize,
    /// Resumable preparation state for effects in this frozen queue prefix.
    prepared_effects: Vec<PreparedEffectState>,
}

#[derive(Debug, Default)]
struct PreparedEffectState {
    /// Candidate bytes accumulated for the effect's next atomic acceptance.
    events: Vec<HistoryEvent>,
    basic_count: usize,
    usage_revision: Option<u64>,
    /// Row anchors already prepared in this effect but not yet published.
    anchors: BTreeSet<String>,
    basic_done: bool,
    usage_done: bool,
    complete: bool,
    frozen_events: Option<Arc<[HistoryEvent]>>,
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
            usage: progress.usage.clone(),
            accepted_effects: 0,
            prepared_effects: Vec::new(),
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

#[derive(Clone)]
struct EffectStateSnapshot {
    usage_revision: Option<u64>,
    basic_done: bool,
    usage_done: bool,
    complete: bool,
    frozen_events: Option<Arc<[HistoryEvent]>>,
}

fn ensure_effect_state(inner: &Inner, index: usize) -> Result<()> {
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("history prefix was not selected")?;
    ensure!(
        index < batch.count,
        "history effect index is outside the frozen prefix"
    );
    if batch.prepared_effects.len() == index {
        batch.prepared_effects.push(PreparedEffectState::default());
    }
    ensure!(
        batch.prepared_effects.len() > index,
        "history effect preparation has a missing slot"
    );
    Ok(())
}

fn effect_state(inner: &Inner, index: usize) -> Result<EffectStateSnapshot> {
    let progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_ref()
        .context("history prefix was not selected")?;
    let state = batch
        .prepared_effects
        .get(index)
        .context("history effect preparation slot disappeared")?;
    Ok(EffectStateSnapshot {
        usage_revision: state.usage_revision,
        basic_done: state.basic_done,
        usage_done: state.usage_done,
        complete: state.complete,
        frozen_events: state.frozen_events.clone(),
    })
}

fn retain_prepared_event(state: &mut PreparedEffectState, event: HistoryEvent) {
    if event.is_anchor
        && let Some(row) = &event.row_key
    {
        state.anchors.insert(row.clone());
    }
    state.events.push(event);
}

fn append_basic_events(inner: &Inner, index: usize, events: Vec<HistoryEvent>) -> Result<()> {
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("history prefix was not selected")?;
    let state = batch
        .prepared_effects
        .get_mut(index)
        .context("history effect preparation slot disappeared")?;
    ensure!(!state.basic_done, "history basic effect was prepared twice");
    for event in events {
        retain_prepared_event(state, event);
    }
    state.basic_count = state.events.len();
    state.basic_done = true;
    Ok(())
}

fn append_usage_events(inner: &Inner, index: usize, prepared: PreparedHistoryUsage) -> Result<()> {
    ensure!(
        prepared.accepted_sequence.is_none(),
        "prepared effect cannot skip usage admission"
    );
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("history prefix was not selected")?;
    let state = batch
        .prepared_effects
        .get_mut(index)
        .context("history effect preparation slot disappeared")?;
    ensure!(!state.usage_done, "history usage effect was prepared twice");
    state.usage_revision = Some(prepared.usage_revision);
    for event in prepared.events {
        retain_prepared_event(state, event);
    }
    state.usage_done = true;
    Ok(())
}

fn complete_effect(inner: &Inner, index: usize) -> Result<()> {
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("history prefix was not selected")?;
    let state = batch
        .prepared_effects
        .get_mut(index)
        .context("history effect preparation slot disappeared")?;
    ensure!(
        state.basic_done && state.usage_done && !state.complete,
        "history effect preparation is incomplete or already complete"
    );
    state.frozen_events = Some(std::mem::take(&mut state.events).into());
    state.complete = true;
    Ok(())
}

// A stale cumulative projection was never accepted. Keep immutable basic facts and body
// identities, then derive usage again from its original facts on the next writer attempt.
fn reset_usage_preparation(inner: &Inner, index: usize) -> Result<()> {
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("history prefix was not selected")?;
    let state = batch
        .prepared_effects
        .get_mut(index)
        .context("history effect preparation slot disappeared")?;
    let frozen = state
        .frozen_events
        .take()
        .context("stale usage had no frozen events")?;
    state.events = frozen[..state.basic_count].to_vec();
    state.anchors = state
        .events
        .iter()
        .filter(|event| event.is_anchor)
        .filter_map(|event| event.row_key.clone())
        .collect();
    state.usage_revision = None;
    state.usage_done = false;
    state.complete = false;
    Ok(())
}

fn accepted_effects(inner: &Inner) -> Result<usize> {
    let progress = lock_progress(inner);
    Ok(progress
        .in_flight
        .as_ref()
        .context("history prefix was not selected")?
        .accepted_effects)
}

fn mark_effect_accepted(inner: &Inner, index: usize) -> Result<()> {
    let mut progress = lock_progress(inner);
    let batch = progress
        .in_flight
        .as_mut()
        .context("history prefix was not selected")?;
    ensure!(
        batch.accepted_effects == index,
        "history effect acceptance is out of order"
    );
    let state = batch
        .prepared_effects
        .get(index)
        .context("history effect preparation slot disappeared")?;
    ensure!(state.complete, "history effect was not completely prepared");
    batch.accepted_effects = index + 1;
    Ok(())
}

async fn prepare_basic_events(
    inner: &Inner,
    history: &HistoryStore,
    effect: &Effect,
    recorded_at: i64,
    run: &str,
) -> Result<Vec<HistoryEvent>> {
    let prepared = &effect.prepared;
    let database_id = history.database_id();
    let mut events = Vec::new();
    let run_candidate = run_event(run, recorded_at)?;
    let mut append_run = false;
    if !history.event_exists_in_memory(&run_candidate.event_id) {
        append_run = true;
    } else {
        match history
            .reader()
            .read_event(
                run_candidate.event_id.clone(),
                crate::history::HistoryDemand {
                    max_rows: 1,
                    max_bytes: 4096,
                },
            )
            .await
        {
            Ok(existing) => {
                ensure!(
                    existing.event_id == run_candidate.event_id
                        && existing.kind == run_candidate.kind
                        && existing.timeline_role == run_candidate.timeline_role
                        && existing.run_id == run_candidate.run_id
                        && existing.payload_schema == run_candidate.payload_schema
                        && existing.payload_json == run_candidate.payload_json,
                    "run start identity conflicts"
                );
            }
            Err(crate::history::HistoryError::NotFound(_)) => append_run = true,
            Err(error) => return Err(error.into()),
        }
    }
    if append_run {
        events.push(run_candidate);
    }
    // Resolve every anchor predicate before allocating body IDs. Cancellation can then occur only
    // before this stage's immutable producer bytes exist; once they exist they are retained below.
    let mut local_anchors = BTreeSet::new();
    let mut turn_anchors = Vec::with_capacity(prepared.history_turns.len());
    for turn in prepared.history_turns.iter() {
        let row = format!("turn:{}", turn.turn_id);
        let anchor = !local_anchors.contains(&row) && !history.anchor_exists(&row).await?;
        turn_anchors.push(anchor);
        if anchor {
            local_anchors.insert(row);
        }
    }
    let mut source_anchors = Vec::with_capacity(prepared.history_sources.len());
    for source in prepared.history_sources.iter() {
        let identity = serde_json::to_string(&source.source)?;
        let row = format!("source:{identity}");
        let anchor = !local_anchors.contains(&row) && !history.anchor_exists(&row).await?;
        source_anchors.push(anchor);
        if anchor {
            local_anchors.insert(row);
        }
    }

    if let Some(report) = &prepared.parent_report {
        events.push(delivery_event(
            &inner.thread.id,
            "parent_report",
            &report.id,
            serde_json::to_string(report)?,
            prepared.run_id,
            BatchWriteContext {
                recorded_at,
                anchor: false,
                database_id,
            },
        )?);
    }
    for fact in prepared.review_delivery.iter() {
        events.push(delivery_event(
            &inner.thread.id,
            "review_delivery",
            &fact.message.id,
            serde_json::to_string(fact)?,
            prepared.run_id,
            BatchWriteContext {
                recorded_at,
                anchor: false,
                database_id,
            },
        )?);
    }
    for fact in prepared.retained_resources.iter() {
        events.push(crate::studio::history_resources::observed_event(
            &fact.reference,
            run,
            &fact.call_id,
            fact.turn_id.as_deref(),
            prepared.sequence,
            recorded_at,
            database_id,
        )?);
    }
    for (turn, anchor) in prepared.history_turns.iter().zip(turn_anchors) {
        let event = turn_event(
            format!("turn:{}:{}:{}", run, turn.turn_id, prepared.sequence),
            turn,
            prepared.history_turn_details.get(&turn.turn_id),
            recorded_at,
            anchor,
            database_id,
        )?;
        events.push(event);
    }
    for (source, anchor) in prepared.history_sources.iter().zip(source_anchors) {
        let (continuation_payload, entity_override, run_override, turn_override) =
            if let crate::HistorySource::Operation { operation_id } = &source.source
                && let Some(operation) = effect
                    .write
                    .effect
                    .continuations
                    .iter()
                    .find(|operation| &operation.request.operation_id == operation_id)
            {
                let payload = pl_core::context::OpaquePayload::new(
                    "pl.core.resume-operation",
                    1,
                    serde_json::to_string(operation)?,
                )?;
                (
                    Some(serde_json::to_vec(&payload)?),
                    Some(operation_id.as_str()),
                    Some(operation.acceptance_epoch.to_string()),
                    Some(operation.turn_id.clone()),
                )
            } else {
                (None, None, None, None)
            };
        let event = source_event(
            source,
            continuation_payload,
            entity_override,
            run_override,
            turn_override,
            BatchWriteContext {
                recorded_at,
                anchor,
                database_id,
            },
        )?;
        events.push(event);
    }
    events.extend(prepared.history_events.iter().cloned());
    Ok(events)
}

async fn admit_effect(
    inner: &Inner,
    history: &HistoryStore,
    effect: &Effect,
    index: usize,
) -> Result<()> {
    let prepared = &effect.prepared;
    let recorded_at = millis(prepared.committed_at)?;
    let run = prepared.run_id.to_string();
    let admission = history.admission_guard().await;
    ensure_effect_state(inner, index)?;
    if !effect_state(inner, index)?.complete {
        if !effect_state(inner, index)?.basic_done {
            let events = prepare_basic_events(inner, history, effect, recorded_at, &run).await?;
            append_basic_events(inner, index, events)?;
        }

        if !effect_state(inner, index)?.usage_done {
            let mut facts = Vec::with_capacity(prepared.accounting.facts.len());
            for fact in prepared.accounting.facts.iter() {
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
                facts.push(HistoryUsageFact {
                    event_id: format!("usage:settlement:{}", fact.record.inference_id),
                    runtime_epoch: prepared.run_id,
                    turn_id: fact.turn_id.clone(),
                    outcome,
                    record: fact.record.clone(),
                    settlement: Some(fact.settlement.clone()),
                });
            }
            let usage = history.prepare_usage(&admission, &facts).await?;
            append_usage_events(inner, index, usage)?;
        }
        complete_effect(inner, index)?;
    }

    let state = effect_state(inner, index)?;
    let usage_revision = state
        .usage_revision
        .unwrap_or_else(|| admission.usage_revision());
    let events = state
        .frozen_events
        .context("complete history effect has no frozen events")?;
    let mut accepted = history
        .accept_locked_at_revision(&admission, &events, usage_revision)
        .await;
    if matches!(accepted, Err(crate::history::HistoryError::Capacity)) {
        history.flush().await?;
        accepted = history
            .accept_locked_at_revision(&admission, &events, usage_revision)
            .await;
    }
    if accepted
        .as_ref()
        .is_err_and(crate::history::HistoryError::is_usage_preparation_changed)
    {
        reset_usage_preparation(inner, index)?;
    }
    accepted.map_err(anyhow::Error::new)?;
    drop(admission);

    mark_effect_accepted(inner, index)
}

pub(super) async fn persist(inner: &Inner, effects: &[Effect]) -> Result<HistoryStore> {
    ensure!(!effects.is_empty(), "cannot persist an empty history batch");
    let started = Instant::now();
    let mut summary = {
        let progress = lock_progress(inner);
        ensure!(
            progress
                .in_flight
                .as_ref()
                .is_some_and(|batch| batch.count == effects.len()),
            "history effects changed after the prefix was frozen"
        );
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
        candidates.push(summary.clone());
    }
    {
        let mut progress = lock_progress(inner);
        progress.in_flight_bytes = effects.iter().map(|effect| effect.bytes).sum();
        report(inner, &progress);
    }

    let history = history_store(inner).await?;
    let database_id = history.database_id().to_owned();
    for (index, effect) in effects.iter().enumerate() {
        let accepted = accepted_effects(inner)?;
        ensure!(
            accepted <= effects.len(),
            "history effect acceptance is ahead of the frozen prefix"
        );
        if index < accepted {
            continue;
        }
        ensure_effect_state(inner, index)?;
        if effect.prepared.bus_admitted {
            if let Some(report) = &effect.prepared.parent_report {
                if !effect_state(inner, index)?.complete {
                    let events = vec![delivery_event(
                        &inner.thread.id,
                        "parent_report",
                        &report.id,
                        serde_json::to_string(report)?,
                        effect.prepared.run_id,
                        BatchWriteContext {
                            recorded_at: millis(effect.prepared.committed_at)?,
                            anchor: false,
                            database_id: &database_id,
                        },
                    )?];
                    append_basic_events(inner, index, events)?;
                    append_usage_events(
                        inner,
                        index,
                        PreparedHistoryUsage {
                            events: Vec::new(),
                            accepted_sequence: None,
                            usage_revision: history.memory_admission_revision(),
                        },
                    )?;
                    complete_effect(inner, index)?;
                }
                let events = effect_state(inner, index)?
                    .frozen_events
                    .context("parent report events were not frozen")?;
                let mut accepted = history.accept_batch(&events).await;
                if matches!(accepted, Err(crate::history::HistoryError::Capacity)) {
                    history.flush().await?;
                    accepted = history.accept_batch(&events).await;
                }
                accepted.map_err(anyhow::Error::new)?;
            } else if !effect_state(inner, index)?.complete {
                append_basic_events(inner, index, Vec::new())?;
                append_usage_events(
                    inner,
                    index,
                    PreparedHistoryUsage {
                        events: Vec::new(),
                        accepted_sequence: None,
                        usage_revision: history.memory_admission_revision(),
                    },
                )?;
                complete_effect(inner, index)?;
            }
            mark_effect_accepted(inner, index)?;
        } else {
            admit_effect(inner, &history, effect, index).await?;
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
        return Err(error);
    }

    let confirmation_started = Instant::now();
    inner
        .conversation
        .confirm_committed(&CommittedBatch { database_id })?;
    for (effect, candidate) in effects.iter().zip(candidates) {
        inner.store.calls().record_effect(&effect.write.effect);
        let mut progress = lock_progress(inner);
        if candidate.applied_sequence >= progress.usage.applied_sequence {
            inner
                .store
                .thread_persistence()
                .set_usage(&inner.thread.id, candidate.clone());
            progress.usage = candidate;
        }
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
    Ok(history)
}
