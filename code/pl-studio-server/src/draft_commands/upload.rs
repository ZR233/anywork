//! One original multipart body, under the existing normal-request permit. No new semaphore.
use super::registry::{DraftCommands, Entry, UploadPermit, closed, conflict, issue, validate_id};
use axum::extract::{FromRequest, Multipart, Request};
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_protocol::studio::{
    AttachmentAdmissionIdentity, AttachmentAdmissionOutcome, CleanupRecovery, FeedCloseIssue,
    FeedCloseOutcome, FeedCloseReport, StudioError,
};
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::draft_commands::StudioAttachmentAdmission;
use std::sync::{Arc, Mutex};
use tokio::sync::OwnedSemaphorePermit;
use tokio::task::JoinHandle;

#[derive(Clone, Debug)]
enum TaskFailure {
    Join(Arc<tokio::task::JoinError>),
    MissingCompletion,
}
type Completion = Shared<BoxFuture<'static, Result<(), TaskFailure>>>;
struct Cleanup {
    task: Completion,
}
struct Failure {
    // The wire diagnostic is redacted; the original actual task failure remains owned here.
    _cause: TaskFailure,
    issue: FeedCloseIssue,
}

struct State {
    closing: bool,
    task: Option<Completion>,
    cleanup: Option<Arc<Cleanup>>,
    directory: Option<std::path::PathBuf>,
    native: Option<StudioAttachmentAdmission>,
    outcome: Option<AttachmentAdmissionOutcome>,
    issues: Vec<FeedCloseIssue>,
    native_issues: Vec<FeedCloseIssue>,
    body_failure: Option<Failure>,
    cleanup_failure: Option<Failure>,
    released: bool,
    permit: Option<OwnedSemaphorePermit>,
}
pub(super) struct Upload {
    id: String,
    state: Mutex<State>,
    registry: std::sync::Weak<DraftCommands>,
}

impl DraftCommands {
    pub(super) fn begin_upload(
        self: &Arc<Self>,
        runtime: StudioRuntime,
        id: String,
        permit: UploadPermit,
        body: Request,
    ) -> anyhow::Result<Arc<Upload>> {
        validate_id(&id)?;
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.reap();
        if registry.entries.contains_key(&id) {
            return Err(conflict().into());
        }
        if registry.sealed {
            return Err(closed().into());
        }
        // Never consume a second body to guess equality. A native command also owns its ID;
        // conflict here is rejection of this HTTP request, not the old command's outcome.
        if runtime.find_attachment_admission(id.clone())?.is_some() {
            return Err(conflict().into());
        }
        let permit = permit
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
            .ok_or_else(StudioError::internal)?;
        let owner = Arc::new(Upload {
            id: id.clone(),
            registry: Arc::downgrade(self),
            state: Mutex::new(State {
                closing: false,
                task: None,
                cleanup: None,
                directory: None,
                native: None,
                outcome: None,
                issues: Vec::new(),
                native_issues: Vec::new(),
                body_failure: None,
                cleanup_failure: None,
                released: false,
                permit: Some(permit),
            }),
        });
        registry.entries.insert(id, Entry::Upload(owner.clone()));
        let work = owner.clone();
        let task = tokio::spawn(async move {
            work.run(runtime, body).await;
        });
        owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(retain(task));
        Ok(owner)
    }
}

impl Upload {
    pub(super) fn identity(&self) -> AttachmentAdmissionIdentity {
        AttachmentAdmissionIdentity {
            operation_id: self.id.clone(),
        }
    }

    async fn run(&self, runtime: StudioRuntime, body: Request) {
        // Even boundary validation belongs to the registered owner. A duplicate upload ID
        // therefore conflicts before extracting or polling any part of the new request body.
        let staged = match Multipart::from_request(body, &()).await {
            Ok(body) => super::staging::stage(self, &runtime, body).await,
            Err(_) => Err(StudioError::invalid_argument(
                "invalid multipart attachment admission body",
            )
            .into()),
        };
        let outcome = match staged {
            Ok(request) => match runtime.begin_attachment_admission(self.id.clone(), request) {
                Ok(job) => {
                    let closing = {
                        let mut state = self
                            .state
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner);
                        state.native = Some(job.clone());
                        state.closing
                    };
                    if closing {
                        job.request_close();
                    }
                    let outcome = job.result().await;
                    let native_issues = match job.close().await.outcome {
                        FeedCloseOutcome::Clean => Vec::new(),
                        FeedCloseOutcome::Unresolved { issues } => issues,
                    };
                    self.state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .native_issues = native_issues;
                    outcome
                }
                Err(error) => AttachmentAdmissionOutcome::Rejected {
                    error: pl_studio_runtime::studio_error_from_anyhow(error),
                },
            },
            Err(error) => AttachmentAdmissionOutcome::Rejected {
                error: pl_studio_runtime::studio_error_from_anyhow(error),
            },
        };
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .outcome = Some(outcome);
        // The original native task/file use has joined before host paths can be removed.
        let native_clean = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .native_issues
            .is_empty();
        if native_clean {
            self.cleanup_directory().await;
        }
    }

    pub(super) fn install_directory(&self, directory: tempfile::TempDir) {
        // Transfer out of TempDir's best-effort Drop. Only this owner performs explicit,
        // fallible deletion, including when the original body or a cleanup worker faults.
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .directory = Some(directory.keep());
    }

    pub(super) fn directory(&self) -> Result<std::path::PathBuf, StudioError> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .directory
            .clone()
            .ok_or_else(StudioError::internal)
    }

    async fn join_body(&self) -> bool {
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        if let Some(task) = task
            && let Err(cause) = task.await
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .body_failure
                .get_or_insert_with(|| failure(cause, "uploadBodyJoinError"));
            return false;
        }
        true
    }

    pub(super) async fn result(&self) -> AttachmentAdmissionOutcome {
        self.join_body().await;
        let (outcome, native) = {
            let state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (state.outcome.clone(), state.native.clone())
        };
        if let Some(outcome) = outcome {
            return outcome;
        }
        // A host fault after native registration cannot revoke the original native result.
        let outcome = if let Some(native) = native {
            native.result().await
        } else {
            AttachmentAdmissionOutcome::UnknownOutcome {
                error: StudioError::internal(),
            }
        };
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .outcome
            .get_or_insert(outcome)
            .clone()
    }

    pub(super) fn request_close(&self) {
        let native = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            state.native.clone()
        };
        if let Some(native) = native {
            native.request_close();
        }
    }

    async fn cleanup_directory(&self) {
        let path = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .directory
            .clone();
        let Some(path) = path else {
            return;
        };
        let result = tokio::fs::remove_dir_all(path).await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        match result {
            Ok(()) => {
                state.directory = None;
                state.issues.clear();
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                state.directory = None;
                state.issues.clear();
            }
            Err(_) => {
                if state.issues.is_empty() {
                    state.issues.push(issue(
                        "uploadStagingCleanup",
                        "The original upload staging directory could not be removed",
                        CleanupRecovery::RetryClose,
                    ));
                }
            }
        }
    }

    pub(super) async fn close(self: &Arc<Self>, retry: bool) -> FeedCloseReport {
        self.request_close();
        let mut task = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match &state.cleanup {
                Some(task)
                    if !retry || task.task.clone().now_or_never().is_none() || state.released =>
                {
                    task.clone()
                }
                _ => {
                    let work = self.clone();
                    let joined = self.clone();
                    let task = tokio::spawn(async move {
                        let body_joined = work.join_body().await;
                        let native = work
                            .state
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .native
                            .clone();
                        let native_issues = if let Some(native) = native {
                            match native.retry_close().await.outcome {
                                FeedCloseOutcome::Clean => Vec::new(),
                                FeedCloseOutcome::Unresolved { issues } => issues,
                            }
                        } else {
                            Vec::new()
                        };
                        let native_clean = native_issues.is_empty();
                        work.state
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .native_issues = native_issues;
                        // A failed host worker may have dropped an outstanding file IO future.
                        // Retain its directory/terminal issue rather than claim a safe deletion.
                        if native_clean && body_joined {
                            work.cleanup_directory().await;
                        }
                    });
                    let task = Arc::new(Cleanup {
                        task: retain_with_join(task, move |result| {
                            let release = {
                                let mut state = joined
                                    .state
                                    .lock()
                                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                                if let Err(cause) = result {
                                    state.cleanup_failure.get_or_insert_with(|| {
                                        failure(cause, "uploadCleanupJoinError")
                                    });
                                }
                                if !state.released
                                    && state.body_failure.is_none()
                                    && state.cleanup_failure.is_none()
                                    && state.issues.is_empty()
                                    && state.native_issues.is_empty()
                                    && state.directory.is_none()
                                {
                                    state.released = true;
                                    state.permit.take();
                                    true
                                } else {
                                    false
                                }
                            };
                            if release && let Some(registry) = joined.registry.upgrade() {
                                registry.remove(&joined.id);
                            }
                        }),
                    });
                    state.cleanup = Some(task.clone());
                    task
                }
            }
        };
        loop {
            if let Err(cause) = task.task.clone().await {
                self.state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .cleanup_failure
                    .get_or_insert_with(|| failure(cause, "uploadCleanupJoinError"));
            }
            let next = {
                let state = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                match &state.cleanup {
                    Some(next) if !Arc::ptr_eq(next, &task) => next.clone(),
                    _ => {
                        let issues = state_issues(&state);
                        return FeedCloseReport {
                            feed_id: self.id.clone(),
                            outcome: if issues.is_empty() {
                                FeedCloseOutcome::Clean
                            } else {
                                FeedCloseOutcome::Unresolved { issues }
                            },
                        };
                    }
                }
            };
            task = next;
        }
    }

    pub(super) fn close_issues(&self) -> Vec<FeedCloseIssue> {
        let (mut issues, native) = {
            let state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (state_issues(&state), state.native.clone())
        };
        if let Some(native) = native {
            for issue in native.close_issues() {
                if !issues.contains(&issue) {
                    issues.push(issue);
                }
            }
        }
        issues
    }
}

fn state_issues(state: &State) -> Vec<FeedCloseIssue> {
    let mut issues = state.issues.clone();
    issues.extend(state.native_issues.clone());
    if let Some(failure) = &state.body_failure {
        issues.push(failure.issue.clone());
    }
    if let Some(failure) = &state.cleanup_failure {
        issues.push(failure.issue.clone());
    }
    issues
}

fn failure(cause: TaskFailure, code: &str) -> Failure {
    let message = match &cause {
        TaskFailure::Join(error) if error.is_panic() => {
            "An original upload body/cleanup worker panicked"
        }
        TaskFailure::Join(_) | TaskFailure::MissingCompletion => {
            "An original upload body/cleanup worker did not join successfully"
        }
    };
    Failure {
        _cause: cause,
        issue: issue(code, message, CleanupRecovery::Terminal),
    }
}

fn retain(task: JoinHandle<()>) -> Completion {
    retain_with_join(task, |_| {})
}
fn retain_with_join(
    task: JoinHandle<()>,
    joined: impl FnOnce(Result<(), TaskFailure>) + Send + 'static,
) -> Completion {
    let (published, observed) = tokio::sync::oneshot::channel();
    tokio::spawn(async move {
        let result = task
            .await
            .map_err(|error| TaskFailure::Join(Arc::new(error)));
        joined(result.clone());
        let _ = published.send(result);
    });
    async move {
        observed
            .await
            .unwrap_or(Err(TaskFailure::MissingCompletion))
    }
    .boxed()
    .shared()
}
