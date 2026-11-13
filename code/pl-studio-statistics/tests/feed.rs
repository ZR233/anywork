use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Waker};

use pl_studio_statistics::{
    StatisticsError, StatisticsPublisher, StudioModelPerformanceEffortSummary,
    StudioModelPerformanceSample, StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
};

fn snapshot() -> StudioModelPerformanceSnapshot {
    let effort = StudioModelPerformanceEffortSummary {
        effort: Some("high".into()),
        sample_count: 1,
        completion_tokens: 20,
        total_ttft_millis: 10,
        ttft_sample_count: 1,
        total_response_millis: 100,
        tokens_per_second: 200.0,
        average_ttft_millis: Some(10.0),
        average_response_millis: 100.0,
    };
    let summary = StudioModelPerformanceSummary {
        account_id: "account".into(),
        account_display_name: "Account".into(),
        model_id: "model".into(),
        sample_count: 1,
        completion_tokens: 20,
        total_ttft_millis: 10,
        ttft_sample_count: 1,
        total_response_millis: 100,
        tokens_per_second: 200.0,
        average_ttft_millis: Some(10.0),
        average_response_millis: 100.0,
        effort_breakdowns: vec![effort; 2],
    };
    let sample = StudioModelPerformanceSample {
        thread_id: "thread".into(),
        call_id: "call".into(),
        purpose: None,
        first_output_source: pl_protocol::FirstOutputSource::Incremental,
        usage_status: pl_protocol::UsageReportStatus::Reported,
        ttft_availability: pl_protocol::MetricAvailability::Available,
        throughput_availability: pl_protocol::MetricAvailability::Available,
        completed_at: 1,
        account_id: "account".into(),
        account_display_name: "Account".into(),
        model_id: Some("model".into()),
        sent_model: None,
        reported_model: None,
        model_match_state: Default::default(),
        effort: Some("high".into()),
        completion_tokens: Some(20),
        ttft_millis: Some(10),
        decode_millis: Some(90),
        total_response_millis: Some(100),
        tokens_per_second: Some(200.0),
    };
    StudioModelPerformanceSnapshot {
        summaries: Arc::new(vec![summary; 2]),
        history: Arc::new(vec![sample; 2]),
        ..Default::default()
    }
}

fn assert_pending(future: Pin<&mut impl Future>) {
    assert!(
        future
            .poll(&mut Context::from_waker(Waker::noop()))
            .is_pending()
    );
}

#[tokio::test]
async fn all_material_pages_preserve_identity_bounds_and_frozen_values_after_ack() {
    let mut source = snapshot();
    let publisher = StatisticsPublisher::new("owner".into(), &source);
    let feed = publisher.subscribe();
    let header = feed.next().await.unwrap().unwrap();
    assert_eq!((header.summary_count, header.history_count), (2, 2));
    let scope = feed
        .open_scope(
            &header.owner_epoch,
            &header.feed_id,
            header.delivery_sequence,
        )
        .unwrap();
    feed.acknowledge(header.delivery_sequence).unwrap();
    assert!(matches!(
        feed.open_scope(
            &header.owner_epoch,
            &header.feed_id,
            header.delivery_sequence
        ),
        Err(StatisticsError::InvalidReference)
    ));
    source.revision += 1;
    source.summaries = Arc::new(Vec::new());
    publisher.publish(&source);

    let summaries = scope.read_summaries(0, 1).unwrap();
    let history = scope.read_history(0, 1).unwrap();
    let efforts = scope.read_efforts(0, 0, 1).unwrap();
    assert_eq!(summaries.items[0].model_id, "model");
    assert_eq!(summaries.items[0].effort_count, 2);
    assert_eq!(history.items, source.history[..1]);
    assert_eq!(efforts.items[0].effort.as_deref(), Some("high"));
    for (total, next, scope_id, publication, bytes, actual_bytes) in [
        (
            summaries.total_count,
            summaries.next_offset,
            summaries.scope_id,
            summaries.publication_revision,
            summaries.source_bytes,
            serde_json::to_vec(&summaries.items).unwrap().len(),
        ),
        (
            history.total_count,
            history.next_offset,
            history.scope_id,
            history.publication_revision,
            history.source_bytes,
            serde_json::to_vec(&history.items).unwrap().len(),
        ),
        (
            efforts.total_count,
            efforts.next_offset,
            efforts.scope_id,
            efforts.publication_revision,
            efforts.source_bytes,
            serde_json::to_vec(&efforts.items).unwrap().len(),
        ),
    ] {
        assert_eq!((total, next), (2, Some(1)));
        assert_eq!(scope_id, scope.scope_id());
        assert_eq!(publication, header.publication_revision);
        assert_eq!(bytes as usize, actual_bytes);
    }
    for limit in [0, 129] {
        assert_eq!(
            scope.read_summaries(0, limit).unwrap_err(),
            StatisticsError::InvalidPageLimit
        );
        assert_eq!(
            scope.read_history(0, limit).unwrap_err(),
            StatisticsError::InvalidPageLimit
        );
        assert_eq!(
            scope.read_efforts(0, 0, limit).unwrap_err(),
            StatisticsError::InvalidPageLimit
        );
    }
    for offset in [3, u64::MAX] {
        assert_eq!(
            scope.read_summaries(offset, 1).unwrap_err(),
            StatisticsError::InvalidReference
        );
        assert_eq!(
            scope.read_history(offset, 1).unwrap_err(),
            StatisticsError::InvalidReference
        );
        assert_eq!(
            scope.read_efforts(0, offset, 1).unwrap_err(),
            StatisticsError::InvalidReference
        );
    }
    assert!(scope.read_summaries(2, 1).unwrap().items.is_empty());
    assert!(scope.read_history(2, 1).unwrap().next_offset.is_none());
    assert!(scope.read_efforts(0, 2, 1).unwrap().items.is_empty());
    scope.close().await.unwrap();
    assert_eq!(
        scope.read_history(0, 1).unwrap_err(),
        StatisticsError::Closed
    );
    feed.close().await.unwrap();
}

#[tokio::test]
async fn ack_backpressure_coalesces_publications_and_cancelled_next_releases_admission() {
    let mut source = snapshot();
    let publisher = StatisticsPublisher::new("owner".into(), &source);
    let feed = publisher.subscribe();
    let first = feed.next().await.unwrap().unwrap();
    // A status change advances publication identity while retaining both materials.
    source.revision += 1;
    source.statistics_pending = true;
    publisher.publish(&source);
    let second = feed.next().await.unwrap().unwrap();
    assert_eq!(first.summaries_revision, second.summaries_revision);
    assert_eq!(first.history_revision, second.history_revision);
    source.revision += 1;
    publisher.publish(&source);
    let mut pending = Box::pin(feed.next());
    assert_pending(pending.as_mut());
    assert_eq!(
        feed.next().await.unwrap_err(),
        StatisticsError::NextInFlight
    );
    drop(pending);
    source.revision += 1;
    source.history = Arc::new(Vec::new());
    publisher.publish(&source);
    assert_eq!(
        feed.acknowledge(second.delivery_sequence).unwrap_err(),
        StatisticsError::InvalidReference
    );
    feed.acknowledge(first.delivery_sequence).unwrap();
    feed.acknowledge(first.delivery_sequence).unwrap();
    let newest = feed.next().await.unwrap().unwrap();
    assert_eq!(newest.publication_revision, source.revision);
    assert_eq!(newest.summaries_revision, first.summaries_revision);
    assert!(newest.history_revision > first.history_revision);
    let mut pending = Box::pin(feed.next());
    assert_pending(pending.as_mut());
    feed.request_close();
    assert!(pending.await.unwrap().is_none());
    feed.close().await.unwrap();
}

#[tokio::test]
async fn scope_capacity_and_foreign_identities_are_enforced_and_close_releases_capacity() {
    let publisher = StatisticsPublisher::new("owner".into(), &snapshot());
    let feed = publisher.subscribe();
    let header = feed.next().await.unwrap().unwrap();
    assert!(matches!(
        feed.open_scope("other", feed.id(), header.delivery_sequence),
        Err(StatisticsError::InvalidReference)
    ));
    assert!(matches!(
        feed.open_scope("owner", "other", header.delivery_sequence),
        Err(StatisticsError::InvalidReference)
    ));
    let first = feed
        .open_scope("owner", feed.id(), header.delivery_sequence)
        .unwrap();
    let second = feed
        .open_scope("owner", feed.id(), header.delivery_sequence)
        .unwrap();
    assert!(matches!(
        feed.open_scope("owner", feed.id(), header.delivery_sequence),
        Err(StatisticsError::ScopeCapacity)
    ));
    first.close().await.unwrap();
    let third = feed
        .open_scope("owner", feed.id(), header.delivery_sequence)
        .unwrap();
    assert_ne!(second.scope_id(), third.scope_id());
    feed.close().await.unwrap();
    assert_eq!(
        third.read_summaries(0, 1).unwrap_err(),
        StatisticsError::Closed
    );
}

#[tokio::test]
async fn oversized_page_refusal_releases_the_scope_for_a_smaller_page() {
    let mut source = snapshot();
    Arc::make_mut(&mut source.summaries)[1].account_display_name = "x".repeat(256 * 1024);
    let publisher = StatisticsPublisher::new("owner".into(), &source);
    let feed = publisher.subscribe();
    let header = feed.next().await.unwrap().unwrap();
    let scope = feed
        .open_scope("owner", feed.id(), header.delivery_sequence)
        .unwrap();
    assert_eq!(
        scope.read_summaries(0, 2).unwrap_err(),
        StatisticsError::PageCapacity
    );
    assert_eq!(scope.read_summaries(0, 1).unwrap().items.len(), 1);
    feed.close().await.unwrap();
}
