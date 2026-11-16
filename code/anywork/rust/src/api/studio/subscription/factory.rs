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

    use anyhow::{Result, ensure};
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
}
