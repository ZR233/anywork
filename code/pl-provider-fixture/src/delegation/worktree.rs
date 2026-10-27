//! Five bounded native-product journeys. Every fact comes from a real tool or
//! committed child report; fixture observations only link those facts on reopen.
mod absent;
mod admission;
mod branch_journey;
mod evidence;
mod exec;
mod git;
mod guards;
mod no_head;
mod partial_close;
mod reopen;

use super::{Environment, SHARED_MODEL, flow::*, journeys::Decision, wire::*};
use anyhow::{Context, Result};
use evidence::*;
use git::{Action, Git};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

pub(super) fn run(flow: &Flow<'_>, prompt: &str, environment: &Environment) -> Progress<Decision> {
    let phase = match prompt.lines().next() {
        Some("[[delegation:worktree:directory]]") => "directory",
        Some("[[delegation:worktree:nested]]") => "nested",
        Some("[[delegation:worktree:dirty]]") => "dirty",
        Some("[[delegation:worktree:guards]]") => "guards",
        Some("[[delegation:worktree:reopen]]") => "reopen",
        _ => return Err(anyhow::anyhow!("unknown worktree journey marker").into()),
    };
    tools(
        flow,
        &[
            "exec",
            "wait",
            "get_tool_task",
            "list_agents",
            "spawn_agent",
            "evaluate_agent",
            "close_agent",
            "read_agent_session",
            "send_message",
        ],
    )?;
    let rows: Vec<AgentRow> = flow.read("worktree-root-identity", "list_agents", json!({}))?;
    let roots: Vec<_> = rows.iter().filter(|row| row.parent_id.is_none()).collect();
    require(
        roots.len() == 1,
        "worktree journey requires exactly one actual caller root",
    )?;
    let root = roots[0];
    require(
        root.lifecycle == Lifecycle::Open && !root.id.is_empty(),
        "directory caller root must be Open with a nonempty identity",
    )?;
    require(
        flow.request.model == SHARED_MODEL
            && flow
                .request
                .reasoning
                .as_ref()
                .and_then(|reasoning| reasoning.effort.as_ref())
                .is_none(),
        "worktree root provider request must use the configured shared model without effort",
    )?;
    let evidence = match phase {
        "directory" | "nested" => baseline(flow, &root.id, phase)?,
        "dirty" => admission::run(flow, &root.id)?,
        "guards" => guards::run(flow, &root.id, environment)?,
        "reopen" => reopen::run(flow, environment, &root.id)?,
        _ => return Err(anyhow::anyhow!("unrecognized worktree phase").into()),
    };
    let note = match phase {
        "directory" => "worktree_directory_baseline_complete",
        "nested" => "worktree_nested_baseline_complete",
        "dirty" => "worktree_dirty_admission_complete",
        "guards" => "worktree_cleanup_guards_complete",
        "reopen" => "worktree_reopened_complete",
        _ => return Err(anyhow::anyhow!("unrecognized worktree phase").into()),
    };
    let mut decision = Decision::answer(note, note);
    decision.receipt = Some(
        serde_json::to_value(Receipt {
            root_agent_id: root.id.clone(),
            phase: phase.into(),
            evidence,
        })
        .context("encode final worktree receipt")?,
    );
    Ok(decision)
}

fn tools(flow: &Flow<'_>, names: &[&str]) -> Progress<()> {
    for tool in names {
        if !flow.request.declared(tool) {
            let found = flow.discovered(&format!("worktree-discover-{tool}"), tool)?;
            require(
                found.tool_ids.iter().any(|id| id == tool) && flow.request.declared(tool),
                "worktree journey cannot discover its required real tool",
            )?;
        }
    }
    Ok(())
}

pub(super) fn child_reply(flow: &Flow<'_>, prompt: &str) -> Progress<Option<Decision>> {
    let action = match prompt.lines().next() {
        Some("[[delegation:child:worktree:read]]") => Action::Read,
        Some("[[delegation:child:worktree:dirty]]") => Action::ChildDirty,
        Some("[[delegation:child:worktree:commit]]") => Action::ChildCommit,
        _ => return Ok(None),
    };
    tools(flow, &["exec", "wait", "get_tool_task"])?;
    let expected = prompt
        .lines()
        .find_map(|line| line.strip_prefix("WORKTREE_EXPECTED_HEAD:"))
        .context("worktree child has no captured parent HEAD")?;
    let before = git::capture(flow, "worktree-child-before", Action::Read, &[])?;
    require(
        before.head == expected,
        "child did not start at captured actual caller HEAD",
    )?;
    let evidence = if matches!(action, Action::Read) {
        before
    } else {
        git::capture(flow, "worktree-child-action", action, &[])?
    };
    match action {
        Action::ChildDirty => require(
            evidence.head == expected && evidence.status == "?? fixture-child-dirty.txt\n",
            "dirty guard child did not retain its single synthetic untracked file",
        )?,
        Action::ChildCommit => require(
            evidence.head != expected && evidence.status.is_empty(),
            "unmerged guard child did not produce its own clean commit",
        )?,
        Action::Read => {}
        _ => return Err(anyhow::anyhow!("invalid worktree child action").into()),
    }
    let text = serde_json::to_string(&evidence).context("encode actual child Git evidence")?;
    Ok(Some(Decision::answer("worktree_child_evidence", &text)))
}

fn routes(flow: &Flow<'_>) -> Progress<(Route, Route)> {
    let models = flow.models()?;
    Ok((
        select(&models, "-a", SHARED_MODEL)?,
        select(&models, "-b", SHARED_MODEL)?,
    ))
}

fn marker(mode: &str, parent: &Git) -> String {
    format!(
        "[[delegation:child:worktree:{mode}]]\nWORKTREE_EXPECTED_HEAD:{}",
        parent.head
    )
}

fn child_report(flow: &Flow<'_>, label: &str, child: &Spawn) -> Progress<(Report, Git)> {
    for retry in 0..8 {
        let matching: Vec<_> = flow
            .request
            .reports()?
            .into_iter()
            .filter(|report| report.child_id == child.agent_id && report.commit_sequence > 0)
            .collect();
        require(
            matching.len() <= 1,
            "fresh worktree child has multiple terminal reports",
        )?;
        if let Some(report) = matching.into_iter().next() {
            report.completed()?;
            let git: Git =
                serde_json::from_str(&report.message).context("decode child-owned Git evidence")?;
            require(
                git.kind == "worktreeEvidence",
                "child report is not actual Git evidence",
            )?;
            let checked = flow.report(label, child, &report.message, 0)?;
            return Ok((checked, git));
        }
        let _ = flow.raw(
            &format!("worktree-{label}-wait-{retry}"),
            "wait",
            json!({"taskIds":[],"timeoutMs":300000}),
        )?;
    }
    Err(anyhow::anyhow!("no completed worktree report after eight bounded waits").into())
}

fn observe_child(flow: &Flow<'_>, label: &str, root: &str, child: Spawn) -> Progress<Child> {
    let (report, git) = child_report(flow, label, &child)?;
    let evaluation = flow.evaluate(
        &format!("{label}-evaluation"),
        &child,
        &report,
        0,
        "Observed synthetic Git execution only; no code-review quality rating.",
        "notRated",
    )?;
    require(
        evaluation.evaluation.parent_agent_id == root
            && evaluation.evaluation.revision == 1
            && evaluation.write == "created"
            && evaluation.evaluation.quality.is_none()
            && evaluation.evaluation.instruction_following.is_none(),
        "worktree evaluation lost actual parent or invented a quality score",
    )?;
    Ok(Child {
        spawn: child.into(),
        report: TerminalReport::observed(report)?,
        git,
        evaluation: evaluation.evaluation,
        checkout_history: Vec::new(),
    })
}

fn baseline(flow: &Flow<'_>, root: &str, phase: &str) -> Progress<Evidence> {
    let mut evidence = Evidence::default();
    let initial = git::capture(flow, "baseline-before", Action::Read, &[])?;
    require(
        initial.status.is_empty(),
        "worktree baseline parent is dirty",
    )?;
    let parent = if phase == "nested" {
        require(
            initial.path != initial.primary_path,
            "nested GUI root is not a real worktree",
        )?;
        let parent = git::capture(flow, "baseline-parent-commit", Action::NestedCommit, &[])?;
        require(
            parent.path != parent.primary_path
                && parent.head != parent.primary_head
                && parent.status.is_empty(),
            "nested caller commit did not distinguish actual HEAD from primary HEAD",
        )?;
        parent
    } else {
        initial.clone()
    };
    evidence.checkpoint("before", initial);
    evidence.checkpoint("parent", parent.clone());
    let (a, b) = routes(flow)?;
    let child = flow.spawn(
        "baseline-executor",
        "worktree_executor",
        Some(&a),
        &marker("read", &parent),
        None,
    )?;
    let mut child = observe_child(flow, "baseline-executor", root, child)?;
    git::new_detached_child(&parent, &child.git)?;
    require(
        child.git.path != parent.path
            && child.git.head == parent.head
            && child.git.common_dir == parent.common_dir
            && child.git.status.is_empty(),
        "worktree child did not derive a clean isolated actual caller HEAD",
    )?;
    if phase == "directory" {
        branch_journey::create(flow, &mut child)?;
    }
    let before_review = git::capture(
        flow,
        "baseline-before-review",
        Action::Read,
        std::slice::from_ref(&child.git.path),
    )?;
    git::retained(&parent, child.checkout(), &before_review)?;
    let reviewer = flow.spawn(
        "baseline-reviewer",
        "reviewer",
        Some(&b),
        &marker("read", &parent),
        Some(&child.spawn.agent_id),
    )?;
    let reviewer = observe_child(flow, "baseline-reviewer", root, reviewer)?;
    require(
        git::same_identity(&reviewer.git, child.checkout())
            && reviewer.git.head == child.checkout().head
            && reviewer.git.branch == child.checkout().branch
            && reviewer.git.detached == child.checkout().detached,
        "reviewer did not borrow the target actual assignment",
    )?;
    let after_review = git::capture(
        flow,
        "baseline-after-review",
        Action::Read,
        std::slice::from_ref(&child.git.path),
    )?;
    require(
        before_review.worktrees == after_review.worktrees
            && before_review.refs == after_review.refs,
        "review created a worktree or ref",
    )?;
    evidence.checkpoint("before-review", before_review);
    evidence.checkpoint("after-review", after_review);
    let closed_review = successful_close(flow, "baseline-close-reviewer", &reviewer, &parent)?;
    require(
        closed_review
            .git
            .targets
            .iter()
            .any(|target| target.path == reviewer.git.path && target.exists),
        "closing reviewer removed the borrowed directory",
    )?;
    evidence.closes.push(closed_review);
    if phase == "directory" {
        branch_journey::finish(flow, &mut child)?;
    }
    let closed_child = successful_close(flow, "baseline-close-executor", &child, &parent)?;
    git::removed(&parent, child.checkout(), &closed_child.git)?;
    evidence.closes.push(closed_child);
    evidence.children.extend([child, reviewer]);
    Ok(evidence)
}

fn successful_close(flow: &Flow<'_>, label: &str, child: &Child, parent: &Git) -> Progress<Close> {
    let spawn = child.spawn.as_spawn();
    let checkout = child.checkout();
    let before = git::capture(
        flow,
        &format!("{label}-before"),
        Action::Read,
        std::slice::from_ref(&checkout.path),
    )?;
    if spawn.profile_id == "worktree_executor" {
        git::retained(parent, checkout, &before)?;
    }
    let result = flow.close(label, &spawn)?;
    require(
        result.agents.len() == 1,
        "close affected an unexpected target tree",
    )?;
    let expected = result
        .agents
        .iter()
        .find(|entry| entry.agent_id == spawn.agent_id)
        .context("close omitted exact target")?;
    let owned = spawn.profile_id == "worktree_executor";
    require(
        if owned {
            matches!(&expected.worktree_cleanup, WorktreeCleanup::Removed { path } if path == &checkout.path)
        } else {
            expected.worktree_cleanup == WorktreeCleanup::NotApplicable
        },
        "close returned the wrong ownership cleanup result",
    )?;
    let tool_output = flow.raw(label, "close_agent", json!({"target":spawn.agent_id}))?;
    let git = git::capture(
        flow,
        &format!("{label}-git"),
        Action::Read,
        std::slice::from_ref(&checkout.path),
    )?;
    git::parent_unchanged(parent, &git)?;
    git::close_preserved(&before, &git, owned.then_some(checkout.path.as_str()))?;
    Ok(Close {
        label: label.into(),
        force: false,
        result,
        tool_output,
        owner_error: None,
        before: Some(before),
        git,
    })
}
