use super::*;

fn runtime_update(
    thread_id: &str,
    turn_id: &str,
    attempt_id: &str,
    state: ThreadRuntimeUsageState,
    sequence: u64,
) -> Result<ThreadNotification> {
    let mut runtime = crate::studio::thread_projection::project_runtime(
        thread_id,
        &Default::default(),
        sequence as i64,
        &Default::default(),
    )?;
    runtime.live_usage = Some(ThreadRuntimeLiveUsage {
        turn_id: turn_id.into(),
        attempt_id: attempt_id.into(),
        completion_tokens: Some(sequence),
        response_millis: Some(sequence * 10),
        latest_context_tokens: None,
        state,
        observation_sequence: sequence,
    });
    runtime.progress = Some(format!("progress-{sequence}"));
    Ok(ThreadNotification::ThreadRuntimeUpdated {
        runtime: Box::new(runtime),
        model_route: Some(ThreadModelRouteSnapshot {
            bot_id: None,
            account_id: "coalescing-account".into(),
            model_id: format!("model-{sequence}"),
            effort: None,
            revision: sequence,
            available: true,
            unavailable_reason: None,
        }),
    })
}

fn runtime_event(notification: &ThreadNotification, revision: u64) -> ThreadLiveEvent {
    let ThreadNotification::ThreadRuntimeUpdated {
        runtime,
        model_route,
    } = notification
    else {
        panic!("expected Runtime test input");
    };
    ThreadLiveEvent::Runtime {
        runtime: Arc::new((**runtime).clone()),
        model_route: model_route.clone(),
        observation_revision: revision,
        catalog_revision: revision,
    }
}

#[tokio::test]
async fn bounded_scan_coalesces_live_runtime_without_crossing_state_or_identity_boundaries()
-> Result<()> {
    use ThreadRuntimeUsageState::{Authoritative, Live};
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = completed_runs::Harness::new(&env).await?;
        harness.effect(vec![], vec![]).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, demand())
            .await?;
        assert_eq!(chat(&mut feed).await?.placement, ChatPlacement::Set);
        let snapshot = state_snapshot(&mut feed).await?;
        completed_runs::activity(&mut feed).await?;
        let mut turn = snapshot.active_turn.context("running Turn baseline")?;
        let base_revision = feed.state_revision;
        let effect_floor = feed.state_effect_floor;
        let runtime_floor = feed.runtime_floor.0.max(feed.runtime_floor.1);
        let (events, state) = broadcast::channel(64);
        feed.state = Some(super::super::super::thread_observation::StateReceiver::new(
            state,
            CancellationToken::new(),
        ));
        feed.state_turn = true;
        let mut expected = Vec::new();
        for (index, (turn_id, attempt_id, usage_state)) in [
            ("turn-a", "attempt-a", Live),
            ("turn-a", "attempt-a", Live),
            ("turn-a", "attempt-a", Live),
            ("turn-a", "attempt-a", Live),
            ("turn-a", "attempt-a", Live),
            ("turn-a", "attempt-a", Live),
            ("turn-b", "attempt-a", Live),
            ("turn-b", "attempt-b", Live),
            ("turn-b", "attempt-b", Authoritative),
            ("turn-b", "attempt-b", Authoritative),
            ("turn-b", "attempt-b", Live),
            ("turn-b", "attempt-b", Live),
        ]
        .into_iter()
        .enumerate()
        {
            let sequence = index as u64 + 1;
            let notification = runtime_update(
                &harness.thread.id,
                turn_id,
                attempt_id,
                usage_state,
                sequence,
            )?;
            events.send(runtime_event(&notification, runtime_floor + sequence))?;
            events.send(ThreadLiveEvent::Activity {
                observation_revision: runtime_floor + sequence,
                activity: None,
            })?;
            if [2, 4, 6, 7, 8, 9, 10, 12].contains(&sequence) {
                expected.push(notification);
            }
            let change = match sequence {
                2 => {
                    turn.revision = effect_floor + 1;
                    expected.push(ThreadNotification::TurnUpdated { turn: turn.clone() });
                    Some(LiveEvent::Turn {
                        turn: turn.clone(),
                        event: TurnEvent::Updated,
                    })
                }
                4 => {
                    let interaction = Box::new(InteractionRequest::user_input(
                        "coalescing-interaction",
                        InteractionScope {
                            thread_id: harness.thread.id.clone(),
                            turn_id: turn.id.clone(),
                            item_id: None,
                            tool_id: None,
                            agent_path: None,
                            purpose: InteractionPurpose::General,
                        },
                        vec![],
                        1,
                    ));
                    expected.push(ThreadNotification::InteractionChanged {
                        interaction: interaction.clone(),
                    });
                    Some(LiveEvent::Interaction(interaction))
                }
                _ => None,
            };
            if let Some(change) = change {
                events.send(ThreadLiveEvent::Committed {
                    sequence: effect_floor + sequence / 2,
                    changes: vec![change],
                })?;
            }
        }
        for (index, notification_expected) in expected.iter().enumerate() {
            let Some(ConversationEvent::State { update }) = feed.recv().await? else {
                bail!("missing ordered State frame {index}");
            };
            if index == 0 {
                assert_eq!(feed.state.as_ref().unwrap().len(), 0, "scan stopped early");
                assert_eq!(feed.pending.len(), expected.len() - 1);
                assert_eq!(feed.state_revision, base_revision + expected.len() as u64);
            }
            let ThreadSubscriptionUpdate::Notification { notification } = *update else {
                bail!("unexpected State snapshot");
            };
            assert_eq!(notification.base_revision, base_revision + index as u64);
            assert_eq!(notification.revision, base_revision + index as u64 + 1);
            assert_eq!(&notification.notification, notification_expected);
        }
        assert!(feed.pending.is_empty());

        // A successful tail replacement refreshes time, but keeps both envelope revisions
        // and the subscription watermark. Compare the whole payload, including model_route.
        let first = runtime_update(&harness.thread.id, "tail-turn", "tail-attempt", Live, 20)?;
        feed.notification(first)?;
        let Some(ThreadSubscriptionUpdate::Notification { notification: tail }) =
            feed.pending.back_mut()
        else {
            bail!("missing pending tail");
        };
        tail.emitted_at = -1;
        let revisions = (tail.base_revision, tail.revision, feed.state_revision);
        let latest = runtime_update(&harness.thread.id, "tail-turn", "tail-attempt", Live, 21)?;
        feed.notification(latest.clone())?;
        assert_eq!(feed.pending.len(), 1);
        let Some(ThreadSubscriptionUpdate::Notification { notification: tail }) =
            feed.pending.back()
        else {
            bail!("missing replaced tail");
        };
        assert_eq!(tail.notification, latest);
        assert!(tail.emitted_at >= 0);
        assert_eq!(
            (tail.base_revision, tail.revision, feed.state_revision),
            revisions
        );
        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn bounded_scan_preserves_budget_and_raw_channel_failures() -> Result<()> {
    use ThreadRuntimeUsageState::{Authoritative, Live};
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "State bounds")
            .await?;
        for case in ["replacement-bytes", "pending-frames", "lagged", "closed"] {
            let mut feed = env
                .runtime
                .open_conversation_feed(&thread.id, ChatScope::Main, demand())
                .await?;
            let _set = chat(&mut feed).await?;
            let _snapshot = state_snapshot(&mut feed).await?;
            completed_runs::activity(&mut feed).await?;
            let revision = feed.state_revision;
            let floor = feed.runtime_floor.0.max(feed.runtime_floor.1);
            let (events, state) = broadcast::channel(if case == "lagged" { 2 } else { 128 });
            feed.state = Some(super::super::super::thread_observation::StateReceiver::new(
                state,
                CancellationToken::new(),
            ));
            feed.state_turn = true;
            let frames = match case {
                "replacement-bytes" => 2,
                "pending-frames" => 65,
                "lagged" => 3,
                "closed" => 0,
                _ => unreachable!(),
            };
            for sequence in 1..=frames {
                let mut notification = runtime_update(
                    &thread.id,
                    "bounded-turn",
                    "bounded-attempt",
                    if case == "replacement-bytes" {
                        Live
                    } else {
                        Authoritative
                    },
                    sequence,
                )?;
                if case == "replacement-bytes"
                    && sequence == 2
                    && let ThreadNotification::ThreadRuntimeUpdated { runtime, .. } =
                        &mut notification
                {
                    runtime.progress = Some("x".repeat(1024 * 1024));
                }
                events.send(runtime_event(&notification, floor + sequence))?;
            }
            drop(events);
            let error = feed.recv().await.expect_err(case);
            assert_eq!(
                error
                    .downcast_ref::<pl_protocol::studio::StudioError>()
                    .and_then(|error| error.reason()),
                Some("conversationResyncRequired"),
                "{case}: {error:#}"
            );
            assert!(
                feed.reader().ensure().is_err(),
                "{case} kept the old read lease"
            );
            if case == "replacement-bytes" {
                assert_eq!(
                    feed.state_revision,
                    revision + 1,
                    "replacement spent a revision"
                );
            }
            if case == "lagged" {
                assert!(error.to_string().contains("state try_recv lagged"));
            }
            feed.close().await?;
            feed.reader().close().await?;
        }
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
