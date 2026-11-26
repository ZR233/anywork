//! Independent bot migration, review admission and saved-workspace invariants.

use super::*;
use crate::test_support::storage::close_factory;
use crate::thread_assembler::StudioChildResources;
use crate::thread_assembler::{StudioActivationFactory, ThreadActivation, ThreadPreparation};
use anyhow::{Context, Result};
use pl_core::thread::{ThreadHandle, extensions::ExtensionMutation};
use pl_tool::workspace::SessionFiles;

use crate::thread_assembler::test_support::{
    CloseFactoryFixture, CorruptCurrentAfterLoad, spawn_live_projection_for_thread,
};
use std::path::PathBuf;

fn migration_review_target(agent_id: &str) -> crate::AgentReviewTargetSnapshot {
    crate::AgentReviewTargetSnapshot {
        agent_id: agent_id.into(),
        feedback: None,
        baseline: Some(crate::AgentReviewBaseline {
            turn_id: format!("migration-fixture-terminal:{agent_id}"),
            input_id: None,
            terminal_sequence: 1,
            commit_sequence: 1,
            input_ordinal: 0,
            message_sequence: 0,
            consumed_messages: 0,
            wake_messages_through: 0,
            execution_sequence: 0,
            continuation_id: None,
        }),
    }
}

struct MigrationFixture {
    business: PathBuf,
    store: crate::studio::StudioStore,
    root: crate::Thread,
    fixture: CloseFactoryFixture,
    managed: PathBuf,
    profile: crate::config::ResolvedAgentProfile,
    request: ChildThreadRequest,
    // Release database/factory handles before removing their directory on every platform.
    temp: tempfile::TempDir,
}
struct MigrationCopy {
    files: SessionFiles,
    canonical: PathBuf,
    marker: PathBuf,
    completion: String,
}
impl MigrationFixture {
    async fn new() -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let business = dunce::canonicalize(temp.path())?.join("business");
        tokio::fs::create_dir_all(&business).await?;
        tokio::fs::write(business.join("business.txt"), b"not migration-owned").await?;
        let store =
            crate::studio::StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let mut root = crate::Thread::placeholder("bot-root");
        root.workspace_id = "bot-project".into();
        root.root_thread_id = root.id.clone();
        root.workspace_path = business.to_string_lossy().into_owned();
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: root.workspace_id.clone(),
                kind: crate::WorkspaceKind::Project,
                name: "Original project".into(),
                path: root.workspace_path.clone(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        let (root_session, root_agent) = crate::studio::records::directory_facts_from_thread(&root);
        delta
            .session_upserts
            .push(root_session.expect("root session facts"));
        delta.agent_upserts.push(root_agent);
        store.persist_directory_summaries(&delta).await?;
        let fixture = close_factory(&store)?;
        let factory = &fixture.factory;
        factory
            .services
            .product_events
            .initialize_directories()
            .await?;
        factory
            .services
            .bots
            .install_workspace_migration_fixture("botA1234", &root.id, &root.workspace_id)
            .await?;
        let bot = factory
            .services
            .bots
            .saved_config_for_thread(&root.id)
            .await?
            .context("saved bot binding")?;
        let managed = factory.services.bots.workspace_root(&bot);
        assert!(!tokio::fs::try_exists(&managed).await?);
        let config = crate::config::StudioConfig::default_config()?;
        let selector = config.mode_model_route(&crate::mode::ThreadModeId::auto())?;
        let route = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), selector)?;
        let frozen_profile = crate::AgentProfileSnapshot {
            profile_id: "migration-child".into(),
            display_name: "Migration child".into(),
            description: "Workspace migration admission".into(),
            when_to_use: "migration fault fixture".into(),
            system_instructions: "Retain original workspace evidence".into(),
            account_id: selector.account_id.as_str().into(),
            model_id: selector.model_id.clone(),
            effort: selector
                .effort
                .as_ref()
                .map(|effort| effort.as_str().into()),
            source: "fixture".into(),
            revision: "1".into(),
            content_hash: "fixture-profile".into(),
            system: false,
            enabled: true,
            workspace_mode: AgentWorkspaceMode::Worktree,
        };
        let profile = crate::config::ResolvedAgentProfile {
            revision: 1,
            definition: frozen_profile.definition(),
            binding: frozen_profile.native_binding(),
            profile: frozen_profile,
            config: config.clone(),
            route,
        };
        let request = ChildThreadRequest {
            workspace_owner: Default::default(),
            id: "rejected-worktree".into(),
            cancellation: Default::default(),
            caller: root.id.clone(),
            call_id: "migration-preflight".into(),
            profile_id: profile.profile.profile_id.clone(),
            model_selection: None,
            delegation: Default::default(),
            task_summary: pl_tool::collaboration::thread::AgentTaskSummary::try_from(
                "Workspace migration".to_owned(),
            )?,
            writable_paths: None,
            review_target_agent_id: None,
            review_feedback: None,
            review_target: None,
            review_workspace: None,
            metadata: pl_core::context::OpaquePayload::text("migration fixture"),
        };
        Ok(Self {
            temp,
            business,
            store,
            root,
            fixture,
            managed,
            profile,
            request,
        })
    }
    async fn migrate_root(&self) -> Result<MigrationCopy> {
        let Self {
            business,
            store,
            root,
            fixture,
            managed,
            ..
        } = self;
        let factory = &fixture.factory;
        // The production migration helper admits a not-yet-materialized target and gives the
        // original preparer the final canonical use before copying its first execution file.
        let files = SessionFiles::new(&root.id);
        tokio::fs::create_dir_all(business.join(files.root()).join("scratch")).await?;
        tokio::fs::write(
            business.join(files.root()).join("scratch/original"),
            b"retained original",
        )
        .await?;
        let mut project = store.read_project(&root.workspace_id).await?.unwrap();
        let execution = factory
            .reserve_thread_workspace_use(&root.id, &root.id, &project)
            .await?;
        let canonical = factory
            .bind_bot_project(
                &root.id,
                &root.id,
                &mut project,
                &execution,
                super::super::bot_workspace::BotWorkspacePreparation::Existing,
            )
            .await?
            .unwrap();
        assert_eq!(canonical, dunce::canonicalize(managed)?);
        assert_eq!(
            tokio::fs::read(managed.join(files.scratch()).join("original")).await?,
            b"retained original"
        );
        // Existing Windows completions may retain native separators and a safe verbatim prefix.
        let completion = tokio::fs::canonicalize(business.join(files.root()))
            .await?
            .to_string_lossy()
            .into_owned();
        let marker = managed.join(files.root()).join(".migration-complete");
        tokio::fs::write(&marker, completion.as_bytes()).await?;
        assert!(fixture.workspace_is_busy(&root.id));
        let frozen = store.workspace_identity(&root.id).await?.unwrap();
        assert_eq!(frozen, local_identity(managed).await?);
        // Windows' native canonical path uses an extended prefix. Re-admitting that same site
        // must retain both the active use and the original durable spelling, without rebinding.
        let equivalent = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            tokio::fs::canonicalize(&managed)
                .await?
                .to_string_lossy()
                .into_owned(),
        )?;
        factory
            .services
            .worktrees
            .assign_workspace(&execution, equivalent.clone())?;
        store.bind_workspace_identity(&root.id, &equivalent).await?;
        assert_eq!(
            store.workspace_identity(&root.id).await?.unwrap().root,
            frozen.root
        );
        drop(execution);

        Ok(MigrationCopy {
            files,
            canonical,
            marker,
            completion,
        })
    }
    async fn add_review_target(&mut self) -> Result<crate::Thread> {
        let Self {
            store,
            root,
            fixture,
            managed,
            profile,
            request,
            ..
        } = self;
        let factory = &fixture.factory;
        let mut target = (*root).clone();
        target.id = "bot-reviewed".into();
        target.agent_path = target.id.clone();
        target.parent_thread_id = Some(root.id.clone());
        target.workspace_path = managed.to_string_lossy().into_owned();
        factory
            .services
            .product_events
            .commit_directory(crate::studio::store::directory::DirectoryDelta {
                agent_upserts: vec![crate::studio::records::directory_facts_from_thread(&target).1],
                ..Default::default()
            })
            .await?;
        store
            .bind_workspace_identity(&target.id, &local_identity(managed).await?)
            .await?;
        profile.profile.workspace_mode = AgentWorkspaceMode::Review;
        request.id = "allowed-review".into();
        request.review_target_agent_id = Some(target.id.clone());
        request.review_workspace = Some(crate::AgentWorkspaceAssignmentSnapshot {
            mode: AgentWorkspaceMode::Directory,
            project_root: target.workspace_path.clone(),
            root: target.workspace_path.clone(),
            writable_paths: None,
            worktree: None,
            review_target: None,
        });
        factory
            .check_bot_spawn_workspace(
                request,
                profile.profile.workspace_mode,
                &factory.directory_member(&root.id)?,
                Some(managed),
            )
            .await?;
        assert!(
            !tokio::fs::try_exists(managed.join(SessionFiles::new(&request.id).root())).await?,
            "read-only admission does not prepare execution files"
        );

        Ok(target)
    }
    async fn other_root(&self) -> Result<(crate::Thread, PathBuf)> {
        let Self {
            temp,
            store,
            root,
            fixture,
            ..
        } = self;
        let factory = &fixture.factory;
        let mut target = root.clone();
        target.parent_thread_id = Some(root.id.clone());
        let other_root = temp.path().join("other-execution-root");
        tokio::fs::create_dir_all(&other_root).await?;
        let mut other = target.clone();
        other.id = "different-root-reviewed".into();
        other.agent_path = other.id.clone();
        other.workspace_path = other_root.to_string_lossy().into_owned();
        factory
            .services
            .product_events
            .commit_directory(crate::studio::store::directory::DirectoryDelta {
                agent_upserts: vec![crate::studio::records::directory_facts_from_thread(&other).1],
                ..Default::default()
            })
            .await?;
        store
            .bind_workspace_identity(&other.id, &local_identity(&other_root).await?)
            .await?;
        Ok((other, other_root))
    }
    async fn shutdown(&self) -> Result<()> {
        self.fixture.factory.services.bots.shutdown().await?;
        self.fixture.shutdown().await
    }
}

#[tokio::test]
async fn worktree_admission_rejects_before_migration_or_lease() -> Result<()> {
    let scenario = MigrationFixture::new().await?;
    let MigrationFixture {
        store,
        root,
        fixture,
        managed,
        profile,
        request,
        ..
    } = &scenario;
    let factory = &fixture.factory;
    let rejected = factory
        .check_bot_spawn_workspace(
            request,
            profile.profile.workspace_mode,
            &factory.directory_member(&root.id)?,
            Some(managed),
        )
        .await;
    assert!(
        matches!(&rejected, Err(ThreadAssemblyError::Workspace { .. })),
        "worktree rejection must precede Git discovery or migration: {:?}",
        rejected.err()
    );
    assert!(!tokio::fs::try_exists(&managed).await?);
    assert!(store.workspace_identity(&request.id).await?.is_none());
    assert!(factory.services.worktrees.snapshot().is_empty());
    assert!(!fixture.workspace_is_busy(&request.id));

    scenario.shutdown().await
}

#[tokio::test]
async fn migration_owns_first_copy_and_preserves_canonical_binding() -> Result<()> {
    let scenario = MigrationFixture::new().await?;
    scenario.migrate_root().await?;
    scenario.shutdown().await
}

#[tokio::test]
async fn review_admission_accepts_only_the_managed_root_without_preparing_files() -> Result<()> {
    let mut scenario = MigrationFixture::new().await?;
    scenario.migrate_root().await?;
    scenario.add_review_target().await?;
    let (other, _other_root) = scenario.other_root().await?;
    let MigrationFixture {
        store,
        root,
        fixture,
        managed,
        profile,
        request,
        ..
    } = &mut scenario;
    let factory = &fixture.factory;
    request.id = "rejected-review".into();
    request.review_target_agent_id = Some(other.id.clone());
    request.review_target = Some(migration_review_target(&other.id));
    request.review_workspace = Some(crate::AgentWorkspaceAssignmentSnapshot {
        mode: AgentWorkspaceMode::Directory,
        project_root: other.workspace_path.clone(),
        root: other.workspace_path.clone(),
        writable_paths: None,
        worktree: None,
        review_target: None,
    });
    let original_binding = store.workspace_identity(&other.id).await?;
    let original_project = store.read_project(&root.workspace_id).await?;
    let rejected = factory
        .check_bot_spawn_workspace(
            request,
            profile.profile.workspace_mode,
            &factory.directory_member(&root.id)?,
            Some(managed),
        )
        .await;
    assert!(
        matches!(&rejected, Err(ThreadAssemblyError::Workspace { .. })),
        "cross-root review rejection must precede migration: {:?}",
        rejected.err()
    );
    assert_eq!(store.workspace_identity(&other.id).await?, original_binding);
    assert_eq!(
        store.read_project(&root.workspace_id).await?,
        original_project
    );
    assert!(factory.services.worktrees.snapshot().is_empty());
    assert!(!fixture.workspace_is_busy(&request.id));
    assert!(store.workspace_identity(&request.id).await?.is_none());
    assert!(!tokio::fs::try_exists(managed.join(SessionFiles::new(&request.id).root())).await?);

    scenario.shutdown().await
}

#[tokio::test]
async fn incompatible_saved_worktree_preserves_original_facts_and_files() -> Result<()> {
    let mut scenario = MigrationFixture::new().await?;
    scenario.migrate_root().await?;
    let (other, other_root) = scenario.other_root().await?;
    let MigrationFixture {
        store,
        fixture,
        managed,
        profile,
        ..
    } = &mut scenario;
    let factory = &fixture.factory;
    // An old incompatible current is rejected before instruction/route migration, binding
    // changes or tools. Its original history and exact execution files remain available.
    let mut old = other.clone();
    old.id = "legacy-bot-worktree".into();
    old.agent_path = old.id.clone();
    old.role = profile.profile.profile_id.clone();
    store
        .persist_directory_summaries(&crate::studio::store::directory::DirectoryDelta {
            agent_upserts: vec![crate::studio::records::directory_facts_from_thread(&old).1],
            ..Default::default()
        })
        .await?;
    let assignment = crate::AgentWorkspaceAssignmentSnapshot {
        mode: AgentWorkspaceMode::Worktree,
        project_root: other.workspace_path.clone(),
        root: other.workspace_path.clone(),
        writable_paths: None,
        worktree: Some(crate::AgentWorktreeSnapshot {
            repository_root: other.workspace_path.clone(),
            path: other.workspace_path.clone(),
            base_commit: "a".repeat(40),
        }),
        review_target: None,
    };
    profile.profile.workspace_mode = AgentWorkspaceMode::Worktree;
    let core = ThreadHandle::restore_current(
        pl_core::thread::current::ThreadCurrent::new(
            old.id.clone(),
            pl_core::thread::current::RuntimeEpoch::new(),
        ),
        None,
    )?;
    let epoch = core.runtime_epoch();
    let mut current_store = store.state_for(&old.workspace_id, &old.id)?;
    current_store
        .attach_current(
            store.thread_persistence().clone(),
            None,
            epoch,
            crate::studio::storage::current_writer::CurrentSource::from_thread(core.clone()),
        )
        .await?;

    core.mutate_extensions(vec![
        ExtensionMutation::Put {
            id: crate::studio::workspace_receipt::EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::workspace_receipt::to_payload(&assignment)
                .map_err(anyhow::Error::msg)?,
        },
        ExtensionMutation::Put {
            id: crate::studio::model_route::AGENT_PROFILE_EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::model_route::encode_profile(&profile.profile)?,
        },
    ])
    .await?;
    current_store
        .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
        .await?;
    let current = store
        .state_for(&old.workspace_id, &old.id)?
        .load_current()
        .await?
        .context("closed fixture current")?;
    let before = serde_json::to_vec(&current)?;
    let old_files = other_root.join(SessionFiles::new(&old.id).root());
    tokio::fs::create_dir_all(&old_files).await?;
    tokio::fs::write(old_files.join("original"), b"old identity preserved").await?;
    let current_path = store.registered_session_paths(&old.id)?.current_file();
    let saved_bytes = tokio::fs::read(&current_path).await?;
    tokio::fs::write(&current_path, b"invalid current after preparation handoff").await?;
    let outcome = StudioActivationFactory::prepare(
        factory,
        ThreadPreparation {
            workspace_owner: Default::default(),
            identity: ThreadActivation::native_test(&old.id, old.parent_thread_id.as_deref()),
            cancellation: Default::default(),
            agent_controls: vec![],
            delegation: None,
            current: Some(current),
        },
    )
    .await;
    tokio::fs::write(&current_path, saved_bytes).await?;
    assert!(
        matches!(outcome, Err(ThreadAssemblyError::Workspace { ref reason, .. })
        if reason.contains("incompatible worktree/Profile binding")),
        "{outcome:?}"
    );
    assert_eq!(
        serde_json::to_vec(
            &store
                .state_for(&old.workspace_id, &old.id)?
                .load_current()
                .await?
                .context("preserved fixture current")?
        )?,
        before
    );
    assert_eq!(
        tokio::fs::read(old_files.join("original")).await?,
        b"old identity preserved"
    );
    assert!(store.workspace_identity(&old.id).await?.is_none());
    assert!(!tokio::fs::try_exists(managed.join(SessionFiles::new(&old.id).root())).await?);

    scenario.shutdown().await
}

#[tokio::test]
async fn removed_source_still_uses_managed_root_for_new_directory_and_review_members() -> Result<()>
{
    let mut scenario = MigrationFixture::new().await?;
    let MigrationCopy {
        files,
        canonical,
        marker,
        completion,
    } = scenario.migrate_root().await?;
    let MigrationFixture {
        temp,
        business,
        store,
        root,
        fixture,
        managed,
        profile,
        request,
        ..
    } = &mut scenario;
    let factory = &fixture.factory;
    tokio::fs::rename(&business, temp.path().join("old-source-unmounted")).await?;
    factory
        .verify_execution_workspace(
            root,
            None,
            super::super::execution_admission::ExecutionWorkspaceCheck::Audit,
        )
        .await?;
    let mut project = store.read_project(&root.workspace_id).await?.unwrap();
    let execution = factory
        .reserve_thread_workspace_use(&root.id, &root.id, &project)
        .await?;
    assert_eq!(
        factory
            .bind_bot_project(
                &root.id,
                &root.id,
                &mut project,
                &execution,
                super::super::bot_workspace::BotWorkspacePreparation::Existing
            )
            .await?,
        Some(canonical)
    );
    assert!(!tokio::fs::try_exists(&business).await?);
    assert_eq!(tokio::fs::read_to_string(&marker).await?, completion);
    assert_eq!(
        tokio::fs::read(managed.join(files.scratch()).join("original"))
            .await
            .context("read migrated temp after the original bot workspace source is unmounted")?,
        b"retained original"
    );
    drop(execution);

    // New identities use M directly after O disappears. Drive actual factory preparation and
    // product registration, then retire exactly the extensions returned by that preparation.
    profile.config.runtime.tool_capabilities = pl_tool::workspace::ToolCapabilityConfig {
        exec: false,
        workspace_files: false,
        skills: false,
        mcp: false,
        lsp: false,
        ask_user: false,
        git: false,
    };
    profile.config.skills.enabled = false;
    let mut prepared = Vec::new();
    let mut prepared_workspace = None;
    for (id, mode, reviewed) in [
        ("new-bot-directory", AgentWorkspaceMode::Directory, None),
        (
            "new-bot-review",
            AgentWorkspaceMode::Review,
            Some("new-bot-directory"),
        ),
    ] {
        request.id = id.into();
        request.workspace_owner = Default::default();
        request.review_target_agent_id = reviewed.map(str::to_owned);
        request.review_target = reviewed.map(migration_review_target);
        request.review_workspace = reviewed.and(prepared_workspace.clone());
        profile.profile.workspace_mode = mode;
        let spec = StudioChildResources::prepare(factory, request, profile).await?;
        let registered = factory
            .services
            .product_events
            .thread_snapshot(id)?
            .context("factory registered child")?;
        assert_eq!(registered.workspace_path, root.workspace_path);
        let assignment = spec
            .initial_extensions
            .get(crate::studio::workspace_receipt::EXTENSION)
            .unwrap();
        let assignment = crate::studio::workspace_receipt::from_payload(assignment)
            .map_err(anyhow::Error::msg)?;
        assert_eq!(
            assignment.root,
            dunce::canonicalize(&managed)?.to_string_lossy()
        );
        assert_ne!(registered.workspace_path, assignment.root);
        if let Some(target) = &request.review_target {
            assert_eq!(assignment.review_target.as_ref(), Some(target));
            let reviewed_workspace = request.review_workspace.as_ref().unwrap();
            assert_eq!(assignment.root, reviewed_workspace.root);
            assert_eq!(assignment.project_root, reviewed_workspace.project_root);
        }
        prepared_workspace = Some(assignment);
        let extensions = spec.initial_extensions.clone();
        drop(spec);
        request.workspace_owner = Default::default();
        let core = ThreadHandle::restore_current(
            pl_core::thread::current::ThreadCurrent::new(
                registered.id.clone(),
                pl_core::thread::current::RuntimeEpoch::new(),
            ),
            None,
        )?;
        let epoch = core.runtime_epoch();
        let mut current_store = store.state_for(&registered.workspace_id, &registered.id)?;
        current_store
            .attach_current(
                store.thread_persistence().clone(),
                None,
                epoch,
                crate::studio::storage::current_writer::CurrentSource::from_thread(core.clone()),
            )
            .await?;

        core.mutate_extensions(
            extensions
                .into_iter()
                .map(|(id, payload)| ExtensionMutation::Put {
                    id,
                    expected_revision: None,
                    payload,
                })
                .collect(),
        )
        .await?;
        prepared.push((registered, core, current_store, epoch));
    }
    for (registered, core, current_store, epoch) in prepared.into_iter().rev() {
        let snapshot = core.snapshot();
        let restore_directory = registered.id == "new-bot-directory";
        if restore_directory {
            current_store
                .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await?;
            store
                .thread_persistence()
                .history_channel(&registered.id)
                .stop_and_join()
                .await?;
            let activation = factory.activation(&registered.id)?;
            let owner = crate::session::SessionRuntime::open(activation.agent.session_id.clone());
            fixture.install(&owner)?;
            owner.retain_directory_identity(&factory.activation(&root.id)?.agent)?;
            let resumed = owner
                .activate(
                    activation,
                    CorruptCurrentAfterLoad::with_pending_model_input(
                        factory.clone(),
                        store,
                        &registered.id,
                    )
                    .await?,
                )
                .await?;
            assert!(
                owner
                    .thread(&registered.id)
                    .is_some_and(|thread| thread.same_instance(&resumed))
            );
            CorruptCurrentAfterLoad::assert_recovered_model_input(&resumed).await?;
            let projection = spawn_live_projection_for_thread(store.clone(), &registered.id);
            let closed = tokio::time::timeout(
                std::time::Duration::from_secs(10),
                owner.close(&registered.id),
            )
            .await;
            if !matches!(closed, Ok(Ok(()))) {
                projection.abort();
            }
            let projected = projection.await;
            closed??;
            projected?;
        }
        factory
            .begin_child_close(&registered, Some(&snapshot), false)
            .await?;
        factory.begin_child_close(&registered, None, false).await?;
        if !restore_directory {
            current_store
                .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await?;
        }
        factory.finish_child_execution(&registered).await?;
        factory.finish_child_worktree_cleanup(&registered).await?;
        let result = store.agent_close(&registered.id).await?.unwrap().result();
        assert!(result.execution_closed);
        assert_eq!(
            result.worktree_cleanup,
            pl_tool::collaboration::control::AgentWorktreeCleanup::NotApplicable
        );
        assert!(
            store
                .state_for(&registered.workspace_id, &registered.id)?
                .load_current()
                .await?
                .is_some()
        );
        assert!(
            factory
                .ensure_member_execution_allowed(&registered.id)
                .await
                .is_err()
        );
        assert!(
            tokio::fs::try_exists(managed.join(SessionFiles::new(&registered.id).root())).await?
        );
        assert!(tokio::fs::try_exists(&managed).await?);
    }
    scenario.shutdown().await
}
