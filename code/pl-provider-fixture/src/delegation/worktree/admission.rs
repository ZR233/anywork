//! Dirty admission must reject before publishing any child, registration or ref.
use super::*;

pub(super) fn run(flow: &Flow<'_>, root: &str) -> Progress<Evidence> {
    let mut evidence = Evidence::default();
    let clean = git::capture(flow, "dirty-initial", Action::Read, &[])?;
    require(
        clean.status.is_empty(),
        "dirty admission must start at a clean synthetic parent",
    )?;
    evidence.checkpoint("initial", clean);
    let (a, b) = routes(flow)?;
    for (stage, action, status) in [
        ("untracked", Action::Untracked, "?? fixture-dirty.txt\n"),
        ("staged", Action::Stage, "A  fixture-dirty.txt\n"),
        (
            "unstaged",
            Action::CommitThenModify,
            " M fixture-dirty.txt\n",
        ),
    ] {
        let label = format!("dirty-{stage}");
        let before = git::capture(flow, &format!("{label}-prepare"), action, &[])?;
        require(
            before.status == status,
            "synthetic admission sample is not the intended dirty state",
        )?;
        let directory_before = directory(flow, &format!("{label}-directory-before"), root)?;
        let message = format!(
            "{}\nDELEGATION_EXPECT_COMPLETION:{}",
            marker("read", &before),
            serde_json::to_string(&completion_expectation(&a)?)
                .context("encode dirty spawn route expectation")?
        );
        let arguments = json!({"profileId":"worktree_executor","taskSummary":format!("Reject {stage} synthetic parent"),"message":message,"modelSelection":a});
        let rejection = flow.raw(&format!("{label}-spawn"), "spawn_agent", arguments)?;
        require(
            serde_json::from_str::<Value>(&rejection).is_err()
                && serde_json::from_str::<Spawn>(&rejection).is_err()
                && rejection.contains(
                    "请先完成 commit，使工作区干净后重试（包括已暂存、未暂存及未跟踪文件）",
                ),
            "dirty worktree spawn did not return a clear commit-required admission rejection",
        )?;
        let after = git::capture(flow, &format!("{label}-after"), Action::Read, &[])?;
        let directory_after = directory(flow, &format!("{label}-directory-after"), root)?;
        require(
            before == after && directory_before == directory_after,
            "rejected dirty spawn changed original data/refs/registrations or published a child",
        )?;
        if stage == "untracked" {
            directory_exemption(flow, root, &before, &a, &b, &mut evidence)?;
        }
        evidence.admissions.push(Admission {
            label,
            before,
            after,
            directory_before,
            directory_after,
            rejection,
        });
    }
    let restored = git::capture(flow, "dirty-restore-clean", Action::CommitDirty, &[])?;
    require(
        restored.status.is_empty()
            && restored
                .files
                .get("fixture-dirty.txt")
                .and_then(Option::as_deref)
                == Some("synthetic dirty modified\n"),
        "synthetic admission cleanup did not commit only the intended file",
    )?;
    evidence.no_head = Some(super::no_head::run(flow, root, &restored, &a)?);
    evidence.checkpoint("restored-clean", restored);
    Ok(evidence)
}

pub(super) fn directory(
    flow: &Flow<'_>,
    label: &str,
    root: &str,
) -> Progress<Vec<DirectoryIdentity>> {
    let rows: Vec<AgentRow> = flow.read(label, "list_agents", json!({}))?;
    require(
        rows.iter().filter(|row| row.parent_id.is_none()).count() == 1
            && rows.iter().any(|row| {
                row.id == root && row.parent_id.is_none() && row.lifecycle == Lifecycle::Open
            }),
        "dirty admission directory belongs to a different caller root",
    )?;
    let mut identities: Vec<_> = rows
        .into_iter()
        .map(|row| DirectoryIdentity {
            id: row.id,
            parent_id: row.parent_id,
        })
        .collect();
    identities.sort_by(|a, b| a.id.cmp(&b.id));
    require(
        identities.windows(2).all(|pair| pair[0].id != pair[1].id),
        "duplicate directory identity",
    )?;
    Ok(identities)
}

fn directory_exemption(
    flow: &Flow<'_>,
    root: &str,
    parent: &Git,
    a: &Route,
    b: &Route,
    evidence: &mut Evidence,
) -> Progress<()> {
    let executor = flow.spawn(
        "dirty-directory-executor",
        "executor",
        Some(a),
        &marker("read", parent),
        None,
    )?;
    let executor = observe_child(flow, "dirty-directory-executor", root, executor)?;
    require(
        executor.git.path == parent.path
            && executor.git.head == parent.head
            && executor.git.common_dir == parent.common_dir
            && executor.git.status == parent.status,
        "directory executor did not read the actual dirty parent assignment",
    )?;
    let reviewer = flow.spawn(
        "dirty-directory-reviewer",
        "reviewer",
        Some(b),
        &marker("read", parent),
        Some(&executor.spawn.agent_id),
    )?;
    let reviewer = observe_child(flow, "dirty-directory-reviewer", root, reviewer)?;
    require(
        reviewer.git.path == parent.path
            && reviewer.git.head == parent.head
            && reviewer.git.common_dir == parent.common_dir
            && reviewer.git.status == parent.status,
        "directory reviewer did not borrow its target dirty assignment",
    )?;
    let during = git::capture(flow, "dirty-directory-during", Action::Read, &[])?;
    require(
        during == *parent,
        "directory/review exemption created a worktree/ref or changed dirty data",
    )?;
    let review_close = successful_close(flow, "dirty-directory-close-reviewer", &reviewer, parent)?;
    let execution_close =
        successful_close(flow, "dirty-directory-close-executor", &executor, parent)?;
    require(
        execution_close
            .git
            .targets
            .iter()
            .any(|target| target.path == parent.path && target.exists)
            && review_close.git.refs == parent.refs
            && execution_close.git.refs == parent.refs
            && review_close.git.worktrees == parent.worktrees
            && execution_close.git.worktrees == parent.worktrees,
        "closing non-owning children removed parent data or changed refs/registrations",
    )?;
    evidence.checkpoint("directory-exemption", during);
    evidence.children.extend([executor, reviewer]);
    evidence.closes.extend([review_close, execution_close]);
    Ok(())
}
