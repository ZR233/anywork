//! Canonical placement, versions and retained execution payloads.
use super::{
    LIVE_ITEM_WINDOW, ProjectionError,
    memory_budget::{RETAINED_ENTRY_OVERHEAD, RetainedBytes},
    preview_cache::PreviewCache,
};
use crate::studio::storage::thread_writer::RuntimeOrderIndex;
use crate::{ExecutionItem, ExecutionShape, ThreadRawItem};
use pl_core::thread::{ThreadSnapshot, TurnState};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

/// Retained bytes of one placement fact keyed by its identity, its fixed entry shell included.
fn fact_bytes(id: &str, fact: &Fact) -> u64 {
    (id.len() as u64)
        .saturating_add(fact.turn_id.len() as u64)
        .saturating_add(RETAINED_ENTRY_OVERHEAD)
}

/// Retained bytes of one content-version entry keyed by its identity.
fn revision_bytes(id: &str) -> u64 {
    (id.len() as u64).saturating_add(RETAINED_ENTRY_OVERHEAD)
}

/// Ordinal, revision and creation stamp of one identity the projection has already published.
///
/// A later revision of the same identity is stamped from this instead of a storage lookup. The body
/// itself is only kept while it can still change, so this metadata is what makes "release the
/// process body" safe without losing the identity's canonical placement.
#[derive(Debug, Clone)]
pub(super) struct Fact {
    pub(super) ordinal: u64,
    pub(super) revision: u64,
    pub(super) created_at: i64,
    pub(super) turn_id: String,
}

impl Fact {
    /// Stand-in payload for an identity whose body left the live window.
    ///
    /// The projection only reads placement metadata and identity presence from it; a projection
    /// that needs the released body itself (re-projecting a pruned tool call) fails closed instead
    /// of inventing content.
    fn placeholder(&self, id: &str, thread_id: &str) -> ExecutionItem {
        ExecutionItem::new(
            id.to_owned(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.to_owned()),
                turn_id: std::borrow::Cow::Owned(self.turn_id.clone()),
                ordinal: self.ordinal,
                revision: self.revision,
                created_at: self.created_at,
                updated_at: self.created_at,
            },
            ExecutionShape::Raw(ThreadRawItem::stored(
                Vec::new(),
                "This item's body is no longer resident in the live window.",
                self.created_at,
            )),
        )
    }
}

#[derive(Default)]
pub(super) struct PlacementWindow {
    items: BTreeMap<String, ExecutionItem>,
    facts: BTreeMap<String, Fact>,
    // One content counter per identity, independent of effect sequence.
    revisions: BTreeMap<String, u64>,
    items_bytes: u64,
    facts_bytes: u64,
    revisions_bytes: u64,
    order_index: Option<Arc<RuntimeOrderIndex>>,
}

impl RetainedBytes for PlacementWindow {
    fn retained_bytes(&self) -> u64 {
        self.items_bytes
            .saturating_add(self.facts_bytes)
            .saturating_add(self.revisions_bytes)
    }
}

impl Drop for PlacementWindow {
    fn drop(&mut self) {
        if let Some(index) = &self.order_index {
            // The original fact owner is leaving. Pending saves and real live
            // sources keep their own protection after these references retire.
            let removed = std::mem::take(&mut self.facts).into_keys().collect();
            index.retain::<()>(&BTreeMap::new(), removed);
        }
    }
}

impl PlacementWindow {
    pub(super) fn bind(&mut self, index: Arc<RuntimeOrderIndex>) {
        self.order_index = Some(index);
    }

    pub(super) fn items(&self) -> &BTreeMap<String, ExecutionItem> {
        &self.items
    }

    pub(super) fn has_fact(&self, id: &str) -> bool {
        self.facts.contains_key(id)
    }

    pub(super) fn has_assignment(&self, id: &str) -> bool {
        self.order_index
            .as_ref()
            .is_some_and(|index| index.assigned(id).is_some())
    }

    pub(super) fn revision(&self, id: &str) -> u64 {
        self.revisions.get(id).copied().unwrap_or(0)
    }

    pub(super) fn completion_exists(&self, id: &str) -> Result<bool, ProjectionError> {
        Ok(self.order_index_of()?.is_sealed(id))
    }

    /// Raises the content-version baseline to the lower bound of the known canonical facts.
    ///
    /// The content version is each identity's own monotonic fact, not a property of this cache: when
    /// an identity was evicted from the retained window, or the projection was re-seeded and meets it
    /// again, the canonical payload resolved back already carries its version and this projection must
    /// continue from it. Restarting at 1 would be lower than the persisted old version, and the shared
    /// session would ignore the frame as stale.
    ///
    /// An identity already resident in `self.items` is left alone: while this projection holds it, its
    /// own counter is the session's authoritative baseline, and re-applying an external version would
    /// only jump it into another version domain. The ordinary path therefore never re-reads storage;
    /// only a cold identity resolved from a placement fact is raised here.
    pub(super) fn adopt_revisions(&mut self, existing: &BTreeMap<String, ExecutionItem>) {
        for (id, item) in existing {
            if item.revision == 0 || self.items.contains_key(id) {
                continue;
            }
            self.raise_revision(id, item.revision);
        }
    }

    /// Advances and returns one identity's new content version.
    pub(super) fn bump_content_revision(&mut self, id: &str) -> u64 {
        let next = self
            .revisions
            .get(id)
            .copied()
            .unwrap_or(0)
            .saturating_add(1);
        self.raise_revision(id, next);
        next
    }

    /// Raises one identity's content-version baseline, keeping the retained-byte estimate in step.
    ///
    /// Inserting an identity's first version also inserts its charged entry, so the running total
    /// follows the table exactly; raising a version the identity already had does not change the
    /// entry's size.
    pub(super) fn raise_revision(&mut self, id: &str, version: u64) {
        match self.revisions.get_mut(id) {
            Some(known) => {
                if version > *known {
                    *known = version;
                }
            }
            None => {
                self.revisions.insert(id.to_owned(), version);
                self.revisions_bytes = self.revisions_bytes.saturating_add(revision_bytes(id));
            }
        }
    }

    /// Resolve only facts still owned by this projection or its in-flight channel.
    pub(super) fn resolve(
        &self,
        thread: &crate::Thread,
        ids: impl IntoIterator<Item = String>,
    ) -> BTreeMap<String, ExecutionItem> {
        ids.into_iter()
            .filter_map(|id| {
                let item = self
                    .items
                    .get(&id)
                    .cloned()
                    .or_else(|| {
                        self.facts
                            .get(&id)
                            .map(|fact| fact.placeholder(&id, &thread.id))
                    })
                    .or_else(|| {
                        self.order_index
                            .as_ref()
                            .and_then(|index| index.pending_placement(&id, &thread.id))
                    });
                item.map(|item| (id, item))
            })
            .collect()
    }

    /// The channel-owned execution-order index explicitly bound to this projection.
    ///
    /// # Errors
    /// Fails when the owner has not bound execution history.
    pub(super) fn order_index_of(&self) -> Result<Arc<RuntimeOrderIndex>, ProjectionError> {
        self.order_index
            .clone()
            .ok_or_else(|| ProjectionError::History("execution history is not bound".into()))
    }

    /// Whether one identity is an execution fact this projection already knows to be terminal.
    ///
    /// This marker has the same active/pending lifetime as its execution placement. Frames from
    /// an ended source are rejected before this lookup, even after the marker was reclaimed.
    pub(super) fn identity_is_terminal(&self, id: &str) -> bool {
        self.order_index
            .as_ref()
            .is_some_and(|index| index.is_terminal(id))
    }

    /// Keeps the placement metadata of one identity that the projection may update later.
    pub(super) fn fact(&mut self, item: &ExecutionItem) {
        self.store_fact(
            item.id.clone(),
            Fact {
                ordinal: item.ordinal,
                revision: item.revision,
                created_at: item.created_at,
                turn_id: item.turn_id.clone(),
            },
        );
    }

    /// Stores one canonical body, keeping the retained-byte estimate in step.
    ///
    /// Replacing a body charges the difference instead of double counting it, so the running total
    /// stays the exact value [`LiveProjection::retained_bytes`] would compute from the table.
    pub(super) fn store_item(&mut self, item: ExecutionItem) {
        let next = item.retained_bytes();
        match self.items.insert(item.id.clone(), item) {
            Some(previous) => {
                self.items_bytes = self
                    .items_bytes
                    .saturating_sub(previous.retained_bytes())
                    .saturating_add(next);
            }
            None => self.items_bytes = self.items_bytes.saturating_add(next),
        }
    }

    /// Releases one canonical body, keeping the retained-byte estimate in step.
    pub(super) fn release_item(&mut self, id: &str) {
        if let Some(previous) = self.items.remove(id) {
            self.items_bytes = self.items_bytes.saturating_sub(previous.retained_bytes());
        }
    }

    /// Stores one placement fact, keeping the retained-byte estimate in step.
    pub(super) fn store_fact(&mut self, id: String, fact: Fact) {
        if !self.facts.contains_key(&id)
            && let Some(index) = &self.order_index
        {
            index.retain_reference(&id);
        }
        let next = fact_bytes(&id, &fact);
        let id_len = id.len() as u64;
        match self.facts.insert(id, fact) {
            Some(replaced) => {
                let replaced_bytes = id_len
                    .saturating_add(replaced.turn_id.len() as u64)
                    .saturating_add(RETAINED_ENTRY_OVERHEAD);
                self.facts_bytes = self
                    .facts_bytes
                    .saturating_sub(replaced_bytes)
                    .saturating_add(next);
            }
            None => self.facts_bytes = self.facts_bytes.saturating_add(next),
        }
    }

    pub(super) fn created_at(&self, id: &str, fallback: i64) -> i64 {
        self.facts.get(id).map_or(fallback, |fact| fact.created_at)
    }

    pub(super) fn retain(
        &mut self,
        live: &BTreeSet<String>,
        referenced: &BTreeSet<String>,
        previews: &mut PreviewCache,
    ) {
        let before = (self.items.len(), self.facts.len(), self.revisions.len());
        let keep = |id: &str, turn_id: &str| live.contains(turn_id) || referenced.contains(id);
        let mut removed = Vec::new();
        self.facts.retain(|id, fact| {
            let retained = keep(id, &fact.turn_id);
            if !retained {
                removed.push(id.clone());
            }
            retained
        });
        self.items.retain(|id, item| {
            let retained = match self.facts.get(id) {
                Some(fact) => keep(id, &fact.turn_id),
                None => false,
            };
            // A body is only worth its bytes while it can still change: a non-terminal item is
            // updated by a later effect, the newest Turn's tool items are re-projected by a late
            // delivery, and everything else keeps placement metadata only.
            retained
                && (!item.state().is_terminal()
                    || matches!(item.state(), ExecutionShape::Tool(_))
                    || referenced.contains(id))
        });
        // A Turn that opened more identities than the window is still bounded here: the oldest
        // non-terminal bodies and tool facts are dropped by canonical placement, and the identity
        // itself stays as placement metadata so a later effect still resolves it.
        if self.facts.len() > LIVE_ITEM_WINDOW {
            let mut placed = self
                .facts
                .iter()
                .map(|(id, fact)| (fact.ordinal, id.clone()))
                .collect::<Vec<_>>();
            placed.sort_unstable();
            let mut newest = placed
                .into_iter()
                .rev()
                .take(LIVE_ITEM_WINDOW)
                .map(|(_, id)| id)
                .collect::<BTreeSet<_>>();
            // The window bounds *optional* retained history; the identities the live snapshot still
            // requires (a live Turn's input, the inference/channel and tool identities of its
            // resident attempts, running tasks and undelivered results) are not optional. Numbering
            // by ordinal would evict them exactly when a Turn produced more parts than the window, so
            // they are always kept on top of the newest `LIVE_ITEM_WINDOW` others.
            newest.extend(
                referenced
                    .iter()
                    .filter(|id| self.facts.contains_key(*id))
                    .cloned(),
            );
            self.facts.retain(|id, _| {
                let retained = newest.contains(id);
                if !retained {
                    removed.push(id.clone());
                }
                retained
            });
            self.items.retain(|id, _| newest.contains(id));
        }
        // An in-flight preview belongs to an identity still inside the retained window; once its
        // placement fact is gone it can no longer be resolved or committed, so its body is released
        // with it. The content versions follow the same bounded window and are not a second history:
        // an identity evicted here recovers its baseline from the canonical fact
        // ([`LiveProjection::adopt_revisions`]) instead of restarting at 1.
        previews.retain(|id| self.has_fact(id));
        self.revisions
            .retain(|id, _| self.items.contains_key(id) || previews.contains_key(id));
        if let Some(index) = &self.order_index {
            index.retain(&self.facts, removed);
        }
        if before != (self.items.len(), self.facts.len(), self.revisions.len()) {
            self.rederive_totals();
        }
    }

    fn rederive_totals(&mut self) {
        self.items_bytes = self.items.values().fold(0_u64, |total, item| {
            total.saturating_add(item.retained_bytes())
        });
        self.facts_bytes = self.facts.iter().fold(0_u64, |total, (id, fact)| {
            total.saturating_add(fact_bytes(id, fact))
        });
        self.revisions_bytes = self
            .revisions
            .keys()
            .fold(0_u64, |total, id| total.saturating_add(revision_bytes(id)));
    }
}

pub(super) fn retained_identities(state: &ThreadSnapshot) -> (BTreeSet<String>, BTreeSet<String>) {
    let mut live = state
        .turns
        .iter()
        .filter(|turn| turn.state == TurnState::Running)
        .map(|turn| turn.turn_id.clone())
        .collect::<BTreeSet<_>>();
    if let Some(newest) = state.turns.last() {
        live.insert(newest.turn_id.clone());
    }
    let mut referenced = state
        .tasks
        .values()
        .filter(|task| task.status == pl_core::thread::task::TaskStatus::Running)
        .map(|task| super::super::order::tool_id(&task.call_id))
        .collect::<BTreeSet<_>>();
    referenced.extend(state.inputs.iter().map(|record| record.input.id.clone()));
    // A complete parent message is still mutable placement: its first model consumption
    // binds it to a Turn. Keep its canonical payload and version until the inbox releases it.
    let inbox_items = state
        .inbox
        .iter()
        .map(|record| super::super::order::message_id(&record.message.id))
        .collect::<BTreeSet<_>>();
    referenced.extend(inbox_items.iter().cloned());
    referenced.extend(state.interactions.values().filter_map(|record| {
        pl_core::tool::opaque::interaction_tool_call_id(&record.request.id)
            .map(super::super::order::tool_id)
    }));
    for attempt in state.attempts.iter() {
        referenced.insert(super::super::order::response_id(
            &attempt.attempt_id,
            "inference",
        ));
        for channel in ["reasoning", "text"] {
            referenced.insert(super::super::attempt_channel_id(
                &attempt.attempt_id,
                channel,
            ));
        }
        // A tool result whose call belongs to a still-resident attempt is part of the same
        // unfinished Turn: a later effect of that Turn re-references the tool identity, so it is
        // as required as the attempt's own channels.
    }
    referenced.extend(
        state
            .live_calls
            .iter()
            .filter(|(_, turn)| state.turns.iter().any(|record| &record.turn_id == *turn))
            .map(|(id, _)| super::super::order::tool_id(id)),
    );
    // A result still owed to model context is delivered by a later effect of a live Turn, so its
    // tool identity is required until that delivery commits.
    referenced.extend(
        state
            .deliveries
            .iter()
            .map(|delivery| super::super::order::tool_id(&delivery.call_id)),
    );
    // A live Turn's own facts stay required for every later effect of that Turn: the input that
    // opened it (named by `turns[].input_id` after the consuming commit pruned the resident
    // record), and the Turn item itself, which each later task / phase / terminal commit
    // re-projects. Both must keep their placement fact, because an identity released here is
    // resolved again with a fresh content version: the input would surface as a hole, and the
    // re-projected Turn item would restart at revision 1 and the durable row would reject the
    // new payload as a revision conflict. The window therefore only ever releases *optional*
    // history, never an identity a live Turn still references.
    for turn in state.turns.iter() {
        if !live.contains(&turn.turn_id) {
            continue;
        }
        referenced.insert(super::super::order::turn_id(&turn.turn_id));
        if let Some(input_id) = &turn.input_id {
            referenced.insert(input_id.clone());
        }
    }
    (live, referenced)
}
