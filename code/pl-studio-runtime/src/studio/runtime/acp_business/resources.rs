use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use pl_acp::session::{Driver, Exit, Observer, OpenRequest, Session};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::studio::WorkspaceUsageLease;
use crate::studio::runtime::acp_host_mcp::HostMcp;
use crate::studio::runtime::acp_worker::{AcpSpawnRequest, AcpWorker, Reclaim};
use pl_remote_helper::Executor;

/// A thin delivery into the original parent's inbox, bound by the Session owner.
pub(crate) type AcpReportDelivery = Arc<
    dyn Fn(
            pl_acp::session::Completed,
        ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<()>> + Send>>
        + Send
        + Sync,
>;

static NEXT_INSTANCE: AtomicU64 = AtomicU64::new(1);

/// Exact local reclamation facts, independent of the peer's history or close capability.
#[derive(Debug, Clone)]
pub(crate) struct AcpCloseOutcome {
    pub(crate) exit: Option<Exit>,
    pub(crate) local_complete: bool,
    pub(crate) worker_error: Option<String>,
    pub(crate) driver_error: Option<String>,
}

struct Owned {
    driver: Option<Driver>,
    join: Option<JoinHandle<Exit>>,
    exit: Option<Exit>,
    worker: Option<AcpWorker>,
    reclaim: Option<JoinHandle<(AcpWorker, Reclaim)>>,
    reclaim_failed: bool,
    usage: Option<WorkspaceUsageLease>,
    worker_error: Option<String>,
    driver_error: Option<String>,
    association: Option<Association>,
    report_join: Option<JoinHandle<()>>,
}

#[derive(Clone)]
struct Association {
    session: crate::studio::records::SessionDirectoryRecord,
    agent: crate::studio::records::AgentDirectoryRecord,
    baseline: Option<(
        crate::studio::records::SessionDirectoryRecord,
        crate::studio::records::AgentDirectoryRecord,
    )>,
}

/// The actual ACP branch, allocated and registered before launch starts.
/// No protocol updates or transcript are copied into this owner.
pub(crate) struct AcpResources {
    pub(crate) instance: u64,
    /// Non-repeating source identity for durable reports and opaque cursors across host restarts.
    pub(crate) generation: String,
    pub(crate) workspace_id: String,
    pub(crate) completion: super::AcpSessionCompletion,
    session: OnceLock<Session>,
    pub(crate) cancellation: CancellationToken,
    cleanup: pl_acp::auth::CleanupBudget,
    owned: Mutex<Owned>,
    obligations: AtomicBool,
    host_mcp: Mutex<Option<HostMcp>>,
    /// Kept independently of the HTTP listener until the entire ACP process tree is joined.
    mcp_frontend: std::sync::Mutex<Option<crate::host_mcp_assets::HostMcpAsset>>,
    mcp_injected: AtomicBool,
    mcp_calls: OnceLock<Arc<AtomicU64>>,
    report_delivery: OnceLock<AcpReportDelivery>,
    delivered_sequence: Arc<AtomicU64>,
    delivery_error: Arc<std::sync::Mutex<Option<String>>>,
    retained_observation: Mutex<Option<Observer>>,
}

impl std::fmt::Debug for AcpResources {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AcpResources")
            .field("instance", &self.instance)
            .finish_non_exhaustive()
    }
}

impl AcpResources {
    pub(crate) fn new(workspace_id: String, completion: super::AcpSessionCompletion) -> Arc<Self> {
        let cleanup = pl_acp::auth::CleanupBudget::new(Duration::from_secs(5));
        Arc::new(Self {
            instance: NEXT_INSTANCE.fetch_add(1, Ordering::Relaxed),
            generation: uuid::Uuid::new_v4().to_string(),
            workspace_id,
            completion,
            session: OnceLock::new(),
            cancellation: CancellationToken::new(),
            cleanup,
            owned: Mutex::new(Owned {
                driver: None,
                join: None,
                exit: None,
                worker: None,
                reclaim: None,
                reclaim_failed: false,
                usage: None,
                worker_error: None,
                driver_error: None,
                association: None,
                report_join: None,
            }),
            obligations: AtomicBool::new(true),
            host_mcp: Mutex::new(None),
            mcp_frontend: std::sync::Mutex::new(None),
            mcp_injected: AtomicBool::new(false),
            mcp_calls: OnceLock::new(),
            report_delivery: OnceLock::new(),
            delivered_sequence: Arc::new(AtomicU64::new(0)),
            delivery_error: Arc::new(std::sync::Mutex::new(None)),
            retained_observation: Mutex::new(None),
        })
    }

    pub(crate) fn session(&self) -> Result<&Session> {
        self.session.get().context("ACP process is not initialized")
    }

    pub(crate) async fn prepare_host_mcp(
        &self,
        host: crate::thread_assembler::AgentHost,
        caller: pl_protocol::AgentId,
        is_root: bool,
        frontend: Option<crate::host_mcp_assets::HostMcpAsset>,
    ) -> Result<pl_acp::session::schema::McpServer> {
        let mut current = self.host_mcp.lock().await;
        ensure!(
            !self.cancellation.is_cancelled() && current.is_none(),
            "ACP Host MCP preparation was closed"
        );
        // No await occurs between server creation and transfer to its registered owner.
        let (service, definition) = HostMcp::start(
            host,
            caller,
            self.cancellation.clone(),
            is_root,
            frontend.as_ref().map(AsRef::as_ref),
        )
        .await?;
        let calls = service.observed_counter();
        *current = Some(service);
        *self
            .mcp_frontend
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = frontend;
        self.mcp_calls
            .set(calls)
            .map_err(|_| anyhow::anyhow!("ACP Host MCP metrics already bound"))?;
        self.mcp_injected.store(true, Ordering::Release);
        Ok(definition)
    }

    pub(crate) fn delivery_error(&self) -> Option<String> {
        self.delivery_error
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }

    pub(crate) async fn host_mcp_status(&self) -> serde_json::Value {
        serde_json::json!({
            "injected": self.mcp_injected.load(Ordering::Acquire),
            "observedToolCalls": self.mcp_calls.get().map_or(0, |calls| calls.load(Ordering::Acquire)),
        })
    }

    /// Keep the original bounded SDK window for a child opened later by the UI.
    /// No transcript is copied; overflow keeps the SDK's honest Gap semantics.
    pub(crate) async fn retain_observer(&self, observer: Observer) -> Result<()> {
        let mut current = self.retained_observation.lock().await;
        ensure!(
            current.is_none() && !self.cancellation.is_cancelled(),
            "ACP observation is already bound or closed"
        );
        *current = Some(observer);
        Ok(())
    }

    pub(crate) async fn take_observation(&self) -> Option<Observer> {
        self.retained_observation.lock().await.take()
    }

    async fn deliver(&self, completed: pl_acp::session::Completed) {
        let Some(delivery) = self.report_delivery.get() else {
            return;
        };
        Self::deliver_report(
            delivery.clone(),
            self.delivered_sequence.clone(),
            self.delivery_error.clone(),
            completed,
        )
        .await;
    }

    async fn deliver_report(
        delivery: AcpReportDelivery,
        delivered_sequence: Arc<AtomicU64>,
        delivery_error: Arc<std::sync::Mutex<Option<String>>>,
        completed: pl_acp::session::Completed,
    ) {
        let sequence = completed.completion_sequence;
        if delivered_sequence.fetch_max(sequence, Ordering::AcqRel) >= sequence {
            return;
        }
        let error = delivery(completed)
            .await
            .err()
            .map(|error| error.to_string());
        *delivery_error
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = error;
    }

    async fn join_report(&self, report: &mut Option<JoinHandle<()>>) {
        if let Some(join) = report.as_mut()
            && let Ok(result) = tokio::time::timeout_at(self.cleanup.deadline(), join).await
        {
            *report = None;
            if let Err(error) = result {
                *self
                    .delivery_error
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) =
                    Some(format!("ACP report task failed: {error}"));
            }
        }
    }

    /// Observes original completion positions, never the UI's content stream.
    pub(crate) async fn start_result_delivery(
        self: &Arc<Self>,
        delivery: AcpReportDelivery,
    ) -> Result<()> {
        self.report_delivery
            .set(delivery)
            .map_err(|_| anyhow::anyhow!("ACP report delivery already bound"))?;
        let session = self.session()?.clone();
        let mut changes = session.completion_changes();
        let resources = Arc::downgrade(self);
        let mut owned = self.owned.lock().await;
        owned.report_join = Some(tokio::spawn(async move {
            loop {
                if let Ok(snapshot) = session.snapshot().await
                    && let Some(completed) = snapshot.last_completed
                    && let Some(resources) = resources.upgrade()
                {
                    resources.deliver(completed).await;
                }
                if changes.changed().await.is_err() {
                    break;
                }
            }
        }));
        Ok(())
    }

    pub(crate) async fn observe(&self, mut request: OpenRequest) -> Result<Observer> {
        let mut owned = self.owned.lock().await;
        ensure!(
            self.session.get().is_none(),
            "ACP preparation already initialized"
        );
        request.cleanup = self.cleanup.clone();
        let (session, observer, driver) = pl_acp::session::channel(request);
        self.session
            .set(session)
            .map_err(|_| anyhow::anyhow!("ACP preparation already initialized"))?;
        owned.driver = Some(driver);
        Ok(observer)
    }

    /// Called only by the already registered preparation task. Never race spawn
    /// against cancellation by dropping its future: every returned worker is retained.
    pub(super) async fn start(
        &self,
        launch: AcpSpawnRequest,
        workers: &Executor,
        usage: WorkspaceUsageLease,
    ) -> Result<()> {
        let mut owned = self.owned.lock().await;
        ensure!(
            owned.driver.is_some() && owned.join.is_none(),
            "ACP preparation already started"
        );
        owned.usage = Some(usage);
        ensure!(
            !self.cancellation.is_cancelled(),
            "ACP preparation cancelled"
        );
        let worker = AcpWorker::spawn(launch, workers, &self.cancellation)
            .await
            .map_err(|_| anyhow::anyhow!("ACP business process launch failed"))?;
        owned.worker = Some(worker);
        let (writer, reader) = owned
            .worker
            .as_mut()
            .and_then(AcpWorker::take_streams)
            .context("ACP business process has no streams")?;
        let driver = owned.driver.take().context("ACP driver already consumed")?;
        owned.join = Some(tokio::spawn(driver.run(writer, reader)));
        Ok(())
    }

    pub(crate) fn cancel(&self) {
        self.cancellation.cancel();
    }

    pub(crate) fn has_obligations(&self) -> bool {
        self.obligations.load(Ordering::Acquire)
    }

    pub(super) async fn retain_association(
        &self,
        session: crate::studio::records::SessionDirectoryRecord,
        agent: crate::studio::records::AgentDirectoryRecord,
        baseline: Option<(
            crate::studio::records::SessionDirectoryRecord,
            crate::studio::records::AgentDirectoryRecord,
        )>,
    ) {
        let mut owned = self.owned.lock().await;
        owned.association = Some(Association {
            session,
            agent,
            baseline,
        });
        self.obligations.store(true, Ordering::Release);
    }

    pub(crate) async fn settle_association(
        &self,
        events: &crate::studio::ProductEventBus,
    ) -> Result<()> {
        let association = self.owned.lock().await.association.clone();
        if let Some(Association {
            session,
            agent,
            baseline,
        }) = association
        {
            if agent.parent_agent_id.is_some() {
                if let Some((_, agent_base)) = baseline {
                    events.commit_agent_update(agent_base, agent).await?;
                } else {
                    events
                        .commit_directory(crate::studio::store::directory::DirectoryDelta {
                            agent_upserts: vec![agent],
                            ..Default::default()
                        })
                        .await?;
                }
            } else if let Some((session_base, agent_base)) = baseline {
                events.commit_session_update(session_base, session).await?;
                events.commit_agent_update(agent_base, agent).await?;
            } else {
                events
                    .commit_directory(crate::studio::store::directory::DirectoryDelta {
                        session_upserts: vec![session],
                        agent_upserts: vec![agent],
                        ..Default::default()
                    })
                    .await?;
            }
            self.owned.lock().await.association = None;
        }
        Ok(())
    }

    pub(crate) async fn outcome(&self) -> AcpCloseOutcome {
        let owned = self.owned.lock().await;
        AcpCloseOutcome {
            exit: owned.exit.clone(),
            local_complete: !self.has_obligations(),
            worker_error: owned.worker_error.clone(),
            driver_error: owned.driver_error.clone(),
        }
    }

    /// The join is borrowed in place throughout every await. Cancelling a waiter
    /// cannot take it from this owner; Pending keeps worker and usage for retry.
    pub(crate) async fn close(&self) -> AcpCloseOutcome {
        self.cancel();
        // Releases only the original observation; SDK cancellation settles pending permissions.
        self.retained_observation.lock().await.take();
        let mut owned = self.owned.lock().await;
        // No driver was launched: dropping it settles SDK opened() waiters.
        drop(owned.driver.take());
        if owned.join.is_some() {
            // A failed protocol close must not short-circuit physical reclamation.
            if let Some(session) = self.session.get()
                && let Err(error) = session.close().await
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
        // Reclamation must keep progressing after the shared deadline or a caller's
        // cancellation. Retrying an expired timeout around a newly created future
        // can repeatedly cancel the supervisor's wait before it drains its exit.
        if owned.reclaim.is_none()
            && let Some(mut worker) = owned.worker.take()
        {
            owned.reclaim = Some(tokio::spawn(async move {
                let result = worker.reclaim().await;
                (worker, result)
            }));
        }
        if let Some(reclaim) = owned.reclaim.as_mut() {
            match tokio::time::timeout_at(self.cleanup.deadline(), reclaim).await {
                Ok(Ok((_, Reclaim::Stopped))) => {
                    owned.reclaim = None;
                    owned.worker_error = None;
                }
                Ok(Ok((_, Reclaim::Settled(error)))) => {
                    owned.reclaim = None;
                    owned.worker_error = Some(error);
                }
                Ok(Ok((worker, Reclaim::Pending(error)))) => {
                    owned.reclaim = None;
                    owned.worker = Some(worker);
                    owned.worker_error = Some(error);
                }
                Ok(Err(error)) => {
                    owned.reclaim = None;
                    owned.reclaim_failed = true;
                    owned.worker_error = Some(error.to_string());
                }
                Err(_) => {
                    owned.worker_error = Some("ACP process reclamation is pending".into());
                }
            }
        }
        // Reclaimed IO can finish a driver whose graceful deadline elapsed.
        if owned.join.as_ref().is_some_and(JoinHandle::is_finished) {
            match owned.join.as_mut().expect("checked join").await {
                Ok(exit) => owned.exit = Some(exit),
                Err(error) => owned.driver_error = Some(error.to_string()),
            }
            owned.join = None;
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
        let mut host_mcp = self.host_mcp.lock().await;
        if let Some(service) = host_mcp.as_mut() {
            match tokio::time::timeout_at(self.cleanup.deadline(), service.close()).await {
                Ok(Ok(())) => {
                    *host_mcp = None;
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
        let local_complete = owned.worker.is_none()
            && owned.reclaim.is_none()
            && !owned.reclaim_failed
            && owned.join.is_none()
            && owned.association.is_none()
            && owned.report_join.is_none()
            && host_mcp.is_none();
        if local_complete {
            self.mcp_frontend
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take();
            owned.usage = None;
            self.obligations.store(false, Ordering::Release);
        }
        AcpCloseOutcome {
            exit: owned.exit.clone(),
            local_complete,
            worker_error: owned.worker_error.clone(),
            driver_error: owned.driver_error.clone(),
        }
    }
}

impl Drop for AcpResources {
    fn drop(&mut self) {
        self.cancellation.cancel();
        // Final cancellation fence only. Normal close always joins in place above.
        if let Some(join) = &self.owned.get_mut().join {
            join.abort();
        }
        if let Some(reclaim) = &self.owned.get_mut().reclaim {
            reclaim.abort();
        }
        if let Some(report) = &self.owned.get_mut().report_join {
            report.abort();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn mcp_status_does_not_wait_for_another_close_slot() {
        let (_, publication) = tokio::sync::watch::channel(Some(Ok(())));
        let resources = AcpResources::new(
            "status-workspace".into(),
            super::super::AcpSessionCompletion { publication },
        );
        let calls = Arc::new(AtomicU64::new(7));
        resources.mcp_calls.set(calls.clone()).unwrap();
        resources.mcp_injected.store(true, Ordering::Release);
        let _closing_slot = resources.host_mcp.lock().await;
        let status = tokio::time::timeout(Duration::from_millis(100), resources.host_mcp_status())
            .await
            .expect("status must not wait for the HTTP shutdown slot");
        assert_eq!(status["observedToolCalls"], 7);
        calls.store(8, Ordering::Release);
        let status = resources.host_mcp_status().await;
        assert_eq!(
            status["observedToolCalls"], 8,
            "read the original counter, not a copied snapshot"
        );
    }
}
