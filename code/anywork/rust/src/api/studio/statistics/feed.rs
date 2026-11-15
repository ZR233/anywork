//! FRB feed and immutable read-scope handles.

use std::sync::atomic::{AtomicBool, Ordering};

use tokio::sync::{Mutex, mpsc};
use tokio_util::sync::CancellationToken;

use super::convert::{
    bridge_effort_page, bridge_header, bridge_history_page, bridge_summary_page, statistics_error,
    statistics_sink_stopped,
};
use super::types::{
    BridgeStatisticsEffortPage, BridgeStatisticsFeedEvent, BridgeStatisticsFeedHeader,
    BridgeStatisticsHistoryPage, BridgeStatisticsScopeIdentity, BridgeStatisticsSummaryPage,
};
use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::subscription::{
    close_failures::CloseFailures,
    error::{close_error, open_error},
    factory::BridgeObservationFactory,
    send_or_cancel,
    task::OwnedTaskSlot,
};
use crate::api::studio::types::BridgeError;
use crate::frb_generated::StreamSink;
use pl_lifecycle::{Managed, ManagedResource};
use pl_studio_statistics::{StatisticsFeed, StatisticsReadScope};

/// Opens one independent latest-value statistics feed from the canonical runtime owner.
pub async fn open_statistics_feed() -> Result<BridgeStatisticsFeed, BridgeError> {
    let bridge = active_bridge().await?;
    bridge.observation_factory.open_statistics().await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_statistics(&self) -> Result<BridgeStatisticsFeed, BridgeError> {
        let source = self.source.clone();
        let inner = self
            .scope
            .open("statisticsFeeds", move |shutdown| async move {
                Ok(BridgeStatisticsFeedInner {
                    feed: source.open_statistics_feed(),
                    shutdown,
                    close_requested: AtomicBool::new(false),
                    events_started: AtomicBool::new(false),
                    producer_cancellation: CancellationToken::new(),
                    event_start: Mutex::new(()),
                    producer: Mutex::new(OwnedTaskSlot::default()),
                    sink: Mutex::new(OwnedTaskSlot::default()),
                    terminal_failures: std::sync::Mutex::new(CloseFailures::default()),
                })
            })
            .await
            .map_err(open_error)?;
        Ok(BridgeStatisticsFeed { inner })
    }
}

/// Managed opaque feed handle. The observation scope retains it until close is confirmed.
pub struct BridgeStatisticsFeed {
    inner: Managed<BridgeStatisticsFeedInner>,
}

pub(crate) struct BridgeStatisticsFeedInner {
    feed: StatisticsFeed,
    shutdown: CancellationToken,
    close_requested: AtomicBool,
    events_started: AtomicBool,
    producer_cancellation: CancellationToken,
    event_start: Mutex<()>,
    producer: Mutex<OwnedTaskSlot>,
    sink: Mutex<OwnedTaskSlot>,
    terminal_failures: std::sync::Mutex<CloseFailures>,
}

impl ManagedResource for BridgeStatisticsFeedInner {
    type Error = BridgeError;

    fn request_close(&self) {
        if self.close_requested.swap(true, Ordering::AcqRel) {
            return;
        }
        self.producer_cancellation.cancel();
        self.feed.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        // Serialize stream creation against close. Once this gate is passed, no new task may be
        // installed after the close path has inspected and joined the existing owners.
        let event_start = self.event_start.lock().await;
        drop(event_start);
        let (feed, producer, sink) = tokio::join!(
            self.feed.close(),
            async {
                self.producer
                    .lock()
                    .await
                    .join("statistics producer task failed")
                    .await
            },
            async {
                self.sink
                    .lock()
                    .await
                    .join("statistics sink task failed")
                    .await
            },
        );
        let mut failures = self
            .terminal_failures
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        if let Err(error) = feed {
            let error = statistics_error(error);
            if !error.retryable {
                self.terminal_failures
                    .lock()
                    .unwrap_or_else(|error| error.into_inner())
                    .record("feed", error.clone());
            }
            failures.record("feed", error);
        }
        if let Err(error) = producer {
            failures.record("producer", error);
        }
        if let Err(error) = sink {
            failures.record("sink", error);
        }
        failures.outcome().map_or(Ok(()), Err)
    }
}

impl BridgeStatisticsFeed {
    /// Opens the ordered typed push stream for this feed. Its producer and sink remain owned by
    /// the observation scope until close confirms that both tasks have stopped.
    pub async fn events(
        &self,
        sink: StreamSink<BridgeStatisticsFeedEvent>,
    ) -> Result<(), BridgeError> {
        let inner = self.inner.get();
        let _event_start = inner.event_start.lock().await;
        if inner.close_requested.load(Ordering::Acquire) || inner.shutdown.is_cancelled() {
            self.inner.request_close();
            return Err(BridgeError::runtime_stopped());
        }
        if inner.events_started.swap(true, Ordering::AcqRel) {
            return Err(BridgeError::invalid_argument(
                "statistics event stream can only be opened once",
            ));
        }

        let (sender, mut receiver) = mpsc::channel(1);
        let feed = inner.feed.clone();
        let shutdown = inner.shutdown.clone();
        let cancellation = inner.producer_cancellation.clone();
        let sink_feed = feed.clone();
        let sink_cancellation = cancellation.clone();
        let sink_task = tokio::spawn(async move {
            while let Some(event) = receiver.recv().await {
                if sink.add(event).is_err() {
                    sink_cancellation.cancel();
                    sink_feed.request_close();
                    return Err(statistics_sink_stopped());
                }
            }
            Ok(())
        });

        let producer_task = tokio::spawn(async move {
            let mut baseline = true;
            loop {
                let next = tokio::select! {
                    _ = cancellation.cancelled() => None,
                    _ = shutdown.cancelled() => {
                        feed.request_close();
                        cancellation.cancel();
                        None
                    }
                    result = feed.next() => match result {
                        Ok(header) => header,
                        Err(error) => {
                            let event = BridgeStatisticsFeedEvent::Failure {
                                error: statistics_error(error),
                            };
                            if !send_or_cancel(&cancellation, &sender, event).await && !cancellation.is_cancelled() {
                                return Err(statistics_sink_stopped());
                            }
                            return Ok(());
                        }
                    }
                };
                let Some(header) = next else {
                    let _ =
                        send_or_cancel(&cancellation, &sender, BridgeStatisticsFeedEvent::Closed)
                            .await;
                    return Ok(());
                };
                let event = if baseline {
                    baseline = false;
                    BridgeStatisticsFeedEvent::Baseline {
                        publication: bridge_header(header),
                    }
                } else {
                    BridgeStatisticsFeedEvent::Data {
                        publication: bridge_header(header),
                    }
                };
                if !send_or_cancel(&cancellation, &sender, event).await {
                    return if cancellation.is_cancelled() {
                        Ok(())
                    } else {
                        Err(statistics_sink_stopped())
                    };
                }
            }
        });

        inner.sink.lock().await.task = Some(sink_task);
        inner.producer.lock().await.task = Some(producer_task);
        Ok(())
    }

    /// Opens a scope fixed to a publication previously returned by this feed.
    pub fn open_scope(
        &self,
        header: BridgeStatisticsFeedHeader,
    ) -> Result<BridgeStatisticsReadScope, BridgeError> {
        if self.inner.get().shutdown.is_cancelled() {
            self.inner.request_close();
            return Err(BridgeError::runtime_stopped());
        }
        let scope = self
            .inner
            .get()
            .feed
            .open_scope(
                &header.owner_epoch,
                &header.feed_id,
                header.delivery_sequence,
            )
            .map_err(statistics_error)?;
        Ok(BridgeStatisticsReadScope { scope })
    }

    /// Confirms the next contiguous delivery prefix; repeated old ACKs are idempotent.
    pub fn acknowledge(&self, delivery_sequence: u64) -> Result<(), BridgeError> {
        self.inner
            .get()
            .feed
            .acknowledge(delivery_sequence)
            .map_err(statistics_error)
    }

    /// Synchronously seals this feed before asynchronous close/join begins.
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    /// Seals admission, cancels waits, joins in-flight calls and scopes, then releases the managed
    /// owner. A failed/abandoned wait leaves the original feed available for retry.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.retry_close().await.map_err(close_error)
    }
}

/// Opaque immutable publication scope; page methods never look up a newer publication.
pub struct BridgeStatisticsReadScope {
    scope: StatisticsReadScope,
}

impl BridgeStatisticsReadScope {
    pub fn identity(&self) -> Result<BridgeStatisticsScopeIdentity, BridgeError> {
        Ok(BridgeStatisticsScopeIdentity {
            owner_epoch: self.scope.owner_epoch(),
            feed_id: self.scope.feed_id().map_err(statistics_error)?,
            scope_id: self.scope.scope_id().to_owned(),
            publication_revision: self.scope.publication_revision(),
        })
    }

    pub fn read_summaries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeStatisticsSummaryPage, BridgeError> {
        self.scope
            .read_summaries(offset, limit)
            .map(bridge_summary_page)
            .map_err(statistics_error)
    }

    pub fn read_history(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeStatisticsHistoryPage, BridgeError> {
        self.scope
            .read_history(offset, limit)
            .map(bridge_history_page)
            .map_err(statistics_error)
    }

    pub fn read_efforts(
        &self,
        summary_index: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeStatisticsEffortPage, BridgeError> {
        self.scope
            .read_efforts(summary_index, offset, limit)
            .map(bridge_effort_page)
            .map_err(statistics_error)
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        self.scope.close().await.map_err(statistics_error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::{Result, ensure};
    use pl_lifecycle::ScopeOwner;
    use std::time::Duration;

    use crate::api::studio::handlers::chat::tests::Environment;

    #[tokio::test]
    async fn producer_panic_is_retained_after_join_and_native_feed_still_closes() -> Result<()> {
        let env = Environment::new().await?;
        let result = async {
            let scope = ScopeOwner::new("bridge", tokio::runtime::Handle::current());
            let factory = BridgeObservationFactory::new(env.runtime.clone(), scope.handle());
            let feed = factory.open_statistics().await?;
            feed.inner.get().producer.lock().await.task = Some(tokio::spawn(async {
                panic!("injected statistics producer panic");
            }));
            let failure = feed
                .close()
                .await
                .expect_err("producer panic must be reported");
            ensure!(!failure.retryable);
            ensure!(feed.inner.get().producer.lock().await.task.is_none());
            ensure!(feed.close().await.unwrap_err() == failure);
            let report = scope
                .close(tokio::time::Instant::now() + Duration::from_secs(5))
                .await;
            ensure!(report.failures.len() == 1 && report.pending.is_empty());
            ensure!(report.failures[0].resource.label == "statisticsFeeds");
            Ok(())
        }
        .await;
        env.finish(result).await
    }
}
