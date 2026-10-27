//! Three fixed external response gates, not a scheduler or a product injection API.
use super::{
    Environment, flow::*, journeys::Decision, review_feedback as feedback, review_wire::*, wire::*,
};
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Default, Debug)]
struct Gate {
    arrived: CancellationToken,
    released: CancellationToken,
}

#[derive(Clone, Default, Debug)]
pub(super) struct Gates {
    busy: Gate,
    changed: Gate,
    closed: Gate,
    target: Gate,
    attempts: Arc<Mutex<BTreeMap<String, Attempt>>>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GateSnapshot {
    pub name: String,
    pub arrived: bool,
    pub released: bool,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Attempt {
    target: String,
    parent: String,
    previous_turn: String,
    accepted_own_message: Option<String>,
    provider_requests_before: usize,
    target_gate_held_at_review_release: bool,
    lifecycle: String,
    pending_inputs: usize,
    running_tasks: usize,
    observed_turn: Option<String>,
}

impl Gates {
    fn gate(&self, name: &str) -> Result<&Gate> {
        match name {
            "rf-review-busy" => Ok(&self.busy),
            "rf-review-changed" => Ok(&self.changed),
            "rf-review-closed" => Ok(&self.closed),
            "rf-target-busy" => Ok(&self.target),
            _ => anyhow::bail!("unknown fixed review gate {name}"),
        }
    }

    pub fn snapshot(&self) -> Vec<GateSnapshot> {
        [
            "rf-review-busy",
            "rf-review-changed",
            "rf-review-closed",
            "rf-target-busy",
        ]
        .into_iter()
        .map(|name| {
            let gate = match name {
                "rf-review-busy" => &self.busy,
                "rf-review-changed" => &self.changed,
                "rf-review-closed" => &self.closed,
                _ => &self.target,
            };
            GateSnapshot {
                name: name.into(),
                arrived: gate.arrived.is_cancelled(),
                released: gate.released.is_cancelled(),
            }
        })
        .collect()
    }

    pub fn release(&self, name: &str) -> Result<()> {
        let gate = self.gate(name)?;
        ensure!(
            gate.arrived.is_cancelled(),
            "gate {name} has no actual arrived response"
        );
        gate.released.cancel();
        Ok(())
    }

    pub async fn before_record(&self, note: &str, stopping: &CancellationToken) -> Result<()> {
        let gate = if let Some(case) = note.strip_prefix("rf-wait-review-") {
            Some(self.gate(&format!("rf-review-{case}"))?)
        } else if note == "rf-wait-target-busy" {
            Some(&self.target)
        } else {
            None
        };
        if let Some(gate) = gate {
            wait(&gate.arrived, stopping, "actual provider response arrival").await?;
        }
        Ok(())
    }

    pub async fn after_record(&self, note: &str, stopping: &CancellationToken) -> Result<()> {
        let gate = if let Some(name) = note
            .strip_suffix("-arrived")
            .filter(|name| name.starts_with("rf-review-"))
        {
            Some(self.gate(name)?)
        } else if note == "rf-target-busy-arrived" {
            Some(&self.target)
        } else {
            None
        };
        if let Some(gate) = gate {
            ensure!(
                !gate.arrived.is_cancelled(),
                "single-use review gate received duplicate response"
            );
            gate.arrived.cancel();
            wait(&gate.released, stopping, "review/target gate release").await?;
        }
        Ok(())
    }
}

async fn wait(token: &CancellationToken, stopping: &CancellationToken, label: &str) -> Result<()> {
    tokio::select! {
        () = stopping.cancelled() => anyhow::bail!("fixture stopped while waiting for {label}"),
        () = token.cancelled() => Ok(()),
        () = tokio::time::sleep(Duration::from_secs(180)) => anyhow::bail!("bounded external wait timed out: {label}"),
    }
}

pub(super) fn run(flow: &Flow<'_>, environment: &Environment, case: &str) -> Progress<Decision> {
    super::review_child::require_no_leak(flow.request)?;
    let (execution, review_route) = feedback::routes(flow)?;
    let (executor, initial) = feedback::executor(flow, &execution, case)?;
    let reviewer = feedback::reviewer(
        flow,
        environment,
        "rf-reviewer",
        &review_route,
        &executor,
        case,
        true,
    )?;
    // This provider response is withheld until the reviewer has really reached
    // its external response gate; list_agents then observes the actual target.
    let _: Vec<AgentRow> =
        flow.read(&format!("rf-wait-review-{case}"), "list_agents", json!({}))?;
    let own_input = if case == "busy" || case == "changed" {
        Some(flow.send("rf-own-work", &executor, &format!("[[delegation:child:rf-executor:{case}-work]]\nA genuinely new parent-owned requirement, not feedback. No architecture changes."))?)
    } else {
        None
    };
    let changed = if case == "changed" {
        Some(
            flow.continued_report(
                "rf-own-completion",
                ContinuationReport {
                    child: &executor,
                    previous: &initial,
                    input: own_input.as_ref().context("changed input missing")?,
                    previous_sequence: executor
                        .message_sequence
                        .context("spawn delivery sequence missing")?,
                    output: "controlled target work complete",
                },
            )?,
        )
    } else {
        None
    };
    if case == "closed" {
        flow.close("rf-close-before-review", &executor)?;
    }
    let rows: Vec<AgentRow> = flow.read(
        if case == "busy" {
            "rf-wait-target-busy"
        } else {
            "rf-target-before-release"
        },
        "list_agents",
        json!({}),
    )?;
    let row = rows
        .iter()
        .find(|row| row.id == executor.agent_id)
        .context("interleaved target missing")?;
    require(
        row.frozen_model.as_ref() == Some(&executor.model),
        "interleaved target changed route",
    )?;
    match case {
        "busy" => require(
            row.lifecycle == Lifecycle::Open
                && row
                    .last_turn
                    .as_ref()
                    .is_some_and(|turn| matches!(turn.state, TurnState::Running)),
            "busy gate did not prove an actual running target",
        )?,
        "changed" => {
            let changed = changed.as_ref().context("changed completion absent")?;
            require(
                changed.turn_id != initial.turn_id
                    && row.lifecycle == Lifecycle::Open
                    && row.pending_inputs == 0
                    && row.running_tasks == 0,
                "changed input did not complete a new idle delivery",
            )?;
            flow.latest_completed_turn(
                "rf-changed-latest",
                LatestTurnCheck {
                    row,
                    child: &executor,
                    turn_id: &changed.turn_id,
                    history: TurnHistory::Always,
                },
            )?;
        }
        "closed" => require(
            row.lifecycle == Lifecycle::Closed && row.pending_inputs == 0 && row.running_tasks == 0,
            "successful close did not produce real closed state",
        )?,
        _ => return Err(anyhow::anyhow!("unknown fixed interleaving").into()),
    }
    {
        let mut attempts = environment
            .review_gates
            .attempts
            .lock()
            .map_err(|_| anyhow::anyhow!("interleaving evidence lock poisoned"))?;
        let attempt = attempts.entry(case.into()).or_insert_with(|| Attempt {
            target: executor.agent_id.clone(),
            parent: row.parent_id.clone().unwrap_or_default(),
            previous_turn: initial.turn_id.clone(),
            accepted_own_message: own_input
                .as_ref()
                .map(|input| input.receipt.message_id.clone()),
            provider_requests_before: 0,
            target_gate_held_at_review_release: false,
            lifecycle: format!("{:?}", row.lifecycle),
            pending_inputs: row.pending_inputs,
            running_tasks: row.running_tasks,
            observed_turn: row.last_turn.as_ref().map(|turn| turn.turn_id.clone()),
        });
        require(
            attempt.target == executor.agent_id
                && !attempt.parent.is_empty()
                && row.parent_id.as_deref() == Some(attempt.parent.as_str())
                && attempt.previous_turn == initial.turn_id
                && attempt.accepted_own_message.as_deref()
                    == own_input
                        .as_ref()
                        .map(|input| input.receipt.message_id.as_str()),
            "interleaving release evidence belongs to a different target/parent/delivery/input",
        )?;
    }
    // Freeze the count and gate fact together before the first reviewer release.
    // Flow replay reuses the original tool receipts; completing the target's
    // own input must not erase its earlier held-state proof or replace the count.
    if !environment
        .review_gates
        .gate(&format!("rf-review-{case}"))?
        .released
        .is_cancelled()
    {
        let count = target_requests(environment, case)?;
        let target_gate_held = case == "busy"
            && environment.review_gates.target.arrived.is_cancelled()
            && !environment.review_gates.target.released.is_cancelled();
        require(
            case != "busy" || target_gate_held,
            "busy target gate was not held at the original reviewer release",
        )?;
        {
            let mut attempts = environment
                .review_gates
                .attempts
                .lock()
                .map_err(|_| anyhow::anyhow!("interleaving evidence lock poisoned"))?;
            let attempt = attempts.get_mut(case).context("attempt missing")?;
            attempt.provider_requests_before = count;
            attempt.target_gate_held_at_review_release = target_gate_held;
        }
        environment
            .review_gates
            .release(&format!("rf-review-{case}"))?;
    }
    let attempt = environment
        .review_gates
        .attempts
        .lock()
        .map_err(|_| anyhow::anyhow!("interleaving evidence lock poisoned"))?
        .get(case)
        .cloned()
        .context("release evidence absent")?;
    require(
        attempt.target == executor.agent_id && !attempt.parent.is_empty(),
        "interleaving identity changed",
    )?;
    let review_report = feedback::review_report(flow, "rf-held-review", &reviewer, &executor)?;
    let review = review_report
        .review
        .as_ref()
        .context("held review missing")?;
    let baseline = review.require_binding(&review_report, &executor)?;
    require(
        baseline.turn_id == initial.turn_id && baseline.input_id == initial.input_id,
        "held reviewer did not retain original frozen delivery",
    )?;
    match (&review.forward, case) {
        (
            Forward::Rejected {
                message_id,
                reason: ForwardReason::TargetChanged,
            },
            "busy" | "changed",
        ) if !message_id.is_empty() => {}
        // The original Running target can fail validate_idle before the later
        // comparison. Consume its frozen release-time proof, not current gate
        // state: subsequent Flow replay may already have completed its own input.
        (
            Forward::Rejected {
                message_id,
                reason: ForwardReason::AdmissionRejected(reason),
            },
            "busy",
        ) if !message_id.is_empty()
            && attempt.target_gate_held_at_review_release
            && matches!(reason.as_slice(), [operation, source]
                if operation == "Studio resource operation failed: validate original reviewed delivery"
                    && source == "child still has running work, pending input, interaction or permission") =>
            {}
        (
            Forward::Rejected {
                message_id,
                reason: ForwardReason::TargetUnavailable,
            },
            "closed",
        ) if !message_id.is_empty() => {}
        (
            Forward::Rejected {
                message_id,
                reason: ForwardReason::AdmissionRejected(reason),
            },
            "closed",
        ) if !message_id.is_empty() && !reason.is_empty() => {}
        _ => {
            return Err(anyhow::anyhow!(
                "interleaved feedback did not clearly reject the changed/busy/closed target: {:?}",
                review.forward
            )
            .into());
        }
    }
    require(
        review.disposition != Disposition::Approved
            && target_requests(environment, case)? == attempt.provider_requests_before,
        "rejected feedback added target model requests",
    )?;
    require(
        !environment
            .review_wrappers
            .lock()
            .map_err(|_| anyhow::anyhow!("wrapper lock poisoned"))?
            .iter()
            .any(|row| row.arrival.target == executor.agent_id),
        "rejected feedback reached target model",
    )?;
    let completed = if case == "busy" {
        environment.review_gates.release("rf-target-busy")?;
        let completed = flow.continued_report(
            "rf-own-completion",
            ContinuationReport {
                child: &executor,
                previous: &initial,
                input: own_input.as_ref().context("busy input missing")?,
                previous_sequence: executor.message_sequence.context("spawn sequence absent")?,
                output: "controlled target work complete",
            },
        )?;
        feedback::idle(flow, "rf-own-idle", &executor, &completed)?;
        Some(completed)
    } else {
        changed
    };
    let after: Vec<AgentRow> = flow.read("rf-after-rejected-feedback", "list_agents", json!({}))?;
    let target = after
        .iter()
        .find(|row| row.id == executor.agent_id)
        .context("target absent after rejection")?;
    require(
        target.pending_inputs == 0
            && target.running_tasks == 0
            && target.frozen_model.as_ref() == Some(&executor.model)
            && target.lifecycle
                == if case == "closed" {
                    Lifecycle::Closed
                } else {
                    Lifecycle::Open
                },
        "rejected feedback left new pending target work",
    )?;
    let expected = completed.as_ref().unwrap_or(&initial);
    flow.latest_completed_turn(
        "rf-after-rejection-latest",
        LatestTurnCheck {
            row: target,
            child: &executor,
            turn_id: &expected.turn_id,
            history: TurnHistory::Always,
        },
    )?;
    require(
        target_requests(environment, case)? == attempt.provider_requests_before,
        "feedback rejection/cleanup added a later target request",
    )?;
    require(
        flow.request
            .reports()?
            .iter()
            .filter(|report| {
                report.child_id == executor.agent_id
                    && report.commit_sequence > expected.commit_sequence
            })
            .count()
            == 0,
        "rejected feedback produced an additional target Turn",
    )?;
    flow.close("rf-close-reviewer", &reviewer)?;
    if case != "closed" {
        flow.close("rf-close-executor", &executor)?;
    }
    let mut decision = Decision::answer(
        &format!("rf-{case}-complete"),
        &format!("review feedback {case} complete"),
    );
    decision.receipt = Some(
        json!({"before":attempt,"afterTarget":feedback::Identity::new(expected),"reviewer":feedback::Identity::new(&review_report),"review":review,"providerRequestsAfter":target_requests(environment, case)?,"ownInput":own_input.as_ref().map(|input| &input.receipt),"feedbackAddedProviderRequests":0}),
    );
    Ok(decision)
}

fn target_requests(environment: &Environment, case: &str) -> Result<usize> {
    Ok(feedback::marker_count(
        environment,
        &format!("[[delegation:child:rf-executor:{case}]]"),
    )? + feedback::marker_count(
        environment,
        &format!("[[delegation:child:rf-executor:{case}-work]]"),
    )?)
}
