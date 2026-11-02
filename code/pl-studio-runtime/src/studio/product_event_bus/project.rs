//! Project 目录：启动基线装载、目录读取与 Project 事实的内存应用与移除。

use anyhow::Result;

use crate::studio::ids::unix_seconds;
use crate::studio::store::directory::ProjectRemoval;
use crate::{
    StudioProductEventEnvelope, StudioProductEventKind, StudioProjectDirectoryData,
    StudioProjectDirectoryState,
};

use super::ProductEventBus;

impl ProductEventBus {
    /// 启动命令显式建立目录初始 revision 与 Project 小集合；普通 read 不改变 revision。
    ///
    /// Thread 摘要已在 [`ProductEventBus::new`] 从 Catalog 全量建立。
    pub async fn initialize_directories(&self) -> Result<()> {
        self.initialize_revision(&self.revisions.project);
        self.initialize_revision(&self.revisions.thread);
        self.initialize_revision(&self.revisions.agent);
        let durable_projects = self.store.list_projects().await?;
        let mut projects = self.project_snapshot.lock().await;
        for project in durable_projects {
            if !projects.iter().any(|current| current.id == project.id) {
                projects.push(project);
            }
        }
        projects.sort_by(|left, right| {
            right
                .updated_at
                .cmp(&left.updated_at)
                .then_with(|| right.id.cmp(&left.id))
        });
        Ok(())
    }

    pub async fn read_project_directory(&self) -> Result<StudioProjectDirectoryState> {
        Ok(StudioProjectDirectoryState {
            state: self.resource(
                &self.revisions.project,
                StudioProjectDirectoryData {
                    projects: self.project_snapshot.lock().await.clone(),
                },
            ),
        })
    }

    pub(in crate::studio) async fn project_snapshot(&self) -> Vec<crate::WorkspaceRecord> {
        self.project_snapshot.lock().await.clone()
    }

    pub(super) async fn apply_project_delta(
        &self,
        upserted: &[crate::WorkspaceRecord],
        removed: &[ProjectRemoval],
    ) -> Result<Option<StudioProductEventEnvelope>> {
        if upserted.is_empty() && removed.is_empty() {
            return Ok(None);
        }
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        index.update_projects(upserted, removed);
        self.bump(&self.revisions.thread);
        self.topics
            .lock()
            .expect("product topic channels lock poisoned")
            .notify(&crate::StudioProductTopic::ThreadDirectory);
        drop(index);
        self.apply_project_snapshot_delta(upserted, removed).await
    }

    pub(super) async fn apply_project_snapshot_delta(
        &self,
        upserted: &[crate::WorkspaceRecord],
        removed: &[ProjectRemoval],
    ) -> Result<Option<StudioProductEventEnvelope>> {
        if upserted.is_empty() && removed.is_empty() {
            return Ok(None);
        }
        let mut projects = self.project_snapshot.lock().await;
        for project in upserted {
            if let Some(existing) = projects.iter_mut().find(|entry| entry.id == project.id) {
                *existing = project.clone();
            } else {
                projects.push(project.clone());
            }
        }
        for removal in removed {
            projects.retain(|project| project.id != removal.workspace_id);
        }
        projects.sort_by(|left, right| {
            right
                .updated_at
                .cmp(&left.updated_at)
                .then_with(|| right.id.cmp(&left.id))
        });
        drop(projects);
        self.bump(&self.revisions.project);
        let state = self.read_project_directory().await?;
        Ok(Some(self.emit(
            StudioProductEventKind::ProjectDirectoryChanged(state),
        )))
    }

    /// 把调用方已经提交的 Project 事实直接应用到内存目录。
    pub async fn apply_project_entry(
        &self,
        project: crate::WorkspaceRecord,
    ) -> Result<StudioProductEventEnvelope> {
        self.apply_project_delta(std::slice::from_ref(&project), &[])
            .await?
            .ok_or_else(|| anyhow::anyhow!("project upsert did not produce an event"))
    }

    /// 从活动 Project 目录移除一个已归档或隔离的 Project。
    pub async fn remove_project_entry(
        &self,
        workspace_id: &str,
    ) -> Result<StudioProductEventEnvelope> {
        self.apply_project_delta(
            &[],
            &[ProjectRemoval {
                workspace_id: workspace_id.to_string(),
                thread_ids: Vec::new(),
                closed_at: unix_seconds(),
            }],
        )
        .await?
        .ok_or_else(|| anyhow::anyhow!("project removal did not produce an event"))
    }
}
