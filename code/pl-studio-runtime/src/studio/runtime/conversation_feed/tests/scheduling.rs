use super::*;
use pl_core::{
    model::{ActiveModelProgress, ModelProgress, ObservedPart},
    thread::{
        AttemptStatus, RequestAttempt, ThreadSnapshot as CoreSnapshot, TurnRecord,
        TurnState as CoreTurnState,
    },
};

async fn publish_body(harness: &mut atoms::Harness, part: &ObservedPart) -> Result<()> {
    let state = CoreSnapshot {
        commit_sequence: harness.sequence,
        turns: vec![TurnRecord {
            turn_id: "atomic-turn".into(),
            input_id: None,
            state: CoreTurnState::Running,
            elapsed_ms: None,
            model_steps: 1,
        }]
        .into(),
        attempts: vec![RequestAttempt::new(
            "atomic-turn".into(),
            "atomic-attempt".into(),
            0,
            AttemptStatus::Running,
        )]
        .into(),
        model_progress: Some(ActiveModelProgress {
            attempt_id: "atomic-attempt".into(),
            progress: ModelProgress::new(part.version(), vec![part.clone()]),
        }),
        ..Default::default()
    };
    harness
        .projection
        .stream(&harness.session, &harness.thread, &state, harness.sequence)
        .await?;
    harness.source.publish_test_conversation(
        &harness.session,
        harness.projection.current_state().context("body current")?,
        None,
        harness.projection.timeline_generation(),
    )
}

fn body_progress(
    harness: &atoms::Harness,
    head: &Arc<ConversationSource>,
) -> Result<Arc<ConversationSource>> {
    let newest = harness
        .source
        .conversation()
        .source
        .context("body source")?;
    // Control only the feed's visible head, independently of the projection's collection
    // revision policy. Body reads still use the real, growing content owner above.
    Ok(Arc::new(ConversationSource {
        current: head.current.clone(),
        handoff: head.handoff.clone(),
        ..(*newest).clone()
    }))
}

fn queue_state(events: &broadcast::Sender<ThreadLiveEvent>, floor: u64, turn: &Turn) -> Result<()> {
    events.send(ThreadLiveEvent::Activity {
        observation_revision: floor + 1,
        activity: None,
    })?;
    events.send(ThreadLiveEvent::UnframedCommit { sequence: floor })?;
    events.send(ThreadLiveEvent::Activity {
        observation_revision: floor + 2,
        activity: None,
    })?;
    events.send(ThreadLiveEvent::Committed {
        sequence: floor + 1,
        changes: vec![LiveEvent::Turn {
            turn: turn.clone(),
            event: TurnEvent::Updated,
        }],
    })?;
    Ok(())
}

async fn next_state(feed: &mut ConversationFeed, expected: &Turn) -> Result<()> {
    let Some(ConversationEvent::State { update }) = feed.recv().await? else {
        bail!("body-only progress or ignored State events let Chat overtake the State fact");
    };
    let ThreadSubscriptionUpdate::Notification { notification } = *update else {
        bail!("expected the typed State notification");
    };
    let ThreadNotification::TurnUpdated { turn } = notification.notification else {
        bail!("expected the original TurnUpdated fact");
    };
    assert_eq!(&turn, expected);
    Ok(())
}

#[tokio::test]
async fn body_only_progress_preserves_state_and_chat_scheduling_opportunities() -> Result<()> {
    let env = support::Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut harness = atoms::Harness::new(&env).await?;
        let member = atoms::start("scheduling-body", false);
        let mut part = ObservedPart::new(member.identity.clone()).appended(&"x".repeat(1024));
        harness.effect(vec![member], vec![]).await?;
        publish_body(&mut harness, &part).await?;
        let mut feed = env
            .runtime
            .open_conversation_feed(&harness.thread.id, ChatScope::Main, demand())
            .await?;
        let initial = chat(&mut feed).await?;
        let snapshot = state_snapshot(&mut feed).await?;
        let mut turn = snapshot.active_turn.context("running Turn baseline")?;
        let (events, state) = broadcast::channel(16);
        feed.state = Some(DeliveryReceiver::new(
            state,
            Arc::new(tokio::sync::Notify::new()),
            CancellationToken::new(),
        ));
        let head = harness
            .source
            .conversation()
            .source
            .context("visible head")?;
        let (progress, progress_rx) = watch::channel(Some(head.clone()));
        feed.progress = Some(progress_rx);

        // Grow the real body beyond its stable preview. Poll to the actual receive wait,
        // without a timer, so the next round starts after a no-output Chat opportunity.
        part = part.appended(" body keeps growing");
        publish_body(&mut harness, &part).await?;
        let body_source = body_progress(&harness, &head)?;
        progress.send_replace(Some(body_source.clone()));
        assert_eq!(
            body_source.current.projection(),
            initial.current.as_ref().unwrap()
        );
        assert!(futures::poll!(Box::pin(feed.recv())).is_pending());
        assert_eq!(feed.seen_serial, body_source.serial);

        // A check must pass all ignored/covered events before a queued visible cut.
        // Reading one raw event per opportunity would incorrectly return Chat here.
        let floor = feed.state_effect_floor;
        turn.revision = floor + 1;
        queue_state(&events, floor, &turn)?;
        harness
            .effect(vec![atoms::start("visible-after-progress", true)], vec![])
            .await?;
        let visible = harness
            .source
            .conversation()
            .source
            .context("visible cut")?
            .current
            .projection()
            .clone();
        assert_ne!(Some(&visible), initial.current.as_ref());
        next_state(&mut feed, &turn).await?;

        // Claim the ready cut: acquiring a cut is itself a Chat processing opportunity,
        // so distinguish that from a cut whose visible entries are already deliverable.
        feed.cut = Some(
            feed.cuts
                .as_mut()
                .context("reliable cut receiver")?
                .try_recv()?,
        );
        // More State is already ready, but the claimed Chat cut must get its turn.
        let floor = feed.state_effect_floor;
        turn.revision = floor + 1;
        queue_state(&events, floor, &turn)?;
        let Some(ConversationEvent::Chat { batch }) = feed.recv().await? else {
            bail!("State checks starved the already-deliverable Chat cut");
        };
        assert_eq!(batch.current.as_ref(), Some(&visible));
        next_state(&mut feed, &turn).await?;

        // Exercise the early continue of an already-claimed, no-visible-change cut
        // while State and another reliable visible cut are both queued.
        let head = harness
            .source
            .conversation()
            .source
            .context("next visible head")?;
        part = part.appended(" still running");
        publish_body(&mut harness, &part).await?;
        let body_source = body_progress(&harness, &head)?;
        progress.send_replace(Some(body_source.clone()));
        assert_eq!(
            body_source.current.projection(),
            feed.current.as_ref().unwrap()
        );
        feed.cut = Some(body_source.cut());
        harness
            .effect(vec![atoms::start("visible-after-empty-cut", false)], vec![])
            .await?;
        let next_visible = harness
            .source
            .conversation()
            .source
            .context("next visible cut")?
            .current
            .projection()
            .clone();
        assert_ne!(next_visible, visible);
        let floor = feed.state_effect_floor;
        turn.revision = floor + 1;
        queue_state(&events, floor, &turn)?;
        next_state(&mut feed, &turn).await?;
        assert_eq!(feed.seen_serial, body_source.serial);
        let Some(ConversationEvent::Chat { batch }) = feed.recv().await? else {
            bail!("State delivery did not leave a Chat opportunity");
        };
        assert_eq!(batch.current.as_ref(), Some(&next_visible));

        feed.close().await?;
        feed.reader().close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    env.finish(result).await
}
