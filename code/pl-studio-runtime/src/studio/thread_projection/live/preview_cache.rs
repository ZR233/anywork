//! Streaming History previews and their short-key version index.
use super::super::observation_parts::{aggregate_id, observation_preview};
use super::memory_budget::{
    RETAINED_ENTRY_OVERHEAD, RETAINED_ITEM_OVERHEAD, RetainedBytes, state_body_bytes,
};
use super::{
    ProjectionError, current,
    placement_window::{Fact, PlacementWindow},
    provenance::ProvenanceLedger,
};
use crate::studio::runtime::chat_item::{BodyKey, TOOL_RESULT_FIELD, static_state};
use crate::{ExecutionShape, ThreadContentLifecycle, ThreadTextChannel, ThreadTextItem};
use pl_core::{
    chat::PresentationPart,
    model::{AggregateChannel, ContentBlock, ObservedPartIdentity},
    thread::ThreadSnapshot,
};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    sync::Arc,
};

/// One in-flight streaming preview's resident fact.
///
/// The content blocks are shared with the producer (cloning them only clones the pointer), the
/// static structure is encoded once per identity, and `observed_version` is the observation's own
/// monotonic counter (model content version / tool accumulated length) — only when it advances does
/// the preview re-emit a frame. Nothing here materializes the whole body per token.
///
/// The `revision` delivered to the window comes from [`PlacementWindow`], this
/// projection's own item content version: the preview and the terminal item share one counter, so
/// the preview can neither pass nor collide with the commit.
#[derive(Clone)]
pub(super) struct LivePreview {
    /// All field blocks currently delivered; a model observation is one field, a tool preview is
    /// the arguments plus the streamed result.
    pub(super) fields: BTreeMap<BodyKey, Arc<ContentBlock>>,
    /// Cheap stable identity of one provider/aggregate observation, absent for a tool-output
    /// preview.
    ///
    /// The preview map itself is keyed by the projection id because the runtime's own preview
    /// contract is defined on it; this short key is what the streaming hot path compares, so an already
    /// delivered part never has to rebuild that long identity to be recognized. Its index entry is
    /// charged to the same retained budget ([`observed_index_bytes`]) as the rest of the projection.
    pub(super) observed: Option<ObservedKey>,
    /// Delivered structure / terminal shape (dynamic bodies cleared, see
    /// [`crate::studio::runtime::chat_item::static_state`]). The content version compares it, so a
    /// tool state transition or an execution terminal advances the version while a volatile
    /// timestamp that only the projection re-stamps does not.
    ///
    /// A preview never carries completion metadata: the terminal-only timeline meta belongs to
    /// sealed records, and this runtime shape is the preview's own structural fact.
    pub(super) shape: ExecutionShape,
    /// Newest **observation** version this identity delivered (model content version / tool
    /// accumulated length), used only for de-duplication; it is not the window item's content
    /// version, which [`PlacementWindow`] owns.
    pub(super) observed_version: u64,
    /// Position in the producer's current generation, not lexical preview or execution order.
    /// Checked against that snapshot before activity reads the part; replacement/reordering
    /// invalidates the observation version even when its bytes did not change.
    pub(super) model_part: Option<super::super::current::ModelPartLocation>,
}

/// Cheap stable identity of one provider/aggregate streaming observation.
///
/// It carries exactly the facts [`crate::chat::presentation_item_id`] derives the projection id
/// from — the provider item id and the part discriminator, never the late output index or part id —
/// so two observations of one identity always agree on it, while an observation that only learned
/// late metadata keeps its key.
///
/// The streaming hot path compares one of these instead of the projection id: the id has a long
/// common prefix across every part of a response, so ordering and comparing it per part per frame is
/// what turns a mostly-unchanged preview into work proportional to the whole response.
#[derive(Clone, PartialEq, Eq, Hash)]
pub(super) enum ObservedKey {
    /// One request-scoped aggregate channel, published before the adapter itemizes the response.
    Aggregate(u32, AggregateChannel),
    /// One provider item part: the item identity plus its part discriminator.
    Provider(u32, Arc<str>, PresentationPart),
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct ObservedVersion {
    content: u64,
    ended: bool,
    model_part: Option<super::super::current::ModelPartLocation>,
}

/// Cheap key of one observation identity, derived without building its projection id.
fn observed_key(generation: u32, identity: &ObservedPartIdentity) -> ObservedKey {
    match identity {
        ObservedPartIdentity::Aggregate { channel } => ObservedKey::Aggregate(generation, *channel),
        ObservedPartIdentity::Provider(provider) => ObservedKey::Provider(
            generation,
            provider.item_id.clone(),
            provider.presentation_part(),
        ),
    }
}

/// Retained bytes of one in-flight preview keyed by its identity.
///
/// The resident bodies are shared content blocks, each counted at its observed length; the
/// Runtime's static execution shape and field-map structure are charged alongside them.
fn preview_bytes(id: &str, preview: &LivePreview) -> u64 {
    preview_entry_bytes(id.len() as u64, preview)
}

/// Retained bytes of one preview entry with its identity length supplied separately.
///
/// This is the one formula every site scores a preview entry with — insert, replacement, release and
/// the re-derivation after the bounded window — so a replacement can never keep a hand-copied older
/// estimate that omits a term the projection added since (for example the short-key observation
/// index). `BTreeMap::insert` hands back the replaced entry without its key, so the caller passes the
/// key length it just used; the replaced key is the very same identity.
///
/// The delivered content blocks are shared pointers: each is charged once at its observed length and
/// never copied here.
fn preview_entry_bytes(id_len: u64, preview: &LivePreview) -> u64 {
    let mut bytes = id_len
        .saturating_add(RETAINED_ENTRY_OVERHEAD)
        .saturating_add(RETAINED_ITEM_OVERHEAD)
        .saturating_add(state_body_bytes(&preview.shape))
        .saturating_add((preview.fields.len() as u64).saturating_mul(RETAINED_ENTRY_OVERHEAD))
        .saturating_add(preview.fields.keys().fold(0_u64, |bytes, field| {
            bytes.saturating_add(match field {
                BodyKey::Host(key) => key.len() as u64,
                _ => 0,
            })
        }))
        .saturating_add(preview_fields_bytes(preview));
    // The short-key observation index is resident metadata of the same projection, so its entry is
    // part of the same budget instead of living outside it.
    if let Some(observed) = &preview.observed {
        bytes = bytes.saturating_add(observed_index_bytes(observed));
    }
    bytes
}

/// Retained bytes of one short-key observation-index entry.
///
/// A provider key carries the provider item identity (its `Arc<str>` is shared with the observation,
/// so only the identity's own bytes are resident) and one entry shell for the key, the delivered
/// version and the map slot; an aggregate key carries no heap body at all. Charging one shell keeps
/// the estimate conservative without materializing anything.
fn observed_index_bytes(observed: &ObservedKey) -> u64 {
    match observed {
        ObservedKey::Aggregate(_, _) => RETAINED_ENTRY_OVERHEAD,
        ObservedKey::Provider(_, item_id, _) => {
            (item_id.len() as u64).saturating_add(RETAINED_ENTRY_OVERHEAD)
        }
    }
}

/// Retained bytes of one preview's delivered field blocks.
fn preview_fields_bytes(preview: &LivePreview) -> u64 {
    preview.fields.values().fold(0_u64, |total, block| {
        total.saturating_add(block.len() as u64)
    })
}

#[derive(Default)]
pub(super) struct PreviewCache {
    preview_attempt: Option<String>,
    retired_model_prefix: Option<(u32, pl_core::model::ModelPartsPrefix, usize)>,
    previews: BTreeMap<String, LivePreview>,
    // Short keys keep unchanged observations from rebuilding their presentation IDs.
    observed: HashMap<ObservedKey, ObservedVersion>,
    previews_bytes: u64,
}

impl RetainedBytes for PreviewCache {
    fn retained_bytes(&self) -> u64 {
        self.previews_bytes
            .saturating_add(self.retired_model_prefix.as_ref().map_or(0, |_| {
                std::mem::size_of::<(u32, pl_core::model::ModelPartsPrefix, usize)>() as u64
                    + RETAINED_ENTRY_OVERHEAD
            }))
    }
}

impl PreviewCache {
    pub(super) fn get(&self, id: &str) -> Option<&LivePreview> {
        self.previews.get(id)
    }

    pub(super) fn contains_key(&self, id: &str) -> bool {
        self.previews.contains_key(id)
    }

    pub(super) fn matching_ids(&self, prefix: String) -> impl Iterator<Item = String> + '_ {
        self.previews
            .range(prefix.clone()..)
            .take_while(move |(id, _)| id.starts_with(&prefix))
            .map(|(id, _)| id.clone())
    }

    pub(super) fn retain(&mut self, keep: impl Fn(&str) -> bool) {
        let before = self.previews.len();
        self.previews.retain(|id, _| keep(id));
        if self.previews.len() != before {
            self.previews_bytes = self.previews.iter().fold(0_u64, |total, (id, preview)| {
                total.saturating_add(preview_bytes(id, preview))
            });
            self.refresh_observed();
        }
    }

    fn refresh_observed(&mut self) {
        self.observed.clear();
        for preview in self.previews.values() {
            if let Some(observed) = &preview.observed {
                self.observed.insert(
                    observed.clone(),
                    ObservedVersion {
                        content: preview.observed_version,
                        ended: preview.shape.is_terminal(),
                        model_part: preview.model_part,
                    },
                );
            }
        }
    }

    /// Provider part identities this projection already showed for one attempt.
    ///
    /// The terminal commit must close the identity the streaming frames used, so every started
    /// provider part is part of the finalize set even when the outcome's own receipt cannot carry it.
    pub(super) fn started_provider_ids(&self, attempt_id: &str) -> Vec<String> {
        self.provider_previews(attempt_id)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Resident previews of one attempt's provider parts.
    ///
    /// A provider part's identity begins with its attempt's presentation prefix, and a `BTreeMap`
    /// keeps its keys in lexicographic order, so one attempt's identities are a single contiguous
    /// range: an effect that finalizes an attempt enumerates that attempt's parts instead of walking
    /// every part the response ever streamed. Only one attempt is ever resident (History staging
    /// clears the table when the attempt changes), so the range is bounded by that attempt.
    pub(super) fn provider_previews<'a>(
        &'a self,
        attempt_id: &str,
    ) -> impl Iterator<Item = (&'a String, &'a LivePreview)> + 'a {
        let prefix = super::super::order::presentation_prefix(attempt_id);
        self.previews
            .range(prefix.clone()..)
            .take_while(move |(id, _)| id.starts_with(prefix.as_str()))
    }

    pub(super) fn stage_history_model_previews(
        &mut self,
        placement: &mut PlacementWindow,
        state: &ThreadSnapshot,
        committed_at: i64,
        ledger: &ProvenanceLedger,
    ) -> Result<(), ProjectionError> {
        let Some(preview) = state.model_progress.as_ref() else {
            self.preview_attempt = None;
            self.clear_model_previews(|id| ledger.has_start(id));
            return Ok(());
        };
        let Some(attempt) = state
            .attempts
            .iter()
            .find(|attempt| attempt.attempt_id == preview.attempt_id)
        else {
            if self.preview_attempt.as_deref() == Some(preview.attempt_id.as_str()) {
                self.preview_attempt = None;
                self.clear_model_previews(|id| ledger.has_start(id));
            }
            return Ok(());
        };
        let at = committed_at;
        // A new attempt uses entirely new observation identities, so the previous attempt's caches
        // no longer apply.
        if self.preview_attempt.as_deref() != Some(preview.attempt_id.as_str()) {
            self.preview_attempt = Some(preview.attempt_id.clone());
            self.clear_model_previews(|id| ledger.has_start(id));
        }
        let progress = &preview.progress;
        // The producer retires the whole-channel aggregate observation the moment it itemizes the
        // response, yet the aggregate preview rows it published before still have to leave the window
        // and this projection, otherwise the same text would show up twice.
        if progress
            .parts()
            .iter()
            .any(|part| matches!(part.identity(), ObservedPartIdentity::Provider(_)))
        {
            for channel in [AggregateChannel::Text, AggregateChannel::Reasoning] {
                let id = aggregate_id(
                    &attempt.attempt_id,
                    progress.observation().generation,
                    channel,
                );
                let streaming = placement
                    .items()
                    .get(&id)
                    .is_some_and(|item| !item.state().is_terminal());
                if streaming || self.previews.contains_key(&id) {
                    placement.release_item(&id);
                    self.release_preview(&id);
                }
            }
        }
        for failed in &progress.observation().failed {
            self.stage_history_observation_parts(
                placement,
                attempt,
                failed.generation,
                &failed.parts,
                Some(&failed.message),
                at,
            )?;
        }
        self.stage_history_observation_parts(
            placement,
            attempt,
            progress.observation().generation,
            progress.parts(),
            None,
            at,
        )?;
        for (id, message) in
            super::super::responses::recovery_notices(&attempt.attempt_id, progress.observation())
        {
            let fields = BTreeMap::from([(BodyKey::Body, ContentBlock::from_text(&message))]);
            if self
                .previews
                .get(&id)
                .is_some_and(|entry| fields_equal(&entry.fields, &fields))
            {
                continue;
            }
            let revision = placement.bump_content_revision(&id);
            let order = placement
                .order_index_of()?
                .reserve_observed(&attempt.attempt_id, &id)
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            let created_at = placement.created_at(&id, at);
            let state = ExecutionShape::Text(ThreadTextItem::new(
                ThreadTextChannel::Commentary,
                String::new(),
                Vec::new(),
                ThreadContentLifecycle::completed(at),
            ));
            placement.store_fact(
                id.clone(),
                Fact {
                    ordinal: order,
                    revision,
                    created_at,
                    turn_id: attempt.turn_id.clone(),
                },
            );
            let entry = LivePreview {
                fields,
                observed: None,
                shape: static_state(&state),
                observed_version: progress.version(),
                model_part: None,
            };
            self.store_preview(id, entry);
        }
        Ok(())
    }

    fn stage_history_observation_parts(
        &mut self,
        placement: &mut PlacementWindow,
        attempt: &pl_core::thread::RequestAttempt,
        generation: u32,
        parts: &pl_core::model::ModelParts,
        failure: Option<&Arc<str>>,
        at: i64,
    ) -> Result<(), ProjectionError> {
        let (prefix, prefix_end) = parts.stable_prefix();
        let mut retired = if failure.is_none() {
            self.retired_model_prefix
                .as_ref()
                .filter(|(known_generation, known_prefix, _)| {
                    *known_generation == generation && *known_prefix == prefix
                })
                .map_or(0, |(_, _, retired)| *retired)
        } else {
            0
        };
        // Consume each shared part in place, never an allocated per-frame list of observations.
        let first = retired;
        for index in first..parts.len() {
            let part = parts.get(index).expect("model part index is in range");
            // An observation with no body yet is not a displayable preview; wait for its first byte.
            if part.is_empty() {
                continue;
            }
            // An identity whose observation version did not advance is not re-delivered, and this is
            // the one condition a long response hits for every already-delivered part on every
            // preview frame. It is decided on the observation's own short identity rather than on the
            // projection id: rebuilding that id and order-comparing its long sibling prefix for every
            // part every frame is what would make this loop cost O(parts) per frame for parts that
            // already delivered their newest body. [`LiveProjection::observed`] mirrors exactly the
            // `observed_version` of the identity's resident preview, so this skips the same set the
            // preview lookup would.
            //
            // It runs before the terminal test below because unchanged observations need no
            // further lookup in the channel's scoped identity table. Both
            // checks skip the same way (neither touches a delivered body or frame), so reordering
            // cannot pull a terminal identity back in: an advanced version still reaches, and is
            // rejected by, the terminal test.
            let key = observed_key(generation, part.identity());
            let observed_version = ObservedVersion {
                content: part.version(),
                ended: failure.is_some(),
                model_part: Some(super::super::current::ModelPartLocation { generation, index }),
            };
            if self.observed.get(&key) == Some(&observed_version) {
                continue;
            }
            let lifecycle = failure.map_or_else(ThreadContentLifecycle::streaming, |message| {
                ThreadContentLifecycle::failed(at, message.to_string())
            });
            let Some((id, field, static_item)) =
                observation_preview(&attempt.attempt_id, generation, part, &lifecycle)
            else {
                return Err(ProjectionError::UnsupportedOutput(
                    "provider presentation part does not match its item".into(),
                ));
            };
            // Within the still-active source, terminal identities cannot be pulled back by a later
            // frame. Ended sources were rejected before any identity or body is materialized.
            if placement.identity_is_terminal(&id)
                || placement
                    .items()
                    .get(&id)
                    .is_some_and(|previous| previous.state().is_terminal())
            {
                // Only a continuous prefix inside the immutable filled index
                // may retire. A still-active earlier part blocks this advance.
                if failure.is_none() && index == retired && index < prefix_end {
                    retired += 1;
                }
                continue;
            }
            // The observation's own content version advanced, so this is a real body change: advance
            // this projection's content version and deliver the frame. It is never skipped because
            // "the committed revision equals the commit watermark" — the content version and the
            // commit watermark are two different facts.
            let revision = placement.bump_content_revision(&id);
            let mut entry = match self.previews.get(&id).cloned() {
                Some(known) => known,
                None => {
                    // A preview's ordinal is allocated by the Runtime's shared execution-order
                    // index — the same allocator the kernel's presentation reservations and the
                    // terminal commit resolve from, so one identity keeps one ordinal across its
                    // preview, its reservation and its durable row without a history read.
                    let order = placement
                        .order_index_of()?
                        .reserve_observed(&attempt.attempt_id, &id)
                        .map_err(|error| ProjectionError::History(error.to_string()))?;
                    let created_at = placement.created_at(&id, at);
                    let shape = static_state(&static_item);
                    // Placement metadata, so the retained window bounds this identity like any other
                    // fact instead of keeping its body alive for the whole Turn.
                    placement.store_fact(
                        id.clone(),
                        Fact {
                            ordinal: order,
                            revision,
                            created_at,
                            turn_id: attempt.turn_id.clone(),
                        },
                    );
                    LivePreview {
                        fields: BTreeMap::new(),
                        // Filled in below with the key this part already resolved, so the identity is
                        // built once per delivered part instead of once per part per frame.
                        observed: None,
                        shape,
                        observed_version: part.version(),
                        model_part: observed_version.model_part,
                    }
                }
            };
            let shape = static_state(&static_item);
            if entry.shape != shape {
                entry.shape = shape;
            }
            entry.observed = Some(key);
            entry.observed_version = part.version();
            entry.model_part = observed_version.model_part;
            entry.fields.insert(field, part.content().clone());
            self.store_preview(id, entry);
        }
        if failure.is_none() {
            self.retired_model_prefix = (retired > 0).then_some((generation, prefix, retired));
        }
        Ok(())
    }

    /// Streaming output preview of a running task: the producer's own shared content block,
    /// delivered in the `tool.result` field and keyed by the stable call identity.
    ///
    /// The Thread publishes each opaque output identity with its immutable content block and its
    /// own observation version, so this shares the newest block instead of rebuilding it from an
    /// accumulated string: an unchanged identity is recognized by version (and by pointer inside the
    /// block comparison), a changed one carries a new block, and a bounded window that rolled over
    /// arrives as a block the consumer's baseline no longer extends. No JSON is encoded and no
    /// canonical `ExecutionItem` is materialized per chunk.
    pub(super) fn stage_history_tool_previews(
        &mut self,
        placement: &mut PlacementWindow,
        thread: &crate::Thread,
        state: &ThreadSnapshot,
        committed_at: i64,
    ) -> Result<(), ProjectionError> {
        for (task_id, progress) in state.tool_progress.iter() {
            let Some(task) = state.tasks.get(task_id) else {
                continue;
            };
            if task.status != pl_core::thread::task::TaskStatus::Running {
                continue;
            }
            // An observation with no body yet is not a displayable preview; wait for its first byte.
            if progress.bytes() == 0 {
                continue;
            }
            let id = super::super::order::tool_id(&task.call_id);
            // The original task invocation and the snapshot's shared progress block are sufficient;
            // History archive progress cannot decide whether this live producer still exists.
            let Some(committed) = current::task_tool_item(thread, state, task)? else {
                continue;
            };
            // A terminal item is never pulled back by a late streaming observation.
            if committed.state().is_terminal() {
                continue;
            }
            // Only an identity whose own version advanced is delivered: an unchanged observation
            // neither re-materializes its body nor re-emits a frame.
            if self
                .previews
                .get(&id)
                .is_some_and(|known| known.observed_version == progress.version())
            {
                continue;
            }
            let result_field = BodyKey::host(TOOL_RESULT_FIELD);
            // One shared block per identity: an unchanged window is the same `Arc`, and a rollover is
            // a different block, so the typed field diff reports a whole replacement instead of
            // appending onto a body that changed identity.
            let block = progress.content();
            // The tool identity's content version advances here so the terminal commit and the
            // preview converge on one counter even though the preview no longer leaves this owner.
            let revision = placement.bump_content_revision(&id);
            let mut entry = match self.previews.get(&id).cloned() {
                Some(known) => known,
                None => {
                    // Reuse the canonical item's body partner fields, swapping only the streamed
                    // result for a shared block; the preview keeps the runtime's own shape fact.
                    LivePreview {
                        fields: crate::studio::runtime::chat_item::content_fields(
                            committed.state(),
                        )
                        .map_err(|error| ProjectionError::History(error.to_string()))?,
                        // A tool-output preview is keyed by the call identity, not by a provider
                        // observation, so it never enters the provider observation index.
                        observed: None,
                        shape: static_state(committed.state()),
                        observed_version: progress.version(),
                        model_part: None,
                    }
                }
            };
            let ordinal = committed.ordinal;
            if !placement.has_fact(&id) {
                placement.store_fact(
                    id.clone(),
                    Fact {
                        ordinal,
                        revision,
                        created_at: committed_at,
                        turn_id: task.turn_id.clone(),
                    },
                );
            }
            entry.observed_version = progress.version();
            entry.fields.insert(result_field, block);
            self.store_preview(id, entry);
        }
        Ok(())
    }

    /// Stores one in-flight preview by projection id, keeping the byte estimate and the short-key
    /// observation index in step.
    pub(super) fn store_preview(&mut self, id: String, entry: LivePreview) {
        // One formula scores both sides of the replacement (`preview_entry_bytes`), so the running
        // total moves by the exact difference instead of re-deriving a smaller hand-copied estimate
        // that could omit the observation-index term.
        let next = preview_bytes(&id, &entry);
        let id_len = id.len() as u64;
        let observed = entry.observed.clone();
        let version = ObservedVersion {
            content: entry.observed_version,
            ended: entry.shape.is_terminal(),
            model_part: entry.model_part,
        };
        match self.previews.insert(id, entry) {
            Some(replaced) => {
                let replaced_bytes = preview_entry_bytes(id_len, &replaced);
                self.previews_bytes = self
                    .previews_bytes
                    .saturating_sub(replaced_bytes)
                    .saturating_add(next);
                // One projection id is a function of one observation identity, so a replacement under
                // it always carries the same short key and this branch is unreachable in the current
                // identity derivation. It is still handled: a replaced key whose mirror entry would
                // otherwise outlive its preview is dropped here instead of quietly making the hot
                // path skip an identity the preview map no longer holds.
                if replaced.observed != observed
                    && let Some(stale) = &replaced.observed
                {
                    self.observed.remove(stale);
                }
            }
            None => self.previews_bytes = self.previews_bytes.saturating_add(next),
        }
        // The index mirrors the delivered entry's own version, so the hot path can compare it
        // without rebuilding the projection id.
        if let Some(observed) = observed {
            self.observed.insert(observed, version);
        }
    }

    /// Releases one in-flight preview by projection id, keeping the byte estimate and the short-key
    /// observation index in step.
    pub(super) fn release_preview(&mut self, id: &str) {
        let Some(removed) = self.previews.remove(id) else {
            return;
        };
        self.previews_bytes = self
            .previews_bytes
            .saturating_sub(preview_bytes(id, &removed));
        if let Some(observed) = &removed.observed {
            self.observed.remove(observed);
        }
    }

    /// Model attempts do not own background tools: preserve their observation baselines until
    /// their own committed result or retained-fact release retires them.
    fn clear_model_previews(&mut self, preserve: impl Fn(&str) -> bool) {
        self.retired_model_prefix = None;
        self.previews.retain(|id, preview| {
            if preview.observed.is_none() || preserve(id) {
                return true;
            }
            self.previews_bytes = self
                .previews_bytes
                .saturating_sub(preview_bytes(id, preview));
            false
        });
        let retained = self
            .previews
            .values()
            .filter_map(|preview| preview.observed.as_ref())
            .collect::<HashSet<_>>();
        self.observed.retain(|key, _| retained.contains(key));
    }
}

/// Whether two field maps carry byte-identical text, compared by shared chain without materializing a
/// body. The field set itself participates: dropping or adding a field is a structural change.
pub(super) fn fields_equal(
    left: &BTreeMap<BodyKey, Arc<ContentBlock>>,
    right: &BTreeMap<BodyKey, Arc<ContentBlock>>,
) -> bool {
    left.len() == right.len()
        && left.iter().all(|(field, block)| {
            right
                .get(field)
                .is_some_and(|other| ContentBlock::text_eq(block, other))
        })
}
