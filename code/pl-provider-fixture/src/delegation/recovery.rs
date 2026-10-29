//! A normal host shutdown is not an explicit task close. Both outcomes are
//! exercised through real tools, in one root across two native GUI lifetimes.

use super::{Environment, SHARED_MODEL, flow::*, journeys::Decision, wire::*};
use anyhow::{Context, Result};
use serde::{Serialize, de::DeserializeOwned};
use serde_json::json;

pub(super) const CHILD_FINAL_NOTES: [&str; 4] = [
    "recovery_child_initial",
    "recovery_child_review_initial",
    "recovery_child_repair",
    "recovery_child_review_resumed",
];
const INITIAL: &str = "delegation recovery initial delivery";
const REPAIRED: &str = "delegation recovery resumed delivery";
const APPROVED: &str = "delegation recovery independent review: approved";
const FIRST_COMMENT: &str =
    "DELEGATION_EVALUATION_ONLY：初次任务交付并经独立审查通过，保留执行者供正常退出后续修。";
const RESUMED_COMMENT: &str =
    "DELEGATION_EVALUATION_ONLY：同一执行者正常重开后完成新增要求，经新的独立审查更新原评价。";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ChildEvidence {
    agent_id: String,
    profile_id: String,
    model: Route,
    message_sequence: u64,
    turn_id: String,
    commit_sequence: u64,
    evaluation: Evaluation,
}

impl ChildEvidence {
    fn new(child: &Spawn, report: &Report, receipt: &EvaluationReceipt) -> Result<Self> {
        require(
            child.agent_id == report.child_id
                && receipt.target == child.agent_id
                && receipt.evaluation.agent_id == child.agent_id
                && receipt.evaluation.profile_id == child.profile_id
                && receipt.evaluation.model == child.model
                && receipt.evaluation.turn_id == report.turn.turn_id,
            "recovery evidence did not bind the real frozen child and completed Turn",
        )?;
        report.completed()?;
        Ok(Self {
            agent_id: child.agent_id.clone(),
            profile_id: child.profile_id.clone(),
            model: child.model.clone(),
            message_sequence: child
                .message_sequence
                .filter(|sequence| *sequence > 0)
                .context("recovery spawn has no accepted delivery sequence")?,
            turn_id: report.turn.turn_id.clone(),
            commit_sequence: report.commit_sequence,
            evaluation: receipt.evaluation.clone(),
        })
    }
}

struct DirectoryExpectation<'a> {
    child: &'a Spawn,
    report: &'a Report,
    lifecycle: Option<Lifecycle>,
}

pub(super) fn run(flow: &Flow<'_>, prompt: &str, environment: &Environment) -> Progress<Decision> {
    if prompt.starts_with("[[delegation:recovery-resume]]") {
        return resumed(flow, environment);
    }
    require(
        prompt.starts_with("[[delegation:recovery]]"),
        "unknown recovery marker",
    )?;
    let models = flow.models()?;
    let execution_route = select(&models, "-a", SHARED_MODEL)?;
    let review_route = select(&models, "-b", SHARED_MODEL)?;
    let executor = flow.spawn(
        "recovery-executor",
        "worktree_executor",
        Some(&execution_route),
        "[[delegation:child:recovery-initial]]",
        None,
    )?;
    let delivery = flow.report("recovery-initial", &executor, INITIAL, 0)?;
    let review_message = format!(
        "[[delegation:child:recovery-review-initial]]\nIndependently accept the complete synthetic initial task for executor {}. Approved scope: deliver one isolated synthetic result, without external data changes. Executor Turn {} delivered: {}. Review that evidence before either final task evaluation.",
        executor.agent_id, delivery.turn.turn_id, delivery.message,
    );
    let reviewer = flow.spawn(
        "recovery-reviewer-initial",
        "reviewer",
        Some(&review_route),
        &review_message,
        Some(&executor.agent_id),
    )?;
    require(
        executor.agent_id != reviewer.agent_id,
        "recovery review reused the executor",
    )?;
    let review = flow.report("recovery-review-initial", &reviewer, APPROVED, 0)?;
    let first = flow.evaluate(
        "recovery-first-evaluation",
        &executor,
        &delivery,
        0,
        FIRST_COMMENT,
        "passed",
    )?;
    let reviewed = flow.evaluate(
        "recovery-initial-review-evaluation",
        &reviewer,
        &review,
        0,
        "初次独立审查已完整交付；显式关闭此 reviewer，不复用它验收后续要求。",
        "passed",
    )?;
    require_created(&first)?;
    require_created(&reviewed)?;
    let closed = flow.close("recovery-close-initial-reviewer", &reviewer)?;
    let rows: Vec<AgentRow> = flow.read("recovery-first-directory", "list_agents", json!({}))?;
    let root = &first.evaluation.parent_agent_id;
    require(
        reviewed.evaluation.parent_agent_id == *root,
        "recovery reviewers changed root",
    )?;
    check_directory(
        flow,
        "recovery-first",
        &rows,
        root,
        &[
            DirectoryExpectation {
                child: &executor,
                report: &delivery,
                lifecycle: Some(Lifecycle::Open),
            },
            DirectoryExpectation {
                child: &reviewer,
                report: &review,
                lifecycle: Some(Lifecycle::Closed),
            },
        ],
    )?;
    check_detail(
        flow,
        "recovery-first-executor-detail",
        &execution_route,
        &[&first.evaluation],
    )?;
    check_detail(
        flow,
        "recovery-first-reviewer-detail",
        &review_route,
        &[&reviewed.evaluation],
    )?;
    let mut decision = Decision::answer(
        "recovery_first_complete",
        "delegation recovery first complete; normal shutdown now, then reopen THIS root and submit [[delegation:recovery-resume]].",
    );
    decision.receipt = Some(json!({
        "rootAgentId":root,
        "executor":ChildEvidence::new(&executor, &delivery, &first)?,
        "reviewer":ChildEvidence::new(&reviewer, &review, &reviewed)?,
        "reviewerClose":closed,
    }));
    Ok(decision)
}

fn resumed(flow: &Flow<'_>, environment: &Environment) -> Progress<Decision> {
    let executor: Spawn = original(flow, "recovery-executor", "spawn_agent")?;
    let old_reviewer: Spawn = original(flow, "recovery-reviewer-initial", "spawn_agent")?;
    let first: EvaluationReceipt = original(flow, "recovery-first-evaluation", "evaluate_agent")?;
    let old_review: EvaluationReceipt =
        original(flow, "recovery-initial-review-evaluation", "evaluate_agent")?;
    let old_close: Closed = original(flow, "recovery-close-initial-reviewer", "close_agent")?;
    require_created(&first)?;
    require_created(&old_review)?;
    require(
        old_close.succeeded_for(&old_reviewer.agent_id)
            && old_close.agents.iter().any(|agent| {
                agent.agent_id == old_reviewer.agent_id
                    && agent.worktree_cleanup == WorktreeCleanup::NotApplicable
            }),
        "recovery lost the original explicit reviewer close receipt",
    )?;
    let delivery = saved_report(flow, &executor, &first)?;
    let review = saved_report(flow, &old_reviewer, &old_review)?;
    let root = &first.evaluation.parent_agent_id;
    require(
        old_review.evaluation.parent_agent_id == *root,
        "restored recovery changed root",
    )?;
    let rows: Vec<AgentRow> = flow.read("recovery-restored-directory", "list_agents", json!({}))?;
    // The previous owner may have persisted Core Closed during normal shutdown.
    // Do not infer Studio explicit-close intent from that physical lifecycle.
    check_directory(
        flow,
        "recovery-restored",
        &rows,
        root,
        &[
            DirectoryExpectation {
                child: &executor,
                report: &delivery,
                lifecycle: None,
            },
            DirectoryExpectation {
                child: &old_reviewer,
                report: &review,
                lifecycle: Some(Lifecycle::Closed),
            },
        ],
    )?;
    flow.discover()?;
    check_detail(
        flow,
        "recovery-restored-executor-detail",
        &executor.model,
        &[&first.evaluation],
    )?;
    check_detail(
        flow,
        "recovery-restored-reviewer-detail",
        &old_reviewer.model,
        &[&old_review.evaluation],
    )?;

    let closed_send = flow.refused_closed_send(ClosedSendCheck {
        label: "recovery-closed-send",
        child: &old_reviewer,
        close: &old_close,
        root,
        turn_id: &review.turn.turn_id,
        marker: "[[delegation:child:recovery-closed-probe]]",
    })?;
    require(
        closed_send.provider_requests_before == 0 && closed_send.provider_requests_after == 0,
        "explicitly closed reviewer received new provider input",
    )?;
    // This checkpoint is reached only after consuming the real negative tool result.
    let _: Vec<AgentRow> =
        flow.read("recovery_explicit_close_rejected", "list_agents", json!({}))?;

    let input = flow.send(
        "recovery-repair",
        &executor,
        "[[delegation:child:recovery-repair]]\nNew post-restart requirement: add one small synthetic revision to the prior delivery, without external data changes. Preserve your original context, Profile, child ID and frozen route.",
    )?;
    let repaired = flow.continued_report(
        "recovery-repair",
        ContinuationReport {
            child: &executor,
            previous: &delivery,
            input: &input,
            previous_sequence: executor
                .message_sequence
                .context("restored spawn lost input sequence")?,
            output: REPAIRED,
        },
    )?;
    let review_message = format!(
        "[[delegation:child:recovery-review-resumed]]\nFresh-context independent acceptance for executor {}. Approved scope: original synthetic delivery plus one new small post-restart revision, with no external data changes or route change. Original Turn {} delivered: {}. New Turn {} delivered: {}. The first reviewer is explicitly closed; independently review this evidence, do not reuse its context or conclusion.",
        executor.agent_id,
        delivery.turn.turn_id,
        delivery.message,
        repaired.turn.turn_id,
        repaired.message,
    );
    let reviewer = flow.spawn(
        "recovery-reviewer-resumed",
        "reviewer",
        Some(&old_reviewer.model),
        &review_message,
        Some(&executor.agent_id),
    )?;
    require(
        reviewer.agent_id != old_reviewer.agent_id && reviewer.agent_id != executor.agent_id,
        "resumed recovery did not spawn a fresh independent reviewer",
    )?;
    let approval = flow.report("recovery-review-resumed", &reviewer, APPROVED, 0)?;
    let updated = flow.evaluate(
        "recovery-updated-evaluation",
        &executor,
        &repaired,
        first.evaluation.revision,
        RESUMED_COMMENT,
        "passed",
    )?;
    require(
        updated.write == "updated"
            && updated.evaluation.revision == 2
            && updated.evaluation.created_at == first.evaluation.created_at
            && updated.evaluation.parent_agent_id == *root,
        "resumed executor did not update its original evaluation to revision two",
    )?;
    let reviewed = flow.evaluate(
        "recovery-resumed-review-evaluation",
        &reviewer,
        &approval,
        0,
        "正常重开后的新增要求已由新的 fresh-context reviewer 独立验收。",
        "passed",
    )?;
    require_created(&reviewed)?;
    let reviewer_close = flow.close("recovery-close-resumed-reviewer", &reviewer)?;
    let executor_close = flow.close("recovery-close-executor", &executor)?;
    require(
        executor_close.succeeded_for(&executor.agent_id)
            && executor_close.agents.iter().any(|agent| {
                agent.agent_id == executor.agent_id
                    && matches!(
                        &agent.worktree_cleanup,
                        WorktreeCleanup::Removed { path } if !path.trim().is_empty()
                    )
            }),
        "recovery executor close did not remove its worktree",
    )?;
    check_detail(
        flow,
        "recovery-final-executor-detail",
        &executor.model,
        &[&updated.evaluation],
    )?;
    check_detail(
        flow,
        "recovery-final-reviewers-detail",
        &old_reviewer.model,
        &[&old_review.evaluation, &reviewed.evaluation],
    )?;
    let rows: Vec<AgentRow> = flow.read("recovery-final-directory", "list_agents", json!({}))?;
    check_directory(
        flow,
        "recovery-final",
        &rows,
        root,
        &[
            DirectoryExpectation {
                child: &executor,
                report: &repaired,
                lifecycle: Some(Lifecycle::Closed),
            },
            DirectoryExpectation {
                child: &old_reviewer,
                report: &review,
                lifecycle: Some(Lifecycle::Closed),
            },
            DirectoryExpectation {
                child: &reviewer,
                report: &approval,
                lifecycle: Some(Lifecycle::Closed),
            },
        ],
    )?;
    require(
        environment.targeted_requests(&old_reviewer.agent_id)? == 0,
        "closed reviewer acquired a late provider request",
    )?;
    let mut decision = Decision::answer("recovery_complete", "delegation recovery complete");
    decision.receipt = Some(json!({
        "rootAgentId":root,
        "executor":ChildEvidence::new(&executor, &repaired, &updated)?,
        "initialReviewer":ChildEvidence::new(&old_reviewer, &review, &old_review)?,
        "reviewer":ChildEvidence::new(&reviewer, &approval, &reviewed)?,
        "continuation":input.receipt,
        "closedSend":closed_send,
        "closeReceipts":[old_close, reviewer_close, executor_close],
    }));
    Ok(decision)
}

fn require_created(receipt: &EvaluationReceipt) -> Result<()> {
    require(
        receipt.write == "created" && receipt.evaluation.revision == 1,
        "recovery expected one new final-task evaluation at revision one",
    )
}

fn check_directory(
    flow: &Flow<'_>,
    label: &str,
    rows: &[AgentRow],
    root: &str,
    expected: &[DirectoryExpectation<'_>],
) -> Progress<()> {
    require(
        rows.iter()
            .any(|row| row.id == root && row.parent_id.is_none()),
        "recovery must reopen the original root, not create a substitute",
    )?;
    require(
        rows.iter()
            .filter(|row| row.parent_id.is_some() && row.lifecycle == Lifecycle::Open)
            .count()
            <= 2,
        "recovery exceeded two Open children",
    )?;
    for (index, entry) in expected.iter().enumerate() {
        let row = rows
            .iter()
            .find(|row| row.id == entry.child.agent_id)
            .context("recovery child missing from real directory")?;
        require(
            row.parent_id.as_deref() == Some(root)
                && row.frozen_model.as_ref() == Some(&entry.child.model)
                && row.pending_inputs == 0
                && row.running_tasks == 0
                && entry
                    .lifecycle
                    .as_ref()
                    .is_none_or(|lifecycle| *lifecycle == row.lifecycle),
            "recovery directory changed frozen identity/latest completed Turn or has pending work",
        )?;
        flow.latest_completed_turn(
            &format!("{label}-saved-turn-{index}"),
            LatestTurnCheck {
                row,
                child: entry.child,
                turn_id: &entry.report.turn.turn_id,
                history: TurnHistory::WhenMissing,
            },
        )?;
    }
    Ok(())
}

fn check_detail(
    flow: &Flow<'_>,
    label: &str,
    route: &Route,
    expected: &[&Evaluation],
) -> Progress<()> {
    let detail: Detail = flow.read(
        label,
        "get_delegation_model",
        json!({"accountId":route.account_id,"modelId":route.model_id}),
    )?;
    require(
        detail.account_id == route.account_id
            && detail.recent_evaluations.len() == expected.len()
            && expected.iter().all(|evaluation| {
                detail
                    .recent_evaluations
                    .iter()
                    .filter(|record| record.agent_id == evaluation.agent_id)
                    .count()
                    == 1
                    && detail
                        .recent_evaluations
                        .iter()
                        .any(|record| record == *evaluation)
            }),
        "recovery detail did not preserve exactly the real evaluation receipts/content/timestamps",
    )?;
    Ok(())
}

fn original<T: DeserializeOwned>(flow: &Flow<'_>, label: &str, tool: &str) -> Progress<T> {
    let (start, _) = flow.request.prompt()?;
    let suffix = format!("-{label}");
    let call = flow.request.input[..start]
        .iter()
        .rfind(|item| {
            item.kind == "function_call"
                && item.name.as_deref() == Some(tool)
                && item
                    .call_id
                    .as_ref()
                    .is_some_and(|id| id.ends_with(&suffix))
        })
        .context("reopened recovery root lost its original real tool history")?;
    let call_id = call
        .call_id
        .as_deref()
        .context("original recovery call lacks identity")?;
    let arguments: serde_json::Value = serde_json::from_str(
        call.arguments
            .as_deref()
            .context("original recovery call lacks arguments")?,
    )
    .context("decode original recovery call arguments")?;
    flow.read_call(
        call_id,
        tool,
        arguments,
        &format!("recovery-history-{label}"),
    )
}

fn saved_report(flow: &Flow<'_>, child: &Spawn, receipt: &EvaluationReceipt) -> Result<Report> {
    let report = flow
        .request
        .reports()?
        .into_iter()
        .find(|report| {
            report.child_id == child.agent_id && report.turn.turn_id == receipt.evaluation.turn_id
        })
        .context("reopened recovery lost original child report")?;
    let _ = ChildEvidence::new(child, &report, receipt)?;
    Ok(report)
}

pub(super) fn child_reply(
    request: &Request,
    prompt: &str,
) -> Result<Option<(&'static str, &'static str)>> {
    let reply = if prompt.starts_with("[[delegation:child:recovery-initial]]") {
        (CHILD_FINAL_NOTES[0], INITIAL)
    } else if prompt.starts_with("[[delegation:child:recovery-review-initial]]") {
        (CHILD_FINAL_NOTES[1], APPROVED)
    } else if prompt.starts_with("[[delegation:child:recovery-repair]]") {
        let (start, _) = request.prompt()?;
        let previous = &request.input[..start];
        require(
            previous.iter().any(|item| {
                item.role.as_deref() == Some("user")
                    && item.content.as_ref().is_some_and(|content| {
                        content
                            .joined()
                            .starts_with("[[delegation:child:recovery-initial]]")
                    })
            }) && previous.iter().any(|item| {
                item.role.as_deref() == Some("assistant")
                    && item
                        .content
                        .as_ref()
                        .is_some_and(|content| content.joined() == INITIAL)
            }),
            "resumed executor provider request lost original task/delivery context",
        )?;
        (CHILD_FINAL_NOTES[2], REPAIRED)
    } else if prompt.starts_with("[[delegation:child:recovery-review-resumed]]") {
        (CHILD_FINAL_NOTES[3], APPROVED)
    } else if prompt.starts_with("[[delegation:child:recovery-closed-probe]]") {
        // This input is deliberately valid. Only the real Runtime may reject
        // explicit-close execution; a supplier rejection would be false proof.
        (
            "recovery_closed_probe_executed",
            "unexpected closed reviewer execution",
        )
    } else {
        return Ok(None);
    };
    Ok(Some(reply))
}
