//! Attachment verification uses the real model projection, retained bytes and current entry points.

use std::sync::Arc;

use crate::AttachmentModality;
use anyhow::Result;
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSource, OpaquePayload, ResourceReference},
    model::ToolCallMode,
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

use super::{CurrentFile, VerifiedResources, verify_recovery_resources};
use crate::{
    resource_store::{FileResourceStore, RESOURCE_ID_PREFIX},
    studio::paths::CURRENT_FILE_NAME,
};

const THREAD: &str = "attachment-current";
const MATERIAL: &[u8] = b"complete retained attachment";

#[tokio::test]
async fn tool_result_current_verifies_command_detail_resources_without_model_resources()
-> Result<()> {
    let directory = tempfile::tempdir()?;
    let root = directory.path();
    let resources = FileResourceStore::new(root.join("resources"));
    let stdout = resources
        .retain_bytes(Arc::from(MATERIAL), "text/plain")
        .await?;
    let stderr_bytes = b"retained stderr";
    let stderr = resources
        .retain_bytes(Arc::from(stderr_bytes.as_slice()), "text/plain")
        .await?;
    let mut current = current_in(
        Slot::OriginalToolContext,
        ContextContent::Text {
            text: "short preview".into(),
        },
        RuntimeEpoch::new(),
    );
    let delivery = &mut Arc::make_mut(&mut current.state.deliveries)[0];
    delivery.output = delivery
        .output
        .clone()
        .with_details(serde_json::json!({"command": {
            "stdoutResource": stdout, "stderrResource": stderr,
        }}));
    let current_file = file(root);
    current_file.save(current.clone()).await?;
    let loaded = current_file.load().await?.unwrap();
    assert_eq!(
        loaded.state.deliveries[0].output.content(),
        current.state.deliveries[0].output.content()
    );
    let path = asset_path(root, &stderr);
    std::fs::remove_file(&path)?;
    let error = current_file.load().await.unwrap_err();
    assert!(error.to_string().contains(stderr.id()));
    std::fs::write(path, stderr_bytes)?;
    assert!(current_file.load().await?.is_some());
    Ok(())
}

#[tokio::test]
async fn tool_result_current_upgrade_preserves_pending_inbox_body_and_resources() -> Result<()> {
    use crate::studio::storage::coordinator::ThreadPersistenceCoordinator;
    use serde_json::json;

    let directory = tempfile::tempdir()?;
    let root = directory.path();
    let coordinator = ThreadPersistenceCoordinator::default();
    let store = FileResourceStore::new(root.join("resources"));
    let resource = store
        .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
        .await?;
    let ContextContent::Media {
        payload: attachment,
    } = attachment_content(resource.clone(), AttachmentModality::File)?
    else {
        anyhow::bail!("fixture attachment is not Media");
    };
    let mut current = serde_json::to_value(ThreadCurrent::new(THREAD.into(), RuntimeEpoch::new()))?;
    current["schemaVersion"] = 1.into();
    current["snapshotRevision"] = 7.into();
    let payload = json!({"format":"test.producer", "version":3, "content":"原件 🧭\n  逐字保留"});
    let author_content = json!([
        {"kind":"text", "text":"历史模型正文"}, {"kind":"opaque", "payload": attachment},
    ]);
    let mut delivered = author_content.as_array().unwrap().clone();
    delivered.insert(0, json!({"kind":"text", "text":"旧的后台完成通知"}));
    current["state"]["deliveries"] = json!([{
        "target":{"kind":"inbox", "value":{"message_id":"task-result:1"}},
        "callId":"source-call", "toolId":"source-tool", "outcome":{"kind":"succeeded"},
        "output":{"payload": payload, "context": author_content}, "deliveredContext": delivered,
    }]);
    current["state"]["inboxSequence"] = 1.into();
    current["state"]["wakeMessagesThrough"] = 1.into();
    current["state"]["inbox"] = json!([{
        "sequence":1, "message":{"id":"task-result:1", "sourceId":"task:source-call",
        "kind":"report", "payload": payload, "context": delivered},
    }]);
    let bytes = serde_json::to_vec_pretty(&current)?;
    let path = root.join(CURRENT_FILE_NAME);
    std::fs::write(&path, &bytes)?;
    assert!(file(root).load().await.is_err());

    let asset = asset_path(root, &resource);
    std::fs::write(&asset, b"corrupt resource")?;
    assert!(
        coordinator
            .upgrade_current_for_recovery(THREAD, root.to_owned())
            .await
            .is_err()
    );
    assert_eq!(std::fs::read(&path)?, bytes);
    assert!(
        coordinator
            .upgrade_current_for_recovery("foreign-thread", root.to_owned())
            .await
            .is_err()
    );
    assert_eq!(std::fs::read(&path)?, bytes);
    std::fs::write(asset, MATERIAL)?;
    let backup = root.join("migration-backups/current-tool-result-v1/current.original.json");
    std::fs::create_dir_all(backup.parent().unwrap())?;
    std::fs::write(&backup, b"different original")?;
    let backup_error = coordinator
        .upgrade_current_for_recovery(THREAD, root.to_owned())
        .await
        .unwrap_err();
    assert!(
        backup_error
            .to_string()
            .contains("backup differs from source")
    );
    assert_eq!(std::fs::read(&backup)?, b"different original");
    assert_eq!(std::fs::read(&path)?, bytes);
    // Resume after a previous attempt published its exact backup but could not replace Current.
    std::fs::write(&backup, &bytes)?;
    coordinator
        .upgrade_current_for_recovery(THREAD, root.to_owned())
        .await?;
    assert_eq!(std::fs::read(backup)?, bytes);
    let mut saved = file(root).load().await?.unwrap();
    assert_eq!(saved.snapshot_revision, 7);
    let delivery = &saved.state.deliveries[0];
    assert_eq!(delivery.output.data(), None);
    assert_eq!(delivery.output.details().unwrap()["legacyPayload"], payload);
    assert_eq!(
        delivery.output.content()[0],
        ContextContent::Text {
            text: "历史模型正文".into()
        }
    );
    let ContextContent::Media { payload } = &delivery.output.content()[1] else {
        anyhow::bail!("old attachment was not preserved")
    };
    assert_eq!(decode_attachment(payload)?.unwrap().reference, resource);
    let notice = &saved.state.inbox[0].message;
    assert_eq!(notice.payload.format(), "pl.core.tool-result-reference");
    assert_eq!(notice.payload.content(), "source-call");
    assert_eq!(notice.context, delivery.delivered_context);
    let original_notice = notice.clone();
    saved.reconcile_saved_local_state()?;
    assert_eq!(saved.state.inbox.len(), 1);
    assert_eq!(saved.state.inbox[0].message, original_notice);
    coordinator
        .upgrade_current_for_recovery(THREAD, root.to_owned())
        .await?;
    Ok(())
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
                tool_data: Default::default(),
            }]
            .into()
        }
        Slot::Input => {
            current.state.inputs = vec![InputRecord {
                accepted_sequence: 1,
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
                output: ToolOutput::from_data("complete producer result".into(), original),
                delivered_context: delivered,
                outcome: ToolOutcome::Succeeded,
                cancellation_cause: None,
            }]
            .into();
        }
        Slot::Preparing => {
            let phase = SavedModelPhase::Preparing {
                pending_step_input: Some(PendingStepInput {
                    content: vec![content],
                }),
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
async fn verified_resources_are_reused_only_for_the_same_reference_and_owner() -> Result<()> {
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
    let mut verified = VerifiedResources::new();
    verify_recovery_resources(&current, &store, &mut verified, CancellationToken::new()).await?;
    assert_eq!(verified.len(), 1, "aliases use the same verified identity");
    std::fs::remove_file(asset_path(directory.path(), &reference))?;
    verify_recovery_resources(&current, &store, &mut verified, CancellationToken::new()).await?;
    assert!(
        verify_recovery_resources(
            &current,
            &store,
            &mut VerifiedResources::new(),
            CancellationToken::new()
        )
        .await
        .is_err(),
        "a fresh owner must verify the resource again"
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
    assert!(
        verify_recovery_resources(&current, &store, &mut verified, CancellationToken::new())
            .await
            .is_err()
    );
    current.state.context.records = Arc::from([]);
    current.state.runtime_facts = Arc::from([]);
    current.state.deliveries = Arc::from([]);
    verify_recovery_resources(&current, &store, &mut verified, CancellationToken::new()).await?;
    assert!(
        verified.is_empty(),
        "unreferenced identities must be evicted"
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
    let ContextContent::Media { payload } = content else {
        panic!("the model producer defines explicit media content")
    };
    let file = file(directory.path());
    for broken in [
        OpaquePayload::new(payload.format(), payload.version() + 1, payload.content())?,
        OpaquePayload::new(payload.format(), payload.version(), "{broken attachment")?,
    ] {
        file.save(current_in(
            Slot::Context,
            ContextContent::Media { payload: broken },
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
    let same_format = ContextContent::Opaque {
        payload: OpaquePayload::new(payload.format(), payload.version(), "opaque bytes")?,
    };
    let expected = current_in(Slot::Context, same_format, RuntimeEpoch::new());
    file.save(expected.clone()).await?;
    assert_eq!(
        file.load().await?.unwrap().state.context,
        expected.state.context,
    );
    Ok(())
}

#[tokio::test(start_paused = true)]
async fn media_save_failure_preserves_old_current_and_receipt() -> Result<()> {
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
        attachment_content(good.clone(), AttachmentModality::File)?,
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
    // A later save of the same immutable reference must use the owner-local verification cache.
    // A real cold load still revalidates the resource, even though that save succeeds.
    std::fs::remove_file(asset_path(directory.path(), &good))?;
    assert_eq!(store.flush_current(epoch).await?, receipt);
    assert!(store.load_current().await.is_err());
    assert_eq!(
        resources
            .retain_bytes(Arc::from(MATERIAL), "application/octet-stream")
            .await?,
        good
    );
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
            ContextContent::Media { payload } => decode_attachment(payload)
                .unwrap()
                .is_some_and(|attachment| attachment.reference == missing),
            _ => false,
        }
    }));
    store
        .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
        .await?;
    Ok(())
}
