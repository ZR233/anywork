use crate::bots::reply::ReplyIdentity;
use crate::bots::storage::InboundClaim;
use crate::bots::test_support::Fixture;
use anyhow::{Context, Result};
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement, TransactionTrait};
use std::time::Duration;

#[tokio::test]
async fn enqueue_reaps_finished_replies_before_trying_the_bounded_budget() -> Result<()> {
    let fixture = Fixture::new().await?;
    let mut inbound = fixture.inbound("budget", true).await?;
    let slots = &fixture.bots.inner.reply_work.slots;
    // Keep all but one permit occupied. The last permit is held by a real
    // dispatched reply until enqueue reaps its joined owner.
    let other_slots = slots.clone().try_acquire_many_owned(31)?;
    inbound.app_id = "cli_old_frozen_app".into();
    inbound.message_id = "budget-first".into();
    inbound.content_hash = "budget-hash-first".into();
    let config = fixture.managed.config.lock().await;
    fixture.managed.store.admit_inbound(inbound.clone()).await?;
    fixture.bots.enqueue_inbound(inbound.clone()).await?;
    assert_eq!(slots.available_permits(), 0);
    drop(config);

    inbound.message_id = "budget-next".into();
    inbound.content_hash = "budget-hash-next".into();
    fixture.managed.store.admit_inbound(inbound.clone()).await?;
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            match fixture.bots.enqueue_inbound(inbound.clone()).await {
                Err(error) if error.diagnostic().message == "bot reply budget is full" => {
                    tokio::task::yield_now().await;
                }
                result => return result,
            }
        }
    })
    .await
    .context("enqueue never recovered the finished reply's permit")??;
    let probe = fixture.ledger_probe().await?;
    let row = probe
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "SELECT status FROM inbound_work WHERE message_id='budget-first'",
        ))
        .await?
        .context("first reply's ledger row")?;
    assert_eq!(row.try_get::<String>("", "status")?, "needs_attention");
    let guard = fixture
        .bots
        .quiesce_archive_threads(&[inbound.creation_id])
        .await?;
    assert_eq!(slots.available_permits(), 1);
    drop(other_slots);
    assert_eq!(slots.available_permits(), 32);
    drop(guard);
    fixture.shutdown().await
}

#[tokio::test]
async fn cancelled_unstarted_finisher_retains_original_budget_and_ledger_retry() -> Result<()> {
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("unstarted", true).await?;
    let worker = "unstarted-worker";
    assert_eq!(
        fixture
            .managed
            .store
            .claim_inbound_work(
                &inbound.bot_id,
                &inbound.chat_id,
                &inbound.message_id,
                worker,
            )
            .await?,
        InboundClaim::Claimed,
    );
    let probe = fixture.ledger_probe().await?;
    let writer = probe.begin().await?;
    writer
        .execute_unprepared("UPDATE inbound_work SET updated_at=updated_at")
        .await?;
    let mut replies = fixture.bots.inner.reply_work.tasks.lock().await;
    let permit = fixture
        .bots
        .inner
        .reply_work
        .slots
        .clone()
        .acquire_owned()
        .await?;
    assert!(
        tokio::time::timeout(
            Duration::from_millis(50),
            replies.finish_unstarted(
                &fixture.bots,
                inbound.creation_id.clone(),
                ReplyIdentity::new(&inbound, worker),
                fixture.bots.inner.reply_work.cancel.child_token(),
                permit,
            ),
        )
        .await
        .is_err()
    );
    assert_eq!(
        fixture.bots.inner.reply_work.slots.available_permits(),
        31,
        "canceling a ledger wait must leave its owner and permit registered",
    );
    writer.rollback().await?;
    replies.retry_finishes(&fixture.bots, None).await?;
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 32);
    assert_eq!(
        fixture
            .managed
            .store
            .list_due_inbound(&inbound.bot_id)
            .await?,
        vec![inbound],
    );
    drop(replies);
    fixture.shutdown().await
}
