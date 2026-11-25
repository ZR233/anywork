use crate::bots::test_support::Fixture;
use anyhow::Result;
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement, TransactionTrait};
use std::time::Duration;

#[tokio::test]
async fn permanent_delete_bot_ledger_removes_only_the_bound_tree_and_retains_neighbor() -> Result<()>
{
    let fixture = Fixture::new().await?;
    let deleted = fixture.inbound("deleted", true).await?;
    let neighbor = fixture.inbound("neighbor", true).await?;
    fixture
        .host
        .runtime
        .delete_thread("delete-bot-tree".into(), deleted.creation_id.clone())
        .await?
        .expect("root deletion");
    assert!(
        fixture
            .bots
            .config_for_thread(&deleted.creation_id)
            .await?
            .is_none()
    );
    assert!(
        fixture
            .bots
            .config_for_thread(&neighbor.creation_id)
            .await?
            .is_some()
    );
    let due = fixture
        .managed
        .store
        .list_due_inbound(&deleted.bot_id)
        .await?;
    assert_eq!(due.len(), 1);
    assert_eq!(due[0], neighbor);
    let db = fixture.ledger_probe().await?;
    assert!(
        db.query_one_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT 1 FROM inbound_identities WHERE bot_id=? AND chat_id=? AND message_id=?",
            [
                deleted.bot_id.into(),
                deleted.chat_id.into(),
                deleted.message_id.into()
            ]
        ))
        .await?
        .is_none()
    );
    assert!(!fixture.bots.runtime_released());
    db.close().await?;
    fixture.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn idle_bound_bot_quiesces_without_releasing_runtime_and_keeps_frozen_inbound() -> Result<()>
{
    let fixture = Fixture::new().await?;
    let inbound = fixture.inbound("idle", true).await?;
    assert!(
        fixture
            .bots
            .config_for_thread(&inbound.creation_id)
            .await?
            .is_some()
    );
    assert!(!fixture.bots.runtime_released());
    let guard = fixture
        .bots
        .quiesce_archive_threads(std::slice::from_ref(&inbound.creation_id))
        .await?;
    assert!(!fixture.bots.runtime_released());
    assert!(fixture.bots.enqueue_inbound(inbound.clone()).await.is_err());
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 32);
    assert_eq!(
        fixture
            .managed
            .store
            .list_due_inbound(&inbound.bot_id)
            .await?,
        vec![inbound]
    );
    drop(guard);
    fixture.shutdown().await
}

#[tokio::test]
async fn quiesce_waits_for_real_finisher_and_retry_joins_original_without_canceling_neighbor()
-> Result<()> {
    let fixture = Fixture::new().await?;
    let target = fixture.inbound("target", false).await?;
    let neighbor = fixture.inbound("neighbor", false).await?;
    let lifecycle = fixture.host.lifecycle_lock().lock().await;
    fixture.bots.enqueue_inbound(target.clone()).await?;
    fixture.bots.enqueue_inbound(neighbor.clone()).await?;
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 30);

    // Real ledger writes cannot ACK while this independent SQLite writer holds
    // the lock. Canceling the archive waiter must not detach its reply owner.
    let probe = fixture.ledger_probe().await?;
    let writer = probe.begin().await?;
    writer
        .execute_unprepared("UPDATE inbound_work SET updated_at=updated_at")
        .await?;
    assert!(
        tokio::time::timeout(
            Duration::from_millis(50),
            fixture
                .bots
                .quiesce_archive_threads(std::slice::from_ref(&target.creation_id))
        )
        .await
        .is_err()
    );
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 30);
    assert!(!fixture.bots.inner.reply_work.cancel.is_cancelled());
    writer.rollback().await?;
    let guard = tokio::time::timeout(
        Duration::from_secs(5),
        fixture
            .bots
            .quiesce_archive_threads(std::slice::from_ref(&target.creation_id)),
    )
    .await??;
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 31);
    assert_eq!(
        fixture
            .managed
            .store
            .list_due_inbound(&target.bot_id)
            .await?,
        vec![target.clone()],
        "the neighbor still owns its claim and producer"
    );
    drop(guard);
    let neighbor_guard = tokio::time::timeout(
        Duration::from_secs(5),
        fixture
            .bots
            .quiesce_archive_threads(std::slice::from_ref(&neighbor.creation_id)),
    )
    .await??;
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 32);
    assert!(!fixture.bots.inner.reply_work.cancel.is_cancelled());
    drop(neighbor_guard);
    drop(lifecycle);
    fixture.shutdown().await
}

#[tokio::test]
async fn archived_catalog_rejects_enqueue_without_changing_platform_identity() -> Result<()> {
    let fixture = Fixture::new().await?;
    let archived = fixture.inbound("archived", true).await?;
    fixture
        .host
        .runtime
        .archive_thread("archive-bound-fixture".into(), archived.creation_id.clone())
        .await?
        .expect("bound bot Thread is archived");
    assert!(
        fixture
            .bots
            .enqueue_inbound(archived.clone())
            .await
            .is_err()
    );
    assert_eq!(fixture.bots.inner.reply_work.slots.available_permits(), 32);
    let due = fixture
        .managed
        .store
        .list_due_inbound(&archived.bot_id)
        .await?;
    assert_eq!(due, vec![archived]);
    fixture.shutdown().await
}
