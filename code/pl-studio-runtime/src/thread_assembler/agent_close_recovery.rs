//! Restart resumes only saved explicit child-close jobs, without model/workspace activation.
use super::{StudioThreadAssembler, agent_services::AgentServices};
use anyhow::{Context, Result, ensure};
use pl_tool::collaboration::thread::WorkspaceRelease;
use std::collections::BTreeMap;

impl StudioThreadAssembler {
    pub(crate) async fn resume_agent_closes(&self) -> Result<()> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("child close services are unavailable")?;
        let mut roots = BTreeMap::<String, Vec<(usize, pl_protocol::Thread)>>::new();
        for pending in services.store.agent_closes().await? {
            if pending.execution_closed && pending.worktree_cleanup.is_terminal() {
                continue;
            }
            let thread = services.record(&pending.agent_id).await?;
            let depth = services
                .authorize(&thread.root_thread_id, &thread.id)
                .await?
                .len();
            roots
                .entry(thread.root_thread_id.clone())
                .or_default()
                .push((depth, thread));
        }
        let mut failures = Vec::new();
        for (root, mut targets) in roots {
            targets.sort_by(|left, right| {
                right
                    .0
                    .cmp(&left.0)
                    .then_with(|| left.1.id.cmp(&right.1.id))
            });
            let admission = self.clone();
            let owner = self.clone();
            let recovery = services.clone();
            if let Err(error) = services
                .operations
                .run(
                    root,
                    move || {
                        ensure!(!admission.0.state().closing, "child close owner is closing");
                        Ok(())
                    },
                    async move { recovery.resume_child_close_tree(owner, targets).await },
                )
                .await
            {
                failures.push(format!("{error:#}"));
            }
        }
        ensure!(
            failures.is_empty(),
            "child close recovery incomplete: {}",
            failures.join("; ")
        );
        Ok(())
    }
}

impl AgentServices {
    async fn resume_child_close_tree(
        &self,
        owner: StudioThreadAssembler,
        targets: Vec<(usize, pl_protocol::Thread)>,
    ) -> Result<()> {
        let ids = targets
            .iter()
            .map(|(depth, thread)| (*depth, thread.id.clone()))
            .collect::<Vec<_>>();
        let _seals = owner
            .seal_agent_close(&ids, WorkspaceRelease::Preserve)
            .await?;
        let mut failures = Vec::new();
        for (_, thread) in &targets {
            if let Some(handle) = owner.observed_thread(&thread.id) {
                handle.interrupt();
            }
        }
        for (_, thread) in &targets {
            if let Err(error) = self.close_saved_child(&owner, thread).await {
                self.factory
                    .record_child_close_error(&thread.id, &error)
                    .await?;
                failures.push(format!("{}: {error:#}", thread.id));
            }
        }
        for (_, thread) in &targets {
            if self
                .store
                .agent_close(&thread.id)
                .await?
                .is_some_and(|record| record.execution_closed)
            {
                match self.factory.finish_child_worktree_cleanup(thread).await {
                    Ok((_, Some(error))) => {
                        failures.push(format!("{}: {}", thread.id, error.message))
                    }
                    Err(error) => failures.push(format!("{}: {error:#}", thread.id)),
                    Ok((_, None)) => {}
                }
            }
        }
        ensure!(failures.is_empty(), "{}", failures.join("; "));
        Ok(())
    }
}
