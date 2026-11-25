//! Join the original ACP member's resources under its shared cleanup budget.

use std::sync::atomic::Ordering;

use super::{AcpCloseOutcome, AcpResources, HostMcp, Owned};

impl AcpResources {
    /// The join is borrowed in place throughout every await. Cancelling a waiter
    /// cannot take it from this owner; Pending keeps worker and usage for retry.
    pub(crate) async fn close(&self) -> AcpCloseOutcome {
        self.cancel();
        let _gate = self.association_gate.lock().await;
        // Releases only the original observation; SDK cancellation settles pending permissions.
        self.retained_observation.lock().await.take();
        let mut owned = self.owned.lock().await;
        self.close_unpublished_and_title(&mut owned).await;
        self.start_workspace_close(&owned).await;
        let mut host_mcp = self.host_mcp.lock().await;
        self.close_host_transport(&mut owned, &mut host_mcp).await;
        self.join_driver_and_reports(&mut owned).await;
        let workspace_complete = self.join_workspace_close(&mut owned).await;
        if workspace_complete {
            self.close_host_tools(&mut owned, &mut host_mcp).await;
        }
        let local_complete = owned.join.is_none()
            && owned.draft_worktree.is_none()
            && owned.association.is_none()
            && owned.title_join.is_none()
            && owned.report_join.is_none()
            && host_mcp.is_none()
            && workspace_complete;
        let closed_account = if local_complete {
            self.mcp_frontend
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
            let account = owned.account.take();
            owned.usage = None;
            self.obligations.store(false, Ordering::Release);
            account
        } else {
            None
        };
        let outcome = AcpCloseOutcome {
            exit: owned.exit.clone(),
            local_complete,
            driver_error: owned.driver_error.clone(),
        };
        drop(owned);
        if let Some(account) = closed_account {
            account.notify_member_closed();
        }
        outcome
    }

    async fn close_unpublished_and_title(&self, owned: &mut Owned) {
        if let Some(join) = owned.title_join.as_mut()
            && let Ok(result) = tokio::time::timeout_at(self.cleanup.deadline(), join).await
        {
            owned.title_join = None;
            if let Err(error) = result {
                owned.driver_error = Some(format!("ACP title projection failed: {error}"));
            }
        }
        if owned.draft {
            owned.association = None;
            if let Some((factory, id)) = &owned.draft_worktree {
                match factory.preserve_acp_draft_worktree(id).await {
                    Ok(()) => owned.draft_worktree = None,
                    Err(error) => owned.driver_error = Some(error.to_string()),
                }
            }
        }
        // No driver was launched: dropping it settles SDK opened() waiters.
        drop(owned.driver.take());
    }

    async fn start_workspace_close(&self, owned: &Owned) {
        // Begin independent local cleanup before observing the peer's close. A stalled prompt
        // must not consume the shared budget while commands/LSP and the MCP transport sit idle.
        if !owned.workspace_closed
            && let Some(tools) = self.workspace_tools.get()
        {
            let mut closing = self.workspace_close.lock().await;
            if closing.is_none() {
                let tools = tools.clone();
                *closing = Some(tokio::spawn(async move { tools.close().await }));
            }
        }
    }

    async fn close_host_transport(&self, owned: &mut Owned, host_mcp: &mut Option<HostMcp>) {
        if let Some(service) = host_mcp.as_mut() {
            match tokio::time::timeout_at(self.cleanup.deadline(), service.close()).await {
                Ok(Ok(())) => {
                    self.mcp_injected.store(false, Ordering::Release);
                }
                Ok(Err(error)) => {
                    owned.driver_error = Some(error.to_string());
                }
                Err(_) => {
                    owned.driver_error = Some("ACP Host MCP shutdown is pending".into());
                }
            }
        }
    }

    async fn join_driver_and_reports(&self, owned: &mut Owned) {
        if owned.join.is_some() {
            // A failed protocol close must not short-circuit physical reclamation.
            if let Some(session) = self.session.get()
                && let Err(error) = session.close().await
                && !matches!(error, pl_acp::session::Error::Closed)
            {
                owned.driver_error.get_or_insert_with(|| error.to_string());
            }
            let deadline = self.cleanup.deadline();
            if let Some(join) = owned.join.as_mut()
                && let Ok(result) = tokio::time::timeout_at(deadline, join).await
            {
                match result {
                    Ok(exit) => owned.exit = Some(exit),
                    Err(error) => owned.driver_error = Some(error.to_string()),
                }
                owned.join = None;
            }
        }
        if owned.join.is_none() {
            self.join_report(&mut owned.report_join).await;
            // The driver's retained Exit is the same source, including its final legal tail.
            if owned.report_join.is_none()
                && let Some(completed) = owned
                    .exit
                    .as_ref()
                    .and_then(|exit| exit.last_completed.clone())
                && completed.completion_sequence > self.delivered_sequence.load(Ordering::Acquire)
                && let Some(delivery) = self.report_delivery.get()
            {
                owned.report_join = Some(tokio::spawn(Self::deliver_report(
                    delivery.clone(),
                    self.delivered_sequence.clone(),
                    self.delivery_error.clone(),
                    completed,
                )));
                self.join_report(&mut owned.report_join).await;
            }
        }
    }

    async fn join_workspace_close(&self, owned: &mut Owned) -> bool {
        if owned.workspace_closed || self.workspace_tools.get().is_none() {
            return true;
        }
        let mut closing = self.workspace_close.lock().await;
        let join = closing.as_mut().expect("workspace cleanup join");
        let result = if join.is_finished() {
            Some(join.await)
        } else {
            tokio::time::timeout_at(self.cleanup.deadline(), join)
                .await
                .ok()
        };
        let Some(result) = result else {
            owned.driver_error = Some("ACP workspace task cleanup is pending".into());
            return false;
        };
        *closing = None;
        match result
            .map_err(anyhow::Error::from)
            .and_then(|result| result)
        {
            Ok(()) => {
                owned.workspace_closed = true;
                true
            }
            Err(error) => {
                owned.driver_error = Some(error.to_string());
                false
            }
        }
    }

    async fn close_host_tools(&self, owned: &mut Owned, host_mcp: &mut Option<HostMcp>) {
        if let Some(service) = host_mcp.as_ref()
            && service.protocol_closed()
        {
            match tokio::time::timeout_at(self.cleanup.deadline(), service.close_tools()).await {
                Ok(Ok(())) => *host_mcp = None,
                Ok(Err(error)) => owned.driver_error = Some(error.to_string()),
                Err(_) => owned.driver_error = Some("ACP Host tool close remains pending".into()),
            }
        }
    }
}
