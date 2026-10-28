//! Shared command/tool/reply send admission; one operation ledger and occupancy owner.
use super::commands::ChatMembership;
use super::delivery::{SendExecution, replay_send};
use super::occupancy::OccupancyBudget;
use super::owner::ManagedBot;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::{SendContent, SendIdentity, SendPlan, markdown_hash};
use super::send_resources::SendInput;
use super::storage::PublicationFilePermit;
use super::storage::publication::DeliveryScope;
use super::storage::{MessageStage, SendRecord, SendRecordStatus, SendSegmentFact, UploadFact};
use super::{BotRuntime, SendAuthority};
use pl_protocol::studio::{BotSendResult, BotSendStopReason, ResourceStamp};
use tokio_util::sync::CancellationToken;

/// Read-only authorization/token preparation precedes any durable resource production.
pub(super) struct SendAdmission {
    pub(super) managed: std::sync::Arc<ManagedBot>,
    pub(super) app_id: String,
    pub(super) project_id: String,
    pub(super) revision: u64,
    pub(super) membership: ChatMembership,
}

pub(super) struct PreparedSend {
    admission: SendAdmission,
    token: String,
}

pub(super) struct SendRequest {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub input: SendInput,
    pub authority: SendAuthority,
}

impl BotRuntime {
    /// Covers source/read/Arc/multipart copies without putting file bytes in occupancy.
    pub(super) fn reserve_send_bytes(
        &self,
        bytes: usize,
    ) -> Result<tokio::sync::OwnedSemaphorePermit, FeishuError> {
        let amount = bytes
            .checked_mul(3)
            .and_then(|n| u32::try_from(n).ok())
            .ok_or_else(super::occupancy::freeze_budget_error)?;
        self.inner
            .send_bytes
            .clone()
            .try_acquire_many_owned(amount)
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Busy,
                    "outgoing file byte budget is full",
                    true,
                    None,
                )
            })
    }

    pub(super) fn check_send_active(&self, cancel: &CancellationToken) -> Result<(), FeishuError> {
        if cancel.is_cancelled()
            || self.inner.reply_cancel.is_cancelled()
            || self.inner.sealed.load(std::sync::atomic::Ordering::Acquire) != 0
        {
            Err(FeishuError::cancelled())
        } else {
            Ok(())
        }
    }

    pub(super) async fn prepare_send_admission(
        &self,
        bot_id: &str,
        chat_id: &str,
        authority: &SendAuthority,
        cancel: &CancellationToken,
    ) -> Result<PreparedSend, FeishuError> {
        self.check_send_active(cancel)?;
        let managed = self.managed(bot_id).await;
        self.check_send_active(cancel)?;
        let managed = managed?;
        let config = managed.config.lock().await.clone();
        self.check_send_active(cancel)?;
        self.authorize_send_source(&config, chat_id, authority)?;
        let membership = self
            .prepare_chat_access(&managed, &config, chat_id, cancel)
            .await;
        self.check_send_active(cancel)?;
        let membership = membership?;
        self.authorize_chat(&config, chat_id, authority.clone(), &membership)?;
        let token = self.token(&managed, &config).await;
        self.check_send_active(cancel)?;
        let token = token?;
        // Both read-only network steps can cross revocation. Recheck before any archive, then
        // the existing claim gate checks this identity/revision again immediately before commit.
        let current = managed.config.lock().await;
        self.check_send_active(cancel)?;
        self.authorize_chat(&current, chat_id, authority.clone(), &membership)?;
        if current.config_revision != config.config_revision {
            return Err(conflict());
        }
        drop(current);
        Ok(PreparedSend {
            admission: SendAdmission {
                managed,
                app_id: config.feishu().app_id.clone(),
                project_id: config.project_id,
                revision: config.config_revision,
                membership,
            },
            token,
        })
    }

    pub async fn send_message(
        &self,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
        owner_epoch: &str,
    ) -> Result<BotSendResult, FeishuError> {
        self.send_message_as(
            operation_id,
            bot_id,
            chat_id,
            text,
            owner_epoch,
            SendAuthority::Owner,
        )
        .await
    }

    pub(super) async fn send_message_as(
        &self,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
        owner_epoch: &str,
        authority: SendAuthority,
    ) -> Result<BotSendResult, FeishuError> {
        let cancel = &self.inner.reply_cancel;
        self.check_send_active(cancel)?;
        let managed = self.managed(&bot_id).await;
        self.check_send_active(cancel)?;
        let managed = managed?;
        // Detect legacy text BEFORE constructing a Markdown plan. Its original hash and receipt
        // survive upgrades; a new file request can never use this legacy interpretation.
        let existing = managed.store.load_send(&operation_id).await;
        self.check_send_active(cancel)?;
        if let Some(existing) = existing? {
            let hash = match &existing.identity {
                SendIdentity::LegacyText => {
                    super::protocol::im::content_hash(&operation_id, &chat_id, &text)
                }
                SendIdentity::Markdown { request_hash } => {
                    if &markdown_hash(&operation_id, &bot_id, &chat_id, &text)? != request_hash
                        || existing.source.is_some()
                    {
                        return Err(conflict());
                    }
                    existing.content_hash.clone()
                }
                SendIdentity::File { .. } | SendIdentity::InboundNotice { .. } => {
                    return Err(conflict());
                }
            };
            super::storage::verify_send_identity(
                &existing,
                &operation_id,
                &bot_id,
                &chat_id,
                &hash,
            )?;
            self.authorize_replay_source(&managed, &authority, cancel)
                .await?;
            self.check_send_active(cancel)?;
            return Ok(self
                .stamp_send(replay_send(existing), &managed, owner_epoch)
                .await);
        }
        let admission = self
            .prepare_send_admission(&bot_id, &chat_id, &authority, cancel)
            .await?;
        let encoded_budget = text
            .len()
            .checked_add(text.len().min(super::protocol::POST_CONTENT_LIMIT_BYTES) * 6 + 512)
            .ok_or_else(super::occupancy::freeze_budget_error)?;
        let bytes_budget = self.reserve_send_bytes(encoded_budget)?;
        self.check_send_active(cancel)?;
        self.send_production(
            SendRequest {
                operation_id,
                bot_id,
                chat_id,
                input: SendInput::Markdown(text),
                authority,
            },
            admission,
            bytes_budget,
            owner_epoch,
            cancel,
        )
        .await
    }

    pub(super) async fn send_production(
        &self,
        request: SendRequest,
        prepared: PreparedSend,
        bytes_budget: tokio::sync::OwnedSemaphorePermit,
        owner_epoch: &str,
        cancel: &CancellationToken,
    ) -> Result<BotSendResult, FeishuError> {
        self.check_send_active(cancel)?;
        let text_bytes = super::occupancy::counted_extra_bytes(
            production_freeze_bytes(&request, &prepared.admission)?,
            [(owner_epoch.len(), 2)],
        )?;
        let worker = self.clone();
        let cancellation = cancel.clone();
        let owner_epoch = owner_epoch.to_owned();
        self.submit_occupancy(text_bytes, move |mut budget| async move {
            // One registration holds source/archive/claim, HTTP and all result saves. The
            // bytes and metadata permits cannot expire between claim and the first POST.
            let (mut result, revision) = worker
                .send_production_owned(
                    request,
                    prepared,
                    Some(bytes_budget),
                    cancellation,
                    &mut budget,
                    None,
                )
                .await?;
            result.receipt.targets = vec![ResourceStamp {
                resource_key: format!("bot:{}", result.bot_id),
                owner_epoch,
                revision,
            }];
            Ok(result)
        })
        .await
    }

    /// Internal automatic file entry. O supplies the stable operation and original binding;
    /// the registered owner holds the original Studio host, never a reopened source store.
    /// Caller drop only abandons its wait. Even an unconfirmed result save retains the attempt
    /// in occupancy; the returned error/diagnostic requests root-owned close/recovery handling.
    pub(in crate::bots) async fn send_public_artifact(
        &self,
        operation_id: String,
        scope: DeliveryScope,
        permit: PublicationFilePermit,
        cancel: CancellationToken,
    ) -> Result<BotSendResult, FeishuError> {
        self.check_send_active(&cancel)?;
        if operation_id.is_empty() {
            return Err(conflict());
        }
        let authority = self.publication_send_authority(scope, permit).await?;
        let bytes = super::occupancy::counted_extra_bytes(
            authority.freeze_bytes(8)?,
            [(operation_id.len(), 8)],
        )?;
        let worker = self.clone();
        let source_host = self.studio_host();
        let (failed_save, failure) = tokio::sync::oneshot::channel();
        let completion = self.submit_occupancy(bytes, move |mut budget| async move {
            let managed = worker.managed(&authority.scope.bot_id).await?;
            if let Some(record) = managed.store.load_send(&operation_id).await? {
                worker
                    .verify_public_artifact_binding(&managed, &record, &operation_id, &authority)
                    .await?;
                if !publication_can_resume(&record) {
                    return Ok(replay_send(record));
                }
                let authority = SendAuthority::Publication(Box::new(authority));
                let prepared = worker
                    .prepare_send_admission(&record.bot_id, &record.chat_id, &authority, &cancel)
                    .await?;
                return worker
                    .deliver_claimed(
                        &prepared.token,
                        &managed,
                        record,
                        SendExecution {
                            authority: &authority,
                            cancel: &cancel,
                            bytes_budget: None,
                            failed_save: Some(failed_save),
                        },
                    )
                    .await;
            }
            let send_authority = SendAuthority::Publication(Box::new(authority.clone()));
            let prepared = worker
                .prepare_send_admission(
                    &authority.scope.bot_id,
                    &authority.scope.chat_id,
                    &send_authority,
                    &cancel,
                )
                .await?;
            let (bytes, bytes_budget) = worker
                .read_public_artifact_owned(&managed, &authority, source_host.as_deref(), &cancel)
                .await?;
            let request = SendRequest {
                operation_id,
                bot_id: authority.scope.bot_id.clone(),
                chat_id: authority.scope.chat_id.clone(),
                input: SendInput::PublicArtifact {
                    scope: Box::new(authority.scope),
                    artifact: Box::new(authority.permit.artifact),
                    bytes,
                },
                authority: send_authority,
            };
            budget.reserve_more(production_freeze_bytes(&request, &prepared.admission)?)?;
            worker
                .send_production_owned(
                    request,
                    prepared,
                    Some(bytes_budget),
                    cancel,
                    &mut budget,
                    Some(failed_save),
                )
                .await
                .map(|(result, _)| result)
        });
        tokio::select! {
            biased;
            result = completion => result,
            Ok(error) = failure => Err(error),
        }
    }

    async fn send_production_owned(
        &self,
        request: SendRequest,
        prepared: PreparedSend,
        bytes_budget: Option<tokio::sync::OwnedSemaphorePermit>,
        cancel: CancellationToken,
        budget: &mut OccupancyBudget,
        failed_save: Option<tokio::sync::oneshot::Sender<FeishuError>>,
    ) -> Result<(BotSendResult, u64), FeishuError> {
        match (&request.authority, &request.input) {
            (
                SendAuthority::Publication(authority),
                SendInput::PublicArtifact {
                    scope, artifact, ..
                },
            ) if **scope == authority.scope && artifact.as_ref() == &authority.permit.artifact => {}
            (SendAuthority::Publication(_), _) | (_, SendInput::PublicArtifact { .. }) => {
                return Err(conflict());
            }
            _ => {}
        }
        let authority = request.authority.clone();
        let PreparedSend { admission, token } = prepared;
        let managed = admission.managed.clone();
        let claimed = self
            .produce_send_owned(request, admission, cancel.clone(), budget)
            .await?;
        if matches!(&claimed.record.identity, SendIdentity::InboundNotice { .. }) {
            return Err(conflict());
        }
        if let SendAuthority::Publication(publication) = &authority {
            self.verify_public_artifact_binding(
                &managed,
                &claimed.record,
                &claimed.record.operation_id,
                publication,
            )
            .await?;
            managed.audience_changed();
            self.request_publish();
        }
        let resume = matches!(authority, SendAuthority::Publication(_))
            && publication_can_resume(&claimed.record);
        let result = if claimed.replay && !resume {
            replay_send(claimed.record)
        } else {
            self.deliver_claimed(
                &token,
                &managed,
                claimed.record,
                SendExecution {
                    authority: &authority,
                    cancel: &cancel,
                    bytes_budget,
                    failed_save,
                },
            )
            .await?
        };
        Ok((result, claimed.revision))
    }

    async fn verify_public_artifact_binding(
        &self,
        managed: &ManagedBot,
        record: &SendRecord,
        operation_id: &str,
        authority: &super::PublicationSendAuthority,
    ) -> Result<(), FeishuError> {
        super::send::verify_public_artifact_record(record, operation_id, authority)?;
        let entity = managed
            .store
            .delivery_entity(&authority.scope.key, &authority.permit.entity)
            .await?
            .ok_or_else(conflict)?;
        let binding = entity.state.file_operation.ok_or_else(conflict)?;
        if binding.operation_id != operation_id
            || binding.artifact != authority.permit.artifact
            || binding.content_hash != record.content_hash
            || binding.uuid != record.segments[0].uuid
        {
            return Err(conflict());
        }
        Ok(())
    }

    /// Read-only confirmation after an unpolled request's admission/correction failed. Mutable
    /// stages come only from the ledger; matching identity is not permission to start HTTP.
    pub(super) async fn confirm_send_record(
        &self,
        managed: &ManagedBot,
        expected: &SendRecord,
        authority: &SendAuthority,
    ) -> Result<SendRecord, FeishuError> {
        let current = managed
            .store
            .load_send(&expected.operation_id)
            .await?
            .ok_or_else(conflict)?;
        super::storage::verify_send_identity(
            &current,
            &expected.operation_id,
            &expected.bot_id,
            &expected.chat_id,
            &expected.content_hash,
        )?;
        if current.identity != expected.identity
            || current.source != expected.source
            || current.facts_complete != expected.facts_complete
            || current.segments.len() != expected.segments.len()
            || current
                .segments
                .iter()
                .zip(&expected.segments)
                .any(|(current, expected)| {
                    current.index != expected.index
                        || current.uuid != expected.uuid
                        || current.content != expected.content
                })
        {
            return Err(conflict());
        }
        if let SendAuthority::Publication(publication) = authority {
            self.verify_public_artifact_binding(
                managed,
                &current,
                &expected.operation_id,
                publication,
            )
            .await?;
        }
        Ok(current)
    }

    pub(super) async fn stamp_send(
        &self,
        mut result: BotSendResult,
        managed: &super::owner::ManagedBot,
        owner_epoch: &str,
    ) -> BotSendResult {
        result.receipt.targets = vec![ResourceStamp {
            resource_key: format!("bot:{}", result.bot_id),
            owner_epoch: owner_epoch.into(),
            revision: managed.config.lock().await.config_revision,
        }];
        result
    }
}

/// Only automatic frontend files may continue these facts. The initial aggregate Unknown is
/// not itself an attempted request: exact upload/message stages are the authority for resuming.
fn publication_can_resume(record: &SendRecord) -> bool {
    let [fact] = record.segments.as_slice() else {
        return false;
    };
    record.facts_complete
        && record.source.is_none()
        && matches!(record.identity, SendIdentity::File { .. })
        && fact.message_stage == Some(MessageStage::NotStarted)
        && matches!(
            fact.upload,
            Some(UploadFact::NotStarted | UploadFact::Accepted { .. })
        )
        && matches!(fact.stop_reason, None | Some(BotSendStopReason::Cancelled))
        && fact.platform_diagnostic.is_none()
        && fact.platform_message_id.is_none()
        && record.platform_message_ids.is_empty()
}

pub(super) fn conflict() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "operationId already used with different content, type or source",
        false,
        None,
    )
}

pub(super) fn into_record(
    operation_id: String,
    bot_id: String,
    chat_id: String,
    plan: SendPlan,
) -> SendRecord {
    let notice = matches!(&plan.identity, SendIdentity::InboundNotice { .. });
    let segments = plan
        .segments
        .into_iter()
        .zip(plan.uuids)
        .enumerate()
        .map(|(index, (content, uuid))| {
            let upload =
                matches!(content, SendContent::File { .. }).then_some(UploadFact::NotStarted);
            SendSegmentFact {
                index: index as u32,
                uuid,
                status: SendRecordStatus::Unknown,
                platform_message_id: None,
                diagnostic: None,
                content: Some(content),
                upload,
                message_stage: Some(MessageStage::NotStarted),
                notice_attempt: notice.then_some(0),
                platform_diagnostic: None,
                stop_reason: None,
            }
        })
        .collect();
    SendRecord {
        operation_id,
        bot_id,
        chat_id,
        content_hash: plan.content_hash,
        identity: plan.identity,
        source: plan.source,
        segments,
        status: SendRecordStatus::Unknown,
        platform_message_ids: Vec::new(),
        facts_complete: true,
    }
}

fn production_freeze_bytes(
    request: &SendRequest,
    admission: &SendAdmission,
) -> Result<usize, FeishuError> {
    let mut bytes = super::occupancy::counted_text_bytes([
        (request.operation_id.as_str(), 3),
        (request.bot_id.as_str(), 3),
        (request.chat_id.as_str(), 3),
        (admission.app_id.as_str(), 2),
        (admission.project_id.as_str(), 2),
    ])?;
    let metadata = match &request.input {
        SendInput::Markdown(_) => 0,
        SendInput::PublicArtifact {
            scope, artifact, ..
        } => {
            let metadata = serde_json::to_vec(artifact.as_ref())
                .map_err(|_| super::occupancy::freeze_budget_error())?;
            super::occupancy::counted_extra_bytes(
                0,
                [
                    (metadata.len(), 4),
                    (scope.bot_id.len(), 4),
                    (scope.chat_id.len(), 4),
                    (scope.thread_id.len(), 4),
                    (scope.app_id.len(), 4),
                    (scope.project_id.len(), 4),
                    (scope.creation_id.len(), 4),
                ],
            )?
        }
    };
    bytes = super::occupancy::counted_extra_bytes(bytes, [(metadata, 1)])?;
    match &request.authority {
        SendAuthority::Tool { project_id } => {
            super::occupancy::counted_extra_bytes(bytes, [(project_id.len(), 2)])
        }
        SendAuthority::InboundReply(reply) => {
            super::occupancy::counted_extra_bytes(bytes, [(reply.freeze_bytes(4)?, 1)])
        }
        SendAuthority::Publication(publication) => {
            super::occupancy::counted_extra_bytes(bytes, [(publication.freeze_bytes(4)?, 1)])
        }
        SendAuthority::Owner => Ok(bytes),
    }
}
