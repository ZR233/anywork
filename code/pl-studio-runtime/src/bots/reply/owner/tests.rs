use crate::bots::InboundWorkOutcome;
use crate::bots::storage::{InboundClaim, MarkOutcome, WorkFinish};
use crate::bots::test_support::Fixture;
use anyhow::Result;
use std::time::Duration;

#[tokio::test]
async fn reply_resolution_wait_is_cancellable_and_mismatched_registration_never_dispatches()
-> Result<()> {
    let fixture = Fixture::new().await?;
    let creating = fixture.inbound("creating", false).await?;
    assert_eq!(
        fixture
            .managed
            .store
            .claim_inbound_work(
                &creating.bot_id,
                &creating.chat_id,
                &creating.message_id,
                "fixture-worker"
            )
            .await?,
        InboundClaim::Claimed
    );
    let lifecycle = fixture.host.lifecycle_lock().lock().await;
    let cancellation = fixture.bots.inner.reply_work.cancel.child_token();
    let reply = fixture.bots.dispatch_prompt(
        creating.clone(),
        "fixture-worker",
        &creating.creation_id,
        cancellation.clone(),
    );
    tokio::pin!(reply);
    assert!(futures::poll!(&mut reply).is_pending());
    cancellation.cancel();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(5), reply).await?,
        InboundWorkOutcome::Interrupted
    );
    drop(lifecycle);
    assert_eq!(
        fixture
            .managed
            .store
            .finish_inbound_work(
                &creating.bot_id,
                &creating.chat_id,
                &creating.message_id,
                "fixture-worker",
                WorkFinish::Interrupted
            )
            .await?,
        MarkOutcome::Applied
    );

    let bound = fixture.inbound("mismatch", true).await?;
    assert_eq!(
        fixture
            .managed
            .store
            .claim_inbound_work(
                &bound.bot_id,
                &bound.chat_id,
                &bound.message_id,
                "fixture-worker"
            )
            .await?,
        InboundClaim::Claimed
    );
    let outcome = fixture
        .bots
        .dispatch_prompt(
            bound.clone(),
            "fixture-worker",
            "different-thread",
            fixture.bots.inner.reply_work.cancel.child_token(),
        )
        .await;
    assert!(
        matches!(outcome, InboundWorkOutcome::NeedsAttention { diagnostic }
    if diagnostic.contains("registered reply owner"))
    );
    assert_eq!(
        fixture.host.runtime.bot_input_fact(
            &bound.creation_id,
            &format!(
                "bot:{}:{}:{}",
                bound.bot_id, bound.chat_id, bound.message_id
            ),
        )?,
        crate::bots::BotInputRead::Absent,
    );
    fixture
        .managed
        .store
        .finish_inbound_work(
            &bound.bot_id,
            &bound.chat_id,
            &bound.message_id,
            "fixture-worker",
            WorkFinish::Interrupted,
        )
        .await?;
    fixture.shutdown().await
}
