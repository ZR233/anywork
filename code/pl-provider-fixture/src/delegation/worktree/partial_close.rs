//! A real failed cleanup still permanently seals execution, before a force retry.
use super::*;

#[derive(Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
struct ClosedState {
    root_agent_id: String,
    target: String,
    model: Route,
    turn_id: String,
    lifecycle: Lifecycle,
    pending_inputs: usize,
    running_tasks: usize,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Dispatch {
    call_id: String,
    before: ClosedState,
    provider_requests_before: usize,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct PartialSendEvidence {
    close_call_id: String,
    failure: no_head::FailedCallEvidence,
    before: ClosedState,
    after: ClosedState,
    provider_requests_before: usize,
    provider_requests_after: usize,
}

pub(super) fn verify(
    flow: &Flow<'_>,
    environment: &Environment,
    root: &str,
    label: &str,
    child: &Child,
    close: &Close,
) -> Progress<PartialSendEvidence> {
    let target = &child.spawn.agent_id;
    require(
        close.result.target == *target
            && close.result.error.is_some()
            && close.result.agents.len() == 1
            && close.result.agents[0].agent_id == *target
            && close.result.agents[0].execution_closed
            && matches!(&close.result.agents[0].worktree_cleanup,
            WorktreeCleanup::Failed { path: Some(path), .. } if path == &child.git.path),
        "partial-close send probe lacks the exact sealed execution/failed cleanup receipt",
    )?;
    let route: Detail = flow.read(
        &format!("{label}-route"),
        "get_delegation_model",
        json!({"accountId":child.spawn.model.account_id,"modelId":child.spawn.model.model_id}),
    )?;
    require(
        route.account_id == child.spawn.model.account_id && route.available,
        "partial-close probe cannot use an unavailable route as closed evidence",
    )?;
    let rows: Vec<AgentRow> = flow.read(&format!("{label}-before"), "list_agents", json!({}))?;
    let before = state(flow, &format!("{label}-before-history"), root, child, &rows)?;
    let mut expectation = completion_expectation(&child.spawn.model)?;
    expectation.continuation = Some(ContinuationTag {
        target_agent_id: target.clone(),
        intent: format!("{}-{label}", flow.prefix),
    });
    let message = format!(
        "{}\nDELEGATION_EXPECT_COMPLETION:{}",
        marker("read", child.checkout()),
        serde_json::to_string(&expectation).context("encode partial-close send expectation")?
    );
    let arguments = json!({"target":target,"message":message});
    let call_id = format!("{}-{label}", flow.prefix);
    // Capture before the actual send, not after a later wait/status query.
    match flow.raw(label, "send_message", arguments.clone()) {
        Err(Stop::Call(mut decision)) => {
            decision.receipt = Some(
                serde_json::to_value(Dispatch {
                    call_id,
                    before,
                    provider_requests_before: environment.targeted_requests(target)?,
                })
                .context("encode partial-close dispatch evidence")?,
            );
            return Err(Stop::Call(decision));
        }
        result => {
            let _ = result?;
        }
    }
    flow.rejected(
        label,
        "send_message",
        arguments.clone(),
        super::super::PERMANENTLY_CLOSED_SEND_PREFIX,
    )?;
    let failure = no_head::observed_failure(flow, label, "send_message", arguments)?;
    require(
        super::super::is_permanently_closed_send_error(&failure.output),
        "partial-close send did not return the exact permanent-close failure",
    )?;
    let dispatch = {
        let observations = environment
            .observations
            .lock()
            .map_err(|_| anyhow::anyhow!("partial-close observations poisoned"))?;
        let mut dispatches = observations
            .iter()
            .filter(|row| row.accepted && row.note == label)
            .map(|row| {
                serde_json::from_value::<Dispatch>(
                    row.receipt
                        .clone()
                        .context("partial-close dispatch lost its pre-call receipt")?,
                )
                .context("decode partial-close dispatch receipt")
            })
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .filter(|dispatch| {
                dispatch.call_id == call_id
                    && dispatch.before.root_agent_id == root
                    && dispatch.before.target == *target
            })
            .collect::<Vec<_>>();
        require(
            dispatches.len() == 1,
            "partial-close dispatch identity is missing/duplicated",
        )?;
        dispatches
            .pop()
            .context("partial-close has no original dispatch")?
    };
    require(
        dispatch.before == before,
        "partial-close send pre-call identity/Turn changed",
    )?;
    let rows: Vec<AgentRow> = flow.read(&format!("{label}-after"), "list_agents", json!({}))?;
    let after = state(flow, &format!("{label}-after-history"), root, child, &rows)?;
    let provider_requests_after = environment.targeted_requests(target)?;
    require(
        after == before && provider_requests_after == dispatch.provider_requests_before,
        "failed cleanup allowed a new input/Turn/task or child provider request",
    )?;
    Ok(PartialSendEvidence {
        close_call_id: format!("{}-{}", flow.prefix, close.label),
        failure,
        before,
        after,
        provider_requests_before: dispatch.provider_requests_before,
        provider_requests_after,
    })
}

fn state(
    flow: &Flow<'_>,
    label: &str,
    root: &str,
    child: &Child,
    rows: &[AgentRow],
) -> Progress<ClosedState> {
    require(
        rows.iter().filter(|row| row.parent_id.is_none()).count() == 1
            && rows.iter().any(|row| {
                row.id == root && row.parent_id.is_none() && row.lifecycle == Lifecycle::Open
            }),
        "partial-close probe is not in the original live caller tree",
    )?;
    let row = rows
        .iter()
        .find(|row| row.id == child.spawn.agent_id)
        .context("partial-close target disappeared")?;
    require(
        row.parent_id.as_deref() == Some(root)
            && row.lifecycle == Lifecycle::Closed
            && row.frozen_model.as_ref() == Some(&child.spawn.model)
            && row.pending_inputs == 0
            && row.running_tasks == 0,
        "partial-close target is not the exact closed child/frozen route with no pending work",
    )?;
    let spawn = child.spawn.as_spawn();
    flow.latest_completed_turn(
        label,
        LatestTurnCheck {
            row,
            child: &spawn,
            turn_id: &child.report.turn.turn_id,
            history: TurnHistory::Always,
        },
    )?;
    Ok(ClosedState {
        root_agent_id: root.into(),
        target: row.id.clone(),
        model: child.spawn.model.clone(),
        turn_id: child.report.turn.turn_id.clone(),
        lifecycle: Lifecycle::Closed,
        pending_inputs: row.pending_inputs,
        running_tasks: row.running_tasks,
    })
}
