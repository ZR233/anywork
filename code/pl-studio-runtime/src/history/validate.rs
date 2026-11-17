use super::*;
use std::collections::BTreeSet;

pub(super) fn event(event: &HistoryEvent) -> Result<usize> {
    let h = &event.header;
    let invalid = |message: &str| HistoryError::InvalidEvent(format!("{}: {message}", h.event_id));
    let header_bytes = serde_json::to_vec(h)?.len();
    if header_bytes > HEAD_MAX_BYTES {
        return Err(invalid("event metadata exceeds 16 KiB"));
    }
    if h.seq != 0 || h.event_id.is_empty() || matches!(h.kind, HistoryEventKind::Other(_)) {
        return Err(invalid(
            "only known events with an owner-assigned sequence are writable",
        ));
    }
    for value in [
        &h.run_id,
        &h.attempt_id,
        &h.entity_id,
        &h.turn_id,
        &h.call_id,
        &h.message_id,
        &h.group_id,
        &h.row_key,
    ]
    .into_iter()
    .flatten()
    {
        if value.is_empty() {
            return Err(invalid("empty optional identity"));
        }
    }
    if h.attempt_id.is_some()
        && h.run_id.is_none()
        && !matches!(
            h.kind,
            HistoryEventKind::LegacyObserved | HistoryEventKind::BoundaryObserved
        )
    {
        return Err(invalid("attempt requires its runtime epoch"));
    }
    if event.head.is_some() != h.row_key.is_some() || (event.is_anchor && event.head.is_none()) {
        return Err(invalid("row head, identity and anchor differ"));
    }
    if let Some(head) = &event.head {
        if serde_json::to_vec(head)?.len() > HEAD_MAX_BYTES {
            return Err(invalid("row head exceeds 16 KiB"));
        }
        match head {
            HistoryRowHead::Work(work) => {
                if h.group_id.as_deref() != Some(&work.group_id)
                    || h.row_key.as_deref() != Some(&format!("work:{}", work.group_id))
                    || work.unfinished_count > work.member_count
                    || work.run_id != h.run_id
                    || (work.closed
                        && h.kind != HistoryEventKind::GroupClosed
                        && h.kind != HistoryEventKind::LegacyObserved)
                {
                    return Err(invalid("work header identity, count or closure differs"));
                }
            }
            HistoryRowHead::Single(entity) | HistoryRowHead::Member(entity) => {
                if h.entity_id.as_deref() != Some(&entity.entity_id)
                    || h.source.as_ref() != Some(&entity.source)
                    || h.run_id != entity.run_id
                    || h.attempt_id != entity.attempt_id
                {
                    return Err(invalid("entity head differs from indexed identity"));
                }
                if matches!(head, HistoryRowHead::Member(_)) && h.group_id.is_none() {
                    return Err(invalid("member requires a group"));
                }
                if let Some(tool) = &entity.tool
                    && h.call_id.as_deref() != Some(&tool.call_id)
                {
                    return Err(invalid("tool identity differs"));
                }
                if matches!(entity.state, HistoryEntityState::KnownActive { .. })
                    && entity.finished_at.is_some()
                {
                    return Err(invalid("active entity cannot have a finish time"));
                }
            }
            HistoryRowHead::Turn(turn) => {
                if h.turn_id.as_deref() != Some(&turn.turn_id)
                    || h.row_key.as_deref() != Some(&format!("turn:{}", turn.turn_id))
                    || (turn.phase.is_some() && turn.state != HistoryTurnState::Running)
                    || (matches!(
                        turn.state,
                        HistoryTurnState::Queued | HistoryTurnState::Running
                    ) && turn.finished_at.is_some())
                {
                    return Err(invalid("invalid turn state or identity"));
                }
            }
            HistoryRowHead::Source(source) => {
                if h.source.as_ref() != Some(&source.source)
                    || h.row_key.as_deref()
                        != Some(&format!(
                            "source:{}",
                            serde_json::to_string(&source.source)?
                        ))
                {
                    return Err(invalid("source head differs"));
                }
            }
            HistoryRowHead::Cost(cost) => {
                if cost.currency.is_empty()
                    || !cost.cost_total.is_finite()
                    || [
                        cost.cost_delta,
                        cost.cache_savings_delta,
                        cost.cache_savings_total,
                    ]
                    .into_iter()
                    .flatten()
                    .any(|value| !value.is_finite())
                    || h.row_key.as_deref() != Some(&cost.row_key()?)
                {
                    return Err(invalid("cost identity or finite amount is invalid"));
                }
            }
            HistoryRowHead::Accounting(accounting) => {
                if h.row_key.as_deref() != Some("accounting:session")
                    || accounting
                        .cache_usage
                        .hit_rate
                        .is_some_and(|value| !value.is_finite())
                {
                    return Err(invalid("invalid accounting head"));
                }
            }
        }
    }
    let mut ids = BTreeSet::new();
    let mut keys = BTreeSet::new();
    let mut bytes = header_bytes.saturating_mul(12)
        + event
            .head
            .as_ref()
            .map(serde_json::to_vec)
            .transpose()?
            .map_or(0, |head| head.len())
        + 256;
    for body in &event.bodies {
        let uuid =
            uuid::Uuid::parse_str(&body.body_id).map_err(|_| invalid("body ID must be UUIDv4"))?;
        if uuid.get_version_num() != 4
            || body.body_key.is_empty()
            || body.role.as_str().is_empty()
            || !ids.insert(&body.body_id)
            || !keys.insert(&body.body_key)
        {
            return Err(invalid("invalid or duplicate immutable body identity"));
        }
        bytes = bytes
            .checked_add(body.bytes.len())
            .and_then(|bytes| {
                bytes.checked_add(
                    4 * (h.event_id.len()
                        + body.body_id.len()
                        + body.body_key.len()
                        + body.role.as_str().len()
                        + body.media_type.as_ref().map_or(0, String::len))
                        + 256,
                )
            })
            .ok_or_else(|| invalid("pending byte count overflow"))?;
    }
    if let Some(payload) = &event.payload_body_id
        && !event
            .bodies
            .iter()
            .any(|body| &body.body_id == payload && body.role == HistoryBodyRole::CanonicalPayload)
    {
        return Err(invalid("payload must be an owned canonical payload body"));
    }
    if h.kind == HistoryEventKind::BusinessChanged {
        let payload = event
            .bodies
            .iter()
            .find(|body| Some(&body.body_id) == event.payload_body_id.as_ref())
            .ok_or_else(|| invalid("business event requires a versioned domain payload"))?;
        let _: pl_core::context::OpaquePayload = serde_json::from_slice(&payload.bytes)
            .map_err(|_| invalid("business payload must retain its domain format and version"))?;
    }
    if let Some(original) = &h.original {
        if original.query_class.is_empty()
            || event.payload_body_id.is_none()
            || !matches!(
                h.kind,
                HistoryEventKind::EntityEnded
                    | HistoryEventKind::InputAccepted
                    | HistoryEventKind::LegacyObserved
            )
        {
            return Err(invalid("invalid canonical original"));
        }
        let entity = match &event.head {
            Some(HistoryRowHead::Single(entity) | HistoryRowHead::Member(entity)) => entity.clone(),
            _ => {
                let metadata = event
                    .bodies
                    .iter()
                    .find(|body| body.role == HistoryBodyRole::CanonicalMetadata)
                    .ok_or_else(|| {
                        invalid("unrendered canonical original requires typed metadata")
                    })?;
                serde_json::from_slice(&metadata.bytes)?
            }
        };
        if entity.kind != original.original_kind
            || entity.entity_id != h.entity_id.clone().unwrap_or_default()
            || entity.tool.as_ref().map(|tool| &tool.name) != original.tool_name.as_ref()
        {
            return Err(invalid("canonical indexes differ from typed original head"));
        }
    }
    Ok(bytes)
}

pub(super) fn query(query: &HistoryEventsQuery) -> Result<()> {
    let empty = match query {
        HistoryEventsQuery::Entity { entity_id } => entity_id.is_empty(),
        HistoryEventsQuery::Turn { turn_id } => turn_id.is_empty(),
        HistoryEventsQuery::Call { call_id } => call_id.is_empty(),
        HistoryEventsQuery::Message { message_id } => message_id.is_empty(),
        HistoryEventsQuery::Attempt { run_id, attempt_id } => {
            run_id.is_empty() || attempt_id.is_empty()
        }
        HistoryEventsQuery::Originals { scope } => !scope.is_valid(),
        _ => false,
    };
    if empty {
        return Err(HistoryError::InvalidDemand(
            "empty history query identity".into(),
        ));
    }
    Ok(())
}

pub(super) fn references(event: &HistoryEvent) -> (Vec<&str>, Vec<&HistoryEventBodyRef>) {
    let mut events = Vec::new();
    let mut bodies = Vec::new();
    match &event.head {
        Some(HistoryRowHead::Single(head) | HistoryRowHead::Member(head)) => {
            events.extend(
                [
                    head.detail_event_id.as_deref(),
                    head.input_manifest_event_id.as_deref(),
                    head.body_manifest_event_id.as_deref(),
                ]
                .into_iter()
                .flatten(),
            );
            if let Some(HistoryWaitHead::Deferred { presentation, .. }) = &head.wait {
                bodies.push(presentation);
            }
        }
        Some(HistoryRowHead::Turn(head)) => events.extend(head.detail_event_id.as_deref()),
        Some(HistoryRowHead::Source(head)) => events.extend(head.detail_event_id.as_deref()),
        Some(HistoryRowHead::Cost(head)) => events.extend(head.detail_event_id.as_deref()),
        Some(HistoryRowHead::Accounting(head)) => events.extend(head.detail_event_id.as_deref()),
        _ => {}
    }
    (events, bodies)
}
