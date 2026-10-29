//! Re-enter each original exception root through public input; never cross-root reads.
use super::{
    Environment,
    flow::*,
    journeys::Decision,
    review_child,
    review_delivery::Notice,
    review_feedback::{self as feedback, Identity},
    wire::*,
};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::BTreeMap;

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct ExceptionFirst {
    pub case: String,
    pub root: String,
    pub target: Spawn,
    pub latest: Identity,
    pub reviewer: Identity,
    pub submission: String,
    pub exception: Notice,
    pub all_child_requests: BTreeMap<String, usize>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Checked {
    pub first: ExceptionFirst,
    pub submission_after: String,
    pub exception_after: Notice,
    pub latest_after: Identity,
    pub all_child_requests_after: BTreeMap<String, usize>,
}

#[derive(Deserialize)]
struct FirstReceipt {
    first: ExceptionFirst,
}

fn saved_first(environment: &Environment, case: &str) -> Result<ExceptionFirst> {
    let observations = environment
        .observations
        .lock()
        .map_err(|_| anyhow::anyhow!("exception first observations poisoned"))?;
    let rows = observations
        .iter()
        .filter(|row| row.accepted && row.note == format!("rf-{case}-complete"))
        .collect::<Vec<_>>();
    require(
        rows.len() == 1,
        "exception reopen needs its unique first checkpoint",
    )?;
    let receipt: FirstReceipt = serde_json::from_value(
        rows[0]
            .receipt
            .clone()
            .context("first exception checkpoint lacks evidence")?,
    )
    .context("decode first exception evidence")?;
    require(receipt.first.case == case, "exception first case changed")?;
    Ok(receipt.first)
}

pub(super) fn exception(
    flow: &Flow<'_>,
    environment: &Environment,
    case: &str,
) -> Progress<Decision> {
    review_child::require_no_leak(flow.request)?;
    let first = saved_first(environment, case)?;
    let rows: Vec<AgentRow> =
        flow.read("rf-exception-reopen-directory", "list_agents", json!({}))?;
    require(
        rows.iter()
            .any(|row| row.id == first.root && row.parent_id.is_none()),
        "exception query did not restore its exact original root",
    )?;
    let target = rows
        .iter()
        .find(|row| row.id == first.target.agent_id)
        .context("reopened exception target absent")?;
    require(
        target.parent_id.as_deref() == Some(first.root.as_str())
            && target.lifecycle == Lifecycle::Closed
            && target.pending_inputs == 0
            && target.running_tasks == 0
            && target.frozen_model.as_ref() == Some(&first.target.model),
        "reopened exception target lost original permanent-close/parent/route state",
    )?;
    flow.latest_completed_turn(
        "rf-exception-reopen-latest",
        LatestTurnCheck {
            row: target,
            child: &first.target,
            turn_id: &first.latest.turn_id,
            history: TurnHistory::Always,
        },
    )?;
    // These are newly supplied product context bytes after real cold start and
    // public query, not a comparison of two copies of the fixture baseline.
    let reports = flow.request.reports()?;
    let report = reports
        .iter()
        .find(|report| Identity::new(report) == first.reviewer)
        .context("reopened exception root lost original review terminal")?;
    report.completed()?;
    report
        .review
        .as_ref()
        .context("reopened submitted conclusion missing")?
        .require_binding(report, &first.target)?;
    let latest = reports
        .iter()
        .find(|report| Identity::new(report) == first.latest)
        .context("reopened exception root lost target's original latest terminal")?;
    latest.completed()?;
    require(
        !reports.iter().any(|report| {
            report.child_id == first.target.agent_id
                && report.commit_sequence > first.latest.commit_sequence
        }),
        "exception reopen added a target terminal",
    )?;
    let notice = flow
        .request
        .review_exceptions()?
        .into_iter()
        .find(|notice| notice.exception_id == first.exception.exception_id)
        .context("reopened root lost its independent exception notification")?;
    require(
        report.raw == first.submission && notice == first.exception,
        "reopened immutable submission/exception identity or exact bytes changed",
    )?;
    let counts = feedback::child_counts(environment)?;
    let final_first = saved_first(environment, "closed")?;
    require(
        counts == final_first.all_child_requests,
        "exception reopen added a child provider request anywhere in the scene",
    )?;
    let checked = Checked {
        submission_after: report.raw.clone(),
        exception_after: notice,
        latest_after: Identity::new(latest),
        all_child_requests_after: counts,
        first,
    };
    let mut decision = Decision::answer(
        &format!("rf-reopen-{case}-checked"),
        "original exception root queried; immutable submission/exception and target latest Turn unchanged",
    );
    decision.receipt =
        Some(serde_json::to_value(checked).context("encode public exception recheck")?);
    Ok(decision)
}

pub(super) fn require_all(environment: &Environment) -> Result<Vec<Checked>> {
    let mut checked = Vec::new();
    for case in ["busy", "changed", "closed"] {
        let first = saved_first(environment, case)?;
        let observations = environment
            .observations
            .lock()
            .map_err(|_| anyhow::anyhow!("exception reopen observations poisoned"))?;
        let rows = observations
            .iter()
            .filter(|row| row.accepted && row.note == format!("rf-reopen-{case}-checked"))
            .collect::<Vec<_>>();
        require(
            rows.len() == 1,
            "aggregate reopen requires each original exception root query",
        )?;
        let proof: Checked = serde_json::from_value(
            rows[0]
                .receipt
                .clone()
                .context("exception recheck lacks public proof")?,
        )?;
        require(
            proof.first == first
                && proof.submission_after == first.submission
                && proof.exception_after == first.exception
                && proof.latest_after == first.latest,
            "exception recheck is not bound to the original case/bytes/target Turn",
        )?;
        checked.push(proof);
    }
    let first = saved_first(environment, "closed")?;
    let current = feedback::child_counts(environment)?;
    require(
        current == first.all_child_requests
            && checked
                .iter()
                .all(|proof| proof.all_child_requests_after == current),
        "aggregate reopen added child provider requests or lost its first baseline",
    )?;
    Ok(checked)
}
