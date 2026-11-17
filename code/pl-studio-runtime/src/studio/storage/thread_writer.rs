//! Per-Thread ordered persistence owner: each effect and its checkpoint commit in one transaction.
//!
//! Admission never blocks the executor. Effects are history facts, so every admitted batch is
//! written to `history.sqlite` in sequence order, each against the effect-matched
//! transfer state it arrived with. The matching checkpoint is not scheduled on its own: the writer
//! holds `write.checkpoint` as the candidate for exactly that effect and commits it together with
//! the effect's history facts, the latest context increment and the history watermark in one
//! `history.sqlite` transaction (`design/15` §15.5). A bounded coalescing window selects only the
//! prepared prefix of the original queue. A failed transaction keeps that prefix frozen for retry;
//! no second obligation queue or independently scheduled checkpoint exists.
//!
//! Publication order is fixed: every blob the checkpoint names must be durable first, and only then
//! is the transaction that writes the pruned checkpoint and advances the watermark committed. The
//! writer folds each effect's cumulative usage accounting exactly once, sets it on that effect's
//! checkpoint as `state.usage_summary`, and only publishes the running summary once the transaction
//! succeeded — so hot reads, reconnects and cold restores observe one cumulative value and a saved
//! checkpoint never carries a summary its own commit did not include.

use crate::ExecutionItem;
use std::{
    collections::{BTreeMap, VecDeque},
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::{Context, Result, ensure};
use pl_core::thread::{
    HistoryExport, ThreadCheckpoint, ThreadSnapshot, UsageSummary,
    cold::{ColdStore, ColdStoreError, StorageIdleStatus, StoragePressure, ThreadWrite},
};

use tokio::time::Instant;

use crate::history::{HistoryClassifier, HistoryStore};
use crate::studio::StudioStore;
use crate::studio::storage::calls::is_retryable_write;
use crate::studio::storage::coordinator::{
    PendingSequenceRange, ThreadPersistenceMetrics, ThreadPersistenceReport,
};
use crate::studio::thread_projection::PreparedEffect;

mod batch;
pub(in crate::studio) use batch::CommittedBatch;

#[cfg(feature = "benchmarks")]
pub(crate) mod benchmark;

#[cfg(feature = "benchmarks")]
use super::calls::observation::Metric as BenchMetric;

/// How long one writer incarnation may keep retrying a transient storage conflict before it must
/// report it.
///
/// A short `SQLITE_BUSY`/`SQLITE_LOCKED`/`SQLITE_IOERR` is a self-healing conflict: the accepted
/// effects stay queued in order and the same `step` writes them again, so surfacing the error would
/// turn a conflict that resolves on its own into a terminal persistence failure that blocks the
/// next model admission. Only a conflict that outlives this window — or a structural, constraint
/// or corruption error, which is never retried — is reported and keeps failing the drain.
const RETRYABLE_BUSY_WINDOW: Duration = Duration::from_secs(30);
const MAX_HISTORY_BATCHES: usize = 4096;
const MAX_HISTORY_THREAD_BYTES: u64 = 64 * 1024 * 1024;
const MAX_HISTORY_PROCESS_BYTES: u64 = 256 * 1024 * 1024;
const NO_PROGRESS_WINDOW: Duration = Duration::from_secs(60);
/// Conservative retained charge for the bounded age index entry owned by one queued effect.
const PENDING_AGE_METADATA_BYTES: u64 = std::mem::size_of::<(i64, u64)>() as u64 + 64;

/// Identity source for live per-Thread writer incarnations.
///
/// The coordinator keys its per-Thread watermarks by this value so a stopped writer can release
/// only its own state, and a replacement incarnation is never mistaken for the writer it replaced.
static NEXT_WRITER_INCARNATION: AtomicUsize = AtomicUsize::new(1);

/// The serial projection owner's charged residents. The pending batch is named so
/// that handing its same Arc to the reliable queue transfers its existing charge.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct ProjectionRetention {
    /// Projection/activity state and pending live events; excludes the prepared batch.
    pub resident_bytes: u64,
    pub pending: Option<PendingProjectionRetention>,
}

impl ProjectionRetention {
    fn total_bytes(self) -> u64 {
        self.resident_bytes
            .saturating_add(self.pending.map_or(0, |pending| pending.prepared_bytes))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct PendingProjectionRetention {
    pub sequence: u64,
    pub prepared_bytes: u64,
}

/// Moves already charged report content from the pending batch into the managed
/// terminal owner. Source validation and the net new charge share one boundary.
#[derive(Debug, Clone, Copy)]
pub(crate) struct ProjectionTransfer {
    pub source: PendingProjectionRetention,
    pub after: ProjectionRetention,
}

/// Borrowed execution metadata for one effect's single funded index commit.
/// Unknown placement is assigned only when every identity and stamp can fit.
#[derive(Clone, Copy)]
pub(in crate::studio) struct ExecutionMaterialization<'a> {
    pub item_id: &'a str,
    pub ordinal: Option<u64>,
    pub revision: u64,
    pub created_at: i64,
    pub updated_at: i64,
    pub turn_id: &'a str,
    pub terminal: bool,
}

impl<'a> ExecutionMaterialization<'a> {
    pub fn from_item(item: &'a ExecutionItem) -> Self {
        Self {
            item_id: &item.id,
            ordinal: (item.ordinal > 0).then_some(item.ordinal),
            revision: item.revision,
            created_at: item.created_at,
            updated_at: item.updated_at,
            turn_id: &item.turn_id,
            terminal: item.is_terminal(),
        }
    }
}

/// The Runtime-owned execution-order index of one Thread.
///
/// Execution ordinals place rows inside the Thread's internal `history_items` execution tables;
/// they are not completion `append_seq` values and never leave the Runtime. Two consumers share
/// one namespace: the kernel's synchronous `reserve_observed_item` callback (a provider
/// presentation identity is reserved before a coalescing preview can discard it, `design/15`
/// §15.5) and the live projection (an aggregate channel, input, tool or turn identity that first
/// appears in a commit or a preview frame). Both must draw from one allocator, or two independent
/// counters would hand the same number to two durable rows.
///
/// Its owning HistoryChannel shares this index with its projection and sink. Only active,
/// referenced or not-yet-saved identities reside here; the scalar ceiling never decreases.
pub(in crate::studio) struct RuntimeOrderIndex {
    inner: Mutex<OrderIndexState>,
    bytes: AtomicU64,
    /// Authoritative non-index/non-delivery residents, committed under `inner` by the channel.
    other_thread_bytes: AtomicU64,
    /// The shared delivery counter is read directly, including releases by managed guards.
    delivery_bytes: Arc<AtomicU64>,
    process_bytes: Arc<AtomicU64>,
    capacity_changed: Mutex<Option<tokio::sync::watch::Sender<u64>>>,
    #[cfg(test)]
    materialize_gate: Mutex<Option<MaterializeGate>>,
    #[cfg(test)]
    confirm_saved_entered: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    #[cfg(test)]
    confirm_saved_calls: AtomicU64,
}

#[cfg(test)]
struct MaterializeGate {
    entered: tokio::sync::oneshot::Sender<()>,
    release: std::sync::mpsc::Receiver<()>,
}

struct OrderIndexState {
    ceiling: u64,
    durable: u64,
    assigned: BTreeMap<String, ExecutionIdentity>,
    by_source: BTreeMap<String, std::collections::BTreeSet<String>>,
    pending: std::collections::BTreeSet<(u64, String)>,
    dirty: std::collections::BTreeSet<String>,
    /// An already admitted material owner failed to fund its next step; only an explicit
    /// successful owner measurement/transfer or retry can reopen optional allocations.
    resident_blocked: bool,
}

#[derive(Clone)]
struct ExecutionIdentity {
    ordinal: u64,
    source: Option<String>,
    source_ended: bool,
    effect: Option<u64>,
    retained: bool,
    terminal: bool,
    sealed: bool,
    /// When unsealed, absence was proved by admission or a history read; not publication.
    completion_checked: bool,
    stamp: Option<ExecutionStamp>,
}

#[derive(Clone, PartialEq, Eq)]
struct ExecutionStamp {
    revision: u64,
    created_at: i64,
    updated_at: i64,
    turn_id: String,
}

impl OrderIndexState {
    fn auxiliary_bytes(&self, id: &str, entry: &ExecutionIdentity) -> u64 {
        let mut bytes = if self.dirty.contains(id) {
            identity_key_bytes(id)
        } else {
            0
        };
        if entry
            .effect
            .is_some_and(|effect| self.pending.contains(&(effect, id.to_owned())))
        {
            bytes = bytes.saturating_add(pending_key_bytes(id));
        }
        if entry.source.is_some() && !entry.source_ended {
            bytes = bytes.saturating_add(identity_key_bytes(id));
        }
        bytes
    }
    fn index_identity(&mut self, id: &str, old_effect: Option<u64>) {
        if let Some(effect) = old_effect {
            self.pending.remove(&(effect, id.to_owned()));
        }
        let entry = &self.assigned[id];
        if let Some(source) = &entry.source
            && !entry.source_ended
        {
            self.by_source
                .entry(source.clone())
                .or_default()
                .insert(id.to_owned());
        }
        if let Some(effect) = entry.effect
            && effect > self.durable
        {
            self.pending.insert((effect, id.to_owned()));
        }
        self.dirty.insert(id.to_owned());
    }
    fn remove_identity(&mut self, id: &str) -> Option<(ExecutionIdentity, u64)> {
        let entry = self.assigned.remove(id)?;
        let mut bytes = entry.bytes(id);
        if let Some(effect) = entry.effect
            && self.pending.remove(&(effect, id.to_owned()))
        {
            bytes = bytes.saturating_add(pending_key_bytes(id));
        }
        if let Some(source) = &entry.source
            && let Some(ids) = self.by_source.get_mut(source)
        {
            if ids.remove(id) {
                bytes = bytes.saturating_add(identity_key_bytes(id));
            }
            if ids.is_empty() {
                self.by_source.remove(source);
                bytes = bytes.saturating_add(source_bucket_bytes(source));
            }
        }
        if self.dirty.remove(id) {
            bytes = bytes.saturating_add(identity_key_bytes(id));
        }
        Some((entry, bytes))
    }
}

#[derive(Debug, thiserror::Error)]
#[error("{scope} execution identity budget is full")]
struct ExecutionIndexBudgetFull {
    scope: &'static str,
}

impl ExecutionIdentity {
    fn bytes(&self, id: &str) -> u64 {
        (std::mem::size_of::<(String, ExecutionIdentity)>() as u64)
            .saturating_add(64)
            .saturating_add(id.len() as u64)
            .saturating_add(self.source.as_ref().map_or(0, |source| source.len() as u64))
            .saturating_add(
                self.stamp
                    .as_ref()
                    .map_or(0, |stamp| stamp.turn_id.len() as u64),
            )
    }
}

fn identity_key_bytes(id: &str) -> u64 {
    (std::mem::size_of::<String>() as u64)
        .saturating_add(64)
        .saturating_add(id.len() as u64)
}
fn pending_key_bytes(id: &str) -> u64 {
    (std::mem::size_of::<(u64, String)>() as u64)
        .saturating_add(64)
        .saturating_add(id.len() as u64)
}
fn source_bucket_bytes(source: &str) -> u64 {
    (std::mem::size_of::<(String, std::collections::BTreeSet<String>)>() as u64)
        .saturating_add(64)
        .saturating_add(source.len() as u64)
}

impl RuntimeOrderIndex {
    fn new(process_bytes: Arc<AtomicU64>, ceiling: u64) -> Self {
        Self::with_delivery(process_bytes, ceiling, Arc::new(AtomicU64::new(0)))
    }

    fn with_delivery(
        process_bytes: Arc<AtomicU64>,
        ceiling: u64,
        delivery_bytes: Arc<AtomicU64>,
    ) -> Self {
        Self {
            inner: Mutex::new(OrderIndexState {
                ceiling,
                durable: 0,
                assigned: BTreeMap::new(),
                by_source: BTreeMap::new(),
                pending: Default::default(),
                dirty: Default::default(),
                resident_blocked: false,
            }),
            bytes: AtomicU64::new(0),
            other_thread_bytes: AtomicU64::new(0),
            delivery_bytes,
            process_bytes,
            capacity_changed: Mutex::new(None),
            #[cfg(test)]
            materialize_gate: Mutex::new(None),
            #[cfg(test)]
            confirm_saved_entered: Mutex::new(None),
            #[cfg(test)]
            confirm_saved_calls: AtomicU64::new(0),
        }
    }

    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        self.bytes.load(Ordering::Acquire)
    }

    pub(in crate::studio) fn assigned(&self, item_id: &str) -> Option<u64> {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get(item_id)
            .map(|entry| entry.ordinal)
    }

    #[cfg(test)]
    pub(in crate::studio) fn assign(&self, item_id: &str) -> Result<u64> {
        self.allocate(item_id, None, None)
    }

    pub(in crate::studio) fn reserve_observed(
        &self,
        attempt_id: &str,
        item_id: &str,
    ) -> Result<u64> {
        self.allocate(item_id, Some(attempt_id), None)
    }

    fn allocate(&self, item_id: &str, source: Option<&str>, ordinal: Option<u64>) -> Result<u64> {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        self.allocate_locked(&mut state, item_id, source, ordinal)
    }

    /// Placement and actual auxiliary keys are funded together before mutation.
    fn allocate_locked(
        &self,
        state: &mut OrderIndexState,
        item_id: &str,
        source: Option<&str>,
        ordinal: Option<u64>,
    ) -> Result<u64> {
        if let Some(entry) = state.assigned.get(item_id) {
            ensure!(
                ordinal.is_none_or(|order| order == entry.ordinal),
                "execution ordinal conflict"
            );
            ensure!(
                source.is_none_or(|source| entry.source.as_deref().is_none_or(|old| old == source)),
                "execution observation source conflict"
            );
            let ordinal = entry.ordinal;
            if let Some(source) = source.filter(|_| entry.source.is_none()) {
                let mut entry = entry.clone();
                entry.source = Some(source.to_owned());
                entry.retained = true;
                self.commit_execution_batch(
                    state,
                    BTreeMap::from([(item_id.to_owned(), entry)]),
                    state.ceiling,
                )?;
            }
            return Ok(ordinal);
        }
        let order = ordinal
            .or_else(|| state.ceiling.checked_add(1))
            .filter(|order| *order <= i64::MAX as u64)
            .context("execution ordinal space is exhausted")?;
        let entry = ExecutionIdentity {
            ordinal: order,
            source: source.map(str::to_owned),
            source_ended: false,
            effect: None,
            retained: true,
            terminal: false,
            sealed: false,
            completion_checked: false,
            stamp: None,
        };
        self.commit_execution_batch(
            state,
            BTreeMap::from([(item_id.to_owned(), entry)]),
            state.ceiling.max(order),
        )?;
        Ok(order)
    }

    fn charge(&self, bytes: u64, blocked: bool) -> Result<()> {
        ensure!(
            !blocked || bytes == 0,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        ensure!(
            self.other_thread_bytes
                .load(Ordering::Acquire)
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(self.retained_bytes())
                .saturating_add(bytes)
                <= MAX_HISTORY_THREAD_BYTES,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        self.process_bytes
            .try_update(Ordering::AcqRel, Ordering::Acquire, |current| {
                current
                    .checked_add(bytes)
                    .filter(|total| *total <= MAX_HISTORY_PROCESS_BYTES)
            })
            .map_err(|_| ExecutionIndexBudgetFull { scope: "process" })?;
        self.bytes.fetch_add(bytes, Ordering::AcqRel);
        Ok(())
    }

    fn seed(&self, ceiling: u64, durable: u64) {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state.ceiling = state.ceiling.max(ceiling);
        state.durable = state.durable.max(durable);
    }

    /// Reserve only the explicit execution boundaries, before Core may reserve provider parts.
    /// This does not project content. The admitted effect owns these charged shells until its
    /// actual save, even if the projection is still processing an older checkpoint.
    #[cfg(test)]
    fn reserve_boundaries(
        &self,
        effect: &pl_core::thread::ThreadEffectBatch,
        additional_bytes: u64,
    ) -> Result<()> {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        self.reserve_boundaries_locked(&mut state, effect, additional_bytes)
    }

    fn reserve_boundaries_locked(
        &self,
        state: &mut OrderIndexState,
        effect: &pl_core::thread::ThreadEffectBatch,
        additional_bytes: u64,
    ) -> Result<()> {
        ensure!(
            !state.resident_blocked,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        let mut ids = effect
            .inputs
            .iter()
            .filter_map(|change| match change {
                pl_core::thread::input::InputChange::Accepted(record) => {
                    Some(record.input.id.clone())
                }
                _ => None,
            })
            .collect::<Vec<_>>();
        if let Some(turn) = &effect.turn
            && turn.state == pl_core::thread::TurnState::Running
        {
            ids.push(crate::studio::thread_projection::order::turn_id(
                &turn.turn_id,
            ));
        }
        let fresh_background = if matches!(
            effect.context,
            Some(pl_core::thread::journal::ContextChange::Append { .. })
        ) {
            crate::studio::thread_projection::order::background_receipts(effect)
                .filter(|(_, receipt)| receipt.is_some())
                .map(|(task, _)| {
                    crate::studio::thread_projection::order::tool_background_started_id(
                        &task.call_id,
                    )
                })
                .collect::<std::collections::BTreeSet<_>>()
        } else {
            Default::default()
        };
        ids.extend(fresh_background.iter().cloned());
        let mut staged = BTreeMap::new();
        let mut ceiling = state.ceiling;
        for id in &ids {
            if staged.contains_key(id) {
                continue;
            }
            if let Some(entry) = state.assigned.get(id) {
                let mut entry = entry.clone();
                entry.effect = Some(entry.effect.unwrap_or(0).max(effect.sequence));
                staged.insert(id.clone(), entry);
                continue;
            }
            ceiling = ceiling
                .checked_add(1)
                .filter(|ordinal| *ordinal <= i64::MAX as u64)
                .context("execution ordinal space is exhausted")?;
            let entry = ExecutionIdentity {
                ordinal: ceiling,
                source: None,
                source_ended: false,
                effect: Some(effect.sequence),
                retained: false,
                terminal: false,
                sealed: false,
                completion_checked: fresh_background.contains(id),
                stamp: None,
            };
            staged.insert(id.clone(), entry);
        }
        let (old_bytes, new_bytes) = Self::replacement_bytes(state, &staged);
        ensure!(
            self.other_thread_bytes
                .load(Ordering::Acquire)
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(self.retained_bytes())
                .saturating_add(additional_bytes)
                .saturating_add(new_bytes.saturating_sub(old_bytes))
                <= MAX_HISTORY_THREAD_BYTES,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        // Fund the whole boundary set before publishing any placement or advancing the ceiling.
        let added = new_bytes.saturating_sub(old_bytes);
        let released = old_bytes.saturating_sub(new_bytes);
        self.charge(added, false)?;
        Self::apply_execution_batch(state, staged, ceiling);
        self.release_charge(released);
        Ok(())
    }

    fn has_pending(&self) -> bool {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state
            .pending
            .last()
            .is_some_and(|(effect, _)| *effect > state.durable)
    }

    pub(in crate::studio) fn materialize(
        &self,
        item: &crate::ExecutionItem,
        effect: u64,
    ) -> Result<()> {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        ensure!(
            item.ordinal <= i64::MAX as u64,
            "execution ordinal space is exhausted"
        );
        if let Some(entry) = state.assigned.get(&item.id) {
            ensure!(entry.ordinal == item.ordinal, "execution ordinal conflict");
        }
        let mut staged = BTreeMap::new();
        Self::stage_materialization(
            &state,
            &mut staged,
            &ExecutionMaterialization {
                item_id: &item.id,
                ordinal: Some(item.ordinal),
                revision: item.revision,
                created_at: item.created_at,
                updated_at: item.updated_at,
                turn_id: &item.turn_id,
                terminal: item.is_terminal(),
            },
            item.ordinal,
            effect,
        )?;
        #[cfg(test)]
        {
            let gate = self.materialize_gate.lock().unwrap().take();
            if let Some(gate) = gate {
                let _ = gate.entered.send(());
                gate.release
                    .recv_timeout(Duration::from_secs(10))
                    .expect("materialization regression gate was not released");
            }
        }
        let ceiling = state.ceiling.max(item.ordinal);
        let released = self.commit_execution_batch(&mut state, staged, ceiling)?;
        drop(state);
        if released > 0 {
            self.notify_capacity();
        }
        Ok(())
    }

    /// Assigns placement and funds all stamps in one commit. No body or codec runs
    /// under the index lock; failures leave the entire effect's metadata unchanged.
    pub(in crate::studio) fn materialize_execution_batch<'a>(
        &self,
        items: impl IntoIterator<Item = ExecutionMaterialization<'a>>,
        effect: u64,
    ) -> Result<BTreeMap<String, u64>> {
        let items = items.into_iter().collect::<Vec<_>>();
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let mut staged = BTreeMap::<String, ExecutionIdentity>::new();
        let mut ceiling = state.ceiling;
        // Known durable ordinals must bound all allocations even when their
        // metadata occurs later in the batch.
        for item in &items {
            if let Some(ordinal) = item.ordinal {
                ensure!(
                    ordinal > 0 && ordinal <= i64::MAX as u64,
                    "execution ordinal is outside the storage range"
                );
                ceiling = ceiling.max(ordinal);
            }
        }
        let mut orders = BTreeMap::new();
        for item in &items {
            let assigned = staged
                .get(item.item_id)
                .or_else(|| state.assigned.get(item.item_id));
            let ordinal = match (assigned, item.ordinal) {
                (Some(entry), requested) => {
                    ensure!(
                        requested.is_none_or(|ordinal| ordinal == entry.ordinal),
                        "execution ordinal conflict"
                    );
                    entry.ordinal
                }
                (None, Some(ordinal)) => ordinal,
                (None, None) => {
                    ceiling = ceiling
                        .checked_add(1)
                        .filter(|ordinal| *ordinal <= i64::MAX as u64)
                        .context("execution ordinal space is exhausted")?;
                    ceiling
                }
            };
            Self::stage_materialization(&state, &mut staged, item, ordinal, effect)?;
            orders.insert(item.item_id.to_owned(), ordinal);
        }
        let released = self.commit_execution_batch(&mut state, staged, ceiling)?;
        drop(state);
        if released > 0 {
            self.notify_capacity();
        }
        Ok(orders)
    }

    /// Stage only execution metadata; no body, live revision or owner state is copied or changed.
    fn stage_materialization(
        state: &OrderIndexState,
        staged: &mut BTreeMap<String, ExecutionIdentity>,
        item: &ExecutionMaterialization<'_>,
        ordinal: u64,
        effect: u64,
    ) -> Result<()> {
        let stamp = ExecutionStamp {
            revision: item.revision,
            created_at: item.created_at,
            updated_at: item.updated_at,
            turn_id: item.turn_id.to_owned(),
        };
        if let Some(entry) = staged.get(item.item_id) {
            ensure!(
                entry.ordinal == ordinal
                    && entry.stamp.as_ref() == Some(&stamp)
                    && entry.terminal == item.terminal,
                "conflicting execution identity in one batch"
            );
            return Ok(());
        }
        let mut entry = if let Some(entry) = state.assigned.get(item.item_id) {
            entry.clone()
        } else {
            ExecutionIdentity {
                ordinal,
                source: None,
                source_ended: false,
                effect: None,
                retained: false,
                terminal: false,
                sealed: false,
                completion_checked: false,
                stamp: None,
            }
        };
        entry.stamp = Some(stamp);
        entry.effect = Some(entry.effect.unwrap_or(0).max(effect));
        entry.terminal |= item.terminal;
        staged.insert(item.item_id.to_owned(), entry);
        Ok(())
    }

    /// Validate and fund the net delta once, before changing any placement, stamp or ceiling.
    fn replacement_bytes(
        state: &OrderIndexState,
        staged: &BTreeMap<String, ExecutionIdentity>,
    ) -> (u64, u64) {
        let mut old_bytes = 0_u64;
        let mut new_bytes = 0_u64;
        let mut sources = BTreeMap::<&str, (usize, usize)>::new();
        for (id, entry) in staged {
            if let Some(old) = state.assigned.get(id) {
                old_bytes = old_bytes
                    .saturating_add(old.bytes(id))
                    .saturating_add(state.auxiliary_bytes(id, old));
                if let Some(source) = &old.source
                    && !old.source_ended
                {
                    sources.entry(source).or_default().0 += 1;
                }
            }
            new_bytes = new_bytes
                .saturating_add(entry.bytes(id))
                .saturating_add(identity_key_bytes(id));
            if entry.effect.is_some_and(|effect| effect > state.durable) {
                new_bytes = new_bytes.saturating_add(pending_key_bytes(id));
            }
            if let Some(source) = &entry.source
                && !entry.source_ended
            {
                new_bytes = new_bytes.saturating_add(identity_key_bytes(id));
                sources.entry(source).or_default().1 += 1;
            }
        }
        for (source, (removed, added)) in sources {
            let old = state.by_source.get(source).map_or(0, |ids| ids.len());
            let new = old
                .checked_sub(removed)
                .and_then(|count| count.checked_add(added))
                .expect("source index matches assigned identities");
            if old == 0 && new != 0 {
                new_bytes = new_bytes.saturating_add(source_bucket_bytes(source));
            } else if old != 0 && new == 0 {
                old_bytes = old_bytes.saturating_add(source_bucket_bytes(source));
            }
        }
        (old_bytes, new_bytes)
    }

    fn apply_execution_batch(
        state: &mut OrderIndexState,
        staged: BTreeMap<String, ExecutionIdentity>,
        ceiling: u64,
    ) {
        for (id, entry) in staged {
            let old = state.assigned.insert(id.clone(), entry);
            state.index_identity(&id, old.and_then(|entry| entry.effect));
        }
        state.ceiling = ceiling;
    }

    fn commit_execution_batch(
        &self,
        state: &mut OrderIndexState,
        staged: BTreeMap<String, ExecutionIdentity>,
        ceiling: u64,
    ) -> Result<u64> {
        let (old_bytes, new_bytes) = Self::replacement_bytes(state, &staged);
        let added = new_bytes.saturating_sub(old_bytes);
        let released = old_bytes.saturating_sub(new_bytes);
        if added > 0 {
            self.charge(added, state.resident_blocked)?;
        }
        Self::apply_execution_batch(state, staged, ceiling);
        self.release_charge(released);
        Ok(released)
    }

    pub(in crate::studio) fn is_terminal(&self, id: &str) -> bool {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get(id)
            .is_some_and(|entry| entry.terminal)
    }

    pub(in crate::studio) fn is_sealed(&self, id: &str) -> bool {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get(id)
            .is_some_and(|entry| entry.sealed)
    }

    pub(in crate::studio) fn completion_checked(&self, id: &str) -> bool {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get(id)
            .is_some_and(|entry| entry.completion_checked)
    }

    pub(in crate::studio) fn mark_completion(&self, id: &str, sealed: bool) {
        if let Some(entry) = self
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get_mut(id)
        {
            entry.completion_checked = true;
            entry.sealed |= sealed;
        }
    }

    #[cfg(test)]
    fn pending(&self, id: &str) -> bool {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state
            .assigned
            .get(id)
            .is_some_and(|entry| entry.effect.is_some_and(|seq| seq > state.durable))
    }

    /// 只有当前已接纳 effect 新认领且尚未物化的身份能跳过历史查找。
    /// 旧正文及已物化身份继续走原恢复边界。
    pub(in crate::studio) fn is_new_reservation(&self, id: &str, effect: u64) -> bool {
        let state = self
            .inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state
            .assigned
            .get(id)
            .is_some_and(|entry| entry.effect == Some(effect) && entry.stamp.is_none())
    }

    pub(in crate::studio) fn pending_placement(
        &self,
        id: &str,
        thread_id: &str,
    ) -> Option<crate::ExecutionItem> {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let entry = state.assigned.get(id)?;
        if !entry.effect.is_some_and(|seq| seq > state.durable) {
            return None;
        }
        let stamp = entry.stamp.as_ref()?;
        Some(crate::ExecutionItem::new(
            id.to_owned(),
            thread_id.to_owned(),
            stamp.turn_id.clone(),
            entry.ordinal,
            stamp.revision,
            stamp.created_at,
            stamp.updated_at,
            crate::ExecutionShape::Raw(pl_protocol::ThreadRawItem::stored(
                Vec::new(),
                "Pending execution body belongs to its prepared batch.",
                stamp.created_at,
            )),
        ))
    }

    /// A source-only reservation that never materialized can be retired immediately.
    /// Materialized identities additionally require a real writer acknowledgement.
    pub(in crate::studio) fn finish_source(&self, attempt_id: &str) {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let Some((source, identities)) = state.by_source.remove_entry(attempt_id) else {
            return;
        };
        let mut released = source_bucket_bytes(&source);
        for id in identities {
            state
                .assigned
                .get_mut(&id)
                .expect("indexed source identity")
                .source_ended = true;
            let bytes = identity_key_bytes(&id);
            if !state.dirty.insert(id) {
                released = released.saturating_add(bytes);
            }
        }
        drop(source);
        self.release_charge(released);
        drop(state);
        self.notify_capacity();
    }

    pub(in crate::studio) fn retain_reference(&self, id: &str) {
        if let Some(entry) = self
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get_mut(id)
        {
            entry.retained = true;
        }
    }

    pub(in crate::studio) fn retain<V>(
        &self,
        identities: &BTreeMap<String, V>,
        removed: Vec<String>,
    ) {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let touched = std::mem::take(&mut state.dirty);
        let dirty_bytes = touched
            .iter()
            .map(|id| identity_key_bytes(id))
            .fold(0_u64, u64::saturating_add);
        for id in touched.iter().chain(&removed) {
            let referenced = identities.contains_key(id);
            if let Some(entry) = state.assigned.get_mut(id) {
                // Only the real source terminal retires a reservation. An older snapshot
                // missing that source cannot prove it ended.
                entry.retained = referenced || (entry.source.is_some() && !entry.source_ended);
            }
        }
        let released = self.prune(&mut state, touched.into_iter().chain(removed));
        self.release_charge(dirty_bytes);
        drop(state);
        if released > 0 || dirty_bytes > 0 {
            self.notify_capacity();
        }
    }

    fn confirm_saved(&self, effect: u64) {
        #[cfg(test)]
        {
            self.confirm_saved_calls.fetch_add(1, Ordering::Relaxed);
            if let Some(entered) = self.confirm_saved_entered.lock().unwrap().take() {
                let _ = entered.send(());
            }
        }
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state.durable = state.durable.max(effect);
        let mut confirmed = Vec::new();
        let mut pending_bytes = 0_u64;
        while state
            .pending
            .first()
            .is_some_and(|(effect, _)| *effect <= state.durable)
        {
            let (_, id) = state.pending.pop_first().expect("confirmed prefix");
            pending_bytes = pending_bytes.saturating_add(pending_key_bytes(&id));
            confirmed.push(id);
        }
        let released = self.prune(&mut state, confirmed);
        self.release_charge(pending_bytes);
        drop(state);
        if released > 0 || pending_bytes > 0 {
            self.notify_capacity();
        }
    }

    fn prune(
        &self,
        state: &mut OrderIndexState,
        identities: impl IntoIterator<Item = String>,
    ) -> u64 {
        let mut released = 0_u64;
        for id in identities {
            if state.assigned.get(&id).is_some_and(|entry| {
                !entry.retained && entry.effect.is_none_or(|seq| seq <= state.durable)
            }) && let Some((_, bytes)) = state.remove_identity(&id)
            {
                released = released.saturating_add(bytes);
            }
        }
        self.release_charge(released);
        released
    }

    fn release_charge(&self, bytes: u64) {
        if bytes == 0 {
            return;
        }
        self.bytes.fetch_sub(bytes, Ordering::AcqRel);
        self.process_bytes.fetch_sub(bytes, Ordering::AcqRel);
    }

    fn notify_capacity(&self) {
        let capacity = self
            .capacity_changed
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        if let Some(capacity) = capacity {
            capacity.send_modify(|revision| *revision = revision.wrapping_add(1));
        }
    }
}

impl Drop for RuntimeOrderIndex {
    fn drop(&mut self) {
        self.release_charge(self.bytes.load(Ordering::Acquire));
        self.notify_capacity();
    }
}

/// One admitted effect waiting for its ordered durable write.
#[derive(Debug)]
struct QueuedEffect {
    _conversation: Option<Arc<crate::studio::conversation_store::ConversationStore>>,
    sequence: u64,
    /// Starts the private batching deadline; later arrivals never reset it.
    admitted_at: Instant,
    write: Arc<HistoryExport>,
    /// Encoded size of `write.effect`, measured once at admission.
    bytes: u64,
    /// The product content the Thread's single live projection owner prepared for this commit.
    ///
    /// `None` until the projection owner took the fact over. The writer never projects an effect
    /// itself, so a fact whose reliable handoff is still unfinished stays queued instead of being
    /// written out of the projection's order.
    prepared: Option<Arc<PreparedEffect>>,
    /// Retained bytes of `prepared`, charged to the reliable budget while this entry holds it.
    prepared_bytes: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum HistoryStage {
    ProjectionPrepare,
    WriterQueue,
    SqlCommit,
}

impl HistoryStage {
    fn as_str(self) -> &'static str {
        match self {
            Self::ProjectionPrepare => "projection_prepare",
            Self::WriterQueue => "writer_queue",
            Self::SqlCommit => "sql_commit",
        }
    }
}

#[derive(Debug, Default)]
struct Progress {
    stopped: bool,
    deleting: bool,
    /// Highest effect sequence whose history/checkpoint transaction completed.
    durable: u64,
    /// Highest checkpoint revision already committed with its effect.
    published_revision: u64,
    /// Checkpoint revision of the effect whose atomic history+checkpoint write is in progress.
    saving_revision: u64,
    /// Admitted effects awaiting their ordered history/checkpoint transaction.
    ///
    /// An entry leaves the queue only once the durable store committed it *and* the Thread's single
    /// live projection owner took it over, so this queue is the one reliable handoff between a core
    /// commit and both durable history and the live product.
    effects: VecDeque<QueuedEffect>,
    /// Identity and usage baseline of the original queue's frozen transaction prefix.
    in_flight: Option<batch::FrozenBatch>,
    /// Highest fixed barrier target; cancelling a waiter does not retract its request.
    flush_target: u64,
    effect_bytes: u64,
    /// Conservatively charged entries in `pending_saved_at`.
    queue_metadata_bytes: u64,
    /// Counts queued checkpoint timestamps so the maximum age is available without a queue scan.
    pending_saved_at: BTreeMap<i64, u64>,
    pending_accounting: Option<PendingAccounting>,
    /// Retained bytes of the prepared batches the queue still holds.
    ///
    /// A prepared batch is the immutable product content the projection owner published, and the
    /// queue holds it until the effect is durable: its text is real resident memory, so it is
    /// charged to the Thread's reliable budget instead of hiding outside it. It is released with the
    /// queue entry and never double-counted against that effect's own encoded size.
    prepared_bytes: u64,
    /// Bytes the Thread's live projection currently retains in its own tables.
    ///
    /// The projection owner publishes this absolute gauge after every projection step. It is what
    /// keeps the Thread's budget honest past durability: the retained bodies and the report
    /// accumulator outlive the prepared batch the writer already committed, so without this the
    /// Thread would claim to be drained while still holding its Turn's process bodies.
    projection_bytes: u64,
    /// The sole pending batch included in projection_bytes, before queue handoff.
    projection_pending: Option<PendingProjectionRetention>,
    /// Newest commit the Thread's live projection owner has handed over.
    ///
    /// This is the handoff ticket the projection's own durability barrier asks for: effects are
    /// admitted in order and the owner hands its batch over in the same order, so "the writer is
    /// durable through this commit" is exactly "every fact this owner handed over is saved". A
    /// channel that has handed nothing over is at `0`, so a projection installed on a restored
    /// Thread — whose commits were already durable before this process started — never waits for a
    /// watermark that cannot move.
    handoff: u64,
    /// Encoded bytes of the effect currently being written.
    in_flight_bytes: u64,
    /// Whether the newest admitted state paused inference admission under storage pressure.
    pressure_paused: bool,
    /// Cumulative usage summary folded through the effects committed so far.
    ///
    /// This is the running value hot reads see. Each effect folds its own absolute increment out of
    /// a clone of this value and sets the result on its checkpoint, so the summary that becomes
    /// durable with an effect is exactly the one this field advances to on that same commit.
    usage: UsageSummary,
    error: Option<String>,
    fault: Option<pl_protocol::studio::HistoryFault>,
    fault_generation: u64,
    /// Whether the newest fault generation's retry has been verified as really landed.
    ///
    /// It stays `false` from the moment a fault is latched until a retry made the fixed target
    /// durable and published — the only fact that makes an explicit continue acceptable. A later
    /// fault clears it again, so a stale verification never vouches for a newer failure.
    fault_recovered: bool,
    fault_target: u64,
    retry_requested: bool,
    /// The oldest undurable obligation's actual stage, shared with the existing watchdog.
    stage: Option<HistoryStage>,
    last_progress_at: Option<Instant>,
    /// Actual accepted output, separate from each operation's upper bound.
    operation_output: BTreeMap<String, OperationOutput>,
}

impl Progress {
    fn enter_stage(&mut self, stage: Option<HistoryStage>, now: Instant) {
        if self.stage != stage {
            self.stage = stage;
            self.last_progress_at = stage.map(|_| now);
        }
    }

    fn refresh_head_stage(&mut self, now: Instant) {
        // Admissions and projection handoffs cannot end an outstanding SQL call.
        if self.stage == Some(HistoryStage::SqlCommit) {
            return;
        }
        let stage = self.effects.front().map(|head| {
            if head.prepared.is_some() {
                HistoryStage::WriterQueue
            } else {
                HistoryStage::ProjectionPrepare
            }
        });
        self.enter_stage(stage, now);
    }

    fn prepared_through(&self) -> u64 {
        let mut through = self.durable;
        for effect in &self.effects {
            if effect.prepared.is_none() || through.checked_add(1) != Some(effect.sequence) {
                break;
            }
            through = effect.sequence;
        }
        through
    }
    /// Locate a sequence in the continuous original queue without scanning it.
    fn queue_offset(&self, sequence: u64) -> Option<usize> {
        let first = self.effects.front()?.sequence;
        let offset = usize::try_from(sequence.checked_sub(first)?).ok()?;
        self.effects
            .get(offset)
            .is_some_and(|queued| queued.sequence == sequence)
            .then_some(offset)
    }

    /// The projection handoff advances continuously from the durable or handed-over tail.
    fn next_unprojected_offset(&self) -> Option<usize> {
        let sequence = self.durable.max(self.handoff).checked_add(1)?;
        self.queue_offset(sequence)
    }

    fn admit_saved_at(&mut self, saved_at: i64) {
        *self.pending_saved_at.entry(saved_at).or_default() += 1;
        self.queue_metadata_bytes = self
            .queue_metadata_bytes
            .saturating_add(PENDING_AGE_METADATA_BYTES);
    }

    fn release_saved_at(&mut self, saved_at: i64) {
        let remove = {
            let count = self
                .pending_saved_at
                .get_mut(&saved_at)
                .expect("queued effect has an age index entry");
            *count -= 1;
            *count == 0
        };
        if remove {
            self.pending_saved_at.remove(&saved_at);
        }
        self.queue_metadata_bytes = self
            .queue_metadata_bytes
            .saturating_sub(PENDING_AGE_METADATA_BYTES);
    }
}

#[derive(Debug)]
struct PendingAccounting {
    projection: super::calls::SessionUsageProjection,
    attempts: u8,
    retry_at: Instant,
}

#[derive(Debug)]
struct OperationOutput {
    limit: u64,
    accepted: u64,
    transferred: u64,
}

impl OperationOutput {
    fn retained(&self) -> u64 {
        self.accepted - self.transferred
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct HistoryStatus {
    pub(crate) fault_generation: u64,
    pub(crate) fault: Option<pl_protocol::studio::HistoryFault>,
    pub(crate) error: Option<String>,
    pub(crate) admitted_sequence: u64,
    pub(crate) committed_sequence: u64,
    pub(crate) queued_records: u64,
    pub(crate) queued_bytes: u64,
}

/// What the writer loop has to do next.
enum Step {
    /// Progress was made; the loop runs another unit immediately.
    Progressed,
    /// Nothing to do yet; every admitted effect already carries its own checkpoint, so the loop
    /// just waits for the next admission or retry notification.
    Idle,
    /// Coalesce until the oldest obligation's fixed deadline, or until notified.
    Coalescing(Instant),
}

#[derive(Debug, thiserror::Error)]
#[error("{source}")]
struct ClassifiedWriteError {
    kind: pl_protocol::studio::HistoryFault,
    #[source]
    source: anyhow::Error,
}

fn classified(
    kind: pl_protocol::studio::HistoryFault,
    source: impl Into<anyhow::Error>,
) -> anyhow::Error {
    ClassifiedWriteError {
        kind,
        source: source.into(),
    }
    .into()
}

/// Reliable admission state owned by the session manager, not by a writer incarnation.
pub(crate) struct HistoryChannel {
    order_index: Arc<RuntimeOrderIndex>,
    #[cfg(test)]
    pub(crate) effects_released: tokio::sync::watch::Sender<u64>,
    #[cfg(test)]
    pub(crate) terminal_parked: tokio::sync::watch::Sender<u64>,
    #[cfg(test)]
    initialization_gate: Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
    #[cfg(test)]
    resident_gate: Mutex<Option<MaterializeGate>>,
    #[cfg(test)]
    sql_pending: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    #[cfg(test)]
    delivery_admission_entered: Mutex<Option<std::sync::mpsc::Sender<()>>>,
    progress: Mutex<Progress>,
    history_classifier: Mutex<Option<HistoryClassifier>>,
    changed: Arc<tokio::sync::Notify>,
    step_lock: tokio::sync::Mutex<()>,
    /// Every writer incarnation's physical workers remain registered until actually joined.
    /// Registration and explicit stop share this gate, including cancellation during startup.
    workers: tokio::sync::Mutex<Vec<tokio::task::JoinHandle<()>>>,
    worker_failure: Mutex<Option<Arc<tokio::task::JoinError>>>,
    deletion_joined: std::sync::atomic::AtomicBool,
    pub(super) stopping: tokio_util::sync::CancellationToken,
    /// The process-wide reliable budget, shared by every Thread's channel.
    ///
    /// It charges the effects the channels hold (their admission encoding plus bounded queue
    /// metadata), and the accepted output still retained by in-flight model/tool operations, each
    /// byte once. A fact produced by that operation takes those bytes over at admission instead of
    /// adding a second charge for the same output, and both charges are released when the fact
    /// becomes durable or the call ends without one.
    ///
    /// The prepared batches and the live projection's retained bodies are deliberately *not* part of
    /// this process counter: they are the same product content the queued effect already charged,
    /// kept alive by a different owner, so charging them here would count one body twice and make the
    /// process limit fire at half the memory it names. They are charged to the owning Thread's
    /// budget instead, which is the enforced per-Thread gate (`StoragePressure::thread_bytes`).
    process_bytes: Arc<AtomicU64>,
    /// Logical-source budget shared across joined storage-only writer replacements.
    delivery_bytes: Arc<AtomicU64>,
    /// Short admission pins share the logical delivery source across replacements.
    delivery_admissions: Arc<AtomicU64>,
    status: tokio::sync::watch::Sender<HistoryStatus>,
    pressure_changed: tokio::sync::watch::Sender<()>,
    capacity_changed: Option<tokio::sync::watch::Sender<u64>>,
}

/// A managed producer releases its additional resident copy on success, error or cancellation.
pub(crate) struct ReviewDeliveryRetention {
    channel: Arc<HistoryChannel>,
    bytes: u64,
    coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
    thread_id: String,
}

/// Keeps the registry row alive while channel accounting runs outside its lock.
pub(crate) struct ReviewDeliveryAdmission {
    channel: Arc<HistoryChannel>,
    coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
    thread_id: String,
}

impl Drop for ReviewDeliveryAdmission {
    fn drop(&mut self) {
        self.channel
            .delivery_admissions
            .fetch_sub(1, Ordering::AcqRel);
        self.coordinator
            .release_delivery_channel(&self.thread_id, &self.channel);
    }
}

impl Drop for ReviewDeliveryRetention {
    fn drop(&mut self) {
        let progress = self
            .channel
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.channel
            .delivery_bytes
            .fetch_sub(self.bytes, Ordering::AcqRel);
        self.channel.report(&progress);
        drop(progress);
        self.channel.release_process_bytes(self.bytes);
        self.coordinator
            .release_delivery_channel(&self.thread_id, &self.channel);
    }
}

impl HistoryChannel {
    #[cfg(test)]
    pub(in crate::studio) async fn hold_writer(&self) -> tokio::sync::MutexGuard<'_, ()> {
        self.step_lock.lock().await
    }
    /// Called under the registry lock; this only pins an atomic logical source,
    /// and never acquires progress or index.
    pub(crate) fn pin_review_delivery(
        self: &Arc<Self>,
        coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
        thread_id: String,
    ) -> ReviewDeliveryAdmission {
        self.delivery_admissions.fetch_add(1, Ordering::AcqRel);
        ReviewDeliveryAdmission {
            channel: self.clone(),
            coordinator,
            thread_id,
        }
    }

    fn other_resident_bytes(progress: &Progress) -> u64 {
        progress
            .effect_bytes
            .saturating_add(progress.queue_metadata_bytes)
            .saturating_add(progress.prepared_bytes)
            .saturating_add(progress.projection_bytes)
            .saturating_add(
                progress
                    .operation_output
                    .values()
                    .map(OperationOutput::retained)
                    .sum::<u64>(),
            )
    }

    /// All channel resident mutations hold progress, then the index. The store is the
    /// linearization point seen by synchronous identity reservations; reports have no authority.
    fn commit_residents(&self, progress: &Progress, _index: &OrderIndexState) {
        self.order_index
            .other_thread_bytes
            .store(Self::other_resident_bytes(progress), Ordering::Release);
    }

    /// Caller holds the index lock, so no provider allocation can spend this same headroom.
    fn check_residents(&self, other_bytes: u64, added_delivery: u64) -> Result<()> {
        ensure!(
            other_bytes
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(added_delivery)
                .saturating_add(self.order_index.retained_bytes())
                <= MAX_HISTORY_THREAD_BYTES,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        Ok(())
    }

    /// Actual retained capacity was returned, independently from whether the per-Thread status
    /// also shrank (projection/delivery bytes may have changed concurrently). Atomic failed-claim
    /// rollback stays local. A charged guard's teardown can also finish a refused resident check;
    /// consumers must compare pre-attempt watermarks, never treat a notification alone as progress.
    fn release_process_bytes(&self, bytes: u64) {
        if bytes == 0 {
            return;
        }
        self.process_bytes.fetch_sub(bytes, Ordering::AcqRel);
        self.pressure_changed.send_replace(());
        if let Some(capacity) = &self.capacity_changed {
            capacity.send_modify(|revision| *revision = revision.wrapping_add(1));
        }
    }
    #[cfg(test)]
    pub(crate) fn retained_delivery_bytes(&self) -> u64 {
        self.delivery_bytes.load(Ordering::Acquire)
    }
    pub(crate) fn with_capacity(
        process_bytes: Arc<AtomicU64>,
        capacity: tokio::sync::watch::Sender<u64>,
    ) -> Self {
        let mut channel = Self::new(process_bytes);
        *channel
            .order_index
            .capacity_changed
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(capacity.clone());
        channel.capacity_changed = Some(capacity);
        channel
    }
    pub(super) fn retain_terminal_bytes(
        &self,
        bytes: u64,
        transfer: ProjectionTransfer,
    ) -> Result<Arc<AtomicU64>> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure!(
            progress.projection_pending == Some(transfer.source),
            "terminal material does not own the charged pending batch"
        );
        let after = transfer
            .after
            .pending
            .context("terminal transfer lost its pending batch")?;
        ensure!(
            after.sequence == transfer.source.sequence
                && after.prepared_bytes <= transfer.source.prepared_bytes
                && transfer.after.resident_bytes
                    == progress
                        .projection_bytes
                        .checked_sub(transfer.source.prepared_bytes)
                        .context("invalid charged projection retention")?,
            "terminal transfer changed unrelated projection residents"
        );
        let mut index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let other = Self::other_resident_bytes(&progress)
            .checked_sub(progress.projection_bytes)
            .context("invalid projection budget")?
            .saturating_add(transfer.after.total_bytes());
        if let Err(error) = self.check_residents(other, bytes) {
            index.resident_blocked = true;
            return Err(error);
        }
        // Projection bytes were never charged a second time to the process. The managed copy
        // owns its process charge in full, while the Thread only funds the net ownership growth.
        if !self.reserve(bytes) {
            index.resident_blocked = true;
            anyhow::bail!(ExecutionIndexBudgetFull { scope: "process" });
        }
        self.delivery_bytes.fetch_add(bytes, Ordering::AcqRel);
        progress.projection_bytes = transfer.after.total_bytes();
        progress.projection_pending = transfer.after.pending;
        index.resident_blocked = false;
        self.commit_residents(&progress, &index);
        drop(index);
        self.report(&progress);
        Ok(self.delivery_bytes.clone())
    }

    /// Cold enumeration owns newly loaded authority, without a live pending batch
    /// whose existing charge could be transferred.
    pub(super) fn retain_cold_terminal_bytes(&self, bytes: u64) -> Result<Arc<AtomicU64>> {
        self.charge_review_delivery(bytes)?;
        Ok(self.delivery_bytes.clone())
    }

    pub(super) fn refresh_terminal_bytes(&self) {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.report(&progress);
    }
    pub(crate) fn delivery_retry_mark(&self) -> (u64, u64, bool, u64, u64) {
        let status = self.status.borrow();
        (
            status.committed_sequence,
            status.fault_generation,
            status.error.is_some(),
            status.queued_bytes,
            self.process_bytes.load(Ordering::Acquire),
        )
    }
    pub(in crate::studio) fn terminal_material_bytes(
        &self,
        authority: &crate::thread_assembler::review_dispatch::TerminalAuthority,
        original: &pl_core::thread::inbox::ThreadMessage,
    ) -> u64 {
        // The producer retains these materials only, not an effect, prepared items or checkpoint.
        // The queue's normal prepared/effect accounting owns those until its durable ACK.
        (original.payload.content().len() as u64)
            .saturating_mul(2)
            .saturating_add(original.id.len() as u64)
            .saturating_add(original.source_id.len() as u64)
            .saturating_add(authority.retained_bytes())
            .saturating_add(4096)
    }
    /// The caller holds a logical-source admission pin, without the registry lock.
    /// The pin prevents idle-row cleanup while channel accounting takes progress -> index.
    pub(crate) fn charge_review_delivery(&self, bytes: u64) -> Result<()> {
        anyhow::ensure!(
            bytes <= MAX_HISTORY_THREAD_BYTES.min(MAX_HISTORY_PROCESS_BYTES),
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "terminal material exceeds the reliable byte ceiling"
            )
        );
        #[cfg(test)]
        if let Some(entered) = self.delivery_admission_entered.lock().unwrap().take() {
            let _ = entered.send(());
        }
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        anyhow::ensure!(
            !index.resident_blocked,
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        self.check_residents(Self::other_resident_bytes(&progress), bytes)
            .map_err(|_| crate::thread_assembler::review_dispatch::TerminalBudgetBlocked)?;
        anyhow::ensure!(
            self.reserve(bytes),
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        self.delivery_bytes.fetch_add(bytes, Ordering::AcqRel);
        drop(index);
        self.report(&progress);
        Ok(())
    }

    pub(crate) fn retain_charged_review_delivery(
        self: &Arc<Self>,
        bytes: u64,
        coordinator: crate::studio::storage::coordinator::ThreadPersistenceCoordinator,
        thread_id: String,
    ) -> Result<ReviewDeliveryRetention> {
        let retained = ReviewDeliveryRetention {
            channel: self.clone(),
            bytes,
            coordinator,
            thread_id,
        };
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let result = self.check_residents(Self::other_resident_bytes(&progress), 0);
        drop(index);
        self.report(&progress);
        drop(progress);
        anyhow::ensure!(
            result.is_ok(),
            crate::thread_assembler::review_dispatch::TerminalBudgetBlocked
        );
        Ok(retained)
    }

    pub(crate) fn has_delivery_bytes(&self) -> bool {
        self.delivery_bytes.load(Ordering::Acquire) > 0
            || self.delivery_admissions.load(Ordering::Acquire) > 0
    }
    pub(crate) fn shares_delivery_budget(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.delivery_bytes, &other.delivery_bytes)
    }

    /// The old physical workers were joined by the storage-only owner. Carry only the logical
    /// producer budget/wakeup, never an old queue, core sequence or writer incarnation.
    pub(crate) fn next_storage_channel(&self) -> Self {
        let mut channel = Self::new(self.process_bytes.clone());
        // A stopped storage-only writer may still have a live producer holding reservations.
        // A resident ConversationStore must keep that same allocator across writer replacement.
        // Only a fully unreferenced index can restart from its scalar ceiling.
        if self.order_index.has_pending() || Arc::strong_count(&self.order_index) > 1 {
            channel.order_index = self.order_index.clone();
        } else {
            let ceiling = self
                .order_index
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner())
                .ceiling;
            channel.order_index = Arc::new(RuntimeOrderIndex::with_delivery(
                self.process_bytes.clone(),
                ceiling,
                self.delivery_bytes.clone(),
            ));
        }
        channel.delivery_bytes = self.delivery_bytes.clone();
        channel.delivery_admissions = self.delivery_admissions.clone();
        channel.pressure_changed = self.pressure_changed.clone();
        channel.capacity_changed = self.capacity_changed.clone();
        *channel
            .order_index
            .capacity_changed
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = channel.capacity_changed.clone();
        channel
    }
    /// Wait only for an already handed-over effect, never for a producer's future projection.
    pub(crate) async fn await_handoff_durable(&self, id: &str, sequence: u64) -> Result<()> {
        ensure!(
            sequence <= self.handoff_ticket(),
            "history wait precedes reliable handoff"
        );
        self.request_flush(sequence);
        let mut status = self.subscribe();
        loop {
            {
                let status = status.borrow_and_update();
                if status.committed_sequence >= sequence {
                    return Ok(());
                }
                if let Some(error) = &status.error {
                    anyhow::bail!(
                        "Thread {id} history did not become durable through {sequence}: {error}"
                    );
                }
            }
            status
                .changed()
                .await
                .context("Thread history progress channel closed")?;
        }
    }

    fn request_flush(&self, sequence: u64) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress.flush_target = progress.flush_target.max(sequence);
        drop(progress);
        self.changed.notify_one();
    }
    pub(crate) fn is_stopping(&self) -> bool {
        self.stopping.is_cancelled()
    }

    pub(crate) fn new(process_bytes: Arc<AtomicU64>) -> Self {
        let (status, _) = tokio::sync::watch::channel(HistoryStatus::default());
        let (pressure_changed, _) = tokio::sync::watch::channel(());
        let order_index = Arc::new(RuntimeOrderIndex::new(process_bytes.clone(), 0));
        let delivery_bytes = order_index.delivery_bytes.clone();
        Self {
            order_index,
            #[cfg(test)]
            effects_released: tokio::sync::watch::channel(0).0,
            #[cfg(test)]
            terminal_parked: tokio::sync::watch::channel(0).0,
            #[cfg(test)]
            initialization_gate: Mutex::new(None),
            #[cfg(test)]
            resident_gate: Mutex::new(None),
            #[cfg(test)]
            sql_pending: Mutex::new(None),
            #[cfg(test)]
            delivery_admission_entered: Mutex::new(None),
            progress: Mutex::new(Progress::default()),
            history_classifier: Mutex::new(None),
            changed: Arc::new(tokio::sync::Notify::new()),
            step_lock: tokio::sync::Mutex::new(()),
            workers: tokio::sync::Mutex::new(Vec::new()),
            worker_failure: Mutex::new(None),
            deletion_joined: std::sync::atomic::AtomicBool::new(false),
            stopping: tokio_util::sync::CancellationToken::new(),
            process_bytes,
            delivery_bytes,
            delivery_admissions: Arc::new(AtomicU64::new(0)),
            status,
            pressure_changed,
            capacity_changed: None,
        }
    }

    fn reserve(&self, bytes: u64) -> bool {
        self.process_bytes
            .try_update(Ordering::AcqRel, Ordering::Acquire, |current| {
                current
                    .checked_add(bytes)
                    .filter(|total| *total <= MAX_HISTORY_PROCESS_BYTES)
            })
            .is_ok()
    }

    #[cfg(test)]
    fn pause_resident_commit(&self) {
        if let Some(gate) = self.resident_gate.lock().unwrap().take() {
            let _ = gate.entered.send(());
            gate.release
                .recv_timeout(Duration::from_secs(10))
                .expect("resident commit regression gate was not released");
        }
    }

    /// Registers an output ceiling without charging bytes that do not exist yet.
    /// The producer must charge each cumulative increment before retaining it.
    fn reserve_operation_output(&self, operation_id: &str, max_bytes: u64) -> Option<u64> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(output) = progress.operation_output.get(operation_id) {
            return Some(output.limit);
        }
        if max_bytes == 0 || self.process_bytes.load(Ordering::Acquire) >= MAX_HISTORY_PROCESS_BYTES
        {
            return None;
        }
        progress.operation_output.insert(
            operation_id.to_owned(),
            OperationOutput {
                limit: max_bytes,
                accepted: 0,
                transferred: 0,
            },
        );
        Some(max_bytes)
    }

    /// Charges only newly accepted bytes. A transfer to an effect never resets the cumulative
    /// producer counter, so later progress cannot charge the same output again.
    fn charge_operation_output(
        &self,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some(output) = progress.operation_output.get(operation_id) else {
            return Err(cold_error("operation output quota is no longer registered"));
        };
        if accepted_bytes <= output.accepted {
            return Ok(());
        }
        let added = accepted_bytes - output.accepted;
        let index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if index.resident_blocked
            || accepted_bytes > output.limit
            || self
                .check_residents(
                    Self::other_resident_bytes(&progress).saturating_add(added),
                    0,
                )
                .is_err()
            || !self.reserve(added)
        {
            return Err(cold_error(&format!(
                "operation {operation_id} cannot retain {added} additional output bytes"
            )));
        }
        progress
            .operation_output
            .get_mut(operation_id)
            .expect("registered output")
            .accepted = accepted_bytes;
        self.commit_residents(&progress, &index);
        drop(index);
        self.report(&progress);
        // Accepted output is part of pressure, but not the queue-only HistoryStatus.
        drop(progress);
        self.pressure_changed.send_replace(());
        Ok(())
    }

    fn release_operation_output(&self, operation_id: &str) {
        let retained = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let index = self
                .order_index
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            let retained = progress
                .operation_output
                .remove(operation_id)
                .map_or(0, |output| output.retained());
            self.commit_residents(&progress, &index);
            drop(index);
            self.report(&progress);
            retained
        };
        // OutputBudget::release can be the only remaining producer event, even cross-Thread.
        self.release_process_bytes(retained);
    }

    pub(crate) fn subscribe(&self) -> tokio::sync::watch::Receiver<HistoryStatus> {
        self.status.subscribe()
    }

    pub(in crate::studio) fn order_index(&self) -> Arc<RuntimeOrderIndex> {
        self.order_index.clone()
    }

    /// Publishes the bytes the Thread's live projection currently retains in its own tables.
    ///
    /// The projection owner is the only writer of this gauge, and it reports an absolute value, so
    /// the Thread's budget covers the report accumulator and the retained bodies without charging a
    /// cumulative estimate twice. It is reported through the same status the reliable queue uses,
    /// so a Thread whose projection still holds its Turn's bodies reads as pending work — which is
    /// what pauses new model/tool admission at a safe gap instead of growing unseen memory.
    pub(in crate::studio) fn set_projection_retention(
        &self,
        retention: ProjectionRetention,
    ) -> Result<()> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(pending) = retention.pending {
            let offset = progress.next_unprojected_offset();
            ensure!(
                offset.is_some_and(|offset| {
                    let effect = &progress.effects[offset];
                    effect.sequence == pending.sequence && effect.prepared.is_none()
                }),
                "projection retention does not name an unprepared admitted effect"
            );
        }
        if let Some(previous) = progress.projection_pending {
            ensure!(
                retention
                    .pending
                    .is_some_and(|pending| pending.sequence == previous.sequence),
                "projection still owns an untransferred pending batch"
            );
        }
        let mut index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        // These are the current materials of an already admitted fact, not a new allocation
        // request. Even on failure retain their full charge, preventing further allocations.
        progress.projection_bytes = retention.total_bytes();
        progress.projection_pending = retention.pending;
        self.commit_residents(&progress, &index);
        let result = self.check_residents(Self::other_resident_bytes(&progress), 0);
        let newly_blocked = result.is_err() && !index.resident_blocked;
        index.resident_blocked = result.is_err();
        drop(index);
        self.report(&progress);
        if newly_blocked {
            self.changed.notify_one();
        }
        result
    }

    pub(in crate::studio) fn release_projection_retention(&self) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        progress.projection_bytes = 0;
        progress.projection_pending = None;
        index.resident_blocked = self
            .check_residents(Self::other_resident_bytes(&progress), 0)
            .is_err();
        self.commit_residents(&progress, &index);
        drop(index);
        self.report(&progress);
    }

    /// Newest commit the Thread's live projection owner has handed over to this channel.
    ///
    /// The projection owner waits on the writer's watermark only for facts it handed over itself, so
    /// this ticket — not an absolute commit sequence — is what its durability barrier targets. It is
    /// `0` while nothing was handed over, which is already durable.
    pub(crate) fn handoff_ticket(&self) -> u64 {
        self.progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .handoff
    }

    /// Hands the Thread's single live projection owner's prepared batch to the reliable handoff.
    ///
    /// The batch is attached to the admitted effect it belongs to, so the writer commits exactly the
    /// content the projection published instead of projecting the effect a second time. Only a fact
    /// this channel already admitted can be handed over — the projection owner reads its work from
    /// this same queue — so an unknown or already durable sequence is refused rather than stored in a
    /// second, unordered slot. Returns whether the batch was attached.
    pub(in crate::studio) fn prepare(&self, prepared: Arc<PreparedEffect>) -> bool {
        self.prepare_with(None, prepared, || Ok(())).is_ok()
    }

    /// 在唯一可靠记录上校验原批次及预算，再同步发布并接收同一原件。
    pub(in crate::studio) fn prepare_with(
        &self,
        original: Option<&Arc<HistoryExport>>,
        prepared: Arc<PreparedEffect>,
        publish: impl FnOnce() -> Result<()>,
    ) -> Result<()> {
        // Measure before taking the lock: the batch is immutable, and the owner's one estimate
        // (see `PreparedEffect::retained_bytes`) walks text lengths instead of encoding a payload
        // inside the critical section.
        let bytes = prepared.retained_bytes();
        let sequence = prepared.sequence;
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if sequence <= progress.durable {
            anyhow::bail!("reliable channel refused prepared effect");
        }
        let Some(index) = progress.queue_offset(sequence) else {
            anyhow::bail!("reliable channel refused prepared effect");
        };
        if let Some(original) = original {
            ensure!(
                Arc::ptr_eq(&progress.effects[index].write, original),
                "original effect is not this channel's accepted write"
            );
        }
        if let Some(existing) = &progress.effects[index].prepared {
            // Retries hand over the original frozen batch; replacing it could lose a published
            // completion or change the bytes behind an unchanged reliable-budget charge.
            ensure!(
                Arc::ptr_eq(existing, &prepared),
                "prepared effect identity differs"
            );
            return publish();
        }
        if progress.next_unprojected_offset() != Some(index) {
            anyhow::bail!("reliable channel refused prepared effect");
        }
        let mut order_index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let transferred = match progress.projection_pending {
            Some(source) if source.sequence == sequence && source.prepared_bytes == bytes => bytes,
            Some(_) => anyhow::bail!("prepared effect budget differs"),
            None => 0,
        };
        let other = Self::other_resident_bytes(&progress);
        if (transferred == 0 && bytes > 0 && order_index.resident_blocked)
            || self
                .check_residents(other.saturating_add(bytes - transferred), 0)
                .is_err()
        {
            let newly_blocked = !order_index.resident_blocked;
            order_index.resident_blocked = true;
            if newly_blocked {
                self.changed.notify_one();
            }
            anyhow::bail!("reliable channel refused prepared effect");
        }
        publish()?;
        if transferred > 0 || progress.projection_pending.is_some() {
            progress.projection_bytes -= transferred;
            progress.projection_pending = None;
        }
        progress.prepared_bytes = progress.prepared_bytes.saturating_add(bytes);
        progress.effects[index].prepared_bytes = bytes;
        progress.effects[index].prepared = Some(prepared);
        progress.handoff = sequence;
        progress.refresh_head_stage(Instant::now());
        #[cfg(test)]
        self.pause_resident_commit();
        self.commit_residents(&progress, &order_index);
        drop(order_index);
        let reported = self.report(&progress);
        drop(progress);
        if !reported {
            // A zero-byte handoff is still a new durable-work boundary, exactly once.
            self.status.send_modify(|_| {});
        }
        self.changed.notify_one();
        Ok(())
    }

    /// Oldest admitted effect the Thread's live projection owner has not taken over yet.
    ///
    /// The reliable queue is the Thread's one ordered handoff, so the projection owner consumes it in
    /// admission order: this is the next fact it owes a projection, and `None` while every admitted
    /// effect is already prepared. Nothing waits for a GUI — a Thread without subscribers still
    /// drains the queue, because the writer cannot save a fact no projection holds.
    pub(in crate::studio) fn next_unprojected(&self) -> Option<Arc<HistoryExport>> {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress
            .next_unprojected_offset()
            .and_then(|offset| progress.effects.get(offset))
            .map(|queued| queued.write.clone())
    }

    /// Captures the bounded, ordered projection backlog for one observer initialization.
    /// Only immutable handles are cloned under the queue lock; history reads happen afterwards.
    pub(in crate::studio) fn unprojected_writes(&self) -> Vec<Arc<HistoryExport>> {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let offset = progress
            .next_unprojected_offset()
            .unwrap_or(progress.effects.len());
        progress
            .effects
            .iter()
            .skip(offset)
            .map(|queued| queued.write.clone())
            .collect()
    }

    /// Publishes the failure of one admitted fact's projection.
    ///
    /// The writer never projects an effect itself, so a fact the projection owner cannot project is
    /// never handed over and never saved. Reporting it here is what makes the durable barrier fail
    /// closed with the projection's own reason — and what keeps `pressure()` agreeing with it —
    /// instead of waiting forever for a batch that will never arrive.
    ///
    /// An unchanged fault is published once. The projection owner re-observes the same pending fact
    /// on every owner snapshot, so re-publishing the identical status would wake its own status
    /// watcher and turn the failure into a busy loop instead of a paused, fail-closed Thread.
    pub(crate) fn fail_projection(&self, sequence: u64, message: String) {
        let published = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let published = progress.error.as_deref() != Some(message.as_str());
            if progress.error.is_none() {
                progress.fault_generation = progress.fault_generation.saturating_add(1);
                progress.retry_requested = false;
            }
            progress.fault_target = progress.fault_target.max(sequence);
            progress.fault = Some(pl_protocol::studio::HistoryFault::WriteFailed);
            progress.error = Some(message);
            progress.fault_recovered = false;
            progress.saving_revision = 0;
            if published {
                self.diagnose(
                    &progress,
                    Instant::now(),
                    "projection_prepare",
                    pl_protocol::studio::HistoryFault::WriteFailed,
                    &["projection_failed"],
                );
                self.report(&progress);
            }
            published
        };
        if published {
            self.changed.notify_one();
        }
    }

    fn report(&self, progress: &Progress) -> bool {
        let previous_bytes = self.status.borrow().queued_bytes;
        let next = HistoryStatus {
            fault_generation: progress.fault_generation,
            fault: progress.fault,
            error: progress.error.clone(),
            admitted_sequence: progress
                .effects
                .back()
                .map_or(progress.durable, |queued| queued.sequence),
            committed_sequence: progress.durable,
            queued_records: progress.effects.len() as u64,
            queued_bytes: progress
                .effect_bytes
                .saturating_add(progress.queue_metadata_bytes)
                .saturating_add(progress.prepared_bytes)
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(progress.projection_bytes)
                .saturating_add(self.order_index.retained_bytes()),
        };
        let decreased = next.queued_bytes < previous_bytes;
        let changed = self.status.send_if_modified(|status| {
            if *status == next {
                return false;
            }
            *status = next;
            true
        });
        if changed {
            self.pressure_changed.send_replace(());
        }
        if decreased && let Some(capacity) = &self.capacity_changed {
            capacity.send_modify(|revision| *revision = revision.wrapping_add(1));
        }
        changed
    }

    pub(crate) fn retry(&self, generation: u64) -> Result<()> {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure!(
            progress.error.is_some() && progress.fault_generation == generation,
            "history fault generation changed; refresh the session status"
        );
        progress.retry_requested = true;
        let mut index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        index.resident_blocked = self
            .check_residents(Self::other_resident_bytes(&progress), 0)
            .is_err();
        drop(index);
        drop(progress);
        // Explicit retry is an owner action even when its public status is unchanged.
        self.status.send_modify(|_| {});
        self.pressure_changed.send_replace(());
        self.changed.notify_one();
        Ok(())
    }

    /// Recheck the owning registry while holding progress, before publishing its terminal fault.
    /// The callback only inspects that registry and follows the report's progress -> registry order.
    pub(crate) fn mark_unavailable(&self, still_unowned: impl FnOnce() -> bool) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.effects.is_empty() || !still_unowned() {
            return;
        }
        if progress.error.is_none() {
            progress.fault_generation = progress.fault_generation.saturating_add(1);
        }
        progress.fault = Some(pl_protocol::studio::HistoryFault::WriterUnavailable);
        progress.error = Some("history writer unavailable; queued facts retained".to_owned());
        progress.fault_recovered = false;
        progress.retry_requested = false;
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        self.report(&progress);
    }

    pub(crate) fn is_clean(&self) -> bool {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress.effects.is_empty() && progress.error.is_none()
    }

    /// Called only after the producer stopped and the observation's handoff became durable.
    /// Cancelling the waiter leaves the workers in this owner for a subsequent join.
    pub(crate) async fn stop_and_join(&self) -> Result<()> {
        self.stop_and_join_with_purpose(crate::thread_assembler::ClosePurpose::Preserve)
            .await
    }

    pub(crate) async fn stop_and_join_for_deletion(&self) -> Result<()> {
        self.stop_and_join_with_purpose(crate::thread_assembler::ClosePurpose::Delete)
            .await
    }

    pub(crate) fn deletion_joined(&self) -> bool {
        self.deletion_joined.load(Ordering::Acquire)
    }

    async fn stop_and_join_with_purpose(
        &self,
        purpose: crate::thread_assembler::ClosePurpose,
    ) -> Result<()> {
        let mut workers = self.workers.lock().await;
        {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            ensure!(
                purpose == crate::thread_assembler::ClosePurpose::Delete
                    || (progress.effects.is_empty() && progress.error.is_none()),
                "cannot stop a history writer with undurable facts"
            );
            progress.stopped = true;
            progress.deleting = purpose == crate::thread_assembler::ClosePurpose::Delete;
        }
        self.stopping.cancel();
        self.changed.notify_waiters();
        while let Some(worker) = workers.last_mut() {
            let joined = worker.await;
            workers.pop();
            if let Err(error) = joined {
                self.worker_failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .get_or_insert_with(|| Arc::new(error));
            }
        }
        let failure = self
            .worker_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if let Some(error) = failure {
            return Err(error).context("history worker failed while stopping");
        }
        if purpose == crate::thread_assembler::ClosePurpose::Delete {
            let (released, discarded) = {
                let mut progress = self
                    .progress
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let released = progress
                    .effect_bytes
                    .saturating_add(progress.queue_metadata_bytes)
                    .saturating_add(
                        progress
                            .operation_output
                            .values()
                            .map(OperationOutput::retained)
                            .sum::<u64>(),
                    );
                let discarded = (
                    std::mem::take(&mut progress.effects),
                    progress.in_flight.take(),
                    progress.projection_pending.take(),
                    progress.pending_accounting.take(),
                );
                progress.effect_bytes = 0;
                progress.queue_metadata_bytes = 0;
                progress.prepared_bytes = 0;
                progress.projection_bytes = 0;
                progress.in_flight_bytes = 0;
                progress.pending_saved_at.clear();
                progress.operation_output.clear();
                self.report(&progress);
                (released, discarded)
            };
            // Prepared material may release delivery guards that re-enter this channel.
            drop(discarded);
            self.release_process_bytes(released);
            self.deletion_joined.store(true, Ordering::Release);
        }
        ensure!(
            purpose == crate::thread_assembler::ClosePurpose::Delete || self.is_clean(),
            "history writer stopped with undurable facts"
        );
        Ok(())
    }

    fn detect_stall(&self) {
        self.detect_stall_at(Instant::now());
    }

    fn detect_stall_at(&self, now: Instant) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.error.is_some()
            || progress.effects.is_empty()
            || !progress
                .last_progress_at
                .is_some_and(|last| now.saturating_duration_since(last) >= NO_PROGRESS_WINDOW)
        {
            return;
        }
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault = Some(pl_protocol::studio::HistoryFault::NoProgress);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        progress.error = Some("history writer made no progress with queued facts".to_owned());
        progress.fault_recovered = false;
        progress.retry_requested = false;
        self.diagnose(
            &progress,
            now,
            "watchdog",
            pl_protocol::studio::HistoryFault::NoProgress,
            &["no_progress"],
        );
        self.report(&progress);
    }

    /// Log only identities, counters and bounded reason categories. Raw error Display/source
    /// strings may contain provider responses, paths or credentials and never enter this event.
    fn diagnose(
        &self,
        progress: &Progress,
        now: Instant,
        source: &str,
        kind: pl_protocol::studio::HistoryFault,
        reasons: &[&str],
    ) {
        let head = progress.effects.front();
        let execution_id = head
            .and_then(|effect| effect.write.state.execution.as_ref())
            .map(|execution| execution.id.as_str());
        // The reliable queue carries execution identity, not live provider request/generation
        // metadata. Attempt IDs and the execution counter cannot substitute for those identities.
        tracing::warn!(
            target: "conversation_work",
            operation = "history_persistence",
            thread_id = ?head.map(|effect| effect.write.effect.thread_id.as_str()),
            execution_id = ?execution_id,
            request_id = ?Option::<&str>::None,
            generation = ?Option::<u32>::None,
            effect = ?head.map(|effect| effect.sequence),
            stage = ?progress.stage.map(HistoryStage::as_str),
            stage_started_at = ?progress.last_progress_at,
            stage_elapsed_ms = ?progress.last_progress_at.map(|started|
                now.saturating_duration_since(started).as_millis().min(u128::from(u64::MAX)) as u64),
            head = ?head.map(|effect| effect.sequence),
            admitted = progress.effects.back().map_or(progress.durable, |effect| effect.sequence),
            prepared_through = progress.prepared_through(),
            durable = progress.durable,
            flush_target = ?(progress.flush_target > progress.durable).then_some(progress.flush_target),
            pending_count = progress.effects.len(),
            pending_bytes = progress.effect_bytes.saturating_add(progress.queue_metadata_bytes)
                .saturating_add(progress.prepared_bytes),
            fault_kind = ?kind,
            fault_generation = progress.fault_generation,
            error_source = source,
            reason_chain = ?reasons,
            "history persistence stalled or failed"
        );
    }
}

impl std::fmt::Debug for HistoryChannel {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryChannel")
            .finish_non_exhaustive()
    }
}

struct Inner {
    store: StudioStore,
    thread: pl_protocol::Thread,
    conversation: Arc<crate::studio::conversation_store::ConversationStore>,
    /// This writer incarnation's coordinator identity; see [`NEXT_WRITER_INCARNATION`].
    owner: usize,
    /// One durable history reader for the life of this writer.
    ///
    /// The history database is the single ordinal/identity allocator, so the writer opens it once
    /// instead of per effect; the pool has one connection, so every batch stays a short
    /// single-writer transaction and two consecutive effects cannot interleave their allocations.
    history: tokio::sync::OnceCell<HistoryStore>,
    channel: Arc<HistoryChannel>,
    changed: Arc<tokio::sync::Notify>,
    history_observer_stop: tokio::sync::watch::Sender<bool>,
}

impl Drop for Inner {
    fn drop(&mut self) {
        self.history_observer_stop.send_replace(true);
    }
}

/// Cloneable sink attached to one core owner incarnation.
#[derive(Clone)]
pub(crate) struct ThreadStorageSink(Arc<Inner>);

/// One actual writer incarnation, retained through attachment and all close joins.
#[derive(Debug)]
pub(crate) struct ThreadStorageBinding {
    pub(crate) conversation: Arc<crate::studio::conversation_store::ConversationStore>,
    pub(crate) incarnation: usize,
    pub(crate) storage: ThreadStorageSink,
    pub(crate) channel: Arc<HistoryChannel>,
}

impl ThreadStorageBinding {
    pub(crate) fn new(
        storage: ThreadStorageSink,
        channel: Arc<HistoryChannel>,
        conversation: Arc<crate::studio::conversation_store::ConversationStore>,
    ) -> Self {
        Self {
            storage,
            channel,
            conversation,
            incarnation: NEXT_WRITER_INCARNATION.fetch_add(1, Ordering::Relaxed),
        }
    }
}

impl Drop for ThreadStorageBinding {
    fn drop(&mut self) {
        self.conversation.detach_execution(self);
    }
}

impl std::fmt::Debug for ThreadStorageSink {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ThreadStorageSink")
            .field("thread_id", &self.0.thread.id)
            .finish_non_exhaustive()
    }
}

fn lock_progress(inner: &Inner) -> std::sync::MutexGuard<'_, Progress> {
    inner
        .channel
        .progress
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Encoded size of one effect, or `u64::MAX` when it cannot be encoded.
fn encoded_bytes(effect: &pl_core::thread::ThreadEffectBatch) -> u64 {
    effect
        .encode()
        .map_or(u64::MAX, |payload| payload.content().len() as u64)
}

/// Accepted output bytes that can transfer to the operation's durable fact.
fn retained_output_draw(progress: &Progress, operation: &str, want: u64) -> u64 {
    progress
        .operation_output
        .get(operation)
        .map_or(0, |output| output.retained().min(want))
}

/// Transfers already charged output to its producing operation's fact without charging twice.
/// Unrelated facts must fit the remaining budget; they cannot spend another operation's output.
/// The plan is computed before admission mutates either counter.
fn output_transfer_plan(
    progress: &Progress,
    funding: Option<&str>,
    bytes: u64,
) -> (Vec<(String, u64)>, u64) {
    let mut plan = Vec::new();
    let mut covered = 0_u64;
    if let Some(operation) = funding {
        let take = retained_output_draw(progress, operation, bytes);
        if take > 0 {
            covered += take;
            plan.push((operation.to_owned(), take));
        }
    }
    (plan, covered)
}

/// The writer's single durable history reader, opened on first use.
///
/// The handle comes from the per-Thread shared writer registry, so this sink's effect commit and a
/// live subscription's ordinal reservation share one ordered writer identity — one SQLite write
/// connection — instead of two independent writers racing for `history.sqlite`'s write lock. Reads
/// stay on their own read-only connections in WAL, so they are never queued behind this one.
async fn history_store(inner: &Inner) -> Result<HistoryStore> {
    let opened = inner
        .history
        .get_or_try_init(|| async { inner.store.history(&inner.thread.id).await })
        .await?;
    Ok(opened.clone())
}

/// Publishes the current queue state so `wait_for_drain` and the product snapshot never report a
/// Thread as finished while an effect (and therefore its checkpoint) is still queued.
fn report(inner: &Inner, progress: &Progress) {
    report_with_calls(inner, progress, Some(inner.store.calls()));
}

/// History-only observers pass no capability to sample or republish global calls state.
fn report_with_calls(
    inner: &Inner,
    progress: &Progress,
    calls: Option<&crate::studio::storage::calls::CallsStore>,
) {
    inner.channel.report(progress);
    let pending = progress
        .effects
        .front()
        .zip(progress.effects.back())
        .map(|(first, last)| PendingSequenceRange {
            first: first.sequence,
            last: last.sequence,
        });
    debug_assert_eq!(
        pending.map_or(0, PendingSequenceRange::count),
        progress.effects.len() as u64
    );
    let pending_bytes = progress
        .effect_bytes
        .saturating_add(progress.queue_metadata_bytes);
    // 每个待写 effect 自带它的候选 checkpoint，并与其在同一个事务落盘：队列非空就意味着历史与
    // checkpoint 都还 dirty，最老待写年龄因此只来自队列里每条 effect 自己的 saved_at。
    let pending_operations = progress.effects.len() as u64;
    let now = crate::studio::unix_seconds();
    let oldest_pending_age_millis =
        progress
            .pending_saved_at
            .first_key_value()
            .map(|(saved_at, _)| {
                u64::try_from(now.saturating_sub(*saved_at))
                    .unwrap_or(0)
                    .saturating_mul(1000)
            });
    let max_admitted = progress
        .effects
        .back()
        .map(|queued| queued.sequence)
        .unwrap_or(0);
    let dirty_revision = progress
        .effects
        .back()
        .map(|queued| queued.write.effect.sequence)
        .unwrap_or(progress.published_revision);
    let metrics = ThreadPersistenceMetrics {
        fault_generation: progress.fault_generation,
        fault: progress.fault,
        state_dirty_revision: dirty_revision,
        state_saving_revision: progress.saving_revision,
        state_durable_revision: progress.published_revision,
        history_admitted_sequence: max_admitted.max(progress.durable),
        history_durable_sequence: progress.durable,
        pending_operations,
        pending_bytes,
        in_flight_bytes: progress.in_flight_bytes,
        oldest_pending_age_millis,
        pressure_paused: progress.pressure_paused,
    };
    inner.store.thread_persistence().report(
        &inner.thread.id,
        inner.owner,
        ThreadPersistenceReport {
            pending,
            pending_checkpoint: false,
            error: progress.error.clone(),
            metrics,
        },
        calls,
    );
}

fn clear_recovered_fault(progress: &mut Progress) -> bool {
    if progress.retry_requested
        && progress.durable >= progress.fault_target
        && progress.published_revision >= progress.fault_target
    {
        progress.error = None;
        progress.fault = None;
        progress.retry_requested = false;
        // The retry named this generation and the fixed target really landed, so an explicit
        // continue would be accepted now: that verified fact is what the UI is allowed to show.
        progress.fault_recovered = true;
        true
    } else {
        false
    }
}

impl ThreadStorageSink {
    pub(crate) async fn new(
        store: StudioStore,
        thread: pl_protocol::Thread,
        restored_checkpoint: Option<&ThreadCheckpoint>,
    ) -> Result<Self> {
        let catalog = store.catalog();
        let registered = catalog
            .agent_by_thread(&thread.id)
            .context("Thread is not registered in the Studio catalog")?;
        let session_workspace = catalog
            .get_session(&registered.session_id)
            .map(|session| session.workspace_id)
            .context("session is not registered in the Studio catalog")?;
        anyhow::ensure!(
            session_workspace == thread.workspace_id
                && store.workspaces().get(&thread.workspace_id).is_some(),
            "Thread {} Project identity is not registered in workspaces",
            thread.id
        );
        let owner = NEXT_WRITER_INCARNATION.fetch_add(1, Ordering::Relaxed);
        let registration = store.thread_persistence().claim(&thread.id, owner)?;
        let channel = registration.channel.clone();
        #[cfg(test)]
        {
            let gate = channel.initialization_gate.lock().unwrap().take();
            if let Some((entered, release)) = gate {
                let _ = entered.send(());
                let _ = release.await;
            }
        }
        let conversation = store.conversation_store(&thread.id).await?;
        let mut workers = channel.workers.lock().await;
        ensure!(
            !channel.stopping.is_cancelled(),
            "history writer is stopping"
        );
        // A preceding incarnation may still be finishing one write. Observe its committed
        // watermark and seed this incarnation while holding the channel's single-writer lease.
        let writer_lease = channel.step_lock.lock().await;
        let history = store.history(&thread.id).await?;
        let durable = restored_checkpoint.map_or(0, |checkpoint| checkpoint.state.commit_sequence);
        let (history_observer_stop, mut stop_observer) = tokio::sync::watch::channel(false);
        let inner = Arc::new(Inner {
            store,
            thread,
            conversation,
            owner,
            history: tokio::sync::OnceCell::new(),
            changed: channel.changed.clone(),
            channel: channel.clone(),
            history_observer_stop,
        });
        let mut history_updates = channel.subscribe();
        // Report the shared queue only after this incarnation has initialized its durable fence.
        // Registration alone cannot discharge a predecessor's obligations: this report proves
        // which retained facts are adopted and which have already become durable.
        {
            let mut progress = lock_progress(&inner);
            progress.durable = progress.durable.max(durable);
            progress.published_revision = progress
                .published_revision
                .max(restored_checkpoint.map_or(0, |checkpoint| checkpoint.state_revision));
            report(&inner, &progress);
        }
        publish_accounting(&inner, &history).await;
        drop(writer_lease);
        let observer = Arc::downgrade(&inner);
        let observer_stop = channel.stopping.clone();
        workers.push(tokio::spawn(async move {
            loop {
                tokio::select! {
                    result = history_updates.changed() => {
                        if result.is_err() {
                            break;
                        }
                        let Some(inner) = observer.upgrade() else {
                            break;
                        };
                        // Every incarnation must report shared history recovery for itself.
                        // This observer owns no calls watermark or accounting refresh work.
                        let progress = lock_progress(&inner);
                        report_with_calls(&inner, &progress, None);
                    },
                    _ = stop_observer.changed() => break,
                    () = observer_stop.cancelled() => break,
                }
            }
        }));
        let worker = inner.clone();
        let watchdog = Arc::downgrade(&inner);
        let watchdog_stop = channel.stopping.clone();
        workers.push(tokio::spawn(async move {
            while let Some(inner) = watchdog.upgrade() {
                inner.channel.detect_stall();
                drop(inner);
                tokio::select! {
                        () = tokio::time::sleep(Duration::from_secs(10)) => {},
                        () = watchdog_stop.cancelled() => break,
                }
            }
        }));
        workers.push(tokio::spawn(async move {
            let inner = worker;
            let _registration = registration;
            // 连续可重试失败的起点；任何一次成功的推进都清零。只有持续超过窗口才升级上报。
            let mut retrying_since: Option<Instant> = None;
            loop {
                // A deletion stop is published under progress before cancellation. Finish any
                // current SQL step, then leave without retries or a final preservation write.
                if inner.channel.stopping.is_cancelled() && lock_progress(&inner).deleting {
                    return;
                }
                retry_accounting(&inner);
                // The task keeps the persistence owner alive while it owes facts, even when the
                // last Thread or GUI handle is dropped. The same owner finishes its bounded
                // Summary handoff without making diagnostic failure a reliable-save failure.
                if inner.channel.stopping.is_cancelled() || Arc::strong_count(&inner) == 1 {
                    let reliable_clean = {
                        let progress = lock_progress(&inner);
                        let clean = progress.effects.is_empty() && progress.error.is_none();
                        if clean {
                            // Another incarnation may have completed the shared queue. Publish
                            // this owner's final obligations even if its observer was cancelled.
                            report(&inner, &progress);
                        }
                        clean
                    };
                    if reliable_clean {
                        let due = lock_progress(&inner)
                            .pending_accounting
                            .as_ref()
                            .map(|pending| pending.retry_at);
                        let Some(due) = due else {
                            return;
                        };
                        // Do not select the already-cancelled stop token while handing off:
                        // that would busy-loop instead of honoring the bounded retry deadline.
                        tokio::time::sleep_until(due).await;
                        continue;
                    }
                }
                let paused = {
                    let progress = lock_progress(&inner);
                    progress.error.is_some()
                        && !progress.retry_requested
                        && progress.fault != Some(pl_protocol::studio::HistoryFault::QueueFull)
                };
                if paused {
                    // 通道可以把一个本 incarnation 自己没失败过的 Thread 标成失败：投影无法完成的
                    // 事实永远不会被交接，writer 因此既不写也不报错。协调器聚合的错误正是进程级
                    // drain 等待的那个事实，所以这里把通道的故障转成协调器可见的错误；否则暂停的
                    // 队列会把停机变成无界等待，而不是带着真实原因的显式失败。
                    {
                        let progress = lock_progress(&inner);
                        report(&inner, &progress);
                    }
                    tokio::select! {
                        () = inner.changed.notified() => {},
                        () = accounting_retry_due(&inner) => {},
                        () = inner.channel.stopping.cancelled() => {},
                    }
                    continue;
                }
                match step(&inner).await {
                    Ok(Step::Progressed) => {
                        retrying_since = None;
                        continue;
                    }
                    Ok(Step::Idle) => {
                        // Upstream preparation and delivery capacity are event-driven.
                        // The existing watchdog owns oldest-undurable stage detection.
                        tokio::select! {
                            () = inner.changed.notified() => {}
                            () = accounting_retry_due(&inner) => {}
                            () = inner.channel.stopping.cancelled() => {}
                        }
                    }
                    Ok(Step::Coalescing(deadline)) => {
                        tokio::select! {
                            () = tokio::time::sleep_until(deadline) => {}
                            () = inner.changed.notified() => {}
                            () = accounting_retry_due(&inner) => {}
                            () = inner.channel.stopping.cancelled() => {}
                        }
                    }
                    Err(error) => {
                        let message = error.to_string();
                        let now = Instant::now();
                        let since = *retrying_since.get_or_insert(now);
                        if !is_retryable_write(&message)
                            || now.saturating_duration_since(since) >= RETRYABLE_BUSY_WINDOW
                        {
                            let kind = error
                                .downcast_ref::<ClassifiedWriteError>()
                                .map_or(pl_protocol::studio::HistoryFault::WriteFailed, |typed| {
                                    typed.kind
                                });
                            record_error(
                                &inner,
                                kind,
                                FaultTarget::Queued,
                                message,
                                &safe_error_reasons(&error),
                            );
                            retrying_since = None;
                        } else {
                            note_absorbed_conflict(&inner);
                            tokio::select! {
                                () = tokio::time::sleep(Duration::from_secs(1)) => {},
                                () = inner.store.thread_persistence().retry_notified() => {},
                                () = accounting_retry_due(&inner) => {},
                                () = inner.channel.stopping.cancelled() => {},
                            }
                        }
                    }
                }
            }
        }));
        drop(workers);
        Ok(Self(inner))
    }

    pub(crate) fn binding(&self) -> ThreadStorageBinding {
        ThreadStorageBinding::new(
            self.clone(),
            self.0.channel.clone(),
            self.0.conversation.clone(),
        )
    }
}

/// Performs one unit of durable work.
async fn step(inner: &Inner) -> Result<Step> {
    let _single_writer = inner.channel.step_lock.lock().await;
    {
        let mut progress = lock_progress(inner);
        // An explicit retry can arrive after an outstanding SQL call completed the fault's
        // fixed fence. Settle it even when no later effect can trigger a commit.
        if clear_recovered_fault(&mut progress) {
            report(inner, &progress);
        }
        // Another attached writer may have failed while this worker waited for step_lock.
        // The pre-lock loop check is not permission to retry that newly published generation.
        if progress.error.is_some()
            && !progress.retry_requested
            && progress.fault != Some(pl_protocol::studio::HistoryFault::QueueFull)
        {
            return Ok(Step::Idle);
        }
    }
    let selected = {
        let mut progress = lock_progress(inner);
        let resident_pressure = {
            let index = inner
                .channel
                .order_index
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            index.resident_blocked
                || HistoryChannel::other_resident_bytes(&progress)
                    .saturating_add(inner.channel.order_index.retained_bytes())
                    .saturating_add(inner.channel.delivery_bytes.load(Ordering::Acquire))
                    >= MAX_HISTORY_THREAD_BYTES
        };
        match batch::select(
            &mut progress,
            Instant::now(),
            inner.channel.process_bytes.load(Ordering::Acquire),
            resident_pressure,
        ) {
            batch::Selection::Idle => return Ok(Step::Idle),
            batch::Selection::Wait(deadline) => return Ok(Step::Coalescing(deadline)),
            batch::Selection::Ready(selected) => selected,
        }
    };
    batch::persist(inner, &selected).await?;
    let mut progress = lock_progress(inner);
    let index = inner
        .channel
        .order_index
        .inner
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut released_bytes = 0_u64;
    for candidate in &selected {
        ensure!(
            progress
                .effects
                .front()
                .is_some_and(|head| head.sequence == candidate.sequence),
            "history queue head changed before acknowledgement"
        );
        let committed = progress.effects.pop_front().expect("checked queue head");
        let bytes = committed.bytes;
        let prepared_bytes = committed.prepared_bytes;
        progress.release_saved_at(committed.write.effect.committed_at);
        progress.prepared_bytes = progress.prepared_bytes.saturating_sub(prepared_bytes);
        progress.effect_bytes -= bytes;
        released_bytes = released_bytes
            .saturating_add(bytes)
            .saturating_add(PENDING_AGE_METADATA_BYTES);
        progress.durable = committed.sequence;
    }
    progress.in_flight = None;
    // Advancing the queue head is progress even when the next head has the same stage.
    progress.stage = None;
    progress.last_progress_at = None;
    progress.refresh_head_stage(Instant::now());
    #[cfg(test)]
    let sequence = progress.durable;
    inner.channel.commit_residents(&progress, &index);
    drop(index);
    clear_recovered_fault(&mut progress);
    report(inner, &progress);
    drop(progress);
    inner.channel.release_process_bytes(released_bytes);
    inner.changed.notify_one();
    #[cfg(test)]
    {
        // Publish only after the writer's own local and queued handles were both released.
        // A terminal producer may still pin them; the history test distinguishes that owner.
        drop(selected);
        inner.channel.effects_released.send_replace(sequence);
    }
    Ok(Step::Progressed)
}

/// Seeds the absolute accounting projection at reopen; normal commits return their own result.
async fn publish_accounting(inner: &Inner, history: &HistoryStore) {
    let result = async {
        let reader = history.reader();
        let Some(accounting) = reader.accounting(None).await? else {
            return Ok(());
        };
        let mut costs = Vec::new();
        let mut cursor = None;
        loop {
            let page = reader
                .costs_page(
                    None,
                    cursor,
                    crate::history::HistoryDemand {
                        max_rows: 512,
                        max_bytes: 1024 * 1024,
                    },
                )
                .await?;
            for entry in page.entries {
                let crate::history::HistoryRowHead::Cost(cost) = entry.head else {
                    continue;
                };
                costs.push(cost);
            }
            let Some(next) = page.next else {
                break;
            };
            cursor = Some(next);
        }
        let revision = accounting
            .updated_at
            .max(costs.iter().map(|cost| cost.updated_at).max().unwrap_or(0))
            as u64;
        let mut purposes =
            std::collections::BTreeMap::<Option<String>, Vec<pl_protocol::RuntimeCostAmount>>::new(
            );
        for cost in costs {
            purposes
                .entry(cost.purpose)
                .or_default()
                .push(pl_protocol::RuntimeCostAmount {
                    currency: cost.currency,
                    amount: cost.cost_total,
                });
        }
        submit_accounting(
            inner,
            super::calls::SessionUsageProjection {
                root_thread_id: inner.thread.root_thread_id.clone(),
                thread_id: inner.thread.id.clone(),
                revision,
                has_unpriced_usage: accounting.has_unpriced_usage,
                purpose_costs: purposes
                    .into_iter()
                    .map(
                        |(purpose, estimated_costs)| super::calls::PurposeUsageProjection {
                            purpose,
                            estimated_costs,
                        },
                    )
                    .collect(),
            },
        );
        Ok::<_, anyhow::Error>(())
    }
    .await;
    if let Err(error) = result {
        tracing::warn!(%error, "读取独立累计统计投影失败");
    }
}

/// Retain only the latest committed absolute projection; retries never re-read the checkpoint.
fn submit_accounting(inner: &Inner, projection: super::calls::SessionUsageProjection) {
    {
        let mut progress = lock_progress(inner);
        if progress
            .pending_accounting
            .as_ref()
            .is_some_and(|pending| pending.projection.revision > projection.revision)
        {
            return;
        }
        progress.pending_accounting = Some(PendingAccounting {
            projection,
            attempts: 0,
            retry_at: Instant::now(),
        });
    }
    retry_accounting(inner);
    inner.changed.notify_one();
}

fn retry_accounting(inner: &Inner) {
    // Admission is synchronous and nonblocking. Keep the shared owner state locked through it so
    // overlapping writer incarnations cannot consume the same retry or overwrite a newer Summary.
    let mut progress = lock_progress(inner);
    let Some(pending) = progress.pending_accounting.as_mut() else {
        return;
    };
    if pending.retry_at > Instant::now() {
        return;
    }
    pending.attempts += 1;
    pending.retry_at = Instant::now() + Duration::from_millis(100 << (pending.attempts - 1));
    let result = inner
        .store
        .calls()
        .replace_session_usage(pending.projection.clone());
    match result {
        Ok(()) => {
            progress.pending_accounting = None;
        }
        Err(error) => {
            tracing::warn!(%error, "累计统计投影未受理，可靠会话累计值已保存");
            if pending.attempts >= 5 {
                // A bounded, explicit best-effort gap, repaired from authority at reopen.
                inner.store.calls().mark_statistics_gap();
                progress.pending_accounting = None;
            }
        }
    }
}

async fn accounting_retry_due(inner: &Inner) {
    let due = lock_progress(inner)
        .pending_accounting
        .as_ref()
        .map(|pending| pending.retry_at);
    if let Some(due) = due {
        tokio::time::sleep_until(due).await;
    } else {
        std::future::pending::<()>().await;
    }
}

/// Atomically writes one effect's history, its latest context increment and its checkpoint.
///
/// The writer consumes the same prepared completions and accounting as the live owner, without
/// projecting or extracting them again. Only this batch's persisted completion prefix is confirmed;
/// committed usage and compact accounting are published only after the transaction succeeds.
#[cfg(test)]
async fn persist_effect(
    inner: &Inner,
    sequence: u64,
    write: &ThreadWrite,
    projected: &PreparedEffect,
    encoded_effect_bytes: u64,
) -> Result<()> {
    batch::persist_one(inner, sequence, write, projected, encoded_effect_bytes).await
}

#[derive(Clone, Copy)]
enum FaultTarget {
    Queued,
    NextWrite,
}

fn record_error(
    inner: &Inner,
    kind: pl_protocol::studio::HistoryFault,
    target: FaultTarget,
    message: String,
    reasons: &[&str],
) {
    {
        let mut progress = lock_progress(inner);
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        if matches!(target, FaultTarget::NextWrite) {
            // Rejecting a ticket did not save any new fact. Equal old watermarks cannot
            // verify repair; a later successful write must cross this failure boundary.
            progress.fault_target = progress
                .fault_target
                .max(progress.durable.saturating_add(1));
        }
        progress.retry_requested = false;
        progress.fault = Some(kind);
        progress.error = Some(message);
        progress.fault_recovered = false;
        // A failed publication is no longer being serialized; the retained checkpoint stays queued
        // for retry, and the metric must not keep reporting it as actively saving.
        progress.saving_revision = 0;
        progress.in_flight_bytes = 0;
        inner.channel.diagnose(
            &progress,
            Instant::now(),
            if kind == pl_protocol::studio::HistoryFault::BlobFailed {
                "blob_fence"
            } else {
                "history_writer"
            },
            kind,
            reasons,
        );
        report(inner, &progress);
    }
    inner.changed.notify_one();
}

fn safe_error_reasons(error: &anyhow::Error) -> Vec<&'static str> {
    error
        .chain()
        .take(4)
        .map(|cause| {
            if let Some(io) = cause.downcast_ref::<std::io::Error>() {
                match io.kind() {
                    std::io::ErrorKind::NotFound => "io_not_found",
                    std::io::ErrorKind::PermissionDenied => "io_permission_denied",
                    std::io::ErrorKind::TimedOut => "io_timed_out",
                    std::io::ErrorKind::Interrupted => "io_interrupted",
                    _ => "io_error",
                }
            } else if cause.is::<sea_orm::DbErr>() {
                "database_error"
            } else if cause.is::<sqlx::Error>() {
                "sql_driver_error"
            } else if cause.is::<ClassifiedWriteError>() {
                "classified_history_error"
            } else {
                "redacted_error"
            }
        })
        .collect()
}

/// Keeps the observable metrics honest while one retryable conflict is absorbed.
///
/// The failed step is no longer writing, so the in-flight byte gauge must not keep claiming a write
/// in progress; the queued effects stay counted, so the process-wide drain still waits and this
/// incarnation never looks settled. No error is published, so `pressure()`/`cold_error` stay clear
/// and the next model admission is not failed by a conflict the writer is still resolving.
fn note_absorbed_conflict(inner: &Inner) {
    let mut progress = lock_progress(inner);
    progress.in_flight_bytes = 0;
    progress.saving_revision = 0;
    report(inner, &progress);
}

impl ThreadStorageSink {
    fn storage_status(&self, thread_id: &str, inspect_idle: bool) -> StorageIdleStatus {
        if thread_id != self.0.thread.id {
            return StorageIdleStatus {
                pressure: StoragePressure {
                    error: Some(storage_error("Thread persistence owner mismatch")),
                    ..Default::default()
                },
                reclaimable_thread_bytes: None,
            };
        }
        let progress = lock_progress(&self.0);
        // The Thread's budget covers every resident body this Thread presents, and one of them only
        // once: the effects still queued, the prepared product batches the reliable handoff still
        // retains (the writer's queue length alone would under-report a Thread whose projection is
        // already done but whose save is not), the bodies its live projection and report accumulator
        // keep after their batch became durable, and the accepted bytes retained by in-flight
        // model/tool output. Those accepted bytes are what a Thread about to publish its result
        // holds; leaving them out would report a Thread as idle while a call is buffering its answer.
        let reserved = progress
            .operation_output
            .values()
            .fold(0_u64, |total, output| {
                total.saturating_add(output.retained())
            });
        let delivery_bytes = self.0.channel.delivery_bytes.load(Ordering::Acquire);
        let (index_bytes, reclaimable) = if inspect_idle {
            let index = self
                .0
                .channel
                .order_index
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            let index_bytes = self.0.channel.order_index.retained_bytes();
            // A durable projection is reconstructible, but an unfinished source, handoff,
            // delivery or output reservation remains an obligation of this incarnation.
            let reclaimable = if progress.effects.is_empty()
                && progress.in_flight.is_none()
                && progress.projection_pending.is_none()
                && progress.operation_output.is_empty()
                && delivery_bytes == 0
                && self.0.channel.delivery_admissions.load(Ordering::Acquire) == 0
                && index.by_source.is_empty()
                && index.pending.is_empty()
                && index.dirty.is_empty()
            {
                Some(progress.projection_bytes.saturating_add(index_bytes))
            } else {
                None
            };
            (index_bytes, reclaimable)
        } else {
            // Ordinary pressure reads stay on the existing atomic accounting path.
            (self.0.channel.order_index.retained_bytes(), None)
        };
        let bytes = progress
            .effect_bytes
            .saturating_add(progress.queue_metadata_bytes)
            .saturating_add(progress.prepared_bytes)
            .saturating_add(progress.projection_bytes)
            .saturating_add(index_bytes)
            .saturating_add(delivery_bytes)
            .saturating_add(reserved);
        let pressure = StoragePressure {
            thread_bytes: bytes,
            store_bytes: self.0.channel.process_bytes.load(Ordering::Acquire),
            // Typed durability receipt: the owner releases the live effect window from this at a
            // storage safety point instead of waiting for an explicit `flush` command.
            durable_sequence: progress.durable,
            // Typed fault category: the history channel already classifies its own failure, so no
            // consumer has to read the error text to know what failed.
            fault: progress.fault.map(storage_fault_kind),
            fault_generation: progress.fault_generation,
            // The writer's own recovery receipt, named by generation: `fault_recovered` means the
            // retry of *this* generation reached the fixed durable target, so the owner can require
            // that exact verdict before releasing the fault it holds instead of accepting an older
            // generation's success.
            recovered_generation: progress
                .fault_recovered
                .then_some(progress.fault_generation),
            error: progress.error.as_deref().map(storage_error),
        };
        StorageIdleStatus {
            pressure,
            reclaimable_thread_bytes: reclaimable,
        }
    }
}

impl ThreadStorageSink {
    pub(crate) fn reserve_observed_item(
        &self,
        thread_id: &str,
        attempt_id: &str,
        item_id: &str,
    ) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence owner mismatch")),
            });
        }
        // The kernel reserves a raw provider presentation identity synchronously, before a
        // coalescing preview can discard it. The Runtime's own execution-order index answers:
        // the live projection draws from the same index, so the preview frame and the terminal
        // commit of one identity always resolve the same ordinal without a second allocator.
        let result = self
            .0
            .channel
            .order_index
            .reserve_observed(attempt_id, item_id);
        if let Err(error) = &result {
            record_error(
                &self.0,
                if error.is::<ExecutionIndexBudgetFull>() {
                    pl_protocol::studio::HistoryFault::QueueFull
                } else {
                    pl_protocol::studio::HistoryFault::WriteFailed
                },
                FaultTarget::Queued,
                error.to_string(),
                &safe_error_reasons(error),
            );
        } else {
            let progress = lock_progress(&self.0);
            report(&self.0, &progress);
        }
        result.map(|_| ()).map_err(|source| ColdStoreError {
            source: source.into_boxed_dyn_error(),
        })
    }

    pub(crate) fn subscribe_pressure(
        &self,
        thread_id: &str,
    ) -> Option<tokio::sync::watch::Receiver<()>> {
        (thread_id == self.0.thread.id).then(|| self.0.channel.pressure_changed.subscribe())
    }

    pub(crate) fn reserve_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        max_bytes: u64,
    ) -> Result<u64, ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(cold_error("Thread persistence owner mismatch"));
        }
        self.0
            .channel
            .reserve_operation_output(operation_id, max_bytes)
            .ok_or_else(|| {
                // No headroom is backpressure, not a failed save: the caller waits at a storage
                // safety point and retries, and the Thread resumes by itself once the budget frees
                // up. Latching a hard fault here would turn a transient wait into a pause that only
                // an explicit resume could release.
                cold_error(&format!(
                    "reliable budget exhausted reserving operation {operation_id}"
                ))
            })
    }

    pub(crate) fn charge_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(cold_error("Thread persistence owner mismatch"));
        }
        // The typed refusal a ceiling cannot hold must reach the caller unchanged: it is what makes
        // the producer cancel the call with the bytes it already has instead of buffering output
        // this process could not retain.
        self.0
            .channel
            .charge_operation_output(operation_id, accepted_bytes)
    }

    pub(crate) fn release_operation_output(&self, thread_id: &str, operation_id: &str) {
        if thread_id == self.0.thread.id {
            self.0.channel.release_operation_output(operation_id);
        }
    }

    pub(crate) fn pressure(&self, thread_id: &str) -> StoragePressure {
        self.storage_status(thread_id, false).pressure
    }

    pub(crate) fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        self.storage_status(thread_id, true)
    }

    pub(crate) fn admit_export(
        &self,
        thread_id: &str,
        write: HistoryExport,
    ) -> Result<(), ColdStoreError> {
        if self.0.channel.stopping.is_cancelled() {
            return Err(cold_error("history writer is stopped"));
        }
        if thread_id != self.0.thread.id
            || write.effect.thread_id != thread_id
            || write.effect.thread_id != thread_id
            || write.effect.sequence == 0
        {
            // A contract failure is terminal for this sink and never a transient conflict: publish it
            // so `pressure().error` — the one report core mirrors into its own storage latch — agrees
            // with the error this call returns instead of letting the latch look recovered.
            record_error(
                &self.0,
                pl_protocol::studio::HistoryFault::WriteFailed,
                FaultTarget::NextWrite,
                "Thread persistence ticket mismatch".to_owned(),
                &["ticket_mismatch"],
            );
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence ticket mismatch")),
            });
        }
        let sequence = write.effect.sequence;
        #[cfg(feature = "benchmarks")]
        self.0
            .store
            .calls()
            .observation()
            .increment(BenchMetric::EffectEncode);
        let bytes = encoded_bytes(&write.effect);
        let mut progress = lock_progress(&self.0);
        if progress.stopped {
            return Err(cold_error("history writer is stopped"));
        }
        if sequence > progress.durable && progress.queue_offset(sequence).is_none() {
            let expected = progress.effects.back().map_or_else(
                || progress.durable.checked_add(1),
                |tail| tail.sequence.checked_add(1),
            );
            if expected != Some(sequence) {
                let message = format!(
                    "Thread {thread_id} persistence sequence {sequence} does not follow {}",
                    expected.map_or_else(
                        || "the exhausted sequence space".to_owned(),
                        |expected| { format!("write_seq {expected}") }
                    )
                );
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(pl_protocol::studio::HistoryFault::WriteFailed);
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                report(&self.0, &progress);
                drop(progress);
                self.0.changed.notify_one();
                return Err(cold_error(&message));
            }
            let mut index = self
                .0
                .channel
                .order_index
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            let queued_bytes = progress
                .effect_bytes
                .saturating_add(progress.queue_metadata_bytes)
                .saturating_add(self.0.channel.order_index.retained_bytes());
            // The fact takes over the bytes of its own operation's reservation instead of being
            // charged next to them; only bytes not already charged need new headroom.
            let (transfer, covered) = output_transfer_plan(
                &progress,
                None,
                bytes.saturating_add(PENDING_AGE_METADATA_BYTES),
            );
            let added = bytes
                .saturating_add(PENDING_AGE_METADATA_BYTES)
                .saturating_sub(covered);
            // Preserve the admission checks' short-circuit order. In particular, never reserve
            // process bytes when an earlier limit refuses the ticket, or reserve twice for logging.
            let rejection_kind = if progress.effects.len() >= MAX_HISTORY_BATCHES {
                Some("slot")
            } else if queued_bytes
                .checked_add(bytes.saturating_add(PENDING_AGE_METADATA_BYTES))
                .is_none_or(|total| total > MAX_HISTORY_THREAD_BYTES)
            {
                Some("thread_bytes")
            } else if added > 0 && !self.0.channel.reserve(added) {
                Some("process_budget")
            } else {
                None
            };
            if let Some(rejection_kind) = rejection_kind {
                let message =
                    format!("history queue full for Thread {thread_id} at write_seq {sequence}");
                tracing::debug!(
                    target: "conversation_work",
                    operation = "history_admission",
                    rejection_kind,
                    thread_id,
                    write_seq = sequence,
                    queued_effects = progress.effects.len(),
                    // Same retained-byte scope as the Thread admission check, not the broader
                    // pressure gauge that also includes projection/prepared/output residents.
                    queued_thread_bytes = queued_bytes,
                    effect_bytes = bytes,
                    thread_bytes_increment = bytes.saturating_add(PENDING_AGE_METADATA_BYTES),
                    process_bytes_increment = added,
                    // Other Threads can change this atomic after reserve refused; this is an
                    // observation, not the failed compare/update's exact budget value.
                    process_bytes_observed = self.0.channel.process_bytes.load(Ordering::Acquire),
                    head = ?progress.effects.front().map(|effect| effect.sequence),
                    admitted = progress.effects.back().map_or(progress.durable, |effect| effect.sequence),
                    durable = progress.durable,
                    stage = ?progress.stage.map(HistoryStage::as_str),
                    fault_generation = progress.fault_generation,
                    "history admission refused"
                );
                drop(index);
                report(&self.0, &progress);
                self.0.changed.notify_one();
                return Err(ColdStoreError {
                    source: Box::new(pl_core::thread::cold::StorageAdmissionBackpressure(message)),
                });
            }
            if let Err(error) = self.0.channel.order_index.reserve_boundaries_locked(
                &mut index,
                &write.effect,
                added,
            ) {
                // Roll back only this admission's process claim; notifications follow the locks.
                self.0
                    .channel
                    .process_bytes
                    .fetch_sub(added, Ordering::AcqRel);
                let message = error.to_string();
                if error.is::<ExecutionIndexBudgetFull>() {
                    drop(index);
                    report(&self.0, &progress);
                    self.0.changed.notify_one();
                    return Err(ColdStoreError {
                        source: Box::new(pl_core::thread::cold::StorageAdmissionBackpressure(
                            message,
                        )),
                    });
                }
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(pl_protocol::studio::HistoryFault::WriteFailed);
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                drop(index);
                report(&self.0, &progress);
                self.0.changed.notify_one();
                return Err(cold_error(&message));
            }
            #[cfg(test)]
            self.0.channel.pause_resident_commit();
            for (operation, taken) in transfer {
                if let Some(output) = progress.operation_output.get_mut(&operation) {
                    output.transferred += taken;
                }
            }
            let admitted_at = Instant::now();
            progress.effects.push_back(QueuedEffect {
                _conversation: Some(self.0.conversation.clone()),
                sequence,
                admitted_at,
                write: Arc::new(write.clone()),
                bytes,
                // The projection owner takes this entry over from the same queue, in this order.
                prepared: None,
                prepared_bytes: 0,
            });
            progress.refresh_head_stage(admitted_at);
            progress.effect_bytes += bytes;
            progress.admit_saved_at(write.effect.committed_at);
            self.0.channel.commit_residents(&progress, &index);
            drop(index);
        }
        // 首次受理从 checkpoint 继承已折叠的累计摘要，然后只折叠本 incarnation 的新 effect。
        if progress.usage.applied_sequence == 0 && write.state.usage_summary.applied_sequence > 0 {
            progress.usage = write.state.usage_summary.clone();
        }
        progress.pressure_paused = write.state.persistence.pressure_paused;
        report(&self.0, &progress);
        drop(progress);
        self.0.changed.notify_one();
        Ok(())
    }

    pub(crate) async fn flush(&self, thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        tracing::debug!(
            target: "conversation_work",
            thread_id,
            flush_requests = 1,
            "thread flush requested"
        );
        if thread_id != self.0.thread.id {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence owner mismatch")),
            });
        }
        // 固定目标只需等待它自己的 effect durable：checkpoint 与该 effect 在同一事务落盘，所以
        // durable 前进即意味着目标 checkpoint 也已提交，不再有独立的发布水位要等。
        self.0.channel.request_flush(sequence);
        let coordinator = self.0.store.thread_persistence().clone();
        let mut progress = coordinator.subscribe();
        // 第二个失败来源是可靠受理通道自己的状态：一个投影无法完成的事实永远到不了协调器的
        // 水位，只有通道会带着投影的真实原因报告它。只等协调器会把这种失败变成永久挂起，
        // 因此两处都必须唤醒这次屏障。
        let mut status = self.0.channel.subscribe();
        loop {
            {
                let local = lock_progress(&self.0);
                // The effect and its checkpoint commit atomically, so durable covers both: a released
                // owner never leaves an effect whose checkpoint is not yet committed behind.
                if local.durable >= sequence {
                    return Ok(());
                }
                if let Some(error) = local.error.clone() {
                    return Err(ColdStoreError {
                        source: Box::new(std::io::Error::other(error)),
                    });
                }
            }
            tokio::select! {
                changed = progress.changed() => {
                    changed.map_err(|_| ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "Thread persistence progress channel closed",
                        )),
                    })?;
                }
                changed = status.changed() => {
                    changed.map_err(|_| ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "Thread history status channel closed",
                        )),
                    })?;
                }
            }
        }
    }

    pub(crate) fn read_tool_task(
        &self,
        thread_id: &str,
        task_id: &str,
    ) -> impl std::future::Future<
        Output = Result<Option<pl_core::thread::cold::DurableToolTask>, ColdStoreError>,
    > + Send {
        let store = self.0.store.clone();
        let owner = self.0.thread.id.clone();
        let task_id = task_id.to_owned();
        async move {
            if thread_id != owner {
                return Err(cold_error("Thread persistence owner mismatch"));
            }
            let paths = store
                .registered_session_paths(&owner)
                .map_err(|error| cold_error(&error.to_string()))?;
            let state = store
                .state_for(paths.workspace_id(), &owner)
                .map_err(|error| cold_error(&error.to_string()))?;
            let current = state
                .load_current()
                .await
                .map_err(|error| cold_error(&error.to_string()))?
                .ok_or_else(|| cold_error("complete current is missing"))?;
            Ok(current.state.tasks.get(&task_id).cloned().map(|task| {
                pl_core::thread::cold::DurableToolTask {
                    delivery: current
                        .state
                        .deliveries
                        .iter()
                        .find(|delivery| delivery.call_id == task.call_id)
                        .cloned(),
                    task,
                }
            }))
        }
    }
}

fn storage_error(message: &str) -> Arc<ColdStoreError> {
    Arc::new(ColdStoreError {
        source: Box::new(std::io::Error::other(message.to_owned())),
    })
}

/// The protocol's typed history fault as the core storage fault the owner mirrors.
///
/// Both sides are already typed values: this is a rename, not a classification. Core therefore never
/// sees an error string that it would have to interpret to know what failed.
fn storage_fault_kind(
    fault: pl_protocol::studio::HistoryFault,
) -> pl_core::thread::cold::StorageFaultKind {
    use pl_core::thread::cold::StorageFaultKind;
    use pl_protocol::studio::HistoryFault;
    match fault {
        HistoryFault::QueueFull => StorageFaultKind::QueueFull,
        HistoryFault::WriteFailed => StorageFaultKind::WriteFailed,
        HistoryFault::WriterUnavailable => StorageFaultKind::WriterUnavailable,
        HistoryFault::NoProgress => StorageFaultKind::NoProgress,
        HistoryFault::CheckpointFailed => StorageFaultKind::CheckpointFailed,
        HistoryFault::BlobFailed => StorageFaultKind::BlobFailed,
    }
}

/// One typed cold-store failure without the shared-error wrapper.
fn cold_error(message: &str) -> ColdStoreError {
    ColdStoreError {
        source: Box::new(std::io::Error::other(message.to_owned())),
    }
}

#[cfg(test)]
impl ColdStore for ThreadStorageSink {
    fn admit(&self, thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.admit_export(
            thread_id,
            HistoryExport {
                effect: write.effect,
                state: write.checkpoint.state,
            },
        )
    }
    async fn flush(&self, thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
        ThreadStorageSink::flush(self, thread_id, sequence).await
    }
    fn pressure(&self, thread_id: &str) -> StoragePressure {
        ThreadStorageSink::pressure(self, thread_id)
    }
    fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        ThreadStorageSink::idle_status(self, thread_id)
    }
    fn subscribe_pressure(&self, thread_id: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        ThreadStorageSink::subscribe_pressure(self, thread_id)
    }
    fn reserve_observed_item(
        &self,
        thread_id: &str,
        attempt: &str,
        item: &str,
    ) -> Result<(), ColdStoreError> {
        ThreadStorageSink::reserve_observed_item(self, thread_id, attempt, item)
    }
    fn reserve_operation_output(
        &self,
        thread_id: &str,
        operation: &str,
        bytes: u64,
    ) -> Result<u64, ColdStoreError> {
        ThreadStorageSink::reserve_operation_output(self, thread_id, operation, bytes)
    }
    fn charge_operation_output(
        &self,
        thread_id: &str,
        operation: &str,
        bytes: u64,
    ) -> Result<(), ColdStoreError> {
        ThreadStorageSink::charge_operation_output(self, thread_id, operation, bytes)
    }
    fn release_operation_output(&self, thread_id: &str, operation: &str) {
        ThreadStorageSink::release_operation_output(self, thread_id, operation)
    }
    fn read_tool_task(
        &self,
        thread_id: &str,
        task: &str,
    ) -> impl std::future::Future<
        Output = Result<Option<pl_core::thread::cold::DurableToolTask>, ColdStoreError>,
    > + Send {
        ThreadStorageSink::read_tool_task(self, thread_id, task)
    }
}
#[cfg(test)]
pub(crate) mod storage_fault_tests {
    use super::*;
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        thread::{
            ThreadCheckpoint, ThreadSnapshot, TurnOutcome, TurnRecord, TurnState,
            current::RuntimeEpoch,
            input::{InputChange, InputRecord, InputState, ThreadInput},
        },
    };

    pub(crate) fn ticket(thread_id: &str, sequence: u64) -> ThreadWrite {
        let state = ThreadSnapshot {
            commit_sequence: sequence,
            ..Default::default()
        };
        ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread_id.to_owned(),
                sequence,
                committed_at: 1,
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread_id.to_owned(), sequence, state),
            output_claim: None,
        }
    }

    pub(super) fn test_thread(thread_id: &str) -> pl_protocol::Thread {
        let mut thread = pl_protocol::Thread::placeholder(thread_id);
        thread.workspace_id = "project-test".into();
        thread.agent_path = thread_id.to_owned();
        thread.root_thread_id = thread_id.to_owned();
        thread
    }

    pub(crate) async fn register_test_thread(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
    ) -> Result<()> {
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: thread.workspace_id.clone(),
                kind: pl_protocol::studio::WorkspaceKind::Project,
                name: "Test".into(),
                path: "/tmp/project-test".into(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        let (session, agent) = crate::studio::records::directory_facts_from_thread(thread);
        if let Some(session) = session {
            delta.session_upserts = vec![session];
        }
        delta.agent_upserts = vec![agent];
        store.persist_directory_summaries(&delta).await
    }

    pub(crate) struct CloseFactoryFixture {
        pub(crate) factory: crate::studio::StudioThreadFactory,
        pub(in crate::studio) writer: crate::studio::agent_host::ThreadWriteBehindWriter,
        pub(crate) config: crate::config::ConfigRuntime,
        pub(crate) events: crate::studio::ProductEventBus,
        store: StudioStore,
        worktrees: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner,
    }

    impl CloseFactoryFixture {
        pub(crate) async fn unpublished_workspace(
            &self,
            id: &str,
            root: &std::path::Path,
        ) -> Result<crate::thread_assembler::WorkspacePreparationOwner> {
            use crate::studio::agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
            let usage = self
                .worktrees
                .reserve_workspace(id, WorkspaceEndpoint::Local)?;
            let identity = WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                dunce::canonicalize(root)?.to_string_lossy().into_owned(),
            )?;
            self.worktrees.assign_workspace(&usage, identity.clone())?;
            self.store.bind_workspace_identity(id, &identity).await?;
            self.worktrees.preserve_workspace_resources(id, identity);
            let files = root.join(pl_tool::workspace::SessionFiles::new(id).root());
            tokio::fs::create_dir_all(files.join("scratch")).await?;
            tokio::fs::write(files.join("scratch/prepared"), b"unpublished owned file").await?;
            let preparation = crate::thread_assembler::WorkspacePreparationOwner::default();
            preparation.retain(&usage);
            Ok(preparation)
        }

        pub(crate) fn workspace_is_busy(&self, id: &str) -> bool {
            self.worktrees.ensure_thread_workspace_idle(id).is_err()
        }

        pub(crate) fn install(
            &self,
            owner: &crate::thread_assembler::SessionRuntime,
        ) -> Result<()> {
            let performance = crate::studio::ModelPerformanceOwner::new(
                self.store.clone(),
                self.events.clone(),
                "close-fault-fixture".into(),
            );
            owner.set_agent_services(
                self.config.clone(),
                self.store.clone(),
                self.events.clone(),
                self.factory.clone(),
                performance,
                crate::studio::StudioRecoveryRegistry::new(),
            )?;
            Ok(())
        }

        pub(crate) async fn shutdown(&self) -> Result<()> {
            self.writer.shutdown().await?;
            Ok(())
        }
    }

    pub(crate) fn close_factory(store: &StudioStore) -> Result<CloseFactoryFixture> {
        use crate::studio::thread_factory::{StudioThreadFactory, StudioThreadServices};
        let writer = crate::studio::agent_host::ThreadWriteBehindWriter::new(store.clone());
        let events = crate::studio::ProductEventBus::new(store.clone(), writer.clone());
        let config = crate::config::ConfigRuntime::initialize(crate::config::ConfigStore::new(
            crate::config::ConfigPaths::from_config_dir(
                store.paths().home().join("isolated-test-config"),
            ),
        ))?;
        let source = crate::worker_assets::RemoteHelperSource::External;
        let bots =
            crate::bots::BotRuntime::new(store.paths().clone(), config.clone(), events.clone())?;
        let worktrees =
            crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
        let factory = StudioThreadFactory::new(StudioThreadServices {
            store: store.clone(),
            worktrees: worktrees.clone(),
            recovery: crate::studio::StudioRecoveryRegistry::new(),
            product_events: events.clone(),
            config_runtime: config.clone(),
            mcp_connector: pl_tool::mcp::McpConnector::default(),
            lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry::new(),
            local_executor: pl_remote_helper::Executor::local()?,
            skills: crate::studio::runtime::SkillCatalogRuntime::new(
                events.clone(),
                store.paths().home().join("isolated-test-skills"),
                pl_remote_helper::Executor::local()?,
                Default::default(),
            ),
            thread_modes: config.thread_mode_manager(),
            ssh_manager: Arc::new(crate::worker_assets::ssh_manager(&source)),
            helper_source: source,
            bots,
            run_export: None,
        });
        Ok(CloseFactoryFixture {
            factory,
            writer,
            config,
            events,
            store: store.clone(),
            worktrees,
        })
    }

    /// Drives the real projection for a writer-only sink. Current publication belongs to
    /// ConversationStore; these writer fixtures hand only append-only history facts to the queue.
    pub(crate) fn spawn_live_projection(sink: &ThreadStorageSink) {
        drop(spawn_projection(
            sink.0.store.clone(),
            sink.0.thread.clone(),
        ));
    }

    pub(crate) fn spawn_live_projection_for_thread(
        store: StudioStore,
        id: &str,
    ) -> tokio::task::JoinHandle<()> {
        let catalog = store.catalog();
        let agent = catalog.get_agent(id).expect("registered projection agent");
        let session = catalog
            .get_session(&agent.session_id)
            .expect("registered projection session");
        let thread = crate::studio::records::thread_projection(&session, &agent, |id| {
            catalog.get_agent(id).map(|agent| agent.thread_id)
        })
        .expect("Native projection");
        spawn_projection(store, thread)
    }

    fn spawn_projection(
        store: StudioStore,
        thread: pl_protocol::Thread,
    ) -> tokio::task::JoinHandle<()> {
        let channel = store.thread_persistence().history_channel(&thread.id);
        tokio::spawn(async move {
            let mut projection = crate::studio::thread_projection::LiveProjection::new();
            projection
                .bind_execution_history(
                    channel.order_index(),
                    RuntimeEpoch::new(),
                    store.history(&thread.id).await.expect("history owner"),
                )
                .expect("one projection binding");
            let mut failed = std::collections::BTreeSet::new();
            let mut updates = channel.subscribe();
            loop {
                if channel.stopping.is_cancelled() {
                    return;
                }
                if let Some(write) = channel.next_unprojected() {
                    let sequence = write.effect.sequence;
                    if failed.contains(&sequence) {
                        tokio::time::sleep(Duration::from_millis(5)).await;
                        continue;
                    }
                    if !write.effect.delivery_repairs.is_empty()
                        && crate::studio::thread_projection::seed_repaired_targets(
                            &mut projection,
                            &store.history(&thread.id).await.expect("history owner"),
                            &write.effect,
                        )
                        .await
                        .is_err()
                    {
                        failed.insert(sequence);
                        channel.fail_projection(sequence, "repair seeding failed".into());
                        continue;
                    }
                    match projection
                        .prepare_committed(&thread, &write.effect, &write.checkpoint.state)
                        .await
                    {
                        Ok(prepared) => {
                            channel.prepare(strip_current(prepared));
                        }
                        Err(error) => {
                            failed.insert(sequence);
                            channel.fail_projection(sequence, error.to_string());
                        }
                    }
                    continue;
                }
                tokio::select! {
                    changed = updates.changed() => if changed.is_err() { return; },
                    () = channel.stopping.cancelled() => return,
                }
            }
        })
    }

    fn strip_current(prepared: Arc<PreparedEffect>) -> Arc<PreparedEffect> {
        let mut handed = (*prepared).clone();
        handed.current_state = None;
        Arc::new(handed)
    }

    async fn saved_current(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
    ) -> Result<Option<pl_core::thread::current::ThreadCurrent>> {
        let paths = store.registered_session_paths(&thread.id)?;
        Ok(store
            .state_for(paths.workspace_id(), &thread.id)?
            .load_current()
            .await?)
    }

    pub(super) async fn live_projection(
        sink: &ThreadStorageSink,
    ) -> Result<crate::studio::thread_projection::LiveProjection> {
        let current = saved_current(&sink.0.store, &sink.0.thread).await?;
        let epoch = match current {
            Some(current) => current.saved_runtime_epoch,
            None => RuntimeEpoch::new(),
        };
        let mut projection = crate::studio::thread_projection::LiveProjection::new();
        projection.bind_execution_history(
            sink.0.channel.order_index(),
            epoch,
            sink.0.store.history(&sink.0.thread.id).await?,
        )?;
        Ok(projection)
    }

    pub(crate) async fn save_terminal_report(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
        message: pl_core::thread::inbox::ThreadMessage,
    ) -> Result<()> {
        let saved = saved_current(store, thread).await?;
        let sequence = saved
            .as_ref()
            .map_or(1, |current| current.snapshot_revision + 1);
        let mut snapshot = saved
            .as_ref()
            .map_or_else(ThreadSnapshot::default, |current| {
                current.state.to_paused_snapshot()
            });
        snapshot.commit_sequence = sequence;
        let turn = TurnRecord {
            turn_id: "original-terminal-turn".into(),
            input_id: None,
            state: TurnState::Finished(TurnOutcome::Completed),
            model_steps: 0,
            elapsed_ms: None,
        };
        snapshot.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
        snapshot.turns = Arc::from([turn.clone()]);
        let terminal = ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence,
                committed_at: 1,
                turn: Some(turn),
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), sequence, snapshot),
            output_claim: None,
        };
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let mut projection = live_projection(&sink).await?;
        let prepared = projection
            .prepare_committed(thread, &terminal.effect, &terminal.checkpoint.state)
            .await?;
        let mut handed = (*prepared).clone();
        handed.current_state = None;
        handed.parent_report = Some(Arc::new(message));
        let handed = Arc::new(handed);
        sink.admit(&thread.id, terminal)?;
        sink.0.channel.prepare(handed);
        sink.flush(&thread.id, sequence).await?;
        sink.0.channel.stop_and_join().await
    }

    pub(crate) fn visible_input_ticket(
        thread_id: &str,
        sequence: u64,
        input_id: &str,
    ) -> Result<ThreadWrite> {
        let mut write = ticket(thread_id, sequence);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: sequence,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: input_id.to_owned(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({
                        "text": "hello",
                        "presentation": "visible",
                        "attachments": [],
                    })
                    .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "hello".into(),
                }],
            },
            ordinal: sequence,
            revision: sequence,
            state: InputState::Consumed {
                turn_id: "visible-turn".into(),
                attempt_id: "attempt".into(),
            },
        };
        write.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Ok(write)
    }
}

#[cfg(test)]
mod writer_tests {
    use super::storage_fault_tests::{
        live_projection, register_test_thread, test_thread, ticket, visible_input_ticket,
    };
    use super::*;
    use crate::history::{HistoryDemand, HistoryEventsQuery};
    use pl_core::thread::current::RuntimeEpoch;
    use sea_orm::{ConnectionTrait, Database};

    struct Fixture {
        _temp: tempfile::TempDir,
        store: StudioStore,
        sink: ThreadStorageSink,
        projection: crate::studio::thread_projection::LiveProjection,
    }

    impl Fixture {
        async fn new(id: &str) -> Result<Self> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            register_test_thread(&store, &test_thread(id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
            let projection = live_projection(&sink).await?;
            Ok(Self {
                _temp: temp,
                store,
                sink,
                projection,
            })
        }

        async fn handoff(&mut self, write: &ThreadWrite) -> Result<Arc<PreparedEffect>> {
            let id = self.sink.0.thread.id.clone();
            self.sink.admit(&id, write.clone())?;
            let prepared = self
                .projection
                .prepare_committed(&self.sink.0.thread, &write.effect, &write.checkpoint.state)
                .await?;
            let mut handed = (*prepared).clone();
            handed.current_state = None;
            let handed = Arc::new(handed);
            ensure!(
                self.sink.0.channel.prepare(handed.clone()),
                "handoff refused"
            );
            Ok(handed)
        }

        fn select(&self, now: Instant) -> batch::Selection {
            batch::select(&mut lock_progress(&self.sink.0), now, 0, false)
        }

        async fn finish(self, sequence: u64) -> Result<()> {
            self.sink
                .flush(&self.sink.0.thread.id.as_str(), sequence)
                .await?;
            self.sink.0.channel.stop_and_join().await
        }
    }

    fn ready(selection: batch::Selection) -> Vec<batch::Effect> {
        match selection {
            batch::Selection::Ready(effects) => effects,
            _ => panic!("expected a frozen prepared prefix"),
        }
    }

    fn sqlite_literal(value: &str) -> String {
        format!("'{}'", value.replace('\'', "''"))
    }

    #[tokio::test]
    async fn queue_retention_is_charged_once_and_released_only_after_flush() -> Result<()> {
        let mut fixture = Fixture::new("queue-retention").await?;
        let id = fixture.sink.0.thread.id.clone();
        let process = fixture.sink.0.channel.process_bytes.clone();
        let baseline = process.load(Ordering::Acquire);
        let write = visible_input_ticket(&id, 1, "queue-input")?;
        fixture.sink.admit(&id, write)?;
        let admitted = process.load(Ordering::Acquire);
        let status = fixture.sink.0.channel.subscribe().borrow().clone();
        assert_eq!(status.queued_records, 1);
        assert!(status.queued_bytes > 0);
        assert!(admitted > baseline);

        let prepared = fixture.handoff(&write).await?;
        assert!(prepared.retained_bytes() > 0);
        assert_eq!(
            process.load(Ordering::Acquire),
            admitted,
            "projection handoff must transfer, not add, the reliable charge"
        );
        assert_eq!(
            fixture.sink.0.channel.subscribe().borrow().queued_records,
            1,
            "the original admission remains queued until the database commit"
        );

        fixture.finish(1).await?;
        assert_eq!(process.load(Ordering::Acquire), baseline);
        assert_eq!(
            fixture.sink.0.channel.subscribe().borrow().queued_records,
            0
        );
        Ok(())
    }

    #[tokio::test]
    async fn sql_failure_rolls_back_and_retries_the_same_frozen_events_and_bodies() -> Result<()> {
        let id = "batch-atomic-retry";
        let mut fixture = Fixture::new(id).await?;
        let first = visible_input_ticket(id, 1, "input-1")?;
        fixture.handoff(&first).await?;
        fixture.sink.flush(id, 1).await?;

        let path = fixture
            .store
            .session_paths("project-test", id)?
            .history_database();
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        let second = visible_input_ticket(id, 2, "input-2")?;
        let third = visible_input_ticket(id, 3, "input-3")?;
        let prepared_second = fixture.handoff(&second).await?;
        let prepared_third = fixture.handoff(&third).await?;
        let rejected_event = prepared_third.history_changes[0]
            .event
            .header
            .event_id
            .clone();
        db.execute_unprepared(&format!(
            "CREATE TRIGGER reject_third_effect BEFORE INSERT ON history_events \
             WHEN NEW.event_id = {} BEGIN \
             SELECT RAISE(ABORT, 'reject third batch member'); END",
            sqlite_literal(&rejected_event)
        ))
        .await?;

        let channel = fixture.sink.0.channel.clone();
        let mut status = channel.subscribe();
        fixture.sink.flush(id, 3).await?;
        while status.borrow_and_update().fault.is_none() {
            status.changed().await?;
        }
        let generation = status.borrow().fault_generation;
        assert!(
            fixture
                .store
                .history(id)
                .await?
                .status()
                .write_error
                .is_some()
        );

        let gate = channel.step_lock.lock().await;
        let fourth = ticket(id, 4);
        fixture.sink.admit(id, fourth.clone())?;
        let retried = ready(fixture.select(Instant::now()));
        assert_eq!(
            retried.len(),
            2,
            "new queued work cannot alter the failed transaction"
        );
        assert!(Arc::ptr_eq(&retried[0].prepared, &prepared_second));
        assert!(Arc::ptr_eq(&retried[1].prepared, &prepared_third));

        let originals: Vec<_> = [&prepared_second, &prepared_third]
            .into_iter()
            .flat_map(|prepared| prepared.history_changes.iter())
            .map(|change| {
                let event_id = change.event.header.event_id.clone();
                let body_id = change
                    .event
                    .payload_body_id
                    .clone()
                    .or_else(|| change.event.bodies.first().map(|body| body.body_id.clone()))
                    .expect("visible history change has a body");
                (event_id, body_id)
            })
            .collect();
        db.execute_unprepared("DROP TRIGGER reject_third_effect")
            .await?;
        drop(gate);
        fixture
            .store
            .thread_persistence()
            .retry_history(id, generation)
            .await?;
        while status.borrow_and_update().error.is_some() {
            status.changed().await?;
        }
        assert_eq!(lock_progress(&fixture.sink.0).durable, 3);

        let reader = fixture.store.history(id).await?.reader();
        for (event_id, body_id) in originals {
            let event = reader
                .read_event(
                    event_id,
                    HistoryDemand {
                        max_rows: 1,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            assert_eq!(
                event.payload_ref.expect("event body").body_id,
                body_id,
                "retry must commit the accepted immutable body identity"
            );
        }
        fixture.handoff(&fourth).await?;
        fixture.finish(4).await?;
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn stopped_writer_joins_workers_and_history_reopens_with_a_new_owner() -> Result<()> {
        let id = "retirement-writer-join";
        let mut fixture = Fixture::new(id).await?;
        let channel = fixture.sink.0.channel.clone();
        let write = ticket(id, 1);
        fixture.handoff(&write).await?;
        fixture.sink.flush(id, 1).await?;

        let (release, released) = tokio::sync::oneshot::channel();
        channel.workers.lock().await.push(tokio::spawn(async move {
            let _ = released.await;
        }));
        let waiter_channel = channel.clone();
        let waiter = tokio::spawn(async move { waiter_channel.stop_and_join().await });
        channel.stopping.cancelled().await;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        assert!(
            !channel.workers.lock().await.is_empty(),
            "cancelled waits cannot lose join ownership"
        );
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("controlled worker lost its owner"))?;
        tokio::time::timeout(Duration::from_secs(5), channel.stop_and_join()).await??;
        assert!(channel.workers.lock().await.is_empty());
        assert!(
            fixture.sink.admit(id, ticket(id, 2)).is_err(),
            "old sinks cannot resume writing"
        );

        let store = fixture.store.clone();
        let reopened = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        assert!(!Arc::ptr_eq(&channel, &reopened.0.channel));
        let mut projection = live_projection(&reopened).await?;
        let next = ticket(id, 2);
        reopened.admit(id, next.clone())?;
        let prepared = projection
            .prepare_committed(&reopened.0.thread, &next.effect, &next.checkpoint.state)
            .await?;
        let mut handed = (*prepared).clone();
        handed.current_state = None;
        reopened.0.channel.prepare(Arc::new(handed));
        reopened.flush(id, 2).await?;
        let page = store
            .history(id)
            .await?
            .reader()
            .events_page(
                HistoryEventsQuery::AllEvents,
                None,
                None,
                HistoryDemand {
                    max_rows: 64,
                    max_bytes: 1024 * 1024,
                },
            )
            .await?;
        assert!(page.entries.len() >= 2);
        reopened.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_replacement_claim_cannot_lose_its_channel_to_predecessor_release() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let thread = test_thread("overlapping-channel-release");
        register_test_thread(&store, &thread).await?;
        let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let previous_channel = previous.0.channel.clone();
        let (waiting, release) = store.thread_persistence().arm_release_gate();
        let writer = previous_channel
            .workers
            .lock()
            .await
            .pop()
            .context("registered predecessor writer")?;
        writer.abort();

        let wake = previous.0.changed.clone();
        drop(previous);
        wake.notify_one();
        tokio::time::timeout(Duration::from_secs(5), waiting).await??;

        let opening = tokio::spawn({
            let store = store.clone();
            let thread = thread.clone();
            async move { ThreadStorageSink::new(store, thread, None).await }
        });
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("predecessor release gate was dropped"))?;
        assert!(writer.await.unwrap_err().is_cancelled());
        let replacement = tokio::time::timeout(Duration::from_secs(5), opening).await???;
        assert!(
            Arc::ptr_eq(
                &replacement.0.channel,
                &store.thread_persistence().history_channel(&thread.id),
            ),
            "predecessor release must not remove the successor's channel"
        );
        assert!(replacement.0.channel.subscribe().borrow().fault.is_none());
        replacement.0.channel.stop_and_join().await?;
        assert!(!Arc::ptr_eq(&previous_channel, &replacement.0.channel));
        Ok(())
    }

    #[tokio::test]
    async fn worker_join_failure_remains_a_failure_after_retry() -> Result<()> {
        let fixture = Fixture::new("retirement-worker-failure").await?;
        let channel = fixture.sink.0.channel.clone();
        channel.workers.lock().await.push(tokio::spawn(async {
            panic!("controlled storage worker failure");
        }));
        assert!(channel.stop_and_join().await.is_err());
        assert!(channel.workers.lock().await.is_empty());
        assert!(
            channel.stop_and_join().await.is_err(),
            "retry cannot erase an observed worker failure"
        );
        Ok(())
    }
}

#[cfg(test)]
mod batch_window_tests {
    use super::storage_fault_tests::{live_projection, register_test_thread, test_thread, ticket};
    use super::*;

    struct Fixture {
        _temp: tempfile::TempDir,
        store: StudioStore,
        sink: ThreadStorageSink,
        projection: crate::studio::thread_projection::LiveProjection,
    }

    impl Fixture {
        async fn new(id: &str) -> Result<Self> {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
            register_test_thread(&store, &test_thread(id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
            let projection = live_projection(&sink).await?;
            Ok(Self {
                _temp: temp,
                store,
                sink,
                projection,
            })
        }

        async fn handoff(&mut self, write: &ThreadWrite) -> Result<Arc<PreparedEffect>> {
            let id = self.sink.0.thread.id.clone();
            self.sink.admit(&id, write.clone())?;
            let prepared = self
                .projection
                .prepare_committed(&self.sink.0.thread, &write.effect, &write.checkpoint.state)
                .await?;
            let mut handed = (*prepared).clone();
            handed.current_state = None;
            let handed = Arc::new(handed);
            ensure!(self.sink.0.channel.prepare(handed), "handoff refused");
            Ok(handed)
        }

        fn select(&self, now: Instant) -> batch::Selection {
            batch::select(&mut lock_progress(&self.sink.0), now, 0, false)
        }

        async fn finish(self, sequence: u64) -> Result<()> {
            self.sink
                .flush(self.sink.0.thread.id.as_str(), sequence)
                .await?;
            self.sink.0.channel.stop_and_join().await
        }
    }

    fn ready(selection: batch::Selection) -> Vec<batch::Effect> {
        match selection {
            batch::Selection::Ready(effects) => effects,
            _ => panic!("expected a frozen prepared prefix"),
        }
    }

    #[tokio::test]
    async fn continuous_arrival_keeps_the_original_deadline_and_retry_boundary() -> Result<()> {
        let mut fixture = Fixture::new("batch-deadline").await?;
        let channel = fixture.sink.0.channel.clone();
        let gate = channel.step_lock.lock().await;
        let now = Instant::now();
        let first = fixture.handoff(&ticket("batch-deadline", 1)).await?;
        lock_progress(&fixture.sink.0)
            .effects
            .front_mut()
            .unwrap()
            .admitted_at = now;
        assert!(
            matches!(fixture.select(now), batch::Selection::Wait(deadline)
                if deadline == now + Duration::from_millis(20))
        );
        fixture.handoff(&ticket("batch-deadline", 2)).await?;
        assert!(
            matches!(fixture.select(now + Duration::from_millis(19)), batch::Selection::Wait(deadline)
                if deadline == now + Duration::from_millis(20))
        );
        fixture.handoff(&ticket("batch-deadline", 3)).await?;
        let selected = ready(fixture.select(now + Duration::from_millis(20)));
        assert_eq!(
            selected
                .iter()
                .map(|effect| effect.sequence)
                .collect::<Vec<_>>(),
            [1, 2, 3]
        );
        assert!(Arc::ptr_eq(&selected[0].prepared, &first));
        fixture.handoff(&ticket("batch-deadline", 4)).await?;
        let retried = ready(fixture.select(now + Duration::from_secs(1)));
        assert_eq!(
            retried.len(),
            3,
            "later admission must not widen a frozen transaction"
        );
        for (original, retry) in selected.iter().zip(&retried) {
            assert!(Arc::ptr_eq(&original.write, &retry.write));
            assert!(Arc::ptr_eq(&original.prepared, &retry.prepared));
        }
        drop(gate);
        fixture.finish(4).await
    }

    #[tokio::test]
    async fn barriers_pressure_and_prepared_gaps_end_the_window() -> Result<()> {
        for mode in ["flush", "handoff-barrier", "pressure", "queue-full", "gap"] {
            let mut fixture = Fixture::new(&format!("batch-cut-{mode}")).await?;
            let id = fixture.sink.0.thread.id.clone();
            let channel = fixture.sink.0.channel.clone();
            let gate = channel.step_lock.lock().await;
            fixture.handoff(&ticket(&id, 1)).await?;
            let now = lock_progress(&fixture.sink.0)
                .effects
                .front()
                .unwrap()
                .admitted_at;
            assert!(matches!(fixture.select(now), batch::Selection::Wait(_)));
            match mode {
                "flush" => {
                    let flush = fixture.sink.flush(&id, 1);
                    tokio::pin!(flush);
                    assert!(futures::poll!(&mut flush).is_pending());
                }
                "handoff-barrier" => {
                    let barrier = channel.await_handoff_durable(&id, 1);
                    tokio::pin!(barrier);
                    assert!(futures::poll!(&mut barrier).is_pending());
                }
                "pressure" => lock_progress(&fixture.sink.0).pressure_paused = true,
                "queue-full" => {
                    lock_progress(&fixture.sink.0).fault =
                        Some(pl_protocol::studio::HistoryFault::QueueFull)
                }
                "gap" => fixture.sink.admit(&id, ticket(&id, 2))?,
                _ => unreachable!(),
            }
            let selected = ready(fixture.select(now));
            assert_eq!(selected.len(), 1, "{mode}");
            drop(gate);
            fixture.sink.flush(&id, 1).await?;
            if mode == "gap" {
                assert_eq!(lock_progress(&fixture.sink.0).durable, 1);
                fixture.handoff(&ticket(&id, 2)).await?;
                fixture.finish(2).await?;
            } else {
                fixture.finish(1).await?;
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn count_and_encoded_byte_limits_cut_a_batch_without_starving_large_effects() -> Result<()>
    {
        let mut fixture = Fixture::new("batch-count").await?;
        let channel = fixture.sink.0.channel.clone();
        let gate = channel.step_lock.lock().await;
        let now = Instant::now();
        for sequence in 1..=64 {
            fixture.handoff(&ticket("batch-count", sequence)).await?;
            if sequence == 63 {
                assert!(matches!(fixture.select(now), batch::Selection::Wait(_)));
            }
        }
        assert_eq!(ready(fixture.select(now)).len(), 64);
        drop(gate);
        fixture.finish(64).await?;

        let mut fixture = Fixture::new("batch-large").await?;
        let channel = fixture.sink.0.channel.clone();
        let gate = channel.step_lock.lock().await;
        let mut large = ticket("batch-large", 1);
        let extension = pl_core::thread::extensions::ExtensionRecord {
            revision: 1,
            payload: pl_core::context::OpaquePayload::text("large".repeat(256 * 1024)),
        };
        large
            .checkpoint
            .state
            .extensions
            .insert("test.large".into(), extension.clone());
        Arc::make_mut(&mut large.effect).extensions =
            Arc::from([pl_core::thread::extensions::ExtensionChange::Put {
                id: "test.large".into(),
                record: extension,
            }]);
        fixture.handoff(&large).await?;
        let now = lock_progress(&fixture.sink.0)
            .effects
            .front()
            .unwrap()
            .admitted_at;
        assert!(
            lock_progress(&fixture.sink.0)
                .effects
                .front()
                .unwrap()
                .bytes
                > 1024 * 1024
        );
        assert_eq!(ready(fixture.select(now)).len(), 1);
        fixture.handoff(&ticket("batch-large", 2)).await?;
        assert_eq!(ready(fixture.select(now)).len(), 1);
        drop(gate);
        fixture.finish(2).await
    }
}

#[cfg(test)]
mod watchdog_tests {
    use super::storage_fault_tests::{
        live_projection, register_test_thread, test_thread, visible_input_ticket,
    };
    use super::*;
    use sea_orm::{Database, SqliteTransactionMode, TransactionOptions, TransactionTrait};

    #[tokio::test]
    async fn unprepared_head_stalls_despite_later_admissions_and_notifications() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = "projection-watchdog";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let channel = sink.0.channel.clone();
        let lease = channel.step_lock.lock().await;
        channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW);
        assert!(channel.subscribe().borrow().fault.is_none());
        sink.admit(id, visible_input_ticket(id, 1, "first")?)?;
        let admitted_at = lock_progress(&sink.0).effects.front().unwrap().admitted_at;
        for sequence in 2..=4 {
            sink.admit(
                id,
                visible_input_ticket(id, sequence, &format!("later-{sequence}"))?,
            )?;
            channel.changed.notify_one();
            channel.status.send_modify(|_| {});
            let _ = sink.pressure(id);
            channel.detect_stall_at(admitted_at + Duration::from_secs(59));
            assert!(channel.subscribe().borrow().fault.is_none());
        }
        let retained = sink.pressure(id).thread_bytes;
        channel.detect_stall_at(admitted_at + NO_PROGRESS_WINDOW);
        let failed = channel.subscribe().borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::NoProgress)
        );
        assert_eq!(failed.committed_sequence, 0);
        assert_eq!(failed.queued_records, 4);
        assert_eq!(sink.pressure(id).thread_bytes, retained);
        assert!(sink.flush(id, 1).await.is_err());

        let mut projection = live_projection(&sink).await?;
        let mut deferred_head = None;
        for sequence in 1..=4 {
            let write = lock_progress(&sink.0).effects[(sequence - 1) as usize]
                .write
                .clone();
            let prepared = projection
                .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
                .await?;
            if sequence == 1 {
                deferred_head = Some(prepared);
                continue;
            }
            if sequence == 2 {
                assert!(
                    !channel.prepare(prepared.clone()),
                    "a prepared tail cannot skip the head"
                );
                assert_eq!(lock_progress(&sink.0).prepared_through(), 0);
                assert!(channel.prepare(deferred_head.take().unwrap()));
            }
            assert!(channel.prepare(prepared));
            assert_eq!(lock_progress(&sink.0).prepared_through(), sequence);
        }
        assert_eq!(channel.subscribe().borrow().fault, failed.fault);
        drop(lease);
        store
            .thread_persistence()
            .retry_history(id, failed.fault_generation)
            .await?;
        sink.flush(id, 4).await?;
        assert_eq!(channel.subscribe().borrow().committed_sequence, 4);
        channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW);
        assert!(channel.subscribe().borrow().fault.is_none());

        let lease = channel.step_lock.lock().await;
        let fifth = visible_input_ticket(id, 5, "explicit-failure")?;
        sink.admit(id, fifth.clone())?;
        channel.fail_projection(5, "controlled projection failure".to_owned());
        let explicit = channel.subscribe().borrow().clone();
        channel.detect_stall_at(Instant::now() + NO_PROGRESS_WINDOW * 2);
        assert_eq!(*channel.subscribe().borrow(), explicit);
        assert!(sink.flush(id, 5).await.is_err());
        let prepared = projection
            .prepare_committed(&sink.0.thread, &fifth.effect, &fifth.checkpoint.state)
            .await?;
        assert!(channel.prepare(prepared));
        drop(lease);
        store
            .thread_persistence()
            .retry_history(id, explicit.fault_generation)
            .await?;
        sink.flush(id, 5).await?;
        channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn pending_sql_retains_writer_and_obligations_until_the_call_returns() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = "sql-watchdog";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let channel = sink.0.channel.clone();
        let lease = channel.step_lock.lock().await;
        let mut projection = live_projection(&sink).await?;
        let write = visible_input_ticket(id, 1, "sql-input")?;
        sink.admit(id, write.clone())?;
        let prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        assert!(channel.prepare(prepared));
        assert_eq!(
            lock_progress(&sink.0).stage,
            Some(HistoryStage::WriterQueue)
        );
        let retained = sink.pressure(id).thread_bytes;

        let path = store.session_paths("project-test", id)?.history_database();
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        let blocker = db
            .begin_with_options(TransactionOptions {
                sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                ..Default::default()
            })
            .await?;
        let (entered, pending) = tokio::sync::oneshot::channel();
        *channel.sql_pending.lock().unwrap() = Some(entered);
        channel.request_flush(1);
        drop(lease);
        pending.await?;
        let started = {
            let progress = lock_progress(&sink.0);
            assert_eq!(progress.stage, Some(HistoryStage::SqlCommit));
            assert_eq!(progress.prepared_through(), 1);
            progress.last_progress_at.unwrap()
        };
        channel.detect_stall_at(started + Duration::from_secs(59));
        assert!(channel.subscribe().borrow().fault.is_none());
        channel.detect_stall_at(started + NO_PROGRESS_WINDOW);
        let failed = channel.subscribe().borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::NoProgress)
        );
        assert_eq!(failed.committed_sequence, 0);
        assert_eq!(failed.queued_records, 1);
        assert_eq!(sink.pressure(id).thread_bytes, retained);
        assert!(
            channel.step_lock.try_lock().is_err(),
            "SQL still owns the writer"
        );
        assert!(
            channel
                .workers
                .lock()
                .await
                .iter()
                .any(|worker| !worker.is_finished())
        );
        assert!(sink.flush(id, 1).await.is_err());

        let mut released = channel.effects_released.subscribe();
        blocker.rollback().await?;
        while *released.borrow_and_update() < 1 {
            released.changed().await?;
        }
        assert_eq!(channel.subscribe().borrow().committed_sequence, 1);
        assert_eq!(channel.subscribe().borrow().fault, failed.fault);
        assert!(!lock_progress(&sink.0).fault_recovered);
        store
            .thread_persistence()
            .retry_history(id, failed.fault_generation)
            .await?;
        sink.flush(id, 1).await?;
        channel.stop_and_join().await?;
        Ok(())
    }
}

#[cfg(test)]
mod execution_index_tests {
    use super::*;

    #[test]
    fn execution_index_retires_sources_and_charges_pending_until_real_confirmation() -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = RuntimeOrderIndex::new(process.clone(), 30);
        let observed = index.reserve_observed("attempt-one", "observed")?;
        assert_eq!(observed, 31);
        let reserved_bytes = index.retained_bytes();
        assert!(reserved_bytes > "observed".len() as u64);
        assert_eq!(process.load(Ordering::Acquire), reserved_bytes);
        index.retain::<()>(&Default::default(), Vec::new());
        let active_bytes = index.retained_bytes();
        assert!(active_bytes > 0 && active_bytes < reserved_bytes);
        assert_eq!(
            index.assigned("observed"),
            Some(observed),
            "an older checkpoint cannot retire a source the projection has not reached"
        );
        index.finish_source("attempt-one");
        let identities = BTreeMap::from([("observed".to_owned(), 5_u64)]);
        index.retain(&identities, Vec::new());
        assert!(
            index.retained_bytes() > 0 && index.retained_bytes() < active_bytes,
            "retained facts own the identity after source and change keys are released"
        );
        assert_eq!(index.assigned("observed"), Some(observed));
        index.retain::<()>(&Default::default(), vec!["observed".into()]);
        assert_eq!(
            index.retained_bytes(),
            0,
            "unmaterialized retired source needs no save"
        );
        let order = index.reserve_observed("attempt-two", "completed")?;
        assert_eq!(
            order, 32,
            "retiring a source cannot rewind the scalar ceiling"
        );
        let item = crate::ExecutionItem::new(
            "completed".into(),
            "thread".into(),
            "turn".into(),
            order,
            9,
            10,
            20,
            crate::ExecutionShape::Raw(pl_protocol::ThreadRawItem::stored(Vec::new(), "done", 20)),
        );
        index.materialize(&item, 7)?;
        index.mark_completion("completed", true);
        index.finish_source("attempt-two");
        index.retain::<()>(&Default::default(), Vec::new());
        assert!(index.pending("completed"));
        assert!(index.is_sealed("completed"));
        assert!(index.is_terminal("completed"));
        index.confirm_saved(6);
        assert!(
            index.retained_bytes() > 0,
            "an earlier save cannot release this pending fact"
        );
        index.confirm_saved(7);
        assert_eq!(index.retained_bytes(), 0);
        Ok(())
    }

    #[test]
    fn execution_index_budget_rejects_without_allocating_or_rewinding() -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = RuntimeOrderIndex::new(process, 30);
        let first = index.allocate("first", None, None)?;
        let second = index.allocate("second", None, None)?;
        assert_eq!((first, second), (1, 2));
        assert_eq!(index.retained_bytes(), 30);
        let rejected = index.allocate("third", None, None).unwrap_err();
        assert!(
            rejected
                .to_string()
                .contains("thread resident execution budget exhausted")
        );
        assert_eq!(index.retained_bytes(), 30);
        assert_eq!(index.assigned("third"), None);
        Ok(())
    }

    #[test]
    fn execution_index_materialize_budget_rejection_leaves_no_partial_identity_or_stamp()
    -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = RuntimeOrderIndex::new(process, 30);
        let first = index.reserve_observed("attempt", "observed")?;
        assert_eq!(first, 1);
        assert_eq!(index.retained_bytes(), 30);
        let large = crate::ExecutionItem::new(
            "observed".into(),
            "thread".into(),
            "turn".into(),
            first,
            9,
            10,
            20,
            crate::ExecutionShape::Raw(pl_protocol::ThreadRawItem::stored(Vec::new(), "done", 20)),
        );
        let rejected = index.materialize(&large, u64::MAX).unwrap_err();
        assert!(
            rejected
                .to_string()
                .contains("thread resident execution budget exhausted")
        );
        assert_eq!(index.retained_bytes(), 30);
        assert_eq!(index.assigned("observed"), Some(first));
        assert!(!index.completion_checked("observed"));
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_materialization_serializes_provider_allocation() -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = Arc::new(RuntimeOrderIndex::new(process, 1024 * 1024));
        let item = crate::ExecutionItem::new(
            "materialized".into(),
            "thread".into(),
            "turn".into(),
            1,
            2,
            10,
            20,
            crate::ExecutionShape::Raw(pl_protocol::ThreadRawItem::stored(Vec::new(), "body", 20)),
        );
        let (entered, materialize_entered) = tokio::sync::oneshot::channel();
        let (release, materialize_release) = std::sync::mpsc::channel();
        *index.materialize_gate.lock().unwrap() = Some(MaterializeGate {
            entered,
            release: materialize_release,
        });
        let materializing = tokio::task::spawn_blocking({
            let index = index.clone();
            move || index.materialize(&item, 1)
        });
        materialize_entered.await?;

        let (attempting, attempted) = tokio::sync::oneshot::channel();
        let provider = tokio::task::spawn_blocking({
            let index = index.clone();
            move || {
                let _ = attempting.send(());
                index.reserve_observed("attempt", "provider-part")
            }
        });
        attempted.await?;
        assert!(
            index.inner.try_lock().is_err(),
            "provider allocation must wait for the materialization commit"
        );
        release.send(())?;
        materializing.await??;
        assert!(provider.await?.is_err());
        assert_eq!(index.assigned("materialized"), Some(1));
        assert_eq!(index.assigned("provider-part"), None);
        Ok(())
    }

    #[tokio::test]
    async fn operation_output_reservation_returns_to_baseline_across_rounds() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = "operation-budget";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store, test_thread(id), None).await?;
        let channel = &sink.0.channel;
        let baseline = channel.process_bytes.load(Ordering::Acquire);
        for index in 0..32 {
            assert_eq!(
                channel.reserve_operation_output(&format!("idle-{index}"), 16 * 1024 * 1024,),
                Some(16 * 1024 * 1024)
            );
        }
        assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
        for index in 0..32 {
            channel.release_operation_output(&format!("idle-{index}"));
        }
        for round in 0..4_u64 {
            let operation = format!("task:call-{round}");
            assert_eq!(
                channel.reserve_operation_output(&operation, 4096),
                Some(4096)
            );
            assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
            channel.charge_operation_output(&operation, 1024)?;
            channel.charge_operation_output(&operation, 2048)?;
            assert!(channel.charge_operation_output(&operation, 4097).is_err());
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline + 2048
            );
            channel.release_operation_output(&operation);
            channel.release_operation_output(&operation);
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline,
                "a finished call releases all accepted bytes exactly once"
            );
        }
        channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn rejected_terminal_transfer_retains_the_source_without_partial_charge() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = "terminal-transfer-budget";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store, test_thread(id), None).await?;
        let channel = &sink.0.channel;
        let lease = channel.step_lock.lock().await;
        sink.admit(id, visible_input_ticket(id, 1, "input")?)?;
        let source = PendingProjectionRetention {
            sequence: 1,
            prepared_bytes: 200,
        };
        channel.set_projection_retention(ProjectionRetention {
            resident_bytes: 100,
            pending: Some(source),
        })?;
        let transfer = ProjectionTransfer {
            source,
            after: ProjectionRetention {
                resident_bytes: 100,
                pending: Some(PendingProjectionRetention {
                    sequence: 1,
                    prepared_bytes: 120,
                }),
            },
        };
        let pressure_before = sink.pressure(id);
        let process_before = channel.process_bytes.load(Ordering::Acquire);
        let too_many = MAX_HISTORY_THREAD_BYTES
            .saturating_sub(pressure_before.thread_bytes)
            .saturating_add(1);
        assert!(channel.retain_terminal_bytes(too_many, transfer).is_err());
        assert_eq!(lock_progress(&sink.0).projection_pending, Some(source));
        assert_eq!(channel.retained_delivery_bytes(), 0);
        assert_eq!(sink.pressure(id).thread_bytes, pressure_before.thread_bytes);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            process_before
        );
        channel.release_projection_retention();
        drop(lease);
        channel.stop_and_join_for_deletion().await?;
        Ok(())
    }

    #[tokio::test]
    async fn full_process_budget_rejects_the_continuous_ticket_without_appending_it() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = "admission-backpressure";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store, test_thread(id), None).await?;
        let channel = &sink.0.channel;
        let lease = channel.step_lock.lock().await;
        channel
            .process_bytes
            .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
        let error = sink
            .admit(id, ticket(id, 1))
            .expect_err("full reliable budget is admission backpressure");
        assert!(
            error
                .source
                .is::<pl_core::thread::cold::StorageAdmissionBackpressure>()
        );
        let status = channel.subscribe().borrow().clone();
        assert_eq!(status.admitted_sequence, 0);
        assert_eq!(status.queued_records, 0);
        assert!(status.fault.is_none() && status.error.is_none());
        assert!(channel.next_unprojected().is_none());
        channel.process_bytes.store(0, Ordering::Release);
        drop(lease);
        channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn fault_generation_rejects_a_retry_for_the_previous_failure() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let id = "fault-generation";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store, test_thread(id), None).await?;
        let channel = &sink.0.channel;
        record_error(
            &sink.0,
            pl_protocol::studio::HistoryFault::WriteFailed,
            FaultTarget::NextWrite,
            "first failure".into(),
            &["redacted_error"],
        );
        let first = channel.subscribe().borrow().fault_generation;
        record_error(
            &sink.0,
            pl_protocol::studio::HistoryFault::WriteFailed,
            FaultTarget::NextWrite,
            "newer failure".into(),
            &["redacted_error"],
        );
        let second = channel.subscribe().borrow().fault_generation;
        assert!(second > first);
        assert!(channel.retry(first).is_err());
        assert_eq!(
            channel.subscribe().borrow().fault_generation,
            second,
            "a stale acknowledgement cannot resume the newer failure"
        );
        channel.stop_and_join_for_deletion().await?;
        Ok(())
    }
}
