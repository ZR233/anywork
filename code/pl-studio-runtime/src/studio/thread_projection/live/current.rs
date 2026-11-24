//! Pure Current projection from one Core owner snapshot.
use super::super::current::{ActiveText, ModelPartLocation};
use super::*;
use crate::{
    ChatActiveStatus, ChatAtom, ChatAtomContent, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind,
    ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome, ChatToolIdentity,
    ContentOwner, ContentRef, ContentTarget, ThreadTextChannel,
};

pub(super) struct CurrentOriginals {
    pub(super) sources: Vec<ChatSourceState>,
    pub(super) atoms: Vec<ChatAtom>,
    pub(super) active: Vec<ActiveText>,
}

pub(super) fn project(
    thread: &crate::Thread,
    state: &ThreadSnapshot,
    owner_id: &str,
) -> Result<CurrentOriginals, ProjectionError> {
    let mut sources = BTreeMap::<ChatSourceId, ChatSourceState>::new();
    let mut atoms = Vec::new();
    let mut active = Vec::new();

    for turn in state
        .turns
        .iter()
        .filter(|turn| turn.state == pl_core::thread::TurnState::Running)
    {
        insert_active_source(
            &mut sources,
            ChatSourceId::ForegroundTurn {
                turn_id: turn.turn_id.clone(),
            },
        );
    }
    if let Some(turn_id) = state
        .execution
        .as_ref()
        .and_then(|execution| execution.turn_id.clone())
    {
        insert_active_source(&mut sources, ChatSourceId::ForegroundTurn { turn_id });
    }
    if let Some(compaction) = state.active_context_compaction.as_ref() {
        let source = ChatSourceId::Operation {
            operation_id: compaction.operation_id.clone(),
        };
        insert_active_source(&mut sources, source.clone());
        atoms.push(ChatAtom {
            id: super::super::order::compaction_id(&compaction.operation_id),
            completion_item_id: None,
            content_present: None,
            completion_seq: None,
            source,
            source_state: None,
            source_order: None,
            kind: ChatAtomKind::Compaction,
            delivery: ChatDeliveryKind::Independent,
            lifecycle: ChatAtomLifecycle::Active {
                started: None,
                status: ChatActiveStatus::Running,
            },
            turn_id: compaction.turn_id.clone(),
            attempt_id: compaction.attempt_id.clone(),
            tool: None,
            wait: None,
            text_channel: None,
            started_at: None,
            finished_at: None,
            contents: Vec::new(),
            payload: None,
        });
    }

    if let Some(progress) = state.model_progress.as_ref()
        && let Some(attempt) = state.attempts.iter().find(|attempt| {
            attempt.attempt_id == progress.attempt_id
                && attempt.status == pl_core::thread::AttemptStatus::Running
        })
    {
        let generation = progress.progress.observation().generation;
        for (index, part) in progress.progress.parts().iter().enumerate() {
            let Some((id, field, shape)) = super::observation_preview(
                &attempt.attempt_id,
                generation,
                part,
                &ThreadContentLifecycle::streaming(),
            ) else {
                return Err(ProjectionError::UnsupportedOutput(
                    "current provider part does not match its item".into(),
                ));
            };
            let block = part.content().clone();
            let fields = BTreeMap::from([(field.clone(), block.clone())]);
            let item = ExecutionItem::new(
                id.clone(),
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(thread.id.clone()),
                    turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                    ordinal: 0,
                    revision: part.version().max(1),
                    created_at: 0,
                    updated_at: 0,
                },
                shape,
            );
            let mut atom = crate::studio::runtime::chat_item::atom(&item);
            atom.attempt_id = Some(attempt.attempt_id.clone());
            atom.started_at = None;
            atom.finished_at = None;
            atom.contents = atom_contents(owner_id, &id, &fields);
            insert_active_source(&mut sources, atom.source.clone());
            active.push((
                id,
                field,
                block,
                atom.text_channel,
                Some(ModelPartLocation { generation, index }),
            ));
            atoms.push(atom);
        }
        for (id, message) in super::super::responses::recovery_notices(
            &attempt.attempt_id,
            progress.progress.observation(),
        ) {
            let block = ContentBlock::from_text(&message);
            let fields = BTreeMap::from([(BodyKey::Body, block.clone())]);
            let shape = ExecutionShape::Text(ThreadTextItem::new(
                ThreadTextChannel::Commentary,
                String::new(),
                Vec::new(),
                ThreadContentLifecycle::streaming(),
            ));
            let item = ExecutionItem::new(
                id.clone(),
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(thread.id.clone()),
                    turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                    ordinal: 0,
                    revision: 1,
                    created_at: 0,
                    updated_at: 0,
                },
                shape,
            );
            let mut atom = crate::studio::runtime::chat_item::atom(&item);
            atom.attempt_id = Some(attempt.attempt_id.clone());
            atom.started_at = None;
            atom.finished_at = None;
            atom.contents = atom_contents(owner_id, &id, &fields);
            insert_active_source(&mut sources, atom.source.clone());
            active.push((
                id,
                BodyKey::Body,
                block,
                Some(ThreadTextChannel::Commentary),
                None,
            ));
            atoms.push(atom);
        }
    }

    for task in state
        .tasks
        .values()
        .filter(|task| task.status == pl_core::thread::task::TaskStatus::Running)
    {
        let source = ChatSourceId::ForegroundTurn {
            turn_id: task.turn_id.clone(),
        };
        insert_active_source(&mut sources, source.clone());
        if let Some(item) = task_tool_item(thread, state, task)? {
            let mut fields = crate::studio::runtime::chat_item::content_fields(item.state())
                .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?;
            if let Some(progress) = state.tool_progress.get(&task.id)
                && !progress.is_empty()
            {
                fields.insert(BodyKey::host(TOOL_RESULT_FIELD), progress.content());
            }
            let id = item.id.clone();
            let text_channel = None;
            let mut atom = crate::studio::runtime::chat_item::atom(&item);
            atom.started_at = None;
            atom.finished_at = None;
            atom.contents = atom_contents(owner_id, &id, &fields);
            for (field, block) in fields {
                active.push((id.clone(), field, block, text_channel, None));
            }
            atoms.push(atom);
        } else {
            // A legacy resident task can still be current without retaining its original invocation.
            // Keep its identity visible, but do not invent empty arguments or query History.
            let atom = ChatAtom {
                id: super::super::order::tool_id(&task.call_id),
                completion_item_id: None,
                content_present: None,
                completion_seq: None,
                source,
                source_state: None,
                source_order: task.started_sequence,
                kind: ChatAtomKind::ToolCall,
                delivery: if task.acknowledgement.is_some() {
                    ChatDeliveryKind::Independent
                } else {
                    ChatDeliveryKind::Foreground
                },
                lifecycle: ChatAtomLifecycle::Active {
                    started: None,
                    status: if state.permissions.values().any(|permission| {
                        permission.call_id == task.call_id
                            && permission.state
                                == pl_core::thread::permissions::PermissionState::Pending
                    }) {
                        ChatActiveStatus::Waiting
                    } else {
                        ChatActiveStatus::Running
                    },
                },
                turn_id: Some(task.turn_id.clone()),
                attempt_id: None,
                tool: Some(ChatToolIdentity {
                    call_id: task.call_id.clone(),
                    name: task.tool_id.clone(),
                }),
                wait: None,
                text_channel: None,
                started_at: None,
                finished_at: None,
                contents: Vec::new(),
                payload: None,
            };
            atoms.push(atom);
        }
    }

    for input in state
        .inputs
        .iter()
        .filter(|input| input.state == pl_core::thread::input::InputState::Pending)
    {
        let Some(item) = super::super::inputs::project_input(
            &thread.id,
            input,
            input.ordinal,
            0,
            input.revision.max(1),
            0,
        )?
        else {
            continue;
        };
        let mut fields = crate::studio::runtime::chat_item::content_fields(item.state())
            .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?;
        let mut atom = crate::studio::runtime::chat_item::atom(&item);
        atom.started_at = None;
        atom.finished_at = None;
        atom.content_present = Some(match item.state() {
            ExecutionShape::Text(text) => !text.text().is_empty() || !text.attachments().is_empty(),
            ExecutionShape::Raw(_) => fields.values().any(|block| !block.is_empty()),
            _ => false,
        });
        let source = atom.source.clone();
        insert_completed_source(&mut sources, source.clone());
        let id = atom.id.clone();
        let text_channel = atom.text_channel;
        atom.contents = atom_contents(owner_id, &id, &fields);
        atoms.push(atom);
        for (field, block) in std::mem::take(&mut fields) {
            active.push((id.clone(), field, block, text_channel, None));
        }
    }

    for record in state
        .inbox
        .iter()
        .filter(|record| record.sequence > state.consumed_messages)
    {
        let message = &record.message;
        let source = ChatSourceId::InboxMessage {
            source_id: message.source_id.clone(),
            message_id: message.id.clone(),
        };
        insert_completed_source(&mut sources, source.clone());
        let text_message =
            message.payload.format() == "text/plain" && message.payload.version() == 1;
        let block = ContentBlock::from_text(message.payload.content());
        let fields = BTreeMap::from([(BodyKey::Body, block.clone())]);
        let id = super::super::order::message_id(&message.id);
        let text_channel = text_message.then_some(ThreadTextChannel::ParentAgent);
        atoms.push(ChatAtom {
            id: id.clone(),
            completion_item_id: None,
            content_present: Some(!block.is_empty()),
            completion_seq: None,
            source,
            source_state: None,
            source_order: Some(record.sequence),
            kind: if text_message {
                ChatAtomKind::Text
            } else {
                ChatAtomKind::Raw
            },
            delivery: ChatDeliveryKind::Independent,
            lifecycle: ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: ChatTerminalOutcome::Completed,
            },
            turn_id: None,
            attempt_id: None,
            tool: None,
            wait: None,
            text_channel,
            started_at: None,
            finished_at: None,
            contents: atom_contents(owner_id, &id, &fields),
            payload: None,
        });
        active.push((id, BodyKey::Body, block, text_channel, None));
    }

    Ok(CurrentOriginals {
        sources: sources.into_values().collect(),
        atoms,
        active,
    })
}

pub(super) fn task_tool_item(
    thread: &crate::Thread,
    state: &ThreadSnapshot,
    task: &pl_core::thread::task::TaskRecord,
) -> Result<Option<ExecutionItem>, ProjectionError> {
    let Some(invocation) = task.invocation.as_ref() else {
        return Ok(None);
    };
    if invocation.call_id != task.call_id || invocation.tool_id != task.tool_id {
        return Err(ProjectionError::UnsupportedOutput(
            "current task invocation differs from its task identity".into(),
        ));
    }
    let items = super::super::tools::project_tool_call(
        state,
        invocation,
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Borrowed(thread.id.as_str()),
            turn_id: std::borrow::Cow::Borrowed(task.turn_id.as_str()),
            ordinal: task.started_sequence.unwrap_or(0),
            created_at: 0,
            revision: task.revision.max(1),
            updated_at: 0,
        },
    )?;
    Ok(items
        .into_iter()
        .find(|item| item.id == super::super::order::tool_id(&task.call_id)))
}

fn atom_contents(
    owner_id: &str,
    item_id: &str,
    fields: &BTreeMap<BodyKey, Arc<ContentBlock>>,
) -> Vec<ChatAtomContent> {
    fields
        .keys()
        .filter_map(|key| {
            Some(ChatAtomContent {
                role: crate::studio::runtime::chat_item::atom_content_role(key)?,
                reference: ContentRef {
                    database_id: owner_id.into(),
                    target: ContentTarget::Body {
                        owner: ContentOwner::Item {
                            item_id: item_id.into(),
                        },
                        key: key.as_key(),
                    },
                },
            })
        })
        .collect()
}

fn insert_active_source(
    sources: &mut BTreeMap<ChatSourceId, ChatSourceState>,
    source: ChatSourceId,
) {
    sources.entry(source.clone()).or_insert(ChatSourceState {
        source,
        lifecycle: ChatSourceLifecycle::Active,
        started: None,
        ended: None,
    });
}

fn insert_completed_source(
    sources: &mut BTreeMap<ChatSourceId, ChatSourceState>,
    source: ChatSourceId,
) {
    sources.entry(source.clone()).or_insert(ChatSourceState {
        source,
        lifecycle: ChatSourceLifecycle::Ended {
            outcome: ChatTerminalOutcome::Completed,
        },
        started: None,
        ended: None,
    });
}
