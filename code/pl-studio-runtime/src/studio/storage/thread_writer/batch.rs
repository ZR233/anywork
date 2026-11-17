//! Private scheduling and append-only history candidates over the original reliable queue.
//!
//! The queue still owns Core admission pressure and shutdown ordering. At a selected cut it
//! converts already-published immutable product facts to schema-25 events, accepts each complete
//! `PreparedEffect` in RAM as one cut, then flushes that prefix. It never reads, fences, or
//! acknowledges `current.json`.

use super::*;
use crate::history::{
    HistoryEvent, HistoryEventKind, HistoryRowHead, HistoryUsageFact, PreparedHistoryUsage,
};
use pl_core::usage::UsageOutcome;
use std::collections::BTreeSet;

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
    /// Row anchors already prepared in this effect but not yet published.
    anchors: BTreeSet<String>,
    /// Candidate classifier state matching `events`; published only after acceptance.
    classifier: Option<crate::history::HistoryClassifier>,
    basic_done: bool,
    classifier_changes: usize,
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
        match prefix {
            "parent_report" => "pl.studio.parent-report",
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

#[derive(Clone)]
struct EffectStateSnapshot {
    basic_done: bool,
    classifier_changes: usize,
    usage_done: bool,
    complete: bool,
    classifier: Option<crate::history::HistoryClassifier>,
    anchors: BTreeSet<String>,
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
        basic_done: state.basic_done,
        classifier_changes: state.classifier_changes,
        usage_done: state.usage_done,
        complete: state.complete,
        classifier: state.classifier.clone(),
        anchors: state.anchors.clone(),
        frozen_events: state.frozen_events.clone(),
    })
}

fn retain_prepared_event(state: &mut PreparedEffectState, event: HistoryEvent) {
    if event.is_anchor
        && let Some(row) = &event.header.row_key
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
    state.basic_done = true;
    Ok(())
}

fn append_classifier_events(
    inner: &Inner,
    index: usize,
    next_change: usize,
    events: Vec<HistoryEvent>,
    classifier: crate::history::HistoryClassifier,
) -> Result<()> {
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
        state.classifier_changes == next_change,
        "history classifier preparation changed concurrently"
    );
    for event in events {
        retain_prepared_event(state, event);
    }
    state.classifier = Some(classifier);
    state.classifier_changes = next_change + 1;
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

fn classifier_for_run(
    inner: &Inner,
    index: usize,
    run: &str,
) -> Result<crate::history::HistoryClassifier> {
    ensure_effect_state(inner, index)?;
    if let Some(classifier) = effect_state(inner, index)?.classifier {
        return Ok(classifier);
    }
    let classifier = {
        let shared = inner
            .channel
            .history_classifier
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match shared.as_ref() {
            Some(classifier) if classifier.run_matches(run) => classifier.clone(),
            _ => crate::history::HistoryClassifier::from_run_id(run)?,
        }
    };
    {
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
            state.classifier.is_none(),
            "history classifier was set twice"
        );
        state.classifier = Some(classifier.clone());
    }
    Ok(classifier)
}

fn publish_classifier(inner: &Inner, classifier: crate::history::HistoryClassifier) {
    *inner
        .channel
        .history_classifier
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(classifier);
}

async fn prepare_basic_events(
    inner: &Inner,
    history: &HistoryStore,
    effect: &Effect,
    recorded_at: i64,
    run: &str,
) -> Result<Vec<HistoryEvent>> {
    let prepared = &effect.prepared;
    let mut events = Vec::new();
    let run_candidate = run_event(run, recorded_at);
    let mut append_run = false;
    match history
        .reader()
        .read_event(
            run_candidate.header.event_id.clone(),
            crate::history::HistoryDemand {
                max_rows: 1,
                max_bytes: 4096,
            },
        )
        .await
    {
        Ok(existing) => {
            let mut expected = run_candidate.header.clone();
            expected.seq = existing.header.seq;
            expected.recorded_at = existing.header.recorded_at;
            ensure!(
                existing.header == expected
                    && existing.payload_ref.is_none()
                    && existing.head.is_none()
                    && existing.owned_manifest_event_id.is_none(),
                "run start identity conflicts"
            );
        }
        Err(crate::history::HistoryError::NotFound(_)) => append_run = true,
        Err(error) => return Err(error.into()),
    }
    if append_run {
        events.push(run_candidate);
    }
    events.extend(crate::history::input_events(
        &prepared.history_inputs,
        run,
        prepared.sequence,
        recorded_at,
    )?);

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
            recorded_at,
            false,
        ));
    }
    for fact in prepared.review_delivery.iter() {
        events.push(delivery_event(
            &inner.thread.id,
            "review_delivery",
            &fact.message.id,
            serde_json::to_string(fact)?,
            prepared.run_id,
            recorded_at,
            false,
        ));
    }
    for fact in prepared.retained_resources.iter() {
        events.push(crate::studio::history_resources::observed_event(
            &fact.reference,
            run,
            &fact.call_id,
            fact.turn_id.as_deref(),
            prepared.sequence,
            recorded_at,
        )?);
    }
    for (turn, anchor) in prepared.history_turns.iter().zip(turn_anchors) {
        let mut event = turn_event(
            turn,
            prepared.history_turn_details.get(&turn.turn_id),
            recorded_at,
            anchor,
        )?;
        event.header.event_id = format!("turn:{}:{}:{}", run, turn.turn_id, prepared.sequence);
        if let Some(HistoryRowHead::Turn(head)) = &mut event.head
            && head.detail_event_id.is_some()
        {
            head.detail_event_id = Some(event.header.event_id.clone());
        }
        events.push(event);
    }
    for (source, anchor) in prepared.history_sources.iter().zip(source_anchors) {
        events.push(source_event(source, recorded_at, anchor)?);
    }
    Ok(events)
}

async fn prepare_classifier_change(
    history: &HistoryStore,
    admission: &tokio::sync::MutexGuard<'_, ()>,
    change: &crate::history::HistoryEntityChange,
    inputs: &std::collections::BTreeMap<
        String,
        crate::studio::thread_projection::HistoryObservationInput,
    >,
    classifier: &crate::history::HistoryClassifier,
    local_anchors: &BTreeSet<String>,
) -> Result<(Vec<HistoryEvent>, crate::history::HistoryClassifier)> {
    let mut change = change.clone();
    let anchors = classifier
        .resolve_record_anchors(admission, history, &change, local_anchors)
        .await?;
    if anchors.requires_boundary_observation(&change) {
        for entity in classifier.boundary_entities() {
            let observed = inputs
                .get(entity)
                .with_context(|| format!("boundary has no producer cut for {entity}"))?;
            change
                .boundary_observations
                .push(observed.freeze(&change.event, history.database_id())?);
        }
    }
    Ok(classifier.build_record(&change, anchors, history.database_id())?)
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
        let classifier = classifier_for_run(inner, index, &run)?;
        ensure!(
            classifier.run_matches(&run),
            "prepared effect changed runtime epoch during history admission"
        );
        if !effect_state(inner, index)?.basic_done {
            let events = prepare_basic_events(inner, history, effect, recorded_at, &run).await?;
            append_basic_events(inner, index, events)?;
        }

        loop {
            let snapshot = effect_state(inner, index)?;
            if snapshot.classifier_changes >= prepared.history_changes.len() {
                break;
            }
            let classifier = snapshot
                .classifier
                .context("history classifier preparation state is missing")?;
            let change = &prepared.history_changes[snapshot.classifier_changes];
            let (events, candidate) = prepare_classifier_change(
                history,
                &admission,
                change,
                &prepared.boundary_inputs,
                &classifier,
                &snapshot.anchors,
            )
            .await?;
            append_classifier_events(inner, index, snapshot.classifier_changes, events, candidate)?;
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
                    event_id: format!("usage:{}:{}", run, fact.record.inference_id),
                    runtime_epoch: prepared.run_id,
                    turn_id: prepared.accounting.primary_turn_id().map(str::to_owned),
                    outcome,
                    record: fact.record.clone(),
                });
            }
            let usage = history.prepare_usage(&admission, &facts).await?;
            append_usage_events(inner, index, usage)?;
        }
        complete_effect(inner, index)?;
    }

    let events = effect_state(inner, index)?
        .frozen_events
        .context("complete history effect has no frozen events")?;
    let mut accepted = history.accept_locked(&admission, &events).await;
    if matches!(accepted, Err(crate::history::HistoryError::Capacity)) {
        // Flush only batches that were already accepted as complete effects. The admission guard
        // stays held so another producer cannot change anchors or accounting totals between the
        // failure and the retry of this identical vector.
        history.flush().await?;
        accepted = history.accept_locked(&admission, &events).await;
    }
    accepted.map_err(anyhow::Error::new)?;
    drop(admission);

    if let Some(classifier) = effect_state(inner, index)?.classifier {
        publish_classifier(inner, classifier);
    }
    mark_effect_accepted(inner, index)
}

pub(super) async fn persist(inner: &Inner, effects: &[Effect]) -> Result<()> {
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
        admit_effect(inner, &history, effect, index).await?;
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
    Ok(())
}
