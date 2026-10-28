//! Owned background diagnostics; frontend readiness does not wait for cold histories or Git.
use super::super::{
    StudioRuntime,
    background_task::{self, BackgroundTask},
};
use anyhow::Result;

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn start_recovery_scan(&self) {
        let mut slot = self.recovery_task.lock().await;
        if slot.as_ref().is_some_and(|task| !task.is_finished()) {
            return;
        }
        self.recovery.begin();
        let runtime = self.clone();
        *slot = Some(BackgroundTask::new(tokio::spawn(async move {
            let mut issues = Vec::new();
            let result = async {
                let stage = crate::startup_timing::Stage::new("recover_worktrees");
                runtime.append_worktree_recovery_issues(&mut issues).await?;
                drop(stage);
                runtime
                    .append_unavailable_project_recovery_issues(&mut issues)
                    .await?;
                Ok::<_, anyhow::Error>(())
            }
            .await;
            match result {
                Ok(()) => {
                    issues.retain(|issue| issue.worktree.as_ref().is_none_or(|preview| {
                        runtime.agent_facility.worktrees.get(&preview.owner_thread_id)
                            .is_some_and(|lease| lease.revision == preview.lease_revision
                                && lease.state != crate::studio::agent_host::worktree_lease::WorktreeLeaseState::Cleaned)
                    }));
                    runtime.recovery.replace(issues);
                }
                Err(error) => {
                    tracing::warn!(
                        diagnostic = %crate::studio::recovery_registry::diagnostic::failure(error.as_ref()),
                        "background recovery failed"
                    );
                    runtime.recovery.fail(error);
                }
            }
        })));
    }
    pub(super) async fn stop_recovery_scan(&self) -> Result<()> {
        background_task::stop(&self.recovery_task)
            .await
            .map_err(|error| anyhow::anyhow!("recovery task failed: {error}"))?;
        self.recovery.stop();
        Ok(())
    }
}
