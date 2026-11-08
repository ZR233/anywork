//! Exercise the production selector/worker with explicit gates, not arrival timing or load.

use super::storage_fault_tests::{
    live_projection, register_test_thread, test_thread, ticket, visible_input_ticket,
};
use super::*;
use pl_core::{
    chat::{ChatBudget, ChatItemHeader, ChatQuery, ContentDescriptor, PayloadMode, ReadDemand},
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
    thread::journal::ContextChange,
};
use sea_orm::{ConnectionTrait, Database};

pub(super) struct Budget;
impl ChatBudget for Budget {
    fn fixed_bytes(&self) -> usize {
        256
    }
    fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
        256 + header.item_id.len()
            + match mode {
                PayloadMode::Inline => header.byte_length as usize,
                PayloadMode::Deferred => 0,
            }
    }
    fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
        256
    }
}

struct Fixture {
    _temp: tempfile::TempDir,
    store: StudioStore,
    sink: ThreadStorageSink,
    projection: crate::studio::thread_projection::LiveProjection,
}

impl Fixture {
    async fn new(id: &str) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        register_test_thread(&store, &test_thread(id)).await?;
        let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
        let projection = live_projection(&sink).await?;
        Ok(Self {
            _temp: temp,
            store,
            sink,
            projection,
        })
    }

    async fn handoff(&mut self, write: &ThreadWrite) -> Result<Arc<PreparedEffect>> {
        self.sink.admit(&self.sink.0.thread.id, write.clone())?;
        let mut prepared = self
            .projection
            .prepare_committed(&self.sink.0.thread, &write.effect, &write.checkpoint.state)
            .await?;
        self.projection
            .publish_prepared(&self.sink.0.chat, &mut prepared)
            .await?;
        ensure!(
            self.sink.0.channel.prepare(prepared.clone()),
            "handoff refused"
        );
        Ok(prepared)
    }

    fn select(&self, now: Instant) -> batch::Selection {
        batch::select(&mut lock_progress(&self.sink.0), now, 0, false)
    }

    async fn finish(self, sequence: u64) -> Result<()> {
        self.sink.flush(&self.sink.0.thread.id, sequence).await?;
        self.sink.0.channel.stop_and_join().await
    }
}

fn ready(selection: batch::Selection) -> Vec<batch::Effect> {
    match selection {
        batch::Selection::Ready(effects) => effects,
        _ => panic!("expected a frozen prepared prefix"),
    }
}

#[tokio::test]
async fn new_execution_writer_prepares_identity_before_the_first_projection() -> Result<()> {
    let id = "writer-prepares-identity";
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    register_test_thread(&store, &test_thread(id)).await?;
    let history_path = store
        .session_paths("project-test", id)?
        .root()
        .join("history.sqlite");
    assert!(!history_path.try_exists()?);

    let sink = ThreadStorageSink::new(store.clone(), test_thread(id), None).await?;
    let history = store.history(id).await?;
    let database_id = history
        .conversation_database_id()
        .await?
        .context("execution writer must prepare a real history identity before any effect")?;
    assert!(!database_id.is_empty());
    assert!(history_path.try_exists()?);
    assert_eq!(history.watermark().await?, 0);
    assert!(history.checkpoint().await?.is_none());

    let channel = sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let mut projection = live_projection(&sink).await?;
    let write = visible_input_ticket(id, 1, "first-execution-input")?;
    sink.admit(id, write.clone())?;
    let mut prepared = projection
        .prepare_committed(&sink.0.thread, &write.effect, &write.checkpoint.state)
        .await?;
    assert_eq!(prepared.current.projection().source_effect_seq, 1);
    projection
        .publish_prepared(&sink.0.chat, &mut prepared)
        .await?;
    assert!(channel.prepare(prepared));
    drop(gate);
    sink.flush(id, 1).await?;
    assert_eq!(
        history.conversation_database_id().await?.as_deref(),
        Some(database_id.as_str())
    );
    channel.stop_and_join().await?;
    Ok(())
}

#[tokio::test]
async fn continuous_arrival_keeps_the_original_deadline_and_retry_boundary() -> Result<()> {
    let mut fixture = Fixture::new("batch-deadline").await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let now = Instant::now();
    let first = fixture.handoff(&ticket("batch-deadline", 1)).await?;
    // Inject an observation clock, without sleeps or enabling Tokio's optional test-util feature.
    lock_progress(&fixture.sink.0)
        .effects
        .front_mut()
        .unwrap()
        .admitted_at = now;
    assert!(
        matches!(fixture.select(now), batch::Selection::Wait(d) if d == now + Duration::from_millis(20))
    );
    fixture.handoff(&ticket("batch-deadline", 2)).await?;
    assert!(
        matches!(fixture.select(now + Duration::from_millis(19)), batch::Selection::Wait(d) if d == now + Duration::from_millis(20))
    );
    fixture.handoff(&ticket("batch-deadline", 3)).await?;
    let selected = ready(fixture.select(now + Duration::from_millis(20)));
    assert_eq!(
        selected
            .iter()
            .map(|effect| effect.sequence)
            .collect::<Vec<_>>(),
        [1, 2, 3]
    );
    assert!(Arc::ptr_eq(&selected[0].prepared, &first));
    fixture.handoff(&ticket("batch-deadline", 4)).await?;
    let retried = ready(fixture.select(now + Duration::from_secs(1)));
    assert_eq!(
        retried.len(),
        3,
        "later admission must not widen a frozen transaction"
    );
    for (original, retry) in selected.iter().zip(&retried) {
        assert!(Arc::ptr_eq(&original.write, &retry.write));
        assert!(Arc::ptr_eq(&original.prepared, &retry.prepared));
    }
    drop(gate);
    fixture.finish(4).await
}

#[tokio::test]
async fn barriers_pressure_and_prepared_gaps_end_the_window() -> Result<()> {
    for mode in ["flush", "handoff-barrier", "pressure", "queue-full", "gap"] {
        let mut fixture = Fixture::new(&format!("batch-cut-{mode}")).await?;
        let id = fixture.sink.0.thread.id.clone();
        let channel = fixture.sink.0.channel.clone();
        let gate = channel.step_lock.lock().await;
        fixture.handoff(&ticket(&id, 1)).await?;
        let now = lock_progress(&fixture.sink.0)
            .effects
            .front()
            .unwrap()
            .admitted_at;
        assert!(matches!(fixture.select(now), batch::Selection::Wait(_)));
        match mode {
            "flush" => {
                let flush = fixture.sink.flush(&id, 1);
                tokio::pin!(flush);
                assert!(futures::poll!(&mut flush).is_pending());
                // Dropping the barrier future leaves its fixed target installed.
            }
            "handoff-barrier" => {
                let barrier = channel.await_handoff_durable(&id, 1);
                tokio::pin!(barrier);
                assert!(futures::poll!(&mut barrier).is_pending());
            }
            "pressure" => lock_progress(&fixture.sink.0).pressure_paused = true,
            "queue-full" => {
                lock_progress(&fixture.sink.0).fault =
                    Some(pl_protocol::studio::HistoryFault::QueueFull)
            }
            "gap" => fixture.sink.admit(&id, ticket(&id, 2))?,
            _ => unreachable!(),
        }
        let selected = ready(fixture.select(now));
        assert_eq!(selected.len(), 1, "{mode}");
        drop(gate);
        fixture.sink.flush(&id, 1).await?;
        if mode == "gap" {
            assert_eq!(lock_progress(&fixture.sink.0).durable, 1);
            // The next handoff is deliberately produced only after the preceding prefix is durable.
            fixture.handoff(&ticket(&id, 2)).await?;
            fixture.finish(2).await?;
        } else {
            fixture.finish(1).await?;
        }
    }
    Ok(())
}

#[tokio::test]
async fn count_and_encoded_byte_limits_cut_a_batch_without_starving_large_effects() -> Result<()> {
    let mut fixture = Fixture::new("batch-count").await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let now = Instant::now();
    for sequence in 1..=64 {
        fixture.handoff(&ticket("batch-count", sequence)).await?;
        if sequence == 63 {
            assert!(matches!(fixture.select(now), batch::Selection::Wait(_)));
        }
    }
    assert_eq!(ready(fixture.select(now)).len(), 64);
    drop(gate);
    fixture.finish(64).await?;

    let mut fixture = Fixture::new("batch-large").await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let mut large = ticket("batch-large", 1);
    let extension = pl_core::thread::extensions::ExtensionRecord {
        revision: 1,
        payload: pl_core::context::OpaquePayload::text("large".repeat(256 * 1024)),
    };
    large
        .checkpoint
        .state
        .extensions
        .insert("test.large".into(), extension.clone());
    Arc::make_mut(&mut large.effect).extensions =
        Arc::from([pl_core::thread::extensions::ExtensionChange::Put {
            id: "test.large".into(),
            record: extension,
        }]);
    fixture.handoff(&large).await?;
    let now = lock_progress(&fixture.sink.0)
        .effects
        .front()
        .unwrap()
        .admitted_at;
    assert!(
        lock_progress(&fixture.sink.0)
            .effects
            .front()
            .unwrap()
            .bytes
            > 1024 * 1024
    );
    assert_eq!(ready(fixture.select(now)).len(), 1);
    fixture.handoff(&ticket("batch-large", 2)).await?;
    assert_eq!(ready(fixture.select(now)).len(), 1);
    drop(gate);
    fixture.finish(2).await
}

fn billed_context_write(id: &str, sequence: u64, prior: &[ContextRecord]) -> Result<ThreadWrite> {
    use crate::studio::thread_projection::AuxiliaryBillingReceipt;
    use pl_core::thread::extensions::{ExtensionChange, ExtensionRecord};
    use pl_protocol::{
        InferenceAccounting, InferenceBillingRecord, PricingOutcome, RuntimeCostAmount, UsageReport,
    };
    let mut write = visible_input_ticket(id, sequence, &format!("input-{sequence}"))?;
    let record = ContextRecord {
        id: format!("context-{sequence}"),
        turn_id: None,
        source: ContextSource::User,
        content: vec![ContextContent::Text {
            text: format!("body-{sequence}").into(),
        }],
        tool_calls: vec![],
    };
    let mut records = prior.to_vec();
    records.push(record.clone());
    write.checkpoint.state.context = ContextSnapshot {
        revision: sequence - 1,
        records: records.into(),
    };
    let interaction = pl_core::thread::interactions::InteractionRecord {
        created_at: 1,
        updated_at: 1,
        continuation_id: None,
        request: pl_core::thread::interactions::InteractionRequest {
            id: format!("question-{sequence}"),
            turn_id: "visible-turn".into(),
            // Opaque producer facts retain terminal receipts even without a product renderer.
            payload: pl_core::context::OpaquePayload::new("test.batch-question", 1, "{}")?,
        },
        revision: 2,
        state: pl_core::thread::interactions::InteractionState::Cancelled,
        extension_mutations: vec![],
    };
    // This terminal fact has left current state; its exact receipt remains an effect obligation.
    // The product current owner must not be asked to render an unregistered interaction format.
    let billing = InferenceBillingRecord {
        inference_id: format!("bill-{sequence}"),
        purpose: Some(format!("purpose-{sequence}")),
        account_id: "account".into(),
        account_display_name: None,
        model_id: Some("model".into()),
        model_observation: None,
        effort: None,
        context_window: None,
        accounting: InferenceAccounting {
            usage: UsageReport {
                input_tokens: Some(sequence),
                ..Default::default()
            },
            pricing: PricingOutcome::Estimated {
                cost: RuntimeCostAmount {
                    currency: "USD".into(),
                    amount: sequence as f64,
                },
                cache_savings: None,
            },
            ..Default::default()
        },
        prompt_generation: None,
        prompt_cache_policy: None,
        prefix_changed_reason: None,
        orchestration: Default::default(),
        timing: None,
        recorded_at: 1,
    };
    let extension = ExtensionRecord {
        revision: 1,
        payload: AuxiliaryBillingReceipt {
            billing,
            succeeded: true,
        }
        .into_payload()?,
    };
    let extension_id = format!("studio.auxiliary-billing.batch-{sequence}");
    write
        .checkpoint
        .state
        .extensions
        .insert(extension_id.clone(), extension.clone());
    let effect = Arc::make_mut(&mut write.effect);
    effect.interactions = Arc::from([interaction]);
    effect.context = Some(ContextChange::Append {
        revision: sequence - 1,
        records: Arc::from([record]),
    });
    effect.extensions = Arc::from([ExtensionChange::Put {
        id: extension_id,
        record: extension,
    }]);
    Ok(write)
}

#[tokio::test]
async fn physical_batch_rolls_back_all_effects_and_replays_the_same_frozen_records() -> Result<()> {
    let id = "batch-atomic-retry";
    let mut fixture = Fixture::new(id).await?;
    fixture.handoff(&ticket(id, 1)).await?;
    fixture.sink.flush(id, 1).await?;
    let history = fixture.store.history(id).await?;
    let path = fixture
        .store
        .session_paths("project-test", id)?
        .root()
        .join("history.sqlite");
    let db = Database::connect(
        crate::studio::paths::sqlite_file_options(
            &path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared(
        "CREATE TRIGGER reject_second_effect BEFORE UPDATE OF applied_write_seq ON history_meta \
         WHEN NEW.applied_write_seq=3 BEGIN SELECT RAISE(ABORT, 'reject second batch member'); END",
    )
    .await?;
    db.execute_unprepared(
        "CREATE TABLE batch_current_applied(sequence INTEGER NOT NULL); \
         CREATE TRIGGER observe_batch_current AFTER UPDATE ON completion_boundary_archive_view_state \
         BEGIN INSERT INTO batch_current_applied(sequence) \
         VALUES(json_extract(CAST(NEW.payload AS TEXT), '$.sourceEffectSeq')); END",
    )
    .await?;
    let channel = fixture.sink.0.channel.clone();
    let gate = channel.step_lock.lock().await;
    let second = billed_context_write(id, 2, &[])?;
    let third = billed_context_write(id, 3, &second.checkpoint.state.context.records)?;
    let prepared_second = fixture.handoff(&second).await?;
    let prepared_third = fixture.handoff(&third).await?;
    channel.request_flush(3);
    let frozen = ready(fixture.select(Instant::now()));
    assert_eq!(frozen.len(), 2);
    drop(gate);
    let mut status = channel.subscribe();
    tokio::time::timeout(
        crate::runtime_test_support::integration_test_deadline()?,
        async {
            while status.borrow_and_update().fault.is_none() {
                status.changed().await?;
            }
            Ok::<_, tokio::sync::watch::error::RecvError>(())
        },
    )
    .await??;
    assert_eq!(
        history.watermark().await?,
        1,
        "the first batch member must roll back too"
    );
    assert_eq!(
        history
            .checkpoint()
            .await?
            .unwrap()
            .state
            .context
            .records
            .len(),
        0
    );
    assert!(history.input_identity("input-2").await?.is_none());
    assert!(history.input_identity("input-3").await?.is_none());
    for sequence in [2, 3] {
        let receipt_id = crate::studio::thread_projection::order::receipt_id(
            "interaction",
            &format!("question-{sequence}"),
        );
        assert!(history.latest_fact_receipt(&receipt_id).await?.is_none());
    }
    let accounting = history.accounting().await?.unwrap();
    assert_eq!(accounting.revision, 1);
    assert!(accounting.purpose_costs.is_empty());
    assert_eq!(fixture.sink.0.chat.durable_seq(), 0);
    assert_eq!(lock_progress(&fixture.sink.0).usage.applied_sequence, 1);

    let gate = channel.step_lock.lock().await;
    let mut fourth = ticket(id, 4);
    fourth.checkpoint.state.context = third.checkpoint.state.context.clone();
    fixture.sink.admit(id, fourth.clone())?;
    let retried = ready(fixture.select(Instant::now()));
    assert_eq!(
        retried.len(),
        2,
        "new queued work cannot alter the failed transaction"
    );
    assert!(Arc::ptr_eq(&retried[0].prepared, &prepared_second));
    assert!(Arc::ptr_eq(&retried[1].prepared, &prepared_third));
    db.execute_unprepared("DROP TRIGGER reject_second_effect")
        .await?;
    // Lose the local queue acknowledgement after the physical commit, then replay that exact batch.
    let confirmations = channel
        .order_index
        .confirm_saved_calls
        .load(Ordering::Relaxed);
    batch::persist(&fixture.sink.0, &retried).await?;
    batch::persist(&fixture.sink.0, &retried).await?;
    assert_eq!(
        channel
            .order_index
            .confirm_saved_calls
            .load(Ordering::Relaxed),
        confirmations + 2,
        "each successful physical batch confirms and prunes the order index once"
    );
    assert_eq!(channel.subscribe().borrow().queued_records, 3);
    assert_eq!(fixture.sink.0.chat.durable_seq(), 2);
    assert_eq!(
        pl_core::chat::ChatHistory::latest_append_seq(&history).await?,
        2
    );
    let checkpoint = history.checkpoint().await?.unwrap();
    assert_eq!(
        checkpoint.state.context.records,
        third.checkpoint.state.context.records
    );
    assert_eq!(checkpoint.state.usage_summary.applied_sequence, 3);
    assert_eq!(checkpoint.state.usage_summary.totals.inference_count, 2);
    assert!(history.input_identity("input-2").await?.is_some());
    assert!(history.input_identity("input-3").await?.is_some());
    for write in [&second, &third] {
        let record = &write.effect.interactions[0];
        let receipt_id =
            crate::studio::thread_projection::order::receipt_id("interaction", &record.request.id);
        let receipt = history.latest_fact_receipt(&receipt_id).await?.unwrap();
        assert_eq!(receipt.kind, "interaction");
        assert_eq!(receipt.payload, serde_json::to_string(record)?);
    }
    assert_eq!(history.accounting().await?.unwrap().purpose_costs.len(), 2);
    let cold = history
        .cold_conversation(
            ChatQuery::new("conversation", None),
            ReadDemand::new(8, 1024 * 1024),
            &Budget,
        )
        .await?
        .unwrap();
    assert_eq!(cold.current.source_effect_seq, 3);
    let applied = db
        .query_all_raw(sea_orm::Statement::from_string(
            sea_orm::DatabaseBackend::Sqlite,
            "SELECT sequence FROM batch_current_applied ORDER BY rowid",
        ))
        .await?
        .iter()
        .map(|row| row.try_get::<i64>("", "sequence"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(
        applied,
        Vec::<i64>::new(),
        "ordered domain mutations remain complete, but neither the batch nor its replay updates archived current"
    );
    let generation = status.borrow().fault_generation;
    drop(gate);
    fixture
        .store
        .thread_persistence()
        .retry_history(id, generation)
        .await?;
    assert_eq!(lock_progress(&fixture.sink.0).durable, 3);
    fixture.handoff(&fourth).await?;
    fixture.finish(4).await
}
