//! 生命周期受应用观察作用域约束的类型化工厂。

use pl_lifecycle::ScopeHandle;
use pl_studio_runtime::StudioRuntime;

use crate::api::studio::types::BridgeError;

pub(crate) struct BridgeObservationFactory {
    pub(crate) source: StudioRuntime,
    pub(crate) scope: ScopeHandle<BridgeError>,
}

impl BridgeObservationFactory {
    pub(crate) fn new(source: StudioRuntime, scope: ScopeHandle<BridgeError>) -> Self {
        Self { source, scope }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    use anyhow::{Context, Result, ensure};
    use futures::poll;
    use pl_lifecycle::ScopeOwner;

    use crate::api::studio::{
        accounts::types::BridgeAccountObservationTarget,
        directory::types::{
            BridgeThreadDirectoryFilter, BridgeThreadDirectoryQuery, BridgeThreadDirectoryWindow,
        },
        handlers::chat::tests::Environment,
        types::{
            BridgeChatClassFilter, BridgeChatScope, BridgeErrorCode, BridgeProductTopic,
            BridgeReadDemand,
        },
    };

    #[tokio::test]
    async fn real_factories_share_shutdown_without_stopping_business_runtime() -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let scope = ScopeOwner::new("bridge", tokio::runtime::Handle::current());
            let factory = BridgeObservationFactory::new(env.runtime.clone(), scope.handle());
            let account = factory
                .open_account(BridgeAccountObservationTarget::Summaries)
                .await?;
            let directory = factory
                .open_threads(
                    BridgeThreadDirectoryQuery {
                        workspace_id: None,
                        search: None,
                        archived: false,
                        filter: BridgeThreadDirectoryFilter::All,
                        thread_ids: None,
                        excluded_thread_ids: Vec::new(),
                    },
                    BridgeThreadDirectoryWindow {
                        before: None,
                        limit: 20,
                    },
                )
                .await?;
            let metadata = factory.open_thread(env.thread_id.clone()).await?;
            let statistics = factory.open_statistics().await?;
            let product = factory
                .open_product_topic(BridgeProductTopic::Updater)
                .await?;
            let demand = BridgeReadDemand {
                max_items: 2,
                max_bytes: 64 * 1024,
            };
            let conversation = factory
                .open_conversation(
                    env.thread_id.clone(),
                    BridgeChatScope {
                        query_class: BridgeChatClassFilter::All,
                        parent_id: None,
                    },
                    demand,
                )
                .await?;
            let state = factory
                .open_conversation_state(env.thread_id.clone())
                .await?;
            let timeline = factory
                .open_timeline(env.thread_id.clone(), 6, 1, demand)
                .await?;

            ensure!(account.next().await?.is_some());
            ensure!(directory.next().await?.is_some());
            ensure!(metadata.next().await?.is_some());
            let mut account_next = Box::pin(account.next());
            let mut directory_next = Box::pin(directory.next());
            ensure!(poll!(account_next.as_mut()).is_pending());
            ensure!(poll!(directory_next.as_mut()).is_pending());
            ensure!(account.next().await.unwrap_err().code == BridgeErrorCode::Busy);
            ensure!(directory.next().await.unwrap_err().code == BridgeErrorCode::Busy);

            scope.request_close();
            let rejected = match factory
                .open_account(BridgeAccountObservationTarget::Summaries)
                .await
            {
                Err(error) => error,
                Ok(_) => anyhow::bail!("a closed scope accepted another account observation"),
            };
            ensure!(rejected.code == BridgeErrorCode::RuntimeStopped);
            ensure!(account_next.await?.is_none());
            ensure!(directory_next.await?.is_none());
            let report = scope
                .close(tokio::time::Instant::now() + Duration::from_secs(10))
                .await;
            ensure!(report.is_clean(), "scope did not close: {report:?}");
            account.close().await?;
            directory.close().await?;
            metadata.close().await?;
            statistics.close().await?;
            product.cancel().await?;
            conversation.close().await?;
            state.close().await?;
            timeline.close().await?;
            ensure!(
                env.runtime.runtime_snapshot().await?.state.kind()
                    == pl_studio_runtime::StudioRuntimeStateKind::Ready
            );
            Ok(())
        }
        .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn closing_bridge_observations_keeps_admitted_execution_and_persistence() -> Result<()> {
        use pl_provider_fixture::{ReplyStage, responses_text_chunks};
        use pl_studio_runtime::{
            ChatAtomKind, ChatScope, ReadDemand, ThreadNotification, ThreadSubscriptionUpdate,
            TurnState,
        };
        use pl_studio_runtime::{
            ConversationEvent, StudioHostKind, StudioRuntime, StudioRuntimeOptions,
        };

        let stage = ReplyStage::new();
        let frames = responses_text_chunks(
            &["execution continues after observation closes"],
            "bridge-observation-close",
            crate::api::studio::handlers::chat::tests::MODEL,
        );
        let reply = stage.gated(frames[..3].to_vec(), frames[3..].to_vec());
        let mut env = Environment::with_followup(Some(reply)).await?;
        let result = tokio::time::timeout(Duration::from_secs(30), async {
            let scope = ScopeOwner::new("bridge", tokio::runtime::Handle::current());
            let factory = BridgeObservationFactory::new(env.runtime.clone(), scope.handle());
            let topic = factory
                .open_product_topic(BridgeProductTopic::Updater)
                .await?;
            let bridge_state = factory
                .open_conversation_state(env.thread_id.clone())
                .await?;
            // 独立状态读取只用于核对原业务执行，不属于待关闭的桥接作用域。
            let mut state = env
                .runtime
                .open_conversation_state_feed(&env.thread_id)
                .await?;
            env.submit_followup().await?;
            stage.wait_reached().await;
            let before = env.runtime.thread_snapshot(&env.thread_id).await?;
            let active = before.active_turn.context("admitted turn")?;
            ensure!(active.input_id.as_deref() == Some("input-bridge-live"));
            ensure!(!active.state.is_terminal());

            scope.request_close();
            let report = scope
                .close(tokio::time::Instant::now() + Duration::from_secs(10))
                .await;
            ensure!(report.is_clean(), "bridge scope did not close: {report:?}");
            topic.cancel().await?;
            bridge_state.close().await?;
            let after = env.runtime.thread_snapshot(&env.thread_id).await?;
            let still_running = after.active_turn.context("original turn remains active")?;
            ensure!(still_running.id == active.id && !still_running.state.is_terminal());

            let title = "观察关闭后仍可保存";
            env.runtime
                .rename_thread(
                    "observer-close-rename".into(),
                    env.thread_id.clone(),
                    title.into(),
                )
                .await?;
            stage.release();
            let completed_id = loop {
                let update = state.recv().await?.context("state feed ended")?;
                let turn = match update {
                    ThreadSubscriptionUpdate::Snapshot { snapshot, .. } => snapshot.active_turn,
                    ThreadSubscriptionUpdate::Notification { notification } => {
                        match notification.notification {
                            ThreadNotification::TurnCompleted { turn } => Some(turn),
                            _ => None,
                        }
                    }
                };
                if let Some(turn) = turn
                    && turn.id == active.id
                    && turn.state.is_terminal()
                {
                    ensure!(matches!(turn.state, TurnState::Completed(_)));
                    break turn.id;
                }
            };
            state.close().await?;
            env.runtime
                .synchronize_thread_observation(&env.thread_id)
                .await?;
            drop(factory);
            env.runtime.shutdown_runtime().await?;
            env.runtime = StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(env.home_path()),
                host: StudioHostKind::Test,
                ..StudioRuntimeOptions::desktop()
            })
            .await?;
            ensure!(env.runtime.read_thread(&env.thread_id).await?.title == title);
            let mut feed = env
                .runtime
                .open_conversation_feed(
                    &env.thread_id,
                    ChatScope::conversation(None),
                    ReadDemand {
                        max_items: 100,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?;
            let batch = loop {
                match feed.recv().await?.context("reopened conversation ended")? {
                    ConversationEvent::Chat { batch } => break batch,
                    ConversationEvent::Activity { .. } => {}
                }
            };
            ensure!(
                batch.entries.iter().any(|entry| {
                    entry.atom.turn_id.as_deref() == Some(completed_id.as_str())
                        && entry.atom.kind == ChatAtomKind::Text
                }),
                "completed turn was not recovered from durable history"
            );
            feed.reader().close().await?;
            feed.close().await?;
            Ok(())
        })
        .await
        .context("bridge observation lifecycle exceeded its test budget")
        .and_then(|result| result);
        stage.release();
        env.finish(result).await
    }
}
