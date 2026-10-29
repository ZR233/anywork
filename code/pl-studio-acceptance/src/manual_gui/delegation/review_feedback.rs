//! Phase-level oracle for the controlled review scene, not an automated test.
use super::*;
use pl_provider_fixture::delegation::Observation;
use serde::Deserialize;
use std::collections::BTreeMap;

const FIRST_NOTES: [&str; 10] = [
    "rf-normal-compact-complete",
    "rf-full-history-complete",
    "rf-approved-complete",
    "rf-inconclusive-complete",
    "rf-natural-complete",
    "rf-omitted-complete",
    "rf-illegal-complete",
    "rf-busy-complete",
    "rf-changed-complete",
    "rf-closed-complete",
];

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Identity {
    child_id: String,
    turn_id: String,
    #[serde(deserialize_with = "required_nullable")]
    input_id: Option<String>,
    commit_sequence: u64,
}

fn required_nullable<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> std::result::Result<Option<String>, D::Error> {
    Option::<String>::deserialize(deserializer)
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct First {
    root: String,
    executor: Identity,
    reviewer: Identity,
    approval: Identity,
    compact: String,
    submission: String,
    approval_report: String,
    executor_report: String,
    arrival: Arrival,
    child_requests: BTreeMap<String, usize>,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Arrival {
    reviewer: String,
    target: String,
    review_turn: String,
    body_sha256: String,
    wrapper_sha256: String,
}

#[derive(Deserialize)]
struct Receipt {
    first: First,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct ExceptionFirst {
    case: String,
    root: String,
    latest: Identity,
    reviewer: Identity,
    submission: String,
    exception: Notice,
    all_child_requests: BTreeMap<String, usize>,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Notice {
    exception_id: String,
    raw: String,
    payload: ExceptionIdentity,
}

// Only identity is used here; branch-specific typed outcome/error-budget checks
// run in the fixture. The complete model-visible bytes are still compared.
#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct ExceptionIdentity {
    reviewer_id: String,
    turn_id: String,
    #[serde(deserialize_with = "required_nullable")]
    input_id: Option<String>,
    terminal_sequence: u64,
    target_agent_id: String,
    feedback_message_id: String,
}

#[derive(Deserialize)]
struct ExceptionReceipt {
    first: ExceptionFirst,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct ExceptionChecked {
    first: ExceptionFirst,
    submission_after: String,
    exception_after: Notice,
    latest_after: Identity,
    all_child_requests_after: BTreeMap<String, usize>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReopenedReceipt {
    first: First,
    exception_reopens: Vec<ExceptionChecked>,
    child_requests_after: BTreeMap<String, usize>,
}

fn receipt(state: &LiveState, note: &str) -> Result<Receipt> {
    evidence(state, note)
}

fn evidence<T: serde::de::DeserializeOwned>(state: &LiveState, note: &str) -> Result<T> {
    let rows = state
        .observations
        .iter()
        .filter(|row| row.note == note && row.accepted)
        .collect::<Vec<_>>();
    ensure!(
        rows.len() == 1,
        "expected one committed phase checkpoint {note}, got {}",
        rows.len()
    );
    serde_json::from_value(
        rows[0]
            .receipt
            .clone()
            .context("review checkpoint lacks receipt")?,
    )
    .context("decode required phase evidence")
}

pub(super) fn check_first(state: &LiveState) -> Result<()> {
    ensure!(
        state.failures.is_empty(),
        "review fixture rejected a request"
    );
    for note in FIRST_NOTES {
        ensure!(
            state
                .observations
                .iter()
                .filter(|row| row.note == note && row.accepted)
                .count()
                == 1,
            "missing/duplicate required review scene checkpoint {note}"
        );
    }
    ensure!(
        state.review_gates.len() == 4
            && state
                .review_gates
                .iter()
                .all(|gate| gate.arrived && gate.released),
        "review scene did not exercise and release all four real response gates"
    );
    let first = receipt(state, "rf-normal-compact-complete")?.first;
    for case in ["busy", "changed", "closed"] {
        let first: ExceptionReceipt = evidence(state, &format!("rf-{case}-complete"))?;
        let first = first.first;
        let payload = &first.exception.payload;
        let decoded: ExceptionIdentity = serde_json::from_str(&first.exception.raw)?;
        ensure!(
            first.case == case
                && !first.root.is_empty()
                && !first.submission.is_empty()
                && payload == &decoded
                && payload.reviewer_id == first.reviewer.child_id
                && payload.turn_id == first.reviewer.turn_id
                && payload.input_id == first.reviewer.input_id
                && payload.terminal_sequence == first.reviewer.commit_sequence
                && payload.target_agent_id == first.latest.child_id
                && first.exception.exception_id
                    == format!(
                        "studio.review-exception.{}:{}:{}:{}:{}:{}:{}",
                        payload.reviewer_id.len(),
                        payload.reviewer_id,
                        payload.turn_id.len(),
                        payload.turn_id,
                        payload.terminal_sequence,
                        payload.target_agent_id.len(),
                        payload.target_agent_id
                    )
                && payload.feedback_message_id
                    == format!(
                        "studio.review.{}:{}:{}:{}:{}",
                        payload.reviewer_id.len(),
                        payload.reviewer_id,
                        payload.turn_id.len(),
                        payload.turn_id,
                        payload.terminal_sequence
                    ),
            "exception evidence lost original payload bytes/bound terminal/target identity"
        );
    }
    for identity in [&first.executor, &first.reviewer, &first.approval] {
        ensure!(
            !identity.child_id.is_empty()
                && !identity.turn_id.is_empty()
                && identity.commit_sequence > 0,
            "phase evidence lacks committed child identity"
        );
    }
    ensure!(
        !first.root.is_empty()
            && !first.submission.is_empty()
            && !first.approval_report.is_empty()
            && !first.executor_report.is_empty()
            && first.reviewer.child_id != first.approval.child_id
            && first.reviewer.child_id != first.executor.child_id
            && first.arrival.target == first.executor.child_id
            && first.arrival.reviewer == first.reviewer.child_id
            && first.arrival.review_turn == first.reviewer.turn_id
            && first.arrival.body_sha256.starts_with("sha256:")
            && first.arrival.wrapper_sha256.starts_with("sha256:"),
        "normal phase identities/content arrival are not bound"
    );
    Ok(())
}

fn child_counts(state: &LiveState) -> BTreeMap<String, usize> {
    let mut counts = BTreeMap::new();
    for row in state
        .observations
        .iter()
        .filter(|row: &&Observation| row.marker.starts_with("[[delegation:child:"))
    {
        *counts.entry(row.marker.clone()).or_default() += 1;
    }
    counts
}

pub(super) fn check_reopened(first: &LiveState, reopened: &LiveState) -> Result<()> {
    check_first(first)?;
    ensure!(
        reopened.failures.is_empty(),
        "reopened fixture has failures"
    );
    let aggregate: ReopenedReceipt = evidence(reopened, "rf-reopen-complete")?;
    ensure!(
        receipt(first, "rf-normal-compact-complete")?.first == aggregate.first,
        "reopened original submitted report bytes/target completion changed"
    );
    ensure!(
        aggregate.exception_reopens.len() == 3,
        "aggregate reopen omitted exception root queries"
    );
    for case in ["busy", "changed", "closed"] {
        let original: ExceptionReceipt = evidence(first, &format!("rf-{case}-complete"))?;
        let checked: ExceptionChecked = evidence(reopened, &format!("rf-reopen-{case}-checked"))?;
        ensure!(
            checked.first == original.first
                && checked.submission_after == original.first.submission
                && checked.exception_after == original.first.exception
                && checked.latest_after == original.first.latest
                && checked.all_child_requests_after == child_counts(first)
                && aggregate
                    .exception_reopens
                    .iter()
                    .filter(|proof| *proof == &checked)
                    .count()
                    == 1,
            "public exception reopen lost original bytes/identities/latest Turn or added child requests"
        );
    }
    ensure!(
        aggregate.child_requests_after == child_counts(first),
        "aggregate child request proof changed"
    );
    ensure!(
        child_counts(first) == child_counts(reopened),
        "normal GUI reopen invoked another child provider request"
    );
    Ok(())
}
