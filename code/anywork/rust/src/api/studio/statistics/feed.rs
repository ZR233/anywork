//! FRB feed and immutable read-scope handles.

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use tokio::sync::{Mutex, mpsc};
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::convert::{
    bridge_effort_page, bridge_header, bridge_history_page, bridge_summary_page,
    statistics_close_error, statistics_error,
};
use super::types::{
    BridgeStatisticsEffortPage, BridgeStatisticsFeedEvent, BridgeStatisticsFeedHeader,
    BridgeStatisticsHistoryPage, BridgeStatisticsScopeIdentity, BridgeStatisticsSummaryPage,
};
use crate::api::studio::bridge_runtime::{active_bridge, current_bridge};
use crate::api::studio::types::BridgeError;
use crate::frb_generated::StreamSink;
use pl_studio_runtime::statistics::{StatisticsError, StatisticsFeed, StatisticsReadScope};

/// Opens one independent latest-value statistics feed from the canonical runtime owner.
pub async fn open_statistics_feed() -> Result<BridgeStatisticsFeed, BridgeError> {
    let bridge = active_bridge().await?;
    let feed = bridge.studio.open_statistics_feed();
    let inner = Arc::new(BridgeStatisticsFeedInner {
        id: bridge.subscriptions.next_id(),
        feed,
        shutdown: bridge.shutdown.child_token(),
        close_requested: AtomicBool::new(false),
        events_started: AtomicBool::new(false),
        producer_cancellation: CancellationToken::new(),
        event_start: Mutex::new(()),
        producer: Mutex::new(None),
        sink: Mutex::new(None),
        settled: AtomicBool::new(false),
    });
    bridge
        .subscriptions
        .register_statistics_feed(&inner, &bridge.shutdown)
        .await?;
    Ok(BridgeStatisticsFeed { inner })
}

/// Managed opaque feed handle. The bridge registry keeps its strong owner until close is confirmed.
pub struct BridgeStatisticsFeed {
    pub(crate) inner: Arc<BridgeStatisticsFeedInner>,
}

pub(crate) struct BridgeStatisticsFeedInner {
    pub(crate) id: u64,
    feed: StatisticsFeed,
    shutdown: CancellationToken,
    close_requested: AtomicBool,
    events_started: AtomicBool,
    producer_cancellation: CancellationToken,
    event_start: Mutex<()>,
    producer: Mutex<Option<JoinHandle<Result<(), StatisticsFeedCloseError>>>>,
    sink: Mutex<Option<JoinHandle<Result<(), StatisticsFeedCloseError>>>>,
    settled: AtomicBool,
}

impl BridgeStatisticsFeedInner {
    pub(crate) fn request_close(&self) {
        if self.close_requested.swap(true, Ordering::AcqRel) {
            return;
        }
        self.producer_cancellation.cancel();
        self.feed.request_close();
    }

    pub(crate) async fn close(&self) -> Result<(), StatisticsFeedCloseError> {
        self.request_close();
        // Serialize stream creation against close. Once this gate is passed, no new task may be
        // installed after the close path has inspected and joined the existing owners.
        let event_start = self.event_start.lock().await;
        drop(event_start);
        self.feed.close().await?;
        let producer = join_task(&self.producer, TaskOwner::Producer).await;
        let sink = join_task(&self.sink, TaskOwner::Sink).await;
        producer?;
        sink?;
        self.settled.store(true, Ordering::Release);
        Ok(())
    }

    pub(crate) fn is_settled(&self) -> bool {
        self.settled.load(Ordering::Acquire)
    }
}

impl BridgeStatisticsFeed {
    /// Opens the ordered typed push stream for this feed. Its producer and sink remain owned by
    /// the feed registry until close confirms that both tasks have stopped.
    pub async fn events(
        &self,
        sink: StreamSink<BridgeStatisticsFeedEvent>,
    ) -> Result<(), BridgeError> {
        let _event_start = self.inner.event_start.lock().await;
        if self.inner.close_requested.load(Ordering::Acquire) || self.inner.shutdown.is_cancelled()
        {
            self.inner.request_close();
            return Err(BridgeError::runtime_stopped());
        }
        if self.inner.events_started.swap(true, Ordering::AcqRel) {
            return Err(BridgeError::invalid_argument(
                "statistics event stream can only be opened once",
            ));
        }

        let (sender, mut receiver) = mpsc::channel(1);
        let feed = self.inner.feed.clone();
        let shutdown = self.inner.shutdown.clone();
        let cancellation = self.inner.producer_cancellation.clone();
        let sink_feed = feed.clone();
        let sink_cancellation = cancellation.clone();
        let sink_task = tokio::spawn(async move {
            while let Some(event) = receiver.recv().await {
                if sink.add(event).is_err() {
                    sink_cancellation.cancel();
                    sink_feed.request_close();
                    return Err(StatisticsFeedCloseError::SinkStopped);
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
                            if sender.send(event).await.is_err() {
                                return Err(StatisticsFeedCloseError::SinkStopped);
                            }
                            return Ok(());
                        }
                    }
                };
                let Some(header) = next else {
                    let _ = sender.send(BridgeStatisticsFeedEvent::Closed).await;
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
                if sender.send(event).await.is_err() {
                    return Err(StatisticsFeedCloseError::SinkStopped);
                }
            }
        });

        *self.inner.sink.lock().await = Some(sink_task);
        *self.inner.producer.lock().await = Some(producer_task);
        Ok(())
    }

    /// Opens a scope fixed to a publication previously returned by this feed.
    pub fn open_scope(
        &self,
        header: BridgeStatisticsFeedHeader,
    ) -> Result<BridgeStatisticsReadScope, BridgeError> {
        if self.inner.shutdown.is_cancelled() {
            self.inner.request_close();
            return Err(BridgeError::runtime_stopped());
        }
        let scope = self
            .inner
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
            .feed
            .acknowledge(delivery_sequence)
            .map_err(statistics_error)
    }

    /// Synchronously seals this feed before asynchronous close/join begins.
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    /// Seals admission, cancels waits, joins in-flight calls and scopes, then releases the registry
    /// owner. A failed/abandoned wait leaves the original feed registered for retry.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.request_close();
        self.inner.close().await.map_err(statistics_close_error)?;
        if let Some(bridge) = current_bridge() {
            bridge
                .subscriptions
                .unregister_statistics_feed(self.inner.id)
                .await;
        }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum StatisticsFeedCloseError {
    #[error(transparent)]
    Feed(#[from] StatisticsError),
    #[error("statistics event sink stopped before close was confirmed")]
    SinkStopped,
    #[error("statistics producer task failed before close was confirmed")]
    ProducerTaskFailed,
    #[error("statistics sink task failed before close was confirmed")]
    SinkTaskFailed,
}

#[derive(Clone, Copy)]
enum TaskOwner {
    Producer,
    Sink,
}

async fn join_task(
    slot: &Mutex<Option<JoinHandle<Result<(), StatisticsFeedCloseError>>>>,
    task_owner: TaskOwner,
) -> Result<(), StatisticsFeedCloseError> {
    let mut owner = slot.lock().await;
    let Some(task) = owner.as_mut() else {
        return Ok(());
    };
    let joined = task.await;
    // A completed handle is removed only after its terminal result is observed; a cancelled close
    // future leaves the handle in this slot and a later close retries the same owner.
    owner.take();
    match joined {
        Ok(result) => result,
        Err(_) => Err(match task_owner {
            TaskOwner::Producer => StatisticsFeedCloseError::ProducerTaskFailed,
            TaskOwner::Sink => StatisticsFeedCloseError::SinkTaskFailed,
        }),
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
