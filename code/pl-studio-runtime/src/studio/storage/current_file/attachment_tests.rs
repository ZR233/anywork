//! Attachment verification uses the real model projection, retained bytes and current entry points.

use std::sync::Arc;

use anyhow::Result;
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSource, OpaquePayload, ResourceReference},
    model::{ModelStepOutput, ToolCallMode},
    thread::{
        RuntimeFact, ToolDelivery, ToolDeliveryTarget, ToolOutcome,
        current::{
            CurrentModelCall, PendingStepInput, RuntimeEpoch, SavedModelPhase, ThreadCurrent,
        },
        inbox::{InboxRecord, ThreadMessage},
        input::{InputRecord, InputState, ThreadInput},
    },
    tool::ToolOutput,
};
use pl_model::runtime::{attachment_content, decode_attachment};
use pl_protocol::AttachmentModality;

use super::{CurrentFile, verify_recovery_resources};
use crate::{
    resource_store::{FileResourceStore, RESOURCE_ID_PREFIX},
    studio::paths::CURRENT_FILE_NAME,
};

const THREAD: &str = "attachment-current";
const MATERIAL: &[u8] = b"complete retained attachment";

#[derive(Debug)]
struct CountingResources {
    store: FileResourceStore,
    reads: Arc<std::sync::atomic::AtomicUsize>,
}

impl pl_core::context::ResourceReader for CountingResources {
    async fn read(
        &self,
        reference: ResourceReference,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> std::result::Result<Arc<[u8]>, pl_core::context::ResourceReadError> {
        self.reads
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        pl_core::context::ResourceReader::read(&self.store, reference, cancellation).await
    }
}

#[derive(Debug, Clone, Copy)]
enum Slot {
    Context,
    Input,
    Inbox,
    RuntimeFact,
    OriginalToolContext,
    PendingDelivery,
    Preparing,
    ReadyToApply,
}

fn current_in(slot: Slot, content: ContextContent, epoch: RuntimeEpoch) -> ThreadCurrent {
    let mut current = ThreadCurrent::new(THREAD.into(), epoch);
    match slot {
        Slot::Context => {
            current.state.context.records = vec![ContextRecord {
                id: "confirmed-input".into(),
                turn_id: None,
                source: ContextSource::User,
                content: vec![content],
                tool_calls: Vec::new(),
            }]
            .into()
        }
        Slot::Input => {
            current.state.inputs = vec![InputRecord {
                accepted_sequence: 1,
                continuation: None,
                delivery: Default::default(),
                input: ThreadInput {
                    id: "pending-input".into(),
                    purpose: Default::default(),
                    payload: OpaquePayload::text("original input"),
                    context: vec![content],
                },
                ordinal: 1,
                revision: 1,
                state: InputState::Pending,
            }]
            .into()
        }
        Slot::Inbox => {
            current.state.inbox = vec![InboxRecord {
                sequence: 1,
                message: ThreadMessage {
                    id: "pending-message".into(),
                    source_id: "sender".into(),
                    kind: Default::default(),
                    payload: OpaquePayload::text("message body"),
                    context: vec![content],
                },
            }]
            .into()
        }
        Slot::RuntimeFact => {
            current.state.runtime_facts = vec![RuntimeFact {
                source_id: "host".into(),
                content: vec![content],
            }]
            .into()
        }
        Slot::OriginalToolContext | Slot::PendingDelivery => {
            let (original, delivered) = if matches!(slot, Slot::OriginalToolContext) {
                (vec![content], Vec::new())
            } else {
                (Vec::new(), vec![content])
            };
            current.state.deliveries = vec![ToolDelivery {
                target: ToolDeliveryTarget::Inbox {
                    message_id: "known-result".into(),
                },
                call_id: "completed-call".into(),
                tool_id: "media-tool".into(),
                output: ToolOutput::new(OpaquePayload::text("complete producer result"), original),
                delivered_context: delivered,
                outcome: ToolOutcome::Succeeded,
            }]
            .into();
        }
        Slot::Preparing | Slot::ReadyToApply => {
            let phase = if matches!(slot, Slot::Preparing) {
                SavedModelPhase::Preparing {
                    pending_step_input: Some(PendingStepInput {
                        content: vec![content],
                    }),
                }
            } else {
                SavedModelPhase::ReadyToApply {
                    output: ModelStepOutput {
                        turn_action: Default::default(),
                        attempt_id: "attempt".into(),
                        base_context_revision: 0,
                        content: vec![content],
                        tool_calls: Vec::new(),
                        private_context: None,
                        usage: Default::default(),
                    },
                }
            };
            current.model_call = Some(CurrentModelCall {
                source_run_id: epoch,
                source_execution_id: "execution".into(),
                source_turn_id: "turn".into(),
                source_attempt_id: "attempt".into(),
                tools: Arc::from([]),
                tool_call_mode: ToolCallMode::Sequential,
                solo_tool_ids: Arc::from([]),
                prepared_parameters: None,
                phase,
            });
        }
    }
    current
}

fn file(directory: &std::path::Path) -> CurrentFile {
    CurrentFile::new(directory.into(), THREAD.into())
}

fn asset_path(directory: &std::path::Path, reference: &ResourceReference) -> std::path::PathBuf {
    directory.join("resources").join(
        reference
            .id()
            .strip_prefix(RESOURCE_ID_PREFIX)
            .expect("FileResourceStore identity"),
    )
}

#[tokio::test]
async fn repeated_resource_references_read_once_without_hiding_conflicting_metadata() -> Result<()>
{
    use pl_core::context::ResourceAccess;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use tokio_util::sync::CancellationToken;

    let directory = tempfile::tempdir()?;
    let store = FileResourceStore::new(directory.path().join("resources"));
    let reference = store
        .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
        .await?;
    let projected = attachment_content(reference.clone(), AttachmentModality::File)?;
    let mut current = current_in(
        Slot::PendingDelivery,
        projected.clone(),
        RuntimeEpoch::new(),
    );
    current.state.context = current_in(
        Slot::Context,
        ContextContent::Resource {
            reference: reference.clone(),
        },
        current.saved_runtime_epoch,
    )
    .state
    .context;
    current.state.runtime_facts = vec![RuntimeFact {
        source_id: "same-attachment".into(),
        content: vec![projected],
    }]
    .into();
    let reads = Arc::new(AtomicUsize::new(0));
    let resources = ResourceAccess::new(CountingResources {
        store,
        reads: reads.clone(),
    });
    verify_recovery_resources(&current, &resources, CancellationToken::new()).await?;
    assert_eq!(
        reads.load(Ordering::Relaxed),
        1,
        "direct and model-projected aliases must share one byte verification per attempt"
    );

    let invalid = ResourceReference::new(
        reference.id().into(),
        reference.content_digest().into(),
        reference.byte_len() + 1,
        reference.media_type().into(),
    )?;
    current.state.runtime_facts = vec![RuntimeFact {
        source_id: "different-length".into(),
        content: vec![attachment_content(invalid, AttachmentModality::File)?],
    }]
    .into();
    reads.store(0, Ordering::Relaxed);
    assert!(
        verify_recovery_resources(&current, &resources, CancellationToken::new())
            .await
            .is_err()
    );
    assert_eq!(
        reads.load(Ordering::Relaxed),
        2,
        "the same ID with a different length still requires a failing byte validation"
    );
    Ok(())
}

#[tokio::test]
async fn opaque_attachments_require_retained_bytes_in_all_recovery_contents() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let resources = FileResourceStore::new(directory.path().join("resources"));
    let file = file(directory.path());
    for slot in [
        Slot::Context,
        Slot::Input,
        Slot::Inbox,
        Slot::RuntimeFact,
        Slot::OriginalToolContext,
        Slot::PendingDelivery,
        Slot::Preparing,
        Slot::ReadyToApply,
    ] {
        let reference = resources
            .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
            .await?;
        let content = attachment_content(reference.clone(), AttachmentModality::File)?;
        let current = current_in(slot, content, RuntimeEpoch::new());
        let expected = serde_json::to_value(&current)?;
        file.save(current).await?;
        assert_eq!(
            serde_json::to_value(file.load().await?.unwrap())?,
            expected,
            "{slot:?}: intact attachment must round-trip"
        );
        let path = directory.path().join(CURRENT_FILE_NAME);
        let original = std::fs::read(&path)?;
        std::fs::remove_file(asset_path(directory.path(), &reference))?;
        assert!(
            file.load().await.is_err(),
            "{slot:?}: missing opaque attachment must fail recovery"
        );
        assert_eq!(
            std::fs::read(&path)?,
            original,
            "{slot:?}: failed load must preserve the original JSON"
        );
    }
    Ok(())
}

#[tokio::test]
async fn opaque_attachment_load_rejects_bad_length_digest_and_changed_bytes() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let resources = FileResourceStore::new(directory.path().join("resources"));
    let reference = resources
        .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
        .await?;
    let file = file(directory.path());
    let bad_length = ResourceReference::new(
        reference.id().into(),
        reference.content_digest().into(),
        reference.byte_len() + 1,
        reference.media_type().into(),
    )?;
    let bad_digest = ResourceReference::new(
        reference.id().into(),
        format!("sha256:{}", "0".repeat(64)),
        reference.byte_len(),
        reference.media_type().into(),
    )?;
    for wrong in [bad_length, bad_digest] {
        file.save(current_in(
            Slot::Context,
            attachment_content(wrong, AttachmentModality::File)?,
            RuntimeEpoch::new(),
        ))
        .await?;
        let path = directory.path().join(CURRENT_FILE_NAME);
        let original = std::fs::read(&path)?;
        assert!(file.load().await.is_err());
        assert_eq!(std::fs::read(path)?, original);
    }
    file.save(current_in(
        Slot::Context,
        attachment_content(reference.clone(), AttachmentModality::File)?,
        RuntimeEpoch::new(),
    ))
    .await?;
    let path = directory.path().join(CURRENT_FILE_NAME);
    let original = std::fs::read(&path)?;
    // Same byte length, different digest: metadata-only validation cannot detect replacement.
    std::fs::write(
        asset_path(directory.path(), &reference),
        vec![b'x'; MATERIAL.len()],
    )?;
    assert!(file.load().await.is_err());
    assert_eq!(std::fs::read(path)?, original);
    Ok(())
}

#[tokio::test]
async fn known_attachment_decode_errors_fail_but_unrelated_opaque_stays_transparent() -> Result<()>
{
    let directory = tempfile::tempdir()?;
    let resources = FileResourceStore::new(directory.path().join("resources"));
    let reference = resources
        .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
        .await?;
    let content = attachment_content(reference, AttachmentModality::File)?;
    let ContextContent::Opaque { payload } = content else {
        panic!("the model producer encodes attachments as opaque")
    };
    let file = file(directory.path());
    for broken in [
        OpaquePayload::new(payload.format(), payload.version() + 1, payload.content())?,
        OpaquePayload::new(payload.format(), payload.version(), "{broken attachment")?,
    ] {
        file.save(current_in(
            Slot::Context,
            ContextContent::Opaque { payload: broken },
            RuntimeEpoch::new(),
        ))
        .await?;
        let path = directory.path().join(CURRENT_FILE_NAME);
        let original = std::fs::read(&path)?;
        assert!(
            file.load().await.is_err(),
            "a recognized but undecodable attachment is not recoverable"
        );
        assert_eq!(std::fs::read(path)?, original);
    }
    let unrelated = ContextContent::Opaque {
        payload: OpaquePayload::new(
            "vendor.signed-material",
            93,
            "signed opaque bytes, not JSON; pl.model.attachment and missing resources are not a schema here",
        )?,
    };
    let expected = current_in(Slot::Context, unrelated, RuntimeEpoch::new());
    file.save(expected.clone()).await?;
    assert_eq!(
        serde_json::to_value(file.load().await?.unwrap())?,
        serde_json::to_value(expected)?
    );
    Ok(())
}

#[tokio::test(start_paused = true)]
async fn opaque_attachment_save_failure_preserves_old_current_and_receipt() -> Result<()> {
    use crate::studio::storage::{
        coordinator::ThreadPersistenceCoordinator, current_writer::CurrentSource, state::StateStore,
    };
    use std::sync::Mutex;
    let directory = tempfile::tempdir()?;
    let resources = FileResourceStore::new(directory.path().join("resources"));
    let good = resources
        .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
        .await?;
    let needed_bytes: Arc<[u8]> = Arc::from(b"newly accepted material".as_slice());
    let missing = resources
        .retain_bytes(needed_bytes.clone(), "application/octet-stream")
        .await?;
    std::fs::remove_file(asset_path(directory.path(), &missing))?;
    let epoch = RuntimeEpoch::new();
    let mut baseline = current_in(
        Slot::Context,
        attachment_content(good, AttachmentModality::File)?,
        epoch,
    );
    baseline.snapshot_revision = 1;
    let transparent = ContextContent::Opaque {
        payload: OpaquePayload::new("vendor.signature", 13, "unaltered signed bytes, not JSON")?,
    };
    let mut records = baseline.state.context.records.to_vec();
    records[0].content.push(transparent.clone());
    baseline.state.context.records = records.into();
    let value = Arc::new(Mutex::new(baseline.clone()));
    let capture = value.clone();
    let finish = value.clone();
    let source = CurrentSource::new(
        move |_, _| {
            let current = capture.lock().unwrap().clone();
            Box::pin(async move { Ok(current) })
        },
        move |_| {
            let current = finish.lock().unwrap().clone();
            Box::pin(async move { Ok(current) })
        },
    );
    let mut store = StateStore::new(directory.path().into(), THREAD);
    store
        .attach_current(ThreadPersistenceCoordinator::default(), None, epoch, source)
        .await?;
    let receipt = store.flush_current(epoch).await?;
    let path = directory.path().join(CURRENT_FILE_NAME);
    let original = std::fs::read(&path)?;
    for (index, slot) in [
        Slot::Input,
        Slot::OriginalToolContext,
        Slot::PendingDelivery,
    ]
    .into_iter()
    .enumerate()
    {
        let mut latest = current_in(
            slot,
            attachment_content(missing.clone(), AttachmentModality::File)?,
            epoch,
        );
        latest.state.context = baseline.state.context.clone();
        latest.snapshot_revision = 2 + index as u64;
        *value.lock().unwrap() = latest;
        assert!(
            store.flush_current(epoch).await.is_err(),
            "{slot:?}: missing material cannot receive a save receipt"
        );
        assert_eq!(
            std::fs::read(&path)?,
            original,
            "{slot:?}: failed save must not replace the last complete JSON"
        );
        let state = store.current_save_state()?;
        assert_eq!(state.receipt, Some(receipt.clone()));
        assert!(state.dirty && state.error.is_some());
        assert_eq!(store.load_current().await?.unwrap().snapshot_revision, 1);
    }
    let restored = resources
        .retain_bytes(needed_bytes, "application/octet-stream")
        .await?;
    assert_eq!(restored, missing);
    let saved = store.flush_current(epoch).await?;
    assert_eq!(saved.snapshot_revision, 4);
    let loaded = store.load_current().await?.unwrap();
    assert!(
        loaded.state.context.records[0]
            .content
            .contains(&transparent)
    );
    assert!(loaded.recovery_contents().into_iter().any(|content| {
        match content {
            ContextContent::Opaque { payload } => decode_attachment(payload)
                .unwrap()
                .is_some_and(|attachment| attachment.reference == missing),
            _ => false,
        }
    }));
    store.close_current(epoch).await?;
    Ok(())
}
