//! Sequential real children keep production concurrency limits intact while
//! exercising the recent-ten evaluation window and exact account isolation.

use super::{OTHER_MODEL, SHARED_MODEL, flow::*, journeys::Decision, wire::*};
use anyhow::Context;
use serde_json::json;

pub(super) fn run(flow: &Flow<'_>, prompt: &str) -> Progress<Decision> {
    if prompt.starts_with("[[delegation:window-reopen]]") {
        return reopened(flow);
    }
    require(
        prompt.starts_with("[[delegation:window]]"),
        "unknown evaluation-window marker",
    )?;
    let models = flow.models()?;
    let a = select(&models, "-a", SHARED_MODEL)?;
    let b = select(&models, "-b", SHARED_MODEL)?;
    let review_route = select(&models, "-a", OTHER_MODEL)?;
    let mut records = Vec::new();
    for index in 0..12 {
        let route = if index == 11 { &b } else { &a };
        let child = flow.spawn(
            &format!("sample-spawn-{index}"),
            "explorer",
            Some(route),
            "[[delegation:child:sample]]",
            None,
        )?;
        let report = flow.report(
            &format!("sample-{index}"),
            &child,
            "delegation sample delivery",
            0,
        )?;
        let reviewer = flow.spawn(
            &format!("sample-review-{index}"),
            "reviewer",
            Some(&review_route),
            "[[delegation:child:review-pass]]",
            Some(&child.agent_id),
        )?;
        let approval = flow.legacy_report(
            &format!("sample-review-{index}"),
            &reviewer,
            "delegation independent review: approved",
            0,
        )?;
        if index == 0 {
            // Count the *original* Unicode text, including the outer spaces.
            let too_long = format!(" {} ", "界".repeat(299));
            flow.rejected(
                "comment-301",
                "evaluate_agent",
                evaluation_arguments(&child, &report, 0, &too_long),
                "exceeds 300 characters",
            )?;
            flow.rejected(
                "comment-whitespace",
                "evaluate_agent",
                evaluation_arguments(&child, &report, 0, " \t\n "),
                "non-empty comment",
            )?;
            let mut not_rated =
                evaluation_arguments(&child, &report, 0, "environment cannot be judged");
            not_rated["outcome"] = "notRated".into();
            flow.rejected(
                "not-rated-with-score",
                "evaluate_agent",
                not_rated,
                "cannot carry scores",
            )?;
            let mut missing =
                evaluation_arguments(&child, &report, 0, "failed result without the second score");
            missing["outcome"] = "failed".into();
            missing
                .as_object_mut()
                .context("evaluation must be an object")?
                .remove("instructionFollowing");
            flow.rejected(
                "rated-without-score",
                "evaluate_agent",
                missing,
                "requires quality and instructionFollowing",
            )?;
        }
        let comment = if index == 0 {
            format!(" {} ", "界".repeat(298))
        } else {
            format!("DELEGATION_EVALUATION_ONLY synthetic final task {index}")
        };
        let outcome = if index % 2 == 0 || index == 11 {
            "notRated"
        } else {
            "passed"
        };
        let receipt = flow.evaluate(
            &format!("sample-eval-{index}"),
            &child,
            &report,
            0,
            &comment,
            outcome,
        )?;
        require(
            receipt.write == "created" && receipt.evaluation.revision == 1,
            "sample did not create exactly one committed child evaluation",
        )?;
        if outcome == "notRated" {
            require(
                receipt.evaluation.quality.is_none()
                    && receipt.evaluation.instruction_following.is_none(),
                "notRated retained a score",
            )?;
        }
        records.push(receipt.evaluation);
        let _ = flow.evaluate(
            &format!("sample-review-eval-{index}"),
            &reviewer,
            &approval,
            0,
            "Independent synthetic sample review delivered.",
            "passed",
        )?;
        flow.close(&format!("sample-review-close-{index}"), &reviewer)?;
        flow.close(&format!("sample-close-{index}"), &child)?;
    }
    check_details(flow, &a, &b, &records, "window")?;
    let mut decision = Decision::answer(
        "window_complete",
        "delegation evaluation window complete; restart this home and submit [[delegation:window-reopen]] in this root.",
    );
    decision.receipt = Some(json!({"committedEvaluations":records}));
    Ok(decision)
}

fn check_details(
    flow: &Flow<'_>,
    a: &Route,
    b: &Route,
    records: &[Evaluation],
    label: &str,
) -> Progress<()> {
    flow.discover()?;
    for (suffix, route) in [("a", a), ("b", b)] {
        let detail: Detail = flow.read(
            &format!("{label}-detail-{suffix}"),
            "get_delegation_model",
            json!({"accountId":route.account_id,"modelId":route.model_id}),
        )?;
        let mut expected: Vec<_> = records
            .iter()
            .filter(|record| {
                record.model.account_id == route.account_id
                    && record.model.model_id == route.model_id
            })
            .cloned()
            .collect();
        expected.sort_by(|left, right| {
            (right.updated_at, &right.agent_id).cmp(&(left.updated_at, &left.agent_id))
        });
        expected.truncate(10);
        require(
            detail.recent_evaluations == expected,
            "recent-ten order, content, timestamps or account isolation differs from real committed receipts",
        )?;
        let rated = expected
            .iter()
            .filter(|record| record.outcome != "notRated")
            .count();
        require(
            detail.evaluations.rated_samples == rated
                && detail.evaluations.not_rated == expected.len() - rated,
            "window summary counted calls/Turns/notRated as rated task samples",
        )?;
        require(
            detail.evaluations.average_quality == (rated > 0).then_some(4.0)
                && detail.evaluations.average_instruction_following == (rated > 0).then_some(5.0),
            "notRated polluted means or unknown empty means became zero",
        )?;
    }
    Ok(())
}

fn reopened(flow: &Flow<'_>) -> Progress<Decision> {
    let mut records = Vec::new();
    for index in 0..12 {
        let suffix = format!("-sample-eval-{index}");
        let call = flow
            .request
            .input
            .iter()
            .find(|item| {
                item.kind == "function_call"
                    && item.name.as_deref() == Some("evaluate_agent")
                    && item
                        .call_id
                        .as_ref()
                        .is_some_and(|id| id.ends_with(&suffix))
            })
            .context("restored window root lost original evaluation calls")?;
        let call_id = call
            .call_id
            .as_deref()
            .context("evaluation has no call id")?;
        let arguments: serde_json::Value = serde_json::from_str(
            call.arguments
                .as_deref()
                .context("evaluation call has no arguments")?,
        )
        .context("decode original evaluation arguments")?;
        let receipt: EvaluationReceipt = flow.read_call(
            call_id,
            "evaluate_agent",
            arguments,
            &format!("window-history-evaluation-{index}"),
        )?;
        records.push(receipt.evaluation);
    }
    require(
        records.len() == 12,
        "reopened window lacks twelve real committed child evaluations",
    )?;
    check_details(
        flow,
        &records[0].model,
        &records[11].model,
        &records,
        "reopened",
    )?;
    Ok(Decision::answer(
        "window_reopened_complete",
        "delegation evaluation window reopened complete",
    ))
}
