mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{ObservedResourceKind, ThreadSubscriptionRequest, ThreadWorkspaceMode};
use pl_provider_fixture::{Protocol, ReplyStage, Step};
use pl_studio_runtime::{
    StudioRecoveryWorktreeOwner, StudioWorktreeInspection, StudioWorktreeRecoveryPreview,
};
use std::{path::Path, time::Duration};
use support::{Environment, completed_prompt, git, held_reply, prompt_step, reached};

async fn preview(
    runtime: &pl_studio_runtime::StudioRuntime,
    id: &str,
    inspection: StudioWorktreeInspection,
) -> Result<StudioWorktreeRecoveryPreview> {
    let previous_revision = runtime.read_recovery_state().state.revision();
    runtime.retry_recovery().await?;
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let state = runtime.read_recovery_state().state;
            if state.kind() == ObservedResourceKind::Ready && state.revision() > previous_revision {
                if let Some(preview) = state
                    .value()
                    .into_iter()
                    .flatten()
                    .filter_map(|issue| issue.worktree.as_ref())
                    .find(|preview| {
                        preview.owner_thread_id == id && preview.inspection == inspection
                    })
                {
                    return Ok::<_, anyhow::Error>(preview.clone());
                }
                // A startup scan can have observed the owner before this explicit directory
                // command. Recheck only after that scan publishes its completed result.
                runtime.retry_recovery().await?;
            }
            if state.kind() == ObservedResourceKind::Ready && state.revision() <= previous_revision
            {
                runtime.retry_recovery().await?;
            }
            ensure!(
                state.kind() != ObservedResourceKind::Failed,
                "recovery scan failed: {state:?}"
            );
            tokio::task::yield_now().await;
        }
    })
    .await
    .context("expected explicit Recovery observation was not published")?
}

#[tokio::test]
async fn changed_root_is_rebound_in_place_and_recovery_reports_the_observed_branch() -> Result<()> {
    let mut env = Environment::new(
        vec![prompt_step(
            "root-identity",
            0,
            support::text_reply("saved root history", "root-identity"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let root = env
            .start(ThreadWorkspaceMode::Worktree, "root-identity")
            .await?;
        completed_prompt(&env.runtime, &root.thread.id, "root-identity").await?;
        let path = Path::new(&root.thread.workspace_path);
        ensure!(
            git(path, &["rev-parse", "--abbrev-ref", "HEAD"])? == "HEAD",
            "new root was not detached"
        );
        git(path, &["switch", "-c", "business"])?;
        std::fs::write(path.join("tracked.txt"), "advanced root\n")?;
        git(path, &["commit", "-am", "advance root"])?;
        git(path, &["branch", "-m", "renamed-business"])?;
        git(&env.repo, &["branch", "pure-session-legacy"])?;
        std::fs::write(path.join("untracked.txt"), "keep untracked\n")?;
        std::fs::write(path.join("ignored.txt"), "keep ignored\n")?;
        let head = git(path, &["rev-parse", "HEAD"])?;
        let branches = git(
            &env.repo,
            &[
                "for-each-ref",
                "refs/heads",
                "--format=%(refname):%(objectname)",
            ],
        )?;
        env.restart().await?;
        let before = support::saved(&env.home, &root.thread.id).await?;
        // Current-stage archive is directory visibility/retirement only. It is not the pending
        // final-close/force contract and must not delete or invent a permanent close intent.
        env.runtime
            .archive_thread("identity-visible-history".into(), root.thread.id.clone())
            .await?
            .context("archive identity owner")?;
        let observation = preview(
            &env.runtime,
            &root.thread.id,
            StudioWorktreeInspection::Available,
        )
        .await?;
        ensure!(
            observation.branch.as_deref() == Some("renamed-business")
                && observation.head_commit.as_deref() == Some(head.as_str())
        );
        ensure!(
            observation.dirty == Some(true),
            "Recovery lost real local content state"
        );
        env.runtime.restore_thread(root.thread.id.clone()).await?;
        let _subscription = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: root.thread.id.clone(),
            })
            .await?;
        ensure!(
            git(path, &["rev-parse", "HEAD"])? == head
                && git(path, &["branch", "--show-current"])? == "renamed-business",
            "cold binding changed Git state"
        );
        ensure!(
            std::fs::read_to_string(path.join("untracked.txt"))? == "keep untracked\n"
                && std::fs::read_to_string(path.join("ignored.txt"))? == "keep ignored\n"
        );
        ensure!(
            git(
                &env.repo,
                &[
                    "for-each-ref",
                    "refs/heads",
                    "--format=%(refname):%(objectname)"
                ]
            )? == branches,
            "directory visibility or binding changed a branch"
        );
        let after = support::saved(&env.home, &root.thread.id).await?;
        ensure!(
            before.path == after.path
                && after.context == before.context
                && after.checkpoint.history_fence >= before.checkpoint.history_fence,
            "cold binding changed saved history ownership or content"
        );
        ensure!(
            !after
                .checkpoint
                .state
                .extensions
                .contains_key("studio.agent-close")
        );
        ensure!(
            env.root_provider.recorded().len() == 1,
            "identity recovery executed a model request"
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn existing_hot_spawn_and_cold_child_binding_do_not_depend_on_creation_branch() -> Result<()>
{
    let begin = ReplyStage::new();
    let spawned = ReplyStage::new();
    let child_running = ReplyStage::new();
    let pl_provider_fixture::Reply::Sse(mut events) =
        support::spawn_reply("identity-spawn", "identity-child")
    else {
        anyhow::bail!("tool fixture must be SSE");
    };
    let first = events.remove(0);
    let mut env = Environment::new(
        vec![
            prompt_step("identity-spawn", 0, begin.gated(vec![first], events)),
            Step::tool_output(
                Protocol::ResponsesHttp,
                "identity-spawn",
                "agentId",
                1,
                held_reply(&spawned, "identity-spawned"),
            ),
        ],
        vec![prompt_step(
            "identity-child",
            0,
            held_reply(&child_running, "identity-child"),
        )],
    )
    .await?;
    let result = async {
        let root = env
            .start(ThreadWorkspaceMode::Worktree, "identity-spawn")
            .await?;
        reached(&begin).await?;
        let root_path = Path::new(&root.thread.workspace_path);
        git(root_path, &["switch", "-c", "root-business"])?;
        git(root_path, &["branch", "-m", "renamed-root"])?;
        begin.release();
        reached(&spawned).await?;
        reached(&child_running).await?;
        let receipt = support::receipt(&env.root_provider, "identity-spawn")?;
        let id = support::child_id(&receipt)?;
        let child_path = support::child_path(&receipt)?;
        ensure!(
            git(child_path, &["rev-parse", "--abbrev-ref", "HEAD"])? == "HEAD",
            "new child was not detached"
        );
        git(child_path, &["switch", "-c", "child-business"])?;
        git(child_path, &["branch", "-m", "renamed-child"])?;
        git(child_path, &["switch", "--detach"])?;
        git(child_path, &["branch", "-D", "renamed-child"])?;
        std::fs::write(child_path.join("tracked.txt"), "detached child advance\n")?;
        git(child_path, &["commit", "-am", "child advance"])?;
        std::fs::write(child_path.join("untracked.txt"), "keep child content\n")?;
        let head = git(child_path, &["rev-parse", "HEAD"])?;
        spawned.release();
        completed_prompt(&env.runtime, &root.thread.id, "identity-spawn").await?;
        env.restart().await?;
        child_running.release();
        let before = support::saved(&env.home, id).await?;
        let workspace = &before.checkpoint.state.extensions["studio.workspace"].payload;
        ensure!(
            workspace.version() == 3,
            "new child did not freeze the current receipt format"
        );
        let saved: pl_protocol::AgentWorkspaceAssignmentSnapshot =
            serde_json::from_str(workspace.content())?;
        ensure!(
            saved.worktree.context("owned child receipt")?.path
                == child_path.to_str().context("child path")?
        );
        let _root_subscription = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: root.thread.id.clone(),
            })
            .await?;
        let _child_subscription = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: id.into(),
            })
            .await?;
        ensure!(
            git(child_path, &["rev-parse", "HEAD"])? == head
                && git(child_path, &["branch", "--show-current"])?.is_empty(),
            "cold child binding reset or rebuilt the original site"
        );
        ensure!(
            std::fs::read_to_string(child_path.join("untracked.txt"))? == "keep child content\n"
        );
        ensure!(git(root_path, &["branch", "--show-current"])? == "renamed-root");
        ensure!(
            env.root_provider.recorded().len() == 2 && env.child_provider.recorded().len() == 1,
            "cold binding executed additional model work"
        );
        // Shutdown before releasing any remaining model stages, avoiding a synthetic completion
        // report being mistaken for an additional user request in the strict fixture.
        env.runtime.shutdown_runtime().await?;
        Ok(())
    }
    .await;
    begin.release();
    spawned.release();
    child_running.release();
    env.finish(result).await
}

#[tokio::test]
async fn factory_missing_error_stays_typed_and_recovery_never_calls_missing_detached() -> Result<()>
{
    let mut env = Environment::new(
        vec![prompt_step(
            "missing-identity",
            0,
            support::text_reply("saved missing-site history", "missing-identity"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let root = env
            .start(ThreadWorkspaceMode::Worktree, "missing-identity")
            .await?;
        completed_prompt(&env.runtime, &root.thread.id, "missing-identity").await?;
        env.restart().await?;
        let history = support::saved(&env.home, &root.thread.id).await?;
        std::fs::remove_dir_all(&root.thread.workspace_path)?;
        let failure = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: root.thread.id.clone(),
            })
            .await
            .err()
            .context("missing checkout unexpectedly activated")?;
        let error = pl_studio_runtime::studio_error_from_anyhow(failure);
        ensure!(
            error.code == pl_protocol::studio::StudioErrorCode::Unavailable
                && error.message.contains("stat")
                && error.message.contains("not found"),
            "real factory lost the typed Missing cause: {:?}: {}",
            error.code,
            error.message
        );
        let missing = preview(
            &env.runtime,
            &root.thread.id,
            StudioWorktreeInspection::Missing,
        )
        .await?;
        ensure!(
            missing.branch.is_none()
                && missing.head_commit.is_none()
                && missing.dirty.is_none()
                && missing.changed_files.is_none(),
            "missing inspection invented mutable Git state"
        );
        // Existing archive remains available for a missing worktree, but visibility restoration
        // must never recreate it or change the original path to the main project.
        env.runtime
            .archive_thread("archive-missing-identity".into(), root.thread.id.clone())
            .await?
            .context("archive missing site")?;
        let restored = env.runtime.restore_thread(root.thread.id.clone()).await?;
        ensure!(
            restored.workspace_path == root.thread.workspace_path
                && !Path::new(&restored.workspace_path).exists()
        );
        ensure!(
            history.path.exists()
                && support::saved(&env.home, &root.thread.id).await?.context == history.context
        );
        ensure!(
            env.root_provider.recorded().len() == 1,
            "failed identity recovery executed a model request"
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn safe_recovery_reports_git_lock_without_deleting_or_expanding_authorization() -> Result<()>
{
    let mut env = Environment::new(
        vec![prompt_step(
            "locked-identity",
            0,
            support::text_reply("saved locked-site history", "locked-identity"),
        )],
        vec![],
    )
    .await?;
    let mut locked = None;
    let result = async {
        let root = env
            .start(ThreadWorkspaceMode::Worktree, "locked-identity")
            .await?;
        completed_prompt(&env.runtime, &root.thread.id, "locked-identity").await?;
        env.restart().await?;
        env.runtime
            .archive_thread("retire-identity-owner".into(), root.thread.id.clone())
            .await?
            .context("retire owner without deleting its site")?;
        let protected = preview(
            &env.runtime,
            &root.thread.id,
            StudioWorktreeInspection::Available,
        )
        .await?;
        let session_files = Path::new(&root.thread.workspace_path).join(".anywork");
        ensure!(
            protected.dirty == Some(true) && session_files.exists(),
            "fixture lacks its real ignored session files"
        );
        ensure!(
            env.runtime
                .cleanup_preserved_worktree(
                    StudioRecoveryWorktreeOwner::Session,
                    &root.thread.id,
                    protected.lease_revision
                )
                .await
                .is_err(),
            "safe Recovery treated ignored content as deletion permission"
        );
        ensure!(
            session_files.exists(),
            "safe Recovery deleted ignored session files"
        );
        // The original runtime resources are already closed. Remove only this fixture's own
        // ignored session files to isolate Git-lock refusal from content-preservation refusal.
        std::fs::remove_dir_all(session_files)?;
        let initial = preview(
            &env.runtime,
            &root.thread.id,
            StudioWorktreeInspection::Available,
        )
        .await?;
        ensure!(
            initial.branch.is_none() && initial.dirty == Some(false),
            "available detached inspection lost its observed state: {initial:?}"
        );
        git(
            &env.repo,
            &["worktree", "lock", &root.thread.workspace_path],
        )?;
        locked = Some(root.thread.workspace_path.clone());
        let failure = env
            .runtime
            .cleanup_preserved_worktree(
                StudioRecoveryWorktreeOwner::Session,
                &root.thread.id,
                initial.lease_revision,
            )
            .await
            .err()
            .context("safe cleanup ignored a Git lock")?;
        let error = pl_studio_runtime::studio_error_from_anyhow(failure);
        ensure!(
            error.code == pl_protocol::studio::StudioErrorCode::Unavailable
                && error.message.contains("locked")
                && error.message.chars().count() <= 2048,
            "Git lock lost bounded typed diagnostics: {:?}: {}",
            error.code,
            error.message
        );
        ensure!(
            Path::new(&root.thread.workspace_path).exists()
                && git(&env.repo, &["worktree", "list", "--porcelain"])?
                    .contains(&root.thread.workspace_path)
        );
        git(
            &env.repo,
            &["worktree", "unlock", &root.thread.workspace_path],
        )?;
        locked = None;
        let retry = preview(
            &env.runtime,
            &root.thread.id,
            StudioWorktreeInspection::Available,
        )
        .await?;
        ensure!(
            retry.lease_revision > initial.lease_revision,
            "failed cleanup did not publish its retry revision"
        );
        env.runtime
            .cleanup_preserved_worktree(
                StudioRecoveryWorktreeOwner::Session,
                &root.thread.id,
                retry.lease_revision,
            )
            .await?;
        ensure!(!Path::new(&root.thread.workspace_path).exists());
        ensure!(git(&env.repo, &["branch", "--format=%(refname:short)"])? == "main");
        Ok(())
    }
    .await;
    if let Some(path) = locked {
        let _ = git(&env.repo, &["worktree", "unlock", &path]);
    }
    env.finish(result).await
}
