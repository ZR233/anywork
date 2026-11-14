//! Project 目录命令：打开、列出与归档 Project，并物化项目归档所需的冷目录范围。

use std::path::Path;

use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::WorkspaceKind;

use crate::studio::records::{DirectoryMember, WorkspaceRecord};
use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord, ProjectRemoval};
use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope};

use super::super::StudioRuntime;
use super::super::thread_title::ThreadTitleCancellationCause;

impl StudioRuntime {
    pub async fn open_project(&self, path: impl AsRef<Path>) -> Result<WorkspaceRecord> {
        let canonical = dunce::canonicalize(path.as_ref())?;
        anyhow::ensure!(canonical.is_dir(), "workspace path is not a directory");
        let path = canonical.as_path();
        let _guard = self.lifecycle_lock.lock().await;
        let path_text = path.to_string_lossy().to_string();
        if let Some(project) = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.path == path_text && project.ssh_alias.is_none())
        {
            ensure!(
                project.kind == WorkspaceKind::Project,
                "the standalone workspace cannot be opened as a user project"
            );
            return Ok(project);
        }
        let name = crate::studio::paths::project_name(path);
        let now = crate::studio::unix_seconds();
        // 聚合冷加载：按 path 找到既有行或分配新 id，然后内存先行提交目录 delta。
        let existing = self.store.find_project_by_path(&path_text, None).await?;
        let (record, delta_record) = match existing {
            Some(existing) => {
                ensure!(
                    existing.kind == WorkspaceKind::Project,
                    "the standalone workspace cannot be opened as a user project"
                );
                let name = existing.name.clone();
                let delta_record = ProjectDirectoryRecord {
                    id: existing.id.clone(),
                    kind: existing.kind,
                    name: name.clone(),
                    path: path_text.clone(),
                    ssh_alias: None,
                    created_at: existing.created_at,
                    updated_at: now,
                    last_opened_at: Some(now),
                    closed: false,
                };
                let public = WorkspaceRecord {
                    id: existing.id.clone(),
                    kind: existing.kind,
                    name,
                    path: path_text,
                    ssh_alias: None,
                    updated_at: now,
                };
                (public, delta_record)
            }
            None => {
                let id = crate::studio::ids::new_id("project");
                let delta_record = ProjectDirectoryRecord {
                    id: id.clone(),
                    kind: WorkspaceKind::Project,
                    name: name.clone(),
                    path: path_text.clone(),
                    ssh_alias: None,
                    created_at: now,
                    updated_at: now,
                    last_opened_at: Some(now),
                    closed: false,
                };
                let public = WorkspaceRecord {
                    id,
                    kind: WorkspaceKind::Project,
                    name,
                    path: path_text,
                    ssh_alias: None,
                    updated_at: now,
                };
                (public, delta_record)
            }
        };
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta::upsert_project(delta_record))
            .await?;
        Ok(record)
    }

    /// Explicitly prepares the shared owner without creating a Thread or a Git repository.
    pub async fn prepare_standalone_workspace(&self) -> Result<crate::StudioProjectDirectoryState> {
        self.prepare_standalone_workspace_at(dirs::document_dir().map(|root| root.join("anywork")))
            .await?;
        self.agent_facility
            .product_events
            .read_project_directory()
            .await
    }

    // Root injection stays private: tests must never locate or mutate the user's Documents.
    async fn prepare_standalone_workspace_at(
        &self,
        root: Option<std::path::PathBuf>,
    ) -> Result<WorkspaceRecord> {
        let runtime = self.clone();
        self.run_thread_lifecycle_operation(async move {
            runtime.prepare_standalone_workspace_owned(root).await
        })
        .await
    }

    /// The retained lifecycle worker owns this mutation through durable write and event publication,
    /// even if its original caller is cancelled between those two phases.
    async fn prepare_standalone_workspace_owned(
        &self,
        root: Option<std::path::PathBuf>,
    ) -> Result<WorkspaceRecord> {
        let published = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.kind == WorkspaceKind::Standalone);
        let canonical = published.is_none().then(|| {
            self.store
                .workspaces()
                .entries()
                .into_iter()
                .find(|entry| entry.kind == WorkspaceKind::Standalone)
        });
        let canonical = canonical.flatten();
        let existing = published
            .as_ref()
            .cloned()
            .or_else(|| canonical.as_ref().map(|entry| entry.project()));
        let root = existing
            .as_ref()
            .map(|project| std::path::PathBuf::from(&project.path))
            .or(root)
            .context("the platform Documents directory could not be located")?;
        let canonical_root = tokio::task::spawn_blocking(move || -> Result<_> {
            std::fs::create_dir_all(&root)
                .with_context(|| format!("create standalone workspace {}", root.display()))?;
            let canonical = dunce::canonicalize(&root)?;
            // Prove write admission now, not on the first user's Thread. This exclusively owned
            // probe is removed by tempfile; no pre-existing Documents entry is touched.
            let probe = tempfile::NamedTempFile::new_in(&canonical)
                .context("the standalone workspace is not writable")?;
            probe.close()?;
            Ok(canonical)
        })
        .await??;
        let path = canonical_root.to_string_lossy().into_owned();
        if let Some(existing) = published {
            ensure!(
                existing.path == path && existing.ssh_alias.is_none(),
                "the standalone workspace identity changed"
            );
            return Ok(existing);
        }
        if let Some(entry) = canonical {
            ensure!(
                entry.path == path && entry.ssh_alias.is_none(),
                "the standalone workspace identity changed"
            );
            let project = entry.project();
            // A cancelled earlier command may have durably written workspaces.toml without
            // publishing its directory event. Replay the exact canonical entry: persistence is
            // content-idempotent, while the missing in-memory projection and revision are repaired.
            self.agent_facility
                .product_events
                .commit_directory(DirectoryDelta::upsert_project(ProjectDirectoryRecord {
                    id: entry.id,
                    kind: entry.kind,
                    name: entry.name,
                    path: entry.path,
                    ssh_alias: entry.ssh_alias,
                    created_at: entry.created_at,
                    updated_at: entry.updated_at,
                    last_opened_at: entry.last_opened_at,
                    closed: entry.closed,
                }))
                .await?;
            return Ok(project);
        }
        ensure!(
            !self
                .agent_facility
                .product_events
                .project_snapshot()
                .await
                .iter()
                .any(|project| project.path == path && project.ssh_alias.is_none())
                && self
                    .store
                    .find_project_by_path(&path, None)
                    .await?
                    .is_none(),
            "the standalone directory already belongs to a user project"
        );
        let now = crate::studio::unix_seconds();
        let project = WorkspaceRecord {
            id: crate::studio::ids::new_id("project"),
            kind: WorkspaceKind::Standalone,
            name: "anywork".into(),
            path,
            ssh_alias: None,
            updated_at: now,
        };
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta::upsert_project(ProjectDirectoryRecord {
                id: project.id.clone(),
                kind: project.kind,
                name: project.name.clone(),
                path: project.path.clone(),
                ssh_alias: None,
                created_at: now,
                updated_at: now,
                last_opened_at: Some(now),
                closed: false,
            }))
            .await?;
        Ok(project)
    }

    /// Renames the project label without changing its filesystem identity.
    pub async fn rename_project(&self, id: &str, name: &str) -> Result<WorkspaceRecord> {
        let _guard = self.lifecycle_lock.lock().await;
        let name = name.trim();
        anyhow::ensure!(
            !name.is_empty() && name.chars().count() <= 80,
            "project name must contain 1 to 80 characters"
        );
        let mut project = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == id)
            .ok_or_else(|| anyhow::anyhow!("Project not found"))?;
        ensure!(
            project.kind == WorkspaceKind::Project,
            "the standalone workspace cannot be renamed"
        );
        project.name = name.to_string();
        let now = crate::studio::unix_seconds();
        project.updated_at = now;
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta::upsert_project(ProjectDirectoryRecord {
                id: project.id.clone(),
                kind: project.kind,
                name: project.name.clone(),
                path: project.path.clone(),
                ssh_alias: project.ssh_alias.clone(),
                created_at: now,
                updated_at: now,
                last_opened_at: Some(now),
                closed: false,
            }))
            .await?;
        Ok(project)
    }

    pub async fn list_projects(&self) -> Result<Vec<WorkspaceRecord>> {
        Ok(self.agent_facility.product_events.project_snapshot().await)
    }

    pub async fn archive_project(&self, workspace_id: &str) -> Result<Option<WorkspaceRecord>> {
        let runtime = self.clone();
        let workspace_id = workspace_id.to_owned();
        self.run_thread_lifecycle_operation(async move {
            runtime.archive_project_owned(&workspace_id).await
        })
        .await
    }

    /// The retained archive worker owns lifecycle admission throughout this operation.
    async fn archive_project_owned(&self, workspace_id: &str) -> Result<Option<WorkspaceRecord>> {
        ensure!(
            !self
                .agent_facility
                .product_events
                .project_snapshot()
                .await
                .iter()
                .any(|project| project.id == workspace_id
                    && project.kind == WorkspaceKind::Standalone),
            "the standalone workspace cannot be archived"
        );
        let threads = self.load_project_archive_scope(workspace_id).await?;
        let has_pending_archive = self
            .store
            .thread_archive(&ArchiveScope::Workspace(workspace_id.into()))
            .await?
            .is_some_and(|operation| operation.phase != ArchivePhase::Published);
        let Some(project) = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == workspace_id)
            .or_else(|| {
                // workspaces.toml is written before catalog.toml. If the latter failed (including
                // across restart), the canonical closed Project must still allow finishing its
                // active catalog rows; absence from the open-project projection is not completion.
                (has_pending_archive || threads.iter().any(|thread| !thread.session.archived))
                    .then(|| {
                        self.store
                            .workspaces()
                            .get(workspace_id)
                            .map(|entry| entry.project())
                    })
                    .flatten()
            })
        else {
            return Ok(None);
        };
        let mut roots = threads
            .iter()
            .filter(|thread| thread.parent_thread_id.is_none())
            .map(|thread| thread.agent.thread_id.clone())
            .collect::<Vec<_>>();
        // New ACP roots cannot publish an Agent reference until the peer returns its ID.
        // Capture their real original owner under the same lifecycle admission boundary.
        let mut acp_owners = std::collections::BTreeMap::new();
        for session in self.sessions.resident_sessions() {
            for root in session.acp_roots_for_workspace(workspace_id) {
                roots.push(root.clone());
                acp_owners.insert(root, session.clone());
            }
        }
        roots.sort();
        roots.dedup();
        // Project archives still reject active work; they do not interrupt an active Turn.
        for thread in &threads {
            if !thread.session.archived && self.thread_is_busy(&thread.agent.thread_id).await? {
                bail!("project has an active turn");
            }
        }
        let mut scopes = Vec::new();
        for root in &roots {
            let session = match acp_owners.get(root) {
                Some(session) => session.clone(),
                None => self.session_for_roots(std::slice::from_ref(root))?,
            };
            let scope = session.seal_archive_scope(std::slice::from_ref(root))?;
            scopes.push((session, scope));
        }
        let admitted = scopes
            .iter()
            .flat_map(|(_, scope)| scope.preparation_identities(workspace_id))
            .collect::<Vec<_>>();
        let mut admitted_ids = scopes
            .iter()
            .flat_map(|(_, scope)| scope.thread_ids())
            .collect::<Vec<_>>();
        admitted_ids.extend(threads.iter().map(|thread| thread.agent.thread_id.clone()));
        admitted_ids.sort();
        admitted_ids.dedup();
        let _pins = self.residency.pin_many(admitted_ids.iter().cloned());
        let frozen = self
            .freeze_thread_archive(
                ArchiveScope::Workspace(workspace_id.into()),
                &threads,
                &admitted,
            )
            .await?;
        admitted_ids.extend(frozen.thread_ids());
        for (_, scope) in &scopes {
            scope.cancel_preparations();
        }
        admitted_ids.sort();
        admitted_ids.dedup();
        let _bot_archive = self.bots.quiesce_archive_threads(&admitted_ids).await?;
        for id in &admitted_ids {
            self.title_tasks
                .cancel(id, ThreadTitleCancellationCause::ProjectArchive)
                .await;
        }
        tokio::time::timeout(self.archive_settle_timeout(), async {
            for (session, scope) in &scopes {
                session.drain_archive_preparations(scope).await?;
            }
            Ok::<(), crate::thread_assembler::ThreadAssemblyError>(())
        })
        .await
        .context("project archive preparations did not join")??;
        let threads = self.load_project_archive_scope(workspace_id).await?;
        ensure!(
            threads
                .iter()
                .all(|thread| admitted_ids.contains(&thread.agent.thread_id)),
            "project archive member has no frozen preparation responsibility"
        );
        let thread_ids = threads
            .iter()
            .map(|thread| thread.agent.thread_id.clone())
            .collect::<Vec<_>>();
        let active_threads = threads
            .iter()
            .filter(|thread| !thread.session.archived)
            .collect::<Vec<_>>();
        for thread in &active_threads {
            match self.thread_is_busy(&thread.agent.thread_id).await {
                Ok(false) => {}
                Ok(true) => {
                    bail!("project has an active turn");
                }
                Err(error) => {
                    return Err(error);
                }
            }
        }
        let mut archive = self
            .freeze_thread_archive(
                ArchiveScope::Workspace(workspace_id.into()),
                &threads,
                &admitted,
            )
            .await?;
        for thread_id in &thread_ids {
            self.title_tasks
                .cancel(thread_id, ThreadTitleCancellationCause::ProjectArchive)
                .await;
        }
        if archive.phase == ArchivePhase::Sealed {
            self.retire_archived_thread_tree(&thread_ids).await?;
            self.retire_private_archive_members(&mut archive).await?;
        }
        // Reuse Saved/Cleaned ACKs without creating a new cold writer or rebuilding cleaned temp.
        self.archive_save_confirmed(&mut archive).await?;
        self.clean_archive_temps(&mut archive).await?;
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                project_removals: vec![ProjectRemoval {
                    workspace_id: project.id.clone(),
                    session_ids: threads
                        .iter()
                        .map(|member| member.session.session_id.clone())
                        .collect::<std::collections::BTreeSet<_>>()
                        .into_iter()
                        .collect(),
                    closed_at: crate::studio::unix_seconds(),
                }],
                ..Default::default()
            })
            .await?;
        self.archive_published(&mut archive).await?;
        for thread_id in &thread_ids {
            self.model_performance.remove_session(thread_id).await?;
        }
        Ok(Some(project))
    }

    pub(in crate::studio::runtime) fn ensure_project_thread_admission_open(
        &self,
        workspace_id: &str,
    ) -> Result<()> {
        self.recovery
            .ensure_project_execution_access(workspace_id)?;
        anyhow::ensure!(
            self.store
                .workspaces()
                .get(workspace_id)
                .is_some_and(|entry| !entry.closed),
            "selected Project is closed or its archive needs to be retried"
        );
        Ok(())
    }

    async fn load_project_archive_scope(&self, workspace_id: &str) -> Result<Vec<DirectoryMember>> {
        let threads = self.store.directory_members_for_project(workspace_id)?;
        Ok(threads)
    }
}

#[cfg(test)]
mod standalone_tests {
    //! Standalone acceptance at the real runtime boundary, without touching platform Documents.
    use super::*;
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::studio::ThreadVisibility;
    use crate::{StudioHostKind, StudioRuntimeOptions};
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;

    fn options(home: &Path) -> StudioRuntimeOptions {
        StudioRuntimeOptions {
            studio_home: Some(home.to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        }
    }

    #[tokio::test]
    async fn archive_private_preparation_failed_retirement_survives_restart_and_preserves_delivery()
    -> Result<()> {
        use crate::studio::{
            agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
            storage_fault_test_support::close_factory,
            store::{
                thread_archive::{ArchivePhase, ArchiveScope},
                thread_preparation::{PreparationBinding, PreparationIdentity},
            },
        };
        use sea_orm::ConnectionTrait;
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let repository = temp.path().join("repository");
        let checkout = temp.path().join("private-worktree");
        tokio::fs::create_dir_all(&repository).await?;
        for args in [
            vec!["init", "--quiet"],
            vec![
                "-c",
                "user.name=fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "--quiet",
                "--allow-empty",
                "-m",
                "fixture",
            ],
            vec![
                "worktree",
                "add",
                "--quiet",
                "--detach",
                checkout.to_str().unwrap(),
                "HEAD",
            ],
        ] {
            let output = tokio::process::Command::new("git")
                .args(args)
                .current_dir(&repository)
                .output()
                .await?;
            ensure!(
                output.status.success(),
                "isolated Git fixture: {:?}",
                output
            );
        }
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let workspace = runtime.open_project(&repository).await?;
        let root = runtime
            .create_thread_with_id("private-root", &workspace.id, "root")
            .await?;
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        let identity = PreparationIdentity {
            thread_id: "unpublished-physical-child".into(),
            workspace_id: workspace.id.clone(),
            parent_id: Some(root.id.clone()),
            root_id: root.id.clone(),
        };
        let binding = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            dunce::canonicalize(&checkout)?
                .to_string_lossy()
                .into_owned(),
        )?;
        runtime
            .store
            .begin_thread_preparation(identity.clone())
            .await?;
        runtime
            .store
            .bind_thread_preparation(&identity.thread_id, &binding)
            .await?;
        let physical = close_factory(&runtime.store)?;
        let owner = physical
            .unpublished_workspace(&identity.thread_id, &checkout)
            .await?;
        let files = pl_tool::workspace::SessionFiles::new(&identity.thread_id);
        let session = checkout.join(files.root());
        for directory in ["artifacts", ".venv", "scratch/.venv"] {
            tokio::fs::create_dir_all(session.join(directory)).await?;
            tokio::fs::write(session.join(directory).join("keep"), directory).await?;
        }
        tokio::fs::write(checkout.join("business"), b"keep worktree").await?;
        // This completed physical preparer never attached storage. Its return is the real stop ACK;
        // retirement is deliberately left pending, and the canonical child has never been published.
        drop(owner);
        runtime
            .store
            .confirm_preparation_stop(&identity.thread_id)
            .await?;
        runtime
            .freeze_thread_archive(
                ArchiveScope::Thread(root.id.clone()),
                std::slice::from_ref(&runtime.store.directory_member(&root.id)?.unwrap()),
                std::slice::from_ref(&identity),
            )
            .await?;
        runtime
            .store
            .database()
            .execute_unprepared(
                "CREATE TRIGGER fail_private_retirement BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind = 'threadPreparation'
          AND NEW.owner_id = 'unpublished-physical-child'
          AND json_extract(NEW.payload_json, '$.retired') = 1
         BEGIN SELECT RAISE(ABORT, 'injected private retirement ACK failure'); END",
            )
            .await?;
        assert!(
            runtime
                .archive_thread("private-first".into(), root.id.clone())
                .await
                .is_err()
        );
        let pending = runtime
            .store
            .thread_archive(&ArchiveScope::Thread(root.id.clone()))
            .await?
            .unwrap();
        assert_eq!(pending.phase, ArchivePhase::Sealed);
        assert_eq!(pending.private_members.len(), 1);
        assert_eq!(pending.private_members[0].identity, identity);
        assert_eq!(
            pending.private_members[0].binding,
            PreparationBinding::Bound {
                identity: binding.clone()
            }
        );
        assert!(
            !runtime
                .store
                .thread_preparation(&identity.thread_id)
                .await?
                .unwrap()
                .retired
        );
        assert!(
            runtime
                .store
                .read_thread(&identity.thread_id)
                .await?
                .is_none()
        );
        assert!(session.join("scratch/prepared").is_file());
        assert!(
            session.join("artifacts/keep").is_file(),
            "real factory must not dispose the root"
        );
        runtime.shutdown_runtime().await?;
        physical.shutdown().await?;
        drop(physical);
        drop(runtime);

        let runtime = StudioRuntime::initialize(options(&home)).await?;
        assert!(
            runtime
                .session_of(&identity.thread_id)
                .and_then(|session| session.observed_thread(&identity.thread_id))
                .is_none()
        );
        assert!(
            runtime
                .store
                .read_thread(&identity.thread_id)
                .await?
                .is_none()
        );
        assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
        // A missing registry/catalog child must not turn the original failed retirement into success.
        assert!(
            runtime
                .archive_thread("private-still-failing".into(), root.id.clone())
                .await
                .is_err()
        );
        assert!(session.join("scratch/prepared").is_file());
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER fail_private_retirement")
            .await?;
        runtime
            .archive_thread("private-retry".into(), root.id.clone())
            .await?
            .context("archive")?;
        let finished = runtime
            .store
            .thread_archive(&ArchiveScope::Thread(root.id))
            .await?
            .unwrap();
        assert_eq!(finished.phase, ArchivePhase::Published);
        assert_eq!(finished.private_members.len(), 1);
        assert!(finished.private_members[0].retired);
        assert!(
            finished.private_members[0].execution_cleaned
                && finished.private_members[0].host_cleaned
        );
        assert!(!checkout.join(files.temp()).exists());
        assert!(!session.join("scratch/prepared").exists());
        for directory in ["artifacts", ".venv", "scratch/.venv"] {
            assert_eq!(
                tokio::fs::read(session.join(directory).join("keep")).await?,
                directory.as_bytes()
            );
        }
        assert_eq!(
            tokio::fs::read(checkout.join("business")).await?,
            b"keep worktree"
        );
        let output = tokio::process::Command::new("git")
            .args(["worktree", "list", "--porcelain", "-z"])
            .current_dir(&repository)
            .output()
            .await?;
        assert!(output.status.success());
        let expected = dunce::canonicalize(&checkout)?;
        let mut registered = false;
        for field in String::from_utf8(output.stdout)?.split('\0') {
            if let Some(path) = field.strip_prefix("worktree ") {
                registered |= dunce::canonicalize(path)? == expected;
            }
        }
        assert!(registered, "the preserved checkout must remain registered");
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn archive_temp_removes_only_bound_disposable_directories_and_restores_lazily()
    -> Result<()> {
        use pl_tool::workspace::SessionFiles;
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let thread = runtime
            .create_thread_with_id("archive-temp", &project.id, "archive")
            .await?;
        let neighbor = runtime
            .create_thread_with_id("neighbor-temp", &project.id, "neighbor")
            .await?;
        runtime
            .ensure_thread_owner(&thread.id)
            .await?
            .flush()
            .await?;
        let files = SessionFiles::new(&thread.id);
        let neighbor_files = SessionFiles::new(&neighbor.id);
        let session = runtime.store.registered_session_paths(&thread.id)?;
        tokio::fs::create_dir_all(session.temp_dir()).await?;
        tokio::fs::write(session.temp_dir().join("transfer"), b"disposable").await?;
        let resources = runtime.store.session_resources_dir(&thread.id)?;
        tokio::fs::create_dir_all(&resources).await?;
        tokio::fs::write(resources.join("reliable"), b"keep reliable").await?;
        tokio::fs::write(workspace.join(files.temp()).join("probe"), b"disposable").await?;
        tokio::fs::write(
            workspace.join(files.artifacts()).join("delivery"),
            b"keep artifact",
        )
        .await?;
        tokio::fs::write(
            workspace.join(neighbor_files.temp()).join("active"),
            b"keep neighbor",
        )
        .await?;
        tokio::fs::write(workspace.join("business"), b"keep business").await?;

        runtime
            .archive_thread("archive-temp-operation".into(), thread.id.clone())
            .await?
            .context("archive reply")?;
        assert!(!session.temp_dir().exists());
        assert!(!workspace.join(files.temp()).exists());
        assert!(session.history_database().is_file());
        assert_eq!(
            tokio::fs::read(resources.join("reliable")).await?,
            b"keep reliable"
        );
        assert_eq!(
            tokio::fs::read(workspace.join(files.artifacts()).join("delivery")).await?,
            b"keep artifact"
        );
        assert_eq!(
            tokio::fs::read(workspace.join(neighbor_files.temp()).join("active")).await?,
            b"keep neighbor"
        );
        assert_eq!(
            tokio::fs::read(workspace.join("business")).await?,
            b"keep business"
        );
        let restored = runtime.restore_thread(thread.id.clone()).await?;
        assert!(!restored.archived);
        assert!(
            !workspace.join(files.temp()).exists(),
            "catalog restoration is not execution"
        );
        runtime.ensure_thread_owner(&thread.id).await?;
        assert!(workspace.join(files.commands()).is_dir());
        assert!(!workspace.join(files.temp()).join("probe").exists());
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn archive_temp_failure_survives_restart_and_cold_reads_do_not_recreate_temp()
    -> Result<()> {
        use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope};
        use pl_tool::workspace::SessionFiles;
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let thread = runtime
            .create_thread_with_id("retry-temp", &project.id, "retry")
            .await?;
        let files = SessionFiles::new(&thread.id);
        let session = runtime.store.registered_session_paths(&thread.id)?;
        tokio::fs::create_dir_all(session.temp_dir()).await?;
        tokio::fs::write(session.temp_dir().join("transfer"), b"disposable").await?;
        // A non-directory at the dedicated temp address is a deterministic I/O failure even under root.
        tokio::fs::remove_dir_all(workspace.join(files.temp())).await?;
        tokio::fs::write(workspace.join(files.temp()), b"wrong kind").await?;
        assert!(
            runtime
                .archive_thread("retry-temp-first".into(), thread.id.clone())
                .await
                .is_err()
        );
        assert_eq!(
            runtime
                .store
                .thread_archive(&ArchiveScope::Thread(thread.id.clone()))
                .await?
                .unwrap()
                .phase,
            ArchivePhase::Saved
        );
        assert_eq!(
            runtime
                .store
                .read_thread(&thread.id)
                .await?
                .unwrap()
                .visibility,
            ThreadVisibility::Active
        );
        runtime.shutdown_runtime().await?;
        drop(runtime);

        let runtime = StudioRuntime::initialize(options(&home)).await?;
        assert!(runtime.ensure_thread_owner(&thread.id).await.is_err());
        assert!(runtime.restore_thread(thread.id.clone()).await.is_err());
        assert_eq!(
            tokio::fs::read(workspace.join(files.temp())).await?,
            b"wrong kind"
        );
        runtime
            .store
            .read_thread(&thread.id)
            .await?
            .context("cold catalog")?;
        assert!(
            runtime
                .session_of(&thread.id)
                .and_then(|session| session.observed_thread(&thread.id))
                .is_none()
        );
        tokio::fs::remove_file(workspace.join(files.temp())).await?;
        runtime
            .archive_thread("retry-temp-second".into(), thread.id.clone())
            .await?
            .context("retry reply")?;
        assert!(!session.temp_dir().exists());
        assert!(!workspace.join(files.temp()).exists());
        assert_eq!(
            runtime
                .store
                .thread_archive(&ArchiveScope::Thread(thread.id))
                .await?
                .unwrap()
                .phase,
            ArchivePhase::Published
        );
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    fn configure(home: &Path) -> Result<std::net::TcpListener> {
        // Activation may construct this anonymous route but these storage tests never submit a model
        // request. Retain the listener to also detect accidental outbound network work.
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account_id = AccountId::new("standalone-fixture")?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: "standalone-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "Standalone fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![ModelInfo::compatible(&route.model_id)],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
        Ok(endpoint)
    }

    fn request(
        workspace_mode: pl_protocol::ThreadWorkspaceMode,
    ) -> pl_protocol::studio::CreateThreadRequest {
        pl_protocol::studio::CreateThreadRequest {
            title: Some("standalone".into()),
            input: pl_protocol::studio::StudioPromptInput {
                input_id: "standalone-start".into(),
                text: "hello".into(),
                attachment_draft_ids: vec![],
            },
            mode: pl_protocol::ThreadModeId::simple().label().into(),
            route: pl_protocol::studio::NewThreadModelRoute {
                account_id: "standalone-fixture".into(),
                model_id: "standalone-model".into(),
                effort: None,
            },
            delegation_mode: None,
            delegation_preference: None,
            workspace_mode,
        }
    }

    #[tokio::test]
    async fn standalone_prepare_is_concurrent_idempotent_and_rejects_project_operations()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let root = temp.path().join("documents/anywork");
        let (left, right) = tokio::join!(
            runtime.prepare_standalone_workspace_at(Some(root.clone())),
            runtime.prepare_standalone_workspace_at(Some(root.clone()))
        );
        let project = left?;
        assert_eq!(project, right?);
        assert_eq!(project.kind, WorkspaceKind::Standalone);
        assert_eq!(Path::new(&project.path), dunce::canonicalize(&root)?);
        assert_eq!(runtime.list_projects().await?, vec![project.clone()]);
        assert_eq!(
            runtime.prepare_standalone_workspace_at(None).await?,
            project
        );
        assert!(
            runtime
                .store
                .list_threads_for_project(&project.id)
                .await?
                .is_empty()
        );
        assert!(runtime.open_project(&root).await.is_err());
        assert!(runtime.rename_project(&project.id, "fake").await.is_err());
        assert!(runtime.archive_project(&project.id).await.is_err());
        assert!(
            runtime
                .apply_settings_field(pl_protocol::studio::UpdateSettingsFieldRequest {
                    operation_id: "pin-standalone".into(),
                    expected_revision: runtime.config_runtime.read()?.revision,
                    update: pl_protocol::studio::SettingsFieldUpdate::GeneralPinnedProjectIds {
                        value: vec![project.id.clone()],
                    },
                })
                .await
                .is_err()
        );
        runtime.shutdown_runtime().await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        assert_eq!(
            runtime.prepare_standalone_workspace_at(None).await?,
            project
        );
        assert_eq!(runtime.list_projects().await?, vec![project]);
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn standalone_prepare_failure_does_not_publish_or_convert_user_project() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let runtime = StudioRuntime::initialize(options(&temp.path().join("home"))).await?;
        assert!(runtime.prepare_standalone_workspace_at(None).await.is_err());
        let blocked = temp.path().join("blocked");
        tokio::fs::write(&blocked, b"not a directory").await?;
        assert!(
            runtime
                .prepare_standalone_workspace_at(Some(blocked))
                .await
                .is_err()
        );
        assert!(runtime.list_projects().await?.is_empty());
        let root = temp.path().join("user-project");
        tokio::fs::create_dir(&root).await?;
        let project = runtime.open_project(&root).await?;
        assert!(
            runtime
                .prepare_standalone_workspace_at(Some(root))
                .await
                .is_err()
        );
        assert_eq!(runtime.list_projects().await?, vec![project]);
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn canonical_standalone_without_snapshot_is_republished_before_thread_creation()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let endpoint = configure(&home)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let root = temp.path().join("documents/anywork");
        tokio::fs::create_dir_all(&root).await?;
        let path = dunce::canonicalize(&root)?.to_string_lossy().into_owned();
        let owner = crate::studio::store::directory::ProjectDirectoryRecord {
            id: "project-canonical-standalone".into(),
            kind: WorkspaceKind::Standalone,
            name: "preserved owner".into(),
            path: path.clone(),
            ssh_alias: None,
            created_at: 17,
            updated_at: 23,
            last_opened_at: Some(19),
            closed: false,
        };
        runtime
            .store
            .persist_directory_summaries(&DirectoryDelta::upsert_project(owner))
            .await?;
        assert!(
            runtime
                .agent_facility
                .product_events
                .project_snapshot()
                .await
                .is_empty(),
            "fixture must model cancellation before ProductEventBus publication"
        );
        let before_entry = runtime
            .store
            .workspaces()
            .get("project-canonical-standalone")
            .context("canonical owner")?;
        let before_document =
            tokio::fs::read_to_string(runtime.store.paths().workspaces_file()).await?;

        let project = runtime
            .prepare_standalone_workspace_at(Some(temp.path().join("ignored-root")))
            .await?;
        assert_eq!(project, before_entry.project());
        assert_eq!(
            runtime
                .agent_facility
                .product_events
                .project_snapshot()
                .await,
            vec![project.clone()]
        );
        assert_eq!(
            runtime
                .store
                .workspaces()
                .get(&project.id)
                .context("replayed owner")?,
            before_entry
        );
        assert_eq!(
            tokio::fs::read_to_string(runtime.store.paths().workspaces_file()).await?,
            before_document,
            "event repair must not alter the canonical document or its revision"
        );
        let thread = runtime.create_thread(&project.id, "after replay").await?;
        assert_eq!(
            Path::new(&thread.workspace_path),
            dunce::canonicalize(root.join(&thread.id))?
        );
        runtime.shutdown_runtime().await?;
        endpoint.set_nonblocking(true)?;
        assert!(
            matches!(endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
        );
        Ok(())
    }

    #[tokio::test]
    async fn standalone_threads_use_exclusive_directories_and_restore_without_rebinding()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let endpoint = configure(&home)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let root = temp.path().join("documents/anywork");
        let project = runtime
            .prepare_standalone_workspace_at(Some(root.clone()))
            .await?;
        let first = runtime.create_thread(&project.id, "first").await?;
        let second = runtime.create_thread(&project.id, "second").await?;
        for thread in [&first, &second] {
            let expected = dunce::canonicalize(root.join(&thread.id))?;
            assert_eq!(Path::new(&thread.workspace_path), expected);
            assert_ne!(thread.workspace_path, project.path);
            assert!(!expected.join(".git").exists());
            assert_eq!(
                runtime
                    .store
                    .workspace_identity(&thread.id)
                    .await?
                    .context("bound workspace")?
                    .root,
                thread.workspace_path
            );
        }
        assert_ne!(first.workspace_path, second.workspace_path);
        let sentinel = Path::new(&first.workspace_path).join("user-work.txt");
        tokio::fs::write(&sentinel, b"keep user files").await?;
        let collision = root.join("occupied-thread");
        tokio::fs::create_dir(&collision).await?;
        tokio::fs::write(collision.join("unknown"), b"keep unknown leftovers").await?;
        assert!(
            runtime
                .create_thread_with_id("occupied-thread", &project.id, "not published")
                .await
                .is_err()
        );
        assert!(
            runtime
                .find_owned_thread("occupied-thread")
                .await?
                .is_none()
        );
        assert_eq!(
            tokio::fs::read(collision.join("unknown")).await?,
            b"keep unknown leftovers"
        );
        assert!(
            runtime
                .create_thread_with_id("../escape", &project.id, "unsafe")
                .await
                .is_err()
        );
        runtime.shutdown_runtime().await?;

        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let restored = runtime
            .find_owned_thread(&first.id)
            .await?
            .context("cold Thread")?;
        assert_eq!(restored.workspace_path, first.workspace_path);
        runtime.register_new_thread(restored).await?;
        assert_eq!(
            runtime
                .store
                .workspace_identity(&first.id)
                .await?
                .context("restored workspace")?
                .root,
            first.workspace_path
        );
        assert_eq!(
            runtime.store.read_project(&project.id).await?.unwrap().kind,
            WorkspaceKind::Standalone
        );
        runtime
            .archive_thread("archive-standalone".into(), first.id.clone())
            .await?;
        assert_eq!(tokio::fs::read(&sentinel).await?, b"keep user files");
        runtime.shutdown_runtime().await?;
        endpoint.set_nonblocking(true)?;
        assert!(
            matches!(endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
        );
        Ok(())
    }

    #[tokio::test]
    async fn standalone_start_rejects_worktree_without_publishing_or_creating_directories()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let root = temp.path().join("documents/anywork");
        let project = runtime
            .prepare_standalone_workspace_at(Some(root.clone()))
            .await?;
        let result = runtime
            .create_thread_command(
                project.id.clone(),
                request(pl_protocol::ThreadWorkspaceMode::Worktree),
                None,
            )
            .await;
        let error = result.expect_err("standalone worktree must fail");
        assert!(
            error.to_string().contains("only support local"),
            "{error:#}"
        );
        assert!(
            runtime
                .store
                .list_threads_for_project(&project.id)
                .await?
                .is_empty()
        );
        assert!(
            tokio::fs::read_dir(root)
                .await?
                .next_entry()
                .await?
                .is_none()
        );
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn standalone_start_directory_creation_failure_is_not_published() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let root = temp.path().join("documents/anywork");
        let project = runtime
            .prepare_standalone_workspace_at(Some(root.clone()))
            .await?;
        let original = root.clone();
        // Fault injection after admission, immediately before the real exclusive create_dir. This
        // simulates the filesystem becoming unwritable without global env or production test knobs.
        let observer = std::sync::Arc::new(move |progress: crate::ThreadPreparationProgress| {
            if matches!(
                progress.stage,
                crate::ThreadPreparationStage::PreparingWorkspace
            ) {
                std::fs::rename(&root, root.with_file_name("preserved")).unwrap();
                std::fs::write(&root, b"blocked parent").unwrap();
            }
        });
        let error = runtime
            .create_thread_command(
                project.id.clone(),
                request(pl_protocol::ThreadWorkspaceMode::Local),
                Some(observer),
            )
            .await
            .expect_err("directory creation must fail");
        assert!(
            error
                .to_string()
                .contains("create standalone Thread directory"),
            "{error:#}"
        );
        let directory = runtime
            .agent_facility
            .product_events
            .read_thread_directory()
            .await?;
        assert!(
            directory
                .state
                .value()
                .context("ready directory")?
                .rows
                .is_empty()
        );
        assert!(
            runtime
                .store
                .list_threads_for_project(&project.id)
                .await?
                .is_empty()
        );
        assert_eq!(tokio::fs::read(original).await?, b"blocked parent");
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    mod preparation_tests {
        //! Real create-to-first-input observations. Provider and MCP sockets are loopback-only.
        use super::*;
        use std::sync::{Arc, Mutex};
        use std::time::{Duration, Instant};
        use tracing::{Subscriber, field::Visit, span};

        #[derive(Clone, Default)]
        struct PreparationLog(Arc<Mutex<Vec<String>>>);

        #[derive(Default)]
        struct Fields(String);
        impl Visit for Fields {
            fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
                use std::fmt::Write;
                write!(&mut self.0, " {}={value:?}", field.name()).unwrap();
            }
        }
        impl Subscriber for PreparationLog {
            fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
                metadata.target() == "thread_preparation"
            }
            fn new_span(&self, _: &span::Attributes<'_>) -> span::Id {
                static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
                span::Id::from_u64(NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
            }
            fn record(&self, _: &span::Id, _: &span::Record<'_>) {}
            fn record_follows_from(&self, _: &span::Id, _: &span::Id) {}
            fn event(&self, event: &tracing::Event<'_>) {
                let mut fields = Fields::default();
                event.record(&mut fields);
                eprintln!("PREPARATION{}", fields.0);
                self.0.lock().unwrap().push(fields.0);
            }
            fn enter(&self, _: &span::Id) {}
            fn exit(&self, _: &span::Id) {}
        }

        #[tokio::test]
        async fn local_first_input_preparation_without_mcp() -> Result<()> {
            tokio::time::timeout(Duration::from_secs(20), async {
                let capture = PreparationLog::default();
                let dispatch = tracing::Dispatch::new(capture.clone());
                let _capture = tracing::dispatcher::set_default(&dispatch);
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _provider = configure(&home)?;
                let store = ConfigStore::new(ConfigPaths::from_config_dir(&home));
                let mut config = store.load()?;
                // Skills discovery normally reads the standard user home; never consume it here.
                config.skills.enabled = false;
                store.save(&config)?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir(&workspace).await?;
                let project = runtime.open_project(&workspace).await?;
                let started = Instant::now();
                let result = runtime
                    .create_thread_command(
                        project.id,
                        request(pl_protocol::ThreadWorkspaceMode::Local),
                        None,
                    )
                    .await;
                let elapsed = started.elapsed();
                let shutdown_started = Instant::now();
                let shutdown = runtime.shutdown_runtime().await;
                shutdown?;
                let response = result?;
                assert_eq!(response.submission.thread_id, response.thread.id);
                assert_eq!(response.submission.input_id, "standalone-start");
                assert!(response.submission.cursor > 0);
                assert!(
                    capture
                        .0
                        .lock()
                        .unwrap()
                        .iter()
                        .any(|line| line.contains("first_input") && line.contains("completed"))
                );
                eprintln!(
                    "PREPARATION_RESULT slow_mcp=false create_ms={} shutdown_ms={}",
                    elapsed.as_millis(),
                    shutdown_started.elapsed().as_millis()
                );
                Ok::<_, anyhow::Error>(())
            })
            .await?
        }

        mod mcp {
            //! Gated loopback MCP protocol fixture. Tests cross the real create/input and shutdown boundaries.
            use super::*;
            use pl_protocol::{McpScope, ThreadMcpLifecycleKind as Lifecycle};
            use std::sync::atomic::{AtomicUsize, Ordering};
            use tokio::io::{AsyncReadExt, AsyncWriteExt};
            use tokio_util::sync::CancellationToken;

            #[derive(Clone)]
            struct Gate {
                reached: CancellationToken,
                release: CancellationToken,
                handshakes: Arc<AtomicUsize>,
                disconnected: Arc<AtomicUsize>,
            }

            struct Server {
                url: String,
                gate: Gate,
                stop: CancellationToken,
                task: tokio::task::JoinHandle<Result<()>>,
            }

            impl Server {
                async fn new(failure: &'static str) -> Result<Self> {
                    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
                    let url = format!("http://{}/mcp", listener.local_addr()?);
                    let gate = Gate {
                        reached: CancellationToken::new(),
                        release: CancellationToken::new(),
                        handshakes: Arc::new(AtomicUsize::new(0)),
                        disconnected: Arc::new(AtomicUsize::new(0)),
                    };
                    let stop = CancellationToken::new();
                    let stopping = stop.clone();
                    let controls = gate.clone();
                    let task = tokio::spawn(async move {
                        let mut requests = tokio::task::JoinSet::new();
                        loop {
                            tokio::select! {
                                () = stopping.cancelled() => break,
                                accepted = listener.accept() => {
                                    let socket = accepted?.0;
                                    requests.spawn(serve_request(socket, controls.clone(), failure));
                                }
                                result = requests.join_next(), if !requests.is_empty() => { result.unwrap()??; }
                            }
                        }
                        // Do not abort handlers or release gates on shutdown. Production must physically
                        // disconnect any blocked request before this fixture can finish.
                        while let Some(result) = requests.join_next().await {
                            result??;
                        }
                        Ok(())
                    });
                    Ok(Self {
                        url,
                        gate,
                        stop,
                        task,
                    })
                }

                async fn close(self) -> Result<()> {
                    self.stop.cancel();
                    tokio::time::timeout(Duration::from_secs(3), self.task).await???;
                    Ok(())
                }
            }

            async fn read_request(
                socket: &mut tokio::net::TcpStream,
            ) -> Result<Option<(String, serde_json::Value)>> {
                let mut bytes = Vec::new();
                let (end, length) = loop {
                    let mut buffer = [0; 4096];
                    let count = socket.read(&mut buffer).await?;
                    if count == 0 {
                        return Ok(None);
                    }
                    bytes.extend_from_slice(&buffer[..count]);
                    anyhow::ensure!(bytes.len() <= 1024 * 1024, "fixture request too large");
                    if let Some(end) = bytes.windows(4).position(|window| window == b"\r\n\r\n") {
                        let header = std::str::from_utf8(&bytes[..end])?;
                        let length = header
                            .lines()
                            .find_map(|line| {
                                let (name, value) = line.split_once(':')?;
                                name.eq_ignore_ascii_case("content-length")
                                    .then(|| value.trim().parse::<usize>())
                            })
                            .transpose()?
                            .unwrap_or(0);
                        break (end + 4, length);
                    }
                };
                while bytes.len() < end + length {
                    let mut buffer = [0; 4096];
                    let count = socket.read(&mut buffer).await?;
                    anyhow::ensure!(count > 0, "fixture body ended early");
                    bytes.extend_from_slice(&buffer[..count]);
                }
                let message: serde_json::Value = if length == 0 {
                    serde_json::Value::Null
                } else {
                    serde_json::from_slice(&bytes[end..end + length])?
                };
                let http_method = std::str::from_utf8(&bytes[..end])?
                    .split_whitespace()
                    .next()
                    .context("HTTP method")?
                    .to_owned();
                Ok(Some((http_method, message)))
            }

            async fn serve_request(
                mut socket: tokio::net::TcpStream,
                gate: Gate,
                failure: &str,
            ) -> Result<()> {
                let Some((http_method, message)) = read_request(&mut socket).await? else {
                    return Ok(());
                };
                let method = message["method"].as_str().unwrap_or("");
                eprintln!("MCP_FIXTURE method={method} failure={failure}");
                if method == "initialize" {
                    gate.handshakes.fetch_add(1, Ordering::SeqCst);
                    gate.reached.cancel();
                    let mut byte = [0];
                    tokio::select! {
                        biased;
                        read = socket.read(&mut byte) => {
                            anyhow::ensure!(read? == 0, "unexpected pipelined fixture request");
                            gate.disconnected.fetch_add(1, Ordering::SeqCst);
                            return Ok(());
                        }
                        () = gate.release.cancelled() => {}
                    }
                }
                let id = message["id"].clone();
                let body = match method {
                    // Exercise the official legacy fallback; the owner behavior is protocol-independent.
                    "server/discover" => serde_json::json!({"jsonrpc":"2.0","id":id,
            "error":{"code":-32601,"message":"fixture uses initialize"}}),
                    "initialize" if failure == "handshake" => {
                        serde_json::json!({"jsonrpc":"2.0","id":id,
            "error":{"code":-32603,"message":"fixture handshake failure"}})
                    }
                    "initialize" => serde_json::json!({"jsonrpc":"2.0","id":id,"result":{
            "protocolVersion":"2025-11-25","capabilities":{"tools":{}},
            "serverInfo":{"name":"gated-fixture","version":"1"}}}),
                    "tools/list" if failure == "list" => {
                        serde_json::json!({"jsonrpc":"2.0","id":id,
            "error":{"code":-32603,"message":"fixture list failure"}})
                    }
                    "tools/list" => serde_json::json!({"jsonrpc":"2.0","id":id,"result":{
            "tools":[{"name":"probe","description":"isolated probe",
                "inputSchema":{"type":"object","properties":{}}}]}}),
                    _ => serde_json::Value::Null,
                };
                let (status, body) = if body.is_null() {
                    (
                        if http_method == "GET" {
                            "405 Method Not Allowed"
                        } else if http_method == "DELETE" {
                            "200 OK"
                        } else {
                            "202 Accepted"
                        },
                        String::new(),
                    )
                } else {
                    ("200 OK", body.to_string())
                };
                let session = if method == "initialize" {
                    "Mcp-Session-Id: fixture-session\r\n"
                } else {
                    ""
                };
                let response = format!(
                    "HTTP/1.1 {status}\r\n{session}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                socket.write_all(response.as_bytes()).await?;
                socket.shutdown().await?;
                Ok(())
            }

            struct Environment {
                _temp: tempfile::TempDir,
                provider: Mutex<Option<pl_provider_fixture::FixtureServer>>,
                home: std::path::PathBuf,
                project_id: String,
                runtime: StudioRuntime,
                prompt_sequence: AtomicUsize,
            }
            impl Environment {
                async fn new(servers: &[(&str, &Server, bool, &str)]) -> Result<Self> {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _unused_endpoint = configure(&home)?;
                    let provider = pl_provider_fixture::FixtureServer::start(vec![
                        pl_provider_fixture::Step::prompt(
                            pl_provider_fixture::Protocol::ResponsesHttp,
                            "hello",
                            0,
                            pl_provider_fixture::Reply::Sse(pl_provider_fixture::responses_text(
                                "done",
                                "initial",
                                "standalone-model",
                            )),
                        )
                        .optional(),
                        pl_provider_fixture::Step::prompt(
                            pl_provider_fixture::Protocol::ResponsesHttp,
                            "hello second",
                            1,
                            pl_provider_fixture::Reply::Sse(pl_provider_fixture::responses_text(
                                "done",
                                "second",
                                "standalone-model",
                            )),
                        )
                        .optional(),
                    ])
                    .await?;
                    let store = ConfigStore::new(ConfigPaths::from_config_dir(&home));
                    let mut config = store.load()?;
                    config.skills.enabled = false;
                    let mut model = ModelInfo::compatible("standalone-model");
                    model
                        .binding
                        .set_transport(pl_model::model::ModelTransportProfile::responses_http());
                    config.models.accounts.insert(
                        AccountId::new("standalone-fixture")?,
                        AccountConfig::from_explicit_models(
                            ProtocolEndpoint::compatible("isolated", provider.base_url()),
                            vec![model],
                        ),
                    );
                    store.save(&config)?;
                    let directory = store.paths().mcp_host_dir();
                    tokio::fs::create_dir_all(&directory).await?;
                    for (id, server, required, extra) in servers {
                        tokio::fs::write(
                            directory.join(format!("{id}.toml")),
                            document(id, server, *required, extra),
                        )
                        .await?;
                    }
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir(&workspace).await?;
                    let project_id = runtime.open_project(&workspace).await?.id;
                    Ok(Self {
                        _temp: temp,
                        provider: Mutex::new(Some(provider)),
                        home,
                        project_id,
                        runtime,
                        prompt_sequence: AtomicUsize::new(0),
                    })
                }
                async fn create(&self) -> Result<crate::StudioStartNewThreadResponse> {
                    let mut request = request(pl_protocol::ThreadWorkspaceMode::Local);
                    let prompt_index = self.prompt_sequence.fetch_add(1, Ordering::Relaxed);
                    request.input.input_id = format!("standalone-start-{prompt_index}");
                    if prompt_index == 1 {
                        request.input.text = "hello second".into();
                    }
                    self.runtime
                        .create_thread_command(self.project_id.clone(), request, None)
                        .await
                }
                async fn shutdown(&self) -> Result<()> {
                    let result = self.runtime.shutdown_runtime().await;
                    let provider = self.provider.lock().unwrap().take();
                    if let Some(provider) = provider {
                        provider.finish().await?;
                    }
                    result?;
                    Ok(())
                }
            }
            fn document(id: &str, server: &Server, required: bool, extra: &str) -> String {
                format!(
                    "schema_version = 1\nid = \"{id}\"\nkind = \"server\"\ntransport = \"streamableHttp\"\nurl = \"{}\"\nrequired = {required}\n{extra}",
                    server.url
                )
            }
            async fn wait_state(
                runtime: &StudioRuntime,
                id: &str,
                server: &str,
                state: Lifecycle,
            ) -> Result<()> {
                let mut events = runtime.agent_facility.product_events.subscribe_internal();
                eprintln!(
                    "MCP_WAIT_STATE server={server} target={state:?} current={:?}",
                    runtime.read_thread_mcp(id).await?.servers
                );
                loop {
                    if runtime
                        .read_thread_mcp(id)
                        .await?
                        .servers
                        .iter()
                        .any(|entry| entry.id == server && entry.lifecycle == state)
                    {
                        return Ok(());
                    }
                    match events.recv().await {
                        Ok(_) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
                        Err(error) => return Err(error.into()),
                    }
                }
            }

            async fn wait_thread_lsp_binding(
                runtime: &StudioRuntime,
                thread_id: &str,
            ) -> Result<crate::protocol::StudioThreadLspStateSnapshot> {
                let mut subscription = runtime
                    .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
                        thread_id: thread_id.to_owned(),
                    })
                    .await?;
                tokio::time::timeout(Duration::from_secs(10), async {
                    loop {
                        let Some(frame) = subscription.recv().await? else {
                            anyhow::bail!("Thread LSP topic closed");
                        };
                        let snapshot = match frame {
                            crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                                crate::StudioProductBaselineState::ThreadLsp(snapshot) => {
                                    Some(*snapshot)
                                }
                                _ => {
                                    anyhow::bail!("Thread LSP topic produced a different baseline")
                                }
                            },
                            crate::StudioProductFrame::Event(event) => match event.kind {
                                crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => {
                                    Some(snapshot)
                                }
                                _ => None,
                            },
                            crate::StudioProductFrame::Lagged { .. } => None,
                        };
                        if let Some(snapshot) = snapshot
                            && snapshot.binding_id.is_some()
                        {
                            return Ok(snapshot);
                        }
                    }
                })
                .await
                .context("Thread LSP binding was not published")?
            }

            #[tokio::test]
            async fn thread_lsp_projection_is_scoped_to_each_accepted_binding() -> Result<()> {
                let env = Environment::new(&[]).await?;
                let first = env.create().await?;
                let first_state = wait_thread_lsp_binding(&env.runtime, &first.thread.id).await?;
                assert!(!first_state.binding_id.as_deref().unwrap().is_empty());
                assert!(first_state.servers.is_empty());
                let first_read = env.runtime.read_thread_lsp_state(&first.thread.id).await?;
                assert_eq!(first_read.revision, first_state.revision);
                assert_eq!(first_read.binding_id, first_state.binding_id);

                let second = env.create().await?;
                let second_state = wait_thread_lsp_binding(&env.runtime, &second.thread.id).await?;
                assert!(!second_state.binding_id.as_deref().unwrap().is_empty());
                assert_ne!(first_state.binding_id, second_state.binding_id);
                assert!(second_state.revision > first_state.revision);
                let first_after_second =
                    env.runtime.read_thread_lsp_state(&first.thread.id).await?;
                assert_eq!(first_after_second.binding_id, first_state.binding_id);
                assert_eq!(first_after_second.servers, first_state.servers);

                let stale = env
                    .runtime
                    .reset_thread_lsp_server(pl_protocol::studio::ThreadLspResetRequest {
                        thread_id: first.thread.id.clone(),
                        binding_id: "expired-binding-qualification".into(),
                        server_id: "irrelevant-while-stale".into(),
                    })
                    .await
                    .expect_err("stale qualification must be rejected before member lookup");
                let stale = stale
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .expect("typed stale binding error");
                assert_eq!(stale.code, pl_protocol::studio::StudioErrorCode::Conflict);
                assert_eq!(
                    stale.reason(),
                    Some(pl_protocol::studio::StudioErrorReason::StaleLspBinding.label())
                );

                let absent = env
                    .runtime
                    .reset_thread_lsp_server(pl_protocol::studio::ThreadLspResetRequest {
                        thread_id: first.thread.id.clone(),
                        binding_id: first_state.binding_id.clone().unwrap(),
                        server_id: "not-a-member".into(),
                    })
                    .await
                    .expect_err("a server outside this binding must be rejected");
                assert_eq!(
                    absent
                        .downcast_ref::<pl_protocol::studio::StudioError>()
                        .map(|error| error.code),
                    Some(pl_protocol::studio::StudioErrorCode::NotFound)
                );

                let mut retired_subscription = env
                    .runtime
                    .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
                        thread_id: first.thread.id.clone(),
                    })
                    .await?;
                let scope = env
                    .runtime
                    .thread_factory
                    .resource_scope(&first.thread.id)
                    .expect("active Thread resource scope");
                env.runtime
                    .thread_factory
                    .close_scope_tools(&first.thread.id, &scope)
                    .await?;
                let retired = tokio::time::timeout(Duration::from_secs(10), async {
                    loop {
                        let Some(frame) = retired_subscription.recv().await? else {
                            anyhow::bail!("Thread LSP topic closed before retirement");
                        };
                        let snapshot = match frame {
                            crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                                crate::StudioProductBaselineState::ThreadLsp(snapshot) => {
                                    Some(*snapshot)
                                }
                                _ => {
                                    anyhow::bail!("Thread LSP topic produced a different baseline")
                                }
                            },
                            crate::StudioProductFrame::Event(event) => match event.kind {
                                crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => {
                                    Some(snapshot)
                                }
                                _ => None,
                            },
                            crate::StudioProductFrame::Lagged { .. } => None,
                        };
                        if let Some(snapshot) = snapshot
                            && snapshot.binding_id.is_none()
                            && snapshot.revision > first_state.revision
                        {
                            return Ok(snapshot);
                        }
                    }
                })
                .await
                .context("retired Thread LSP empty projection was not published")??;
                assert!(retired.servers.is_empty());
                let empty_read = env.runtime.read_thread_lsp_state(&first.thread.id).await?;
                assert_eq!(empty_read.revision, retired.revision);
                assert_eq!(empty_read.binding_id, None);
                assert!(empty_read.servers.is_empty());

                let released = env
                    .runtime
                    .reset_thread_lsp_server(pl_protocol::studio::ThreadLspResetRequest {
                        thread_id: first.thread.id.clone(),
                        binding_id: first_state.binding_id.clone().unwrap(),
                        server_id: "released-binding-server".into(),
                    })
                    .await
                    .expect_err("a retired Thread binding must be rejected as stale");
                let released = released
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .expect("typed released binding error");
                assert_eq!(
                    released.code,
                    pl_protocol::studio::StudioErrorCode::Conflict
                );
                assert_eq!(
                    released.reason(),
                    Some(pl_protocol::studio::StudioErrorReason::StaleLspBinding.label())
                );

                let unknown = env
                    .runtime
                    .read_thread_lsp_state("unknown-thread-lsp")
                    .await
                    .expect_err("unknown Thread must not become an empty successful projection");
                assert_eq!(
                    unknown
                        .downcast_ref::<pl_protocol::studio::StudioError>()
                        .map(|error| error.code),
                    Some(pl_protocol::studio::StudioErrorCode::NotFound)
                );
                env.shutdown().await?;
                Ok(())
            }

            #[tokio::test]
            async fn thread_lsp_cancellation_after_snapshot_commits_only_empty_projection()
            -> Result<()> {
                let env = Environment::new(&[]).await?;
                let project = env
                    .runtime
                    .agent_facility
                    .product_events
                    .project_snapshot()
                    .await
                    .into_iter()
                    .find(|project| project.id == env.project_id)
                    .context("fixture project record")?;
                let root = std::path::PathBuf::from(project.path);
                let configuration = root.join(".anywork/lsp/fixture.toml");
                tokio::fs::create_dir_all(configuration.parent().unwrap()).await?;
                let peer = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                    .parent()
                    .context("Runtime crate parent")?
                    .join("pl-tool/tests/support/lsp_fixture.py");
                anyhow::ensure!(peer.is_file(), "missing real LSP fixture {peer:?}");
                let source = format!(
                    "schema_version = 1\nid = 'fixture'\ncommand = 'python3'\nargs = {}\nlanguage_ids = ['fixture']\nextensions = ['fixture']\noperations = ['hover']\n",
                    serde_json::to_string(&[
                        "-u".to_owned(),
                        peer.display().to_string(),
                        "{workspaceRoot}/lsp-requests.jsonl".to_owned(),
                    ])?
                );
                tokio::fs::write(&configuration, source).await?;

                let created = env.create().await?;
                let thread_id = created.thread.id.clone();
                let mut topic = env
                    .runtime
                    .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
                        thread_id: thread_id.clone(),
                    })
                    .await?;
                let initial = loop {
                    let Some(frame) = topic.recv().await? else {
                        anyhow::bail!("Thread LSP topic closed");
                    };
                    let snapshot = match frame {
                        crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                            crate::StudioProductBaselineState::ThreadLsp(snapshot) => {
                                Some(*snapshot)
                            }
                            _ => anyhow::bail!("unexpected Thread LSP baseline"),
                        },
                        crate::StudioProductFrame::Event(event) => match event.kind {
                            crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => {
                                Some(snapshot)
                            }
                            _ => None,
                        },
                        crate::StudioProductFrame::Lagged { dropped, .. } => {
                            anyhow::bail!("Thread LSP topic lost {dropped} frames")
                        }
                    };
                    if let Some(snapshot) = snapshot
                        && snapshot.binding_id.is_some()
                        && snapshot.servers.iter().any(|server| server.id == "fixture")
                    {
                        break snapshot;
                    }
                };
                let binding_id = initial.binding_id.clone().unwrap();
                let mut result_topic = env
                    .runtime
                    .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
                        thread_id: thread_id.clone(),
                    })
                    .await?;
                let (entered, resume) = env
                    .runtime
                    .external_runtimes
                    .lsp_state
                    .pause_thread_snapshot_for_test("fixture");
                let refresh_runtime = env.runtime.clone();
                let refresh =
                    tokio::spawn(async move { refresh_runtime.refresh_thread_lsp_states().await });
                let mut entered = entered;
                entered.wait_for(|paused| *paused).await?;
                let current = env.runtime.thread_factory.binding_snapshot(&thread_id);
                let Some(current) = current else {
                    resume.send_replace(true);
                    anyhow::bail!(
                        "current accepted Thread binding disappeared before cancellation"
                    );
                };
                let same_binding = current.lsp_binding_id.as_deref() == Some(binding_id.as_str());
                let captured_member = initial.servers.iter().any(|server| server.id == "fixture");
                current.lifetime.cancel();
                resume.send_replace(true);
                assert!(
                    same_binding,
                    "the cancellation must target the captured binding"
                );
                assert!(
                    captured_member,
                    "captured LSP server member must be non-empty"
                );
                refresh.await??;
                let published = env.runtime.read_thread_lsp_state(&thread_id).await?;
                assert!(published.revision > initial.revision);
                assert_eq!(published.binding_id, None);
                assert!(published.servers.is_empty());
                let retired_event = loop {
                    let Some(frame) = result_topic.recv().await? else {
                        anyhow::bail!("Thread LSP topic closed before invalidation event");
                    };
                    let snapshot = match frame {
                        crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                            crate::StudioProductBaselineState::ThreadLsp(snapshot) => {
                                Some(*snapshot)
                            }
                            _ => anyhow::bail!("unexpected Thread LSP baseline"),
                        },
                        crate::StudioProductFrame::Event(event) => match event.kind {
                            crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => {
                                Some(snapshot)
                            }
                            _ => None,
                        },
                        crate::StudioProductFrame::Lagged { dropped, .. } => {
                            anyhow::bail!("Thread LSP topic lost {dropped} events")
                        }
                    };
                    if let Some(snapshot) = snapshot
                        && snapshot.revision > initial.revision
                    {
                        break snapshot;
                    }
                };
                assert_eq!(retired_event.binding_id, None);
                assert!(retired_event.servers.is_empty());
                env.shutdown().await?;
                Ok(())
            }
            fn tool_id(server: &str) -> String {
                format!("mcp__{server}__probe")
            }
            async fn wait_tool(
                runtime: &StudioRuntime,
                thread: &pl_core::thread::ThreadHandle,
                id: String,
            ) -> Result<()> {
                let mut snapshots = thread.subscribe();
                let mut events = runtime.agent_facility.product_events.subscribe_internal();
                eprintln!(
                    "MCP_TOOL_WAIT cleanup={:?} model={:?}",
                    thread.snapshot().tool_cleanup,
                    thread.snapshot().model_execution
                );
                loop {
                    if tokio::time::timeout(
                        Duration::from_secs(5),
                        thread.reveal_tools(vec![id.clone()]),
                    )
                    .await
                    .with_context(|| {
                        format!(
                            "actor did not answer reveal; model={:?}",
                            thread.snapshot().model_execution
                        )
                    })?
                    .is_ok()
                    {
                        assert!(
                            thread
                                .snapshot()
                                .discovered_tools
                                .iter()
                                .any(|tool| tool.tool_id == id)
                        );
                        return Ok(());
                    }
                    let issues = runtime.recovery_issues();
                    if let Some(issue) = issues.iter().find(|issue| {
                        issue.category == crate::studio::StudioRecoveryIssueCategory::ToolCatalog
                    }) {
                        anyhow::bail!("{}", issue.message);
                    }
                    tokio::select! {
                        snapshot = snapshots.next() => { snapshot.context("Thread closed before MCP tool refresh")?; }
                        event = events.recv() => { event?; }
                    }
                }
            }

            #[tokio::test]
            async fn optional_preparation_accepts_before_handshake_then_refreshes_and_reports_failure()
            -> Result<()> {
                tokio::time::timeout(Duration::from_secs(20), async {
                    let dispatch = tracing::Dispatch::new(PreparationLog::default());
                    let _capture = tracing::dispatcher::set_default(&dispatch);
                    let good = Server::new("").await?;
                    let failed = Server::new("list").await?;
                    let env = Environment::new(&[
                        ("optional", &good, false, "startup_timeout_secs = 60\n"),
                        ("failed", &failed, false, "startup_timeout_secs = 60\n"),
                    ])
                    .await?;
                    let started = Instant::now();
                    let response = env.create().await?;
                    good.gate.reached.cancelled().await;
                    failed.gate.reached.cancelled().await;
                    assert!(!good.gate.release.is_cancelled());
                    assert!(
                        response.submission.cursor > 0,
                        "input accepted while both handshakes are held"
                    );
                    eprintln!(
                        "OPTIONAL_PREPARATION accepted_with_closed_gate=true create_ms={}",
                        started.elapsed().as_millis()
                    );
                    let thread = env.runtime.ensure_thread_owner(&response.thread.id).await?;
                    eprintln!("MCP_OPTIONAL owner acquired");
                    assert!(
                        thread
                            .reveal_tools(vec![tool_id("optional")])
                            .await
                            .is_err()
                    );
                    eprintln!("MCP_OPTIONAL absent tool checked");
                    let initial = env.runtime.read_thread_mcp(&response.thread.id).await?;
                    assert!(
                        initial
                            .servers
                            .iter()
                            .all(|entry| entry.lifecycle == Lifecycle::Connecting)
                    );
                    good.gate.release.cancel();
                    failed.gate.release.cancel();
                    wait_state(
                        &env.runtime,
                        &response.thread.id,
                        "optional",
                        Lifecycle::Available,
                    )
                    .await?;
                    wait_state(
                        &env.runtime,
                        &response.thread.id,
                        "failed",
                        Lifecycle::Unavailable,
                    )
                    .await?;
                    wait_tool(&env.runtime, &thread, tool_id("optional")).await?;
                    eprintln!("MCP_OPTIONAL catalog installed");
                    assert!(
                        env.runtime
                            .read_thread_mcp(&response.thread.id)
                            .await?
                            .generation
                            > initial.generation
                    );
                    env.shutdown().await?;
                    eprintln!("MCP_OPTIONAL runtime stopped");
                    good.close().await?;
                    eprintln!("MCP_OPTIONAL good fixture stopped");
                    failed.close().await?;
                    Ok::<_, anyhow::Error>(())
                })
                .await?
            }

            #[tokio::test]
            async fn mixed_preparation_waits_only_required_and_reuses_its_ready_connection()
            -> Result<()> {
                tokio::time::timeout(Duration::from_secs(20), async {
        let required = Server::new("").await?;
        let optional = Server::new("").await?;
        let env = Environment::new(&[
            ("required", &required, true, "startup_timeout_secs = 60\n"),
            ("optional", &optional, false, "startup_timeout_secs = 60\n"),
        ])
        .await?;
        let creating = env.create();
        tokio::pin!(creating);
        tokio::select! {
            () = required.gate.reached.cancelled() => {}
            result = &mut creating => panic!("required handshake was bypassed: {result:?}"),
        }
        assert!(futures::poll!(&mut creating).is_pending());
        required.gate.release.cancel();
        eprintln!("MCP_MIXED required gate released");
        let response = creating.await?;
        eprintln!("MCP_MIXED created");
        optional.gate.reached.cancelled().await;
        assert!(!optional.gate.release.is_cancelled());
        assert!(response.submission.cursor > 0);
        let thread = env.runtime.ensure_thread_owner(&response.thread.id).await?;
        // Immediate discovery checks the actual first catalog, not just the health projection.
        thread.reveal_tools(vec![tool_id("required")]).await?;
        assert!(
            thread
                .reveal_tools(vec![tool_id("optional")])
                .await
                .is_err()
        );
        optional.gate.release.cancel();
        wait_tool(&env.runtime, &thread, tool_id("optional")).await?;
        assert_eq!(required.gate.handshakes.load(Ordering::SeqCst), 1);
        env.shutdown().await?;
        required.close().await?;
        optional.close().await?;
        Ok::<_, anyhow::Error>(())
    })
    .await?
            }

            #[tokio::test]
            async fn required_failures_compensate_and_disabled_required_does_not_start()
            -> Result<()> {
                tokio::time::timeout(Duration::from_secs(30), async {
        for (failure, extra) in [
            ("handshake", "startup_timeout_secs = 2\n"),
            ("list", "startup_timeout_secs = 2\n"),
            ("timeout", "startup_timeout_secs = 1\n"),
            (
                "credential",
                "bearer_token_env_var = \"ANYWORK_ISOLATED_MCP_MISSING_CREDENTIAL_6802B2ED\"\n",
            ),
            ("disabled", "enabled = false\n"),
        ] {
            let server = Server::new(failure).await?;
            if failure != "timeout" {
                server.gate.release.cancel();
            }
            let env = Environment::new(&[("required", &server, true, extra)]).await?;
            let result = env.create().await;
            eprintln!(
                "MCP_REQUIRED_CASE kind={failure} accepted={}",
                result.is_ok()
            );
            if failure == "disabled" {
                assert!(result.is_ok(), "{result:?}");
                assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 0);
            } else {
                let error = result.expect_err("enabled required failure must reject creation");
                assert!(
                    format!("{error:#}").contains("required MCP server"),
                    "{error:#}"
                );
                assert!(
                    env.runtime
                        .store
                        .list_threads_for_project(&env.project_id)
                        .await?
                        .iter()
                        .all(|thread| thread.visibility != crate::studio::ThreadVisibility::Active)
                );
                assert!(env.runtime.sessions.observed_threads().is_empty());
            }
            env.shutdown().await?;
            server.close().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await?
            }

            #[tokio::test]
            async fn invalid_reconnect_preserves_pending_optional_preparation() -> Result<()> {
                tokio::time::timeout(Duration::from_secs(20), async {
                    for failure in ["", "list"] {
                        let server = Server::new(failure).await?;
                        let env = Environment::new(&[(
                            "optional",
                            &server,
                            false,
                            "startup_timeout_secs = 60\n",
                        )])
                        .await?;
                        let response = env.create().await?;
                        server.gate.reached.cancelled().await;
                        let thread = env.runtime.ensure_thread_owner(&response.thread.id).await?;
                        // The actor's initial directory is installed and answers discovery while the
                        // optional handshake remains held. A rejected command must not fence that owner.
                        thread.reveal_tools(vec!["discover_tools".into()]).await?;
                        let before = env.runtime.read_thread_mcp(&response.thread.id).await?;
                        assert_eq!(before.servers[0].lifecycle, Lifecycle::Connecting);

                        let rejected = tokio::time::timeout(
                            Duration::from_secs(2),
                            env.runtime.reconnect_thread_mcp(
                                pl_protocol::ReconnectThreadMcpRequest {
                                    thread_id: response.thread.id.clone(),
                                    server_id: Some("missing".into()),
                                },
                            ),
                        )
                        .await
                        .context("invalid reconnect waited for the unrelated optional handshake")?
                        .expect_err("a missing reconnect target must be rejected");
                        let public = rejected
                            .downcast_ref::<pl_protocol::studio::StudioError>()
                            .context(
                                "invalid reconnect must preserve its public error classification",
                            )?;
                        assert_eq!(
                            public.code,
                            pl_protocol::studio::StudioErrorCode::InvalidArgument
                        );
                        assert!(rejected.to_string().contains("not enabled"), "{rejected:#}");
                        assert!(!server.gate.release.is_cancelled());
                        assert_eq!(
                            env.runtime.read_thread_mcp(&response.thread.id).await?,
                            before,
                            "rejection must not mutate the existing preparation projection"
                        );

                        server.gate.release.cancel();
                        let expected = if failure.is_empty() {
                            Lifecycle::Available
                        } else {
                            Lifecycle::Unavailable
                        };
                        wait_state(&env.runtime, &response.thread.id, "optional", expected).await?;
                        if failure.is_empty() {
                            wait_tool(&env.runtime, &thread, tool_id("optional")).await?;
                        }
                        assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 1);
                        env.shutdown().await?;
                        server.close().await?;
                    }
                    Ok::<_, anyhow::Error>(())
                })
                .await?
            }

            #[tokio::test]
            async fn pending_preparation_is_joined_on_configuration_reconnect_and_shutdown()
            -> Result<()> {
                tokio::time::timeout(Duration::from_secs(30), async {
                    for action in [
                        "configuration",
                        "reconnect",
                        "changed-failed-reconnect",
                        "shutdown",
                    ] {
                        let server = Server::new("").await?;
                        let replacement = if action == "changed-failed-reconnect" {
                            let server = Server::new("list").await?;
                            server.gate.release.cancel();
                            Some(server)
                        } else {
                            None
                        };
                        let env = Environment::new(&[(
                            "optional",
                            &server,
                            false,
                            "startup_timeout_secs = 60\n",
                        )])
                        .await?;
                        let response = env.create().await?;
                        server.gate.reached.cancelled().await;
                        if action == "shutdown" {
                            env.shutdown().await?;
                            assert!(server.gate.disconnected.load(Ordering::SeqCst) > 0);
                        } else if action.ends_with("reconnect") {
                            if let Some(replacement) = &replacement {
                                let directory =
                                    ConfigPaths::from_config_dir(&env.home).mcp_host_dir();
                                tokio::fs::write(
                                    directory.join("optional.toml"),
                                    document("optional", replacement, false, ""),
                                )
                                .await?;
                                // Freeze the legitimate interval between catalog commit and per-owner
                                // reconciliation. Explicit reconnect must not present the old endpoint's
                                // ready lease as readiness of this newly committed, failing endpoint.
                                env.runtime
                                    .config_runtime
                                    .reload_mcp_catalog(&McpScope::Host)?;
                            }
                            let reconnecting = env.runtime.reconnect_thread_mcp(
                                pl_protocol::ReconnectThreadMcpRequest {
                                    thread_id: response.thread.id.clone(),
                                    server_id: None,
                                },
                            );
                            tokio::pin!(reconnecting);
                            assert!(futures::poll!(&mut reconnecting).is_pending());
                            server.gate.release.cancel();
                            let result = reconnecting.await;
                            if let Some(replacement) = &replacement {
                                assert!(result.is_err());
                                let state =
                                    env.runtime.read_thread_mcp(&response.thread.id).await?;
                                assert_eq!(state.servers[0].endpoint_summary, replacement.url);
                                assert_eq!(state.servers[0].lifecycle, Lifecycle::Unavailable);
                            } else {
                                assert_eq!(result?.servers[0].lifecycle, Lifecycle::Available);
                                assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 2);
                            }
                            env.shutdown().await?;
                        } else {
                            let directory = ConfigPaths::from_config_dir(&env.home).mcp_host_dir();
                            tokio::fs::write(
                                directory.join("optional.toml"),
                                document("optional", &server, false, "enabled = false\n"),
                            )
                            .await?;
                            env.runtime.reload_mcp_catalog(&McpScope::Host).await?;
                            server.gate.release.cancel();
                            assert_eq!(server.gate.handshakes.load(Ordering::SeqCst), 1);
                            let state = env.runtime.read_thread_mcp(&response.thread.id).await?;
                            assert!(
                                state
                                    .servers
                                    .iter()
                                    .all(|entry| entry.lifecycle != Lifecycle::Available)
                            );
                            env.shutdown().await?;
                            let closed = env.runtime.read_thread_mcp(&response.thread.id).await?;
                            assert!(
                                closed.servers.is_empty(),
                                "no late producer publication after close"
                            );
                        }
                        server.close().await?;
                        if let Some(replacement) = replacement {
                            replacement.close().await?;
                        }
                    }
                    Ok::<_, anyhow::Error>(())
                })
                .await?
            }
        }
    }

    mod archive_responsibility {
        //! Real failed spawn disposal and process restart, using only isolated product/workspace fixtures.
        use super::*;
        use crate::{
            studio::{
                agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
                storage_fault_test_support::{
                    ThreadStorageSink, close_factory, spawn_live_projection_for_thread,
                },
                store::{
                    thread_archive::{ArchivePhase, ArchiveScope},
                    thread_preparation::{
                        PreparationBinding, PreparationDisposition, PreparationIdentity,
                        PreparationSave, ThreadPreparationRecord,
                    },
                },
            },
            thread_assembler::{
                ChildThreadRequest, StudioChildFactory, StudioChildResources, StudioThreadSpec,
                ThreadAssemblyError, archive_test_spec, spawn_failed_archive_fixture,
            },
        };
        use pl_core::thread::{
            ThreadHandle,
            cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
        };
        use sea_orm::ConnectionTrait;
        use std::{sync::Arc, time::Duration};

        type Prepare = dyn Fn(
                ChildThreadRequest,
            )
                -> futures::future::BoxFuture<'static, Result<StudioThreadSpec, ThreadAssemblyError>>
            + Send
            + Sync;
        struct FailingPreparer {
            prepare: Arc<Prepare>,
            physical: crate::studio::StudioThreadFactory,
        }
        impl std::fmt::Debug for FailingPreparer {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("FailingPreparer")
            }
        }
        impl StudioChildFactory for FailingPreparer {
            type Admission = ();

            async fn admit(
                &self,
                _: &str,
                _: pl_protocol::DelegationSettings,
                _: Option<pl_protocol::studio::NewThreadModelRoute>,
            ) -> Result<(), ThreadAssemblyError> {
                Ok(())
            }

            async fn prepare(
                &self,
                request: ChildThreadRequest,
                _: (),
            ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
                (self.prepare)(request).await
            }
            async fn discard_unpublished(
                &self,
                id: &str,
                usage: Option<&crate::studio::WorkspaceUsageLease>,
                disposition: pl_tool::collaboration::thread::WorkspaceRelease,
            ) -> Result<(), ThreadAssemblyError> {
                StudioChildResources::discard_unpublished(&self.physical, id, usage, disposition)
                    .await
            }
        }

        async fn git(root: &Path, args: &[&str]) -> Result<()> {
            let output = tokio::process::Command::new("git")
                .args(args)
                .current_dir(root)
                .output()
                .await?;
            ensure!(
                output.status.success(),
                "isolated worktree fixture: {output:?}"
            );
            Ok(())
        }

        #[tokio::test]
        async fn archive_first_scope_write_failure_recovers_exited_private_owner_and_original_binding()
        -> Result<()> {
            for restart in [false, true] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                git(&workspace, &["init", "--quiet"]).await?;
                git(
                    &workspace,
                    &[
                        "-c",
                        "user.name=fixture",
                        "-c",
                        "user.email=fixture@example.invalid",
                        "commit",
                        "--quiet",
                        "--allow-empty",
                        "-m",
                        "fixture",
                    ],
                )
                .await?;
                let checkout = dunce::canonicalize(temp.path())?.join("private-worktree");
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let root = runtime
                    .create_thread_with_id("first-write-root", &project.id, "root")
                    .await?;
                runtime.ensure_thread_owner(&root.id).await?.flush().await?;
                let physical = Arc::new(close_factory(&runtime.store)?);
                let release = Arc::new(tokio::sync::Semaphore::new(0));
                let (ready, mut prepared) = tokio::sync::watch::channel(None);
                let factory = FailingPreparer {
                    physical: physical.factory.clone(),
                    prepare: Arc::new({
                        let physical = physical.clone();
                        let repository = workspace.clone();
                        let workspace = checkout.clone();
                        let release = release.clone();
                        let store = runtime.store.clone();
                        move |request| {
                            let physical = physical.clone();
                            let repository = repository.clone();
                            let workspace = workspace.clone();
                            let release = release.clone();
                            let ready = ready.clone();
                            let store = store.clone();
                            Box::pin(async move {
                                let binding = WorkspaceIdentity::canonical(
                                    WorkspaceEndpoint::Local,
                                    workspace.to_string_lossy().into_owned(),
                                )
                                .unwrap();
                                store
                                    .bind_thread_preparation(&request.id, &binding)
                                    .await
                                    .unwrap();
                                git(
                                    &repository,
                                    &[
                                        "worktree",
                                        "add",
                                        "--quiet",
                                        "--detach",
                                        workspace.to_str().unwrap(),
                                        "HEAD",
                                    ],
                                )
                                .await
                                .unwrap();
                                let owner = physical
                                    .unpublished_workspace(&request.id, &workspace)
                                    .await
                                    .unwrap();
                                ready.send_replace(Some((
                                    request.id.clone(),
                                    request.cancellation.clone(),
                                )));
                                release.acquire().await.unwrap().forget();
                                drop(owner);
                                Err(ThreadAssemblyError::Closed)
                            })
                        }
                    }),
                };
                let mut spawn = tokio::spawn(spawn_failed_archive_fixture(
                    runtime.session_for_roots(std::slice::from_ref(&root.id))?,
                    root.id.clone(),
                    factory,
                ));
                tokio::time::timeout(Duration::from_secs(5), prepared.wait_for(Option::is_some))
                    .await??;
                let (id, cancellation) = prepared.borrow().clone().unwrap();
                let files = pl_tool::workspace::SessionFiles::new(&id);
                let session = checkout.join(files.root());
                tokio::fs::write(checkout.join("business"), b"keep worktree").await?;
                for directory in ["artifacts", ".venv", "scratch/.venv"] {
                    tokio::fs::create_dir_all(session.join(directory)).await?;
                    tokio::fs::write(session.join(directory).join("keep"), directory).await?;
                }
                runtime
                    .store
                    .database()
                    .execute_unprepared(
                        "CREATE TRIGGER reject_first_archive BEFORE INSERT ON studio_objects
             WHEN NEW.object_kind='threadArchive'
             BEGIN SELECT RAISE(ABORT,'injected first archive scope failure'); END",
                    )
                    .await?;
                let first = tokio::time::timeout(
                    Duration::from_secs(5),
                    runtime.archive_thread("first-write-failure".into(), root.id.clone()),
                )
                .await?;
                assert!(first.is_err());
                assert!(
                    runtime.store.publish_preparation(&id).await.is_err(),
                    "an admitted builder must not publish away retained archive preserve responsibility"
                );
                assert!(
                    !cancellation.is_cancelled(),
                    "no cancellation before the complete scope commits"
                );
                assert!(
                    runtime
                        .store
                        .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                        .await?
                        .is_none()
                );
                release.add_permits(1);
                assert!(
                    tokio::time::timeout(Duration::from_secs(5), &mut spawn)
                        .await??
                        .is_err()
                );
                let scope = runtime
                    .session_for_roots(std::slice::from_ref(&root.id))?
                    .seal_archive_scope(std::slice::from_ref(&root.id))?;
                assert!(
                    !scope.thread_ids().contains(&id),
                    "real disposal and reservation have exited"
                );
                drop(scope);
                let original = runtime.store.thread_preparation(&id).await?.unwrap();
                assert!(original.stopped && original.retired);
                assert_eq!(
                    original.disposition,
                    PreparationDisposition::ArchivePreserve
                );
                assert!(matches!(original.binding, PreparationBinding::Bound { .. }));
                assert!(runtime.store.read_thread(&id).await?.is_none());
                assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
                assert!(session.join("scratch/prepared").exists());
                runtime
                    .store
                    .database()
                    .execute_unprepared("DROP TRIGGER reject_first_archive")
                    .await?;
                physical.shutdown().await?;
                drop(physical);
                let runtime = if restart {
                    runtime.shutdown_runtime().await?;
                    drop(runtime);
                    StudioRuntime::initialize(options(&home)).await?
                } else {
                    runtime
                };
                runtime
                    .archive_thread("first-write-retry".into(), root.id.clone())
                    .await?
                    .context("retry")?;
                let completed = runtime
                    .store
                    .thread_archive(&ArchiveScope::Thread(root.id))
                    .await?
                    .unwrap();
                assert_eq!(completed.phase, ArchivePhase::Published);
                let member = completed
                    .private_members
                    .iter()
                    .find(|member| member.identity.thread_id == id)
                    .context("exited private owner must remain in the complete frozen scope")?;
                assert_eq!(member.binding, original.binding);
                assert!(member.host_cleaned && member.execution_cleaned);
                assert_eq!(
                    runtime
                        .store
                        .thread_preparation(&id)
                        .await?
                        .unwrap()
                        .disposition,
                    PreparationDisposition::TempCleaned
                );
                assert!(!checkout.join(files.temp()).exists());
                assert!(!session.join("scratch/prepared").exists());
                for directory in ["artifacts", ".venv", "scratch/.venv"] {
                    assert_eq!(
                        tokio::fs::read(session.join(directory).join("keep")).await?,
                        directory.as_bytes()
                    );
                }
                assert!(checkout.join(".git").is_file());
                assert_eq!(
                    tokio::fs::read(checkout.join("business")).await?,
                    b"keep worktree"
                );
                let worktrees = tokio::process::Command::new("git")
                    .args(["worktree", "list", "--porcelain", "-z"])
                    .current_dir(&workspace)
                    .output()
                    .await?;
                assert!(worktrees.status.success());
                let expected = dunce::canonicalize(&checkout)?;
                let mut registered = false;
                for field in String::from_utf8(worktrees.stdout)?.split('\0') {
                    if let Some(path) = field.strip_prefix("worktree ") {
                        registered |= dunce::canonicalize(path)? == expected;
                    }
                }
                assert!(registered, "the preserved checkout must remain registered");
                runtime.shutdown_runtime().await?;
            }
            Ok(())
        }

        #[derive(Debug)]
        struct RejectLaterPrivateWrites {
            sink: ThreadStorageSink,
            original_fence: u64,
        }
        impl ColdStore for RejectLaterPrivateWrites {
            fn pressure(&self, id: &str) -> StoragePressure {
                self.sink.pressure(id)
            }
            fn admit(&self, id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
                if write.effect.sequence > self.original_fence {
                    return Err(ColdStoreError {
                        source: Box::new(std::io::Error::other(
                            "injected later private checkpoint failure",
                        )),
                    });
                }
                self.sink.admit(id, write)
            }
            async fn flush(&self, id: &str, through: u64) -> Result<(), ColdStoreError> {
                self.sink.flush(id, through).await
            }
        }

        /// Seeds the isolated home with the durable facts the crashing private owner inherits: the
        /// project, the required root with a durable owner checkpoint, the required-private catalog
        /// row, and a real older incarnation's durable earlier checkpoint. This heavy preparation runs
        /// in the parent and shuts its runtime down cleanly, so the spawned producer's bounded crash
        /// window only has to cover the original owner's own work.
        async fn seed_private_crash_fixture(base: &Path) -> Result<()> {
            eprintln!("private crash seed: start");
            let home = base.join("home");
            let workspace = base.join("workspace");
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            eprintln!("private crash seed: runtime initialized");
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("required-root", &project.id, "root")
                .await?;
            runtime.ensure_thread_owner(&root.id).await?.flush().await?;
            eprintln!("private crash seed: root ready");
            let mut protocol = pl_protocol::Thread::placeholder("required-private");
            protocol.agent_path = protocol.id.clone();
            protocol.workspace_id = project.id.clone();
            protocol.workspace_path = workspace.to_string_lossy().into_owned();
            protocol.root_thread_id = root.id.clone();
            protocol.parent_thread_id = Some(root.id.clone());
            runtime
                .agent_facility
                .product_events
                .commit_directory(crate::studio::store::directory::DirectoryDelta {
                    agent_upserts: vec![crate::studio::records::AgentDirectoryRecord {
                        agent_id: protocol.id.clone(),
                        session_id: protocol.root_thread_id.clone(),
                        parent_agent_id: protocol.parent_thread_id.clone(),
                        thread_id: protocol.id.clone(),
                        role: crate::config::ROOT_AGENT_ROUTE_KEY.into(),
                        title: Some(protocol.id.clone()),
                        backend: pl_protocol::session::AgentBackend::Native {
                            config: pl_protocol::NativeAgentConfig {
                                route: None,
                                system_instructions: None,
                            },
                            status: protocol.status,
                        },
                        explicitly_closed: false,
                        created_at: protocol.created_at,
                        updated_at: protocol.updated_at,
                    }],
                    ..Default::default()
                })
                .await?;
            // A real older incarnation leaves a durable earlier checkpoint before private AttachCold.
            let old = ThreadStorageSink::new(runtime.store.clone(), protocol.clone(), None).await?;
            let projection = spawn_live_projection_for_thread(runtime.store.clone(), &protocol.id);
            let previous = ThreadHandle::resume_without_model(protocol.id.clone(), None)?;
            previous.attach_storage(ColdStoreHandle::new(old)).await?;
            previous.close().await?;
            runtime
                .store
                .thread_persistence()
                .history_channel(&protocol.id)
                .stop_and_join()
                .await?;
            projection.await?;
            runtime.shutdown_runtime().await?;
            eprintln!("private crash seed: earlier checkpoint durable and seed runtime shut down");
            Ok(())
        }

        async fn produce_private_storage_crash(base: &Path, receipt: bool) -> Result<()> {
            eprintln!("private crash fixture: initialize receipt={receipt}");
            let home = base.join("home");
            let workspace = base.join("workspace");
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            eprintln!("private crash fixture: runtime initialized");
            let project = runtime.open_project(&workspace).await?;
            eprintln!("private crash fixture: project reopened");
            // The crashing owner still has to observe the seeded root: assembling required-private
            // reserves against its live parent entry before the private AttachCold.
            runtime
                .ensure_thread_owner("required-root")
                .await?
                .flush()
                .await?;
            eprintln!("private crash fixture: root owner restored");
            let catalog = runtime.store.catalog();
            let private_agent = catalog
                .get_agent("required-private")
                .context("seeded required-private catalog row")?;
            let private_session = catalog
                .get_session(&private_agent.session_id)
                .context("seeded required-private session row")?;
            let protocol = crate::studio::records::thread_projection(
                &private_session,
                &private_agent,
                |id| catalog.get_agent(id).map(|agent| agent.thread_id),
            )?;
            let checkpoint = runtime
                .store
                .history(&protocol.id)
                .await?
                .checkpoint()
                .await?
                .context("seeded durable earlier checkpoint")?;
            eprintln!("private crash fixture: seeded protocol and checkpoint read");
            let old_fence = checkpoint.history_fence;
            let physical = close_factory(&runtime.store)?;
            runtime
                .store
                .begin_thread_preparation(PreparationIdentity {
                    thread_id: protocol.id.clone(),
                    workspace_id: project.id.clone(),
                    parent_id: protocol.parent_thread_id.clone(),
                    root_id: protocol.root_thread_id.clone(),
                })
                .await?;
            let binding = WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                dunce::canonicalize(&workspace)?
                    .to_string_lossy()
                    .into_owned(),
            )?;
            runtime
                .store
                .bind_thread_preparation(&protocol.id, &binding)
                .await?;
            let _preparer = physical
                .unpublished_workspace(&protocol.id, &workspace)
                .await?;
            let files = pl_tool::workspace::SessionFiles::new(&protocol.id);
            tokio::fs::create_dir_all(workspace.join(files.artifacts())).await?;
            tokio::fs::write(workspace.join(files.artifacts()).join("keep"), b"delivery").await?;
            if receipt {
                runtime
                    .store
                    .database()
                    .execute_unprepared(
                        "CREATE TRIGGER reject_original_stop BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadPreparation' AND NEW.owner_id='required-private'
              AND json_extract(NEW.payload_json,'$.stopped')=1
             BEGIN SELECT RAISE(ABORT,'injected stop after original closed receipt'); END",
                    )
                    .await?;
            }
            let sink =
                ThreadStorageSink::new(runtime.store.clone(), protocol.clone(), Some(&checkpoint))
                    .await?;
            let _projection = spawn_live_projection_for_thread(runtime.store.clone(), &protocol.id);
            let storage = if receipt {
                ColdStoreHandle::new(sink)
            } else {
                ColdStoreHandle::new(RejectLaterPrivateWrites {
                    sink,
                    original_fence: old_fence,
                })
            };
            let mut spec = archive_test_spec(
                protocol.id.clone(),
                protocol.parent_thread_id.clone(),
                &workspace,
            );
            spec.checkpoint = Some(checkpoint);
            spec.cold_store = Some(storage);
            spec.initial_extensions.insert(
                String::new(),
                pl_core::context::OpaquePayload::text("invalid initialization"),
            );
            eprintln!("private crash fixture: attach and fail initialization");
            assert!(
                runtime
                    .session_for_roots(&["required-root".to_owned()])?
                    .assemble(spec)
                    .await
                    .is_err()
            );
            eprintln!("private crash fixture: original failure retained");
            let record = runtime
                .store
                .thread_preparation(&protocol.id)
                .await?
                .unwrap();
            assert!(!record.published && !record.stopped);
            assert_eq!(
                record.save,
                if receipt {
                    PreparationSave::Confirmed
                } else {
                    PreparationSave::Required
                }
            );
            let evidence = serde_json::json!({"record": record, "oldFence": old_fence});
            tokio::fs::write(
                base.join("original-owner-evidence.json"),
                serde_json::to_vec(&evidence)?,
            )
            .await?;
            // The enclosing test starts this exact test binary as an isolated producer process. Do not
            // run graceful shutdown: it would either retry or discharge the original obligation.
            std::process::exit(0);
        }

        async fn crash_original_private_owner(
            base: &Path,
            receipt: bool,
        ) -> Result<serde_json::Value> {
            seed_private_crash_fixture(base).await?;
            let mut command = tokio::process::Command::new(std::env::current_exe()?);
            command
        .arg("archive_original_required_receipt_is_not_replaced_by_a_cold_checkpoint_after_crash")
        .arg("--nocapture")
        .env("ANYWORK_ARCHIVE_PRIVATE_CRASH_FIXTURE", base)
        .kill_on_drop(true);
            if receipt {
                command.env("ANYWORK_ARCHIVE_PRIVATE_RECEIPT", "1");
            } else {
                command.env_remove("ANYWORK_ARCHIVE_PRIVATE_RECEIPT");
            }
            command
                .stdout(std::process::Stdio::inherit())
                .stderr(std::process::Stdio::inherit());
            let mut child = command.spawn()?;
            let status = match tokio::time::timeout(Duration::from_secs(20), child.wait()).await {
                Ok(result) => result?,
                Err(error) => {
                    child.kill().await?;
                    child.wait().await?;
                    return Err(error)
                        .context("original private producer did not reach its crash boundary");
                }
            };
            ensure!(status.success(), "original producer fixture: {status}");
            Ok(serde_json::from_slice(
                &tokio::fs::read(base.join("original-owner-evidence.json")).await?,
            )?)
        }

        #[tokio::test]
        async fn archive_original_required_receipt_is_not_replaced_by_a_cold_checkpoint_after_crash()
        -> Result<()> {
            const CHILD: &str = "ANYWORK_ARCHIVE_PRIVATE_CRASH_FIXTURE";
            if let Some(base) = std::env::var_os(CHILD) {
                return produce_private_storage_crash(
                    Path::new(&base),
                    std::env::var_os("ANYWORK_ARCHIVE_PRIVATE_RECEIPT").is_some(),
                )
                .await;
            }
            for receipt in [false, true] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let evidence = crash_original_private_owner(temp.path(), receipt).await?;
                let original: ThreadPreparationRecord =
                    serde_json::from_value(evidence["record"].clone())?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                assert!(
                    runtime
                        .store
                        .read_thread("required-private")
                        .await?
                        .is_some()
                );
                assert!(
                    runtime
                        .session_of("required-private")
                        .and_then(|session| session.observed_thread("required-private"))
                        .is_none()
                );
                if receipt {
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER reject_original_stop")
                        .await?;
                } else {
                    let before = runtime
                        .store
                        .history("required-private")
                        .await?
                        .checkpoint()
                        .await?
                        .unwrap();
                    assert_eq!(before.history_fence, evidence["oldFence"].as_u64().unwrap());
                }
                let result = tokio::time::timeout(
                    Duration::from_secs(10),
                    runtime.archive_thread("required-restart".into(), "required-root".into()),
                )
                .await?;
                let pending = runtime
                    .store
                    .thread_preparation("required-private")
                    .await?
                    .unwrap();
                assert_eq!(
                    pending.storage.as_ref().unwrap().incarnation,
                    original.storage.as_ref().unwrap().incarnation
                );
                let operation = runtime
                    .store
                    .thread_archive(&ArchiveScope::Thread("required-root".into()))
                    .await?
                    .unwrap();
                let member = operation
            .private_members
            .iter()
            .find(|member| member.identity.thread_id == "required-private")
            .context(
                "catalog membership must not promote the original private storage obligation",
            )?;
                assert_eq!(member.binding, original.binding);
                let files = pl_tool::workspace::SessionFiles::new("required-private");
                if receipt {
                    result?.context("valid original closed receipt must permit retry")?;
                    assert_eq!(operation.phase, ArchivePhase::Published);
                    assert_eq!(pending.save, PreparationSave::Confirmed);
                    assert_eq!(pending.disposition, PreparationDisposition::TempCleaned);
                    assert!(!workspace.join(files.temp()).exists());
                } else {
                    assert!(result.is_err());
                    assert_eq!(pending.save, PreparationSave::Required);
                    assert!(pending.storage.as_ref().unwrap().closed_receipt.is_none());
                    assert_eq!(operation.phase, ArchivePhase::Sealed);
                    assert!(
                        runtime
                            .session_of("required-private")
                            .and_then(|session| session.observed_thread("required-private"))
                            .is_none(),
                        "no substitute cold incarnation"
                    );
                    assert!(
                        workspace
                            .join(files.root())
                            .join("scratch/prepared")
                            .exists()
                    );
                    assert!(runtime.ensure_thread_owner("required-root").await.is_err());
                }
                assert_eq!(
                    tokio::fs::read(workspace.join(files.artifacts()).join("keep")).await?,
                    b"delivery"
                );
                runtime.shutdown_runtime().await?;
            }
            Ok(())
        }

        async fn archive_receipt_scope(
            runtime: &StudioRuntime,
            scope: &ArchiveScope,
        ) -> Result<()> {
            match scope {
                ArchiveScope::Thread(id) => {
                    runtime
                        .archive_thread("receipt-retry".into(), id.clone())
                        .await?
                        .context("thread archive")?;
                }
                ArchiveScope::Workspace(id) => {
                    runtime
                        .archive_project(id)
                        .await?
                        .context("workspace archive")?;
                }
            }
            Ok(())
        }

        async fn reject_changed_saved_projection(
            runtime: &StudioRuntime,
            scope: &ArchiveScope,
        ) -> Result<()> {
            let tree = runtime.store.read_directory_tree("required-root").await?;
            let private_index = tree
                .iter()
                .position(|thread| thread.agent.thread_id == "required-private")
                .unwrap();
            let frozen = runtime.store.thread_archive(scope).await?.unwrap();
            assert_eq!(frozen.phase, ArchivePhase::Saved);
            let mut changed = tree.clone();
            let mut extra = tree[private_index].clone();
            extra.agent.thread_id = "unfrozen-member".into();
            changed.push(extra);
            let error = runtime
                .freeze_thread_archive(scope.clone(), &changed, &[])
                .await
                .unwrap_err();
            assert!(error.to_string().contains("gained a member"), "{error:#}");
            let mut new_admission = frozen.private_members[0].identity.clone();
            new_admission.thread_id = "unfrozen-preparation".into();
            assert!(
                runtime
                    .freeze_thread_archive(scope.clone(), &tree, &[new_admission])
                    .await
                    .is_err()
            );
            assert!(
                runtime
                    .store
                    .thread_preparation("unfrozen-preparation")
                    .await?
                    .is_none()
            );
            let without_public = tree
                .iter()
                .filter(|thread| thread.agent.thread_id != "required-root")
                .cloned()
                .collect::<Vec<_>>();
            assert!(
                runtime
                    .freeze_thread_archive(scope.clone(), &without_public, &[])
                    .await
                    .is_err()
            );
            for field in ["workspace", "root", "parent"] {
                let mut changed = tree.clone();
                match field {
                    "workspace" => {
                        changed[private_index].session.workspace_id = "different-workspace".into()
                    }
                    "root" => changed[private_index].root_thread_id = "different-root".into(),
                    "parent" => {
                        changed[private_index].parent_thread_id = Some("different-parent".into())
                    }
                    _ => unreachable!(),
                }
                let error = runtime
                    .freeze_thread_archive(scope.clone(), &changed, &[])
                    .await
                    .unwrap_err();
                assert!(
                    error.to_string().contains("changed identity"),
                    "{field}: {error:#}"
                );
            }
            // A filtered projection can lose P precisely because its canonical ownership changed.
            // Its absence must not be mistaken for a private identity that never had a catalog row.
            let catalog = runtime.store.catalog();
            let canonical_agent = catalog.get_agent("required-private").unwrap();
            let canonical_session = catalog.get_session(&canonical_agent.session_id).unwrap();
            let canonical_sessions = catalog.sessions();
            let canonical_agents = catalog.agents();
            let without_private = tree
                .iter()
                .filter(|thread| thread.agent.thread_id != "required-private")
                .cloned()
                .collect::<Vec<_>>();
            for field in ["workspace", "root", "parent"] {
                // 保持 read_thread 仍能定位该成员，仅替换身份事实，模拟另一份目录写入。
                match field {
                    "workspace" => {
                        let mut shifted = canonical_session.clone();
                        shifted.workspace_id = "different-workspace".into();
                        catalog.upsert_session(shifted).await?;
                    }
                    "root" => {
                        let mut shifted = canonical_session.clone();
                        shifted.session_id = "different-root".into();
                        catalog.upsert_session(shifted).await?;
                        let mut shifted_agent = canonical_agent.clone();
                        shifted_agent.session_id = "different-root".into();
                        catalog.upsert_agent(shifted_agent).await?;
                    }
                    "parent" => {
                        let mut shifted = canonical_agent.clone();
                        shifted.parent_agent_id = Some("different-parent".into());
                        catalog.upsert_agent(shifted).await?;
                    }
                    _ => unreachable!(),
                }
                let outcome = runtime
                    .freeze_thread_archive(scope.clone(), &without_private, &[])
                    .await;
                catalog
                    .test_restore_records(canonical_sessions.clone(), canonical_agents.clone())
                    .await?;
                let error = outcome.unwrap_err();
                let expected = match field {
                    "root" => "directory root identity mismatch",
                    "parent" => "directory parent Agent is missing",
                    _ => "changed identity",
                };
                assert!(error.to_string().contains(expected), "{field}: {error:#}");
            }
            // A validly encoded but conflicting frozen binding must not be repaired from a newer view.
            let mut conflicting = frozen.clone();
            let original = match &mut conflicting.private_members[0].binding {
                PreparationBinding::Bound { identity } => identity,
                PreparationBinding::Unbound => {
                    panic!("receipt fixture has a frozen physical binding")
                }
            };
            original.root.push_str("-different-binding");
            conflicting.changed()?;
            runtime.store.save_thread_archive(&conflicting).await?;
            let error = runtime
                .freeze_thread_archive(scope.clone(), &tree, &[])
                .await
                .unwrap_err();
            assert!(
                error.to_string().contains("physical binding changed"),
                "{error:#}"
            );
            let mut restored = frozen;
            restored.revision = conflicting.revision;
            restored.changed()?;
            runtime.store.save_thread_archive(&restored).await?;
            // A private identity does not owe catalog publication; its original responsibility remains.
            let without_private = tree
                .into_iter()
                .filter(|thread| thread.agent.thread_id != "required-private")
                .collect::<Vec<_>>();
            let projected = runtime
                .freeze_thread_archive(scope.clone(), &without_private, &[])
                .await?;
            assert_eq!(projected.members.len(), 1);
            assert_eq!(projected.private_members.len(), 1);
            Ok(())
        }

        #[tokio::test]
        async fn archive_private_catalog_projection_retries_saved_cleaned_and_published_ack()
        -> Result<()> {
            for workspace_archive in [false, true] {
                for restart in [false, true] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir_all(&workspace).await?;
                    let evidence = crash_original_private_owner(temp.path(), true).await?;
                    let original: ThreadPreparationRecord =
                        serde_json::from_value(evidence["record"].clone())?;
                    let mut runtime = StudioRuntime::initialize(options(&home)).await?;
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER reject_original_stop")
                        .await?;
                    let root = runtime.store.read_thread("required-root").await?.unwrap();
                    let scope = if workspace_archive {
                        ArchiveScope::Workspace(root.workspace_id.clone())
                    } else {
                        ArchiveScope::Thread(root.id.clone())
                    };
                    let files = pl_tool::workspace::SessionFiles::new("required-private");
                    let blocked_temp = workspace.join(files.temp());
                    tokio::fs::write(&blocked_temp, b"recoverable temp obstruction").await?;
                    let error = archive_receipt_scope(&runtime, &scope).await.unwrap_err();
                    let saved = runtime.store.thread_archive(&scope).await?.unwrap();
                    assert_eq!(
                        saved.phase,
                        ArchivePhase::Saved,
                        "must reach the real cleanup failure: {error:#}"
                    );
                    assert_eq!(saved.members.len(), 1);
                    assert_eq!(saved.private_members.len(), 1);
                    assert_eq!(saved.private_members[0].binding, original.binding);
                    assert_eq!(saved.private_members[0].save, PreparationSave::Confirmed);
                    assert!(saved.private_members[0].stopped && saved.private_members[0].retired);
                    assert_eq!(
                        runtime
                            .store
                            .read_thread("required-private")
                            .await?
                            .unwrap()
                            .visibility,
                        crate::studio::ThreadVisibility::Active
                    );
                    reject_changed_saved_projection(&runtime, &scope).await?;
                    if restart {
                        runtime.shutdown_runtime().await?;
                        drop(runtime);
                        runtime = StudioRuntime::initialize(options(&home)).await?;
                    }
                    tokio::fs::remove_file(&blocked_temp).await?;
                    runtime.store.database().execute_unprepared(
                "CREATE TRIGGER reject_cleanup_ack BEFORE UPDATE ON studio_objects
                 WHEN NEW.object_kind='threadArchive' AND json_extract(NEW.payload_json,'$.phase')='cleaned'
                 BEGIN SELECT RAISE(ABORT,'injected Cleaned ACK failure'); END",
            ).await?;
                    let error = archive_receipt_scope(&runtime, &scope).await.unwrap_err();
                    assert!(
                        format!("{error:#}").contains("injected Cleaned ACK failure"),
                        "{error:#}"
                    );
                    let cleaned_without_ack = runtime.store.thread_archive(&scope).await?.unwrap();
                    assert_eq!(cleaned_without_ack.phase, ArchivePhase::Saved);
                    assert!(
                        cleaned_without_ack.private_members[0].host_cleaned
                            && cleaned_without_ack.private_members[0].execution_cleaned
                    );
                    assert_eq!(
                        runtime
                            .store
                            .read_thread("required-private")
                            .await?
                            .unwrap()
                            .visibility,
                        crate::studio::ThreadVisibility::Active
                    );
                    if restart {
                        runtime.shutdown_runtime().await?;
                        drop(runtime);
                        runtime = StudioRuntime::initialize(options(&home)).await?;
                    }
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER reject_cleanup_ack")
                        .await?;
                    runtime.store.database().execute_unprepared(
                "CREATE TRIGGER reject_published_ack BEFORE UPDATE ON studio_objects
                 WHEN NEW.object_kind='threadArchive' AND json_extract(NEW.payload_json,'$.phase')='published'
                 BEGIN SELECT RAISE(ABORT,'injected Published ACK failure'); END",
            ).await?;
                    let error = archive_receipt_scope(&runtime, &scope).await.unwrap_err();
                    assert!(
                        format!("{error:#}").contains("injected Published ACK failure"),
                        "{error:#}"
                    );
                    assert_eq!(
                        runtime.store.thread_archive(&scope).await?.unwrap().phase,
                        ArchivePhase::Cleaned
                    );
                    assert_eq!(
                        runtime
                            .store
                            .read_thread("required-private")
                            .await?
                            .unwrap()
                            .visibility,
                        crate::studio::ThreadVisibility::Archived
                    );
                    if restart {
                        runtime.shutdown_runtime().await?;
                        drop(runtime);
                        runtime = StudioRuntime::initialize(options(&home)).await?;
                    }
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER reject_published_ack")
                        .await?;
                    archive_receipt_scope(&runtime, &scope).await?;
                    let published = runtime.store.thread_archive(&scope).await?.unwrap();
                    assert_eq!(published.phase, ArchivePhase::Published);
                    assert_eq!(published.members.len(), 1);
                    assert_eq!(published.private_members.len(), 1);
                    assert_eq!(published.private_members[0].binding, original.binding);
                    let preparation = runtime
                        .store
                        .thread_preparation("required-private")
                        .await?
                        .unwrap();
                    assert_eq!(
                        preparation.storage.as_ref().unwrap().incarnation,
                        original.storage.as_ref().unwrap().incarnation
                    );
                    assert_eq!(preparation.disposition, PreparationDisposition::TempCleaned);
                    assert!(!blocked_temp.exists());
                    for id in ["required-root", "required-private"] {
                        assert!(
                            !runtime
                                .store
                                .registered_session_paths(id)?
                                .temp_dir()
                                .exists(),
                            "{id} host temp must stay cleaned across ACK retries"
                        );
                        assert!(
                            runtime
                                .session_of(id)
                                .and_then(|session| session.observed_thread(id))
                                .is_none()
                        );
                    }
                    assert_eq!(
                        tokio::fs::read(workspace.join(files.artifacts()).join("keep")).await?,
                        b"delivery"
                    );
                    runtime.shutdown_runtime().await?;
                }
            }
            Ok(())
        }
    }

    mod deletion {
        //! Real lifecycle deletion, independent of UI/FRB and without external model requests.
        use super::*;
        use crate::studio::{
            agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
            runtime::conversation_reader::ConversationReader,
            storage_fault_test_support::{ThreadStorageSink, spawn_live_projection_for_thread},
            store::{
                directory::DirectoryDelta, thread_delete::DeletePhase,
                thread_preparation::PreparationIdentity,
            },
        };
        use pl_core::thread::{ThreadHandle, cold::ColdStoreHandle};
        use pl_tool::workspace::SessionFiles;
        use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

        #[tokio::test]
        async fn permanent_delete_preflight_failure_retries_without_repairing_history() -> Result<()>
        {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("preflight-root", &project.id, "root")
                .await?;
            let files = SessionFiles::new(&root.id);
            let path = workspace.join(files.root());
            if path.exists() {
                tokio::fs::remove_dir_all(&path).await?;
            }
            tokio::fs::create_dir_all(path.parent().unwrap()).await?;
            tokio::fs::write(&path, b"unexpected file").await?;
            let error = runtime
                .delete_thread("preflight-fail".into(), root.id.clone())
                .await
                .expect_err("wrong target kind must be preserved");
            let public = crate::error_mapping::studio_error_from_anyhow_ref(&error);
            assert!(public.message.contains("删除执行端目录"), "{public}");
            let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
            assert!(
                operation
                    .members
                    .iter()
                    .find(|member| member.identity.thread_id == root.id)
                    .unwrap()
                    .host_deleted,
                "an independent host directory must finish after execution preflight fails"
            );
            assert!(
                !operation
                    .members
                    .iter()
                    .find(|member| member.identity.thread_id == root.id)
                    .unwrap()
                    .execution_removal_started
            );
            assert_eq!(tokio::fs::read(&path).await?, b"unexpected file");
            tokio::fs::remove_file(&path).await?;
            tokio::fs::create_dir(&path).await?;
            tokio::fs::write(path.join("retry"), b"disposable").await?;
            runtime
                .delete_thread("preflight-retry".into(), root.id.clone())
                .await?
                .context("retry must complete")?;
            assert!(!path.exists());
            assert!(runtime.store.read_thread(&root.id).await?.is_none());
            runtime.shutdown_runtime().await?;
            Ok(())
        }

        #[tokio::test]
        async fn permanent_delete_takes_pending_project_archive_atomically_and_preserves_neighbor()
        -> Result<()> {
            use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope};
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("transfer-root", &project.id, "root")
                .await?;
            let neighbor = runtime
                .create_thread_with_id("transfer-neighbor", &project.id, "neighbor")
                .await?;
            let source_scope = ArchiveScope::Workspace(project.id.clone());
            runtime
                .store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER reject_project_cleanup BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadArchive'
         AND json_extract(NEW.payload_json,'$.scope.kind')='workspace'
         AND json_extract(NEW.payload_json,'$.phase')='cleaned'
         BEGIN SELECT RAISE(ABORT,'project cleanup ACK failure'); END",
                )
                .await?;
            let error = runtime
                .archive_project(&project.id)
                .await
                .expect_err("project archive must leave its original cleanup responsibility");
            assert!(
                format!("{error:#}").contains("project cleanup ACK failure"),
                "{error:#}"
            );
            let source = runtime.store.thread_archive(&source_scope).await?;
            let source = source.context("pending project archive")?;
            assert_eq!(source.phase, ArchivePhase::Saved);
            assert!(
                source
                    .members
                    .iter()
                    .all(|member| member.host_cleaned && member.execution_cleaned)
            );
            let original_neighbor = source
                .members
                .iter()
                .find(|member| member.thread_id == neighbor.id)
                .context("neighbor cleanup responsibility")?;
            runtime
                .store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER reject_delete_transfer BEFORE INSERT ON studio_objects
         WHEN NEW.object_kind='threadDelete' BEGIN SELECT RAISE(ABORT,'transfer rollback'); END",
                )
                .await?;
            assert!(
                runtime
                    .delete_thread("transfer-fail".into(), root.id.clone())
                    .await
                    .is_err()
            );
            let unchanged = runtime.store.thread_archive(&source_scope).await?.unwrap();
            assert_eq!(unchanged.revision, source.revision);
            assert_eq!(unchanged.thread_ids(), source.thread_ids());
            assert!(
                runtime
                    .store
                    .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                    .await?
                    .is_none()
            );
            assert!(runtime.store.thread_delete(&root.id).await?.is_none());
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_delete_transfer")
                .await?;
            runtime
                .delete_thread("transfer-success".into(), root.id.clone())
                .await?
                .context("delete without finishing preservation")?;
            let remaining = runtime.store.thread_archive(&source_scope).await?.unwrap();
            assert_eq!(remaining.phase, ArchivePhase::Saved);
            assert_eq!(remaining.thread_ids(), vec![neighbor.id.clone()]);
            assert_eq!(
                serde_json::to_value(&remaining.members[0])?,
                serde_json::to_value(original_neighbor)?,
                "the neighbor's original binding and completed cleanup must survive unchanged"
            );
            assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
            assert!(runtime.store.read_thread(&root.id).await?.is_none());
            runtime.shutdown_runtime().await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let resumed = runtime.store.thread_archive(&source_scope).await?.unwrap();
            assert_eq!(resumed.phase, ArchivePhase::Saved);
            assert_eq!(resumed.thread_ids(), vec![neighbor.id.clone()]);
            assert_eq!(
                serde_json::to_value(&resumed.members[0])?,
                serde_json::to_value(original_neighbor)?
            );
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_project_cleanup")
                .await?;
            runtime
                .archive_project(&project.id)
                .await?
                .context("remaining project archive can continue")?;
            runtime.shutdown_runtime().await?;
            Ok(())
        }

        #[tokio::test]
        async fn permanent_delete_resumes_removing_with_a_previously_published_project_archive()
        -> Result<()> {
            use crate::studio::store::thread_archive::ArchiveScope;
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("resume-root", &project.id, "root")
                .await?;
            let neighbor = runtime
                .create_thread_with_id("resume-neighbor", &project.id, "neighbor")
                .await?;
            runtime
                .archive_project(&project.id)
                .await?
                .context("archive project")?;
            let scope = ArchiveScope::Workspace(project.id.clone());
            let mut original = runtime.store.thread_archive(&scope).await?.unwrap();
            runtime
                .store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER pause_before_removing BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'pause before removing'); END",
                )
                .await?;
            let error = runtime
                .delete_thread("resume-pause".into(), root.id.clone())
                .await
                .expect_err("pause after producers released");
            assert!(
                format!("{error:#}").contains("pause before removing"),
                "{error:#}"
            );
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER pause_before_removing")
                .await?;
            // Prior producers could persist Removing while the published project still
            // retained its members. Recreate that durable cut using the original record.
            let mut deletion = runtime.store.thread_delete(&root.id).await?.unwrap();
            deletion.phase = DeletePhase::Removing;
            deletion.changed()?;
            runtime.store.save_thread_delete(&deletion).await?;
            original.revision = runtime
                .store
                .thread_archive(&scope)
                .await?
                .unwrap()
                .revision
                + 1;
            runtime.store.save_thread_archive(&original).await?;
            runtime.shutdown_runtime().await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            runtime
                .delete_thread("resume-complete".into(), root.id.clone())
                .await?
                .context("resumed deletion")?;
            assert_eq!(
                runtime
                    .store
                    .thread_archive(&scope)
                    .await?
                    .unwrap()
                    .thread_ids(),
                vec![neighbor.id.clone()]
            );
            assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
            assert!(runtime.store.read_thread(&root.id).await?.is_none());
            runtime.shutdown_runtime().await?;
            Ok(())
        }

        #[tokio::test]
        async fn permanent_delete_releases_live_failed_save_and_failed_terminal_without_repair()
        -> Result<()> {
            use crate::thread_assembler::{
                agent_review::ReviewDeliverySource,
                review_dispatch::{TerminalAuthority, TerminalDelivery, TerminalMaterialRetention},
            };
            use pl_core::{context::OpaquePayload, thread::extensions::ExtensionMutation};
            use std::sync::{Arc, atomic::AtomicU64};
            use tokio_util::sync::CancellationToken;

            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("delete-live-fault", &project.id, "root")
                .await?;
            let owner = runtime.ensure_thread_owner(&root.id).await?;
            owner.flush().await?;
            runtime.synchronize_thread_observation(&root.id).await?;
            let child = cold_child(&runtime, &root.clone().into(), "delete-cold-child").await?;
            let producer_released = CancellationToken::new();
            let released = producer_released.clone();
            runtime
                .require_session(&child.id)?
                .start_terminal_delivery(Arc::new(TerminalDelivery {
                    thread: child.clone(),
                    sequence: 1,
                    authority: Arc::new(TerminalAuthority::capture(&owner.snapshot())?),
                    original: None,
                    source: ReviewDeliverySource::Reconciliation,
                    revocation: Arc::new(AtomicU64::new(0)),
                    channel: None,
                    wake: false,
                    _material: Some(Arc::new(TerminalMaterialRetention::new(move || {
                        released.cancel()
                    }))),
                }))
                .await?;
            let failure = tokio::time::timeout(
                std::time::Duration::from_secs(10),
                runtime
                    .require_session(&child.id)?
                    .join_review_delivery(&child.id),
            )
            .await?
            .expect_err("missing original must block the actual terminal producer");
            ensure!(
                format!("{failure:#}").contains("original terminal message is missing"),
                "{failure:#}"
            );
            assert!(
                !producer_released.is_cancelled(),
                "failed producer must remain retained before deletion"
            );

            let host = runtime.store.session_paths(&project.id, &root.id)?;
            let db = sea_orm::Database::connect(
                crate::studio::paths::sqlite_file_options(
                    &host.history_database(),
                    crate::studio::paths::SqliteFileMode::ReadWrite,
                    |options| options,
                )
                .await?,
            )
            .await?;
            db.execute_unprepared("CREATE TRIGGER reject_delete_save BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'permanent deletion must not repair this save'); END").await?;
            owner
                .mutate_extensions(vec![ExtensionMutation::Put {
                    id: "delete-fault".into(),
                    expected_revision: None,
                    payload: OpaquePayload::text("unsaved content"),
                }])
                .await?;
            let save_error =
                tokio::time::timeout(std::time::Duration::from_secs(10), owner.flush())
                    .await?
                    .expect_err("the live writer must expose its real save failure");
            ensure!(
                format!("{save_error:#}").contains("permanent deletion must not repair"),
                "{save_error:#}"
            );
            db.close().await?;
            let channel = runtime.store.thread_persistence().history_channel(&root.id);
            let durable = channel.subscribe().borrow().committed_sequence;
            let unsaved_sequence = owner.snapshot().commit_sequence;
            assert!(durable < unsaved_sequence);
            assert!(runtime.thread_observations.live_feed(&root.id).is_some());
            let history = runtime.store.history(&root.id).await?;

            tokio::time::timeout(
                std::time::Duration::from_secs(15),
                runtime.delete_thread("delete-live-fault".into(), root.id.clone()),
            )
            .await??
            .context("deletion reply")?;
            assert!(
                producer_released.is_cancelled(),
                "the failed producer's retained task must actually exit"
            );
            assert!(channel.deletion_joined(), "writer must actually join");
            assert_eq!(
                channel.subscribe().borrow().committed_sequence,
                durable,
                "deletion must not invent a save ACK"
            );
            assert_eq!(
                owner.snapshot().commit_sequence,
                unsaved_sequence,
                "deletion adds no preservation facts"
            );
            assert_eq!(
                owner.snapshot().lifecycle,
                pl_core::thread::ThreadLifecycle::Closed
            );
            assert!(
                runtime
                    .session_of(&root.id)
                    .and_then(|session| session.observed_thread(&root.id))
                    .is_none()
            );
            assert!(runtime.thread_observations.live_feed(&root.id).is_none());
            assert!(
                runtime
                    .store
                    .thread_persistence()
                    .shared_history(&root.id)
                    .is_none()
            );
            assert!(!host.root().exists());
            let closed = history
                .parent_report(1)
                .await
                .expect_err("the original pool must reject reads after deletion");
            ensure!(
                format!("{closed:#}").contains("permanently closed"),
                "{closed:#}"
            );
            runtime.shutdown_runtime().await?;
            Ok(())
        }

        async fn cold_child(
            runtime: &StudioRuntime,
            parent: &pl_protocol::Thread,
            id: &str,
        ) -> Result<pl_protocol::Thread> {
            let mut child = pl_protocol::Thread::placeholder(id);
            child.agent_path = format!("{}/{}", parent.agent_path, child.id);
            child.workspace_id = parent.workspace_id.clone();
            child.workspace_path = parent.workspace_path.clone();
            child.root_thread_id = parent.root_thread_id.clone();
            child.parent_thread_id = Some(parent.id.clone());
            let (_, agent) = crate::studio::records::directory_facts_from_thread(&child);
            runtime
                .agent_facility
                .product_events
                .commit_directory(DirectoryDelta {
                    agent_upserts: vec![agent],
                    ..Default::default()
                })
                .await?;
            let sink = ThreadStorageSink::new(runtime.store.clone(), child.clone(), None).await?;
            let projection = spawn_live_projection_for_thread(runtime.store.clone(), &child.id);
            let owner = ThreadHandle::resume_without_model(child.id.clone(), None)?;
            owner.attach_storage(ColdStoreHandle::new(sink)).await?;
            owner.close().await?;
            runtime
                .store
                .thread_persistence()
                .history_channel(&child.id)
                .stop_and_join()
                .await?;
            projection.await?;
            // S1 archive belongs to the Session, not independently to a child. The caller exercises
            // both active and archived Session trees while this child stays cold in either case.
            Ok(child)
        }

        #[tokio::test]
        async fn permanent_delete_cold_missing_or_unreadable_history_skips_storage_and_temp_cleanup()
        -> Result<()> {
            for unreadable_history in [false, true] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let (delta, session, agent) = DirectoryDelta::register_session(
                    "delete-cold".into(),
                    &project.id,
                    "cold",
                    pl_protocol::ThreadModeId::simple(),
                    pl_protocol::ThreadWorkspaceMode::Local,
                    dunce::canonicalize(&workspace)?
                        .to_string_lossy()
                        .into_owned(),
                    crate::config::ROOT_AGENT_ROUTE_KEY,
                );
                runtime
                    .agent_facility
                    .product_events
                    .commit_directory(delta)
                    .await?;
                let root = crate::studio::ThreadRecord::from_directory_thread(
                    crate::studio::records::thread_projection(&session, &agent, |id| {
                        runtime
                            .store
                            .catalog()
                            .get_agent(id)
                            .map(|agent| agent.thread_id)
                    })?,
                );
                let neighbor = runtime
                    .create_thread_with_id("keep-cold", &project.id, "neighbor")
                    .await?;
                let host = runtime.store.session_paths(&project.id, &root.id)?;
                runtime
                    .store
                    .begin_removal_preparation(
                        PreparationIdentity {
                            thread_id: root.id.clone(),
                            workspace_id: project.id.clone(),
                            parent_id: None,
                            root_id: root.id.clone(),
                        },
                        true,
                    )
                    .await?;
                assert!(
                    runtime
                        .session_of(&root.id)
                        .and_then(|session| session.observed_thread(&root.id))
                        .is_none()
                );
                assert!(!host.history_database().exists());
                if unreadable_history {
                    tokio::fs::create_dir_all(host.root()).await?;
                    tokio::fs::write(host.history_database(), b"not a SQLite database").await?;
                }
                let files = SessionFiles::new(&root.id);
                tokio::fs::create_dir_all(workspace.join(files.root())).await?;
                // A stale temp file must not need to satisfy archive temp-directory validation:
                // permanent deletion removes the dedicated session root in one operation.
                tokio::fs::write(workspace.join(files.temp()), b"disposable temp file").await?;
                runtime.store.database().execute_unprepared(
            "CREATE TRIGGER pause_cold_delete BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'pause before physical deletion'); END"
        ).await?;
                let error = runtime
                    .delete_thread("pause-cold".into(), root.id.clone())
                    .await
                    .expect_err("the phase commit must reach the injected barrier");
                assert!(
                    format!("{error:#}").contains("pause before physical deletion"),
                    "{error:#}"
                );
                assert!(
                    runtime
                        .store
                        .thread_persistence()
                        .shared_history(&root.id)
                        .is_none(),
                    "cold deletion must not open a history pool"
                );
                assert_eq!(
                    tokio::fs::read(workspace.join(files.temp())).await?,
                    b"disposable temp file"
                );
                if unreadable_history {
                    assert_eq!(
                        tokio::fs::read(host.history_database()).await?,
                        b"not a SQLite database"
                    );
                } else {
                    assert!(!host.history_database().exists());
                }
                runtime
                    .store
                    .database()
                    .execute_unprepared("DROP TRIGGER pause_cold_delete")
                    .await?;
                runtime
                    .delete_thread("finish-cold".into(), root.id.clone())
                    .await?
                    .context("cold deletion reply")?;
                assert!(!host.root().exists());
                assert!(!workspace.join(files.root()).exists());
                assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                assert!(
                    runtime
                        .delete_thread("repeat-cold".into(), root.id.clone())
                        .await?
                        .is_none()
                );
                runtime.shutdown_runtime().await?;
            }
            Ok(())
        }

        #[tokio::test]
        async fn permanent_delete_removes_active_or_archived_tree_private_files_and_revokes_readers()
        -> Result<()> {
            for archived in [false, true] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let root = runtime
                    .create_thread_with_id("delete-root", &project.id, "root")
                    .await?;
                let neighbor = runtime
                    .create_thread_with_id("delete-neighbor", &project.id, "neighbor")
                    .await?;
                runtime.ensure_thread_owner(&root.id).await?.flush().await?;
                runtime
                    .ensure_thread_owner(&neighbor.id)
                    .await?
                    .flush()
                    .await?;
                let child = cold_child(&runtime, &root.clone().into(), "delete-cold-child").await?;
                let grandchild = cold_child(&runtime, &child, "delete-cold-grandchild").await?;
                for (agent, parent) in [
                    (&child.id, &root.id),
                    (&grandchild.id, &child.id),
                    (&neighbor.id, &neighbor.id),
                ] {
                    runtime.store.database().execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                "INSERT INTO agent_evaluations
                 (agent_id,parent_agent_id,account_id,model_id,profile_id,mode,preference,turn_id,
                  revision,task_category,outcome,comment,created_at,updated_at)
                 VALUES (?,?,'fixture','model','profile','profile','balanced','final',1,'coding','notRated','original evaluation',1,1)",
                [agent.clone().into(), parent.clone().into()])).await?;
                }
                let config = runtime.config_runtime.read()?;
                runtime.config_runtime.update(config.revision, |desired| {
                    let mut next = desired.clone();
                    next.ui.pinned_thread_ids = vec![root.id.clone(), neighbor.id.clone()];
                    Ok(next)
                })?;
                let private = PreparationIdentity {
                    thread_id: "delete-unpublished".into(),
                    workspace_id: project.id.clone(),
                    parent_id: Some(root.id.clone()),
                    root_id: root.id.clone(),
                };
                runtime
                    .store
                    .begin_thread_preparation(private.clone())
                    .await?;
                let binding = WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    dunce::canonicalize(&workspace)?
                        .to_string_lossy()
                        .into_owned(),
                )?;
                runtime
                    .store
                    .bind_thread_preparation(&private.thread_id, &binding)
                    .await?;
                runtime
                    .store
                    .confirm_preparation_stop(&private.thread_id)
                    .await?;
                runtime
                    .store
                    .set_preparation_disposition(
                        &private.thread_id,
                        crate::studio::store::thread_preparation::PreparationDisposition::Remove,
                    )
                    .await?;
                runtime
                    .store
                    .confirm_preparation_retirement(&private.thread_id)
                    .await?;
                let ids = [&root.id, &child.id, &grandchild.id, &private.thread_id];
                for id in ids {
                    let host = runtime.store.session_paths(&project.id, id)?;
                    for name in ["notes", "plan", "reports", "resources", "attachments"] {
                        tokio::fs::create_dir_all(host.root().join(name)).await?;
                        tokio::fs::write(
                            host.root().join(name).join("private"),
                            b"delete this body",
                        )
                        .await?;
                    }
                    let files = SessionFiles::new(id);
                    for path in [files.temp(), files.artifacts()] {
                        tokio::fs::create_dir_all(workspace.join(&path)).await?;
                        tokio::fs::write(
                            workspace.join(path).join("private"),
                            b"delete execution data",
                        )
                        .await?;
                    }
                }
                let neighbor_files = SessionFiles::new(&neighbor.id);
                tokio::fs::write(
                    workspace.join(neighbor_files.artifacts()).join("keep"),
                    b"neighbor artifact",
                )
                .await?;
                tokio::fs::write(workspace.join("business"), b"ordinary project content").await?;
                if archived {
                    runtime
                        .archive_thread("archive-delete".into(), root.id.clone())
                        .await?
                        .context("archive reply")?;
                }
                let feed = runtime
                    .open_conversation_feed(
                        &root.id,
                        pl_protocol::ChatScope::conversation(None),
                        pl_protocol::ReadDemand {
                            max_items: 16,
                            max_bytes: 65536,
                        },
                    )
                    .await?;
                let reader: ConversationReader = feed.reader().clone();
                let old_history = runtime.store.history(&root.id).await?;
                let root_host = runtime.store.session_paths(&project.id, &root.id)?;
                let child_host = runtime.store.session_paths(&project.id, &child.id)?;
                let grandchild_host = runtime.store.session_paths(&project.id, &grandchild.id)?;
                let private_host = runtime
                    .store
                    .session_paths(&project.id, &private.thread_id)?;
                assert!(
                    runtime
                        .delete_thread("reject-child".into(), child.id.clone())
                        .await
                        .is_err()
                );
                let started = std::time::Instant::now();
                let result = runtime
                    .delete_thread("permanent-delete".into(), root.id.clone())
                    .await?
                    .context("delete reply")?;
                println!(
                    "PERMANENT_DELETE_TREE members=4 depth=3 archived={archived} elapsed_us={}",
                    started.elapsed().as_micros()
                );
                assert_eq!(result.result.deleted_thread_ids.len(), ids.len());
                for id in ids {
                    assert!(result.result.deleted_thread_ids.contains(id));
                }
                assert_eq!(
                    result
                        .result
                        .next_root
                        .as_ref()
                        .map(|root| root.thread_id.as_str()),
                    Some(neighbor.id.as_str())
                );
                assert!(
                    reader.ensure().is_err(),
                    "an old reader must lose its read qualification"
                );
                assert!(
                    old_history.conversation_database_id().await.is_err(),
                    "the original pools must close"
                );
                for host in [root_host, child_host, grandchild_host, private_host] {
                    assert!(!host.root().exists());
                }
                for id in ids {
                    assert!(runtime.store.read_thread(id).await?.is_none());
                    assert!(!workspace.join(SessionFiles::new(id).root()).exists());
                    assert!(runtime.store.thread_preparation(id).await?.is_none());
                    let owned = runtime.store.database().query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                "SELECT 1 FROM studio_objects WHERE owner_id=? AND owner_kind IN ('thread','agent')",
                [id.clone().into()])).await?;
                    assert!(owned.is_none(), "private/lease/close records must be gone");
                }
                for id in [&child.id, &grandchild.id] {
                    assert!(runtime.store.read_agent_evaluation(id).await?.is_none());
                }
                assert!(
                    runtime
                        .store
                        .database()
                        .query_one_raw(Statement::from_sql_and_values(
                            DatabaseBackend::Sqlite,
                            "SELECT 1 FROM agent_evaluations WHERE agent_id=?",
                            [neighbor.id.clone().into()]
                        ))
                        .await?
                        .is_some()
                );
                assert_eq!(
                    runtime.config_runtime.read()?.config.ui.pinned_thread_ids,
                    vec![neighbor.id.clone()]
                );
                let (session, agent) = crate::studio::records::directory_facts_from_thread(
                    &pl_protocol::Thread::from(root.clone()),
                );
                let mut delayed =
                    crate::studio::records::row_projection(&session.expect("root session"), &agent);
                delayed.title = "late metadata must not restore deletion".into();
                runtime
                    .agent_facility
                    .product_events
                    .apply_thread_delta(vec![delayed], vec![])
                    .await?;
                assert!(
                    runtime
                        .agent_facility
                        .product_events
                        .thread_snapshot(&root.id)?
                        .is_none()
                );
                assert_eq!(
                    tokio::fs::read(workspace.join("business")).await?,
                    b"ordinary project content"
                );
                assert_eq!(
                    tokio::fs::read(workspace.join(neighbor_files.artifacts()).join("keep"))
                        .await?,
                    b"neighbor artifact"
                );
                assert!(
                    runtime
                        .store
                        .history(&neighbor.id)
                        .await?
                        .conversation_database_id()
                        .await?
                        .is_some()
                );
                assert!(
                    runtime
                        .create_thread_with_id(&root.id, &project.id, "cannot recreate")
                        .await
                        .is_err()
                );
                assert!(runtime.restore_thread(root.id.clone()).await.is_err());
                assert!(
                    runtime
                        .delete_thread("duplicate-delete".into(), root.id.clone())
                        .await?
                        .is_none()
                );
                let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
                assert_eq!(operation.phase, DeletePhase::Published);
                assert!(operation.members.is_empty());
                runtime.shutdown_runtime().await?;
                let restarted = StudioRuntime::initialize(options(&home)).await?;
                assert!(restarted.store.read_thread(&root.id).await?.is_none());
                assert!(restarted.store.read_thread(&neighbor.id).await?.is_some());
                assert!(
                    restarted
                        .create_thread_with_id(&root.id, &project.id, "cannot restart")
                        .await
                        .is_err()
                );
                restarted.shutdown_runtime().await?;
            }
            Ok(())
        }

        #[cfg(unix)]
        #[tokio::test]
        async fn permanent_delete_failure_is_durable_retries_original_binding_and_preserves_neighbor()
        -> Result<()> {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("retry-delete", &project.id, "root")
                .await?;
            let neighbor = runtime
                .create_thread_with_id("retry-neighbor", &project.id, "neighbor")
                .await?;
            runtime.ensure_thread_owner(&root.id).await?.flush().await?;
            runtime
                .ensure_thread_owner(&neighbor.id)
                .await?
                .flush()
                .await?;
            let files = SessionFiles::new(&root.id);
            let outside = temp.path().join("outside");
            tokio::fs::create_dir(&outside).await?;
            tokio::fs::write(outside.join("keep"), b"outside").await?;
            runtime.store.database().execute_unprepared(
        "CREATE TRIGGER reject_deleted_phase BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='dataDeleted'
         BEGIN SELECT RAISE(ABORT,'injected deletion commit failure'); END"
    ).await?;
            assert!(
                runtime
                    .delete_thread("fail-delete".into(), root.id.clone())
                    .await
                    .is_err()
            );
            assert_eq!(
                runtime.store.thread_delete(&root.id).await?.unwrap().phase,
                DeletePhase::Removing
            );
            assert!(runtime.store.history(&root.id).await.is_err());
            assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_deleted_phase")
                .await?;
            runtime.shutdown_runtime().await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            // Retrying a durable host-deleted member must not re-delete a same-path replacement.
            let host = runtime.store.session_paths(&project.id, &root.id)?;
            tokio::fs::create_dir_all(host.root()).await?;
            tokio::fs::write(host.root().join("replacement"), b"preserve replacement").await?;
            let result = runtime
                .delete_thread("retry-delete".into(), root.id.clone())
                .await?
                .context("retry reply")?;
            assert_eq!(result.result.deleted_root_id, root.id);
            assert_eq!(
                tokio::fs::read(host.root().join("replacement")).await?,
                b"preserve replacement"
            );
            assert!(!workspace.join(files.root()).exists());
            assert_eq!(tokio::fs::read(outside.join("keep")).await?, b"outside");
            assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
            runtime.shutdown_runtime().await?;
            Ok(())
        }

        #[tokio::test]
        async fn permanent_delete_effect_before_ack_preserves_host_and_execution_replacements()
        -> Result<()> {
            for host_target in [false, true] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let root = runtime
                    .create_thread_with_id("unknown-delete", &project.id, "root")
                    .await?;
                let neighbor = runtime
                    .create_thread_with_id("unknown-neighbor", &project.id, "neighbor")
                    .await?;
                runtime.ensure_thread_owner(&root.id).await?.flush().await?;
                runtime
                    .ensure_thread_owner(&neighbor.id)
                    .await?
                    .flush()
                    .await?;
                let host = runtime.store.session_paths(&project.id, &root.id)?;
                let target = if host_target {
                    host.root().to_owned()
                } else {
                    workspace.join(SessionFiles::new(&root.id).root())
                };
                let field = if host_target {
                    "hostDeleted"
                } else {
                    "executionDeleted"
                };
                let started = if host_target {
                    "hostRemovalStarted"
                } else {
                    "executionRemovalStarted"
                };
                runtime
                    .store
                    .database()
                    .execute_unprepared(&format!(
                "CREATE TRIGGER reject_session_removal_start BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete'
              AND json_extract(NEW.payload_json,'$.phase')='removing'
              AND json_extract(NEW.payload_json,'$.members[0].{started}')=1
             BEGIN SELECT RAISE(ABORT,'injected started fence failure'); END"
            ))
                    .await?;
                assert!(
                    runtime
                        .delete_thread("unknown-start-failure".into(), root.id.clone())
                        .await
                        .is_err()
                );
                assert!(
                    target.is_dir(),
                    "removal cannot outrun its durable started fence"
                );
                runtime
                    .store
                    .database()
                    .execute_unprepared("DROP TRIGGER reject_session_removal_start")
                    .await?;
                runtime
                    .store
                    .database()
                    .execute_unprepared(&format!(
                        "CREATE TRIGGER reject_session_removal_ack BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete'
              AND json_extract(NEW.payload_json,'$.phase')='removing'
              AND json_extract(NEW.payload_json,'$.members[0].{field}')=1
             BEGIN SELECT RAISE(ABORT,'injected effect-before-ACK failure'); END"
                    ))
                    .await?;
                assert!(
                    runtime
                        .delete_thread("unknown-first".into(), root.id.clone())
                        .await
                        .is_err()
                );
                assert!(
                    !target.exists(),
                    "physical removal must precede the injected ACK failure"
                );
                let pending = runtime
                    .store
                    .thread_delete(&root.id)
                    .await?
                    .context("retained removal")?;
                let member = &pending.members[0];
                assert!(if host_target {
                    member.host_removal_started && !member.host_deleted
                } else {
                    member.execution_removal_started && !member.execution_deleted
                });
                let mut old_payload = serde_json::to_value(&pending)?;
                let old_member = old_payload["members"][0].as_object_mut().unwrap();
                old_member.remove("hostRemovalStarted");
                old_member.remove("executionRemovalStarted");
                let old: crate::studio::store::thread_delete::ThreadDeleteOperation =
                    serde_json::from_value(old_payload)?;
                assert!(
                    old.members[0].host_removal_started && old.members[0].execution_removal_started,
                    "old Removing records cannot prove the physical effect was unstarted"
                );
                runtime
                    .store
                    .database()
                    .execute_unprepared("DROP TRIGGER reject_session_removal_ack")
                    .await?;
                runtime.shutdown_runtime().await?;
                tokio::fs::create_dir_all(&target).await?;
                tokio::fs::write(target.join("replacement"), b"preserve unknown replacement")
                    .await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                assert!(
                    runtime
                        .delete_thread("unknown-retry".into(), root.id.clone())
                        .await
                        .is_err(),
                    "an unacknowledged removal must never delete a same-path replacement"
                );
                assert_eq!(
                    tokio::fs::read(target.join("replacement")).await?,
                    b"preserve unknown replacement"
                );
                assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                // Only this fixture owns the replacement. Once it is absent, retry may reconcile the
                // original removal without issuing another destructive call against an existing object.
                tokio::fs::remove_dir_all(&target).await?;
                runtime
                    .delete_thread("unknown-absent".into(), root.id.clone())
                    .await?
                    .context("absence reconciliation")?;
                assert!(!host.root().exists());
                assert!(!workspace.join(SessionFiles::new(&root.id).root()).exists());
                assert!(
                    runtime
                        .store
                        .history(&neighbor.id)
                        .await?
                        .conversation_database_id()
                        .await?
                        .is_some()
                );
                runtime.shutdown_runtime().await?;
            }
            Ok(())
        }

        async fn git_fixture(root: &Path, args: &[&str]) -> Result<String> {
            let output = tokio::process::Command::new("git")
                .args(args)
                .current_dir(root)
                .output()
                .await?;
            ensure!(
                output.status.success(),
                "Git fixture {args:?}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            Ok(String::from_utf8(output.stdout)?)
        }

        #[tokio::test]
        async fn archive_owned_worktrees_wait_for_borrowers_and_git_locks_discard_content_and_preserve_refs()
        -> Result<()> {
            use crate::{
                agent::worktree::{
                    ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
                },
                studio::{
                    agent_host::worktree_lease::{
                        WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
                    },
                    store::thread_archive::{ArchivePhase, ArchiveScope},
                },
            };
            for root_owned in [true, false] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let repository = temp.path().join("repository");
                tokio::fs::create_dir(&repository).await?;
                git_fixture(&repository, &["init", "--quiet"]).await?;
                git_fixture(
                    &repository,
                    &[
                        "-c",
                        "user.name=fixture",
                        "-c",
                        "user.email=fixture@example.invalid",
                        "commit",
                        "--quiet",
                        "--allow-empty",
                        "-m",
                        "fixture",
                    ],
                )
                .await?;
                let repository = dunce::canonicalize(repository)?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&repository).await?;
                let manager = WorktreeManager::new(
                    repository.clone(),
                    std::sync::Arc::new(ExecutorWorktreeBackend::new(
                        pl_remote_helper::Executor::local()?,
                    )),
                );
                let head = manager.resolve_head(&repository).await?;
                let owner_id = if root_owned {
                    "owned-root"
                } else {
                    "owned-private-child"
                };
                let ownership = if root_owned {
                    WorktreeOwnership::Session {
                        thread_id: "owned-root".into(),
                    }
                } else {
                    WorktreeOwnership::Child {
                        child_id: owner_id.into(),
                    }
                };
                let handle = manager
                    .create(WorktreeCreateSpec {
                        repo_root: repository.clone(),
                        root_thread_id: "owned-root".into(),
                        ownership,
                        base_commit: head.clone(),
                    })
                    .await
                    .map_err(|error| anyhow::anyhow!("{error:?}"))?;
                let identity = WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    handle.path.to_string_lossy().into_owned(),
                )?;
                let mut lease = WorktreeLease {
                    revision: 1,
                    state: WorktreeLeaseState::Prepared,
                    owner_kind: if root_owned {
                        WorktreeLeaseOwnerKind::Session
                    } else {
                        WorktreeLeaseOwnerKind::Child
                    },
                    owner_thread_id: owner_id.into(),
                    root_thread_id: "owned-root".into(),
                    workspace_id: project.id.clone(),
                    ssh_alias: None,
                    repository_root: repository.to_string_lossy().into_owned(),
                    path: identity.root.clone(),
                    base_commit: head,
                };
                runtime
                    .store
                    .bind_workspace_identity(owner_id, &identity)
                    .await?;
                runtime
                    .agent_facility
                    .worktrees
                    .record_durable(lease.clone())
                    .await?;
                lease.transition(WorktreeLeaseState::Active);
                runtime
                    .agent_facility
                    .worktrees
                    .record_durable(lease)
                    .await?;
                let root = if root_owned {
                    let (delta, session, agent) = DirectoryDelta::register_session(
                        "owned-root".into(),
                        &project.id,
                        "owned",
                        pl_protocol::ThreadModeId::simple(),
                        pl_protocol::ThreadWorkspaceMode::Worktree,
                        identity.root.clone(),
                        crate::config::ROOT_AGENT_ROUTE_KEY,
                    );
                    runtime
                        .agent_facility
                        .product_events
                        .commit_directory(delta)
                        .await?;
                    let root = crate::studio::ThreadRecord::from_directory_thread(
                        crate::studio::records::thread_projection(&session, &agent, |id| {
                            runtime
                                .store
                                .catalog()
                                .get_agent(id)
                                .map(|agent| agent.thread_id)
                        })?,
                    );
                    runtime.register_new_thread(root.clone()).await?;
                    root
                } else {
                    let root = runtime
                        .create_thread_with_id("owned-root", &project.id, "local root")
                        .await?;
                    let preparation = PreparationIdentity {
                        thread_id: owner_id.into(),
                        workspace_id: project.id.clone(),
                        parent_id: Some(root.id.clone()),
                        root_id: root.id.clone(),
                    };
                    runtime.store.begin_thread_preparation(preparation).await?;
                    runtime
                        .store
                        .bind_thread_preparation(owner_id, &identity)
                        .await?;
                    runtime.store.confirm_preparation_stop(owner_id).await?;
                    runtime
                        .store
                        .confirm_preparation_retirement(owner_id)
                        .await?;
                    root
                };
                runtime.ensure_thread_owner(&root.id).await?.flush().await?;
                let reliable = runtime
                    .store
                    .registered_session_paths(&root.id)?
                    .history_database();
                tokio::fs::write(handle.path.join(".gitignore"), b"ignored\n").await?;
                tokio::fs::write(handle.path.join("dirty"), b"untracked content").await?;
                tokio::fs::write(handle.path.join("ignored"), b"ignored content").await?;
                let refs = git_fixture(
                    &repository,
                    &["for-each-ref", "--format=%(refname):%(objectname)"],
                )
                .await?;
                let borrower = runtime
                    .agent_facility
                    .worktrees
                    .reserve_workspace("outside-tree", WorkspaceEndpoint::Local)?;
                runtime
                    .agent_facility
                    .worktrees
                    .assign_workspace(&borrower, identity.clone())?;
                assert!(
                    runtime
                        .archive_thread("borrower-archive".into(), root.id.clone())
                        .await
                        .is_err()
                );
                assert!(handle.path.join("dirty").is_file());
                assert_eq!(
                    runtime
                        .store
                        .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                        .await?
                        .unwrap()
                        .phase,
                    ArchivePhase::Saved
                );
                drop(borrower);
                let mut legacy = runtime
                    .store
                    .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                    .await?
                    .unwrap();
                legacy.worktrees.clear();
                legacy.phase = ArchivePhase::Cleaned;
                legacy.changed()?;
                runtime.store.save_thread_archive(&legacy).await?;
                git_fixture(
                    &repository,
                    &["worktree", "lock", handle.path.to_str().unwrap()],
                )
                .await?;
                assert!(
                    runtime
                        .archive_thread("locked-archive".into(), root.id.clone())
                        .await
                        .is_err()
                );
                assert!(handle.path.join("dirty").is_file());
                git_fixture(
                    &repository,
                    &["worktree", "unlock", handle.path.to_str().unwrap()],
                )
                .await?;
                // Forced cleanup must not inspect disposable file content or depend on a healthy index.
                let index =
                    git_fixture(&handle.path, &["rev-parse", "--git-path", "index"]).await?;
                let index = Path::new(index.trim());
                let index = if index.is_absolute() {
                    index.to_owned()
                } else {
                    handle.path.join(index)
                };
                tokio::fs::write(index, b"invalid disposable Git index").await?;
                assert!(
                    git_fixture(&handle.path, &["status", "--porcelain=v1"])
                        .await
                        .is_err()
                );
                runtime
                    .archive_thread("discard-archive".into(), root.id.clone())
                    .await?
                    .context("archive reply")?;
                assert!(!handle.path.exists());
                assert!(reliable.is_file());
                assert_eq!(
                    git_fixture(
                        &repository,
                        &["for-each-ref", "--format=%(refname):%(objectname)"]
                    )
                    .await?,
                    refs
                );
                assert!(repository.is_dir());
                if root_owned {
                    let replacement = manager
                        .create(WorktreeCreateSpec {
                            repo_root: repository.clone(),
                            root_thread_id: root.id.clone(),
                            ownership: WorktreeOwnership::Session {
                                thread_id: root.id.clone(),
                            },
                            base_commit: manager.resolve_head(&repository).await?,
                        })
                        .await
                        .map_err(|error| anyhow::anyhow!("{error:?}"))?;
                    tokio::fs::write(
                        replacement.path.join("replacement"),
                        b"preserve replacement",
                    )
                    .await?;
                    assert!(
                        runtime
                            .archive_thread("replacement-archive".into(), root.id.clone())
                            .await
                            .is_err()
                    );
                    assert_eq!(
                        tokio::fs::read(replacement.path.join("replacement")).await?,
                        b"preserve replacement"
                    );
                    manager
                        .cleanup(
                            &replacement,
                            crate::agent::worktree::WorktreeCleanupPolicy::Discard,
                        )
                        .await?;
                    runtime
                        .archive_thread("settle-original-archive".into(), root.id.clone())
                        .await?
                        .context("settled archive")?;
                }
                runtime.restore_thread(root.id.clone()).await?;
                if root_owned {
                    assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
                }
                assert!(
                    !handle.path.exists(),
                    "restoration cannot recreate a removed worktree"
                );
                runtime
                    .delete_thread("delete-archived-worktrees".into(), root.id.clone())
                    .await?
                    .context("delete reply")?;
                assert!(!reliable.exists());
                assert!(repository.join(".git").is_dir());
                assert_eq!(
                    git_fixture(
                        &repository,
                        &["for-each-ref", "--format=%(refname):%(objectname)"]
                    )
                    .await?,
                    refs
                );
                runtime.shutdown_runtime().await?;
            }
            Ok(())
        }

        #[tokio::test]
        async fn permanent_delete_releases_unregistered_worktree_without_touching_leftovers()
        -> Result<()> {
            use crate::{
                agent::worktree::{
                    ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
                },
                studio::{
                    agent_host::worktree_lease::{
                        WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
                    },
                    store::thread_archive::ArchiveScope,
                },
            };
            for root_owned in [true, false] {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let repository = temp.path().join("repository");
                tokio::fs::create_dir(&repository).await?;
                git_fixture(&repository, &["init", "--quiet"]).await?;
                git_fixture(
                    &repository,
                    &[
                        "-c",
                        "user.name=fixture",
                        "-c",
                        "user.email=fixture@example.invalid",
                        "commit",
                        "--quiet",
                        "--allow-empty",
                        "-m",
                        "fixture",
                    ],
                )
                .await?;
                let repository = dunce::canonicalize(repository)?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&repository).await?;
                let manager = WorktreeManager::new(
                    repository.clone(),
                    std::sync::Arc::new(ExecutorWorktreeBackend::new(
                        pl_remote_helper::Executor::local()?,
                    )),
                );
                let head = manager.resolve_head(&repository).await?;
                let owner_id = if root_owned {
                    "owned-root"
                } else {
                    "owned-private-child"
                };
                let ownership = if root_owned {
                    WorktreeOwnership::Session {
                        thread_id: "owned-root".into(),
                    }
                } else {
                    WorktreeOwnership::Child {
                        child_id: owner_id.into(),
                    }
                };
                let handle = manager
                    .create(WorktreeCreateSpec {
                        repo_root: repository.clone(),
                        root_thread_id: "owned-root".into(),
                        ownership,
                        base_commit: head.clone(),
                    })
                    .await
                    .map_err(|error| anyhow::anyhow!("{error:?}"))?;
                let identity = WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    handle.path.to_string_lossy().into_owned(),
                )?;
                let mut lease = WorktreeLease {
                    revision: 1,
                    state: WorktreeLeaseState::Prepared,
                    owner_kind: if root_owned {
                        WorktreeLeaseOwnerKind::Session
                    } else {
                        WorktreeLeaseOwnerKind::Child
                    },
                    owner_thread_id: owner_id.into(),
                    root_thread_id: "owned-root".into(),
                    workspace_id: project.id.clone(),
                    ssh_alias: None,
                    repository_root: repository.to_string_lossy().into_owned(),
                    path: identity.root.clone(),
                    base_commit: head,
                };
                runtime
                    .store
                    .bind_workspace_identity(owner_id, &identity)
                    .await?;
                runtime
                    .agent_facility
                    .worktrees
                    .record_durable(lease.clone())
                    .await?;
                lease.transition(WorktreeLeaseState::Active);
                runtime
                    .agent_facility
                    .worktrees
                    .record_durable(lease)
                    .await?;
                let root = if root_owned {
                    let (delta, session, agent) = DirectoryDelta::register_session(
                        "owned-root".into(),
                        &project.id,
                        "owned",
                        pl_protocol::ThreadModeId::simple(),
                        pl_protocol::ThreadWorkspaceMode::Worktree,
                        identity.root.clone(),
                        crate::config::ROOT_AGENT_ROUTE_KEY,
                    );
                    runtime
                        .agent_facility
                        .product_events
                        .commit_directory(delta)
                        .await?;
                    let root = crate::studio::ThreadRecord::from_directory_thread(
                        crate::studio::records::thread_projection(&session, &agent, |id| {
                            runtime
                                .store
                                .catalog()
                                .get_agent(id)
                                .map(|agent| agent.thread_id)
                        })?,
                    );
                    runtime.register_new_thread(root.clone()).await?;
                    root
                } else {
                    let root = runtime
                        .create_thread_with_id("owned-root", &project.id, "local root")
                        .await?;
                    let preparation = PreparationIdentity {
                        thread_id: owner_id.into(),
                        workspace_id: project.id.clone(),
                        parent_id: Some(root.id.clone()),
                        root_id: root.id.clone(),
                    };
                    runtime.store.begin_thread_preparation(preparation).await?;
                    runtime
                        .store
                        .bind_thread_preparation(owner_id, &identity)
                        .await?;
                    runtime.store.confirm_preparation_stop(owner_id).await?;
                    runtime
                        .store
                        .confirm_preparation_retirement(owner_id)
                        .await?;
                    root
                };

                let neighbor = runtime
                    .create_thread_with_id("neighbor", &project.id, "neighbor")
                    .await?;
                runtime.shutdown_runtime().await?;
                git_fixture(
                    &repository,
                    &[
                        "worktree",
                        "remove",
                        "--force",
                        handle.path.to_str().unwrap(),
                    ],
                )
                .await?;
                tokio::fs::create_dir_all(&handle.path).await?;
                let leftover = handle.path.join("keep.txt");
                tokio::fs::write(&leftover, b"unowned content").await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                assert!(
                    runtime
                        .archive_thread("archive-orphan".into(), root.id.clone())
                        .await
                        .is_err()
                );
                runtime
                    .delete_thread("delete-orphan".into(), root.id.clone())
                    .await?
                    .context("delete must complete")?;
                assert_eq!(tokio::fs::read(&leftover).await?, b"unowned content");
                assert!(runtime.store.read_thread(&root.id).await?.is_none());
                assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                assert!(
                    runtime
                        .store
                        .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                        .await?
                        .is_none()
                );
                runtime.shutdown_runtime().await?;
                let reopened = StudioRuntime::initialize(options(&home)).await?;
                assert!(reopened.store.read_thread(&root.id).await?.is_none());
                assert!(reopened.store.read_thread(&neighbor.id).await?.is_some());
                assert_eq!(tokio::fs::read(&leftover).await?, b"unowned content");
                reopened.shutdown_runtime().await?;
            }
            Ok(())
        }

        mod required {
            //! The original private owner may stop for deletion without a successful preservation receipt.
            use super::*;
            use crate::studio::ThreadRecord;

            #[tokio::test]
            async fn permanent_delete_sealed_missing_public_member_retries_frozen_scope()
            -> Result<()> {
                use crate::studio::store::thread_archive::ArchiveScope;
                for missing_root in [false, true] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir_all(&workspace).await?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&workspace).await?;
                    let root = runtime
                        .create_thread_with_id("missing-public-root", &project.id, "root")
                        .await?;
                    let middle =
                        cold_child(&runtime, &root.clone().into(), "missing-public-middle").await?;
                    let leaf = cold_child(&runtime, &middle, "missing-public-leaf").await?;
                    let neighbor = runtime
                        .create_thread_with_id("missing-public-neighbor", &project.id, "keep")
                        .await?;
                    let binding = WorkspaceIdentity::canonical(
                        WorkspaceEndpoint::Local,
                        dunce::canonicalize(&workspace)?
                            .to_string_lossy()
                            .into_owned(),
                    )?;
                    for id in [&root.id, &middle.id, &leaf.id, &neighbor.id] {
                        runtime.store.bind_workspace_identity(id, &binding).await?;
                        let execution = workspace.join(SessionFiles::new(id).root());
                        tokio::fs::create_dir_all(&execution).await?;
                        tokio::fs::write(execution.join("marker"), id).await?;
                    }
                    runtime.store.database().execute_unprepared(
            "CREATE TRIGGER pause_missing_public BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'pause sealed public deletion'); END"
        ).await?;
                    let error = runtime
                        .delete_thread("freeze-missing-public".into(), root.id.clone())
                        .await
                        .expect_err("retain a sealed deletion before physical cleanup");
                    assert!(
                        format!("{error:#}").contains("pause sealed public deletion"),
                        "{error:#}"
                    );
                    let deletion = runtime.store.thread_delete(&root.id).await?.unwrap();
                    assert_eq!(deletion.phase, DeletePhase::Sealed);
                    let scope = ArchiveScope::Thread(root.id.clone());
                    let frozen = runtime.store.thread_archive(&scope).await?.unwrap();
                    assert_eq!(frozen.members.len(), 3);
                    let tree = runtime.store.read_directory_tree(&root.id).await?;
                    let mut extra = tree.clone();
                    let mut unadmitted = tree[0].clone();
                    unadmitted.agent.thread_id = "outside-sealed-scope".into();
                    extra.push(unadmitted);
                    assert!(
                        runtime
                            .freeze_thread_removal(scope.clone(), &extra, &[])
                            .await
                            .is_err()
                    );
                    assert!(
                        runtime
                            .store
                            .thread_preparation("outside-sealed-scope")
                            .await?
                            .is_none()
                    );
                    for field in ["workspace", "root", "parent", "binding"] {
                        let mut changed = tree.clone();
                        let member = changed
                            .iter_mut()
                            .find(|thread| thread.agent.thread_id == middle.id)
                            .unwrap();
                        match field {
                            "workspace" => {
                                member.session.workspace_id = "different-workspace".into()
                            }
                            "root" => member.root_thread_id = neighbor.id.clone(),
                            "parent" => member.parent_thread_id = Some(neighbor.id.clone()),
                            // Change the frozen original, rather than asking a mutable path to override it.
                            "binding" => {}
                            _ => unreachable!(),
                        }
                        if field == "binding" {
                            let mut conflicting = frozen.clone();
                            conflicting
                                .members
                                .iter_mut()
                                .find(|member| member.thread_id == middle.id)
                                .unwrap()
                                .execution
                                .root
                                .push_str("-replacement");
                            conflicting.changed()?;
                            runtime.store.save_thread_archive(&conflicting).await?;
                            assert!(
                                runtime
                                    .freeze_thread_removal(scope.clone(), &tree, &[])
                                    .await
                                    .is_err()
                            );
                            let mut restored = frozen.clone();
                            restored.revision = conflicting.revision;
                            restored.changed()?;
                            runtime.store.save_thread_archive(&restored).await?;
                        } else {
                            assert!(
                                runtime
                                    .freeze_thread_removal(scope.clone(), &changed, &[])
                                    .await
                                    .is_err(),
                                "{field}"
                            );
                        }
                    }
                    runtime
                        .agent_facility
                        .product_events
                        .drain_directory_writes()
                        .await?;
                    let missing = if missing_root { &root.id } else { &leaf.id };
                    let catalog = runtime.store.catalog();
                    let mut sessions = catalog.sessions();
                    let mut agents = catalog.agents();
                    if missing_root {
                        sessions.retain(|session| session.session_id != root.id);
                        agents.retain(|agent| agent.session_id != root.id);
                    } else {
                        agents.retain(|agent| agent.thread_id != *missing);
                    }
                    // Retain the original runtime responsibility while removing canonical public facts
                    // between attempts. Removing the whole root also removes its session and descendants,
                    // so the directory remains structurally valid.
                    catalog.test_restore_records(sessions, agents).await?;
                    assert!(runtime.store.read_thread(missing).await?.is_none());
                    let remaining = runtime.store.read_directory_tree(&root.id).await?;
                    let retried = runtime
                        .freeze_thread_removal(scope.clone(), &remaining, &[])
                        .await?;
                    assert_eq!(retried.members.len(), frozen.members.len());
                    for original in &frozen.members {
                        let member = retried
                            .members
                            .iter()
                            .find(|member| member.thread_id == original.thread_id)
                            .unwrap();
                        assert_eq!(member.execution, original.execution);
                        assert_eq!(member.host_session, original.host_session);
                    }
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER pause_missing_public")
                        .await?;
                    let reply = runtime
                        .delete_thread("retry-missing-public".into(), root.id.clone())
                        .await?
                        .unwrap();
                    assert_eq!(reply.result.deleted_thread_ids, deletion.thread_ids);
                    for original in &frozen.members {
                        assert!(!original.host_session.exists());
                        assert!(
                            !workspace
                                .join(SessionFiles::new(&original.thread_id).root())
                                .exists()
                        );
                    }
                    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                    assert_eq!(
                        tokio::fs::read(
                            workspace
                                .join(SessionFiles::new(&neighbor.id).root())
                                .join("marker")
                        )
                        .await?,
                        neighbor.id.as_bytes()
                    );
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_cold_private_preparations_join_and_retire_after_restart()
            -> Result<()> {
                use crate::studio::store::thread_preparation::{
                    PreparationBinding, PreparationSave,
                };
                for restart in [false, true] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir_all(&workspace).await?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&workspace).await?;
                    let root = runtime
                        .create_thread_with_id("cold-private-root", &project.id, "root")
                        .await?;
                    let neighbor = runtime
                        .create_thread_with_id("cold-private-neighbor", &project.id, "keep")
                        .await?;
                    let id = "cold-private-child";
                    runtime
                        .store
                        .begin_removal_preparation(
                            PreparationIdentity {
                                thread_id: id.into(),
                                workspace_id: project.id.clone(),
                                parent_id: Some(root.id.clone()),
                                root_id: root.id.clone(),
                            },
                            false,
                        )
                        .await?;
                    let binding = WorkspaceIdentity::canonical(
                        WorkspaceEndpoint::Local,
                        dunce::canonicalize(&workspace)?
                            .to_string_lossy()
                            .into_owned(),
                    )?;
                    runtime.store.bind_thread_preparation(id, &binding).await?;
                    // A durable obligation from a previous owner must not require loading its cold store.
                    runtime
                        .store
                        .require_preparation_save(id, "departed-incarnation", 7)
                        .await?;
                    let host = runtime.store.session_paths(&project.id, id)?;
                    tokio::fs::create_dir_all(host.root()).await?;
                    tokio::fs::write(host.history_database(), b"unreadable private content")
                        .await?;
                    let execution = workspace.join(SessionFiles::new(id).root());
                    tokio::fs::create_dir_all(&execution).await?;
                    tokio::fs::write(execution.join("artifact"), b"private").await?;
                    let runtime = if restart {
                        runtime.shutdown_runtime().await?;
                        StudioRuntime::initialize(options(&home)).await?
                    } else {
                        runtime
                    };
                    runtime.store.database().execute_unprepared(
            "CREATE TRIGGER inspect_cold_private BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'inspect cold private stop'); END"
        ).await?;
                    let error = runtime
                        .delete_thread("inspect-cold-private".into(), root.id.clone())
                        .await
                        .expect_err("inspect ACK before physical deletion");
                    assert!(
                        format!("{error:#}").contains("inspect cold private stop"),
                        "{error:#}"
                    );
                    let record = runtime.store.thread_preparation(id).await?.unwrap();
                    assert!(record.stopped && record.deletion_stopped && record.retired);
                    assert_eq!(record.save, PreparationSave::Required);
                    assert_eq!(
                        record.binding,
                        PreparationBinding::Bound { identity: binding }
                    );
                    assert!(record.storage.unwrap().closed_receipt.is_none());
                    assert!(
                        runtime
                            .store
                            .thread_persistence()
                            .shared_history(id)
                            .is_none()
                    );
                    assert_eq!(
                        tokio::fs::read(host.history_database()).await?,
                        b"unreadable private content"
                    );
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER inspect_cold_private")
                        .await?;
                    runtime
                        .delete_thread("finish-cold-private".into(), root.id.clone())
                        .await?
                        .unwrap();
                    assert!(!host.root().exists());
                    assert!(!execution.exists());
                    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_missing_frozen_private_and_failed_member_continue_independent_items()
            -> Result<()> {
                use crate::studio::store::thread_archive::ArchiveScope;
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let root = runtime
                    .create_thread_with_id("continue-root", &project.id, "root")
                    .await?;
                let neighbor = runtime
                    .create_thread_with_id("continue-neighbor", &project.id, "keep")
                    .await?;
                let id = "continue-private";
                let identity = PreparationIdentity {
                    thread_id: id.into(),
                    workspace_id: project.id.clone(),
                    parent_id: Some(root.id.clone()),
                    root_id: root.id.clone(),
                };
                runtime
                    .store
                    .begin_removal_preparation(identity, false)
                    .await?;
                runtime
                    .store
                    .bind_thread_preparation(
                        id,
                        &WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Local,
                            dunce::canonicalize(&workspace)?
                                .to_string_lossy()
                                .into_owned(),
                        )?,
                    )
                    .await?;
                let host = runtime.store.session_paths(&project.id, id)?;
                tokio::fs::create_dir_all(host.root()).await?;
                let execution = workspace.join(SessionFiles::new(id).root());
                tokio::fs::create_dir_all(&execution).await?;
                let tree = runtime.store.read_directory_tree(&root.id).await?;
                let archive = runtime
                    .freeze_thread_removal(ArchiveScope::Thread(root.id.clone()), &tree, &[])
                    .await?;
                runtime.store.save_thread_archive(&archive).await?;
                runtime
        .store
        .database()
        .execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "DELETE FROM studio_objects WHERE owner_id=? AND object_kind='threadPreparation'",
            [id.into()],
        ))
        .await?;
                let failed = workspace.join(SessionFiles::new(&root.id).root());
                if failed.exists() {
                    tokio::fs::remove_dir_all(&failed).await?;
                }
                tokio::fs::create_dir_all(failed.parent().unwrap()).await?;
                tokio::fs::write(&failed, b"preserve wrong target kind").await?;
                runtime
                    .delete_thread("continue-delete".into(), root.id.clone())
                    .await
                    .expect_err("one unsafe target");
                let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
                assert_eq!(operation.phase, DeletePhase::Removing);
                let private = operation
                    .members
                    .iter()
                    .find(|member| member.identity.thread_id == id)
                    .unwrap();
                assert!(private.execution_deleted && private.host_deleted);
                assert!(!execution.exists() && !host.root().exists());
                assert_eq!(
                    tokio::fs::read(&failed).await?,
                    b"preserve wrong target kind"
                );
                assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                // Completed siblings must not be re-deleted when a retry encounters a replacement.
                tokio::fs::create_dir_all(&execution).await?;
                tokio::fs::write(execution.join("replacement"), b"keep").await?;
                tokio::fs::remove_file(&failed).await?;
                runtime
                    .delete_thread("continue-retry".into(), root.id)
                    .await?
                    .unwrap();
                assert_eq!(
                    tokio::fs::read(execution.join("replacement")).await?,
                    b"keep"
                );
                runtime.shutdown_runtime().await?;
                Ok(())
            }
            use crate::studio::store::thread_preparation::{PreparationBinding, PreparationSave};
            use pl_core::thread::cold::{ColdStore, ColdStoreError, StoragePressure, ThreadWrite};
            use std::sync::{
                Arc,
                atomic::{AtomicBool, AtomicUsize, Ordering},
            };

            #[derive(Debug)]
            struct PrivateFlushFailure {
                sink: ThreadStorageSink,
                closing: Arc<AtomicBool>,
                flushes: Arc<AtomicUsize>,
            }

            impl ColdStore for PrivateFlushFailure {
                fn pressure(&self, id: &str) -> StoragePressure {
                    self.sink.pressure(id)
                }
                fn admit(
                    &self,
                    id: &str,
                    write: ThreadWrite,
                ) -> std::result::Result<(), ColdStoreError> {
                    if write.checkpoint.state.lifecycle == pl_core::thread::ThreadLifecycle::Closed
                    {
                        self.closing.store(true, Ordering::SeqCst);
                    }
                    self.sink.admit(id, write)
                }
                async fn flush(
                    &self,
                    id: &str,
                    sequence: u64,
                ) -> std::result::Result<(), ColdStoreError> {
                    self.flushes.fetch_add(1, Ordering::SeqCst);
                    self.sink.flush(id, sequence).await?;
                    if self.closing.load(Ordering::SeqCst) {
                        return Err(ColdStoreError {
                            source: Box::new(std::io::Error::other(
                                "private original save ACK failed",
                            )),
                        });
                    }
                    Ok(())
                }
            }

            #[tokio::test]
            async fn permanent_delete_private_required_save_records_real_stop_without_save_ack()
            -> Result<()> {
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let root = runtime
                    .create_thread_with_id("delete-private-root", &project.id, "root")
                    .await?;
                runtime.ensure_thread_owner(&root.id).await?.flush().await?;
                let id = "delete-private-required";
                let mut private = pl_protocol::Thread::placeholder(id);
                private.workspace_id = project.id.clone();
                private.workspace_path = workspace.to_string_lossy().into_owned();
                private.root_thread_id = root.id.clone();
                private.parent_thread_id = Some(root.id.clone());
                let (_, agent) = crate::studio::records::directory_facts_from_thread(&private);
                runtime
                    .agent_facility
                    .product_events
                    .commit_directory(DirectoryDelta {
                        agent_upserts: vec![agent],
                        ..Default::default()
                    })
                    .await?;
                runtime
                    .store
                    .begin_thread_preparation(PreparationIdentity {
                        thread_id: id.into(),
                        workspace_id: project.id.clone(),
                        parent_id: Some(root.id.clone()),
                        root_id: root.id.clone(),
                    })
                    .await?;
                let binding = WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    dunce::canonicalize(&workspace)?
                        .to_string_lossy()
                        .into_owned(),
                )?;
                runtime.store.bind_thread_preparation(id, &binding).await?;
                let sink = ThreadStorageSink::new(runtime.store.clone(), private, None).await?;
                let projection = spawn_live_projection_for_thread(runtime.store.clone(), id);
                let flushes = Arc::new(AtomicUsize::new(0));
                let mut spec = crate::thread_assembler::archive_test_spec(
                    id.into(),
                    Some(root.id.clone()),
                    &workspace,
                );
                spec.cold_store = Some(ColdStoreHandle::new(PrivateFlushFailure {
                    sink,
                    closing: Arc::new(AtomicBool::new(false)),
                    flushes: flushes.clone(),
                }));
                spec.initial_extensions.insert(
                    String::new(),
                    pl_core::context::OpaquePayload::text("invalid initialization"),
                );
                assert!(
                    runtime
                        .session_for_roots(std::slice::from_ref(&root.id))?
                        .assemble(spec)
                        .await
                        .is_err()
                );
                let record = runtime
                    .store
                    .thread_preparation(id)
                    .await?
                    .context("retained private owner")?;
                assert_eq!(record.save, PreparationSave::Required);
                assert!(!record.stopped);
                assert!(
                    runtime
                        .session_of(id)
                        .and_then(|session| session.observed_thread(id))
                        .is_some()
                );
                let before = flushes.load(Ordering::SeqCst);
                assert!(
                    !workspace.join(SessionFiles::new(id).root()).exists(),
                    "the first execution removal must also handle an absent bound session"
                );
                runtime
                    .store
                    .database()
                    .execute_unprepared(
                        "CREATE TRIGGER inspect_private_stop BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'inspect deletion stop without save'); END",
                    )
                    .await?;
                let error = tokio::time::timeout(
                    std::time::Duration::from_secs(15),
                    runtime.delete_thread("inspect-private".into(), root.id.clone()),
                )
                .await?
                .expect_err("inspect the retained stop ACK before physical deletion");
                ensure!(
                    format!("{error:#}").contains("inspect deletion stop without save"),
                    "{error:#}"
                );
                projection.await?;
                let stopped = runtime
                    .store
                    .thread_preparation(id)
                    .await?
                    .context("private stop ACK")?;
                assert!(stopped.stopped && stopped.retired && stopped.deletion_stopped);
                assert_eq!(stopped.save, PreparationSave::Required);
                assert!(stopped.storage.as_ref().unwrap().closed_receipt.is_none());
                assert_eq!(
                    stopped.binding,
                    PreparationBinding::Bound { identity: binding }
                );
                assert_eq!(
                    flushes.load(Ordering::SeqCst),
                    before,
                    "deletion must never retry original flush"
                );
                assert!(
                    runtime
                        .session_of(id)
                        .and_then(|session| session.observed_thread(id))
                        .is_none()
                );
                runtime
                    .store
                    .database()
                    .execute_unprepared("DROP TRIGGER inspect_private_stop")
                    .await?;
                runtime
                    .delete_thread("finish-private".into(), root.id)
                    .await?
                    .context("private deletion reply")?;
                assert!(runtime.store.thread_preparation(id).await?.is_none());
                runtime.shutdown_runtime().await?;
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_unpublished_bound_root_retries_after_restart() -> Result<()> {
                use crate::studio::store::thread_archive::ArchiveScope;
                for (restart, remote) in
                    [(false, false), (true, false), (false, true), (true, true)]
                {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir_all(&workspace).await?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&workspace).await?;
                    // Publish only directory identity: the original preparation never attached storage.
                    let (delta, session, agent) = DirectoryDelta::register_session(
                        "private-root".into(),
                        &project.id,
                        "root",
                        pl_protocol::ThreadModeId::simple(),
                        pl_protocol::ThreadWorkspaceMode::Local,
                        workspace.to_string_lossy().into_owned(),
                        crate::config::ROOT_AGENT_ROUTE_KEY,
                    );
                    runtime
                        .agent_facility
                        .product_events
                        .commit_directory(delta)
                        .await?;
                    let root = ThreadRecord::from_directory_thread(
                        crate::studio::records::thread_projection(&session, &agent, |id| {
                            runtime
                                .store
                                .catalog()
                                .get_agent(id)
                                .map(|agent| agent.thread_id)
                        })?,
                    );
                    let neighbor = runtime
                        .create_thread_with_id("private-root-neighbor", &project.id, "keep")
                        .await?;
                    runtime
                        .store
                        .begin_removal_preparation(
                            PreparationIdentity {
                                thread_id: root.id.clone(),
                                workspace_id: project.id.clone(),
                                parent_id: None,
                                root_id: root.id.clone(),
                            },
                            false,
                        )
                        .await?;
                    let binding = if remote {
                        WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Ssh {
                                host: "fixture.invalid".into(),
                                port: 22,
                                username: "fixture".into(),
                            },
                            "/isolated/workspace".into(),
                        )?
                    } else {
                        WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Local,
                            dunce::canonicalize(&workspace)?
                                .to_string_lossy()
                                .into_owned(),
                        )?
                    };
                    runtime
                        .store
                        .bind_thread_preparation(&root.id, &binding)
                        .await?;
                    let execution = workspace.join(SessionFiles::new(&root.id).root());
                    tokio::fs::create_dir_all(&execution).await?;
                    tokio::fs::write(execution.join("marker"), b"remove").await?;
                    let host = runtime.store.session_paths(&project.id, &root.id)?;
                    tokio::fs::create_dir_all(host.root()).await?;
                    tokio::fs::write(host.root().join("marker"), b"host").await?;
                    runtime
                        .agent_facility
                        .product_events
                        .drain_directory_writes()
                        .await?;
                    // Retirement must release resources without writing a child-failure projection.
                    // The directory becomes writable again before actual deletion publication.
                    let catalog = runtime.store.paths().catalog_file();
                    let catalog_bytes = tokio::fs::read(&catalog).await?;
                    tokio::fs::remove_file(&catalog).await?;
                    tokio::fs::create_dir(&catalog).await?;
                    runtime.store.database().execute_unprepared(
            "CREATE TRIGGER pause_private_root BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'pause private root deletion'); END"
        ).await?;
                    let error = runtime
                        .delete_thread("pause-private-root".into(), root.id.clone())
                        .await
                        .expect_err("pause before removal");
                    ensure!(
                        format!("{error:#}").contains("pause private root deletion"),
                        "{error:#}"
                    );
                    let archive = runtime
                        .store
                        .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                        .await?
                        .unwrap();
                    assert!(archive.members.is_empty());
                    assert_eq!(archive.private_members.len(), 1);
                    let preparation = runtime.store.thread_preparation(&root.id).await?.unwrap();
                    assert!(
                        preparation.stopped && preparation.retired && preparation.deletion_stopped
                    );
                    assert!(!preparation.published && preparation.storage.is_none());
                    assert!(execution.exists());
                    assert_eq!(
                        runtime
                            .store
                            .catalog()
                            .get_agent(&root.id)
                            .unwrap()
                            .native_status(),
                        agent.native_status()
                    );
                    tokio::fs::remove_dir(&catalog).await?;
                    tokio::fs::write(&catalog, catalog_bytes).await?;
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER pause_private_root")
                        .await?;
                    let runtime = if restart {
                        runtime.shutdown_runtime().await?;
                        StudioRuntime::initialize(options(&home)).await?
                    } else {
                        runtime
                    };
                    let result = runtime
                        .delete_thread("finish-private-root".into(), root.id.clone())
                        .await;
                    if remote {
                        // No real SSH service is contacted. Retirement must finish even when its original
                        // endpoint is unavailable; independent host removal still proceeds, with remote
                        // cleanup retained as a real failure rather than silently falling back to local.
                        let error =
                            result.expect_err("unconfigured original endpoint must remain pending");
                        ensure!(
                            format!("{error:#}")
                                .contains("delete frozen SSH endpoint is no longer configured"),
                            "{error:#}"
                        );
                        let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
                        assert_eq!(operation.phase, DeletePhase::Removing);
                        assert!(operation.members[0].host_deleted);
                        assert!(!operation.members[0].execution_deleted);
                        assert!(execution.exists());
                        assert!(runtime.store.read_thread(&root.id).await?.is_some());
                    } else {
                        result?.context("root deletion must finish")?;
                        assert!(!execution.exists());
                        assert!(runtime.store.read_thread(&root.id).await?.is_none());
                    }
                    assert!(!host.root().exists());
                    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }
        }

        mod auxiliary {
            //! Deletion isolates undecodable auxiliary rows while ordinary reads remain strict.
            use super::*;
            use std::sync::{Arc, Mutex};
            use tracing::{Subscriber, field::Visit, span};

            #[derive(Clone, Default)]
            struct Captured(Arc<Mutex<Vec<String>>>);

            impl Visit for Captured {
                fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
                    self.0
                        .lock()
                        .unwrap()
                        .push(format!("{}={value}", field.name()));
                }
                fn record_debug(
                    &mut self,
                    field: &tracing::field::Field,
                    value: &dyn std::fmt::Debug,
                ) {
                    self.0
                        .lock()
                        .unwrap()
                        .push(format!("{}={value:?}", field.name()));
                }
            }

            impl Subscriber for Captured {
                fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
                    metadata.target().starts_with("pl_studio_runtime")
                }
                fn new_span(&self, attributes: &span::Attributes<'_>) -> span::Id {
                    attributes.record(&mut self.clone());
                    static NEXT: std::sync::atomic::AtomicU64 =
                        std::sync::atomic::AtomicU64::new(1);
                    span::Id::from_u64(NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
                }
                fn record(&self, _: &span::Id, values: &span::Record<'_>) {
                    values.record(&mut self.clone());
                }
                fn record_follows_from(&self, _: &span::Id, _: &span::Id) {}
                fn event(&self, event: &tracing::Event<'_>) {
                    event.record(&mut self.clone());
                }
                fn enter(&self, _: &span::Id) {}
                fn exit(&self, _: &span::Id) {}
            }

            async fn damaged_aux(
                runtime: &StudioRuntime,
                kind: &str,
                owner: &str,
                object: &str,
                schema: i64,
                payload: &str,
            ) -> Result<()> {
                runtime.store.database().execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "INSERT OR REPLACE INTO studio_objects
         (owner_kind,owner_id,object_kind,revision,schema_version,payload_json,payload_hash,updated_at)
         VALUES (?,?,?,1,?,?,?,0)",
        [kind.into(), owner.into(), object.into(), schema.into(), payload.into(),
            pl_core::context::content_hash(payload.as_bytes()).into()],
    )).await?;
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_skips_bad_aux_preserves_unknown_rows_and_logs_safe_reasons()
            -> Result<()> {
                use crate::studio::store::thread_archive::ArchiveScope;
                let temp = tempfile::tempdir()?;
                let home = temp.path().join("home");
                let _endpoint = configure(&home)?;
                let workspace = temp.path().join("workspace");
                tokio::fs::create_dir_all(&workspace).await?;
                let runtime = StudioRuntime::initialize(options(&home)).await?;
                let project = runtime.open_project(&workspace).await?;
                let root = runtime
                    .create_thread_with_id("bad-aux-root", &project.id, "root")
                    .await?;
                let neighbor = runtime
                    .create_thread_with_id("bad-aux-neighbor", &project.id, "keep")
                    .await?;
                let secret = "SYNTHETIC-SECRET-USER-CONTENT";
                let broken = format!(r#"{{"rootId":"{secret}""#);
                let project_scope = ArchiveScope::Workspace(project.id.clone()).key();
                let neighbor_scope = ArchiveScope::Thread(neighbor.id.clone()).key();
                let root_scope = ArchiveScope::Thread(root.id.clone()).key();
                for scope in [&project_scope, &neighbor_scope, &root_scope] {
                    damaged_aux(&runtime, "archive", scope, "threadArchive", 2, &broken).await?;
                }
                damaged_aux(
                    &runtime,
                    "thread",
                    "unknown-private",
                    "threadPreparation",
                    2,
                    &broken,
                )
                .await?;
                let invalid = serde_json::json!({
                    "identity": { "threadId": "invalid-stop", "workspaceId": project.id,
                        "parentId": neighbor.id, "rootId": neighbor.id },
                    "revision": 1, "binding": { "state": "unbound" },
                    "save": "required", "storage": null, "disposition": "pending",
                    "stopped": true, "retired": false, "published": false
                });
                // Use the actual binding representation so this reaches validation, rather than JSON shape.
                let mut invalid = invalid;
                invalid["binding"] = serde_json::to_value(
                    crate::studio::store::thread_preparation::PreparationBinding::Unbound,
                )?;
                damaged_aux(
                    &runtime,
                    "thread",
                    "invalid-stop",
                    "threadPreparation",
                    2,
                    &invalid.to_string(),
                )
                .await?;
                assert!(runtime.store.thread_preparations().await.is_err());
                assert!(runtime.store.thread_archives().await.is_err());
                let captured = Captured::default();
                let dispatch = tracing::Dispatch::new(captured.clone());
                let _capture = tracing::dispatcher::set_default(&dispatch);
                let failed = workspace.join(SessionFiles::new(&root.id).root());
                if failed.exists() {
                    tokio::fs::remove_dir_all(&failed).await?;
                }
                tokio::fs::create_dir_all(failed.parent().unwrap()).await?;
                tokio::fs::write(&failed, secret).await?;
                runtime
                    .delete_thread("safe-aux-failed-correlation".into(), root.id.clone())
                    .await
                    .expect_err("preserve the wrong target while logging safe failure metadata");
                tokio::fs::remove_file(&failed).await?;
                runtime
                    .delete_thread("safe-aux-correlation".into(), root.id.clone())
                    .await?
                    .unwrap();
                let records = captured.0.lock().unwrap().join("\n");
                for expected in [
                    "deletion_id=safe-aux-correlation",
                    "stage=",
                    "member=",
                    "reason=aux_json",
                    "reason=preparation_save_ack",
                    "decision=preserve_unknown_skip",
                    "outcome=skipped",
                    "elapsed_ms=",
                    "line=",
                    "column=",
                    "outcome=incomplete",
                    "decision=continue_independent",
                ] {
                    assert!(
                        records.contains(expected),
                        "missing {expected} in {records}"
                    );
                }
                assert!(
                    !records.contains(secret),
                    "raw auxiliary body leaked into diagnostics"
                );
                assert!(runtime.store.read_thread(&root.id).await?.is_none());
                assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                // Shared objects whose scope cannot be decoded retain exactly their original bytes.
                let rows = runtime
                    .store
                    .database()
                    .query_all_raw(Statement::from_sql_and_values(
                        DatabaseBackend::Sqlite,
                        "SELECT payload_json FROM studio_objects WHERE
         (owner_kind='archive' AND owner_id IN (?,?))
         OR (owner_id='unknown-private' AND object_kind='threadPreparation')",
                        [project_scope.into(), neighbor_scope.into()],
                    ))
                    .await?;
                assert_eq!(rows.len(), 3);
                for row in rows {
                    assert_eq!(row.try_get::<String>("", "payload_json")?, broken);
                }
                assert!(runtime.store.thread_preparations().await.is_err());
                runtime.shutdown_runtime().await?;
                Ok(())
            }
        }

        mod recovery {
            //! Durable intent failures must not contaminate independently committed deletion progress.
            use super::*;
            use crate::studio::store::thread_archive::{ArchiveScope, ThreadArchiveOperation};
            use std::sync::Arc;

            async fn reject_intent(
                runtime: &StudioRuntime,
                owner: &str,
                object: &str,
                target: &str,
                collection: &str,
                identity: &str,
                flag: &str,
            ) -> Result<()> {
                // The first intent fails at revision N+1. A buggy caller's later independent save at
                // N+2 succeeds, exposing any unsaved in-memory flag that leaked into that commit.
                let sql = format!(
        "CREATE TRIGGER reject_first_intent BEFORE UPDATE ON studio_objects
         WHEN NEW.owner_id='{owner}' AND NEW.object_kind='{object}'
          AND NEW.revision=OLD.revision+1
          AND EXISTS (SELECT 1 FROM json_each(NEW.payload_json,'$.{collection}')
            WHERE json_extract(value,'$.{identity}')='{target}' AND json_extract(value,'$.{flag}')=1)
          AND NOT EXISTS (SELECT 1 FROM json_each(OLD.payload_json,'$.{collection}')
            WHERE json_extract(value,'$.{identity}')='{target}' AND json_extract(value,'$.{flag}')=1)
         BEGIN SELECT RAISE(ABORT,'one intent persistence failure'); END"
    );
                runtime.store.database().execute_unprepared(&sql).await?;
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_progress_failure_keeps_session_targets_retryable()
            -> Result<()> {
                for flag in [
                    "executionRemovalStarted",
                    "hostRemovalStarted",
                    "executionDeleted",
                    "hostDeleted",
                ] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir_all(&workspace).await?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&workspace).await?;
                    let root = runtime
                        .create_thread_with_id("intent-root", &project.id, "root")
                        .await?;
                    let child = cold_child(&runtime, &root.clone().into(), "intent-child").await?;
                    for id in [&root.id, &child.id] {
                        let host = runtime.store.session_paths(&project.id, id)?;
                        tokio::fs::create_dir_all(host.root()).await?;
                        tokio::fs::write(host.root().join("marker"), id).await?;
                        let execution = workspace.join(SessionFiles::new(id).root());
                        tokio::fs::create_dir_all(&execution).await?;
                        tokio::fs::write(execution.join("marker"), id).await?;
                    }
                    reject_intent(
                        &runtime,
                        &root.id,
                        "threadDelete",
                        &root.id,
                        "members",
                        "identity.threadId",
                        flag,
                    )
                    .await?;
                    let error = runtime
                        .delete_thread("reject-session-intent".into(), root.id.clone())
                        .await
                        .expect_err(
                            "the failed item remains pending while independent members finish",
                        );
                    assert!(
                        format!("{error:#}").contains("one intent persistence failure"),
                        "{error:#}"
                    );
                    let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
                    assert_eq!(operation.phase, DeletePhase::Removing);
                    let member = operation
                        .members
                        .iter()
                        .find(|member| member.identity.thread_id == root.id)
                        .unwrap();
                    let completion = flag.ends_with("Deleted");
                    let failed_path = if flag.starts_with("execution") {
                        assert_eq!(member.execution_removal_started, completion);
                        assert!(!member.execution_deleted && member.host_deleted);
                        workspace.join(SessionFiles::new(&root.id).root())
                    } else {
                        assert_eq!(member.host_removal_started, completion);
                        assert!(!member.host_deleted && member.execution_deleted);
                        member.host_session.clone()
                    };
                    if completion {
                        assert!(
                            !failed_path.exists(),
                            "physical removal precedes the failed completion ACK"
                        );
                    } else {
                        assert!(
                            failed_path.join("marker").is_file(),
                            "failed intent must not perform removal"
                        );
                    }
                    let independent = operation
                        .members
                        .iter()
                        .find(|member| member.identity.thread_id == child.id)
                        .unwrap();
                    assert!(independent.host_deleted && independent.execution_deleted);
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER reject_first_intent")
                        .await?;
                    runtime
                        .delete_thread("retry-session-intent".into(), root.id)
                        .await?
                        .unwrap();
                    assert!(!failed_path.exists());
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }

            async fn private_worktrees(
                runtime: &StudioRuntime,
                repository: &Path,
                workspace_id: &str,
                root: &str,
                ids: &[&str],
            ) -> Result<Vec<std::path::PathBuf>> {
                use crate::{
                    agent::worktree::{
                        ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager,
                        WorktreeOwnership,
                    },
                    studio::agent_host::worktree_lease::{
                        WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
                    },
                };
                let manager = WorktreeManager::new(
                    repository.to_owned(),
                    Arc::new(ExecutorWorktreeBackend::new(
                        pl_remote_helper::Executor::local()?,
                    )),
                );
                let head = manager.resolve_head(repository).await?;
                let mut paths = Vec::new();
                for id in ids {
                    let handle = manager
                        .create(WorktreeCreateSpec {
                            repo_root: repository.to_owned(),
                            root_thread_id: root.into(),
                            ownership: WorktreeOwnership::Child {
                                child_id: (*id).into(),
                            },
                            base_commit: head.clone(),
                        })
                        .await?;
                    let identity = WorkspaceIdentity::canonical(
                        WorkspaceEndpoint::Local,
                        handle.path.to_string_lossy().into_owned(),
                    )?;
                    runtime
                        .store
                        .begin_removal_preparation(
                            PreparationIdentity {
                                thread_id: (*id).into(),
                                workspace_id: workspace_id.into(),
                                root_id: root.into(),
                                parent_id: Some(root.into()),
                            },
                            false,
                        )
                        .await?;
                    runtime.store.bind_thread_preparation(id, &identity).await?;
                    runtime.store.bind_workspace_identity(id, &identity).await?;
                    let mut lease = WorktreeLease {
                        revision: 1,
                        state: WorktreeLeaseState::Prepared,
                        owner_kind: WorktreeLeaseOwnerKind::Child,
                        owner_thread_id: (*id).into(),
                        root_thread_id: root.into(),
                        workspace_id: workspace_id.into(),
                        ssh_alias: None,
                        repository_root: repository.to_string_lossy().into_owned(),
                        path: identity.root.clone(),
                        base_commit: head.clone(),
                    };
                    runtime
                        .agent_facility
                        .worktrees
                        .record_durable(lease.clone())
                        .await?;
                    lease.transition(WorktreeLeaseState::Active);
                    runtime
                        .agent_facility
                        .worktrees
                        .record_durable(lease)
                        .await?;
                    tokio::fs::write(handle.path.join("marker"), b"original worktree").await?;
                    paths.push(handle.path);
                }
                Ok(paths)
            }

            async fn repository_fixture(path: &Path) -> Result<()> {
                tokio::fs::create_dir_all(path).await?;
                git_fixture(path, &["init", "--quiet"]).await?;
                git_fixture(
                    path,
                    &[
                        "-c",
                        "user.name=fixture",
                        "-c",
                        "user.email=fixture@example.invalid",
                        "commit",
                        "--quiet",
                        "--allow-empty",
                        "-m",
                        "fixture",
                    ],
                )
                .await?;
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_progress_failure_keeps_multiple_worktrees_retryable()
            -> Result<()> {
                for flag in ["removalStarted", "cleaned"] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let repository = temp.path().join("repository");
                    repository_fixture(&repository).await?;
                    let repository = dunce::canonicalize(repository)?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&repository).await?;
                    let root = runtime
                        .create_thread_with_id("worktree-intent-root", &project.id, "root")
                        .await?;
                    let paths = private_worktrees(
                        &runtime,
                        &repository,
                        &project.id,
                        &root.id,
                        &["worktree-intent-a", "worktree-intent-b"],
                    )
                    .await?;
                    let scope = ArchiveScope::Thread(root.id.clone());
                    reject_intent(
                        &runtime,
                        &scope.key(),
                        "threadArchive",
                        "worktree-intent-a",
                        "worktrees",
                        "lease.ownerThreadId",
                        flag,
                    )
                    .await?;
                    let error = runtime
                        .delete_thread("reject-worktree-intent".into(), root.id.clone())
                        .await
                        .expect_err("first worktree intent fails, second worktree still completes");
                    assert!(
                        format!("{error:#}").contains("one intent persistence failure"),
                        "{error:#}"
                    );
                    let archive = runtime.store.thread_archive(&scope).await?.unwrap();
                    let first = archive
                        .worktrees
                        .iter()
                        .find(|entry| entry.lease.owner_thread_id == "worktree-intent-a")
                        .unwrap();
                    assert!(!first.cleaned);
                    if flag == "removalStarted" {
                        assert!(!first.removal_started && first.common_dir.is_none());
                        assert!(paths[0].join("marker").is_file());
                    } else {
                        assert!(first.removal_started && first.common_dir.is_some());
                        assert!(
                            !paths[0].exists(),
                            "physical removal finished before its ACK failed"
                        );
                    }
                    let second = archive
                        .worktrees
                        .iter()
                        .find(|entry| entry.lease.owner_thread_id == "worktree-intent-b")
                        .unwrap();
                    assert!(second.removal_started && second.cleaned);
                    assert!(!paths[1].exists());
                    let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
                    assert!(operation.members.iter().all(|member| member.host_deleted));
                    let member = operation
                        .members
                        .iter()
                        .find(|member| member.identity.thread_id == "worktree-intent-a")
                        .unwrap();
                    assert!(
                        !member.execution_deleted,
                        "uncommitted progress cannot acknowledge execution deletion"
                    );
                    let public = crate::error_mapping::studio_error_from_anyhow_ref(
                        &runtime
                            .store
                            .history(&root.id)
                            .await
                            .err()
                            .context("reads must be revoked")?,
                    );
                    assert_eq!(public.code, pl_protocol::studio::StudioErrorCode::Conflict);
                    assert!(public.message.contains("重试删除"));
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER reject_first_intent")
                        .await?;
                    runtime
                        .delete_thread("retry-worktree-intent".into(), root.id)
                        .await?
                        .unwrap();
                    assert!(paths.iter().all(|path| !path.exists()));
                    assert!(repository.join(".git").is_dir());
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }

            async fn pause_sealed(runtime: &StudioRuntime) -> Result<()> {
                runtime
                    .store
                    .database()
                    .execute_unprepared(
                        "CREATE TRIGGER pause_recovery BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'inspect frozen recovery'); END",
                    )
                    .await?;
                Ok(())
            }

            async fn lose_archive(
                runtime: &StudioRuntime,
                scope: &ArchiveScope,
                corrupt: bool,
            ) -> Result<()> {
                let sql = if corrupt {
                    "UPDATE studio_objects SET payload_json='broken archive',payload_hash='invalid'
         WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'"
                } else {
                    "DELETE FROM studio_objects WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'"
                };
                runtime
                    .store
                    .database()
                    .execute_raw(Statement::from_sql_and_values(
                        DatabaseBackend::Sqlite,
                        sql,
                        [scope.key().into()],
                    ))
                    .await?;
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_recovers_frozen_members_without_canonical_or_archive_aux()
            -> Result<()> {
                for corrupt in [false, true] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let workspace = temp.path().join("workspace");
                    tokio::fs::create_dir_all(&workspace).await?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&workspace).await?;
                    let root = runtime
                        .create_thread_with_id("aux-recovery-root", &project.id, "root")
                        .await?;
                    let child =
                        cold_child(&runtime, &root.clone().into(), "aux-recovery-child").await?;
                    let neighbor = runtime
                        .create_thread_with_id("aux-recovery-neighbor", &project.id, "keep")
                        .await?;
                    assert!(runtime.store.thread_preparation(&child.id).await?.is_none());
                    let execution = workspace.join(SessionFiles::new(&child.id).root());
                    tokio::fs::create_dir_all(&execution).await?;
                    tokio::fs::write(execution.join("marker"), b"frozen child").await?;
                    pause_sealed(&runtime).await?;
                    let first = runtime
                        .delete_thread("seal-aux-recovery".into(), root.id.clone())
                        .await
                        .unwrap_err();
                    assert!(
                        format!("{first:#}").contains("inspect frozen recovery"),
                        "{first:#}"
                    );
                    let frozen = runtime.store.thread_delete(&root.id).await?.unwrap();
                    let scope = ArchiveScope::Thread(root.id.clone());
                    runtime
                        .agent_facility
                        .product_events
                        .drain_directory_writes()
                        .await?;
                    let catalog = runtime.store.catalog();
                    let mut agents = catalog.agents();
                    agents.retain(|agent| agent.thread_id != child.id);
                    catalog
                        .test_restore_records(catalog.sessions(), agents)
                        .await?;
                    lose_archive(&runtime, &scope, corrupt).await?;
                    runtime
            .store
            .database()
            .execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "DELETE FROM studio_objects WHERE owner_id=? AND object_kind='threadPreparation'",
                [root.id.clone().into()],
            ))
            .await?;
                    let error = runtime
                        .delete_thread("inspect-aux-recovery".into(), root.id.clone())
                        .await
                        .unwrap_err();
                    assert!(
                        format!("{error:#}").contains("inspect frozen recovery"),
                        "{error:#}"
                    );
                    let restored = runtime.store.thread_delete(&root.id).await?.unwrap();
                    assert!(
                        runtime.store.thread_preparation(&root.id).await?.is_none(),
                        "durable deletion must not recreate an absent preparation as unbound"
                    );
                    assert_eq!(restored.thread_ids, frozen.thread_ids);
                    for member in &frozen.members {
                        let current = restored
                            .members
                            .iter()
                            .find(|current| current.identity == member.identity)
                            .unwrap();
                        assert_eq!(current.host_session, member.host_session);
                        assert_eq!(current.execution, member.execution);
                    }
                    if corrupt {
                        let raw = runtime.store.database().query_one_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "SELECT payload_json FROM studio_objects WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'",
                [scope.key().into()],
            )).await?.unwrap();
                        assert_eq!(raw.try_get::<String>("", "payload_json")?, "broken archive");
                    }
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER pause_recovery")
                        .await?;
                    runtime
                        .delete_thread("finish-aux-recovery".into(), root.id)
                        .await?
                        .unwrap();
                    assert!(!execution.exists());
                    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }

            #[tokio::test]
            async fn permanent_delete_keeps_unavailable_worktree_progress_blocked() -> Result<()> {
                for corrupt in [false, true] {
                    let temp = tempfile::tempdir()?;
                    let home = temp.path().join("home");
                    let _endpoint = configure(&home)?;
                    let repository = temp.path().join("repository");
                    repository_fixture(&repository).await?;
                    let repository = dunce::canonicalize(repository)?;
                    let runtime = StudioRuntime::initialize(options(&home)).await?;
                    let project = runtime.open_project(&repository).await?;
                    let root = runtime
                        .create_thread_with_id("unknown-git-root", &project.id, "root")
                        .await?;
                    let paths = private_worktrees(
                        &runtime,
                        &repository,
                        &project.id,
                        &root.id,
                        &["unknown-git-child"],
                    )
                    .await?;
                    pause_sealed(&runtime).await?;
                    assert!(
                        runtime
                            .delete_thread("seal-unknown-git".into(), root.id.clone())
                            .await
                            .is_err()
                    );
                    let scope = ArchiveScope::Thread(root.id.clone());
                    let original: ThreadArchiveOperation =
                        runtime.store.thread_archive(&scope).await?.unwrap();
                    runtime
                        .store
                        .database()
                        .execute_unprepared("DROP TRIGGER pause_recovery")
                        .await?;
                    lose_archive(&runtime, &scope, corrupt).await?;
                    let error = runtime
                        .delete_thread("block-unknown-git".into(), root.id.clone())
                        .await
                        .unwrap_err();
                    assert!(
                        format!("{error:#}").contains("no readable original owner"),
                        "{error:#}"
                    );
                    assert!(paths[0].join("marker").is_file());
                    assert_eq!(
                        runtime.store.thread_delete(&root.id).await?.unwrap().phase,
                        DeletePhase::Sealed
                    );
                    // Restore the exact original owner only to release this fixture's managed resources.
                    lose_archive(&runtime, &scope, false).await?;
                    runtime.store.save_thread_archive(&original).await?;
                    runtime
                        .delete_thread("finish-known-git".into(), root.id)
                        .await?
                        .unwrap();
                    runtime.shutdown_runtime().await?;
                }
                Ok(())
            }
        }
    }
}
