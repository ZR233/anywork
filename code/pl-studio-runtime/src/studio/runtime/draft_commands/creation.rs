use super::super::thread_execution::{StudioExecutionSourcePin, StudioThreadExecution};
use super::super::{StudioRuntime, StudioStartNewThreadRequest, StudioSubmitPromptResponse};
use super::lifetime::Lifetime;
use super::registry::Registry;
use crate::studio::agent_host::worktree_lease::WorktreeLease;
use crate::studio::records::ThreadRecord;
use anyhow::Result;
use pl_protocol::studio::{
    BeginThreadCreationRequest, CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport,
    StudioError, StudioErrorCode, SubmitPromptReceipt, ThreadCreationIdentity,
    ThreadCreationOutcome, ThreadCreationResult, ThreadPreparationProgress,
};
use std::future::Future;
use std::sync::{Arc, Mutex, Weak};
use tokio::sync::Notify;
use tokio::sync::watch;

#[derive(Default)]
struct EvidenceState {
    dispatched: bool,
    thread: Option<ThreadRecord>,
    accepted: Option<StudioSubmitPromptResponse>,
    source: Option<Result<Arc<StudioExecutionSourcePin>, StudioError>>,
    rollback_thread: Option<String>,
    rollback_seal: Option<crate::thread_assembler::AgentOperationSeal>,
    rollback_lease: Option<WorktreeLease>,
    cleanup_runtime: Option<StudioRuntime>,
}

/// Written at the actual initialization/acceptance boundaries, never inferred from error codes.
#[derive(Default)]
pub(in crate::studio::runtime) struct CreationEvidence(Mutex<EvidenceState>);

impl CreationEvidence {
    pub(in crate::studio::runtime) fn thread(&self, thread: ThreadRecord) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .thread = Some(thread);
    }
    pub(in crate::studio::runtime) fn capture(
        &self,
        runtime: &StudioRuntime,
        original: &pl_core::thread::ThreadHandle,
    ) {
        let source = runtime
            .capture_execution_source(original)
            .map(Arc::new)
            .map_err(crate::studio_error_from_anyhow);
        let mut state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.source.is_none() {
            state.source = Some(source);
        }
    }
    pub(in crate::studio::runtime) fn dispatching(&self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .dispatched = true;
    }
    pub(in crate::studio::runtime) fn accepted(&self, receipt: &StudioSubmitPromptResponse) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .accepted = Some(receipt.clone());
    }
    pub(in crate::studio::runtime) fn dispatched(&self) -> bool {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .dispatched
    }
    fn confirmed(&self) -> Option<ThreadCreationResult> {
        let state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let receipt = state.accepted.as_ref()?;
        Some(ThreadCreationResult {
            thread: state.thread.clone()?.into(),
            receipt: SubmitPromptReceipt {
                thread_id: receipt.thread_id.clone(),
                input_id: receipt.input_id.clone(),
                cursor: receipt.cursor,
                request_digest: receipt.request_digest.clone(),
            },
        })
    }
    pub(in crate::studio::runtime) async fn compensate(
        &self,
        runtime: &StudioRuntime,
        id: &str,
    ) -> Result<()> {
        // Retain the assembler's original per-Thread admission seal across failed compensation
        // and retry. Otherwise a newly admitted input could be archived by a stale cleanup.
        let operation = runtime.threads.agent_operation(id).await;
        let seal = runtime.threads.seal_agent_operation(id);
        {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.rollback_thread = Some(id.to_owned());
            state.rollback_seal = Some(seal);
            state.cleanup_runtime = Some(runtime.clone());
        }
        drop(operation);
        let result = runtime.compensate_unstarted_thread(id).await;
        if result.is_ok() {
            self.compensated();
        }
        result
    }
    fn compensated(&self) {
        let mut state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.rollback_thread = None;
        state.rollback_seal = None;
    }
    pub(in crate::studio::runtime) async fn preserve(
        &self,
        runtime: &StudioRuntime,
        lease: Option<WorktreeLease>,
        reason: Option<&str>,
    ) {
        let Some(lease) = lease else {
            return;
        };
        {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.rollback_lease = Some(lease.clone());
            state.cleanup_runtime = Some(runtime.clone());
        }
        if runtime
            .preserve_creation_worktree(lease, reason)
            .await
            .is_ok()
        {
            self.0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .rollback_lease = None;
        }
    }
    async fn cleanup(&self) -> Vec<FeedCloseIssue> {
        let (runtime, thread, lease) = {
            let state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (
                state.cleanup_runtime.clone(),
                state.rollback_thread.clone(),
                state.rollback_lease.clone(),
            )
        };
        let mut issues = Vec::new();
        if let Some(runtime) = runtime {
            if let Some(id) = thread {
                if runtime.compensate_unstarted_thread(&id).await.is_ok() {
                    self.compensated();
                } else {
                    issues.push(super::issue(
                        "threadCompensation",
                        "The unpublished input's Thread compensation is unresolved",
                        CleanupRecovery::RetryClose,
                    ));
                }
            }
            if let Some(lease) = lease {
                if runtime
                    .preserve_creation_worktree(lease, Some("Thread creation did not complete"))
                    .await
                    .is_ok()
                {
                    self.0
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .rollback_lease = None;
                } else {
                    issues.push(super::issue(
                        "worktreePreservation",
                        "The original creation worktree lease could not be preserved",
                        CleanupRecovery::RetryClose,
                    ));
                }
            }
        }
        let mut state = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.rollback_thread.is_none() && state.rollback_lease.is_none() {
            state.cleanup_runtime = None;
        }
        issues
    }
}

pub(super) struct CreationOwner {
    pub(super) life: Arc<Lifetime>,
    pub(super) request: BeginThreadCreationRequest,
    evidence: Arc<CreationEvidence>,
    outcome: Mutex<Option<ThreadCreationOutcome>>,
    progress: watch::Sender<(Option<ThreadPreparationProgress>, bool)>,
    progress_owners: Arc<ProgressOwners>,
}

#[derive(Default)]
struct ProgressOwners {
    active: Mutex<u64>,
    changed: Notify,
}
impl ProgressOwners {
    async fn joined(&self) {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if *self
                .active
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                == 0
            {
                return;
            }
            changed.await;
        }
    }
}

#[derive(Clone)]
pub struct StudioThreadCreation(pub(super) Arc<CreationOwner>);

pub struct StudioThreadCreationProgress {
    life: Arc<Lifetime>,
    owners: Arc<ProgressOwners>,
    observed: watch::Receiver<(Option<ThreadPreparationProgress>, bool)>,
}
pub struct StudioCreatedInputExecutionSource {
    owner: Arc<CreationOwner>,
    pin: Arc<StudioExecutionSourcePin>,
    input_id: String,
}

impl CreationOwner {
    pub(super) fn new(
        request: BeginThreadCreationRequest,
        registry: Weak<Mutex<Registry>>,
    ) -> Arc<Self> {
        let (progress, _) = watch::channel((None, false));
        Arc::new(Self {
            life: Lifetime::new(request.operation_id.clone(), registry),
            request,
            evidence: Arc::new(CreationEvidence::default()),
            outcome: Mutex::new(None),
            progress,
            progress_owners: Arc::default(),
        })
    }
    pub(super) async fn run(&self, runtime: StudioRuntime) {
        let result = async {
            let request = self.request.request.clone();
            let mode =
                pl_protocol::ThreadModeId::from_label(request.mode.trim()).map_err(|_| {
                    StudioError::invalid_argument("mode must be an available mode.* id")
                })?;
            let progress = self.progress.clone();
            runtime
                .run_new_thread_creation(
                    StudioStartNewThreadRequest {
                        project_id: self.request.project_id.clone(),
                        title: request.title,
                        input: request.input,
                        mode,
                        route: request.route,
                        delegation_mode: request.delegation_mode,
                        delegation_preference: request.delegation_preference,
                        workspace_mode: request.workspace_mode,
                        options: Default::default(),
                        preparation_observer: Some(Arc::new(move |value| {
                            progress.send_replace((Some(value), false));
                        })),
                    },
                    &self.evidence,
                )
                .await
        }
        .await;
        let outcome = match result {
            Ok(value) => ThreadCreationOutcome::Returned {
                value: Box::new(ThreadCreationResult {
                    thread: value.thread.into(),
                    receipt: SubmitPromptReceipt {
                        thread_id: value.submission.thread_id,
                        input_id: value.submission.input_id,
                        cursor: value.submission.cursor,
                        request_digest: value.submission.request_digest,
                    },
                }),
            },
            Err(error) => match self.evidence.confirmed() {
                Some(value) => ThreadCreationOutcome::Returned {
                    value: Box::new(value),
                },
                None if self.evidence.dispatched() => ThreadCreationOutcome::UnknownOutcome {
                    error: crate::studio_error_from_anyhow(error),
                },
                None => ThreadCreationOutcome::Rejected {
                    error: crate::studio_error_from_anyhow(error),
                },
            },
        };
        *self
            .outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(outcome);
    }
    fn finish_result(&self) -> ThreadCreationOutcome {
        let confirmed = self.evidence.confirmed();
        self.outcome
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get_or_insert_with(|| match confirmed {
                Some(value) => ThreadCreationOutcome::Returned {
                    value: Box::new(value),
                },
                None => ThreadCreationOutcome::UnknownOutcome {
                    error: StudioError::internal(),
                },
            })
            .clone()
    }
    pub(super) fn finish_progress(&self) {
        self.finish_result();
        self.progress.send_modify(|(_, finished)| *finished = true);
    }
    pub(super) fn request_close(&self) {
        self.life.request_close();
        let source = self
            .evidence
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .source
            .clone();
        if let Some(Ok(pin)) = source {
            pin.request_close();
        }
    }
}

impl StudioThreadCreation {
    /// Side-effect-free fact used by HTTP to reap only actually joined Clean owners.
    pub fn is_closed(&self) -> bool {
        self.0.life.is_closed()
    }
    /// Current retained diagnostics only; does not close, retry, dispatch or release anything.
    pub fn close_issues(&self) -> Vec<FeedCloseIssue> {
        self.0.life.issues()
    }
    pub fn matches_request(&self, request: &BeginThreadCreationRequest) -> bool {
        &self.0.request == request
    }
    pub fn identity(&self) -> ThreadCreationIdentity {
        ThreadCreationIdentity {
            operation_id: self.0.life.id.clone(),
            project_id: self.0.request.project_id.clone(),
            input_id: self.0.request.request.input.input_id.clone(),
        }
    }
    pub async fn result(&self) -> ThreadCreationOutcome {
        let joined = self.0.life.join_work().await;
        let outcome = self.0.finish_result();
        if !joined {
            self.0
                .progress
                .send_modify(|(_, finished)| *finished = true);
        }
        outcome
    }
    pub fn subscribe_progress(&self) -> Result<StudioThreadCreationProgress, StudioError> {
        self.0.life.admit(|| {
            let mut active = self
                .0
                .progress_owners
                .active
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            *active = active.checked_add(1).ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Overloaded,
                    "Preparation observation identity exhausted",
                    false,
                )
            })?;
            Ok(StudioThreadCreationProgress {
                life: self.0.life.clone(),
                owners: self.0.progress_owners.clone(),
                observed: self.0.progress.subscribe(),
            })
        })
    }
    pub async fn execution_source(&self) -> Result<StudioCreatedInputExecutionSource, StudioError> {
        self.0.life.admit(|| Ok(()))?;
        let ThreadCreationOutcome::Returned { value } = self.result().await else {
            return Err(StudioError::new(
                StudioErrorCode::Unavailable,
                "Creation has no confirmed input receipt",
                false,
            ));
        };
        self.0.life.admit(|| {
            let state = self
                .0
                .evidence
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let pin = state.source.clone().ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Unavailable,
                    "The original creation execution source was not captured",
                    false,
                )
            })??;
            if pin.thread_id() != value.thread.id
                || value.receipt.thread_id != value.thread.id
                || value.receipt.input_id != self.0.request.request.input.input_id
            {
                return Err(StudioError::new(
                    StudioErrorCode::Protocol,
                    "The original creation source and receipt identities do not match",
                    false,
                ));
            }
            Ok(StudioCreatedInputExecutionSource {
                owner: self.0.clone(),
                pin,
                input_id: value.receipt.input_id,
            })
        })
    }
    pub fn request_close(&self) {
        self.0.request_close();
    }
    async fn finish(&self, retry: bool) -> FeedCloseReport {
        self.request_close();
        let work = self.0.clone();
        let cleanup = self.0.life.close_task(retry, async move {
            work.life.join_work().await;
            // These are real observer leases. A Hyper body or FRB producer must actually release
            // its receiver before the command permit can be returned, not merely see cancel.
            work.progress_owners.joined().await;
            // A source may have arrived after requestClose while the accepted creation continued.
            let source = work
                .evidence
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .source
                .clone();
            let mut issues = work.evidence.cleanup().await;
            if let Some(Ok(pin)) = source {
                pin.request_close();
                if let FeedCloseOutcome::Unresolved { issues: pending } =
                    pin.retry_close().await.outcome
                {
                    issues.extend(pending);
                }
            }
            work.life.replace_cleanup(issues);
        });
        self.0.life.report(cleanup).await
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.finish(false).await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.finish(true).await
    }
}

impl StudioThreadCreationProgress {
    pub fn current(&self) -> Option<ThreadPreparationProgress> {
        self.observed.borrow().0.clone()
    }
    pub async fn changed(&mut self) -> Result<Option<ThreadPreparationProgress>, StudioError> {
        if self.observed.borrow().1 {
            return Ok(None);
        }
        tokio::select! { biased;
            () = self.life.cancel.cancelled() => Err(super::closed()),
            result = self.observed.changed() => {
                result.map_err(|_| StudioError::internal())?;
                let (value, finished) = self.observed.borrow_and_update().clone();
                if finished { Ok(None) } else { Ok(value) }
            }
        }
    }
}
impl Drop for StudioThreadCreationProgress {
    fn drop(&mut self) {
        let mut active = self
            .owners
            .active
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        *active -= 1;
        drop(active);
        self.owners.changed.notify_waiters();
    }
}

impl StudioCreatedInputExecutionSource {
    pub fn thread_id(&self) -> String {
        self.pin.thread_id()
    }
    pub fn input_id(&self) -> String {
        self.input_id.clone()
    }
    pub fn runtime_epoch(&self) -> String {
        self.pin.runtime_epoch()
    }
    pub fn incarnation(&self) -> u64 {
        self.pin.incarnation()
    }
    pub fn open_execution(
        &self,
    ) -> impl Future<Output = Result<StudioThreadExecution>> + Send + 'static + use<> {
        let admitted = self.owner.life.admit(|| Ok(self.pin.open_execution()));
        let life = self.owner.life.clone();
        async move {
            let feed = admitted?.await?;
            if life.admit(|| Ok(())).is_err() {
                let _ = feed.close().await;
                return Err(super::closed().into());
            }
            Ok(feed)
        }
    }
}
