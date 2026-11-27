//! Stateless decoders turning Schema 27 `HistoryEventRecord` rows into typed `TimelineItem`
//! and folded `WorkGroupMember` presentation models with single-row Fallback resilience.

use std::collections::BTreeMap;

use crate::history::{
    HistoryBodyRole, HistoryEntityKind, HistoryEventKind, HistoryEventRecord, decode_event_envelope,
};
use crate::{ChatSourceId, ThreadTextChannel};

use super::member_decoder::{
    decode_work_group_member, fallback_work_group_member, find_inline_text, find_primary_body_ref,
    manifest_bodies, merge_work_group_member, outcome_label,
};
use super::models::{TimelineItem, TimelineItemId, WorkGroupMember, WorkGroupStatus};

pub fn boundary_item_id(seq: u64) -> TimelineItemId {
    format!("msg:{seq}")
}

pub fn work_group_item_id(first_seq: u64) -> TimelineItemId {
    format!("work:{first_seq}")
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
            WorkGroupMember::Agent { status, .. } => {
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
        let member = decode_work_group_member(&record).unwrap_or_else(|| {
            fallback_work_group_member(&record, "invalid or unhandled work member".into())
        });
        let key = member.id().to_owned();
        if let Some(existing) = folded.get_mut(&key) {
            merge_work_group_member(existing, member);
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
