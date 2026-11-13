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
    ThreadCheckpoint, ThreadSnapshot, UsageSummary,
    cold::{ColdStore, ColdStoreError, StoragePressure, ThreadWrite},
};
use pl_protocol::ThreadItem;
use tokio::time::Instant;

use crate::studio::StudioStore;
use crate::studio::storage::coordinator::{
    PendingSequenceRange, ThreadPersistenceMetrics, ThreadPersistenceReport,
};
use crate::studio::storage::history::{
    AccountingCommit, EffectCommit, InputIdentityWrite, MessageIdentityWrite, SessionAccounting,
    is_retryable_write,
};
use crate::studio::thread_projection::PreparedEffect;

mod batch;

#[cfg(test)]
mod batch_tests;
#[cfg(feature = "benchmarks")]
pub(crate) mod benchmark;
#[cfg(test)]
mod watchdog_tests;
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
    pub fn from_item(item: &'a ThreadItem) -> Self {
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
                completion_checked: false,
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

    fn has_unfinished_source(&self) -> bool {
        !self
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .by_source
            .is_empty()
    }

    pub(in crate::studio) fn materialize(
        &self,
        item: &pl_protocol::ThreadItem,
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

    pub(in crate::studio) fn pending_placement(
        &self,
        id: &str,
        thread_id: &str,
    ) -> Option<pl_protocol::ThreadItem> {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let entry = state.assigned.get(id)?;
        if !entry.effect.is_some_and(|seq| seq > state.durable) {
            return None;
        }
        let stamp = entry.stamp.as_ref()?;
        Some(pl_protocol::ThreadItem::new(
            id.to_owned(),
            thread_id.to_owned(),
            stamp.turn_id.clone(),
            entry.ordinal,
            stamp.revision,
            stamp.created_at,
            stamp.updated_at,
            pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
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
    sequence: u64,
    /// Starts the private batching deadline; later arrivals never reset it.
    admitted_at: Instant,
    write: Arc<ThreadWrite>,
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
        // Otherwise a fresh owner needs only the scalar ceiling, not its predecessor's identities.
        if self.order_index.has_pending()
            || (self.order_index.has_unfinished_source()
                && Arc::strong_count(&self.order_index) > 1)
        {
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
        if prepared.completion_drafts.is_some() {
            return false;
        }
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
            return false;
        }
        let Some(index) = progress.queue_offset(sequence) else {
            return false;
        };
        if let Some(existing) = &progress.effects[index].prepared {
            // Retries hand over the original frozen batch; replacing it could lose a published
            // completion or change the bytes behind an unchanged reliable-budget charge.
            return Arc::ptr_eq(existing, &prepared);
        }
        if progress.next_unprojected_offset() != Some(index) {
            return false;
        }
        let mut order_index = self
            .order_index
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let transferred = match progress.projection_pending {
            Some(source) if source.sequence == sequence && source.prepared_bytes == bytes => bytes,
            Some(_) => return false,
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
            return false;
        }
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
        true
    }

    /// Oldest admitted effect the Thread's live projection owner has not taken over yet.
    ///
    /// The reliable queue is the Thread's one ordered handoff, so the projection owner consumes it in
    /// admission order: this is the next fact it owes a projection, and `None` while every admitted
    /// effect is already prepared. Nothing waits for a GUI — a Thread without subscribers still
    /// drains the queue, because the writer cannot save a fact no projection holds.
    pub(in crate::studio) fn next_unprojected(&self) -> Option<Arc<ThreadWrite>> {
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
    pub(in crate::studio) fn unprojected_writes(&self) -> Vec<Arc<ThreadWrite>> {
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
            .and_then(|effect| effect.write.checkpoint.state.execution.as_ref())
            .map(|execution| execution.id.as_str());
        // The reliable queue carries execution identity, not live provider request/generation
        // metadata. Attempt IDs and the execution counter cannot substitute for those identities.
        tracing::warn!(
            target: "conversation_work",
            operation = "history_persistence",
            thread_id = ?head.map(|effect| effect.write.checkpoint.thread_id.as_str()),
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
    chat: pl_core::chat::Session,
    /// This writer incarnation's coordinator identity; see [`NEXT_WRITER_INCARNATION`].
    owner: usize,
    /// One durable history reader for the life of this writer.
    ///
    /// The history database is the single ordinal/identity allocator, so the writer opens it once
    /// instead of per effect; the pool has one connection, so every batch stays a short
    /// single-writer transaction and two consecutive effects cannot interleave their allocations.
    history: tokio::sync::OnceCell<crate::studio::storage::history::HistoryStore>,
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
#[derive(Debug, Clone)]
pub(crate) struct ThreadStorageBinding {
    pub(crate) storage: pl_core::thread::cold::ColdStoreHandle,
    pub(crate) channel: Arc<HistoryChannel>,
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
async fn history_store(inner: &Inner) -> Result<crate::studio::storage::history::HistoryStore> {
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
        .map(|queued| queued.write.checkpoint.state_revision)
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
        let chat = store.chat_session(&thread.id).await?;
        let mut workers = channel.workers.lock().await;
        ensure!(
            !channel.stopping.is_cancelled(),
            "history writer is stopping"
        );
        // A preceding incarnation may still be finishing one write. Observe its committed
        // watermark and seed this incarnation while holding the channel's single-writer lease.
        let writer_lease = channel.step_lock.lock().await;
        let history = store.history(&thread.id).await?;
        // Execution owns schema/identity preparation. The first projection must already have a
        // real database identity, without making Chat opens or individual effects create one.
        history.prepare_write().await?;
        let durable = history.watermark().await?;
        // Seed the Runtime's execution-order index from the same durable store this writer owns:
        // `history_items`'s maximum ordinal is the ceiling no new execution identity may reuse.
        // Registering here (idempotently, max-raising) covers both this incarnation and any
        // replacement that follows, before the first admission or preview can allocate.
        channel.order_index.seed(
            history
                .latest_execution_ordinal()
                .await
                .context("reading the durable execution-order ceiling")?,
            durable,
        );
        let restored_fence = restored_checkpoint.map_or(0, |checkpoint| checkpoint.history_fence);
        ensure!(
            durable == restored_fence,
            "Thread {} history watermark {durable} does not match checkpoint fence {restored_fence}",
            thread.id
        );
        // An unfinished Turn may publish another Running record after reopening. Its execution
        // boundary already exists: recover that exact placement before synchronous admission can
        // reserve new provider identities. Only checkpoint-owned live Turns remain resident.
        if let Some(checkpoint) = restored_checkpoint {
            for turn in checkpoint
                .state
                .turns
                .iter()
                .filter(|turn| turn.state == pl_core::thread::TurnState::Running)
            {
                let id = crate::studio::thread_projection::order::turn_id(&turn.turn_id);
                if channel.order_index.assigned(&id).is_none()
                    && let Some(item) = history.item(&id).await?
                {
                    channel.order_index.materialize(&item, 0)?;
                }
            }
        }
        let (history_observer_stop, mut stop_observer) = tokio::sync::watch::channel(false);
        let inner = Arc::new(Inner {
            store,
            thread,
            chat,
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
        if let Ok(history) = history_store(&inner).await {
            publish_accounting(&inner, &history).await;
        }
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
        ThreadStorageBinding {
            storage: pl_core::thread::cold::ColdStoreHandle::new(self.clone()),
            channel: self.0.channel.clone(),
        }
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
        progress.release_saved_at(committed.write.checkpoint.saved_at);
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
async fn publish_accounting(
    inner: &Inner,
    history: &crate::studio::storage::history::HistoryStore,
) {
    #[cfg(feature = "benchmarks")]
    inner
        .store
        .calls()
        .observation()
        .increment(BenchMetric::AccountingRead);
    match history.accounting().await {
        Ok(Some(accounting)) => submit_accounting(inner, accounting),
        Ok(None) => {}
        Err(error) => {
            tracing::warn!(%error, "读取累计统计投影失败");
        }
    }
}

/// Retain only the latest committed absolute projection; retries never re-read the checkpoint.
fn submit_accounting(inner: &Inner, accounting: SessionAccounting) {
    use super::calls::{PurposeUsageProjection, SessionUsageProjection};
    let projection = SessionUsageProjection {
        root_thread_id: inner.thread.root_thread_id.clone(),
        thread_id: inner.thread.id.clone(),
        revision: accounting.revision,
        has_unpriced_usage: accounting.has_unpriced_usage,
        purpose_costs: accounting
            .purpose_costs
            .into_iter()
            .map(|(purpose, estimated_costs)| PurposeUsageProjection {
                purpose,
                estimated_costs,
            })
            .collect(),
    };
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

/// Minimal durable identities of the messages one effect admitted.
///
/// The writer stores them in the same transaction as the effect's history, so a delivery that left
/// core's resident window can still be adjudicated from the per-Thread index. The digest comes from
/// core's own message digest over the frozen source/body/context fields, which is exactly what the
/// host recomputes when it repeats a delivery, so an identical repeat returns the original sequence
/// and a different body is rejected instead of delivered twice.
fn admitted_message_identities(
    effect: &pl_core::thread::ThreadEffectBatch,
) -> Vec<MessageIdentityWrite> {
    effect
        .inbox
        .iter()
        .map(|record| MessageIdentityWrite {
            message_id: record.message.id.clone(),
            item_id: crate::studio::thread_projection::order::message_id(&record.message.id),
            sequence: record.sequence,
            digest: Some(record.message.digest()),
        })
        .collect()
}

/// Minimal identities of every input this commit must be able to answer for.
///
/// A terminal input keeps its receipt so a repeated submission is answered after the resident
/// identity window (and the attachment drafts it referenced) are gone. A still-pending continuation
/// control is written too: its admission is the whole point of the operation, so the receipt has to
/// be readable before the input is consumed, while consuming and discarding later only move its
/// state forward in the same row.
///
/// A control input has no host prompt body, so its request digest binds the Thread and the
/// continuation it was admitted for instead of a payload that does not exist.
fn durable_input_identities(thread_id: &str, snapshot: &ThreadSnapshot) -> Vec<InputIdentityWrite> {
    use pl_core::thread::input::{InputPurpose, InputState};
    snapshot
        .inputs
        .iter()
        .filter(|record| {
            record.state != InputState::Pending
                || record.input.purpose == InputPurpose::Continuation
        })
        .map(|record| {
            let control = record
                .continuation
                .as_ref()
                .filter(|_| record.input.purpose == InputPurpose::Continuation);
            let mut entry = crate::studio::storage::state::InputIdentityEntry::new(
                pl_core::thread::input::input_identity(record),
                record.accepted_sequence,
            );
            if control.is_some() {
                // The frozen route revision and the admission revision belong to the first
                // admission; the write path preserves them, so only a first write fills them in.
                entry.expected_model_route_revision = frozen_route_revision(snapshot);
                entry.continuation_admission_revision = Some(record.revision);
            }
            InputIdentityWrite {
                entry,
                request_digest: match control {
                    Some(continuation) => Some(
                        crate::studio::thread_projection::continuation_request_digest(
                            thread_id,
                            &continuation.point_id,
                            frozen_route_revision(snapshot),
                        ),
                    ),
                    None => crate::studio::thread_projection::saved_prompt_request_digest(
                        &record.input.payload,
                    ),
                },
                presentation: crate::studio::thread_projection::input_presentation(record),
            }
        })
        .collect()
}

/// Route revision this Thread had when the control input was first written.
///
/// A control input is only admitted after the caller's frozen revision matched the saved one under
/// the same lifecycle lock, so the value the identity index keeps is the request's own frozen fact;
/// it is never rewritten by a later commit.
fn frozen_route_revision(snapshot: &ThreadSnapshot) -> Option<u64> {
    crate::studio::model_route::route_record(snapshot, false)
        .ok()
        .flatten()
        .map(|(record, _)| record.revision)
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

impl ColdStore for ThreadStorageSink {
    fn reserve_observed_item(
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

    fn subscribe_pressure(&self, thread_id: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        (thread_id == self.0.thread.id).then(|| self.0.channel.pressure_changed.subscribe())
    }

    fn reserve_operation_output(
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

    fn charge_operation_output(
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

    fn release_operation_output(&self, thread_id: &str, operation_id: &str) {
        if thread_id == self.0.thread.id {
            self.0.channel.release_operation_output(operation_id);
        }
    }

    fn pressure(&self, thread_id: &str) -> StoragePressure {
        if thread_id != self.0.thread.id {
            return StoragePressure {
                error: Some(storage_error("Thread persistence owner mismatch")),
                ..Default::default()
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
        let bytes = progress
            .effect_bytes
            .saturating_add(progress.queue_metadata_bytes)
            .saturating_add(progress.prepared_bytes)
            .saturating_add(progress.projection_bytes)
            .saturating_add(self.0.channel.order_index.retained_bytes())
            .saturating_add(self.0.channel.delivery_bytes.load(Ordering::Acquire))
            .saturating_add(reserved);
        StoragePressure {
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
        }
    }

    fn admit(&self, thread_id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if self.0.channel.stopping.is_cancelled() {
            return Err(cold_error("history writer is stopped"));
        }
        if thread_id != self.0.thread.id
            || write.effect.thread_id != thread_id
            || write.checkpoint.thread_id != thread_id
            || write.effect.sequence == 0
            || write.effect.sequence != write.checkpoint.state_revision
            || write.checkpoint.history_fence != write.effect.sequence
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
                write.output_claim.as_deref(),
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
            progress.admit_saved_at(write.checkpoint.saved_at);
            self.0.channel.commit_residents(&progress, &index);
            drop(index);
        }
        // 首次受理从 checkpoint 继承已折叠的累计摘要，然后只折叠本 incarnation 的新 effect。
        if progress.usage.applied_sequence == 0
            && write.checkpoint.state.usage_summary.applied_sequence > 0
        {
            progress.usage = write.checkpoint.state.usage_summary.clone();
        }
        progress.pressure_paused = write.checkpoint.state.persistence.pressure_paused;
        report(&self.0, &progress);
        drop(progress);
        self.0.changed.notify_one();
        Ok(())
    }

    async fn flush(&self, thread_id: &str, sequence: u64) -> Result<(), ColdStoreError> {
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

    fn read_tool_task(
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
            store
                .history(&owner)
                .await
                .map_err(|error| cold_error(&error.to_string()))?
                .tool_task(&task_id)
                .await
                .map_err(|error| cold_error(&error.to_string()))
        }
    }
}

/// Durable receipts for the terminal interaction/permission facts one effect committed.
///
/// The receipt payload is the committed core record itself (its stable serde encoding is the
/// source of the digest) and its revision is the record's own revision, so a repeated terminal
/// command can be answered with the same receipt while a conflicting payload for one revision
/// fails the effect transaction instead of overwriting the accepted fact.
fn fact_receipts(
    effect: &pl_core::thread::ThreadEffectBatch,
    prepared: &PreparedEffect,
) -> Result<Vec<crate::studio::storage::history::FactReceiptWrite>> {
    let mut receipts = Vec::new();
    for fact in &prepared.review_delivery {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: fact.message.id.clone(),
            revision: 1,
            kind: "reviewDeliveryException",
            payload: serde_json::to_string(fact)?,
        });
    }
    if let Some(message) = &prepared.parent_report {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: message.id.clone(),
            revision: 1,
            kind: "parentReport",
            payload: serde_json::to_string(message)?,
        });
    }
    for record in effect.interactions.iter() {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: crate::studio::thread_projection::order::receipt_id(
                "interaction",
                &record.request.id,
            ),
            revision: record.revision,
            kind: "interaction",
            payload: serde_json::to_string(record)?,
        });
    }
    for record in effect.permissions.iter() {
        receipts.push(crate::studio::storage::history::FactReceiptWrite {
            item_id: crate::studio::thread_projection::order::receipt_id("permission", &record.id),
            revision: record.revision,
            kind: "permission",
            payload: serde_json::to_string(record)?,
        });
    }
    Ok(receipts)
}

fn rolled_back_turns(snapshot: &ThreadSnapshot) -> std::collections::BTreeSet<String> {
    let mut removed = std::collections::BTreeSet::new();
    for replacement in snapshot.context_replacements.iter() {
        if replacement.reason != pl_core::thread::ContextReplacementReason::Rewind {
            continue;
        }
        let retained = replacement
            .current
            .records
            .iter()
            .filter_map(|record| record.turn_id.as_ref())
            .collect::<std::collections::BTreeSet<_>>();
        for record in replacement.previous.records.iter() {
            if let Some(turn) = &record.turn_id
                && !retained.contains(turn)
            {
                removed.insert(turn.clone());
            }
        }
    }
    removed
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
pub(crate) mod storage_fault_tests;
