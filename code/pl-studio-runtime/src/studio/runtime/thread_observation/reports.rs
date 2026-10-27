//! One immutable projection per terminal Turn; no separate delivery state or mutable report store.
use super::ObservationServices;
use crate::studio::thread_projection::TurnResult;
use crate::thread_assembler::agent_review::{
    ReviewDeliverySource, ReviewFeedbackDelivery, ReviewForward, terminal_report_id,
};
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
    turn: TerminalTurn<'a>,
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
    disposition: ReviewDisposition,
    summary: String,
    reviewed_version: Option<String>,
    reason: Option<ReviewConclusionReason>,
    forward: ReviewForward,
    full_report: FullReportLocation<'a>,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
enum ReviewConclusionReason {
    MissingConclusion,
    AbnormalTerminal,
    UnsettledWork,
    InvalidFrozenBinding,
    TargetChangedOrUnavailable,
    TargetVerificationFailed(
        #[serde(
            serialize_with = "crate::thread_assembler::agent_review::serialize_workspace_error"
        )]
        std::sync::Arc<crate::studio::thread_factory::ReviewWorkspaceError>,
    ),
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct FullReportLocation<'a> {
    agent_id: &'a str,
    turn_id: &'a str,
}

/// Cold history retains the product Turn, not invented Core counters or durations.
#[derive(Debug, Clone, Copy, serde::Serialize)]
#[serde(untagged)]
pub(super) enum TerminalTurn<'a> {
    Live(&'a TurnRecord),
    Saved(&'a pl_protocol::Turn),
}

impl<'a> TerminalTurn<'a> {
    fn id(self) -> &'a str {
        match self {
            Self::Live(turn) => &turn.turn_id,
            Self::Saved(turn) => &turn.id,
        }
    }
    fn input_id(self) -> Option<&'a str> {
        match self {
            Self::Live(turn) => turn.input_id.as_deref(),
            Self::Saved(turn) => turn.input_id.as_deref(),
        }
    }
    fn normal(self) -> bool {
        match self {
            Self::Live(turn) => matches!(
                turn.state,
                pl_core::thread::TurnState::Finished(pl_core::thread::TurnOutcome::Completed)
            ),
            Self::Saved(turn) => {
                matches!(&turn.state, pl_protocol::TurnState::Completed(state) if state.completion() == pl_protocol::TurnCompletion::Normal)
            }
        }
    }
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct MessageIdentity<'a> {
    id: &'a str,
    source_id: &'a str,
    sequence: u64,
    consumed: bool,
}

pub(super) struct TerminalPublication<'a> {
    pub turn: TerminalTurn<'a>,
    pub sequence: u64,
    pub wake: bool,
    pub result: &'a TurnResult,
    pub source: ReviewDeliverySource,
}

pub(super) async fn publish_terminal(
    services: &ObservationServices,
    thread: &Thread,
    snapshot: &ThreadSnapshot,
    publication: TerminalPublication<'_>,
) -> Result<()> {
    let TerminalPublication {
        turn,
        sequence,
        wake,
        result,
        source,
    } = publication;
    let Some(parent) = thread.parent_thread_id.as_deref() else {
        return Ok(());
    };
    // The result facts come from the reliable in-memory projection that owns this Thread's live
    // facts; the hot path never reads them back from history, and a Turn that committed its visible
    // output over many effects reports all of it rather than only the effect that finished it.
    // This is deliberately before target adjudication: a parent's accepted report owns its actual
    // original disposition and must never be regenerated under the same identity after recovery.
    if services
        .threads
        .terminal_report_accepted(parent, &thread.id, sequence)
        .await?
    {
        return Ok(());
    }
    // The terminal commit and its durable barrier can outlive an owner update. Never approve or
    // forward using an old idle snapshot while the reviewer already owns newer work.
    let current = services
        .threads
        .thread(&thread.id)
        .map(|thread| thread.snapshot());
    let snapshot = current.as_ref().unwrap_or(snapshot);
    let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)?;
    let profile = crate::studio::model_route::saved_profile(snapshot)?.map(|(profile, _)| profile);
    let is_review = assignment
        .as_ref()
        .is_some_and(|assignment| assignment.mode == pl_protocol::AgentWorkspaceMode::Review)
        || profile.as_ref().is_some_and(|profile| {
            profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review
        });
    let review = if is_review {
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
        let mut reason = if !valid_binding {
            Some(ReviewConclusionReason::InvalidFrozenBinding)
        } else if !turn.normal() {
            Some(ReviewConclusionReason::AbnormalTerminal)
        } else if !idle(snapshot) {
            Some(ReviewConclusionReason::UnsettledWork)
        } else if typed.is_none() {
            Some(ReviewConclusionReason::MissingConclusion)
        } else {
            None
        };
        if reason.is_none()
            && services
                .threads
                .thread(&thread.id)
                .is_some_and(|thread| !idle(&thread.snapshot()))
        {
            reason = Some(ReviewConclusionReason::UnsettledWork);
        }
        let receipt_first_feedback = typed
            .is_some_and(|review| review.disposition == ReviewDisposition::NeedsChanges)
            && valid_binding
            && assignment
                .as_ref()
                .and_then(|assignment| assignment.review_target.as_ref())
                .is_some_and(|target| {
                    target.feedback == Some(pl_protocol::AgentReviewFeedback::ToExecutor)
                });
        // A previous accepted feedback must remain visible even if that feedback has already
        // started a new target Turn. Only a still-valid live conclusion can authorize a new send.
        let forward = if typed
            .is_some_and(|review| review.disposition == ReviewDisposition::NeedsChanges)
            && valid_binding
        {
            match (
                assignment.as_ref(),
                result
                    .finish
                    .as_ref()
                    .and_then(|finish| finish.feedback_message.as_deref()),
            ) {
                (Some(assignment), Some(body)) => {
                    services
                        .threads
                        .forward_review(ReviewFeedbackDelivery {
                            reviewer: &thread.id,
                            turn_id: turn.id(),
                            terminal_sequence: sequence,
                            assignment,
                            body,
                            source: if reason.is_none() {
                                source
                            } else {
                                ReviewDeliverySource::Reconciliation
                            },
                        })
                        .await
                }
                _ => ReviewForward::NotRequired,
            }
        } else {
            ReviewForward::NotRequired
        };
        // Feedback's own boundary adjudicates receipts BEFORE any target version/physical probe.
        // Reconciliation without a receipt never probes/activates a workspace or first-sends.
        if !receipt_first_feedback
            && reason.is_none()
            && typed.is_some_and(|review| review.disposition != ReviewDisposition::Inconclusive)
        {
            match services
                .threads
                .review_baseline_current(parent, assignment.as_ref().expect("validated binding"))
                .await
            {
                Ok(true) => {}
                Ok(false) => reason = Some(ReviewConclusionReason::TargetChangedOrUnavailable),
                Err(error) => {
                    let source = match error
                        .downcast::<crate::studio::thread_factory::ReviewWorkspaceError>()
                    {
                        Ok(error) => error,
                        Err(error) => {
                            crate::studio::thread_factory::ReviewWorkspaceError::Assembly(
                                crate::thread_assembler::ThreadAssemblyError::Resource {
                                    operation: "verify review target",
                                    source: error.into(),
                                },
                            )
                        }
                    };
                    reason = Some(ReviewConclusionReason::TargetVerificationFailed(
                        std::sync::Arc::new(source),
                    ));
                }
            }
        }
        if receipt_first_feedback && matches!(&forward, ReviewForward::Rejected { reason: crate::thread_assembler::agent_review::ReviewForwardReason::TargetChanged | crate::thread_assembler::agent_review::ReviewForwardReason::WorkspaceCheckRejected(_), .. }) {
            reason = Some(ReviewConclusionReason::TargetChangedOrUnavailable);
        }
        let disposition = if reason.is_none() {
            typed.expect("validated conclusion").disposition
        } else {
            ReviewDisposition::Inconclusive
        };
        Some(ReviewReport {
            target: assignment
                .as_ref()
                .and_then(|assignment| assignment.review_target.as_ref()),
            disposition,
            summary: typed.map_or_else(
                || "没有可验证的结构化审查结论；请按全文定位读取原报告。".into(),
                |review| review.summary.clone(),
            ),
            reviewed_version: typed.map(|review| review.reviewed_version.clone()),
            reason,
            forward,
            full_report: FullReportLocation {
                agent_id: &thread.id,
                turn_id: turn.id(),
            },
        })
    } else {
        None
    };
    let mut report = report(thread, turn, snapshot, result)?;
    report.commit_sequence = sequence;
    if is_review {
        report.message =
            "审查全文保留在审查者历史；结构化结论、回送状态及全文定位见 review。".into();
        report.last_tool = None;
        report.review = review;
    }
    let content = serde_json::to_string(&report)?;
    let message_id = terminal_report_id(&thread.id, sequence);
    services
        .threads
        .notify_parent(
            parent,
            pl_core::thread::inbox::ThreadMessage {
                kind: pl_core::context::AgentMessageKind::Report,
                // Preserve the sequence-derived identity used by historical terminal notifications.
                id: message_id,
                source_id: format!("studio.child:{}", thread.id),
                payload: OpaquePayload::new("pl.studio.turn-report", 2, content.clone())?,
                context: vec![ContextContent::Text {
                    text: content.into(),
                }],
            },
            wake,
        )
        .await?;
    Ok(())
}

fn report<'a>(
    thread: &'a Thread,
    turn: TerminalTurn<'a>,
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
        turn_id: turn.id(),
        input_id: turn.input_id(),
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
                item.turn_id == turn.id()
                    || item.state == pl_core::thread::permissions::PermissionState::Pending
            })
            .collect(),
        review: None,
    })
}

fn idle(snapshot: &ThreadSnapshot) -> bool {
    crate::thread_assembler::agent_review::validate_idle(snapshot).is_ok()
}
