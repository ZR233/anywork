//! Each protection uses a fresh owned worktree. Force retries never grant a
//! second force, replace identity, unlock another owner, or delete a ref.
use super::*;

#[derive(Clone, Copy)]
enum Expected<'a> {
    Dirty,
    Unmerged,
    Borrowed(&'a str),
    Locked,
    Removed,
}

pub(super) fn run(flow: &Flow<'_>, root: &str, environment: &Environment) -> Progress<Evidence> {
    let parent = git::capture(flow, "guards-parent", Action::Read, &[])?;
    require(
        parent.status.is_empty(),
        "cleanup guards must start at a clean parent",
    )?;
    let mut evidence = Evidence::default();
    evidence.checkpoint("parent", parent.clone());
    let (a, b) = routes(flow)?;
    for (label, mode, expected) in [
        ("guard-dirty", "dirty", Expected::Dirty),
        ("guard-unmerged", "commit", Expected::Unmerged),
    ] {
        let spawn = flow.spawn(
            label,
            "worktree_executor",
            Some(&a),
            &marker(mode, &parent),
            None,
        )?;
        let child = observe_child(flow, label, root, spawn)?;
        isolated(&parent, &child.git)?;
        if mode == "dirty" {
            require(
                child.git.head == parent.head && child.git.status == "?? fixture-child-dirty.txt\n",
                "dirty child report lacks the intended untracked content",
            )?;
        } else {
            require(
                child.git.head != parent.head
                    && child.git.status.is_empty()
                    && child.git.commit_file.as_deref()
                        == Some(b"synthetic unmerged child commit\n".as_slice())
                    && child
                        .git
                        .files
                        .get("fixture-child-commit.txt")
                        .and_then(Option::as_deref)
                        == Some("synthetic unmerged child commit\n"),
                "unmerged child report lacks its independent clean commit",
            )?;
        }
        let denied = close(
            flow,
            &format!("{label}-default"),
            &parent,
            &child,
            false,
            expected,
        )?;
        if mode == "dirty" {
            require(
                denied.git.targets.iter().any(|target| {
                    target.path == child.git.path
                        && target.dirty_file.as_deref() == Some("synthetic child dirty guard\n")
                }),
                "default close destroyed the child's dirty synthetic file",
            )?;
        }
        evidence.partial_closed_sends.push(partial_close::verify(
            flow,
            environment,
            root,
            &format!("{label}-sealed-send"),
            &child,
            &denied,
        )?);
        evidence.closes.push(denied);
        evidence.closes.push(close(
            flow,
            &format!("{label}-force"),
            &parent,
            &child,
            true,
            Expected::Removed,
        )?);
        evidence.children.push(child);
    }
    let spawn = flow.spawn(
        "guard-borrowed",
        "worktree_executor",
        Some(&a),
        &marker("read", &parent),
        None,
    )?;
    let child = observe_child(flow, "guard-borrowed", root, spawn)?;
    isolated(&parent, &child.git)?;
    require(
        child.git.head == parent.head && child.git.status.is_empty(),
        "borrowed guard did not start clean at parent HEAD",
    )?;
    let before_review = git::capture(
        flow,
        "guard-borrow-before-review",
        Action::Read,
        std::slice::from_ref(&child.git.path),
    )?;
    let reviewer = flow.spawn(
        "guard-borrower",
        "reviewer",
        Some(&b),
        &review::message(&parent),
        Some(&child.spawn.agent_id),
    )?;
    let reviewer = observe_child(flow, "guard-borrower", root, reviewer)?;
    review::require_target(&reviewer, &child)?;
    require(
        reviewer.git.path == child.git.path
            && reviewer.git.head == child.git.head
            && reviewer.git.common_dir == child.git.common_dir,
        "borrower did not execute at target actual assignment",
    )?;
    let after_review = git::capture(
        flow,
        "guard-borrow-after-review",
        Action::Read,
        std::slice::from_ref(&child.git.path),
    )?;
    require(
        before_review.refs == after_review.refs
            && before_review.worktrees == after_review.worktrees,
        "borrower created a worktree/ref",
    )?;
    evidence.checkpoint("before-borrow", before_review);
    evidence.checkpoint("active-borrow", after_review);
    // The reviewer is complete but intentionally Open, so its real borrowed
    // assignment remains owned by the product, not by the scripted provider.
    evidence.closes.push(close(
        flow,
        "guard-borrow-force",
        &parent,
        &child,
        true,
        Expected::Borrowed(&reviewer.spawn.agent_id),
    )?);
    let review_close = successful_close(flow, "guard-release-reviewer", &reviewer, &parent)?;
    git::retained(&parent, &child.git, &review_close.git)?;
    evidence.closes.push(review_close);
    let locked = git::capture(
        flow,
        "guard-lock-original",
        Action::Lock,
        std::slice::from_ref(&child.git.path),
    )?;
    require(
        locked.worktrees.iter().any(|tree| {
            tree.path == child.git.path
                && tree.locked.as_deref() == Some("synthetic acceptance lock")
        }),
        "synthetic original worktree lock was not registered",
    )?;
    evidence.checkpoint("locked", locked);
    let denied = close(
        flow,
        "guard-locked-force",
        &parent,
        &child,
        true,
        Expected::Locked,
    )?;
    require(
        denied.git.worktrees.iter().any(|tree| {
            tree.path == child.git.path
                && tree.locked.as_deref() == Some("synthetic acceptance lock")
        }),
        "force bypassed or changed the Git lock",
    )?;
    evidence.closes.push(denied);
    let unlocked = git::capture(
        flow,
        "guard-unlock-own-lock",
        Action::Unlock,
        std::slice::from_ref(&child.git.path),
    )?;
    git::retained(&parent, &child.git, &unlocked)?;
    require(
        unlocked
            .worktrees
            .iter()
            .any(|tree| tree.path == child.git.path && tree.locked.is_none()),
        "synthetic lock was not released",
    )?;
    evidence.checkpoint("unlocked", unlocked);
    evidence.closes.push(close(
        flow,
        "guard-final-force",
        &parent,
        &child,
        true,
        Expected::Removed,
    )?);
    evidence.children.extend([child, reviewer]);
    absent::run(flow, root, &parent, &a, &mut evidence)?;
    Ok(evidence)
}

fn isolated(parent: &Git, child: &Git) -> Result<()> {
    git::new_detached_child(parent, child)
}

fn close(
    flow: &Flow<'_>,
    label: &str,
    parent: &Git,
    child: &Child,
    force: bool,
    expected: Expected<'_>,
) -> Progress<Close> {
    let before = git::capture(
        flow,
        &format!("{label}-before"),
        Action::Read,
        std::slice::from_ref(&child.git.path),
    )?;
    git::retained(parent, &child.git, &before)?;
    let arguments = json!({"target":child.spawn.agent_id,"force":force});
    let (tool_output, owner_error) = if matches!(expected, Expected::Removed) {
        let _: Closed = flow.read(label, "close_agent", arguments.clone())?;
        let call_id = format!("{}-{label}", flow.prefix);
        let (index, output) = flow
            .request
            .tool_call_output(&call_id, "close_agent", &arguments)?
            .context("successful guard close lost its original call/output")?;
        let text = match output {
            ToolCallOutput::Immediate(text) => text,
            ToolCallOutput::Pending { task_id, .. } => {
                let completion = flow
                    .request
                    .task_completion_after(index, &task_id, "close_agent")?
                    .context("Flow did not resolve the guard close terminal report")?;
                require(
                    completion.status == TaskCompletionStatus::Succeeded,
                    "guard removal did not finish successfully",
                )?;
                completion.projection
            }
        };
        (text, None)
    } else {
        let owner_error = match flow.read::<Closed>(label, "close_agent", arguments.clone()) {
            Err(Stop::Call(call)) => return Err(Stop::Call(call)),
            Err(Stop::Failed(error)) => Some(format!("{error:#}")),
            Ok(result) => {
                require(
                    result.error.is_some(),
                    "protected cleanup unexpectedly succeeded",
                )?;
                None
            }
        };
        (
            no_head::observed_failure(flow, label, "close_agent", arguments)?.output,
            owner_error,
        )
    };
    // Expected cleanup failures retain their actual structured partial result,
    // even though the framework appends its tool-failure annotation afterwards.
    let result: Closed = exec::first(&tool_output)?;
    require(
        result.target == child.spawn.agent_id && result.agents.len() == 1,
        "guard close returned another target or unexpected target tree",
    )?;
    let target = &result.agents[0];
    require(
        target.agent_id == child.spawn.agent_id && target.execution_closed,
        "guard close did not really seal the exact execution",
    )?;
    match expected {
        Expected::Removed => {
            require(
                !tool_output.contains("Framework recorded tool failure:")
                    && result.succeeded_for(&child.spawn.agent_id)
                    && matches!(&target.worktree_cleanup, WorktreeCleanup::Removed { path } if path == &child.git.path),
                "authorized force retry did not remove its exact original binding",
            )?;
        }
        reason => {
            let error = result
                .error
                .as_ref()
                .context("protected cleanup returned no top-level failure")?;
            let WorktreeCleanup::Failed {
                path,
                error: cleanup_error,
            } = &target.worktree_cleanup
            else {
                return Err(anyhow::anyhow!("protected cleanup did not return Failed").into());
            };
            require(
                path.as_deref() == Some(child.git.path.as_str())
                    && !error.code.is_empty()
                    && !error.message.is_empty()
                    && !cleanup_error.code.is_empty()
                    && !cleanup_error.message.is_empty(),
                "protected cleanup lost original path/error details",
            )?;
            let text = format!(
                "{} {} {} {}",
                error.code, error.message, cleanup_error.code, cleanup_error.message
            )
            .to_ascii_lowercase();
            let intended = match reason {
                Expected::Borrowed(reviewer_id) => {
                    error.code == "agentCloseIncomplete"
                        && cleanup_error.code == "agentCloseIncomplete"
                        && error.message.contains(&cleanup_error.message)
                        && cleanup_error
                            .message
                            .strip_prefix("workspace is still used or resolving by agents: ")
                            .is_some_and(|blockers| {
                                blockers.split(", ").any(|id| id == reviewer_id)
                            })
                }
                Expected::Dirty => ["dirty", "uncommitted", "untracked"]
                    .iter()
                    .any(|hint| text.contains(hint)),
                Expected::Unmerged => ["integrat", "ancestor", "commit", "unmerged"]
                    .iter()
                    .any(|hint| text.contains(hint)),
                Expected::Locked => text.contains("lock"),
                Expected::Removed => {
                    return Err(anyhow::anyhow!("invalid failure expectation").into());
                }
            };
            require(
                intended,
                "cleanup failed for a different reason than the intended protection",
            )?;
        }
    }
    let git = git::capture(
        flow,
        &format!("{label}-git"),
        Action::Read,
        std::slice::from_ref(&child.git.path),
    )?;
    if matches!(expected, Expected::Removed) {
        git::removed(parent, &child.git, &git)?;
        git::close_preserved(&before, &git, Some(child.git.path.as_str()))?;
    } else {
        git::retained(parent, &child.git, &git)?;
        git::close_preserved(&before, &git, None)?;
    }
    Ok(Close {
        label: label.into(),
        force,
        result,
        tool_output,
        owner_error,
        before: Some(before),
        git,
    })
}
