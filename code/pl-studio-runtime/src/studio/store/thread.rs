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
    pub(in crate::studio) fn directory_member(
        &self,
        thread_id: &str,
    ) -> Result<Option<crate::studio::records::DirectoryMember>> {
        let catalog = self.catalog();
        catalog
            .agent_by_thread(thread_id)
            .map(|agent| {
                let session = catalog
                    .get_session(&agent.session_id)
                    .ok_or_else(|| anyhow::anyhow!("directory Session is missing"))?;
                crate::studio::records::DirectoryMember::resolve(session, agent, |id| {
                    catalog.get_agent(id)
                })
            })
            .transpose()
    }

    pub(in crate::studio) fn directory_members_for_project(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<crate::studio::records::DirectoryMember>> {
        let catalog = self.catalog();
        catalog
            .sessions()
            .into_iter()
            .filter(|session| session.workspace_id == workspace_id)
            .flat_map(|session| {
                catalog
                    .agents_for_session(&session.session_id)
                    .into_iter()
                    .map(move |agent| (session.clone(), agent))
            })
            .map(|(session, agent)| {
                crate::studio::records::DirectoryMember::resolve(session, agent, |id| {
                    catalog.get_agent(id)
                })
            })
            .collect()
    }

    /// Cleanup reads the whole root tree including archived descendants, without replaying
    /// their journals. The catalog already carries the persisted status summary.
    pub async fn list_threads_for_root(&self, root_thread_id: &str) -> Result<Vec<ThreadRecord>> {
        session_tree(self.catalog(), root_thread_id)
            .into_iter()
            .flat_map(|snapshot| {
                snapshot.agents.into_iter().map(move |agent| {
                    thread_projection(&snapshot.session, &agent, |id| {
                        self.catalog().get_agent(id).map(|agent| agent.thread_id)
                    })
                    .map(ThreadRecord::from_directory_thread)
                })
            })
            .collect()
    }

    /// Cold baseline for explicit archive restoration, including archived descendants.
    pub(in crate::studio) async fn read_directory_tree(
        &self,
        root_id: &str,
    ) -> Result<Vec<crate::studio::records::DirectoryMember>> {
        session_tree(self.catalog(), root_id)
            .into_iter()
            .flat_map(|snapshot| {
                snapshot.agents.into_iter().map(move |agent| {
                    crate::studio::records::DirectoryMember::resolve(
                        snapshot.session.clone(),
                        agent,
                        |id| self.catalog().get_agent(id),
                    )
                })
            })
            .collect()
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
        snapshots
            .into_iter()
            .flat_map(|snapshot| {
                snapshot
                    .agents
                    .into_iter()
                    .map(move |agent| (snapshot.session.clone(), agent))
            })
            .map(|(session, agent)| {
                thread_projection(&session, &agent, |id| {
                    catalog.get_agent(id).map(|agent| agent.thread_id)
                })
                .map(ThreadRecord::from_directory_thread)
            })
            .collect()
    }

    pub async fn read_thread(&self, thread_id: &str) -> Result<Option<ThreadRecord>> {
        let catalog = self.catalog();
        catalog
            .agent_by_thread(thread_id)
            .and_then(|agent| {
                catalog
                    .get_session(&agent.session_id)
                    .map(|session| (session, agent))
            })
            .map(|(session, agent)| {
                thread_projection(&session, &agent, |id| {
                    catalog.get_agent(id).map(|agent| agent.thread_id)
                })
                .map(ThreadRecord::from_directory_thread)
            })
            .transpose()
    }
}

fn session_tree(catalog: &CatalogStore, root_id: &str) -> Vec<SessionDirectorySnapshot> {
    let Some(session) = catalog
        .agent_by_thread(root_id)
        .filter(|agent| agent.is_root_agent())
        .and_then(|agent| {
            catalog
                .get_session(&agent.session_id)
                .filter(|session| session.root_agent_id == agent.agent_id)
        })
    else {
        return Vec::new();
    };
    let agents = catalog.agents_for_session(&session.session_id);
    vec![SessionDirectorySnapshot { session, agents }]
}
