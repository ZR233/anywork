//! Shared decoders and state mergers for `WorkGroupMember` items across `TimelineDataLayer`
//! and `LiveStatusDataLayer`, ensuring live and cold timelines share one source of truth.

use crate::history::{
    EventPayloadEnvelope, HistoryBodyManifestEntry, HistoryBodyRole, HistoryEntityKind,
    HistoryEntityState, HistoryEventKind, HistoryEventRecord, decode_event_envelope,
};
use crate::ChatTerminalOutcome;

use super::models::{BodyRef, WorkGroupMember};

pub(super) fn manifest_to_body_ref(
    entry: &HistoryBodyManifestEntry,
    owner_event_id: &str,
) -> Option<BodyRef> {
    if let Some(reference) = &entry.reference {
        return Some(BodyRef {
            database_id: reference.database_id.clone(),
            body_id: reference.body_id.clone(),
            owner_event_id: owner_event_id.to_owned(),
            body_key: reference.body_key.clone(),
            role: entry.role.clone(),
            byte_length: entry.byte_length,
            media_type: entry.media_type.clone(),
            inline_text: entry.inline_text.clone(),
        });
    }
    None
}

pub(super) fn manifest_bodies(
    envelope: &EventPayloadEnvelope,
    owner_event_id: &str,
) -> Vec<BodyRef> {
    envelope
        .bodies
        .iter()
        .filter_map(|entry| manifest_to_body_ref(entry, owner_event_id))
        .collect()
}

pub(super) fn find_inline_text(
    envelope: &EventPayloadEnvelope,
    roles: &[&str],
    keys: &[&str],
) -> Option<String> {
    for key in keys {
        if let Some(inline) = envelope
            .bodies
            .iter()
            .find(|b| b.key == *key)
            .and_then(|b| b.inline_text.as_ref())
        {
            return Some(inline.clone());
        }
    }
    for role in roles {
        let joined: Vec<&str> = envelope
            .bodies
            .iter()
            .filter(|b| b.role == *role)
            .filter_map(|b| b.inline_text.as_deref())
            .collect();
        if !joined.is_empty() {
            return Some(joined.join(""));
        }
    }
    None
}

pub(super) fn find_primary_body_ref(
    envelope: &EventPayloadEnvelope,
    owner_event_id: &str,
    preferred_keys: &[&str],
) -> Option<BodyRef> {
    for key in preferred_keys {
        if let Some(entry) = envelope.bodies.iter().find(|b| b.key == *key)
            && let Some(r) = manifest_to_body_ref(entry, owner_event_id)
        {
            return Some(r);
        }
    }
    envelope
        .bodies
        .iter()
        .find(|b| b.role == HistoryBodyRole::Body.as_str())
        .and_then(|b| manifest_to_body_ref(b, owner_event_id))
}

pub(super) fn outcome_label(state: &HistoryEntityState) -> &'static str {
    match state {
        HistoryEntityState::Unknown => "unknown",
        HistoryEntityState::KnownActive { .. } => "active",
        HistoryEntityState::KnownTerminal { outcome } => match outcome {
            ChatTerminalOutcome::Completed => "completed",
            ChatTerminalOutcome::Failed => "failed",
            ChatTerminalOutcome::Cancelled => "cancelled",
            ChatTerminalOutcome::Transferred => "transferred",
        },
    }
}

fn non_empty_str(value: Option<&serde_json::Value>) -> Option<&str> {
    value
        .and_then(serde_json::Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

#[must_use]
pub fn fallback_work_group_member(record: &HistoryEventRecord, reason: String) -> WorkGroupMember {
    WorkGroupMember::Fallback {
        id: record
            .entity_id
            .clone()
            .unwrap_or_else(|| record.event_id.clone()),
        seq: record.seq,
        event_id: record.event_id.clone(),
        event_kind: record.kind.as_str().to_owned(),
        reason,
        occurred_at_ms: record.occurred_at.or(Some(record.recorded_at)),
    }
}

fn decode_reasoning_member(
    record: &HistoryEventRecord,
    envelope: &EventPayloadEnvelope,
    entity_id: String,
    occurred_at_ms: Option<i64>,
) -> WorkGroupMember {
    let text = find_inline_text(envelope, &[HistoryBodyRole::Body.as_str()], &["body"])
        .unwrap_or_default();
    let summary = find_inline_text(
        envelope,
        &[HistoryBodyRole::ReasoningSummary.as_str()],
        &["part.summaryText.0"],
    )
    .unwrap_or_else(|| text.chars().take(120).collect());
    let body_ref = find_primary_body_ref(envelope, &record.event_id, &["body"]);
    let outcome = match non_empty_str(envelope.data.get("outcome").and_then(|o| o.get("kind"))) {
        Some("succeeded" | "completed") => "completed".to_owned(),
        Some("failed") => "failed".to_owned(),
        Some("cancelled") => "cancelled".to_owned(),
        Some("streaming") => "running".to_owned(),
        _ => {
            let label = outcome_label(&envelope.meta.state);
            if record.kind == HistoryEventKind::ReasoningCompleted
                && matches!(label, "active" | "unknown")
            {
                "completed".to_owned()
            } else {
                label.to_owned()
            }
        }
    };
    WorkGroupMember::Reasoning {
        id: entity_id,
        seq: record.seq,
        text,
        summary,
        body_ref,
        outcome,
        started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
        finished_at_ms: envelope.meta.finished_at,
    }
}

fn decode_tool_call_member(
    record: &HistoryEventRecord,
    envelope: &EventPayloadEnvelope,
    entity_id: String,
    occurred_at_ms: Option<i64>,
) -> WorkGroupMember {
    let call_id = record
        .call_id
        .clone()
        .or_else(|| envelope.meta.tool.as_ref().map(|t| t.call_id.clone()))
        .unwrap_or(entity_id);
    let tool_name = record
        .tool_name
        .clone()
        .or_else(|| envelope.meta.tool.as_ref().map(|t| t.name.clone()))
        .unwrap_or_else(|| "tool".into());
    let status = match record.kind {
        HistoryEventKind::ToolCalled => "running".to_owned(),
        HistoryEventKind::ToolWaitingApproval => "awaitingApproval".to_owned(),
        HistoryEventKind::ToolBackgrounded => "backgrounded".to_owned(),
        HistoryEventKind::ToolCancelRequested => "cancelling".to_owned(),
        _ => envelope
            .data
            .get("state")
            .and_then(|s| s.get("kind"))
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| outcome_label(&envelope.meta.state))
            .to_owned(),
    };
    let arguments = find_inline_text(
        envelope,
        &[HistoryBodyRole::ToolArguments.as_str()],
        &["tool.arguments"],
    );
    let result_preview = find_inline_text(
        envelope,
        &[HistoryBodyRole::ToolOutput.as_str()],
        &["tool.result"],
    );
    let wait_json = envelope
        .data
        .get("wait")
        .filter(|v| !v.is_null())
        .and_then(|v| serde_json::to_string(v).ok());
    WorkGroupMember::ToolCall {
        id: format!("call:{call_id}"),
        seq: record.seq,
        call_id,
        turn_id: record.turn_id.clone(),
        tool_name: tool_name.clone(),
        presentation_contract: envelope.meta.presentation_contract.clone(),
        status,
        summary: tool_name,
        arguments,
        result_preview,
        payload_json: record.payload_json.clone(),
        bodies: manifest_bodies(envelope, &record.event_id),
        wait_json,
        started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
        finished_at_ms: envelope.meta.finished_at,
    }
}

fn decode_agent_member(
    record: &HistoryEventRecord,
    envelope: &EventPayloadEnvelope,
    entity_id: String,
    occurred_at_ms: Option<i64>,
) -> WorkGroupMember {
    let identity = envelope.data.get("identity");
    let agent_id = non_empty_str(identity.and_then(|i| i.get("agentId")))
        .or_else(|| non_empty_str(identity.and_then(|i| i.get("id"))))
        .or_else(|| non_empty_str(envelope.data.get("agentId")))
        .unwrap_or(&entity_id)
        .to_owned();
    let role = non_empty_str(identity.and_then(|i| i.get("role")))
        .or_else(|| non_empty_str(envelope.data.get("role")));
    let name = non_empty_str(identity.and_then(|i| i.get("name")))
        .or_else(|| non_empty_str(identity.and_then(|i| i.get("displayName"))))
        .or(role)
        .or_else(|| non_empty_str(identity.and_then(|i| i.get("path"))))
        .or_else(|| non_empty_str(envelope.data.get("name")))
        .or_else(|| {
            record
                .tool_name
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
        })
        .unwrap_or("Agent")
        .to_owned();

    let summary = non_empty_str(identity.and_then(|i| i.get("taskSummary")))
        .or_else(|| non_empty_str(identity.and_then(|i| i.get("task_summary"))))
        .or_else(|| non_empty_str(identity.and_then(|i| i.get("task"))))
        .or_else(|| non_empty_str(envelope.data.get("taskSummary")))
        .or_else(|| non_empty_str(envelope.data.get("task_summary")))
        .or_else(|| non_empty_str(envelope.data.get("summary")))
        .or_else(|| {
            envelope
                .data
                .get("outcome")
                .and_then(|o| o.get("data"))
                .and_then(|d| {
                    non_empty_str(d.get("summary"))
                        .or_else(|| non_empty_str(d.get("reason")))
                        .or_else(|| non_empty_str(d.get("error")))
                })
        })
        .unwrap_or(&name)
        .to_owned();

    let status = match non_empty_str(envelope.data.get("outcome").and_then(|o| o.get("kind"))) {
        Some("queued" | "running") => "running",
        Some("succeeded" | "completed") => "completed",
        Some("failed" | "denied") => "failed",
        Some("cancelled") => "cancelled",
        _ => match record.kind {
            HistoryEventKind::AgentSpawned => "running",
            _ => match &envelope.meta.state {
                HistoryEntityState::Unknown | HistoryEntityState::KnownActive { .. } => "running",
                HistoryEntityState::KnownTerminal { outcome } => match outcome {
                    ChatTerminalOutcome::Completed | ChatTerminalOutcome::Transferred => {
                        "completed"
                    }
                    ChatTerminalOutcome::Failed => "failed",
                    ChatTerminalOutcome::Cancelled => "cancelled",
                },
            },
        },
    }
    .to_owned();

    WorkGroupMember::Agent {
        id: entity_id,
        seq: record.seq,
        agent_id,
        name,
        status,
        summary,
        payload_json: record.payload_json.clone(),
        started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
        finished_at_ms: envelope.meta.finished_at,
    }
}

fn decode_file_change_member(
    record: &HistoryEventRecord,
    envelope: &EventPayloadEnvelope,
    entity_id: String,
    occurred_at_ms: Option<i64>,
) -> WorkGroupMember {
    let summary = non_empty_str(envelope.data.get("path"))
        .or_else(|| non_empty_str(envelope.data.get("summary")))
        .unwrap_or("File change")
        .to_owned();
    WorkGroupMember::FileChange {
        id: entity_id,
        seq: record.seq,
        summary,
        payload_json: record.payload_json.clone(),
        bodies: manifest_bodies(envelope, &record.event_id),
        occurred_at_ms,
    }
}

fn decode_skill_member(
    record: &HistoryEventRecord,
    envelope: &EventPayloadEnvelope,
    entity_id: String,
    occurred_at_ms: Option<i64>,
) -> WorkGroupMember {
    let activation = envelope.data.get("activation");
    let name = non_empty_str(activation.and_then(|a| a.get("name")))
        .or_else(|| non_empty_str(envelope.data.get("name")))
        .unwrap_or("Skill")
        .to_owned();
    let summary = non_empty_str(activation.and_then(|a| a.get("summary")))
        .or_else(|| non_empty_str(activation.and_then(|a| a.get("description"))))
        .or_else(|| non_empty_str(envelope.data.get("summary")))
        .unwrap_or(&name)
        .to_owned();
    WorkGroupMember::Skill {
        id: entity_id,
        seq: record.seq,
        name,
        summary,
        payload_json: record.payload_json.clone(),
        occurred_at_ms,
    }
}

/// Decodes one `HistoryEventRecord` into a `WorkGroupMember`. Returns `None` when the record
/// has no valid `anywork.event/1` envelope or represents a non-member entity kind.
#[must_use]
pub fn decode_work_group_member(record: &HistoryEventRecord) -> Option<WorkGroupMember> {
    let occurred_at_ms = record.occurred_at.or(Some(record.recorded_at));
    let envelope = decode_event_envelope(record).ok()?;
    let entity_id = record
        .entity_id
        .clone()
        .unwrap_or_else(|| envelope.meta.entity_id.clone());

    match envelope.meta.entity_kind {
        HistoryEntityKind::Reasoning => Some(decode_reasoning_member(
            record,
            &envelope,
            entity_id,
            occurred_at_ms,
        )),
        HistoryEntityKind::ToolCall | HistoryEntityKind::Interaction => Some(
            decode_tool_call_member(record, &envelope, entity_id, occurred_at_ms),
        ),
        HistoryEntityKind::Agent => Some(decode_agent_member(
            record,
            &envelope,
            entity_id,
            occurred_at_ms,
        )),
        HistoryEntityKind::FileChange => Some(decode_file_change_member(
            record,
            &envelope,
            entity_id,
            occurred_at_ms,
        )),
        HistoryEntityKind::Skill => Some(decode_skill_member(
            record,
            &envelope,
            entity_id,
            occurred_at_ms,
        )),
        _ => None,
    }
}

/// Merges an incoming `WorkGroupMember` update into an existing folded member entry,
/// preserving initial discovery fields (`started_at_ms`, `arguments`, `bodies`, etc.).
pub fn merge_work_group_member(existing: &mut WorkGroupMember, incoming: WorkGroupMember) {
    match (existing, incoming) {
        (
            WorkGroupMember::ToolCall {
                seq,
                turn_id,
                presentation_contract,
                status,
                summary,
                arguments,
                result_preview,
                payload_json,
                bodies,
                wait_json,
                started_at_ms,
                finished_at_ms,
                ..
            },
            WorkGroupMember::ToolCall {
                seq: new_seq,
                turn_id: new_turn_id,
                presentation_contract: new_contract,
                status: new_status,
                summary: new_summary,
                arguments: new_args,
                result_preview: new_res,
                payload_json: new_payload,
                bodies: new_bodies,
                wait_json: new_wait,
                started_at_ms: new_start,
                finished_at_ms: new_end,
                ..
            },
        ) => {
            *seq = (*seq).max(new_seq);
            if new_turn_id.is_some() {
                *turn_id = new_turn_id;
            }
            if new_contract.is_some() {
                *presentation_contract = new_contract;
            }
            *status = new_status;
            if !new_summary.is_empty() {
                *summary = new_summary;
            }
            for (inline, incoming_text, key) in [
                (arguments, new_args, "tool.arguments"),
                (result_preview, new_res, "tool.result"),
            ] {
                if incoming_text.is_some() {
                    *inline = incoming_text;
                    bodies.retain(|body| body.body_key != key);
                } else if new_bodies.iter().any(|body| body.body_key == key) {
                    *inline = None;
                }
            }
            *payload_json = new_payload;
            for body in new_bodies {
                if let Some(existing_body) = bodies
                    .iter_mut()
                    .find(|existing_body| existing_body.body_key == body.body_key)
                {
                    *existing_body = body;
                } else {
                    bodies.push(body);
                }
            }
            if new_wait.is_some() {
                *wait_json = new_wait;
            }
            if started_at_ms.is_none() {
                *started_at_ms = new_start;
            }
            if new_end.is_some() {
                *finished_at_ms = new_end;
            }
        }
        (
            WorkGroupMember::Agent {
                seq,
                agent_id,
                name,
                status,
                summary,
                payload_json,
                started_at_ms,
                finished_at_ms,
                ..
            },
            WorkGroupMember::Agent {
                seq: new_seq,
                agent_id: new_agent_id,
                name: new_name,
                status: new_status,
                summary: new_summary,
                payload_json: new_payload,
                started_at_ms: new_start,
                finished_at_ms: new_end,
                ..
            },
        ) => {
            *seq = (*seq).max(new_seq);
            if !new_agent_id.is_empty() {
                *agent_id = new_agent_id;
            }
            if !new_name.is_empty() && (new_name != "Agent" || name.is_empty()) {
                *name = new_name;
            }
            *status = new_status;
            if !new_summary.is_empty() && (new_summary != "Agent" || summary.is_empty()) {
                *summary = new_summary;
            }
            *payload_json = new_payload;
            if started_at_ms.is_none() {
                *started_at_ms = new_start;
            }
            if new_end.is_some() {
                *finished_at_ms = new_end;
            }
        }
        (slot, next) => *slot = next,
    }
}
