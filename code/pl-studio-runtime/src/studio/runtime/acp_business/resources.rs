use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use pl_acp::session::{Driver, Exit, Observer, OpenRequest, Session};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::studio::WorkspaceUsageLease;
use crate::studio::runtime::acp_worker::{AcpSpawnRequest, AcpWorker, Reclaim};
use pl_remote_helper::Executor;

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
    pub(crate) workspace_id: String,
    pub(crate) completion: super::AcpSessionCompletion,
    session: OnceLock<Session>,
    pub(crate) cancellation: CancellationToken,
    cleanup: pl_acp::auth::CleanupBudget,
    owned: Mutex<Owned>,
    obligations: AtomicBool,
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
            }),
            obligations: AtomicBool::new(true),
        })
    }

    pub(crate) fn session(&self) -> Result<&Session> {
        self.session.get().context("ACP process is not initialized")
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
            if let Some((session_base, agent_base)) = baseline {
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
        let local_complete = owned.worker.is_none()
            && owned.reclaim.is_none()
            && !owned.reclaim_failed
            && owned.join.is_none()
            && owned.association.is_none();
        if local_complete {
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
    }
}
