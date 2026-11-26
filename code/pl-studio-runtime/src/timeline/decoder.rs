//! Stateless decoders turning Schema 27 `HistoryEventRecord` rows into typed `TimelineItem`
//! and folded `WorkGroupMember` presentation models with single-row Fallback resilience.

use std::collections::BTreeMap;

use crate::history::{
    EventPayloadEnvelope, HistoryBodyManifestEntry, HistoryBodyRole, HistoryEntityKind,
    HistoryEntityState, HistoryEventKind, HistoryEventRecord, decode_event_envelope,
};
use crate::{ChatSourceId, ChatTerminalOutcome, ThreadTextChannel};

use super::models::{BodyRef, TimelineItem, TimelineItemId, WorkGroupMember, WorkGroupStatus};

pub fn boundary_item_id(seq: u64) -> TimelineItemId {
    format!("msg:{seq}")
}

pub fn work_group_item_id(first_seq: u64) -> TimelineItemId {
    format!("work:{first_seq}")
}

fn manifest_to_body_ref(entry: &HistoryBodyManifestEntry, owner_event_id: &str) -> Option<BodyRef> {
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

fn manifest_bodies(envelope: &EventPayloadEnvelope, owner_event_id: &str) -> Vec<BodyRef> {
    envelope
        .bodies
        .iter()
        .filter_map(|entry| manifest_to_body_ref(entry, owner_event_id))
        .collect()
}

fn find_inline_text(envelope: &EventPayloadEnvelope, roles: &[&str], keys: &[&str]) -> Option<String> {
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

fn find_primary_body_ref(
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

fn outcome_label(state: &HistoryEntityState) -> &'static str {
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

fn fallback_boundary(record: &HistoryEventRecord, reason: String) -> TimelineItem {
    TimelineItem::Fallback {
        id: boundary_item_id(record.seq),
        seq: record.seq,
        event_id: record.event_id.clone(),
        event_kind: record.kind.as_str().to_owned(),
        reason,
        raw_preview: (!record.payload_json.is_empty())
            .then(|| record.payload_json.chars().take(240).collect()),
        occurred_at_ms: record.occurred_at.or(Some(record.recorded_at)),
    }
}

/// Decodes one `timeline_role = 2` (`Boundary`) record into a `TimelineItem`.
/// Never fails the entire page on a single corrupt/unknown record: returns `TimelineItem::Fallback`.
#[must_use]
pub fn decode_boundary_item(record: &HistoryEventRecord) -> TimelineItem {
    let id = boundary_item_id(record.seq);
    let occurred_at_ms = record.occurred_at.or(Some(record.recorded_at));
    let turn_id = record.turn_id.clone();

    if record.payload_schema != "anywork.event/1" {
        return fallback_boundary(
            record,
            format!("unsupported payload_schema {}", record.payload_schema),
        );
    }

    let envelope = match decode_event_envelope(record) {
        Ok(env) => env,
        Err(error) => return fallback_boundary(record, format!("invalid event envelope: {error}")),
    };

    if record.kind == HistoryEventKind::ConnectionDisconnected
        || record.kind == HistoryEventKind::ConnectionReconnected
        || envelope.item_type == "connection"
    {
        let data = &envelope.data;
        let scope = data
            .get("scope")
            .and_then(|v| v.as_str())
            .unwrap_or("model")
            .to_owned();
        let state = data
            .get("state")
            .and_then(|v| v.as_str())
            .unwrap_or(record.kind.as_str())
            .to_owned();
        let transport = data
            .get("transport")
            .and_then(|v| v.as_str())
            .unwrap_or("http")
            .to_owned();
        let fallback_transport = data
            .get("fallbackTransport")
            .and_then(|v| v.as_str())
            .map(str::to_owned);
        let attempt = data.get("attempt").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let max_attempts = data
            .get("maxAttempts")
            .and_then(|v| v.as_u64())
            .unwrap_or(0) as u32;
        let recoverable = data
            .get("recoverable")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let reason = data
            .get("reason")
            .and_then(|v| v.as_str())
            .map(str::to_owned);
        let duration_ms = data.get("durationMs").and_then(|v| v.as_u64());
        return TimelineItem::ConnectionNotice {
            id,
            seq: record.seq,
            turn_id,
            scope,
            state,
            transport,
            fallback_transport,
            attempt,
            max_attempts,
            recoverable,
            reason,
            duration_ms,
            occurred_at_ms,
        };
    }

    if record.kind == HistoryEventKind::CompactionCompleted
        || envelope.meta.entity_kind == HistoryEntityKind::Compaction
        || envelope.item_type == "contextCompaction"
    {
        let data = &envelope.data;
        let summary = data
            .get("summary")
            .and_then(|v| v.as_str())
            .or_else(|| data.get("reason").and_then(|v| v.as_str()))
            .unwrap_or("Context compacted")
            .to_owned();
        let tokens_before = data.get("tokensBefore").and_then(|v| v.as_u64());
        let tokens_after = data.get("tokensAfter").and_then(|v| v.as_u64());
        return TimelineItem::Compaction {
            id,
            seq: record.seq,
            turn_id,
            summary,
            outcome: outcome_label(&envelope.meta.state).to_owned(),
            tokens_before,
            tokens_after,
            occurred_at_ms,
        };
    }

    if record.kind == HistoryEventKind::PlanResolved
        || envelope.meta.entity_kind == HistoryEntityKind::Plan
        || envelope.item_type == "plan"
    {
        let data = &envelope.data;
        let decision = data
            .get("decision")
            .and_then(|v| v.as_str())
            .unwrap_or("resolved")
            .to_owned();
        let document = find_inline_text(&envelope, &[], &["plan.document"]);
        let document_ref = find_primary_body_ref(&envelope, &record.event_id, &["plan.document"]);
        let feedback = find_inline_text(&envelope, &[], &["plan.feedback"]);
        return TimelineItem::PlanResolution {
            id,
            seq: record.seq,
            turn_id,
            decision,
            document,
            document_ref,
            feedback,
            occurred_at_ms,
        };
    }

    if record.kind == HistoryEventKind::TurnReceiptRecorded
        || envelope.meta.entity_kind == HistoryEntityKind::TurnReceipt
        || envelope.item_type == "turn"
    {
        let data = &envelope.data;
        let input_id = data
            .get("inputId")
            .and_then(|v| v.as_str())
            .map(str::to_owned);
        let outcome = data
            .get("outcome")
            .and_then(|o| o.get("kind"))
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| outcome_label(&envelope.meta.state))
            .to_owned();
        let message = data
            .get("outcome")
            .and_then(|o| o.get("data"))
            .and_then(|d| {
                d.get("reason")
                    .or_else(|| d.get("message"))
                    .or_else(|| d.get("error").and_then(|e| e.get("message")))
            })
            .and_then(|v| v.as_str())
            .map(str::to_owned);
        let turn_failure = data
            .get("outcome")
            .and_then(|o| o.get("data"))
            .and_then(|d| d.get("failure"))
            .and_then(|value| serde_json::from_value::<crate::TurnFailure>(value.clone()).ok())
            .map(Box::new);
        return TimelineItem::TurnOutcome {
            id,
            seq: record.seq,
            turn_id,
            input_id,
            outcome,
            message,
            turn_failure,
            occurred_at_ms,
        };
    }

    if record.kind == HistoryEventKind::InputAccepted
        || record.kind == HistoryEventKind::InboxMessageReceived
        || envelope.meta.entity_kind == HistoryEntityKind::Input
        || (envelope.meta.entity_kind == HistoryEntityKind::Text
            && matches!(
                envelope.meta.text_channel,
                Some(ThreadTextChannel::User | ThreadTextChannel::ParentAgent)
            ))
    {
        let text = find_inline_text(
            &envelope,
            &[HistoryBodyRole::Body.as_str()],
            &["body", "accepted.payload"],
        )
        .unwrap_or_default();
        let input_id = match &record.source {
            Some(ChatSourceId::Input { input_id }) => Some(input_id.clone()),
            _ => None,
        };
        let channel = match envelope.meta.text_channel {
            Some(ThreadTextChannel::ParentAgent) => "parentAgent",
            _ => "user",
        }
        .to_owned();
        let attachments = envelope
            .data
            .get("attachments")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();
        return TimelineItem::UserMessage {
            id,
            seq: record.seq,
            turn_id,
            input_id,
            channel,
            text,
            attachments,
            occurred_at_ms,
        };
    }

    if matches!(
        envelope.meta.entity_kind,
        HistoryEntityKind::ToolCall | HistoryEntityKind::Interaction
    ) || envelope.item_type == "tool"
    {
        let call_id = record
            .call_id
            .clone()
            .or_else(|| envelope.meta.tool.as_ref().map(|t| t.call_id.clone()))
            .or_else(|| {
                envelope
                    .data
                    .get("invocation")
                    .and_then(|i| i.get("toolCallId"))
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
            })
            .unwrap_or_else(|| envelope.meta.entity_id.clone());
        let tool_name = record
            .tool_name
            .clone()
            .or_else(|| envelope.meta.tool.as_ref().map(|t| t.name.clone()))
            .or_else(|| {
                envelope
                    .data
                    .get("invocation")
                    .and_then(|i| i.get("name"))
                    .and_then(|v| v.as_str())
                    .map(str::to_owned)
            })
            .unwrap_or_else(|| "tool".into());
        let state = envelope
            .data
            .get("state")
            .and_then(|s| s.get("kind"))
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| outcome_label(&envelope.meta.state))
            .to_owned();
        return TimelineItem::StandaloneTool {
            id,
            seq: record.seq,
            turn_id,
            call_id,
            tool_name: tool_name.clone(),
            presentation_contract: envelope.meta.presentation_contract.clone(),
            state,
            summary: tool_name,
            payload_json: record.payload_json.clone(),
            bodies: manifest_bodies(&envelope, &record.event_id),
            occurred_at_ms,
        };
    }

    if record.kind == HistoryEventKind::TextCompleted
        || envelope.meta.entity_kind == HistoryEntityKind::Text
        || envelope.item_type == "text"
    {
        let channel = match envelope.meta.text_channel {
            Some(ThreadTextChannel::Commentary) => "commentary",
            Some(ThreadTextChannel::Final) => "final",
            Some(ThreadTextChannel::ParentAgent) => "parentAgent",
            Some(ThreadTextChannel::User) => "user",
            None => "final",
        };
        let text = find_inline_text(&envelope, &[HistoryBodyRole::Body.as_str()], &["body"])
            .unwrap_or_default();
        let body_ref = find_primary_body_ref(&envelope, &record.event_id, &["body"]);
        let outcome = outcome_label(&envelope.meta.state).to_owned();
        return TimelineItem::AssistantText {
            id,
            seq: record.seq,
            turn_id,
            attempt_id: record.attempt_id.clone(),
            channel: channel.to_owned(),
            text,
            body_ref,
            is_final_turn_delivery: channel == "final" && outcome == "completed",
            outcome,
            model_recovery: envelope.meta.model_recovery.clone().map(Box::new),
            occurred_at_ms,
        };
    }

    fallback_boundary(
        record,
        format!("unhandled timeline boundary kind {}", record.kind.as_str()),
    )
}

#[must_use]
pub fn summarize_work_group(
    events: &[HistoryEventRecord],
    after_boundary_seq: Option<u64>,
    before_boundary_seq: Option<u64>,
    active: bool,
) -> Option<TimelineItem> {
    let first = events.first()?;
    let last = events.last()?;
    let members = fold_work_group_members(events.to_vec());
    let member_count = u32::try_from(members.len()).unwrap_or(u32::MAX);
    let mut tool_names = Vec::new();
    let mut has_failed = false;
    let mut has_cancelled = false;
    let mut started_at_ms = first.occurred_at.or(Some(first.recorded_at));
    let mut finished_at_ms = last.occurred_at.or(Some(last.recorded_at));

    for member in &members {
        match member {
            WorkGroupMember::ToolCall {
                tool_name,
                status,
                started_at_ms: s,
                finished_at_ms: f,
                ..
            } => {
                if !tool_names.contains(tool_name) {
                    tool_names.push(tool_name.clone());
                }
                if status == "failed" || status == "denied" {
                    has_failed = true;
                } else if status == "cancelled" || status == "interrupted" {
                    has_cancelled = true;
                }
                if let Some(s) = s {
                    started_at_ms = Some(started_at_ms.map_or(*s, |cur| cur.min(*s)));
                }
                if let Some(f) = f {
                    finished_at_ms = Some(finished_at_ms.map_or(*f, |cur| cur.max(*f)));
                }
            }
            WorkGroupMember::Reasoning { outcome, .. } => {
                if outcome == "failed" {
                    has_failed = true;
                } else if outcome == "cancelled" {
                    has_cancelled = true;
                }
            }
            WorkGroupMember::Wait { status, .. } | WorkGroupMember::Agent { status, .. } => {
                if status == "failed" || status == "denied" {
                    has_failed = true;
                } else if status == "cancelled" {
                    has_cancelled = true;
                }
            }
            _ => {}
        }
    }

    let status = if active {
        WorkGroupStatus::Active
    } else if has_failed {
        WorkGroupStatus::Failed
    } else if has_cancelled {
        WorkGroupStatus::Cancelled
    } else {
        WorkGroupStatus::Completed
    };

    let summary = if !tool_names.is_empty() {
        let preview: Vec<&str> = tool_names.iter().take(3).map(String::as_str).collect();
        if tool_names.len() > 3 {
            format!("{} +{}", preview.join(", "), tool_names.len() - 3)
        } else {
            preview.join(", ")
        }
    } else if members
        .iter()
        .any(|m| matches!(m, WorkGroupMember::Reasoning { .. }))
    {
        "Reasoning".into()
    } else {
        format!("{member_count} work steps")
    };

    Some(TimelineItem::WorkGroup {
        id: work_group_item_id(first.seq),
        first_seq: first.seq,
        last_seq: last.seq,
        after_boundary_seq,
        before_boundary_seq,
        member_count,
        summary,
        status,
        started_at_ms,
        finished_at_ms,
    })
}

/// Folds `timeline_role = 1` events in a `WorkRange` by `call_id` / `entity_id` into latest-state members,
/// preserving initial discovery order.
#[must_use]
pub fn fold_work_group_members(events: Vec<HistoryEventRecord>) -> Vec<WorkGroupMember> {
    let mut order: Vec<String> = Vec::new();
    let mut folded: BTreeMap<String, WorkGroupMember> = BTreeMap::new();

    for record in events {
        let member = decode_work_member(&record);
        let key = member.id().to_owned();
        if let Some(existing) = folded.get_mut(&key) {
            merge_member(existing, member);
        } else {
            order.push(key.clone());
            folded.insert(key, member);
        }
    }

    order
        .into_iter()
        .filter_map(|key| folded.remove(&key))
        .collect()
}

fn merge_member(existing: &mut WorkGroupMember, incoming: WorkGroupMember) {
    match (existing, incoming) {
        (
            WorkGroupMember::ToolCall {
                seq,
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
            if new_contract.is_some() {
                *presentation_contract = new_contract;
            }
            *status = new_status;
            if !new_summary.is_empty() {
                *summary = new_summary;
            }
            if new_args.is_some() {
                *arguments = new_args;
            }
            if new_res.is_some() {
                *result_preview = new_res;
            }
            *payload_json = new_payload;
            if !new_bodies.is_empty() {
                *bodies = new_bodies;
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
        (slot, next) => *slot = next,
    }
}

fn decode_work_member(record: &HistoryEventRecord) -> WorkGroupMember {
    let occurred_at_ms = record.occurred_at.or(Some(record.recorded_at));
    let Ok(envelope) = decode_event_envelope(record) else {
        return WorkGroupMember::Fallback {
            id: record
                .entity_id
                .clone()
                .unwrap_or_else(|| record.event_id.clone()),
            seq: record.seq,
            event_id: record.event_id.clone(),
            event_kind: record.kind.as_str().to_owned(),
            reason: "invalid work member payload".into(),
            occurred_at_ms,
        };
    };

    let entity_id = record
        .entity_id
        .clone()
        .unwrap_or_else(|| envelope.meta.entity_id.clone());

    match envelope.meta.entity_kind {
        HistoryEntityKind::Reasoning => {
            let text = find_inline_text(&envelope, &[HistoryBodyRole::Body.as_str()], &["body"])
                .unwrap_or_default();
            let summary = find_inline_text(
                &envelope,
                &[HistoryBodyRole::ReasoningSummary.as_str()],
                &["part.summaryText.0"],
            )
            .unwrap_or_else(|| text.chars().take(120).collect());
            let body_ref = find_primary_body_ref(&envelope, &record.event_id, &["body"]);
            WorkGroupMember::Reasoning {
                id: entity_id,
                seq: record.seq,
                text,
                summary,
                body_ref,
                outcome: outcome_label(&envelope.meta.state).to_owned(),
                started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
                finished_at_ms: envelope.meta.finished_at,
            }
        }
        HistoryEntityKind::ToolCall | HistoryEntityKind::Interaction => {
            let call_id = record
                .call_id
                .clone()
                .or_else(|| envelope.meta.tool.as_ref().map(|t| t.call_id.clone()))
                .unwrap_or_else(|| entity_id.clone());
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
                &envelope,
                &[HistoryBodyRole::ToolArguments.as_str()],
                &["tool.arguments"],
            );
            let result_preview = find_inline_text(
                &envelope,
                &[HistoryBodyRole::ToolOutput.as_str()],
                &["tool.result"],
            );
            let wait_json = envelope
                .data
                .get("wait")
                .filter(|v| !v.is_null())
                .and_then(|v| serde_json::to_string(v).ok());
            if let Some(wait) = &wait_json
                && matches!(tool_name.as_str(), "wait" | "sleep")
            {
                return WorkGroupMember::Wait {
                    id: format!("call:{call_id}"),
                    seq: record.seq,
                    call_id,
                    summary: tool_name,
                    status,
                    wait_json: wait.clone(),
                    started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
                    finished_at_ms: envelope.meta.finished_at,
                };
            }
            WorkGroupMember::ToolCall {
                id: format!("call:{call_id}"),
                seq: record.seq,
                call_id,
                tool_name: tool_name.clone(),
                presentation_contract: envelope.meta.presentation_contract.clone(),
                status,
                summary: tool_name,
                arguments,
                result_preview,
                payload_json: record.payload_json.clone(),
                bodies: manifest_bodies(&envelope, &record.event_id),
                wait_json,
                started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
                finished_at_ms: envelope.meta.finished_at,
            }
        }
        HistoryEntityKind::Agent => WorkGroupMember::Agent {
            id: entity_id.clone(),
            seq: record.seq,
            agent_id: envelope
                .data
                .get("identity")
                .and_then(|i| i.get("agentId"))
                .and_then(|v| v.as_str())
                .unwrap_or(&entity_id)
                .to_owned(),
            name: envelope
                .data
                .get("identity")
                .and_then(|i| i.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or("Agent")
                .to_owned(),
            status: outcome_label(&envelope.meta.state).to_owned(),
            summary: envelope
                .data
                .get("identity")
                .and_then(|i| i.get("name"))
                .and_then(|v| v.as_str())
                .unwrap_or("Agent")
                .to_owned(),
            payload_json: record.payload_json.clone(),
            started_at_ms: envelope.meta.started_at.or(occurred_at_ms),
            finished_at_ms: envelope.meta.finished_at,
        },
        HistoryEntityKind::FileChange => WorkGroupMember::FileChange {
            id: entity_id,
            seq: record.seq,
            summary: envelope
                .data
                .get("path")
                .and_then(|v| v.as_str())
                .unwrap_or("File change")
                .to_owned(),
            payload_json: record.payload_json.clone(),
            bodies: manifest_bodies(&envelope, &record.event_id),
            occurred_at_ms,
        },
        HistoryEntityKind::Skill => WorkGroupMember::Skill {
            id: entity_id,
            seq: record.seq,
            name: envelope
                .data
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("Skill")
                .to_owned(),
            summary: envelope
                .data
                .get("name")
                .and_then(|v| v.as_str())
                .unwrap_or("Skill")
                .to_owned(),
            payload_json: record.payload_json.clone(),
            occurred_at_ms,
        },
        _ => WorkGroupMember::Fallback {
            id: entity_id,
            seq: record.seq,
            event_id: record.event_id.clone(),
            event_kind: record.kind.as_str().to_owned(),
            reason: format!("unhandled work entity kind {:?}", envelope.meta.entity_kind),
            occurred_at_ms,
        },
    }
}
