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

fn receipt(state: &LiveState, note: &str) -> Result<Receipt> {
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
    ensure!(
        receipt(first, "rf-normal-compact-complete")?.first
            == receipt(reopened, "rf-reopen-complete")?.first,
        "reopened original parent report/target completion/accepted receipt changed"
    );
    ensure!(
        child_counts(first) == child_counts(reopened),
        "normal GUI reopen invoked another child provider request"
    );
    Ok(())
}
