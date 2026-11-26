use crate::studio::runtime::StudioRuntime;
use crate::studio::runtime::thread_service::test_support::{configure, options, request};
use crate::timeline::{ConversationEvent, SessionDetailKind, TimelineItem, TimelinePatch};
use crate::{StudioErrorCode, ThreadWorkspaceMode};
use anyhow::{Context, Result};
use pl_core::context::{OpaquePayload, content_hash};
use pl_core::model::ToolCallMode;
use pl_core::thread::current::{CurrentModelCall, SavedModelPhase, ThreadCurrent};
use pl_core::thread::extensions::ExtensionRecord;
use sea_orm::{ConnectionTrait, DbBackend, EntityTrait, Statement};
use serde_json::json;
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[tokio::test]
async fn cold_session_meta_reports_corrupt_history_but_accepts_absence() -> Result<()> {
    let temporary = tempfile::tempdir()?;
    let home = temporary.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temporary.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread(&project.id, "cold history metadata")
        .await?;
    let owner = runtime.ensure_thread_owner(&thread.id).await?;
    runtime.synchronize_thread_observation(&thread.id).await?;
    runtime
        .store
        .conversation_store(&thread.id)
        .await?
        .flush_current(owner.runtime_epoch())
        .await?;
    let paths = runtime.store.registered_session_paths(&thread.id)?;
    let history = runtime.store.history(&thread.id).await?;
    runtime.shutdown_runtime().await?;
    // Fault injection starts only after the writer's WAL and both pools have finished closing.
    history.close().await?;
    drop(history);
    drop(owner);
    drop(runtime);

    let current = tokio::fs::read(paths.current_file())
        .await
        .context("saved fixture Current")?;
    tokio::fs::write(paths.history_database(), b"invalid history database").await?;
    assert_eq!(
        tokio::fs::read(paths.history_database()).await?,
        b"invalid history database"
    );
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert!(runtime.open_conversation_feed(&thread.id, 8).await.is_err());
    assert!(
        runtime.thread_session_meta(&thread.id).await.is_err(),
        "corruption must not become partial metadata success"
    );
    assert_eq!(
        tokio::fs::read(paths.history_database()).await?,
        b"invalid history database"
    );
    assert_eq!(tokio::fs::read(paths.current_file()).await?, current);
    assert!(!paths.root().join("migration-backups").exists());
    assert!(
        runtime
            .session_of(&thread.id)
            .and_then(|session| session.observed_thread(&thread.id))
            .is_none()
    );

    // Missing history still permits the saved pause metadata; it is not corruption.
    tokio::fs::remove_file(paths.history_database()).await?;
    assert!(
        !runtime
            .thread_session_meta(&thread.id)
            .await?
            .execution_present
    );
    assert!(!paths.history_database().exists());
    runtime.shutdown_runtime().await?;
    Ok(())
}

struct ColdConversation {
    _temporary: tempfile::TempDir,
    endpoint: pl_provider_fixture::FixtureServer,
    home: PathBuf,
    thread_id: String,
    workspace: PathBuf,
    current_path: PathBuf,
    history_path: PathBuf,
    current: ThreadCurrent,
}

impl ColdConversation {
    async fn new(mode: ThreadWorkspaceMode) -> Result<Self> {
        let temporary = tempfile::tempdir()?;
        let home = temporary.path().join("home");
        let endpoint = configure(&home).await?;
        let repository = temporary.path().join("workspace");
        tokio::fs::create_dir(&repository).await?;
        if mode == ThreadWorkspaceMode::Worktree {
            git(&repository, &["init", "--quiet"])?;
            tokio::fs::write(repository.join("tracked.txt"), "committed\n").await?;
            git(&repository, &["add", "tracked.txt"])?;
            git(
                &repository,
                &[
                    "-c",
                    "user.name=fixture",
                    "-c",
                    "user.email=fixture@example.invalid",
                    "commit",
                    "--quiet",
                    "-m",
                    "fixture",
                ],
            )?;
        }
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&repository).await?;
        let started = runtime
            .create_thread_command(project.id, request(mode), None)
            .await?;
        let thread_id = started.thread.id;
        let paths = runtime.store.registered_session_paths(&thread_id)?;
        runtime.shutdown_runtime().await?;
        drop(runtime);
        let current_path = paths.current_file();
        let current = ThreadCurrent::from_json(&tokio::fs::read(&current_path).await?, &thread_id)?;
        let history_path = paths.history_database();
        assert!(!crate::history::requires_history_upgrade(&history_path, &thread_id).await?);
        Ok(Self {
            _temporary: temporary,
            endpoint,
            home,
            thread_id,
            workspace: started.thread.workspace_path.into(),
            current_path,
            history_path,
            current,
        })
    }

    fn set_plan(&mut self, payload: OpaquePayload) {
        self.set_extension(crate::plan_tool::PLAN_EXTENSION, payload);
    }

    fn set_extension(&mut self, key: &str, payload: OpaquePayload) {
        self.current.state.extension_sequence += 1;
        self.current.state.extensions.insert(
            key.into(),
            ExtensionRecord {
                revision: self.current.state.extension_sequence,
                payload,
            },
        );
    }

    fn set_prepared_request(&mut self, payload: OpaquePayload) {
        self.current.model_call = Some(CurrentModelCall {
            source_run_id: self.current.saved_runtime_epoch,
            source_execution_id: "saved-execution".into(),
            source_turn_id: "saved-turn".into(),
            source_attempt_id: "saved-attempt".into(),
            tools: Arc::from([]),
            tool_call_mode: ToolCallMode::Sequential,
            solo_tool_ids: Arc::from([]),
            prepared_parameters: Some(payload),
            phase: SavedModelPhase::Preparing {
                pending_step_input: None,
            },
        });
    }

    async fn save_fixture(&self) -> Result<Vec<u8>> {
        let bytes = serde_json::to_vec(&self.current)?;
        tokio::fs::write(&self.current_path, &bytes).await?;
        Ok(bytes)
    }
}

fn git(root: &Path, args: &[&str]) -> Result<String> {
    let output = std::process::Command::new("git")
        .current_dir(root)
        .args(args)
        .output()?;
    anyhow::ensure!(
        output.status.success(),
        "Git fixture {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(String::from_utf8(output.stdout)?)
}

fn legacy_plan(markdown: &str) -> String {
    json!({
        "revision": 4,
        "state": "approved",
        "document": {"version": 2, "markdown": markdown, "contentHash": content_hash(markdown.as_bytes())},
        "updatedAt": 9
    }).to_string()
}

#[tokio::test]
async fn cold_checkpoint_plan_and_timeline_survive_repeated_read_only_feed_opens() -> Result<()> {
    use crate::plan_tool::{AgentSessionPlanPhase, AgentSessionPlanRuntimeSnapshot};

    let mut saved = ColdConversation::new(ThreadWorkspaceMode::Local).await?;
    let markdown = "Keep the saved plan";
    let hash = content_hash(markdown.as_bytes());
    saved.set_plan(OpaquePayload::new(
        "pl.studio.plan",
        1,
        legacy_plan(markdown),
    )?);
    let current = saved.save_fixture().await?;
    let history = tokio::fs::read(&saved.history_path).await?;
    let request_count = saved.endpoint.recorded().len();
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    for _ in 0..2 {
        let feed = runtime
            .open_conversation_feed_with_maintenance(&saved.thread_id, 16)
            .await?;
        let meta = feed.session_meta_snapshot();
        assert!(!meta.execution_present);
        let plan = meta.plan.context("expected old plan in cold feed")?;
        assert_eq!(plan.revision, 4);
        assert_eq!(plan.state, AgentSessionPlanPhase::Approved);
        let window = feed.read_session_detail(SessionDetailKind::Plan, 0, 4096)?;
        let detail: AgentSessionPlanRuntimeSnapshot = serde_json::from_slice(&window.bytes)?;
        let document = detail.document.context("expected old Plan Markdown")?;
        assert_eq!(document.version, 2);
        assert_eq!(document.markdown, markdown);
        assert_eq!(document.content_hash, hash);
        let Some(ConversationEvent::Timeline(TimelinePatch::Reset { items, .. })) =
            feed.next_event().await
        else {
            anyhow::bail!("expected saved timeline in initial Reset");
        };
        assert!(items.iter().any(|item| matches!(item, TimelineItem::UserMessage { text, input_id: Some(input_id), .. } if text == "hello" && input_id == "standalone-start")));
        feed.close().await;
        assert!(
            runtime
                .session_of(&saved.thread_id)
                .and_then(|session| session.thread(&saved.thread_id))
                .is_none()
        );
        assert_eq!(saved.endpoint.recorded().len(), request_count);
        assert_eq!(tokio::fs::read(&saved.current_path).await?, current);
        assert_eq!(tokio::fs::read(&saved.history_path).await?, history);
    }
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn cold_checkpoint_plan_identifies_unsupported_and_malformed_payloads() -> Result<()> {
    let mut saved = ColdConversation::new(ThreadWorkspaceMode::Local).await?;
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    let history = tokio::fs::read(&saved.history_path).await?;
    let request_count = saved.endpoint.recorded().len();
    let mislabeled = legacy_plan("Do not silently clear this plan");
    for (revision, content, cause) in [
        (99, "{}", "unsupported plan payload"),
        (1, "{", "EOF"),
        (2, "{", "EOF"),
        (2, mislabeled.as_str(), "missing field `plan`"),
        (2, "{}", "missing field `plan`"),
    ] {
        saved.set_plan(OpaquePayload::new("pl.studio.plan", revision, content)?);
        let current = saved.save_fixture().await?;
        let error = runtime
            .open_conversation_feed_with_maintenance(&saved.thread_id, 16)
            .await
            .err()
            .with_context(|| format!("invalid saved plan must fail the cold feed with {cause}"))?;
        let diagnostic = format!("{error:#}");
        assert!(diagnostic.contains(cause), "{diagnostic}");
        let mapped = crate::studio_error_from_anyhow(error);
        assert_eq!(mapped.code, StudioErrorCode::Storage);
        assert!(mapped.message.contains("saved plan"), "{mapped:?}");
        assert!(
            mapped.message.contains(&format!("revision {revision}")),
            "{mapped:?}"
        );
        assert_rejected_before_publication(&runtime, &saved.thread_id);
        assert_eq!(saved.endpoint.recorded().len(), request_count);
        assert_eq!(tokio::fs::read(&saved.current_path).await?, current);
        assert_eq!(tokio::fs::read(&saved.history_path).await?, history);
    }
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn cold_checkpoint_activation_reuses_dirty_worktree_with_account_bound_request() -> Result<()>
{
    let mut saved = ColdConversation::new(ThreadWorkspaceMode::Worktree).await?;
    tokio::fs::write(saved.workspace.join("tracked.txt"), "uncommitted\n").await?;
    tokio::fs::write(saved.workspace.join("new.txt"), "untracked\n").await?;
    let status = git(&saved.workspace, &["status", "--porcelain=v1"])?;
    assert!(status.lines().any(|line| line == " M tracked.txt"));
    assert!(status.lines().any(|line| line == "?? new.txt"));
    let head = git(&saved.workspace, &["rev-parse", "HEAD"])?;
    saved.set_prepared_request(OpaquePayload::new("pl.model.prepared-request", 2, json!({
        "binding": {
            "accountId": "standalone-fixture", "modelId": "standalone-model",
            "protocol": "open_ai", "wireApi": "responses", "isolation": "saved-isolation", "purpose": "conversation"
        },
        "tools": [], "toolChoice": "auto", "parallelToolCalls": false
    }).to_string())?);
    saved.save_fixture().await?;
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    let feed = runtime.open_conversation_feed(&saved.thread_id, 16).await?;
    assert!(!feed.session_meta_snapshot().execution_present);
    feed.close().await;
    let request_count = saved.endpoint.recorded().len();
    let owner = runtime
        .ensure_thread_owner(&saved.thread_id)
        .await
        .context("restore account-bound Current into its original worktree")?;
    assert_ne!(owner.runtime_epoch(), saved.current.saved_runtime_epoch);
    assert!(
        owner.snapshot().continuation.is_some(),
        "the saved model call must restore as paused"
    );
    let binding = runtime
        .thread_factory
        .binding_snapshot(&saved.thread_id)
        .context("active tool workspace binding")?;
    assert_eq!(binding.workspace.root(), saved.workspace);
    assert!(
        !runtime
            .recovery_issues()
            .iter()
            .any(|issue| issue.thread_id.as_deref() == Some(&saved.thread_id))
    );
    assert_eq!(saved.endpoint.recorded().len(), request_count);
    assert_eq!(git(&saved.workspace, &["rev-parse", "HEAD"])?, head);
    assert_eq!(
        git(&saved.workspace, &["status", "--porcelain=v1"])?,
        status
    );
    assert_eq!(
        tokio::fs::read(saved.workspace.join("tracked.txt")).await?,
        b"uncommitted\n"
    );
    assert_eq!(
        tokio::fs::read(saved.workspace.join("new.txt")).await?,
        b"untracked\n"
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn cold_checkpoint_activation_reports_saved_data_corruption_on_healthy_worktree() -> Result<()>
{
    let mut saved = ColdConversation::new(ThreadWorkspaceMode::Worktree).await?;
    let valid = serde_json::to_vec(&saved.current)?;
    saved.set_prepared_request(OpaquePayload::new("pl.model.prepared-request", 2, "{")?);
    let bad_request = serde_json::to_vec(&saved.current)?;
    saved.current = ThreadCurrent::from_json(&valid, &saved.thread_id)?;
    saved.set_plan(OpaquePayload::new("pl.studio.plan", 2, "{")?);
    let bad_plan = serde_json::to_vec(&saved.current)?;
    saved.set_plan(OpaquePayload::new(
        "pl.studio.plan",
        2,
        legacy_plan("Do not silently clear this plan"),
    )?);
    let wrong_shape = serde_json::to_vec(&saved.current)?;
    let history = tokio::fs::read(&saved.history_path).await?;
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    let request_count = saved.endpoint.recorded().len();
    for (source, phase, revision, cause) in [
        (
            bad_request.as_slice(),
            "prepared request",
            Some("revision 2"),
            "EOF",
        ),
        (b"{", "load the saved conversation checkpoint", None, "EOF"),
        (bad_plan.as_slice(), "saved plan", Some("revision 2"), "EOF"),
        (
            wrong_shape.as_slice(),
            "saved plan",
            Some("revision 2"),
            "missing field `plan`",
        ),
    ] {
        tokio::fs::write(&saved.current_path, source).await?;
        let error = runtime
            .ensure_thread_owner(&saved.thread_id)
            .await
            .err()
            .with_context(|| {
                format!("saved-data failure in {phase} ({cause}) must fail activation")
            })?;
        let diagnostic = format!("{error:#}");
        assert!(diagnostic.contains(phase), "{diagnostic}");
        assert!(diagnostic.contains(cause), "{diagnostic}");
        let mapped = crate::studio_error_from_anyhow(error);
        assert_eq!(mapped.code, StudioErrorCode::Storage);
        assert!(mapped.message.contains(phase), "{mapped:?}");
        assert!(!mapped.retryable);
        if let Some(revision) = revision {
            assert!(mapped.message.contains(revision), "{mapped:?}");
        }
        assert_rejected_before_publication(&runtime, &saved.thread_id);
        assert_eq!(saved.endpoint.recorded().len(), request_count);
        assert_eq!(tokio::fs::read(&saved.current_path).await?, source);
        assert_eq!(tokio::fs::read(&saved.history_path).await?, history);
    }
    tokio::fs::write(&saved.current_path, valid).await?;
    let feed = runtime.open_conversation_feed(&saved.thread_id, 16).await?;
    assert!(!feed.session_meta_snapshot().execution_present);
    feed.close().await;
    runtime.shutdown_runtime().await?;
    Ok(())
}

fn assert_rejected_before_publication(runtime: &StudioRuntime, thread_id: &str) {
    assert!(
        !runtime.recovery_issues().iter().any(|issue| {
            issue.thread_id.as_deref() == Some(thread_id)
                && issue.category == crate::StudioRecoveryIssueCategory::Repository
        }),
        "saved data failure was reported as a Repository problem for {thread_id}"
    );
    assert!(runtime.thread_factory.binding_snapshot(thread_id).is_none());
    assert!(
        runtime
            .session_of(thread_id)
            .and_then(|session| session.observed_thread(thread_id))
            .is_none()
    );
}

#[tokio::test]
async fn cold_checkpoint_preparation_binding_write_failure_preserves_worktree_and_sources()
-> Result<()> {
    let saved = ColdConversation::new(ThreadWorkspaceMode::Worktree).await?;
    let current = tokio::fs::read(&saved.current_path).await?;
    let history = tokio::fs::read(&saved.history_path).await?;
    let tracked = saved.workspace.join("tracked.txt");
    let untracked = saved.workspace.join("new.txt");
    tokio::fs::write(&tracked, b"uncommitted\n").await?;
    tokio::fs::write(&untracked, b"untracked\n").await?;
    let status = git(&saved.workspace, &["status", "--porcelain=v1"])?;
    let head = git(&saved.workspace, &["rev-parse", "HEAD"])?;
    let request_count = saved.endpoint.recorded().len();
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    runtime.stop_recovery_scan().await?;
    let db = runtime.store.database();
    db.execute_unprepared(&format!(
        "CREATE TRIGGER reject_fixture_preparation_binding BEFORE UPDATE ON studio_objects \
         WHEN NEW.owner_kind='thread' AND NEW.owner_id='{}' \
           AND NEW.object_kind='threadPreparation' AND json_extract(NEW.payload_json,'$.binding.kind')='bound' \
         BEGIN SELECT RAISE(ABORT,'fixture preparation binding update blocked'); END",
        saved.thread_id,
    )).await?;
    let activation = runtime.ensure_thread_owner(&saved.thread_id).await;
    db.execute_unprepared("DROP TRIGGER reject_fixture_preparation_binding")
        .await?;
    let failure = activation
        .err()
        .context("the rejected SQLite binding update must prevent activation")?;
    assert!(
        failure.chain().any(
            |cause| cause.downcast_ref::<sea_orm::DbErr>().is_some_and(|cause| {
                cause
                    .to_string()
                    .contains("fixture preparation binding update blocked")
            })
        ),
        "{failure:#}"
    );
    assert_rejected_before_publication(&runtime, &saved.thread_id);
    let mapped = crate::studio_error_from_anyhow(failure);
    assert_eq!(mapped.code, StudioErrorCode::Storage);
    assert!(
        mapped.message.contains("conversation preparation record"),
        "{mapped:?}"
    );
    assert!(mapped.retryable);
    assert_eq!(saved.endpoint.recorded().len(), request_count);
    assert_eq!(tokio::fs::read(&saved.current_path).await?, current);
    assert!(
        tokio::fs::read(&saved.history_path).await? == history,
        "failed activation changed saved history"
    );
    assert_eq!(git(&saved.workspace, &["rev-parse", "HEAD"])?, head);
    assert_eq!(
        git(&saved.workspace, &["status", "--porcelain=v1"])?,
        status
    );
    assert_eq!(tokio::fs::read(tracked).await?, b"uncommitted\n");
    assert_eq!(tokio::fs::read(untracked).await?, b"untracked\n");
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn cold_checkpoint_workspace_check_keeps_data_errors_and_existing_diagnostics_separate()
-> Result<()> {
    let mut saved = ColdConversation::new(ThreadWorkspaceMode::Worktree).await?;
    let valid = serde_json::to_vec(&saved.current)?;
    let history = tokio::fs::read(&saved.history_path).await?;
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    runtime.stop_recovery_scan().await?;
    let request_count = saved.endpoint.recorded().len();
    for (key, format, revision, content) in [
        ("studio.project", "pl.studio.project", 1, "{"),
        ("studio.workspace", "pl.studio.workspace", 3, "{}"),
    ] {
        saved.current = ThreadCurrent::from_json(&valid, &saved.thread_id)?;
        saved.set_extension(key, OpaquePayload::new(format, revision, content)?);
        let current = saved.save_fixture().await?;
        let failure = runtime
            .ensure_thread_owner(&saved.thread_id)
            .await
            .err()
            .with_context(|| format!("corrupt {format} must refuse activation"))?;
        assert_rejected_before_publication(&runtime, &saved.thread_id);
        assert_saved_workspace_error(failure, format, revision);
        assert_eq!(saved.endpoint.recorded().len(), request_count);
        assert_eq!(tokio::fs::read(&saved.current_path).await?, current);
        assert!(
            tokio::fs::read(&saved.history_path).await? == history,
            "corrupt {format} changed saved history"
        );
    }

    let thread = runtime.read_protocol_thread(&saved.thread_id).await?;
    let valid_snapshot = ThreadCurrent::from_json(&valid, &saved.thread_id)?
        .state
        .to_paused_snapshot();
    let corrupt_snapshot = saved.current.state.to_paused_snapshot();
    let db = runtime.store.database();
    let id = saved.thread_id.as_str();
    let recorded_identity = crate::studio::store::object::studio_object::Entity::find_by_id((
        "thread".to_owned(),
        id.to_owned(),
        "workspaceIdentity".to_owned(),
    ))
    .one(db)
    .await?
    .context("frozen worktree identity fixture")?;
    let set_identity_payload = |payload: String| async move {
        let hash = content_hash(payload.as_bytes());
        let changed = db.execute_raw(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            "UPDATE studio_objects SET payload_json=?,payload_hash=? WHERE owner_kind='thread' AND owner_id=? AND object_kind='workspaceIdentity'",
            [payload.into(), hash.into(), id.to_owned().into()],
        )).await?;
        anyhow::ensure!(changed.rows_affected() == 1);
        Ok::<_, anyhow::Error>(())
    };
    set_identity_payload("{".into()).await?;
    let failure = runtime
        .verify_thread_execution_preparation(&thread, Some(&valid_snapshot))
        .await
        .expect_err("unreadable frozen identity must fail the workspace check");
    assert_rejected_before_publication(&runtime, id);
    assert_frozen_identity_storage_error(failure);
    let lease = runtime
        .agent_facility
        .worktrees
        .get(id)
        .context("original worktree lease")?;
    let failure = crate::studio::worktree::workspace_preparation::manager_from_lease(
        &runtime.store,
        &runtime.ssh_manager,
        &lease,
        None,
    )
    .await
    .err()
    .context("lease manager must fail on unreadable frozen identity")?;
    assert_frozen_identity_storage_error(failure);
    set_identity_payload(recorded_identity.payload_json.clone()).await?;

    let moved = saved.workspace.with_extension("unavailable-fixture");
    tokio::fs::rename(&saved.workspace, &moved).await?;
    let missing = runtime
        .verify_thread_execution_preparation(&thread, Some(&valid_snapshot))
        .await;
    tokio::fs::rename(&moved, &saved.workspace).await?;
    assert!(
        missing
            .expect_err("missing worktree must fail verification")
            .chain()
            .any(|cause| {
                cause
                    .downcast_ref::<std::io::Error>()
                    .is_some_and(|error| error.kind() == std::io::ErrorKind::NotFound)
            })
    );
    let issue_id = format!("execution-workspace:{}", saved.thread_id);
    let issue = || {
        runtime
            .recovery_issues()
            .into_iter()
            .find(|issue| issue.id == issue_id)
    };
    let before = issue().context("missing worktree diagnostic")?;
    let failure = runtime
        .verify_thread_execution_preparation(&thread, Some(&corrupt_snapshot))
        .await
        .expect_err("corrupt receipt prevents a new workspace verification");
    assert_saved_workspace_error(failure, "pl.studio.workspace", 3);
    assert_eq!(issue(), Some(before.clone()));
    set_identity_payload("{".into()).await?;
    let failure = runtime
        .verify_thread_execution_preparation(&thread, Some(&valid_snapshot))
        .await
        .expect_err("unreadable frozen identity cannot supersede a physical observation");
    assert_frozen_identity_storage_error(failure);
    assert_eq!(issue(), Some(before));
    set_identity_payload(recorded_identity.payload_json.clone()).await?;
    runtime
        .verify_thread_execution_preparation(&thread, Some(&valid_snapshot))
        .await?;
    assert!(
        issue().is_none(),
        "a successful workspace verification clears its old diagnostic"
    );
    let mut conflicting_identity: serde_json::Value =
        serde_json::from_str(&recorded_identity.payload_json)?;
    conflicting_identity["identity"]["root"] = json!(lease.repository_root);
    set_identity_payload(conflicting_identity.to_string()).await?;
    tokio::fs::write(&saved.current_path, &valid).await?;
    let failure = runtime
        .ensure_thread_owner(id)
        .await
        .err()
        .context("conflicting frozen identity must prevent activation")?;
    assert!(
        failure.chain().any(|cause| matches!(
            cause.downcast_ref::<crate::agent::worktree::WorktreeError>(),
            Some(crate::agent::worktree::WorktreeError::IdentityMismatch(_))
        )),
        "{failure:#}"
    );
    assert!(runtime.recovery_issues().iter().any(|issue| {
        issue.thread_id.as_deref() == Some(id)
            && issue.category == crate::StudioRecoveryIssueCategory::Repository
    }));
    set_identity_payload(recorded_identity.payload_json).await?;
    assert_eq!(tokio::fs::read(&saved.current_path).await?, valid);
    assert!(
        tokio::fs::read(&saved.history_path).await? == history,
        "identity failures changed saved history"
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

fn assert_frozen_identity_storage_error(error: anyhow::Error) {
    assert!(
        error.chain().any(|cause| cause.is::<serde_json::Error>()),
        "{error:#}"
    );
    let mapped = crate::studio_error_from_anyhow(error);
    assert_eq!(mapped.code, StudioErrorCode::Storage);
    assert!(
        mapped.message.contains("frozen workspace identity"),
        "{mapped:?}"
    );
    assert!(!mapped.retryable);
}

fn assert_saved_workspace_error(error: anyhow::Error, format: &str, revision: u32) {
    assert!(
        error.chain().any(|cause| cause.is::<serde_json::Error>()),
        "{error:#}"
    );
    let mapped = crate::studio_error_from_anyhow(error);
    assert_eq!(mapped.code, StudioErrorCode::Storage);
    assert!(
        mapped.message.contains("saved workspace binding"),
        "{mapped:?}"
    );
    assert!(mapped.message.contains(format), "{mapped:?}");
    assert!(
        mapped.message.contains(&format!("revision {revision}")),
        "{mapped:?}"
    );
    assert!(!mapped.retryable);
}

#[tokio::test]
async fn cold_checkpoint_activation_reports_corrupt_model_route_on_healthy_worktree() -> Result<()>
{
    let mut saved = ColdConversation::new(ThreadWorkspaceMode::Worktree).await?;
    let route = saved
        .current
        .state
        .extensions
        .get_mut(crate::studio::model_route::MODEL_ROUTE_EXTENSION)
        .context("fixture must have a saved model route")?;
    route.payload = OpaquePayload::new(route.payload.format(), route.payload.version(), "{")?;
    let current = saved.save_fixture().await?;
    let history = tokio::fs::read(&saved.history_path).await?;
    let request_count = saved.endpoint.recorded().len();
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    let error = runtime
        .ensure_thread_owner(&saved.thread_id)
        .await
        .err()
        .context("corrupt model route must fail activation")?;
    let diagnostic = format!("{error:#}");
    assert!(
        diagnostic.contains("model route") && diagnostic.contains("EOF"),
        "{diagnostic}"
    );
    assert_rejected_before_publication(&runtime, &saved.thread_id);
    let mapped = crate::studio_error_from_anyhow(error);
    assert_eq!(mapped.code, StudioErrorCode::Storage);
    assert!(mapped.message.contains("saved model route"), "{mapped:?}");
    assert_eq!(saved.endpoint.recorded().len(), request_count);
    assert_eq!(tokio::fs::read(&saved.current_path).await?, current);
    assert_eq!(tokio::fs::read(&saved.history_path).await?, history);
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn cold_checkpoint_native_send_distinguishes_child_data_and_workspace_failures() -> Result<()>
{
    use pl_tool::collaboration::control::AgentCallContext;
    use pl_tool::collaboration::thread::{AgentControlHost, AgentMessage};

    let saved = ColdConversation::new(ThreadWorkspaceMode::Worktree).await?;
    let runtime = StudioRuntime::initialize(options(&saved.home)).await?;
    runtime.save_user_agent_profile(
        "save-recovery-fixture".into(),
        None,
        "recovery-fixture",
        &crate::config::UserAgentProfile {
            enabled: true,
            display_name: "Recovery fixture".into(),
            description: "Run in an isolated Git worktree".into(),
            when_to_use: "Child cold recovery fixture".into(),
            workspace_mode: crate::AgentWorkspaceMode::Worktree,
            binding: crate::AgentBinding::Native(crate::NativeAgentConfig {
                route: Some(request(ThreadWorkspaceMode::Worktree).route),
                system_instructions: Some("Execute the isolated fixture task.".into()),
            }),
        },
    )?;
    let root = runtime.ensure_thread_owner(&saved.thread_id).await?;
    let owner = runtime.require_session(&saved.thread_id)?;
    let (caller, _, _) = runtime
        .agent_facility
        .product_events
        .agent_execution_identity(&saved.thread_id)
        .context("root execution identity")?;
    let resources = owner.native_resources(&root)?;
    let profiles = runtime.config_runtime.agent_profiles_snapshot()?;
    let delegation =
        crate::studio::delegation::saved(&root.snapshot())?.context("root delegation")?;
    let host = owner.native_agent_host(&caller, &resources, &profiles, delegation)?;
    let call = |id: &str| AgentCallContext {
        caller: caller.agent_id.clone(),
        call_id: id.into(),
        cancellation: Default::default(),
    };
    let spawn = host.spawn(call("spawn"), serde_json::from_value(json!({
        "profileId": "recovery-fixture", "taskSummary": "Create an isolated child", "message": "Initial task"
    }))?).await?;
    assert!(spawn.receipt.message_accepted, "{:?}", spawn.message_error);
    let agent = crate::AgentId::new(spawn.receipt.agent_id)?;
    let child = runtime
        .agent_facility
        .product_events
        .member_identity(&caller.session_id, &agent)
        .context("child execution identity")?;
    let id = child.thread_id.as_str();
    let lease = runtime
        .agent_facility
        .worktrees
        .get(id)
        .context("child worktree lease")?;
    let paths = runtime.store.registered_session_paths(id)?;
    let history_owner = runtime.store.history(id).await?;
    owner.close(id).await?;
    // Capture bytes after the writer and reader pools close and SQLite folds in the WAL.
    history_owner.close().await?;
    drop(history_owner);
    assert!(owner.observed_thread(id).is_none());
    let current = tokio::fs::read(paths.current_file()).await?;
    let history = tokio::fs::read(paths.history_database()).await?;
    let request_count = saved.endpoint.recorded().len();
    let send = |input_id: &str| {
        host.send(
            call(input_id),
            AgentMessage {
                id: input_id.into(),
                target: agent.to_string(),
                message: "Resume isolated child".into(),
            },
        )
    };
    tokio::fs::write(paths.current_file(), b"{").await?;
    let error = send("bad-child-current")
        .await
        .expect_err("invalid child Current must refuse the message");
    let error = anyhow::Error::new(error);
    let diagnostic = format!("{error:#}");
    assert!(
        diagnostic.contains("load the saved conversation checkpoint") && diagnostic.contains("EOF"),
        "{diagnostic}"
    );
    assert_rejected_before_publication(&runtime, id);
    assert_eq!(
        crate::studio_error_from_anyhow(error).code,
        StudioErrorCode::Storage
    );
    assert_eq!(tokio::fs::read(paths.current_file()).await?, b"{");
    assert!(
        tokio::fs::read(paths.history_database()).await? == history,
        "child data rejection changed the saved history bytes"
    );

    tokio::fs::write(paths.current_file(), &current).await?;
    let original = PathBuf::from(lease.path);
    let moved = original.with_extension("unavailable-fixture");
    tokio::fs::rename(&original, &moved).await?;
    let missing = send("missing-child-worktree").await;
    let recreated = original.exists();
    tokio::fs::rename(&moved, &original).await?;
    let error =
        anyhow::Error::new(missing.expect_err("missing child worktree must refuse the message"));
    assert!(
        error.chain().any(|cause| cause
            .downcast_ref::<std::io::Error>()
            .is_some_and(|error| error.kind() == std::io::ErrorKind::NotFound)),
        "{error:#}"
    );
    assert!(!recreated);
    assert!(
        runtime.recovery_issues().iter().any(|issue| {
            issue.id == format!("worktree-lease-{id}")
                && issue.category == crate::StudioRecoveryIssueCategory::Repository
                && issue
                    .worktree
                    .as_ref()
                    .is_some_and(|worktree| worktree.path == original.to_string_lossy())
        }),
        "missing child worktree lost its lease diagnostic"
    );
    assert!(owner.observed_thread(id).is_none());
    assert_eq!(saved.endpoint.recorded().len(), request_count);
    assert_eq!(tokio::fs::read(paths.current_file()).await?, current);
    assert!(
        tokio::fs::read(paths.history_database()).await? == history,
        "child workspace rejection changed the saved history bytes"
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}
