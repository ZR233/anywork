//! Private scheduling and transaction candidates over the original reliable queue.

use super::*;
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
                && projected.current.projection.source_effect_seq == sequence,
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
    let committed = history.commit_checkpoint_effects(&commits).await;
    lock_progress(inner).saving_revision = 0;
    let accounting = committed?;
    ensure!(
        accounting.len() == effects.len(),
        "history batch accounting result length differs"
    );
    // There are no await points in local settlement. On a rejected transaction none of these
    // actions run; on an interrupted acknowledgement the frozen prefix/baseline is retried.
    for ((effect, candidate), accounting) in effects.iter().zip(candidates).zip(accounting) {
        if let Some(last) = effect.prepared.completions.last() {
            inner.chat.confirm_durable(last.header.append_seq)?;
        }
        inner.channel.order_index.confirm_saved(effect.sequence);
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
    let mut progress = lock_progress(inner);
    progress.in_flight_bytes = 0;
    report(inner, &progress);
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
