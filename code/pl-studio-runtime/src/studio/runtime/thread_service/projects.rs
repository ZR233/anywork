//! Project 目录命令：打开、列出与归档 Project，并物化项目归档所需的冷目录范围。

use std::path::Path;

use crate::WorkspaceKind;
use anyhow::{Context, Result, bail, ensure};

use crate::studio::records::{DirectoryMember, WorkspaceRecord};
use crate::studio::store::ProjectRow;
use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord, ProjectRemoval};
use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope};

use super::super::StudioRuntime;
use super::super::thread_title::ThreadTitleCancellationCause;

/// Path identity used by local and remote project open. Local has no SSH alias.
pub(in crate::studio::runtime) enum OpenedProject {
    Local { path: String },
    Remote { alias: String, path: String },
}

pub(in crate::studio::runtime) enum FoundProject {
    Published(WorkspaceRecord),
    Stored(ProjectRow),
}

impl StudioRuntime {
    /// Hot snapshot wins. A miss falls through to the durable path identity, including a closed row.
    pub(in crate::studio::runtime) async fn find_project_record(
        &self,
        path: &str,
        alias: Option<&str>,
    ) -> Result<Option<FoundProject>> {
        if let Some(project) = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.path == path && project.ssh_alias.as_deref() == alias)
        {
            return Ok(Some(FoundProject::Published(project)));
        }
        Ok(self
            .store
            .find_project_by_path(path, alias)
            .await?
            .map(FoundProject::Stored))
    }

    /// Publishes an opened project without taking the lifecycle lock. Callers keep that lock.
    ///
    /// A published hit returns immediately. Local open rejects a standalone identity; remote open
    /// keeps its historical kind write of `Project` even when reusing a stored row.
    pub(in crate::studio::runtime) async fn commit_opened_project(
        &self,
        opened: OpenedProject,
    ) -> Result<WorkspaceRecord> {
        let now = crate::studio::unix_seconds();
        let (id, kind, name, path, ssh_alias, created_at) = match opened {
            OpenedProject::Local { path } => match self.find_project_record(&path, None).await? {
                Some(FoundProject::Published(project)) => {
                    ensure!(
                        project.kind == WorkspaceKind::Project,
                        "the standalone workspace cannot be opened as a user project"
                    );
                    return Ok(project);
                }
                Some(FoundProject::Stored(existing)) => {
                    ensure!(
                        existing.kind == WorkspaceKind::Project,
                        "the standalone workspace cannot be opened as a user project"
                    );
                    (
                        existing.id,
                        existing.kind,
                        existing.name,
                        path,
                        None,
                        existing.created_at,
                    )
                }
                None => (
                    crate::studio::ids::new_id("project"),
                    WorkspaceKind::Project,
                    crate::studio::paths::project_name(Path::new(&path)),
                    path,
                    None,
                    now,
                ),
            },
            OpenedProject::Remote { alias, path } => {
                match self
                    .find_project_record(&path, Some(alias.as_str()))
                    .await?
                {
                    Some(FoundProject::Published(project)) => return Ok(project),
                    Some(FoundProject::Stored(existing)) => (
                        existing.id,
                        WorkspaceKind::Project,
                        existing.name,
                        path,
                        Some(alias),
                        existing.created_at,
                    ),
                    None => (
                        crate::studio::ids::new_id("project"),
                        WorkspaceKind::Project,
                        remote_project_name(&path),
                        path,
                        Some(alias),
                        now,
                    ),
                }
            }
        };
        let public = WorkspaceRecord::from_directory_projection(
            id.clone(),
            kind,
            name.clone(),
            path.clone(),
            ssh_alias.clone(),
            now,
        );
        let delta = ProjectDirectoryRecord {
            id: id.clone(),
            kind,
            name: name.clone(),
            path,
            ssh_alias,
            created_at,
            updated_at: now,
            last_opened_at: Some(now),
            closed: false,
        };
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta::upsert_project(delta))
            .await?;
        Ok(public)
    }

    pub(in crate::studio::runtime) async fn commit_remote_project(
        &self,
        alias: &str,
        path: String,
    ) -> Result<WorkspaceRecord> {
        self.commit_opened_project(OpenedProject::Remote {
            alias: alias.to_string(),
            path,
        })
        .await
    }

    pub async fn open_project(&self, path: impl AsRef<Path>) -> Result<WorkspaceRecord> {
        let canonical = dunce::canonicalize(path.as_ref())?;
        anyhow::ensure!(canonical.is_dir(), "workspace path is not a directory");
        let _guard = self.lifecycle_lock.lock().await;
        self.commit_opened_project(OpenedProject::Local {
            path: canonical.to_string_lossy().into_owned(),
        })
        .await
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
    pub(super) async fn prepare_standalone_workspace_at(
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
            self.find_project_record(&path, None).await?.is_none(),
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
        let existing = self
            .store
            .workspaces()
            .get(id)
            .context("Project directory entry not found")?;
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
                created_at: existing.created_at,
                updated_at: now,
                last_opened_at: Some(now),
                closed: false,
            }))
            .await?;
        Ok(project)
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
        let threads = self.load_project_archive_scope(workspace_id)?;
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
        let mut pipeline = super::settlement::TreeSettlementPipeline::pin(self, admitted_ids);
        let frozen = self
            .freeze_thread_archive(
                ArchiveScope::Workspace(workspace_id.into()),
                &threads,
                &admitted,
            )
            .await?;
        pipeline.extend_ids(frozen.thread_ids());
        for (_, scope) in &scopes {
            scope.cancel_preparations();
        }
        pipeline.quiesce(self).await?;
        pipeline
            .cancel_titles(self, ThreadTitleCancellationCause::ProjectArchive)
            .await;
        pipeline
            .join_scopes(&scopes, "project archive preparations did not join")
            .await?;
        let threads = self.load_project_archive_scope(workspace_id)?;
        pipeline.ensure_frozen(
            threads.iter().map(|thread| thread.agent.thread_id.as_str()),
            "project archive member has no frozen preparation responsibility",
        )?;
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
        // Reuse Saved/Cleaned ACKs without creating a new cold writer or rebuilding cleaned temp.
        self.finish_sealed_archive(&mut archive, &thread_ids)
            .await?;
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

    fn load_project_archive_scope(&self, workspace_id: &str) -> Result<Vec<DirectoryMember>> {
        let threads = self.store.directory_members_for_project(workspace_id)?;
        Ok(threads)
    }
}

fn remote_project_name(path: &str) -> String {
    path.trim_end_matches('/')
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or("remote-workspace")
        .to_string()
}

#[cfg(test)]
mod standalone_tests;
