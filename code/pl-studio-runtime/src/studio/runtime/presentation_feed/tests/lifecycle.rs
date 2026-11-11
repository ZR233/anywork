use super::{production::timeline, production::work_reference, *};
use crate::{
    runtime_test_support::Environment,
    studio::runtime::conversation_feed::tests::completed_runs::{Harness, start},
};
use anyhow::Context;
use futures::poll;
use pl_protocol::DisplayMemberWindow;
use std::task::Poll;

#[tokio::test]
async fn parked_feed_and_member_receives_do_not_block_queries_and_close_only_their_observation()
-> Result<()> {
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        h.effect(vec![start("reasoning", true)], vec![]).await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, demand(1))
            .await?;
        let initial = timeline(&mut feed).await?;
        let reference = work_reference(&initial.live.context("live Work")?)?;
        let mut state = env
            .runtime
            .open_conversation_state_feed(&h.thread.id)
            .await?;
        assert!(matches!(
            state.recv().await?,
            Some(pl_protocol::ThreadSubscriptionUpdate::Snapshot { .. })
        ));
        state.close().await?;
        let reader = feed.reader().clone();
        let feed_cancel = feed.cancellation_token();
        {
            let receiving = feed.receive();
            tokio::pin!(receiving);
            assert!(matches!(poll!(&mut receiving), Poll::Pending));
            reader.read_business_refs().await?;
            let mut members = reader
                .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(1))
                .await?;
            let first = members
                .next()
                .await?
                .context("member query while feed waits")?;
            assert_eq!(first.entries.len(), 1);
            let cancel = members.cancellation_token();
            {
                let next = members.next();
                tokio::pin!(next);
                assert!(matches!(poll!(&mut next), Poll::Pending));
                reader.read_business_refs().await?;
                cancel.cancel();
                assert!(matches!(
                    next.await
                        .expect_err("local member close")
                        .downcast_ref::<ChatError>(),
                    Some(ChatError::Cancelled)
                ));
            }
            members.close().await?;
            reader.read_business_refs().await?;
            feed_cancel.cancel();
            assert!(matches!(
                receiving
                    .await
                    .expect_err("local feed close")
                    .downcast_ref::<ChatError>(),
                Some(ChatError::Cancelled)
            ));
        }
        feed.request_close();
        feed.close().await?;
        reader.read_business_refs().await?;
        let mut independent = reader
            .open_display_members(reference, DisplayMemberWindow::Latest, demand(1))
            .await?;
        assert_eq!(
            independent
                .next()
                .await?
                .context("reader survives producer close")?
                .entries
                .len(),
            1
        );
        // Only the outer full owner closes this independent qualification.
        reader.request_close();
        reader.close().await?;
        assert!(independent.next().await.is_err());
        independent.close().await?;
        assert!(reader.read_business_refs().await.is_err());
        Ok(())
    }
    .await;
    env.finish(result).await
}
