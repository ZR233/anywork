use super::*;

#[tokio::test]
async fn timeline_uses_original_credit_and_lock_free_read_lease() -> Result<()> {
    let env = Environment::new().await?;
    let result: Result<()> = async {
        let native = env
            .runtime
            .open_timeline_feed(
                &env.thread_id,
                pl_protocol::ReadDemand {
                    max_items: 1,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        let owner = Arc::new(ConversationOwner::timeline(
            native,
            CancellationToken::new(),
        ));
        owner.install_lifecycle(|_| {})?;
        let mut port = start_port(&owner).await;
        let frame = receive(&mut port).await?;
        let (sequence, before) = match frame.event {
            BridgeConversationEvent::Timeline { batch } => {
                ensure!(batch.presentation_version == pl_protocol::PRESENTATION_VERSION);
                ensure!(batch.placement == crate::api::studio::types::BridgeChatPlacement::Set);
                (
                    frame.delivery_sequence,
                    batch.before.context("fixture needs older display blocks")?,
                )
            }
            event => anyhow::bail!("GUI feed emitted non-timeline event: {event:?}"),
        };
        ensure!(owner.native.try_lock().is_err());
        let page = tokio::time::timeout(
            Duration::from_secs(5),
            owner
                .content()?
                .reader
                .load_timeline_older(&before, chat_demand()),
        )
        .await??;
        ensure!(page.placement == pl_protocol::ChatPlacement::Prepend);
        ensure!(!page.blocks.is_empty());
        ensure!(
            port.try_recv().is_err(),
            "read must not ACK the pending frame"
        );
        ensure!(owner.acknowledge("foreign", sequence).is_err());
        ensure!(
            owner
                .acknowledge(&owner.subscription_id, sequence + 1)
                .is_err()
        );
        owner.producer_cancel.cancel();
        let terminal = receive(&mut port).await?;
        ensure!(terminal.delivery_sequence == sequence);
        ensure!(matches!(terminal.event, BridgeConversationEvent::Closed));
        ensure!(port.recv().await.is_none());
        // Producer retirement must not steal the read owner's independent responsibility.
        owner
            .content()?
            .reader
            .load_timeline_older(&before, chat_demand())
            .await?;
        owner.close().await?;
        ensure!(owner.is_settled());
        ensure!(owner.native.lock().await.is_none());
        ensure!(
            owner
                .content()?
                .reader
                .load_timeline_older(&before, chat_demand())
                .await
                .is_err()
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}
