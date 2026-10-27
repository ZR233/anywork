//! Reopen links prior observations to freshly read directory and full history.
use super::*;

pub(super) fn run(flow: &Flow<'_>, environment: &Environment, root: &str) -> Progress<Evidence> {
    // Only final receipts are eligible; tool dispatch observations are not state.
    let observed: Vec<(usize, Receipt)> = {
        let observations = environment
            .observations
            .lock()
            .map_err(|_| anyhow::anyhow!("worktree observations poisoned"))?;
        observations
            .iter()
            .filter(|row| {
                row.accepted
                    && matches!(
                        row.note.as_str(),
                        "worktree_directory_baseline_complete" | "worktree_cleanup_guards_complete"
                    )
            })
            .map(|row| {
                let receipt = serde_json::from_value::<Receipt>(
                    row.receipt
                        .clone()
                        .context("final worktree observation has no receipt")?,
                )
                .context("decode observed final receipt")?;
                let expected_phase = if row.note == "worktree_directory_baseline_complete" {
                    "directory"
                } else {
                    "guards"
                };
                require(
                    receipt.phase == expected_phase,
                    "final worktree note/phase association changed",
                )?;
                Ok((row.ordinal, receipt))
            })
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .filter(|(_, receipt)| receipt.root_agent_id == root)
            .collect()
    };
    require(
        observed
            .iter()
            .filter(|(_, receipt)| receipt.phase == "directory")
            .count()
            == 1
            && observed
                .iter()
                .filter(|(_, receipt)| receipt.phase == "guards")
                .count()
                == 1,
        "reopen needs this original root's unique directory and guards final receipts",
    )?;
    let (guards_ordinal, guards) = observed
        .iter()
        .find(|(_, receipt)| receipt.phase == "guards")
        .context("reopen has no original-root guards receipt")?;
    require(
        observed
            .iter()
            .all(|(ordinal, _)| ordinal <= guards_ordinal),
        "guards is not the latest original-root completed baseline",
    )?;
    let checkpoints: Vec<_> = guards
        .evidence
        .checkpoints
        .iter()
        .filter(|checkpoint| checkpoint.label == "parent")
        .collect();
    require(
        checkpoints.len() == 1,
        "guards final receipt needs exactly one real parent checkpoint",
    )?;
    let baseline = &checkpoints[0].git;
    flow.discover()?;
    let parent = git::capture(flow, "reopen-parent", Action::Read, &[])?;
    require(parent.status.is_empty(), "reopened parent is dirty")?;
    git::parent_unchanged(baseline, &parent)?;
    require(
        baseline.refs == parent.refs,
        "reopened refs differ from the original-root guards successor baseline",
    )?;
    let mut evidence = Evidence::default();
    evidence.checkpoint("guards-parent-baseline", baseline.clone());
    for (_, receipt) in observed {
        let Evidence {
            children,
            mut closes,
            not_present,
            ..
        } = receipt.evidence;
        for (index, child) in children.into_iter().enumerate() {
            let label = format!("reopen-{}-{index}", receipt.phase);
            let close_index = closes
                .iter()
                .rposition(|close| close.result.succeeded_for(&child.spawn.agent_id))
                .context("reopen child has no successful final close")?;
            let prior = closes.remove(close_index);
            let rows: Vec<AgentRow> =
                flow.read(&format!("{label}-directory"), "list_agents", json!({}))?;
            require(
                rows.iter().any(|row| {
                    row.id == root && row.parent_id.is_none() && row.lifecycle == Lifecycle::Open
                }),
                "reopened caller identity changed",
            )?;
            let row = rows
                .iter()
                .find(|row| row.id == child.spawn.agent_id)
                .context("reopened closed child is absent")?;
            require(
                row.parent_id.as_deref() == Some(root)
                    && row.lifecycle == Lifecycle::Closed
                    && row.pending_inputs == 0
                    && row.running_tasks == 0
                    && row.frozen_model.as_ref() == Some(&child.spawn.model),
                "reopened child lost closed identity/frozen route or acquired work",
            )?;
            let spawn = child.spawn.as_spawn();
            flow.latest_completed_turn(
                &format!("{label}-history"),
                LatestTurnCheck {
                    row,
                    child: &spawn,
                    turn_id: &child.report.turn.turn_id,
                    history: TurnHistory::Always,
                },
            )?;
            let refused = flow.refused_closed_send(ClosedSendCheck {
                label: &format!("{label}-send"),
                child: &spawn,
                close: &prior.result,
                root,
                turn_id: &child.report.turn.turn_id,
                marker: &marker("read", child.checkout()),
            })?;
            let git = git::capture(
                flow,
                &format!("{label}-git"),
                Action::Read,
                std::slice::from_ref(&child.git.path),
            )?;
            git::parent_unchanged(&parent, &git)?;
            require(
                parent.refs == git.refs,
                "reopen observations changed the verified successor refs",
            )?;
            if child.spawn.profile_id == "worktree_executor" {
                let member = prior
                    .result
                    .agents
                    .iter()
                    .find(|agent| agent.agent_id == child.spawn.agent_id)
                    .context("reopened worktree close omitted its exact target")?;
                match &member.worktree_cleanup {
                    WorktreeCleanup::Removed { path } => {
                        require(path == &child.git.path, "reopened Removed path changed")?;
                        git::removed_site(path, &git)?;
                    }
                    WorktreeCleanup::NotPresent { path, .. } => {
                        require(path == &child.git.path, "reopened NotPresent path changed")?;
                        let case = not_present
                            .iter()
                            .find(|case| case.child_id == child.spawn.agent_id)
                            .context(
                                "reopened NotPresent child has no original physical evidence",
                            )?;
                        absent::verify_reopened(
                            flow,
                            &label,
                            &parent,
                            &child,
                            case,
                            &prior.result,
                        )?;
                    }
                    _ => {
                        return Err(anyhow::anyhow!(
                            "reopened owned worktree has no approved terminal cleanup"
                        )
                        .into());
                    }
                }
            } else if prior
                .result
                .agents
                .iter()
                .find(|agent| agent.agent_id == child.spawn.agent_id)
                .context("review close lost target")?
                .worktree_cleanup
                == WorktreeCleanup::NotApplicable
            {
                // A reviewer whose executor was removed shares that absent path.
                git::removed_site(&child.git.path, &git)?;
            } else {
                return Err(anyhow::anyhow!("reopened reviewer had owned worktree cleanup").into());
            }
            evidence.reopened.push(Reopened {
                child_id: child.spawn.agent_id.clone(),
                turn_id: child.report.turn.turn_id.clone(),
                close: prior.result,
                refused_send: serde_json::from_value(
                    serde_json::to_value(refused).context("encode closed-send evidence")?,
                )
                .context("retain typed closed-send evidence")?,
                git,
            });
        }
    }
    evidence.checkpoint("parent", parent);
    Ok(evidence)
}
