use std::time::Duration;

use anyhow::{Context, Result, ensure};
use tokio::sync::{mpsc, oneshot};

use super::*;
use crate::api::studio::handlers::chat::{BridgeConversationFeed, producer, tests::Environment};
use crate::api::studio::types::{BridgeConversationEvent, BridgeReadDemand};

mod live;
mod output_limit;
mod state;

fn managed(feed: ConversationFeed) -> Arc<ConversationOwner> {
    let owner = Arc::new(ConversationOwner::new(feed, CancellationToken::new()));
    owner.install_lifecycle(|_| {}).unwrap();
    owner
}

fn managed_state(feed: ConversationStateFeed) -> Arc<ConversationOwner> {
    let owner = Arc::new(ConversationOwner::new_state(feed, CancellationToken::new()));
    owner.install_lifecycle(|_| {}).unwrap();
    owner
}

async fn start_port(owner: &Arc<ConversationOwner>) -> mpsc::Receiver<BridgeConversationFrame> {
    let (tx, rx) = mpsc::channel(2);
    let task_owner = Arc::clone(owner);
    let mut slot = owner.producer.lock().await;
    slot.task = Some(tokio::spawn(async move {
        producer::run_into(task_owner, move |frame| tx.try_send(frame).is_ok()).await
    }));
    rx
}

async fn receive(
    rx: &mut mpsc::Receiver<BridgeConversationFrame>,
) -> Result<BridgeConversationFrame> {
    tokio::time::timeout(Duration::from_secs(5), rx.recv())
        .await?
        .context("port closed")
}

#[tokio::test]
async fn paused_producer_does_not_block_original_lease_queries_or_steal_read_close() -> Result<()> {
    let env = Environment::new().await?;
    let result = async {
        let owner = managed(env.feed().await?);
        let facade = BridgeConversationFeed {
            inner: Arc::clone(&owner),
        };
        let mut port = start_port(&owner).await;
        let (sequence, before) = loop {
            let frame = receive(&mut port).await?;
            match frame.event {
                BridgeConversationEvent::Chat { batch } => {
                    ensure!(batch.placement == crate::api::studio::types::BridgeChatPlacement::Set);
                    break (
                        frame.delivery_sequence,
                        batch.before.context("fixture needs older items")?,
                    );
                }
                BridgeConversationEvent::Activity { .. } => {
                    owner.acknowledge(&owner.subscription_id, frame.delivery_sequence)?;
                }
                event => anyhow::bail!("unexpected initial event: {event:?}"),
            }
        };
        ensure!(
            owner.native.try_lock().is_err(),
            "production pump must hold its native receiver"
        );
        let mut credit = Box::pin(owner.wait_credit());
        ensure!(
            futures::poll!(credit.as_mut()).is_pending(),
            "one unacknowledged batch must exhaust credit"
        );
        ensure!(owner.state.lock().unwrap().inflight_bytes > 0);
        ensure!(owner.acknowledge("another-subscription", sequence).is_err());
        ensure!(
            owner
                .acknowledge(&owner.subscription_id, sequence + 1)
                .is_err()
        );
        owner.acknowledge(&owner.subscription_id, sequence - 1)?;
        ensure!(
            futures::poll!(credit.as_mut()).is_pending(),
            "old ACK must not free the outstanding batch"
        );
        let demand = BridgeReadDemand {
            max_items: 2,
            max_bytes: 64 * 1024,
        };
        let page = tokio::time::timeout(
            Duration::from_secs(5),
            facade.load_older(before.clone(), demand),
        )
        .await??;
        ensure!(matches!(
            page.placement,
            crate::api::studio::types::BridgeChatPlacement::Prepend
        ));
        ensure!(!page.entries.is_empty());
        ensure!(
            port.try_recv().is_err(),
            "query must neither ACK nor publish another stream frame"
        );

        // Natural producer retirement owns only the feed. The private original read lease stays usable.
        owner.producer_cancel.cancel();
        ensure!(!credit.await);
        let terminal = receive(&mut port).await?;
        ensure!(terminal.delivery_sequence == sequence);
        ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
        ensure!(
            port.recv().await.is_none(),
            "terminal must be attempted only once"
        );
        let page = facade.load_older(before.clone(), demand).await?;
        ensure!(
            !page.entries.is_empty(),
            "producer exit must not close the facade's read lease"
        );
        facade.close().await?;
        ensure!(owner.is_settled());
        ensure!(owner.native.lock().await.is_none());
        ensure!(facade.load_older(before.clone(), demand).await.is_err());
        ensure!(
            owner
                .content()?
                .reader
                .load_older(&before, chat_demand())
                .await
                .is_err()
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}

fn chat_demand() -> pl_protocol::ReadDemand {
    pl_protocol::ReadDemand {
        max_items: 2,
        max_bytes: 64 * 1024,
    }
}

#[tokio::test]
async fn close_before_first_frame_uses_sequence_zero_and_joins_every_task() -> Result<()> {
    let env = Environment::new().await?;
    let result = async {
        let owner = managed(env.feed().await?);
        owner.producer_cancel.cancel();
        let mut port = start_port(&owner).await;
        let terminal = receive(&mut port).await?;
        ensure!(terminal.delivery_sequence == 0);
        ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
        ensure!(port.recv().await.is_none());
        owner.close().await?;
        ensure!(owner.is_settled());
        ensure!(owner.producer.lock().await.task.is_none());
        ensure!(owner.native.lock().await.is_none());
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn cancelled_close_wait_retains_join_and_producer_failure_still_closes_read() -> Result<()> {
    let env = Environment::new().await?;
    let result = async {
        let owner = managed(env.feed().await?);
        let (release, held) = oneshot::channel();
        owner.producer.lock().await.task = Some(tokio::spawn(async move {
            held.await.map_err(|_| closed())?;
            Ok(())
        }));
        let mut close = Box::pin(owner.close());
        ensure!(futures::poll!(close.as_mut()).is_pending());
        drop(close);
        let mut retry = Box::pin(owner.close());
        ensure!(
            futures::poll!(retry.as_mut()).is_pending(),
            "cancelling a waiter must not abandon the original join"
        );
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("producer was abandoned"))?;
        retry.await?;
        ensure!(owner.is_settled());

        let mut feed = env.feed().await?;
        let before = loop {
            if let Some(pl_studio_runtime::ConversationEvent::Chat { batch }) = feed.recv().await? {
                break batch.before.context("fixture needs older items")?;
            }
        };
        let failed = managed(feed);
        failed
            .content()?
            .reader
            .load_older(&before, chat_demand())
            .await?;
        failed.producer.lock().await.task = Some(tokio::spawn(async {
            panic!("injected producer panic");
        }));
        let diagnostic = failed
            .close()
            .await
            .expect_err("producer panic must propagate");
        ensure!(diagnostic.message.contains("producer"));
        ensure!(
            failed.native.lock().await.is_none(),
            "producer failure must not skip feed cleanup"
        );
        let read_error = failed
            .content()?
            .reader
            .load_older(&before, chat_demand())
            .await
            .expect_err("producer failure must not skip read cleanup");
        ensure!(
            BridgeError::from(read_error).code
                == crate::api::studio::types::BridgeErrorCode::Cancelled
        );
        ensure!(
            !failed.is_settled(),
            "failure must retain unresolved owner diagnostics"
        );
        ensure!(
            failed.close().await.unwrap_err() == diagnostic,
            "retry must retain the first failure"
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}
