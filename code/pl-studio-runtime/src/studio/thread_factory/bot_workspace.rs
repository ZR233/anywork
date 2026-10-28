//! Bot execution admission is read-only and precedes migration, tools, worktrees and model opening.
use super::{StudioThreadFactory, errors::resource_error};
use crate::studio::agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity};
use crate::thread_assembler::{ChildThreadRequest, ThreadAssemblyError};
use pl_protocol::{AgentWorkspaceMode, ThreadWorkspaceMode};
use std::path::Path;

impl StudioThreadFactory {
    pub(super) async fn check_bot_spawn_workspace(
        &self,
        request: &ChildThreadRequest,
        profile: &crate::config::ResolvedAgentProfile,
        root: &crate::studio::ThreadRecord,
    ) -> Result<(), ThreadAssemblyError> {
        let Some(bot) = self
            .services
            .bots
            .config_for_thread(&root.id)
            .await
            .map_err(|error| resource_error("read bot workspace admission", error))?
        else {
            return Ok(());
        };
        if root.workspace_mode != ThreadWorkspaceMode::Local
            || profile.profile.workspace_mode == AgentWorkspaceMode::Worktree
        {
            return Err(bot_workspace_refusal(
                &request.id,
                "bot children must use the bot-managed execution root; worktree Profiles are not permitted",
            ));
        }
        self.ensure_bot_execution_workspace(&root.clone().into(), None)
            .await?;
        if profile.profile.workspace_mode == AgentWorkspaceMode::Review {
            let target = request.review_target_agent_id.as_deref().ok_or_else(|| {
                bot_workspace_refusal(&request.id, "bot review requires a frozen review target")
            })?;
            let expected = local_identity(&self.services.bots.workspace_root(&bot)).await?;
            self.check_bot_review_target(&request.id, &root.id, target, &expected)
                .await?;
        }
        Ok(())
    }

    /// Existing incompatible records remain readable. This gate neither migrates their history nor
    /// rewrites a binding; it only denies activation/continuation and emits a typed workspace error.
    pub(crate) async fn ensure_bot_execution_workspace(
        &self,
        thread: &pl_protocol::Thread,
        snapshot: Option<&pl_core::thread::ThreadSnapshot>,
    ) -> Result<(), ThreadAssemblyError> {
        let Some(bot) = self
            .services
            .bots
            .config_for_thread(&thread.root_thread_id)
            .await
            .map_err(|error| resource_error("read saved bot workspace admission", error))?
        else {
            return Ok(());
        };
        if thread.workspace_mode != ThreadWorkspaceMode::Local {
            return Err(bot_workspace_refusal(
                &thread.id,
                "saved bot session uses a worktree root; its binding and history were preserved",
            ));
        }
        let managed = self.services.bots.workspace_root(&bot);
        if thread.parent_thread_id.is_none() {
            // A pre-migration root may have no physical identity yet. A frozen assignment, however,
            // cannot be rebound to the managed root to make incompatible old execution look valid.
            if let Some(frozen) = self
                .services
                .store
                .workspace_identity(&thread.id)
                .await
                .map_err(|error| resource_error("read frozen bot root identity", error))?
            {
                let expected = local_identity(&managed).await?;
                self.check_bot_frozen_identity(&thread.id, &frozen, &expected)
                    .await?;
            }
            return Ok(());
        }
        let loaded;
        let snapshot = match snapshot {
            Some(snapshot) => snapshot,
            None => {
                loaded = super::recovery::load_checkpoint_read_only(&self.services.store, thread)
                    .await
                    .map_err(|error| resource_error("read saved bot child admission", error))?
                    .ok_or_else(|| {
                        bot_workspace_refusal(
                            &thread.id,
                            "bot child has no saved workspace receipt",
                        )
                    })?;
                &loaded.state
            }
        };
        let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)
            .map_err(|error| resource_error("decode saved bot workspace receipt", error))?
            .ok_or_else(|| {
                bot_workspace_refusal(&thread.id, "bot child has no frozen workspace assignment")
            })?;
        let profile = crate::studio::model_route::required_saved_profile(snapshot, &thread.id)
            .map_err(|error| resource_error("decode saved bot child Profile", error))?;
        if assignment.mode == AgentWorkspaceMode::Worktree
            || assignment.worktree.is_some()
            || profile.workspace_mode != assignment.mode
        {
            return Err(bot_workspace_refusal(
                &thread.id,
                "saved bot child has an incompatible worktree/Profile binding; original data was preserved",
            ));
        }
        let expected = local_identity(&managed).await?;
        let actual = local_identity(Path::new(&assignment.root)).await?;
        let project = local_identity(Path::new(&assignment.project_root)).await?;
        if actual != expected || project != expected {
            return Err(bot_workspace_refusal(
                &thread.id,
                "saved bot child execution root differs from its bot-managed canonical root",
            ));
        }
        if let Some(frozen) = self
            .services
            .store
            .workspace_identity(&thread.id)
            .await
            .map_err(|error| resource_error("read frozen bot child identity", error))?
        {
            self.check_bot_frozen_identity(&thread.id, &frozen, &expected)
                .await?;
        }
        if assignment.mode == AgentWorkspaceMode::Review {
            let target = assignment.review_target.as_ref().ok_or_else(|| {
                bot_workspace_refusal(&thread.id, "saved bot reviewer has no frozen target")
            })?;
            self.check_bot_review_target(
                &thread.id,
                &thread.root_thread_id,
                &target.agent_id,
                &expected,
            )
            .await?;
        }
        Ok(())
    }

    async fn check_bot_review_target(
        &self,
        reviewer: &str,
        root_id: &str,
        target: &str,
        expected: &WorkspaceIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        let record = self.thread_record(target).await?;
        if record.root_thread_id != root_id || self.services.worktrees.get(target).is_some() {
            return Err(bot_workspace_refusal(
                reviewer,
                "bot review target has a different root or an owned worktree",
            ));
        }
        let frozen = self
            .services
            .store
            .workspace_identity(target)
            .await
            .map_err(|error| resource_error("read frozen bot review target", error))?
            .ok_or_else(|| {
                bot_workspace_refusal(
                    reviewer,
                    "bot review target has no frozen physical execution identity",
                )
            })?;
        self.check_bot_frozen_identity(reviewer, &frozen, expected)
            .await
    }

    async fn check_bot_frozen_identity(
        &self,
        id: &str,
        frozen: &WorkspaceIdentity,
        expected: &WorkspaceIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        if frozen.endpoint != WorkspaceEndpoint::Local
            || frozen != expected
            || local_identity(Path::new(&frozen.root)).await? != *expected
        {
            return Err(bot_workspace_refusal(
                id,
                "frozen bot workspace is not the bot-managed canonical execution root",
            ));
        }
        Ok(())
    }
}

async fn local_identity(path: &Path) -> Result<WorkspaceIdentity, ThreadAssemblyError> {
    let path = path.to_owned();
    let canonical = tokio::task::spawn_blocking(move || dunce::canonicalize(path))
        .await?
        .map_err(|error| resource_error("resolve canonical bot execution root", error))?;
    WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        canonical.to_string_lossy().into_owned(),
    )
    .map_err(StudioThreadFactory::workspace_usage_error)
}

fn bot_workspace_refusal(id: &str, reason: &str) -> ThreadAssemblyError {
    ThreadAssemblyError::Workspace {
        thread_id: id.into(),
        reason: reason.into(),
    }
}

#[cfg(test)]
mod migration_tests {
    use super::*;
    use crate::studio::storage_fault_test_support::{
        ThreadStorageSink, close_factory, spawn_live_projection,
    };
    use crate::thread_assembler::{
        StudioActivationFactory, StudioChildResources, ThreadActivation, ThreadPreparation,
    };
    use anyhow::{Context, Result};
    use pl_core::thread::{ThreadHandle, cold::ColdStoreHandle, extensions::ExtensionMutation};
    use pl_tool::workspace::SessionFiles;

    #[tokio::test]
    async fn bot_workspace_migration_admission_preserves_rejected_bindings_and_owns_first_copy()
    -> Result<()> {
        // This private resource-factory test starts after the upstream review admission boundary.
        // Its synthetic delivery identity supplies that boundary's input; it does not prove a
        // model completed a Turn or that the host generated review authority end to end.
        fn migration_review_target(agent_id: &str) -> pl_protocol::AgentReviewTargetSnapshot {
            pl_protocol::AgentReviewTargetSnapshot {
                agent_id: agent_id.into(),
                feedback: None,
                baseline: Some(pl_protocol::AgentReviewBaseline {
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

        let temp = tempfile::tempdir()?;
        let business = temp.path().join("business");
        tokio::fs::create_dir_all(&business).await?;
        tokio::fs::write(business.join("business.txt"), b"not migration-owned").await?;
        let store =
            crate::studio::StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let mut root = pl_protocol::Thread::placeholder("bot-root");
        root.project_id = "bot-project".into();
        root.root_thread_id = root.id.clone();
        root.workspace_path = business.to_string_lossy().into_owned();
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: root.project_id.clone(),
                name: "Original project".into(),
                path: root.workspace_path.clone(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        delta.thread_upserts.push(root.clone());
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
            .product_events
            .warm_thread_index(vec![root.clone()]);
        factory
            .services
            .bots
            .install_workspace_migration_fixture("botA1234", &root.id, &root.project_id)
            .await?;
        let bot = factory
            .services
            .bots
            .config_for_thread(&root.id)
            .await?
            .context("saved bot binding")?;
        let managed = factory.services.bots.workspace_root(&bot);
        assert!(!tokio::fs::try_exists(&managed).await?);
        let config = crate::config::StudioConfig::default_config()?;
        let selector = config.mode_model_route(&pl_protocol::ThreadModeId::simple())?;
        let route = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), selector)?;
        let mut profile = crate::config::ResolvedAgentProfile {
            revision: 1,
            profile: pl_protocol::AgentProfileSnapshot {
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
            },
            config: config.clone(),
            route,
        };
        let mut request = ChildThreadRequest {
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
        let rejected = StudioChildResources::prepare(factory, &request, &profile).await;
        assert!(
            matches!(&rejected, Err(ThreadAssemblyError::Workspace { .. })),
            "worktree rejection must precede Git discovery or migration: {:?}",
            rejected.err()
        );
        assert!(!tokio::fs::try_exists(&managed).await?);
        assert!(store.workspace_identity(&request.id).await?.is_none());
        assert!(factory.services.worktrees.snapshot().is_empty());
        assert!(!fixture.workspace_is_busy(&request.id));

        // The production migration helper admits a not-yet-materialized target and gives the
        // original preparer the final canonical use before copying its first execution file.
        let files = SessionFiles::new(&root.id);
        tokio::fs::create_dir_all(business.join(files.root()).join("scratch")).await?;
        tokio::fs::write(
            business.join(files.root()).join("scratch/original"),
            b"retained original",
        )
        .await?;
        let mut project = store.read_project(&root.project_id).await?.unwrap();
        let execution = factory
            .reserve_thread_workspace_use(&root.id, &root.id, &project)
            .await?;
        let canonical = factory
            .bind_bot_project(
                &root.id,
                &root.id,
                &mut project,
                &execution,
                super::super::root_resources::BotWorkspacePreparation::Existing,
            )
            .await?
            .unwrap();
        assert_eq!(canonical, dunce::canonicalize(&managed)?);
        assert_eq!(
            tokio::fs::read(managed.join(files.root()).join("scratch/original")).await?,
            b"retained original"
        );
        assert!(fixture.workspace_is_busy(&root.id));
        assert_eq!(
            store.workspace_identity(&root.id).await?.unwrap(),
            local_identity(&managed).await?
        );
        drop(execution);

        let mut target = root.clone();
        target.id = "bot-reviewed".into();
        target.agent_path = target.id.clone();
        target.parent_thread_id = Some(root.id.clone());
        target.workspace_path = managed.to_string_lossy().into_owned();
        store
            .persist_directory_summaries(&crate::studio::store::directory::DirectoryDelta {
                thread_upserts: vec![target.clone()],
                ..Default::default()
            })
            .await?;
        factory
            .services
            .product_events
            .warm_thread_index(vec![target.clone()]);
        store
            .bind_workspace_identity(&target.id, &local_identity(&managed).await?)
            .await?;
        profile.profile.workspace_mode = AgentWorkspaceMode::Review;
        request.id = "allowed-review".into();
        request.review_target_agent_id = Some(target.id.clone());
        factory
            .check_bot_spawn_workspace(
                &request,
                &profile,
                &crate::studio::ThreadRecord::from_directory_thread(root.clone()),
            )
            .await?;
        assert!(
            !tokio::fs::try_exists(managed.join(SessionFiles::new(&request.id).root())).await?,
            "read-only admission does not prepare execution files"
        );

        let other_root = temp.path().join("other-execution-root");
        tokio::fs::create_dir_all(&other_root).await?;
        let mut other = target.clone();
        other.id = "different-root-reviewed".into();
        other.agent_path = other.id.clone();
        other.workspace_path = other_root.to_string_lossy().into_owned();
        store
            .persist_directory_summaries(&crate::studio::store::directory::DirectoryDelta {
                thread_upserts: vec![other.clone()],
                ..Default::default()
            })
            .await?;
        factory
            .services
            .product_events
            .warm_thread_index(vec![other.clone()]);
        store
            .bind_workspace_identity(&other.id, &local_identity(&other_root).await?)
            .await?;
        request.id = "rejected-review".into();
        request.review_target_agent_id = Some(other.id.clone());
        request.review_target = Some(migration_review_target(&other.id));
        request.review_workspace = Some(pl_protocol::AgentWorkspaceAssignmentSnapshot {
            mode: AgentWorkspaceMode::Directory,
            project_root: other.workspace_path.clone(),
            root: other.workspace_path.clone(),
            writable_paths: None,
            worktree: None,
            review_target: None,
        });
        let original_binding = store.workspace_identity(&other.id).await?;
        let original_project = store.read_project(&root.project_id).await?;
        let rejected = StudioChildResources::prepare(factory, &request, &profile).await;
        assert!(
            matches!(&rejected, Err(ThreadAssemblyError::Workspace { .. })),
            "cross-root review rejection must precede migration: {:?}",
            rejected.err()
        );
        assert_eq!(store.workspace_identity(&other.id).await?, original_binding);
        assert_eq!(
            store.read_project(&root.project_id).await?,
            original_project
        );
        assert!(factory.services.worktrees.snapshot().is_empty());
        assert!(!fixture.workspace_is_busy(&request.id));
        assert!(store.workspace_identity(&request.id).await?.is_none());
        assert!(!tokio::fs::try_exists(managed.join(SessionFiles::new(&request.id).root())).await?);

        // An old incompatible checkpoint is rejected before instruction/route migration, binding
        // changes or tools. Its original history and exact execution files remain available.
        let mut old = other.clone();
        old.id = "legacy-bot-worktree".into();
        old.agent_path = old.id.clone();
        old.role = profile.profile.profile_id.clone();
        store
            .persist_directory_summaries(&crate::studio::store::directory::DirectoryDelta {
                thread_upserts: vec![old.clone()],
                ..Default::default()
            })
            .await?;
        let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
            mode: AgentWorkspaceMode::Worktree,
            project_root: other.workspace_path.clone(),
            root: other.workspace_path.clone(),
            writable_paths: None,
            worktree: Some(pl_protocol::AgentWorktreeSnapshot {
                repository_root: other.workspace_path.clone(),
                path: other.workspace_path.clone(),
                base_commit: "a".repeat(40),
            }),
            review_target: None,
        };
        profile.profile.workspace_mode = AgentWorkspaceMode::Worktree;
        let core = ThreadHandle::resume_without_model(old.id.clone(), None)?;
        let sink = ThreadStorageSink::new(store.clone(), old.clone(), None).await?;
        spawn_live_projection(&sink);
        core.attach_storage(ColdStoreHandle::new(sink)).await?;
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
        core.close().await?;
        store
            .thread_persistence()
            .history_channel(&old.id)
            .stop_and_join()
            .await?;
        let history = store.history(&old.id).await?;
        let before = serde_json::to_vec(&history.checkpoint().await?)?;
        let old_files = other_root.join(SessionFiles::new(&old.id).root());
        tokio::fs::create_dir_all(&old_files).await?;
        tokio::fs::write(old_files.join("original"), b"old identity preserved").await?;
        assert!(matches!(
            StudioActivationFactory::prepare(
                factory,
                ThreadPreparation {
                    workspace_owner: Default::default(),
                    identity: ThreadActivation {
                        id: old.id.clone(),
                        parent_id: old.parent_thread_id.clone()
                    },
                    cancellation: Default::default(),
                    agent_controls: vec![],
                    delegation: None
                }
            )
            .await,
            Err(ThreadAssemblyError::Workspace { .. })
        ));
        assert_eq!(serde_json::to_vec(&history.checkpoint().await?)?, before);
        assert_eq!(
            tokio::fs::read(old_files.join("original")).await?,
            b"old identity preserved"
        );
        assert!(store.workspace_identity(&old.id).await?.is_none());
        assert!(!tokio::fs::try_exists(managed.join(SessionFiles::new(&old.id).root())).await?);

        tokio::fs::rename(&business, temp.path().join("old-source-unmounted")).await?;
        let mut project = store.read_project(&root.project_id).await?.unwrap();
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
                    super::super::root_resources::BotWorkspacePreparation::Existing
                )
                .await?,
            Some(canonical)
        );
        assert!(!tokio::fs::try_exists(&business).await?);
        assert_eq!(
            tokio::fs::read(managed.join(files.root()).join("scratch/original")).await?,
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
            let spec = StudioChildResources::prepare(factory, &request, &profile).await?;
            let registered = factory
                .services
                .product_events
                .thread_snapshot(id)
                .context("factory registered child")?;
            assert_eq!(registered.workspace_path, root.workspace_path);
            let assignment = spec
                .initial_extensions
                .get(crate::studio::workspace_receipt::EXTENSION)
                .unwrap();
            let assignment = crate::studio::workspace_receipt::from_payload(assignment)
                .map_err(anyhow::Error::msg)?;
            assert_eq!(assignment.root, managed.to_string_lossy());
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
            let core = ThreadHandle::resume_without_model(registered.id.clone(), None)?;
            let sink = ThreadStorageSink::new(store.clone(), registered.clone(), None).await?;
            spawn_live_projection(&sink);
            core.attach_storage(ColdStoreHandle::new(sink)).await?;
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
            core.flush().await?;
            prepared.push((registered, core));
        }
        for (registered, core) in prepared.into_iter().rev() {
            factory
                .begin_child_close(&registered, Some(&core.snapshot()), false)
                .await?;
            factory.begin_child_close(&registered, None, false).await?;
            core.close().await?;
            store
                .thread_persistence()
                .history_channel(&registered.id)
                .stop_and_join()
                .await?;
            factory.finish_child_execution(&registered).await?;
            factory.finish_child_worktree_cleanup(&registered).await?;
            let result = store.agent_close(&registered.id).await?.unwrap().result();
            assert!(result.execution_closed);
            assert_eq!(
                result.worktree_cleanup,
                crate::studio::agent_close::AgentWorktreeCleanup::NotApplicable
            );
            assert!(
                store
                    .history(&registered.id)
                    .await?
                    .checkpoint()
                    .await?
                    .is_some()
            );
            assert!(
                store
                    .ensure_agent_execution_allowed(&registered.id)
                    .await
                    .is_err()
            );
            assert!(
                tokio::fs::try_exists(managed.join(SessionFiles::new(&registered.id).root()))
                    .await?
            );
            assert!(tokio::fs::try_exists(&managed).await?);
        }
        factory.services.bots.shutdown().await?;
        fixture.shutdown().await?;
        Ok(())
    }
}
