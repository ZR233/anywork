//! Real independent native feeds drive the shared production bridge producer.
use super::*;
use crate::api::studio::{
    handlers::chat::{BridgeConversationStateFeed, tests::MODEL},
    types::{
        BridgeErrorCode, BridgeThreadNotification, BridgeThreadSubscriptionUpdate, BridgeTurnState,
    },
};
use pl_provider_fixture::{Reply, responses_text};

#[tokio::test]
async fn content_without_ack_does_not_block_state_runtime_or_share_ack_credit() -> Result<()> {
    let env = Environment::with_followup(Some(Reply::Sse(responses_text(
        "Independent state completed.",
        "bridge-state-followup",
        MODEL,
    ))))
    .await?;
    let result = tokio::time::timeout(Duration::from_secs(15), async {
        let content = managed(env.feed().await?);
        let state = managed_state(
            env.runtime
                .open_conversation_state_feed(&env.thread_id)
                .await?,
        );
        ensure!(
            state.content().is_err(),
            "state must not own a content reader"
        );
        ensure!(content.subscription_id != state.subscription_id);
        let mut content_port = start_port(&content).await;
        let mut state_port = start_port(&state).await;
        let first_content = receive(&mut content_port).await?;
        ensure!(matches!(
            first_content.event,
            BridgeConversationEvent::Chat { .. }
        ));
        ensure!(first_content.delivery_sequence == 1);
        let first_state = receive(&mut state_port).await?;
        ensure!(first_state.thread_id == env.thread_id);
        ensure!(first_state.subscription_id == state.subscription_id);
        ensure!(first_state.delivery_sequence == 1);
        ensure!(matches!(
            first_state.event,
            BridgeConversationEvent::State { update }
                if matches!(*update, BridgeThreadSubscriptionUpdate::Snapshot { .. })
        ));

        // Neither another feed's identity nor a future prefix can release this feed's credit.
        ensure!(
            state
                .acknowledge(&content.subscription_id, 1)
                .unwrap_err()
                .code
                == BridgeErrorCode::InvalidArgument
        );
        ensure!(
            content
                .acknowledge(&state.subscription_id, 1)
                .unwrap_err()
                .code
                == BridgeErrorCode::InvalidArgument
        );
        ensure!(
            state
                .acknowledge(&state.subscription_id, 2)
                .unwrap_err()
                .code
                == BridgeErrorCode::InvalidArgument
        );
        let mut blocked = Box::pin(state.wait_credit());
        ensure!(futures::poll!(blocked.as_mut()).is_pending());
        state.acknowledge(&state.subscription_id, 0)?;
        ensure!(futures::poll!(blocked.as_mut()).is_pending());
        state.acknowledge(&state.subscription_id, 1)?;
        state.acknowledge(&state.subscription_id, 1)?;
        ensure!(blocked.await);
        let mut content_blocked = Box::pin(content.wait_credit());
        ensure!(futures::poll!(content_blocked.as_mut()).is_pending());
        ensure!(content_port.try_recv().is_err());

        env.submit_followup().await?;
        let mut sent = 1;
        let mut runtime_seen = false;
        loop {
            let frame = receive(&mut state_port).await?;
            ensure!(frame.subscription_id == state.subscription_id);
            ensure!(frame.thread_id == state.thread_id);
            ensure!(frame.delivery_sequence == sent + 1);
            sent = frame.delivery_sequence;
            let BridgeConversationEvent::State { update } = frame.event else {
                anyhow::bail!("state producer emitted non-State data");
            };
            let mut completed = false;
            if let BridgeThreadSubscriptionUpdate::Notification { notification } = *update {
                match notification.notification {
                    BridgeThreadNotification::ThreadRuntimeUpdated { .. } => runtime_seen = true,
                    BridgeThreadNotification::TurnCompleted { turn }
                        if turn.input_id.as_deref() == Some("input-bridge-live") =>
                    {
                        ensure!(matches!(turn.state, BridgeTurnState::Completed { .. }));
                        completed = true;
                    }
                    _ => {}
                }
            }
            if completed {
                ensure!(
                    runtime_seen,
                    "no runtime update crossed the blocked content feed"
                );
                break;
            }
            state.acknowledge(&state.subscription_id, sent)?;
        }
        ensure!(futures::poll!(content_blocked.as_mut()).is_pending());
        ensure!(
            content_port.try_recv().is_err(),
            "state ACK released content credit"
        );
        {
            let credit = content.state.lock().unwrap();
            ensure!(credit.sent == 1 && credit.acknowledged == 0);
        }
        // Both producers now wait for independent ACKs. Close must emit terminals and join
        // without acquiring credit or acknowledging either outstanding ordinary frame.
        let (content_close, state_close) = tokio::join!(content.close(), state.close());
        content_close?;
        state_close?;
        ensure!(!content_blocked.await);
        for (owner, port, sequence) in [
            (&content, &mut content_port, 1),
            (&state, &mut state_port, sent),
        ] {
            let terminal = receive(port).await?;
            ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
            ensure!(terminal.delivery_sequence == sequence);
            ensure!(port.recv().await.is_none());
            ensure!(owner.is_settled());
            ensure!(owner.native.lock().await.is_none());
            ensure!(owner.producer.lock().await.task.is_none());
        }
        Ok(())
    })
    .await
    .context("independent bridge feeds timed out")
    .and_then(|result| result);
    env.finish(result).await
}

#[tokio::test]
async fn state_close_before_listen_and_with_available_credit_retains_native_join() -> Result<()> {
    let env = Environment::new().await?;
    let result = async {
        let unopened = managed_state(
            env.runtime
                .open_conversation_state_feed(&env.thread_id)
                .await?,
        );
        let facade = BridgeConversationStateFeed {
            inner: Arc::clone(&unopened),
        };
        facade.close().await?;
        facade.close().await?;
        ensure!(unopened.is_settled());
        ensure!(unopened.native.lock().await.is_none());
        ensure!(unopened.producer.lock().await.task.is_none());
        ensure!(
            facade
                .acknowledge("wrong".into(), u64::MAX)
                .unwrap_err()
                .code
                == BridgeErrorCode::Cancelled
        );

        let idle = managed_state(
            env.runtime
                .open_conversation_state_feed(&env.thread_id)
                .await?,
        );
        let mut port = start_port(&idle).await;
        let first = receive(&mut port).await?;
        idle.acknowledge(&idle.subscription_id, first.delivery_sequence)?;
        ensure!(idle.wait_credit().await);
        tokio::time::timeout(Duration::from_secs(5), idle.close()).await??;
        ensure!(idle.is_settled());
        ensure!(idle.native.lock().await.is_none());
        ensure!(idle.producer.lock().await.task.is_none());
        Ok(())
    }
    .await;
    env.finish(result).await
}
