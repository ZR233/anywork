//! Shared command/tool/reply send admission; one operation ledger and occupancy owner.
use super::commands::ChatMembership;
use super::delivery::replay_send;
use super::owner::ManagedBot;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::{SendContent, SendIdentity, SendPlan, markdown_hash};
use super::send_resources::SendInput;
use super::storage::{MessageStage, SendRecord, SendRecordStatus, SendSegmentFact, UploadFact};
use super::{BotRuntime, SendAuthority};
use pl_protocol::studio::{BotSendResult, ResourceStamp};
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

    pub(crate) async fn send_message_as(
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
                SendIdentity::File { .. } => return Err(conflict()),
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
        let PreparedSend { admission, token } = prepared;
        let managed = admission.managed.clone();
        let text_bytes = production_freeze_bytes(&request, &admission)?;
        let worker = self.clone();
        let cancellation = cancel.clone();
        let claimed = self
            .submit_occupancy(text_bytes, move |budget| async move {
                // This permit and the registered task survive caller drop through retain/claim/GC.
                let _bytes_budget = bytes_budget;
                worker
                    .produce_send_owned(request, admission, cancellation, budget)
                    .await
            })
            .await?;
        let mut result = if claimed.replay {
            replay_send(claimed.record)
        } else {
            self.deliver_claimed(&token, &managed.store, claimed.record, cancel)
                .await?
        };
        result.receipt.targets = vec![ResourceStamp {
            resource_key: format!("bot:{}", result.bot_id),
            owner_epoch: owner_epoch.into(),
            revision: claimed.revision,
        }];
        Ok(result)
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
        SendInput::File {
            request_hash,
            source,
            filename,
            ..
        } => {
            let source_bytes = serde_json::to_vec(source)
                .map_err(|_| super::occupancy::freeze_budget_error())?
                .len();
            super::occupancy::counted_extra_bytes(
                0,
                [
                    (source_bytes, 3),
                    (request_hash.len(), 3),
                    (filename.len(), 3),
                ],
            )?
        }
    };
    bytes = super::occupancy::counted_extra_bytes(bytes, [(metadata, 1)])?;
    match &request.authority {
        SendAuthority::Source(source) => {
            let source_bytes = serde_json::to_vec(source)
                .map_err(|_| super::occupancy::freeze_budget_error())?
                .len();
            super::occupancy::counted_extra_bytes(bytes, [(source_bytes, 3)])
        }
        SendAuthority::Tool { project_id } => {
            super::occupancy::counted_extra_bytes(bytes, [(project_id.len(), 2)])
        }
        SendAuthority::Owner | SendAuthority::AutoReply => Ok(bytes),
    }
}
