//! `StudioStore` 上的轻量会话目录入口。
//!
//! 本模块负责已提交摘要的持久化，不承担运行期目录查询；不读取任何会话
//! `state.toml`/`history.sqlite`（design/17 §17.1、§17.2）。目录 mutation 的唯一
//! 命令通道是 `ProductEventBus::commit_directory`：它同步写入本模块的 `catalog.toml`
//! 事实，write-behind 队列再把同一 delta 异步落到 SQLite 镜像并幂等重放 TOML。

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
        for session in &delta.session_upserts {
            if let Some(root) = catalog.get_agent(&session.root_agent_id) {
                self.prepare_session_manifest(session, &root).await?;
            }
            catalog.upsert_session(session.clone()).await?;
        }
        for agent in &delta.agent_upserts {
            let session = catalog.get_session(&agent.session_id).ok_or_else(|| {
                anyhow::anyhow!("agent session is not registered: {}", agent.session_id)
            })?;
            self.prepare_session_manifest(&session, agent).await?;
            catalog.upsert_agent(agent.clone()).await?;
        }
        let archived_at = delta
            .session_removals
            .iter()
            .map(|removal| removal.archived_at)
            .chain(
                delta
                    .project_removals
                    .iter()
                    .map(|removal| removal.closed_at),
            )
            .max();
        let archived_ids = delta
            .session_removals
            .iter()
            .flat_map(|removal| removal.session_ids.iter().cloned())
            .chain(
                delta
                    .project_removals
                    .iter()
                    .flat_map(|removal| removal.session_ids.iter().cloned()),
            )
            .collect::<Vec<_>>();
        if let Some(archived_at) = archived_at {
            catalog.archive_sessions(&archived_ids, archived_at).await?;
        }
        for fault in &delta.unregistered_faults {
            let mut agent = catalog.get_agent(&fault.agent_id).ok_or_else(|| {
                anyhow::anyhow!("spawn compensation agent not found: {}", fault.agent_id)
            })?;
            agent.status = fault.state.kind;
            agent.updated_at = crate::studio::ids::unix_seconds();
            catalog.upsert_agent(agent).await?;
        }
        Ok(())
    }
}
