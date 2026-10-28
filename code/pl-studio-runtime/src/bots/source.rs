//! Source identity/trust and exact Saved-original reads. Frontend publication and inbound/tool
//! grants remain distinct; neither resource availability nor a constructor grants a new write.

use super::config::BotConfigFile;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::SendSource;
use super::storage::publication::DeliveryFilePreparationBlock;
use pl_core::context::{ResourceReadError, ResourceReference};
use tokio_util::sync::CancellationToken;

impl super::BotRuntime {
    /// 从原创建归属取得目标种类；信任名单不能作为聊天种类的证据。
    pub(in crate::bots) async fn publication_send_authority(
        &self,
        scope: super::storage::publication::DeliveryScope,
        permit: super::storage::PublicationFilePermit,
    ) -> Result<super::PublicationSendAuthority, FeishuError> {
        let managed = self.managed(&scope.bot_id).await?;
        let audience = managed
            .store
            .audience_scope(&scope.thread_id, &scope.bot_id)
            .await?
            .ok_or_else(|| denied("public artifact has no proven creation origin"))?;
        let origin = audience.origin;
        if origin.requires_upgrade
            || origin.thread_id != scope.thread_id
            || origin.chat_id != scope.chat_id
            || origin.project_id != scope.project_id
            || origin.creation_id != scope.creation_id
            || origin.binding_revision != scope.binding_revision
        {
            return Err(denied(
                "public artifact creation origin does not match its scope",
            ));
        }
        if let super::storage::target::TargetProof::Created { evidence } = &origin.target
            && (evidence.bot_id != scope.bot_id || evidence.app_id != scope.app_id)
        {
            return Err(denied(
                "public artifact creation target belongs to another app",
            ));
        }
        let target = origin
            .target
            .kind()
            .cloned()
            .ok_or_else(|| denied("public artifact target kind is unproven"))?;
        let authority = super::PublicationSendAuthority {
            scope,
            permit,
            target,
        };
        let config = managed.config.lock().await;
        authorize_publication_identity(&config, &authority.scope.chat_id, &authority)?;
        Ok(authority)
    }

    /// The caller is the registered send owner. Reserve once for the source read, retained copy
    /// and multipart peak, then transfer that same permit through archive and HTTP settlement.
    pub(super) async fn read_public_artifact_owned(
        &self,
        managed: &super::owner::ManagedBot,
        authority: &super::PublicationSendAuthority,
        source_host: Option<&crate::studio::StudioRuntime>,
        cancel: &CancellationToken,
    ) -> Result<(std::sync::Arc<[u8]>, tokio::sync::OwnedSemaphorePermit), FeishuError> {
        self.check_send_active(cancel)?;
        let artifact = &authority.permit.artifact;
        let metadata = artifact.resource();
        if metadata.byte_len == 0
            || metadata.byte_len > super::protocol::FILE_UPLOAD_LIMIT_BYTES as u64
        {
            // S already derives this channel-only Blocked state from the canonical original.
            return Err(super::send::rejected(
                "file upload requires 1..=30,000,000 bytes",
            ));
        }
        let budget = match self.reserve_send_bytes(metadata.byte_len as usize) {
            Ok(budget) => budget,
            Err(error) => {
                return Err(self
                    .block_public_artifact_preparation(
                        managed,
                        authority,
                        cancel,
                        DeliveryFilePreparationBlock::BudgetUnavailable,
                        error,
                    )
                    .await);
            }
        };
        let reference = ResourceReference::new(
            metadata.id.clone(),
            metadata.content_digest.clone(),
            metadata.byte_len,
            metadata.media_type.clone(),
        )
        .map_err(|error| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "Saved public artifact resource identity is invalid",
                false,
                None,
            )
            .with_source(error)
        })?;
        let read = async {
            let host = source_host.ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "Studio public artifact source host is unavailable",
                    true,
                    None,
                )
            })?;
            // The host validates Thread ownership and the exact reference through the original
            // resource reader, including its length/digest check; no Vec copy or path fallback.
            host.read_thread_resource_exact(artifact.thread_id(), reference, cancel.clone())
                .await
                .map_err(|error| {
                    if matches!(error, ResourceReadError::Cancelled) {
                        FeishuError::cancelled().with_source(error)
                    } else {
                        FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            "Saved public artifact original is unavailable or invalid",
                            false,
                            None,
                        )
                        .with_source(error)
                    }
                })
        }
        .await;
        // A cancellation/closed runtime is not evidence of a damaged source.
        self.check_send_active(cancel)?;
        match read {
            Ok(bytes) => Ok((bytes, budget)),
            Err(error) if error.kind() == FeishuErrorKind::Cancelled => Err(error),
            Err(error) => Err(self
                .block_public_artifact_preparation(
                    managed,
                    authority,
                    cancel,
                    DeliveryFilePreparationBlock::SourceUnavailable,
                    error,
                )
                .await),
        }
    }

    async fn block_public_artifact_preparation(
        &self,
        managed: &super::owner::ManagedBot,
        authority: &super::PublicationSendAuthority,
        cancel: &CancellationToken,
        reason: DeliveryFilePreparationBlock,
        primary: FeishuError,
    ) -> FeishuError {
        let result = async {
            let _admission = managed.admission.lock().await;
            self.check_send_active(cancel)?;
            self.reject_closed_admission(managed)?;
            let current = managed.config.lock().await;
            authorize_publication_identity(&current, &authority.scope.chat_id, authority)?;
            drop(current);
            let permit = &authority.permit;
            managed
                .store
                .block_delivery_file_preparation(
                    &permit.token,
                    &permit.entity,
                    permit.expected_ledger_version,
                    &permit.artifact,
                    reason,
                )
                .await?;
            managed.audience_changed();
            self.request_publish();
            Ok::<_, FeishuError>(())
        }
        .await;
        match result {
            Ok(()) => primary,
            Err(settlement) => FeishuError::new(
                settlement.kind(),
                "public artifact preparation failed; its item-local Blocked settlement is unconfirmed",
                settlement.retryable(),
                None,
            ).with_source(PreparationSettlementFailure { primary, settlement }),
        }
    }
}

#[derive(Debug, thiserror::Error)]
#[error("public artifact preparation and its item-local settlement failed: {settlement}")]
struct PreparationSettlementFailure {
    #[source]
    primary: FeishuError,
    settlement: FeishuError,
}

/// A finite legacy reply may have distinct creation and Thread IDs. Its actual binding and worker
/// lease are fenced separately at intent; app/project/trust must still be current for every write.
pub(super) fn authorize_source_identity(
    config: &BotConfigFile,
    chat_id: &str,
    source: &SendSource,
) -> Result<(), FeishuError> {
    if !config.enabled
        || config.id != source.bot_id
        || config.feishu().app_id != source.app_id
        || config.project_id != source.project_id
        || chat_id != source.chat_id
    {
        return Err(denied(
            "bot source identity is disabled, changed or no longer applicable",
        ));
    }
    let trusted = match source.chat_kind.as_str() {
        "direct" => config.feishu().trusted_open_ids.contains(&source.open_id),
        "group" => config.feishu().trusted_chat_ids.contains(&source.chat_id),
        _ => false,
    };
    if !trusted {
        return Err(denied("the original bot source trust has been revoked"));
    }
    Ok(())
}

fn denied(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Permission, message, false, None)
}

/// 平台自动投递与工具开关独立；数据库围栏另外核当前授权、绑定与认领。
pub(super) fn authorize_publication_identity(
    config: &BotConfigFile,
    chat_id: &str,
    authority: &super::PublicationSendAuthority,
) -> Result<(), FeishuError> {
    let scope = &authority.scope;
    let permit = &authority.permit;
    if !config.enabled
        || !scope.key.is_frontend()
        || scope.needs_recovery
        || config.id != scope.bot_id
        || chat_id != scope.chat_id
        || config.feishu().app_id != scope.app_id
        || config.project_id != scope.project_id
        || permit.token.scope != scope.key
        || permit.artifact.thread_id() != scope.thread_id
        || permit.artifact.entity_key() != permit.entity
    {
        return Err(denied(
            "public artifact source identity is disabled, changed or inconsistent",
        ));
    }
    let trusted = match &authority.target {
        super::storage::target::TargetKind::Group => {
            config.feishu().trusted_chat_ids.contains(chat_id)
        }
        super::storage::target::TargetKind::Direct { open_id } => {
            config.feishu().trusted_open_ids.contains(open_id)
        }
    };
    if !trusted {
        return Err(denied("public artifact target trust has been revoked"));
    }
    Ok(())
}
