//! Runs the platform protocol and hands completed credentials to the serial owner.
use super::invalidate_waiting;
use crate::bots::credentials::{CredentialCommit, CredentialDecision};
use crate::bots::operation::{DiagnosticSlot, RegistrationSave};
use crate::bots::owner::BotRuntime;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::protocol::registration::{
    PollRegistration, PollRegistrationOutcome, RegistrationClient,
};
use crate::studio::{new_id, unix_seconds};
use crate::{BotDiagnostic, BotRegistrationStatus};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio::time::{Instant as TokioInstant, timeout_at};
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub(super) struct RegistrationJob {
    inner: Arc<Mutex<RegistrationJobInner>>,
}

struct RegistrationJobInner {
    handle: Option<JoinHandle<()>>,
}

impl RegistrationJob {
    pub(super) fn spawn(handle: JoinHandle<()>) -> Self {
        Self {
            inner: Arc::new(Mutex::new(RegistrationJobInner {
                handle: Some(handle),
            })),
        }
    }

    pub(super) async fn join(&self) -> Result<(), FeishuError> {
        let mut inner = self.inner.lock().await;
        crate::bots::join_owned_task(&mut inner.handle)
            .await
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("bot registration join failed: {error}"),
                    true,
                    None,
                )
            })
    }
}

enum WaitingAdmission {
    Current,
    Stale,
}

enum CompleteClaim {
    Stale,
    Claimed {
        name: String,
        workspace_id: String,
        bot_id: String,
    },
}

enum WorkerFinish {
    Denied {
        message: String,
    },
    Expired,
    Failed {
        code: String,
        message: String,
        retryable: bool,
    },
}

enum PollWait {
    Continue,
    Stop,
}

pub(super) struct RegistrationWorker {
    runtime: BotRuntime,
}

impl RegistrationWorker {
    pub(super) fn new(runtime: BotRuntime) -> Self {
        Self { runtime }
    }

    pub(super) async fn run(&self, attempt_id: String, cancel: CancellationToken) {
        let client = RegistrationClient::new(self.runtime.inner.http.clone());
        let begin = tokio::select! {
            _ = cancel.cancelled() => {
                self.note_cancelled_worker(&attempt_id).await;
                return;
            }
            result = client.begin("anywork") => result,
        };
        let begin = match begin {
            Ok(begin) => begin,
            Err(error) => {
                self.finish_worker(
                    &attempt_id,
                    WorkerFinish::Failed {
                        code: error.kind().label().to_string(),
                        message: error.diagnostic().message,
                        retryable: error.retryable(),
                    },
                )
                .await;
                return;
            }
        };
        let now = Instant::now();
        let expires_in = Duration::from_secs(u64::from(begin.expires_in.max(1)));
        let deadline = now.checked_add(expires_in).unwrap_or(now);
        let expires_at = unix_seconds().saturating_add(i64::from(begin.expires_in));
        let waiting = {
            let mut slot = self.runtime.inner.registration.current.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.machine.attempt_id == attempt_id
                        && !active.cancel.is_cancelled()
                        && !active.machine.commit_claimed
                        && matches!(
                            active.machine.status,
                            BotRegistrationStatus::Preparing { .. }
                        ) =>
                {
                    active.machine.wait_for_scan(
                        begin.device_code.clone(),
                        begin.verification_url,
                        deadline,
                        expires_at,
                        begin.interval_seconds,
                    );
                    self.runtime.request_publish();
                    WaitingAdmission::Current
                }
                _ => WaitingAdmission::Stale,
            }
        };
        match waiting {
            WaitingAdmission::Stale => return,
            WaitingAdmission::Current => self.runtime.publish().await,
        }
        self.poll_registration(attempt_id, begin.device_code, cancel)
            .await;
    }

    async fn poll_registration(
        &self,
        attempt_id: String,
        device_code: String,
        cancel: CancellationToken,
    ) {
        let client = RegistrationClient::new(self.runtime.inner.http.clone());
        loop {
            let (interval, deadline) = {
                let slot = self.runtime.inner.registration.current.lock().await;
                match slot.as_ref() {
                    Some(active)
                        if active.machine.attempt_id == attempt_id
                            && !active.machine.commit_claimed
                            && !active.cancel.is_cancelled() =>
                    {
                        (
                            active.machine.interval_seconds.max(1),
                            active.machine.deadline,
                        )
                    }
                    _ => return,
                }
            };
            let now = Instant::now();
            if now >= deadline {
                self.finish_worker(&attempt_id, WorkerFinish::Expired).await;
                return;
            }
            let remaining = deadline.saturating_duration_since(now);
            let sleep_for = Duration::from_secs(u64::from(interval)).min(remaining);
            tokio::select! {
                _ = cancel.cancelled() => {
                    self.note_cancelled_worker(&attempt_id).await;
                    return;
                }
                _ = tokio::time::sleep(sleep_for) => {}
            }
            match self
                .poll_once(&client, &attempt_id, &device_code, deadline, &cancel)
                .await
            {
                PollWait::Continue => {}
                PollWait::Stop => return,
            }
        }
    }

    async fn poll_once(
        &self,
        client: &RegistrationClient,
        attempt_id: &str,
        device_code: &str,
        deadline: Instant,
        cancel: &CancellationToken,
    ) -> PollWait {
        if Instant::now() >= deadline {
            self.finish_worker(attempt_id, WorkerFinish::Expired).await;
            return PollWait::Stop;
        }
        let deadline = TokioInstant::from_std(deadline);
        let outcome = tokio::select! {
            _ = cancel.cancelled() => {
                self.note_cancelled_worker(attempt_id).await;
                return PollWait::Stop;
            }
            result = timeout_at(deadline, client.poll(device_code)) => result,
        };
        match outcome {
            Err(_) => {
                self.finish_worker(attempt_id, WorkerFinish::Expired).await;
                PollWait::Stop
            }
            Ok(Ok(PollRegistrationOutcome::Pending)) => {
                if self.refresh_waiting(attempt_id, false).await {
                    PollWait::Continue
                } else {
                    PollWait::Stop
                }
            }
            Ok(Ok(PollRegistrationOutcome::SlowDown)) => {
                if self.refresh_waiting(attempt_id, true).await {
                    PollWait::Continue
                } else {
                    PollWait::Stop
                }
            }
            Ok(Ok(PollRegistrationOutcome::Completed(result))) => {
                self.complete_registration(attempt_id, result).await;
                PollWait::Stop
            }
            Ok(Ok(PollRegistrationOutcome::Denied { message })) => {
                self.finish_worker(attempt_id, WorkerFinish::Denied { message })
                    .await;
                PollWait::Stop
            }
            Ok(Ok(PollRegistrationOutcome::Expired)) => {
                self.finish_worker(attempt_id, WorkerFinish::Expired).await;
                PollWait::Stop
            }
            Ok(Ok(PollRegistrationOutcome::Failed { code, message })) => {
                self.finish_worker(
                    attempt_id,
                    WorkerFinish::Failed {
                        code,
                        message,
                        retryable: true,
                    },
                )
                .await;
                PollWait::Stop
            }
            Ok(Err(error)) => {
                self.finish_worker(
                    attempt_id,
                    WorkerFinish::Failed {
                        code: error.kind().label().to_string(),
                        message: error.diagnostic().message,
                        retryable: error.retryable(),
                    },
                )
                .await;
                PollWait::Stop
            }
        }
    }

    async fn refresh_waiting(&self, attempt_id: &str, slow_down: bool) -> bool {
        let outcome = {
            let mut slot = self.runtime.inner.registration.current.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.machine.attempt_id == attempt_id
                        && !active.machine.commit_claimed
                        && !active.cancel.is_cancelled() =>
                {
                    let waiting = active
                        .machine
                        .refresh_waiting(slow_down, Some((Instant::now(), unix_seconds())));
                    self.runtime.request_publish();
                    Some(waiting)
                }
                _ => None,
            }
        };
        match outcome {
            Some(_) => {
                self.runtime.publish().await;
                outcome == Some(true)
            }
            None => false,
        }
    }

    async fn complete_registration(&self, attempt_id: &str, result: PollRegistration) {
        let claim = {
            let mut slot = self.runtime.inner.registration.current.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.machine.attempt_id == attempt_id
                        && !active.cancel.is_cancelled()
                        && !active.machine.commit_claimed =>
                {
                    let claim = if active.machine.expired(Instant::now(), unix_seconds()) {
                        active.machine.expire();
                        CompleteClaim::Stale
                    } else {
                        let bot_id = new_id("bot");
                        active.machine.claim_commit(bot_id.clone());
                        CompleteClaim::Claimed {
                            name: active.machine.name.clone(),
                            workspace_id: active.machine.workspace_id.clone(),
                            bot_id,
                        }
                    };
                    self.runtime.request_publish();
                    claim
                }
                _ => CompleteClaim::Stale,
            }
        };
        match claim {
            CompleteClaim::Stale => {
                self.runtime.publish().await;
            }
            CompleteClaim::Claimed {
                name,
                workspace_id,
                bot_id,
            } => {
                self.runtime.publish().await;
                let trusted_open_id = result.open_id.filter(|value| !value.trim().is_empty());
                let committed = self
                    .runtime
                    .save_registration_bot(RegistrationSave {
                        bot_id: bot_id.clone(),
                        name,
                        workspace_id,
                        app_id: result.client_id,
                        secret: result.client_secret,
                        trusted_open_id,
                        operation_id: attempt_id.to_string(),
                    })
                    .await;
                self.settle_commit(attempt_id, &bot_id, committed).await
            }
        }
    }

    async fn settle_commit(
        &self,
        attempt_id: &str,
        bot_id: &str,
        committed: Result<CredentialCommit, FeishuError>,
    ) {
        match committed {
            Ok(commit) if commit.decision == CredentialDecision::Applied && commit.publishable => {
                {
                    let mut slot = self.runtime.inner.registration.current.lock().await;
                    if let Some(active) = slot.as_mut()
                        && active.machine.attempt_id == attempt_id
                        && active.machine.commit_claimed
                    {
                        active.machine.clear_authorization_material();
                        active.machine.completed_bot_id = Some(bot_id.to_string());
                        active.machine.status = BotRegistrationStatus::Completed {
                            attempt_id: attempt_id.to_string(),
                        };
                        self.runtime.request_publish();
                    }
                }
                if let Ok(managed) = self.runtime.managed(bot_id).await
                    && let Some(secret) = commit.secret.clone()
                    && let Err(error) = self
                        .runtime
                        .start_connection(&managed, commit.config.clone(), secret)
                        .await
                {
                    managed
                        .diagnostic
                        .lock()
                        .await
                        .set(DiagnosticSlot::Connection, Some(error.diagnostic()));
                }
                self.runtime.publish().await;
            }
            Ok(commit) => {
                let diagnostic = commit.diagnostic.clone().unwrap_or_else(|| {
                    let uncertain = commit.decision == CredentialDecision::Uncertain;
                    FeishuError::new(
                        if uncertain {
                            FeishuErrorKind::Unavailable
                        } else {
                            FeishuErrorKind::Rejected
                        },
                        if uncertain {
                            format!("bot credential commit {attempt_id} is uncertain")
                        } else {
                            format!("bot credential operation {attempt_id} was not applied")
                        },
                        uncertain,
                        None,
                    )
                    .diagnostic()
                });
                self.fail_after_claim(attempt_id, diagnostic).await;
            }
            Err(error) => {
                self.fail_after_claim(attempt_id, error.diagnostic()).await;
            }
        }
    }

    async fn fail_after_claim(&self, attempt_id: &str, diagnostic: BotDiagnostic) {
        {
            let mut slot = self.runtime.inner.registration.current.lock().await;
            if let Some(active) = slot.as_mut()
                && active.machine.attempt_id == attempt_id
            {
                active.machine.clear_authorization_material();
                active.machine.status = BotRegistrationStatus::Failed {
                    attempt_id: attempt_id.to_string(),
                    code: diagnostic.code,
                    message: diagnostic.message,
                    retryable: diagnostic.retryable,
                };
                self.runtime.request_publish();
            }
        }
        self.runtime.publish().await;
    }

    async fn finish_worker(&self, attempt_id: &str, finish: WorkerFinish) {
        let changed = {
            let mut slot = self.runtime.inner.registration.current.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.machine.attempt_id == attempt_id
                        && !active.machine.commit_claimed
                        && !matches!(
                            active.machine.status,
                            BotRegistrationStatus::Cancelled { .. }
                                | BotRegistrationStatus::Completed { .. }
                        ) =>
                {
                    active.machine.clear_authorization_material();
                    active.machine.status = match finish {
                        WorkerFinish::Denied { message } => BotRegistrationStatus::Denied {
                            attempt_id: attempt_id.to_string(),
                            message,
                        },
                        WorkerFinish::Expired => BotRegistrationStatus::Expired {
                            attempt_id: attempt_id.to_string(),
                        },
                        WorkerFinish::Failed {
                            code,
                            message,
                            retryable,
                        } => BotRegistrationStatus::Failed {
                            attempt_id: attempt_id.to_string(),
                            code,
                            message,
                            retryable,
                        },
                    };
                    self.runtime.request_publish();
                    true
                }
                _ => false,
            }
        };
        if changed {
            self.runtime.publish().await;
        }
    }

    async fn note_cancelled_worker(&self, attempt_id: &str) {
        let changed = {
            let mut slot = self.runtime.inner.registration.current.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.machine.attempt_id == attempt_id
                        && !active.machine.commit_claimed
                        && !active.machine.is_terminal() =>
                {
                    invalidate_waiting(active);
                    self.runtime.request_publish();
                    true
                }
                _ => false,
            }
        };
        if changed {
            self.runtime.publish().await;
        }
    }
}
