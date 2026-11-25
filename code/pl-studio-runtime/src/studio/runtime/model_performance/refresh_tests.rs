use super::*;
use crate::studio::storage::calls::{PurposeUsageProjection, SessionUsageProjection};
use crate::studio::storage::write_behind::ThreadWriteBehindWriter;
use std::time::Duration;

#[tokio::test]
async fn committed_model_settlement_reaches_the_periodic_session_costs() -> anyhow::Result<()> {
    use crate::studio::storage::thread_writer::{ThreadStorageSink, storage_fault_tests};
    use anyhow::Context as _;
    use pl_core::{
        context::ContextContent,
        model::ModelFactory,
        thread::{StepInput, ThreadHandle, history_sink::HistorySinkHandle},
    };
    use pl_model::{
        model::{ModelDefinition, ModelPricing, ModelTransportProfile, TokenPriceTier},
        runtime::{InferenceClock, ThreadModel},
    };
    use pl_provider_fixture::{
        FixtureServer, Protocol, Reply, Step, WebSocketAction, responses_text,
    };
    use serde_json::json;
    use tokio_util::sync::CancellationToken;

    #[derive(Debug)]
    struct FixedClock;
    impl InferenceClock for FixedClock {
        fn unix_seconds(&self) -> pl_protocol::Result<i64> {
            Ok(1_780_000_000)
        }
    }

    let temp = tempfile::tempdir()?;
    let path = temp.path().join("data/studio.sqlite");
    let store = StudioStore::open(&path).await?;
    let id = "priced-session";
    let mut thread = crate::Thread::placeholder(id);
    thread.workspace_id = "project-test".into();
    thread.agent_path = id.into();
    thread.root_thread_id = id.into();
    storage_fault_tests::register_test_thread(&store, &thread).await?;
    let mut events = responses_text("model answer", "priced-response", "priced-model");
    events.last_mut().unwrap()["response"]["usage"] = json!({
        "input_tokens": 11, "output_tokens": 7, "total_tokens": 18,
        "input_tokens_details": {"cached_tokens": 0},
    });
    let retry_reached = CancellationToken::new();
    let release_retry = CancellationToken::new();
    let mut retry = vec![WebSocketAction::Barrier {
        reached: retry_reached.clone(),
        release: release_retry.clone(),
    }];
    retry.extend(events.into_iter().map(WebSocketAction::Event));
    let provider = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesWebSocket,
            "priced input",
            0,
            Reply::WebSocketScript(vec![
                WebSocketAction::Event(json!({"type": "response.created", "response": {
                    "id": "priced-partial", "model": "priced-model",
                }})),
                WebSocketAction::Event(json!({"type": "response.in_progress", "response": {
                    "id": "priced-partial", "model": "priced-model", "usage": {
                        "input_tokens": 11, "output_tokens": 5, "total_tokens": 16,
                        "input_tokens_details": {"cached_tokens": 0},
                    },
                }})),
                WebSocketAction::Disconnect,
            ]),
        ),
        Step::prompt(
            Protocol::ResponsesWebSocket,
            "priced input",
            1,
            Reply::WebSocketScript(retry),
        ),
    ])
    .await?;
    let mut model = ModelDefinition::compatible("priced-model");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_websocket());
    model.extra.pricing = ModelPricing::published(
        "USD",
        vec![TokenPriceTier::flat(2.0, 8.0, Some(1.0), None)],
        "https://example.test/prices",
    );
    let runtime = pl_model::runtime::new_with_account_id(
        "priced",
        pl_model_openai::endpoint::endpoint(Some(provider.base_url())),
        model,
    )?
    .with_clock(Arc::new(FixedClock));
    let thread_owner = ThreadHandle::start_current(
        id.into(),
        Some(
            ModelFactory::new(ThreadModel::new(runtime, None))
                .open_session()
                .await?,
        ),
    )?;
    let sink = ThreadStorageSink::new(store.clone(), thread.clone()).await?;
    thread_owner
        .attach_history(HistorySinkHandle::new(sink))
        .await?;
    let projector = storage_fault_tests::spawn_live_projection_for_thread(store.clone(), id);
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let owner = ModelPerformanceOwner::new(
        store.clone(),
        ProductEventBus::new(store.clone(), writer.clone()),
        "priced-summary".into(),
    );
    owner.initialize_projection().await;

    let step = tokio::spawn({
        let thread_owner = thread_owner.clone();
        async move {
            thread_owner
                .step(StepInput {
                    turn_id: "priced-turn".into(),
                    attempt_id: uuid::Uuid::new_v4().to_string(),
                    cancellation: Default::default(),
                    content: vec![ContextContent::Text {
                        text: "priced input".into(),
                    }],
                })
                .await
        }
    });
    tokio::time::timeout(Duration::from_secs(5), retry_reached.cancelled())
        .await
        .with_context(|| format!("waiting for the model retry: {:?}", provider.recorded()))?;
    let history_store = store.history(id).await?;
    let history = history_store.reader();
    let (first_cut, first_position) = history.capture_committed_position().await?;
    let partial = history.accounting(Some(first_cut)).await?.unwrap();
    assert_eq!(partial.inference_count, 1);
    assert!(partial.has_incomplete_usage);
    assert!(!partial.has_unpriced_usage);
    let cost = tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if let Some(cost) = owner.session_costs_snapshot(id).await.cost {
                break cost;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("a committed History settlement must reach product costs on the next refresh");
    assert!(cost.has_incomplete_usage);
    assert!(!cost.has_unpriced_usage);
    assert_eq!(cost.estimated_costs[0].currency, "USD");
    assert!((cost.estimated_costs[0].amount - 0.000_062).abs() < 1e-12);

    owner.request_close();
    release_retry.cancel();
    tokio::time::timeout(Duration::from_secs(5), step).await???;
    let (final_cut, final_position) = history.capture_committed_position().await?;
    let complete = history.accounting(Some(final_cut)).await?.unwrap();
    assert!(final_position > first_position);
    assert_eq!(complete.updated_at, partial.updated_at);
    assert_eq!(complete.inference_count, 2);
    assert_eq!(complete.total_tokens, 34);
    history.close().await;
    assert_eq!(provider.finish().await?.len(), 2);
    thread_owner.close().await?;
    let channel = store.thread_persistence().history_channel(id);
    channel
        .await_handoff_durable(id, thread_owner.snapshot().commit_sequence)
        .await?;
    channel.stop_and_join().await?;
    projector.await?;
    history_store.close().await?;
    store.calls().stop_best_effort();
    owner.close().await?;
    let final_state = owner.session_costs_snapshot(id).await;
    assert!(!final_state.statistics_gap);
    assert!(!final_state.statistics_pending);
    assert!(!final_state.read_failed);
    let final_cost = final_state
        .cost
        .context("final cost after the original writer drains")?;
    assert!(final_cost.has_incomplete_usage);
    assert!(!final_cost.has_unpriced_usage);
    assert!((final_cost.estimated_costs[0].amount - 0.000_140).abs() < 1e-12);
    writer.shutdown().await?;
    store.close().await?;

    let reopened = StudioStore::open(&path).await?;
    let reopened_history = reopened.history(id).await?;
    let _sink = ThreadStorageSink::new(reopened.clone(), thread).await?;
    let calls = reopened.calls();
    let ticket = calls.admitted_ticket();
    let mut processed = calls.subscribe_processed_ticket();
    tokio::time::timeout(
        Duration::from_secs(5),
        processed.wait_for(|done| *done >= ticket),
    )
    .await??;
    let channel = reopened.thread_persistence().history_channel(id);
    channel.stop_and_join().await?;
    reopened_history.close().await?;
    let writer = ThreadWriteBehindWriter::new(reopened.clone());
    let owner = ModelPerformanceOwner::new(
        reopened.clone(),
        ProductEventBus::new(reopened.clone(), writer.clone()),
        "reopened-summary".into(),
    );
    owner.initialize_projection().await;
    let state = owner.session_costs_snapshot(id).await;
    assert_eq!(state.cost, Some(final_cost));
    assert!(!state.statistics_gap);
    owner.close().await?;
    writer.shutdown().await?;
    reopened.close().await?;
    Ok(())
}

#[tokio::test]
async fn changes_wait_for_the_next_period_and_idle_periods_do_not_publish() -> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let events = ProductEventBus::new(store.clone(), writer.clone());
    let mut receiver = events.subscribe_topic(&crate::StudioProductTopic::ModelPerformance);
    let owner = ModelPerformanceOwner::new(store.clone(), events, "periodic-refresh".into());
    // Establish the initial material before starting the observer or virtual clock.
    owner.publish_locked_projection(true, true).await;
    receiver.try_recv()?;
    assert!(!owner.snapshot().await.statistics_gap);

    tokio::time::pause();
    owner.emit_snapshot_after_flush();
    store.calls().mark_statistics_gap();
    // A status-only material change needs no asynchronous SQL read. Let the real observer
    // consume its wakeups without advancing the clock: immediate publication is a failure.
    for _ in 0..3 {
        tokio::task::yield_now().await;
    }
    assert!(!owner.snapshot().await.statistics_gap);
    tokio::time::advance(Duration::from_millis(999)).await;
    tokio::task::yield_now().await;
    assert!(!owner.snapshot().await.statistics_gap);
    tokio::time::advance(Duration::from_millis(1)).await;
    let event = receiver.recv().await?;
    let crate::StudioProductEventKind::ModelPerformanceStateChanged(published) = event.kind else {
        panic!("expected model-performance state");
    };
    assert!(published.statistics_gap);
    assert_eq!(owner.snapshot().await.revision, published.revision);

    tokio::time::advance(Duration::from_secs(5)).await;
    tokio::task::yield_now().await;
    assert!(matches!(
        receiver.try_recv(),
        Err(tokio::sync::broadcast::error::TryRecvError::Empty)
    ));
    assert_eq!(owner.snapshot().await.revision, published.revision);
    tokio::time::resume();
    owner.close().await?;
    assert!(
        owner
            .observer
            .as_ref()
            .unwrap()
            .task
            .lock()
            .unwrap()
            .is_none()
    );
    writer.shutdown().await?;
    store.close().await?;
    Ok(())
}

fn own_usage(thread: &str, revision: u64, usd: f64) -> SessionUsageProjection {
    SessionUsageProjection {
        root_thread_id: "root".into(),
        thread_id: thread.into(),
        revision,
        has_unpriced_usage: false,
        has_incomplete_usage: false,
        purpose_costs: vec![PurposeUsageProjection {
            purpose: Some("turn".into()),
            estimated_costs: vec![crate::RuntimeCostAmount {
                currency: "USD".into(),
                amount: usd,
            }],
        }],
    }
}

#[tokio::test]
async fn close_publishes_each_threads_latest_saved_summary_after_observer_cancellation()
-> anyhow::Result<()> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let events = ProductEventBus::new(store.clone(), writer.clone());
    let owner = ModelPerformanceOwner::new(store.clone(), events, "final-refresh".into());
    owner.initialize_projection().await;
    assert!(owner.session_costs_snapshot("root").await.cost.is_none());
    // Studio broadcasts observer cancellation before Thread writers finish. Final close must
    // still adopt summaries committed during that drain, without waiting for another tick.
    owner.request_close();
    tokio::task::yield_now().await;
    let calls = store.calls();
    let mut progress = calls.subscribe_materials();
    for summary in [
        own_usage("root", 1, 10.0),
        own_usage("child", 1, 20.0),
        own_usage("grandchild", 1, 30.0),
        own_usage("child", 2, 25.0),
        own_usage("child", 2, 25.0),
        own_usage("child", 1, 20.0),
    ] {
        calls.replace_session_usage(summary)?;
    }
    let mut auxiliary = own_usage("auxiliary", 1, 0.0);
    auxiliary.has_unpriced_usage = true;
    auxiliary.purpose_costs = vec![PurposeUsageProjection {
        purpose: Some("compaction".into()),
        estimated_costs: vec![crate::RuntimeCostAmount {
            currency: "EUR".into(),
            amount: 3.0,
        }],
    }];
    calls.replace_session_usage(auxiliary)?;
    let mut incomplete = own_usage("unreported", 1, 0.0);
    incomplete.purpose_costs.clear();
    incomplete.has_incomplete_usage = true;
    calls.replace_session_usage(incomplete)?;
    let mut other_root = own_usage("other-root", 1, 99.0);
    other_root.root_thread_id = "other-root".into();
    calls.replace_session_usage(other_root)?;
    let ticket = calls.admitted_ticket();
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if progress.borrow_and_update().processed_ticket >= ticket {
                return Ok::<_, anyhow::Error>(());
            }
            progress.changed().await?;
        }
    })
    .await??;
    assert!(progress.borrow().last_error.is_none());
    assert!(!progress.borrow().statistics_gap);

    owner.close().await?;
    let snapshot = owner.session_costs_snapshot("root").await;
    assert!(!snapshot.statistics_pending);
    assert!(!snapshot.read_failed);
    let cost = snapshot
        .cost
        .expect("final saved summaries must be visible");
    assert_eq!(
        cost.estimated_costs
            .iter()
            .map(|cost| (cost.currency.as_str(), cost.amount))
            .collect::<Vec<_>>(),
        [("EUR", 3.0), ("USD", 65.0)]
    );
    assert!(cost.has_unpriced_usage);
    let json = serde_json::to_value(&cost)?;
    assert_eq!(json["hasIncompleteUsage"], true);
    assert!(json["purposeCosts"][0].get("hasIncompleteUsage").is_none());
    assert_eq!(cost.purpose_costs.len(), 2);
    let other_cost = owner
        .session_costs_snapshot("other-root")
        .await
        .cost
        .unwrap();
    assert_eq!(other_cost.estimated_costs[0].amount, 99.0);
    assert_eq!(
        serde_json::to_value(other_cost)?["hasIncompleteUsage"],
        false
    );
    writer.shutdown().await?;
    store.close().await?;
    Ok(())
}
