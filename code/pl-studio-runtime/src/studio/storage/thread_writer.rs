//! Per-Thread ordered persistence owner: each effect and its checkpoint commit in one transaction.
//!
//! Admission never blocks the executor. Effects are history facts, so every admitted batch is
//! written to `history.sqlite` in sequence order, each against the effect-matched
//! transfer state it arrived with. The matching checkpoint is not scheduled on its own: the writer
//! holds `write.checkpoint` as the candidate for exactly that effect and commits it together with
//! the effect's history facts, the latest context increment and the history watermark in one
//! `history.sqlite` transaction (`design/15` §15.5). There is no coalescing interval and no second
//! in-flight checkpoint, so no revision can be observed as dirty without its effect, and the
//! published revision always moves with the durable effect sequence.
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
use crate::studio::storage::coordinator::{ThreadPersistenceMetrics, ThreadPersistenceReport};
use crate::studio::storage::history::{
    AccountingCommit, EffectCommit, InputIdentityWrite, MessageIdentityWrite, SessionAccounting,
    is_retryable_write,
};
use crate::studio::thread_projection::PreparedEffect;

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
    /// An already admitted material owner failed to fund its next step; only an explicit
    /// successful owner measurement/transfer or retry can reopen optional allocations.
    resident_blocked: bool,
}

#[derive(Clone)]
struct ExecutionIdentity {
    ordinal: u64,
    source: Option<String>,
    source_seen: bool,
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
        self.allocate_locked(&mut state, item_id, source, ordinal, 0)
    }

    /// Validate and fund the entire mutation before inserting or changing an identity. A caller
    /// materializing a stamp includes its growth in this one charge while holding the same lock.
    fn allocate_locked(
        &self,
        state: &mut OrderIndexState,
        item_id: &str,
        source: Option<&str>,
        ordinal: Option<u64>,
        stamp_growth: u64,
    ) -> Result<u64> {
        let blocked = state.resident_blocked;
        if let Some(entry) = state.assigned.get_mut(item_id) {
            ensure!(
                ordinal.is_none_or(|order| order == entry.ordinal),
                "execution ordinal conflict"
            );
            ensure!(
                source.is_none_or(|source| entry.source.as_deref().is_none_or(|old| old == source)),
                "execution observation source conflict"
            );
            let source = source.filter(|_| entry.source.is_none());
            let added = stamp_growth.saturating_add(source.map_or(0, |source| source.len() as u64));
            if added > 0 {
                self.charge(added, blocked)?;
            }
            if let Some(source) = source {
                entry.source = Some(source.to_owned());
            }
            return Ok(entry.ordinal);
        }
        let order = ordinal
            .or_else(|| state.ceiling.checked_add(1))
            .filter(|order| *order <= i64::MAX as u64)
            .context("execution ordinal space is exhausted")?;
        let entry = ExecutionIdentity {
            ordinal: order,
            source: source.map(str::to_owned),
            source_seen: false,
            source_ended: false,
            effect: None,
            retained: true,
            terminal: false,
            sealed: false,
            completion_checked: false,
            stamp: None,
        };
        let bytes = entry.bytes(item_id).saturating_add(stamp_growth);
        self.charge(bytes, blocked)?;
        state.ceiling = state.ceiling.max(order);
        state.assigned.insert(item_id.to_owned(), entry);
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
        let mut bytes = 0_u64;
        for id in &ids {
            if state.assigned.contains_key(id) || staged.contains_key(id) {
                continue;
            }
            ceiling = ceiling
                .checked_add(1)
                .filter(|ordinal| *ordinal <= i64::MAX as u64)
                .context("execution ordinal space is exhausted")?;
            let entry = ExecutionIdentity {
                ordinal: ceiling,
                source: None,
                source_seen: false,
                source_ended: false,
                effect: Some(effect.sequence),
                retained: false,
                terminal: false,
                sealed: false,
                completion_checked: false,
                stamp: None,
            };
            bytes = bytes.saturating_add(entry.bytes(id));
            staged.insert(id.clone(), entry);
        }
        ensure!(
            self.other_thread_bytes
                .load(Ordering::Acquire)
                .saturating_add(self.delivery_bytes.load(Ordering::Acquire))
                .saturating_add(self.retained_bytes())
                .saturating_add(additional_bytes)
                .saturating_add(bytes)
                <= MAX_HISTORY_THREAD_BYTES,
            ExecutionIndexBudgetFull { scope: "thread" }
        );
        // Fund the whole boundary set before publishing any placement or advancing the ceiling.
        self.charge(bytes, false)?;
        state.ceiling = ceiling;
        state.assigned.extend(staged);
        for id in ids {
            let entry = state.assigned.get_mut(&id).expect("reserved boundary");
            entry.effect = Some(entry.effect.unwrap_or(0).max(effect.sequence));
        }
        Ok(())
    }

    fn has_pending(&self) -> bool {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state
            .assigned
            .values()
            .any(|entry| entry.effect.is_some_and(|seq| seq > state.durable))
    }

    fn has_unfinished_source(&self) -> bool {
        self.inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .values()
            .any(|entry| entry.source.is_some() && !entry.source_ended)
    }

    pub(in crate::studio) fn materialize(
        &self,
        item: &pl_protocol::ThreadItem,
        effect: u64,
    ) -> Result<()> {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let old = state
            .assigned
            .get(&item.id)
            .and_then(|entry| entry.stamp.as_ref())
            .map_or(0, |stamp| stamp.turn_id.len() as u64);
        let new = item.turn_id.len() as u64;
        self.allocate_locked(
            &mut state,
            &item.id,
            None,
            Some(item.ordinal),
            new.saturating_sub(old),
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
        // allocate_locked and this update share the index lock: a save cannot prune the entry
        // between checking its placement and attaching the new pending obligation.
        let entry = state
            .assigned
            .get_mut(&item.id)
            .expect("allocated identity");
        if old > new {
            self.release_charge(old - new);
        }
        entry.stamp = Some(ExecutionStamp {
            revision: item.revision,
            created_at: item.created_at,
            updated_at: item.updated_at,
            turn_id: item.turn_id.clone(),
        });
        entry.effect = Some(entry.effect.unwrap_or(0).max(effect));
        entry.terminal |= item.is_terminal();
        drop(state);
        if old > new {
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
            ensure!(entry.ordinal == ordinal, "execution ordinal conflict");
            entry.clone()
        } else {
            ExecutionIdentity {
                ordinal,
                source: None,
                source_seen: false,
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
    fn commit_execution_batch(
        &self,
        state: &mut OrderIndexState,
        staged: BTreeMap<String, ExecutionIdentity>,
        ceiling: u64,
    ) -> Result<u64> {
        let mut old_bytes = 0_u64;
        let mut new_bytes = 0_u64;
        for (id, entry) in &staged {
            old_bytes =
                old_bytes.saturating_add(state.assigned.get(id).map_or(0, |old| old.bytes(id)));
            new_bytes = new_bytes.saturating_add(entry.bytes(id));
        }
        let added = new_bytes.saturating_sub(old_bytes);
        let released = old_bytes.saturating_sub(new_bytes);
        if added > 0 {
            self.charge(added, state.resident_blocked)?;
        }
        if released > 0 {
            self.release_charge(released);
        }
        state.assigned.extend(staged);
        state.ceiling = ceiling;
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
        for entry in state.assigned.values_mut() {
            if entry.source.as_deref() == Some(attempt_id) {
                entry.source_ended = true;
            }
        }
    }

    pub(in crate::studio) fn retain(
        &self,
        sources: &std::collections::BTreeSet<String>,
        identities: &std::collections::BTreeSet<String>,
    ) {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        for (id, entry) in &mut state.assigned {
            let source_live = entry.source.as_ref().is_some_and(|source| {
                if sources.contains(source) {
                    entry.source_seen = true;
                } else if entry.source_seen {
                    entry.source_ended = true;
                }
                // A synchronous producer can reserve before this projection reaches its start
                // checkpoint. Absence from an older checkpoint does not prove source retirement.
                !entry.source_ended
            });
            entry.retained = identities.contains(id) || source_live;
        }
        let released = self.prune(&mut state);
        drop(state);
        if released > 0 {
            self.notify_capacity();
        }
    }

    fn confirm_saved(&self, effect: u64) {
        #[cfg(test)]
        if let Some(entered) = self.confirm_saved_entered.lock().unwrap().take() {
            let _ = entered.send(());
        }
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state.durable = state.durable.max(effect);
        let released = self.prune(&mut state);
        drop(state);
        if released > 0 {
            self.notify_capacity();
        }
    }

    fn prune(&self, state: &mut OrderIndexState) -> u64 {
        let mut released = 0_u64;
        state.assigned.retain(|id, entry| {
            let keep = entry.retained || entry.effect.is_some_and(|seq| seq > state.durable);
            if !keep {
                released = released.saturating_add(entry.bytes(id));
            }
            keep
        });
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

#[derive(Debug, Default)]
struct Progress {
    stopped: bool,
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
    effect_bytes: u64,
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
    last_progress_at: Option<Instant>,
    /// Actual accepted output, separate from each operation's upper bound.
    operation_output: BTreeMap<String, OperationOutput>,
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
    delivery_admission_entered: Mutex<Option<std::sync::mpsc::Sender<()>>>,
    progress: Mutex<Progress>,
    changed: Arc<tokio::sync::Notify>,
    step_lock: tokio::sync::Mutex<()>,
    /// Every writer incarnation's physical workers remain registered until actually joined.
    /// Registration and explicit stop share this gate, including cancellation during startup.
    workers: tokio::sync::Mutex<Vec<tokio::task::JoinHandle<()>>>,
    worker_failure: Mutex<Option<Arc<tokio::task::JoinError>>>,
    pub(super) stopping: tokio_util::sync::CancellationToken,
    /// The process-wide reliable budget, shared by every Thread's channel.
    ///
    /// It charges exactly two things, each byte once: the effects the channels hold, each at the
    /// encoded size it was admitted with, and the accepted output still retained by in-flight
    /// model/tool operations. A fact produced by that operation takes those bytes over at
    /// admission instead of adding a second charge for the same output, and both charges are
    /// released when the fact becomes durable or the call ends without one.
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
            delivery_admission_entered: Mutex::new(None),
            progress: Mutex::new(Progress::default()),
            changed: Arc::new(tokio::sync::Notify::new()),
            step_lock: tokio::sync::Mutex::new(()),
            workers: tokio::sync::Mutex::new(Vec::new()),
            worker_failure: Mutex::new(None),
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
            ensure!(
                progress.effects.iter().any(|effect| {
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
        index.resident_blocked = result.is_err();
        drop(index);
        self.report(&progress);
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
        // Locate the entry by index so the budget update and the attach happen in one place without
        // holding a borrow of the queue while `prepared_bytes` changes.
        let Some(index) = progress
            .effects
            .iter()
            .position(|queued| queued.sequence == sequence)
        else {
            return false;
        };
        if let Some(existing) = &progress.effects[index].prepared {
            // Retries hand over the original frozen batch; replacing it could lose a published
            // completion or change the bytes behind an unchanged reliable-budget charge.
            return Arc::ptr_eq(existing, &prepared);
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
            order_index.resident_blocked = true;
            return false;
        }
        if transferred > 0 || progress.projection_pending.is_some() {
            progress.projection_bytes -= transferred;
            progress.projection_pending = None;
        }
        progress.prepared_bytes = progress.prepared_bytes.saturating_add(bytes);
        progress.effects[index].prepared_bytes = bytes;
        progress.effects[index].prepared = Some(prepared);
        progress.handoff = progress.handoff.max(sequence);
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
            .effects
            .iter()
            .find(|queued| queued.prepared.is_none())
            .map(|queued| queued.write.clone())
    }

    /// Captures the bounded, ordered projection backlog for one observer initialization.
    /// Only immutable handles are cloned under the queue lock; history reads happen afterwards.
    pub(in crate::studio) fn unprojected_writes(&self) -> Vec<Arc<ThreadWrite>> {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        progress
            .effects
            .iter()
            .filter(|queued| queued.prepared.is_none())
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
        let mut workers = self.workers.lock().await;
        {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            ensure!(
                progress.effects.is_empty() && progress.error.is_none(),
                "cannot stop a history writer with undurable facts"
            );
            progress.stopped = true;
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
        ensure!(
            self.is_clean(),
            "history writer stopped with undurable facts"
        );
        Ok(())
    }

    fn detect_stall(&self) {
        let mut progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.error.is_some()
            || progress.effects.is_empty()
            || !progress
                .last_progress_at
                .is_some_and(|last| last.elapsed() >= NO_PROGRESS_WINDOW)
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
        self.report(&progress);
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
        .iter()
        .map(|queued| queued.sequence)
        .collect::<Vec<_>>();
    let pending_bytes = progress.effect_bytes;
    // 每个待写 effect 自带它的候选 checkpoint，并与其在同一个事务落盘：队列非空就意味着历史与
    // checkpoint 都还 dirty，最老待写年龄因此只来自队列里每条 effect 自己的 saved_at。
    let pending_operations = progress.effects.len() as u64;
    let now = crate::studio::unix_seconds();
    let oldest_pending_age_millis = progress
        .effects
        .iter()
        .map(|queued| queued.write.checkpoint.saved_at)
        .map(|saved_at| {
            u64::try_from(now.saturating_sub(saved_at))
                .unwrap_or(0)
                .saturating_mul(1000)
        })
        .reduce(u64::min);
    let max_admitted = progress
        .effects
        .back()
        .map(|queued| queued.sequence)
        .unwrap_or(0);
    let dirty_revision = progress
        .effects
        .iter()
        .map(|queued| queued.write.checkpoint.state_revision)
        .max()
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
        let registered = store
            .catalog()
            .get(&thread.id)
            .context("Thread is not registered in the Studio catalog")?;
        anyhow::ensure!(
            registered.project_id == thread.project_id
                && store.workspaces().get(&thread.project_id).is_some(),
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
                        // 无合并窗口：空闲只等下一次受理或重试通知，周期性醒来只为检测停顿。
                        tokio::select! {
                            () = tokio::time::sleep(Duration::from_secs(1)) => {}
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
                            record_error(&inner, kind, message);
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
        // An explicit retry may arrive after QueueFull's fixed fence already
        // committed. Settle it even when no later effect can trigger a commit.
        if progress.fault == Some(pl_protocol::studio::HistoryFault::QueueFull)
            && clear_recovered_fault(&mut progress)
        {
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
    // 每个 effect 与它自己的候选 checkpoint 在同一次事务落盘：队列顺序即提交顺序，不再有单独的
    // checkpoint 选择、合并窗口或发布步骤。
    let next_effect = lock_progress(inner).effects.front().map(|queued| {
        (
            queued.sequence,
            queued.write.clone(),
            queued.prepared.clone(),
            queued.bytes,
        )
    });
    let Some((sequence, write, prepared, bytes)) = next_effect else {
        return Ok(Step::Idle);
    };
    // The Thread's live projection owner consumed this fact before the durable store may write it:
    // the writer commits the content that owner published instead of projecting the effect again, so
    // live and durable history can never disagree and durability never advances past a commit the
    // product has not published.
    let Some(prepared) = prepared else {
        return Ok(Step::Idle);
    };
    persist_effect(inner, sequence, &write, &prepared, bytes).await?;
    let mut progress = lock_progress(inner);
    let index = inner
        .channel
        .order_index
        .inner
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut released_bytes = 0;
    if let Some(committed) = progress.effects.pop_front() {
        let bytes = committed.bytes;
        let prepared_bytes = committed.prepared_bytes;
        ensure!(
            committed.sequence == sequence,
            "history queue head changed before acknowledgement"
        );
        progress.prepared_bytes = progress.prepared_bytes.saturating_sub(prepared_bytes);
        progress.effect_bytes -= bytes;
        released_bytes = bytes;
        progress.durable = progress.durable.max(sequence);
        progress.last_progress_at = (!progress.effects.is_empty()).then(Instant::now);
    }
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
        drop(write);
        drop(prepared);
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
async fn persist_effect(
    inner: &Inner,
    sequence: u64,
    write: &ThreadWrite,
    projected: &PreparedEffect,
    encoded_effect_bytes: u64,
) -> Result<()> {
    ensure!(
        projected.sequence == sequence
            && projected.accounting.sequence == sequence
            && projected.accounting.thread_id == inner.thread.id,
        "prepared history batch {sequence} was handed over as {}",
        projected.sequence
    );
    // 累计摘要按 effect 顺序折叠一次：从 writer 的运行值 clone，折叠本 effect 的绝对增量，放进该
    // effect 自己的 checkpoint，与它的历史事实在同一事务落盘。折叠只作用于 clone，事务失败时运行
    // 值不变，因此热读看到的总量绝不领先于已落库的 checkpoint。
    let (summary, accounting_changed) = {
        let progress = lock_progress(inner);
        let mut summary = progress.usage.clone();
        projected.accounting.fold_into(&mut summary);
        let changed = summary.pricing != progress.usage.pricing;
        (summary, changed)
    };
    let mut checkpoint = write.checkpoint.clone();
    checkpoint.state.usage_summary = summary.clone();
    // 统一 blob fence：checkpoint 引用的附件 blob 必须已经 durable，才允许提交引用它们的事务。
    let referenced = crate::studio::thread_projection::referenced_attachment_ids(&checkpoint.state);
    {
        let mut progress = lock_progress(inner);
        progress.in_flight_bytes = encoded_effect_bytes;
        progress.saving_revision = checkpoint.state_revision;
        report(inner, &progress);
    }
    inner
        .store
        .blob_fence(&inner.thread.id, &referenced)
        .await
        .map_err(|error| classified(pl_protocol::studio::HistoryFault::BlobFailed, error))?;
    let history = history_store(inner).await?;
    // 一个事务同时写：effect 的历史事实（含重放身份索引）、effect.context 增量对应的最新上下文、
    // pruned checkpoint 以及 history watermark。任一步失败即整体回滚，绝不会出现"历史已推进但
    // checkpoint 未落盘"或反过来的半提交状态。
    let completions: Vec<_> = projected
        .completions
        .iter()
        .map(|item| (**item).clone())
        .collect();
    let committed = history
        .commit_checkpoint_effect(
            &checkpoint,
            &write.effect,
            EffectCommit {
                items: &projected.items,
                completions: &completions,
                rolled_back_turns: &rolled_back_turns(&write.checkpoint.state),
                identities: &durable_input_identities(&inner.thread.id, &write.checkpoint.state),
                messages: &admitted_message_identities(&write.effect),
                receipts: &{
                    #[cfg(feature = "benchmarks")]
                    inner
                        .store
                        .calls()
                        .observation()
                        .increment(BenchMetric::ReceiptExtraction);
                    fact_receipts(&write.effect, projected)?
                },
                tasks: &write.effect.tasks,
                deliveries: &write.effect.deliveries,
                delivery_repairs: &write.effect.delivery_repairs,
                attempt: write.effect.attempt.as_ref(),
            },
            AccountingCommit {
                facts: &projected.accounting,
                material_changed: accounting_changed,
            },
        )
        .await;
    {
        let mut progress = lock_progress(inner);
        progress.saving_revision = 0;
    }
    let committed_accounting = committed?;
    inner.channel.order_index.confirm_saved(sequence);
    super::state::clear_checkpoint_recovery(&inner.thread.id);
    if let Some(accounting) = committed_accounting {
        submit_accounting(inner, accounting);
    }
    // Only this batch's actual persisted prefix may leave pending. A later effect can already
    // have published more records; acknowledging the Session head would falsely save those.
    if let Some(last) = projected.completions.last() {
        inner.chat.confirm_durable(last.append_seq)?;
    }
    // 调用统计始终是独立的 best-effort：它与历史/checkpoint 事务无关，失败只影响可丢诊断。
    inner.store.calls().record_effect(&write.effect);
    // 事务成功后才发布运行值、已落库 revision 和用量累计。
    inner
        .store
        .thread_persistence()
        .set_usage(&inner.thread.id, summary.clone());
    {
        let mut progress = lock_progress(inner);
        progress.usage = summary;
        progress.published_revision = progress.published_revision.max(checkpoint.state_revision);
        progress.in_flight_bytes = 0;
        progress.pressure_paused = write.checkpoint.state.persistence.pressure_paused;
        report(inner, &progress);
    }
    Ok(())
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

fn record_error(inner: &Inner, kind: pl_protocol::studio::HistoryFault, message: String) {
    {
        let mut progress = lock_progress(inner);
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        progress.retry_requested = false;
        progress.fault = Some(kind);
        progress.error = Some(message);
        progress.fault_recovered = false;
        // A failed publication is no longer being serialized; the retained checkpoint stays queued
        // for retry, and the metric must not keep reporting it as actively saving.
        progress.saving_revision = 0;
        report(inner, &progress);
    }
    inner.changed.notify_one();
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
                error.to_string(),
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
            || write.effect.sequence != write.checkpoint.state_revision
            || write.checkpoint.history_fence != write.effect.sequence
        {
            // A contract failure is terminal for this sink and never a transient conflict: publish it
            // so `pressure().error` — the one report core mirrors into its own storage latch — agrees
            // with the error this call returns instead of letting the latch look recovered.
            record_error(
                &self.0,
                pl_protocol::studio::HistoryFault::WriteFailed,
                "Thread persistence ticket mismatch".to_owned(),
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
        if sequence > progress.durable
            && !progress
                .effects
                .iter()
                .any(|queued| queued.sequence == sequence)
        {
            let mut index = self
                .0
                .channel
                .order_index
                .inner
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            let queued_bytes = progress
                .effect_bytes
                .saturating_add(self.0.channel.order_index.retained_bytes());
            // The fact takes over the bytes of its own operation's reservation instead of being
            // charged next to them; only bytes not already charged need new headroom.
            let (transfer, covered) =
                output_transfer_plan(&progress, write.output_claim.as_deref(), bytes);
            let added = bytes.saturating_sub(covered);
            if progress.effects.len() >= MAX_HISTORY_BATCHES
                || queued_bytes
                    .checked_add(bytes)
                    .is_none_or(|total| total > MAX_HISTORY_THREAD_BYTES)
                || (added > 0 && !self.0.channel.reserve(added))
            {
                let message =
                    format!("history queue full for Thread {thread_id} at write_seq {sequence}");
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(pl_protocol::studio::HistoryFault::QueueFull);
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                drop(index);
                report(&self.0, &progress);
                return Err(cold_error(&message));
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
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(if error.is::<ExecutionIndexBudgetFull>() {
                    pl_protocol::studio::HistoryFault::QueueFull
                } else {
                    pl_protocol::studio::HistoryFault::WriteFailed
                });
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                drop(index);
                report(&self.0, &progress);
                return Err(cold_error(&message));
            }
            #[cfg(test)]
            self.0.channel.pause_resident_commit();
            for (operation, taken) in transfer {
                if let Some(output) = progress.operation_output.get_mut(&operation) {
                    output.transferred += taken;
                }
            }
            progress.effects.push_back(QueuedEffect {
                sequence,
                write: Arc::new(write.clone()),
                bytes,
                // The projection owner takes this entry over from the same queue, in this order.
                prepared: None,
                prepared_bytes: 0,
            });
            progress.effect_bytes += bytes;
            progress.last_progress_at.get_or_insert_with(Instant::now);
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
        if thread_id != self.0.thread.id {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence owner mismatch")),
            });
        }
        // 固定目标只需等待它自己的 effect durable：checkpoint 与该 effect 在同一事务落盘，所以
        // durable 前进即意味着目标 checkpoint 也已提交，不再有独立的发布水位要等。
        self.0.changed.notify_one();
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
pub(crate) mod storage_fault_tests {
    use super::*;
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        model::{
            DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
            ModelToolCall, PreparedModelCall,
        },
        thread::{
            ModelStepLimit, ThreadEffectBatch, ThreadHandle, ThreadSnapshot, TurnInput,
            TurnOutcome, TurnRecord, TurnState,
            cold::ColdStoreHandle,
            input::{InputChange, InputRecord, InputState, ThreadInput},
            task::TaskStatus,
        },
        tool::{
            ToolOutput,
            opaque::{CallContext, Registration, Tool, ToolError},
        },
    };
    use sea_orm::{ConnectionTrait, Database};
    use tokio::sync::{Notify, mpsc};
    use tokio_util::sync::CancellationToken;

    #[derive(Debug)]
    struct ConcurrentModel(Arc<AtomicUsize>);

    impl ModelSession for ConcurrentModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            self.0.fetch_add(1, Ordering::Relaxed);
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("running both tools"),
                    }],
                    tool_calls: ["first", "second"]
                        .into_iter()
                        .map(|id| ModelToolCall {
                            rejection: None,
                            call_id: id.to_owned(),
                            tool_id: id.to_owned(),
                            arguments: OpaquePayload::text(id),
                        })
                        .collect(),
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[derive(Debug)]
    struct ConcurrentTool {
        started: mpsc::UnboundedSender<String>,
        release: Arc<Notify>,
        executions: Arc<Mutex<Vec<String>>>,
    }

    impl Tool for ConcurrentTool {
        async fn execute(
            &self,
            input: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            self.executions
                .lock()
                .unwrap()
                .push(context.call_id.clone());
            self.started.send(context.call_id).unwrap();
            self.release.notified().await;
            Ok(ToolOutput::new(
                input.clone(),
                vec![ContextContent::Text {
                    text: Arc::from(input.content()),
                }],
            ))
        }
    }

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

    fn ticket_referencing_attachment(
        thread_id: &str,
        attachment: &crate::studio::AttachmentRecord,
    ) -> Result<ThreadWrite> {
        let mut write = ticket(thread_id, 1);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: "attached-input".to_owned(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({
                        "text": "attached",
                        "presentation": "visible",
                        "attachments": [attachment],
                    })
                    .to_string(),
                )?,
                context: Vec::new(),
            },
            ordinal: 1,
            revision: 1,
            state: InputState::Pending,
        };
        write.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Ok(write)
    }

    fn test_thread(thread_id: &str) -> pl_protocol::Thread {
        let mut thread = pl_protocol::Thread::placeholder(thread_id);
        thread.project_id = "project-test".into();
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
                id: thread.project_id.clone(),
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
        delta.thread_upserts = vec![thread.clone()];
        store.persist_directory_summaries(&delta).await
    }

    async fn sink(thread_id: &str) -> Result<(tempfile::TempDir, StudioStore, ThreadStorageSink)> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread(thread_id);
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread, None).await?;
        spawn_live_projection(&sink);
        Ok((temp, store, sink))
    }

    #[tokio::test]
    async fn late_reliable_summary_publishes_without_another_billing() -> Result<()> {
        use crate::studio::agent_host::ThreadWriteBehindWriter;
        use crate::studio::runtime::ModelPerformanceOwner;
        use crate::studio::thread_projection::AuxiliaryBillingReceipt;
        use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};
        use pl_protocol::{
            FirstOutputSource, InferenceAccounting, InferenceBillingRecord, InferenceTiming,
            PricingOutcome, RuntimeCostAmount, UsageReport,
        };

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread("late-summary");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let product_writer = ThreadWriteBehindWriter::new(store.clone());
        let events = crate::studio::ProductEventBus::new(store.clone(), product_writer.clone());
        let mut cost_events = events.subscribe_topic(&crate::StudioProductTopic::SessionCosts {
            root_thread_id: thread.root_thread_id.clone(),
        });
        let owner = ModelPerformanceOwner::new(store.clone(), events, "late-summary-owner".into());
        owner.initialize_projection().await;
        let feed = owner.subscribe_statistics();
        let initial = feed.next().await?.context("missing initial statistics")?;
        feed.acknowledge(initial.delivery_sequence)?;

        let billing = InferenceBillingRecord {
            inference_id: "title-call".into(),
            purpose: Some("title".into()),
            account_id: "account".into(),
            account_display_name: Some("Account".into()),
            model_id: Some("model".into()),
            model_observation: None,
            effort: None,
            context_window: None,
            accounting: InferenceAccounting {
                usage: UsageReport {
                    input_tokens: Some(10),
                    output_tokens: Some(2),
                    cache_read_tokens: Some(0),
                    total_tokens: Some(12),
                    ..Default::default()
                },
                pricing: PricingOutcome::Estimated {
                    cost: RuntimeCostAmount {
                        currency: "USD".into(),
                        amount: 1.25,
                    },
                    cache_savings: None,
                },
                ..Default::default()
            },
            prompt_generation: None,
            prompt_cache_policy: None,
            prefix_changed_reason: None,
            orchestration: Default::default(),
            timing: Some(InferenceTiming {
                first_output_source: FirstOutputSource::CompletedToolInput,
                ttft_millis: Some(100),
                decode_millis: Some(0),
                response_millis: 100,
            }),
            recorded_at: crate::studio::unix_seconds(),
        };
        let extension = ExtensionRecord {
            revision: 1,
            payload: AuxiliaryBillingReceipt {
                billing: billing.clone(),
                succeeded: true,
            }
            .into_payload()?,
        };
        let mut write = ticket(&thread.id, 1);
        Arc::make_mut(&mut write.effect).extensions = vec![ExtensionChange::Put {
            id: "studio.auxiliary-billing.title".into(),
            record: extension.clone(),
        }]
        .into();
        write.checkpoint.state.extension_sequence = 1;
        write
            .checkpoint
            .state
            .extensions
            .insert("studio.auxiliary-billing.title".into(), extension);

        // Block the actual ordered history writer, not a replacement saver or artificial delay.
        let history_gate = sink.0.channel.step_lock.lock().await;
        sink.admit(&thread.id, write.clone())?;
        let mut live = live_projection(&sink).await?;
        let (_, mut prepared) = live
            .prepare(&thread, &write.effect, &write.checkpoint.state, false)
            .await?;
        live.publish_prepared(&sink.0.chat, &mut prepared).await?;
        assert!(sink.0.channel.prepare(prepared.clone()));
        for fact in prepared.accounting.facts.iter() {
            owner.record_auxiliary_inference(
                &thread.root_thread_id,
                &thread.id,
                &fact.record,
                fact.status,
            )?;
        }
        let billing_publication = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let header = feed.next().await?.context("statistics feed closed")?;
                feed.acknowledge(header.delivery_sequence)?;
                if owner.snapshot().await.history.len() == 1 {
                    break Ok::<_, anyhow::Error>(header);
                }
            }
        })
        .await
        .context("Billing performance publication timed out")??;
        assert_eq!(store.history(&thread.id).await?.watermark().await?, 0);
        assert!(
            owner
                .session_costs_snapshot(&thread.id)
                .await
                .cost
                .is_none()
        );
        let before_costs = owner.snapshot().await;
        assert_eq!(
            billing_publication.history_count,
            before_costs.history.len() as u64
        );
        assert_eq!(before_costs.history[0].completion_tokens, Some(2));
        assert_eq!(
            before_costs.history[0].first_output_source,
            FirstOutputSource::CompletedToolInput
        );
        assert_eq!(before_costs.history[0].decode_millis, Some(0));

        drop(history_gate);
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
        // A late cost-only Summary must publish its scoped fact, not manufacture a global
        // performance revision solely to wake this test. Observe the actual consumer topic.
        let costs_publication = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let crate::StudioProductEventKind::SessionCostsChanged(state) =
                    cost_events.recv().await?.kind
                    && state
                        .cost
                        .as_ref()
                        .and_then(|cost| cost.estimated_costs.first())
                        .is_some_and(|cost| cost.amount == 1.25)
                {
                    break Ok::<_, anyhow::Error>(state);
                }
            }
        })
        .await
        .context("late Summary scoped cost publication timed out")??;
        assert_eq!(costs_publication.root_thread_id, thread.root_thread_id);
        assert!(!costs_publication.read_failed);
        assert_eq!(
            owner.session_costs_snapshot(&thread.id).await,
            costs_publication
        );
        let after_costs = owner.snapshot().await;
        assert!(
            Arc::ptr_eq(&after_costs.history, &before_costs.history),
            "cost-only publication must retain the frozen history material"
        );
        assert!(
            Arc::ptr_eq(&after_costs.summaries, &before_costs.summaries),
            "cost-only publication must retain the frozen summary material"
        );
        assert_eq!(after_costs.history, before_costs.history);
        assert_eq!(
            store
                .history(&thread.id)
                .await?
                .checkpoint()
                .await?
                .unwrap()
                .state
                .usage_summary
                .totals
                .inference_count,
            1
        );

        // Repeating the same reliable fact and billing does not add another contribution.
        let admitted = store.calls().admitted_ticket();
        sink.admit(&thread.id, write)?;
        owner.record_auxiliary_inference(
            &thread.root_thread_id,
            &thread.id,
            &billing,
            super::super::calls::CallStatus::Committed,
        )?;
        assert_eq!(store.calls().admitted_ticket(), admitted);
        sink.0.channel.stop_and_join().await?;
        feed.close().await?;
        owner.close().await?;
        product_writer.shutdown().await?;
        store.close().await?;
        Ok(())
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
            owner: &crate::thread_assembler::StudioThreadAssembler,
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
            mcp_runtime: pl_tool::mcp::McpRuntime::new(pl_tool::mcp::McpConnector::default())
                .handle(),
            lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry::new(),
            skills: crate::studio::runtime::SkillCatalogRuntime::new(
                events.clone(),
                store.paths().home().join("isolated-test-skills"),
            ),
            thread_modes: config.thread_mode_manager(),
            ssh_manager: Arc::new(crate::worker_assets::ssh_manager(&source)),
            helper_source: source,
            bots,
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

    #[tokio::test]
    async fn close_intent_preserves_inherited_and_actual_assignment_for_subdirectory_projects()
    -> Result<()> {
        use crate::agent::worktree::{WorktreeManager, WorktreeOwnership};
        use crate::studio::agent_host::worktree_lease::{
            WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
            WorktreeLeaseState,
        };
        use pl_protocol::{
            AgentWorkspaceAssignmentSnapshot, AgentWorkspaceMode, AgentWorktreeSnapshot,
        };
        async fn register(
            store: &StudioStore,
            thread: &pl_protocol::Thread,
            project_root: &std::path::Path,
        ) -> Result<()> {
            let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
                crate::studio::store::directory::ProjectDirectoryRecord {
                    id: thread.project_id.clone(),
                    kind: pl_protocol::studio::WorkspaceKind::Project,
                    name: "Subdirectory Project".into(),
                    path: project_root.to_string_lossy().into_owned(),
                    ssh_alias: None,
                    created_at: 1,
                    updated_at: 1,
                    last_opened_at: None,
                    closed: false,
                },
            );
            delta.thread_upserts.push(thread.clone());
            store.persist_directory_summaries(&delta).await
        }
        let temp = tempfile::tempdir()?;
        let repository = temp.path().join("repository");
        let project_root = repository.join("subdirectory");
        tokio::fs::create_dir_all(&project_root).await?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let mut root = test_thread("root-local");
        root.workspace_path = project_root.to_string_lossy().into_owned();
        register(&store, &root, &project_root).await?;
        let mut root_worktree = test_thread("root-worktree");
        root_worktree.workspace_mode = pl_protocol::ThreadWorkspaceMode::Worktree;
        let root_site = WorktreeManager::allocate_path(
            &repository,
            &root_worktree.id,
            &WorktreeOwnership::Session {
                thread_id: root_worktree.id.clone(),
            },
        );
        root_worktree.workspace_path = root_site.to_string_lossy().into_owned();
        register(&store, &root_worktree, &project_root).await?;
        let child_site = WorktreeManager::allocate_path(
            &repository,
            &root.id,
            &WorktreeOwnership::Child {
                child_id: "worktree-owner".into(),
            },
        );
        let child_receipt = AgentWorktreeSnapshot {
            repository_root: repository.to_string_lossy().into_owned(),
            path: child_site.to_string_lossy().into_owned(),
            base_commit: "a".repeat(40),
        };
        let mut cases = Vec::new();
        for (id, parent, mode, assigned, receipt, reviewed) in [
            (
                "worktree-owner",
                &root,
                AgentWorkspaceMode::Worktree,
                &child_site,
                Some(child_receipt.clone()),
                None,
            ),
            (
                "review-owner",
                &root,
                AgentWorkspaceMode::Review,
                &child_site,
                Some(child_receipt.clone()),
                Some(pl_protocol::AgentReviewTargetSnapshot {
                    baseline: None,
                    feedback: None,
                    agent_id: "worktree-owner".into(),
                }),
            ),
            (
                "directory-owner",
                &root,
                AgentWorkspaceMode::Directory,
                &project_root,
                None,
                None,
            ),
            (
                "session-directory-owner",
                &root_worktree,
                AgentWorkspaceMode::Directory,
                &root_site,
                None,
                None,
            ),
        ] {
            tokio::fs::create_dir_all(assigned).await?;
            let mut thread = test_thread(id);
            thread.parent_thread_id = Some(parent.id.clone());
            thread.root_thread_id = parent.id.clone();
            thread.workspace_path = parent.workspace_path.clone();
            thread.workspace_mode = parent.workspace_mode;
            register(&store, &thread, &project_root).await?;
            let assignment = AgentWorkspaceAssignmentSnapshot {
                mode,
                project_root: project_root.to_string_lossy().into_owned(),
                root: assigned.to_string_lossy().into_owned(),
                writable_paths: None,
                worktree: receipt,
                review_target: reviewed,
            };
            cases.push((thread, assignment));
        }
        store
            .persist_directory_summaries(
                &crate::studio::store::directory::DirectoryDelta::upsert_project(
                    crate::studio::store::directory::ProjectDirectoryRecord {
                        id: "project-test".into(),
                        kind: pl_protocol::studio::WorkspaceKind::Project,
                        name: "Subdirectory Project".into(),
                        path: project_root.to_string_lossy().into_owned(),
                        ssh_alias: None,
                        created_at: 1,
                        updated_at: 1,
                        last_opened_at: None,
                        closed: false,
                    },
                ),
            )
            .await?;
        let project = store.read_project("project-test").await?.unwrap();
        let fixture = close_factory(&store)?;
        for (owner, kind, root_id, path) in [
            (
                "worktree-owner",
                WorktreeLeaseOwnerKind::Child,
                root.id.as_str(),
                child_site.clone(),
            ),
            (
                root_worktree.id.as_str(),
                WorktreeLeaseOwnerKind::Session,
                root_worktree.id.as_str(),
                root_site.clone(),
            ),
        ] {
            let mut lease = WorktreeLease {
                revision: 1,
                state: WorktreeLeaseState::Prepared,
                owner_kind: kind,
                owner_thread_id: owner.into(),
                root_thread_id: root_id.into(),
                project_id: "project-test".into(),
                ssh_alias: None,
                repository_root: repository.to_string_lossy().into_owned(),
                path: path.to_string_lossy().into_owned(),
                base_commit: "a".repeat(40),
            };
            fixture.worktrees.record_durable(lease.clone()).await?;
            lease.transition(WorktreeLeaseState::Active);
            fixture.worktrees.record_durable(lease).await?;
        }
        for (thread, assignment) in cases {
            store.prepare_session_manifest(&thread).await?;
            let execution = std::path::Path::new(&assignment.root)
                .join(pl_tool::workspace::SessionFiles::new(&thread.id).root());
            tokio::fs::create_dir_all(&execution).await?;
            tokio::fs::write(execution.join("owned"), b"exact owner").await?;
            let identity =
                WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, assignment.root.clone())?;
            store.bind_workspace_identity(&thread.id, &identity).await?;
            let core =
                pl_core::thread::ThreadHandle::resume_without_model(thread.id.clone(), None)?;
            core.mutate_extensions(vec![
                pl_core::thread::extensions::ExtensionMutation::Put {
                    id: crate::studio::workspace_receipt::EXTENSION.into(),
                    expected_revision: None,
                    payload: crate::studio::workspace_receipt::to_payload(&assignment)
                        .map_err(anyhow::Error::msg)?,
                },
                pl_core::thread::extensions::ExtensionMutation::Put {
                    id: "studio.project".into(),
                    expected_revision: None,
                    payload: pl_core::context::OpaquePayload::new(
                        "pl.studio.project",
                        1,
                        serde_json::to_string(&project)?,
                    )?,
                },
            ])
            .await?;
            let close = fixture
                .factory
                .begin_child_close(&thread, Some(&core.snapshot()), false)
                .await?;
            if assignment.mode == AgentWorkspaceMode::Worktree {
                let owned = close.worktree.as_ref().context("actual owned worktree")?;
                assert_eq!(owned.lease.path, assignment.root);
                assert_eq!(owned.identity, identity);
                assert_ne!(thread.workspace_path, owned.lease.path);
            } else {
                assert!(
                    close.worktree.is_none(),
                    "directory/review must not acquire deletion ownership"
                );
            }
            assert_eq!(
                tokio::fs::read(execution.join("owned")).await?,
                b"exact owner"
            );
            let repeated = fixture
                .factory
                .begin_child_close(&thread, None, false)
                .await?;
            assert_eq!(close, repeated);
            core.close().await?;
        }
        fixture.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn unknown_old_close_candidates_preserve_source_and_refuse_new_delete_authority()
    -> Result<()> {
        use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let parent = test_thread("legacy-parent");
        register_test_thread(&store, &parent).await?;
        let mut child = test_thread("legacy-child");
        child.parent_thread_id = Some(parent.id.clone());
        child.root_thread_id = parent.id.clone();
        child.workspace_path = parent.workspace_path.clone();
        register_test_thread(&store, &child).await?;
        let source = store
            .registered_session_paths(&child.id)?
            .root()
            .join("retained-evidence");
        tokio::fs::create_dir_all(source.parent().unwrap()).await?;
        tokio::fs::write(&source, b"original history and attachments").await?;
        let payload = r#"{"unknownOriginalCloseFacts":true}"#;
        let hash = pl_core::context::content_hash(payload.as_bytes());
        store.database().execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "INSERT INTO studio_objects(owner_kind,owner_id,object_kind,schema_version,revision,payload_json,payload_hash,updated_at) VALUES ('thread',?,'agentRetirement',99,1,?,?,1)",
            [child.id.clone().into(), payload.to_owned().into(), hash.clone().into()])).await?;
        let fixture = close_factory(&store)?;
        assert!(
            store
                .ensure_agent_execution_allowed(&child.id)
                .await
                .is_err()
        );
        assert!(
            fixture
                .factory
                .begin_child_close(&child, None, true)
                .await
                .is_err()
        );
        assert!(store.agent_close(&child.id).await?.is_none());
        let row = store.database().query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "SELECT schema_version,payload_json,payload_hash FROM studio_objects WHERE owner_id=? AND object_kind='agentRetirement'",
            [child.id.into()])).await?.context("preserved unknown object")?;
        assert_eq!(row.try_get::<i64>("", "schema_version")?, 99);
        assert_eq!(row.try_get::<String>("", "payload_json")?, payload);
        assert_eq!(row.try_get::<String>("", "payload_hash")?, hash);
        assert_eq!(
            tokio::fs::read(source).await?,
            b"original history and attachments"
        );
        fixture.shutdown().await?;
        Ok(())
    }

    /// Replaces the former whole-resource retirement case with the actual close/storage contract:
    /// save ACKs, live borrowers, content protection, retained history/refs and replacement safety.
    #[tokio::test]
    async fn close_worktree_preserves_original_history_refs_and_terminal_replacements() -> Result<()>
    {
        use crate::agent::worktree::{
            LocalWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
        };
        use crate::studio::agent_close::AgentWorktreeCleanup;
        use crate::studio::agent_host::worktree_lease::{
            WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
            WorktreeLeaseState,
        };
        use pl_core::context::ResourceReader;
        use pl_core::thread::{ThreadHandle, cold::ColdStoreHandle, extensions::ExtensionMutation};

        async fn git(root: &std::path::Path, args: &[&str]) -> Result<String> {
            let output = tokio::process::Command::new("git")
                .args(args)
                .current_dir(root)
                .output()
                .await?;
            anyhow::ensure!(
                output.status.success(),
                "git {args:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            Ok(String::from_utf8(output.stdout)?.trim().to_owned())
        }
        let temp = tempfile::tempdir()?;
        let repository = temp.path().join("repository");
        tokio::fs::create_dir_all(&repository).await?;
        git(&repository, &["init", "--quiet"]).await?;
        git(&repository, &["config", "user.name", "Close fixture"]).await?;
        git(
            &repository,
            &["config", "user.email", "close@example.invalid"],
        )
        .await?;
        tokio::fs::write(repository.join(".gitignore"), b".anywork/\n").await?;
        tokio::fs::write(repository.join("tracked"), b"committed").await?;
        git(&repository, &["add", ".gitignore", "tracked"]).await?;
        git(
            &repository,
            &["commit", "--quiet", "-m", "fixture baseline"],
        )
        .await?;
        let repository = dunce::canonicalize(repository)?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let mut parent = test_thread("close-parent");
        parent.workspace_path = repository.to_string_lossy().into_owned();
        register_test_thread(&store, &parent).await?;
        let mut child = test_thread("close-owned-child");
        child.parent_thread_id = Some(parent.id.clone());
        child.root_thread_id = parent.id.clone();
        child.workspace_path = parent.workspace_path.clone();
        register_test_thread(&store, &child).await?;
        let fixture = close_factory(&store)?;
        let manager = WorktreeManager::new(
            repository.clone(),
            Arc::new(LocalWorktreeBackend::default()),
        );
        let ownership = WorktreeOwnership::Child {
            child_id: child.id.clone(),
        };
        let head = manager.resolve_head(&repository).await?;
        let mut lease = WorktreeLease {
            revision: 1,
            state: WorktreeLeaseState::Prepared,
            owner_kind: WorktreeLeaseOwnerKind::Child,
            owner_thread_id: child.id.clone(),
            root_thread_id: parent.id.clone(),
            project_id: child.project_id.clone(),
            ssh_alias: None,
            repository_root: parent.workspace_path.clone(),
            path: WorktreeManager::allocate_path(&repository, &parent.id, &ownership)
                .to_string_lossy()
                .into_owned(),
            base_commit: head.clone(),
        };
        fixture.worktrees.record_durable(lease.clone()).await?;
        let handle = manager
            .create(WorktreeCreateSpec {
                repo_root: repository.clone(),
                root_thread_id: parent.id.clone(),
                ownership,
                base_commit: head,
            })
            .await?;
        lease.transition(WorktreeLeaseState::Active);
        fixture.worktrees.record_durable(lease.clone()).await?;
        let identity = WorkspaceIdentity::canonical(WorkspaceEndpoint::Local, lease.path.clone())?;
        store.bind_workspace_identity(&child.id, &identity).await?;
        store
            .bind_workspace_identity(
                &parent.id,
                &WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    parent.workspace_path.clone(),
                )?,
            )
            .await?;
        let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
            mode: pl_protocol::AgentWorkspaceMode::Worktree,
            project_root: parent.workspace_path.clone(),
            root: lease.path.clone(),
            writable_paths: None,
            review_target: None,
            worktree: Some(pl_protocol::AgentWorktreeSnapshot {
                repository_root: lease.repository_root.clone(),
                path: lease.path.clone(),
                base_commit: lease.base_commit.clone(),
            }),
        };
        let core = ThreadHandle::resume_without_model(child.id.clone(), None)?;
        let sink = ThreadStorageSink::new(store.clone(), child.clone(), None).await?;
        spawn_live_projection(&sink);
        core.attach_storage(ColdStoreHandle::new(sink)).await?;
        core.mutate_extensions(vec![ExtensionMutation::Put {
            id: crate::studio::workspace_receipt::EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::workspace_receipt::to_payload(&assignment)
                .map_err(anyhow::Error::msg)?,
        }])
        .await?;
        let resources =
            crate::resource_store::FileResourceStore::new(store.session_resources_dir(&child.id)?);
        let reference = resources
            .retain_bytes(
                Arc::from(&b"reliable original attachment"[..]),
                "text/plain",
            )
            .await?;
        let independent_files =
            repository.join(pl_tool::workspace::SessionFiles::new(&parent.id).root());
        tokio::fs::create_dir_all(&independent_files).await?;
        tokio::fs::write(
            independent_files.join("retained"),
            b"independent session files",
        )
        .await?;
        let borrower = fixture
            .worktrees
            .reserve_workspace("active-reviewer", WorkspaceEndpoint::Local)?;
        fixture
            .worktrees
            .assign_workspace(&borrower, identity.clone())?;
        fixture
            .factory
            .begin_child_close(&child, Some(&core.snapshot()), false)
            .await?;
        crate::studio::agent_close::commit(&core).await?;
        core.close().await?;
        store
            .thread_persistence()
            .history_channel(&child.id)
            .stop_and_join()
            .await?;
        let history = store.history(&child.id).await?;
        let saved = serde_json::to_vec(&history.checkpoint().await?)?;
        fixture.factory.finish_child_execution(&child).await?;
        let (blocked, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(blocked.execution_closed);
        assert!(
            error
                .context("active borrower must block")?
                .message
                .contains("active-reviewer")
        );
        assert!(matches!(
            blocked.worktree_cleanup,
            AgentWorktreeCleanup::Failed { .. }
        ));
        drop(borrower);
        tokio::fs::write(handle.path.join("tracked"), b"uncommitted child work").await?;
        let (dirty, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(error.is_some());
        assert!(matches!(
            dirty.worktree_cleanup,
            AgentWorktreeCleanup::Failed { .. }
        ));
        assert!(tokio::fs::try_exists(&handle.path).await?);
        git(&handle.path, &["add", "tracked"]).await?;
        git(
            &handle.path,
            &["commit", "--quiet", "-m", "undelivered child work"],
        )
        .await?;
        let before_refusal_head = git(&handle.path, &["rev-parse", "HEAD"]).await?;
        // Detached creation owns no branch. An independently created business ref must survive
        // close even when the child checks it out after its ownership was frozen.
        let retained_branch = "retained-business";
        git(&handle.path, &["switch", "-c", retained_branch]).await?;
        let (_, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(
            error
                .context("undelivered HEAD must block default close")?
                .message
                .contains("not contained")
        );
        assert!(
            store.agent_close(&child.id).await?.unwrap().git.is_none(),
            "content refusal must precede the destructive grant, preserving a force retry"
        );
        fixture
            .factory
            .begin_child_close(&child, None, true)
            .await?;
        git(&repository, &["worktree", "lock", &lease.path]).await?;
        let (_, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(
            error
                .context("Git lock must still block force")?
                .message
                .contains("locked")
        );
        assert!(
            !store
                .agent_close(&child.id)
                .await?
                .unwrap()
                .git
                .unwrap()
                .removal_started,
            "a confirmed Git refusal plus the original remaining site permits a fresh attempt"
        );
        // A previous attempt's expected HEAD is content authorization, not permanent identity.
        tokio::fs::write(
            handle.path.join("tracked"),
            b"advanced after confirmed refusal",
        )
        .await?;
        git(&handle.path, &["add", "tracked"]).await?;
        git(
            &handle.path,
            &["commit", "--quiet", "-m", "advance after refused removal"],
        )
        .await?;
        let retained_head = git(&handle.path, &["rev-parse", "HEAD"]).await?;
        assert_ne!(retained_head, before_refusal_head);
        git(&repository, &["worktree", "unlock", &lease.path]).await?;
        let (removed, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(error.is_none(), "{error:?}");
        assert_eq!(
            removed.worktree_cleanup,
            AgentWorktreeCleanup::Removed {
                path: lease.path.clone()
            }
        );
        assert!(!tokio::fs::try_exists(&handle.path).await?);
        assert_eq!(
            git(&repository, &["rev-parse", retained_branch]).await?,
            retained_head
        );
        assert_eq!(serde_json::to_vec(&history.checkpoint().await?)?, saved);
        assert_eq!(
            &*resources.read(reference, Default::default()).await?,
            b"reliable original attachment"
        );
        assert_eq!(
            tokio::fs::read(independent_files.join("retained")).await?,
            b"independent session files"
        );
        git(
            &repository,
            &["worktree", "add", &lease.path, retained_branch],
        )
        .await?;
        let (repeated, error) = fixture
            .factory
            .finish_child_worktree_cleanup(&child)
            .await?;
        assert!(
            error.is_some(),
            "a terminal grant must not delete a replacement"
        );
        assert_eq!(repeated.worktree_cleanup, removed.worktree_cleanup);
        assert!(tokio::fs::try_exists(&handle.path).await?);
        fixture
            .factory
            .restore_workspace_admission(
                crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
            )
            .await?;
        assert!(tokio::fs::try_exists(&handle.path).await?);
        assert!(
            store
                .ensure_agent_execution_allowed(&child.id)
                .await
                .is_err()
        );
        assert!(history.checkpoint().await?.is_some());
        // A fresh process hydrates the top-level lease after it reads the close record. The old
        // preserved ownership must not resurrect a physical borrow once this result is terminal.
        let restarted = close_factory(&store)?;
        restarted
            .factory
            .restore_workspace_admission(
                crate::studio::agent_host::worktree_lease::load_leases(&store).await?,
            )
            .await?;
        let container = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            repository.to_string_lossy().into_owned(),
        )?;
        let seal = restarted.worktrees.try_seal_workspace(
            "new-container-owner",
            container.clone(),
            &std::collections::BTreeSet::new(),
        )?;
        restarted
            .worktrees
            .release_workspace_seal("new-container-owner", &container)?;
        drop(seal);
        assert!(
            store
                .ensure_agent_execution_allowed(&child.id)
                .await
                .is_err()
        );
        restarted.shutdown().await?;
        fixture.shutdown().await?;
        Ok(())
    }

    /// Physical binding persistence and live admission share exact identities. The domain seal's
    /// producer still owns the grant ACK proof; this component does not execute a full close/Git.
    #[tokio::test]
    async fn saved_workspace_identity_keeps_preparers_and_pending_cleanup_until_release()
    -> Result<()> {
        use crate::studio::agent_host::{
            ThreadWriteBehindWriter,
            worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity, WorktreeLeaseOwner},
        };
        use std::collections::BTreeSet;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let root = temp.path().join("repository");
        let workspace = root.join(".anywork/worktrees/root-a/child-w");
        tokio::fs::create_dir_all(&workspace).await?;
        let canonical = dunce::canonicalize(&workspace)?;
        let identity = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            canonical.to_string_lossy().into_owned(),
        )?;
        store.bind_workspace_identity("child-w", &identity).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let owner = WorktreeLeaseOwner::new(writer.clone());
        let preparing = owner.reserve_workspace("root-b-preparer", WorkspaceEndpoint::Local)?;
        let foreign_owner = WorktreeLeaseOwner::new(writer.clone());
        let foreign =
            foreign_owner.reserve_workspace("foreign-preparer", WorkspaceEndpoint::Local)?;
        assert!(
            owner.assign_workspace(&foreign, identity.clone()).is_err(),
            "equal serials from different runtime owners must not alias"
        );
        drop(foreign);
        let closing = BTreeSet::from(["child-w".into(), "review-r".into()]);
        assert!(
            owner
                .try_seal_workspace("child-w", identity.clone(), &closing)
                .err()
                .unwrap()
                .to_string()
                .contains("root-b-preparer")
        );
        // An assigned ancestor root does not borrow every worktree below its pool forever.
        owner.assign_workspace(
            &preparing,
            WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                dunce::canonicalize(&root)?.to_string_lossy().into_owned(),
            )?,
        )?;
        let external = owner.reserve_workspace("other-project-root", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&external, identity.clone())?;
        assert!(
            owner
                .try_seal_workspace("child-w", identity.clone(), &closing)
                .err()
                .unwrap()
                .to_string()
                .contains("other-project-root")
        );
        drop(external);
        let binding = owner.reserve_workspace("review-r", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&binding, identity.clone())?;
        let observer_owner = binding.clone();
        owner.preserve_workspace_resources("review-r", identity.clone());
        let seal = owner.try_seal_workspace("child-w", identity.clone(), &closing)?;
        seal.durable()?;
        drop(binding); // Forgetting the binding does not join the actual observer owner.
        assert!(owner.ensure_thread_workspace_idle("review-r").is_err());
        assert!(owner.begin_workspace_removal("child-w", &identity).is_err());
        drop(observer_owner);
        owner.ensure_thread_workspace_idle("review-r")?;
        // A real failed cleanup obligation still blocks independently of active runtime tokens.
        assert!(
            owner
                .begin_workspace_removal("child-w", &identity)
                .err()
                .unwrap()
                .to_string()
                .contains("review-r")
        );
        owner.release_workspace_resources("review-r", &identity)?;
        // The physical seal is distinct from the agent execution seal and ends at a reliable
        // terminal result; retained SessionFiles alone must not keep a stopped review active.
        let removal = owner.begin_workspace_removal("child-w", &identity)?;
        assert!(
            owner
                .reserve_workspace("new-preparer", WorkspaceEndpoint::Local)
                .is_err()
        );
        drop(removal);
        drop(seal);
        let rejected = owner.reserve_workspace("late-borrower", WorkspaceEndpoint::Local)?;
        assert!(owner.assign_workspace(&rejected, identity.clone()).is_err());
        drop(rejected);
        let reopened = StudioStore::open(store.paths().database()).await?;
        let frozen = reopened.workspace_identity("child-w").await?.unwrap();
        assert_eq!(frozen, identity);
        assert!(
            reopened
                .bind_workspace_identity(
                    "child-w",
                    &WorkspaceIdentity::canonical(
                        WorkspaceEndpoint::Local,
                        dunce::canonicalize(&root)?.to_string_lossy().into_owned()
                    )?
                )
                .await
                .is_err()
        );
        // Alias and credential spelling do not split one endpoint/path into two physical sites.
        let first = pl_tool::remote::SshServerProfile {
            alias: "one".into(),
            host_name: "host.example".into(),
            port: 22,
            username: "user".into(),
            identity_file: Some("key-one".into()),
        };
        let second = pl_tool::remote::SshServerProfile {
            alias: "two".into(),
            identity_file: Some("key-two".into()),
            ..first.clone()
        };
        let ssh_a = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::from_profile(Some(&first)),
            "/repo/.anywork/worktrees/root-a/remote-w".into(),
        )?;
        let ssh_b = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::from_profile(Some(&second)),
            ssh_a.root.clone(),
        )?;
        let remote_borrower = owner.reserve_workspace("remote-root-b", ssh_b.endpoint.clone())?;
        owner.assign_workspace(&remote_borrower, ssh_b.clone())?;
        assert!(
            owner
                .try_seal_workspace("remote-w", ssh_a.clone(), &BTreeSet::new())
                .err()
                .unwrap()
                .to_string()
                .contains("remote-root-b")
        );
        drop(remote_borrower);
        let pending = owner.try_seal_workspace("remote-w", ssh_a.clone(), &BTreeSet::new())?;
        drop(pending); // Losing the waiting handle cannot adjudicate an unconfirmed product write.
        let late = owner.reserve_workspace("remote-late", ssh_b.endpoint.clone())?;
        assert!(owner.assign_workspace(&late, ssh_b.clone()).is_err());
        // This fixture sent no grant and started no removal, so explicitly release its known seal.
        owner.release_workspace_seal("remote-w", &ssh_a)?;
        owner.assign_workspace(&late, ssh_b)?;
        // Ordinary archive/failed preparation holds a reversible removal, not a permanent seal.
        let independent = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            root.join("independent").to_string_lossy().into_owned(),
        )?;
        let temporary = owner.reserve_workspace("ordinary-preparer", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&temporary, independent.clone())?;
        let still_owned = temporary.clone();
        assert!(
            owner
                .begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))
                .is_err()
        );
        drop(still_owned);
        let cleanup =
            owner.begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))?;
        assert!(
            owner
                .reserve_workspace("during-cleanup", WorkspaceEndpoint::Local)
                .is_err()
        );
        drop(cleanup);
        owner.assign_workspace(&temporary, independent.clone())?;
        let cleanup =
            owner.begin_workspace_cleanup("ordinary-preparer", &independent, Some(&temporary))?;
        cleanup.complete();
        drop(temporary);
        let restored = owner.reserve_workspace("ordinary-restored", WorkspaceEndpoint::Local)?;
        owner.assign_workspace(&restored, independent)?;
        writer.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn cancelled_sink_initialization_releases_its_claim_before_worker_registration()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread("cancelled-sink-initialization");
        register_test_thread(&store, &thread).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let (entered, waiting) = tokio::sync::oneshot::channel();
        let (_release, released) = tokio::sync::oneshot::channel();
        *channel.initialization_gate.lock().unwrap() = Some((entered, released));
        let opening_store = store.clone();
        let opening_thread = thread.clone();
        let opening = tokio::spawn(async move {
            ThreadStorageSink::new(opening_store, opening_thread, None).await
        });
        waiting.await?;
        opening.abort();
        assert!(opening.await.unwrap_err().is_cancelled());
        channel.stop_and_join().await?;
        let replacement = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        assert!(!Arc::ptr_eq(&channel, &replacement.0.channel));
        assert!(Arc::ptr_eq(
            &replacement.0.channel,
            &store.thread_persistence().history_channel(&thread.id)
        ));
        replacement.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_replacement_claim_cannot_lose_its_channel_to_predecessor_release() -> Result<()> {
        for retain_pending in [false, true] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let thread = test_thread("overlapping-channel-release");
            register_test_thread(&store, &thread).await?;
            let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
            let previous_channel = previous.0.channel.clone();
            let write_gate = if retain_pending {
                Some(previous_channel.step_lock.lock().await)
            } else {
                None
            };
            if retain_pending {
                previous.admit(&thread.id, ticket(&thread.id, 1))?;
            }
            let wake = previous.0.changed.clone();
            let (waiting, release) = store.thread_persistence().arm_release_gate();
            let stopped_writer = if retain_pending {
                let writer = previous_channel
                    .workers
                    .lock()
                    .await
                    .pop()
                    .context("registered predecessor writer")?;
                writer.abort();
                Some(writer)
            } else {
                None
            };
            drop(previous);
            wake.notify_one();
            tokio::time::timeout(Duration::from_secs(5), waiting).await??;
            drop(write_gate);
            let replacement = tokio::time::timeout(
                Duration::from_secs(5),
                ThreadStorageSink::new(store.clone(), thread.clone(), None),
            )
            .await;
            release.send(())?;
            if let Some(writer) = stopped_writer {
                assert!(writer.await.unwrap_err().is_cancelled());
            }
            let replacement = replacement??;
            if !retain_pending {
                previous_channel.stop_and_join().await?;
            }
            assert!(
                Arc::ptr_eq(
                    &replacement.0.channel,
                    &store.thread_persistence().history_channel(&thread.id)
                ),
                "predecessor release must not remove the new incarnation's channel"
            );
            assert!(
                replacement.0.channel.subscribe().borrow().fault.is_none(),
                "a predecessor cannot publish WriterUnavailable after its successor initialized"
            );
            spawn_live_projection(&replacement);
            if !retain_pending {
                replacement.admit(&thread.id, ticket(&thread.id, 1))?;
            }
            tokio::time::timeout(Duration::from_secs(5), replacement.flush(&thread.id, 1))
                .await??;
            assert_eq!(store.history(&thread.id).await?.watermark().await?, 1);
            replacement.0.channel.stop_and_join().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_cancelled_replacement_cannot_acknowledge_its_predecessors_pending_facts()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = test_thread("cancelled-queue-adoption");
        register_test_thread(&store, &thread).await?;
        let previous = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = previous.0.channel.clone();
        let write_gate = channel.step_lock.lock().await;
        previous.admit(&thread.id, ticket(&thread.id, 1))?;
        let mut previous_flush = Box::pin(previous.flush(&thread.id, 1));
        assert!(futures::poll!(previous_flush.as_mut()).is_pending());
        let (entered, waiting) = tokio::sync::oneshot::channel();
        let (_release, released) = tokio::sync::oneshot::channel();
        *channel.initialization_gate.lock().unwrap() = Some((entered, released));
        let opening_store = store.clone();
        let opening_thread = thread.clone();
        let opening = tokio::spawn(async move {
            ThreadStorageSink::new(opening_store, opening_thread, None).await
        });
        waiting.await?;
        let writer = channel
            .workers
            .lock()
            .await
            .pop()
            .context("registered writer")?;
        writer.abort();
        assert!(writer.await.unwrap_err().is_cancelled());
        opening.abort();
        assert!(opening.await.unwrap_err().is_cancelled());
        assert!(
            store.thread_persistence().snapshot().pending_commits > 0,
            "an initializer cannot acknowledge queue adoption merely by claiming its identity"
        );
        assert!(store.thread_persistence().wait_for_drain().await.is_err());
        assert_eq!(store.history(&thread.id).await?.watermark().await?, 0);
        assert!(
            matches!(
                futures::poll!(previous_flush.as_mut()),
                std::task::Poll::Ready(Err(_))
            ),
            "the old sink's pending flush must receive the unavailable-writer failure"
        );
        drop(previous_flush);
        let unavailable = channel.subscribe().borrow().clone();
        assert_eq!(
            unavailable.fault,
            Some(pl_protocol::studio::HistoryFault::WriterUnavailable)
        );
        assert!(unavailable.error.is_some());
        assert_eq!(unavailable.committed_sequence, 0);
        assert_eq!(unavailable.queued_records, 1);
        drop(write_gate);
        drop(previous);

        let replacement = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        assert!(Arc::ptr_eq(&channel, &replacement.0.channel));
        spawn_live_projection(&replacement);
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history(&thread.id, unavailable.fault_generation),
        )
        .await??;
        tokio::time::timeout(Duration::from_secs(5), replacement.flush(&thread.id, 1)).await??;
        assert_eq!(store.history(&thread.id).await?.watermark().await?, 1);
        let recovered = channel.subscribe().borrow().clone();
        assert_eq!(recovered.committed_sequence, 1);
        assert_eq!(recovered.queued_records, 0);
        assert!(recovered.fault.is_none());
        assert!(recovered.error.is_none());
        assert_eq!(
            replacement.pressure(&thread.id).recovered_generation,
            Some(unavailable.fault_generation)
        );
        store.thread_persistence().wait_for_drain().await?;
        replacement.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn stopped_writer_joins_survive_cancelled_waiters_and_history_reopens() -> Result<()> {
        let id = "retirement-writer-join";
        let (_temp, store, sink) = sink(id).await?;
        let channel = sink.0.channel.clone();
        let write_gate = channel.step_lock.lock().await;
        sink.admit(id, ticket(id, 1))?;
        assert!(channel.stop_and_join().await.is_err());
        assert!(
            !channel.stopping.is_cancelled(),
            "pending facts must keep their writer"
        );
        drop(write_gate);
        tokio::time::timeout(Duration::from_secs(5), sink.flush(id, 1)).await??;
        let history = store.history(id).await?;
        let saved = history.checkpoint().await?.context("durable checkpoint")?;
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
        channel.stop_and_join().await?;
        assert!(
            sink.admit(id, ticket(id, 2)).is_err(),
            "old sinks cannot resume writing"
        );
        assert_eq!(history.watermark().await?, saved.history_fence);
        let reopened = ThreadStorageSink::new(store.clone(), test_thread(id), Some(&saved)).await?;
        spawn_live_projection(&reopened);
        assert!(!Arc::ptr_eq(&channel, &reopened.0.channel));
        reopened.admit(id, ticket(id, 2))?;
        tokio::time::timeout(Duration::from_secs(5), reopened.flush(id, 2)).await??;
        assert_eq!(history.watermark().await?, 2);
        reopened.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn review_exception_cas_is_atomic_and_budget_survives_writer_replacement() -> Result<()> {
        use crate::thread_assembler::{
            agent_review::{ReviewDeliverySource, ReviewForward, ReviewForwardReason},
            review_delivery::ReviewDeliveryException,
        };
        use pl_core::thread::extensions::ExtensionMutation;
        let id = "review-cas-history";
        let (_temp, store, sink) = sink(id).await?;
        let thread = ThreadHandle::resume_without_model(id.into(), None)?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: "fixture-original-source".into(),
                expected_revision: None,
                payload: OpaquePayload::text("original durable source"),
            }])
            .await?;
        tokio::time::timeout(Duration::from_secs(5), thread.flush()).await??;
        let history = store.history(id).await?;
        let terminal = history.watermark().await?;
        let body_budget = 256 * 1024;
        let retained = store
            .thread_persistence()
            .retain_review_delivery(id, body_budget)?;
        let fact = ReviewDeliveryException::from_forward(
            id,
            "saved-turn",
            None,
            terminal,
            "executor",
            ReviewDeliverySource::Reconciliation,
            &ReviewForward::Unconfirmed {
                message_id: crate::thread_assembler::agent_review::review_message_id(
                    id,
                    "saved-turn",
                    terminal,
                ),
                reason: ReviewForwardReason::RecoveryRequiresScheduling,
            },
        )
        .context("exception fixture")?
        .into_fact()?;
        let path = store
            .session_paths("project-test", id)?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared("CREATE TRIGGER reject_review_cas BEFORE INSERT ON history_fact_receipts WHEN NEW.kind='reviewDeliveryException' BEGIN SELECT RAISE(ABORT,'controlled review CAS failure'); END").await?;
        let mut status = sink.0.channel.subscribe();
        let records = thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: fact.extension_id(),
                expected_revision: None,
                payload: fact.encode()?,
            }])
            .await?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        assert!(
            history
                .review_delivery_exception(&fact.message.id)
                .await?
                .is_none()
        );
        assert_eq!(history.watermark().await?, terminal);
        assert!(
            !history
                .checkpoint()
                .await?
                .unwrap()
                .state
                .extensions
                .contains_key(&fact.extension_id())
        );
        assert!(thread.flush().await.is_err());
        let failed = status.borrow().clone();
        db.execute_unprepared("DROP TRIGGER reject_review_cas")
            .await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history(id, failed.fault_generation),
        )
        .await??;
        tokio::time::timeout(Duration::from_secs(5), thread.flush()).await??;
        assert_eq!(
            history
                .review_delivery_exception(&fact.message.id)
                .await?
                .unwrap()
                .message
                .digest(),
            fact.message.digest()
        );
        assert!(
            history
                .checkpoint()
                .await?
                .unwrap()
                .state
                .extensions
                .contains_key(&fact.extension_id())
        );
        thread
            .mutate_extensions(vec![ExtensionMutation::Delete {
                id: fact.extension_id(),
                expected_revision: records[&fact.extension_id()].revision,
            }])
            .await?;
        thread.close().await?;
        sink.0.channel.stop_and_join().await?;
        let checkpoint = history
            .checkpoint()
            .await?
            .context("closed CAS source checkpoint")?;
        assert!(
            !checkpoint
                .state
                .extensions
                .contains_key(&fact.extension_id())
        );
        let reopened =
            ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
        spawn_live_projection(&reopened);
        assert!(!Arc::ptr_eq(&sink.0.channel, &reopened.0.channel));
        assert!(sink.0.channel.shares_delivery_budget(&reopened.0.channel));
        assert!(reopened.pressure(id).thread_bytes >= body_budget);
        let before = reopened.0.channel.process_bytes.load(Ordering::Acquire);
        assert!(
            store
                .thread_persistence()
                .retain_review_delivery(id, MAX_HISTORY_THREAD_BYTES)
                .is_err()
        );
        assert_eq!(
            reopened.0.channel.process_bytes.load(Ordering::Acquire),
            before
        );
        drop(retained);
        assert!(!reopened.0.channel.has_delivery_bytes());
        let resumed = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
        resumed
            .attach_storage(ColdStoreHandle::new(reopened.clone()))
            .await?;
        resumed.close().await?;
        reopened.0.channel.stop_and_join().await?;
        assert_eq!(
            history
                .review_delivery_exception(&fact.message.id)
                .await?
                .unwrap()
                .message
                .digest(),
            fact.message.digest()
        );
        assert!(
            store
                .thread_persistence()
                .retained_history_channel(id)
                .is_none()
        );
        Ok(())
    }

    #[tokio::test]
    async fn worker_join_failure_remains_a_failure_after_retry() -> Result<()> {
        let (_temp, _store, sink) = sink("retirement-worker-failure").await?;
        let channel = sink.0.channel.clone();
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

    #[tokio::test]
    async fn explicit_close_intent_is_atomic_retryable_and_survives_owner_shutdown() -> Result<()> {
        use pl_core::thread::extensions::ExtensionMutation;
        let id = "close-intent-storage";
        let (_temp, store, sink) = sink(id).await?;
        let thread = ThreadHandle::resume_without_model(id.into(), None)?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        let route = pl_model::config::ModelRouteConfig {
            account_id: pl_model::config::AccountId::new("frozen-account")?,
            model_id: "frozen-model".into(),
            effort: None,
        };
        thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::model_route::encode(&route)?,
            }])
            .await?;
        thread.flush().await?;
        let history = store.history(id).await?;
        let before = history.checkpoint().await?.context("saved baseline")?;
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &store.session_paths("project-test", id)?.history_database(),
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_close_intent BEFORE UPDATE ON session_checkpoint
            BEGIN SELECT RAISE(ABORT, 'controlled close intent rejection'); END",
        )
        .await?;
        let rejected = tokio::time::timeout(
            Duration::from_secs(5),
            crate::studio::agent_close::commit(&thread),
        )
        .await?;
        assert!(
            rejected.is_err(),
            "a rejected checkpoint cannot acknowledge explicit closure"
        );
        let unchanged = history.checkpoint().await?.context("retained checkpoint")?;
        assert_eq!(
            serde_json::to_vec(&unchanged)?,
            serde_json::to_vec(&before)?
        );
        assert_eq!(history.watermark().await?, before.history_fence);
        assert!(!crate::studio::agent_close::is_explicitly_closed(
            &unchanged.state
        )?);
        let generation = sink.0.channel.subscribe().borrow().fault_generation;
        db.execute_unprepared("DROP TRIGGER reject_close_intent")
            .await?;
        store
            .thread_persistence()
            .retry_history(id, generation)
            .await?;
        crate::studio::agent_close::commit(&thread).await?;
        thread.close().await?;
        let saved = history.checkpoint().await?.context("closed checkpoint")?;
        assert_eq!(
            saved.state.lifecycle,
            pl_core::thread::ThreadLifecycle::Closed
        );
        assert!(crate::studio::agent_close::is_explicitly_closed(
            &saved.state
        )?);
        assert_eq!(
            saved.state.extensions[crate::studio::model_route::MODEL_ROUTE_EXTENSION],
            before.state.extensions[crate::studio::model_route::MODEL_ROUTE_EXTENSION]
        );
        assert_eq!(saved.history_fence, history.watermark().await?);
        drop(history);
        let reloaded = crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
            &store,
            &test_thread(id),
        )
        .await?
        .context("reopened canonical checkpoint")?;
        assert!(crate::studio::agent_close::is_explicitly_closed(
            &reloaded.state
        )?);
        assert_eq!(reloaded.history_fence, saved.history_fence);
        assert_eq!(
            reloaded.state.extensions[crate::studio::agent_close::EXTENSION],
            saved.state.extensions[crate::studio::agent_close::EXTENSION]
        );
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn a_reopened_studio_sink_accepts_a_thread_with_durable_history() -> Result<()> {
        let id = "reopened-durable-thread";
        let temp = tempfile::tempdir()?;
        // Native paths remain literal, including URI-looking characters and deep data roots.
        let database = temp
            .path()
            .join("存储 %2F #")
            .join("nested".repeat(16))
            .join("studio/v2/studio.sqlite");
        let store = StudioStore::open(&database).await?;
        let thread = test_thread(id);
        register_test_thread(&store, &thread).await?;
        let original = ThreadStorageSink::new(store.clone(), thread, None).await?;
        spawn_live_projection(&original);
        let write = ticket(id, 1);
        let checkpoint = write.checkpoint.clone();
        original.admit(id, write)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            original.flush(id, 1),
            || channel_facts(&original),
        )
        .await??;
        drop(original);
        drop(store);

        let reopened_store = StudioStore::open(&database).await?;
        assert!(
            ThreadStorageSink::new(reopened_store.clone(), test_thread(id), None,)
                .await
                .is_err(),
            "history ahead of the checkpoint must not silently skip effects"
        );
        let reopened =
            ThreadStorageSink::new(reopened_store, test_thread(id), Some(&checkpoint)).await?;
        spawn_live_projection(&reopened);
        let resumed = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
        resumed
            .attach_storage(ColdStoreHandle::new(reopened.clone()))
            .await?;
        assert_eq!(reopened.pressure(id).durable_sequence, 1);
        await_durable(
            Duration::from_secs(5),
            "reopened durable barrier",
            resumed.flush(),
            || String::from("the reopened owner never reached its durable ticket"),
        )
        .await??;
        resumed.close().await?;
        let saved = reopened
            .0
            .store
            .history(id)
            .await?
            .checkpoint()
            .await?
            .context("owner shutdown checkpoint")?;
        assert_eq!(
            saved.state.lifecycle,
            pl_core::thread::ThreadLifecycle::Closed
        );
        assert!(
            !crate::studio::agent_close::is_explicitly_closed(&saved.state)?,
            "ordinary shutdown must not seal future execution"
        );
        let restored = ThreadHandle::resume_without_model(id.into(), Some(saved))?;
        assert_eq!(
            restored.snapshot().lifecycle,
            pl_core::thread::ThreadLifecycle::Open
        );
        assert!(!crate::studio::agent_close::is_explicitly_closed(
            &restored.snapshot()
        )?);
        restored.close().await?;
        Ok(())
    }

    /// The projection an observation worker would own: empty until the test hands it the admitted
    /// facts, which it folds and hands back to the reliable channel exactly like the production owner.
    async fn live_projection(
        sink: &ThreadStorageSink,
    ) -> Result<crate::studio::thread_projection::LiveProjection> {
        let mut projection = crate::studio::thread_projection::LiveProjection::new();
        projection.bind_execution_history(
            sink.0.channel.order_index(),
            sink.0.store.history(&sink.0.thread.id).await?,
        )?;
        Ok(projection)
    }

    #[test]
    fn execution_index_retires_sources_and_charges_pending_until_real_confirmation() -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = Arc::new(RuntimeOrderIndex::new(process.clone(), 30));
        let observed = index.reserve_observed("attempt-one", "observed")?;
        assert_eq!(observed, 31);
        let reserved_bytes = index.retained_bytes();
        assert!(reserved_bytes > "observed".len() as u64);
        assert_eq!(process.load(Ordering::Acquire), reserved_bytes);
        index.retain(&Default::default(), &Default::default());
        assert_eq!(
            index.retained_bytes(),
            reserved_bytes,
            "an older checkpoint cannot retire a source the projection has not reached"
        );
        index.finish_source("attempt-one");
        index.retain(&Default::default(), &Default::default());
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
        let item = pl_protocol::ThreadItem::new(
            "completed".into(),
            "thread".into(),
            "turn".into(),
            order,
            9,
            10,
            20,
            pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
                Vec::new(),
                "done",
                20,
            )),
        );
        index.materialize(&item, 7)?;
        index.mark_completion("completed", true);
        index.finish_source("attempt-two");
        index.retain(&Default::default(), &Default::default());
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
        assert_eq!(process.load(Ordering::Acquire), 0);
        assert!(!index.is_sealed("completed"));
        assert!(!index.is_terminal("completed"));
        assert_eq!(index.assign("next")?, 33);
        drop(index);
        assert_eq!(process.load(Ordering::Acquire), 0);
        Ok(())
    }

    #[test]
    fn execution_index_budget_rejects_without_allocating_or_rewinding() -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = RuntimeOrderIndex::new(process.clone(), 10);
        index
            .other_thread_bytes
            .store(MAX_HISTORY_THREAD_BYTES, Ordering::Release);
        let rejected = index.reserve_observed("attempt", "rejected").unwrap_err();
        assert!(rejected.is::<ExecutionIndexBudgetFull>());
        assert_eq!(index.assigned("rejected"), None);
        assert_eq!(process.load(Ordering::Acquire), 0);
        index.other_thread_bytes.store(0, Ordering::Release);
        assert_eq!(index.reserve_observed("attempt", "accepted")?, 11);
        index.finish_source("attempt");
        index.retain(&Default::default(), &Default::default());
        assert_eq!(process.load(Ordering::Acquire), 0);
        Ok(())
    }

    #[test]
    fn execution_index_materialize_budget_rejection_leaves_no_partial_identity_or_stamp()
    -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = RuntimeOrderIndex::new(process.clone(), 40);
        let id = "materialize-budget";
        let probe = RuntimeOrderIndex::new(Arc::new(AtomicU64::new(0)), 40);
        probe.assign(id)?;
        let placement_bytes = probe.retained_bytes();
        let item = pl_protocol::ThreadItem::new(
            id.into(),
            "thread".into(),
            "original-turn".into(),
            41,
            9,
            10,
            20,
            pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
                Vec::new(),
                "completed",
                20,
            )),
        );
        // There is room for placement alone, but not its stamp. Both must be funded before
        // insertion; rejecting the stamp must not leave an unowned retained=true entry.
        index.other_thread_bytes.store(
            MAX_HISTORY_THREAD_BYTES - placement_bytes,
            Ordering::Release,
        );
        let error = index.materialize(&item, 7).unwrap_err();
        assert!(error.is::<ExecutionIndexBudgetFull>());
        assert_eq!(index.assigned(id), None);
        assert_eq!(index.inner.lock().unwrap().ceiling, 40);
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(process.load(Ordering::Acquire), 0);

        index.other_thread_bytes.store(0, Ordering::Release);
        index.materialize(&item, 7)?;
        index.retain(&Default::default(), &Default::default());
        let pending = index.pending_placement(id, "thread").unwrap();
        let resident_bytes = index.retained_bytes();
        let mut growing = item.clone();
        growing.turn_id.push_str("-additional-stamp-bytes");
        growing.revision += 1;
        index
            .other_thread_bytes
            .store(MAX_HISTORY_THREAD_BYTES - resident_bytes, Ordering::Release);
        let error = index.materialize(&growing, 8).unwrap_err();
        assert!(error.is::<ExecutionIndexBudgetFull>());
        assert_eq!(index.pending_placement(id, "thread"), Some(pending));
        assert_eq!(index.inner.lock().unwrap().assigned[id].effect, Some(7));
        assert_eq!(index.retained_bytes(), resident_bytes);
        assert_eq!(process.load(Ordering::Acquire), resident_bytes);
        index.confirm_saved(7);
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(process.load(Ordering::Acquire), 0);
        Ok(())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn execution_index_materialize_and_real_save_confirmation_are_atomic() -> Result<()> {
        for materialize_first in [true, false] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let id = if materialize_first {
                "materialize-first"
            } else {
                "confirmation-first"
            };
            register_test_thread(&store, &test_thread(id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
            let lease = sink.0.channel.step_lock.lock().await;
            let chat = store.chat_session(id).await?;
            let mut projection = live_projection(&sink).await?;
            let old_write = visible_input_ticket(id, 1, "racing-identity")?;
            let old_prepared =
                drive_live_projection(&mut projection, &chat, &sink, id, old_write.clone()).await?;
            drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 2)).await?;
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: projection.retained_bytes(),
                    pending: None,
                })?;
            let index = sink.0.channel.order_index();
            {
                let state = index.inner.lock().unwrap();
                let entry = &state.assigned["racing-identity"];
                assert!(!entry.retained);
                assert_eq!(entry.effect, Some(1));
                assert_eq!(state.durable, 0);
            }
            // This is the old placement a later reliable fact captured through live.resolve.
            let old_placement = index.pending_placement("racing-identity", id).unwrap();
            let mut next_item = old_prepared.items[0].clone();
            next_item.ordinal = old_placement.ordinal;
            next_item.created_at = old_placement.created_at;
            next_item.revision = old_placement.revision + 1;
            next_item.updated_at += 1;

            if materialize_first {
                let (entered, materialize_entered) = tokio::sync::oneshot::channel();
                let (release, materialize_release) = std::sync::mpsc::channel();
                *index.materialize_gate.lock().unwrap() = Some(MaterializeGate {
                    entered,
                    release: materialize_release,
                });
                let materializing = tokio::task::spawn_blocking({
                    let index = index.clone();
                    let item = next_item.clone();
                    move || index.materialize(&item, 3)
                });
                tokio::time::timeout(Duration::from_secs(5), materialize_entered).await??;
                assert!(
                    matches!(
                        index.inner.try_lock(),
                        Err(std::sync::TryLockError::WouldBlock)
                    ),
                    "allocation and stamp/effect update must stay in one critical section"
                );
                let (entered, confirmation_entered) = tokio::sync::oneshot::channel();
                *index.confirm_saved_entered.lock().unwrap() = Some(entered);
                let saving = tokio::task::spawn_blocking({
                    let inner = sink.0.clone();
                    let write = old_write.clone();
                    let prepared = old_prepared.clone();
                    move || {
                        tokio::runtime::Handle::current().block_on(persist_effect(
                            &inner,
                            1,
                            &write,
                            &prepared,
                            encoded_bytes(&write.effect),
                        ))
                    }
                });
                tokio::time::timeout(Duration::from_secs(5), confirmation_entered).await??;
                assert_eq!(
                    store.history(id).await?.watermark().await?,
                    1,
                    "the real transaction committed before it tried to reclaim the old identity"
                );
                assert!(
                    !saving.is_finished(),
                    "confirmation must wait for the materialization lock"
                );
                release.send(())?;
                tokio::time::timeout(Duration::from_secs(5), materializing).await???;
                tokio::time::timeout(Duration::from_secs(5), saving).await???;
            } else {
                persist_effect(
                    &sink.0,
                    1,
                    &old_write,
                    &old_prepared,
                    encoded_bytes(&old_write.effect),
                )
                .await?;
                assert_eq!(index.assigned("racing-identity"), None);
                assert_eq!(index.retained_bytes(), 0);
                // Confirmation won the lock before this call. Recreate the captured placement,
                // never allocate a different ordinal for this later reliable fact.
                index.materialize(&next_item, 3)?;
            }
            let pending = index.pending_placement("racing-identity", id).unwrap();
            assert_eq!(pending.ordinal, old_placement.ordinal);
            assert_eq!(pending.revision, next_item.revision);
            assert_eq!(pending.created_at, old_placement.created_at);
            assert_eq!(pending.updated_at, next_item.updated_at);
            assert_eq!(
                index.inner.lock().unwrap().assigned["racing-identity"].effect,
                Some(3)
            );
            // The later fact has also left the live window; only its new unsaved obligation
            // must keep the reconstructed identity resident until the writer reaches it.
            index.retain(&Default::default(), &Default::default());
            assert!(index.pending("racing-identity"));
            assert_eq!(chat.durable_seq(), 1);
            let mut next_write = visible_input_ticket(id, 3, "racing-identity")?;
            let input = Arc::make_mut(&mut next_write.checkpoint.state.inputs)
                .first_mut()
                .unwrap();
            input.accepted_sequence = 1;
            input.ordinal = 1;
            Arc::make_mut(&mut next_write.effect).inputs = Arc::from([InputChange::Transition {
                id: input.input.id.clone(),
                revision: input.revision,
                state: input.state.clone(),
            }]);
            let mut next_prepared = old_prepared.clone();
            next_prepared.sequence = 3;
            next_prepared.accounting = Arc::new(
                crate::studio::thread_projection::PreparedAccounting::prepare(&next_write.effect)?,
            );
            next_prepared.items = vec![next_item.clone()];
            next_prepared.completions = Arc::from([]);
            sink.admit(id, next_write)?;
            assert!(sink.0.channel.prepare(Arc::new(next_prepared)));
            drop(lease);
            tokio::time::timeout(Duration::from_secs(5), sink.flush(id, 3)).await??;
            let history = store.history(id).await?;
            let saved = history.item("racing-identity").await?.unwrap();
            assert_eq!(saved.ordinal, old_placement.ordinal);
            assert_eq!(saved.revision, next_item.revision);
            assert_eq!(saved.created_at, old_placement.created_at);
            assert_eq!(history.watermark().await?, 3);
            assert_eq!(index.retained_bytes(), 0);
            assert_eq!(sink.pressure(id).thread_bytes, 0);
            assert_eq!(sink.0.channel.process_bytes.load(Ordering::Acquire), 0);
            sink.0.channel.stop_and_join().await?;
        }
        Ok(())
    }

    #[test]
    fn execution_index_channel_replacement_carries_only_live_or_pending_obligations() -> Result<()>
    {
        let process = Arc::new(AtomicU64::new(0));
        let (capacity, mut capacity_changes) = tokio::sync::watch::channel(0_u64);
        let channel = HistoryChannel::with_capacity(process.clone(), capacity.clone());
        let producer = channel.order_index();
        assert_eq!(producer.reserve_observed("running", "part")?, 1);
        let replacement = channel.next_storage_channel();
        assert!(Arc::ptr_eq(&producer, &replacement.order_index()));
        assert_eq!(replacement.order_index.assign("next")?, 2);
        let weak = Arc::downgrade(&producer);
        drop(producer);
        drop(channel);
        drop(replacement);
        assert!(
            weak.upgrade().is_none(),
            "no registry may keep the last owner alive"
        );
        assert_eq!(process.load(Ordering::Acquire), 0);
        assert!(capacity_changes.has_changed()?);
        capacity_changes.borrow_and_update();
        let closed = HistoryChannel::new(process.clone());
        let finished_projection = closed.order_index();
        assert_eq!(finished_projection.assign("finished-scope")?, 1);
        let weak = Arc::downgrade(&closed.order_index);
        let reopened = closed.next_storage_channel();
        assert!(!Arc::ptr_eq(&closed.order_index, &reopened.order_index));
        assert_eq!(reopened.order_index.retained_bytes(), 0);
        assert_eq!(reopened.order_index.assign("new-scope")?, 2);
        drop(closed);
        drop(finished_projection);
        assert!(weak.upgrade().is_none());
        drop(reopened);
        assert_eq!(process.load(Ordering::Acquire), 0);
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_many_completed_scopes_return_the_reliable_budget_to_baseline()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "index-bounded";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let mut projection = live_projection(&sink).await?;
        let chat = store.chat_session(id).await?;
        let index = sink.0.channel.order_index();
        for sequence in 1..=20 {
            let mut write = ticket(id, sequence);
            let mut records = Vec::new();
            for part in 0..80 {
                let input =
                    visible_input_ticket(id, sequence, &format!("turn-{sequence}-part-{part}"))?;
                let mut record = input.checkpoint.state.inputs[0].clone();
                record.state = InputState::Consumed {
                    turn_id: format!("turn-{sequence}"),
                    attempt_id: format!("attempt-{sequence}"),
                };
                records.push(record);
            }
            let turn = turn_record(
                &format!("turn-{sequence}"),
                &records[0].input.id,
                TurnState::Finished(TurnOutcome::Completed),
            );
            write.checkpoint.state.turns = Arc::from([turn.clone()]);
            Arc::make_mut(&mut write.effect).turn = Some(turn);
            write.checkpoint.state.inputs = records.clone().into();
            Arc::make_mut(&mut write.effect).inputs = records
                .into_iter()
                .map(InputChange::Accepted)
                .collect::<Vec<_>>()
                .into();
            drive_live_projection(&mut projection, &chat, &sink, id, write).await?;
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: projection.retained_bytes(),
                    pending: None,
                })?;
            sink.flush(id, sequence).await?;
            assert!(index.inner.lock().unwrap().assigned.len() <= 81);
            assert!(index.retained_bytes() < 32 * 1024);
            assert!(sink.pressure(id).thread_bytes < 128 * 1024);
        }
        drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 21)).await?;
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        sink.flush(id, 21).await?;
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(sink.pressure(id).thread_bytes, 0);
        assert_eq!(sink.0.channel.process_bytes.load(Ordering::Acquire), 0);
        assert_eq!(chat.head_seq(), 1620);
        sink.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_late_reliable_input_restores_placement_without_resealing() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "index-late";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let mut accepted = visible_input_ticket(id, 1, "late-input")?;
        let input = Arc::make_mut(&mut accepted.checkpoint.state.inputs)
            .first_mut()
            .unwrap();
        input.state = InputState::Pending;
        Arc::make_mut(&mut accepted.effect).inputs =
            Arc::from([InputChange::Accepted(input.clone())]);
        let first = drive_live_projection(&mut projection, &chat, &sink, id, accepted).await?;
        sink.flush(id, 1).await?;
        let history = store.history(id).await?;
        let original = pl_core::chat::ChatHistory::item(&history, "late-input")
            .await?
            .unwrap();
        assert_eq!(original.turn_id, None);
        let checkpoint = history.checkpoint().await?.unwrap();
        sink.0.channel.stop_and_join().await?;
        drop(projection);
        drop(sink);
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
        let mut projection = live_projection(&sink).await?;
        assert_eq!(sink.0.channel.order_index.retained_bytes(), 0);
        let mut late = visible_input_ticket(id, 2, "late-input")?;
        let input = Arc::make_mut(&mut late.checkpoint.state.inputs)
            .first_mut()
            .unwrap();
        input.state = InputState::Consumed {
            turn_id: "later-turn".into(),
            attempt_id: "later-attempt".into(),
        };
        input.accepted_sequence = 1;
        input.ordinal = 1;
        Arc::make_mut(&mut late.effect).inputs = Arc::from([InputChange::Transition {
            id: input.input.id.clone(),
            revision: input.revision,
            state: input.state.clone(),
        }]);
        let prepared = drive_live_projection(&mut projection, &chat, &sink, id, late).await?;
        assert!(
            prepared.completions.is_empty(),
            "a later execution binding cannot reseal completion"
        );
        assert_eq!(prepared.items[0].ordinal, first.items[0].ordinal);
        assert_eq!(prepared.items[0].created_at, first.items[0].created_at);
        assert!(prepared.items[0].revision > first.items[0].revision);
        sink.flush(id, 2).await?;
        assert_eq!(chat.head_seq(), 1);
        assert_eq!(
            pl_core::chat::ChatHistory::item(&history, "late-input").await?,
            Some(original)
        );
        sink.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_retired_pending_survives_a_rejected_writer_transaction() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "index-failed";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 1)).await?;
        sink.flush(id, 1).await?;
        let lease = sink.0.channel.step_lock.lock().await;
        let write = visible_input_ticket(id, 2, "pending-retired")?;
        let prepared =
            drive_live_projection(&mut projection, &chat, &sink, id, write.clone()).await?;
        drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 3)).await?;
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: projection.retained_bytes(),
                pending: None,
            })?;
        let index = sink.0.channel.order_index();
        assert!(index.pending("pending-retired"));
        let path = store
            .session_paths("project-test", id)?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_index_save BEFORE UPDATE OF applied_write_seq ON history_meta
             BEGIN SELECT RAISE(ABORT, 'controlled index save rejection'); END",
        )
        .await?;
        assert!(
            persist_effect(&sink.0, 2, &write, &prepared, encoded_bytes(&write.effect))
                .await
                .is_err()
        );
        let charged = index.retained_bytes();
        assert!(charged > 0);
        assert_eq!(chat.durable_seq(), 0);
        assert_eq!(sink.0.channel.subscribe().borrow().queued_records, 2);
        assert!(sink.pressure(id).thread_bytes >= charged);
        assert!(index.pending("pending-retired"));
        assert!(index.is_sealed("pending-retired"));
        db.execute_unprepared("DROP TRIGGER reject_index_save")
            .await?;
        persist_effect(&sink.0, 2, &write, &prepared, encoded_bytes(&write.effect)).await?;
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(chat.durable_seq(), 1);
        drop(lease);
        sink.flush(id, 3).await?;
        assert_eq!(sink.pressure(id).thread_bytes, 0);
        sink.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_writer_replacement_and_cold_reopen_preserve_the_right_ceiling()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let database = temp.path().join("studio/v2/studio.sqlite");
        let id = "index-reopened";
        let store = StudioStore::open(&database).await?;
        register_test_thread(&store, &test_thread(id)).await?;
        let original = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let mut projection = live_projection(&original).await?;
        let chat = store.chat_session(id).await?;
        let first = drive_live_projection(
            &mut projection,
            &chat,
            &original,
            id,
            visible_input_ticket(id, 1, "durable-execution")?,
        )
        .await?;
        original.flush(id, 1).await?;
        let checkpoint = store.history(id).await?.checkpoint().await?.unwrap();
        let index = original.0.channel.order_index();
        let weak = Arc::downgrade(&index);
        let reserved = index.reserve_observed("still-running", "unmaterialized-part")?;
        assert!(reserved > first.items[0].ordinal);
        let replacement =
            ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
        assert!(Arc::ptr_eq(&index, &replacement.0.channel.order_index()));
        assert_eq!(
            replacement
                .0
                .channel
                .order_index
                .assign("replacement-next")?,
            reserved + 1
        );
        replacement.0.channel.stop_and_join().await?;
        drop(projection);
        drop(index);
        drop(first);
        drop(original);
        drop(replacement);
        drop(chat);
        drop(store);
        assert!(
            weak.upgrade().is_none(),
            "closed owners cannot leave a process registry behind"
        );
        let reopened_store = StudioStore::open(&database).await?;
        let reopened =
            ThreadStorageSink::new(reopened_store, test_thread(id), Some(&checkpoint)).await?;
        let reopened_index = reopened.0.channel.order_index();
        assert_eq!(reopened_index.retained_bytes(), 0);
        assert_eq!(
            reopened_index.assign("cold-next")?,
            2,
            "cold reopen derives its ceiling from durable execution rows, not abandoned reservations"
        );
        reopened.0.channel.stop_and_join().await?;
        Ok(())
    }

    /// Takes the admitted facts over exactly as the Thread's live projection owner does.
    ///
    /// The Studio runtime installs that owner during Thread assembly, and the history writer refuses
    /// to save a fact no projection holds. These tests exercise the writer on its own, so they drive
    /// the same production projection against the same reliable admission channel: one projection per
    /// commit, published shape unchanged, only the caller differs.
    pub(crate) fn spawn_live_projection(sink: &ThreadStorageSink) {
        drop(spawn_projection(
            sink.0.store.clone(),
            sink.0.thread.clone(),
        ));
    }

    /// Drives the real projection for an assembler-installed sink without downcasting its erased
    /// ColdStoreHandle or retaining that writer incarnation after its core/observer have ended.
    pub(crate) fn spawn_live_projection_for_thread(
        store: StudioStore,
        id: &str,
    ) -> tokio::task::JoinHandle<()> {
        let thread = store
            .catalog()
            .get(id)
            .expect("registered projection Thread")
            .to_thread();
        spawn_projection(store, thread)
    }

    fn spawn_projection(
        store: StudioStore,
        thread: pl_protocol::Thread,
    ) -> tokio::task::JoinHandle<()> {
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store
            .thread_persistence()
            .chat_session(&thread.id)
            .expect("initialized writer Session");
        tokio::spawn(async move {
            let mut projection = crate::studio::thread_projection::LiveProjection::new();
            projection
                .bind_execution_history(
                    channel.order_index(),
                    store
                        .history(&thread.id)
                        .await
                        .expect("initialized execution history"),
                )
                .expect("one projection binding");
            let mut failed = std::collections::BTreeSet::new();
            // Wake on the channel's own status watch, never on the channel's `Notify`: the history
            // writer is the one task that waits on that `Notify`, and a second waiter would consume
            // the single wakeup permit a recovery notification hands out.
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
                    // A reliable-output repair can name an identity this bounded window released; the
                    // production observation owner reads that committed body back and folds it in, so
                    // the harness drives the same step instead of skipping a fact the writer must save.
                    if !write.effect.delivery_repairs.is_empty() {
                        let seeded = match store.history(&thread.id).await {
                            Ok(history) => crate::studio::thread_projection::seed_repaired_targets(
                                &mut projection,
                                &history,
                                &write.effect,
                            )
                            .await
                            .map_err(|error| error.to_string()),
                            Err(error) => Err(error.to_string()),
                        };
                        if let Err(error) = seeded {
                            failed.insert(sequence);
                            channel.fail_projection(sequence, error);
                            continue;
                        }
                    }
                    let published = async {
                        let mut prepared = projection
                            .prepare_committed(&thread, &write.effect, &write.checkpoint.state)
                            .await?;
                        projection.publish_prepared(&chat, &mut prepared).await?;
                        Ok::<_, crate::studio::thread_projection::ProjectionError>(prepared)
                    }
                    .await;
                    match published {
                        Ok(prepared) => {
                            channel.prepare(prepared);
                        }
                        // The writer never projects, so failing here is what the running Studio sees
                        // from its observation worker: the fact is reported and the barrier fails
                        // closed with the projection's own reason.
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

    /// Save the original terminal report in the same real effect/checkpoint transaction as Studio.
    /// No parent owner is needed; recovery must later prove its independently missing receipt.
    pub(crate) async fn save_terminal_report(
        store: &StudioStore,
        thread: &pl_protocol::Thread,
        message: pl_core::thread::inbox::ThreadMessage,
    ) -> Result<()> {
        let checkpoint = store.history(&thread.id).await?.checkpoint().await?;
        let sink =
            ThreadStorageSink::new(store.clone(), thread.clone(), checkpoint.as_ref()).await?;
        let sequence = checkpoint
            .as_ref()
            .map_or(1, |checkpoint| checkpoint.history_fence + 1);
        let mut terminal = ticket(&thread.id, sequence);
        if let Some(checkpoint) = checkpoint {
            terminal.checkpoint.state = checkpoint.state;
            terminal.checkpoint.state.commit_sequence = sequence;
        }
        let turn = TurnRecord {
            turn_id: "original-terminal-turn".into(),
            input_id: None,
            state: TurnState::Finished(TurnOutcome::Completed),
            model_steps: 0,
            elapsed_ms: None,
        };
        terminal.checkpoint.state.lifecycle = pl_core::thread::ThreadLifecycle::Closed;
        terminal.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut terminal.effect).turn = Some(turn);
        let mut projection = live_projection(&sink).await?;
        let mut prepared = projection
            .prepare_committed(thread, &terminal.effect, &terminal.checkpoint.state)
            .await?;
        projection
            .publish_prepared(&sink.0.chat, &mut prepared)
            .await?;
        Arc::get_mut(&mut prepared)
            .context("new prepared effect unexpectedly shared")?
            .parent_report = Some(Arc::new(message));
        sink.admit(&thread.id, terminal)?;
        sink.0.channel.prepare(prepared);
        sink.flush(&thread.id, sequence).await?;
        sink.0.channel.stop_and_join().await
    }

    /// One ticket whose effect commits a visible prompt item, i.e. the shortest effect that projects
    /// a durable body the writer must confirm.
    fn visible_input_ticket(thread_id: &str, sequence: u64, input_id: &str) -> Result<ThreadWrite> {
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
                    serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
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

    /// A commit the Thread's projection owner has not handed over is never written.
    ///
    /// This is what makes "the owner released this effect from its window" imply "the projection
    /// published it": the durable watermark cannot move past a fact no projection took over, so a
    /// released commit is always one the product already has. The sink below is built without the
    /// test projection, so nothing takes the fact over until the test hands it in itself.
    #[tokio::test]
    async fn a_commit_without_a_projection_handoff_is_never_saved() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("no-handoff")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("no-handoff"), None).await?;
        let calls_before = store.calls().metrics();
        let materials_before = store.calls().subscribe_materials().borrow().clone();
        let write = ticket("no-handoff", 1);
        sink.admit("no-handoff", write.clone())?;
        assert!(
            tokio::time::timeout(Duration::from_millis(200), sink.flush("no-handoff", 1))
                .await
                .is_err(),
            "an unprojected commit must not reach a durable barrier"
        );
        let unprojected = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(unprojected.committed_sequence, 0);
        assert_eq!(unprojected.queued_records, 1);
        assert_eq!(store.history("no-handoff").await?.watermark().await?, 0);

        let chat = store.chat_session("no-handoff").await?;
        let mut projection = live_projection(&sink).await?;
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        sink.0.channel.prepare(prepared);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("no-handoff", 1),
            || channel_facts(&sink),
        )
        .await??;
        assert_eq!(store.history("no-handoff").await?.watermark().await?, 1);
        assert_eq!(store.calls().metrics(), calls_before);
        assert_eq!(
            *store.calls().subscribe_materials().borrow(),
            materials_before
        );
        Ok(())
    }

    #[tokio::test]
    async fn hidden_consumed_input_keeps_turn_history_complete_after_body_pruning() -> Result<()> {
        let (_temp, store, sink) = sink("hidden-input").await?;
        let input_id = "interaction:confirmed:continuation";
        let turn_id = "turn-after-confirmation";
        let mut accepted = ticket("hidden-input", 1);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: input_id.into(),
                payload: OpaquePayload::new(
                    "pl.studio.interaction-continuation",
                    1,
                    serde_json::json!({"interactionId":"confirmed","presentation":"hidden"})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "answer".into(),
                }],
            },
            ordinal: 1,
            revision: 2,
            state: InputState::Consumed {
                turn_id: turn_id.into(),
                attempt_id: "attempt-1".into(),
            },
        };
        accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        sink.admit("hidden-input", accepted)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("hidden-input", 1),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history("hidden-input").await?;
        assert!(history.existing_items([input_id.into()]).await?.is_empty());
        assert!(history.input_identity(input_id).await?.is_some());

        let mut later = ticket("hidden-input", 2);
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: Some(input_id.into()),
            turn_id: turn_id.into(),
            state: TurnState::Running,
            model_steps: 0,
        };
        later.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut later.effect).turn = Some(turn);
        sink.admit("hidden-input", later)?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 2),
            sink.flush("hidden-input", 2),
            || channel_facts(&sink),
        )
        .await??;
        assert_eq!(history.watermark().await?, 2);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn missing_visible_input_item_still_blocks_history() -> Result<()> {
        // A Thread re-activated after its durable timeline lost a visible input body. The projection
        // that installs now has never folded that input — it is a fresh owner, exactly like a Thread
        // whose earlier incarnation committed the input — so the effect that still references it must
        // fail closed instead of committing a timeline with a hole.
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("missing-visible")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("missing-visible"), None).await?;
        let mut accepted = ticket("missing-visible", 1);
        let input = InputRecord {
            continuation: None,
            accepted_sequence: 1,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: "visible-input".into(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "hello".into(),
                }],
            },
            ordinal: 1,
            revision: 2,
            state: InputState::Consumed {
                turn_id: "visible-turn".into(),
                attempt_id: "attempt".into(),
            },
        };
        accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut accepted.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        // The incarnation that committed the input projects and hands it over normally.
        let chat = store.chat_session("missing-visible").await?;
        sink.admit("missing-visible", accepted.clone())?;
        let mut owner = live_projection(&sink).await?;
        let mut prepared = owner
            .prepare_committed(&sink.0.thread, &accepted.effect, &accepted.checkpoint.state)
            .await?;
        owner.publish_prepared(&chat, &mut prepared).await?;
        sink.0.channel.prepare(prepared);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("missing-visible", 1),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history("missing-visible").await?;
        let path = store
            .session_paths("project-test", "missing-visible")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared("DELETE FROM history_items WHERE item_id='visible-input'")
            .await?;

        // The owner this Thread gets on re-activation never folded the input, and the durable row
        // the projection would resolve it from is gone.
        spawn_live_projection(&sink);
        let mut later = ticket("missing-visible", 2);
        let turn = TurnRecord {
            elapsed_ms: None,
            input_id: Some("visible-input".into()),
            turn_id: "visible-turn".into(),
            state: TurnState::Running,
            model_steps: 0,
        };
        later.checkpoint.state.turns = Arc::from([turn.clone()]);
        Arc::make_mut(&mut later.effect).turn = Some(turn);
        sink.admit("missing-visible", later)?;
        let error = await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 2),
            sink.flush("missing-visible", 2),
            || channel_facts(&sink),
        )
        .await
        .context("a torn projection must fail the durable barrier instead of hanging")?
        .expect_err("a visible input without its item must fail closed");
        assert!(
            error
                .to_string()
                .contains("missing the committed input item")
        );
        assert_eq!(history.watermark().await?, 1);
        Ok(())
    }

    #[tokio::test]
    async fn unconsumed_input_survives_failed_preparation_and_a_new_turn() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "unconsumed-retry";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let mut input = consumed_visible_input("pending-input", "second-turn", 1)?;
        input.state = InputState::Pending;
        let mut accepted = ticket(id, 1);
        accepted.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut accepted.effect).inputs =
            Arc::from([InputChange::Accepted(input.clone())]);
        drive_live_projection(&mut projection, &chat, &sink, id, accepted).await?;
        // Both runs publish a Turn before model preparation consumes anything. The first one
        // failed preparation, so the same pending identity legitimately enters the second run.
        for (sequence, turn_id, turn_state) in [
            (2, "first-turn", TurnState::Running),
            (
                3,
                "first-turn",
                TurnState::Failed {
                    description: "model preparation rejected media".into(),
                    model_failure: None,
                },
            ),
            (4, "second-turn", TurnState::Running),
        ] {
            let mut turn = turn_record(turn_id, "pending-input", turn_state);
            if sequence == 3 {
                turn.elapsed_ms = Some(1);
            }
            let mut write = ticket(id, sequence);
            write.checkpoint.state.inputs = Arc::from([input.clone()]);
            write.checkpoint.state.turns = Arc::from([turn.clone()]);
            Arc::make_mut(&mut write.effect).turn = Some(turn);
            drive_live_projection(&mut projection, &chat, &sink, id, write).await?;
            await_durable(
                Duration::from_secs(5),
                &format!("commit {}", sequence),
                sink.flush(id, sequence),
                || channel_facts(&sink),
            )
            .await??;
            let saved = store
                .history(id)
                .await?
                .existing_items(["pending-input".into()])
                .await?;
            assert!(saved["pending-input"].turn_id.is_empty());
        }
        input.state = InputState::Consumed {
            turn_id: "second-turn".into(),
            attempt_id: "attempt".into(),
        };
        input.revision += 1;
        let mut consumed = ticket(id, 5);
        consumed.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut consumed.effect).inputs = Arc::from([InputChange::Transition {
            id: input.input.id.clone(),
            revision: input.revision,
            state: input.state.clone(),
        }]);
        drive_live_projection(&mut projection, &chat, &sink, id, consumed).await?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 5),
            sink.flush(id, 5),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history(id).await?;
        let saved = history.existing_items(["pending-input".into()]).await?;
        assert_eq!(saved["pending-input"].turn_id, "second-turn");
        assert_eq!(history.watermark().await?, 5);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    /// One visible, already-consumed input record owned by `turn_id`.
    ///
    /// This is exactly what core's consuming commit leaves behind: the input is `Consumed`, so it has
    /// a visible timeline item whose `turn_id` is the Turn it opened.
    fn consumed_visible_input(id: &str, turn_id: &str, sequence: u64) -> Result<InputRecord> {
        Ok(InputRecord {
            continuation: None,
            accepted_sequence: sequence,
            delivery: Default::default(),
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: id.to_owned(),
                payload: OpaquePayload::new(
                    "pl.studio.prompt",
                    1,
                    serde_json::json!({"text":"hello","presentation":"visible","attachments":[]})
                        .to_string(),
                )?,
                context: vec![ContextContent::Text {
                    text: "hello".into(),
                }],
            },
            ordinal: sequence,
            revision: sequence,
            state: InputState::Consumed {
                turn_id: turn_id.to_owned(),
                attempt_id: "attempt".to_owned(),
            },
        })
    }

    /// One Turn record naming `input_id` as the input that opened it.
    fn turn_record(turn_id: &str, input_id: &str, state: TurnState) -> TurnRecord {
        TurnRecord {
            elapsed_ms: None,
            input_id: Some(input_id.to_owned()),
            turn_id: turn_id.to_owned(),
            state,
            model_steps: 0,
        }
    }

    /// One provider output item with a single text part, as a model receipt reports it.
    ///
    /// The multi-item stress response is exactly a long list of these: one stable identity per
    /// provider item, all delivered inside one model step.
    fn provider_presentation_part(
        index: usize,
    ) -> pl_model::completion::CompletionPresentationItem {
        use pl_model::completion::{
            CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
            CompletionPresentationPartKind,
        };
        CompletionPresentationItem {
            provider_item_id: format!("stress-item-{index}"),
            output_index: Some(index as u32),
            kind: CompletionPresentationItemKind::Text(pl_protocol::trace::TraceTextChannel::Final),
            parts: vec![CompletionPresentationPart {
                content_index: 0,
                provider_part_id: Some(format!("stress-part-{index}")),
                kind: CompletionPresentationPartKind::OutputText,
                text: format!("chunk-{index}"),
            }],
        }
    }

    /// The snapshot attempt and the matching effect update for one committed step of `parts` parts.
    ///
    /// The receipt is the model crate's own `pl.model.assistant` frame — the same payload a real
    /// adapter writes — so the projection itemizes it through its public receipt reader instead of a
    /// test-only shape.
    fn committed_parts_attempt(
        turn_id: &str,
        attempt_id: &str,
        parts: usize,
    ) -> Result<(
        pl_core::thread::RequestAttempt,
        pl_core::thread::journal::AttemptUpdate,
    )> {
        committed_presentation_attempt(
            turn_id,
            attempt_id,
            (0..parts).map(provider_presentation_part).collect(),
        )
    }

    fn committed_presentation_attempt(
        turn_id: &str,
        attempt_id: &str,
        presentation_items: Vec<pl_model::completion::CompletionPresentationItem>,
    ) -> Result<(
        pl_core::thread::RequestAttempt,
        pl_core::thread::journal::AttemptUpdate,
    )> {
        let receipt = pl_model::runtime::ModelResponseReceipt {
            binding: pl_model::runtime::ModelCallBinding {
                account_id: "fixture".into(),
                model_id: "fixture-model".into(),
                protocol: pl_model::protocol::ProtocolKind::OpenAiCompatible,
                wire_api: pl_model::protocol::WireApi::ChatCompletions,
                isolation: "test".into(),
                purpose: "test".into(),
                context_window: None,
                max_context_window: None,
                auto_compact_limit: None,
            },
            response: pl_model::completion::CompletionResponse {
                replay: None,
                response_id: None,
                content: None,
                reasoning_content: None,
                tool_calls: Vec::new(),
                responses_context_items: Vec::new(),
                presentation_items,
                orchestration: Default::default(),
                timing: None,
                accounting: Default::default(),
                model: "fixture-model".into(),
                model_observation: None,
                observation: Default::default(),
            },
        };
        // The durable assistant frame is exactly this pair of receipt and tool bindings.
        #[derive(serde::Serialize)]
        #[serde(rename_all = "camelCase")]
        struct Frame<'a> {
            receipt: &'a pl_model::runtime::ModelResponseReceipt,
            bindings: Vec<ModelToolCall>,
        }
        let frame = OpaquePayload::new(
            "pl.model.assistant",
            // 与 pl-model 当前 `pl.model.assistant` 帧版本一致（该常量不对外重导出）。
            5,
            serde_json::to_string(&Frame {
                receipt: &receipt,
                bindings: Vec::new(),
            })?,
        )?;
        let output = ModelStepOutput {
            attempt_id: attempt_id.to_owned(),
            base_context_revision: 0,
            content: vec![ContextContent::Opaque { payload: frame }],
            tool_calls: Vec::new(),
            private_context: None,
            usage: Default::default(),
        };
        let tools: Arc<[pl_core::model::ModelToolDeclaration]> =
            Arc::from(Vec::<pl_core::model::ModelToolDeclaration>::new());
        let attempt = pl_core::thread::RequestAttempt::new(
            turn_id.to_owned(),
            attempt_id.to_owned(),
            0,
            pl_core::thread::AttemptStatus::Committed,
        );
        let update = pl_core::thread::journal::AttemptUpdate {
            request_metadata: None,
            usage_binding: None,
            tool_projection: None,
            turn_id: turn_id.to_owned(),
            attempt_id: attempt_id.to_owned(),
            retry_of: None,
            input_revision: 0,
            tools,
            outcome: pl_core::thread::AttemptOutcome::Committed(output),
            input_estimate: None,
        };
        Ok((attempt, update))
    }

    /// Hands one admitted fact to the production live projection and to the writer, exactly as the
    /// Thread's observation worker does: admit, take the owed fact over, project it, hand the batch
    /// back. The writer saves only what this owner handed over, so a `flush` afterwards is the same
    /// durable barrier the product uses.
    async fn drive_live_projection(
        projection: &mut crate::studio::thread_projection::LiveProjection,
        chat: &pl_core::chat::Session,
        sink: &ThreadStorageSink,
        thread_id: &str,
        write: ThreadWrite,
    ) -> Result<crate::studio::thread_projection::PreparedEffect> {
        sink.admit(thread_id, write)?;
        let write = sink
            .0
            .channel
            .next_unprojected()
            .context("the admitted fact is owed a projection")?;
        let (_, mut prepared) = projection
            .prepare(&sink.0.thread, &write.effect, &write.checkpoint.state, true)
            .await?;
        assert!(prepared.completion_drafts.is_some());
        assert!(!sink.0.channel.prepare(prepared.clone()));
        projection.publish_prepared(chat, &mut prepared).await?;
        assert!(prepared.completion_drafts.is_none());
        assert!(sink.0.channel.prepare(prepared.clone()));
        Ok((*prepared).clone())
    }

    /// A delayed Running acknowledgement must not retire provider observations published after
    /// its batch was prepared. The writer step lock fixes the interleaving without timing sleeps.
    #[tokio::test]
    async fn running_save_ack_preserves_later_failed_and_current_observations() -> Result<()> {
        use pl_core::{
            chat::{PresentationPart, presentation_item_id},
            model::{
                ActiveModelProgress, ModelProgressSender, ModelTextChannel, ObservedItemKind,
                ObservedPart, ObservedPartIdentity, ObservedPartKind, ProviderPartIdentity,
            },
            thread::{AttemptOutcome, AttemptStatus},
        };

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "running-save-ack";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let (mut attempt, mut update) = committed_parts_attempt("turn", "attempt", 0)?;
        attempt.status = AttemptStatus::Running;
        update.outcome = AttemptOutcome::Running;
        let mut write = ticket(id, 1);
        write.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut write.effect).attempt = Some(update);
        let mut state = write.checkpoint.state.clone();

        let locked = sink.0.channel.step_lock.lock().await;
        drive_live_projection(&mut projection, &chat, &sink, id, write).await?;
        let sender = ModelProgressSender::detached(1024);
        let part = |text: &str| {
            ObservedPart::new(ObservedPartIdentity::Provider(ProviderPartIdentity {
                item_id: Arc::from("same-provider-id"),
                output_index: Some(0),
                item_kind: ObservedItemKind::Text(ModelTextChannel::Final),
                part: ObservedPartKind::OutputText,
                content_index: 0,
            }))
            .authorized(text)
        };
        sender.edit_parts(|parts| parts.push(part("failed body")));
        sender.begin_recovery(5, Arc::from("connection interrupted"))?;
        sender.edit_parts(|parts| parts.push(part("current body")));
        state.model_progress = Some(ActiveModelProgress {
            attempt_id: "attempt".into(),
            progress: sender.latest(),
        });
        projection.stream(&chat, &sink.0.thread, &state, 1).await?;
        let failed_id = presentation_item_id(
            "attempt",
            0,
            "same-provider-id",
            Some(PresentationPart::OutputText(0)),
        );
        let current_id = presentation_item_id(
            "attempt",
            1,
            "same-provider-id",
            Some(PresentationPart::OutputText(0)),
        );
        // The two observations are facts of this Runtime projection owner now: the completion
        // session never saw them, and their bodies stay the shared blocks `stream` stored.
        let failed_body = preview_body(&projection, &failed_id);
        let current_body = preview_body(&projection, &current_id);
        drop(locked);
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush(id, 1),
            || channel_facts(&sink),
        )
        .await??;

        // No further provider update is needed to keep either identity live after the save ack:
        // the delayed Running write owns neither observation, so both previews remain this owner's
        // resident facts with their bodies unchanged.
        assert_eq!(
            preview_body(&projection, &failed_id),
            failed_body,
            "the delayed Running acknowledgement must not retire the failed observation"
        );
        assert_eq!(
            preview_body(&projection, &current_id),
            current_body,
            "the delayed Running acknowledgement must not retire the current observation"
        );
        assert!(
            store
                .history(id)
                .await?
                .existing_items([failed_id.clone(), current_id.clone()])
                .await?
                .is_empty(),
            "Running saved only its prepared start facts, not these later observations"
        );
        let mut stale = state.clone();
        stale.model_progress.as_mut().unwrap().attempt_id = "retired-before-current".into();
        projection.stream(&chat, &sink.0.thread, &stale, 1).await?;
        assert_eq!(
            preview_body(&projection, &current_id),
            current_body,
            "an unrelated retired source cannot erase the current source's preview"
        );
        Arc::make_mut(&mut state.attempts)[0].status = AttemptStatus::Cancelled;
        projection.stream(&chat, &sink.0.thread, &state, 1).await?;
        assert!(projection.preview_fields(&failed_id).is_none());
        assert!(projection.preview_fields(&current_id).is_none());
        projection.stream(&chat, &sink.0.thread, &state, 1).await?;
        assert!(
            projection.preview_fields(&current_id).is_none(),
            "a delayed frame from an ended attempt cannot recreate its preview"
        );
        Ok(())
    }

    /// The body text one preview currently holds, straight from the projection's shared blocks.
    fn preview_body(
        projection: &crate::studio::thread_projection::LiveProjection,
        id: &str,
    ) -> String {
        let fields = projection
            .preview_fields(id)
            .expect("the observation stays a resident preview of this owner");
        fields
            .values()
            .map(|block| block.text())
            .collect::<Vec<_>>()
            .join("")
    }

    #[tokio::test]
    async fn parent_message_keeps_identity_until_consumed_and_saved() -> Result<()> {
        use pl_core::thread::inbox::{InboxRecord, ThreadMessage};

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "child-message";
        let mut thread = test_thread(id);
        thread.parent_thread_id = Some("parent".into());
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread, None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let record = InboxRecord {
            sequence: 1,
            message: ThreadMessage {
                kind: pl_core::context::AgentMessageKind::Report,
                id: "initial:spawn".into(),
                source_id: "agent:parent".into(),
                payload: OpaquePayload::text("implement the assigned task"),
                context: Vec::new(),
            },
        };
        let item_id = crate::studio::thread_projection::order::message_id(&record.message.id);
        let mut accepted = ticket(id, 1);
        accepted.checkpoint.state.inbox = Arc::from([record.clone()]);
        Arc::make_mut(&mut accepted.effect).inbox = Arc::from([record.clone()]);
        let accepted_batch =
            drive_live_projection(&mut projection, &chat, &sink, id, accepted.clone()).await?;
        let original = accepted_batch
            .items
            .iter()
            .find(|item| item.id == item_id)
            .context("accepted parent message")?
            .clone();
        // Re-observation before consumption must not invent a new content version.
        let (_, mut repeat) = projection
            .prepare(
                &sink.0.thread,
                &accepted.effect,
                &accepted.checkpoint.state,
                true,
            )
            .await?;
        projection.publish_prepared(&chat, &mut repeat).await?;
        assert_eq!(
            repeat
                .items
                .iter()
                .find(|item| item.id == item_id)
                .context("the re-observation still projects the identity")?
                .revision,
            original.revision
        );

        let (attempt, update) = committed_parts_attempt("child-turn", "child-attempt", 1)?;
        let mut consumed = ticket(id, 2);
        consumed.checkpoint.state.consumed_messages = 1;
        consumed.checkpoint.state.inbox = Arc::from([record]);
        consumed.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut consumed.effect).attempt = Some(update);
        Arc::make_mut(&mut consumed.effect).consumed_messages = Some(1);
        drive_live_projection(&mut projection, &chat, &sink, id, consumed).await?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 2),
            sink.flush(id, 2),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history(id).await?;
        let saved = history.existing_items([item_id.clone()]).await?;
        let item = saved.get(&item_id).context("saved parent message")?;
        assert_eq!(item.ordinal, original.ordinal);
        assert_eq!(item.turn_id, "child-turn");
        assert!(item.revision > original.revision);
        assert!(
            matches!(item.state(), pl_protocol::ThreadItemState::Text(text)
            if text.channel() == pl_protocol::ThreadTextChannel::ParentAgent
                && text.text() == "implement the assigned task")
        );
        assert_eq!(history.watermark().await?, 2);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);

        // A saved but unconsumed follow-up has no Turn. Reinstall the projection from its
        // durable identity before consuming it, as activation does for an idle child.
        let mut followup = ticket(id, 3);
        followup.checkpoint.state.consumed_messages = 1;
        let mut record = accepted.checkpoint.state.inbox[0].clone();
        record.sequence = 2;
        record.message.id = "followup".into();
        followup.checkpoint.state.inbox = Arc::from([record.clone()]);
        Arc::make_mut(&mut followup.effect).inbox = Arc::from([record.clone()]);
        drive_live_projection(&mut projection, &chat, &sink, id, followup).await?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 3),
            sink.flush(id, 3),
            || channel_facts(&sink),
        )
        .await??;
        let followup_id = crate::studio::thread_projection::order::message_id(&record.message.id);
        let saved = history.existing_items([followup_id.clone()]).await?;
        let original = saved[&followup_id].clone();
        projection = live_projection(&sink).await?;
        projection.seed(saved.into_values().collect(), Default::default());
        let (attempt, update) = committed_parts_attempt("next-turn", "next-attempt", 1)?;
        let mut consumed = ticket(id, 4);
        consumed.checkpoint.state.consumed_messages = 2;
        consumed.checkpoint.state.inbox = Arc::from([record]);
        consumed.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut consumed.effect).attempt = Some(update);
        Arc::make_mut(&mut consumed.effect).consumed_messages = Some(2);
        drive_live_projection(&mut projection, &chat, &sink, id, consumed).await?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 4),
            sink.flush(id, 4),
            || channel_facts(&sink),
        )
        .await??;
        let saved = history.existing_items([followup_id.clone()]).await?;
        assert_eq!(saved[&followup_id].ordinal, original.ordinal);
        assert_eq!(saved[&followup_id].turn_id, "next-turn");
        assert!(saved[&followup_id].revision > original.revision);
        assert_eq!(history.watermark().await?, 4);
        Ok(())
    }

    /// A live Turn survives a retained window smaller than the response it produced.
    ///
    /// The live projection is a bounded observation owner: it releases a Turn's oldest facts by
    /// ordinal once that Turn commits more identities than `LIVE_ITEM_WINDOW`. A Turn's own input is
    /// the identity core keeps referencing from *every* later effect of that Turn — above all its
    /// terminal one, whose checkpoint has already pruned the consumed body and carries only the
    /// minimal `turns[].input_id` — while it is also the oldest fact the Turn ever created. Numbering
    /// the window purely by ordinal therefore evicted exactly that identity, the terminal effect then
    /// resolved the pruned input as a hole and the durable barrier failed closed with
    /// `MissingDurableInput`: the multi-item stress fault. The window must bound only *optional*
    /// retained history; the minimal identity a live Turn still references is not optional.
    ///
    /// Keeping an identity without keeping its content version is not enough: the Turn's own item is
    /// re-projected by the same later effects, so a window that released it made the re-projection
    /// restart at revision 1, and the durable row rejected the new payload as a revision conflict.
    /// Identity and version have to survive together.
    ///
    /// This drives the production `advance` path over the same reliable handoff the observation
    /// worker uses, with no GUI subscriber: the projection publishes into the shared session and
    /// hands the batch to the writer exactly like the owner. The pressure is a real provider receipt
    /// with more presentation parts than the window holds, not a fabricated per-Turn input queue.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn execution_index_delivery_admission_releases_registry_before_channel_accounting()
    -> Result<()> {
        for cold in [false, true] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let id = if cold {
                "cold-pin-lock-order"
            } else {
                "review-pin-lock-order"
            };
            register_test_thread(&store, &test_thread(id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
            let (entered, entering) = std::sync::mpsc::channel();
            *sink.0.channel.delivery_admission_entered.lock().unwrap() = Some(entered);
            tokio::task::block_in_place(|| -> Result<()> {
                // The writer already owns progress. Admission reaches accounting only after it
                // pinned the actual registry source; it must not still own the registry here.
                let progress = lock_progress(&sink.0);
                let admission = std::thread::spawn({
                    let coordinator = store.thread_persistence().clone();
                    let channel = sink.0.channel.clone();
                    move || -> Result<Box<dyn std::any::Any + Send>> {
                        if cold {
                            Ok(Box::new(
                                coordinator.retain_terminal_material(id, &channel, 1024, None)?,
                            ))
                        } else {
                            Ok(Box::new(coordinator.retain_review_delivery(id, 1024)?))
                        }
                    }
                });
                entering.recv_timeout(Duration::from_secs(5))?;
                assert_eq!(
                    sink.0.channel.delivery_admissions.load(Ordering::Acquire),
                    1
                );
                let (probed, probe) = std::sync::mpsc::channel();
                let registry = std::thread::spawn({
                    let coordinator = store.thread_persistence().clone();
                    move || {
                        let channel = coordinator.history_channel(id);
                        let _ = probed.send(channel);
                    }
                });
                let registry_source = probe.recv_timeout(Duration::from_secs(5));
                if registry_source.is_ok() {
                    // This is the real progress -> registry writer report, while delivery's
                    // accounting is blocked on the progress lock above.
                    report(&sink.0, &progress);
                }
                // Also release the blocked participants before reporting a regression failure.
                drop(progress);
                let retained = admission
                    .join()
                    .map_err(|_| anyhow::anyhow!("delivery admission panicked"))??;
                registry
                    .join()
                    .map_err(|_| anyhow::anyhow!("registry probe panicked"))?;
                let source = registry_source?;
                assert!(Arc::ptr_eq(&source, &sink.0.channel));
                assert_eq!(
                    sink.0.channel.delivery_admissions.load(Ordering::Acquire),
                    0
                );
                assert_eq!(sink.0.channel.retained_delivery_bytes(), 1024);
                drop(retained);
                assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
                Ok(())
            })?;
            sink.0.channel.stop_and_join().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_unchanged_projection_reports_stay_quiet_but_retry_and_handoff_wake()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "projection-watch";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let channel = &sink.0.channel;
        let lease = channel.step_lock.lock().await;
        let mut status = channel.subscribe();
        let mut pressure = channel.pressure_changed.subscribe();
        let mut capacity = store.thread_persistence().subscribe_delivery_capacity();
        let steady = ProjectionRetention {
            resident_bytes: 256,
            pending: None,
        };
        channel.set_projection_retention(steady)?;
        assert!(status.has_changed()? && pressure.has_changed()?);
        status.borrow_and_update();
        pressure.borrow_and_update();
        capacity.borrow_and_update();
        for _ in 0..8 {
            channel.set_projection_retention(steady)?;
            assert!(!status.has_changed()?);
            assert!(!pressure.has_changed()?);
            assert!(!capacity.has_changed()?);
        }
        let full = ProjectionRetention {
            resident_bytes: MAX_HISTORY_THREAD_BYTES + 1,
            pending: None,
        };
        assert!(channel.set_projection_retention(full).is_err());
        status.borrow_and_update();
        pressure.borrow_and_update();
        for _ in 0..8 {
            assert!(channel.set_projection_retention(full).is_err());
            assert!(!status.has_changed()?);
            assert!(!pressure.has_changed()?);
        }
        channel.release_projection_retention();
        assert!(status.has_changed()? && pressure.has_changed()? && capacity.has_changed()?);
        status.borrow_and_update();
        pressure.borrow_and_update();
        let write = ticket(id, 1);
        sink.admit(id, write.clone())?;
        let mut projection = live_projection(&sink).await?;
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection
            .publish_prepared(&sink.0.chat, &mut prepared)
            .await?;
        assert_eq!(
            prepared.retained_bytes(),
            prepared.accounting.retained_bytes(),
            "content-empty handoffs still own their prepared accounting"
        );
        status.borrow_and_update();
        assert!(channel.prepare(prepared.clone()));
        assert!(
            status.has_changed()?,
            "a new content-empty handoff must wake the observer"
        );
        status.borrow_and_update();
        assert!(channel.prepare(prepared));
        assert!(
            !status.has_changed()?,
            "repeating the same handoff is not a new event"
        );
        channel.fail_projection(1, "controlled projection report failure".into());
        let generation = status.borrow_and_update().fault_generation;
        pressure.borrow_and_update();
        channel.fail_projection(1, "controlled projection report failure".into());
        assert!(!status.has_changed()? && !pressure.has_changed()?);
        channel.retry(generation)?;
        assert!(status.has_changed()? && pressure.has_changed()?);
        drop(lease);
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let snapshot = status.borrow_and_update().clone();
                if snapshot.committed_sequence == 1 && snapshot.error.is_none() {
                    break Ok::<_, anyhow::Error>(());
                }
                status.changed().await?;
            }
        })
        .await??;
        channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_multi_item_effect_rejection_keeps_projection_and_stamps_atomic()
    -> Result<()> {
        assert_empty_multi_item_prepare_is_atomic(false).await
    }

    #[tokio::test]
    async fn execution_index_empty_prepare_rejects_unfunded_stamp_without_reserving_shells()
    -> Result<()> {
        assert_empty_multi_item_prepare_is_atomic(true).await
    }

    async fn assert_empty_multi_item_prepare_is_atomic(stamp_shortfall: bool) -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "batch-projection-budget";
        let attempt_id = "batch-attempt";
        let turn_id = "batch-turn";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, 2)?;
        let mut write = ticket(id, 1);
        write.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut write.effect).attempt = Some(update);
        sink.admit(id, write)?;
        let owed = sink.0.channel.next_unprojected().unwrap();
        let candidates = crate::studio::thread_projection::project_effect_items(
            &sink.0.thread,
            &owed.checkpoint.state,
            &owed.effect,
            &Default::default(),
            &Default::default(),
            &Default::default(),
        )?
        .items;
        let ids = candidates
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>();
        assert_eq!(ids.len(), 3);
        let index = sink.0.channel.order_index();
        let probe = RuntimeOrderIndex::new(Arc::new(AtomicU64::new(0)), 0);
        // This separate, disposable index measures the established shell charge only. The
        // production index below remains empty until its one actual prepare call.
        probe.assign(&ids[0])?;
        let first_shell = probe.retained_bytes();
        for identity in &ids[1..] {
            probe.assign(identity)?;
        }
        let shells = probe.retained_bytes();
        let stamps = candidates
            .iter()
            .map(|item| item.turn_id.len() as u64)
            .sum::<u64>();
        assert!(stamps > 1);
        let available = if stamp_shortfall {
            shells + stamps - 1
        } else {
            first_shell
        };
        if stamp_shortfall {
            assert!(
                available >= shells,
                "every shell fits before testing the final stamp"
            );
            assert!(
                available < shells + stamps,
                "the complete stamp delta does not fit"
            );
        }
        let queued = sink.pressure(id).thread_bytes;
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: MAX_HISTORY_THREAD_BYTES - queued - available,
                pending: None,
            })?;
        let process = sink.0.channel.process_bytes.load(Ordering::Acquire);
        let thread_bytes = sink.pressure(id).thread_bytes;
        let index_bytes = index.retained_bytes();
        let index_state = {
            let state = index.inner.lock().unwrap();
            (
                state.ceiling,
                state.durable,
                state.resident_blocked,
                state.assigned.len(),
            )
        };
        let projection_bytes = projection.retained_bytes();
        let completion_head = chat.head_seq();
        assert_eq!(index_bytes, 0);
        assert_eq!(index_state, (0, 0, false, 0));
        assert_eq!(projection_bytes, 0);
        assert_eq!(completion_head, 0);
        let failure = projection
            .prepare(&sink.0.thread, &owed.effect, &owed.checkpoint.state, true)
            .await
            .err()
            .context("the empty-index prepare must reject the insufficient batch budget")?;
        assert!(failure.to_string().contains("budget"), "{failure}");
        assert_eq!(index.retained_bytes(), index_bytes);
        {
            let state = index.inner.lock().unwrap();
            assert_eq!(
                (
                    state.ceiling,
                    state.durable,
                    state.resident_blocked,
                    state.assigned.len()
                ),
                index_state
            );
        }
        assert_eq!(
            sink.0.channel.process_bytes.load(Ordering::Acquire),
            process
        );
        assert_eq!(sink.pressure(id).thread_bytes, thread_bytes);
        assert_eq!(projection.retained_bytes(), projection_bytes);
        assert!(projection.turn_result(turn_id).is_none());
        assert_eq!(chat.head_seq(), completion_head);
        assert!(Arc::ptr_eq(
            &sink.0.channel.next_unprojected().unwrap(),
            &owed
        ));

        // Restore headroom and retry the same owed write, without any separate identity
        // reservation. Nothing from the rejected prepare may consume an ordinal or revision.
        sink.0.channel.release_projection_retention();
        let (_, mut prepared) = projection
            .prepare(&sink.0.thread, &owed.effect, &owed.checkpoint.state, true)
            .await?;
        assert!(prepared.completion_drafts.is_some());
        assert!(prepared.completions.is_empty());
        assert_eq!(chat.head_seq(), 0);
        assert!(!sink.0.channel.prepare(prepared.clone()));
        projection.publish_prepared(&chat, &mut prepared).await?;
        assert_eq!(prepared.items.len(), 3);
        assert!(
            prepared
                .items
                .iter()
                .all(|item| item.revision == 1 && item.ordinal > 0)
        );
        let actual_ids = prepared
            .items
            .iter()
            .map(|item| item.id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(actual_ids, ids.iter().cloned().collect());
        let ordinals = prepared
            .items
            .iter()
            .map(|item| item.ordinal)
            .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(ordinals, [1, 2, 3].into_iter().collect());
        assert_eq!(index.inner.lock().unwrap().ceiling, 3);
        assert_eq!(prepared.completions.len(), 3);
        for (offset, completion) in prepared.completions.iter().enumerate() {
            assert_eq!(completion.append_seq, offset as u64 + 1);
        }
        let published = prepared.clone();
        projection.publish_prepared(&chat, &mut prepared).await?;
        assert!(Arc::ptr_eq(&published, &prepared));
        assert_eq!(
            chat.head_seq(),
            3,
            "publication retry cannot append duplicate identities"
        );
        assert!(sink.0.channel.prepare(prepared));
        sink.flush(id, 1).await?;
        assert_eq!(chat.head_seq(), 3);
        assert_eq!(
            store
                .history(id)
                .await?
                .items_for_turn(turn_id)
                .await?
                .len(),
            3
        );
        sink.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn execution_index_channel_resident_commits_serialize_provider_allocation() -> Result<()>
    {
        // Admission, direct preparation, and transfer of an already charged pending batch.
        for mode in 0..3 {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let id = format!("resident-commit-{mode}");
            register_test_thread(&store, &test_thread(&id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(&id), None).await?;
            let chat = store.chat_session(&id).await?;
            let mut projection = live_projection(&sink).await?;
            let write = visible_input_ticket(&id, 1, "input")?;
            let lease = sink.0.channel.step_lock.lock().await;
            let prepared = if mode == 0 {
                let probe = RuntimeOrderIndex::new(Arc::new(AtomicU64::new(0)), 0);
                probe.reserve_boundaries(&write.effect, 0)?;
                let resident_bytes = MAX_HISTORY_THREAD_BYTES
                    - encoded_bytes(&write.effect)
                    - probe.retained_bytes();
                sink.0
                    .channel
                    .set_projection_retention(ProjectionRetention {
                        resident_bytes,
                        pending: None,
                    })?;
                None
            } else {
                sink.admit(&id, write.clone())?;
                let mut prepared = projection
                    .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
                    .await?;
                projection.publish_prepared(&chat, &mut prepared).await?;
                let bytes = prepared.retained_bytes();
                sink.0
                    .channel
                    .set_projection_retention(ProjectionRetention {
                        resident_bytes: MAX_HISTORY_THREAD_BYTES
                            - sink.pressure(&id).thread_bytes
                            - bytes,
                        pending: (mode == 2).then_some(PendingProjectionRetention {
                            sequence: 1,
                            prepared_bytes: bytes,
                        }),
                    })?;
                Some(prepared)
            };
            let (entered, entered_rx) = tokio::sync::oneshot::channel();
            let (release, release_rx) = std::sync::mpsc::channel();
            *sink.0.channel.resident_gate.lock().unwrap() = Some(MaterializeGate {
                entered,
                release: release_rx,
            });
            let mutation = {
                let sink = sink.clone();
                let write = write.clone();
                let prepared = prepared.clone();
                let id = id.clone();
                tokio::task::spawn_blocking(move || -> Result<()> {
                    if let Some(prepared) = prepared {
                        ensure!(
                            sink.0.channel.prepare(prepared),
                            "prepared handoff rejected"
                        );
                    } else {
                        sink.admit(&id, write)?;
                    }
                    Ok(())
                })
            };
            tokio::time::timeout(Duration::from_secs(5), entered_rx).await??;
            let (attempting, attempted) = tokio::sync::oneshot::channel();
            let provider = {
                let sink = sink.clone();
                let id = id.clone();
                tokio::task::spawn_blocking(move || {
                    let _ = attempting.send(());
                    sink.reserve_observed_item(&id, "provider-attempt", "provider-part")
                })
            };
            attempted.await?;
            assert!(
                sink.0.channel.order_index.inner.try_lock().is_err(),
                "the resident mutation must exclude identity allocation until its commit"
            );
            release.send(())?;
            mutation.await??;
            assert!(provider.await?.is_err());
            assert_eq!(sink.pressure(&id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
            assert_eq!(sink.0.channel.order_index.assigned("provider-part"), None);
            {
                let progress = lock_progress(&sink.0);
                assert_eq!(progress.effects.len(), 1);
                assert_eq!(progress.projection_pending, None);
                assert_eq!(progress.effects[0].sequence, 1);
                if let Some(prepared) = &prepared {
                    assert!(Arc::ptr_eq(
                        progress.effects[0].prepared.as_ref().unwrap(),
                        prepared
                    ));
                } else {
                    assert!(progress.effects[0].prepared.is_none());
                }
            }
            // Rejecting the optional provider reservation leaves the original fact fully owed.
            sink.0.channel.release_projection_retention();
            if prepared.is_none() {
                drive_live_projection(&mut projection, &chat, &sink, &id, write).await?;
            }
            drop(lease);
            let generation = sink.0.channel.subscribe().borrow().fault_generation;
            store
                .thread_persistence()
                .retry_history(&id, generation)
                .await?;
            sink.flush(&id, 1).await?;
            assert_eq!(store.history(&id).await?.watermark().await?, 1);
            sink.0.channel.stop_and_join().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_terminal_transfer_rejection_retains_source_and_releases_capacity()
    -> Result<()> {
        use pl_core::thread::inbox::ThreadMessage;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "terminal-transfer-budget";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let write = visible_input_ticket(id, 1, "input")?;
        sink.admit(id, write.clone())?;
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        Arc::get_mut(&mut prepared).unwrap().parent_report = Some(Arc::new(ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Report,
            id: "terminal-report".into(),
            source_id: "agent:worker".into(),
            payload: OpaquePayload::text("the original completed report"),
            context: Vec::new(),
        }));
        let source = PendingProjectionRetention {
            sequence: 1,
            prepared_bytes: prepared.retained_bytes(),
        };
        let report_bytes = prepared.parent_report_retained_bytes();
        let material_bytes = report_bytes + 1024;
        let resident =
            MAX_HISTORY_THREAD_BYTES - sink.pressure(id).thread_bytes - source.prepared_bytes;
        let mut before = ProjectionRetention {
            resident_bytes: resident,
            pending: Some(source),
        };
        sink.0.channel.set_projection_retention(before)?;
        let transfer = |before: ProjectionRetention| ProjectionTransfer {
            source,
            after: ProjectionRetention {
                resident_bytes: before.resident_bytes,
                pending: Some(PendingProjectionRetention {
                    sequence: 1,
                    prepared_bytes: source.prepared_bytes - report_bytes,
                }),
            },
        };
        let process_before = sink.0.channel.process_bytes.load(Ordering::Acquire);
        assert!(
            store
                .thread_persistence()
                .retain_terminal_material(
                    id,
                    &sink.0.channel,
                    material_bytes,
                    Some(transfer(before))
                )
                .is_err()
        );
        assert_eq!(sink.pressure(id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
        assert_eq!(
            sink.0.channel.process_bytes.load(Ordering::Acquire),
            process_before
        );
        assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
        assert_eq!(lock_progress(&sink.0).projection_pending, Some(source));
        assert!(prepared.parent_report.is_some());
        assert!(
            sink.0
                .channel
                .order_index
                .reserve_observed("attempt", "blocked-part")
                .is_err()
        );
        assert_eq!(sink.0.channel.order_index.assigned("blocked-part"), None);

        before.resident_bytes -= material_bytes;
        sink.0.channel.set_projection_retention(before)?;
        sink.0
            .channel
            .process_bytes
            .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
        assert!(
            store
                .thread_persistence()
                .retain_terminal_material(
                    id,
                    &sink.0.channel,
                    material_bytes,
                    Some(transfer(before))
                )
                .is_err()
        );
        assert_eq!(
            sink.0.channel.process_bytes.load(Ordering::Acquire),
            MAX_HISTORY_PROCESS_BYTES
        );
        assert_eq!(lock_progress(&sink.0).projection_pending, Some(source));
        assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
        sink.0
            .channel
            .process_bytes
            .store(process_before, Ordering::Release);
        let retained = store.thread_persistence().retain_terminal_material(
            id,
            &sink.0.channel,
            material_bytes,
            Some(transfer(before)),
        )?;
        Arc::get_mut(&mut prepared).unwrap().parent_report = None;
        assert_eq!(
            lock_progress(&sink.0).projection_pending,
            transfer(before).after.pending
        );
        assert_eq!(sink.0.channel.retained_delivery_bytes(), material_bytes);
        assert!(sink.pressure(id).thread_bytes <= MAX_HISTORY_THREAD_BYTES);
        // The real managed guard releases through the coordinator callback, not a report write.
        drop(retained);
        assert_eq!(sink.0.channel.retained_delivery_bytes(), 0);
        sink.0
            .channel
            .order_index
            .reserve_observed("attempt", "released-part")?;
        assert!(sink.0.channel.prepare(prepared));
        sink.0.channel.release_projection_retention();
        sink.flush(id, 1).await?;
        sink.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_cold_terminal_material_uses_new_admission_and_managed_release()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "cold-material-budget";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let channel = &sink.0.channel;
        let process_before = channel.process_bytes.load(Ordering::Acquire);
        channel.set_projection_retention(ProjectionRetention {
            resident_bytes: MAX_HISTORY_THREAD_BYTES - 512,
            pending: None,
        })?;
        assert!(
            store
                .thread_persistence()
                .retain_terminal_material(id, channel, 1024, None)
                .is_err()
        );
        assert_eq!(channel.retained_delivery_bytes(), 0);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            process_before
        );
        assert_eq!(
            sink.pressure(id).thread_bytes,
            MAX_HISTORY_THREAD_BYTES - 512
        );
        {
            let progress = lock_progress(&sink.0);
            assert_eq!(progress.projection_pending, None);
            assert!(progress.effects.is_empty());
        }
        channel.set_projection_retention(ProjectionRetention {
            resident_bytes: MAX_HISTORY_THREAD_BYTES - 1024,
            pending: None,
        })?;
        let material = store
            .thread_persistence()
            .retain_terminal_material(id, channel, 1024, None)?;
        assert_eq!(channel.retained_delivery_bytes(), 1024);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            process_before + 1024
        );
        assert_eq!(sink.pressure(id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
        assert!(
            channel
                .order_index
                .reserve_observed("attempt", "part")
                .is_err()
        );
        assert_eq!(channel.order_index.assigned("part"), None);
        drop(material);
        assert_eq!(channel.retained_delivery_bytes(), 0);
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            process_before
        );
        channel.order_index.reserve_observed("attempt", "part")?;
        channel.release_projection_retention();
        channel.stop_and_join().await?;
        Ok(())
    }

    #[test]
    fn execution_index_admission_boundaries_reject_atomically_and_stay_charged() -> Result<()> {
        let process = Arc::new(AtomicU64::new(0));
        let index = RuntimeOrderIndex::new(process.clone(), 0);
        let mut write = visible_input_ticket("boundary-budget", 1, "input")?;
        Arc::make_mut(&mut write.effect).turn =
            Some(turn_record("turn", "input", TurnState::Running));
        assert!(
            index
                .reserve_boundaries(&write.effect, MAX_HISTORY_THREAD_BYTES - 1)
                .is_err()
        );
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(process.load(Ordering::Acquire), 0);
        assert!(index.inner.lock().unwrap().assigned.is_empty());
        assert_eq!(index.inner.lock().unwrap().ceiling, 0);
        process.store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
        assert!(index.reserve_boundaries(&write.effect, 0).is_err());
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(process.load(Ordering::Acquire), MAX_HISTORY_PROCESS_BYTES);
        assert!(index.inner.lock().unwrap().assigned.is_empty());
        assert_eq!(index.inner.lock().unwrap().ceiling, 0);
        process.store(0, Ordering::Release);
        index.reserve_boundaries(&write.effect, 0)?;
        let bytes = index.retained_bytes();
        assert!(bytes > 0);
        assert_eq!(process.load(Ordering::Acquire), bytes);
        // Processing an older checkpoint cannot retire an admitted but unprojected boundary.
        index.retain(&Default::default(), &Default::default());
        assert_eq!(index.retained_bytes(), bytes);
        index.confirm_saved(1);
        assert_eq!(index.retained_bytes(), 0);
        assert_eq!(process.load(Ordering::Acquire), 0);
        assert_eq!(index.assign("next")?, 3);
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_running_turn_recovers_its_boundary_before_cold_admission() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "turn-cold-boundary";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let mut opening = visible_input_ticket(id, 1, "input")?;
        let running = turn_record("visible-turn", "input", TurnState::Running);
        opening.checkpoint.state.turns = Arc::from([running.clone()]);
        Arc::make_mut(&mut opening.effect).turn = Some(running.clone());
        let original = drive_live_projection(&mut projection, &chat, &sink, id, opening).await?;
        sink.flush(id, 1).await?;
        let turn_id = crate::studio::thread_projection::order::turn_id("visible-turn");
        let original_turn = original
            .items
            .iter()
            .find(|item| item.id == turn_id)
            .unwrap();
        let history = store.history(id).await?;
        let checkpoint = history.checkpoint().await?.context("running checkpoint")?;
        sink.0.channel.stop_and_join().await?;
        drop(projection);
        drop(sink);
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread(id), Some(&checkpoint)).await?;
        assert_eq!(
            sink.0.channel.order_index.assigned(&turn_id),
            Some(original_turn.ordinal)
        );
        let mut projection = live_projection(&sink).await?;
        let mut update = ticket(id, 2);
        update.checkpoint.state.turns = Arc::from([running.clone()]);
        Arc::make_mut(&mut update.effect).turn = Some(running);
        let prepared = drive_live_projection(&mut projection, &chat, &sink, id, update).await?;
        assert_eq!(prepared.items[0].ordinal, original_turn.ordinal);
        sink.flush(id, 2).await?;
        assert_eq!(
            history.item(&turn_id).await?.unwrap().ordinal,
            original_turn.ordinal
        );
        sink.0.channel.stop_and_join().await?;
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_turn_start_precedes_provider_reservations_before_projection()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let id = "turn-start-order";
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let chat = store.chat_session(id).await?;
        let mut projection = live_projection(&sink).await?;
        let turn_id = "turn";
        let input_id = "input";
        let attempt_id = "attempt";
        let input = consumed_visible_input(input_id, turn_id, 1)?;
        let running = turn_record(turn_id, input_id, TurnState::Running);
        let mut opening = ticket(id, 1);
        opening.checkpoint.state.inputs = Arc::from([input.clone()]);
        opening.checkpoint.state.turns = Arc::from([running.clone()]);
        Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Arc::make_mut(&mut opening.effect).turn = Some(running.clone());
        // Core can already produce observations while the one projection owner still owes the
        // admitted Turn start. Its provider reservation must not precede that Turn's first item.
        sink.admit(id, opening.clone())?;
        let part_id = crate::studio::thread_projection::order::presentation_id(
            attempt_id,
            0,
            "stress-item-0",
            Some(crate::studio::thread_projection::order::PresentationPart::OutputText(0)),
        );
        sink.reserve_observed_item(id, attempt_id, &part_id)?;
        let opening_batch =
            drive_live_projection(&mut projection, &chat, &sink, id, opening).await?;
        sink.flush(id, 1).await?;
        let first = opening_batch
            .items
            .iter()
            .map(|item| item.ordinal)
            .min()
            .unwrap();
        let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, 1)?;
        let mut step = ticket(id, 2);
        step.checkpoint.state.turns = Arc::from([running]);
        step.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut step.effect).attempt = Some(update);
        let batch = drive_live_projection(&mut projection, &chat, &sink, id, step).await?;
        sink.flush(id, 2).await?;
        assert!(
            batch
                .items
                .iter()
                .find(|item| item.id == part_id)
                .unwrap()
                .ordinal
                > first
        );
        let finished = turn_record(
            turn_id,
            input_id,
            TurnState::Finished(TurnOutcome::Completed),
        );
        let mut terminal = ticket(id, 3);
        terminal.checkpoint.state.turns = Arc::from([finished.clone()]);
        Arc::make_mut(&mut terminal.effect).turn = Some(finished);
        drive_live_projection(&mut projection, &chat, &sink, id, terminal).await?;
        sink.flush(id, 3).await?;
        // The next checkpoint releases the finished source and its actual references. Real save
        // confirmation must allow the entire index to retire without losing the durable boundary.
        drive_live_projection(&mut projection, &chat, &sink, id, ticket(id, 4)).await?;
        sink.flush(id, 4).await?;
        assert_eq!(sink.0.channel.order_index.retained_bytes(), 0);
        let head = chat.head_seq();
        let mut late = ticket(id, 5);
        let mut input = consumed_visible_input(input_id, turn_id, 1)?;
        input.revision = 5;
        late.checkpoint.state.inputs = Arc::from([input.clone()]);
        Arc::make_mut(&mut late.effect).inputs = Arc::from([InputChange::Transition {
            id: input_id.into(),
            revision: input.revision,
            state: input.state,
        }]);
        let late_batch = drive_live_projection(&mut projection, &chat, &sink, id, late).await?;
        assert_eq!(late_batch.items[0].ordinal, first);
        assert!(late_batch.completions.is_empty());
        sink.flush(id, 5).await?;
        assert_eq!(chat.head_seq(), head);
        let history = store.history(id).await?;
        assert_eq!(history.items_for_turn(turn_id).await?[0].ordinal, first);
        let checkpoint = history.checkpoint().await?.context("saved late fact")?;
        drop(projection);
        // Run the actual Core close, whose Closing/Closed commits are additional reliable facts,
        // with the same channel/writer and one replacement projection owner.
        let observer = spawn_projection(store.clone(), test_thread(id));
        let core = ThreadHandle::resume_without_model(id.into(), Some(checkpoint))?;
        core.attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        tokio::time::timeout(Duration::from_secs(10), core.close()).await??;
        let closed = history.checkpoint().await?.context("saved Core close")?;
        assert_eq!(
            closed.state.lifecycle,
            pl_core::thread::ThreadLifecycle::Closed
        );
        assert!(closed.history_fence > 5);
        assert_eq!(history.watermark().await?, closed.history_fence);
        assert_eq!(history.items_for_turn(turn_id).await?[0].ordinal, first);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        sink.0.channel.stop_and_join().await?;
        tokio::time::timeout(Duration::from_secs(5), observer).await??;
        Ok(())
    }

    #[tokio::test]
    async fn a_live_turn_input_survives_a_window_smaller_than_its_parts() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("window-input")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("window-input"), None).await?;
        let thread_id = "window-input";
        let turn_id = "long-turn";
        let attempt_id = "long-attempt";
        let input_id = "input-under-the-window";
        let chat = store.chat_session(thread_id).await?;
        let mut projection = live_projection(&sink).await?;

        // Commit 1: the Turn's own opening input. Every later commit's checkpoint has pruned the
        // consumed body from `state.inputs` and keeps only the minimal `turns[].input_id`.
        let input = consumed_visible_input(input_id, turn_id, 1)?;
        let mut opening = ticket(thread_id, 1);
        opening.checkpoint.state.inputs = Arc::from([input.clone()]);
        opening.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Arc::make_mut(&mut opening.effect).turn =
            Some(turn_record(turn_id, input_id, TurnState::Running));
        drive_live_projection(&mut projection, &chat, &sink, thread_id, opening).await?;

        // Commit 2: one model step whose receipt itemizes more provider parts than the window holds.
        // That pushes the Turn's own oldest facts out of the ordinal window.
        let parts = crate::studio::thread_projection::LIVE_ITEM_WINDOW + 8;
        let (attempt, update) = committed_parts_attempt(turn_id, attempt_id, parts)?;
        let mut step = ticket(thread_id, 2);
        step.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        step.checkpoint.state.attempts = Arc::from([attempt.clone()]);
        Arc::make_mut(&mut step.effect).attempt = Some(update);
        drive_live_projection(&mut projection, &chat, &sink, thread_id, step).await?;

        // Commit 3: the Turn's terminal effect. Its checkpoint names the input without carrying its
        // body, and it re-projects the Turn item, so both the input identity and the Turn's content
        // version have to resolve from the projection's own memory.
        let finished = || {
            turn_record(
                turn_id,
                input_id,
                TurnState::Finished(TurnOutcome::Completed),
            )
        };
        let mut terminal = ticket(thread_id, 3);
        terminal.checkpoint.state.turns = Arc::from([finished()]);
        terminal.checkpoint.state.attempts = Arc::from([attempt]);
        Arc::make_mut(&mut terminal.effect).turn = Some(finished());
        drive_live_projection(&mut projection, &chat, &sink, thread_id, terminal).await?;

        // Every fact is handed over, so the durable barrier reaches the terminal commit with no
        // fault, and the rows a long Turn produced are complete instead of a hole or a revision
        // conflict.
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 3),
            sink.flush(thread_id, 3),
            || channel_facts(&sink),
        )
        .await??;
        let history = store.history(thread_id).await?;
        assert_eq!(history.watermark().await?, 3);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        assert!(history.input_identity(input_id).await?.is_some());
        let turn_item_id = crate::studio::thread_projection::order::turn_id(turn_id);
        let last_part_id = crate::studio::thread_projection::order::presentation_id(
            attempt_id,
            0,
            &format!("stress-item-{}", parts - 1),
            Some(crate::studio::thread_projection::order::PresentationPart::OutputText(0)),
        );
        let mut rows = history
            .existing_items([
                input_id.to_owned(),
                turn_item_id.clone(),
                last_part_id.clone(),
            ])
            .await?;
        let input_row = rows
            .remove(input_id)
            .expect("the live Turn's consumed input stays a complete durable row");
        match input_row.state() {
            pl_protocol::ThreadItemState::Text(text) => assert_eq!(text.text(), "hello"),
            other => panic!("the input row keeps its visible body, got {other:?}"),
        }
        let turn_row = rows
            .remove(&turn_item_id)
            .expect("the Turn row is re-projected onto its own content version");
        match turn_row.state() {
            pl_protocol::ThreadItemState::Turn(turn) => {
                assert!(matches!(turn.state(), pl_protocol::TurnState::Completed(_)))
            }
            other => panic!("the Turn row keeps its Turn state, got {other:?}"),
        }
        let part_row = rows
            .remove(&last_part_id)
            .expect("the receipt's provider parts are durable rows");
        match part_row.state() {
            pl_protocol::ThreadItemState::Text(text) => {
                assert_eq!(text.text(), format!("chunk-{}", parts - 1).as_str())
            }
            other => panic!("the provider part keeps its text, got {other:?}"),
        }
        Ok(())
    }

    #[tokio::test]
    async fn a_cold_owner_seeds_the_same_terminal_turn_the_live_projection_publishes() -> Result<()>
    {
        // A Thread re-activated after its last Turn finished has no live frame left for that fact:
        // the authoritative snapshot carries only the active Turn and `turnCompleted` is broadcast
        // once. The owner therefore seeds its retained last-Turn fact from durable history on the
        // install path. This drives that cold read over real committed rows and proves it agrees with
        // the live projection the frame would have used — same identity, same revision, same state —
        // while a Turn that is still running (or not yet durable) is never reported as finished.
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("cold-turn")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("cold-turn"), None).await?;
        let thread_id = "cold-turn";
        let turn_id = "terminal-turn";
        let input_id = "cold-input";
        let chat = store.chat_session(thread_id).await?;
        let mut projection = live_projection(&sink).await?;

        // A Thread whose history was never written reads as "no finished Turn" instead of creating a
        // database, so this cold read can never make the live path wait on the writer.
        assert!(
            store
                .history_for("project-test", "never-written")
                .await?
                .newest_terminal_turn()
                .await?
                .is_none()
        );

        // Commit 1: the Turn opens and is durable, but it is still running — the cold seed must not
        // mistake the newest Turn row for a finished one.
        let input = consumed_visible_input(input_id, turn_id, 1)?;
        let mut opening = ticket(thread_id, 1);
        opening.checkpoint.state.inputs = Arc::from([input.clone()]);
        opening.checkpoint.state.turns =
            Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
        Arc::make_mut(&mut opening.effect).inputs = Arc::from([InputChange::Accepted(input)]);
        Arc::make_mut(&mut opening.effect).turn =
            Some(turn_record(turn_id, input_id, TurnState::Running));
        drive_live_projection(&mut projection, &chat, &sink, thread_id, opening).await?;
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 1),
            sink.flush(thread_id, 1),
            || channel_facts(&sink),
        )
        .await??;
        assert!(
            store
                .history(thread_id)
                .await?
                .newest_terminal_turn()
                .await?
                .is_none()
        );
        let history = store.history(thread_id).await?;
        let admitted = history.latest_turn_at(1).await?.context("admitted Turn")?;
        assert_eq!(admitted.id, turn_id);
        assert!(!admitted.state.is_terminal());
        assert!(history.latest_turn_at(0).await.is_err());
        assert!(history.latest_turn_at(2).await.is_err());

        // Intervening commits advance the execution clock without changing the Turn item.
        // A terminal frame must outrank running frames even when its item content version is small.
        for sequence in 2..=10 {
            let mut intermediate = ticket(thread_id, sequence);
            intermediate.checkpoint.state.turns =
                Arc::from([turn_record(turn_id, input_id, TurnState::Running)]);
            drive_live_projection(&mut projection, &chat, &sink, thread_id, intermediate).await?;
        }
        // Commit 11: the Turn finishes. The live projection of that same effect is the fact the frame
        // carried; the durable row the writer commits has to recover the identical Turn.
        let finished = || {
            turn_record(
                turn_id,
                input_id,
                TurnState::Finished(TurnOutcome::Completed),
            )
        };
        let mut terminal = ticket(thread_id, 11);
        terminal.checkpoint.state.turns = Arc::from([finished()]);
        Arc::make_mut(&mut terminal.effect).turn = Some(finished());
        let prepared =
            drive_live_projection(&mut projection, &chat, &sink, thread_id, terminal).await?;
        let live = crate::studio::thread_projection::prepared_terminal_turn(&prepared)
            .context("the live projection must carry the finished Turn")?;
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 11),
            sink.flush(thread_id, 11),
            || channel_facts(&sink),
        )
        .await??;

        let cold = store
            .history(thread_id)
            .await?
            .newest_terminal_turn()
            .await?
            .context("the durable history must carry the finished Turn")?;
        assert_eq!(
            live.revision, 11,
            "terminal frame must use the execution clock"
        );
        assert_eq!(cold.id, live.id);
        assert_eq!(cold.revision, live.revision);
        assert_eq!(cold.state, live.state);
        let saved = history.checkpoint().await?.context("durable checkpoint")?;
        assert!(saved.state.turns.is_empty(), "terminal Turns must retire");
        assert_eq!(
            history.latest_turn_at(saved.history_fence).await?,
            Some(live.clone())
        );

        // A later running admission must outrank the saved terminal. Evaluation cannot use the
        // terminal-only seed as a shortcut, even while that older terminal remains readable.
        let next_id = "newer-running-turn";
        let next_input = consumed_visible_input("newer-input", next_id, 12)?;
        let mut next = ticket(thread_id, 12);
        next.checkpoint.state.inputs = Arc::from([next_input.clone()]);
        next.checkpoint.state.turns =
            Arc::from([turn_record(next_id, "newer-input", TurnState::Running)]);
        Arc::make_mut(&mut next.effect).inputs = Arc::from([InputChange::Accepted(next_input)]);
        Arc::make_mut(&mut next.effect).turn =
            Some(turn_record(next_id, "newer-input", TurnState::Running));
        drive_live_projection(&mut projection, &chat, &sink, thread_id, next).await?;
        await_durable(
            Duration::from_secs(30),
            &format!("commit {}", 12),
            sink.flush(thread_id, 12),
            || channel_facts(&sink),
        )
        .await??;
        let latest = history.latest_turn_at(12).await?.context("latest Turn")?;
        assert_eq!(latest.id, next_id);
        assert!(!latest.state.is_terminal());
        assert_eq!(history.newest_terminal_turn().await?, Some(cold));
        assert!(history.latest_turn_at(11).await.is_err());
        Ok(())
    }

    #[tokio::test]
    async fn retained_budget_counts_the_bodies_the_live_projection_holds() {
        // A running Turn retains tool arguments, terminal results, attachment metadata and opaque
        // payloads. Charging only text and reasoning would leave the largest resident bodies outside
        // the Thread's reliable budget, so the estimate has to cover every category payload.
        let arguments = "a".repeat(4096);
        let result = "r".repeat(8192);
        let artifact = "z".repeat(2048);
        let raw_content = "p".repeat(1024);
        let failure = "f".repeat(256);
        let attachment = pl_protocol::ThreadAttachment {
            id: "artifact-attachment".to_owned(),
            modality: pl_protocol::AttachmentModality::File,
            media_type: "application/octet-stream".to_owned(),
            filename: Some("artifact.bin".to_owned()),
            width: None,
            height: None,
            byte_size: 64 * 1024 * 1024,
        };
        let tool = pl_protocol::ThreadItem::new(
            "tool-item".to_owned(),
            "retained-budget".to_owned(),
            "turn".to_owned(),
            1,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    "call".to_owned(),
                    "shell".to_owned(),
                    arguments.clone(),
                ),
                pl_protocol::ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                    1,
                    pl_protocol::ThreadToolOutput::new(
                        result.clone(),
                        vec![attachment.clone()],
                        vec![serde_json::json!({"stdout": artifact.clone()})],
                        Some(0),
                    ),
                )),
            )),
        );
        let raw = pl_protocol::ThreadItem::new(
            "raw-item".to_owned(),
            "retained-budget".to_owned(),
            "turn".to_owned(),
            2,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Raw(pl_protocol::ThreadRawItem::stored(
                vec![pl_protocol::ThreadRawPayload {
                    format: "pl.model.receipt".to_owned(),
                    version: 1,
                    content: raw_content.clone(),
                }],
                String::new(),
                1,
            )),
        );
        let failed_text = pl_protocol::ThreadItem::new(
            "failed-text".to_owned(),
            "retained-budget".to_owned(),
            "turn".to_owned(),
            3,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Text(pl_protocol::ThreadTextItem::new(
                pl_protocol::ThreadTextChannel::Commentary,
                "visible".to_owned(),
                vec![attachment],
                pl_protocol::ThreadContentLifecycle::failed(1, failure.clone()),
            )),
        );
        let bytes = crate::studio::thread_projection::retained_bytes(&[tool, raw, failed_text]);
        let bodies =
            (arguments.len() + result.len() + artifact.len() + raw_content.len() + failure.len())
                as u64;
        assert!(
            bytes >= bodies,
            "retained budget {bytes} must cover the {bodies} resident body bytes"
        );
    }

    #[tokio::test]
    async fn projection_gauge_is_part_of_the_thread_budget() -> Result<()> {
        let (_temp, _store, sink) = sink("projection-budget").await?;
        // The projection owner keeps a Turn's retained bodies and its report accumulator resident
        // after their batch became durable. The Thread's budget therefore reads the owner's absolute
        // gauge, and releasing the owner's tables releases the budget with them.
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention {
                resident_bytes: 8192,
                pending: None,
            })?;
        assert_eq!(sink.pressure("projection-budget").thread_bytes, 8192);
        assert_eq!(sink.0.channel.subscribe().borrow().queued_bytes, 8192);
        sink.0
            .channel
            .set_projection_retention(ProjectionRetention::default())?;
        assert_eq!(sink.pressure("projection-budget").thread_bytes, 0);
        assert_eq!(sink.0.channel.subscribe().borrow().queued_bytes, 0);
        Ok(())
    }

    #[tokio::test]
    async fn operation_output_reservation_returns_to_baseline_across_rounds() -> Result<()> {
        // Idle operations must not spend their hypothetical maximum output. More than sixteen
        // parallel tools with tiny output must run without exhausting the 256 MiB process budget.
        let (_temp, _store, sink) = sink("operation-budget").await?;
        let channel = &sink.0.channel;
        let baseline = channel.process_bytes.load(Ordering::Acquire);
        for index in 0..32 {
            assert_eq!(
                channel.reserve_operation_output(&format!("idle-{index}"), 16 * 1024 * 1024),
                Some(16 * 1024 * 1024)
            );
        }
        assert_eq!(channel.process_bytes.load(Ordering::Acquire), baseline);
        for index in 0..32 {
            channel.release_operation_output(&format!("idle-{index}"));
        }
        for round in 0..4_u64 {
            let operation = format!("task:call-{round}");
            let granted = channel
                .reserve_operation_output(&operation, 4096)
                .expect("the empty budget funds the reservation");
            assert_eq!(granted, 4096);
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline,
                "a ceiling without produced bytes consumes no resident budget"
            );
            channel.charge_operation_output(&operation, 1024)?;
            channel.charge_operation_output(&operation, 1024)?;
            assert!(channel.charge_operation_output(&operation, 4097).is_err());
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline + 1024
            );
            channel.release_operation_output(&operation);
            channel.release_operation_output(&operation);
            assert_eq!(
                channel.process_bytes.load(Ordering::Acquire),
                baseline,
                "a finished call releases all accepted bytes"
            );
        }
        Ok(())
    }

    /// The whole reserve/complete/refuse/recover cycle of parallel in-flight operations.
    ///
    /// Four Threads reserve the process budget down to its last byte, which is exactly the state
    /// where charging an admitted fact *next to* the reservation that produced it would need space
    /// that does not exist: every result would be refused, no result could be handed over, and the
    /// reservations would be held forever waiting for the queue they themselves block. The rule under
    /// test is the transfer instead — the bytes a reservation covers become the fact's own charge, so
    /// a fully reserved process still hands its facts over — together with the boundaries that stay
    /// real: an uncovered fact is refused with a typed fault instead of being admitted over budget,
    /// the refused fact is handed over unchanged once its Thread's ceiling comes back, and the
    /// process gauge returns to the baseline once everything is durable.
    #[tokio::test]
    async fn parallel_reservations_transfer_into_their_facts_without_deadlock() -> Result<()> {
        // No test projection here: nothing takes the admitted facts over until the test hands them
        // in itself, so the durable watermark cannot drain the queue while the reservations are
        // still charged and every step below is deterministic.
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let operations = (0..4)
            .map(|index| format!("task:parallel-{index}"))
            .collect::<Vec<_>>();
        let mut sinks = Vec::new();
        // Each Thread first admits its input identity, then charges output up to its own limit.
        // This funds both the existing boundaries and the output instead of placing the entire
        // process allowance on one Thread or inventing uncharged identities at the full limit.
        for (index, operation) in operations.iter().enumerate() {
            let id = format!("output-transfer-{index}");
            register_test_thread(&store, &test_thread(&id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(&id), None).await?;
            sink.admit(
                &id,
                visible_input_ticket(&id, 1, &format!("input-{index}"))?,
            )?;
            let reservation = MAX_HISTORY_THREAD_BYTES - sink.pressure(&id).thread_bytes;
            let granted = sink
                .0
                .channel
                .reserve_operation_output(operation, reservation)
                .expect("the Thread can register its remaining allowance");
            assert_eq!(granted, reservation);
            sink.0
                .channel
                .charge_operation_output(operation, reservation)?;
            assert_eq!(sink.pressure(&id).thread_bytes, MAX_HISTORY_THREAD_BYTES);
            sinks.push(sink);
        }
        let sink = &sinks[0];
        let channel = &sink.0.channel;
        let process_bytes = channel.process_bytes.clone();
        let baseline = 0;
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            MAX_HISTORY_PROCESS_BYTES,
            "the reservations alone fill the process budget"
        );
        assert!(
            channel
                .reserve_operation_output("task:one-too-many", MAX_HISTORY_THREAD_BYTES)
                .is_none(),
            "a call that the reliable budget cannot fund is backpressure, never a silent grant"
        );

        // A fact no reservation covers is refused while there is no headroom and no projection holds
        // a queued fact that could free any: typed backpressure, nothing dropped, ticket untouched.
        let uncovered = visible_input_ticket(&sink.0.thread.id, 3, "input-uncovered")?;
        sink.admit(&sink.0.thread.id, uncovered.clone())
            .expect_err("an unfunded fact cannot be admitted into a full budget");
        let refused = channel.subscribe().borrow().clone();
        assert_eq!(
            refused.fault,
            Some(pl_protocol::studio::HistoryFault::QueueFull)
        );
        // Both live incarnations observe the same real fault before recovery.
        // Neither may leave its own coordinator report blocked after it clears.
        let overlapping =
            ThreadStorageSink::new(store.clone(), sink.0.thread.clone(), None).await?;

        // Every call returns: its result is admitted while the process budget is still full, which
        // only works because the reservation it was made under is transferred onto the fact.
        for (index, operation) in operations.iter().enumerate() {
            let sink = &sinks[index];
            let mut write = visible_input_ticket(&sink.0.thread.id, 2, &format!("input-{index}"))?;
            let input = Arc::make_mut(&mut write.checkpoint.state.inputs)
                .first_mut()
                .unwrap();
            input.accepted_sequence = 1;
            input.ordinal = 1;
            Arc::make_mut(&mut write.effect).inputs = Arc::from([InputChange::Transition {
                id: input.input.id.clone(),
                revision: input.revision,
                state: input.state.clone(),
            }]);
            write.output_claim = Some(operation.clone());
            sink.admit(&sink.0.thread.id, write)
                .expect("the reservation funds the fact it was made for");
        }
        assert_eq!(
            channel.process_bytes.load(Ordering::Acquire),
            MAX_HISTORY_PROCESS_BYTES,
            "transferring a reservation onto a fact adds no second charge for the same output"
        );

        // Recovery: the first call ends, so its remaining ceiling comes back and the very same
        // ticket is admitted unchanged; the rest of the calls end too.
        channel.release_operation_output(&operations[0]);
        sink.admit(&sink.0.thread.id, uncovered)?;
        for (sink, operation) in sinks.iter().zip(&operations).skip(1) {
            sink.0.channel.release_operation_output(operation);
        }

        // The Thread's own projection owner hands the admitted facts over in admission order, which
        // is what lets the writer save them; then the fixed fault generation is retried and every
        // fact is durable.
        for (index, sink) in sinks.iter().enumerate() {
            let mut projection = live_projection(sink).await?;
            while let Some(write) = sink.0.channel.next_unprojected() {
                let mut prepared = projection
                    .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
                    .await?;
                projection
                    .publish_prepared(&sink.0.chat, &mut prepared)
                    .await?;
                assert!(sink.0.channel.prepare(prepared));
            }
            // A real subsequent checkpoint releases the last input reference. Its pending
            // identity charge still survives until the writer confirms the actual transaction.
            let target = if index == 0 { 4 } else { 3 };
            drive_live_projection(
                &mut projection,
                &sink.0.chat,
                sink,
                &sink.0.thread.id,
                ticket(&sink.0.thread.id, target),
            )
            .await?;
        }
        // Force the late-retry ordering: QueueFull allows the writer to commit
        // the fixed target before the explicit recovery request is accepted.
        let mut drained = channel.subscribe();
        await_durable(
            Duration::from_secs(10),
            "parallel reservations durable before retry",
            async {
                loop {
                    let status = drained.borrow_and_update().clone();
                    if status.committed_sequence == 4 && status.queued_records == 0 {
                        break;
                    }
                    drained.changed().await?;
                }
                Ok::<(), anyhow::Error>(())
            },
            || channel_facts(sink),
        )
        .await??;
        {
            let progress = lock_progress(&sink.0);
            assert_eq!(
                progress.fault,
                Some(pl_protocol::studio::HistoryFault::QueueFull)
            );
            assert_eq!(progress.fault_generation, refused.fault_generation);
            assert_eq!(progress.fault_target, 3);
            assert!(progress.published_revision >= progress.fault_target);
            assert!(!progress.retry_requested);
        }
        await_durable(
            Duration::from_secs(10),
            "parallel reservations recover already-durable target",
            store
                .thread_persistence()
                .retry_history(&sink.0.thread.id, refused.fault_generation),
            || channel_facts(sink),
        )
        .await??;
        assert!(
            store.thread_persistence().snapshot().error.is_none(),
            "all live writer reports must reflect the recovered shared fault"
        );
        for (index, sink) in sinks.iter().enumerate() {
            let target = if index == 0 { 4 } else { 3 };
            sink.flush(&sink.0.thread.id, target).await?;
            assert_eq!(
                store.history(&sink.0.thread.id).await?.watermark().await?,
                target
            );
            let drained = sink.0.channel.subscribe().borrow().clone();
            assert!(drained.error.is_none() && drained.fault.is_none());
            sink.0.channel.stop_and_join().await?;
        }
        assert_eq!(
            process_bytes.load(Ordering::Acquire),
            baseline,
            "once every fact is durable and every call ended, the process gauge is back to baseline"
        );
        drop(overlapping);
        Ok(())
    }

    #[tokio::test]
    async fn queue_pressure_keeps_the_original_ticket_until_retry_and_commit() -> Result<()> {
        let (_temp, store, sink) = sink("queue-pressure").await?;
        let write = ticket("queue-pressure", 1);
        sink.0
            .channel
            .process_bytes
            .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
        assert!(sink.admit("queue-pressure", write.clone()).is_err());
        let fault = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(
            fault.fault,
            Some(pl_protocol::studio::HistoryFault::QueueFull)
        );
        assert_eq!(fault.admitted_sequence, 0);
        assert_eq!(fault.queued_records, 0);
        sink.0.channel.process_bytes.store(0, Ordering::Release);
        sink.admit("queue-pressure", write)?;
        assert!(sink.flush("queue-pressure", 1).await.is_err());
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("queue-pressure", fault.fault_generation),
        )
        .await??;
        assert_eq!(store.history("queue-pressure").await?.watermark().await?, 1);
        let recovered = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(recovered.queued_records, 0);
        assert_eq!(recovered.fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn sqlite_rejection_retains_the_real_writer_queue_until_recovery() -> Result<()> {
        let (_temp, store, sink) = sink("sqlite-rejection").await?;
        sink.admit("sqlite-rejection", ticket("sqlite-rejection", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("sqlite-rejection", 1),
            || channel_facts(&sink),
        )
        .await??;
        let path = store
            .session_paths("project-test", "sqlite-rejection")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled writer rejection'); END",
        )
        .await?;
        let mut status = sink.0.channel.subscribe();
        sink.admit("sqlite-rejection", ticket("sqlite-rejection", 2))?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        assert_eq!(failed.queued_records, 1);
        assert_eq!(
            store.history("sqlite-rejection").await?.watermark().await?,
            1
        );
        assert!(sink.flush("sqlite-rejection", 2).await.is_err());
        db.execute_unprepared("DROP TRIGGER reject_history").await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("sqlite-rejection", failed.fault_generation),
        )
        .await??;
        assert_eq!(
            store.history("sqlite-rejection").await?.watermark().await?,
            2
        );
        let recovered = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(recovered.queued_records, 0);
        assert_eq!(recovered.fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn execution_index_durable_background_ack_replayed_with_other_drafts_after_reclamation()
    -> Result<()> {
        use pl_core::{
            context::{ContextRecord, ContextSnapshot, ContextSource},
            thread::{
                journal::ContextChange,
                task::{TaskAcknowledgement, TaskRecord},
            },
        };
        for cold_projection in [false, true] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let id = if cold_projection {
                "ack-cold-replay"
            } else {
                "ack-reclaimed-replay"
            };
            register_test_thread(&store, &test_thread(id)).await?;
            let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
            let chat = store.chat_session(id).await?;
            let history = store.history(id).await?;
            let index = sink.0.channel.order_index();
            let mut projection = live_projection(&sink).await?;
            let call_id = "background-call";
            let tool_id = "background-tool";
            let turn_id = "background-turn";
            let receipt_id = "task-receipt";
            let task = TaskRecord {
                id: format!("task:{call_id}"),
                call_id: call_id.into(),
                tool_id: tool_id.into(),
                turn_id: turn_id.into(),
                revision: 2,
                status: TaskStatus::Running,
                cancel_requested: false,
                started_sequence: Some(1),
                acknowledgement: Some(TaskAcknowledgement {
                    record_id: receipt_id.into(),
                    context_revision: 1,
                }),
            };
            let context = ContextSnapshot {
                revision: 1,
                records: Arc::from([
                    ContextRecord {
                        id: "assistant-call".into(),
                        turn_id: Some(turn_id.into()),
                        source: ContextSource::Assistant,
                        content: vec![],
                        tool_calls: vec![ModelToolCall {
                            rejection: None,
                            call_id: call_id.into(),
                            tool_id: tool_id.into(),
                            arguments: OpaquePayload::text("background arguments"),
                        }],
                    },
                    ContextRecord {
                        id: receipt_id.into(),
                        turn_id: Some(turn_id.into()),
                        source: ContextSource::ToolResult {
                            call_id: call_id.into(),
                            tool_id: tool_id.into(),
                        },
                        content: vec![ContextContent::Text {
                            text: Arc::from(format!(
                                "Task {} is running. Its result will be delivered when execution finishes.",
                                task.id
                            )),
                        }],
                        tool_calls: vec![],
                    },
                ]),
            };
            assert!(context.pending_calls()?.is_empty());
            let mut initial = ticket(id, 1);
            initial.checkpoint.state.context = context.clone();
            initial.checkpoint.state.tasks = BTreeMap::from([(task.id.clone(), task.clone())]);
            Arc::make_mut(&mut initial.effect).context =
                Some(ContextChange::Replace(context.clone()));
            Arc::make_mut(&mut initial.effect).tasks = Arc::from([task.clone()]);
            let first =
                drive_live_projection(&mut projection, &chat, &sink, id, initial.clone()).await?;
            sink.flush(id, 1).await?;
            let ack_id =
                crate::studio::thread_projection::order::tool_background_started_id(call_id);
            let tool_item_id = crate::studio::thread_projection::order::tool_id(call_id);
            let original_ack = pl_core::chat::ChatHistory::item(&history, &ack_id)
                .await?
                .context("the matching context fact must really save its background ACK")?;
            assert_eq!(first.completions.len(), 1);
            assert_eq!(original_ack.append_seq, 1);
            assert_eq!(chat.durable_seq(), 1);
            let meta = crate::studio::runtime::timeline_content::meta::TimelineMeta::for_item(
                &original_ack,
            )?;
            assert!(
                matches!(meta.descriptor, pl_protocol::TimelineDescriptor::Tool(tool)
                if matches!(tool.state, pl_protocol::TimelineToolState::BackgroundStarted { .. }))
            );
            assert_eq!(
                index.assigned(&ack_id),
                None,
                "the real writer confirmation must retire the ACK index entry"
            );
            assert!(!index.is_sealed(&ack_id));
            let original_tool = history
                .item(&tool_item_id)
                .await?
                .context("saved running tool")?;
            if cold_projection {
                drop(projection);
                sink.0.channel.release_projection_retention();
                projection = live_projection(&sink).await?;
                assert_eq!(projection.retained_bytes(), 0);
            }
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: projection.retained_bytes(),
                    pending: None,
                })?;
            let ceiling = index.inner.lock().unwrap().ceiling;
            let before_head = chat.head_seq();
            let mut replay = visible_input_ticket(id, 2, "after-ack-a")?;
            let mut inputs = vec![
                replay.checkpoint.state.inputs[0].clone(),
                visible_input_ticket(id, 2, "after-ack-b")?
                    .checkpoint
                    .state
                    .inputs[0]
                    .clone(),
            ];
            for (offset, input) in inputs.iter_mut().enumerate() {
                input.state = InputState::Pending;
                input.ordinal += offset as u64;
            }
            replay.checkpoint.state.inputs = inputs.clone().into();
            replay.checkpoint.state.context = context.clone();
            replay.checkpoint.state.tasks = initial.checkpoint.state.tasks.clone();
            let effect = Arc::make_mut(&mut replay.effect);
            effect.inputs = inputs
                .into_iter()
                .map(InputChange::Accepted)
                .collect::<Vec<_>>()
                .into();
            effect.tasks = Arc::from([task.clone()]);
            effect.context = Some(ContextChange::Replace(context.clone()));
            // This is the same acknowledged task and its exact ToolResult context, together
            // with two new completed inputs. No marker or ACK shell is manually installed.
            assert_eq!(
                effect.tasks[0].acknowledgement,
                initial.effect.tasks[0].acknowledgement
            );
            assert!(matches!(&effect.context,
                Some(ContextChange::Replace(replayed)) if replayed == &context));
            let lease = sink.0.channel.step_lock.lock().await;
            sink.admit(id, replay)?;
            assert_eq!(index.inner.lock().unwrap().ceiling, ceiling + 2);
            assert_eq!(index.assigned(&ack_id), None);
            let owed = sink
                .0
                .channel
                .next_unprojected()
                .context("replayed ACK fact is owed")?;
            let before_index = index.retained_bytes();
            let before_process = sink.0.channel.process_bytes.load(Ordering::Acquire);
            let before_thread = sink.pressure(id).thread_bytes;
            let before_projection = projection.retained_bytes();
            let (_, mut prepared) = projection
                .prepare(&sink.0.thread, &owed.effect, &owed.checkpoint.state, false)
                .await?;
            let new_ids = ["after-ack-a".to_owned(), "after-ack-b".to_owned()]
                .into_iter()
                .collect::<std::collections::BTreeSet<_>>();
            let drafts = prepared
                .completion_drafts
                .as_ref()
                .context("publication still owed")?;
            assert_eq!(
                drafts.len(),
                2,
                "a saved ACK must be excluded even without a resident marker"
            );
            assert_eq!(
                drafts
                    .iter()
                    .map(|draft| draft.item_id.clone())
                    .collect::<std::collections::BTreeSet<_>>(),
                new_ids
            );
            assert_eq!(index.assigned(&ack_id), None);
            assert_eq!(index.inner.lock().unwrap().ceiling, ceiling + 2);
            assert_eq!(index.retained_bytes(), before_index);
            assert_eq!(
                sink.0.channel.process_bytes.load(Ordering::Acquire),
                before_process
            );
            assert!(prepared.items.iter().all(|item| item.ordinal > 0));
            let tool = prepared
                .items
                .iter()
                .find(|item| item.id == tool_item_id)
                .unwrap();
            assert_eq!(tool.ordinal, original_tool.ordinal);
            assert_eq!(tool.revision, original_tool.revision);
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: projection.retained_bytes(),
                    pending: Some(PendingProjectionRetention {
                        sequence: prepared.sequence,
                        prepared_bytes: prepared.retained_bytes(),
                    }),
                })?;
            assert_eq!(
                sink.pressure(id).thread_bytes,
                before_thread - before_projection
                    + projection.retained_bytes()
                    + prepared.retained_bytes()
            );
            projection.publish_prepared(&chat, &mut prepared).await?;
            assert_eq!(prepared.completions.len(), 2);
            assert_eq!(
                prepared
                    .completions
                    .iter()
                    .map(|item| item.item_id.clone())
                    .collect::<std::collections::BTreeSet<_>>(),
                new_ids
            );
            for (offset, item) in prepared.completions.iter().enumerate() {
                assert_eq!(item.append_seq, before_head + offset as u64 + 1);
                assert_ne!(item.item_id, ack_id);
            }
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: projection.retained_bytes(),
                    pending: Some(PendingProjectionRetention {
                        sequence: prepared.sequence,
                        prepared_bytes: prepared.retained_bytes(),
                    }),
                })?;
            assert!(sink.0.channel.prepare(prepared));
            sink.0
                .channel
                .set_projection_retention(ProjectionRetention {
                    resident_bytes: projection.retained_bytes(),
                    pending: None,
                })?;
            drop(lease);
            sink.flush(id, 2).await?;
            assert_eq!(chat.head_seq(), before_head + 2);
            assert_eq!(chat.durable_seq(), before_head + 2);
            assert_eq!(history.watermark().await?, 2);
            assert_eq!(
                pl_core::chat::ChatHistory::item(&history, &ack_id).await?,
                Some(original_ack)
            );
            assert_eq!(index.assigned(&ack_id), None);
            assert_eq!(index.inner.lock().unwrap().ceiling, ceiling + 2);
            sink.0.channel.release_projection_retention();
            sink.0.channel.stop_and_join().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn concurrent_tool_results_survive_a_real_writer_failure_without_reexecution()
    -> Result<()> {
        let (_temp, store, sink) = sink("concurrent-results").await?;
        let requests = Arc::new(AtomicUsize::new(0));
        let thread = ThreadHandle::start(
            "concurrent-results".into(),
            DynModelSession::new(ConcurrentModel(requests.clone())),
        )?;
        let (started, mut starts) = mpsc::unbounded_channel();
        let executions = Arc::new(Mutex::new(Vec::new()));
        let releases: Vec<_> = (0..2).map(|_| Arc::new(Notify::new())).collect();
        thread
            .register_tools(
                ["first", "second"]
                    .into_iter()
                    .zip(releases.iter())
                    .map(|(id, release)| {
                        Registration::new(
                            id.into(),
                            OpaquePayload::text(format!("Tool {id}")),
                            ConcurrentTool {
                                started: started.clone(),
                                release: release.clone(),
                                executions: executions.clone(),
                            },
                        )
                    })
                    .collect::<Result<Vec<_>, _>>()?,
            )
            .await?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        let turn = TurnInput {
            turn_id: "both-running".into(),
            attempt_prefix: "both-running".into(),
            content: vec![ContextContent::Text {
                text: Arc::from("start"),
            }],
            max_model_steps: ModelStepLimit::Limited(1.try_into()?),
            cancellation: CancellationToken::new(),
        };
        let runner = tokio::spawn({
            let thread = thread.clone();
            async move { thread.run_turn(turn).await }
        });
        tokio::time::timeout(Duration::from_secs(10), async {
            let mut started = [starts.recv().await, starts.recv().await];
            started.sort();
            assert_eq!(started, [Some("first".into()), Some("second".into())]);
        })
        .await?;
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), runner)
                .await???
                .outcome,
            TurnOutcome::StepLimit
        );
        thread.flush().await?;
        let baseline = store
            .history("concurrent-results")
            .await?
            .watermark()
            .await?;
        let chat = store.chat_session("concurrent-results").await?;
        let started_head = chat.head_seq();
        let history = store.history("concurrent-results").await?;
        for call_id in ["first", "second"] {
            let receipt_id =
                crate::studio::thread_projection::order::tool_background_started_id(call_id);
            let receipt = pl_core::chat::ChatHistory::item(&history, &receipt_id)
                .await?
                .context("acknowledged background call must publish its own completion")?;
            let meta =
                crate::studio::runtime::timeline_content::meta::TimelineMeta::for_item(&receipt)?;
            let pl_protocol::TimelineDescriptor::Tool(tool) = meta.descriptor else {
                anyhow::bail!("background receipt lost its tool descriptor");
            };
            assert!(matches!(
                tool.state,
                pl_protocol::TimelineToolState::BackgroundStarted { .. }
            ));
            assert_eq!(
                tool.invocation.task_id.as_deref(),
                Some(format!("task:{call_id}").as_str())
            );
            assert!(
                pl_core::chat::ChatHistory::item(
                    &history,
                    &crate::studio::thread_projection::order::tool_id(call_id),
                )
                .await?
                .is_none(),
                "a running background result is not a completion"
            );
        }
        let path = store
            .session_paths("project-test", "concurrent-results")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled concurrent rejection'); END",
        )
        .await?;

        for release in &releases {
            release.notify_one();
        }
        let mut snapshots = thread.subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let snapshot = snapshots.next().await.unwrap();
                if snapshot.terminal_tasks.len()
                    + snapshot
                        .tasks
                        .values()
                        .filter(|task| task.status != TaskStatus::Running)
                        .count()
                    == 2
                {
                    break;
                }
            }
        })
        .await?;
        let mut status = sink.0.channel.subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        assert!(failed.queued_records >= 2);
        assert_eq!(
            store
                .history("concurrent-results")
                .await?
                .watermark()
                .await?,
            baseline
        );
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        assert_eq!(*executions.lock().unwrap(), ["first", "second"]);

        db.execute_unprepared("DROP TRIGGER reject_history").await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("concurrent-results", failed.fault_generation),
        )
        .await??;
        thread.flush().await?;
        let history = store.history("concurrent-results").await?;
        assert_eq!(
            history.watermark().await?,
            thread.snapshot().commit_sequence
        );
        for id in ["first", "second"] {
            let fact = history.tool_task(&format!("task:{id}")).await?.unwrap();
            assert_eq!(fact.task.call_id, id);
            assert_eq!(fact.delivery.unwrap().call_id, id);
            let completion = pl_core::chat::ChatHistory::item(
                &history,
                &crate::studio::thread_projection::order::tool_id(id),
            )
            .await?
            .context("finished background call must publish its separate final result")?;
            assert!(completion.append_seq > started_head);
        }
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        assert_eq!(executions.lock().unwrap().len(), 2);
        thread.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn committed_batch_is_replayed_after_ack_is_lost() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("lost-ack")).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread("lost-ack"), None).await?;
        // The Thread's projection owner hands the batch over before the writer may write it. The test
        // drives that one write directly, under the step lock, so it can lose the acknowledgement while
        // the queue entry stays — exactly the retry the writer has to make idempotent.
        let write = visible_input_ticket("lost-ack", 1, "replayed-completion")?;
        let bytes = encoded_bytes(&write.effect);
        let chat = store.chat_session("lost-ack").await?;
        let mut projection = live_projection(&sink).await?;
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        let locked = sink.0.channel.step_lock.lock().await;
        sink.admit("lost-ack", write.clone())?;
        assert!(sink.0.channel.prepare(prepared.clone()));
        assert!(sink.0.channel.prepare(prepared.clone()));
        assert!(
            !sink.0.channel.prepare(Arc::new((*prepared).clone())),
            "a second preparation must not replace the frozen queued batch"
        );
        persist_effect(&sink.0, 1, &write, &prepared, bytes).await?;
        assert_eq!(
            lock_progress(&sink.0).effect_bytes,
            bytes,
            "a committed but unacknowledged queue entry still owns its effect bytes"
        );
        assert_eq!(chat.durable_seq(), 1);
        assert_eq!(store.history("lost-ack").await?.watermark().await?, 1);
        assert_eq!(
            pl_core::chat::ChatHistory::latest_append_seq(&store.history("lost-ack").await?)
                .await?,
            1,
            "retry must not append a second completion"
        );
        assert_eq!(sink.0.channel.subscribe().borrow().queued_records, 1);
        sink.0.channel.mark_unavailable(|| true);
        let unavailable = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(
            unavailable.fault,
            Some(pl_protocol::studio::HistoryFault::WriterUnavailable)
        );
        assert!(sink.flush("lost-ack", 1).await.is_err());
        drop(locked);
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("lost-ack", unavailable.fault_generation),
        )
        .await??;
        assert_eq!(store.history("lost-ack").await?.watermark().await?, 1);
        let status = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(status.queued_records, 0);
        assert_eq!(status.fault, None);
        assert_eq!(lock_progress(&sink.0).effect_bytes, 0);
        let mut persistence = store.thread_persistence().subscribe();
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let row = store
                    .thread_persistence()
                    .queue_snapshot()
                    .threads
                    .into_iter()
                    .find(|row| row.thread_id == "lost-ack")
                    .context("missing live Thread persistence row")?;
                if row.history_admitted_sequence == Some(1)
                    && row.history_durable_sequence == Some(1)
                {
                    break Ok::<_, anyhow::Error>(());
                }
                persistence.changed().await?;
            }
        })
        .await??;
        Ok(())
    }

    #[tokio::test]
    async fn completion_confirmation_does_not_acknowledge_a_later_published_batch() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("completion-prefix")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("completion-prefix"), None).await?;
        let chat = store.chat_session("completion-prefix").await?;
        let lease = sink.0.channel.step_lock.lock().await;
        let mut projection = live_projection(&sink).await?;
        let mut batches = Vec::new();
        for (sequence, input_id) in [(1, "first-completion"), (2, "later-completion")] {
            let write = visible_input_ticket("completion-prefix", sequence, input_id)?;
            let mut prepared = projection
                .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
                .await?;
            projection.publish_prepared(&chat, &mut prepared).await?;
            sink.admit("completion-prefix", write.clone())?;
            assert!(sink.0.channel.prepare(prepared.clone()));
            batches.push((write, prepared));
        }
        assert_eq!(chat.head_seq(), 2);
        assert_eq!(chat.durable_seq(), 0);
        persist_effect(
            &sink.0,
            1,
            &batches[0].0,
            &batches[0].1,
            encoded_bytes(&batches[0].0.effect),
        )
        .await?;
        assert_eq!(
            chat.durable_seq(),
            1,
            "the Session head is not a save receipt"
        );
        let history = store.history("completion-prefix").await?;
        assert!(
            pl_core::chat::ChatHistory::item(&history, "later-completion")
                .await?
                .is_none()
        );
        let visible = chat.page(pl_core::chat::ChatPageRequest::latest()).await?;
        assert_eq!(
            visible
                .items
                .iter()
                .map(|item| item.item_id.as_str())
                .collect::<Vec<_>>(),
            ["first-completion", "later-completion"],
            "a later published completion stays queryable while only the first is durable"
        );
        drop(lease);
        sink.flush("completion-prefix", 2).await?;
        assert_eq!(chat.durable_seq(), 2);
        Ok(())
    }

    /// A rejected commit rolls back the effect's history, its latest context and its checkpoint
    /// together, so the writer never advances the history watermark to a revision whose checkpoint
    /// the very same transaction failed to store — the atomicity the old split write could not give.
    #[tokio::test]
    async fn a_rejected_atomic_commit_never_advances_history_without_its_checkpoint() -> Result<()>
    {
        let (_temp, store, sink) = sink("atomic-failure").await?;
        // Commit one effect first so the history database exists, then reject the second one's whole
        // transaction from the watermark update that every atomic commit performs.
        sink.admit("atomic-failure", ticket("atomic-failure", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("atomic-failure", 1),
            || channel_facts(&sink),
        )
        .await??;
        let path = store
            .session_paths("project-test", "atomic-failure")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_watermark BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled atomic rejection'); END",
        )
        .await?;
        let mut status = sink.0.channel.subscribe();
        let chat = store.chat_session("atomic-failure").await?;
        sink.admit(
            "atomic-failure",
            visible_input_ticket("atomic-failure", 2, "pending-completion")?,
        )?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        // Nothing of the rejected revision is durable: the watermark stays on the previously
        // committed effect and the effect is retained in order for retry.
        assert_eq!(failed.committed_sequence, 1);
        assert_eq!(failed.queued_records, 1);
        assert_eq!(store.history("atomic-failure").await?.watermark().await?, 1);
        assert_eq!(chat.head_seq(), 1);
        assert_eq!(chat.durable_seq(), 0);
        assert!(
            pl_core::chat::ChatHistory::item(
                &store.history("atomic-failure").await?,
                "pending-completion",
            )
            .await?
            .is_none(),
            "rejected transaction must roll back timeline_records too"
        );
        let pending_budget = sink.0.channel.subscribe().borrow().queued_bytes;
        assert!(
            pending_budget > 0,
            "pending completion stays in the reliable budget"
        );
        assert!(sink.flush("atomic-failure", 2).await.is_err());
        db.execute_unprepared("DROP TRIGGER reject_watermark")
            .await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("atomic-failure", failed.fault_generation),
        )
        .await??;
        assert_eq!(store.history("atomic-failure").await?.watermark().await?, 2);
        assert_eq!(chat.durable_seq(), 1);
        assert!(
            pl_core::chat::ChatHistory::item(
                &store.history("atomic-failure").await?,
                "pending-completion",
            )
            .await?
            .is_some()
        );
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn missing_blob_blocks_checkpoint_until_the_same_attachment_is_durable() -> Result<()> {
        use pl_core::context::ResourceReader as _;
        use sha2::Digest as _;

        let (temp, store, sink) = sink("blob-fence").await?;
        let session = store.session_paths("project-test", "blob-fence")?;
        let source = temp.path().join("attachment-draft");
        let bytes = b"restored";
        tokio::fs::write(&source, bytes).await?;
        let draft = crate::studio::store::attachment::AttachmentDraftObject {
            draft_id: "draft-1".to_owned(),
            modality: pl_protocol::studio::StudioAttachmentModality::File,
            media_type: "text/plain".to_owned(),
            filename: "attachment.txt".to_owned(),
            storage_path: source,
            byte_size: bytes.len() as u64,
            content_sha256: hex::encode(sha2::Sha256::digest(bytes)),
            width: None,
            height: None,
            initial_remote_url: None,
        };
        let attachment = store
            .promote_attachment_drafts("blob-fence", &[draft])
            .await?
            .pop()
            .context("promoted attachment is missing")?;
        let reference = store.retain_attachment_resource(&attachment).await?;
        let blob = session.root().join(&attachment.blob_relative_path);
        tokio::fs::remove_file(&blob).await?;
        let resources = crate::resource_store::FileResourceStore::new(session.resources_dir());
        assert_eq!(
            resources
                .read(reference, tokio_util::sync::CancellationToken::new())
                .await?
                .as_ref(),
            bytes
        );
        store.record_attachments(vec![attachment.clone()]).await?;
        let mut status = sink.0.channel.subscribe();
        sink.admit(
            "blob-fence",
            ticket_referencing_attachment("blob-fence", &attachment)?,
        )?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let failed = status.borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::BlobFailed)
        );
        // The blob fence runs before the atomic commit, so the missing blob blocks both the effect's
        // history and its checkpoint: the watermark stays untouched until the blob is durable.
        assert_eq!(failed.committed_sequence, 0);
        assert_eq!(failed.queued_records, 1);
        assert!(sink.flush("blob-fence", 1).await.is_err());
        tokio::fs::create_dir_all(blob.parent().expect("blob has a parent")).await?;
        tokio::fs::write(&blob, bytes).await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("blob-fence", failed.fault_generation),
        )
        .await??;
        assert_eq!(store.history("blob-fence").await?.watermark().await?, 1);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        Ok(())
    }

    #[tokio::test]
    async fn closing_the_chat_and_sink_does_not_release_pending_history() -> Result<()> {
        let (_temp, store, sink) = sink("closed-view").await?;
        sink.admit("closed-view", ticket("closed-view", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("closed-view", 1),
            || channel_facts(&sink),
        )
        .await??;
        let chat = store.chat_session("closed-view").await?;
        let path = store
            .session_paths("project-test", "closed-view")?
            .root()
            .join("history.sqlite");
        let db = Database::connect(
            crate::studio::paths::sqlite_file_options(
                &path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared(
            "CREATE TRIGGER reject_history BEFORE UPDATE OF applied_write_seq ON history_meta \
             BEGIN SELECT RAISE(ABORT, 'controlled closed-view rejection'); END",
        )
        .await?;
        let channel = store.thread_persistence().history_channel("closed-view");
        let mut updates = channel.subscribe();
        sink.admit("closed-view", ticket("closed-view", 2))?;
        tokio::time::timeout(Duration::from_secs(5), async {
            while updates.borrow_and_update().fault.is_none() {
                updates.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        })
        .await??;
        let generation = updates.borrow().fault_generation;
        drop(chat);
        drop(sink);
        assert_eq!(channel.subscribe().borrow().queued_records, 1);
        assert_eq!(store.history("closed-view").await?.watermark().await?, 1);
        db.execute_unprepared("DROP TRIGGER reject_history").await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            store
                .thread_persistence()
                .retry_history("closed-view", generation),
        )
        .await??;
        assert_eq!(store.history("closed-view").await?.watermark().await?, 2);
        assert_eq!(channel.subscribe().borrow().queued_records, 0);
        Ok(())
    }

    #[tokio::test]
    async fn stopped_statistics_consumer_never_blocks_history_or_checkpoint() -> Result<()> {
        let (temp, store, sink) = sink("statistics-gap").await?;
        let calls_before = store.calls().metrics();
        let materials_before = store.calls().subscribe_materials().borrow().clone();
        store.calls().stop_best_effort();
        sink.admit("statistics-gap", ticket("statistics-gap", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("statistics-gap", 1),
            || channel_facts(&sink),
        )
        .await??;
        assert_eq!(store.history("statistics-gap").await?.watermark().await?, 1);
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        assert_eq!(store.calls().metrics(), calls_before);
        assert_eq!(
            *store.calls().subscribe_materials().borrow(),
            materials_before
        );
        assert!(!store.thread_persistence().queue_snapshot().statistics_gap);

        // A real committed absolute Summary still has a handoff obligation. The history owner
        // keeps its bounded retries through shutdown, without a per-Thread calls observer.
        let accounting = store
            .history("statistics-gap")
            .await?
            .accounting()
            .await?
            .context("committed accounting")?;
        submit_accounting(&sink.0, accounting);
        assert!(lock_progress(&sink.0).pending_accounting.is_some());
        tokio::time::timeout(Duration::from_secs(5), sink.0.channel.stop_and_join()).await??;
        assert!(lock_progress(&sink.0).pending_accounting.is_none());
        assert!(store.calls().statistics_gap());
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        store.thread_persistence().report_calls(store.calls());
        assert!(store.thread_persistence().queue_snapshot().statistics_gap);
        // Later material-free work cannot erase a real rejection.
        store
            .calls()
            .record_effect(&ticket("statistics-gap", 2).effect);
        assert!(store.calls().statistics_gap());
        drop(sink);
        store.close().await?;
        let reopened = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let history = reopened.history("statistics-gap").await?;
        assert_eq!(history.watermark().await?, 1);
        assert_eq!(
            history
                .checkpoint()
                .await?
                .context("checkpoint")?
                .history_fence,
            1
        );
        reopened.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn crashed_statistics_consumer_does_not_block_history_and_restarts() -> Result<()> {
        let (_temp, store, sink) = sink("statistics-crash").await?;
        let calls = store.calls();
        let summary = |revision| super::super::calls::SessionUsageProjection {
            root_thread_id: "statistics-crash".into(),
            thread_id: "statistics-crash".into(),
            revision,
            has_unpriced_usage: false,
            purpose_costs: vec![],
        };
        calls.panic_on_next_mutation();
        calls.replace_session_usage(summary(1))?;
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if calls
                    .last_error()
                    .is_some_and(|message| message.contains("terminated unexpectedly"))
                {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("call writer did not report the injected worker exit")?;
        assert!(calls.statistics_gap());
        let dropped_ticket = calls.admitted_ticket();
        calls.replace_session_usage(summary(2))?;
        let resumed_ticket = calls.admitted_ticket();
        assert!(resumed_ticket > dropped_ticket);

        sink.admit("statistics-crash", ticket("statistics-crash", 1))?;
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 1),
            sink.flush("statistics-crash", 1),
            || channel_facts(&sink),
        )
        .await
        .context("history flush stalled after the call writer exit")??;
        assert_eq!(
            store.history("statistics-crash").await?.watermark().await?,
            1
        );
        assert_eq!(sink.0.channel.subscribe().borrow().fault, None);
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if calls.processed_ticket() >= resumed_ticket {
                    break;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("call writer did not advance the resumed ticket")?;
        assert!(calls.statistics_gap());
        Ok(())
    }

    #[tokio::test]
    async fn recovery_rechecks_new_faults_and_stop_after_the_channel_clears() -> Result<()> {
        for stopping in [false, true] {
            let id = if stopping {
                "recovery-stop"
            } else {
                "recovery-new-generation"
            };
            let (_temp, store, sink) = sink(id).await?;
            let channel = &sink.0.channel;
            channel
                .process_bytes
                .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
            let first = ticket(id, 1);
            assert!(sink.admit(id, first.clone()).is_err());
            let failed = channel.subscribe().borrow().clone();
            let generation = failed.fault_generation;
            channel.process_bytes.store(0, Ordering::Release);
            sink.admit(id, first)?;
            let (entered, release) = store.thread_persistence().pause_retry_before_reports();
            let coordinator = store.thread_persistence().clone();
            let recovery =
                tokio::spawn(async move { coordinator.retry_history(id, generation).await });
            tokio::time::timeout(Duration::from_secs(5), entered).await??;
            if stopping {
                // Keep this owner's pre-commit report visible while its observer is
                // being cancelled. The worker's final report must discharge it.
                store.thread_persistence().report(
                    id,
                    sink.0.owner,
                    ThreadPersistenceReport {
                        pending: vec![1],
                        pending_checkpoint: false,
                        error: failed.error,
                        metrics: ThreadPersistenceMetrics {
                            fault_generation: generation,
                            fault: failed.fault,
                            state_dirty_revision: 1,
                            history_admitted_sequence: 1,
                            pending_operations: 1,
                            ..Default::default()
                        },
                    },
                    Some(store.calls()),
                );
                channel.stop_and_join().await?;
            } else {
                channel
                    .process_bytes
                    .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
                assert!(sink.admit(id, ticket(id, 2)).is_err());
                channel.process_bytes.store(0, Ordering::Release);
            }
            release
                .send(())
                .map_err(|_| anyhow::anyhow!("recovery check lost its owner"))?;
            let error = tokio::time::timeout(Duration::from_secs(5), recovery)
                .await??
                .expect_err("a changed recovery boundary must not return success");
            if stopping {
                assert!(error.to_string().contains("stopping"));
            } else {
                assert!(error.to_string().contains("generation changed"));
                let next = channel.subscribe().borrow().fault_generation;
                assert!(next > generation);
                sink.admit(id, ticket(id, 2))?;
                tokio::time::timeout(
                    Duration::from_secs(5),
                    store.thread_persistence().retry_history(id, next),
                )
                .await??;
                channel.stop_and_join().await?;
            }
            assert!(store.thread_persistence().snapshot().error.is_none());
        }
        Ok(())
    }

    #[tokio::test]
    async fn empty_queue_retry_does_not_clear_a_ticket_contract_failure() -> Result<()> {
        let (_temp, store, sink) = sink("ticket-contract").await?;
        assert!(
            sink.admit("ticket-contract", ticket("another-thread", 1))
                .is_err()
        );
        let failed = sink.0.channel.subscribe().borrow().clone();
        assert_eq!(
            failed.fault,
            Some(pl_protocol::studio::HistoryFault::WriteFailed)
        );
        assert_eq!(failed.queued_records, 0);
        sink.0.channel.retry(failed.fault_generation)?;
        // Exercise the worker after the retry, with equal zero watermarks but no
        // successful write that could repair the rejected ticket's contract.
        assert!(matches!(step(&sink.0).await?, Step::Idle));
        let pressure = sink.pressure("ticket-contract");
        assert!(pressure.error.is_some());
        assert_eq!(
            pressure.fault,
            Some(pl_core::thread::cold::StorageFaultKind::WriteFailed)
        );
        assert_eq!(pressure.recovered_generation, None);
        assert_eq!(
            store.history("ticket-contract").await?.watermark().await?,
            0
        );
        Ok(())
    }

    #[tokio::test]
    async fn stale_fault_generation_cannot_resume_a_new_queue_failure() -> Result<()> {
        let (_temp, store, sink) = sink("fault-generation").await?;
        for sequence in [1, 2] {
            sink.0
                .channel
                .process_bytes
                .store(MAX_HISTORY_PROCESS_BYTES, Ordering::Release);
            let write = ticket("fault-generation", sequence);
            assert!(sink.admit("fault-generation", write.clone()).is_err());
            let failed = sink.0.channel.subscribe().borrow().clone();
            assert_eq!(failed.fault_generation, sequence);
            if sequence == 2 {
                assert!(sink.0.channel.retry(1).is_err());
                assert_eq!(sink.0.channel.subscribe().borrow().fault_generation, 2);
            }
            sink.0.channel.process_bytes.store(0, Ordering::Release);
            sink.admit("fault-generation", write)?;
            tokio::time::timeout(
                Duration::from_secs(5),
                store
                    .thread_persistence()
                    .retry_history("fault-generation", sequence),
            )
            .await??;
        }
        assert_eq!(
            store.history("fault-generation").await?.watermark().await?,
            2
        );
        Ok(())
    }

    /// The continue entry the UI reads is exactly the Thread owner's readiness, with nothing else
    /// able to light it.
    ///
    /// The writer reports watermarks and the typed fault generation, but no readiness of its own:
    /// the owner can still owe a newer fault while a writer has long since written an older retry, so
    /// the projection takes the owner's single verdict — byte for byte — instead of combining
    /// anything a writer reports. `resume_required` stays a separate fact: readiness never releases
    /// the latch by itself.
    #[test]
    fn can_resume_is_exactly_the_owners_readiness() {
        use crate::studio::thread_projection::storage_state;

        let mut owner = ThreadSnapshot::default();
        owner.persistence.resume_required = true;
        owner.persistence.fault_generation = 2;

        // A writer that is already past this generation's fault — it reports the same generation with
        // no error and fully admitted watermarks — still cannot offer a continue the owner refuses.
        let writer = pl_protocol::ThreadPersistenceSnapshot {
            fault_generation: 2,
            history_admitted_sequence: Some(9),
            history_durable_sequence: Some(9),
            last_error: None,
            ..pl_protocol::ThreadPersistenceSnapshot::default()
        };
        let storage = storage_state(&owner, &writer);
        assert!(storage.resume_required);
        assert!(
            !storage.can_resume,
            "only the owner's own generation-matched readiness may enable the continue"
        );
        assert_eq!(
            storage.accepted_sequence,
            Some(9),
            "the writer's own watermarks still reach the UI as facts"
        );

        // The owner's verified readiness is the fact, whatever else the writer reports.
        owner.persistence.resume_ready = true;
        assert!(storage_state(&owner, &writer).can_resume);
    }

    /// One `(identity, content version)` pair is one canonical payload, even when the same fact is
    /// projected a second time.
    ///
    /// The projection owner folds an admitted fact once, but the same effect can legitimately reach
    /// the projection again — a commit the owner's snapshot already carried, a durable step retried
    /// after a real writer failure, or a re-subscription. Every pass must deliver the *same bytes*
    /// for a `(item_id, revision)` pair: a pass that restamped the projection clock would hand the
    /// durable writer two different payloads under one version, which the store's own revision fence
    /// rejects as a real save fault instead of the idempotent rewrite it is. This pins that a repeat
    /// projection reuses the version, placement and timestamps of the payload it already delivered.
    #[tokio::test]
    async fn reprojecting_an_unchanged_effect_keeps_one_canonical_payload() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("stable-payload")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("stable-payload"), None).await?;
        let chat = store.chat_session("stable-payload").await?;
        // The commit sequence is deliberately far above the item's own content version, so a sequence
        // leaking into the version shows up as a value change instead of a coincidence.
        let write = visible_input_ticket("stable-payload", 9, "stable-input")?;
        let mut projection = live_projection(&sink).await?;
        let mut first = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut first).await?;
        let mut second = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut second).await?;
        assert_eq!(
            first.items[0].revision, 1,
            "a first delivery takes the projection's own content version, not the commit sequence"
        );
        assert_eq!(
            serde_json::to_vec(&first.items)?,
            serde_json::to_vec(&second.items)?,
            "a repeat projection of an unchanged fact is byte-identical, so one version never names two payloads"
        );
        Ok(())
    }

    /// The durable row carries the item's own **content version**, never the effect sequence that
    /// committed it, and a cold read of the same history file observes the same value.
    ///
    /// A save receipt is a fact about one exact `(identity, content version)` pair. Substituting the
    /// commit sequence for the version would let an acknowledgement vouch for a payload the store
    /// never wrote, so both ends are pinned here: the shared session confirms exactly the revision
    /// the projection published, and a separate history handle — the cold path, which decodes the
    /// durable row itself instead of reading live projection state — returns that same revision.
    #[tokio::test]
    async fn the_durable_row_keeps_the_items_own_content_version_across_a_cold_read() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread("revision-fence")).await?;
        let sink =
            ThreadStorageSink::new(store.clone(), test_thread("revision-fence"), None).await?;
        let chat = store.chat_session("revision-fence").await?;
        // The commit sequence is deliberately far above the item's first content version: the
        // projection decides the content version, and the writer has to store that exact value.
        let write = visible_input_ticket("revision-fence", 9, "revision-input")?;
        // No test projection task here: the test hands the one fact over itself, exactly like the
        // Thread's observation worker, so the publish/hand-off/confirm order is deterministic.
        let mut projection = live_projection(&sink).await?;
        // Advance through real, contiguous empty commits; a large write sequence cannot be
        // invented independently of the checkpoint's history fence.
        for sequence in 1..9 {
            let seed = ticket("revision-fence", sequence);
            let mut prepared = projection
                .prepare_committed(&sink.0.thread, &seed.effect, &seed.checkpoint.state)
                .await?;
            projection.publish_prepared(&chat, &mut prepared).await?;
            sink.admit("revision-fence", seed)?;
            sink.0.channel.prepare(prepared);
        }
        let mut prepared = projection
            .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        projection.publish_prepared(&chat, &mut prepared).await?;
        // The completion records were published atomically before this handoff: the accepted input
        // is complete at acceptance, so the frozen batch carries it and nothing republishes per
        // item.
        sink.admit("revision-fence", write)?;
        sink.0.channel.prepare(prepared.clone());
        await_durable(
            Duration::from_secs(5),
            &format!("commit {}", 9),
            sink.flush("revision-fence", 9),
            || channel_facts(&sink),
        )
        .await??;

        // The real allocation entry point is pinned, not just "different from the commit sequence":
        // a fresh projection's first delivery of a new identity is that identity's content version 1.
        let published = prepared
            .items
            .iter()
            .find(|item| item.id == "revision-input")
            .context("the accepted input is part of the prepared batch")?;
        assert_eq!(
            published.revision, 1,
            "a first delivery takes the projection's own content version, not the commit sequence"
        );
        assert_ne!(
            published.revision, 9,
            "a content version is the item's own fact, never the commit sequence"
        );
        assert_eq!(prepared.completions.len(), 1);
        assert_eq!(prepared.completions[0].item_id, "revision-input");

        let path = store
            .session_paths("project-test", "revision-fence")?
            .root()
            .join("history.sqlite");
        let cold =
            crate::studio::storage::history::HistoryStore::open(&path, "revision-fence").await?;
        let durable = cold.items_for_turn("visible-turn").await?;
        assert_eq!(durable.len(), 1);
        assert_eq!(durable[0].id, "revision-input");
        assert_eq!(
            durable[0].revision, published.revision,
            "the persisted row carries the same content version the projection allocated"
        );
        Ok(())
    }

    /// The archive duty a real command capture owes after its append failed.
    ///
    /// It re-materializes the accepted chunk through the real local backend and then archives the
    /// fragment with the real content-addressed store, so the reference the retry names is a genuine
    /// durable resource and not a stand-in.
    #[derive(Debug)]
    struct CaptureRepairObligation {
        backend: pl_tool::command::LocalCommandBackend,
        archive: crate::resource_store::FileResourceStore,
        capture_file: std::path::PathBuf,
        call_id: String,
        committed_len: u64,
        pending: Vec<u8>,
        retries: Arc<AtomicUsize>,
    }

    impl pl_core::thread::cold::OutputRetryObligation for CaptureRepairObligation {
        fn identity(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn retry(&self) -> pl_core::thread::cold::OutputRetryFuture<'_> {
            Box::pin(async move {
                self.retries.fetch_add(1, Ordering::SeqCst);
                // The real backend truncates the fragment back to its committed offset and re-appends
                // exactly the accepted chunk with the same framing a successful append would produce,
                // so a repeated retry reproduces the same bytes instead of appending them twice.
                pl_tool::command::CommandBackend::repair_output_chunk(
                    &self.backend,
                    &self.capture_file,
                    pl_tool::command::CommandCaptureStream::Stdout,
                    self.committed_len,
                    &self.pending,
                )
                .await
                .map_err(|error| pl_core::thread::cold::ColdStoreError {
                    source: Box::new(std::io::Error::other(error.to_string())),
                })?;
                let reference = self
                    .archive
                    .retain_command_capture(&self.capture_file)
                    .await
                    .map_err(|error| pl_core::thread::cold::ColdStoreError {
                        source: Box::new(error),
                    })?;
                Ok(pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(
                    pl_core::thread::cold::OutputRepair {
                        call_id: self.call_id.clone(),
                        reference,
                    },
                ))
            })
        }
        fn received_bytes(&self) -> u64 {
            self.committed_len.saturating_add(self.pending.len() as u64)
        }
        fn location(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn kind(&self) -> pl_core::thread::cold::StorageFaultKind {
            pl_core::thread::cold::StorageFaultKind::WriteFailed
        }
    }

    /// A command whose capture append really failed, so its archive still owes the accepted bytes.
    #[derive(Debug)]
    struct FailedAppendCaptureTool {
        backend: pl_tool::command::LocalCommandBackend,
        archive: crate::resource_store::FileResourceStore,
        capture_file: std::path::PathBuf,
        committed_len: u64,
        pending: Vec<u8>,
        retries: Arc<AtomicUsize>,
        created: Arc<Mutex<Vec<Arc<CaptureRepairObligation>>>>,
    }

    impl Tool for FailedAppendCaptureTool {
        async fn execute(
            &self,
            input: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            let obligation = Arc::new(CaptureRepairObligation {
                backend: self.backend.clone(),
                archive: self.archive.clone(),
                capture_file: self.capture_file.clone(),
                call_id: context.call_id.clone(),
                committed_len: self.committed_len,
                pending: self.pending.clone(),
                retries: self.retries.clone(),
            });
            self.created.lock().unwrap().push(obligation.clone());
            let source = pl_core::thread::cold::ColdStoreError {
                source: Box::new(std::io::Error::other("capture append failed")),
            };
            let fault = pl_core::thread::cold::OutputStorageFault::new(
                pl_core::thread::cold::StorageFaultKind::WriteFailed,
                Arc::new(source),
            )
            .with_obligation(obligation);
            Err(ToolError::new(fault).with_output(ToolOutput::new(
                input.clone(),
                vec![ContextContent::Text {
                    text: Arc::from("accepted so far"),
                }],
            )))
        }
    }

    #[derive(Debug)]
    struct CaptureModel;

    impl ModelSession for CaptureModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("calling capture"),
                    }],
                    tool_calls: vec![ModelToolCall {
                        rejection: None,
                        call_id: "capture-1".to_owned(),
                        tool_id: "capture".to_owned(),
                        arguments: OpaquePayload::text("capture"),
                    }],
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    /// The owner facts one stuck wait is diagnosed from, so a timeout names a stage instead of a bare
    /// deadline and a real owner bug is not masked by a longer one.
    fn stage_facts(snapshot: &ThreadSnapshot) -> String {
        format!(
            "fault={:?} generation={} phase={:?} obligations={} resume_required={} resume_ready={} \
             commit={} durable={}",
            snapshot.persistence.fault,
            snapshot.persistence.fault_generation,
            snapshot.persistence.execution_phase,
            snapshot.persistence.output_obligations.len(),
            snapshot.persistence.resume_required,
            snapshot.persistence.resume_ready,
            snapshot.commit_sequence,
            snapshot.persistence.durable_sequence,
        )
    }

    /// A best-effort snapshot of the reliable channel taken when one durable barrier expires.
    ///
    /// It reports the watermarks, the queue, the published fault and the oldest effect no projection
    /// has taken over yet, so an expired budget is accompanied by the facts the wait was measured
    /// against instead of only `deadline has elapsed`. The values are read from live state and may
    /// already reflect concurrent progress: they are not an atomic snapshot of one instant, and
    /// `unprojected` names only the earliest effect that is unprepared at the moment of the read.
    /// Neither its presence nor its absence decides on its own whether a stall came from scheduling,
    /// IO, a lock or a logic defect — those fields are evidence for a later judgement, not a verdict.
    fn channel_facts(sink: &ThreadStorageSink) -> String {
        let channel = &sink.0.channel;
        let facts = {
            let status = channel.subscribe();
            let status = status.borrow();
            format!(
                "durable={} admitted={} queued={} ({} bytes) fault={:?} generation={} error={:?}",
                status.committed_sequence,
                status.admitted_sequence,
                status.queued_records,
                status.queued_bytes,
                status.fault,
                status.fault_generation,
                status.error,
            )
        };
        let unprojected = channel
            .next_unprojected()
            .map(|write| write.effect.sequence);
        format!("{facts} unprojected={unprojected:?}")
    }

    /// Awaits the supplied future under the caller's timeout budget.
    ///
    /// On expiry, appends the caller-provided diagnostic text without inferring a cause.
    async fn await_durable<T>(
        budget: Duration,
        stage: &str,
        future: impl std::future::Future<Output = T>,
        describe: impl FnOnce() -> String,
    ) -> Result<T> {
        match tokio::time::timeout(budget, future).await {
            Ok(value) => Ok(value),
            Err(_) => anyhow::bail!("`{stage}` did not land: {}", describe()),
        }
    }

    /// Waits until the authoritative snapshot satisfies `predicate`, tagging `stage` on timeout.
    ///
    /// The subscription yields the current snapshot first, so a boundary that already landed is observed
    /// without waiting for an unrelated new frame — the exact shape of the earlier hang — and the timeout
    /// reports the stage and the last owner facts so the production cause is located, not hidden.
    async fn await_stage(
        thread: &ThreadHandle,
        stage: &str,
        predicate: impl Fn(&ThreadSnapshot) -> bool,
    ) -> Result<ThreadSnapshot> {
        let mut snapshots = thread.subscribe();
        let reached = tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = snapshots.next().await.expect("thread stays observable");
                if predicate(&snapshot) {
                    return snapshot;
                }
            }
        })
        .await;
        reached.map_err(|_| {
            anyhow::anyhow!(
                "stage `{stage}` was not reached: {}",
                stage_facts(&thread.snapshot())
            )
        })
    }

    /// The reference a repaired capture stored reaches the durable tool result, not just memory.
    ///
    /// The append failed after the fragment already held a partial write, so the retry must repair
    /// the fragment through the real local backend before archiving it: the archived bytes are the
    /// accepted content, verbatim and without duplication. The writer must then record that reference
    /// on the tool identity it was committed under — on the projected item *and* on the delivery
    /// history keeps — so the UI and a cold reopen can both locate the complete output, and the pause
    /// must stay closed until the archive really landed.
    #[tokio::test]
    async fn a_repaired_capture_reference_reaches_the_durable_tool_result() -> Result<()> {
        use pl_core::context::ResourceReader;
        use pl_core::thread::cold::OutputRetryObligation as _;

        let (temp, store, sink) = sink("archive-repair").await?;
        let resources_root = temp.path().join("resources");
        std::fs::create_dir_all(&resources_root)?;
        let archive = crate::resource_store::FileResourceStore::new(resources_root);
        let backend = pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf());

        let capture_file = temp.path().join("capture.fragment");
        let committed = b"accepted line one\n".to_vec();
        let pending = b"accepted line two".to_vec();
        // The failed append left the fragment short of the bytes already accepted and published live:
        // a few bytes of the pending chunk were written, without their framing and without the rest.
        let mut partial = committed.clone();
        partial.extend_from_slice(&pending[..4]);
        std::fs::write(&capture_file, &partial)?;
        let mut expected = committed.clone();
        expected.extend_from_slice(&pending);

        let retries = Arc::new(AtomicUsize::new(0));
        let created: Arc<Mutex<Vec<Arc<CaptureRepairObligation>>>> =
            Arc::new(Mutex::new(Vec::new()));
        let thread =
            ThreadHandle::start("archive-repair".into(), DynModelSession::new(CaptureModel))?;
        thread
            .register_tools(vec![Registration::new(
                "capture".into(),
                OpaquePayload::text("Tool capture"),
                FailedAppendCaptureTool {
                    backend,
                    archive: archive.clone(),
                    capture_file: capture_file.clone(),
                    committed_len: committed.len() as u64,
                    pending: pending.clone(),
                    retries: retries.clone(),
                    created: created.clone(),
                },
            )?])
            .await?;
        thread
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;

        let runner = tokio::spawn({
            let thread = thread.clone();
            async move {
                thread
                    .run_turn(TurnInput {
                        turn_id: "capture-turn".into(),
                        attempt_prefix: "capture".into(),
                        content: vec![ContextContent::Text {
                            text: Arc::from("run capture"),
                        }],
                        max_model_steps: ModelStepLimit::Limited(
                            std::num::NonZeroU32::new(1).expect("positive model step limit"),
                        ),
                        cancellation: CancellationToken::new(),
                    })
                    .await
            }
        });
        let faulted = await_stage(&thread, "typed storage fault latch", |snapshot| {
            snapshot.persistence.resume_required
        })
        .await?;
        assert_eq!(
            faulted.persistence.fault,
            Some(pl_core::thread::cold::StorageFaultKind::WriteFailed)
        );
        let generation = faulted.persistence.fault_generation;
        assert_eq!(
            faulted.persistence.output_obligations.len(),
            1,
            "the failed capture owes exactly one archive obligation"
        );
        assert!(
            !faulted.persistence.resume_ready,
            "a failed archive must not offer a continue before its bytes are stored"
        );

        // The requirement is that the owed obligation blocks continuation, not that the Turn reaches
        // one particular phase: with a one-step limit the Turn may simply end after the fault, and no
        // later phase frame is guaranteed to be published. Stopping the driver and refusing the
        // explicit continue while the obligation is still owed proves the real boundary.
        drop(runner);
        assert!(
            !thread.snapshot().persistence.output_obligations.is_empty(),
            "the failed capture is still owed before the retry: {}",
            stage_facts(&thread.snapshot())
        );
        assert!(
            thread.resume_storage(generation).await.is_err(),
            "the pause stays closed until the archive obligation is re-stored"
        );

        thread.retry_output_storage().await?;
        thread.flush().await?;
        assert_eq!(
            retries.load(Ordering::SeqCst),
            1,
            "the real repair and archive run exactly once for the failed capture"
        );

        let history = store.history("archive-repair").await?;
        let fact = history
            .tool_task("task:capture-1")
            .await?
            .context("the committed tool task is durable")?;
        let delivery = fact.delivery.context("the committed delivery is durable")?;
        let reference = delivery
            .delivered_context
            .iter()
            .find_map(|content| match content {
                ContextContent::Resource { reference } => Some(reference.clone()),
                _ => None,
            })
            .context("the repaired reference is recorded on the committed delivery")?;
        assert!(
            reference.id().starts_with("pl.studio.resource:"),
            "the delivery records the real content-addressed archive reference"
        );
        let stored_bytes =
            ResourceReader::read(&archive, reference.clone(), CancellationToken::new()).await?;
        assert_eq!(
            stored_bytes.as_ref(),
            expected.as_slice(),
            "the archive stores the accepted bytes verbatim, once, without the partial write"
        );
        let items = history.items_for_turn("capture-turn").await?;
        let output = items
            .iter()
            .find_map(|item| match item.state() {
                pl_protocol::ThreadItemState::Tool(tool) => tool.terminal_output(),
                _ => None,
            })
            .context("the repaired call keeps its durable terminal result")?;
        let referenced = serde_json::to_value(&reference)?;
        assert_eq!(
            output
                .output_artifacts()
                .iter()
                .filter(|artifact| *artifact == &referenced)
                .count(),
            1,
            "the durable item carries the repaired reference exactly once"
        );

        // Off-window stage: the bounded live window is not a save authority. A window that never saw
        // the commit — no GUI open, a slow reader, or a rolled-over window — must still project the
        // repair from the already-committed body, so the canonical item and its content version come
        // from the single projection owner and the durable row is a pure confirmation. A second,
        // already-committed tool identity with no reference yet is written through the writer's own
        // durable commit path, then repaired by a fresh window that has to read it back.
        // The durable identity the single projection owner derives from the call id, kept identical to
        // `order::tool_id` so the owner's own history lookup finds exactly this committed row.
        // This is a separate cold fixture, not an out-of-band mutation of the live writer's
        // database: its artificial sequence must not invalidate the live recovery checkpoint.
        let history = crate::studio::storage::history::HistoryStore::open(
            &temp.path().join("off-window.sqlite"),
            "archive-repair",
        )
        .await?;
        let off_window_id = format!("tool:{}:capture-2", "capture-2".len());
        let off_window_item = pl_protocol::ThreadItem::new(
            off_window_id.clone(),
            "archive-repair".to_owned(),
            "capture-turn".to_owned(),
            41,
            1,
            1,
            1,
            pl_protocol::ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    "capture-2".to_owned(),
                    "capture".to_owned(),
                    "{}".to_owned(),
                ),
                pl_protocol::ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                    1,
                    pl_protocol::ThreadToolOutput::new(
                        "accepted so far".to_owned(),
                        Vec::new(),
                        Vec::new(),
                        None,
                    ),
                )),
            )),
        );
        let cold_chat = pl_core::chat::Session::new(
            history.clone(),
            pl_core::chat::TimelineEpoch::new("off-window-repair")?,
        );
        let original_completion = cold_chat
            .publish_batch(vec![crate::studio::runtime::chat_item::completion_draft(
                &off_window_item,
                1_000_000,
            )?])
            .await?;
        let completions: Vec<_> = original_completion
            .iter()
            .map(|item| (**item).clone())
            .collect();
        history
            .commit_effect(
                1_000_000,
                EffectCommit {
                    items: std::slice::from_ref(&off_window_item),
                    completions: &completions,
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        cold_chat.confirm_durable(original_completion.last().unwrap().append_seq)?;
        let repair_only = ThreadEffectBatch {
            thread_id: "archive-repair".to_owned(),
            sequence: 1_000_001,
            committed_at: 1,
            delivery_repairs: Arc::from([pl_core::thread::cold::OutputRepair {
                call_id: "capture-2".to_owned(),
                reference: reference.clone(),
            }]),
            ..Default::default()
        };
        let off_window_channel = HistoryChannel::new(Arc::new(AtomicU64::new(0)));
        off_window_channel.order_index.seed(
            history.latest_execution_ordinal().await?,
            history.watermark().await?,
        );
        let mut off_window = crate::studio::thread_projection::LiveProjection::new();
        off_window.bind_execution_history(off_window_channel.order_index(), history.clone())?;
        crate::studio::thread_projection::seed_repaired_targets(
            &mut off_window,
            &history,
            &repair_only,
        )
        .await?;
        assert!(
            off_window.holds_terminal_tool(&off_window_id),
            "the off-window repair reads the committed body back before projecting it"
        );
        let chat = cold_chat;
        let mut packaged = off_window
            .prepare_committed(
                &test_thread("archive-repair"),
                &repair_only,
                &ThreadSnapshot::default(),
            )
            .await?;
        off_window.publish_prepared(&chat, &mut packaged).await?;
        assert!(
            packaged.completions.is_empty(),
            "a repaired execution result cannot reseal its changed payload into completion history"
        );
        assert_eq!(
            pl_core::chat::ChatHistory::item(&history, &off_window_id).await?,
            Some((*original_completion[0]).clone())
        );
        let repackaged = packaged
            .items
            .iter()
            .find(|item| item.id == off_window_id)
            .context("the off-window repair is projected at its original identity")?;
        assert_eq!(
            repackaged.ordinal, off_window_item.ordinal,
            "the supplement keeps the committed position instead of taking a new one"
        );
        assert_eq!(
            repackaged.revision,
            off_window_item.revision + 1,
            "the single projection owner assigns the content version; the writer never invents one"
        );
        let repackaged_output = match repackaged.state() {
            pl_protocol::ThreadItemState::Tool(tool) => tool.terminal_output(),
            _ => None,
        }
        .context("the off-window supplement keeps the terminal tool result")?;
        assert_eq!(
            repackaged_output
                .output_artifacts()
                .iter()
                .filter(|artifact| *artifact == &referenced)
                .count(),
            1,
            "the off-window projection appends the reference exactly once"
        );

        // The caller can only continue once the obligation and its repair really landed.
        thread.resume_storage(generation).await?;
        assert!(!thread.snapshot().persistence.resume_required);

        // A repeated retry reproduces the same bytes and the same reference instead of appending twice.
        let obligation = created
            .lock()
            .unwrap()
            .first()
            .cloned()
            .expect("the tool created its obligation");
        let again = obligation.retry().await?;
        let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(repaired) = again else {
            anyhow::bail!("the repeated retry must name the same repaired reference");
        };
        assert_eq!(repaired.reference, reference);
        assert_eq!(
            std::fs::read(&capture_file)?,
            expected,
            "repeating the repair reproduces the fragment instead of duplicating the chunk"
        );
        assert_eq!(retries.load(Ordering::SeqCst), 2);
        thread.close().await?;
        Ok(())
    }

    /// Re-materializes a whole multi-chunk capture plan through the real local backend, then archives
    /// the fragment: the same shape core retries for a failed command capture.
    #[derive(Debug)]
    struct CapturePlanObligation {
        backend: pl_tool::command::LocalCommandBackend,
        archive: crate::resource_store::FileResourceStore,
        capture_file: std::path::PathBuf,
        call_id: String,
        plan: pl_tool::command::CaptureRepair,
        retries: Arc<AtomicUsize>,
    }

    impl pl_core::thread::cold::OutputRetryObligation for CapturePlanObligation {
        fn identity(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn retry(&self) -> pl_core::thread::cold::OutputRetryFuture<'_> {
            Box::pin(async move {
                self.retries.fetch_add(1, Ordering::SeqCst);
                // Replay the plan in acceptance order: one truncation back to the backend-confirmed
                // offset, then every accepted chunk re-appended with its own framing.
                let mut confirmed = self.plan.confirmed;
                for chunk in &self.plan.chunks {
                    let capture = match chunk.stream {
                        pl_tool::command::CommandCaptureStream::Stdout => self.capture_file.clone(),
                        pl_tool::command::CommandCaptureStream::Stderr => {
                            self.capture_file.with_file_name("stderr.log")
                        }
                    };
                    let committed_len = pl_tool::command::CommandBackend::repair_output_chunk(
                        &self.backend,
                        &capture,
                        chunk.stream,
                        confirmed.get(chunk.stream),
                        &chunk.pending,
                    )
                    .await
                    .map_err(|error| {
                        pl_core::thread::cold::ColdStoreError {
                            source: Box::new(std::io::Error::other(error.to_string())),
                        }
                    })?;
                    confirmed.set(chunk.stream, committed_len);
                }
                let reference = self
                    .archive
                    .retain_command_capture(&self.capture_file)
                    .await
                    .map_err(|error| pl_core::thread::cold::ColdStoreError {
                        source: Box::new(error),
                    })?;
                Ok(pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(
                    pl_core::thread::cold::OutputRepair {
                        call_id: self.call_id.clone(),
                        reference,
                    },
                ))
            })
        }
        fn received_bytes(&self) -> u64 {
            self.plan.confirmed.total()
        }
        fn location(&self) -> String {
            self.capture_file.display().to_string()
        }
        fn kind(&self) -> pl_core::thread::cold::StorageFaultKind {
            pl_core::thread::cold::StorageFaultKind::WriteFailed
        }
    }

    /// Two streams' accepted chunks survive one reader's partial capture write.
    ///
    /// The first stdout append failed after writing part of its chunk, and the stderr reader had
    /// already accepted (and published) a chunk. Both must be re-materialized verbatim, once, in
    /// acceptance order: the second append must not land past the fault, and a repeated retry must not
    /// duplicate or truncate either chunk. The archived reference must read back the whole fragment.
    #[tokio::test]
    async fn a_two_stream_capture_repair_replays_every_accepted_chunk_once() -> Result<()> {
        use pl_core::context::ResourceReader;
        use pl_core::thread::cold::OutputRetryObligation as _;

        let temp = tempfile::tempdir()?;
        let resources_root = temp.path().join("resources");
        std::fs::create_dir_all(&resources_root)?;
        let archive = crate::resource_store::FileResourceStore::new(resources_root);
        let backend = pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf());

        // The committed offset comes from the real backend's confirmed writes, not a hand-computed or
        // swallowed fragment length: prepare the header, then append the chunk the capture already
        // stored. That returned length is exactly what a repair truncates back to.
        let target = pl_tool::command::CommandBackend::output_target(
            &backend,
            "session",
            "exec",
            "capture-2",
            "capture",
        )
        .await?;
        pl_tool::command::CommandBackend::prepare_output(
            &backend,
            &target,
            "capture",
            "/tmp",
            pl_tool::command::MAX_CAPTURE_BYTES,
        )
        .await?;
        let capture_file = target.capture_file().to_path_buf();
        let committed = b"committed line\n".to_vec();
        let committed_len = pl_tool::command::CommandBackend::append_output_chunk(
            &backend,
            &target,
            pl_tool::command::CommandCaptureStream::Stdout,
            &committed,
        )
        .await?;
        let committed_prefix = std::fs::read(&capture_file)?;
        assert_eq!(
            committed_len,
            committed_prefix.len() as u64,
            "the repair offset is the backend-confirmed fragment length"
        );

        let stdout_pending = b"first failed stdout chunk".to_vec();
        let stderr_pending = b"second stream accepted chunk".to_vec();
        // The failed append left its framing and a few bytes of its chunk past the confirmed offset;
        // the stderr chunk was accepted and published before the fault, so it is still owed.
        {
            use std::io::Write as _;
            let mut fragment = std::fs::OpenOptions::new()
                .append(true)
                .open(&capture_file)?;
            fragment.write_all(b"=== STDOUT ===\n")?;
            fragment.write_all(&stdout_pending[..7])?;
        }

        let expected = {
            let mut expected = committed_prefix;
            expected.extend_from_slice(&stdout_pending);
            expected
        };

        let retries = Arc::new(AtomicUsize::new(0));
        let obligation = Arc::new(CapturePlanObligation {
            backend,
            archive: archive.clone(),
            capture_file: capture_file.clone(),
            call_id: "capture-2".to_owned(),
            plan: pl_tool::command::CaptureRepair {
                confirmed: pl_tool::command::CommandCaptureOffsets {
                    stdout: committed_len,
                    stderr: 0,
                },
                chunks: vec![
                    pl_tool::command::CaptureRepairChunk {
                        stream: pl_tool::command::CommandCaptureStream::Stdout,
                        pending: Arc::from(stdout_pending.clone()),
                    },
                    pl_tool::command::CaptureRepairChunk {
                        stream: pl_tool::command::CommandCaptureStream::Stderr,
                        pending: Arc::from(stderr_pending.clone()),
                    },
                ],
            },
            retries: retries.clone(),
        });

        let first = obligation.retry().await?;
        assert_eq!(
            std::fs::read(capture_file.with_file_name("stderr.log"))?,
            stderr_pending
        );
        let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(first) = first else {
            anyhow::bail!("the repair must name the stored reference");
        };
        assert_eq!(
            std::fs::read(&capture_file)?,
            expected,
            "the retry stores both accepted chunks verbatim, in order, without the partial write"
        );
        let stored =
            ResourceReader::read(&archive, first.reference.clone(), CancellationToken::new())
                .await?;
        assert_eq!(
            stored.as_ref(),
            expected.as_slice(),
            "the archived reference reads back the whole accepted fragment"
        );

        let again = obligation.retry().await?;
        let pl_core::thread::cold::OutputRetryOutcome::StoredWithRepair(again) = again else {
            anyhow::bail!("the repeated retry must name the same stored reference");
        };
        assert_eq!(again.reference, first.reference);
        assert_eq!(
            std::fs::read(&capture_file)?,
            expected,
            "the repeated retry reproduces the same fragment instead of duplicating a chunk"
        );
        assert_eq!(retries.load(Ordering::SeqCst), 2);
        Ok(())
    }

    use pl_tool::command::CommandBackend as _;

    /// A command backend whose capture append is held and then failed, over in-memory IO.
    ///
    /// The read/repair and header capabilities delegate to a real [`pl_tool::command::LocalCommandBackend`],
    /// but `spawn` hands back a [`pl_tool::command::ManagedCommand`] over duplex pipes the test feeds
    /// directly, and `append_output_chunk` waits for a gate and then fails like a real disk write error.
    /// That makes the operation's single writer task — not a hand-made plan — the thing that observes the
    /// fault.
    struct ScriptedCaptureBackend {
        inner: pl_tool::command::LocalCommandBackend,
        stdout: std::sync::Mutex<Option<pl_tool::command::CommandReader>>,
        stderr: std::sync::Mutex<Option<pl_tool::command::CommandReader>>,
        exit: Arc<Notify>,
        gate: Arc<Notify>,
    }

    impl std::fmt::Debug for ScriptedCaptureBackend {
        fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter
                .debug_struct("ScriptedCaptureBackend")
                .finish_non_exhaustive()
        }
    }

    impl pl_tool::command::CommandBackend for ScriptedCaptureBackend {
        type Error = pl_protocol::PureError;

        fn capture_ownership(&self) -> pl_tool::command::CommandCaptureOwnership {
            self.inner.capture_ownership()
        }
        fn capture_storage_cost(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
            stream: pl_tool::command::CommandCaptureStream,
            chunk: &[u8],
        ) -> u64 {
            self.inner.capture_storage_cost(target, stream, chunk)
        }

        async fn resolve_cwd(
            &self,
            cwd: Option<&std::path::Path>,
            allow_workspace_escape: bool,
        ) -> Result<String, Self::Error> {
            self.inner.resolve_cwd(cwd, allow_workspace_escape).await
        }

        async fn output_target(
            &self,
            session_id: &str,
            tool_id: &str,
            call_id: &str,
            command: &str,
        ) -> Result<pl_tool::command::CommandOutputTarget, Self::Error> {
            self.inner
                .output_target(session_id, tool_id, call_id, command)
                .await
        }

        async fn spawn(
            &self,
            _request: pl_tool::command::CommandSpawnRequest,
        ) -> Result<pl_tool::command::ManagedCommand, Self::Error> {
            let stdout = self.stdout.lock().expect("stdout reader").take();
            let stderr = self.stderr.lock().expect("stderr reader").take();
            let exit = self.exit.clone();
            Ok(pl_tool::command::ManagedCommand::new(
                None,
                pl_tool::command::CommandIo {
                    stdin: None,
                    stdout,
                    stderr,
                },
                move |_cancellation| async move {
                    exit.notified().await;
                    Ok(pl_tool::command::CommandExit {
                        supervision_failure: None,
                        signal: None,
                        capture_failure: None,
                        exit_code: Some(0),
                        capture: None,
                    })
                },
            ))
        }

        async fn prepare_output(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
            command: &str,
            working_directory: &str,
            capture_limit_bytes: u64,
        ) -> Result<u64, Self::Error> {
            self.inner
                .prepare_output(target, command, working_directory, capture_limit_bytes)
                .await
        }

        async fn append_output_chunk(
            &self,
            _target: &pl_tool::command::CommandOutputTarget,
            _stream: pl_tool::command::CommandCaptureStream,
            _chunk: &[u8],
        ) -> Result<u64, Self::Error> {
            // Hold the operation's single writer until the test has confirmed both streams' accepted
            // chunks, then fail the append the way a real capture write error would.
            self.gate.notified().await;
            Err(pl_protocol::PureError::ToolExecutionFailed {
                tool: "exec".to_owned(),
                error: "capture append failed".to_owned(),
            })
        }

        async fn repair_output_chunk(
            &self,
            capture_file: &std::path::Path,
            stream: pl_tool::command::CommandCaptureStream,
            committed_len: u64,
            chunk: &[u8],
        ) -> Result<u64, Self::Error> {
            self.inner
                .repair_output_chunk(capture_file, stream, committed_len, chunk)
                .await
        }

        async fn publish_output(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
        ) -> Result<(), Self::Error> {
            self.inner.publish_output(target).await
        }

        async fn collect_output_artifacts(
            &self,
            target: &pl_tool::command::CommandOutputTarget,
            sizes: pl_tool::command::CommandOutputSizes,
        ) -> Result<Vec<serde_json::Value>, Self::Error> {
            self.inner.collect_output_artifacts(target, sizes).await
        }
    }

    /// Signals once both command streams have published an accepted chunk.
    #[derive(Debug, Default)]
    struct BothStreamsSeen {
        stdout: AtomicUsize,
        stderr: AtomicUsize,
        both: Notify,
    }

    impl pl_tool::command::CommandOutputObserver for BothStreamsSeen {
        fn output_chunk(
            &self,
            stream: pl_tool::command::CommandOutputStream,
            chunk: &[u8],
            _revision: u64,
        ) {
            let counter = match stream {
                pl_tool::command::CommandOutputStream::Stdout => &self.stdout,
                pl_tool::command::CommandOutputStream::Stderr => &self.stderr,
            };
            counter.fetch_add(chunk.len().max(1), Ordering::SeqCst);
            if self.stdout.load(Ordering::SeqCst) > 0 && self.stderr.load(Ordering::SeqCst) > 0 {
                self.both.notify_one();
            }
        }
    }

    /// The real command lifecycle retains and replays a two-stream capture fault.
    ///
    /// This drives the operation, not a hand-made plan: both readers accept *and publish* a chunk from
    /// their stream, the operation's single writer is held until then and only then fails its append,
    /// and the scripted process then exits. So the retained repair plan must hold both streams' accepted
    /// chunks, the terminal result must not be a success, and replaying the plan through the real local
    /// backend must archive exactly those bytes under one reference that reads back whole.
    #[tokio::test]
    async fn a_two_stream_capture_fault_is_retained_and_replayed_by_the_lifecycle() -> Result<()> {
        use pl_core::context::ResourceReader;

        let temp = tempfile::tempdir()?;
        let resources_root = temp.path().join("resources");
        std::fs::create_dir_all(&resources_root)?;
        let archive = crate::resource_store::FileResourceStore::new(resources_root);

        let (mut stdout_writer, stdout_reader) = tokio::io::duplex(1024);
        let (mut stderr_writer, stderr_reader) = tokio::io::duplex(1024);
        let gate = Arc::new(Notify::new());
        let exit = Arc::new(Notify::new());
        let backend = ScriptedCaptureBackend {
            inner: pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf()),
            stdout: std::sync::Mutex::new(Some(
                Box::pin(stdout_reader) as pl_tool::command::CommandReader
            )),
            stderr: std::sync::Mutex::new(Some(
                Box::pin(stderr_reader) as pl_tool::command::CommandReader
            )),
            exit: exit.clone(),
            gate: gate.clone(),
        };
        let manager = Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
            backend,
        )));

        let seen = Arc::new(BothStreamsSeen::default());
        let observer: Arc<dyn pl_tool::command::CommandOutputObserver> = seen.clone();
        let request = pl_tool::command::CommandStartRequest {
            command: "scripted".to_owned(),
            cwd: Some(temp.path().to_path_buf()),
            allow_workspace_escape: false,
            timeout: Duration::from_secs(30),
            yield_time: Duration::ZERO,
            max_output_chars: 4096,
            session_id: "two-stream-lifecycle".to_owned(),
            tool_id: "task-two-stream-lifecycle".to_owned(),
            call_id: "task-two-stream-lifecycle".to_owned(),
            cancellation_token: None,
            output_observer: Some(observer),
        };
        let runner = {
            let manager = manager.clone();
            tokio::spawn(
                async move { manager.run_task("task-two-stream-lifecycle", request).await },
            )
        };

        tokio::io::AsyncWriteExt::write_all(&mut stdout_writer, b"OUT-1\n").await?;
        tokio::io::AsyncWriteExt::write_all(&mut stderr_writer, b"ERR-1\n").await?;
        tokio::time::timeout(Duration::from_secs(30), seen.both.notified())
            .await
            .context("both streams should have published an accepted chunk")?;

        // Both accepted chunks are queued in the one plan; now let the held append fail for real, then
        // close the streams and exit the scripted process so the operation settles.
        gate.notify_one();
        drop(stdout_writer);
        drop(stderr_writer);
        exit.notify_one();

        let snapshot = match tokio::time::timeout(Duration::from_secs(30), runner).await {
            Ok(Ok(Ok(snapshot))) => snapshot,
            Ok(Ok(Err(error))) => {
                anyhow::bail!("the operation returned an error instead of a snapshot: {error}")
            }
            Ok(Err(error)) => anyhow::bail!("the operation task failed: {error}"),
            Err(_) => {
                anyhow::bail!("the operation never settled: the capture writer did not drain")
            }
        };

        assert!(
            matches!(
                &snapshot.output_failure,
                Some(pl_tool::command::CommandCaptureFailure::Write { .. })
            ),
            "the real append failure must surface as a typed capture write failure: {:?}",
            snapshot.output_failure
        );
        assert!(
            snapshot.state.final_result().is_some(),
            "the snapshot is only returned once the operation settled"
        );
        assert!(
            !matches!(
                snapshot.state.final_result(),
                Some(pl_tool::command::CommandProcessFinalResult::Succeeded { .. })
            ),
            "a capture write failure must never be reported as a successful command"
        );

        let plan = snapshot
            .capture_repair()
            .cloned()
            .context("both accepted chunks must stay owed after the failed append")?;
        assert_eq!(
            plan.chunks.len(),
            2,
            "both streams' accepted chunks are retained"
        );
        assert!(
            plan.chunks.iter().any(|chunk| {
                chunk.stream == pl_tool::command::CommandCaptureStream::Stdout
                    && &chunk.pending[..] == b"OUT-1\n".as_slice()
            }),
            "the stdout chunk is retained verbatim"
        );
        assert!(
            plan.chunks.iter().any(|chunk| {
                chunk.stream == pl_tool::command::CommandCaptureStream::Stderr
                    && &chunk.pending[..] == b"ERR-1\n".as_slice()
            }),
            "the stderr chunk is retained verbatim"
        );

        // Replay the plan through the real local backend and archive it: the stored reference must read
        // back exactly the accepted bytes, in acceptance order, with the failed append left off.
        let real = pl_tool::command::LocalCommandBackend::new(temp.path().to_path_buf());
        let mut confirmed = plan.confirmed;
        for chunk in &plan.chunks {
            let capture = match chunk.stream {
                pl_tool::command::CommandCaptureStream::Stdout => &snapshot.capture_file,
                pl_tool::command::CommandCaptureStream::Stderr => &snapshot.stderr_capture_file,
            };
            let committed_len = real
                .repair_output_chunk(
                    capture,
                    chunk.stream,
                    confirmed.get(chunk.stream),
                    &chunk.pending,
                )
                .await?;
            confirmed.set(chunk.stream, committed_len);
        }
        let reference = archive
            .retain_command_capture(&snapshot.capture_file)
            .await?;
        let stored = ResourceReader::read(&archive, reference, CancellationToken::new()).await?;
        let stored = String::from_utf8_lossy(stored.as_ref());
        assert!(
            stored.contains("OUT-1"),
            "the archive keeps the stdout chunk: {stored}"
        );
        let stderr_reference = archive
            .retain_command_capture(&snapshot.stderr_capture_file)
            .await?;
        let stderr =
            ResourceReader::read(&archive, stderr_reference, CancellationToken::new()).await?;
        assert_eq!(stderr.as_ref(), b"ERR-1\n");
        assert_eq!(stored.as_ref(), "OUT-1\n");

        Ok(())
    }
}
