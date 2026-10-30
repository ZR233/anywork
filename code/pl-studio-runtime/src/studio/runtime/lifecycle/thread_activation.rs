//! Product activation follows saved ancestry and shares the single Thread assembler.
use super::super::StudioRuntime;
use crate::studio::ThreadRecord;
use crate::thread_assembler::ThreadActivation;
use anyhow::{Context, Result};

impl StudioRuntime {
    pub(in crate::studio) async fn ensure_thread_owner(
        &self,
        id: &str,
    ) -> Result<pl_core::thread::ThreadHandle> {
        let record = self.read_protocol_thread(id).await?;
        self.store.ensure_agent_execution_allowed(id).await?;
        self.check_thread_read_access(&record)?;
        let live = self
            .threads
            .observed_thread(id)
            .map(|thread| thread.snapshot());
        self.verify_thread_execution_preparation(&record, live.as_ref())
            .await?;
        self.check_thread_execution_access(&record)?;
        self.store.ensure_agent_execution_allowed(id).await?;
        let _activation_pin = self.pin_thread(id);
        if let Some(thread) = self.threads.thread(id) {
            self.residency.touch(id).await;
            self.enforce_residency_limit().await;
            return Ok(thread);
        }
        let mut ancestry: Vec<(ThreadActivation, ThreadRecord)> = Vec::new();
        let mut directory = Vec::new();
        let mut seen = std::collections::BTreeSet::new();
        let mut cursor = id.to_owned();
        loop {
            anyhow::ensure!(seen.insert(cursor.clone()), "cyclic Thread ancestry");
            if self.threads.thread(&cursor).is_some() {
                break;
            }
            let record = self.read_owned_thread(&cursor).await?;
            self.store.ensure_agent_execution_allowed(&cursor).await?;
            self.verify_thread_execution_preparation(
                &pl_protocol::Thread::from(record.clone()),
                None,
            )
            .await?;
            self.check_thread_execution_access(&pl_protocol::Thread::from(record.clone()))?;
            anyhow::ensure!(
                record.visibility == crate::studio::ThreadVisibility::Active,
                "archived Thread cannot be activated for execution"
            );
            let parent = record.parent_thread_id.clone();
            directory.push(pl_protocol::Thread::from(record.clone()));
            ancestry.push((
                ThreadActivation {
                    id: record.id.clone(),
                    parent_id: parent.clone(),
                },
                record,
            ));
            let Some(parent) = parent else {
                break;
            };
            cursor = parent;
        }
        // Observers and tool refresh can run as soon as activation publishes an owner.
        // Warm the validated ancestry first, preserving any newer in-memory entries.
        self.agent_facility
            .product_events
            .warm_thread_index(directory);
        for (identity, record) in ancestry.into_iter().rev() {
            let activated_id = identity.id.clone();
            if let Err(error) = self
                .threads
                .activate(identity, self.thread_factory.clone())
                .await
            {
                // `worktree` 会话激活失败必须显式发布该 Thread 的 Recovery，
                // 不允许静默回落到主工作区。
                if record.workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
                    let failure = anyhow::Error::from(error);
                    self.publish_session_workspace_issue(
                        &pl_protocol::Thread::from(record),
                        &failure,
                    )
                    .await;
                    return Err(failure);
                }
                return Err(error.into());
            }
            self.residency.touch(&activated_id).await;
        }
        // 主会话载入/恢复时就地核对它自己的子成员：中断事实与待决摘要只在各自保存的检查点里
        // 读取并投影到目录，不激活成员、不重建工作区、不发模型请求（design/17）。
        let restored_root = self.read_owned_thread(id).await?;
        if restored_root.parent_thread_id.is_none() {
            self.thread_observations.reconcile_children(id).await?;
        }
        self.residency.touch(id).await;
        self.enforce_residency_limit().await;
        self.threads
            .thread(id)
            .context("Thread activation did not publish its owner")
    }
}
