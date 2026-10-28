//! Immutable terminal reports contain submitted conclusions, never later delivery outcomes.
use crate::studio::thread_projection::TurnResult;
use anyhow::Result;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{ThreadSnapshot, TurnRecord},
};
use pl_protocol::Thread;
use pl_tool::finish_turn::ReviewDisposition;

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TurnReport<'a> {
    child_id: &'a str,
    commit_sequence: u64,
    turn: &'a TurnRecord,
    turn_id: &'a str,
    input_id: Option<&'a str>,
    message: String,
    messages: Vec<MessageIdentity<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    last_tool: Option<pl_protocol::ThreadToolItem>,
    running_tasks: Vec<&'a str>,
    pending_interactions: Vec<&'a str>,
    permissions: Vec<&'a pl_core::thread::permissions::PermissionRecord>,
    #[serde(skip_serializing_if = "Option::is_none")]
    review: Option<ReviewReport<'a>>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct ReviewReport<'a> {
    target: Option<&'a pl_protocol::AgentReviewTargetSnapshot>,
    /// Conclusion submitted for this frozen baseline, not approval of a later checkout.
    disposition: ReviewDisposition,
    summary: String,
    reviewed_version: Option<&'a str>,
    reason: Option<ReviewConclusionReason>,
    full_report: FullReportLocation<'a>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
enum ReviewConclusionReason {
    MissingConclusion,
    AbnormalTerminal,
    UnsettledWork,
    InvalidFrozenBinding,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct FullReportLocation<'a> {
    agent_id: &'a str,
    turn_id: &'a str,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MessageIdentity<'a> {
    id: &'a str,
    source_id: &'a str,
    sequence: u64,
    consumed: bool,
}

/// Frozen by the terminal projection before handing the effect to its one history writer.
/// No current target lookup, filesystem probe, forwarding or future idle assertion belongs here.
pub(super) fn terminal_message(
    thread: &Thread,
    snapshot: &ThreadSnapshot,
    turn: &TurnRecord,
    sequence: u64,
    result: &TurnResult,
) -> Result<pl_core::thread::inbox::ThreadMessage> {
    let mut report = report(thread, turn, snapshot, result)?;
    report.commit_sequence = sequence;
    let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)?;
    let profile = crate::studio::model_route::saved_profile(snapshot)?.map(|(profile, _)| profile);
    let is_review = assignment
        .as_ref()
        .is_some_and(|assignment| assignment.mode == pl_protocol::AgentWorkspaceMode::Review)
        || profile.as_ref().is_some_and(|profile| {
            profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review
        });
    if is_review {
        let typed = result
            .finish
            .as_ref()
            .and_then(|finish| finish.review.as_ref());
        let valid_binding = assignment.as_ref().is_some_and(|assignment| {
            assignment.mode == pl_protocol::AgentWorkspaceMode::Review
                && assignment
                    .review_target
                    .as_ref()
                    .is_some_and(|target| target.baseline.is_some() && target.agent_id != thread.id)
        }) && profile.as_ref().is_some_and(|profile| {
            profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review
        });
        let unsettled = !report.running_tasks.is_empty()
            || !report.pending_interactions.is_empty()
            || snapshot
                .permissions
                .values()
                .any(|item| item.state == pl_core::thread::permissions::PermissionState::Pending)
            || snapshot.continuation.is_some();
        let reason = if !valid_binding {
            Some(ReviewConclusionReason::InvalidFrozenBinding)
        } else if !matches!(
            turn.state,
            pl_core::thread::TurnState::Finished(pl_core::thread::TurnOutcome::Completed)
        ) {
            Some(ReviewConclusionReason::AbnormalTerminal)
        } else if unsettled {
            Some(ReviewConclusionReason::UnsettledWork)
        } else if typed.is_none() {
            Some(ReviewConclusionReason::MissingConclusion)
        } else {
            None
        };
        let disposition = if reason.is_none() {
            typed
                .expect("a valid submitted conclusion exists")
                .disposition
        } else {
            ReviewDisposition::Inconclusive
        };
        let summary = typed.map_or_else(
            || "未提交有效结构化审查结论".to_owned(),
            |review| review.summary.clone(),
        );
        report.message = summary.clone();
        report.last_tool = None;
        report.review = Some(ReviewReport {
            target: assignment
                .as_ref()
                .and_then(|assignment| assignment.review_target.as_ref()),
            disposition,
            summary,
            reviewed_version: typed.map(|review| review.reviewed_version.as_str()),
            reason,
            full_report: FullReportLocation {
                agent_id: &thread.id,
                turn_id: &turn.turn_id,
            },
        });
        return encode_message(thread, sequence, &report);
    }
    encode_message(thread, sequence, &report)
}

fn encode_message(
    thread: &Thread,
    sequence: u64,
    report: &TurnReport<'_>,
) -> Result<pl_core::thread::inbox::ThreadMessage> {
    let content = serde_json::to_string(report)?;
    Ok(pl_core::thread::inbox::ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: crate::studio::agent_close::terminal_report_id(&thread.id, sequence),
        source_id: format!("studio.child:{}", thread.id),
        payload: OpaquePayload::new("pl.studio.turn-report", 3, content.clone())?,
        context: vec![ContextContent::Text {
            text: content.into(),
        }],
    })
}

fn report<'a>(
    thread: &'a Thread,
    turn: &'a TurnRecord,
    snapshot: &'a ThreadSnapshot,
    result: &'a TurnResult,
) -> Result<TurnReport<'a>> {
    let mut message = result.final_text().unwrap_or_default();
    let last_tool = if message.is_empty() {
        result.last_tool().cloned()
    } else {
        None
    };
    if message.is_empty() {
        message = format!(
            "本轮已停止，未提交最终总结。实际状态：{:?}。\n\n本轮已有可见输出：\n{}",
            turn,
            result.commentary()
        );
    }
    let message_item_ids = result
        .identities()
        .collect::<std::collections::BTreeSet<_>>();
    let through = snapshot
        .wake_messages_through
        .max(snapshot.consumed_messages);
    let messages = snapshot
        .inbox
        .iter()
        .filter(|record| {
            let item_id = crate::studio::thread_projection::order::message_id(&record.message.id);
            record.sequence <= through && message_item_ids.contains(item_id.as_str())
        })
        .map(|record| MessageIdentity {
            id: &record.message.id,
            source_id: &record.message.source_id,
            sequence: record.sequence,
            consumed: record.sequence <= snapshot.consumed_messages,
        })
        .collect();
    Ok(TurnReport {
        child_id: &thread.id,
        commit_sequence: snapshot.commit_sequence,
        turn,
        turn_id: &turn.turn_id,
        input_id: turn.input_id.as_deref(),
        message,
        messages,
        last_tool,
        running_tasks: snapshot
            .tasks
            .values()
            .filter(|task| task.status == pl_core::thread::task::TaskStatus::Running)
            .map(|task| task.id.as_str())
            .collect(),
        pending_interactions: snapshot
            .interactions
            .values()
            .filter(|item| item.state == pl_core::thread::interactions::InteractionState::Pending)
            .map(|item| item.request.id.as_str())
            .collect(),
        permissions: snapshot
            .permissions
            .values()
            .filter(|item| {
                item.turn_id == turn.turn_id
                    || item.state == pl_core::thread::permissions::PermissionState::Pending
            })
            .collect(),
        review: None,
    })
}
