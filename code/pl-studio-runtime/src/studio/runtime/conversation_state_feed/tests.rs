use super::*;
use crate::runtime_test_support as support;
use crate::studio::runtime::conversation_feed::tests::{completed_runs, state_snapshot};
use anyhow::{Context, Result, bail};
use pl_protocol::*;
use std::time::Duration;
#[path = "coalescing.rs"]
mod coalescing;

#[tokio::test]
async fn state_only_cold_open_prepares_supported_history_without_execution() -> Result<()> {
    use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
    use crate::studio::storage::history::{HistoryStore, discard_empty_demand_fixture};
    use sea_orm::{ConnectionTrait, Database};

    let mut env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "state-only migration")
            .await?;
        let path = env
            .runtime
            .store
            .registered_session_paths(&thread.id)?
            .history_database();
        env.runtime.shutdown_runtime().await?;
        let history = HistoryStore::open(&path, &thread.id).await?;
        let saved_sequence = history.watermark().await?;
        let saved_checkpoint =
            serde_json::to_value(history.checkpoint().await?.context("created checkpoint")?)?;
        drop(history);

        // Match the supported-v2 fixture at the original storage boundary.
        // This isolated history has no completion outputs to discard.
        let db = Database::connect(
            sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
        )
        .await?;
        discard_empty_demand_fixture(&db).await?;
        db.execute_unprepared(
            "DROP TABLE seaql_migrations;
             DROP TABLE timeline_records;
             ALTER TABLE history_input_identities DROP COLUMN request_digest;
             UPDATE history_meta SET schema_version=8",
        )
        .await?;
        db.close().await?;
        env.restart().await?;
        assert!(
            env.runtime
                .session_of(&thread.id)
                .and_then(|session| session.observed_thread(&thread.id))
                .is_none()
        );
        let history = env.runtime.store.history(&thread.id).await?;
        assert!(
            history.cold_state_facet().await.is_err(),
            "fixture must still require supported-history preparation"
        );

        // No content feed or execution admission may prepare this for State.
        let mut state = env.runtime.open_conversation_state_feed(&thread.id).await?;
        let snapshot = state_snapshot(&mut state).await?;
        assert_eq!(snapshot.thread.id, thread.id);
        assert!(snapshot.active_turn.is_none() && snapshot.activity.is_none());
        assert!(
            env.runtime
                .session_of(&thread.id)
                .and_then(|session| session.observed_thread(&thread.id))
                .is_none()
        );
        assert_eq!(env.root_provider.recorded().len(), 0);
        assert_eq!(
            serde_json::to_value(history.checkpoint().await?.context("prepared checkpoint")?)?,
            saved_checkpoint
        );
        assert_eq!(history.watermark().await?, saved_sequence);
        state.close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn unconsumed_content_does_not_delay_final_state_and_cold_statistics() -> Result<()> {
    use crate::config::{ConfigPaths, ConfigStore};
    use crate::studio::runtime::conversation_feed::tests::demand;
    use pl_model::{
        config::{AccountId, AccountModelCatalogConfig},
        model::{ModelPricing, TokenPriceTier},
    };
    use pl_provider_fixture::ReplyStage;

    let stage = ReplyStage::new();
    let mut env = support::Environment::new(
        vec![support::prompt_step(
            "independent-state",
            0,
            support::held_reply(&stage, "state-response"),
        )],
        vec![],
    )
    .await?;
    let phase = std::cell::Cell::new("configure");
    let result = tokio::time::timeout(Duration::from_secs(45), async {
        let store = ConfigStore::new(ConfigPaths::from_config_dir(&env.home));
        let mut config = store.load()?;
        let account = config
            .models
            .accounts
            .get_mut(&AccountId::new("root-fixture")?)
            .context("fixture account")?;
        let AccountModelCatalogConfig::Explicit { models, .. } = &mut account.catalog else {
            bail!("expected explicit fixture catalog");
        };
        let model = models
            .iter_mut()
            .find(|model| model.model_id == support::MODEL)
            .context("fixture model")?;
        model.context_window = Some(128_000);
        model.max_context_window = Some(256_000);
        model.pricing = ModelPricing::Rates {
            currency: "USD".into(),
            tiers: vec![TokenPriceTier::flat(1.0, 2.0, Some(0.1), None)],
            weekly_adjustment: None,
            source: "state regression".into(),
            verified_at: 1,
        };
        store.save(&config)?;
        phase.set("restart configured fixture");
        env.restart().await?;
        phase.set("admit prompt");
        let started = env
            .start(ThreadWorkspaceMode::Local, "independent-state")
            .await?;
        let id = &started.thread.id;
        phase.set("provider stage");
        support::reached(&stage).await?;
        // The fixture gate proves provider admission, not projection progress.
        // Settle the known running cut before checking its baseline.
        env.runtime.synchronize_thread_observation(id).await?;
        phase.set("open content");
        let mut content = env
            .runtime
            .open_conversation_feed(id, ChatScope::Main, demand())
            .await?;
        phase.set("open State");
        let mut state = env.runtime.open_conversation_state_feed(id).await?;
        assert_eq!(state.thread_id(), id);
        assert_ne!(state.subscription_id(), content.subscription_id());
        let baseline = state_snapshot(&mut state).await?;
        let turn_id = baseline.active_turn.context("running baseline")?.id;
        let mut revision = baseline.revision;
        let mut epoch = 1;
        stage.release();
        phase.set("final State");
        // Do not poll content at all, including its initial Set/Activity. There is
        // no subsequent prompt or activity publication to flush a lost final value.
        let final_runtime = tokio::time::timeout(Duration::from_secs(20), async {
            let mut terminal = false;
            let mut durable = None;
            loop {
                let update = state
                    .recv()
                    .await?
                    .context("State ended before terminal statistics")?;
                let ThreadSubscriptionUpdate::Notification { notification } = update else {
                    bail!("unexpected second baseline");
                };
                assert_eq!(notification.thread_id, *id);
                assert_eq!(notification.epoch, epoch);
                assert_eq!(notification.base_revision, revision);
                assert_eq!(notification.revision, revision + 1);
                revision = notification.revision;
                epoch = notification.epoch;
                match notification.notification {
                    ThreadNotification::TurnCompleted { turn } => {
                        assert_eq!(turn.id, turn_id);
                        assert!(matches!(turn.state, TurnState::Completed(_)));
                        terminal = true;
                    }
                    ThreadNotification::ThreadRuntimeUpdated { runtime, .. }
                        if runtime.live_usage.is_none() && runtime.usage.completion_tokens == 5 =>
                    {
                        durable = Some(*runtime);
                    }
                    ThreadNotification::Lagged { .. } => bail!("finite State script lost frames"),
                    _ => {}
                }
                if terminal && let Some(runtime) = durable.take() {
                    break Ok::<_, anyhow::Error>(runtime);
                }
            }
        })
        .await
        .context("final State required unrelated future content")??;
        assert_eq!(final_runtime.usage.prompt_tokens, 11);
        assert_eq!(final_runtime.usage.total_tokens, 16);
        assert!(final_runtime.usage.latest_context_tokens > 0);
        assert!(!final_runtime.usage.estimated_costs.is_empty());
        assert_eq!(final_runtime.turn_completion_tokens, 5);
        assert!(final_runtime.turn_response_millis > 0);
        state.close().await?;
        assert!(state.cancellation_token().is_cancelled());
        assert!(!content.cancellation_token().is_cancelled());
        assert!(
            matches!(
                content.recv().await?,
                Some(crate::studio::ConversationEvent::Chat { batch })
                    if batch.placement == ChatPlacement::Set
            ),
            "closing State invalidated the independently owned content feed"
        );
        content.close().await?;
        content.reader().close().await?;
        phase.set("flush executed owner");
        env.runtime
            .require_session(id)?
            .observed_thread(id)
            .context("executed owner")?
            .flush()
            .await?;
        phase.set("cold restart");
        env.restart().await?;
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none()
        );
        let requests = env.root_provider.recorded().len();
        phase.set("cold State");
        let mut cold = env.runtime.open_conversation_state_feed(id).await?;
        let snapshot = state_snapshot(&mut cold).await?;
        assert!(snapshot.active_turn.is_none() && snapshot.activity.is_none());
        assert!(snapshot.business_refs.interactions.is_some());
        let runtime = snapshot.runtime.context("cold saved runtime missing")?;
        assert!(runtime.live_usage.is_none());
        let mut expected_usage = final_runtime.usage;
        expected_usage.updated_at = runtime.usage.updated_at;
        assert_eq!(runtime.usage, expected_usage);
        assert_eq!(
            runtime.turn_completion_tokens,
            final_runtime.turn_completion_tokens
        );
        assert_eq!(
            runtime.turn_response_millis,
            final_runtime.turn_response_millis
        );
        assert!(
            env.runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_none(),
            "cold State activated execution"
        );
        assert_eq!(env.root_provider.recorded().len(), requests);
        cold.request_close();
        assert!(matches!(
            cold.recv()
                .await
                .unwrap_err()
                .downcast_ref::<core::ChatError>(),
            Some(core::ChatError::Cancelled)
        ));
        cold.close().await?;
        Ok(())
    })
    .await
    .with_context(|| format!("State scenario timed out during {}", phase.get()))
    .and_then(std::convert::identity);
    stage.release();
    if let Err(error) = &result {
        eprintln!("State scenario failed during {}: {error:#}", phase.get());
    }
    env.finish(result).await
}

#[tokio::test]
async fn retained_terminal_state_requires_coverage_and_no_active_turn_and_is_deduplicated()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "retained State qualification")
            .await?;
        let mut feed = env.runtime.open_conversation_state_feed(&thread.id).await?;
        let _snapshot = feed.recv().await?.context("initial State snapshot")?;
        assert!(feed.pending.is_empty());
        let uncovered = feed
            .applied
            .checked_add(1)
            .context("test State cut exhausted")?;
        let terminal = Turn {
            input_id: Some("original-input".into()),
            id: "original-turn".into(),
            thread_id: thread.id.clone(),
            revision: uncovered,
            state: TurnState::Completed(CompletedTurnState::new(
                Some(1),
                2,
                TurnCompletion::Normal,
            )),
            updated_at: 2,
        };
        let revision = feed.revision;
        feed.reflect_terminal(terminal.clone())?;
        assert!(feed.pending.is_empty(), "future terminal crossed the cut");
        assert_eq!(feed.revision, revision);

        feed.applied = terminal.revision;
        feed.active_turn = Some("newer-active-turn".into());
        feed.reflect_terminal(terminal.clone())?;
        assert!(feed.pending.is_empty(), "older terminal hid an active Turn");
        assert_eq!(feed.revision, revision);

        feed.active_turn = None;
        feed.reflect_terminal(terminal.clone())?;
        assert_eq!(feed.pending.len(), 1);
        assert_eq!(feed.revision, revision + 1);
        feed.reflect_terminal(terminal.clone())?;
        feed.apply(ThreadLiveEvent::Committed {
            sequence: terminal.revision + 1,
            changes: vec![LiveEvent::Turn {
                turn: terminal.clone(),
                event: TurnEvent::Completed,
            }],
        })?;
        assert_eq!(
            feed.pending.len(),
            1,
            "retained/live duplicate spent a frame"
        );
        assert_eq!(feed.revision, revision + 1);

        let newer = Turn {
            revision: terminal.revision + 1,
            ..terminal
        };
        feed.reflect_terminal(newer)?;
        assert_eq!(feed.pending.len(), 2, "newer same-Turn fact was suppressed");
        assert_eq!(feed.revision, revision + 2);
        feed.apply(ThreadLiveEvent::UnframedCommit {
            sequence: feed.applied,
        })?;
        assert_eq!(feed.pending.len(), 2, "covered gap spent a State frame");
        assert_eq!(feed.revision, revision + 2);
        for _ in 0..2 {
            assert!(matches!(
                feed.recv().await?,
                Some(ThreadSubscriptionUpdate::Notification { .. })
            ));
        }
        let (events, state) = tokio::sync::broadcast::channel(1);
        feed.state = Some(StateReceiver::new(state, Default::default()));
        events.send(ThreadLiveEvent::UnframedCommit {
            sequence: feed.applied + 1,
        })?;
        let update = feed
            .recv()
            .await?
            .context("uncovered gap must publish Lagged")?;
        assert!(
            matches!(update, ThreadSubscriptionUpdate::Notification { notification }
            if notification.epoch == 2
                && matches!(notification.notification, ThreadNotification::Lagged { dropped: 1 }))
        );
        feed.close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
