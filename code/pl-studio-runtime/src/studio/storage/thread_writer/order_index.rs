//! Execution identity placement and byte-budget ownership for one Thread.

use super::*;

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
}

pub(super) struct OrderIndexState {
    ceiling: u64,
    durable: u64,
    assigned: BTreeMap<String, ExecutionIdentity>,
    by_source: BTreeMap<String, std::collections::BTreeSet<String>>,
    pending: std::collections::BTreeSet<(u64, String)>,
    dirty: std::collections::BTreeSet<String>,
    /// An already admitted material owner failed to fund its next step; only an explicit
    /// successful owner measurement/transfer or retry can reopen optional allocations.
    pub(super) resident_blocked: bool,
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
    pub(super) fn is_idle(&self) -> bool {
        self.by_source.is_empty() && self.pending.is_empty() && self.dirty.is_empty()
    }

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
pub(super) struct ExecutionIndexBudgetFull {
    pub(super) scope: &'static str,
}

impl ExecutionIdentity {
    pub(super) fn bytes(&self, id: &str) -> u64 {
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
    pub(super) fn lock_state(&self) -> std::sync::MutexGuard<'_, OrderIndexState> {
        self.inner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub(super) fn set_other_resident_bytes(&self, _state: &OrderIndexState, bytes: u64) {
        self.other_thread_bytes.store(bytes, Ordering::Release);
    }

    pub(super) fn set_capacity_notifier(&self, capacity: tokio::sync::watch::Sender<u64>) {
        *self
            .capacity_changed
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(capacity);
    }

    pub(super) fn delivery_counter(&self) -> Arc<AtomicU64> {
        self.delivery_bytes.clone()
    }

    pub(super) fn new(process_bytes: Arc<AtomicU64>, ceiling: u64) -> Self {
        Self::with_delivery(process_bytes, ceiling, Arc::new(AtomicU64::new(0)))
    }

    pub(super) fn with_delivery(
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

    pub(in crate::studio) fn reserve_observed(
        &self,
        attempt_id: &str,
        item_id: &str,
    ) -> Result<u64> {
        self.allocate(item_id, Some(attempt_id), None)
    }

    pub(super) fn allocate(
        &self,
        item_id: &str,
        source: Option<&str>,
        ordinal: Option<u64>,
    ) -> Result<u64> {
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

            stamp: None,
        };
        self.commit_execution_batch(
            state,
            BTreeMap::from([(item_id.to_owned(), entry)]),
            state.ceiling.max(order),
        )?;
        Ok(order)
    }

    pub(super) fn charge(&self, bytes: u64, blocked: bool) -> Result<()> {
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

    /// Reserve only the explicit execution boundaries, before Core may reserve provider parts.
    /// This does not project content. The admitted effect owns these charged shells until its
    /// actual save, even if the projection is still processing an older checkpoint.
    #[cfg(test)]
    pub(super) fn reserve_boundaries(
        &self,
        effect: &pl_core::thread::ThreadEffectBatch,
        additional_bytes: u64,
    ) -> Result<()> {
        let mut state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        self.reserve_boundaries_locked(&mut state, effect, additional_bytes)
    }

    pub(super) fn reserve_boundaries_locked(
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

    pub(super) fn has_pending(&self) -> bool {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        state
            .pending
            .last()
            .is_some_and(|(effect, _)| *effect > state.durable)
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

    pub(in crate::studio) fn mark_completion(&self, id: &str, sealed: bool) {
        if let Some(entry) = self
            .inner
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .assigned
            .get_mut(id)
        {
            entry.sealed |= sealed;
        }
    }

    #[cfg(test)]
    pub(super) fn pending(&self, id: &str) -> bool {
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
    ) -> Option<crate::ExecutionItem> {
        let state = self.inner.lock().unwrap_or_else(|error| error.into_inner());
        let entry = state.assigned.get(id)?;
        if !entry.effect.is_some_and(|seq| seq > state.durable) {
            return None;
        }
        let stamp = entry.stamp.as_ref()?;
        Some(crate::ExecutionItem::new(
            id.to_owned(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.to_owned()),
                turn_id: std::borrow::Cow::Owned(stamp.turn_id.clone()),
                ordinal: entry.ordinal,
                revision: stamp.revision,
                created_at: stamp.created_at,
                updated_at: stamp.updated_at,
            },
            crate::ExecutionShape::Raw(crate::ThreadRawItem::stored(
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

    pub(super) fn confirm_saved(&self, effect: u64) {
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
