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

async fn recovery_ready(runtime: &pl_studio_runtime::StudioRuntime) -> Result<()> {
    // Retry may join a scan already in progress. Wait for a complete new Ready result,
    // never treat an empty Refreshing snapshot as success.
    let before = runtime.read_recovery_state().state.revision();
    runtime.retry_recovery().await?;
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let state = runtime.read_recovery_state().state;
            ensure!(state.kind() != ObservedResourceKind::Failed, "{state:?}");
            if state.kind() == ObservedResourceKind::Ready && state.revision() > before {
                return Ok(());
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .context("Recovery Retry did not complete")?
}

async fn lease_fact(home: &Path, id: &str, preserve: bool) -> Result<serde_json::Value> {
    use sea_orm::{ConnectionTrait, Database, DbBackend, Statement};
    let path = home.join("studio/v2/studio.sqlite");
    let db = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
    let row = db.query_one_raw(Statement::from_sql_and_values(
        DbBackend::Sqlite,
        "SELECT payload_json FROM studio_objects WHERE owner_kind='agent' AND owner_id=? AND object_kind='worktreeLease'",
        [id.into()],
    )).await?.context("durable worktree lease")?;
    let mut fact: serde_json::Value =
        serde_json::from_str(&row.try_get::<String>("", "payload_json")?)?;
    if preserve {
        // Isolated historical fact, installed only while this test's host is stopped.
        fact["state"] = "preserved".into();
        let revision = fact["revision"].as_u64().context("lease revision")? + 1;
        fact["revision"] = revision.into();
        let payload = serde_json::to_string(&fact)?;
        let result = db.execute_raw(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            "UPDATE studio_objects SET revision=?,payload_json=?,payload_hash=? WHERE owner_kind='agent' AND owner_id=? AND object_kind='worktreeLease'",
            [revision.into(), payload.clone().into(), pl_core::context::content_hash(payload.as_bytes()).into(), id.into()],
        )).await?;
        ensure!(result.rows_affected() == 1);
    }
    db.close().await?;
    Ok(fact)
}

#[tokio::test]
async fn rejected_initial_root_input_preserves_the_confirmed_original_binding() -> Result<()> {
    let mut env = Environment::new(vec![], vec![]).await?;
    let result = async {
        // Admit a real file draft, then fault only its test-owned spool bytes. Preflight
        // still sees the valid metadata; promotion fails after factory confirmation.
        let config_store = pl_studio_runtime::config::ConfigStore::new(
            pl_studio_runtime::config::ConfigPaths::from_config_dir(&env.home),
        );
        let mut config = config_store.load()?;
        let mut model = pl_model::model::ModelInfo::compatible(support::MODEL);
        model
            .binding
            .set_transport(pl_model::model::ModelTransportProfile::responses_http());
        model.capabilities.instruction_snapshot_overrides = true;
        model.base_instructions = "Lifecycle fixture model base".into();
        model
            .capabilities
            .input
            .push(pl_model::model::ModelInputCapability::media(
                pl_model::model::ModelModality::File,
                vec![pl_model::model::ModelInputSource::Local],
            ));
        model
            .binding
            .request
            .media
            .push(pl_model::model::ModelMediaInputProfile {
                modality: pl_model::model::ModelModality::File,
                wire: pl_model::model::MediaWireFormat::ResponsesInputFile,
                first_send: vec![pl_model::model::MediaRepresentation::DataUrl],
                replay: vec![pl_model::model::MediaRepresentation::DataUrl],
            });
        config.models.accounts.insert(
            pl_model::config::AccountId::new("root-fixture")?,
            pl_model::config::AccountConfig::from_explicit_models(
                pl_model::protocol::ProtocolEndpoint::compatible(
                    "root-fixture",
                    env.root_provider.base_url(),
                ),
                vec![model],
            ),
        );
        config_store.save(&config)?;
        env.restart().await?;
        let source = env.home.join("failed-initial-attachment.txt");
        std::fs::write(&source, "retain the original worktree")?;
        let route = pl_protocol::studio::NewThreadModelRoute {
            account_id: "root-fixture".into(),
            model_id: support::MODEL.into(),
            effort: None,
        };
        let drafts = env
            .runtime
            .admit_attachment_drafts(pl_protocol::studio::AdmitAttachmentDraftsRequest {
                context: pl_protocol::studio::StudioAttachmentAdmissionContext::NewThread {
                    route: route.clone(),
                },
                sources: vec![
                    pl_protocol::studio::StudioAttachmentDraftSource::LocalFile {
                        path: source.to_string_lossy().into_owned(),
                    },
                ],
            })
            .await?;
        let draft = drafts
            .drafts
            .first()
            .context("admitted initial attachment")?;
        std::fs::remove_file(
            env.home
                .join("studio/v2/attachment-drafts")
                .join(&draft.draft_id),
        )?;
        let progress = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let recorded = progress.clone();
        let failure = env
            .runtime
            .create_thread_command(
                env.project.id.clone(),
                pl_protocol::studio::CreateThreadRequest {
                    title: Some("Rejected initial input".into()),
                    input: StudioPromptInput {
                        input_id: "input-rejected-initial".into(),
                        text: "must not reach a model".into(),
                        attachment_draft_ids: vec![draft.draft_id.clone()],
                    },
                    mode: pl_protocol::ThreadModeId::simple().to_string(),
                    route,
                    delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                    delegation_preference: None,
                    workspace_mode: ThreadWorkspaceMode::Worktree,
                },
                Some(std::sync::Arc::new(move |event| {
                    recorded.lock().unwrap().push(event);
                })),
            )
            .await
            .err()
            .context("missing attachment bytes unexpectedly accepted")?;
        ensure!(
            failure.chain().any(|cause| cause
                .downcast_ref::<std::io::Error>()
                .is_some_and(|error| error.kind() == std::io::ErrorKind::NotFound)),
            "{failure:#}"
        );
        let submitted_path = progress
            .lock()
            .unwrap()
            .iter()
            .find(|event| {
                event.stage == pl_studio_runtime::ThreadPreparationStage::SubmittingPrompt
            })
            .and_then(|event| event.workspace_path.clone())
            .context("failure occurred before the confirmed root reached initial input")?;
        let issue = env
            .runtime
            .recovery_issues()
            .into_iter()
            .find(|issue| {
                issue
                    .worktree
                    .as_ref()
                    .is_some_and(|preview| preview.path == submitted_path)
            })
            .context("confirmed root failure did not immediately publish its preserved site")?;
        let preview = issue.worktree.context("failed root preview")?;
        ensure!(
            preview.state == "preserved" && preview.lease_revision == 3,
            "Prepared -> Active -> failed retention lost its revision: {preview:?}"
        );
        ensure!(preview.inspection == StudioWorktreeInspection::Available);
        ensure!(
            issue.message.contains("first prompt"),
            "wrong failure diagnosis: {}",
            issue.message
        );
        let retained = lease_fact(&env.home, &preview.owner_thread_id, false).await?;
        ensure!(retained["state"] == "preserved" && retained["revision"] == 3);
        ensure!(Path::new(&submitted_path).is_dir());
        ensure!(
            std::fs::read_to_string(Path::new(&submitted_path).join("tracked.txt"))?
                == "preserve project content\n"
        );
        ensure!(
            git(Path::new(&submitted_path), &["rev-parse", "HEAD"])?
                == git(&env.repo, &["rev-parse", "HEAD"])?
        );
        recovery_ready(&env.runtime).await?;
        ensure!(
            env.runtime.recovery_issues().iter().any(|issue| {
                issue.worktree.as_ref().is_some_and(|current| {
                    current.owner_thread_id == preview.owner_thread_id
                        && current.state == "preserved"
                        && current.lease_revision == 3
                })
            }),
            "successful factory confirmation hid its later failed-input retention"
        );
        env.restart().await?;
        recovery_ready(&env.runtime).await?;
        ensure!(lease_fact(&env.home, &preview.owner_thread_id, false).await? == retained);
        ensure!(env.runtime.recovery_issues().iter().any(|issue| {
            issue
                .worktree
                .as_ref()
                .is_some_and(|current| current.owner_thread_id == preview.owner_thread_id)
        }));
        ensure!(
            env.root_provider.recorded().is_empty() && env.child_provider.recorded().is_empty()
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn parent_send_confirms_cold_clean_dirty_and_legacy_child_bindings() -> Result<()> {
    for (dirty, legacy) in [(false, false), (true, false), (true, true)] {
        let spawned = ReplyStage::new();
        let child_initial = ReplyStage::new();
        let child_resumed = ReplyStage::new();
        let parent_resumed = ReplyStage::new();
        let mut env = Environment::new(
            vec![
                prompt_step(
                    "cold-spawn",
                    0,
                    support::spawn_reply("cold-spawn", "cold-child"),
                ),
                Step::tool_output(
                    Protocol::ResponsesHttp,
                    "cold-spawn",
                    "agentId",
                    1,
                    held_reply(&spawned, "cold-spawned"),
                ),
            ],
            vec![
                prompt_step("cold-child", 0, held_reply(&child_initial, "cold-child")),
                prompt_step(
                    "cold-resume-child",
                    1,
                    held_reply(&child_resumed, "cold-child-resumed"),
                ),
            ],
        )
        .await?;
        let result = async {
            let root = env
                .start(ThreadWorkspaceMode::Worktree, "cold-spawn")
                .await?;
            reached(&spawned).await?;
            reached(&child_initial).await?;
            let receipt = support::receipt(&env.root_provider, "cold-spawn")?;
            let id = support::child_id(&receipt)?.to_owned();
            let path = support::child_path(&receipt)?.to_owned();
            if dirty {
                std::fs::write(path.join("tracked.txt"), "keep modified\n")?;
                std::fs::write(path.join("untracked.txt"), "keep untracked\n")?;
                std::fs::write(path.join("ignored.txt"), "keep ignored\n")?;
            }
            let head = git(&path, &["rev-parse", "HEAD"])?;
            let status = git(&path, &["status", "--porcelain", "--ignored"])?;
            spawned.release();
            completed_prompt(&env.runtime, &root.thread.id, "cold-spawn").await?;
            env.runtime.shutdown_runtime().await?;
            let original = lease_fact(&env.home, &id, false).await?;
            ensure!(
                original["state"] == "active",
                "ordinary shutdown downgraded a healthy child"
            );
            let expected = lease_fact(&env.home, &id, legacy).await?;

            // The cold parent uses its actual send_message tool. No child subscription or
            // Runtime ensure_thread_owner call can mask a missing factory confirmation.
            let replacement = pl_provider_fixture::FixtureServer::start(vec![
                prompt_step(
                    "cold-resume-parent",
                    0,
                    support::tool_reply(
                        "send_message",
                        "cold-send",
                        serde_json::json!({"target":id,"message":"cold-resume-child"}),
                    ),
                ),
                Step::tool_output(
                    Protocol::ResponsesHttp,
                    "cold-send",
                    "sequence",
                    1,
                    held_reply(&parent_resumed, "cold-parent-resumed"),
                ),
            ])
            .await?;
            let old = std::mem::replace(&mut env.root_provider, replacement);
            old.finish().await?;
            let config_store = pl_studio_runtime::config::ConfigStore::new(
                pl_studio_runtime::config::ConfigPaths::from_config_dir(&env.home),
            );
            let mut config = config_store.load()?;
            config
                .models
                .accounts
                .get_mut(&pl_model::config::AccountId::new("root-fixture")?)
                .context("root fixture account")?
                .base_url = env.root_provider.base_url();
            config_store.save(&config)?;
            env.restart().await?;
            recovery_ready(&env.runtime).await?;
            ensure!(
                env.root_provider.recorded().is_empty() && env.child_provider.recorded().len() == 1,
                "restart or Recovery Retry resumed model execution"
            );
            ensure!(
                !env.runtime
                    .recovery_issues()
                    .iter()
                    .any(|issue| { issue.thread_id.as_deref() == Some(&root.thread.id) }),
                "healthy cold root binding produced a Recovery issue"
            );
            let before = lease_fact(&env.home, &id, false).await?;
            ensure!(before == expected, "read-only Recovery changed a binding");
            if legacy {
                ensure!(
                    env.runtime.recovery_issues().iter().any(|issue| {
                        issue.id == format!("worktree-lease-{id}")
                            && issue
                                .worktree
                                .as_ref()
                                .is_some_and(|preview| preview.state == "preserved")
                    }),
                    "old preserved facts disappeared before real activation"
                );
            } else {
                ensure!(
                    !env.runtime
                        .recovery_issues()
                        .iter()
                        .any(|issue| { issue.thread_id.as_deref() == Some(&id) }),
                    "healthy cold binding produced a Recovery issue"
                );
            }
            let parent = env.runtime.thread_snapshot(&root.thread.id).await?;
            env.runtime
                .submit_prompt_command(
                    root.thread.id.clone(),
                    SubmitPromptRequest {
                        input: StudioPromptInput {
                            input_id: "input-cold-resume-parent".into(),
                            text: "cold-resume-parent".into(),
                            attachment_draft_ids: vec![],
                        },
                        expected_model_route_revision: parent
                            .runtime
                            .as_ref()
                            .and_then(|runtime| runtime.model_route.as_ref())
                            .context("saved parent model route")?
                            .revision,
                    },
                )
                .await?;
            reached(&child_resumed).await?;
            reached(&parent_resumed).await?;
            let send = support::receipt(&env.root_provider, "cold-send")?;
            ensure!(send["target"] == id && send["sequence"].as_u64().is_some());
            let confirmed = lease_fact(&env.home, &id, false).await?;
            let mut expected_active = expected.clone();
            expected_active["state"] = "active".into();
            expected_active["revision"] =
                (expected["revision"].as_u64().context("original revision")? + u64::from(legacy))
                    .into();
            ensure!(
                confirmed == expected_active,
                "confirmation changed the original binding"
            );
            recovery_ready(&env.runtime).await?;
            ensure!(
                !env.runtime
                    .recovery_issues()
                    .iter()
                    .any(|issue| { issue.thread_id.as_deref() == Some(&id) }),
                "confirmed child retained a stale Recovery issue"
            );
            ensure!(git(&path, &["rev-parse", "HEAD"])? == head);
            ensure!(git(&path, &["status", "--porcelain", "--ignored"])? == status);
            if dirty {
                ensure!(std::fs::read_to_string(path.join("tracked.txt"))? == "keep modified\n");
                ensure!(std::fs::read_to_string(path.join("untracked.txt"))? == "keep untracked\n");
                ensure!(std::fs::read_to_string(path.join("ignored.txt"))? == "keep ignored\n");
            }
            ensure!(env.child_provider.recorded().len() == 2);
            env.runtime.shutdown_runtime().await?;
            ensure!(
                lease_fact(&env.home, &id, false).await? == confirmed,
                "second ordinary shutdown changed the confirmed binding"
            );
            Ok(())
        }
        .await;
        spawned.release();
        child_initial.release();
        child_resumed.release();
        parent_resumed.release();
        env.finish(result)
            .await
            .with_context(|| format!("dirty={dirty}, legacy={legacy}"))?;
    }
    Ok(())
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
        env.runtime.shutdown_runtime().await?;
        let retained = lease_fact(&env.home, &root.thread.id, true).await?;
        env.restart().await?;
        let history = support::saved(&env.home, &root.thread.id).await?;
        let original_snapshot = env.runtime.thread_snapshot(&root.thread.id).await?;
        let query = TimelinePageQuery::default();
        // A page value does not retain a cold Session. Hold the same explicit
        // query scope across subscription and recovery, as production readers do.
        let reader = env.runtime.timeline_reader(&root.thread.id).await?;
        let original_page = reader.page(&query).await?;
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
                && snapshot.thread.project_id == env.project.id
                && snapshot.thread.root_thread_id == root.thread.root_thread_id
                && snapshot.thread.workspace_mode == ThreadWorkspaceMode::Worktree
                && snapshot.thread.workspace_path == root.thread.workspace_path,
            "history subscription lost the original Thread/workspace identity"
        );
        let subscribed_page = env.runtime.timeline_page(&root.thread.id, &query).await?;
        ensure!(
            subscribed_page == original_page,
            "missing-worktree subscription lost original history content: \
             before={original_page:?}; after={subscribed_page:?}"
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
        recovery_ready(&env.runtime).await?;
        ensure!(
            lease_fact(&env.home, &root.thread.id, false).await? == retained,
            "failed cold verification or Retry washed out the original preserved fact"
        );
        ensure!(
            execution_issue.scope == StudioRecoveryIssueScope::Thread
                && execution_issue.category == StudioRecoveryIssueCategory::Repository
                && execution_issue.impact == StudioRecoveryImpact::ExecutionBlocked
                && execution_issue.action == StudioRecoveryIssueAction::Retry
                && execution_issue.thread_id.as_deref() == Some(root.thread.id.as_str())
                && execution_issue.project_id.as_deref() == Some(env.project.id.as_str())
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
                && missing_issue.project_id.as_deref() == Some(env.project.id.as_str())
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
