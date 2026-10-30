//! Real inbound registration and reply consumers, on isolated Studio/bot stores.
use super::*;
use crate::bots::InboundWorkOutcome;
use crate::bots::storage::{MarkOutcome, WorkFinish};
use crate::studio::bot_archive_test_host::BotArchiveTestHost;
use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
use anyhow::Result;
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement, TransactionTrait,
};
use std::time::Duration;

pub(in crate::bots) struct Fixture {
    pub(in crate::bots) host: BotArchiveTestHost,
    pub(in crate::bots) bots: BotRuntime,
    managed: Arc<ManagedBot>,
    workspace_id: String,
    _temp: tempfile::TempDir,
}

impl Fixture {
    pub(in crate::bots) async fn new() -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let host = BotArchiveTestHost::new(&temp.path().join("home")).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let project = host.runtime.open_project(&workspace).await?;
        let bots = host.bots();
        // Keep the periodic recovery worker out of controlled interleavings.
        // All tested recovery calls below use the real enqueue implementation.
        if let Some(recovery) = bots.inner.recovery.lock().await.take() {
            recovery.abort();
            assert!(recovery.await.unwrap_err().is_cancelled());
        }
        host.runtime
            .save_bot(SaveBotRequest {
                operation_id: "archive-fixture-save".into(),
                bot_id: Some("archive-fixture".into()),
                expected_config_revision: 0,
                name: "Archive fixture".into(),
                workspace_id: project.id.clone(),
                app_id: "cli_archive_fixture".into(),
                secret: BotSecretUpdate::Clear,
                enabled: false,
                tools_enabled: false,
                model_route: None,
            })
            .await?;
        let managed = bots.managed("archive-fixture").await?;
        Ok(Self {
            host,
            bots,
            managed,
            workspace_id: project.id,
            _temp: temp,
        })
    }

    pub(in crate::bots) async fn inbound(
        &self,
        chat_id: &str,
        bound: bool,
    ) -> Result<FrozenInbound> {
        self.inbound_with_attachments(chat_id, bound, Vec::new())
            .await
    }

    pub(in crate::bots) async fn inbound_with_attachments(
        &self,
        chat_id: &str,
        bound: bool,
        attachments: Vec<crate::bots::inbound::InboundAttachment>,
    ) -> Result<FrozenInbound> {
        let creation_id = format!("archive-thread-{chat_id}");
        self.managed
            .store
            .claim_thread_binding(chat_id, &creation_id, &self.workspace_id)
            .await?;
        if bound {
            let thread = self
                .host
                .runtime
                .create_thread_with_id(creation_id.clone(), &self.workspace_id, "Archive")
                .await?;
            self.managed
                .store
                .bind_thread(chat_id, &thread.id, &creation_id, &self.workspace_id)
                .await?;
        }
        let projection = self
            .managed
            .store
            .binding_for_chat(chat_id, "archive-fixture", &self.workspace_id)
            .await?;
        let inbound = FrozenInbound {
            bot_id: "archive-fixture".into(),
            message_id: format!("message-{chat_id}"),
            chat_id: chat_id.into(),
            content_hash: format!("hash-{chat_id}"),
            text: format!("original frozen text for {chat_id}"),
            attachments,
            open_id: "fixture-user".into(),
            chat_kind: "direct".into(),
            app_id: "cli_archive_fixture".into(),
            workspace_id: self.workspace_id.clone(),
            creation_id,
            binding_revision: projection.revision,
            watch_input: String::new(),
        };
        assert!(matches!(
            self.managed.store.admit_inbound(inbound.clone()).await?,
            InboundAdmit::Fresh(_)
        ));
        Ok(inbound)
    }

    pub(in crate::bots) async fn ledger_probe(&self) -> Result<DatabaseConnection> {
        let path = self
            .bots
            .inner
            .paths
            .bot_dir("archive-fixture")
            .join("state.sqlite");
        Ok(Database::connect(
            sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
        )
        .await?)
    }

    pub(in crate::bots) async fn shutdown(&self) -> Result<()> {
        self.host.runtime.shutdown_runtime().await?;
        Ok(())
    }

    pub(in crate::bots) async fn enqueue(&self, inbound: FrozenInbound) -> Result<()> {
        Ok(self.bots.enqueue_inbound(inbound).await?)
    }
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
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
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
async fn enqueue_reaps_finished_replies_before_trying_the_bounded_budget() -> Result<()> {
    let fixture = Fixture::new().await?;
    let mut inbound = fixture.inbound("budget", true).await?;
    // A changed app is a real dispatch terminal path before any network work.
    // Hold its config read so all 32 owners are registered before any finish.
    inbound.app_id = "cli_old_frozen_app".into();
    let config = fixture.managed.config.lock().await;
    for index in 0..32 {
        inbound.message_id = format!("budget-{index}");
        inbound.content_hash = format!("budget-hash-{index}");
        fixture.managed.store.admit_inbound(inbound.clone()).await?;
        fixture.bots.enqueue_inbound(inbound.clone()).await?;
    }
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 0);
    drop(config);
    let probe = fixture.ledger_probe().await?;
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            let finished: i64 = probe
                .query_one_raw(Statement::from_string(
                    DatabaseBackend::Sqlite,
                    "SELECT COUNT(*) AS n FROM inbound_work WHERE status='needs_attention'",
                ))
                .await?
                .expect("count row")
                .try_get("", "n")?;
            if finished == 32 {
                break;
            }
            tokio::task::yield_now().await;
        }
        anyhow::Ok(())
    })
    .await??;
    // Ledger ACK precedes task return. Give the same owned tasks their final
    // poll; permits intentionally remain held until enqueue observes joins.
    tokio::task::yield_now().await;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 0);
    inbound.message_id = "budget-next".into();
    inbound.content_hash = "budget-hash-next".into();
    fixture.managed.store.admit_inbound(inbound.clone()).await?;
    fixture.bots.enqueue_inbound(inbound.clone()).await?;
    let guard = fixture
        .bots
        .quiesce_archive_threads(&[inbound.creation_id])
        .await?;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
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
    let mut replies = fixture.bots.inner.replies.lock().await;
    let permit = fixture
        .bots
        .inner
        .reply_slots
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
                fixture.bots.inner.reply_cancel.child_token(),
                permit,
            ),
        )
        .await
        .is_err()
    );
    assert_eq!(
        fixture.bots.inner.reply_slots.available_permits(),
        31,
        "canceling a ledger wait must leave its owner and permit registered",
    );
    writer.rollback().await?;
    replies.retry_finishes(&fixture.bots, None).await?;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
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

#[tokio::test]
async fn quiesce_waits_for_real_finisher_and_retry_joins_original_without_canceling_neighbor()
-> Result<()> {
    let fixture = Fixture::new().await?;
    let target = fixture.inbound("target", false).await?;
    let neighbor = fixture.inbound("neighbor", false).await?;
    let lifecycle = fixture.host.lifecycle_lock().lock().await;
    fixture.bots.enqueue_inbound(target.clone()).await?;
    fixture.bots.enqueue_inbound(neighbor.clone()).await?;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 30);

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
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 30);
    assert!(!fixture.bots.inner.reply_cancel.is_cancelled());
    writer.rollback().await?;
    let guard = tokio::time::timeout(
        Duration::from_secs(5),
        fixture
            .bots
            .quiesce_archive_threads(std::slice::from_ref(&target.creation_id)),
    )
    .await??;
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 31);
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
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
    assert!(!fixture.bots.inner.reply_cancel.is_cancelled());
    drop(neighbor_guard);
    drop(lifecycle);
    fixture.shutdown().await
}

#[tokio::test]
async fn durable_seal_and_archived_catalog_reject_actual_enqueue_without_changing_identity()
-> Result<()> {
    let fixture = Fixture::new().await?;
    let sealed = fixture.inbound("sealed", true).await?;
    let archived = fixture.inbound("archived", true).await?;
    fixture.host.seal_thread(&sealed.creation_id).await?;
    assert!(fixture.bots.enqueue_inbound(sealed.clone()).await.is_err());
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
    assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
    let due = fixture
        .managed
        .store
        .list_due_inbound(&sealed.bot_id)
        .await?;
    assert_eq!(due.len(), 2);
    assert!(due.contains(&sealed));
    assert!(due.contains(&archived));
    fixture.shutdown().await
}

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
    let cancellation = fixture.bots.inner.reply_cancel.child_token();
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
            fixture.bots.inner.reply_cancel.child_token(),
        )
        .await;
    assert!(
        matches!(outcome, InboundWorkOutcome::NeedsAttention { diagnostic }
        if diagnostic.contains("registered reply owner"))
    );
    assert!(
        fixture
            .host
            .runtime
            .bot_input_fact(
                &bound.creation_id,
                &format!(
                    "bot:{}:{}:{}",
                    bound.bot_id, bound.chat_id, bound.message_id
                ),
            )
            .await?
            .eq(&crate::bots::BotInputRead::Absent)
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
