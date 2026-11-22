use std::collections::BTreeSet;

use super::{body::decode_business_head_raw, *};

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct PayloadValidationProbe {
    #[serde(default)]
    meta: Option<PayloadMetaProbe>,
    #[serde(default)]
    bodies: Vec<HistoryBodyManifestEntry>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct PayloadMetaProbe {
    #[serde(default)]
    wait: Option<HistoryWaitHead>,
}

pub(super) fn event(event: &HistoryEvent) -> Result<usize> {
    if event.seq != 0 {
        return Err(HistoryError::InvalidEvent(
            "caller must not assign event sequence".into(),
        ));
    }
    validate_common(event)
}

pub(super) fn validate_common(event: &HistoryEvent) -> Result<usize> {
    if event.event_id.is_empty() {
        return Err(HistoryError::InvalidEvent(
            "event_id must not be empty".into(),
        ));
    }
    if event.kind.as_str().is_empty() {
        return Err(HistoryError::InvalidEvent(
            "event kind must not be empty".into(),
        ));
    }
    if event.payload_schema.is_empty() {
        return Err(HistoryError::InvalidEvent(
            "payload_schema must not be empty".into(),
        ));
    }
    let parsed: serde_json::Value = serde_json::from_str(&event.payload_json).map_err(|error| {
        HistoryError::InvalidEvent(format!("payload_json is not valid JSON: {error}"))
    })?;
    if !parsed.is_object() {
        return Err(HistoryError::InvalidEvent(
            "payload_json must be a JSON object".into(),
        ));
    }

    match (event.row_scope, &event.row_key) {
        (Some(scope), Some(row_key)) => {
            if event.timeline_role != HistoryTimelineRole::Hidden {
                return Err(HistoryError::InvalidEvent(
                    "business anchor row must use timeline_role = hidden".into(),
                ));
            }
            if row_key.is_empty() {
                return Err(HistoryError::InvalidEvent(
                    "row_key must not be empty".into(),
                ));
            }
            let head = decode_business_head_raw(scope, &event.payload_json)?;
            match (&head, scope) {
                (HistoryBusinessRowHead::Turn(turn), HistoryBusinessRowScope::Turn) => {
                    if row_key != &format!("turn:{}", turn.turn_id)
                        || event.turn_id.as_deref() != Some(turn.turn_id.as_str())
                    {
                        return Err(HistoryError::InvalidEvent(
                            "turn business row identity differs from turn_id or row_key".into(),
                        ));
                    }
                }
                (HistoryBusinessRowHead::Source(src), HistoryBusinessRowScope::Source) => {
                    let expected = format!("source:{}", serde_json::to_string(&src.source)?);
                    if row_key != &expected || event.source.as_ref() != Some(&src.source) {
                        return Err(HistoryError::InvalidEvent(
                            "source business row identity differs from source or row_key".into(),
                        ));
                    }
                }
                (HistoryBusinessRowHead::Cost(cost), HistoryBusinessRowScope::Cost) => {
                    if row_key != &cost.row_key()? || cost.currency.is_empty() {
                        return Err(HistoryError::InvalidEvent(
                            "cost business row identity differs or currency is empty".into(),
                        ));
                    }
                }
                (HistoryBusinessRowHead::Accounting(_), HistoryBusinessRowScope::Accounting) => {
                    if row_key != "accounting:session" {
                        return Err(HistoryError::InvalidEvent(
                            "accounting row must use accounting:session row_key".into(),
                        ));
                    }
                }
                _ => {
                    return Err(HistoryError::InvalidEvent(
                        "business row head scope mismatch".into(),
                    ));
                }
            }
        }
        (None, None) => {
            if event.is_anchor {
                return Err(HistoryError::InvalidEvent(
                    "is_anchor requires row_scope and row_key".into(),
                ));
            }
        }
        _ => {
            return Err(HistoryError::InvalidEvent(
                "row_scope and row_key must both be set or both be absent".into(),
            ));
        }
    }

    if let Some(original) = &event.original {
        if original.query_class.is_empty() {
            return Err(HistoryError::InvalidEvent(
                "original query_class must not be empty".into(),
            ));
        }
        if let Some(tool) = &original.tool_name
            && event.tool_name.as_deref() != Some(tool.as_str())
        {
            return Err(HistoryError::InvalidEvent(
                "original tool_name differs from indexed tool_name".into(),
            ));
        }
    }

    let mut body_ids = BTreeSet::new();
    let mut body_keys = BTreeSet::new();
    let mut retained_bytes = event.event_id.len()
        + event.kind.as_str().len()
        + event.payload_schema.len()
        + event.payload_json.len()
        + 256;
    for body in &event.bodies {
        if body.body_id.is_empty() || body.body_key.is_empty() {
            return Err(HistoryError::InvalidEvent(
                "body_id and body_key must not be empty".into(),
            ));
        }
        if body.role.as_str().is_empty() {
            return Err(HistoryError::InvalidEvent(
                "body role must not be empty".into(),
            ));
        }
        if !body_ids.insert(body.body_id.as_str()) || !body_keys.insert(body.body_key.as_str()) {
            return Err(HistoryError::InvalidEvent(
                "duplicate body_id or body_key in event".into(),
            ));
        }
        retained_bytes = retained_bytes
            .saturating_add(body.body_id.len())
            .saturating_add(body.body_key.len())
            .saturating_add(body.bytes.len())
            .saturating_add(128);
    }
    Ok(retained_bytes)
}

pub(super) fn query(query: &HistoryEventsQuery) -> Result<()> {
    match query {
        HistoryEventsQuery::AllEvents | HistoryEventsQuery::TextOriginals => Ok(()),
        HistoryEventsQuery::Entity { entity_id } if !entity_id.is_empty() => Ok(()),
        HistoryEventsQuery::Turn { turn_id } if !turn_id.is_empty() => Ok(()),
        HistoryEventsQuery::Source { .. } => Ok(()),
        HistoryEventsQuery::Call { call_id } if !call_id.is_empty() => Ok(()),
        HistoryEventsQuery::Message { message_id } if !message_id.is_empty() => Ok(()),
        HistoryEventsQuery::Attempt { run_id, attempt_id }
            if !run_id.is_empty() && !attempt_id.is_empty() =>
        {
            Ok(())
        }
        HistoryEventsQuery::Originals { scope } => {
            if scope
                .parent_id
                .as_ref()
                .is_some_and(|parent| parent.as_str().is_empty())
            {
                return Err(HistoryError::InvalidDemand(
                    "empty parent scope identity".into(),
                ));
            }
            Ok(())
        }
        _ => Err(HistoryError::InvalidDemand(
            "empty history query identity".into(),
        )),
    }
}

pub(super) fn references(event: &HistoryEvent) -> (Vec<String>, Vec<HistoryEventBodyRef>) {
    let mut events = Vec::new();
    let mut bodies = Vec::new();
    if let Some(scope) = event.row_scope
        && let Ok(head) = decode_business_head_raw(scope, &event.payload_json)
    {
        match head {
            HistoryBusinessRowHead::Turn(head) => {
                if let Some(id) = head.detail_event_id {
                    events.push(id);
                }
            }
            HistoryBusinessRowHead::Source(head) => {
                if let Some(id) = head.detail_event_id {
                    events.push(id);
                }
            }
            HistoryBusinessRowHead::Cost(head) => {
                if let Some(id) = head.detail_event_id {
                    events.push(id);
                }
            }
            HistoryBusinessRowHead::Accounting(head) => {
                if let Some(id) = head.detail_event_id {
                    events.push(id);
                }
            }
        }
    }
    if let Ok(probe) = serde_json::from_str::<PayloadValidationProbe>(&event.payload_json) {
        for entry in probe.bodies {
            if let Some(reference) = entry.reference {
                bodies.push(reference);
            }
        }
        if let Some(HistoryWaitHead::Deferred { presentation, .. }) =
            probe.meta.and_then(|meta| meta.wait)
        {
            bodies.push(presentation);
        }
    }
    (events, bodies)
}
