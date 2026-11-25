use super::*;
use tokio_util::sync::CancellationToken;

#[tokio::test]
async fn state_lag_resets_before_replay_and_closure_wins_over_buffered_frames() {
    let (_, progress) = watch::channel(Progress::default());
    let cancellation = CancellationToken::new();
    let feed = ThreadLiveFeed::new(None, progress, cancellation.clone());
    let mut slow = feed.subscribe();
    let mut parked = feed.subscribe();

    for revision in 1_u64..=(u64::try_from(LIVE_FEED_FRAMES).unwrap() + 2) {
        feed.publish(|| ThreadLiveEvent::Activity {
            observation_revision: revision,
            activity: None,
        });
    }
    match slow.try_recv() {
        Err(broadcast::error::TryRecvError::Lagged(dropped)) => {
            assert_eq!(
                dropped, 2,
                "exactly the two frames beyond the bound are lost"
            );
        }
        other => panic!("expected an explicit lag reset, got {other:?}"),
    }
    match slow.try_recv() {
        Ok(ThreadLiveEvent::Activity {
            observation_revision,
            activity,
        }) => {
            assert_eq!(observation_revision, 3);
            assert!(activity.is_none());
        }
        other => panic!("lag must reset to the oldest retained frame, got {other:?}"),
    }
    assert_eq!(
        feed.state_activity()
            .expect("latest observation")
            .observation_revision,
        u64::try_from(LIVE_FEED_FRAMES).unwrap() + 2
    );

    let parked = tokio::spawn(async move { parked.recv().await });
    cancellation.cancel();
    assert!(matches!(
        parked.await.expect("receiver task finishes"),
        Err(broadcast::error::RecvError::Closed)
    ));
    assert!(matches!(
        slow.try_recv(),
        Err(broadcast::error::TryRecvError::Closed)
    ));
}

#[tokio::test]
async fn state_receiver_close_wins_over_buffered_content_and_wakes_parked_readers() {
    let (events, receiver) = broadcast::channel(4);
    let closed = CancellationToken::new();
    events
        .send(ThreadLiveEvent::UnframedCommit { sequence: 1 })
        .unwrap();
    let mut buffered = StateReceiver::new(receiver, closed.clone());
    assert!(matches!(
        buffered.recv().await,
        Ok(ThreadLiveEvent::UnframedCommit { sequence: 1 })
    ));

    let mut parked = StateReceiver::new(events.subscribe(), closed.clone());
    let task = tokio::spawn(async move { parked.recv().await });
    let _ = events.send(ThreadLiveEvent::UnframedCommit { sequence: 2 });
    closed.cancel();
    assert!(matches!(
        task.await.expect("parked State receiver task"),
        Err(broadcast::error::RecvError::Closed)
    ));
    assert!(matches!(
        StateReceiver::new(events.subscribe(), closed).try_recv(),
        Err(broadcast::error::TryRecvError::Closed)
    ));
}

#[test]
fn publish_last_turn_advances_for_shorter_followup_and_ignores_stale_revisions() {
    use crate::{CompletedTurnState, Turn, TurnCompletion, TurnState};
    use tokio_util::sync::CancellationToken;

    let (_, progress) = watch::channel(Progress::default());
    let feed = ThreadLiveFeed::new(None, progress, CancellationToken::new());
    let turn1 = Arc::new(Turn {
        input_id: None,
        id: "turn-long-1".into(),
        thread_id: "child".into(),
        revision: 10,
        state: TurnState::Completed(CompletedTurnState::new(
            Some(100),
            110,
            TurnCompletion::Normal,
        )),
        updated_at: 110,
    });
    let turn2 = Arc::new(Turn {
        input_id: None,
        id: "turn-short-2".into(),
        thread_id: "child".into(),
        revision: 12,
        state: TurnState::Completed(CompletedTurnState::new(
            Some(111),
            112,
            TurnCompletion::Normal,
        )),
        updated_at: 112,
    });
    let stale = Arc::new(Turn {
        input_id: None,
        id: "turn-stale".into(),
        thread_id: "child".into(),
        revision: 9,
        state: TurnState::Completed(CompletedTurnState::new(
            Some(90),
            95,
            TurnCompletion::Normal,
        )),
        updated_at: 95,
    });

    feed.publish_last_turn(turn1);
    feed.publish_last_turn(stale);
    assert_eq!(
        feed.last_turn
            .borrow()
            .as_ref()
            .map(|t| (t.id.as_str(), t.revision)),
        Some(("turn-long-1", 10))
    );

    feed.publish_last_turn(turn2);
    assert_eq!(
        feed.last_turn
            .borrow()
            .as_ref()
            .map(|t| (t.id.as_str(), t.revision)),
        Some(("turn-short-2", 12))
    );
}
