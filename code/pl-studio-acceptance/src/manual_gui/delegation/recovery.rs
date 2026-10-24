//! Stage checks consume actual provider observations after each real GUI exit.
//! They never activate children or write product state.

use anyhow::{Context, Result, ensure};
use pl_provider_fixture::delegation::{CLOSED_SEND_ACTIVATION_ERROR, LiveState, Observation};
use serde::{Deserialize, de::DeserializeOwned};

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Route {
    account_id: String,
    model_id: String,
    effort: Option<String>,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Evaluation {
    agent_id: String,
    parent_agent_id: String,
    model: Route,
    profile_id: String,
    mode: String,
    preference: String,
    turn_id: String,
    revision: u64,
    outcome: String,
    quality: Option<u8>,
    instruction_following: Option<u8>,
    comment: String,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Child {
    agent_id: String,
    profile_id: String,
    model: Route,
    message_sequence: u64,
    turn_id: String,
    commit_sequence: u64,
    evaluation: Evaluation,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct Close {
    target: String,
    lifecycle: Lifecycle,
    workspace_disposition: String,
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum Lifecycle {
    Closed,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct First {
    root_agent_id: String,
    executor: Child,
    reviewer: Child,
    reviewer_close: Close,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Sent {
    target: String,
    message_id: String,
    sequence: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClosedSend {
    call_id: String,
    tool: String,
    target: String,
    tool_error: String,
    provider_requests_before: usize,
    provider_requests_after: usize,
    before: ClosedState,
    after: ClosedState,
}

#[derive(Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct ClosedState {
    target: String,
    parent_agent_id: String,
    model: Route,
    turn_id: String,
    lifecycle: Lifecycle,
    pending_inputs: usize,
    running_tasks: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClosedDispatch {
    call_id: String,
    tool: String,
    target: String,
    before: ClosedState,
    provider_requests_before: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Reopened {
    root_agent_id: String,
    executor: Child,
    initial_reviewer: Child,
    reviewer: Child,
    continuation: Sent,
    closed_send: ClosedSend,
    close_receipts: Vec<Close>,
}

fn checkpoint<'a>(state: &'a LiveState, note: &str) -> Result<&'a Observation> {
    let mut rows = state
        .observations
        .iter()
        .filter(|row| row.note == note && row.accepted);
    let row = rows
        .next()
        .with_context(|| format!("recovery phase incomplete: missing {note}"))?;
    ensure!(
        rows.next().is_none(),
        "recovery checkpoint {note} was repeated"
    );
    Ok(row)
}

fn receipt<T: DeserializeOwned>(state: &LiveState, note: &str) -> Result<T> {
    serde_json::from_value(
        checkpoint(state, note)?
            .receipt
            .clone()
            .context("recovery checkpoint lacks real receipt evidence")?,
    )
    .context("decode recovery stage receipt")
}

fn child(state: &LiveState, root: &str, child: &Child, note: &str) -> Result<()> {
    ensure!(
        !child.agent_id.trim().is_empty()
            && !child.turn_id.trim().is_empty()
            && child.message_sequence > 0
            && child.commit_sequence > 0,
        "recovery child lacks real accepted/committed identity"
    );
    let evaluation = &child.evaluation;
    ensure!(
        evaluation.agent_id == child.agent_id
            && evaluation.parent_agent_id == root
            && evaluation.model == child.model
            && evaluation.profile_id == child.profile_id
            && evaluation.turn_id == child.turn_id
            && evaluation.mode == "automatic"
            && evaluation.preference == "balanced"
            && evaluation.outcome == "passed",
        "recovery evaluation does not bind the frozen child/final Turn/root policy"
    );
    let row = checkpoint(state, note)?;
    let alias = if child.model.account_id.ends_with("-a") {
        "a"
    } else {
        "b"
    };
    ensure!(
        row.model == child.model.model_id
            && row.endpoint_alias == alias
            && row.actual_effort == child.model.effort
            && row.expected_account_id.as_deref() == Some(&child.model.account_id),
        "recovery actual completion does not match the child's frozen route"
    );
    Ok(())
}

fn targeted_requests(state: &LiveState, target: &str) -> usize {
    state
        .observations
        .iter()
        .filter(|row| row.input_target_agent_id.as_deref() == Some(target))
        .count()
}

pub(super) fn check_first(state: &LiveState) -> Result<()> {
    let first: First = receipt(state, "recovery_first_complete")?;
    ensure!(
        !first.root_agent_id.trim().is_empty(),
        "recovery first root identity missing"
    );
    child(
        state,
        &first.root_agent_id,
        &first.executor,
        "recovery_child_initial",
    )?;
    child(
        state,
        &first.root_agent_id,
        &first.reviewer,
        "recovery_child_review_initial",
    )?;
    ensure!(
        first.executor.agent_id != first.reviewer.agent_id
            && first.executor.profile_id == "executor"
            && first.reviewer.profile_id == "reviewer"
            && first.executor.evaluation.revision == 1
            && first.reviewer.evaluation.revision == 1,
        "recovery first did not finish two independent revision-one tasks"
    );
    ensure!(
        first.reviewer_close.target == first.reviewer.agent_id
            && first.reviewer_close.workspace_disposition == "preserve",
        "recovery first reviewer was not explicitly closed"
    );
    ensure!(
        targeted_requests(state, &first.reviewer.agent_id) == 0,
        "recovery first reviewer already received an unexpected continuation"
    );
    ensure!(
        state
            .observations
            .iter()
            .all(|row| row.marker != "[[delegation:recovery-resume]]"
                && row.marker != "[[delegation:child:recovery-repair]]"
                && row.marker != "[[delegation:child:recovery-review-resumed]]"),
        "recovery resume ran before the real first GUI shutdown/restart"
    );
    Ok(())
}

pub(super) fn check_reopened(first_state: &LiveState, state: &LiveState) -> Result<()> {
    check_first(first_state)?;
    ensure!(
        state.observations.len() >= first_state.observations.len()
            && serde_json::to_value(&state.observations[..first_state.observations.len()])?
                == serde_json::to_value(&first_state.observations)?,
        "recovery did not retain the same fixture observations across GUI lifetimes"
    );
    let first: First = receipt(first_state, "recovery_first_complete")?;
    let reopened: Reopened = receipt(state, "recovery_complete")?;
    ensure!(
        reopened.root_agent_id == first.root_agent_id
            && reopened.executor.agent_id == first.executor.agent_id
            && reopened.executor.profile_id == first.executor.profile_id
            && reopened.executor.model == first.executor.model
            && reopened.executor.message_sequence == first.executor.message_sequence
            && reopened.executor.turn_id != first.executor.turn_id
            && reopened.executor.commit_sequence > first.executor.commit_sequence,
        "recovery did not continue the original root/child/frozen route with a new committed Turn"
    );
    child(
        state,
        &first.root_agent_id,
        &reopened.executor,
        "recovery_child_repair",
    )?;
    child(
        state,
        &first.root_agent_id,
        &reopened.reviewer,
        "recovery_child_review_resumed",
    )?;
    ensure!(
        reopened.initial_reviewer == first.reviewer
            && reopened.reviewer.agent_id != first.reviewer.agent_id
            && reopened.reviewer.agent_id != first.executor.agent_id
            && reopened.reviewer.profile_id == "reviewer"
            && reopened.reviewer.evaluation.revision == 1
            && reopened.executor.evaluation.revision == 2
            && reopened.executor.evaluation.created_at == first.executor.evaluation.created_at,
        "recovery reviewer freshness, original record or final revision was not preserved"
    );
    ensure!(
        reopened.continuation.target == first.executor.agent_id
            && !reopened.continuation.message_id.trim().is_empty()
            && reopened.continuation.sequence > first.executor.message_sequence,
        "recovery lacks a new real delivery to the original executor"
    );
    let continuation = checkpoint(state, "recovery_child_repair")?
        .continuation
        .as_ref()
        .context("recovery executor final has no actual continuation input witness")?;
    ensure!(
        continuation.target_agent_id == first.executor.agent_id
            && !continuation.intent.is_empty()
            && continuation.input_sha256.len() == 64
            && continuation.output == "delegation recovery resumed delivery",
        "recovery executor provider input/output witness is incomplete"
    );
    let _ = checkpoint(state, "recovery_explicit_close_rejected")?;
    let dispatch: ClosedDispatch = receipt(state, "recovery-closed-send")?;
    let closed = &reopened.closed_send;
    ensure!(
        closed.target == first.reviewer.agent_id
            && !closed.call_id.trim().is_empty()
            && closed.call_id == dispatch.call_id
            && closed.tool == "send_message"
            && dispatch.tool == closed.tool
            && dispatch.target == closed.target
            && dispatch.before == closed.before
            && dispatch.provider_requests_before == closed.provider_requests_before
            && closed.provider_requests_before == 0
            && closed.provider_requests_after == 0
            && targeted_requests(state, &first.reviewer.agent_id) == 0
            && serde_json::from_str::<Sent>(&closed.tool_error).is_err()
            && serde_json::from_str::<serde_json::Value>(&closed.tool_error).is_err()
            && closed.tool_error == CLOSED_SEND_ACTIVATION_ERROR
            && closed.before == closed.after
            && closed.before.target == first.reviewer.agent_id
            && closed.before.parent_agent_id == first.root_agent_id
            && closed.before.model == first.reviewer.model
            && closed.before.turn_id == first.reviewer.turn_id
            && closed.before.pending_inputs == 0
            && closed.before.running_tasks == 0,
        "recovery explicit-close negative did not return a real error without new target provider requests"
    );
    ensure!(
        reopened.close_receipts.len() == 3
            && reopened.close_receipts.contains(&first.reviewer_close),
        "recovery lost the original explicit close or final close receipts"
    );
    for target in [
        &first.executor.agent_id,
        &first.reviewer.agent_id,
        &reopened.reviewer.agent_id,
    ] {
        ensure!(
            reopened
                .close_receipts
                .iter()
                .filter(|receipt| receipt.target == *target
                    && receipt.workspace_disposition == "preserve")
                .count()
                == 1,
            "recovery final close receipts do not cover each real child exactly once"
        );
    }
    ensure!(
        state
            .observations
            .iter()
            .all(|row| row.marker != "[[delegation:child:recovery-closed-probe]]"),
        "explicitly closed reviewer reached a real provider request after restart"
    );
    Ok(())
}
