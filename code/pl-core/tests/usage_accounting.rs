use pl_core::model::ModelUsage;
use pl_core::thread::{ThreadCheckpoint, UsageSummary};
use pl_core::usage::{
    RECENT_USAGE_GAP_LIMIT, USAGE_PURPOSE_LIMIT, UsageField, UsageIssue, UsageIssueReason,
    UsageOutcome, UsageSource, UsageStatus, UsageThroughputSample, analyze_usage,
};

fn source(sequence: u64) -> UsageSource {
    UsageSource {
        thread_id: "thread".into(),
        call_id: format!("call-{sequence}"),
        turn_id: Some("turn".into()),
        effect_sequence: sequence,
        observed_at: 100,
        purpose: Some("primary".into()),
        outcome: UsageOutcome::Succeeded,
    }
}

fn complete() -> ModelUsage {
    ModelUsage {
        input_tokens: Some(4),
        output_tokens: Some(2),
        cache_read_tokens: Some(2),
        cache_write_tokens: Some(2),
        reasoning_tokens: Some(2),
        total_tokens: Some(6),
    }
}

#[test]
fn legacy_accounting_is_converted_only_at_the_explicit_boundary() {
    let checkpoint = ThreadCheckpoint::capture("thread".into(), 0, Default::default());
    for schema in 1..=5 {
        let mut root = serde_json::to_value(&checkpoint).unwrap();
        root["schemaVersion"] = serde_json::json!(schema);
        root["state"]["usageSummary"] = serde_json::json!({
            "inferenceCount": 7, "totalTokens": 500,
            "hasIncompleteUsage": true, "cacheIncomplete": true,
            "turnId": "old-turn", "turnCompletionTokens": 9
        });
        let envelope = serde_json::to_string(&root).unwrap();
        // The normal schema-6 reader cannot silently default away the saved flat counters.
        assert!(serde_json::from_str::<ThreadCheckpoint>(&envelope).is_err());
        let upgraded = ThreadCheckpoint::decode_legacy(&envelope).unwrap();
        assert_eq!(upgraded.schema_version, 6);
        assert_eq!(upgraded.state.usage_summary.totals.total_tokens, 500);
        assert_eq!(upgraded.state.usage_summary.totals.inference_count, 7);
        assert!(upgraded.state.usage_summary.diagnostics.legacy_unknown);
        assert!(upgraded.state.usage_summary.diagnostics.legacy_incomplete);
        assert!(upgraded.state.usage_summary.cache.incomplete);
        assert_eq!(upgraded.state.usage_summary.throughput, Default::default());
        assert!(upgraded.state.usage_summary.context.latest_call.is_none());
        assert_eq!(upgraded.state.usage_summary.diagnostics.incomplete_calls, 0);
        for malformed in [
            serde_json::json!({"totalTokens": "not-a-counter"}),
            serde_json::json!({"totals": {"totalTokens": 500}}),
            serde_json::json!([]),
        ] {
            root["state"]["usageSummary"] = malformed;
            assert!(
                ThreadCheckpoint::decode_legacy(&serde_json::to_string(&root).unwrap()).is_err(),
                "schema {schema}: {}",
                root["state"]["usageSummary"]
            );
        }
        root["state"] = serde_json::json!(123);
        assert!(ThreadCheckpoint::decode_legacy(&serde_json::to_string(&root).unwrap()).is_err());
    }
}

#[test]
fn analysis_preserves_raw_total_zero_and_independent_cache_evidence() {
    let total_only = ModelUsage {
        total_tokens: Some(80),
        ..Default::default()
    };
    let analysis = analyze_usage(&total_only);
    assert_eq!(analysis.status, UsageStatus::Partial);
    assert_eq!(analysis.total_tokens, Some(80));
    assert_eq!(analysis.context_tokens, Some(80));
    assert_eq!(total_only.input_tokens, None);

    let contradictory = ModelUsage {
        total_tokens: Some(99),
        ..complete()
    };
    let analysis = analyze_usage(&contradictory);
    assert_eq!(analysis.status, UsageStatus::Invalid);
    assert_eq!(analysis.total_tokens, Some(99));
    assert_eq!(analysis.context_tokens, None);
    assert!(analysis.issues.contains(&UsageIssue {
        field: UsageField::Total,
        reason: UsageIssueReason::Inconsistent,
    }));
    assert_eq!(contradictory.total_tokens, Some(99));

    let zero = ModelUsage {
        input_tokens: Some(0),
        output_tokens: Some(0),
        cache_read_tokens: Some(0),
        ..Default::default()
    };
    assert!(analyze_usage(&zero).is_complete());
    assert_eq!(analyze_usage(&zero).context_tokens, Some(0));
    assert_eq!(
        analyze_usage(&ModelUsage::default()).status,
        UsageStatus::Missing
    );

    for output in [None, Some(0)] {
        let usage = ModelUsage {
            output_tokens: output,
            total_tokens: Some(99),
            ..complete()
        };
        assert_eq!(analyze_usage(&usage).cache_sample, Some((4, 2)));
    }
}

#[test]
fn each_total_overflow_preserves_the_old_value_and_identifies_the_counter() {
    type Counter = fn(&mut UsageSummary) -> &mut u64;
    let counters: [(UsageField, Counter); 7] = [
        (UsageField::InferenceCount, |s| {
            &mut s.totals.inference_count
        }),
        (UsageField::Input, |s| &mut s.totals.prompt_tokens),
        (UsageField::Output, |s| &mut s.totals.completion_tokens),
        (UsageField::CacheRead, |s| {
            &mut s.totals.cached_prompt_tokens
        }),
        (UsageField::CacheWrite, |s| &mut s.totals.cache_write_tokens),
        (UsageField::Reasoning, |s| &mut s.totals.reasoning_tokens),
        (UsageField::Total, |s| &mut s.totals.total_tokens),
    ];
    for (field, counter) in counters {
        let mut summary = UsageSummary::default();
        let old = if field == UsageField::InferenceCount {
            u64::MAX
        } else {
            u64::MAX - 1
        };
        *counter(&mut summary) = old;
        summary.add_usage(&complete(), source(1), true, None);
        assert_eq!(*counter(&mut summary), old, "{field:?}");
        assert_eq!(summary.diagnostics.overflow_calls, 1);
        assert_eq!(summary.diagnostics.incomplete_calls, 1);
        assert!(
            summary
                .context
                .latest_call
                .as_ref()
                .unwrap()
                .issues
                .contains(&UsageIssue {
                    field,
                    reason: UsageIssueReason::Overflow,
                }),
            "{field:?}"
        );
        assert_eq!(
            summary
                .diagnostics
                .by_issue
                .iter()
                .filter(|row| row.issue.reason == UsageIssueReason::Overflow)
                .count(),
            1
        );
    }
}

#[test]
fn cache_and_throughput_samples_commit_as_atomic_pairs() {
    for field in 0..3 {
        let mut summary = UsageSummary::default();
        summary.cache.input_tokens = 10;
        summary.cache.read_tokens = 3;
        summary.cache.sample_count = 1;
        match field {
            0 => summary.cache.input_tokens = u64::MAX - 1,
            1 => summary.cache.read_tokens = u64::MAX - 1,
            _ => summary.cache.sample_count = u64::MAX,
        }
        let old = summary.cache.clone();
        summary.add_usage(&complete(), source(1), true, None);
        assert_eq!(summary.cache.input_tokens, old.input_tokens);
        assert_eq!(summary.cache.read_tokens, old.read_tokens);
        assert_eq!(summary.cache.sample_count, old.sample_count);
        assert!(summary.cache.incomplete);
        assert!(
            summary
                .context
                .latest_call
                .as_ref()
                .unwrap()
                .issues
                .contains(&UsageIssue {
                    field: UsageField::CachePair,
                    reason: UsageIssueReason::Overflow,
                })
        );
    }
    for field in 0..2 {
        let mut summary = UsageSummary::default();
        summary.throughput.turn_id = "turn".into();
        summary.throughput.completion_tokens = if field == 0 { u64::MAX - 1 } else { 2 };
        summary.throughput.response_millis = if field == 1 { u64::MAX - 1 } else { 3 };
        let old = summary.throughput.clone();
        summary.add_usage(
            &complete(),
            source(1),
            true,
            Some(UsageThroughputSample {
                output_tokens: 2,
                response_millis: 3,
            }),
        );
        assert_eq!(summary.throughput, old);
        assert!(
            summary
                .context
                .latest_call
                .as_ref()
                .unwrap()
                .issues
                .contains(&UsageIssue {
                    field: UsageField::ThroughputPair,
                    reason: UsageIssueReason::Overflow,
                })
        );
    }
    let mut summary = UsageSummary::default();
    summary.add_usage(
        &complete(),
        source(1),
        true,
        Some(UsageThroughputSample {
            output_tokens: 2,
            response_millis: 3,
        }),
    );
    summary.add_usage(
        &complete(),
        source(2),
        true,
        Some(UsageThroughputSample {
            output_tokens: 2,
            response_millis: 3,
        }),
    );
    assert_eq!(summary.cache.sample_count, 2);
    assert_eq!(
        (summary.cache.input_tokens, summary.cache.read_tokens),
        (8, 4)
    );
    assert_eq!(
        (
            summary.throughput.completion_tokens,
            summary.throughput.response_millis
        ),
        (4, 6)
    );
    let previous = summary.throughput.clone();
    let mut next = source(3);
    next.turn_id = Some("untimed-turn".into());
    summary.add_usage(&complete(), next, true, None);
    assert_eq!(summary.throughput, previous);
}

#[test]
fn missing_cancel_retains_context_and_cumulative_gap_after_recovery() {
    let mut summary = UsageSummary::default();
    summary.add_usage(&complete(), source(1), true, None);
    let mut cancelled = source(2);
    cancelled.outcome = UsageOutcome::Cancelled;
    summary.add_usage(&ModelUsage::default(), cancelled.clone(), true, None);
    assert_eq!(summary.context.tokens, 6);
    assert_eq!(
        summary.context.latest_call.as_ref().unwrap().source,
        cancelled
    );
    assert_eq!(
        summary.context.latest_call.as_ref().unwrap().status,
        UsageStatus::Missing
    );
    summary.add_usage(&complete(), source(3), true, None);
    assert_eq!(
        summary.context.latest_call.as_ref().unwrap().source,
        source(3)
    );
    assert_eq!(
        summary.context.latest_call.as_ref().unwrap().status,
        UsageStatus::Reported
    );
    assert_eq!(summary.totals.total_tokens, 12);
    assert_eq!(summary.totals.inference_count, 3);
    assert_eq!(summary.diagnostics.incomplete_calls, 1);
    assert_eq!(summary.diagnostics.missing_calls, 1);
    assert_eq!(summary.diagnostics.recent_gaps.len(), 1);
    assert!(summary.has_incomplete_usage());
    assert_eq!(
        summary
            .diagnostics
            .by_outcome
            .iter()
            .find(|row| row.outcome == UsageOutcome::Cancelled)
            .unwrap()
            .incomplete_calls,
        1
    );
}

#[test]
fn diagnostic_dimensions_and_recent_gap_tail_are_bounded() {
    let mut summary = UsageSummary::default();
    let calls = USAGE_PURPOSE_LIMIT + 12;
    for i in 0..calls {
        let mut invocation = source(i as u64);
        invocation.purpose = Some(format!("purpose-{i}"));
        summary.add_usage(&ModelUsage::default(), invocation, true, None);
    }
    assert_eq!(summary.diagnostics.by_purpose.len(), USAGE_PURPOSE_LIMIT);
    assert_eq!(summary.diagnostics.other_purpose_calls, 12);
    assert_eq!(
        summary.diagnostics.recent_gaps.len(),
        RECENT_USAGE_GAP_LIMIT
    );
    assert_eq!(
        summary
            .diagnostics
            .recent_gaps
            .first()
            .unwrap()
            .source
            .effect_sequence,
        (calls - RECENT_USAGE_GAP_LIMIT) as u64
    );
    assert_eq!(
        summary
            .diagnostics
            .recent_gaps
            .last()
            .unwrap()
            .source
            .effect_sequence,
        (calls - 1) as u64
    );
    assert_eq!(summary.diagnostics.by_issue.len(), 3);
    // A known purpose still updates its existing bucket after the category bound is reached.
    let mut invocation = source(calls as u64);
    invocation.purpose = Some("purpose-0".into());
    summary.add_usage(&complete(), invocation, true, None);
    assert_eq!(summary.diagnostics.by_purpose[0].calls, 2);
    assert_eq!(summary.diagnostics.by_purpose[0].incomplete_calls, 1);
    assert_eq!(summary.diagnostics.other_purpose_calls, 12);
}

#[test]
fn diagnostic_counter_overflow_is_visible_without_wrapping() {
    let mut summary = UsageSummary::default();
    summary.add_usage(&ModelUsage::default(), source(1), true, None);
    summary.diagnostics.incomplete_calls = u64::MAX;
    summary.diagnostics.missing_calls = u64::MAX;
    summary.diagnostics.by_outcome[0].calls = u64::MAX;
    summary.diagnostics.by_outcome[0].incomplete_calls = u64::MAX;
    summary.diagnostics.by_purpose[0].calls = u64::MAX;
    summary.diagnostics.by_purpose[0].incomplete_calls = u64::MAX;
    summary.diagnostics.by_issue[0].calls = u64::MAX;
    summary.add_usage(&ModelUsage::default(), source(2), true, None);
    assert!(summary.diagnostics.counts_overflowed);
    assert_eq!(summary.diagnostics.incomplete_calls, u64::MAX);
    assert_eq!(summary.diagnostics.missing_calls, u64::MAX);
    assert_eq!(summary.diagnostics.by_outcome[0].calls, u64::MAX);
    assert_eq!(summary.diagnostics.by_outcome[0].incomplete_calls, u64::MAX);
    assert_eq!(summary.diagnostics.by_purpose[0].calls, u64::MAX);
    assert_eq!(summary.diagnostics.by_purpose[0].incomplete_calls, u64::MAX);
    assert_eq!(summary.diagnostics.by_issue[0].calls, u64::MAX);
    assert_eq!(summary.totals.inference_count, 2);

    let mut summary = UsageSummary::default();
    summary.diagnostics.partial_calls = u64::MAX;
    summary.diagnostics.invalid_calls = u64::MAX;
    summary.diagnostics.overflow_calls = u64::MAX;
    summary.diagnostics.other_purpose_calls = u64::MAX;
    summary.diagnostics.by_purpose = (0..USAGE_PURPOSE_LIMIT)
        .map(|i| pl_core::usage::UsagePurposeCount {
            purpose: Some(format!("category-{i}")),
            calls: 0,
            incomplete_calls: 0,
        })
        .collect();
    summary.add_usage(
        &ModelUsage {
            total_tokens: Some(1),
            ..Default::default()
        },
        source(1),
        true,
        None,
    );
    summary.add_usage(
        &ModelUsage {
            input_tokens: Some(u64::MAX),
            output_tokens: Some(1),
            ..Default::default()
        },
        source(2),
        true,
        None,
    );
    assert!(summary.diagnostics.counts_overflowed);
    assert_eq!(summary.diagnostics.partial_calls, u64::MAX);
    assert_eq!(summary.diagnostics.invalid_calls, u64::MAX);
    assert_eq!(summary.diagnostics.overflow_calls, u64::MAX);
    assert_eq!(summary.diagnostics.other_purpose_calls, u64::MAX);
    assert_eq!(summary.diagnostics.by_purpose.len(), USAGE_PURPOSE_LIMIT);
    assert_eq!(summary.totals.inference_count, 2);
}
