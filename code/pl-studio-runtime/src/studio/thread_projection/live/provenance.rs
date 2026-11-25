//! Actual lifecycle folded by the existing projection owner, emitting stateless atomic history events.
use super::*;
use crate::history::{
    HistoryEvent, HistoryEventKind, HistoryOriginalInfo, HistoryTimelineRole, PendingBody,
};
use crate::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind,
    ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome,
};
use crate::{ExecutionItem, ExecutionShape};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum EmittedToolStage {
    Called,
    WaitingApproval,
    Backgrounded,
    CancelRequested,
}

pub(super) type StagedChanges = (Vec<(ChatFactPosition, HistoryEvent)>, Vec<ChatSourceState>);
pub(super) type ProvenanceChanges = (Vec<HistoryEvent>, Vec<ChatSourceState>);

fn millis(at: i64) -> Result<i64, ProjectionError> {
    crate::history::milliseconds_from_seconds(at)
        .map_err(|error| ProjectionError::History(error.to_string()))
}

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

fn slots(parts: &[usize]) -> Result<usize, ProjectionError> {
    parts.iter().try_fold(0usize, |sum, part| {
        sum.checked_add(*part)
            .ok_or_else(|| ProjectionError::History("effect provenance position overflow".into()))
    })
}

fn member_base(effect: &ThreadEffectBatch) -> Result<usize, ProjectionError> {
    // Positions name slots in the immutable effect, not the number of notifications emitted.
    // Duplicate suppression or activation restore must never shift another fact's evidence.
    slots(&[
        1,
        effect.inputs.len(),
        effect.inbox.len(),
        effect.context_compactions.len(),
        effect.continuations.len(),
        effect.model_connection_events.len(),
        effect.model_member_starts.len(),
        effect.model_member_content_available.len(),
    ])
}

fn turn_outcome(state: &pl_core::thread::TurnState) -> Option<ChatTerminalOutcome> {
    match state {
        pl_core::thread::TurnState::Running => None,
        pl_core::thread::TurnState::Failed { .. } => Some(ChatTerminalOutcome::Failed),
        pl_core::thread::TurnState::Cancelled | pl_core::thread::TurnState::Interrupted => {
            Some(ChatTerminalOutcome::Cancelled)
        }
        pl_core::thread::TurnState::Finished(_) => Some(ChatTerminalOutcome::Completed),
    }
}

fn merge_item_contents(
    atom: &mut ChatAtom,
    item: &ExecutionItem,
    database_id: &str,
) -> Result<(), ProjectionError> {
    let fields = crate::studio::runtime::chat_item::content_fields(item.state())
        .map_err(|error| ProjectionError::History(error.to_string()))?;
    for key in fields.keys() {
        let Some(role) = crate::studio::runtime::chat_item::atom_content_role(key) else {
            continue;
        };
        let key = key.as_key();
        if atom.contents.iter().any(|content| {
            matches!(
                &content.reference.target,
                crate::ContentTarget::Body { key: known, .. } if known == &key
            )
        }) {
            continue;
        }
        atom.contents.push(crate::ChatAtomContent {
            role,
            reference: crate::ContentRef {
                database_id: database_id.into(),
                target: crate::ContentTarget::Body {
                    owner: crate::ContentOwner::Item {
                        item_id: item.id.clone(),
                    },
                    key,
                },
            },
        });
    }
    Ok(())
}

fn set_event_atom_columns(
    event: &mut HistoryEvent,
    atom: &ChatAtom,
    run: RuntimeEpoch,
    occurred_at: Option<i64>,
    matched_message_id: Option<&str>,
) -> Result<(), ProjectionError> {
    event.occurred_at = occurred_at.map(millis).transpose()?;
    event.run_id = Some(run.to_string());
    event.turn_id = atom.turn_id.clone();
    event.attempt_id = atom.attempt_id.clone();
    event.call_id = atom.tool.as_ref().map(|tool| tool.call_id.clone());
    event.entity_id = Some(atom.id.clone());
    event.message_id = matched_message_id
        .map(str::to_owned)
        .or_else(|| match &atom.source {
            ChatSourceId::InboxMessage { message_id, .. }
            | ChatSourceId::BackgroundResult { message_id } => Some(message_id.clone()),
            _ => None,
        });
    event.tool_name = atom.tool.as_ref().map(|tool| tool.name.clone());
    event.source = Some(atom.source.clone());
    Ok(())
}

fn event_kind_for_draft(atom: &ChatAtom) -> HistoryEventKind {
    if matches!(atom.source, ChatSourceId::InboxMessage { .. }) {
        return HistoryEventKind::InboxMessageReceived;
    }
    match atom.kind {
        ChatAtomKind::Input => HistoryEventKind::InputAccepted,
        ChatAtomKind::Text => HistoryEventKind::TextCompleted,
        ChatAtomKind::Reasoning => HistoryEventKind::ReasoningCompleted,
        ChatAtomKind::Plan => HistoryEventKind::PlanResolved,
        ChatAtomKind::TurnReceipt => HistoryEventKind::TurnReceiptRecorded,
        ChatAtomKind::Compaction => HistoryEventKind::CompactionCompleted,
        ChatAtomKind::Agent => HistoryEventKind::AgentCompleted,
        ChatAtomKind::ToolCall | ChatAtomKind::Interaction => {
            if atom.delivery == ChatDeliveryKind::BackgroundHandoff {
                HistoryEventKind::ToolBackgrounded
            } else {
                HistoryEventKind::ToolCompleted
            }
        }
        _ => HistoryEventKind::ItemRecorded,
    }
}

fn draft_timeline_role(atom: &ChatAtom) -> HistoryTimelineRole {
    if crate::studio::thread_projection::hidden(atom) {
        HistoryTimelineRole::Hidden
    } else if crate::studio::thread_projection::work(atom) {
        HistoryTimelineRole::Work
    } else if atom.kind == ChatAtomKind::Text && atom.content_present == Some(false) {
        HistoryTimelineRole::Hidden
    } else {
        HistoryTimelineRole::Boundary
    }
}

fn active_item_type(kind: ChatAtomKind) -> &'static str {
    match kind {
        ChatAtomKind::Text => "text",
        ChatAtomKind::Reasoning => "thinking",
        ChatAtomKind::Compaction => "contextCompaction",
        ChatAtomKind::Agent => "agent",
        ChatAtomKind::FileChange => "file",
        ChatAtomKind::Skill => "skill",
        ChatAtomKind::Plan => "plan",
        ChatAtomKind::TurnReceipt => "turn",
        _ => "raw",
    }
}

impl LiveProjection {
    /// Execution activation only. Passive conversation opens never create this owner or scan history.
    pub(in crate::studio) fn restore_current(
        &mut self,
        thread: &crate::Thread,
        state: &ThreadSnapshot,
    ) -> Result<(), ProjectionError> {
        if self.provenance_restored {
            return Err(ProjectionError::History(
                "current provenance was already restored".into(),
            ));
        }
        let sequence = state.commit_sequence;
        self.provenance_restored = true;
        self.observe_current(thread, state, sequence)
    }

    pub(in crate::studio) fn confirm_sources(&mut self, through: u64) {
        self.source_states
            .retain(|_, state| state.ended.is_none_or(|at| at.effect_seq > through));
    }

    fn source_change(
        &mut self,
        source: ChatSourceId,
        outcome: Option<ChatTerminalOutcome>,
        actual_start: bool,
        at: ChatFactPosition,
        sources: &mut Vec<ChatSourceState>,
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
        sources.push(state);
        Ok(())
    }

    pub(super) fn begin_provenance(
        &mut self,
        effect: &ThreadEffectBatch,
        run: RuntimeEpoch,
    ) -> Result<StagedChanges, ProjectionError> {
        let mut staged = Vec::new();
        let mut sources = Vec::new();
        let recorded_at = millis(effect.committed_at)?;
        if let Some(turn) = &effect.turn
            && turn_outcome(&turn.state).is_none()
        {
            self.source_change(
                ChatSourceId::ForegroundTurn {
                    turn_id: turn.turn_id.clone(),
                },
                None,
                true,
                position(effect, 0)?,
                &mut sources,
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
                    position(effect, slots(&[1, index])?)?,
                    &mut sources,
                )?;
            }
        }
        for (index, operation) in effect.continuations.iter().enumerate() {
            let outcome = match operation.disposition {
                pl_core::thread::ContinuationDisposition::Scheduled => None,
                pl_core::thread::ContinuationDisposition::Effective => {
                    Some(ChatTerminalOutcome::Completed)
                }
                pl_core::thread::ContinuationDisposition::NotExecuted(_) => {
                    Some(ChatTerminalOutcome::Cancelled)
                }
            };
            self.source_change(
                ChatSourceId::Operation {
                    operation_id: operation.request.operation_id.clone(),
                },
                outcome,
                outcome.is_none(),
                position(
                    effect,
                    slots(&[1, effect.inputs.len(), effect.inbox.len(), index])?,
                )?,
                &mut sources,
            )?;
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
                slots(&[
                    1,
                    effect.inputs.len(),
                    effect.inbox.len(),
                    effect.continuations.len(),
                    index,
                ])?,
            )?;
            self.source_change(source.clone(), outcome, outcome.is_none(), at, &mut sources)?;
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
                    content_present: None,
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
                    wait: None,
                    text_channel: None,
                    started_at: Some(effect.committed_at),
                    finished_at: None,
                    contents: Vec::new(),
                    payload: None,
                };
                self.atom_starts.insert(item_id.clone(), atom.clone());
            }
        }
        let conn_base = slots(&[
            1,
            effect.inputs.len(),
            effect.inbox.len(),
            effect.context_compactions.len(),
            effect.continuations.len(),
        ])?;
        for (index, conn) in effect.model_connection_events.iter().enumerate() {
            let at = position(effect, slots(&[conn_base, index])?)?;
            let kind = match conn.kind {
                pl_core::model::ModelConnectionEventKind::Disconnected => {
                    HistoryEventKind::ConnectionDisconnected
                }
                pl_core::model::ModelConnectionEventKind::Reconnected => {
                    HistoryEventKind::ConnectionReconnected
                }
            };
            let mut history_event = HistoryEvent::new(
                format!(
                    "conn:model:{run}:{}:{}:{}",
                    effect.sequence,
                    index,
                    conn.kind.as_str()
                ),
                kind,
                HistoryTimelineRole::Boundary,
                recorded_at,
            );
            history_event.occurred_at = Some(millis(effect.committed_at)?);
            history_event.run_id = Some(run.to_string());
            history_event.turn_id = Some(conn.turn_id.clone());
            history_event.attempt_id = Some(conn.attempt_id.clone());
            let mut data = serde_json::Map::new();
            data.insert(
                "state".into(),
                serde_json::Value::String(conn.kind.as_str().to_owned()),
            );
            data.insert("scope".into(), serde_json::Value::String("model".into()));
            data.insert(
                "transport".into(),
                serde_json::Value::String(conn.transport.clone()),
            );
            if let Some(fallback) = &conn.fallback_transport {
                data.insert(
                    "fallbackTransport".into(),
                    serde_json::Value::String(fallback.clone()),
                );
            }
            data.insert(
                "attempt".into(),
                serde_json::Value::Number(serde_json::Number::from(conn.retry)),
            );
            data.insert(
                "maxAttempts".into(),
                serde_json::Value::Number(serde_json::Number::from(conn.max_retries)),
            );
            data.insert(
                "recoverable".into(),
                serde_json::Value::Bool(conn.recoverable),
            );
            if let Some(reason) = &conn.reason {
                data.insert("reason".into(), serde_json::Value::String(reason.clone()));
            }
            if let Some(duration_ms) = conn.duration_ms {
                data.insert(
                    "durationMs".into(),
                    serde_json::Value::Number(serde_json::Number::from(duration_ms)),
                );
            }
            crate::studio::runtime::chat_item::build_connection_event(
                &mut history_event,
                serde_json::Value::Object(data),
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
            staged.push((at, history_event));
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
            let item = ExecutionItem::new(
                id.clone(),
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(effect.thread_id.clone()),
                    turn_id: std::borrow::Cow::Owned(start.turn_id.clone()),
                    ordinal: order,
                    revision: self.bump_content_revision(&id),
                    created_at: effect.committed_at,
                    updated_at: effect.committed_at,
                },
                shape.clone(),
            );
            self.fact(&item);
            let content = crate::ChatAtomContent {
                role: crate::studio::runtime::chat_item::atom_content_role(&field).ok_or_else(
                    || {
                        ProjectionError::UnsupportedOutput(
                            "canonical member start has no content role".into(),
                        )
                    },
                )?,
                reference: crate::ContentRef {
                    database_id: self
                        .current
                        .owner_id()
                        .ok_or_else(|| {
                            ProjectionError::History(
                                "canonical member start has no runtime owner".into(),
                            )
                        })?
                        .into(),
                    target: crate::ContentTarget::Body {
                        owner: crate::ContentOwner::Item {
                            item_id: id.clone(),
                        },
                        key: field.as_key(),
                    },
                },
            };
            if !self.previews.contains_key(&id) {
                self.store_preview(
                    id.clone(),
                    LivePreview {
                        fields: BTreeMap::from([(field, ContentBlock::from_text(""))]),
                        observed: None,
                        shape,
                        observed_version: 0,
                        model_part: None,
                    },
                );
            }
            let at = position(
                effect,
                slots(&[
                    1,
                    effect.inputs.len(),
                    effect.inbox.len(),
                    effect.continuations.len(),
                    effect.context_compactions.len(),
                    index,
                ])?,
            )?;
            let mut atom = crate::studio::runtime::chat_item::atom(&item);
            atom.contents = vec![content];
            atom.attempt_id = Some(start.attempt_id.clone());
            atom.started_at = Some(effect.committed_at);
            atom.lifecycle = ChatAtomLifecycle::Active {
                started: Some(at),
                status: ChatActiveStatus::Running,
            };
            self.atom_starts.insert(id.clone(), atom);
        }
        if self.atom_starts.len() > LIVE_ITEM_WINDOW {
            return Err(ProjectionError::History(
                "active member provenance exceeds retained window".into(),
            ));
        }
        Ok((staged, sources))
    }

    pub(super) fn complete_provenance(
        &mut self,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        items: &[ExecutionItem],
        drafts: &[ChatDraft],
        staged_changes: StagedChanges,
        run: RuntimeEpoch,
    ) -> Result<ProvenanceChanges, ProjectionError> {
        let (mut staged, mut sources) = staged_changes;
        let current_owner_id = self
            .current
            .owner_id()
            .ok_or_else(|| ProjectionError::History("missing runtime owner identity".into()))?
            .to_owned();
        let history_database_id = self
            .database_id
            .as_deref()
            .ok_or_else(|| ProjectionError::History("missing history database identity".into()))?
            .to_owned();
        let recorded_at = millis(effect.committed_at)?;

        for (item_index, item) in items.iter().enumerate().filter(|(_, item)| {
            !completion_ready(item)
                && !matches!(
                    item.state(),
                    ExecutionShape::Inference(_) | ExecutionShape::Turn(_)
                )
        }) {
            let mut active_tool_stage: Option<(
                &crate::ThreadToolItem,
                EmittedToolStage,
                bool,
                bool,
            )> = None;
            if let ExecutionShape::Tool(tool) = item.state() {
                let call_id = tool.invocation().tool_call_id();
                let task = tool.invocation().task_id().and_then(|task_id| {
                    effect
                        .tasks
                        .iter()
                        .find(|task| task.id == task_id)
                        .or_else(|| state.tasks.get(task_id))
                        .or_else(|| state.terminal_tasks.iter().find(|task| task.id == task_id))
                        .filter(|task| {
                            task.call_id == call_id
                                && task.tool_id == tool.invocation().name()
                                && task.turn_id == item.turn_id
                        })
                });
                let cancel_requested = task.is_some_and(|task| task.cancel_requested);
                let waiting = matches!(tool.state(), ThreadToolState::AwaitingApproval(_))
                    || tool.user_input().is_some_and(|input| {
                        matches!(input.state(), crate::ThreadToolUserInputState::Pending)
                    });
                let backgrounded = task.is_some_and(|task| task.acknowledgement.is_some())
                    || self.completion_exists(&super::super::order::tool_background_started_id(
                        call_id,
                    ))?;
                let stage = if cancel_requested {
                    EmittedToolStage::CancelRequested
                } else if waiting {
                    EmittedToolStage::WaitingApproval
                } else if backgrounded {
                    EmittedToolStage::Backgrounded
                } else {
                    EmittedToolStage::Called
                };
                if !backgrounded && !self.previews.contains_key(&item.id) {
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
                            model_part: None,
                        },
                    );
                }
                active_tool_stage = Some((tool, stage, cancel_requested, waiting));
            }
            let old = self.atom_starts.get(&item.id).cloned();
            let mut atom = crate::studio::runtime::chat_item::atom(item);
            atom.source = old
                .as_ref()
                .map_or_else(|| atom.source.clone(), |old| old.source.clone());
            atom.attempt_id = old.as_ref().and_then(|old| old.attempt_id.clone());
            atom.contents = old
                .as_ref()
                .map_or_else(Vec::new, |old| old.contents.clone());
            merge_item_contents(&mut atom, item, &current_owner_id)?;
            let actual_start = match item.state() {
                ExecutionShape::Tool(tool) => {
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
            let item_pos = position(effect, slots(&[member_base(effect)?, item_index])?)?;
            let started = match &old {
                Some(old) => match old.lifecycle {
                    ChatAtomLifecycle::Active { started, .. }
                    | ChatAtomLifecycle::Terminal { started, .. } => started,
                },
                None => actual_start.then_some(item_pos),
            };
            atom.lifecycle = ChatAtomLifecycle::Active {
                started,
                status: if active_tool_stage.is_some_and(|(_, _, _, waiting)| waiting) {
                    ChatActiveStatus::Waiting
                } else {
                    ChatActiveStatus::Running
                },
            };
            atom.started_at = old
                .as_ref()
                .map_or(actual_start.then_some(effect.committed_at), |old| {
                    old.started_at
                });
            let first_start = old.is_none();
            if old.as_ref() != Some(&atom) {
                self.atom_starts.insert(atom.id.clone(), atom.clone());
            }

            if let Some((tool, stage, cancel_requested, _)) = active_tool_stage {
                let call_id = tool.invocation().tool_call_id();
                if self.emitted_tool_stages.get(call_id).copied() != Some(stage) {
                    self.emitted_tool_stages.insert(call_id.to_owned(), stage);
                    if self.emitted_tool_stages.len() > LIVE_ITEM_WINDOW {
                        return Err(ProjectionError::History(
                            "active tool provenance exceeds retained window".into(),
                        ));
                    }
                    if stage != EmittedToolStage::Backgrounded {
                        let kind = match stage {
                            EmittedToolStage::Called => HistoryEventKind::ToolCalled,
                            EmittedToolStage::WaitingApproval => {
                                HistoryEventKind::ToolWaitingApproval
                            }
                            EmittedToolStage::CancelRequested => {
                                HistoryEventKind::ToolCancelRequested
                            }
                            EmittedToolStage::Backgrounded => unreachable!(),
                        };
                        let timeline_role = if crate::studio::thread_projection::work(&atom) {
                            HistoryTimelineRole::Work
                        } else {
                            HistoryTimelineRole::Hidden
                        };
                        let mut history_event = HistoryEvent::new(
                            format!(
                                "tool-stage:{run}:{}:{}:{}",
                                effect.sequence,
                                call_id,
                                kind.as_str()
                            ),
                            kind,
                            timeline_role,
                            recorded_at,
                        );
                        set_event_atom_columns(
                            &mut history_event,
                            &atom,
                            run,
                            Some(effect.committed_at),
                            None,
                        )?;
                        crate::studio::runtime::chat_item::build_active_tool_event(
                            &mut history_event,
                            &atom,
                            item,
                            cancel_requested,
                            &history_database_id,
                        )
                        .map_err(|error| ProjectionError::History(error.to_string()))?;
                        staged.push((item_pos, history_event));
                    }
                }
            } else if first_start {
                // Non-tool active starts stay strictly in Current RAM via self.atom_starts.
            }
        }

        let draft_count = drafts.len();
        let draft_atoms = drafts
            .iter()
            .map(|draft| {
                serde_json::from_slice::<ChatAtom>(&draft.metadata)
                    .map_err(|error| ProjectionError::History(error.to_string()))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let interrupted_ids = if let Some(attempt) = &effect.attempt
            && matches!(
                attempt.outcome,
                pl_core::thread::AttemptOutcome::Interrupted
            ) {
            self.atom_starts
                .values()
                .filter(|atom| {
                    atom.attempt_id.as_deref() == Some(attempt.attempt_id.as_str())
                        && matches!(atom.kind, ChatAtomKind::Text | ChatAtomKind::Reasoning)
                        && !draft_atoms.iter().any(|draft| draft.id == atom.id)
                })
                .map(|atom| atom.id.clone())
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        let draft_base = slots(&[member_base(effect)?, items.len()])?;
        let interruption_base = slots(&[draft_base, draft_count, effect.inbox.len()])?;
        let receipt_base = slots(&[interruption_base, interrupted_ids.len()])?;

        for (index, draft) in drafts.iter().enumerate() {
            let mut atom = draft_atoms[index].clone();
            let final_turn_receipt = atom.kind == ChatAtomKind::TurnReceipt
                && effect.turn.as_ref().is_some_and(|turn| {
                    turn_outcome(&turn.state).is_some()
                        && atom.source
                            == ChatSourceId::ForegroundTurn {
                                turn_id: turn.turn_id.clone(),
                            }
                });
            let terminal_position = position(
                effect,
                slots(&[
                    if final_turn_receipt {
                        receipt_base
                    } else {
                        draft_base
                    },
                    index,
                ])?,
            )?;
            if atom.source_state.is_some() {
                return Err(ProjectionError::History(
                    "frozen provenance contains a read-time source state".into(),
                ));
            }
            if matches!(
                atom.source,
                ChatSourceId::Input { .. } | ChatSourceId::InboxMessage { .. }
            ) {
                self.source_change(
                    atom.source.clone(),
                    Some(ChatTerminalOutcome::Completed),
                    true,
                    match atom.lifecycle {
                        ChatAtomLifecycle::Terminal {
                            ended: Some(at), ..
                        } => at,
                        _ => terminal_position,
                    },
                    &mut sources,
                )?;
                let kind = event_kind_for_draft(&atom);
                let timeline_role = draft_timeline_role(&atom);
                let mut history_event =
                    HistoryEvent::new(draft.item_id.clone(), kind, timeline_role, recorded_at);
                set_event_atom_columns(
                    &mut history_event,
                    &atom,
                    run,
                    atom.finished_at.or(atom.started_at),
                    None,
                )?;
                history_event.original = Some(HistoryOriginalInfo {
                    query_class: draft.query_class.clone(),
                    parent_id: draft
                        .parent_id
                        .as_ref()
                        .map(|parent| parent.as_str().to_owned()),
                    original_kind: atom.kind,
                    tool_name: atom.tool.as_ref().map(|tool| tool.name.clone()),
                });
                crate::studio::runtime::chat_item::build_event_from_draft(
                    &mut history_event,
                    &atom,
                    draft,
                    &history_database_id,
                    Vec::new(),
                )
                .map_err(|error| ProjectionError::History(error.to_string()))?;
                staged.push((terminal_position, history_event));
                continue;
            }
            let item = items
                .iter()
                .find(|item| item.id == atom.id)
                .ok_or_else(|| {
                    ProjectionError::History("completion lost its canonical member".into())
                })?;
            atom.source_order = Some(item.ordinal);
            let old = if atom.delivery == ChatDeliveryKind::BackgroundHandoff {
                self.release_preview(&atom.id);
                self.atom_starts.get(&atom.id).cloned()
            } else {
                self.atom_starts.remove(&atom.id)
            };
            if let Some(old) = &old {
                atom.source_order = old.source_order;
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
            if effect.inputs.iter().any(|change| match change {
                pl_core::thread::input::InputChange::Accepted(record) => record.input.id == atom.id,
                pl_core::thread::input::InputChange::Transition { id, .. } => id == &atom.id,
            }) {
                atom.source = ChatSourceId::Input {
                    input_id: atom.id.clone(),
                };
                atom.kind = crate::ChatAtomKind::Input;
            }
            let mut matched_message_id: Option<String> = None;
            for (inbox_index, record) in effect.inbox.iter().enumerate() {
                let background_tool = matches!(item.state(), ExecutionShape::Tool(tool)
                    if tool.invocation().task_id() == Some(record.message.source_id.as_str()));
                if atom.id == super::super::order::message_id(&record.message.id) || background_tool
                {
                    atom.source = ChatSourceId::BackgroundResult {
                        message_id: record.message.id.clone(),
                    };
                    atom.delivery = ChatDeliveryKind::Independent;
                    // Keep atom.id as tool_id(call_id) so background completion stays unified with
                    // tool_called / tool_backgrounded / tool_cancel_requested by call_id and entity_id.
                    if background_tool {
                        atom.source_order = Some(record.sequence);
                    }
                    matched_message_id = Some(record.message.id.clone());
                    let outcome = match atom.lifecycle {
                        ChatAtomLifecycle::Terminal { outcome, .. } => outcome,
                        _ => ChatTerminalOutcome::Completed,
                    };
                    self.source_change(
                        atom.source.clone(),
                        Some(outcome),
                        true,
                        position(effect, slots(&[draft_base, draft_count, inbox_index])?)?,
                        &mut sources,
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
                    &mut sources,
                )?;
            }
            if let Some(tool) = &atom.tool {
                if atom.delivery == ChatDeliveryKind::BackgroundHandoff {
                    self.emitted_tool_stages
                        .insert(tool.call_id.clone(), EmittedToolStage::Backgrounded);
                } else {
                    self.emitted_tool_stages.remove(&tool.call_id);
                }
            }
            let kind = event_kind_for_draft(&atom);
            let timeline_role = draft_timeline_role(&atom);
            let mut history_event =
                HistoryEvent::new(draft.item_id.clone(), kind, timeline_role, recorded_at);
            set_event_atom_columns(
                &mut history_event,
                &atom,
                run,
                atom.finished_at.or(atom.started_at),
                matched_message_id.as_deref(),
            )?;
            history_event.original = Some(HistoryOriginalInfo {
                query_class: draft.query_class.clone(),
                parent_id: draft
                    .parent_id
                    .as_ref()
                    .map(|parent| parent.as_str().to_owned()),
                original_kind: atom.kind,
                tool_name: atom.tool.as_ref().map(|tool| tool.name.clone()),
            });
            let mut extra_bodies = Vec::new();
            if let Some(tool) = &atom.tool
                && let Some(task) = effect
                    .tasks
                    .iter()
                    .find(|task| task.call_id == tool.call_id)
                && let Some(delivery) = effect
                    .deliveries
                    .iter()
                    .find(|delivery| delivery.call_id == tool.call_id)
            {
                let saved = crate::studio::storage::tool_task::body(task, delivery)
                    .map_err(|error| ProjectionError::History(error.to_string()))?;
                extra_bodies.push(PendingBody::new(
                    saved.body_key,
                    saved.role,
                    saved.media_type,
                    saved.bytes,
                ));
            }
            crate::studio::runtime::chat_item::build_event_from_draft(
                &mut history_event,
                &atom,
                draft,
                &history_database_id,
                extra_bodies,
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
            staged.push((terminal_position, history_event));
        }

        for (index, id) in interrupted_ids.into_iter().enumerate() {
            let mut atom = self
                .atom_starts
                .remove(&id)
                .expect("captured active identity");
            let ChatAtomLifecycle::Active { started, .. } = atom.lifecycle else {
                continue;
            };
            let interrupted_pos = position(effect, slots(&[interruption_base, index])?)?;
            atom.lifecycle = ChatAtomLifecycle::Terminal {
                started,
                ended: Some(interrupted_pos),
                outcome: ChatTerminalOutcome::Cancelled,
            };
            atom.finished_at = Some(effect.committed_at);
            atom.contents.clear();
            self.release_preview(&id);
            let kind = if atom.kind == ChatAtomKind::Reasoning {
                HistoryEventKind::ReasoningCompleted
            } else {
                HistoryEventKind::TextCompleted
            };
            let mut history_event = HistoryEvent::new(
                format!("entity:{run}:{}:{}:interrupted", effect.sequence, atom.id),
                kind,
                HistoryTimelineRole::Hidden,
                recorded_at,
            );
            set_event_atom_columns(&mut history_event, &atom, run, atom.finished_at, None)?;
            crate::studio::runtime::chat_item::build_active_state_event(
                &mut history_event,
                &atom,
                active_item_type(atom.kind),
                serde_json::json!({ "status": "cancelled" }),
            )
            .map_err(|error| ProjectionError::History(error.to_string()))?;
            staged.push((interrupted_pos, history_event));
        }

        if let Some(turn) = &effect.turn
            && let Some(outcome) = turn_outcome(&turn.state)
        {
            self.source_change(
                ChatSourceId::ForegroundTurn {
                    turn_id: turn.turn_id.clone(),
                },
                Some(outcome),
                false,
                position(effect, slots(&[receipt_base, draft_count])?)?,
                &mut sources,
            )?;
        }

        staged.sort_by_key(|(pos, _)| *pos);
        if self.source_states.len() > LIVE_ITEM_WINDOW {
            return Err(ProjectionError::History(
                "source provenance exceeds retained window".into(),
            ));
        }
        Ok((
            staged.into_iter().map(|(_, event)| event).collect(),
            sources,
        ))
    }
}

// Independent history visibility classification.
pub(crate) fn work(atom: &ChatAtom) -> bool {
    let background_tool = atom.kind == ChatAtomKind::ToolCall
        && matches!(atom.source, ChatSourceId::BackgroundResult { .. })
        && atom
            .tool
            .as_ref()
            .is_some_and(|tool| tool.name != pl_tool::file_display::TOOL_SHOW_FILES);
    background_tool
        || (matches!(
            atom.kind,
            ChatAtomKind::Reasoning
                | ChatAtomKind::ToolCall
                | ChatAtomKind::FileChange
                | ChatAtomKind::Skill
        ) && atom.delivery != ChatDeliveryKind::Independent)
}

pub(crate) fn hidden(atom: &ChatAtom) -> bool {
    !matches!(atom.source, ChatSourceId::InboxMessage { .. })
        && (atom.kind == ChatAtomKind::Inference
            || (atom.kind == ChatAtomKind::TurnReceipt
                && matches!(
                    atom.lifecycle,
                    ChatAtomLifecycle::Terminal {
                        outcome: ChatTerminalOutcome::Completed,
                        ..
                    }
                )))
}
