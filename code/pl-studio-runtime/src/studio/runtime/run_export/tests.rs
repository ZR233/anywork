use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use crate::{
    InferenceAccounting, InferenceBillingRecord, PricingOutcome, RuntimeCostAmount, UnpricedReason,
    UsageReport,
};
use anyhow::{Context, Result, ensure};
use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};
use pl_core::thread::{ThreadEffectBatch, UsageSummary};
use sha2::{Digest, Sha256};

use super::manifest::{validate_output_dir_preflight, write_run_manifest};
use super::reader::export_history_originals_window;
use super::types::{
    ChatItemHeaderExportV3, EventBodyV3, EventSourceV3, EventV3, ExportedBlobV3, ExportedContentV3,
    MAX_QUEUED_BATCHES, RunExportOptions, RunManifestV3, UsageCoverage, UsageMetricKey,
};
use super::usage::{UsageAccumulator, fold_next_accounting};
use super::writer::{ExportCommand, FsContentBlobSink};
use super::{NewMemberRegistration, RetiredThreadCut, RunExporter};
use crate::history::{
    EventPayloadEnvelope, HistoryBody, HistoryBodyRole, HistoryDemand, HistoryEntityState,
    HistoryEvent, HistoryEventKind, HistoryEventMeta, HistoryLimits, HistoryOriginalInfo,
    HistorySingleVisibility, HistoryStore, HistoryTimelineRole, PendingBody, decode_event_envelope,
    pack_bodies,
};
use crate::studio::thread_projection::{AuxiliaryBillingReceipt, CurrentState, PreparedAccounting};

struct ThreadUsageInput<'a> {
    thread_id: &'a str,
    initial_effect_seq: u64,
    through_effect_seq: u64,
    summary: &'a UsageSummary,
    receipts: &'a [PreparedAccounting],
}

fn test_current(thread_id: &str, revision: u64) -> Result<Arc<CurrentState>> {
    CurrentState::cold(
        "fixture-database".into(),
        thread_id.into(),
        revision,
        &pl_core::thread::ThreadSnapshot::default(),
    )
}

fn read_contents_manifest(
    root: &std::path::Path,
    manifest: &ExportedBlobV3,
) -> Result<Vec<ExportedContentV3>> {
    let bytes = std::fs::read(root.join(&manifest.path))?;
    ensure!(
        bytes.len() as u64 == manifest.byte_length,
        "contents manifest length mismatch"
    );
    ensure!(
        super::sha256_hex(&bytes) == manifest.sha256,
        "contents manifest hash mismatch"
    );
    String::from_utf8(bytes)?
        .lines()
        .map(|line| serde_json::from_str(line).map_err(Into::into))
        .collect()
}

async fn history_checkpoint(
    history: &crate::history::HistoryReader,
) -> Result<super::types::CompletionCursorV3> {
    let (cut, history_seq) = history.capture_position().await?;
    Ok(super::types::CompletionCursorV3 { cut, history_seq })
}

fn text_original(
    index: u64,
    channel: crate::ThreadTextChannel,
    text: &str,
    database_id: &str,
) -> Result<HistoryEvent> {
    let event_id = format!("event-{index}");
    let entity_id = format!("msg-{index}");
    let input_id = format!("bot:fixture:dm:om_{index}");
    let source = crate::ChatSourceId::InboxMessage {
        source_id: "om".into(),
        message_id: format!("om_{index}"),
    };
    let turn_id = format!("turn-{index}");
    let query_class = serde_json::to_string(&crate::ChatClassFilter::All {})?;
    let meta = HistoryEventMeta {
        entity_id: entity_id.clone(),
        entity_kind: crate::ChatAtomKind::Text,
        delivery: crate::ChatDeliveryKind::Foreground,
        state: HistoryEntityState::KnownTerminal {
            outcome: crate::ChatTerminalOutcome::Completed,
        },
        started_at: None,
        finished_at: None,
        text_channel: Some(channel),
        single_visibility: Some(HistorySingleVisibility::Content),
        presentation_contract: None,
        source_order: None,
        content_present: Some(true),
        wait: None,
        tool: None,
    };
    let mut event = HistoryEvent::new(
        event_id,
        HistoryEventKind::TextCompleted,
        HistoryTimelineRole::Divider,
        index as i64,
    );
    event.entity_id = Some(entity_id);
    event.run_id = Some("fixture-runtime".into());
    event.turn_id = Some(turn_id.clone());
    event.source = Some(source);
    event.message_id = Some(format!("om_{index}"));
    event.original = Some(HistoryOriginalInfo {
        query_class,
        parent_id: None,
        original_kind: crate::ChatAtomKind::Text,
        tool_name: None,
    });
    event.occurred_at = Some(index as i64);
    let manifest = pack_bodies(
        &mut event,
        vec![PendingBody::new(
            "body",
            HistoryBodyRole::Body,
            Some("text/plain".into()),
            text.as_bytes().to_vec(),
        )],
        database_id,
    )?;
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "text".into(),
        meta,
        data: serde_json::json!({
            "channel": channel,
            "inputId": input_id,
        }),
        bodies: manifest,
        source_order: None,
        turn_id: Some(turn_id),
        captured_at: None,
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(event)
}

fn history_change(
    event_id: &str,
    kind: HistoryEventKind,
    atom: &crate::ChatAtom,
    recorded_at: i64,
) -> Result<HistoryEvent> {
    let state = match &atom.lifecycle {
        crate::ChatAtomLifecycle::Active { status, .. } => {
            HistoryEntityState::KnownActive { status: *status }
        }
        crate::ChatAtomLifecycle::Terminal { outcome, .. } => {
            HistoryEntityState::KnownTerminal { outcome: *outcome }
        }
    };
    let meta = HistoryEventMeta {
        entity_id: atom.id.clone(),
        entity_kind: atom.kind,
        delivery: atom.delivery,
        state,
        started_at: atom.started_at,
        finished_at: atom.finished_at,
        text_channel: atom.text_channel,
        single_visibility: None,
        presentation_contract: None,
        source_order: atom.source_order,
        content_present: atom.content_present,
        wait: atom
            .wait
            .clone()
            .map(|presentation| crate::history::HistoryWaitHead::Inline { presentation }),
        tool: atom.tool.clone(),
    };
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: "contextCompaction".into(),
        meta,
        data: serde_json::json!({}),
        bodies: Vec::new(),
        source_order: atom.source_order,
        turn_id: atom.turn_id.clone(),
        captured_at: None,
    };
    let mut event = HistoryEvent::new(event_id, kind, HistoryTimelineRole::Hidden, recorded_at);
    event.entity_id = Some(atom.id.clone());
    event.turn_id = atom.turn_id.clone();
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(event)
}

#[test]
fn event_v3_writer_reader_is_independent_of_object_field_order() -> Result<()> {
    let history = text_original(1, crate::ThreadTextChannel::Final, "original", "fixture-db")?;
    let record = history.to_record();
    let envelope = decode_event_envelope(&record)?;
    let event = EventV3 {
        schema_version: super::types::EVENTS_SCHEMA_VERSION,
        run_id: "field-order-run".into(),
        event_seq: 1,
        body: EventBodyV3::Completion {
            header: Box::new(ChatItemHeaderExportV3::from_history(&record)),
            atom: Box::new(envelope.meta),
            payload: ExportedBlobV3 {
                path: "contents/payload.bin".into(),
                byte_length: 7,
                sha256: "payload-sha".into(),
                media_type: Some("application/json".into()),
                encoding: "utf-8".into(),
            },
            contents_manifest: ExportedBlobV3 {
                path: "contents/manifest.bin".into(),
                byte_length: 8,
                sha256: "manifest-sha".into(),
                media_type: Some("application/x-ndjson".into()),
                encoding: "utf-8".into(),
            },
        },
        emitted_at: "2026-11-13T15:00:00.020Z".into(),
        thread_id: Some("thread-root".into()),
        source: EventSourceV3 {
            history_event_id: Some("event-1".into()),
            history_event_seq: Some(1),
            effect_seq: None,
            turn_id: Some("turn-1".into()),
            attempt_id: None,
            tool_call_id: None,
            current_owner_id: None,
            current_revision: None,
        },
    };
    let encoded = serde_json::to_string(&event)?;
    assert_eq!(serde_json::from_str::<EventV3>(&encoded)?, event);

    let body_first = r#"{"schemaVersion":3,"runId":"order-run","eventSeq":1,"type":"runStarted","data":{"runId":"order-run","build":{"version":"1.0.0","gitCommit":null,"target":"test"},"manifestSha256":"manifest"},"emittedAt":"2026-11-13T15:00:00.010Z","threadId":null,"source":{"historyEventId":null,"historyEventSeq":null,"effectSeq":null,"turnId":null,"attemptId":null,"toolCallId":null,"currentOwnerId":null,"currentRevision":null}}"#;
    let metadata_first = r#"{"emittedAt":"2026-11-13T15:00:00.010Z","source":{"historyEventId":null,"historyEventSeq":null,"effectSeq":null,"turnId":null,"attemptId":null,"toolCallId":null,"currentOwnerId":null,"currentRevision":null},"threadId":null,"data":{"manifestSha256":"manifest","build":{"target":"test","gitCommit":null,"version":"1.0.0"},"runId":"order-run"},"type":"runStarted","eventSeq":1,"runId":"order-run","schemaVersion":3}"#;
    let decoded_body_first: EventV3 = serde_json::from_str(body_first)?;
    let decoded_metadata_first: EventV3 = serde_json::from_str(metadata_first)?;
    assert_eq!(decoded_body_first, decoded_metadata_first);
    Ok(())
}

#[tokio::test]
async fn history_export_streams_body_directories_larger_than_one_page() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let history = HistoryStore::open(
        &temp.path().join("manifest-history.sqlite"),
        "manifest-thread",
        HistoryLimits::default(),
    )
    .await?;
    let reader = history.reader();
    let mut event = text_original(
        1,
        crate::ThreadTextChannel::Final,
        "manifest original",
        reader.database_id(),
    )?;
    for index in 0..260 {
        event.bodies.push(HistoryBody::new(
            format!("item:part.outputText.{index}"),
            HistoryBodyRole::Body,
            b"x".to_vec(),
        ));
    }
    let events = [event];
    history.accept_batch(&events).await?;
    history.flush().await?;
    let (cut, history_seq) = reader.capture_position().await?;
    let mut sink = FsContentBlobSink::new(temp.path().join("manifest-export"));
    let page = export_history_originals_window(&reader, history_seq, 0, &mut sink).await?;
    assert_eq!(page.records.len(), 1);
    assert!(!page.has_more);
    let manifest = read_contents_manifest(
        &temp.path().join("manifest-export"),
        &page.records[0].contents_manifest,
    )?;
    assert_eq!(manifest.len(), 261);
    assert!(
        manifest
            .iter()
            .any(|entry| entry.body_key == "body" && entry.native_ref.is_none())
    );
    assert!(
        manifest
            .iter()
            .any(|entry| entry.body_key == "item:part.outputText.259" && entry.native_ref.is_some())
    );
    assert!(!cut.token.is_empty());
    Ok(())
}

fn build_and_reconcile_usage(
    trace_complete: bool,
    threads: &[ThreadUsageInput<'_>],
) -> super::usage::BuiltUsageExport {
    let mut acc = UsageAccumulator::default();
    let mut replays = Vec::new();
    for thread in threads {
        let mut replay = UsageSummary {
            applied_sequence: thread.initial_effect_seq,
            ..Default::default()
        };
        for receipt in thread.receipts {
            fold_next_accounting(thread.thread_id, receipt, &mut replay)
                .expect("contiguous test receipts");
            acc.record(receipt);
        }
        replays.push(replay);
    }
    let inputs: Vec<_> = threads
        .iter()
        .zip(&replays)
        .map(|(thread, replayed)| super::usage::ThreadUsageInput {
            thread_id: thread.thread_id,
            through_effect_seq: thread.through_effect_seq,
            summary: thread.summary,
            replayed,
        })
        .collect();
    acc.finish(trace_complete, &inputs)
}

fn aux_effect(
    thread_id: &str,
    sequence: u64,
    inference_id: &str,
    account_id: &str,
    model_id: Option<&str>,
    usage: UsageReport,
    pricing: PricingOutcome,
) -> Result<PreparedAccounting> {
    let payload = AuxiliaryBillingReceipt {
        billing: InferenceBillingRecord {
            inference_id: inference_id.to_string(),
            purpose: Some("title".to_string()),
            account_id: account_id.to_string(),
            account_display_name: None,
            model_id: model_id.map(str::to_string),
            model_observation: None,
            effort: None,
            requested_service_tier: None,
            context_window: None,
            accounting: InferenceAccounting {
                usage,
                pricing,
                price_snapshot: None,
                request_started_at: Some(1_763_000_000_000),
            },
            prompt_generation: None,
            prompt_cache_policy: None,
            prefix_changed_reason: None,
            orchestration: Default::default(),
            timing: None,
            recorded_at: 1_763_000_000_100 + sequence as i64,
        },
        succeeded: true,
    }
    .into_payload()?;
    let effect = ThreadEffectBatch {
        thread_id: thread_id.to_string(),
        sequence,
        committed_at: 1_763_000_000_100 + sequence as i64,
        extensions: vec![ExtensionChange::Put {
            id: inference_id.to_string(),
            record: ExtensionRecord {
                revision: 1,
                payload,
            },
        }]
        .into(),
        ..Default::default()
    };
    let prepared = PreparedAccounting::prepare(&effect)?;
    assert!(prepared.binding().is_none());
    Ok(prepared)
}

fn fold_all(initial_seq: u64, receipts: &[PreparedAccounting]) -> UsageSummary {
    let mut summary = UsageSummary {
        applied_sequence: initial_seq,
        ..UsageSummary::default()
    };
    for receipt in receipts {
        if receipt.sequence > summary.applied_sequence {
            receipt.fold_into(&mut summary);
        }
    }
    summary
}

#[test]
fn usage_and_cost_reconciliation_covers_unknown_zero_overflow_and_model_switch() -> Result<()> {
    // 1. Unknown tokens + Unpriced stay null without fabricating 0; explicit 0 stays Some(0).
    let r1 = aux_effect(
        "t-unknown",
        1,
        "inf-1",
        "acct-a",
        Some("vendor/m1"),
        UsageReport {
            input_tokens: Some(100),
            output_tokens: None,
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(100),
        },
        PricingOutcome::Unpriced {
            reason: UnpricedReason::MissingPrice,
        },
    )?;
    let r2 = aux_effect(
        "t-unknown",
        2,
        "inf-2",
        "acct-a",
        Some("vendor/m2"),
        UsageReport {
            input_tokens: Some(0),
            output_tokens: Some(0),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(0),
        },
        PricingOutcome::NoCharge,
    )?;
    let receipts = vec![r1, r2];
    let summary = fold_all(0, &receipts);
    let built = build_and_reconcile_usage(
        true,
        &[ThreadUsageInput {
            thread_id: "t-unknown",
            initial_effect_seq: 0,
            through_effect_seq: 2,
            summary: &summary,
            receipts: &receipts,
        }],
    );
    assert!(built.reconciled);
    assert!(!built.usage_complete);
    assert!(!built.cost_complete);
    assert_eq!(built.export.coverage, UsageCoverage::Complete);
    assert!(built.export.has_unknown_values);
    assert_eq!(built.export.totals.inference_count, Some(2));
    assert_eq!(built.export.totals.input_tokens, Some(100));
    assert_eq!(built.export.totals.output_tokens, None);
    assert_eq!(built.export.known_totals.output_tokens, 0);
    assert_eq!(built.export.totals.estimated_cost_usd, None);
    assert_eq!(built.export.by_model.len(), 2);
    // Model 2 (vendor/m2) retains frozen identity & NoCharge => 0.0 USD and complete!
    let m2 = built
        .export
        .by_model
        .iter()
        .find(|m| m.model_id.as_deref() == Some("vendor/m2"))
        .expect("vendor/m2 entry");
    assert_eq!(m2.totals.output_tokens, Some(0));
    assert_eq!(m2.totals.estimated_cost_usd, Some(0.0));
    assert!(m2.unknown_fields.is_empty());
    let m1 = built
        .export
        .by_model
        .iter()
        .find(|m| m.model_id.as_deref() == Some("vendor/m1"))
        .expect("vendor/m1 entry");
    assert!(m1.unknown_fields.contains(&UsageMetricKey::OutputTokens));
    assert!(
        m1.unknown_fields
            .contains(&UsageMetricKey::EstimatedCostUsd)
    );

    // 2. Non-USD pricing cannot coerce to USD cost_complete.
    let r_eur = aux_effect(
        "t-eur",
        1,
        "inf-eur",
        "acct-eur",
        Some("eu/model"),
        UsageReport {
            input_tokens: Some(10),
            output_tokens: Some(5),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(15),
        },
        PricingOutcome::Estimated {
            cost: RuntimeCostAmount {
                currency: "EUR".to_string(),
                amount: 1.5,
            },
            cache_savings: None,
        },
    )?;
    let sum_eur = fold_all(0, std::slice::from_ref(&r_eur));
    let built_eur = build_and_reconcile_usage(
        true,
        &[ThreadUsageInput {
            thread_id: "t-eur",
            initial_effect_seq: 0,
            through_effect_seq: 1,
            summary: &sum_eur,
            receipts: std::slice::from_ref(&r_eur),
        }],
    );
    assert!(built_eur.reconciled);
    assert!(built_eur.usage_complete);
    assert!(!built_eur.cost_complete);
    assert_eq!(built_eur.export.totals.estimated_cost_usd, None);

    // 3. Contradictory explicit total_tokens makes usage incomplete (unknown total_tokens).
    let r_contradict = aux_effect(
        "t-contradict",
        1,
        "inf-contradict",
        "acct-c",
        Some("m-c"),
        UsageReport {
            input_tokens: Some(10),
            output_tokens: Some(5),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(999),
        },
        PricingOutcome::NoCharge,
    )?;
    let sum_contradict = fold_all(0, std::slice::from_ref(&r_contradict));
    let built_contradict = build_and_reconcile_usage(
        true,
        &[ThreadUsageInput {
            thread_id: "t-contradict",
            initial_effect_seq: 0,
            through_effect_seq: 1,
            summary: &sum_contradict,
            receipts: std::slice::from_ref(&r_contradict),
        }],
    );
    assert!(built_contradict.reconciled);
    assert!(!built_contradict.usage_complete);
    assert_eq!(built_contradict.export.totals.total_tokens, None);

    // 4. u64::MAX overflow flags overflow without wrapping.
    let r_big1 = aux_effect(
        "t-ovf",
        1,
        "inf-b1",
        "acct-o",
        Some("m-o"),
        UsageReport {
            input_tokens: Some(u64::MAX),
            output_tokens: Some(0),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(u64::MAX),
        },
        PricingOutcome::NoCharge,
    )?;
    let r_big2 = aux_effect(
        "t-ovf",
        2,
        "inf-b2",
        "acct-o",
        Some("m-o"),
        UsageReport {
            input_tokens: Some(1),
            output_tokens: Some(0),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(1),
        },
        PricingOutcome::NoCharge,
    )?;
    let big_receipts = vec![r_big1, r_big2];
    let sum_big = fold_all(0, &big_receipts);
    let built_big = build_and_reconcile_usage(
        true,
        &[ThreadUsageInput {
            thread_id: "t-ovf",
            initial_effect_seq: 0,
            through_effect_seq: 2,
            summary: &sum_big,
            receipts: &big_receipts,
        }],
    );
    assert!(built_big.reconciled);
    assert!(!built_big.usage_complete);
    assert!(
        built_big.cost_complete,
        "token overflow must not invalidate known NoCharge costs"
    );
    assert_eq!(built_big.export.totals.input_tokens, None);

    // 5. Reconciliation mismatch against tampered UsageSummary fails reconciliation cleanly.
    let mut tampered = summary.clone();
    tampered.totals.prompt_tokens += 42;
    let built_mismatch = build_and_reconcile_usage(
        true,
        &[ThreadUsageInput {
            thread_id: "t-unknown",
            initial_effect_seq: 0,
            through_effect_seq: 2,
            summary: &tampered,
            receipts: &receipts,
        }],
    );
    assert!(!built_mismatch.reconciled);
    assert!(built_mismatch.reconcile_error.is_some());

    // 6. Empty receipts keeps zero usageComplete & costComplete.
    let empty_summary = UsageSummary::default();
    let built_empty = build_and_reconcile_usage(
        true,
        &[ThreadUsageInput {
            thread_id: "t-empty",
            initial_effect_seq: 0,
            through_effect_seq: 0,
            summary: &empty_summary,
            receipts: &[],
        }],
    );
    assert!(built_empty.reconciled);
    assert!(built_empty.usage_complete);
    assert!(built_empty.cost_complete);
    assert_eq!(built_empty.export.totals.inference_count, Some(0));
    assert_eq!(built_empty.export.totals.estimated_cost_usd, Some(0.0));
    Ok(())
}

#[tokio::test]
async fn missing_effects_and_conflicting_blobs_cannot_be_sealed() -> Result<()> {
    use super::writer::{BlobChunkWriter, ContentBlobSink};
    let skipped = PreparedAccounting::prepare(&ThreadEffectBatch {
        thread_id: "gap".into(),
        sequence: 2,
        ..Default::default()
    })?;
    let mut replay = UsageSummary::default();
    assert!(fold_next_accounting("gap", &skipped, &mut replay).is_err());
    assert_eq!(
        replay,
        UsageSummary::default(),
        "reject the gap before changing the reducer"
    );

    let dir = tempfile::tempdir()?;
    let mut sink = FsContentBlobSink::new(dir.path().to_path_buf());
    let mut writer = sink.begin_blob().await?;
    writer.write_chunk(b"safe").await?;
    let target = dir
        .path()
        .join(format!("contents/{}.bin", super::sha256_hex(b"safe")));
    std::fs::write(&target, b"evil")?;
    assert!(writer.finish(None, "utf-8".into()).await.is_err());
    assert_eq!(
        std::fs::read(&target)?,
        b"evil",
        "never overwrite a conflicting hash target"
    );
    assert_eq!(
        std::fs::read_dir(dir.path().join("contents"))?.count(),
        1,
        "failed blob temporaries must be removed"
    );

    #[cfg(unix)]
    {
        let linked = tempfile::tempdir()?;
        let external = tempfile::tempdir()?;
        std::os::unix::fs::symlink(external.path(), linked.path().join("contents"))?;
        let mut sink = FsContentBlobSink::new(linked.path().to_path_buf());
        assert!(sink.begin_blob().await.is_err());
        assert_eq!(std::fs::read_dir(external.path())?.count(), 0);
    }
    Ok(())
}

#[tokio::test]
async fn writer_bounded_backpressure_drains_on_resume_and_unblocks_on_deadline() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let out_dir = dir.path().join("export-bp");
    let studio_home = dir.path().join("home");
    std::fs::create_dir_all(&studio_home)?;
    std::fs::write(studio_home.join("config.toml"), "[models]\n")?;

    let exporter = RunExporter::start(RunExportOptions {
        output_dir: out_dir.clone(),
        run_id: uuid::Uuid::new_v4().to_string(),
        cwd: dir.path().to_path_buf(),
        studio_home: studio_home.clone(),
        account_id: Some("acct".to_string()),
        model_id: Some("vendor/m".to_string()),
        reasoning_effort: None,
        mode: Some("mode.simple".to_string()),
        max_model_steps: None,
        prompt_sha256: "a".repeat(64),
        skill_search: Default::default(),
        config: None,
    })
    .await?;

    let coordinator = exporter.coordinator();
    let history = HistoryStore::open(
        &dir.path().join("hist.sqlite"),
        "t-root",
        HistoryLimits::default(),
    )
    .await?;
    let history_reader = history.reader();
    coordinator.enroll_root("t-root");
    coordinator
        .register_member(NewMemberRegistration {
            root_thread_id: "t-root".into(),
            thread_id: "t-root".into(),
            agent_id: "agent-root".into(),
            parent_agent_id: None,
            parent_thread_id: None,
            role: Some("root".into()),
            workspace_id: "ws-1".into(),
            spawn_tool_call_id: None,
            initial_effect_seq: 0,
            history: history_reader.clone(),
        })
        .await;

    // Pause the writer before filling its bounded queue.
    let queue = coordinator.queue();
    queue.set_paused(true);

    // Poll the original producer to the full queue, then release the writer.
    let queue_clone = queue.clone();
    let producer = async move {
        for idx in 0..=MAX_QUEUED_BATCHES {
            let res = queue_clone
                .admit(
                    ExportCommand::SkillsDiscovered {
                        thread_id: "t-root".to_string(),
                        report: pl_tool::skill::SkillDiscoveryReport {
                            source_fingerprint: format!("fp-{idx}"),
                            sources: Vec::new(),
                            winners: Vec::new(),
                            warnings: Vec::new(),
                            complete: true,
                        },
                    },
                    64,
                )
                .await;
            if res.is_err() {
                return false;
            }
        }
        true
    };
    tokio::pin!(producer);
    assert!(
        futures::poll!(&mut producer).is_pending(),
        "bounded queue must apply backpressure"
    );
    assert_eq!(queue.queued_counts().0, MAX_QUEUED_BATCHES);

    queue.set_paused(false);
    assert!(tokio::time::timeout(Duration::from_secs(5), producer).await?);

    let history_cut = history_checkpoint(&history_reader).await?;
    let cut = RetiredThreadCut {
        thread_id: "t-root".into(),
        through_effect_seq: 0,
        history: history_reader.clone(),
        history_cut: history_cut.cut,
        history_seq: history_cut.history_seq,
        summary: UsageSummary::default(),
        status: Some("retired".into()),
        aborted: false,
        error: None,
    };
    coordinator.record_thread_final_cut(cut);
    let report = coordinator
        .finalize_internal(None, true, true, Some(0), None)
        .await;
    assert!(report.trace_complete, "{:?}", report.failure);
    assert!(report.trace.sealed);

    // Also verify tight shutdown deadline + permanent close unblocks waiting producers cleanly.
    let out_dir2 = dir.path().join("export-deadline");
    let exp2 = RunExporter::start(RunExportOptions {
        output_dir: out_dir2,
        run_id: uuid::Uuid::new_v4().to_string(),
        cwd: dir.path().to_path_buf(),
        studio_home,
        account_id: Some("acct".to_string()),
        model_id: Some("vendor/m".to_string()),
        reasoning_effort: None,
        mode: Some("mode.simple".to_string()),
        max_model_steps: None,
        prompt_sha256: "b".repeat(64),
        skill_search: Default::default(),
        config: None,
    })
    .await?;
    let coord2 = exp2.coordinator();
    let q2 = coord2.queue();
    q2.set_paused(true);
    let blocked = {
        let q = q2.clone();
        async move {
            for _ in 0..=MAX_QUEUED_BATCHES + 1 {
                if q.admit(
                    ExportCommand::SkillsDiscovered {
                        thread_id: "t-none".into(),
                        report: pl_tool::skill::SkillDiscoveryReport {
                            source_fingerprint: "fp".into(),
                            sources: Vec::new(),
                            winners: Vec::new(),
                            warnings: Vec::new(),
                            complete: true,
                        },
                    },
                    64,
                )
                .await
                .is_err()
                {
                    return false;
                }
            }
            true
        }
    };
    tokio::pin!(blocked);
    assert!(futures::poll!(&mut blocked).is_pending());
    assert_eq!(q2.queued_counts().0, MAX_QUEUED_BATCHES);
    let deadline = tokio::time::Instant::now() + Duration::from_millis(25);
    coord2.arm_shutdown_deadline(Some(deadline));
    coord2.close_admission_on_producer_timeout();
    assert!(!tokio::time::timeout(Duration::from_secs(2), blocked).await?);
    let report2 = coord2
        .finalize_internal(None, false, false, Some(1), Some(deadline))
        .await;
    assert!(!report2.trace_complete);
    assert!(!report2.trace.sealed);
    Ok(())
}

#[tokio::test]
async fn writer_idempotency_and_conflict_matrix() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let studio_home = dir.path().join("home");
    std::fs::create_dir_all(&studio_home)?;
    std::fs::write(studio_home.join("config.toml"), "[models]\n")?;
    let history = HistoryStore::open(
        &dir.path().join("h.sqlite"),
        "t-idem",
        HistoryLimits::default(),
    )
    .await?;
    let history_reader = history.reader();
    let current = test_current("t-idem", 0)?;

    // 1. Identical redelivery & non-billing effect sequence advance stay idempotent & sealed.
    let exporter = RunExporter::start(RunExportOptions {
        output_dir: dir.path().join("idem-ok"),
        run_id: uuid::Uuid::new_v4().to_string(),
        cwd: dir.path().to_path_buf(),
        studio_home: studio_home.clone(),
        account_id: Some("acct".into()),
        model_id: Some("m".into()),
        reasoning_effort: None,
        mode: Some("mode.simple".into()),
        max_model_steps: None,
        prompt_sha256: "c".repeat(64),
        skill_search: Default::default(),
        config: None,
    })
    .await?;
    let coord = exporter.coordinator();
    coord.enroll_root("t-idem");
    let make_reg = || NewMemberRegistration {
        root_thread_id: "t-idem".into(),
        thread_id: "t-idem".into(),
        agent_id: "agent-idem".into(),
        parent_agent_id: None,
        parent_thread_id: None,
        role: Some("root".into()),
        workspace_id: "ws-1".into(),
        spawn_tool_call_id: None,
        initial_effect_seq: 0,
        history: history_reader.clone(),
    };
    coord.register_member(make_reg()).await;
    coord.register_member(make_reg()).await; // identical re-registration

    // Non-billing effect at seq=1, followed by billing effect at seq=2 redelivered twice identically.
    let non_billing = PreparedAccounting::prepare(&ThreadEffectBatch {
        thread_id: "t-idem".into(),
        sequence: 1,
        committed_at: 100,
        ..Default::default()
    })?;
    let billing = aux_effect(
        "t-idem",
        2,
        "inf-idem",
        "acct",
        Some("m"),
        UsageReport {
            input_tokens: Some(10),
            output_tokens: Some(5),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(15),
        },
        PricingOutcome::NoCharge,
    )?;
    let mut summary = UsageSummary::default();
    non_billing.fold_into(&mut summary);
    billing.fold_into(&mut summary);

    let mut atom = crate::ChatAtom {
        id: "bodyless".into(),
        completion_item_id: None,
        completion_seq: None,
        source: crate::ChatSourceId::Operation {
            operation_id: "bodyless".into(),
        },
        source_state: None,
        source_order: None,
        kind: crate::ChatAtomKind::Compaction,
        delivery: crate::ChatDeliveryKind::Independent,
        lifecycle: crate::ChatAtomLifecycle::Active {
            started: Some(crate::ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            status: crate::ChatActiveStatus::Running,
        },
        turn_id: None,
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: None,
        started_at: None,
        finished_at: None,
        content_present: None,
        contents: vec![],
        payload: None,
    };
    let start = history_change(
        "lifecycle-start",
        HistoryEventKind::CompactionStarted,
        &atom,
        1,
    )?;
    atom.lifecycle = crate::ChatAtomLifecycle::Terminal {
        started: Some(crate::ChatFactPosition {
            effect_seq: 1,
            suborder: 0,
        }),
        ended: Some(crate::ChatFactPosition {
            effect_seq: 2,
            suborder: 0,
        }),
        outcome: crate::ChatTerminalOutcome::Cancelled,
    };
    let end = history_change(
        "lifecycle-end",
        HistoryEventKind::CompactionCompleted,
        &atom,
        2,
    )?;
    let start: Arc<[_]> = Arc::from([start]);
    let end: Arc<[_]> = Arc::from([end]);
    coord
        .admit_live_handoff(
            "t-idem",
            &non_billing,
            &start,
            &summary,
            &current,
            &history_reader,
        )
        .await;
    coord
        .admit_live_handoff(
            "t-idem",
            &billing,
            &end,
            &summary,
            &current,
            &history_reader,
        )
        .await;
    coord
        .admit_live_handoff(
            "t-idem",
            &billing,
            &end,
            &summary,
            &current,
            &history_reader,
        )
        .await; // idempotent redelivery

    let final_history = history_checkpoint(&history_reader).await?;
    coord.record_thread_final_cut(RetiredThreadCut {
        thread_id: "t-idem".into(),
        through_effect_seq: 2,
        history: history_reader.clone(),
        history_cut: final_history.cut,
        history_seq: final_history.history_seq,
        summary: summary.clone(),
        status: Some("retired".into()),
        aborted: false,
        error: None,
    });
    let ok_report = coord
        .finalize_internal(None, true, true, Some(0), None)
        .await;
    assert!(ok_report.trace_complete, "{:?}", ok_report.failure);
    let usage = ok_report.usage.as_ref().expect("usage present");
    assert_eq!(usage.totals.inference_count, Some(1));
    assert_eq!(usage.totals.total_tokens, Some(15));

    let events = std::fs::read_to_string(dir.path().join("idem-ok/events.jsonl"))?
        .lines()
        .map(serde_json::from_str::<EventV3>)
        .collect::<Result<Vec<_>, _>>()?;
    let facts = events
        .iter()
        .filter_map(|event| match &event.body {
            super::types::EventBodyV3::ExecutionLifecycle { facts } => Some(facts),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(
        facts.len(),
        2,
        "identical redelivery must not duplicate a lifecycle event"
    );
    assert!(
        facts
            .iter()
            .flat_map(|facts| facts.iter())
            .all(|fact| !fact.event_id.is_empty()
                && fact.occurred_at.is_none()
                && fact.head.started_at.is_none()
                && fact.head.finished_at.is_none()
                && fact.head.tool.is_none()),
        "bodyless starts and unknown times cannot become fabricated completions"
    );
    assert_eq!(
        facts[1][0].head.state,
        HistoryEntityState::KnownTerminal {
            outcome: crate::ChatTerminalOutcome::Cancelled
        }
    );
    // 2. Conflicting effect at same (threadId, effectSeq) triggers fatal failure + cancellation.
    let exp_conflict = RunExporter::start(RunExportOptions {
        output_dir: dir.path().join("idem-conflict"),
        run_id: uuid::Uuid::new_v4().to_string(),
        cwd: dir.path().to_path_buf(),
        studio_home,
        account_id: Some("acct".into()),
        model_id: Some("m".into()),
        reasoning_effort: None,
        mode: Some("mode.simple".into()),
        max_model_steps: None,
        prompt_sha256: "d".repeat(64),
        skill_search: Default::default(),
        config: None,
    })
    .await?;
    let c2 = exp_conflict.coordinator();
    c2.enroll_root("t-idem");
    c2.register_member(NewMemberRegistration {
        root_thread_id: "t-idem".into(),
        thread_id: "t-idem".into(),
        agent_id: "agent-idem".into(),
        parent_agent_id: None,
        parent_thread_id: None,
        role: Some("root".into()),
        workspace_id: "ws-1".into(),
        spawn_tool_call_id: None,
        initial_effect_seq: 0,
        history: history_reader.clone(),
    })
    .await;
    let changed_billing = aux_effect(
        "t-idem",
        2,
        "inf-different",
        "acct",
        Some("m"),
        UsageReport {
            input_tokens: Some(99),
            output_tokens: Some(1),
            cache_read_tokens: Some(0),
            cache_write_tokens: Some(0),
            reasoning_tokens: Some(0),
            total_tokens: Some(100),
        },
        PricingOutcome::NoCharge,
    )?;
    c2.admit_live_handoff(
        "t-idem",
        &billing,
        &Arc::from([]),
        &summary,
        &current,
        &history_reader,
    )
    .await;
    c2.admit_live_handoff(
        "t-idem",
        &changed_billing,
        &Arc::from([]),
        &summary,
        &current,
        &history_reader,
    )
    .await;
    assert!(exp_conflict.cancellation().is_cancelled());
    let bad_report = c2.finalize_internal(None, true, true, Some(0), None).await;
    assert!(!bad_report.trace_complete);
    assert!(!bad_report.trace.sealed);
    assert_eq!(
        bad_report.failure.as_ref().map(|f| f.code.as_str()),
        Some("effectRedeliveryConflict")
    );
    // 3. The same inference in a later effect is a conflict even when native totals
    // also counted it twice. Reconciliation alone must not legitimize duplicate billing.
    for missing_events in [false, true] {
        if missing_events && !cfg!(unix) {
            continue;
        }
        let out_dir = dir.path().join(if missing_events {
            "missing-events"
        } else {
            "cross-effect"
        });
        let exporter = RunExporter::start(RunExportOptions {
            output_dir: out_dir.clone(),
            run_id: uuid::Uuid::new_v4().to_string(),
            cwd: dir.path().to_path_buf(),
            studio_home: dir.path().join("home"),
            account_id: None,
            model_id: None,
            reasoning_effort: None,
            mode: None,
            max_model_steps: None,
            prompt_sha256: "a".repeat(64),
            skill_search: Default::default(),
            config: None,
        })
        .await?;
        let coordinator = exporter.coordinator();
        coordinator.enroll_root("t-idem");
        coordinator.register_member(make_reg()).await;
        coordinator
            .admit_live_handoff(
                "t-idem",
                &non_billing,
                &Arc::from([]),
                &summary,
                &current,
                &history_reader,
            )
            .await;
        coordinator
            .admit_live_handoff(
                "t-idem",
                &billing,
                &Arc::from([]),
                &summary,
                &current,
                &history_reader,
            )
            .await;
        let mut final_summary = summary.clone();
        if missing_events {
            // An open Unix file remains writable after unlink. Finalization must reject the
            // missing archive path rather than claim success with a null event-file hash.
            let events = out_dir.join("events.jsonl");
            tokio::time::timeout(Duration::from_secs(5), async {
                while !events.exists() {
                    tokio::task::yield_now().await;
                }
            })
            .await?;
            std::fs::remove_file(events)?;
        } else {
            let mut repeated = billing.clone();
            repeated.sequence = 3;
            repeated.fold_into(&mut final_summary);
            coordinator
                .admit_live_handoff(
                    "t-idem",
                    &repeated,
                    &Arc::from([]),
                    &final_summary,
                    &current,
                    &history_reader,
                )
                .await;
        }
        let final_history = history_checkpoint(&history_reader).await?;
        coordinator.record_thread_final_cut(RetiredThreadCut {
            thread_id: "t-idem".into(),
            through_effect_seq: final_summary.applied_sequence,
            history: history_reader.clone(),
            history_cut: final_history.cut,
            history_seq: final_history.history_seq,
            summary: final_summary,
            status: Some("closed".into()),
            aborted: false,
            error: None,
        });
        let report = coordinator
            .finalize_internal(None, true, true, Some(0), None)
            .await;
        assert!(!report.trace_complete);
        assert!(!report.trace.sealed);
        let failure = report.failure.context("export must fail explicitly")?;
        if missing_events {
            assert_eq!(failure.code, "exportMeasureFailed");
            assert!(
                report.usage_complete,
                "complete accounting survives a content-file failure"
            );
        } else {
            assert!(
                failure.message.contains("inference_id conflict"),
                "{failure:?}"
            );
        }
    }
    Ok(())
}

#[test]
fn manifest_preflight_redaction_and_readonly_toml_fallback() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let existing_empty = dir.path().join("empty-dir");
    std::fs::create_dir_all(&existing_empty)?;
    validate_output_dir_preflight(&existing_empty)?;

    let not_created = dir.path().join("brand-new/sub");
    validate_output_dir_preflight(&not_created)?;
    assert!(
        !not_created.exists(),
        "preflight must remain read-only without creating output_dir"
    );

    let non_empty = dir.path().join("non-empty");
    std::fs::create_dir_all(&non_empty)?;
    std::fs::write(non_empty.join("sentinel.txt"), b"keep")?;
    assert!(validate_output_dir_preflight(&non_empty).is_err());

    let regular_file = dir.path().join("plain-file");
    std::fs::write(&regular_file, b"keep")?;
    assert!(validate_output_dir_preflight(&regular_file).is_err());

    #[cfg(unix)]
    {
        let symlink_target = dir.path().join("sym-target");
        std::fs::create_dir_all(&symlink_target)?;
        let symlink_out = dir.path().join("sym-out");
        std::os::unix::fs::symlink(&symlink_target, &symlink_out)?;
        assert!(validate_output_dir_preflight(&symlink_out).is_err());
    }

    // Read-only TOML parsing + redaction strips inline tokens/headers while keeping *_env names.
    let home = dir.path().join("studio-home");
    std::fs::create_dir_all(&home)?;
    std::fs::write(
        home.join("config.toml"),
        r#"
[skills]
enabled = false
external_dirs = ["/opt/ext-skills"]

[skills.system]
enabled = false

[models.accounts.acct1]
bearer_token_env = "ANYWK_SAFE_ENV_NAME"
bearer_token = "inline-secret-token-should-disappear"
http_headers = { "Authorization" = "Bearer secret", "X-Custom" = "val" }
"#,
    )?;
    let out = dir.path().join("manifest-out");
    std::fs::create_dir_all(&out)?;
    let (manifest, _sha) = write_run_manifest(&RunExportOptions {
        output_dir: out,
        run_id: uuid::Uuid::new_v4().to_string(),
        cwd: dir.path().to_path_buf(),
        studio_home: home,
        account_id: Some("acct1".into()),
        model_id: Some("m1".into()),
        reasoning_effort: None,
        mode: Some("mode.simple".into()),
        max_model_steps: None,
        prompt_sha256: "e".repeat(64),
        skill_search: Default::default(),
        config: None,
    })?;
    assert_eq!(manifest.invocation.max_model_steps, None);
    assert!(!manifest.skill_search.skills_enabled);
    assert!(!manifest.skill_search.system_enabled);
    assert_eq!(manifest.skill_search.external_dirs, vec!["/opt/ext-skills"]);
    let manifest_text = serde_json::to_string(&manifest)?;
    assert!(!manifest_text.contains("inline-secret-token-should-disappear"));
    assert!(!manifest_text.contains("Bearer secret"));
    assert!(
        manifest
            .config_inputs
            .iter()
            .all(|entry| entry.redacted_summary.is_none())
    );
    let config_entry = &manifest.config_inputs[0];
    assert_eq!(
        config_entry.sha256.as_deref(),
        Some(
            super::sha256_hex(&std::fs::read(
                manifest.invocation.studio_home.clone() + "/config.toml"
            )?)
            .as_str()
        )
    );
    Ok(())
}

#[tokio::test]
async fn retired_child_keeps_history_reader_and_streams_bounded_body_windows() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let studio_home = dir.path().join("home");
    std::fs::create_dir_all(&studio_home)?;
    let workspace = dir.path().join("task");
    std::fs::create_dir_all(&workspace)?;

    let child_thread_id = "closed-child-thread";
    let history = HistoryStore::open(
        &dir.path().join("closed-history.sqlite"),
        child_thread_id,
        HistoryLimits::default(),
    )
    .await?;
    let history_reader = history.reader();
    let exporter = RunExporter::start(RunExportOptions {
        output_dir: dir.path().join("backfill-out"),
        run_id: uuid::Uuid::new_v4().to_string(),
        cwd: workspace.clone(),
        studio_home,
        account_id: None,
        model_id: None,
        reasoning_effort: None,
        mode: None,
        max_model_steps: None,
        prompt_sha256: "a".repeat(64),
        skill_search: Default::default(),
        config: None,
    })
    .await?;
    let coord = exporter.coordinator();
    coord.enroll_root(child_thread_id);
    coord
        .register_member(NewMemberRegistration {
            root_thread_id: child_thread_id.into(),
            thread_id: child_thread_id.into(),
            agent_id: "child-agent".into(),
            parent_agent_id: Some("parent".into()),
            parent_thread_id: Some("parent-thread".into()),
            role: Some("child".into()),
            workspace_id: "ws-closed".into(),
            spawn_tool_call_id: Some("spawn".into()),
            initial_effect_seq: 0,
            history: history_reader.clone(),
        })
        .await;
    let huge_text = "中".repeat(320 * 1024);
    let mut events = Vec::new();
    for idx in 1..=257u64 {
        let content = if idx == 257 {
            huge_text.clone()
        } else {
            format!("message-{idx}")
        };
        events.push(text_original(
            idx,
            crate::ThreadTextChannel::ParentAgent,
            &content,
            history_reader.database_id(),
        )?);
    }
    history.accept_batch(&events).await?;
    history.flush().await?;
    let huge_original = history_reader
        .original_for_entity(
            "msg-257".into(),
            None,
            HistoryDemand {
                max_rows: 1,
                max_bytes: 1024 * 1024,
            },
        )
        .await?
        .context("History original msg-257 missing")?;
    let huge_body = history_reader
        .list_bodies(
            huge_original.event_id,
            None,
            HistoryDemand {
                max_rows: 128,
                max_bytes: 1024 * 1024,
            },
        )
        .await?
        .entries
        .into_iter()
        .find(|body| body.body_key == "body")
        .context("huge History body directory entry missing")?
        .reference;
    let mut offset = 0_u64;
    while offset < huge_body.byte_length {
        let window = history_reader
            .read_body(huge_body.clone(), offset, 64 * 1024)
            .await?;
        assert!(!window.bytes.is_empty() && window.bytes.len() <= 64 * 1024);
        offset += window.bytes.len() as u64;
    }
    assert_eq!(offset, huge_text.len() as u64);

    let final_history = history_checkpoint(&history_reader).await?;
    coord.record_thread_final_cut(RetiredThreadCut {
        thread_id: child_thread_id.into(),
        through_effect_seq: 0,
        history: history_reader.clone(),
        history_cut: final_history.cut,
        history_seq: final_history.history_seq,
        summary: UsageSummary::default(),
        status: Some("closed".into()),
        aborted: false,
        error: None,
    });
    // The retained HistoryReader is the only export source here; no live Current owner exists.
    drop(history);
    let expected_hash = hex::encode(Sha256::digest(huge_text.as_bytes()));
    let report = coord
        .finalize_internal(None, true, true, Some(0), None)
        .await;
    assert!(report.trace_complete, "{:?}", report.failure);
    let out_dir = exporter.output_dir().to_path_buf();
    let exported: Vec<EventV3> = std::fs::read_to_string(out_dir.join("events.jsonl"))?
        .lines()
        .map(serde_json::from_str)
        .collect::<Result<_, _>>()?;
    let completions = exported
        .iter()
        .filter_map(|event| match &event.body {
            EventBodyV3::Completion {
                atom,
                payload,
                contents_manifest,
                ..
            } => Some((event, atom, payload, contents_manifest)),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(completions.len(), 257);
    assert!(
        completions
            .iter()
            .all(|(event, atom, ..)| event.source.history_event_id.is_some()
                && event.source.history_event_seq.is_some()
                && atom.entity_kind == crate::ChatAtomKind::Text
                && atom.started_at.is_none()
                && atom.finished_at.is_none())
    );
    let (_, _, payload, contents_manifest) = completions
        .iter()
        .find(|(_, _, _, manifest)| {
            read_contents_manifest(&out_dir, manifest).is_ok_and(|contents| {
                contents
                    .iter()
                    .any(|content| content.sha256 == expected_hash)
            })
        })
        .context("huge original was not exported")?;
    let contents = read_contents_manifest(&out_dir, contents_manifest)?;
    let blob_path = out_dir.join(format!("contents/{expected_hash}.bin"));
    let exported_bytes = std::fs::read(&blob_path)?;
    assert_eq!(exported_bytes.len(), huge_text.len());
    assert_eq!(exported_bytes, huge_text.as_bytes());
    assert!(
        contents
            .iter()
            .any(|content| content.sha256 == expected_hash
                && content.byte_length == huge_text.len() as u64
                && content.encoding == "utf-8")
    );
    let payload_bytes = std::fs::read(out_dir.join(&payload.path))?;
    let payload: serde_json::Value = serde_json::from_slice(&payload_bytes)?;
    assert_eq!(payload["contract"], "anywork.event/1");
    Ok(())
}

#[test]
fn golden_fixtures_roundtrip_and_sha256_integrity() -> Result<()> {
    let fixture_root =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/run-export/v3");
    let run_bytes = std::fs::read(fixture_root.join("run.json"))?;
    let manifest: RunManifestV3 = serde_json::from_slice(&run_bytes)?;
    assert_eq!(manifest.schema_version, 3);
    let expected_manifest_sha = hex::encode(Sha256::digest(&run_bytes));

    let events_bytes = std::fs::read(fixture_root.join("events.jsonl"))?;
    let expected_events_sha = hex::encode(Sha256::digest(&events_bytes));
    let events_text = String::from_utf8(events_bytes)?;
    let events: Vec<EventV3> = events_text
        .lines()
        .map(serde_json::from_str)
        .collect::<Result<Vec<_>, _>>()?;
    assert!(!events.is_empty());
    for (idx, event) in events.iter().enumerate() {
        assert_eq!(event.event_seq, idx as u64 + 1);
    }

    match &events[0].body {
        super::types::EventBodyV3::RunStarted {
            manifest_sha256, ..
        } => assert_eq!(manifest_sha256, &expected_manifest_sha),
        other => anyhow::bail!("expected runStarted first, got {other:?}"),
    }

    // Verify all referenced payload + content blobs exist with matching SHA-256 and byte length.
    for event in &events {
        if let super::types::EventBodyV3::Completion {
            payload,
            contents_manifest,
            ..
        } = &event.body
        {
            let p_bytes = std::fs::read(fixture_root.join(&payload.path))?;
            assert_eq!(p_bytes.len() as u64, payload.byte_length);
            assert_eq!(hex::encode(Sha256::digest(&p_bytes)), payload.sha256);
            for content in read_contents_manifest(&fixture_root, contents_manifest)? {
                let c_bytes = std::fs::read(fixture_root.join(&content.path))?;
                assert_eq!(c_bytes.len() as u64, content.byte_length);
                assert_eq!(hex::encode(Sha256::digest(&c_bytes)), content.sha256);
            }
        }
    }

    let result: super::types::ResultV3 =
        serde_json::from_slice(&std::fs::read(fixture_root.join("result.json"))?)?;
    assert!(result.trace_complete);
    assert!(result.usage_complete);
    assert!(result.cost_complete);
    assert_eq!(
        result.trace.events_sha256.as_deref(),
        Some(expected_events_sha.as_str())
    );
    assert_eq!(result.trace.event_count, events.len() as u64);
    Ok(())
}
