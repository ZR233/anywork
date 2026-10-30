//! Project 目录命令：打开、列出与归档 Project，并物化项目归档所需的冷目录范围。

use std::path::Path;

use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::WorkspaceKind;

use crate::studio::records::{ProjectRecord, ThreadRecord, ThreadVisibility};
use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord, ProjectRemoval};

use super::super::StudioRuntime;
use super::super::thread_title::ThreadTitleCancellationCause;

#[cfg(test)]
#[path = "standalone_tests.rs"]
mod standalone_tests;

impl StudioRuntime {
    pub async fn open_project(&self, path: impl AsRef<Path>) -> Result<ProjectRecord> {
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
                let public = ProjectRecord {
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
                let public = ProjectRecord {
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
    ) -> Result<ProjectRecord> {
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
    ) -> Result<ProjectRecord> {
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
        let project = ProjectRecord {
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
    pub async fn rename_project(&self, id: &str, name: &str) -> Result<ProjectRecord> {
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

    pub async fn list_projects(&self) -> Result<Vec<ProjectRecord>> {
        Ok(self.agent_facility.product_events.project_snapshot().await)
    }

    pub async fn archive_project(&self, project_id: &str) -> Result<Option<ProjectRecord>> {
        let runtime = self.clone();
        let project_id = project_id.to_owned();
        self.run_thread_lifecycle_operation(async move {
            runtime.archive_project_owned(&project_id).await
        })
        .await
    }

    /// The retained archive worker owns lifecycle admission throughout this operation.
    async fn archive_project_owned(&self, project_id: &str) -> Result<Option<ProjectRecord>> {
        ensure!(
            !self
                .agent_facility
                .product_events
                .project_snapshot()
                .await
                .iter()
                .any(
                    |project| project.id == project_id && project.kind == WorkspaceKind::Standalone
                ),
            "the standalone workspace cannot be archived"
        );
        let threads = self.load_project_archive_scope(project_id).await?;
        let Some(project) = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == project_id)
            .or_else(|| {
                // workspaces.toml is written before catalog.toml. If the latter failed (including
                // across restart), the canonical closed Project must still allow finishing its
                // active catalog rows; absence from the open-project projection is not completion.
                threads
                    .iter()
                    .any(|thread| thread.visibility == ThreadVisibility::Active)
                    .then(|| {
                        self.store
                            .workspaces()
                            .get(project_id)
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
            .map(|thread| thread.id.clone())
            .collect::<Vec<_>>();
        roots.sort();
        let mut root_operations = Vec::new();
        for root in &roots {
            root_operations.push(self.threads.agent_operation(root).await);
        }
        // A spawn admitted before these permits may just have published another child. Re-read
        // the directory only after root preparation is ordered, then seal children in stable order.
        let threads = self.load_project_archive_scope(project_id).await?;
        let thread_ids = threads
            .iter()
            .map(|thread| thread.id.clone())
            .collect::<Vec<_>>();
        let active_threads = threads
            .iter()
            .filter(|thread| thread.visibility == ThreadVisibility::Active)
            .collect::<Vec<_>>();
        let _pins = self.residency.pin_many(thread_ids.iter().cloned());
        let child_ids = threads
            .iter()
            .filter(|thread| thread.parent_thread_id.is_some())
            .map(|thread| thread.id.clone())
            .collect::<Vec<_>>();
        let _child_seals = self.threads.seal_agent_operations(&child_ids).await;
        let _root_seals = roots
            .iter()
            .map(|root| self.threads.seal_agent_operation(root))
            .collect::<Vec<_>>();
        drop(root_operations);
        for thread in &active_threads {
            match self.thread_is_busy(&thread.id).await {
                Ok(false) => {}
                Ok(true) => {
                    bail!("project has an active turn");
                }
                Err(error) => {
                    return Err(error);
                }
            }
        }
        self.retire_archived_thread_tree(&thread_ids).await?;
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                project_removals: vec![ProjectRemoval {
                    project_id: project.id.clone(),
                    thread_ids: thread_ids.clone(),
                    closed_at: crate::studio::unix_seconds(),
                }],
                ..Default::default()
            })
            .await?;
        for thread_id in &thread_ids {
            self.title_tasks
                .cancel(thread_id, ThreadTitleCancellationCause::ProjectArchive)
                .await;
            self.model_performance.remove_session(thread_id).await?;
        }
        Ok(Some(project))
    }

    pub(super) fn ensure_project_thread_admission_open(&self, project_id: &str) -> Result<()> {
        self.recovery.ensure_project_execution_access(project_id)?;
        anyhow::ensure!(
            self.store
                .workspaces()
                .get(project_id)
                .is_some_and(|entry| !entry.closed),
            "selected Project is closed or its archive needs to be retried"
        );
        Ok(())
    }

    async fn load_project_archive_scope(&self, project_id: &str) -> Result<Vec<ThreadRecord>> {
        let threads = self.store.list_threads_for_project(project_id).await?;
        let entries = threads
            .iter()
            .filter(|thread| thread.visibility == ThreadVisibility::Active)
            .cloned()
            .map(pl_protocol::Thread::from)
            .collect();
        self.agent_facility
            .product_events
            .warm_thread_index(entries);
        Ok(threads)
    }
}
