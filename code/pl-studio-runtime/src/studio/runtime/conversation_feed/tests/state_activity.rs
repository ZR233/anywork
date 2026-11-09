//! The original typed State summary is independent of body/member Activity barriers.
use super::*;
use completed_runs::{Harness, activity};
use pl_core::{
    model::{
        ActiveModelProgress, AggregateChannel, ModelProgress, ObservedPart, ObservedPartIdentity,
    },
    thread::{
        ActiveExecution, ExecutionPhase, ModelExecutionPhase, RequestAttempt,
        ThreadSnapshot as CoreSnapshot, TurnRecord, TurnState as CoreTurnState,
    },
};

fn thinking(revision: u64) -> Result<CoreSnapshot> {
    let attempt: RequestAttempt = serde_json::from_value(serde_json::json!({
        "turnId": "summary-turn", "attemptId": "summary-attempt",
        "retryOf": null, "inputRevision": 0, "status": {"kind": "running"}
    }))?;
    Ok(CoreSnapshot {
        observation_revision: revision,
        execution: Some(ActiveExecution {
            id: "summary-execution".into(),
            phase: ExecutionPhase::Running,
            turn_id: Some("summary-turn".into()),
        }),
        turns: vec![TurnRecord {
            turn_id: "summary-turn".into(),
            input_id: None,
            state: CoreTurnState::Running,
            model_steps: 1,
            elapsed_ms: None,
        }]
        .into(),
        attempts: vec![attempt].into(),
        model_execution: Some(ModelExecutionPhase::Running),
        model_progress: Some(ActiveModelProgress {
            attempt_id: "summary-attempt".into(),
            progress: ModelProgress::new(
                1,
                vec![
                    ObservedPart::new(ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Reasoning,
                    })
                    .appended("thinking before a completed member exists"),
                ],
            ),
        }),
        ..Default::default()
    })
}

async fn publish(h: &mut Harness, state: &CoreSnapshot) -> Result<Option<ThreadActivity>> {
    h.projection
        .stream(&h.session, &h.thread, state, state.commit_sequence)
        .await?;
    let summary = h.projection.current_activity();
    h.source
        .publish_test_state_activity(state.observation_revision, summary.clone());
    h.source.publish_test_conversation(
        &h.session,
        h.projection.current_state().context("current owner cut")?,
    )?;
    Ok(summary)
}

async fn expect_update(
    feed: &mut ConversationFeed,
    state: &mut ConversationStateFeed,
    expected: Option<&ThreadActivity>,
    notifications: usize,
) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        for _ in 0..notifications {
            loop {
                let update = state.recv().await?.context("State summary feed ended")?;
                if let ThreadSubscriptionUpdate::Notification { notification } = update
                    && let ThreadNotification::ActivityChanged { activity } =
                        notification.notification
                {
                    assert_eq!(activity.as_deref(), expected);
                    break;
                }
            }
        }
        loop {
            match feed.recv().await?.context("summary feed ended")? {
                ConversationEvent::Activity { snapshot } => {
                    assert_eq!(snapshot.completed_through, feed.delivered);
                    assert!(
                        snapshot.entries.is_empty(),
                        "summary invented a body member"
                    );
                    if notifications == 0 {
                        // No producer remains in flight in this synthetic cut.
                        // Allow the State owner's bounded coalescing interval.
                        assert!(
                            tokio::time::timeout(Duration::from_millis(100), state.recv())
                                .await
                                .is_err(),
                            "unchanged or retired phase emitted a State frame"
                        );
                    }
                    return Ok(());
                }
                ConversationEvent::Chat { .. } => {
                    bail!("a phase-only change invented a completion batch")
                }
            }
        }
    })
    .await?
}

#[tokio::test]
async fn preexisting_thinking_summary_and_phase_clear_do_not_require_body_entries() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let mut state = thinking(10)?;
        let first = publish(&mut h, &state).await?.context("thinking summary")?;
        assert_eq!(first.kind, ThreadActivityKind::Thinking);
        let mut feed = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        let set = chat(&mut feed).await?;
        assert!(set.entries.is_empty());
        let mut state_feed = env
            .runtime
            .open_conversation_state_feed(&h.thread.id)
            .await?;
        let baseline = state_snapshot(&mut state_feed).await?;
        assert_eq!(baseline.activity.as_ref(), Some(&first));
        assert!(baseline.active_turn.is_some());
        let snapshot = activity(&mut feed).await?;
        assert!(snapshot.execution_present);
        assert!(snapshot.entries.is_empty());
        assert_eq!(snapshot.completed_through, set.through_seq);

        state.observation_revision = 11;
        state.attempts = Arc::from([]);
        state.model_progress = None;
        state.model_execution = Some(ModelExecutionPhase::PreparingRequest);
        let preparing = publish(&mut h, &state)
            .await?
            .context("preparing summary")?;
        assert_eq!(preparing.kind, ThreadActivityKind::Preparing);
        expect_update(&mut feed, &mut state_feed, Some(&preparing), 1).await?;
        state.observation_revision = 12;
        state.execution.as_mut().unwrap().phase = ExecutionPhase::Stopping;
        let stopping = publish(&mut h, &state).await?.context("stopping summary")?;
        assert_eq!(stopping.kind, ThreadActivityKind::Stopping);
        expect_update(&mut feed, &mut state_feed, Some(&stopping), 1).await?;
        let idle = CoreSnapshot {
            observation_revision: 13,
            turns: vec![TurnRecord {
                turn_id: "summary-turn".into(),
                input_id: None,
                state: CoreTurnState::Interrupted,
                model_steps: 1,
                elapsed_ms: Some(1),
            }]
            .into(),
            ..Default::default()
        };
        assert!(publish(&mut h, &idle).await?.is_none());
        expect_update(&mut feed, &mut state_feed, None, 1).await?;

        // Older or same-cut events must neither revive the summary nor replace
        // the retained baseline for a subscriber opening after this clear.
        h.source
            .publish_test_state_activity(10, Some(first.clone()));
        h.source.publish_test_state_activity(13, Some(first));
        let next_idle = CoreSnapshot {
            observation_revision: 14,
            ..Default::default()
        };
        publish(&mut h, &next_idle).await?;
        expect_update(&mut feed, &mut state_feed, None, 0).await?;
        let mut reopened = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        chat(&mut reopened).await?;
        let mut reopened_state = env
            .runtime
            .open_conversation_state_feed(&h.thread.id)
            .await?;
        assert!(
            state_snapshot(&mut reopened_state)
                .await?
                .activity
                .is_none()
        );
        reopened_state.close().await?;
        reopened.close().await?;
        reopened.reader().close().await?;
        state_feed.close().await?;
        feed.close().await?;
        feed.reader().close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn idle_to_thinking_summary_and_old_epoch_events_keep_the_original_qualification()
-> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        let mut old = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        chat(&mut old).await?;
        let mut old_state = env
            .runtime
            .open_conversation_state_feed(&h.thread.id)
            .await?;
        assert!(state_snapshot(&mut old_state).await?.activity.is_none());
        activity(&mut old).await?;
        let summary = publish(&mut h, &thinking(10)?)
            .await?
            .context("thinking summary")?;
        expect_update(&mut old, &mut old_state, Some(&summary), 1).await?;

        let retired = h.source.clone();
        let slot = env
            .runtime
            .thread_observations
            .observation_slot(&h.thread.id);
        // A1 -> B -> A2 use distinct original source instances, not a reusable
        // cancellation handle or an executionPresent-derived phase.
        let (_b_owner, progress) = watch::channel(Default::default());
        let b = Arc::new(
            super::super::super::thread_observation::ThreadLiveFeed::new(
                None,
                progress,
                Default::default(),
            ),
        );
        slot.install(b);
        let (_a_owner, progress) = watch::channel(Default::default());
        h.source = Arc::new(
            super::super::super::thread_observation::ThreadLiveFeed::new(
                None,
                progress,
                Default::default(),
            ),
        );
        publish(
            &mut h,
            &CoreSnapshot {
                observation_revision: 1,
                ..Default::default()
            },
        )
        .await?;
        slot.install(h.source.clone());
        retired.publish_test_state_activity(999, Some(summary.clone()));
        assert!(old.recv().await.is_err());
        assert!(old_state.recv().await.is_err());
        let mut new = env
            .runtime
            .open_conversation_feed(&h.thread.id, ChatScope::Main, demand())
            .await?;
        chat(&mut new).await?;
        let mut new_state = env
            .runtime
            .open_conversation_state_feed(&h.thread.id)
            .await?;
        assert!(state_snapshot(&mut new_state).await?.activity.is_none());
        activity(&mut new).await?;
        retired.publish_test_state_activity(1000, Some(summary));
        publish(
            &mut h,
            &CoreSnapshot {
                observation_revision: 2,
                ..Default::default()
            },
        )
        .await?;
        expect_update(&mut new, &mut new_state, None, 0).await?;
        old_state.close().await?;
        new_state.close().await?;
        old.close().await?;
        old.reader().close().await?;
        new.reader().ensure()?;
        new.close().await?;
        new.reader().close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}
