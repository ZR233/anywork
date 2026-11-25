mod close;

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use pl_acp::session::{
    Driver, Exit, Observer, OpenRequest, OpenSetup, Session, SessionTitleUpdate,
};
use tokio::sync::{Mutex, watch};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::studio::WorkspaceUsageLease;
use crate::studio::runtime::acp_accounts::AccountConnection;
use crate::studio::runtime::acp_host_mcp::HostMcp;
use crate::{AcpSessionReference, studio::records::AcpPeerTitle};

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
    pub(crate) driver_error: Option<String>,
}

struct Owned {
    draft: bool,
    draft_worktree: Option<(crate::studio::StudioThreadFactory, String)>,
    driver: Option<Driver>,
    join: Option<JoinHandle<Exit>>,
    exit: Option<Exit>,
    account: Option<Arc<AccountConnection>>,
    usage: Option<WorkspaceUsageLease>,
    driver_error: Option<String>,
    association: Option<Association>,
    title_join: Option<JoinHandle<()>>,
    report_join: Option<JoinHandle<()>>,
    workspace_closed: bool,
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
    initial_configuration: AtomicBool,
    cleanup: pl_acp::auth::CleanupBudget,
    owned: Mutex<Owned>,
    association_gate: Mutex<()>,
    obligations: AtomicBool,
    host_mcp: Mutex<Option<HostMcp>>,
    pub(in crate::studio::runtime) workspace_tools:
        OnceLock<Arc<super::super::acp_workspace_tools::WorkspaceTools>>,
    pub(in crate::studio::runtime) workflow_plan: OnceLock<Arc<super::AcpWorkflowPlanOwner>>,
    workspace_close: Mutex<Option<JoinHandle<Result<()>>>>,
    /// Member lease of the account-cached image; the account retains its own lease until
    /// the entire ACP process tree is joined, independently of this session's service.
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
    pub(crate) fn new(
        workspace_id: String,
        completion: super::AcpSessionCompletion,
        draft: bool,
    ) -> Arc<Self> {
        let cleanup = pl_acp::auth::CleanupBudget::new(Duration::from_secs(5));
        Arc::new(Self {
            instance: NEXT_INSTANCE.fetch_add(1, Ordering::Relaxed),
            generation: uuid::Uuid::new_v4().to_string(),
            workspace_id,
            completion,
            session: OnceLock::new(),
            cancellation: CancellationToken::new(),
            initial_configuration: AtomicBool::new(false),
            cleanup,
            owned: Mutex::new(Owned {
                draft,
                draft_worktree: None,
                driver: None,
                join: None,
                exit: None,
                account: None,
                usage: None,
                driver_error: None,
                association: None,
                title_join: None,
                report_join: None,
                workspace_closed: false,
            }),
            obligations: AtomicBool::new(true),
            association_gate: Mutex::new(()),
            host_mcp: Mutex::new(None),
            workspace_tools: OnceLock::new(),
            workflow_plan: OnceLock::new(),
            workspace_close: Mutex::new(None),
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

    pub(crate) fn begin_initial_configuration(&self) {
        self.initial_configuration.store(true, Ordering::Release);
    }

    pub(crate) fn finish_initial_configuration(&self) {
        self.initial_configuration.store(false, Ordering::Release);
    }

    /// Concurrent send/configure cannot bypass a new child's first-message setup.
    pub(crate) fn ensure_input_ready(&self) -> Result<(), pl_acp::session::Error> {
        if self.cancellation.is_cancelled() {
            return Err(pl_acp::session::Error::Closed);
        }
        if self.initial_configuration.load(Ordering::Acquire) {
            return Err(pl_acp::session::Error::Busy);
        }
        Ok(())
    }

    pub(super) async fn association_published(&self) -> bool {
        let owned = self.owned.lock().await;
        // `draft` ends when commit takes on publication responsibility, not
        // when the write succeeds. A failed write still retains its association.
        !owned.draft && owned.association.is_none()
    }

    /// Order a title directory write against this exact generation's close.
    pub(super) async fn title_update_admission(&self) -> Option<tokio::sync::MutexGuard<'_, ()>> {
        let gate = tokio::select! {
            biased;
            () = self.cancellation.cancelled() => return None,
            gate = self.association_gate.lock() => gate,
        };
        let snapshot = self.session().ok()?.snapshot().await.ok()?;
        (snapshot.ready && !snapshot.closing && !self.cancellation.is_cancelled()).then_some(gate)
    }

    /// Observe only the latest title from the original typed SDK state. The
    /// protocol driver and content observer never await directory publication.
    pub(super) async fn start_title_projection(
        self: &Arc<Self>,
        events: crate::studio::ProductEventBus,
        thread_id: String,
        reference: AcpSessionReference,
        mut changes: watch::Receiver<Option<SessionTitleUpdate>>,
    ) {
        let _gate = self.association_gate.lock().await;
        if self.cancellation.is_cancelled() {
            return;
        }
        let close = self.cancellation.clone();
        let resources = Arc::downgrade(self);
        let mut owned = self.owned.lock().await;
        debug_assert!(
            owned.title_join.is_none(),
            "title projection belongs to one preparation"
        );
        owned.title_join = Some(tokio::spawn(async move {
            loop {
                let update = changes.borrow_and_update().clone();
                if let Some(update) = update {
                    let Some(resources) = resources.upgrade() else {
                        break;
                    };
                    let Some(_gate) = resources.title_update_admission().await else {
                        break;
                    };
                    if resources.association_published().await {
                        events
                            .record_acp_pushed_title(&thread_id, &reference, pushed_title(&update))
                            .await;
                    }
                }
                tokio::select! {
                    biased;
                    () = close.cancelled() => break,
                    result = changes.changed() => if result.is_err() { break; },
                }
            }
        }));
    }

    pub(crate) async fn retain_draft_worktree(
        &self,
        factory: crate::studio::StudioThreadFactory,
        id: String,
    ) {
        self.owned.lock().await.draft_worktree = Some((factory, id));
        self.obligations.store(true, Ordering::Release);
    }

    pub(crate) async fn prepare_host_mcp(
        &self,
        host: crate::thread_assembler::AgentHost,
        caller: crate::AgentId,
        is_root: bool,
        frontend: Option<crate::host_mcp_assets::HostMcpAsset>,
    ) -> Result<OpenSetup> {
        let mut current = self.host_mcp.lock().await;
        ensure!(
            !self.cancellation.is_cancelled() && current.is_none(),
            "ACP Host MCP preparation was closed"
        );
        // Keep partial registrations and transport handles in the original owner even
        // if preparation fails or the waiting future is cancelled.
        *current = Some(HostMcp::pending(host, caller, self.cancellation.clone()));
        let service = current.as_mut().expect("attached Host MCP owner");
        let definition = service
            .launch(
                is_root,
                frontend.as_ref().map(AsRef::as_ref),
                self.workspace_tools.get().cloned(),
                self.workflow_plan.get().cloned(),
            )
            .await?;
        let calls = service.observed_counter();
        *self
            .mcp_frontend
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = frontend;
        self.mcp_calls
            .set(calls)
            .map_err(|_| anyhow::anyhow!("ACP Host MCP metrics already bound"))?;
        self.mcp_injected.store(true, Ordering::Release);
        Ok(OpenSetup {
            mcp_servers: vec![definition],
            allow_once_for_tool: Some(service.permission_filter()),
            instructions: None,
        })
    }

    pub(crate) async fn host_mcp_frontend(&self) -> Result<crate::host_mcp_assets::HostMcpAsset> {
        let account = self
            .owned
            .lock()
            .await
            .account
            .clone()
            .context("ACP account is not attached")?;
        account.frontend().await
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
        self: &Arc<Self>,
        account: Arc<AccountConnection>,
        protocol: pl_acp::connection::Connection,
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
        account.attach(self)?;
        owned.account = Some(account);
        let driver = owned.driver.take().context("ACP driver already consumed")?;
        let cancellation = self.cancellation.clone();
        let session = self.session()?.clone();
        owned.join = Some(tokio::spawn(async move {
            let drive = driver.run(protocol);
            tokio::pin!(drive);
            tokio::select! {
                result = &mut drive => result,
                () = cancellation.cancelled() => {
                    // Keep polling the original driver while admitting its own close command.
                    let close = session.close();
                    tokio::pin!(close);
                    tokio::select! { result = &mut drive => return result, _ = &mut close => {} }
                    drive.await
                }
            }
        }));
        Ok(())
    }

    pub(crate) fn cancel(&self) {
        self.cancellation.cancel();
        if let Some(tools) = self.workspace_tools.get() {
            tools.stop();
        }
    }

    pub(in crate::studio::runtime) async fn retain_workspace_tools(
        &self,
        tools: Arc<super::super::acp_workspace_tools::WorkspaceTools>,
        usage: WorkspaceUsageLease,
    ) -> Result<()> {
        let mut owned = self.owned.lock().await;
        ensure!(
            !self.cancellation.is_cancelled(),
            "ACP workspace preparation closed"
        );
        self.workspace_tools
            .set(tools)
            .map_err(|_| anyhow::anyhow!("ACP tools already prepared"))?;
        owned.usage = Some(usage);
        self.obligations.store(true, Ordering::Release);
        Ok(())
    }

    pub(in crate::studio::runtime) fn retain_workflow_plan(
        &self,
        owner: Arc<super::AcpWorkflowPlanOwner>,
    ) -> Result<()> {
        ensure!(
            !self.cancellation.is_cancelled(),
            "ACP workflow preparation closed"
        );
        self.workflow_plan
            .set(owner)
            .map_err(|_| anyhow::anyhow!("ACP workflow plan owner already prepared"))?;
        Ok(())
    }

    pub(in crate::studio::runtime) fn workflow_snapshot(
        &self,
    ) -> Option<crate::protocol::AcpWorkflowStateSnapshot> {
        self.workflow_plan.get().map(|wp| wp.snapshot())
    }

    pub(in crate::studio::runtime) fn subscribe_workflow(
        &self,
    ) -> Option<watch::Receiver<Option<crate::protocol::AcpWorkflowStateSnapshot>>> {
        self.workflow_plan.get().map(|wp| wp.subscribe())
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
        let _gate = self.association_gate.lock().await;
        if self.owned.lock().await.draft {
            return Ok(());
        }
        self.publish_association(events).await
    }

    /// Explicit first-submission boundary; ordinary shutdown never publishes an unused draft.
    pub(super) async fn commit_draft(
        &self,
        events: &crate::studio::ProductEventBus,
        first_prompt_text: &str,
    ) -> Result<()> {
        let _gate = self.association_gate.lock().await;
        ensure!(!self.cancellation.is_cancelled(), "ACP draft is closed");
        {
            let mut owned = self.owned.lock().await;
            if owned.draft {
                let association = owned
                    .association
                    .as_mut()
                    .context("ACP draft association is missing")?;
                association.session.title =
                    super::super::thread_title::provisional_title(first_prompt_text);
                // Freeze the title before the first publication attempt, including
                // when an unsuccessful commit must settle this same association later.
                owned.draft = false;
            }
        }
        self.publish_association(events).await
    }

    async fn publish_association(&self, events: &crate::studio::ProductEventBus) -> Result<()> {
        let association = self.owned.lock().await.association.clone();
        if let Some(Association {
            mut session,
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
                // A draft may receive its peer title before the user sends any input.
                // The first directory cut can carry it without opening a second observer.
                if !self.cancellation.is_cancelled()
                    && let Ok(sdk) = self.session()
                    && let Some(update) = sdk.title_changes().borrow().as_ref()
                    && let Some(metadata) = session.acp_title.as_mut()
                {
                    metadata.peer = Some(pushed_title(update));
                }
                events
                    .commit_directory(crate::studio::store::directory::DirectoryDelta {
                        session_upserts: vec![session],
                        agent_upserts: vec![agent],
                        ..Default::default()
                    })
                    .await?;
            }
            let mut owned = self.owned.lock().await;
            owned.association = None;
            if let Some((factory, id)) = owned.draft_worktree.take() {
                factory.complete_acp_draft_worktree(&id);
            }
        }
        Ok(())
    }

    pub(crate) async fn outcome(&self) -> AcpCloseOutcome {
        let owned = self.owned.lock().await;
        AcpCloseOutcome {
            exit: owned.exit.clone(),
            local_complete: !self.has_obligations(),
            driver_error: owned.driver_error.clone(),
        }
    }
}

fn pushed_title(update: &SessionTitleUpdate) -> AcpPeerTitle {
    let title = match update {
        SessionTitleUpdate::Clear => None,
        SessionTitleUpdate::Set(title) => {
            let title = title.trim();
            (!title.is_empty()).then(|| title.to_owned())
        }
    };
    AcpPeerTitle::Pushed { title }
}

impl Drop for AcpResources {
    fn drop(&mut self) {
        self.cancel();
        // Final cancellation fence only. Normal close always joins in place above.
        if let Some(join) = &self.owned.get_mut().join {
            join.abort();
        }
        if let Some(report) = &self.owned.get_mut().report_join {
            report.abort();
        }
        if let Some(title) = &self.owned.get_mut().title_join {
            title.abort();
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
            false,
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
