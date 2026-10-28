//! Delivery → independent review → all repairs → final evaluation → cold close.

use super::{Environment, SHARED_MODEL, flow::*, journeys::Decision, wire::*};
use anyhow::Context;
use serde_json::json;

const COMMENT: &str = "DELEGATION_EVALUATION_ONLY：完成交付、独立审查及返修后验收通过。";
const LATE_COMMENT: &str = "DELEGATION_EVALUATION_ONLY：后续新增要求已返修并复核，更新原记录。";

pub(super) fn run(flow: &Flow<'_>, prompt: &str, environment: &Environment) -> Progress<Decision> {
    if prompt.starts_with("[[delegation:foreign]]") {
        let evaluation = environment
            .foreign
            .lock()
            .map_err(|_| anyhow::anyhow!("foreign receipt lock poisoned"))?
            .clone()
            .context("complete lifecycle root before the independent foreign-root probe")?;
        flow.rejected("foreign-parent", "evaluate_agent", json!({"target":evaluation.agent_id,"expectedTurnId":evaluation.turn_id,"expectedRevision":evaluation.revision,"taskCategory":"general","outcome":"passed","quality":4,"instructionFollowing":5,"comment":LATE_COMMENT}), "target must be the caller's direct child")?;
        return Ok(Decision::answer(
            "foreign_parent_rejected",
            "foreign parent rejected",
        ));
    }
    if prompt.starts_with("[[delegation:cold]]") {
        return cold(flow);
    }
    require(
        prompt.starts_with("[[delegation:lifecycle]]"),
        "unknown lifecycle marker",
    )?;
    let models = flow.models()?;
    let execution_route = select(&models, "-a", SHARED_MODEL)?;
    let review_route = select(&models, "-b", SHARED_MODEL)?;
    let executor = flow.spawn(
        "executor",
        "executor",
        Some(&execution_route),
        "[[delegation:child:initial]]",
        None,
    )?;
    let initial = flow.report("initial", &executor, "delegation initial delivery", 0)?;
    let initial_reviewer = flow.spawn(
        "reviewer-initial",
        "reviewer",
        Some(&review_route),
        "[[delegation:child:review]]",
        Some(&executor.agent_id),
    )?;
    let changes = flow.legacy_report(
        "review",
        &initial_reviewer,
        "delegation independent review: changes requested",
        0,
    )?;
    require(
        initial_reviewer.agent_id != executor.agent_id,
        "initial review reused the executor identity",
    )?;
    let initial_review_eval = flow.evaluate(
        "initial-review-evaluation",
        &initial_reviewer,
        &changes,
        0,
        "首轮独立审查任务已完整交付，指出需修复项。",
        "passed",
    )?;
    require(
        initial_review_eval.write == "created" && initial_review_eval.evaluation.revision == 1,
        "initial reviewer did not receive its own new final-task record",
    )?;
    flow.close("close-initial-reviewer", &initial_reviewer)?;
    let repair_input = flow.send("repair", &executor, "[[delegation:child:repair]]\nFix the independent review finding in the original task; keep the original frozen route. No external data changes.")?;
    let repaired = flow.continued_report(
        "repair",
        ContinuationReport {
            child: &executor,
            previous: &initial,
            input: &repair_input,
            previous_sequence: executor
                .message_sequence
                .context("spawn receipt lacks its accepted delivery sequence")?,
            output: "delegation repaired delivery",
        },
    )?;
    let repair_review_message = format!(
        "[[delegation:child:review-pass]]\nFresh-context independent acceptance for executor {}. Approved scope: synthetic initial delivery, the reported finding, and its repair; no external data changes. Initial review Turn {} reported: {}. Repaired executor Turn {} delivered: {}. Verify the repair against that scope, not the previous reviewer's conclusion.",
        executor.agent_id,
        changes.turn.turn_id,
        changes.message,
        repaired.turn.turn_id,
        repaired.message,
    );
    let repair_reviewer = flow.spawn(
        "reviewer-repair",
        "reviewer",
        Some(&review_route),
        &repair_review_message,
        Some(&executor.agent_id),
    )?;
    let approved = flow.legacy_report(
        "rereview",
        &repair_reviewer,
        "delegation independent review: approved",
        0,
    )?;
    require(
        repair_reviewer.agent_id != initial_reviewer.agent_id
            && repair_reviewer.agent_id != executor.agent_id
            && (&approved.child_id, &approved.turn.turn_id)
                != (&changes.child_id, &changes.turn.turn_id),
        "repair acceptance did not use a fresh reviewer child and scoped Turn identity",
    )?;
    // The first evaluation is deliberately after delivery, review, repair and
    // independent re-review; terminal Turn count is not a task-finish signal.
    let first = flow.evaluate(
        "final-evaluation",
        &executor,
        &repaired,
        0,
        COMMENT,
        "passed",
    )?;
    require(
        first.write == "created" && first.evaluation.revision == 1,
        "first final evaluation did not create revision one",
    )?;
    let repair_review_eval = flow.evaluate(
        "repair-review-evaluation",
        &repair_reviewer,
        &approved,
        0,
        "首次修复已由 fresh-context reviewer 独立验收，审查任务完整交付。",
        "passed",
    )?;
    require(
        repair_review_eval.write == "created" && repair_review_eval.evaluation.revision == 1,
        "repair reviewer did not receive its own new final-task record",
    )?;
    flow.close("close-repair-reviewer", &repair_reviewer)?;
    let repeated = flow.evaluate(
        "idempotent-evaluation",
        &executor,
        &repaired,
        0,
        COMMENT,
        "passed",
    )?;
    require(
        repeated.write == "unchanged" && repeated.evaluation == first.evaluation,
        "idempotent retry changed original revision/timestamp/content",
    )?;
    flow.rejected(
        "same-turn-conflict",
        "evaluate_agent",
        evaluation_arguments(&executor, &repaired, 1, "different final content"),
        "content conflicts with the same final Turn",
    )?;

    // A real late requirement starts new work. The child response remains held
    // at an external provider gate while the root attempts the old terminal.
    let late_input = flow.send("late-repair", &executor, "[[delegation:child:late-repair]]\nA genuinely new post-delivery requirement: deliver one additional synthetic revision, without changing model.")?;
    flow.rejected(
        "running-old-terminal",
        "evaluate_agent",
        evaluation_arguments(&executor, &repaired, 1, COMMENT),
        "child still has running work, pending input, interaction or permission",
    )?;
    // The endpoint waits for the actual held child request before issuing the
    // previous call. Seeing this rejection releases that external response.
    let _ = flow.raw("repair_rejected_old_terminal", "list_agents", json!({}))?;
    let late = flow.continued_report(
        "late-repair",
        ContinuationReport {
            child: &executor,
            previous: &repaired,
            input: &late_input,
            previous_sequence: repair_input.receipt.sequence,
            output: "delegation late repaired delivery",
        },
    )?;
    flow.rejected(
        "stale-turn",
        "evaluate_agent",
        evaluation_arguments(&executor, &repaired, 1, COMMENT),
        "latest committed terminal Turn",
    )?;
    flow.rejected(
        "stale-revision",
        "evaluate_agent",
        evaluation_arguments(&executor, &late, 0, LATE_COMMENT),
        "revision conflict",
    )?;
    let late_review_message = format!(
        "[[delegation:child:review-pass]]\nFresh-context independent acceptance for executor {}. Approved scope: the same repaired synthetic delivery plus a genuinely new post-delivery requirement for one additional revision, without changing model or external data. Earlier accepted executor Turn {} delivered: {}. Latest executor Turn {} delivered: {}. Independently verify the added scope before the executor's final evaluation is updated; do not reuse earlier reviewers' contexts or authority.",
        executor.agent_id, repaired.turn.turn_id, repaired.message, late.turn.turn_id, late.message,
    );
    let late_reviewer = flow.spawn(
        "reviewer-late",
        "reviewer",
        Some(&review_route),
        &late_review_message,
        Some(&executor.agent_id),
    )?;
    let late_approved = flow.legacy_report(
        "late-rereview",
        &late_reviewer,
        "delegation independent review: approved",
        0,
    )?;
    require(
        [&executor, &initial_reviewer, &repair_reviewer]
            .iter()
            .all(|child| child.agent_id != late_reviewer.agent_id)
            && [&changes, &approved].iter().all(|report| {
                (&report.child_id, &report.turn.turn_id)
                    != (&late_approved.child_id, &late_approved.turn.turn_id)
            }),
        "late acceptance did not use a third distinct reviewer child and scoped Turn identity",
    )?;
    let updated = flow.evaluate(
        "updated-evaluation",
        &executor,
        &late,
        1,
        LATE_COMMENT,
        "passed",
    )?;
    require(
        updated.write == "updated"
            && updated.evaluation.revision == 2
            && updated.evaluation.created_at == first.evaluation.created_at
            && updated.evaluation.agent_id == first.evaluation.agent_id,
        "new terminal appended a sample or lost original creation identity",
    )?;
    let late_review_eval = flow.evaluate(
        "late-review-evaluation",
        &late_reviewer,
        &late_approved,
        0,
        "新增要求已由另一位 fresh-context reviewer 独立验收，审查任务完整交付。",
        "passed",
    )?;
    require(
        late_review_eval.write == "created" && late_review_eval.evaluation.revision == 1,
        "late reviewer did not receive its own new revision-one record",
    )?;
    let detail: Detail = flow.read(
        "updated-detail",
        "get_delegation_model",
        json!({"accountId":executor.model.account_id,"modelId":executor.model.model_id}),
    )?;
    check_evaluations(&detail, &[&updated.evaluation])?;
    let reviewer_evaluations = [
        &initial_review_eval.evaluation,
        &repair_review_eval.evaluation,
        &late_review_eval.evaluation,
    ];
    let review_detail: Detail = flow.read(
        "reviewers-detail",
        "get_delegation_model",
        json!({"accountId":review_route.account_id,"modelId":review_route.model_id}),
    )?;
    check_evaluations(&review_detail, &reviewer_evaluations)?;
    let rows: Vec<AgentRow> = flow.read("frozen-directory", "list_agents", json!({}))?;
    check_rows(
        &rows,
        &[
            &executor,
            &initial_reviewer,
            &repair_reviewer,
            &late_reviewer,
        ],
    )?;
    check_lifecycle(
        &rows,
        &[&initial_reviewer, &repair_reviewer],
        Lifecycle::Closed,
    )?;
    check_lifecycle(&rows, &[&executor, &late_reviewer], Lifecycle::Open)?;
    *environment
        .foreign
        .lock()
        .map_err(|_| anyhow::anyhow!("foreign receipt lock poisoned"))? =
        Some(updated.evaluation.clone());
    let mut decision = Decision::answer(
        "lifecycle_complete",
        "delegation lifecycle complete; probe a different root with [[delegation:foreign]], then reopen this root and submit [[delegation:cold]].",
    );
    decision.receipt = Some(json!({
        "executor":updated.evaluation,"reviewers":reviewer_evaluations,
        "firstEvaluation":first.evaluation,"idempotentEvaluation":repeated.evaluation,
        "closedBeforeReopen":[initial_reviewer.agent_id,repair_reviewer.agent_id],
        "pendingColdClose":[executor.agent_id,late_reviewer.agent_id],
        "reviewReports":[
            {"agentId":initial_reviewer.agent_id,"turnId":changes.turn.turn_id,"commitSequence":changes.commit_sequence,"reviewTargetAgentId":executor.agent_id},
            {"agentId":repair_reviewer.agent_id,"turnId":approved.turn.turn_id,"commitSequence":approved.commit_sequence,"reviewTargetAgentId":executor.agent_id},
            {"agentId":late_reviewer.agent_id,"turnId":late_approved.turn.turn_id,"commitSequence":late_approved.commit_sequence,"reviewTargetAgentId":executor.agent_id},
        ],
    }));
    Ok(decision)
}

fn check_rows(rows: &[AgentRow], children: &[&Spawn]) -> anyhow::Result<()> {
    for child in children {
        let row = rows
            .iter()
            .find(|row| row.id == child.agent_id)
            .context("child missing from real agent directory")?;
        require(
            row.frozen_model.as_ref() == Some(&child.model)
                && row.pending_inputs == 0
                && row.running_tasks == 0,
            "directory lost frozen route or reports pending work",
        )?;
    }
    Ok(())
}

fn check_lifecycle(
    rows: &[AgentRow],
    children: &[&Spawn],
    expected: Lifecycle,
) -> anyhow::Result<()> {
    require(
        children.iter().all(|child| {
            rows.iter().any(|row| {
                row.id == child.agent_id
                    && row.lifecycle == expected
                    && row.frozen_model.as_ref() == Some(&child.model)
            })
        }),
        "agent directory changed the expected lifecycle or frozen identity",
    )
}

fn check_evaluations(detail: &Detail, expected: &[&Evaluation]) -> anyhow::Result<()> {
    require(
        detail.recent_evaluations.len() == expected.len()
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
        "detail did not preserve exactly the real committed child evaluation records",
    )
}

fn historical<T: serde::de::DeserializeOwned>(
    flow: &Flow<'_>,
    label: &str,
    tool: &str,
) -> Progress<T> {
    let suffix = format!("-{label}");
    let call = flow
        .request
        .input
        .iter()
        .rfind(|item| {
            item.kind == "function_call"
                && item.name.as_deref() == Some(tool)
                && item
                    .call_id
                    .as_ref()
                    .is_some_and(|id| id.ends_with(&suffix))
        })
        .context("cold root did not restore original tool history")?;
    let call_id = call
        .call_id
        .as_deref()
        .context("historical call has no identity")?;
    let arguments: serde_json::Value = serde_json::from_str(
        call.arguments
            .as_deref()
            .context("historical call has no arguments")?,
    )
    .context("decode historical call arguments")?;
    flow.read_call(call_id, tool, arguments, &format!("cold-history-{label}"))
}

fn cold(flow: &Flow<'_>) -> Progress<Decision> {
    let executor: Spawn = historical(flow, "executor", "spawn_agent")?;
    let initial_reviewer: Spawn = historical(flow, "reviewer-initial", "spawn_agent")?;
    let repair_reviewer: Spawn = historical(flow, "reviewer-repair", "spawn_agent")?;
    let late_reviewer: Spawn = historical(flow, "reviewer-late", "spawn_agent")?;
    let evaluation: EvaluationReceipt = historical(flow, "updated-evaluation", "evaluate_agent")?;
    let initial_review_eval: EvaluationReceipt =
        historical(flow, "initial-review-evaluation", "evaluate_agent")?;
    let repair_review_eval: EvaluationReceipt =
        historical(flow, "repair-review-evaluation", "evaluate_agent")?;
    let late_review_eval: EvaluationReceipt =
        historical(flow, "late-review-evaluation", "evaluate_agent")?;
    let rows: Vec<AgentRow> = flow.read("cold-list", "list_agents", json!({}))?;
    check_rows(
        &rows,
        &[
            &executor,
            &initial_reviewer,
            &repair_reviewer,
            &late_reviewer,
        ],
    )?;
    check_lifecycle(
        &rows,
        &[&initial_reviewer, &repair_reviewer],
        Lifecycle::Closed,
    )?;
    flow.discover()?;
    let detail: Detail = flow.read(
        "cold-detail",
        "get_delegation_model",
        json!({"accountId":executor.model.account_id,"modelId":executor.model.model_id}),
    )?;
    check_evaluations(&detail, &[&evaluation.evaluation])?;
    let review_detail: Detail = flow.read(
        "cold-reviewers-detail",
        "get_delegation_model",
        json!({"accountId":late_reviewer.model.account_id,"modelId":late_reviewer.model.model_id}),
    )?;
    check_evaluations(
        &review_detail,
        &[
            &initial_review_eval.evaluation,
            &repair_review_eval.evaluation,
            &late_review_eval.evaluation,
        ],
    )?;
    // The first two review tasks were already evaluated and really closed in
    // phase one. Only these retained targets need the explicit cold-close path.
    let executor_close = flow.close("cold-close-executor", &executor)?;
    flow.close("cold-close-reviewer-late", &late_reviewer)?;
    // A completed close removes its owner; the next send uses activation just
    // like a cold send. Keep the supplier input valid, not a fake rejection.
    let closed_send = flow.refused_closed_send(ClosedSendCheck {
        label: "closed-send",
        child: &executor,
        close: &executor_close,
        root: &evaluation.evaluation.parent_agent_id,
        turn_id: &evaluation.evaluation.turn_id,
        marker: "[[delegation:child:sample]]",
    })?;
    let closed: Vec<AgentRow> = flow.read("closed-list", "list_agents", json!({}))?;
    check_lifecycle(
        &closed,
        &[
            &executor,
            &initial_reviewer,
            &repair_reviewer,
            &late_reviewer,
        ],
        Lifecycle::Closed,
    )?;
    let mut decision = Decision::answer("cold_close_complete", "delegation cold close complete");
    decision.receipt = Some(json!({
        "closedChildren":[executor.agent_id,initial_reviewer.agent_id,repair_reviewer.agent_id,late_reviewer.agent_id],
        "executor":evaluation.evaluation,
        "reviewers":[initial_review_eval.evaluation,repair_review_eval.evaluation,late_review_eval.evaluation],
        "closedSend":closed_send,
    }));
    Ok(decision)
}
