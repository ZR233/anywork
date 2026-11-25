use anyhow::Result;

use super::StudioStore;
use crate::studio::records::WorkspaceRecord;

impl StudioStore {
    pub async fn list_projects(&self) -> Result<Vec<WorkspaceRecord>> {
        let mut entries = self
            .workspaces()
            .entries()
            .into_iter()
            .filter(|entry| !entry.closed)
            .collect::<Vec<_>>();
        entries.sort_by(|left, right| {
            right
                .last_opened_at
                .cmp(&left.last_opened_at)
                .then_with(|| right.updated_at.cmp(&left.updated_at))
                .then_with(|| right.id.cmp(&left.id))
        });
        Ok(entries.into_iter().map(|entry| entry.project()).collect())
    }

    /// 聚合冷加载：按 path 找到既有 Project 行身份事实。
    pub(in crate::studio) async fn find_project_by_path(
        &self,
        path: &str,
        ssh_alias: Option<&str>,
    ) -> Result<Option<ProjectRow>> {
        Ok(self
            .workspaces()
            .find_by_path(path, ssh_alias)
            .map(|entry| ProjectRow {
                id: entry.id,
                kind: entry.kind,
                name: entry.name,
                created_at: entry.created_at,
            }))
    }

    pub async fn read_project(&self, workspace_id: &str) -> Result<Option<WorkspaceRecord>> {
        Ok(self
            .workspaces()
            .get(workspace_id)
            .map(|entry| entry.project()))
    }
}

/// `find_project_by_path` 返回的持久身份事实。
#[derive(Debug, Clone)]
pub(in crate::studio) struct ProjectRow {
    pub(in crate::studio) id: String,
    pub(in crate::studio) kind: crate::WorkspaceKind,
    pub(in crate::studio) name: String,
    pub(in crate::studio) created_at: i64,
}
