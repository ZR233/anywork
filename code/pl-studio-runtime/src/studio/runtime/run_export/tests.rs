use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use pl_core::chat::{Session, TimelineEpoch};
use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};
use pl_core::thread::{ThreadEffectBatch, UsageSummary};
use pl_protocol::{
    InferenceAccounting, InferenceBillingRecord, PricingOutcome, RuntimeCostAmount, ThreadItem,
    UnpricedReason, UsageReport,
};
use sha2::{Digest, Sha256};

use super::manifest::{sanitize_json_value, validate_output_dir_preflight, write_run_manifest};
use super::reader::{export_completions_range, resolve_readonly_session};
use super::types::{
    EventV1, MAX_QUEUED_BATCHES, RunExportOptions, RunManifestV1, UsageCoverage, UsageMetricKey,
};
use super::usage::{ThreadUsageInput, build_and_reconcile_usage};
use super::writer::{ExportCommand, FsContentBlobSink};
use super::{NewMemberRegistration, RetiredThreadCut, RunExporter};
use crate::studio::paths::StudioPaths;
use crate::studio::storage::history::conversation::current::PreparedCurrent;
use crate::studio::storage::history::{EffectCommit, HistoryStore};
use crate::studio::store::StudioStore;
use crate::studio::store::directory::DirectoryDelta;
use crate::studio::thread_projection::{
    AuxiliaryBillingReceipt, FrozenCurrentProjection, PreparedAccounting,
};

fn test_current(sequence: u64) -> PreparedCurrent {
    PreparedCurrent::new(
        FrozenCurrentProjection::new(pl_protocol::CurrentProjection::empty(
            sequence,
            pl_protocol::ThreadStatus::Idle,
        )),
        Arc::from([]),
    )
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
async fn writer_bounded_backpressure_drains_on_resume_and_unblocks_on_deadline() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let out_dir = dir.path().join("export-bp");
    let studio_home = dir.path().join("home");
    std::fs::create_dir_all(&studio_home)?;
    std::fs::write(studio_home.join("config.toml"), "[models]\n")?;

    let exporter = RunExporter::start(RunExportOptions {
        output_dir: out_dir.clone(),
        run_id: "run-bp-1".to_string(),
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
    let history = HistoryStore::open(&dir.path().join("hist.sqlite"), "t-root").await?;
    let session = Session::new(history, TimelineEpoch::new("ep-1")?);
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
            session: session.clone(),
        })
        .await;

    // Wait briefly for initial RunStarted + AgentRegistered to settle, then pause writer.
    let queue = coordinator.queue();
    queue.set_paused(true);

    // Fill queue past MAX_QUEUED_BATCHES (256) in a background producer and prove it blocks.
    let queue_clone = queue.clone();
    let producer = tokio::spawn(async move {
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
    });

    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let (batches, _) = queue.queued_counts();
            if batches >= MAX_QUEUED_BATCHES {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await?;
    assert!(
        !producer.is_finished(),
        "bounded queue must apply backpressure"
    );

    queue.set_paused(false);
    assert!(tokio::time::timeout(Duration::from_secs(5), producer).await??);

    let cut = RetiredThreadCut {
        thread_id: "t-root".into(),
        through_effect_seq: 0,
        session: session.clone(),
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
        run_id: "run-bp-2".to_string(),
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
    let blocked = tokio::spawn({
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
    });
    tokio::time::timeout(Duration::from_secs(5), async {
        while q2.queued_counts().0 < MAX_QUEUED_BATCHES {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await?;
    let deadline = tokio::time::Instant::now() + Duration::from_millis(25);
    coord2.arm_shutdown_deadline(Some(deadline));
    coord2.close_admission_on_producer_timeout();
    assert!(!tokio::time::timeout(Duration::from_secs(2), blocked).await??);
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
    let history = HistoryStore::open(&dir.path().join("h.sqlite"), "t-idem").await?;
    let session = Session::new(history, TimelineEpoch::new("ep-idem")?);

    // 1. Identical redelivery & non-billing effect sequence advance stay idempotent & sealed.
    let exporter = RunExporter::start(RunExportOptions {
        output_dir: dir.path().join("idem-ok"),
        run_id: "run-idem-ok".into(),
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
        session: session.clone(),
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

    coord
        .admit_live_handoff("t-idem", &non_billing, &summary, &session)
        .await;
    coord
        .admit_live_handoff("t-idem", &billing, &summary, &session)
        .await;
    coord
        .admit_live_handoff("t-idem", &billing, &summary, &session)
        .await; // idempotent redelivery

    coord.record_thread_final_cut(RetiredThreadCut {
        thread_id: "t-idem".into(),
        through_effect_seq: 2,
        session: session.clone(),
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

    // 2. Conflicting effect at same (threadId, effectSeq) triggers fatal failure + cancellation.
    let exp_conflict = RunExporter::start(RunExportOptions {
        output_dir: dir.path().join("idem-conflict"),
        run_id: "run-idem-bad".into(),
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
        session: session.clone(),
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
    c2.admit_live_handoff("t-idem", &billing, &summary, &session)
        .await;
    c2.admit_live_handoff("t-idem", &changed_billing, &summary, &session)
        .await;
    assert!(exp_conflict.cancellation().is_cancelled());
    let bad_report = c2.finalize_internal(None, true, true, Some(0), None).await;
    assert!(!bad_report.trace_complete);
    assert!(!bad_report.trace.sealed);
    assert_eq!(
        bad_report.failure.as_ref().map(|f| f.code.as_str()),
        Some("effectRedeliveryConflict")
    );
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
        run_id: "run-manifest-test".into(),
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
    let summary_text = serde_json::to_string(
        manifest.config_inputs[0]
            .redacted_summary
            .as_ref()
            .expect("config summary"),
    )?;
    assert!(summary_text.contains("ANYWK_SAFE_ENV_NAME"));
    assert!(!summary_text.contains("inline-secret-token-should-disappear"));
    assert!(!summary_text.contains("Bearer secret"));
    assert!(summary_text.contains("[REDACTED]"));
    assert!(summary_text.contains("redactedHeaderNames"));

    let extra_redacted = sanitize_json_value(serde_json::json!({
        "apiKey": "raw-api-key",
        "apiKeyEnv": "MY_API_KEY_ENV",
        "password": "secret-pw",
        "env": { "SECRET_TOKEN": "raw-val" }
    }));
    let extra_text = extra_redacted.to_string();
    assert!(!extra_text.contains("raw-api-key"));
    assert!(!extra_text.contains("secret-pw"));
    assert!(!extra_text.contains("raw-val"));
    assert!(extra_text.contains("MY_API_KEY_ENV"));
    Ok(())
}

#[tokio::test]
async fn closed_child_read_only_backfill_streams_large_content_beyond_window() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let studio_home = dir.path().join("home");
    let paths = StudioPaths::resolve(Some(studio_home))?;
    std::fs::create_dir_all(paths.data_dir())?;
    let store = StudioStore::open(paths.database()).await?;
    let workspace = dir.path().join("task");
    std::fs::create_dir_all(&workspace)?;

    let child_thread_id = "closed-child-thread";
    let mut delta =
        DirectoryDelta::upsert_project(crate::studio::store::directory::ProjectDirectoryRecord {
            id: "ws-closed".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Closed Project".into(),
            path: workspace.to_string_lossy().into_owned(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        });
    let (thread_delta, _session_record, _agent_record) = DirectoryDelta::register_session(
        child_thread_id.to_string(),
        "ws-closed",
        "closed child",
        pl_protocol::ThreadModeId::simple(),
        pl_protocol::ThreadWorkspaceMode::Local,
        workspace.to_string_lossy().into_owned(),
        crate::config::ROOT_AGENT_ROUTE_KEY,
    );
    delta.session_upserts = thread_delta.session_upserts;
    delta.agent_upserts = thread_delta.agent_upserts;
    store.persist_directory_summaries(&delta).await?;

    // Initialize HistoryStore SQLite first so conversation_database_id() returns its stable ID.
    let history = store.history_for("ws-closed", child_thread_id).await?;
    history
        .commit_effect(
            1,
            EffectCommit {
                current: &test_current(1),
                items: &[],
                completions: &[],
                rolled_back_turns: &Default::default(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
        )
        .await?;
    let db_id = history
        .conversation_database_id()
        .await?
        .context("database_id missing after first commit")?;
    let writer_session = store.chat_session(child_thread_id).await?;
    let huge_text = "B".repeat(320 * 1024);

    let mut drafts = Vec::new();
    let mut items = Vec::new();
    for idx in 1..=40u64 {
        let seq = idx + 1;
        let content = if idx == 40 {
            huge_text.clone()
        } else {
            format!("message-{idx}")
        };
        let mut item = ThreadItem::completed_user_message(
            format!("msg-{idx}"),
            child_thread_id.to_string(),
            String::new(),
            content,
            Vec::new(),
            1_763_000_000 + idx as i64,
        );
        item.ordinal = idx;
        item.revision = 1;
        let draft = crate::studio::runtime::chat_item::completion_draft(&item, seq, &db_id)?;
        drafts.push(draft);
        items.push(item);
    }
    let completions: Vec<_> = writer_session
        .publish_batch(drafts)
        .await?
        .iter()
        .cloned()
        .collect();
    history
        .commit_effect(
            41,
            EffectCommit {
                current: &test_current(41),
                items: &items,
                completions: &completions,
                rolled_back_turns: &Default::default(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
        )
        .await?;
    writer_session.confirm_durable(40)?;
    let expired_weak = writer_session.downgrade();
    drop(writer_session);
    drop(history);
    store.close().await?;

    // Reopen a cold Store + read-only Session on disk (simulating a retired/closed child) and
    // verify all 40 completions (beyond ChatWindow / hot cache) + >300 KiB chunked blob export.
    let store_ro = StudioStore::open(paths.database()).await?;
    let out_dir = dir.path().join("backfill-out");
    std::fs::create_dir_all(out_dir.join("contents"))?;
    let (readonly_session, ro_db_id) =
        resolve_readonly_session(&expired_weak, &store_ro, child_thread_id).await?;
    assert_eq!(ro_db_id.as_deref(), Some(db_id.as_str()));
    let mut sink = FsContentBlobSink::new(out_dir.clone());
    let (through_seq, records) = export_completions_range(
        &readonly_session,
        ro_db_id.as_deref(),
        0,
        Some(40),
        &mut sink,
    )
    .await?;
    assert_eq!(through_seq, 40);
    assert_eq!(records.len(), 40);
    let last = records.last().expect("40th item");
    assert_eq!(last.header.append_seq, 40);
    let expected_hash = hex::encode(Sha256::digest(huge_text.as_bytes()));
    let blob_path = out_dir.join(format!("contents/{expected_hash}.bin"));
    let exported_bytes = std::fs::read(&blob_path)?;
    assert_eq!(exported_bytes.len(), huge_text.len());
    assert!(
        last.contents
            .iter()
            .any(|c| c.sha256 == expected_hash && c.byte_length == huge_text.len() as u64)
            || last.payload.byte_length > 300 * 1024
    );

    store_ro.close().await?;
    Ok(())
}

#[test]
fn golden_fixtures_roundtrip_and_sha256_integrity() -> Result<()> {
    let fixture_root =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/run-export/v1");
    let run_bytes = std::fs::read(fixture_root.join("run.json"))?;
    let manifest: RunManifestV1 = serde_json::from_slice(&run_bytes)?;
    assert_eq!(manifest.schema_version, 1);
    let expected_manifest_sha = hex::encode(Sha256::digest(&run_bytes));

    let events_bytes = std::fs::read(fixture_root.join("events.jsonl"))?;
    let expected_events_sha = hex::encode(Sha256::digest(&events_bytes));
    let events_text = String::from_utf8(events_bytes)?;
    let events: Vec<EventV1> = events_text
        .lines()
        .map(serde_json::from_str)
        .collect::<Result<Vec<_>, _>>()?;
    assert!(!events.is_empty());
    for (idx, event) in events.iter().enumerate() {
        assert_eq!(event.event_seq, idx as u64 + 1);
    }

    match &events[0].body {
        super::types::EventBodyV1::RunStarted {
            manifest_sha256, ..
        } => assert_eq!(manifest_sha256, &expected_manifest_sha),
        other => anyhow::bail!("expected runStarted first, got {other:?}"),
    }

    // Verify all referenced payload + content blobs exist with matching SHA-256 and byte length.
    for event in &events {
        if let super::types::EventBodyV1::Completion {
            payload, contents, ..
        } = &event.body
        {
            let p_bytes = std::fs::read(fixture_root.join(&payload.path))?;
            assert_eq!(p_bytes.len() as u64, payload.byte_length);
            assert_eq!(hex::encode(Sha256::digest(&p_bytes)), payload.sha256);
            for content in contents {
                let c_bytes = std::fs::read(fixture_root.join(&content.path))?;
                assert_eq!(c_bytes.len() as u64, content.byte_length);
                assert_eq!(hex::encode(Sha256::digest(&c_bytes)), content.sha256);
            }
        }
    }

    let result: super::types::ResultV1 =
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
