//! Resolve placement and freeze completion drafts from one effect cut.
use super::{
    LiveProjection, ProjectionError, completion_ready,
    placement_window::Fact,
    prepared::{original_tool_result_body, review_delivery_facts},
    preview_cache::fields_equal,
};
use crate::studio::thread_projection::observation_parts::{classify, stable_id};
use crate::studio::{
    runtime::chat_item::{background_started_draft, completion_draft, static_state},
    storage::thread_writer::ExecutionMaterialization,
};
use crate::{ExecutionItem, ExecutionShape, ThreadContentLifecycle};
use pl_core::{
    chat::ChatDraft,
    model::ObservedPartIdentity,
    thread::{ThreadEffectBatch, ThreadSnapshot},
};
use std::collections::{BTreeMap, BTreeSet};

pub(super) struct ProjectedContent {
    pub(super) items: Vec<ExecutionItem>,
    pub(super) review_delivery: Vec<crate::thread_assembler::review_delivery::ReviewDeliveryFact>,
    pub(super) completion_drafts: Vec<ChatDraft>,
}

impl LiveProjection {
    /// Projects one effect's canonical content exactly once.
    ///
    /// Resident identities resolve against this projection's own tables and its channel index;
    /// missing content must be supplied by this effect's producer cut, never a storage lookup.
    /// The projected bodies are folded into this projection in the same step, so a later effect of
    /// the same Turn resolves them without a second projection or a storage lookup.
    pub(super) fn project(
        &mut self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
    ) -> Result<ProjectedContent, ProjectionError> {
        let review_delivery =
            review_delivery_facts(&thread.id, effect).map_err(ProjectionError::ReviewDelivery)?;
        let (turn_failures, hidden_inputs) = self.feed.projection_facts(effect, state);
        let provisional = super::super::project_effect_items(
            thread,
            state,
            effect,
            &BTreeMap::new(),
            &BTreeMap::new(),
            &BTreeSet::new(),
        )?;
        // The same identity set the durable writer enumerates: the items this effect produces,
        // the pruned inputs it still references, and the calls whose producing attempt left the
        // state. All three are resolved from the projection's own facts.
        let mut ids = provisional
            .items
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>();
        ids.extend(provisional.unresolved_inputs.iter().cloned());
        ids.extend(provisional.unresolved_calls.iter().cloned());
        // Only a channel this projection already started may be finalized by this effect. A channel
        // the response never produced must not be reserved here: reserving a name is not starting a
        // row, and an effect mentioning a channel would otherwise fabricate an empty aggregate item
        // (an empty `reasoning`/`text` row) the provider never emitted. A provider part the window
        // already showed is a started identity too: `finalize` has to name it even when the outcome's
        // own receipt cannot carry it, so this commit closes the identity the streaming frames used
        // instead of inventing a second aggregate one.
        if let Some(attempt) = &effect.attempt {
            for channel in ["reasoning", "text"] {
                let id = super::super::attempt_channel_id(&attempt.attempt_id, channel);
                if self.identity_is_started(&id) {
                    ids.push(id);
                }
            }
            ids.extend(self.previews.started_provider_ids(&attempt.attempt_id));
            // Later generations can still use channel aggregates (for example Chat).
            // They must be resolved as started identities just like generation zero.
            let prefix = super::super::order::observation_prefix(&attempt.attempt_id);
            ids.extend(self.previews.matching_ids(prefix));
        }
        let mut background_ids = Vec::new();
        if let Some(context) = &effect.context {
            let revision = match context {
                pl_core::thread::journal::ContextChange::Append { revision, .. } => *revision,
                pl_core::thread::journal::ContextChange::Replace(snapshot) => snapshot.revision,
            };
            for task in effect.tasks.iter() {
                if task
                    .acknowledgement
                    .as_ref()
                    .is_some_and(|ack| ack.context_revision == revision)
                {
                    let id = super::super::order::tool_background_started_id(&task.call_id);
                    if !self.placement.completion_exists(&id)? {
                        ids.push(id.clone());
                        background_ids.push((task.call_id.clone(), id));
                    }
                }
            }
        }
        let mut existing = self.placement.resolve(thread, ids);
        // Only a bounded reception may take its committed body from the preview the window already
        // showed: the stream stopped before the provider's authoritative item, so the prefix that did
        // arrive stays on the identity it was shown on instead of being lost. A normally received
        // response always carries its complete provider parts in its own receipt, so its committed
        // content never depends on what a subscriber happened to observe.
        if let Some(attempt) = &effect.attempt {
            for (id, item) in self.attempt_preview_items(
                &thread.id,
                state,
                &attempt.attempt_id,
                &attempt.turn_id,
                effect.committed_at,
            )? {
                // The provider part the window is showing is the body this commit must close. A
                // placement fact alone resolves to a release placeholder, so it must never beat the
                // preview that still holds the streamed text; a canonical committed payload (this
                // projection's own body) stays authoritative.
                if !self.placement.items().contains_key(&id)
                    && (self.provenance.has_start(&id)
                        || super::super::responses::keeps_bounded_preview(&attempt.outcome))
                {
                    existing.insert(id, item);
                }
            }
        }
        let projected = super::super::project_effect_items(
            thread,
            state,
            effect,
            &existing,
            &BTreeMap::new(),
            &hidden_inputs,
        )?;
        // 实时帧同样不允许带着无法补全的 identity 继续：投影失败由调用方转成报告并 fail-closed。
        projected.ensure_complete()?;
        let mut items = projected.items;
        // Model/Core already checked the final receipt against independently admitted members.
        // Their frozen product fact must not acquire the final attempt's time, source or revision.
        // A sealed presentation part is immutable, unlike mutable tool delivery metadata.
        let member_prefixes = effect
            .attempt
            .iter()
            .map(|attempt| &attempt.attempt_id)
            .chain(effect.model_members.iter().map(|member| &member.attempt_id))
            .map(|attempt| super::super::order::presentation_prefix(attempt))
            .collect::<BTreeSet<_>>();
        let index = self.placement.order_index_of()?;
        items.retain(|item| {
            !(matches!(
                item.state(),
                ExecutionShape::Text(_) | ExecutionShape::Thinking(_)
            ) && index.is_sealed(&item.id)
                && member_prefixes
                    .iter()
                    .any(|prefix| item.id.starts_with(prefix)))
        });
        for item in &mut items {
            if let crate::ExecutionShape::Turn(turn) = item.state()
                && let crate::TurnState::Failed(failed) = turn.state()
                && let Some(failure) = turn_failures.get(&item.turn_id)
            {
                let state = crate::TurnState::Failed(crate::FailedTurnState::new(
                    failed.started_at(),
                    failed.completed_at(),
                    failure.clone(),
                ));
                let turn = crate::ThreadTurnItem::new(state)
                    .with_input_id(turn.input_id().map(str::to_owned));
                *item = item.clone().with_state(crate::ExecutionShape::Turn(turn));
            }
        }
        // 先在候选载荷上计算内容版本；整批身份预算通过之前不修改投影自己的版本表。
        // 冷恢复的 canonical revision 仍是单调下限，已驻留身份继续使用本所有者的版本域。
        // 每一条目的内容版本由本投影自己的内容版本给出，和 effect 序号（提交 / 可靠保存水位）无关：
        // Turn 绑定、正文、结构或终态状态真的变了才递增，否则沿用旧版本（例如只推进 saved 的保存确认，
        // 或与上次完全相同的重新投影）。该版本同时被流式预览使用，因此同一身份的预览与终态沿同一个
        // 计数器收束，终态不会被预览版本挡住，旧保存回执也无法确认它没写过的新载荷。
        for item in items.iter_mut() {
            // The payload this revision was last delivered with, when this projection still knows
            // it: the deterministic comparison partner for a repeat projection.
            let previous = self
                .placement
                .items()
                .get(item.id.as_str())
                .or_else(|| existing.get(item.id.as_str()))
                .map(|previous| {
                    (
                        previous.ordinal,
                        previous.turn_id.clone(),
                        previous.created_at,
                        previous.updated_at,
                    )
                });
            let changed = self.content_changed(item.id.as_str(), item, &existing)?;
            let stable_terminal = self
                .placement
                .items()
                .get(&item.id)
                .or_else(|| existing.get(&item.id))
                .filter(|previous| {
                    !changed
                        && previous.is_terminal()
                        && matches!(previous.state(), ExecutionShape::Turn(_))
                });
            let mut current = stable_terminal.map_or_else(
                || self.placement.revision(item.id.as_str()),
                |previous| previous.revision,
            );
            if !self.placement.items().contains_key(&item.id) {
                current = current.max(
                    existing
                        .get(&item.id)
                        .map_or(0, |previous| previous.revision),
                );
            }
            item.revision = match (current, changed) {
                (current, false) if current > 0 => current,
                _ => current.saturating_add(1),
            };
            // One `(identity, revision)` pair is one canonical payload. A repeat projection whose
            // body, structure and terminal shape are unchanged therefore keeps the placement and the
            // timestamps of the payload it was last delivered with instead of restamping the
            // projection clock: otherwise the same revision would be written twice with two
            // different payloads, and the durable row's own revision fence rejects that as a real
            // conflict. A body that did change takes the fresh stamp together with its new version.
            if !changed && let Some((ordinal, turn_id, created_at, updated_at)) = previous {
                item.ordinal = ordinal;
                item.turn_id = turn_id;
                item.created_at = created_at;
                item.updated_at = updated_at;
            }
        }
        let index = self.placement.order_index_of()?;
        let mut backgrounds = Vec::with_capacity(background_ids.len());
        for (call_id, id) in &background_ids {
            let item = items
                .iter()
                .find(|item| item.id == super::super::order::tool_id(call_id))
                .ok_or_else(|| ProjectionError::MissingDurableToolCall(call_id.clone()))?;
            backgrounds.push(ExecutionMaterialization {
                item_id: id,
                ordinal: None,
                ..ExecutionMaterialization::from_item(item)
            });
        }
        let completion_drafts =
            self.prepare_completion_drafts(thread, state, effect, &items, &background_ids)?;
        // No projection body, revision or report accumulator changes until every
        // identity and stamp in this effect has passed the same atomic budget check.
        let orders = index
            .materialize_execution_batch(
                items
                    .iter()
                    .map(ExecutionMaterialization::from_item)
                    .chain(backgrounds),
                effect.sequence,
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        for item in &mut items {
            item.ordinal = orders[&item.id];
        }
        items.sort_by_key(|item| item.ordinal);
        // Execution ordinals still order execution material, but must never
        // reorder the producer's terminal receipts before Session assigns seq.
        self.feed.remember_projection(turn_failures, hidden_inputs);
        self.placement.adopt_revisions(&existing);
        for item in &items {
            self.placement.raise_revision(&item.id, item.revision);
            self.record(item.clone())?;
        }
        for delivery in effect.deliveries.iter() {
            if let Some(finish) = super::super::completions::committed_finish(delivery)
                && let Some(turn) = items
                    .iter()
                    .find(|item| item.id == super::super::order::tool_id(&delivery.call_id))
                    .map(|item| item.turn_id.clone())
            {
                self.results.entry(turn).or_default().finish = Some(finish);
            }
        }
        Ok(ProjectedContent {
            items,
            review_delivery,
            completion_drafts,
        })
    }

    /// Freezes and publishes this effect's completion batch, exactly once per identity.
    ///
    /// An item contributes a completion only at its reliable completion boundary — a terminal
    /// execution fact inside an admitted effect: an accepted input is complete at acceptance, a
    /// tool result seals when its own call finishes (a sibling tool may still be running), a text
    /// or thinking part seals at the attempt's finalization or its explicit bounded-interrupted
    /// boundary, and a Turn seals at its terminal transition. Non-terminal bodies stay live facts
    /// of the runtime and never occupy the completion timeline. An identity that already sealed —
    /// including an earlier terminal identity or a later higher-revision execution repair —
    /// is skipped: the completion atom is immutable and one identity publishes once.
    ///
    /// # Errors
    /// Propagates the completion session's typed failures (payload conflict, sequence exhaustion,
    /// retained-capacity refusal) as projection failures; nothing is marked sealed until the whole batch
    /// published.
    fn prepare_completion_drafts(
        &self,
        thread: &crate::Thread,
        state: &ThreadSnapshot,
        effect: &ThreadEffectBatch,
        items: &[ExecutionItem],
        background_ids: &[(String, String)],
    ) -> Result<Vec<ChatDraft>, ProjectionError> {
        let mut drafts = Vec::new();
        let owner_id = self
            .current
            .owner_id()
            .ok_or_else(|| ProjectionError::History("missing database identity".into()))?;
        // Completion order within an effect: accepted inputs, accepted inbox,
        // then its original terminal receipts. All share Session's one allocator.
        for (index, change) in effect.inputs.iter().enumerate() {
            if let pl_core::thread::input::InputChange::Accepted(record) = change
                && let Some(draft) = crate::studio::runtime::chat_item::accepted_input_draft(
                    thread,
                    record,
                    crate::ChatFactPosition {
                        effect_seq: effect.sequence,
                        suborder: u32::try_from(
                            index.checked_add(1).ok_or(ProjectionError::Count)?,
                        )
                        .map_err(|_| ProjectionError::Count)?,
                    },
                    effect.committed_at,
                    owner_id,
                )?
            {
                drafts.push(draft);
            }
        }
        for (index, record) in effect.inbox.iter().enumerate() {
            // A forwarded final task result is already sealed by its real tool producer.
            if state
                .tasks
                .values()
                .chain(effect.tasks.iter())
                .any(|task| task.id == record.message.source_id)
            {
                continue;
            }
            if let Some(draft) = crate::studio::runtime::chat_item::accepted_inbox_draft(
                thread,
                record,
                crate::ChatFactPosition {
                    effect_seq: effect.sequence,
                    suborder: u32::try_from(
                        effect
                            .inputs
                            .len()
                            .checked_add(1)
                            .ok_or(ProjectionError::Count)?
                            .checked_add(index)
                            .ok_or(ProjectionError::Count)?,
                    )
                    .map_err(|_| ProjectionError::Count)?,
                },
                effect.committed_at,
                owner_id,
            )? {
                drafts.push(draft);
            }
        }

        // Share the exact receipt/identity matching rule with fresh admission. Replace still
        // materializes restored facts, but never grants a fresh reservation.
        for (task, receipt) in super::super::order::background_receipts(effect) {
            let id = super::super::order::tool_background_started_id(&task.call_id);
            if !background_ids.iter().any(|(_, candidate)| candidate == &id) {
                continue;
            }
            let receipt = receipt.ok_or_else(|| {
                ProjectionError::History(
                    "background acknowledgement does not match its unique committed context fact"
                        .into(),
                )
            })?;
            let item = items
                .iter()
                .find(|item| item.id == super::super::order::tool_id(&task.call_id))
                .ok_or_else(|| ProjectionError::MissingDurableToolCall(task.call_id.clone()))?;
            let draft = background_started_draft(
                item,
                &task.id,
                &super::super::content::text_content(&receipt.content),
                effect.sequence,
                effect.committed_at,
                self.current
                    .owner_id()
                    .ok_or_else(|| ProjectionError::History("missing database identity".into()))?,
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
            drafts.push(draft);
        }
        for item in items {
            if crate::studio::runtime::chat_item::atom(item).kind == crate::ChatAtomKind::Input
                || state.inputs.iter().any(|record| record.input.id == item.id)
                || effect.inputs.iter().any(|change| match change {
                    pl_core::thread::input::InputChange::Accepted(record) => {
                        record.input.id == item.id
                    }
                    pl_core::thread::input::InputChange::Transition { id, .. } => id == &item.id,
                })
                || state
                    .inbox
                    .iter()
                    .chain(effect.inbox.iter())
                    .any(|record| super::super::order::message_id(&record.message.id) == item.id)
            {
                continue;
            }
            if !completion_ready(item) || self.placement.order_index_of()?.is_sealed(&item.id) {
                continue;
            }
            // A cold reliable-output repair may carry a new execution-item revision
            // without a resident completion qualification. Read that exact original
            // identity only for repair targets; never reseal its supplemented payload.
            if effect
                .delivery_repairs
                .iter()
                .any(|repair| super::super::order::tool_id(&repair.call_id) == item.id)
                && self.placement.completion_exists(&item.id)?
            {
                continue;
            }
            drafts.push(
                completion_draft(
                    item,
                    effect.sequence,
                    self.current.owner_id().ok_or_else(|| {
                        ProjectionError::History("missing database identity".into())
                    })?,
                    original_tool_result_body(item, state),
                )
                .map_err(|error| ProjectionError::History(error.to_string()))?,
            );
        }
        Ok(drafts)
    }

    /// Whether this projected item differs from the **persistable payload** last delivered for it.
    ///
    /// The payload is the turn binding (a queued input/item identity that is only later bound to the
    /// Turn that consumes it, so the binding is durable content and not placement metadata), the
    /// dynamic fields ([`crate::studio::runtime::chat_item::content_fields`], compared by shared
    /// chain without materializing a body) plus the structure / terminal shape
    /// ([`crate::studio::runtime::chat_item::static_state`], covering kind, attachments, lifecycle and
    /// tool state). None of them includes the `ExecutionItem` timestamps that only this projection
    /// restamps, so a repeated projection keeps its version — and with it a byte-identical payload —
    /// while a real transition (turn binding, terminal admission, tool state) always reads as a
    /// change.
    fn content_changed(
        &self,
        id: &str,
        item: &ExecutionItem,
        existing: &BTreeMap<String, ExecutionItem>,
    ) -> Result<bool, ProjectionError> {
        let candidate_fields = crate::studio::runtime::chat_item::content_fields(item.state())
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        let candidate_shape = static_state(item.state());
        if let Some(preview) = self.previews.get(id) {
            return Ok(preview.shape != candidate_shape
                || !fields_equal(&candidate_fields, &preview.fields));
        }
        // A committed fact resident in memory wins; on cold recovery the canonical fact resolved by
        // this pass is compared the same way, so a payload identical to the stored one is not treated
        // as a first delivery and does not raise the version for nothing.
        Ok(
            match self.placement.items().get(id).or_else(|| existing.get(id)) {
                Some(previous) => {
                    previous.turn_id != item.turn_id
                        || static_state(previous.state()) != candidate_shape
                        || !fields_equal(
                            &candidate_fields,
                            &crate::studio::runtime::chat_item::content_fields(previous.state())
                                .map_err(|error| ProjectionError::History(error.to_string()))?,
                        )
                }
                None => true,
            },
        )
    }

    /// Whether one identity is a row this projection or the Runtime's order index already holds.
    ///
    /// Placement metadata alone does not make an identity started: a fact can outlive the preview
    /// it described (the window replaces an aggregate preview the moment the adapter itemizes the
    /// response), and reserving its name would fabricate a terminal row nothing ever showed.
    fn identity_is_started(&self, id: &str) -> bool {
        self.placement.items().contains_key(id)
            || self.previews.contains_key(id)
            || self.placement.has_assignment(id)
    }

    /// Canonical items for one attempt's original in-flight provider parts.
    ///
    /// Read only for a **bounded** reception (see [`super::super::responses::keeps_bounded_preview`]). The
    /// effect's own `HistoryExport.state.model_progress` is the only source; a newer live preview or
    /// a later canonical final cannot replace that original cut. The terminal projection materializes
    /// the received prefix here, and
    /// [`super::super::responses::finalize_missing_presentation`] closes it
    /// on the same identity. A normally received response takes its body from its own receipt instead.
    /// Only provider-part identities qualify — an aggregate channel is not a provider part, and its own
    /// liveness is decided by [`LiveProjection::identity_is_started`].
    fn attempt_preview_items(
        &mut self,
        thread_id: &str,
        state: &ThreadSnapshot,
        attempt_id: &str,
        turn_id: &str,
        committed_at: i64,
    ) -> Result<Vec<(String, ExecutionItem)>, ProjectionError> {
        let Some(progress) = state
            .model_progress
            .as_ref()
            .filter(|progress| progress.attempt_id == attempt_id)
        else {
            return Ok(Vec::new());
        };
        let generation = progress.progress.observation().generation;
        let prefix = super::super::order::presentation_prefix(attempt_id);
        let mut items = Vec::new();
        for part in progress.progress.parts().iter() {
            if part.is_empty() || !matches!(part.identity(), ObservedPartIdentity::Provider(_)) {
                continue;
            }
            let identity = part.identity();
            let kind = classify(identity).ok_or_else(|| {
                ProjectionError::UnsupportedOutput(
                    "interrupted provider part does not match its item".into(),
                )
            })?;
            let id = stable_id(attempt_id, generation, identity);
            if !id.starts_with(&prefix) || self.placement.identity_is_terminal(&id) {
                continue;
            }
            let (_, state) = kind.shape(part.text(), &ThreadContentLifecycle::streaming());
            let ordinal = self
                .placement
                .order_index_of()?
                .reserve_observed(attempt_id, &id)
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            let revision = self
                .placement
                .revision(&id)
                .max(1)
                .max(part.version().max(1));
            self.placement.raise_revision(&id, revision);
            self.placement.store_fact(
                id.clone(),
                Fact {
                    ordinal,
                    revision,
                    created_at: committed_at,
                    turn_id: turn_id.to_owned(),
                },
            );
            items.push((
                id.clone(),
                ExecutionItem::new(
                    id,
                    crate::ItemStamp {
                        thread_id: std::borrow::Cow::Owned(thread_id.to_owned()),
                        turn_id: std::borrow::Cow::Owned(turn_id.to_owned()),
                        ordinal,
                        revision,
                        created_at: committed_at,
                        updated_at: committed_at,
                    },
                    state,
                ),
            ));
        }
        Ok(items)
    }

    /// Records one projected payload and keeps its revision strictly monotonic.
    ///
    /// The ordinal is the placement this projection resolved and the revision is this projection's own
    /// content version (the placement window), never the effect sequence that happened to
    /// commit the payload. Live frames, resubscription, the window and the durable writer therefore
    /// agree on one content version per identity, while the effect sequence stays only the commit /
    /// reliable-save watermark. A stale payload is ignored rather than renumbered.
    fn record(&mut self, item: ExecutionItem) -> Result<(), ProjectionError> {
        if item.ordinal == 0 {
            return Err(ProjectionError::ItemOrder(item.id));
        }
        if self
            .placement
            .items()
            .get(&item.id)
            .is_some_and(|previous| previous.revision > item.revision)
        {
            // A stale payload never regresses a newer body; it produces no frame either way.
            return Ok(());
        }
        // A committed fact replaces the same identity's preview: dropping the cache makes the next
        // streaming observation rebuild its static meta and argument partner fields from the freshly
        // committed canonical fact instead of reusing a stale preview.
        self.previews.release_preview(&item.id);
        // The channel index holds scoped terminal/completion markers alongside execution placement.
        self.placement.fact(&item);
        self.observe_result(&item);
        self.placement.store_item(item);
        Ok(())
    }

    /// Adds one committed payload to the report facts of its Turn.
    fn observe_result(&mut self, item: &ExecutionItem) {
        if item.turn_id.is_empty() {
            return;
        }
        self.results
            .entry(item.turn_id.clone())
            .or_default()
            .observe(item);
    }
}
