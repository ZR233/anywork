mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ObservedResourceKind, ThreadSubscriptionRequest, ThreadSubscriptionUpdate, ThreadWorkspaceMode,
    TimelinePageQuery,
    studio::{StudioErrorCode, StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::{Protocol, ReplyStage, Step};
use pl_studio_runtime::{
    StudioRecoveryImpact, StudioRecoveryIssueAction, StudioRecoveryIssueCategory,
    StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner, StudioWorktreeInspection,
    StudioWorktreeRecoveryPreview,
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
        reached(&spawned).await.with_context(|| {
            format!(
                "spawn result was not accepted: {:?}",
                support::tool_output(&env.root_provider, "identity-spawn")
            )
        })?;
        reached(&child_running)
            .await
            .context("spawned child did not start its model request")?;
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
        let original_snapshot = env.runtime.thread_snapshot(&root.thread.id).await?;
        let query = TimelinePageQuery::default();
        let original_page = env.runtime.timeline_page(&root.thread.id, &query).await?;
        ensure!(
            original_page.thread_id == root.thread.id
                && !original_page.has_older
                && original_page.items.iter().any(|item| {
                    item.fields.iter().any(|field| {
                        field.field == pl_protocol::ThreadContentField::Text
                            && field.text == "saved missing-site history"
                    })
                }),
            "original complete history did not contain the saved reply"
        );
        std::fs::remove_dir_all(&root.thread.workspace_path)?;
        let mut subscription = env
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: root.thread.id.clone(),
            })
            .await?;
        let Some(ThreadSubscriptionUpdate::Snapshot { snapshot }) =
            tokio::time::timeout(Duration::from_secs(20), subscription.recv())
                .await
                .context("missing-worktree history initial frame was not delivered")??
        else {
            anyhow::bail!("history subscription did not begin with a complete Snapshot");
        };
        ensure!(
            snapshot.as_ref() == &original_snapshot,
            "missing-worktree subscription changed the complete saved snapshot"
        );
        ensure!(
            snapshot.schema_version == pl_protocol::THREAD_SCHEMA_VERSION
                && snapshot.revision == history.checkpoint.state.commit_sequence
                && snapshot.thread.id == root.thread.id
                && snapshot.thread.workspace_id == env.project.id
                && snapshot.thread.root_thread_id == root.thread.root_thread_id
                && snapshot.thread.workspace_mode == ThreadWorkspaceMode::Worktree
                && snapshot.thread.workspace_path == root.thread.workspace_path,
            "history subscription lost the original Thread/workspace identity"
        );
        ensure!(
            env.runtime.timeline_page(&root.thread.id, &query).await? == original_page,
            "missing-worktree subscription lost original history content"
        );
        ensure!(
            snapshot.active_turn.is_none()
                && snapshot.activity.is_none()
                && snapshot.storage.is_none()
                && snapshot.runtime.as_ref().is_some_and(|runtime| {
                    runtime.thread_id == root.thread.id
                        && runtime.execution.is_none()
                        && runtime.live_usage.is_none()
                })
                && !env
                    .runtime
                    .persistence_queue_snapshot()
                    .threads
                    .iter()
                    .any(|thread| thread.thread_id == root.thread.id)
                && env.root_provider.recorded().len() == 1,
            "read-only history subscription activated execution or a persistence writer"
        );

        let failure = env
            .runtime
            .submit_prompt_command(
                root.thread.id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: "input-missing-identity-rejected".into(),
                        text: "must not execute in the missing workspace".into(),
                        attachment_draft_ids: vec![],
                    },
                    expected_model_route_revision: snapshot
                        .runtime
                        .as_ref()
                        .and_then(|runtime| runtime.model_route.as_ref())
                        .context("original saved model route is missing")?
                        .revision,
                },
            )
            .await
            .err()
            .context("new input unexpectedly activated the missing checkout")?;
        // Public submission canonicalizes the execution root before reaching Git's typed Missing
        // check. Its retained IO NotFound source therefore maps to Storage, not Unavailable.
        let source = failure
            .chain()
            .find_map(|cause| cause.downcast_ref::<std::io::Error>())
            .context("missing workspace rejection lost its typed IO source")?;
        ensure!(
            source.kind() == std::io::ErrorKind::NotFound,
            "input was refused for an unrelated IO failure: {failure:#}"
        );
        let execution_issue = env
            .runtime
            .recovery_issues()
            .into_iter()
            .find(|issue| issue.id == format!("execution-workspace:{}", root.thread.id))
            .context("execution rejection did not publish this Thread's Recovery issue")?;
        ensure!(
            execution_issue.scope == StudioRecoveryIssueScope::Thread
                && execution_issue.category == StudioRecoveryIssueCategory::Repository
                && execution_issue.impact == StudioRecoveryImpact::ExecutionBlocked
                && execution_issue.action == StudioRecoveryIssueAction::Retry
                && execution_issue.thread_id.as_deref() == Some(root.thread.id.as_str())
                && execution_issue.workspace_id.as_deref() == Some(env.project.id.as_str())
                && execution_issue.message.contains(&source.to_string()),
            "execution rejection has the wrong Recovery owner, impact or cause: {execution_issue:?}"
        );
        let error = pl_studio_runtime::studio_error_from_anyhow(failure);
        ensure!(
            error.code == StudioErrorCode::Storage && error.retryable,
            "public execution rejection lost the formal NotFound mapping: {:?}: {}",
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
        let missing_issue = env
            .runtime
            .recovery_issues()
            .into_iter()
            .find(|issue| issue.worktree.as_ref() == Some(&missing))
            .context("typed Missing worktree diagnostic disappeared")?;
        ensure!(
            missing.owner_kind == StudioRecoveryWorktreeOwner::Session
                && missing.owner_thread_id == root.thread.id
                && missing.path == root.thread.workspace_path
                && missing_issue.scope == StudioRecoveryIssueScope::Thread
                && missing_issue.category == StudioRecoveryIssueCategory::Repository
                && missing_issue.impact == StudioRecoveryImpact::ExecutionBlocked
                && missing_issue.action == StudioRecoveryIssueAction::Retry
                && missing_issue.thread_id.as_deref() == Some(root.thread.id.as_str())
                && missing_issue.workspace_id.as_deref() == Some(env.project.id.as_str())
                && missing_issue.message.contains("stat")
                && missing_issue.message.contains("not found"),
            "Recovery lost the original typed Missing owner or safe cause: {missing_issue:?}"
        );
        ensure!(
            env.runtime.thread_snapshot(&root.thread.id).await? == original_snapshot
                && env.runtime.timeline_page(&root.thread.id, &query).await? == original_page
                && env
                    .runtime
                    .runtime_snapshot()
                    .await?
                    .active_turns
                    .is_empty()
                && !env
                    .runtime
                    .persistence_queue_snapshot()
                    .threads
                    .iter()
                    .any(|thread| thread.thread_id == root.thread.id),
            "rejected input changed original history or activated execution"
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
        let root_path = Path::new(&root.thread.workspace_path);
        ensure!(root_path.exists(), "failed cleanup removed the checkout");
        let worktrees = git(&env.repo, &["worktree", "list", "--porcelain", "-z"])?;
        ensure!(
            worktrees
                .split('\0')
                .filter_map(|record| record.strip_prefix("worktree "))
                .any(|path| Path::new(path) == root_path),
            "failed cleanup removed the worktree registration"
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
