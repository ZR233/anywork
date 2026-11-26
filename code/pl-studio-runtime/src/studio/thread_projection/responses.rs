//! Saved model output projection, without rerunning an adapter or advancing a session.
use super::{ProjectionError, content::text_content};
use crate::{ExecutionItem, ExecutionShape};
use crate::{ThreadContentLifecycle, ThreadTextChannel, ThreadTextItem, ThreadThinkingItem};
use pl_core::{
    context::ContextContent,
    model::{
        AggregateChannel, ModelStepOutput, ObservedItemKind, ObservedPartIdentity, ObservedPartKind,
    },
    thread::{AttemptOutcome, ThreadSnapshot},
};
use pl_model::completion::{
    CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
    CompletionPresentationPartKind,
};
use std::collections::{BTreeMap, BTreeSet};

/// Identity and ordering shared by one model attempt projection.
#[derive(Clone, Copy)]
pub(super) struct AttemptStamp<'a> {
    pub(super) thread_id: &'a str,
    pub(super) attempt: &'a pl_core::thread::journal::AttemptUpdate,
    pub(super) ordinal: u64,
    pub(super) created_at: i64,
    pub(super) revision: u64,
    pub(super) updated_at: i64,
}

/// Terminal streaming identities an attempt actually started.
///
/// Aggregate preview identities are probed even for itemized responses so an earlier preview can
/// be closed without emitting duplicate aggregate content. Provider part identities use the same
/// function as terminal projection and the caller's durable item/reservation fact.
pub(in crate::studio) fn started_channels(
    attempt: &pl_core::thread::journal::AttemptUpdate,
    known_ids: impl IntoIterator<Item = String>,
    started: impl Fn(&str) -> bool,
) -> BTreeSet<String> {
    let mut channels = BTreeSet::new();
    for kind in ["reasoning", "text"] {
        let id = super::order::response_id(&attempt.attempt_id, kind);
        if started(&id) {
            channels.insert(id);
        }
    }
    let output = match &attempt.outcome {
        AttemptOutcome::Committed(output)
        | AttemptOutcome::Rejected { output, .. }
        | AttemptOutcome::Cancelled { result: Ok(output) } => Some(output),
        _ => None,
    };
    // A malformed receipt is projected as Raw by project_attempt, not as presentation content.
    if let Some(Ok(Some(receipt))) = output.map(pl_model::runtime::model_response_receipt) {
        for id in super::order::presentation_ids(
            &attempt.attempt_id,
            receipt.response.observation.generation,
            &receipt.response.presentation_items,
        ) {
            if started(&id) {
                channels.insert(id);
            }
        }
    }
    let prefix = super::order::presentation_prefix(&attempt.attempt_id);
    let observation_prefix = super::order::observation_prefix(&attempt.attempt_id);
    for id in known_ids {
        if (id.starts_with(&prefix) || id.starts_with(&observation_prefix)) && started(&id) {
            channels.insert(id);
        }
    }
    channels
}

/// Whether a commit's own receipt cannot carry the provider presentation parts it started.
///
/// Only a bounded reception qualifies: a failed, cancelled or interrupted stream stopped before the
/// provider's authoritative item, so the prefix the window already received stays on the identity it
/// was shown on. A normally received response ([`AttemptOutcome::Committed`]) — and a response the
/// workflow rejected after receiving it ([`AttemptOutcome::Rejected`]) — always carries its complete
/// provider parts, so its committed content is never taken from a subscriber's view of a preview.
pub(in crate::studio) fn keeps_bounded_preview(outcome: &AttemptOutcome) -> bool {
    !matches!(
        outcome,
        AttemptOutcome::Committed(_) | AttemptOutcome::Rejected { .. }
    )
}

/// Closes preview parts absent from a terminal receipt (notably a bounded failure preview).
/// The previous item is required to preserve its channel and partially streamed content.
pub(super) fn finalize_missing_presentation(
    thread_id: &str,
    attempt: &pl_core::thread::journal::AttemptUpdate,
    revision: u64,
    updated_at: i64,
    finalize: &BTreeSet<String>,
    existing: &BTreeMap<String, ExecutionItem>,
    items: &mut Vec<ExecutionItem>,
) -> Result<(), ProjectionError> {
    let lifecycle = match &attempt.outcome {
        AttemptOutcome::Running => return Ok(()),
        AttemptOutcome::Committed(_) => ThreadContentLifecycle::completed(updated_at),
        AttemptOutcome::Rejected { reason, .. } => {
            ThreadContentLifecycle::failed(updated_at, reason.to_string())
        }
        AttemptOutcome::Failed(error) => {
            ThreadContentLifecycle::failed(updated_at, error.to_string())
        }
        AttemptOutcome::Cancelled { result: Ok(_) } => ThreadContentLifecycle::cancelled(
            updated_at,
            "The model returned after cancellation; this output was not committed to context."
                .into(),
        ),
        AttemptOutcome::Cancelled { result: Err(error) } => {
            ThreadContentLifecycle::cancelled(updated_at, error.to_string())
        }
        AttemptOutcome::Interrupted => ThreadContentLifecycle::cancelled(
            updated_at,
            "Execution interrupted before recovery".into(),
        ),
    };
    let prefix = super::order::presentation_prefix(&attempt.attempt_id);
    let emitted = items
        .iter()
        .map(|item| item.id.clone())
        .collect::<BTreeSet<_>>();
    for id in finalize.iter().filter(|id| id.starts_with(&prefix)) {
        if emitted.contains(id) {
            continue;
        }
        let previous = existing.get(id).ok_or_else(|| {
            ProjectionError::History(format!("missing previously started provider item {id}"))
        })?;
        if previous.is_terminal() {
            continue;
        }
        let state = match previous.state() {
            ExecutionShape::Text(text) => ExecutionShape::Text(ThreadTextItem::new(
                text.channel(),
                text.text().to_owned(),
                text.attachments().to_vec(),
                lifecycle.clone(),
            )),
            ExecutionShape::Thinking(thinking) => {
                ExecutionShape::Thinking(ThreadThinkingItem::new(
                    thinking.summary().to_vec(),
                    thinking.content().to_vec(),
                    lifecycle.clone(),
                ))
            }
            _ => {
                return Err(ProjectionError::UnsupportedOutput(
                    "started provider presentation has no content state".into(),
                ));
            }
        };
        items.push(ExecutionItem::new(
            id.clone(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal: previous.ordinal,
                revision,
                created_at: previous.created_at,
                updated_at,
            },
            state,
        ));
    }
    Ok(())
}

pub(super) fn project_attempt(
    snapshot: &ThreadSnapshot,
    stamp: AttemptStamp<'_>,
    finalize: &BTreeSet<String>,
    soft_preempted: bool,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let AttemptStamp {
        thread_id,
        attempt,
        created_at,
        revision,
        updated_at,
        ..
    } = stamp;
    let mut items = vec![inference_item(
        thread_id, attempt, created_at, updated_at, revision,
    )?];
    if let Some(opaque) = project_opaque_attempt(stamp)? {
        items.push(opaque);
        return Ok(items);
    }
    let Some((mut response, mut lifecycle, channel)) = select_response(snapshot, stamp)? else {
        return Ok(items);
    };
    if soft_preempted {
        response.cancelled_failure = None;
        lifecycle = ThreadContentLifecycle::completed(stamp.updated_at);
        for item in &mut response.presentation_items {
            if let CompletionPresentationItemKind::Text(_) = item.kind {
                item.kind = CompletionPresentationItemKind::Text(
                    pl_core::model::ModelTextChannel::Commentary,
                );
            }
        }
        if response.text.is_empty() && response.presentation_items.is_empty() {
            let partial_id = format!("{}:partial", attempt.attempt_id);
            if let Some(record) = snapshot.context.records.iter().find(|r| {
                r.id == partial_id && matches!(r.source, pl_core::context::ContextSource::Assistant)
            }) {
                for item in &record.content {
                    if let ContextContent::Text { text } = item {
                        response.text.push_str(text);
                    }
                }
            }
        }
    }
    items.extend(project_recovery(
        stamp,
        &response.observation,
        response.cancelled_failure.take(),
    )?);
    project_response_channels(stamp, finalize, response, lifecycle, channel, &mut items)?;
    Ok(items)
}

fn project_opaque_attempt(
    stamp: AttemptStamp<'_>,
) -> Result<Option<ExecutionItem>, ProjectionError> {
    let AttemptStamp {
        thread_id,
        attempt,
        ordinal,
        created_at,
        revision,
        updated_at,
    } = stamp;
    let output = match &attempt.outcome {
        AttemptOutcome::Committed(output)
        | AttemptOutcome::Rejected { output, .. }
        | AttemptOutcome::Cancelled { result: Ok(output) } => Some(output),
        AttemptOutcome::Running
        | AttemptOutcome::Interrupted
        | AttemptOutcome::Failed(_)
        | AttemptOutcome::Cancelled { result: Err(_) } => None,
    };
    let decoding_error = attempt
        .request_metadata
        .as_ref()
        .and_then(|payload| pl_model::runtime::model_request_receipt(payload).err())
        .map(|error| error.to_string())
        .or_else(|| {
            output
                .and_then(|output| response_content(output).err())
                .map(|error| error.to_string())
        });
    Ok(if let Some(notice) = decoding_error {
        let mut payloads = attempt
            .request_metadata
            .iter()
            .map(super::raw_payload)
            .collect::<Vec<_>>();
        if let Some(output) = output {
            for content in &output.content {
                payloads.push(match content {
                    ContextContent::Text { text } => crate::ThreadRawPayload {
                        format: "text/plain".into(),
                        version: 1,
                        content: text.to_string(),
                    },
                    ContextContent::Opaque { payload } => super::raw_payload(payload),
                    ContextContent::Resource { reference } => crate::ThreadRawPayload {
                        format: "pl.resource-reference".into(),
                        version: 1,
                        content: serde_json::to_string(reference)?,
                    },
                });
            }
        }
        Some(ExecutionItem::new(
            super::order::response_id(&attempt.attempt_id, "text"),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal,
                revision,
                created_at,
                updated_at,
            },
            ExecutionShape::Raw(crate::ThreadRawItem::stored(payloads, notice, updated_at)),
        ))
    } else {
        None
    })
}

fn select_response(
    snapshot: &ThreadSnapshot,
    stamp: AttemptStamp<'_>,
) -> Result<Option<(ResponseContent, ThreadContentLifecycle, ThreadTextChannel)>, ProjectionError> {
    let AttemptStamp {
        attempt,
        updated_at,
        ..
    } = stamp;
    Ok(Some(match &attempt.outcome {
        AttemptOutcome::Committed(output) => (
            response_content(output)?,
            ThreadContentLifecycle::completed(updated_at),
            if output.tool_calls.is_empty() {
                ThreadTextChannel::Final
            } else {
                ThreadTextChannel::Commentary
            },
        ),
        AttemptOutcome::Rejected { output, reason } => (
            response_content(output)?,
            ThreadContentLifecycle::failed(updated_at, reason.to_string()),
            ThreadTextChannel::Commentary,
        ),
        AttemptOutcome::Cancelled { result: Ok(output) } => (
            response_content(output)?,
            ThreadContentLifecycle::cancelled(
                updated_at,
                "The model returned after cancellation; this output was not committed to context."
                    .into(),
            ),
            ThreadTextChannel::Commentary,
        ),
        AttemptOutcome::Running => {
            let Some(preview) = snapshot
                .model_progress
                .as_ref()
                .filter(|preview| preview.attempt_id == attempt.attempt_id)
            else {
                return Ok(None);
            };
            (
                progress_content(&preview.progress)?,
                ThreadContentLifecycle::streaming(),
                ThreadTextChannel::Commentary,
            )
        }
        // 已经开始的 overlay 由同一身份的终态收束；重启中断没有可恢复的正文。
        AttemptOutcome::Interrupted => (
            ResponseContent::default(),
            ThreadContentLifecycle::cancelled(
                updated_at,
                "Execution interrupted before recovery".into(),
            ),
            ThreadTextChannel::Commentary,
        ),
        AttemptOutcome::Failed(error) => (
            failure_content(error, false)?,
            ThreadContentLifecycle::failed(updated_at, error.to_string()),
            ThreadTextChannel::Commentary,
        ),
        AttemptOutcome::Cancelled { result: Err(error) } => (
            failure_content(error, true)?,
            ThreadContentLifecycle::cancelled(updated_at, error.to_string()),
            ThreadTextChannel::Commentary,
        ),
    }))
}

fn project_response_channels(
    stamp: AttemptStamp<'_>,
    finalize: &BTreeSet<String>,
    response: ResponseContent,
    lifecycle: ThreadContentLifecycle,
    channel: ThreadTextChannel,
    items: &mut Vec<ExecutionItem>,
) -> Result<(), ProjectionError> {
    let AttemptStamp {
        thread_id,
        attempt,
        ordinal,
        created_at,
        revision,
        updated_at,
    } = stamp;
    let text_id =
        super::order::observation_id(&attempt.attempt_id, response.observation.generation, "text");
    let reasoning_id = super::order::observation_id(
        &attempt.attempt_id,
        response.observation.generation,
        "reasoning",
    );
    // 上述终态即使正文为空也要发出，但只对**实际开始过 streaming 的同一 identity channel**
    // 收束；`finalize.contains` 是一次 durable 事实查询的结果，因此 writer 与 live 对同一
    // identity 落相同终态，而从未开始的 channel 不会凭空出现空条目。
    let terminates_live_channels = !matches!(attempt.outcome, AttemptOutcome::Running);
    if !response.presentation_items.is_empty() {
        items.extend(project_presentation_items(
            PresentationStamp {
                thread_id,
                turn_id: &attempt.turn_id,
                attempt_id: &attempt.attempt_id,
                ordinal,
                created_at,
                revision,
                updated_at,
                generation: response.observation.generation,
                lifecycle: &lifecycle,
            },
            &response.presentation_items,
        )?);
        // The legacy preview has only two aggregate identities. When one was already started,
        // finalize it without repeating the provider's aggregate text or reasoning.
        if terminates_live_channels && finalize.contains(&reasoning_id) {
            items.push(ExecutionItem::new(
                reasoning_id.clone(),
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(thread_id.into()),
                    turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                    ordinal,
                    revision,
                    created_at,
                    updated_at,
                },
                ExecutionShape::Thinking(ThreadThinkingItem::new(
                    Vec::new(),
                    Vec::new(),
                    lifecycle.clone(),
                )),
            ));
        }
        if terminates_live_channels && finalize.contains(&text_id) {
            items.push(ExecutionItem::new(
                text_id.clone(),
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(thread_id.into()),
                    turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                    ordinal,
                    revision,
                    created_at,
                    updated_at,
                },
                ExecutionShape::Text(ThreadTextItem::new(
                    ThreadTextChannel::Commentary,
                    String::new(),
                    Vec::new(),
                    lifecycle,
                )),
            ));
        }
        return Ok(());
    }
    // The provider itemized this attempt, so its canonical content is the provider parts — never a
    // second aggregate identity for the same text, and never an empty `reasoning` row that no provider
    // part produced. A bounded reception closes the started identity with the prefix the window
    // already received; a normally received response always carries those parts in its own receipt,
    // so an empty part set here means the authoritative output was lost. Failing closed keeps a
    // partial preview body from being committed as that response's content.
    let mut current_prefix = super::order::presentation_prefix(&attempt.attempt_id);
    if response.observation.generation != 0 {
        current_prefix.push_str(&format!("generation:{}:", response.observation.generation));
    }
    if finalize.iter().any(|id| id.starts_with(&current_prefix)) {
        if keeps_bounded_preview(&attempt.outcome) {
            return Ok(());
        }
        return Err(ProjectionError::UnsupportedOutput(
            "terminal receipt lost its committed provider presentation identity".into(),
        ));
    }
    if let Some(reasoning) = response.reasoning.filter(|text| !text.is_empty()) {
        items.push(ExecutionItem::new(
            reasoning_id.clone(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal,
                revision,
                created_at,
                updated_at,
            },
            ExecutionShape::Thinking(ThreadThinkingItem::new(
                Vec::new(),
                vec![reasoning],
                lifecycle.clone(),
            )),
        ));
    } else if terminates_live_channels && finalize.contains(&reasoning_id) {
        items.push(ExecutionItem::new(
            reasoning_id.clone(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal,
                revision,
                created_at,
                updated_at,
            },
            ExecutionShape::Thinking(ThreadThinkingItem::new(
                Vec::new(),
                Vec::new(),
                lifecycle.clone(),
            )),
        ));
    }
    if !response.text.is_empty() {
        items.push(ExecutionItem::new(
            text_id.clone(),
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal,
                revision,
                created_at,
                updated_at,
            },
            ExecutionShape::Text(ThreadTextItem::new(
                channel,
                response.text,
                Vec::new(),
                lifecycle,
            )),
        ));
    } else if terminates_live_channels && finalize.contains(&text_id) {
        items.push(ExecutionItem::new(
            text_id,
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal,
                revision,
                created_at,
                updated_at,
            },
            ExecutionShape::Text(ThreadTextItem::new(
                channel,
                String::new(),
                Vec::new(),
                lifecycle,
            )),
        ));
    }
    Ok(())
}

struct PresentationStamp<'a> {
    thread_id: &'a str,
    turn_id: &'a str,
    attempt_id: &'a str,
    ordinal: u64,
    created_at: i64,
    revision: u64,
    updated_at: i64,
    generation: u32,
    lifecycle: &'a ThreadContentLifecycle,
}

/// The reliable member port supplies its own terminal fact; it is not an attempt outcome.
pub(super) fn project_model_member(
    thread_id: &str,
    member: &pl_core::model::ModelCompletedMember,
    revision: u64,
    committed_at: i64,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let receipt = pl_model::runtime::model_member_receipt(member)
        .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))?;
    let lifecycle = match receipt.state {
        pl_model::runtime::ModelMemberState::Completed => {
            ThreadContentLifecycle::completed(committed_at)
        }
        pl_model::runtime::ModelMemberState::Interrupted => ThreadContentLifecycle::cancelled(
            committed_at,
            "Provider marked this output member as interrupted".into(),
        ),
    };
    project_presentation_items(
        PresentationStamp {
            thread_id,
            turn_id: &member.turn_id,
            attempt_id: &member.attempt_id,
            ordinal: 0,
            created_at: committed_at,
            revision,
            updated_at: committed_at,
            generation: member.generation,
            lifecycle: &lifecycle,
        },
        std::slice::from_ref(&receipt.item),
    )
}

fn project_presentation_items(
    stamp: PresentationStamp<'_>,
    presentation_items: &[CompletionPresentationItem],
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let PresentationStamp {
        thread_id,
        turn_id,
        attempt_id,
        ordinal,
        created_at,
        revision,
        updated_at,
        generation,
        lifecycle,
    } = stamp;
    let mut projected = Vec::new();
    let mut ids = BTreeSet::new();
    for item in presentation_items {
        for part in item
            .parts
            .iter()
            .map(Some)
            .chain(item.parts.is_empty().then_some(None))
        {
            let id = super::order::presentation_id(
                attempt_id,
                generation,
                &item.provider_item_id,
                part.map(super::order::presentation_part),
            );
            if !ids.insert(id.clone()) {
                return Err(ProjectionError::UnsupportedOutput(
                    "duplicate provider presentation identity".into(),
                ));
            }
            let state = match (item.kind, part) {
                (CompletionPresentationItemKind::Text(channel), None)
                | (
                    CompletionPresentationItemKind::Text(channel),
                    Some(CompletionPresentationPart {
                        kind: CompletionPresentationPartKind::OutputText,
                        ..
                    }),
                ) => {
                    let channel = super::observation_parts::text_channel(channel);
                    ExecutionShape::Text(ThreadTextItem::new(
                        channel,
                        part.map_or_else(String::new, |part| part.text.clone()),
                        Vec::new(),
                        lifecycle.clone(),
                    ))
                }
                (CompletionPresentationItemKind::Reasoning, None)
                | (
                    CompletionPresentationItemKind::Reasoning,
                    Some(CompletionPresentationPart {
                        kind: CompletionPresentationPartKind::ReasoningText,
                        ..
                    }),
                ) => ExecutionShape::Thinking(ThreadThinkingItem::new(
                    Vec::new(),
                    part.map_or_else(Vec::new, |part| vec![part.text.clone()]),
                    lifecycle.clone(),
                )),
                (
                    CompletionPresentationItemKind::Reasoning,
                    Some(CompletionPresentationPart {
                        kind: CompletionPresentationPartKind::SummaryText,
                        text,
                        ..
                    }),
                ) => ExecutionShape::Thinking(ThreadThinkingItem::new(
                    vec![text.clone()],
                    Vec::new(),
                    lifecycle.clone(),
                )),
                _ => {
                    return Err(ProjectionError::UnsupportedOutput(
                        "provider presentation part does not match its item".into(),
                    ));
                }
            };
            projected.push(ExecutionItem::new(
                id,
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(thread_id.into()),
                    turn_id: std::borrow::Cow::Owned(turn_id.into()),
                    ordinal,
                    revision,
                    created_at,
                    updated_at,
                },
                state,
            ));
        }
    }
    Ok(projected)
}

/// The same provider-neutral facts drive live commentary and durable final projection.
pub(super) fn recovery_notices(
    attempt_id: &str,
    observation: &pl_core::model::ModelObservation,
) -> Vec<(String, String, crate::ModelRecoveryNotice)> {
    use pl_core::model::ModelRecoveryPhase;
    let Some(status) = observation.recovery else {
        return Vec::new();
    };
    let notice = |decision: Option<&pl_model::runtime::ModelRecoveryDecision>, retry, phase| {
        crate::ModelRecoveryNotice {
            failure_kind: decision.map(|decision| decision.failure_kind),
            reason: decision.map(|decision| decision.recovery),
            retry_count: retry,
            max_retries: decision.map_or(status.max_retries, |decision| decision.max_retries),
            effective_wait_millis: decision.map(|decision| decision.effective_wait_millis),
            phase,
            failure: decision
                .and_then(|decision| decision.provider_failure.as_ref())
                .map(super::turns::provider_failure),
        }
    };
    let mut last_decision = None;
    let mut notices = Vec::new();
    for (index, failed) in observation.failed.iter().enumerate() {
        let decision = failed
            .recovery
            .as_ref()
            .and_then(|payload| pl_model::runtime::model_recovery_decision(payload).ok());
        let retry = decision.as_ref().map_or_else(
            || u32::try_from(index + 1).unwrap_or(u32::MAX),
            |decision| decision.retry,
        );
        let latest = retry == status.retry && index + 1 == observation.failed.len();
        let phase = if latest {
            status.phase
        } else {
            ModelRecoveryPhase::Retrying
        };
        notices.push((
            super::order::response_id(attempt_id, &format!("recovery:retry:{retry}")),
            failed.message.to_string(),
            notice(decision.as_ref(), retry, phase),
        ));
        if latest {
            last_decision = decision;
        }
    }
    let message = match status.phase {
        ModelRecoveryPhase::Repairing
        | ModelRecoveryPhase::Waiting
        | ModelRecoveryPhase::Retrying => None,
        ModelRecoveryPhase::Recovered => Some("模型请求已恢复，继续执行。".to_owned()),
        ModelRecoveryPhase::Exhausted => Some(format!(
            "模型请求已用尽 {} 次重试，本轮已停止。",
            status.max_retries
        )),
        ModelRecoveryPhase::Failed => Some("模型请求恢复未完成，本轮已停止。".to_owned()),
        ModelRecoveryPhase::Cancelled => Some("模型请求恢复已取消，本轮已停止。".to_owned()),
    };
    if let Some(message) = message {
        notices.push((
            super::order::response_id(attempt_id, "recovery:result"),
            message,
            notice(last_decision.as_ref(), status.retry, status.phase),
        ));
    }
    notices
}

fn project_recovery(
    stamp: AttemptStamp<'_>,
    observation: &pl_core::model::ModelObservation,
    cancelled_failure: Option<crate::ModelRecoveryNotice>,
) -> Result<Vec<ExecutionItem>, ProjectionError> {
    let AttemptStamp {
        thread_id,
        attempt,
        ordinal,
        created_at,
        revision,
        updated_at,
    } = stamp;
    let mut items = Vec::new();
    for failed in &observation.failed {
        let lifecycle = ThreadContentLifecycle::failed(updated_at, failed.message.to_string());
        for part in &failed.parts {
            if part.is_empty() {
                continue;
            }
            let (id, state) = super::observation_parts::failed_preview(
                &attempt.attempt_id,
                failed.generation,
                part,
                &lifecycle,
            )?;
            items.push(ExecutionItem::new(
                id,
                crate::ItemStamp {
                    thread_id: std::borrow::Cow::Owned(thread_id.into()),
                    turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                    ordinal,
                    revision,
                    created_at,
                    updated_at,
                },
                state,
            ));
        }
    }
    let mut notices = recovery_notices(&attempt.attempt_id, observation);
    if let Some(notice) = cancelled_failure {
        let id = super::order::response_id(&attempt.attempt_id, "recovery:result");
        // Retry decisions remain attached to the original retry rows. The result row always
        // carries the terminal receipt, including cancellation during a later save.
        notices.retain(|(existing, _, _)| existing != &id);
        notices.push((id, "模型请求恢复已取消，本轮已停止。".to_owned(), notice));
    }
    for (id, message, notice) in notices {
        items.push(ExecutionItem::new(
            id,
            crate::ItemStamp {
                thread_id: std::borrow::Cow::Owned(thread_id.into()),
                turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
                ordinal,
                revision,
                created_at,
                updated_at,
            },
            ExecutionShape::Text(
                ThreadTextItem::new(
                    ThreadTextChannel::Commentary,
                    message,
                    Vec::new(),
                    ThreadContentLifecycle::completed(updated_at),
                )
                .with_model_recovery(Some(notice)),
            ),
        ));
    }
    Ok(items)
}

fn inference_item(
    thread_id: &str,
    attempt: &pl_core::thread::journal::AttemptUpdate,
    created_at: i64,
    updated_at: i64,
    revision: u64,
) -> Result<ExecutionItem, ProjectionError> {
    use crate::{ThreadInferenceItem, ThreadInferenceState as State};
    let model = attempt
        .request_metadata
        .as_ref()
        .and_then(|payload| pl_model::runtime::model_request_receipt(payload).ok())
        .map_or_else(String::new, |receipt| receipt.binding.model_id);
    let state = match &attempt.outcome {
        AttemptOutcome::Running => State::Running(crate::RunningThreadInference),
        AttemptOutcome::Committed(output) => {
            let usage = &output.usage;
            State::Completed(crate::CompletedThreadInference::new(
                updated_at,
                crate::TokenUsageSnapshot {
                    prompt_tokens: usage.input_tokens.unwrap_or(0),
                    completion_tokens: usage.output_tokens.unwrap_or(0),
                    cached_prompt_tokens: usage.cache_read_tokens.unwrap_or(0),
                    cache_write_tokens: usage.cache_write_tokens.unwrap_or(0),
                    cache_miss_tokens: usage
                        .input_tokens
                        .zip(usage.cache_read_tokens)
                        .map_or(0, |(input, cached)| input.saturating_sub(cached)),
                    reasoning_tokens: usage.reasoning_tokens.unwrap_or(0),
                    inference_count: 1,
                    total_tokens: usage
                        .input_tokens
                        .zip(usage.output_tokens)
                        .and_then(|(a, b)| a.checked_add(b))
                        .unwrap_or(0),
                },
            ))
        }
        AttemptOutcome::Failed(error) => State::Failed(crate::FailedThreadInference::new(
            updated_at,
            error.to_string(),
        )),
        AttemptOutcome::Rejected { reason, .. } => State::Failed(
            crate::FailedThreadInference::new(updated_at, reason.to_string()),
        ),
        AttemptOutcome::Cancelled { .. } => State::Cancelled(crate::CancelledThreadInference::new(
            updated_at,
            "Model execution cancelled".into(),
        )),
        AttemptOutcome::Interrupted => State::Cancelled(crate::CancelledThreadInference::new(
            updated_at,
            "Execution interrupted before recovery".into(),
        )),
    };
    Ok(ExecutionItem::new(
        super::order::response_id(&attempt.attempt_id, "inference"),
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Owned(thread_id.into()),
            turn_id: std::borrow::Cow::Owned(attempt.turn_id.clone()),
            ordinal: 0,
            revision,
            created_at,
            updated_at,
        },
        ExecutionShape::Inference(ThreadInferenceItem::new(
            attempt.attempt_id.clone(),
            model,
            state,
        )),
    ))
}

#[derive(Default)]
struct ResponseContent {
    text: String,
    reasoning: Option<String>,
    presentation_items: Vec<CompletionPresentationItem>,
    observation: pl_core::model::ModelObservation,
    cancelled_failure: Option<crate::ModelRecoveryNotice>,
}

fn failure_content(
    error: &pl_core::model::ModelError,
    cancelled: bool,
) -> Result<ResponseContent, ProjectionError> {
    let receipt = error
        .details
        .as_ref()
        .is_some_and(|details| details.format() == "pl.model.failure")
        .then(|| pl_model::runtime::model_failure_receipt(error))
        .transpose()?
        .flatten();
    let mut content = match receipt
        .as_ref()
        .and_then(|receipt| receipt.partial_progress.as_ref())
    {
        Some(progress) => progress_content(progress)?,
        None => ResponseContent::default(),
    };
    if let Some(receipt) = receipt {
        if cancelled
            && let (Some(retry_count), Some(max_retries)) =
                (receipt.retry_count, receipt.max_retries)
        {
            let failure = receipt.provider_failure.as_ref().map(|provider| {
                let mut failure = super::turns::provider_failure(provider);
                failure.recovery = Some(crate::ModelRecoveryInfo {
                    retry_count: Some(retry_count),
                    max_retries: Some(max_retries),
                    effective_wait_millis: None,
                    reason: None,
                    stop_reason: receipt.recovery_stop,
                    error: receipt.recovery_error,
                });
                failure
            });
            content.cancelled_failure = Some(crate::ModelRecoveryNotice {
                failure_kind: receipt
                    .provider_failure
                    .as_ref()
                    .map(|provider| provider.kind),
                reason: None,
                retry_count,
                max_retries,
                effective_wait_millis: None,
                phase: pl_core::model::ModelRecoveryPhase::Cancelled,
                failure,
            });
        }
        if !receipt.presentation_items.is_empty() {
            content.presentation_items = receipt.presentation_items;
        }
    }
    Ok(content)
}

/// Projects the live observation of one attempt, without re-decoding a producer payload.
///
/// An aggregate observation is the preview of a whole channel before the adapter itemizes the
/// response; provider observations regroup by their stable item identity. This is a read of the
/// observation snapshot, so it materializes text only where this projection needs it.
fn progress_content(
    progress: &pl_core::model::ModelProgress,
) -> Result<ResponseContent, ProjectionError> {
    let mut text = String::new();
    let mut reasoning = String::new();
    let mut items: Vec<CompletionPresentationItem> = Vec::new();
    for part in progress.parts() {
        let identity = match part.identity() {
            ObservedPartIdentity::Aggregate { channel } => {
                match channel {
                    AggregateChannel::Text => text.push_str(&part.text()),
                    AggregateChannel::Reasoning => reasoning.push_str(&part.text()),
                }
                continue;
            }
            ObservedPartIdentity::Provider(identity) => identity,
        };
        let kind = match identity.item_kind {
            ObservedItemKind::Text(channel) => CompletionPresentationItemKind::Text(channel),
            ObservedItemKind::Reasoning => CompletionPresentationItemKind::Reasoning,
        };
        let part_kind = match identity.part {
            ObservedPartKind::OutputText => CompletionPresentationPartKind::OutputText,
            ObservedPartKind::ReasoningText => CompletionPresentationPartKind::ReasoningText,
            ObservedPartKind::SummaryText => CompletionPresentationPartKind::SummaryText,
        };
        if super::observation_parts::classify(part.identity()).is_none() {
            return Err(ProjectionError::UnsupportedOutput(
                "provider presentation part does not match its item".into(),
            ));
        }
        let observed_part = CompletionPresentationPart {
            content_index: identity.content_index,
            provider_part_id: None,
            kind: part_kind,
            text: part.text(),
        };
        let item_id: &str = identity.item_id.as_ref();
        // The output index can arrive after streaming starts, so only the provider item id groups
        // parts; a late index completes the item instead of starting a second one.
        match items
            .iter_mut()
            .find(|item| item.provider_item_id == item_id)
        {
            Some(item) => {
                item.output_index = item.output_index.or(identity.output_index);
                item.parts.push(observed_part);
            }
            None => items.push(CompletionPresentationItem {
                provider_item_id: item_id.to_owned(),
                output_index: identity.output_index,
                kind,
                parts: vec![observed_part],
            }),
        }
    }
    Ok(ResponseContent {
        text,
        reasoning: (!reasoning.is_empty()).then_some(reasoning),
        presentation_items: items,
        observation: progress.observation().clone(),
        cancelled_failure: None,
    })
}

fn response_content(output: &ModelStepOutput) -> Result<ResponseContent, ProjectionError> {
    let receipt = pl_model::runtime::model_response_receipt(output)?;
    for content in &output.content {
        match content {
            ContextContent::Text { .. } => {}
            ContextContent::Opaque { payload }
                if receipt.is_some() && payload.format() == "pl.model.assistant" => {}
            ContextContent::Opaque { payload } => {
                return Err(ProjectionError::UnsupportedOutput(format!(
                    "{} version {}",
                    payload.format(),
                    payload.version()
                )));
            }
            ContextContent::Resource { reference } => {
                return Err(ProjectionError::UnsupportedOutput(format!(
                    "resource {}",
                    reference.id()
                )));
            }
        }
    }
    let (reasoning, presentation_items, observation) = receipt.map_or_else(
        || (None, Vec::new(), Default::default()),
        |receipt| {
            (
                receipt.response.reasoning_content,
                receipt.response.presentation_items,
                receipt.response.observation,
            )
        },
    );
    Ok(ResponseContent {
        text: text_content(&output.content),
        reasoning,
        presentation_items,
        observation,
        cancelled_failure: None,
    })
}

#[cfg(test)]
mod recovery_tests {
    use super::*;
    use pl_core::context::OpaquePayload;
    use pl_core::model::{ModelProgressSender, ModelRecoveryPhase};
    use pl_model::runtime::ModelRecoveryDecision;
    use pl_protocol::{
        ProviderFailure, ProviderFailureKind, ProviderFailureStage, ProviderRecovery,
        RetryDisposition,
    };

    #[tokio::test]
    async fn cancellation_while_saving_first_failure_keeps_the_original_history_diagnostic()
    -> anyhow::Result<()> {
        cancellation_while_saving_failure_keeps_the_final_history_diagnostic(0).await
    }

    #[tokio::test]
    async fn cancellation_while_saving_second_failure_keeps_the_latest_history_diagnostic()
    -> anyhow::Result<()> {
        cancellation_while_saving_failure_keeps_the_final_history_diagnostic(1).await
    }

    async fn cancellation_while_saving_failure_keeps_the_final_history_diagnostic(
        generation: u32,
    ) -> anyhow::Result<()> {
        use crate::history::{HistoryEvent, HistoryEventKind, HistoryTimelineRole};
        use crate::studio::runtime::chat_item::{atom, build_event_from_draft, completion_draft};
        use pl_core::model::{CancellationToken, Model};
        use pl_core::thread::{
            HistoryExport, StepInput, ThreadEffectBatch, ThreadError, ThreadHandle, UsageSummary,
            cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
            history_sink::{HistorySink, HistorySinkHandle},
            journal::AttemptUpdate,
        };
        use std::sync::{
            Arc, Mutex,
            atomic::{AtomicU64, Ordering},
        };
        use std::time::Duration;
        use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
        use tokio::sync::Notify;

        #[derive(Debug, Default)]
        struct Gate {
            generation: u32,
            settlement: AtomicU64,
            entered: Notify,
            release: Notify,
            cancelled: Mutex<Option<AttemptUpdate>>,
        }
        #[derive(Debug)]
        struct Sink(Arc<Gate>);
        impl HistorySink for Sink {
            fn fold_usage(&self, _: &mut UsageSummary, _: &ThreadEffectBatch) {}
            fn reserve_observed_item(
                &self,
                _: &str,
                _: &str,
                _: &str,
            ) -> Result<(), ColdStoreError> {
                Ok(())
            }
            fn reserve_operation_output(
                &self,
                _: &str,
                _: &str,
                max: u64,
            ) -> Result<u64, ColdStoreError> {
                Ok(max)
            }
            fn charge_operation_output(
                &self,
                _: &str,
                _: &str,
                _: u64,
            ) -> Result<(), ColdStoreError> {
                Ok(())
            }
            fn release_operation_output(&self, _: &str, _: &str) {}
            fn pressure(&self, _: &str) -> StoragePressure {
                StoragePressure::default()
            }
            fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
                StorageIdleStatus {
                    pressure: self.pressure(thread_id),
                    reclaimable_thread_bytes: None,
                }
            }
            fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
                None
            }
            fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
                if write
                    .effect
                    .model_sub_attempt_settlements
                    .iter()
                    .any(|fact| fact.generation == self.0.generation)
                {
                    self.0
                        .settlement
                        .store(write.effect.sequence, Ordering::Release);
                }
                if let Some(attempt) = &write.effect.attempt
                    && matches!(attempt.outcome, AttemptOutcome::Cancelled { .. })
                {
                    *self.0.cancelled.lock().unwrap() = Some(attempt.clone());
                }
                Ok(())
            }
            async fn confirm_model_settlement(
                &self,
                _: &str,
                sequence: u64,
            ) -> Result<(), ColdStoreError> {
                if sequence == self.0.settlement.load(Ordering::Acquire) {
                    self.0.entered.notify_one();
                    self.0.release.notified().await;
                }
                Ok(())
            }
        }

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let base = format!("http://{}/v1", listener.local_addr()?);
        let server = tokio::spawn(async move {
            for served in 0..=generation {
                let (socket, _) = listener.accept().await.unwrap();
                let mut socket = BufReader::new(socket);
                let mut length = None;
                loop {
                    let mut line = String::new();
                    assert_ne!(socket.read_line(&mut line).await.unwrap(), 0);
                    if line == "\r\n" {
                        break;
                    }
                    if let Some((name, value)) = line.split_once(':')
                        && name.eq_ignore_ascii_case("content-length")
                    {
                        length = Some(value.trim().parse().unwrap());
                    }
                }
                socket
                    .read_exact(&mut vec![0; length.unwrap()])
                    .await
                    .unwrap();
                let (headers, body) = if served == 0 {
                    ("HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nx-request-id: first-429\r\nretry-after: 0", r#"{"error":{"code":"rate_limit_exceeded","type":"rate_limit_error","message":"initial rejection"}}"#.to_owned())
                } else {
                    (
                        "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nx-request-id: second-stream",
                        format!(
                            "data: {}\n\n",
                            serde_json::json!({
                                "type": "response.failed", "response": { "id": "failed", "status": "failed", "error": {
                                    "code": "server_error", "type": "generation_error", "message": "second failure"
                                }}
                            })
                        ),
                    )
                };
                let reply = format!(
                    "{headers}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                socket.get_mut().write_all(reply.as_bytes()).await.unwrap();
            }
            listener
        });
        let mut model = pl_model::model::ModelDefinition::compatible("model");
        model
            .extra
            .binding
            .set_transport(pl_model::model::ModelTransportProfile::responses_http());
        let runtime = pl_model::runtime::new_with_account_id(
            "fixture",
            pl_model_openai::endpoint::endpoint(Some(base)),
            model,
        )?;
        let thread = ThreadHandle::start(
            "cancellation".into(),
            pl_model::runtime::ThreadModel::new(runtime, None)
                .open_session()
                .await?,
        )?;
        let gate = Arc::new(Gate {
            generation,
            ..Default::default()
        });
        thread
            .attach_history(HistorySinkHandle::new(Sink(gate.clone())))
            .await?;
        let cancellation = CancellationToken::new();
        let running = tokio::spawn({
            let thread = thread.clone();
            let cancellation = cancellation.clone();
            async move {
                thread
                    .step(StepInput {
                        turn_id: "turn".into(),
                        attempt_id: "attempt".into(),
                        cancellation,
                        content: vec![ContextContent::Text {
                            text: "question".into(),
                        }],
                    })
                    .await
            }
        });
        tokio::time::timeout(Duration::from_secs(5), gate.entered.notified()).await?;
        cancellation.cancel();
        gate.release.notify_one();
        assert!(matches!(
            tokio::time::timeout(Duration::from_secs(5), running).await??,
            Err(ThreadError::Cancelled)
        ));
        let listener = server.await?;
        assert!(
            tokio::time::timeout(Duration::from_millis(50), listener.accept())
                .await
                .is_err()
        );
        let attempt = gate
            .cancelled
            .lock()
            .unwrap()
            .take()
            .expect("committed cancelled attempt");
        let AttemptOutcome::Cancelled { result: Err(error) } = &attempt.outcome else {
            unreachable!()
        };
        let receipt = pl_model::runtime::model_failure_receipt(error)?.unwrap();
        assert_eq!(receipt.retry_count, Some(generation));
        let (request_id, code, error_type, stage) = if generation == 0 {
            (
                "first-429",
                "rate_limit_exceeded",
                "rate_limit_error",
                "request",
            )
        } else {
            (
                "second-stream",
                "server_error",
                "generation_error",
                "stream",
            )
        };
        assert_eq!(
            receipt
                .provider_failure
                .as_ref()
                .unwrap()
                .context
                .request_id
                .as_deref(),
            Some(request_id)
        );
        let items = project_attempt(
            &thread.snapshot(),
            AttemptStamp {
                thread_id: "cancellation",
                attempt: &attempt,
                ordinal: 1,
                created_at: 1,
                revision: 1,
                updated_at: 2,
            },
            &BTreeSet::new(),
            false,
        )?;
        let item = items
            .iter()
            .find(|item| item.id == super::super::order::response_id("attempt", "recovery:result"))
            .expect("cancelled attempt has a typed failure in the history timeline");
        let draft = completion_draft(item, 1, "database", None)?;
        let mut event = HistoryEvent::new(
            "cancelled-recovery",
            HistoryEventKind::TextCompleted,
            HistoryTimelineRole::Boundary,
            2000,
        );
        build_event_from_draft(&mut event, &atom(item), &draft, "database", Vec::new())?;
        let payload: serde_json::Value = serde_json::from_str(&event.payload_json)?;
        let notice = &payload["meta"]["modelRecovery"];
        assert_eq!(notice["retryCount"], generation);
        assert_eq!(notice["phase"], "cancelled");
        assert!(notice["effectiveWaitMillis"].is_null());
        assert_eq!(notice["failure"]["requestId"], request_id);
        assert_eq!(notice["failure"]["code"], code);
        assert_eq!(notice["failure"]["errorType"], error_type);
        assert_eq!(notice["failure"]["stage"], stage);
        if generation == 1 {
            let retry = items
                .iter()
                .find(|item| {
                    item.id == super::super::order::response_id("attempt", "recovery:retry:1")
                })
                .unwrap();
            let failure = retry
                .text()
                .unwrap()
                .model_recovery()
                .unwrap()
                .failure
                .as_ref()
                .unwrap();
            assert_eq!(failure.request_id.as_deref(), Some("first-429"));
            assert_eq!(failure.code.as_deref(), Some("rate_limit_exceeded"));
        }
        thread.close().await?;
        Ok(())
    }

    fn reject_upload(
        progress: &ModelProgressSender,
        retry: u32,
        message: &str,
    ) -> anyhow::Result<()> {
        let mut failure = ProviderFailure::new(
            ProviderFailureKind::ServiceBusy,
            message,
            RetryDisposition::Retryable {
                retry_after_ms: Some(1200),
            },
        )
        .at_stage(ProviderFailureStage::Attachment);
        failure.code = Some("server_error".into());
        failure.error_type = Some("upload_error".into());
        failure.http_status = Some(503);
        failure.context.request_id = Some(format!("upload-{retry}"));
        let decision = ModelRecoveryDecision {
            failure_kind: failure.kind,
            recovery: ProviderRecovery::None,
            retry,
            max_retries: 5,
            effective_wait_millis: 1200,
            provider_failure: Some(failure),
        };
        let payload = OpaquePayload::new(
            "pl.model.recovery-decision",
            1,
            serde_json::to_string(&decision)?,
        )?;
        progress.stage_preparation_recovery(
            5,
            retry,
            message.into(),
            Some(payload),
            ModelRecoveryPhase::Waiting,
        )?;
        Ok(())
    }

    #[test]
    fn attachment_recovery_after_first_inference_preserves_the_original_diagnosis()
    -> anyhow::Result<()> {
        let progress = ModelProgressSender::detached(4096);
        reject_upload(&progress, 1, "upload service busy")?;
        progress.start_recovery_send();
        assert_eq!(progress.latest().observation().generation, 0);
        progress.finish_recovery(ModelRecoveryPhase::Recovered);

        let notices = recovery_notices("a", progress.latest().observation());
        assert_eq!(notices.len(), 2);
        assert_eq!(notices[0].1, "upload service busy");
        assert_eq!(notices[1].1, "模型请求已恢复，继续执行。");
        let original = notices[0]
            .2
            .failure
            .as_ref()
            .expect("original provider diagnosis");
        assert_eq!(original.code.as_deref(), Some("server_error"));
        assert_eq!(original.error_type.as_deref(), Some("upload_error"));
        assert_eq!(original.http_status, Some(503));
        assert_eq!(original.request_id.as_deref(), Some("upload-1"));
        assert_eq!(original.stage, Some(ProviderFailureStage::Attachment));
        assert_eq!(original.message, "upload service busy");
        assert_eq!(original.retry.retry_after_ms(), Some(1200));
        assert_eq!(notices[1].2.phase, ModelRecoveryPhase::Recovered);
        assert_eq!(notices[1].2.failure.as_ref(), Some(original));
        Ok(())
    }

    #[test]
    fn only_latest_preparation_failure_tracks_waiting_and_cancelled_phases() -> anyhow::Result<()> {
        let progress = ModelProgressSender::detached(4096);
        reject_upload(&progress, 1, "first upload failed")?;
        reject_upload(&progress, 2, "second upload failed")?;
        assert_eq!(progress.latest().observation().generation, 0);
        let waiting = recovery_notices("a", progress.latest().observation());
        assert_eq!(waiting.len(), 2);
        assert_eq!(waiting[0].1, "first upload failed");
        assert_eq!(waiting[1].1, "second upload failed");
        assert_eq!(waiting[0].2.phase, ModelRecoveryPhase::Retrying);
        assert_eq!(waiting[1].2.phase, ModelRecoveryPhase::Waiting);

        progress.finish_recovery(ModelRecoveryPhase::Cancelled);
        let cancelled = recovery_notices("a", progress.latest().observation());
        assert_eq!(cancelled.len(), 3);
        assert_eq!(cancelled[0], waiting[0]);
        assert_eq!(cancelled[1].0, waiting[1].0);
        assert_eq!(cancelled[1].1, waiting[1].1);
        assert_eq!(cancelled[1].2.phase, ModelRecoveryPhase::Cancelled);
        assert_eq!(cancelled[2].2.phase, ModelRecoveryPhase::Cancelled);
        let failure = cancelled[2]
            .2
            .failure
            .as_ref()
            .expect("cancelled wait diagnosis");
        assert_eq!(failure.request_id.as_deref(), Some("upload-2"));
        assert_eq!(cancelled[1].2.failure.as_ref(), Some(failure));
        Ok(())
    }
}
