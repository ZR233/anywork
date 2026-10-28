//! One claimed operation owns upload/message facts. Local stops never invent platform rejection.
use super::BotRuntime;
use super::SendAuthority;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::http::{PostFailure, PreparedPost};
use super::protocol::im::{FeishuIm, MessageContent};
use super::send::{SendContent, SendIdentity};
use super::storage::{MessageStage, SendRecord, SendRecordStatus, UploadFact};
use super::storage::{PublicationFileAttempt, PublicationFileProgress, PublicationFileStage};
use pl_core::context::{ResourceReader, ResourceReference};
use pl_protocol::studio::*;
use std::{future::Future, task::Poll, time::Duration};
use tokio_util::sync::CancellationToken;

impl BotRuntime {
    pub(super) async fn deliver_claimed(
        &self,
        token: &str,
        managed: &super::owner::ManagedBot,
        record: SendRecord,
        execution: SendExecution<'_>,
    ) -> Result<BotSendResult, FeishuError> {
        Delivery {
            runtime: self,
            token,
            managed,
            authority: execution.authority,
            record,
            cancel: execution.cancel,
            _bytes_budget: execution.bytes_budget,
            failed_save: execution.failed_save,
            save_diagnostic: None,
        }
        .run()
        .await
    }
}

/// The admitted caller's authority and resource ownership travel together until settlement.
pub(super) struct SendExecution<'a> {
    pub(super) authority: &'a SendAuthority,
    pub(super) cancel: &'a CancellationToken,
    pub(super) bytes_budget: Option<tokio::sync::OwnedSemaphorePermit>,
    pub(super) failed_save: Option<tokio::sync::oneshot::Sender<FeishuError>>,
}

struct Delivery<'a> {
    runtime: &'a BotRuntime,
    token: &'a str,
    managed: &'a super::owner::ManagedBot,
    authority: &'a SendAuthority,
    record: SendRecord,
    cancel: &'a CancellationToken,
    _bytes_budget: Option<tokio::sync::OwnedSemaphorePermit>,
    failed_save: Option<tokio::sync::oneshot::Sender<FeishuError>>,
    save_diagnostic: Option<BotDiagnostic>,
}

#[derive(Clone, Copy)]
enum Action {
    Upload,
    Message,
}

impl Action {
    fn stage(self) -> PublicationFileStage {
        match self {
            Self::Upload => PublicationFileStage::Upload,
            Self::Message => PublicationFileStage::Message,
        }
    }
}

enum Attempt<T> {
    Response(Result<T, PostFailure>),
    Cancelled,
}

struct Started<T> {
    outcome: Attempt<T>,
    publication: Option<PublicationFileAttempt>,
}

#[derive(Clone, Copy)]
enum SaveResponsibility {
    Unpolled,
    PlatformResult,
}

#[derive(Debug, thiserror::Error)]
#[error("durable send confirmation also failed after admission/correction failure ({admission})")]
struct SendConfirmationFailure {
    admission: FeishuError,
    #[source]
    confirmation: FeishuError,
}

fn correction_fenced(error: &FeishuError) -> bool {
    !error.retryable()
        && matches!(
            error.kind(),
            FeishuErrorKind::Conflict | FeishuErrorKind::Permission
        )
}

impl Delivery<'_> {
    async fn run(mut self) -> Result<BotSendResult, FeishuError> {
        let im = FeishuIm::new(self.runtime.inner.http.clone());
        for index in 0..self.record.segments.len() {
            if self.runtime.check_send_active(self.cancel).is_err() {
                let action = if self.record.segments[index].upload == Some(UploadFact::NotStarted) {
                    Action::Upload
                } else {
                    Action::Message
                };
                self.stop_before_start(
                    index,
                    action,
                    BotSendStopReason::Cancelled,
                    "send cancelled before the next network request",
                    None,
                )
                .await?;
                return Ok(replay_send(self.record));
            }
            let content = self.record.segments[index].content.clone();
            let prepared = match content {
                Some(SendContent::Markdown { text }) => im.prepare_content(
                    self.token,
                    &self.record.chat_id,
                    MessageContent::Markdown(&text),
                    &self.record.segments[index].uuid,
                ),
                Some(SendContent::File {
                    upload_filename,
                    resource,
                    ..
                }) => {
                    let Some(file_key) = self.upload(index, &upload_filename, resource).await?
                    else {
                        return Ok(replay_send(self.record));
                    };
                    im.prepare_content(
                        self.token,
                        &self.record.chat_id,
                        MessageContent::File {
                            file_key: &file_key,
                        },
                        &self.record.segments[index].uuid,
                    )
                }
                None => Err(FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "new send is missing frozen content",
                    false,
                    None,
                )),
            };
            let prepared = match prepared {
                Ok(prepared) => prepared,
                Err(error) => {
                    self.stop_before_start(
                        index,
                        Action::Message,
                        BotSendStopReason::LocalFailure,
                        &error.diagnostic().message,
                        None,
                    )
                    .await?;
                    return Ok(replay_send(self.record));
                }
            };
            let Some(started) = self
                .execute(index, Action::Message, im.send_prepared(prepared))
                .await?
            else {
                return Ok(replay_send(self.record));
            };
            let progress = match started.outcome {
                Attempt::Response(Ok(sent)) => {
                    self.record
                        .platform_message_ids
                        .push(sent.message_id.clone());
                    let fact = &mut self.record.segments[index];
                    fact.status = SendRecordStatus::Succeeded;
                    fact.message_stage = Some(MessageStage::Accepted);
                    fact.platform_message_id = Some(sent.message_id.clone());
                    self.record.status = if index + 1 == self.record.segments.len() {
                        SendRecordStatus::Succeeded
                    } else {
                        SendRecordStatus::Partial
                    };
                    PublicationFileProgress::Sent {
                        message_id: sent.message_id,
                    }
                }
                Attempt::Response(Err(error)) => {
                    let progress = self.platform_failure(index, Action::Message, error);
                    self.settle(started.publication, progress).await?;
                    return Ok(replay_send(self.record));
                }
                Attempt::Cancelled => {
                    self.set_unknown(index, Action::Message);
                    self.local_stop(
                        index,
                        BotSendStopReason::Cancelled,
                        "message request cancelled in flight; result is unknown",
                    );
                    self.settle(
                        started.publication,
                        PublicationFileProgress::Unknown {
                            stage: PublicationFileStage::Message,
                            diagnostic: Some(FeishuError::cancelled().diagnostic()),
                        },
                    )
                    .await?;
                    return Ok(replay_send(self.record));
                }
            };
            self.settle(started.publication, progress).await?;
        }
        let mut result = replay_send(self.record);
        result.receipt.disposition = CommandDisposition::Applied;
        Ok(result)
    }

    async fn upload(
        &mut self,
        index: usize,
        filename: &str,
        resource: ResourceReference,
    ) -> Result<Option<String>, FeishuError> {
        if matches!(self.authority, SendAuthority::Publication(_)) {
            match &self.record.segments[index].upload {
                Some(UploadFact::Accepted { file_key }) => return Ok(Some(file_key.clone())),
                Some(UploadFact::NotStarted) => {}
                _ => return Ok(None),
            }
        }
        // All local IO, byte/MIME checks and request construction precede InFlight.
        let prepared = self.prepare_upload(filename, &resource).await;
        let (prepared, _bytes_budget) = match prepared {
            Ok(prepared) => prepared,
            Err(error) => {
                let reason = if self.runtime.check_send_active(self.cancel).is_err() {
                    BotSendStopReason::Cancelled
                } else {
                    BotSendStopReason::LocalFailure
                };
                self.stop_before_start(
                    index,
                    Action::Upload,
                    reason,
                    &error.diagnostic().message,
                    None,
                )
                .await?;
                return Ok(None);
            }
        };
        let http = self.runtime.inner.http.clone();
        let Some(started) = self
            .execute(index, Action::Upload, http.upload_file(prepared))
            .await?
        else {
            return Ok(None);
        };
        match started.outcome {
            Attempt::Response(Ok(file_key)) => {
                self.record.segments[index].upload = Some(UploadFact::Accepted {
                    file_key: file_key.clone(),
                });
                self.settle(
                    started.publication,
                    PublicationFileProgress::Uploaded {
                        file_key: file_key.clone(),
                    },
                )
                .await?;
                Ok(Some(file_key))
            }
            Attempt::Response(Err(error)) => {
                let progress = self.platform_failure(index, Action::Upload, error);
                self.settle(started.publication, progress).await?;
                Ok(None)
            }
            Attempt::Cancelled => {
                self.set_unknown(index, Action::Upload);
                self.local_stop(
                    index,
                    BotSendStopReason::Cancelled,
                    "upload request cancelled in flight; result is unknown",
                );
                self.settle(
                    started.publication,
                    PublicationFileProgress::Unknown {
                        stage: PublicationFileStage::Upload,
                        diagnostic: Some(FeishuError::cancelled().diagnostic()),
                    },
                )
                .await?;
                Ok(None)
            }
        }
    }

    async fn prepare_upload(
        &self,
        filename: &str,
        resource: &ResourceReference,
    ) -> Result<(PreparedPost, Option<tokio::sync::OwnedSemaphorePermit>), FeishuError> {
        let budget = if self._bytes_budget.is_some() {
            None
        } else {
            Some(
                self.runtime
                    .reserve_send_bytes(resource.byte_len() as usize)?,
            )
        };
        let bytes = self
            .runtime
            .send_resources(&self.record.bot_id)
            .read(resource.clone(), self.cancel.clone())
            .await
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "retained send resource is unavailable or invalid",
                    false,
                    None,
                )
                .with_source(error)
            })?;
        let request = self.runtime.inner.http.prepare_file_upload(
            self.token,
            filename,
            resource.media_type(),
            bytes,
        )?;
        Ok((request, budget))
    }

    /// Freeze/pin the SAME HTTP future before intent. Keep the short admission through its first
    /// poll, then release it regardless of Ready/Pending. A Close cannot cross intent -> start.
    async fn execute<T>(
        &mut self,
        index: usize,
        action: Action,
        future: impl Future<Output = Result<T, PostFailure>>,
    ) -> Result<Option<Started<T>>, FeishuError> {
        let mut future = std::pin::pin!(future);
        let rate = &self.managed.send_rate;
        let permit = tokio::select! {
            _ = self.cancel.cancelled() => None,
            _ = self.runtime.inner.reply_cancel.cancelled() => None,
            permit = rate.acquire() => Some(permit),
        };
        let Some(permit) = permit else {
            self.stop_before_start(
                index,
                action,
                BotSendStopReason::Cancelled,
                "send cancelled before the next network request",
                None,
            )
            .await?;
            return Ok(None);
        };
        let managed = self.managed;
        let admission = if matches!(
            self.authority,
            SendAuthority::InboundReply(_) | SendAuthority::Publication(_)
        ) {
            Some(managed.admission.lock().await)
        } else {
            None
        };
        if let Err(error) = self.check_stage_admission().await {
            drop(admission);
            drop(permit);
            self.stop_before_start(
                index,
                action,
                BotSendStopReason::Cancelled,
                &error.diagnostic().message,
                None,
            )
            .await?;
            return Ok(None);
        }
        let intent = match self.authority {
            SendAuthority::Publication(authority) => managed
                .store
                .begin_publication_file_stage(
                    &self.record.operation_id,
                    &authority.permit,
                    action.stage(),
                )
                .await
                .map(Some),
            SendAuthority::InboundReply(reply) => {
                self.set_in_flight(index, action);
                managed
                    .store
                    .save_reply_send_intent(&self.record, reply)
                    .await
                    .map(|()| None)
            }
            SendAuthority::Owner | SendAuthority::Tool { .. } => {
                self.set_in_flight(index, action);
                managed.store.save_send(&self.record).await.map(|()| None)
            }
        };
        let mut publication = match intent {
            Ok(attempt) => attempt,
            Err(error) => {
                drop(admission);
                drop(permit);
                // No HTTP future was polled. A failed/uncertain DB admission is not a platform
                // result or proof of rollback. Confirm the SAME operation, never substitute a
                // local NotStarted snapshot for an intent whose COMMIT receipt may be lost.
                return Err(self.unstarted_failure(error).await);
            }
        };
        if let Some(attempt) = &publication {
            self.record = attempt.record().clone();
        }
        self.changed();
        if let Err(error) = self.check_stage_admission().await {
            drop(admission);
            drop(permit);
            self.set_not_started(index, action);
            self.stop_before_start(
                index,
                action,
                BotSendStopReason::Cancelled,
                &error.diagnostic().message,
                publication,
            )
            .await?;
            return Ok(None);
        }
        permit.start();
        let first = std::future::poll_fn(|cx| {
            if let Some(attempt) = &mut publication {
                attempt.mark_request_started();
            }
            Poll::Ready(future.as_mut().poll(cx))
        })
        .await;
        drop(admission);
        let outcome = match first {
            Poll::Ready(result) => Attempt::Response(result),
            Poll::Pending => attempt(future, self.cancel, &self.runtime.inner.reply_cancel).await,
        };
        Ok(Some(Started {
            outcome,
            publication,
        }))
    }

    async fn check_stage_admission(&self) -> Result<(), FeishuError> {
        self.runtime.check_send_active(self.cancel)?;
        match self.authority {
            SendAuthority::InboundReply(_) | SendAuthority::Publication(_) => {
                self.runtime.reject_closed_admission(self.managed)?;
                let config = self.managed.config.lock().await;
                self.runtime.check_send_active(self.cancel)?;
                self.runtime
                    .authorize_send_source(&config, &self.record.chat_id, self.authority)
            }
            SendAuthority::Owner | SendAuthority::Tool { .. } => Ok(()),
        }
    }

    fn set_in_flight(&mut self, index: usize, action: Action) {
        match action {
            Action::Upload => self.record.segments[index].upload = Some(UploadFact::InFlight),
            Action::Message => {
                self.record.segments[index].message_stage = Some(MessageStage::InFlight)
            }
        }
    }

    async fn stop_before_start(
        &mut self,
        index: usize,
        action: Action,
        reason: BotSendStopReason,
        diagnostic: &str,
        attempt: Option<PublicationFileAttempt>,
    ) -> Result<(), FeishuError> {
        self.set_not_started(index, action);
        self.local_stop(index, reason, diagnostic);
        let progress = PublicationFileProgress::NotStarted {
            stage: action.stage(),
            reason,
            diagnostic: diagnostic.into(),
        };
        if attempt.is_some() {
            return self.settle(attempt, progress).await;
        }
        let SendAuthority::Publication(authority) = self.authority else {
            return self.persist(SaveResponsibility::Unpolled).await;
        };
        let mut delay = Duration::from_millis(100);
        loop {
            match self
                .managed
                .store
                .stop_publication_file_before_start(
                    &self.record.operation_id,
                    &authority.permit,
                    progress.clone(),
                )
                .await
            {
                Ok(record) => {
                    self.record = record;
                    self.saved().await;
                    return Ok(());
                }
                Err(error) if correction_fenced(&error) => {
                    return Err(self.unstarted_failure(error).await);
                }
                Err(error) => self.save_before_start_failed(&error).await,
            }
            tokio::time::sleep(delay).await;
            delay = (delay * 2).min(Duration::from_secs(5));
        }
    }

    fn set_not_started(&mut self, index: usize, action: Action) {
        match action {
            Action::Upload => self.record.segments[index].upload = Some(UploadFact::NotStarted),
            Action::Message => {
                self.record.segments[index].message_stage = Some(MessageStage::NotStarted)
            }
        }
    }

    fn set_unknown(&mut self, index: usize, action: Action) {
        match action {
            Action::Upload => self.record.segments[index].upload = Some(UploadFact::Unknown),
            Action::Message => {
                self.record.segments[index].message_stage = Some(MessageStage::Unknown)
            }
        }
    }

    fn local_stop(&mut self, index: usize, reason: BotSendStopReason, message: &str) {
        for fact in self.record.segments.iter_mut().skip(index) {
            fact.stop_reason = Some(reason);
            fact.diagnostic = Some(message.into());
            fact.status = if fact_unknown(fact) {
                SendRecordStatus::Unknown
            } else {
                SendRecordStatus::Rejected
            };
        }
        self.aggregate_stop();
    }

    fn platform_failure(
        &mut self,
        index: usize,
        action: Action,
        failure: PostFailure,
    ) -> PublicationFileProgress {
        let (unknown, error) = match failure {
            PostFailure::Rejected(error) => (false, error),
            PostFailure::Unknown(error) => (true, error),
        };
        let fact = &mut self.record.segments[index];
        match action {
            Action::Upload => {
                fact.upload = Some(if unknown {
                    UploadFact::Unknown
                } else {
                    UploadFact::Rejected
                })
            }
            Action::Message => {
                fact.message_stage = Some(if unknown {
                    MessageStage::Unknown
                } else {
                    MessageStage::Rejected
                })
            }
        }
        fact.status = if unknown {
            SendRecordStatus::Unknown
        } else {
            SendRecordStatus::Rejected
        };
        fact.diagnostic = Some(error.diagnostic().message);
        fact.platform_diagnostic = Some(error.diagnostic());
        self.aggregate_stop();
        if unknown {
            PublicationFileProgress::Unknown {
                stage: action.stage(),
                diagnostic: Some(error.diagnostic()),
            }
        } else {
            PublicationFileProgress::Rejected {
                stage: action.stage(),
                diagnostic: error.diagnostic(),
            }
        }
    }

    fn aggregate_stop(&mut self) {
        self.record.status = if self.record.segments.iter().any(fact_unknown) {
            SendRecordStatus::Unknown
        } else if self.record.platform_message_ids.is_empty() {
            SendRecordStatus::Rejected
        } else {
            SendRecordStatus::Partial
        };
    }

    async fn settle(
        &mut self,
        attempt: Option<PublicationFileAttempt>,
        progress: PublicationFileProgress,
    ) -> Result<(), FeishuError> {
        let Some(mut attempt) = attempt else {
            if matches!(self.authority, SendAuthority::Publication(_)) {
                return Err(FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "frontend file result is missing its original attempt owner",
                    false,
                    None,
                ));
            }
            return self.persist(SaveResponsibility::PlatformResult).await;
        };
        let mut delay = Duration::from_millis(100);
        // Only stop_before_start constructs this progress, before mark_request_started/first
        // poll. No true HTTP result is abandoned when an old correction fence is permanent.
        let before_start = matches!(progress, PublicationFileProgress::NotStarted { .. });
        loop {
            match self
                .managed
                .store
                .settle_publication_file_stage(&mut attempt, progress.clone())
                .await
            {
                Ok(record) => {
                    self.record = record;
                    self.saved().await;
                    return Ok(());
                }
                Err(error) if before_start && correction_fenced(&error) => {
                    return Err(self.unstarted_failure(error).await);
                }
                Err(error) if before_start => self.save_before_start_failed(&error).await,
                Err(error) => self.save_failed(error).await,
            }
            // Never cancel or repeat HTTP while a real result is owed. Both the non-Clone
            // attempt and known progress remain inside this registered owner, even on Close.
            tokio::time::sleep(delay).await;
            delay = (delay * 2).min(Duration::from_secs(5));
        }
    }

    async fn persist(&mut self, responsibility: SaveResponsibility) -> Result<(), FeishuError> {
        let mut delay = Duration::from_millis(100);
        loop {
            match self.managed.store.save_send(&self.record).await {
                Ok(()) => {
                    self.saved().await;
                    return Ok(());
                }
                Err(error) if matches!(responsibility, SaveResponsibility::Unpolled) => {
                    if correction_fenced(&error) {
                        return Err(self.unstarted_failure(error).await);
                    }
                    self.save_before_start_failed(&error).await;
                }
                Err(error) => self.save_failed(error).await,
            }
            tokio::time::sleep(delay).await;
            delay = (delay * 2).min(Duration::from_secs(5));
        }
    }

    async fn save_failed(&mut self, error: FeishuError) {
        self.publish_save_failure(
            &error,
            "sendResultSettlement",
            "the original managed send owner retains its result; close must join or report recovery failure, never resend",
        ).await;
        if let Some(failed) = self.failed_save.take() {
            let _ = failed.send(error.with_observed_send(replay_send(self.record.clone())));
        }
    }

    async fn save_before_start_failed(&mut self, error: &FeishuError) {
        // Keep waiting under the original owner for retryable local IO. In particular, do not
        // publish the speculative local NotStarted as an observed receipt through failed_save.
        self.publish_save_failure(
            error,
            "sendAdmissionSettlement",
            "HTTP was not polled; its local stop is not confirmed; the original owner is retrying only the local save",
        ).await;
    }

    async fn unstarted_failure(&mut self, admission: FeishuError) -> FeishuError {
        let error = match self.runtime.confirm_send_record(self.managed, &self.record, self.authority).await {
            Ok(current) => {
                self.record = current;
                let unknown = self.record.segments.iter().any(fact_unknown);
                FeishuError::new(
                    admission.kind(),
                    if unknown {
                        "HTTP was not polled; the original durable send is in flight or unknown; local recovery is required and it must not be replayed"
                    } else {
                        "HTTP was not polled; admission/correction failed; the receipt contains only confirmed original durable send facts"
                    },
                    admission.retryable() && !unknown,
                    admission.platform_code().map(str::to_owned),
                ).with_source(admission).with_observed_send(replay_send(self.record.clone()))
            }
            Err(confirmation) => FeishuError::new(
                confirmation.kind(),
                "HTTP was not polled; the original durable send outcome could not be confirmed; local recovery is required before any new request",
                confirmation.retryable(),
                confirmation.platform_code().map(str::to_owned),
            ).with_source(SendConfirmationFailure { admission, confirmation }),
        };
        self.publish_save_failure(
            &error,
            "sendAdmissionRecovery",
            "the unpolled request owner is ending; preserve the original ledger/UUID and confirm its durable facts, never replay an InFlight or Unknown request",
        ).await;
        // No network result is owed on this path. Return the confirmed facts (or no receipt),
        // then let the registered task end and release its budgets. This read grants no action.
        error
    }

    async fn publish_save_failure(&mut self, error: &FeishuError, code: &str, guidance: &str) {
        let mut diagnostic = error.diagnostic();
        diagnostic.code = code.into();
        diagnostic.guidance = Some(guidance.into());
        let mut current = self.managed.diagnostic.lock().await;
        if current.is_none() || current.as_ref() == self.save_diagnostic.as_ref() {
            *current = Some(diagnostic.clone());
            self.save_diagnostic = Some(diagnostic);
        }
        drop(current);
        self.changed();
    }

    async fn saved(&mut self) {
        if let Some(ours) = self.save_diagnostic.take() {
            let mut current = self.managed.diagnostic.lock().await;
            if current.as_ref() == Some(&ours) {
                *current = None;
            }
        }
        self.changed();
    }

    fn changed(&self) {
        self.managed.audience_changed();
        self.runtime.request_publish();
    }
}

// Poll the prepared HTTP action first. Once polled, cancellation is an uncertain attempted POST;
// cancellations before execution are handled by begin(), retaining NotStarted.
async fn attempt<T>(
    future: impl std::future::Future<Output = Result<T, PostFailure>>,
    cancel: &CancellationToken,
    runtime_cancel: &CancellationToken,
) -> Attempt<T> {
    tokio::select! { biased; result = future => Attempt::Response(result), _ = cancel.cancelled() => Attempt::Cancelled, _ = runtime_cancel.cancelled() => Attempt::Cancelled }
}

fn fact_unknown(fact: &super::storage::SendSegmentFact) -> bool {
    matches!(
        fact.upload,
        Some(UploadFact::InFlight | UploadFact::Unknown)
    ) || matches!(
        fact.message_stage,
        Some(MessageStage::InFlight | MessageStage::Unknown)
    )
}

pub(super) fn replay_send(existing: SendRecord) -> BotSendResult {
    let uncertain_stage = existing.segments.iter().any(|fact| {
        fact.upload == Some(UploadFact::InFlight)
            || fact.message_stage == Some(MessageStage::InFlight)
    });
    let facts_complete = existing.facts_complete;
    let is_file_operation = matches!(existing.identity, SendIdentity::File { .. });
    let operation_id = existing.operation_id;
    BotSendResult {
        operation_id: operation_id.clone(),
        bot_id: existing.bot_id,
        chat_id: existing.chat_id,
        status: if uncertain_stage {
            BotSendStatus::Unknown
        } else {
            product_status(existing.status)
        },
        segments: existing
            .segments
            .into_iter()
            .map(|fact| {
                let in_flight = matches!(fact.upload, Some(UploadFact::InFlight))
                    || fact.message_stage == Some(MessageStage::InFlight);
                let upload_stage = match &fact.upload {
                    Some(UploadFact::NotStarted) => Some(BotSendStage::NotStarted),
                    Some(UploadFact::Accepted { .. }) => Some(BotSendStage::Accepted),
                    Some(UploadFact::Rejected) => Some(BotSendStage::Rejected),
                    Some(UploadFact::InFlight | UploadFact::Unknown) => Some(BotSendStage::Unknown),
                    None if is_file_operation
                        || matches!(fact.content, Some(SendContent::File { .. })) =>
                    {
                        Some(BotSendStage::Unknown)
                    }
                    None => None,
                };
                let message_stage = match fact.message_stage {
                    Some(MessageStage::NotStarted) => BotSendStage::NotStarted,
                    Some(MessageStage::Accepted) => BotSendStage::Accepted,
                    Some(MessageStage::Rejected) => BotSendStage::Rejected,
                    Some(MessageStage::InFlight | MessageStage::Unknown) => BotSendStage::Unknown,
                    None if fact
                        .platform_message_id
                        .as_ref()
                        .is_some_and(|id| !id.is_empty()) =>
                    {
                        BotSendStage::Accepted
                    }
                    None => BotSendStage::Unknown,
                };
                let diagnostic = fact.platform_diagnostic.or_else(|| {
                    let message = if in_flight {
                        Some("上传或消息请求结果未知；不会自动重新 POST".into())
                    } else {
                        fact.diagnostic
                    }?;
                    Some(BotDiagnostic {
                        code: "sendSegment".into(),
                        message,
                        retryable: false,
                        platform_code: None,
                        guidance: (!facts_complete).then(|| "legacySegmentFactsUnproven".into()),
                    })
                });
                BotSendSegment {
                    index: fact.index,
                    status: if in_flight {
                        BotSendStatus::Unknown
                    } else {
                        product_status(fact.status)
                    },
                    upload_stage,
                    message_stage,
                    stop_reason: fact.stop_reason,
                    platform_message_id: fact.platform_message_id,
                    diagnostic,
                }
            })
            .collect(),
        receipt: StudioCommandReceipt {
            operation_id,
            disposition: CommandDisposition::NoChange,
            targets: Vec::new(),
            effect: CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
    }
}

fn product_status(status: SendRecordStatus) -> BotSendStatus {
    match status {
        SendRecordStatus::Succeeded => BotSendStatus::Succeeded,
        SendRecordStatus::Partial => BotSendStatus::Partial,
        SendRecordStatus::Rejected => BotSendStatus::Rejected,
        SendRecordStatus::Unknown => BotSendStatus::Unknown,
    }
}
