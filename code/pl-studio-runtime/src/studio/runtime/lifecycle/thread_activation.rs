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
        let _activation_pin = self.pin_thread(id);
        if let Some(thread) = self.threads.thread(id) {
            self.residency.touch(id).await;
            // A resident owner skips preparation, so this is where a binding that failed earlier is
            // retried: the promotion and the Recovery retirement are idempotent, so any later command
            // that touches this Thread repairs the state instead of leaving it permanently half-done.
            self.bind_activated_workspace(id).await?;
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
            // The owner is published, so the site it runs in is live again: the lease says so and the
            // workspace Recovery entry for it is retired. Without this a restored child kept the
            // `preserved`/`prepared` state it had while it was stopped, which made a later scan present
            // a working site as broken and let explicit cleanup delete a directory a running child was
            // using.
            self.bind_activated_workspace(&activated_id).await?;
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

    /// Binds the workspace of a just-published owner to an `active` lease and retires its Recovery.
    ///
    /// The lease promotion is one lease revision and is idempotent: an owner that was already active
    /// keeps its state, and a `cleaned` site is never presented as active. The Recovery entries for a
    /// site that is now in use are removed and the observed state is republished, so the product never
    /// offers "clean up" for a workspace a live child runs in.
    async fn bind_activated_workspace(&self, thread_id: &str) -> Result<()> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseState;
        if let Some(mut lease) = self.agent_facility.worktrees.get(thread_id)
            && matches!(
                lease.state,
                WorktreeLeaseState::Prepared | WorktreeLeaseState::Preserved
            )
        {
            lease.transition(WorktreeLeaseState::Active);
            // A lease that could not be saved as `active` is not a restored site: the failure is
            // propagated so the caller can retry, and the Recovery entry below is deliberately kept —
            // retiring it would tell the product the site is fine while its own record says otherwise.
            self.agent_facility
                .worktrees
                .record(lease)
                .map_err(|error| {
                    anyhow::anyhow!("the activated workspace lease could not be saved: {error}")
                })?;
        }
        let stale = self
            .recovery
            .snapshot()
            .into_iter()
            .filter(|issue| issue.thread_id.as_deref() == Some(thread_id))
            .filter(|issue| {
                issue.category == crate::studio::StudioRecoveryIssueCategory::Repository
            })
            .map(|issue| issue.id)
            .collect::<Vec<_>>();
        for issue_id in stale {
            self.recovery.update_if_current(
                &issue_id,
                None,
                || true,
                |issues| {
                    self.agent_facility
                        .product_events
                        .emit_recovery_state(issues);
                },
            );
        }
        Ok(())
    }
}
