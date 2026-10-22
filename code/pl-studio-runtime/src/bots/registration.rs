//! 扫码注册 attempt owner：短原子裁决、真实 job 槽、取消/完成竞争与协议轮询。
//!
//! 网络、凭据 IO 与 join 都在裁决锁外。可见状态离开无 await 短块前
//! `request_publish`，回执再 `publish()`。job 句柄放在可 clone 的持久 owner 内，
//! 元数据短锁只 clone 该 owner，锁外借 `&mut` 等待；不 `take` 句柄。
//! 开始/替换由独立 `registration_start` 协调闸门串行；cancel/close/worker 不取该闸门。

use super::credentials::{CredentialCommit, CredentialDecision};
use super::operation::RegistrationSave;
use super::owner::BotRuntime;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::registration::{
    PollRegistration, PollRegistrationOutcome, RegistrationClient,
};
use crate::studio::new_id;
use crate::studio::unix_seconds;
use pl_protocol::studio::{
    BotDiagnostic, BotRegistrationAttempt, BotRegistrationStatus, BotsCommandReply,
    CommandDisposition, CommandEffectPoint, ResourceStamp, StudioCommandReceipt,
};
use std::pin::Pin;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio::time::{Instant as TokioInstant, timeout_at};
use tokio_util::sync::CancellationToken;

const SLOW_DOWN_INCREMENT_SECS: u32 = 5;

#[derive(Clone)]
pub(crate) struct RegistrationJob {
    inner: Arc<Mutex<RegistrationJobInner>>,
}

struct RegistrationJobInner {
    handle: Option<JoinHandle<()>>,
}

impl RegistrationJob {
    fn spawn(handle: JoinHandle<()>) -> Self {
        Self {
            inner: Arc::new(Mutex::new(RegistrationJobInner {
                handle: Some(handle),
            })),
        }
    }

    async fn join(&self) -> Result<(), FeishuError> {
        let mut inner = self.inner.lock().await;
        let Some(handle) = inner.handle.as_mut() else {
            return Ok(());
        };
        let joined = Pin::new(handle).await;
        inner.handle = None;
        match joined {
            Ok(()) => Ok(()),
            Err(error) if error.is_cancelled() => Ok(()),
            Err(error) => Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                format!("bot registration join failed: {error}"),
                true,
                None,
            )),
        }
    }
}

pub(crate) struct ActiveRegistration {
    pub(crate) attempt_id: String,
    pub(crate) operation_id: String,
    pub(crate) name: String,
    pub(crate) project_id: String,
    pub(crate) device_code: String,
    pub(crate) verification_url: String,
    pub(crate) expires_at: i64,
    pub(crate) deadline: Instant,
    pub(crate) interval_seconds: u32,
    pub(crate) cancel: CancellationToken,
    pub(crate) status: BotRegistrationStatus,
    pub(crate) completed_bot_id: Option<String>,
    pub(crate) commit_claimed: bool,
    pub(crate) job: RegistrationJob,
}

impl ActiveRegistration {
    fn snapshot(&self) -> BotRegistrationAttempt {
        BotRegistrationAttempt {
            attempt_id: self.attempt_id.clone(),
            name: self.name.clone(),
            project_id: self.project_id.clone(),
            status: self.status.clone(),
            completed_bot_id: self.completed_bot_id.clone(),
        }
    }

    fn clear_authorization_material(&mut self) {
        self.device_code.clear();
        self.verification_url.clear();
        if let BotRegistrationStatus::Waiting {
            verification_url, ..
        }
        | BotRegistrationStatus::SlowDown {
            verification_url, ..
        } = &mut self.status
        {
            verification_url.clear();
        }
    }

    fn matches_request(&self, operation_id: &str, name: &str, project_id: &str) -> bool {
        self.operation_id == operation_id && self.name == name && self.project_id == project_id
    }

    fn is_terminal(&self) -> bool {
        matches!(
            self.status,
            BotRegistrationStatus::Completed { .. }
                | BotRegistrationStatus::Denied { .. }
                | BotRegistrationStatus::Expired { .. }
                | BotRegistrationStatus::Cancelled { .. }
                | BotRegistrationStatus::Failed { .. }
        )
    }

    fn is_committing(&self) -> bool {
        self.commit_claimed && matches!(self.status, BotRegistrationStatus::Committing { .. })
    }
}

enum StartAdmission {
    Reuse { changed: bool },
    Launch { previous: Option<RegistrationJob> },
}

enum CancelAdmission {
    NoChange,
    Cancelled { job: RegistrationJob },
}

enum WaitingAdmission {
    Current,
    Stale,
}

enum CompleteClaim {
    Stale,
    Claimed {
        name: String,
        project_id: String,
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

impl BotRuntime {
    pub(crate) fn registration_snapshot(active: &ActiveRegistration) -> BotRegistrationAttempt {
        active.snapshot()
    }

    pub async fn start_registration(
        &self,
        operation_id: String,
        name: String,
        project_id: String,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        let name = name.trim().to_string();
        let project_id = project_id.trim().to_string();
        if name.is_empty() {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bot name and projectId are required",
                false,
                None,
            ));
        }
        self.ensure_publisher().await?;
        let _start = self.inner.registration_start.lock().await;
        loop {
            let admission = {
                let mut slot = self.inner.registration.lock().await;
                if self.management_sealed() {
                    return Err(sealed_registration_error());
                }
                match slot.as_mut() {
                    Some(active) if active.matches_request(&operation_id, &name, &project_id) => {
                        StartAdmission::Reuse { changed: false }
                    }
                    Some(active) if active.operation_id == operation_id => {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Conflict,
                            "operationId already used with different bot input",
                            false,
                            None,
                        ));
                    }
                    Some(active) if active.is_committing() => {
                        return Err(busy_registration_error());
                    }
                    Some(active) => {
                        if !active.is_terminal() {
                            invalidate_waiting(active);
                            self.request_publish();
                        }
                        StartAdmission::Launch {
                            previous: Some(active.job.clone()),
                        }
                    }
                    None => StartAdmission::Launch { previous: None },
                }
            };
            match admission {
                StartAdmission::Reuse { changed } => {
                    return Ok(self
                        .registration_reply(operation_id, changed, owner_epoch)
                        .await);
                }
                StartAdmission::Launch { previous } => {
                    if let Some(job) = previous {
                        job.join().await?;
                    }
                    if self
                        .install_registration(
                            operation_id.clone(),
                            name.clone(),
                            project_id.clone(),
                        )
                        .await?
                    {
                        self.publish().await;
                        return Ok(self
                            .registration_reply(operation_id, true, owner_epoch)
                            .await);
                    }
                }
            }
        }
    }

    async fn install_registration(
        &self,
        operation_id: String,
        name: String,
        project_id: String,
    ) -> Result<bool, FeishuError> {
        let mut slot = self.inner.registration.lock().await;
        if self.management_sealed() {
            return Err(sealed_registration_error());
        }
        match slot.as_ref() {
            Some(active) if active.matches_request(&operation_id, &name, &project_id) => {
                return Ok(false);
            }
            Some(active) if active.operation_id == operation_id => {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "operationId already used with different bot input",
                    false,
                    None,
                ));
            }
            Some(active) if active.is_committing() => {
                return Err(busy_registration_error());
            }
            Some(_) | None => {}
        }
        let attempt_id = new_id("botreg");
        let cancel = CancellationToken::new();
        let runtime = self.clone();
        let worker_attempt = attempt_id.clone();
        let worker_cancel = cancel.clone();
        let handle = tokio::spawn(async move {
            runtime
                .run_registration(worker_attempt, worker_cancel)
                .await;
        });
        *slot = Some(ActiveRegistration {
            attempt_id: attempt_id.clone(),
            operation_id,
            name,
            project_id,
            device_code: String::new(),
            verification_url: String::new(),
            expires_at: 0,
            deadline: Instant::now(),
            interval_seconds: 5,
            cancel,
            status: BotRegistrationStatus::Preparing { attempt_id },
            completed_bot_id: None,
            commit_claimed: false,
            job: RegistrationJob::spawn(handle),
        });
        self.request_publish();
        Ok(true)
    }

    pub async fn cancel_registration(
        &self,
        operation_id: String,
        attempt_id: String,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        self.ensure_publisher().await?;
        let admission = {
            let mut slot = self.inner.registration.lock().await;
            match slot.as_mut() {
                Some(active) if active.attempt_id != attempt_id => {
                    return Err(FeishuError::new(
                        FeishuErrorKind::NotFound,
                        "registration attempt was not found",
                        false,
                        None,
                    ));
                }
                Some(active)
                    if matches!(active.status, BotRegistrationStatus::Cancelled { .. }) =>
                {
                    CancelAdmission::NoChange
                }
                Some(active) if active.is_committing() => {
                    return Err(busy_registration_error());
                }
                Some(active) if active.is_terminal() => CancelAdmission::NoChange,
                Some(active) => {
                    invalidate_waiting(active);
                    self.request_publish();
                    CancelAdmission::Cancelled {
                        job: active.job.clone(),
                    }
                }
                None => {
                    return Err(FeishuError::new(
                        FeishuErrorKind::NotFound,
                        "registration attempt was not found",
                        false,
                        None,
                    ));
                }
            }
        };
        match admission {
            CancelAdmission::NoChange => Ok(self
                .registration_reply(operation_id, false, owner_epoch)
                .await),
            CancelAdmission::Cancelled { job } => {
                self.publish().await;
                job.join().await?;
                Ok(self
                    .registration_reply(operation_id, true, owner_epoch)
                    .await)
            }
        }
    }

    pub(crate) async fn close_registration(&self) -> Result<(), FeishuError> {
        let job = {
            let mut slot = self.inner.registration.lock().await;
            slot.as_mut().map(|active| {
                if !active.commit_claimed && !active.is_terminal() {
                    invalidate_waiting(active);
                    self.request_publish();
                }
                active.job.clone()
            })
        };
        if let Some(job) = job {
            job.join().await?;
        }
        self.publish().await;
        Ok(())
    }

    async fn run_registration(&self, attempt_id: String, cancel: CancellationToken) {
        let client = RegistrationClient::new(self.inner.http.clone());
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
            let mut slot = self.inner.registration.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.attempt_id == attempt_id
                        && !active.cancel.is_cancelled()
                        && !active.commit_claimed
                        && matches!(active.status, BotRegistrationStatus::Preparing { .. }) =>
                {
                    active.device_code = begin.device_code.clone();
                    active.verification_url = begin.verification_url.clone();
                    active.expires_at = expires_at;
                    active.deadline = deadline;
                    active.interval_seconds = begin.interval_seconds.max(1);
                    active.status = BotRegistrationStatus::Waiting {
                        attempt_id: attempt_id.clone(),
                        verification_url: begin.verification_url.clone(),
                        expires_at,
                        interval_seconds: active.interval_seconds,
                    };
                    self.request_publish();
                    WaitingAdmission::Current
                }
                _ => WaitingAdmission::Stale,
            }
        };
        match waiting {
            WaitingAdmission::Stale => return,
            WaitingAdmission::Current => self.publish().await,
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
        let client = RegistrationClient::new(self.inner.http.clone());
        loop {
            let (interval, deadline) = {
                let slot = self.inner.registration.lock().await;
                match slot.as_ref() {
                    Some(active)
                        if active.attempt_id == attempt_id
                            && !active.commit_claimed
                            && !active.cancel.is_cancelled() =>
                    {
                        (active.interval_seconds.max(1), active.deadline)
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
                if let Err(error) = self.complete_registration(attempt_id, result).await {
                    self.finish_worker(
                        attempt_id,
                        WorkerFinish::Failed {
                            code: error.kind().label().to_string(),
                            message: error.diagnostic().message,
                            retryable: error.retryable(),
                        },
                    )
                    .await;
                }
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
            let mut slot = self.inner.registration.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.attempt_id == attempt_id
                        && !active.commit_claimed
                        && !active.cancel.is_cancelled() =>
                {
                    if Instant::now() >= active.deadline || unix_seconds() >= active.expires_at {
                        active.clear_authorization_material();
                        active.status = BotRegistrationStatus::Expired {
                            attempt_id: attempt_id.to_string(),
                        };
                        self.request_publish();
                        Some(false)
                    } else {
                        if slow_down {
                            active.interval_seconds = active
                                .interval_seconds
                                .saturating_add(SLOW_DOWN_INCREMENT_SECS)
                                .max(1);
                        }
                        active.status = if slow_down {
                            BotRegistrationStatus::SlowDown {
                                attempt_id: attempt_id.to_string(),
                                verification_url: active.verification_url.clone(),
                                expires_at: active.expires_at,
                                interval_seconds: active.interval_seconds,
                            }
                        } else {
                            BotRegistrationStatus::Waiting {
                                attempt_id: attempt_id.to_string(),
                                verification_url: active.verification_url.clone(),
                                expires_at: active.expires_at,
                                interval_seconds: active.interval_seconds,
                            }
                        };
                        self.request_publish();
                        Some(true)
                    }
                }
                _ => None,
            }
        };
        match outcome {
            Some(_) => {
                self.publish().await;
                outcome == Some(true)
            }
            None => false,
        }
    }

    async fn complete_registration(
        &self,
        attempt_id: &str,
        result: PollRegistration,
    ) -> Result<(), FeishuError> {
        let claim = {
            let mut slot = self.inner.registration.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.attempt_id == attempt_id
                        && !active.cancel.is_cancelled()
                        && !active.commit_claimed
                        && Instant::now() < active.deadline
                        && unix_seconds() < active.expires_at =>
                {
                    let bot_id = new_id("bot");
                    active.commit_claimed = true;
                    active.clear_authorization_material();
                    active.completed_bot_id = None;
                    active.status = BotRegistrationStatus::Committing {
                        attempt_id: attempt_id.to_string(),
                        bot_id: bot_id.clone(),
                    };
                    self.request_publish();
                    CompleteClaim::Claimed {
                        name: active.name.clone(),
                        project_id: active.project_id.clone(),
                        bot_id,
                    }
                }
                Some(active)
                    if active.attempt_id == attempt_id
                        && !active.commit_claimed
                        && !active.cancel.is_cancelled()
                        && (Instant::now() >= active.deadline
                            || unix_seconds() >= active.expires_at) =>
                {
                    active.clear_authorization_material();
                    active.status = BotRegistrationStatus::Expired {
                        attempt_id: attempt_id.to_string(),
                    };
                    self.request_publish();
                    CompleteClaim::Stale
                }
                _ => CompleteClaim::Stale,
            }
        };
        match claim {
            CompleteClaim::Stale => {
                self.publish().await;
                Ok(())
            }
            CompleteClaim::Claimed {
                name,
                project_id,
                bot_id,
            } => {
                self.publish().await;
                let trusted_open_id = result.open_id.filter(|value| !value.trim().is_empty());
                let committed = self
                    .save_registration_bot(RegistrationSave {
                        bot_id: bot_id.clone(),
                        name,
                        project_id,
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
    ) -> Result<(), FeishuError> {
        match committed {
            Ok(commit) if commit.decision == CredentialDecision::Applied && commit.publishable => {
                {
                    let mut slot = self.inner.registration.lock().await;
                    if let Some(active) = slot.as_mut()
                        && active.attempt_id == attempt_id
                        && active.commit_claimed
                    {
                        active.clear_authorization_material();
                        active.completed_bot_id = Some(bot_id.to_string());
                        active.status = BotRegistrationStatus::Completed {
                            attempt_id: attempt_id.to_string(),
                        };
                        self.request_publish();
                    }
                }
                if let Ok(managed) = self.managed(bot_id).await
                    && let Some(secret) = commit.secret.clone()
                    && let Err(error) = self
                        .start_connection(&managed, commit.config.clone(), secret)
                        .await
                {
                    *managed.diagnostic.lock().await = Some(error.diagnostic());
                }
                self.publish().await;
                Ok(())
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
                Ok(())
            }
            Err(error) => {
                self.fail_after_claim(attempt_id, error.diagnostic()).await;
                Ok(())
            }
        }
    }

    async fn fail_after_claim(&self, attempt_id: &str, diagnostic: BotDiagnostic) {
        {
            let mut slot = self.inner.registration.lock().await;
            if let Some(active) = slot.as_mut()
                && active.attempt_id == attempt_id
            {
                active.clear_authorization_material();
                active.status = BotRegistrationStatus::Failed {
                    attempt_id: attempt_id.to_string(),
                    code: diagnostic.code,
                    message: diagnostic.message,
                    retryable: diagnostic.retryable,
                };
                self.request_publish();
            }
        }
        self.publish().await;
    }

    async fn finish_worker(&self, attempt_id: &str, finish: WorkerFinish) {
        let changed = {
            let mut slot = self.inner.registration.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.attempt_id == attempt_id
                        && !active.commit_claimed
                        && !matches!(
                            active.status,
                            BotRegistrationStatus::Cancelled { .. }
                                | BotRegistrationStatus::Completed { .. }
                        ) =>
                {
                    active.clear_authorization_material();
                    active.status = match finish {
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
                    self.request_publish();
                    true
                }
                _ => false,
            }
        };
        if changed {
            self.publish().await;
        }
    }

    async fn note_cancelled_worker(&self, attempt_id: &str) {
        let changed = {
            let mut slot = self.inner.registration.lock().await;
            match slot.as_mut() {
                Some(active)
                    if active.attempt_id == attempt_id
                        && !active.commit_claimed
                        && !active.is_terminal() =>
                {
                    invalidate_waiting(active);
                    self.request_publish();
                    true
                }
                _ => false,
            }
        };
        if changed {
            self.publish().await;
        }
    }

    async fn registration_reply(
        &self,
        operation_id: String,
        changed: bool,
        owner_epoch: &str,
    ) -> BotsCommandReply {
        let snapshot = self.snapshot().await;
        BotsCommandReply {
            stamp: Some(ResourceStamp {
                resource_key: "bots".to_string(),
                owner_epoch: owner_epoch.to_string(),
                revision: snapshot.revision,
            }),
            receipt: StudioCommandReceipt {
                operation_id,
                disposition: if changed {
                    CommandDisposition::Applied
                } else {
                    CommandDisposition::NoChange
                },
                targets: vec![ResourceStamp {
                    resource_key: "bots".to_string(),
                    owner_epoch: owner_epoch.to_string(),
                    revision: snapshot.revision,
                }],
                effect: CommandEffectPoint::Immediate,
                effective: true,
                durable: false,
                requires_identity_observation: false,
            },
            snapshot,
        }
    }
}

fn invalidate_waiting(active: &mut ActiveRegistration) {
    active.cancel.cancel();
    active.clear_authorization_material();
    active.status = BotRegistrationStatus::Cancelled {
        attempt_id: active.attempt_id.clone(),
    };
}

fn sealed_registration_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot runtime is sealed",
        true,
        None,
    )
}

fn busy_registration_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Busy,
        "registration is committing or already owned",
        true,
        None,
    )
}
