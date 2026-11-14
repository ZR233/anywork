//! Private scheduling and transaction candidates over the original reliable queue.

use super::*;

/// 只能由本 writer 在真实事务成功后构造的确认区间。
pub(in crate::studio) struct CommittedBatch {
    database_id: String,
    effect: u64,
    append_seq: Option<u64>,
    display: Option<(u64, u64, u64)>,
}

impl CommittedBatch {
    pub(in crate::studio) fn database_id(&self) -> &str {
        &self.database_id
    }
    pub(in crate::studio) fn effect(&self) -> u64 {
        self.effect
    }
    pub(in crate::studio) fn display(&self) -> Option<(u64, u64, u64)> {
        self.display
    }
    pub(in crate::studio) fn append_seq(&self) -> Option<u64> {
        self.append_seq
    }
}
use crate::studio::storage::history::{CheckpointEffect, FactReceiptWrite};

const WINDOW: Duration = Duration::from_millis(20);
const MAX_EFFECTS: usize = 64;
const MAX_BYTES: u64 = 1024 * 1024;

#[derive(Debug)]
pub(super) struct FrozenBatch {
    count: usize,
    first: u64,
    last: u64,
    /// Reuse this baseline even if SQLite succeeded but local acknowledgement was interrupted.
    usage: UsageSummary,
}

pub(super) struct Effect {
    pub(super) sequence: u64,
    pub(super) write: Arc<ThreadWrite>,
    pub(super) prepared: Arc<PreparedEffect>,
    bytes: u64,
}

pub(super) enum Selection {
    Idle,
    Wait(Instant),
    Ready(Vec<Effect>),
}

/// Called under progress and step_lock. Only immutable queue handles escape the progress lock;
/// the queue, not this temporary view, owns every obligation until local acknowledgement.
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
            // An admitted oversize effect can form its own transaction, never starve.
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
            || progress.fault == Some(pl_protocol::studio::HistoryFault::QueueFull)
            || progress.effects.len() >= MAX_HISTORY_BATCHES
            || progress.effect_bytes >= MAX_HISTORY_THREAD_BYTES
            || process_bytes >= MAX_HISTORY_PROCESS_BYTES;
        // A known unprepared gap must not wait for the next handoff: that handoff can itself
        // depend on this prefix being durable. The window only collects a genuinely open tail.
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
    debug_assert_eq!(
        selected.first().map(|effect| effect.sequence),
        Some(frozen.first)
    );
    debug_assert_eq!(
        selected.last().map(|effect| effect.sequence),
        Some(frozen.last)
    );
    Selection::Ready(selected)
}

struct Candidate {
    checkpoint: ThreadCheckpoint,
    summary: UsageSummary,
    accounting_changed: bool,
    rolled_back: std::collections::BTreeSet<String>,
    identities: Vec<InputIdentityWrite>,
    messages: Vec<MessageIdentityWrite>,
    receipts: Vec<FactReceiptWrite>,
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
        let sequence = effect.sequence;
        ensure!(
            projected.sequence == sequence
                && projected.accounting.sequence == sequence
                && projected.accounting.thread_id == inner.thread.id
                && projected.current.projection().source_effect_seq == sequence,
            "prepared history batch {sequence} has inconsistent handoff identities"
        );
        let before = summary.pricing.clone();
        projected.accounting.fold_into(&mut summary);
        let mut checkpoint = effect.write.checkpoint.clone();
        checkpoint.state.usage_summary = summary.clone();
        #[cfg(feature = "benchmarks")]
        inner
            .store
            .calls()
            .observation()
            .increment(BenchMetric::ReceiptExtraction);
        candidates.push(Candidate {
            checkpoint,
            summary: summary.clone(),
            accounting_changed: before != summary.pricing,
            rolled_back: rolled_back_turns(&effect.write.checkpoint.state),
            identities: durable_input_identities(&inner.thread.id, &effect.write.checkpoint.state),
            messages: admitted_message_identities(&effect.write.effect),
            receipts: fact_receipts(&effect.write.effect, projected)?,
        });
    }
    {
        let mut progress = lock_progress(inner);
        progress.in_flight_bytes = effects.iter().map(|effect| effect.bytes).sum();
        progress.saving_revision = candidates
            .last()
            .expect("nonempty batch")
            .checkpoint
            .state_revision;
        report(inner, &progress);
    }
    // Every candidate's references must cross the fence before any history/current is published.
    for candidate in &candidates {
        let referenced = crate::studio::thread_projection::referenced_attachment_ids(
            &candidate.checkpoint.state,
        );
        inner
            .store
            .blob_fence(&inner.thread.id, &referenced)
            .await
            .map_err(|error| classified(pl_protocol::studio::HistoryFault::BlobFailed, error))?;
    }
    let history = history_store(inner).await?;
    let database_id = history
        .conversation_database_id()
        .await?
        .context("writer database identity is missing")?;
    let commits: Vec<_> = effects
        .iter()
        .zip(&candidates)
        .map(|(effect, candidate)| CheckpointEffect {
            checkpoint: &candidate.checkpoint,
            effect: &effect.write.effect,
            history: EffectCommit {
                items: &effect.prepared.items,
                completions: &effect.prepared.completions,
                current: &effect.prepared.current,
                rolled_back_turns: &candidate.rolled_back,
                identities: &candidate.identities,
                messages: &candidate.messages,
                receipts: &candidate.receipts,
                tasks: &effect.write.effect.tasks,
                deliveries: &effect.write.effect.deliveries,
                delivery_repairs: &effect.write.effect.delivery_repairs,
                attempt: effect.write.effect.attempt.as_ref(),
            },
            accounting: AccountingCommit {
                facts: &effect.prepared.accounting,
                material_changed: candidate.accounting_changed,
            },
        })
        .collect();
    let database_started = Instant::now();
    let prepared_elapsed_us = database_started.duration_since(started).as_micros() as u64;
    lock_progress(inner).enter_stage(Some(HistoryStage::SqlCommit), database_started);
    #[cfg(not(test))]
    let committed = history.commit_checkpoint_effects(&commits).await;
    #[cfg(test)]
    let committed = {
        // Observe a real pending HistoryStore call. Tests may hold SQLite's write lock; this
        // hook neither substitutes persistence nor pretends that dropping a future cancels SQL.
        let commit = history.commit_checkpoint_effects(&commits);
        tokio::pin!(commit);
        std::future::poll_fn(|cx| {
            let polled = commit.as_mut().poll(cx);
            if polled.is_pending()
                && let Some(entered) = inner
                    .channel
                    .sql_pending
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .take()
            {
                let _ = entered.send(());
            }
            polled
        })
        .await
    };
    let database_elapsed_us = database_started.elapsed().as_micros() as u64;
    {
        let mut progress = lock_progress(inner);
        if let Err(error) = &committed {
            inner.channel.diagnose(
                &progress,
                Instant::now(),
                "history_store",
                pl_protocol::studio::HistoryFault::WriteFailed,
                &safe_error_reasons(error),
            );
        }
        progress.saving_revision = 0;
        progress.enter_stage(Some(HistoryStage::WriterQueue), Instant::now());
    }
    if committed.is_err() {
        tracing::debug!(
            target: "conversation_work",
            thread_id = inner.thread.id,
            batch_effects = effects.len(),
            prepared_elapsed_us,
            database_elapsed_us,
            success = false,
            "history batch transaction"
        );
    }
    let accounting = committed?;
    let confirmation_started = Instant::now();
    ensure!(
        accounting.len() == effects.len(),
        "history batch accounting result length differs"
    );
    // There are no await points in local settlement. On a rejected transaction none of these
    // actions run; on an interrupted acknowledgement the frozen prefix/baseline is retried.
    let append_seq = effects
        .iter()
        .rev()
        .find_map(|effect| effect.prepared.completions.last())
        .map(|item| item.header.append_seq);
    inner.conversation.confirm_committed(&CommittedBatch {
        database_id,
        effect: effects.last().expect("nonempty batch").sequence,
        append_seq,
        display: effects
            .iter()
            .rev()
            .find_map(|effect| effect.prepared.display.as_ref())
            .map(|delta| (delta.effect_seq, delta.ready_frontier, delta.last_order)),
    })?;
    for ((effect, candidate), accounting) in effects.iter().zip(candidates).zip(accounting) {
        super::super::state::clear_checkpoint_recovery(&inner.thread.id);
        if let Some(accounting) = accounting {
            submit_accounting(inner, accounting);
        }
        // Calls are diagnostics, never part of the reliable transaction's success criterion.
        inner.store.calls().record_effect(&effect.write.effect);
        let mut progress = lock_progress(inner);
        // A replay after ACK loss still reconstructs each checkpoint from the frozen baseline,
        // but must not transiently publish an older running summary or pressure observation.
        if candidate.summary.applied_sequence >= progress.usage.applied_sequence {
            inner
                .store
                .thread_persistence()
                .set_usage(&inner.thread.id, candidate.summary.clone());
            progress.usage = candidate.summary;
        }
        if candidate.checkpoint.state_revision >= progress.published_revision {
            progress.pressure_paused = effect.write.checkpoint.state.persistence.pressure_paused;
        }
        progress.published_revision = progress
            .published_revision
            .max(candidate.checkpoint.state_revision);
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
        prepared_elapsed_us,
        database_elapsed_us,
        confirmation_elapsed_us = confirmation_started.elapsed().as_micros() as u64,
        success = true,
        "history batch transaction"
    );
    Ok(())
}

#[cfg(test)]
pub(super) async fn persist_one(
    inner: &Inner,
    sequence: u64,
    write: &ThreadWrite,
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
