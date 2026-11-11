//! `StudioStore` 上的轻量会话目录入口。
//!
//! 本模块负责已提交摘要的持久化，不承担运行期目录查询；不读取任何会话
//! `state.toml`/`history.sqlite`（design/17 §17.1、§17.2）。目录 mutation 的唯一
//! 命令通道是 `ProductEventBus::commit_directory`：它同步写入本模块的 `catalog.toml`
//! 事实，write-behind 队列再幂等重放同一 TOML delta。

use anyhow::Result;

use crate::studio::store::StudioStore;
use crate::studio::store::directory::DirectoryDelta;

impl StudioStore {
    /// 把一次目录 delta 幂等写入 canonical TOML 目录事实源（`workspaces.toml` + `catalog.toml`）。
    ///
    /// 这是目录摘要持久化的唯一实现：命令通道（`ProductEventBus::commit_directory`）同步调用
    /// 它保证发布 revision 前事实已落盘，write-behind 批次在 [`super::directory::apply_directory_delta`]
    /// 中异步调用同一实现，使观察热路径的状态摘要经现有 writer/revision 机制合并落盘。
    /// 各写入彼此幂等：内容一致时不推进 revision、不落盘；命令与观察 delta 按 FIFO 顺序
    /// 合并，最终目录以最后提交的命令为准。
    pub(in crate::studio) async fn persist_directory_summaries(
        &self,
        delta: &DirectoryDelta,
    ) -> Result<()> {
        self.persist_directory_summaries_on(delta, self.database())
            .await
    }

    /// Write-behind already owns the single product connection. Read its deletion fences on that
    /// same transaction, rather than waiting for a second pool connection while holding the first.
    pub(in crate::studio) async fn persist_directory_summaries_on(
        &self,
        delta: &DirectoryDelta,
        db: &impl sea_orm::ConnectionTrait,
    ) -> Result<()> {
        // Workspace/Project TOML is the canonical directory fact.
        for project in &delta.project_upserts {
            self.prepare_workspace_manifest(&crate::studio::records::WorkspaceRecord {
                id: project.id.clone(),
                kind: project.kind,
                name: project.name.clone(),
                path: project.path.clone(),
                ssh_alias: project.ssh_alias.clone(),
                updated_at: project.updated_at,
            })
            .await?;
        }
        self.workspaces().apply_delta(delta).await?;
        let catalog = self.catalog();
        let deletions = Self::thread_deletes_on(db).await?;
        let mut delta = delta.clone();
        let agents = &delta.agent_upserts;
        delta.session_upserts.retain(|session| {
            let root = agents
                .iter()
                .find(|agent| agent.agent_id == session.root_agent_id)
                .cloned()
                .or_else(|| catalog.get_agent(&session.root_agent_id));
            !deletions.iter().any(|operation| {
                operation.phase != super::thread_delete::DeletePhase::Sealed
                    && root
                        .as_ref()
                        .is_some_and(|root| operation.root_id == root.thread_id)
            })
        });
        delta.agent_upserts.retain(|agent| {
            !deletions.iter().any(|operation| {
                operation.phase != super::thread_delete::DeletePhase::Sealed
                    && operation.thread_ids.contains(&agent.thread_id)
            })
        });
        for session in &delta.session_upserts {
            if let Some(root) = catalog.get_agent(&session.root_agent_id)
                && matches!(
                    root.backend,
                    pl_protocol::session::AgentBackend::Native { .. }
                )
            {
                self.prepare_session_manifest(session, &root, |id| {
                    delta
                        .agent_upserts
                        .iter()
                        .find(|agent| agent.agent_id == id)
                        .cloned()
                        .or_else(|| catalog.get_agent(id))
                })
                .await?;
            }
        }
        for agent in &delta.agent_upserts {
            if matches!(
                agent.backend,
                pl_protocol::session::AgentBackend::Acp { .. }
            ) {
                continue;
            }
            let session = delta
                .session_upserts
                .iter()
                .find(|session| session.session_id == agent.session_id)
                .cloned()
                .or_else(|| catalog.get_session(&agent.session_id))
                .ok_or_else(|| {
                    anyhow::anyhow!("agent session is not registered: {}", agent.session_id)
                })?;
            self.prepare_session_manifest(&session, agent, |id| {
                delta
                    .agent_upserts
                    .iter()
                    .find(|agent| agent.agent_id == id)
                    .cloned()
                    .or_else(|| catalog.get_agent(id))
            })
            .await?;
        }
        catalog.apply_delta(delta).await
    }
}
