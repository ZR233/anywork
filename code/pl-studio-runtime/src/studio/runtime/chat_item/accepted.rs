//! Frozen facts from the original reliable admission. Consumption never changes this shape.
use super::*;
use crate::studio::thread_projection::{ContentError, InputView, ProjectionError, input_view};
use pl_core::{
    context::OpaquePayload,
    thread::{inbox::InboxRecord, input::InputRecord},
};
use pl_protocol::{
    ChatAtomLifecycle, ChatDeliveryKind, ChatFactPosition, ChatSourceId, ChatTerminalOutcome,
    MessagePresentation, Thread, ThreadContentLifecycle, ThreadTextChannel,
};
#[cfg(test)]
mod tests;

pub(in crate::studio) fn accepted_input_draft(
    thread: &Thread,
    record: &InputRecord,
    accepted_at: ChatFactPosition,
    timestamp: i64,
    database_id: &str,
) -> Result<Option<ChatDraft>, ProjectionError> {
    validate_admission(thread, accepted_at, database_id)?;
    if record.input.id.is_empty()
        || record.ordinal == 0
        || record.accepted_sequence != accepted_at.effect_seq
    {
        return Err(ProjectionError::MissingInput(record.input.id.clone()));
    }
    record
        .input
        .validate_purpose()
        .map_err(|error| ProjectionError::UserInput(error.to_string()))?;
    let state = match input_view(record) {
        Ok(InputView::Content(content)) => {
            if content.presentation == MessagePresentation::Hidden {
                return Ok(None);
            }
            ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::User,
                content.text,
                content.attachments,
                ThreadContentLifecycle::completed(timestamp),
            ))
        }
        Ok(InputView::ControlNotice { .. }) => return Ok(None),
        Err(error @ ContentError::Unsupported { .. }) => {
            ThreadItemState::Raw(ThreadRawItem::stored(
                vec![original_payload(&record.input.payload)],
                error.to_string(),
                timestamp,
            ))
        }
        Err(error) => return Err(ProjectionError::UserInput(error.to_string())),
    };
    let item = ThreadItem::new(
        record.input.id.clone(),
        thread.id.clone(),
        String::new(),
        record.ordinal,
        record.accepted_sequence,
        timestamp,
        timestamp,
        state,
    );
    freeze_accepted(
        &item,
        ChatSourceId::Input {
            input_id: record.input.id.clone(),
        },
        &record.input.payload,
        accepted_at,
        timestamp,
        database_id,
    )
    .map(Some)
}

pub(in crate::studio) fn accepted_inbox_draft(
    thread: &Thread,
    record: &InboxRecord,
    accepted_at: ChatFactPosition,
    timestamp: i64,
    database_id: &str,
) -> Result<Option<ChatDraft>, ProjectionError> {
    let message = &record.message;
    if message.id.is_empty() || message.source_id.is_empty() || record.sequence == 0 {
        return Err(ProjectionError::History(
            "invalid accepted inbox identity".into(),
        ));
    }
    validate_admission(thread, accepted_at, database_id)?;
    // Preserve the existing trusted parent route. A source prefix or a role claimed in its body
    // cannot grant public eligibility; other adapters must establish that at their own admission.
    let Some(parent) = thread.parent_thread_id.as_ref() else {
        return Ok(None);
    };
    if message.source_id != format!("agent:{parent}") {
        return Ok(None);
    }
    let id = crate::studio::thread_projection::order::message_id(&message.id);
    let state = if message.payload.format() == "text/plain" && message.payload.version() == 1 {
        ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::ParentAgent,
            message.payload.content().into(),
            vec![],
            ThreadContentLifecycle::completed(timestamp),
        ))
    } else {
        ThreadItemState::Raw(ThreadRawItem::stored(
            vec![original_payload(&message.payload)],
            "Opaque accepted parent message",
            timestamp,
        ))
    };
    let item = ThreadItem::new(
        id,
        thread.id.clone(),
        String::new(),
        record.sequence,
        accepted_at.effect_seq,
        timestamp,
        timestamp,
        state,
    );
    freeze_accepted(
        &item,
        ChatSourceId::InboxMessage {
            source_id: message.source_id.clone(),
            message_id: message.id.clone(),
        },
        &message.payload,
        accepted_at,
        timestamp,
        database_id,
    )
    .map(Some)
}

fn original_payload(payload: &OpaquePayload) -> ThreadRawPayload {
    ThreadRawPayload {
        format: payload.format().into(),
        version: payload.version(),
        content: payload.content().into(),
    }
}

fn validate_admission(
    thread: &Thread,
    at: ChatFactPosition,
    database: &str,
) -> Result<(), ProjectionError> {
    if thread.id.is_empty()
        || database.is_empty()
        || at.effect_seq == 0
        || at.effect_seq > i64::MAX as u64
    {
        return Err(ProjectionError::History(
            "accepted content lacks its original admission identity".into(),
        ));
    }
    Ok(())
}

fn freeze_accepted(
    item: &ThreadItem,
    source: ChatSourceId,
    original: &OpaquePayload,
    accepted_at: ChatFactPosition,
    timestamp: i64,
    database_id: &str,
) -> Result<ChatDraft, ProjectionError> {
    if item.thread_id.is_empty()
        || database_id.is_empty()
        || accepted_at.effect_seq == 0
        || accepted_at.effect_seq > i64::MAX as u64
    {
        return Err(ProjectionError::History(
            "accepted content has no reliable admission".into(),
        ));
    }
    let mut descriptor = serde_json::to_value(
        descriptor::item_descriptor(item)
            .map_err(|error| ProjectionError::History(error.to_string()))?,
    )?;
    let mut bodies = content_fields(item.state())
        .map_err(|error| ProjectionError::History(error.to_string()))?;
    let original_block = ContentBlock::from_text(original.content());
    let original_key = [BodyKey::Body, raw_payload_field(0)]
        .into_iter()
        .find(|key| {
            bodies
                .get(key)
                .is_some_and(|body| ContentBlock::text_eq(body, &original_block))
        })
        .unwrap_or_else(|| BodyKey::host("accepted.payload"));
    bodies.entry(original_key.clone()).or_insert(original_block);
    let reference = ContentRef {
        database_id: database_id.into(),
        target: ContentTarget::Body {
            owner: ContentOwner::Item {
                item_id: item.id.clone(),
            },
            key: original_key.as_key(),
        },
    };
    descriptor["data"]["acceptedPayload"] = serde_json::json!({
        "format": original.format(), "version": original.version(), "reference": reference,
    });
    let mut metadata = atom(item);
    metadata.source = source;
    metadata.delivery = ChatDeliveryKind::Independent;
    metadata.turn_id = None;
    metadata.attempt_id = None;
    metadata.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(accepted_at),
        outcome: ChatTerminalOutcome::Completed,
    };
    freeze(
        item,
        CompletionStamp {
            id: &item.id,
            source_effect_seq: accepted_at.effect_seq,
            sealed_at: timestamp,
        },
        database_id,
        descriptor,
        &mut bodies,
        &ChatContents::new(),
        Some(metadata),
    )
    .map_err(|error| ProjectionError::History(error.to_string()))
}
