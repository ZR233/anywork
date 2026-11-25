//! Registration commands serialize attempts and never await a worker under the state lock.
mod machine;
mod worker;

use self::machine::RegistrationStateMachine;
use self::worker::{RegistrationJob, RegistrationWorker};
use crate::bots::owner::{BotRuntime, ReceiptDurability};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::new_id;
use crate::{BotRegistrationAttempt, BotsCommandReply};
use std::time::Instant;
use tokio_util::sync::CancellationToken;

pub(crate) struct ActiveRegistration {
    machine: RegistrationStateMachine,
    cancel: CancellationToken,
    job: RegistrationJob,
}

enum StartAdmission {
    Reuse,
    Launch { previous: Option<RegistrationJob> },
}

enum CancelAdmission {
    NoChange,
    Cancelled { job: RegistrationJob },
}

impl BotRuntime {
    pub(crate) fn registration_snapshot(active: &ActiveRegistration) -> BotRegistrationAttempt {
        active.machine.snapshot()
    }

    pub async fn start_registration(
        &self,
        operation_id: String,
        name: String,
        workspace_id: String,
        owner_epoch: &str,
    ) -> Result<BotsCommandReply, FeishuError> {
        let name = name.trim().to_string();
        let workspace_id = workspace_id.trim().to_string();
        if name.is_empty() {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "bot name and workspaceId are required",
                false,
                None,
            ));
        }
        self.ensure_publisher().await?;
        let _start = self.inner.registration.start.lock().await;
        loop {
            let admission = {
                let mut slot = self.inner.registration.current.lock().await;
                if self.management_sealed() {
                    return Err(sealed_registration_error());
                }
                match slot.as_mut() {
                    Some(active)
                        if active
                            .machine
                            .matches_request(&operation_id, &name, &workspace_id) =>
                    {
                        StartAdmission::Reuse
                    }
                    Some(active) if active.machine.operation_id == operation_id => {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Conflict,
                            "operationId already used with different bot input",
                            false,
                            None,
                        ));
                    }
                    Some(active) if active.machine.is_committing() => {
                        return Err(busy_registration_error());
                    }
                    Some(active) => {
                        if !active.machine.is_terminal() {
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
                StartAdmission::Reuse => {
                    // 同一请求重放只复用进行中的注册，不产生新的状态变更。
                    return Ok(self
                        .reply(
                            operation_id,
                            false,
                            owner_epoch,
                            ReceiptDurability::Ephemeral,
                        )
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
                            workspace_id.clone(),
                        )
                        .await?
                    {
                        self.publish().await;
                        return Ok(self
                            .reply(
                                operation_id,
                                true,
                                owner_epoch,
                                ReceiptDurability::Ephemeral,
                            )
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
        workspace_id: String,
    ) -> Result<bool, FeishuError> {
        let mut slot = self.inner.registration.current.lock().await;
        if self.management_sealed() {
            return Err(sealed_registration_error());
        }
        match slot.as_ref() {
            Some(active)
                if active
                    .machine
                    .matches_request(&operation_id, &name, &workspace_id) =>
            {
                return Ok(false);
            }
            Some(active) if active.machine.operation_id == operation_id => {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "operationId already used with different bot input",
                    false,
                    None,
                ));
            }
            Some(active) if active.machine.is_committing() => {
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
            RegistrationWorker::new(runtime)
                .run(worker_attempt, worker_cancel)
                .await;
        });
        *slot = Some(ActiveRegistration {
            machine: RegistrationStateMachine::new(
                attempt_id,
                operation_id,
                name,
                workspace_id,
                Instant::now(),
            ),
            cancel,
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
            let mut slot = self.inner.registration.current.lock().await;
            match slot.as_mut() {
                Some(active) if active.machine.attempt_id != attempt_id => {
                    return Err(FeishuError::new(
                        FeishuErrorKind::NotFound,
                        "registration attempt was not found",
                        false,
                        None,
                    ));
                }
                Some(active) if active.machine.is_committing() => {
                    return Err(busy_registration_error());
                }
                Some(active) if active.machine.is_terminal() => CancelAdmission::NoChange,
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
                .reply(
                    operation_id,
                    false,
                    owner_epoch,
                    ReceiptDurability::Ephemeral,
                )
                .await),
            CancelAdmission::Cancelled { job } => {
                self.publish().await;
                job.join().await?;
                Ok(self
                    .reply(
                        operation_id,
                        true,
                        owner_epoch,
                        ReceiptDurability::Ephemeral,
                    )
                    .await)
            }
        }
    }

    pub(crate) async fn close_registration(&self) -> Result<(), FeishuError> {
        let job = {
            let mut slot = self.inner.registration.current.lock().await;
            slot.as_mut().map(|active| {
                if !active.machine.commit_claimed && !active.machine.is_terminal() {
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
}

fn invalidate_waiting(active: &mut ActiveRegistration) {
    active.cancel.cancel();
    active.machine.cancel();
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
