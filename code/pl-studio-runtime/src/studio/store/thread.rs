//! Thread/会话目录记录的冷读取入口。
//!
//! 目录 mutation 已统一走 `store::directory::DirectoryDelta` 的 write-behind
//! 通道（design/17 §17.2）；本文件只保留命令路径允许的聚合冷加载与分页查询，
//! 全部从 `catalog.toml` 的会话/成员记录投影，不从 Native 快照反推成员归属。

use anyhow::Result;

use crate::studio::catalog::CatalogStore;
use crate::studio::records::{ThreadRecord, thread_projection};
use crate::studio::store::StudioStore;

/// 冷读目录树时按会话装载的成员事实。
pub(in crate::studio) struct SessionDirectorySnapshot {
    pub(in crate::studio) session: crate::studio::records::SessionDirectoryRecord,
    pub(in crate::studio) agents: Vec<crate::studio::records::AgentDirectoryRecord>,
}

impl StudioStore {
    pub async fn list_root_threads(&self, workspace_id: &str) -> Result<Vec<ThreadRecord>> {
        Ok(self
            .catalog()
            .sessions()
            .into_iter()
            .filter(|session| {
                session.workspace_id == workspace_id
                    && !session.archived
                    && self
                        .catalog()
                        .get_agent(&session.root_agent_id)
                        .is_some_and(|root| root.is_root_agent())
            })
            .filter_map(|session| root_thread_record(self.catalog(), &session))
            .collect())
    }

    /// Archive selection reads only directory facts, not historical journals.
    pub async fn list_root_threads_for_archive(
        &self,
        root_thread_id: &str,
    ) -> Result<Vec<ThreadRecord>> {
        let Some(root) = self.catalog().get_session(root_thread_id) else {
            return Ok(Vec::new());
        };
        let workspace_id = root.workspace_id;
        Ok(self
            .catalog()
            .sessions()
            .into_iter()
            .filter(|session| session.workspace_id == workspace_id && !session.archived)
            .filter_map(|session| root_thread_record(self.catalog(), &session))
            .collect())
    }

    /// Archive scope includes every active descendant without replaying its journal.
    pub async fn list_threads_for_archive(
        &self,
        root_thread_id: &str,
    ) -> Result<Vec<ThreadRecord>> {
        Ok(session_tree(self.catalog(), root_thread_id, false)
            .into_iter()
            .flat_map(|snapshot| {
                snapshot.agents.into_iter().map(move |agent| {
                    ThreadRecord::from_directory_thread(thread_projection(
                        &snapshot.session,
                        &agent,
                    ))
                })
            })
            .collect())
    }

    /// Active descendants of one root. The catalog already carries the persisted status summary.
    pub async fn list_threads_for_root(&self, root_thread_id: &str) -> Result<Vec<ThreadRecord>> {
        self.list_threads_for_archive(root_thread_id).await
    }

    /// Cold baseline for explicit archive restoration, including archived descendants.
    pub(in crate::studio) async fn read_directory_tree(
        &self,
        root_id: &str,
    ) -> Result<Vec<ThreadRecord>> {
        Ok(session_tree(self.catalog(), root_id, true)
            .into_iter()
            .flat_map(|snapshot| {
                snapshot.agents.into_iter().map(move |agent| {
                    ThreadRecord::from_directory_thread(thread_projection(
                        &snapshot.session,
                        &agent,
                    ))
                })
            })
            .collect())
    }

    /// Project 归档 activation 一次性装载其完整 Thread 目录。
    pub async fn list_threads_for_project(&self, workspace_id: &str) -> Result<Vec<ThreadRecord>> {
        let catalog = self.catalog();
        let mut snapshots = catalog
            .sessions()
            .into_iter()
            .filter(|session| session.workspace_id == workspace_id)
            .filter_map(|session| {
                let agents = catalog.agents_for_session(&session.session_id);
                (!agents.is_empty()).then_some(SessionDirectorySnapshot { session, agents })
            })
            .collect::<Vec<_>>();
        snapshots.sort_by(|left, right| {
            left.session
                .created_at
                .cmp(&right.session.created_at)
                .then_with(|| left.session.session_id.cmp(&right.session.session_id))
        });
        Ok(snapshots
            .into_iter()
            .flat_map(|snapshot| {
                snapshot
                    .agents
                    .into_iter()
                    .map(move |agent| (snapshot.session.clone(), agent))
            })
            .map(|(session, agent)| {
                ThreadRecord::from_directory_thread(thread_projection(&session, &agent))
            })
            .collect())
    }

    pub async fn list_project_thread_ids(&self, workspace_id: &str) -> Result<Vec<String>> {
        let catalog = self.catalog();
        Ok(catalog
            .sessions()
            .into_iter()
            .filter(|session| session.workspace_id == workspace_id)
            .flat_map(|session| {
                catalog
                    .agents_for_session(&session.session_id)
                    .into_iter()
                    .map(|agent| agent.thread_id)
            })
            .collect())
    }

    pub async fn read_thread(&self, thread_id: &str) -> Result<Option<ThreadRecord>> {
        let catalog = self.catalog();
        Ok(catalog
            .agent_by_thread(thread_id)
            .and_then(|agent| {
                catalog
                    .get_session(&agent.session_id)
                    .map(|session| (session, agent))
            })
            .map(|(session, agent)| {
                ThreadRecord::from_directory_thread(thread_projection(&session, &agent))
            }))
    }

    pub(in crate::studio) async fn read_thread_association(
        &self,
        thread_id: &str,
    ) -> Result<Option<ThreadRecord>> {
        self.read_thread(thread_id).await
    }
}

fn root_thread_record(
    catalog: &CatalogStore,
    session: &crate::studio::records::SessionDirectoryRecord,
) -> Option<ThreadRecord> {
    catalog
        .get_agent(&session.root_agent_id)
        .filter(|root| root.is_root_agent() && root.session_id == session.session_id)
        .map(|root| ThreadRecord::from_directory_thread(thread_projection(session, &root)))
}

fn session_tree(
    catalog: &CatalogStore,
    root_id: &str,
    include_archived: bool,
) -> Vec<SessionDirectorySnapshot> {
    let Some(session) = catalog.get_session(root_id) else {
        return Vec::new();
    };
    if !include_archived && session.archived {
        return Vec::new();
    }
    let agents = catalog.agents_for_session(&session.session_id);
    vec![SessionDirectorySnapshot { session, agents }]
}
