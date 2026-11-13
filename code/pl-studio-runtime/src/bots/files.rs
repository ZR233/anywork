//! File progress lives in the original send ledger, under the original reply owner.

use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::SendRate;
use super::storage::{BotStateStore, SendRecord, SendRecordStatus, SendSegmentFact};
use super::{
    SendAuthority,
    owner::BotRuntime,
    storage::{ClaimLease, FrozenInbound},
};
use crate::channel_output::{
    ChannelDeliveryResult, ChannelOutputBinding, ChannelOutputPort, PlatformMessageId,
};
use crate::channel_output::{
    ChannelError, ChannelRegistry, ChannelTarget, FileDelivery, UploadHandle,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

/// Source assembly for today's Feishu inbound owner. No credential access or HTTP
/// occurs here; another source chooses its own binding at this same boundary.
pub(super) fn feishu_reply_binding(
    runtime: BotRuntime,
    inbound: &FrozenInbound,
    worker_id: &str,
) -> ChannelOutputBinding {
    ChannelOutputBinding::new(
        ChannelTarget {
            adapter: "feishu".into(),
            account_id: inbound.bot_id.clone(),
            conversation_id: inbound.chat_id.clone(),
        },
        FeishuOutputPort {
            runtime,
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            worker_id: worker_id.into(),
        },
    )
}

struct FeishuOutputPort {
    runtime: BotRuntime,
    bot_id: String,
    chat_id: String,
    message_id: String,
    worker_id: String,
}

impl FeishuOutputPort {
    async fn authorize(
        &self,
        target: &ChannelTarget,
        cancel: &CancellationToken,
    ) -> Result<(), ChannelDeliveryResult> {
        if cancel.is_cancelled()
            || target.adapter != "feishu"
            || target.account_id != self.bot_id
            || target.conversation_id != self.chat_id
        {
            return Err(ChannelDeliveryResult::Rejected {
                diagnostic: "file output source is cancelled or target conflicts with its binding"
                    .into(),
                retryable: false,
            });
        }
        let managed = self
            .runtime
            .managed(&self.bot_id)
            .await
            .map_err(preflight_error)?;
        match managed
            .store
            .renew_inbound_claim(
                &self.bot_id,
                &self.chat_id,
                &self.message_id,
                &self.worker_id,
            )
            .await
            .map_err(preflight_error)?
        {
            ClaimLease::Renewed => Ok(()),
            ClaimLease::LostClaim => Err(ChannelDeliveryResult::Rejected {
                diagnostic: "file output source no longer holds its inbound claim".into(),
                retryable: false,
            }),
        }
    }

    async fn failed_send(&self, operation: &str, error: FeishuError) -> ChannelDeliveryResult {
        if !error.acceptance_unknown() {
            return preflight_error(error);
        }
        // Credential/token preparation can fail before a durable send intent.
        // Preserve its retryability without labelling a known unattempted send Unknown.
        // Once an intent exists (or cannot be read), do not claim non-acceptance.
        if let Ok(managed) = self.runtime.managed(&self.bot_id).await
            && matches!(managed.store.send_exists(operation).await, Ok(false))
        {
            return preflight_error(error);
        }
        ChannelDeliveryResult::Unknown {
            diagnostic: error.to_string(),
        }
    }
}

fn preflight_error(error: FeishuError) -> ChannelDeliveryResult {
    ChannelDeliveryResult::Rejected {
        diagnostic: error.to_string(),
        retryable: error.retryable(),
    }
}

impl ChannelOutputPort for FeishuOutputPort {
    async fn send_caption(
        &self,
        target: &ChannelTarget,
        operation: &str,
        caption: &str,
        cancel: &CancellationToken,
    ) -> ChannelDeliveryResult {
        if let Err(result) = self.authorize(target, cancel).await {
            return result;
        }
        match self
            .runtime
            .send_message_as(
                operation.into(),
                target.account_id.clone(),
                target.conversation_id.clone(),
                caption.into(),
                "auto-reply",
                SendAuthority::AutoReply,
            )
            .await
        {
            Ok(result) => match result.status {
                pl_protocol::studio::BotSendStatus::Succeeded => ChannelDeliveryResult::Confirmed {
                    message_ids: result
                        .segments
                        .into_iter()
                        .filter_map(|segment| segment.platform_message_id)
                        .map(PlatformMessageId)
                        .collect(),
                },
                pl_protocol::studio::BotSendStatus::Unknown => ChannelDeliveryResult::Unknown {
                    diagnostic: "caption message acceptance is unknown".into(),
                },
                pl_protocol::studio::BotSendStatus::Rejected
                | pl_protocol::studio::BotSendStatus::Partial => ChannelDeliveryResult::Rejected {
                    diagnostic: "caption delivery was rejected or only partially confirmed".into(),
                    retryable: false,
                },
            },
            Err(error) => self.failed_send(operation, error).await,
        }
    }

    async fn send_file(
        &self,
        target: &ChannelTarget,
        operation: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
        cancel: &CancellationToken,
    ) -> ChannelDeliveryResult {
        if let Err(result) = self.authorize(target, cancel).await {
            return result;
        }
        match self
            .runtime
            .send_file_as(
                operation.into(),
                target.clone(),
                file.clone(),
                bytes,
                cancel,
            )
            .await
        {
            Ok(record) => match record.status {
                SendRecordStatus::Succeeded => ChannelDeliveryResult::Confirmed {
                    message_ids: record
                        .platform_message_ids
                        .into_iter()
                        .map(PlatformMessageId)
                        .collect(),
                },
                SendRecordStatus::Unknown => ChannelDeliveryResult::Unknown {
                    diagnostic: "file upload or message acceptance is unknown".into(),
                },
                SendRecordStatus::Rejected | SendRecordStatus::Partial => {
                    ChannelDeliveryResult::Rejected {
                        diagnostic: "file delivery was rejected or only partially confirmed".into(),
                        retryable: false,
                    }
                }
            },
            Err(error) => self.failed_send(operation, error).await,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum DeliveryStage {
    Planned,
    /// Durable before polling HTTP. A crash/cancellation never resets it to Planned.
    Unknown,
    Confirmed,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct FileDeliveryFact {
    pub target: ChannelTarget,
    pub file: FileDelivery,
    pub upload: DeliveryStage,
    pub uploaded: Option<UploadHandle>,
    pub message: DeliveryStage,
}

pub(crate) fn initial_record(
    operation: String,
    target: ChannelTarget,
    file: FileDelivery,
) -> Result<SendRecord, FeishuError> {
    let fingerprint = serde_json::to_vec(&(&operation, &target, &file))
        .map_err(|error| local_error(error.to_string()))?;
    Ok(SendRecord {
        operation_id: operation.clone(),
        bot_id: target.account_id.clone(),
        chat_id: target.conversation_id.clone(),
        content_hash: hex::encode(Sha256::digest(fingerprint)),
        status: SendRecordStatus::Unknown,
        platform_message_ids: Vec::new(),
        segments: vec![SendSegmentFact {
            index: 0,
            uuid: operation,
            status: SendRecordStatus::Unknown,
            platform_message_id: None,
            diagnostic: None,
            file_delivery: Some(FileDeliveryFact {
                target,
                file,
                upload: DeliveryStage::Planned,
                uploaded: None,
                message: DeliveryStage::Planned,
            }),
        }],
        facts_complete: true,
    })
}

pub(crate) fn resumable(record: &SendRecord) -> bool {
    record
        .segments
        .first()
        .and_then(|fact| fact.file_delivery.as_ref())
        .is_some_and(|fact| {
            fact.upload == DeliveryStage::Planned
                || fact.upload == DeliveryStage::Confirmed && fact.message == DeliveryStage::Planned
        })
}

pub(crate) fn validate_record(record: &SendRecord) -> Result<(), FeishuError> {
    let [segment] = record.segments.as_slice() else {
        return Err(local_error(
            "file delivery must have exactly one ledger segment",
        ));
    };
    let fact = segment
        .file_delivery
        .as_ref()
        .ok_or_else(|| local_error("missing file delivery facts"))?;
    let expected = initial_record(
        record.operation_id.clone(),
        fact.target.clone(),
        fact.file.clone(),
    )?;
    if record.bot_id != expected.bot_id
        || record.chat_id != expected.chat_id
        || record.content_hash != expected.content_hash
        || segment.uuid != record.operation_id
        || fact.upload == DeliveryStage::Confirmed
            && fact
                .uploaded
                .as_ref()
                .is_none_or(|handle| handle.0.is_empty())
        || fact.message != DeliveryStage::Planned && fact.upload != DeliveryStage::Confirmed
        || record.status == SendRecordStatus::Succeeded && fact.message != DeliveryStage::Confirmed
    {
        return Err(local_error(
            "file delivery ledger fingerprint or stage conflict",
        ));
    }
    Ok(())
}

pub(crate) async fn deliver(
    registry: &ChannelRegistry,
    store: &BotStateStore,
    mut record: SendRecord,
    bytes: Vec<u8>,
    rate: &SendRate,
    cancel: &CancellationToken,
) -> Result<SendRecord, FeishuError> {
    validate_record(&record)?;
    if !resumable(&record) || cancel.is_cancelled() {
        return Ok(record);
    }
    let mut fact = record.segments[0]
        .file_delivery
        .clone()
        .ok_or_else(|| local_error("missing file delivery facts"))?;
    if fact.upload == DeliveryStage::Planned {
        if let Err(error) = fact.file.resource.verify(&bytes) {
            fact.upload = DeliveryStage::Rejected;
            apply_error(&mut record, ChannelError::Rejected(error.to_string()));
            record.segments[0].file_delivery = Some(fact);
            store.save_send(&record).await?;
            return Ok(record);
        }
        // No automatic retry after this durable write, even if the process stops
        // before the request reaches the peer.
        let permit = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Ok(record),
            permit = rate.acquire() => permit,
        };
        fact.upload = DeliveryStage::Unknown;
        record.segments[0].file_delivery = Some(fact.clone());
        store.save_send(&record).await?;
        permit.start();
        let result = tokio::select! {
            biased;
            _ = cancel.cancelled() => Err(ChannelError::Unknown("upload cancelled after intent".into())),
            result = registry.upload(&fact.target, &record.operation_id, &fact.file, bytes) => result,
        };
        match result {
            Ok(handle) => {
                fact.upload = DeliveryStage::Confirmed;
                fact.uploaded = Some(handle);
            }
            Err(error) => {
                if matches!(error, ChannelError::Rejected(_)) {
                    fact.upload = DeliveryStage::Rejected;
                }
                apply_error(&mut record, error);
                record.segments[0].file_delivery = Some(fact);
                store.save_send(&record).await?;
                return Ok(record);
            }
        }
        record.segments[0].file_delivery = Some(fact.clone());
        // Upload confirmation is durable independently of the send intent.
        store.save_send(&record).await?;
    }
    if cancel.is_cancelled() {
        return Ok(record);
    }
    let handle = fact
        .uploaded
        .as_ref()
        .ok_or_else(|| local_error("confirmed upload lacks adapter handle"))?;
    let permit = tokio::select! {
        biased;
        _ = cancel.cancelled() => return Ok(record),
        permit = rate.acquire() => permit,
    };
    fact.message = DeliveryStage::Unknown;
    record.segments[0].file_delivery = Some(fact.clone());
    store.save_send(&record).await?;
    permit.start();
    let result = tokio::select! {
        biased;
        _ = cancel.cancelled() => Err(ChannelError::Unknown("message cancelled after intent".into())),
        result = registry.send(&fact.target, &record.operation_id, &fact.file, handle) => result,
    };
    match result {
        Ok(id) => {
            fact.message = DeliveryStage::Confirmed;
            record.status = SendRecordStatus::Succeeded;
            record.platform_message_ids = vec![id.0.clone()];
            record.segments[0].status = SendRecordStatus::Succeeded;
            record.segments[0].platform_message_id = Some(id.0);
        }
        Err(error) => {
            if matches!(error, ChannelError::Rejected(_)) {
                fact.message = DeliveryStage::Rejected;
            }
            apply_error(&mut record, error);
        }
    }
    record.segments[0].file_delivery = Some(fact);
    // Drained even on cancellation: the caller owns this future until completion.
    store.save_send(&record).await?;
    Ok(record)
}

fn apply_error(record: &mut SendRecord, error: ChannelError) {
    record.status = match &error {
        ChannelError::Rejected(_) => SendRecordStatus::Rejected,
        ChannelError::Unknown(_) => SendRecordStatus::Unknown,
    };
    record.segments[0].status = record.status;
    record.segments[0].diagnostic = Some(error.to_string());
}

pub(crate) fn local_error(message: impl Into<String>) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Unavailable, message, false, None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bots::protocol::{
        endpoint::EndpointPolicy, files::FeishuFileAdapter, http::FeishuHttp,
    };
    use crate::channel_output::{ChannelAdapter, FileCapabilities, PlatformMessageId};
    use pl_core::context::ResourceReference;
    use pl_protocol::AttachmentModality;
    use pl_provider_fixture::feishu::{
        CallKind, DIRECT_CHAT_ID, FeishuPeer, SendDisposition, TENANT_ACCESS_TOKEN,
    };
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };
    use std::time::Duration;

    fn file(bytes: &[u8], image: bool) -> FileDelivery {
        FileDelivery {
            resource: ResourceReference::new(
                "pl.studio.resource:test".into(),
                format!("sha256:{}", hex::encode(Sha256::digest(bytes))),
                bytes.len() as u64,
                if image { "image/png" } else { "text/markdown" }.into(),
            )
            .unwrap(),
            filename: if image { "picture.png" } else { "report.md" }.into(),
            modality: if image {
                AttachmentModality::Image
            } else {
                AttachmentModality::File
            },
        }
    }

    fn target(adapter: &str) -> ChannelTarget {
        ChannelTarget {
            adapter: adapter.into(),
            account_id: "test-bot".into(),
            conversation_id: DIRECT_CHAT_ID.into(),
        }
    }

    fn registry(peer: &FeishuPeer) -> ChannelRegistry {
        registry_with_timeout(peer, Duration::from_millis(150))
    }

    fn registry_with_timeout(peer: &FeishuPeer, timeout: Duration) -> ChannelRegistry {
        let mut policy = EndpointPolicy::production().unwrap();
        policy.open_api = url::Url::parse(peer.origin()).unwrap();
        let http = FeishuHttp::new(policy).unwrap().test_timeout(timeout);
        let mut registry = ChannelRegistry::default();
        registry
            .register(
                "feishu".into(),
                FeishuFileAdapter {
                    http,
                    token: TENANT_ACCESS_TOKEN.into(),
                },
            )
            .unwrap();
        registry
    }

    async fn run(
        registry: &ChannelRegistry,
        store: &BotStateStore,
        operation: &str,
        bytes: &[u8],
        image: bool,
    ) -> SendRecord {
        run_file(registry, store, operation, bytes, file(bytes, image)).await
    }

    async fn run_file(
        registry: &ChannelRegistry,
        store: &BotStateStore,
        operation: &str,
        bytes: &[u8],
        file: FileDelivery,
    ) -> SendRecord {
        let initial = initial_record(operation.into(), target("feishu"), file).unwrap();
        let record = store.claim_send(&initial).await.unwrap().unwrap_or(initial);
        deliver(
            registry,
            store,
            record,
            bytes.to_vec(),
            &SendRate::new(),
            &CancellationToken::new(),
        )
        .await
        .unwrap()
    }

    /// Uses the production binding, credential lease, authorization and send command.
    /// Only the HTTP peer and its synthetic secret are test infrastructure.
    struct BindingFixture {
        fixture: crate::bots::commands::archive_tests::Fixture,
        runtime: BotRuntime,
        managed: Arc<crate::bots::owner::ManagedBot>,
        binding: ChannelOutputBinding,
        peer: FeishuPeer,
    }

    impl BindingFixture {
        async fn new() -> anyhow::Result<Self> {
            use crate::bots::storage::{InboundAdmit, InboundClaim};
            use pl_protocol::studio::{BotSecretUpdate, SaveBotRequest};
            use pl_provider_fixture::feishu::{
                DEFAULT_APP_ID, DEFAULT_APP_SECRET, TRUSTED_USER_OPEN_ID,
            };
            let fixture = crate::bots::commands::archive_tests::Fixture::new().await?;
            let workspace_id = fixture
                .bots
                .managed("archive-fixture")
                .await?
                .config
                .lock()
                .await
                .workspace_id
                .clone();
            let peer = FeishuPeer::start().await?;
            let mut policy = EndpointPolicy::production()?;
            policy.open_api = url::Url::parse(peer.origin())?;
            policy.accounts = policy.open_api.clone();
            let http = FeishuHttp::new(policy)?.test_timeout(Duration::from_secs(5));
            let mut runtime = BotRuntime::new(
                fixture.bots.inner.paths.clone(),
                fixture.bots.inner.config.clone(),
                fixture.bots.inner.events.clone(),
            )?;
            Arc::get_mut(&mut runtime.inner)
                .expect("unpublished runtime")
                .http = http;
            runtime
                .save_bot(
                    SaveBotRequest {
                        operation_id: "file-binding-save".into(),
                        bot_id: Some("file-binding".into()),
                        expected_config_revision: 0,
                        name: "File binding fixture".into(),
                        workspace_id: workspace_id.clone(),
                        app_id: DEFAULT_APP_ID.into(),
                        secret: BotSecretUpdate::Clear,
                        enabled: false,
                        tools_enabled: false,
                        model_route: None,
                    },
                    "file-binding-test",
                )
                .await?;
            let managed = runtime.managed("file-binding").await?;
            managed
                .token
                .replace(DEFAULT_APP_ID.into(), DEFAULT_APP_SECRET.into())
                .await;
            managed
                .store
                .observe_direct(DIRECT_CHAT_ID, Some(TRUSTED_USER_OPEN_ID), None)
                .await?;
            let inbound = FrozenInbound {
                bot_id: "file-binding".into(),
                message_id: "file-source-message".into(),
                chat_id: DIRECT_CHAT_ID.into(),
                content_hash: "file-source-fingerprint".into(),
                text: "explicit file".into(),
                attachments: Vec::new(),
                open_id: TRUSTED_USER_OPEN_ID.into(),
                chat_kind: "direct".into(),
                app_id: DEFAULT_APP_ID.into(),
                workspace_id,
                creation_id: "file-source-thread".into(),
                binding_revision: 0,
                watch_input: String::new(),
            };
            assert!(matches!(
                managed.store.admit_inbound(inbound.clone()).await?,
                InboundAdmit::Fresh(_)
            ));
            assert_eq!(
                managed
                    .store
                    .claim_inbound_work(
                        &inbound.bot_id,
                        &inbound.chat_id,
                        &inbound.message_id,
                        "file-worker"
                    )
                    .await?,
                InboundClaim::Claimed
            );
            let binding = feishu_reply_binding(runtime.clone(), &inbound, "file-worker");
            Ok(Self {
                fixture,
                runtime,
                managed,
                binding,
                peer,
            })
        }

        async fn wait_for_upload(&self) {
            tokio::time::timeout(Duration::from_secs(5), async {
                loop {
                    if self
                        .peer
                        .control()
                        .snapshot_report()
                        .await
                        .calls
                        .iter()
                        .any(|call| call.kind == Some(CallKind::FileUpload))
                    {
                        return;
                    }
                    tokio::task::yield_now().await;
                }
            })
            .await
            .expect("upload request did not reach the controlled peer");
        }

        async fn shutdown(mut self) {
            self.runtime.shutdown().await.unwrap();
            self.peer.shutdown().await.unwrap();
            self.fixture.shutdown().await.unwrap();
        }
    }

    #[tokio::test]
    async fn production_binding_serializes_same_operation_until_both_stages_are_durable()
    -> anyhow::Result<()> {
        let fixture = BindingFixture::new().await?;
        fixture
            .peer
            .control()
            .set_upload_script(vec![SendDisposition::Hang])
            .await;
        let file = file(b"file", false);
        let cancel = CancellationToken::new();
        let operation = "overlapping-file-operation";
        let (first, second) = tokio::time::timeout(Duration::from_secs(10), async {
        tokio::join!(
            fixture.binding.send_file(operation, &file, b"file".to_vec(), &cancel),
            async {
                fixture.wait_for_upload().await;
                let second = fixture.binding.send_file(operation, &file, b"file".to_vec(), &cancel);
                tokio::pin!(second);
                tokio::select! {
                    result = &mut second => panic!("second send bypassed the held file owner: {result:?}"),
                    () = fixture.managed.file_delivery_waiting.notified() => {}
                }
                let current = fixture.managed.store.load_send(operation).await.unwrap().unwrap();
                assert_eq!(current.segments[0].file_delivery.as_ref().unwrap().upload, DeliveryStage::Unknown);
                let report = fixture.peer.control().snapshot_report().await;
                assert_eq!(report.calls.iter().filter(|call| call.kind == Some(CallKind::FileUpload)).count(), 1);
                assert_eq!(report.calls.iter().filter(|call| call.kind == Some(CallKind::MessageSend)).count(), 0);
                fixture.peer.control().release_upload().await;
                second.await
            }
        )
    }).await?;
        assert!(
            matches!(&first, ChannelDeliveryResult::Confirmed { message_ids } if message_ids.len() == 1),
            "{first:?}"
        );
        assert_eq!(first, second);
        assert!(fixture.managed.file_delivery.try_lock().is_ok());
        let report = fixture.peer.control().snapshot_report().await;
        assert_eq!(
            report
                .calls
                .iter()
                .filter(|call| call.kind == Some(CallKind::FileUpload))
                .count(),
            1
        );
        assert_eq!(
            report
                .calls
                .iter()
                .filter(|call| call.kind == Some(CallKind::MessageSend))
                .count(),
            1
        );
        let current = fixture.managed.store.load_send(operation).await?.unwrap();
        assert_eq!(current.status, SendRecordStatus::Succeeded);
        fixture.shutdown().await;
        Ok(())
    }

    #[tokio::test]
    async fn multipart_originals_keys_and_reopen_do_not_resend_but_new_call_does() {
        let mut peer = FeishuPeer::start().await.unwrap();
        let registry = registry(&peer);
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("ledger.sqlite3");
        let store = BotStateStore::new(path.clone());
        let bytes = b"# original markdown\n";
        let sent = run(&registry, &store, "display:call-1:0", bytes, false).await;
        assert_eq!(sent.status, SendRecordStatus::Succeeded, "{sent:?}");
        let facts = sent.segments[0].file_delivery.as_ref().unwrap();
        assert_eq!(facts.upload, DeliveryStage::Confirmed);
        assert_eq!(facts.message, DeliveryStage::Confirmed);
        let image = b"\x89PNG\r\n\x1a\nfixture-image";
        assert_eq!(
            run(&registry, &store, "display:call-1:1", image, true)
                .await
                .status,
            SendRecordStatus::Succeeded
        );
        let video_bytes = b"\x00\x00\x00\x18ftypmp42\x00\xfforiginal-video";
        let video = FileDelivery {
            resource: ResourceReference::new(
                "pl.studio.resource:video".into(),
                format!("sha256:{}", hex::encode(Sha256::digest(video_bytes))),
                video_bytes.len() as u64,
                "video/mp4".into(),
            )
            .unwrap(),
            filename: "recording.mp4".into(),
            modality: AttachmentModality::Video,
        };
        let sent_video = run_file(
            &registry,
            &store,
            "display:call-1:2",
            video_bytes,
            video.clone(),
        )
        .await;
        assert_eq!(
            sent_video.status,
            SendRecordStatus::Succeeded,
            "{sent_video:?}"
        );
        drop(store);
        let reopened = BotStateStore::new(path);
        let replay = run(&registry, &reopened, "display:call-1:0", bytes, false).await;
        assert_eq!(replay.platform_message_ids, sent.platform_message_ids);
        let replay_video =
            run_file(&registry, &reopened, "display:call-1:2", video_bytes, video).await;
        assert_eq!(
            replay_video.platform_message_ids,
            sent_video.platform_message_ids
        );
        assert_eq!(
            run(&registry, &reopened, "display:call-2:0", bytes, false)
                .await
                .status,
            SendRecordStatus::Succeeded
        );
        let report = peer.control().snapshot_report().await;
        let uploads = report
            .calls
            .iter()
            .filter(|call| {
                matches!(
                    call.kind,
                    Some(CallKind::ImageUpload | CallKind::FileUpload)
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(uploads.len(), 4);
        assert_eq!(
            uploads[0].send_body.as_ref().unwrap()["filename"],
            "report.md"
        );
        assert_eq!(
            uploads[0].send_body.as_ref().unwrap()["sha256"],
            hex::encode(Sha256::digest(bytes))
        );
        let video_upload = uploads[2];
        assert_eq!(video_upload.kind, Some(CallKind::FileUpload));
        let video_body = video_upload.send_body.as_ref().unwrap();
        assert_eq!(video_body["filename"], "recording.mp4");
        assert_eq!(video_body["fields"]["file_type"], "stream");
        assert_eq!(
            video_body["sha256"],
            hex::encode(Sha256::digest(video_bytes))
        );
        let sends = report
            .calls
            .iter()
            .filter(|call| call.kind == Some(CallKind::MessageSend))
            .collect::<Vec<_>>();
        assert_eq!(sends.len(), 4);
        assert_eq!(sends[0].msg_type.as_deref(), Some("file"));
        assert_eq!(sends[1].msg_type.as_deref(), Some("image"));
        assert_eq!(sends[2].msg_type.as_deref(), Some("file"));
        peer.shutdown().await.unwrap();
    }

    #[tokio::test]
    async fn upload_rejection_message_rejection_and_timeout_are_distinct_durable_results() {
        let mut peer = FeishuPeer::start().await.unwrap();
        let registry = registry(&peer);
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("ledger.sqlite3");
        let store = BotStateStore::new(path.clone());
        peer.control()
            .set_upload_script(vec![SendDisposition::Reject {
                code: 234006,
                msg: "upload limit".into(),
            }])
            .await;
        let rejected = run(&registry, &store, "upload-rejected", b"file", false).await;
        assert_eq!(rejected.status, SendRecordStatus::Rejected, "{rejected:?}");
        let fact = rejected.segments[0].file_delivery.as_ref().unwrap();
        assert_eq!(fact.upload, DeliveryStage::Rejected);
        assert_eq!(fact.message, DeliveryStage::Planned);
        peer.control()
            .set_send_script(vec![
                SendDisposition::Reject {
                    code: 230002,
                    msg: "send rejected".into(),
                },
                SendDisposition::AcceptThenDrop,
            ])
            .await;
        let rejected = run(&registry, &store, "message-rejected", b"file", false).await;
        assert_eq!(rejected.status, SendRecordStatus::Rejected);
        let fact = rejected.segments[0].file_delivery.as_ref().unwrap();
        assert_eq!(fact.upload, DeliveryStage::Confirmed);
        assert_eq!(fact.message, DeliveryStage::Rejected);
        let unknown = run(&registry, &store, "message-timeout", b"file", false).await;
        assert_eq!(unknown.status, SendRecordStatus::Unknown);
        let fact = unknown.segments[0].file_delivery.as_ref().unwrap();
        assert_eq!(fact.upload, DeliveryStage::Confirmed);
        assert_eq!(fact.message, DeliveryStage::Unknown);
        drop(store);
        let reopened = BotStateStore::new(path);
        let before = peer.control().snapshot_report().await.calls.len();
        assert_eq!(
            run(&registry, &reopened, "message-timeout", b"file", false)
                .await
                .status,
            SendRecordStatus::Unknown
        );
        assert_eq!(peer.control().snapshot_report().await.calls.len(), before);
        peer.control()
            .set_upload_script(vec![SendDisposition::AcceptThenDrop])
            .await;
        let unknown_upload = run(&registry, &reopened, "upload-timeout", b"file", false).await;
        assert_eq!(unknown_upload.status, SendRecordStatus::Unknown);
        assert_eq!(
            unknown_upload.segments[0]
                .file_delivery
                .as_ref()
                .unwrap()
                .upload,
            DeliveryStage::Unknown
        );
        let before = peer.control().snapshot_report().await.calls.len();
        assert_eq!(
            run(&registry, &reopened, "upload-timeout", b"file", false)
                .await
                .status,
            SendRecordStatus::Unknown
        );
        assert_eq!(peer.control().snapshot_report().await.calls.len(), before);
        peer.shutdown().await.unwrap();
    }

    #[tokio::test]
    async fn confirmed_upload_reopens_and_sends_without_uploading_again() {
        let mut peer = FeishuPeer::start().await.unwrap();
        let registry = registry(&peer);
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("ledger.sqlite3");
        let store = BotStateStore::new(path.clone());
        let mut initial = initial_record(
            "resume-uploaded".into(),
            target("feishu"),
            file(b"file", false),
        )
        .unwrap();
        assert!(store.claim_send(&initial).await.unwrap().is_none());
        let mut fact = initial.segments[0].file_delivery.clone().unwrap();
        fact.upload = DeliveryStage::Unknown;
        initial.segments[0].file_delivery = Some(fact.clone());
        store.save_send(&initial).await.unwrap();
        let handle = registry
            .upload(
                &fact.target,
                &initial.operation_id,
                &fact.file,
                b"file".to_vec(),
            )
            .await
            .unwrap();
        fact.upload = DeliveryStage::Confirmed;
        fact.uploaded = Some(handle);
        initial.segments[0].file_delivery = Some(fact);
        store.save_send(&initial).await.unwrap();
        drop(store);
        let reopened = BotStateStore::new(path);
        assert_eq!(
            run(&registry, &reopened, "resume-uploaded", b"file", false)
                .await
                .status,
            SendRecordStatus::Succeeded
        );
        let report = peer.control().snapshot_report().await;
        assert_eq!(
            report
                .calls
                .iter()
                .filter(|call| call.kind == Some(CallKind::FileUpload))
                .count(),
            1
        );
        assert_eq!(
            report
                .calls
                .iter()
                .filter(|call| call.kind == Some(CallKind::MessageSend))
                .count(),
            1
        );
        peer.shutdown().await.unwrap();
    }

    struct SecondAdapter(Arc<AtomicUsize>);
    impl ChannelAdapter for SecondAdapter {
        fn capabilities(&self) -> FileCapabilities {
            FileCapabilities {
                image_max_bytes: None,
                file_max_bytes: Some(100),
            }
        }
        async fn upload(
            &self,
            _: &ChannelTarget,
            _: &str,
            _: &FileDelivery,
            bytes: Vec<u8>,
        ) -> Result<UploadHandle, ChannelError> {
            assert_eq!(bytes, b"second");
            self.0.fetch_add(1, Ordering::SeqCst);
            Ok(UploadHandle("opaque-second-handle".into()))
        }
        async fn send(
            &self,
            _: &ChannelTarget,
            _: &str,
            _: &FileDelivery,
            handle: &UploadHandle,
        ) -> Result<PlatformMessageId, ChannelError> {
            assert_eq!(handle.0, "opaque-second-handle");
            self.0.fetch_add(1, Ordering::SeqCst);
            Ok(PlatformMessageId("second-message".into()))
        }
    }

    #[tokio::test]
    async fn second_registered_adapter_uses_the_same_delivery_driver() {
        let mut peer = FeishuPeer::start().await.unwrap();
        let mut registry = registry(&peer);
        let counter = Arc::new(AtomicUsize::new(0));
        registry
            .register("second".into(), SecondAdapter(counter.clone()))
            .unwrap();
        let temp = tempfile::tempdir().unwrap();
        let store = BotStateStore::new(temp.path().join("ledger.sqlite3"));
        let initial = initial_record(
            "second-call".into(),
            target("second"),
            file(b"second", false),
        )
        .unwrap();
        assert!(store.claim_send(&initial).await.unwrap().is_none());
        let sent = deliver(
            &registry,
            &store,
            initial,
            b"second".to_vec(),
            &SendRate::new(),
            &CancellationToken::new(),
        )
        .await
        .unwrap();
        assert_eq!(sent.platform_message_ids, ["second-message"]);
        assert_eq!(counter.load(Ordering::SeqCst), 2);
        assert!(peer.control().snapshot_report().await.calls.is_empty());
        peer.shutdown().await.unwrap();
    }

    #[tokio::test]
    async fn existing_text_ledger_facts_keep_identity_and_result_without_file_fields() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("ledger.sqlite3");
        let store = BotStateStore::new(path.clone());
        let segment: SendSegmentFact = serde_json::from_str(
            r#"{
        "index":0,"uuid":"original-uuid","status":"succeeded",
        "platform_message_id":"original-message","diagnostic":null
    }"#,
        )
        .unwrap();
        assert!(segment.file_delivery.is_none());
        let record = SendRecord {
            operation_id: "original-operation".into(),
            bot_id: "original-bot".into(),
            chat_id: "original-chat".into(),
            content_hash: "original-hash".into(),
            status: SendRecordStatus::Succeeded,
            platform_message_ids: vec!["original-message".into()],
            segments: vec![segment.clone()],
            facts_complete: true,
        };
        store.save_send(&record).await.unwrap();
        drop(store);
        let reopened = BotStateStore::new(path);
        let restored = reopened
            .load_send("original-operation")
            .await
            .unwrap()
            .unwrap();
        assert_eq!(restored.content_hash, "original-hash");
        assert_eq!(restored.status, SendRecordStatus::Succeeded);
        assert_eq!(restored.platform_message_ids, ["original-message"]);
        assert_eq!(restored.segments, [segment]);
    }

    #[tokio::test]
    async fn cancellation_drains_upload_intent_and_never_retries_it() -> anyhow::Result<()> {
        let fixture = BindingFixture::new().await?;
        fixture
            .peer
            .control()
            .set_upload_script(vec![SendDisposition::AcceptThenDrop])
            .await;
        let file = file(b"file", false);
        let cancel = CancellationToken::new();
        let (result, ()) = tokio::join!(
            fixture
                .binding
                .send_file("cancel-upload", &file, b"file".to_vec(), &cancel),
            async {
                fixture.wait_for_upload().await;
                let waiting_cancel = CancellationToken::new();
                let waiting = fixture.binding.send_file(
                    "cancel-upload",
                    &file,
                    b"file".to_vec(),
                    &waiting_cancel,
                );
                tokio::pin!(waiting);
                tokio::select! {
                    result = &mut waiting => panic!("waiter bypassed the active sender: {result:?}"),
                    () = fixture.managed.file_delivery_waiting.notified() => {}
                }
                waiting_cancel.cancel();
                assert!(matches!(
                    waiting.await,
                    ChannelDeliveryResult::Unknown { .. }
                ));
                assert!(
                    fixture.managed.file_delivery.try_lock().is_err(),
                    "cancelling a waiter released the active sender's guard"
                );
                cancel.cancel();
            }
        );
        assert!(matches!(result, ChannelDeliveryResult::Unknown { .. }));
        assert!(
            fixture.managed.file_delivery.try_lock().is_ok(),
            "cancelled sender retained the file guard"
        );
        let saved = fixture
            .managed
            .store
            .load_send("cancel-upload")
            .await?
            .unwrap();
        assert!(
            saved.segments[0]
                .diagnostic
                .as_ref()
                .unwrap()
                .contains("cancelled")
        );
        assert_eq!(
            saved.segments[0].file_delivery.as_ref().unwrap().upload,
            DeliveryStage::Unknown
        );
        let before = fixture.peer.control().snapshot_report().await.calls.len();
        let replay = fixture
            .binding
            .send_file(
                "cancel-upload",
                &file,
                b"file".to_vec(),
                &CancellationToken::new(),
            )
            .await;
        assert!(matches!(replay, ChannelDeliveryResult::Unknown { .. }));
        assert_eq!(
            fixture.peer.control().snapshot_report().await.calls.len(),
            before
        );
        fixture.shutdown().await;
        Ok(())
    }
}
