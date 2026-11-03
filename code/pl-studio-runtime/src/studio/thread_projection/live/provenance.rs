//! Actual lifecycle folded by the existing projection owner. No display ranges or group state.
use super::*;
use pl_protocol::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatEntry,
    ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome,
};

type Changes = (Vec<ChatEntry>, Vec<ChatSourceState>);

fn position(
    effect: &ThreadEffectBatch,
    entries: usize,
) -> Result<ChatFactPosition, ProjectionError> {
    Ok(ChatFactPosition {
        effect_seq: effect.sequence,
        suborder: u32::try_from(entries)
            .map_err(|_| ProjectionError::History("effect provenance position overflow".into()))?,
    })
}

fn member_base(effect: &ThreadEffectBatch) -> usize {
    // Positions name slots in the immutable effect, not the number of notifications emitted.
    // Duplicate suppression or activation restore must never shift another fact's evidence.
    1_usize
        .saturating_add(effect.inputs.len())
        .saturating_add(effect.context_compactions.len())
        .saturating_add(effect.model_member_starts.len())
}

impl LiveProjection {
    /// Execution activation only. Passive conversation opens never create this owner or scan history.
    pub(in crate::studio) async fn restore_current(
        &mut self,
        chat: &Session,
        thread: &pl_protocol::Thread,
        state: &ThreadSnapshot,
    ) -> Result<(), ProjectionError> {
        if self.provenance_restored {
            return Err(ProjectionError::History(
                "current provenance was already restored".into(),
            ));
        }
        let history = self
            .execution_history
            .clone()
            .ok_or_else(|| ProjectionError::History("execution history is not bound".into()))?;
        let saved = history
            .conversation_current()
            .await
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        self.provenance_restored = true;
        let Some(saved) = saved else {
            return Ok(());
        };
        if saved.atoms.len() > LIVE_ITEM_WINDOW || saved.sources.len() > LIVE_ITEM_WINDOW {
            return Err(ProjectionError::History(
                "saved current provenance exceeds retained window".into(),
            ));
        }
        for source in saved.sources {
            self.source_states.insert(source.source.clone(), source);
        }
        for atom in saved.atoms {
            if !matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
                || atom.payload.is_some()
                || atom.completion_seq.is_some()
                || atom.source_state.is_some()
            {
                return Err(ProjectionError::History(
                    "saved current contains a completed atom".into(),
                ));
            }
            if self.items.get(&atom.id).is_some_and(completion_ready) {
                continue;
            }
            // An operation start owns provenance only, not a provisional business item or body.
            // Restore it from the same saved current without inventing canonical execution content.
            if atom.kind == ChatAtomKind::Compaction {
                if !matches!(&atom.source, ChatSourceId::Operation { operation_id }
                    if atom.id == super::super::order::compaction_id(operation_id))
                    || atom.delivery != ChatDeliveryKind::Independent
                    || !atom.contents.is_empty()
                {
                    return Err(ProjectionError::History(
                        "saved active compaction has invalid operation provenance".into(),
                    ));
                }
                self.atom_starts.insert(atom.id.clone(), atom);
                continue;
            }
            let shape = match atom.kind {
                pl_protocol::ChatAtomKind::Text => ThreadItemState::Text(ThreadTextItem::new(
                    atom.text_channel.ok_or_else(|| {
                        ProjectionError::History("saved active text has no channel".into())
                    })?,
                    String::new(),
                    Vec::new(),
                    ThreadContentLifecycle::streaming(),
                )),
                pl_protocol::ChatAtomKind::Reasoning => {
                    ThreadItemState::Thinking(ThreadThinkingItem::new(
                        Vec::new(),
                        Vec::new(),
                        ThreadContentLifecycle::streaming(),
                    ))
                }
                _ => self
                    .items
                    .get(&atom.id)
                    .map(|item| static_state(item.state()))
                    .ok_or_else(|| {
                        ProjectionError::History(format!(
                            "saved active {} has no canonical execution item",
                            atom.id
                        ))
                    })?,
            };
            let mut fields = BTreeMap::new();
            // Read only the exact unfinished content owners named by this small current, not a history
            // scan. The restored prefix must remain available if recovery interrupts its attempt.
            for content in &atom.contents {
                let pl_protocol::ContentTarget::Body { owner, key } = &content.reference.target
                else {
                    return Err(ProjectionError::History(
                        "saved active content is not a body".into(),
                    ));
                };
                if self.current.database_id() != Some(content.reference.database_id.as_str()) {
                    return Err(ProjectionError::History(
                        "saved active content belongs to another database".into(),
                    ));
                }
                let content_key = pl_core::chat::ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(owner)
                        .map_err(|error| ProjectionError::History(error.to_string()))?,
                    key: key.clone(),
                };
                let reference = pl_core::chat::ContentRef::Body(content_key.clone());
                let mut bytes = Vec::new();
                let mut generation = None;
                let mut length = None;
                loop {
                    let window = pl_core::chat::ChatHistory::read_content(
                        &history,
                        &pl_core::chat::ContentReadRequest {
                            epoch: chat.epoch(),
                            reference: reference.clone(),
                            offset: bytes.len() as u64,
                            max_bytes: 64 * 1024,
                            generation,
                        },
                    )
                    .await
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
                    if generation.is_some_and(|generation| generation != window.generation)
                        || window.offset != bytes.len() as u64
                        || window.bytes.as_bytes().len() > 64 * 1024
                        || window.offset > window.available_through
                        || window.bytes.as_bytes().len() as u64
                            > window.available_through - window.offset
                    {
                        return Err(ProjectionError::History(
                            "saved active content changed generation".into(),
                        ));
                    }
                    generation = Some(window.generation);
                    let length = *length.get_or_insert(window.available_through);
                    let remaining = usize::try_from(length.saturating_sub(bytes.len() as u64))
                        .map_err(|_| {
                            ProjectionError::History("saved active content length overflow".into())
                        })?;
                    let chunk = window.bytes.as_bytes();
                    if remaining > 0 && chunk.is_empty() {
                        return Err(ProjectionError::History(
                            "saved active content made no progress".into(),
                        ));
                    }
                    bytes.extend_from_slice(&chunk[..chunk.len().min(remaining)]);
                    if bytes.len() as u64 == length {
                        break;
                    }
                }
                let text = String::from_utf8(bytes)
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
                self.current
                    .restore_generation(
                        content_key,
                        generation.ok_or_else(|| {
                            ProjectionError::History("saved body returned no generation".into())
                        })?,
                    )
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
                let part = |prefix: &str| {
                    key.strip_prefix(prefix)
                        .and_then(|index| index.parse::<u32>().ok())
                };
                let key = if key == "body" {
                    BodyKey::Body
                } else if let Some(index) = part("part.reasoningText.") {
                    BodyKey::Part(PresentationPart::ReasoningText(index))
                } else if let Some(index) = part("part.summaryText.") {
                    BodyKey::Part(PresentationPart::SummaryText(index))
                } else if let Some(index) = part("part.outputText.") {
                    BodyKey::Part(PresentationPart::OutputText(index))
                } else {
                    BodyKey::host(key)
                };
                fields.insert(key, ContentBlock::from_text(&text));
            }
            let canonical = self.items.get(&atom.id);
            let fact = self.facts.get(&atom.id);
            let created_at = canonical
                .map(|item| item.created_at)
                .or_else(|| fact.map(|fact| fact.created_at))
                .or(atom.started_at)
                .unwrap_or(0);
            let revision = canonical
                .map(|item| item.revision)
                .or_else(|| fact.map(|fact| fact.revision))
                .unwrap_or(1);
            let updated_at = canonical.map_or(created_at, |item| item.updated_at);
            let mut item = ThreadItem::new(
                atom.id.clone(),
                history.thread_id().into(),
                atom.turn_id.clone().unwrap_or_default(),
                atom.source_order
                    .or_else(|| fact.map(|fact| fact.ordinal))
                    .unwrap_or(0),
                revision,
                created_at,
                updated_at,
                shape.clone(),
            );
            let index = self.order_index_of()?;
            let orders = index
                .materialize_execution_batch(
                    std::iter::once(ExecutionMaterialization::from_item(&item)),
                    saved.source_effect_seq,
                )
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            item.ordinal = orders[&item.id];
            if let Some(attempt) = &atom.attempt_id {
                index
                    .reserve_observed(attempt, &atom.id)
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
            }
            self.fact(&item);
            self.store_preview(
                atom.id.clone(),
                LivePreview {
                    fields,
                    observed: None,
                    shape,
                    observed_version: 0,
                },
            );
            self.atom_starts.insert(atom.id.clone(), atom);
        }
        self.sync_provenance()?;
        // Reliable effects are folded before streaming on activation. Install the restored blocks
        // in the original current owner now: completion freezing reads item_contents before the
        // next effect freezes current, and must see these exact generations and content owners.
        let active = self.current_texts();
        self.current
            .observe(thread, state, saved.source_effect_seq, active)
            .map(|_| ())
            .map_err(|error| ProjectionError::History(error.to_string()))
    }
    pub(in crate::studio) fn confirm_sources(&mut self, through: u64) {
        self.source_states
            .retain(|_, state| state.ended.is_none_or(|at| at.effect_seq > through));
    }

    pub(super) fn sync_provenance(&mut self) -> Result<(), ProjectionError> {
        let database = self.current.database_id().ok_or_else(|| {
            ProjectionError::History("provenance has no database identity".into())
        })?;
        for atom in self.atom_starts.values_mut() {
            if let Some(preview) = self.previews.get(&atom.id) {
                atom.contents = preview
                    .fields
                    .keys()
                    .filter_map(|key| {
                        Some(pl_protocol::ChatAtomContent {
                            role: crate::studio::runtime::chat_item::atom_content_role(key)?,
                            reference: pl_protocol::ContentRef {
                                database_id: database.into(),
                                target: pl_protocol::ContentTarget::Body {
                                    owner: pl_protocol::ContentOwner::Item {
                                        item_id: atom.id.clone(),
                                    },
                                    key: key.as_key(),
                                },
                            },
                        })
                    })
                    .collect();
            }
        }
        self.current.provenance(
            self.source_states.values().cloned().collect(),
            self.atom_starts.values().cloned().collect(),
        );
        Ok(())
    }

    fn source_change(
        &mut self,
        source: ChatSourceId,
        outcome: Option<ChatTerminalOutcome>,
        actual_start: bool,
        at: ChatFactPosition,
        changes: &mut Changes,
    ) -> Result<(), ProjectionError> {
        let old = self.source_states.get(&source);
        let started = old
            .and_then(|old| old.started)
            .or(actual_start.then_some(at));
        let state = ChatSourceState {
            source: source.clone(),
            lifecycle: outcome.map_or(ChatSourceLifecycle::Active, |outcome| {
                ChatSourceLifecycle::Ended { outcome }
            }),
            started,
            ended: outcome.map(|_| at),
        };
        if old == Some(&state) {
            return Ok(());
        }
        self.source_states.insert(source, state.clone());
        changes.0.push(ChatEntry::Source(state.clone()));
        changes.1.push(state);
        Ok(())
    }

    pub(super) fn begin_provenance(
        &mut self,
        effect: &ThreadEffectBatch,
    ) -> Result<Changes, ProjectionError> {
        let mut changes = (Vec::new(), Vec::new());
        if let Some(turn) = &effect.turn {
            let outcome = match turn.state {
                pl_core::thread::TurnState::Running => None,
                pl_core::thread::TurnState::Failed { .. } => Some(ChatTerminalOutcome::Failed),
                pl_core::thread::TurnState::Cancelled | pl_core::thread::TurnState::Interrupted => {
                    Some(ChatTerminalOutcome::Cancelled)
                }
                pl_core::thread::TurnState::Finished(_) => Some(ChatTerminalOutcome::Completed),
            };
            self.source_change(
                ChatSourceId::ForegroundTurn {
                    turn_id: turn.turn_id.clone(),
                },
                outcome,
                outcome.is_none(),
                position(effect, 0)?,
                &mut changes,
            )?;
        }
        for (index, change) in effect.inputs.iter().enumerate() {
            if let pl_core::thread::input::InputChange::Accepted(record) = change {
                self.source_change(
                    ChatSourceId::Input {
                        input_id: record.input.id.clone(),
                    },
                    Some(ChatTerminalOutcome::Completed),
                    true,
                    position(effect, 1 + index)?,
                    &mut changes,
                )?;
            }
        }
        for (index, event) in effect.context_compactions.iter().enumerate() {
            use pl_core::thread::{
                ContextCompactionEvent as Event, ContextCompactionOutcome as Outcome,
            };
            let (id, outcome) = match event {
                Event::Started { operation_id, .. } => (operation_id, None),
                Event::Finished {
                    operation_id,
                    outcome,
                } => (
                    operation_id,
                    Some(match outcome {
                        Outcome::Failed { .. } => ChatTerminalOutcome::Failed,
                        Outcome::Cancelled => ChatTerminalOutcome::Cancelled,
                        Outcome::Changed { .. } | Outcome::Unchanged => {
                            ChatTerminalOutcome::Completed
                        }
                    }),
                ),
            };
            let source = ChatSourceId::Operation {
                operation_id: id.clone(),
            };
            let at = position(
                effect,
                1_usize
                    .saturating_add(effect.inputs.len())
                    .saturating_add(index),
            )?;
            self.source_change(source.clone(), outcome, outcome.is_none(), at, &mut changes)?;
            if let Event::Started {
                turn_id,
                attempt_id,
                ..
            } = event
            {
                let item_id = super::super::order::compaction_id(id);
                if self.atom_starts.contains_key(&item_id) || self.identity_is_terminal(&item_id) {
                    continue;
                }
                let atom = ChatAtom {
                    id: item_id.clone(),
                    completion_item_id: None,
                    completion_seq: None,
                    source,
                    source_state: None,
                    source_order: None,
                    kind: ChatAtomKind::Compaction,
                    delivery: ChatDeliveryKind::Independent,
                    lifecycle: ChatAtomLifecycle::Active {
                        started: Some(at),
                        status: ChatActiveStatus::Running,
                    },
                    turn_id: turn_id.clone(),
                    attempt_id: attempt_id.clone(),
                    tool: None,
                    text_channel: None,
                    started_at: Some(effect.committed_at),
                    finished_at: None,
                    contents: Vec::new(),
                    payload: None,
                };
                self.atom_starts.insert(item_id, atom.clone());
                changes.0.push(ChatEntry::Atom(Box::new(atom)));
            }
        }
        for (index, start) in effect.model_member_starts.iter().enumerate() {
            let (id, field, shape) = observation_start(
                &start.attempt_id,
                start.generation,
                &start.identity,
                &ThreadContentLifecycle::streaming(),
            )
            .ok_or_else(|| {
                ProjectionError::UnsupportedOutput("invalid canonical member start".into())
            })?;
            if self.atom_starts.contains_key(&id) || self.identity_is_terminal(&id) {
                continue;
            }
            let order = self
                .order_index_of()?
                .reserve_observed(&start.attempt_id, &id)
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            let item = ThreadItem::new(
                id.clone(),
                effect.thread_id.clone(),
                start.turn_id.clone(),
                order,
                self.bump_content_revision(&id),
                effect.committed_at,
                effect.committed_at,
                shape.clone(),
            );
            self.fact(&item);
            // An empty canonical part is still an identity, including on failure without progress.
            if !self.previews.contains_key(&id) {
                self.store_preview(
                    id.clone(),
                    LivePreview {
                        fields: BTreeMap::from([(field, ContentBlock::from_text(""))]),
                        observed: None,
                        shape,
                        observed_version: 0,
                    },
                );
            }
            let mut atom = crate::studio::runtime::chat_item::atom(&item);
            atom.attempt_id = Some(start.attempt_id.clone());
            atom.started_at = Some(effect.committed_at);
            atom.lifecycle = ChatAtomLifecycle::Active {
                started: Some(position(
                    effect,
                    1_usize
                        .saturating_add(effect.inputs.len())
                        .saturating_add(effect.context_compactions.len())
                        .saturating_add(index),
                )?),
                status: ChatActiveStatus::Running,
            };
            self.atom_starts.insert(id, atom.clone());
            changes.0.push(ChatEntry::Atom(Box::new(atom)));
        }
        if self.atom_starts.len() > LIVE_ITEM_WINDOW {
            return Err(ProjectionError::History(
                "active member provenance exceeds retained window".into(),
            ));
        }
        Ok(changes)
    }

    pub(super) fn complete_provenance(
        &mut self,
        effect: &ThreadEffectBatch,
        items: &[ThreadItem],
        drafts: &mut [ChatDraft],
        changes: &mut Changes,
    ) -> Result<(), ProjectionError> {
        for (item_index, item) in items.iter().enumerate().filter(|(_, item)| {
            !completion_ready(item)
                && !matches!(
                    item.state(),
                    ThreadItemState::Inference(_) | ThreadItemState::Turn(_)
                )
        }) {
            if let ThreadItemState::Tool(tool) = item.state() {
                if self.order_index_of()?.is_sealed(
                    &super::super::order::tool_background_started_id(
                        tool.invocation().tool_call_id(),
                    ),
                ) {
                    continue;
                }
                if !self.previews.contains_key(&item.id) {
                    let mut fields =
                        crate::studio::runtime::chat_item::content_fields(item.state())
                            .map_err(|error| ProjectionError::History(error.to_string()))?;
                    fields.retain(|key, _| {
                        crate::studio::runtime::chat_item::atom_content_role(key).is_some()
                    });
                    self.store_preview(
                        item.id.clone(),
                        LivePreview {
                            fields,
                            observed: None,
                            shape: static_state(item.state()),
                            observed_version: 0,
                        },
                    );
                }
            }
            let old = self.atom_starts.get(&item.id);
            let mut atom = crate::studio::runtime::chat_item::atom(item);
            atom.source = old.map_or_else(|| atom.source.clone(), |old| old.source.clone());
            atom.attempt_id = old.and_then(|old| old.attempt_id.clone());
            atom.contents = old.map_or_else(Vec::new, |old| old.contents.clone());
            let actual_start = match item.state() {
                ThreadItemState::Tool(tool) => {
                    let call = tool.invocation().tool_call_id();
                    effect.tasks.iter().any(|task| {
                        task.call_id == call && task.started_sequence == Some(effect.sequence)
                    }) || effect.attempt.as_ref().is_some_and(|attempt| {
                        matches!(&attempt.outcome,
                            pl_core::thread::AttemptOutcome::Committed(output)
                                if output.tool_calls.iter().any(|tool| tool.call_id == call))
                    }) || effect
                        .context
                        .as_ref()
                        .is_some_and(|context| match context {
                            pl_core::thread::journal::ContextChange::Append { records, .. } => {
                                records.iter().any(|record| {
                                    record.tool_calls.iter().any(|tool| tool.call_id == call)
                                })
                            }
                            pl_core::thread::journal::ContextChange::Replace(_) => false,
                        })
                }
                _ => false,
            };
            let started = match old {
                Some(old) => match old.lifecycle {
                    ChatAtomLifecycle::Active { started, .. }
                    | ChatAtomLifecycle::Terminal { started, .. } => started,
                },
                None => actual_start
                    .then(|| position(effect, member_base(effect).saturating_add(item_index)))
                    .transpose()?,
            };
            atom.lifecycle = ChatAtomLifecycle::Active {
                started,
                status: if matches!(item.state(), ThreadItemState::Tool(tool)
                    if matches!(tool.state(), ThreadToolState::AwaitingApproval(_))
                    || tool.user_input().is_some_and(|input|
                        matches!(input.state(), pl_protocol::ThreadToolUserInputState::Pending)))
                {
                    ChatActiveStatus::Waiting
                } else {
                    ChatActiveStatus::Running
                },
            };
            atom.started_at = old.map_or(actual_start.then_some(effect.committed_at), |old| {
                old.started_at
            });
            if old == Some(&atom) {
                continue;
            }
            self.atom_starts.insert(atom.id.clone(), atom.clone());
            changes.0.push(ChatEntry::Atom(Box::new(atom)));
        }
        let draft_count = drafts.len();
        for (index, draft) in drafts.iter_mut().enumerate() {
            let terminal_position = position(
                effect,
                member_base(effect)
                    .saturating_add(items.len())
                    .saturating_add(index),
            )?;
            let mut atom: ChatAtom = serde_json::from_slice(&draft.metadata)
                .map_err(|error| ProjectionError::History(error.to_string()))?;
            if atom.source_state.is_some() {
                return Err(ProjectionError::History(
                    "frozen provenance contains a read-time source state".into(),
                ));
            }
            let item = items
                .iter()
                .find(|item| item.id == atom.id)
                .ok_or_else(|| {
                    ProjectionError::History("completion lost its canonical member".into())
                })?;
            atom.source_order = Some(item.ordinal);
            let old = self.atom_starts.remove(&atom.id);
            if let Some(old) = &old {
                atom.source_order = old.source_order;
            }
            if atom.delivery == ChatDeliveryKind::BackgroundHandoff {
                self.release_preview(&atom.id);
            }
            let started = old.as_ref().and_then(|atom| match atom.lifecycle {
                ChatAtomLifecycle::Active { started, .. } => started,
                ChatAtomLifecycle::Terminal { started, .. } => started,
            });
            atom.attempt_id = old.as_ref().and_then(|atom| atom.attempt_id.clone());
            if atom.attempt_id.is_none() {
                atom.attempt_id = effect
                    .model_members
                    .iter()
                    .map(|member| &member.attempt_id)
                    .chain(effect.attempt.iter().map(|attempt| &attempt.attempt_id))
                    .find(|attempt| {
                        atom.id
                            .starts_with(&super::super::order::presentation_prefix(attempt))
                            || atom
                                .id
                                .starts_with(&super::super::order::observation_prefix(attempt))
                            || ["text", "reasoning"].iter().any(|kind| {
                                atom.id == super::super::order::response_id(attempt, kind)
                            })
                    })
                    .cloned();
            }
            atom.started_at = old.as_ref().and_then(|atom| atom.started_at);
            if let ChatAtomLifecycle::Terminal { outcome, .. } = atom.lifecycle {
                atom.lifecycle = ChatAtomLifecycle::Terminal {
                    started,
                    ended: Some(terminal_position),
                    outcome,
                };
            }
            // Input association is supplemental; it never changes first source identity.
            if effect.inputs.iter().any(|change| match change {
                pl_core::thread::input::InputChange::Accepted(record) => record.input.id == atom.id,
                pl_core::thread::input::InputChange::Transition { id, .. } => id == &atom.id,
            }) {
                atom.source = ChatSourceId::Input {
                    input_id: atom.id.clone(),
                };
                atom.kind = pl_protocol::ChatAtomKind::Input;
            }
            for (inbox_index, record) in effect.inbox.iter().enumerate() {
                let background_tool = matches!(item.state(), ThreadItemState::Tool(tool)
                    if tool.invocation().task_id() == Some(record.message.source_id.as_str()));
                if atom.id == super::super::order::message_id(&record.message.id) || background_tool
                {
                    atom.source = ChatSourceId::BackgroundResult {
                        message_id: record.message.id.clone(),
                    };
                    atom.delivery = ChatDeliveryKind::Independent;
                    // The final inbox result is not a resurrection of the transferred foreground member.
                    if background_tool {
                        atom.id = super::super::order::message_id(&record.message.id);
                        atom.source_order = Some(record.sequence);
                    }
                    let outcome = match atom.lifecycle {
                        ChatAtomLifecycle::Terminal { outcome, .. } => outcome,
                        _ => ChatTerminalOutcome::Completed,
                    };
                    self.source_change(
                        atom.source.clone(),
                        Some(outcome),
                        true,
                        position(
                            effect,
                            member_base(effect)
                                .saturating_add(items.len())
                                .saturating_add(draft_count)
                                .saturating_add(inbox_index),
                        )?,
                        changes,
                    )?;
                }
            }
            for event in effect.context_compactions.iter() {
                if let pl_core::thread::ContextCompactionEvent::Finished {
                    operation_id,
                    outcome,
                } = event
                    && atom.id == super::super::order::compaction_id(operation_id)
                {
                    atom.source = ChatSourceId::Operation {
                        operation_id: operation_id.clone(),
                    };
                    let source = self.source_states.get(&atom.source);
                    atom.delivery = ChatDeliveryKind::Independent;
                    atom.turn_id = old.as_ref().and_then(|atom| atom.turn_id.clone());
                    atom.lifecycle = ChatAtomLifecycle::Terminal {
                        started: source.and_then(|source| source.started),
                        ended: source.and_then(|source| source.ended),
                        outcome: match outcome {
                            pl_core::thread::ContextCompactionOutcome::Failed { .. } => {
                                ChatTerminalOutcome::Failed
                            }
                            pl_core::thread::ContextCompactionOutcome::Cancelled => {
                                ChatTerminalOutcome::Cancelled
                            }
                            _ => ChatTerminalOutcome::Completed,
                        },
                    };
                }
            }
            if let ChatSourceId::Receipt { .. } = &atom.source {
                self.source_change(
                    atom.source.clone(),
                    Some(ChatTerminalOutcome::Completed),
                    true,
                    terminal_position,
                    changes,
                )?;
            }
            draft.metadata = serde_json::to_vec(&atom)
                .map_err(|error| ProjectionError::History(error.to_string()))?
                .into();
        }
        // Only the original writer's durable acknowledgement may release unsaved source facts.
        if self.source_states.len() > LIVE_ITEM_WINDOW {
            return Err(ProjectionError::History(
                "source provenance exceeds retained window".into(),
            ));
        }
        Ok(())
    }
}
