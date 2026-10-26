use super::super::{
    StudioRuntime, lifecycle::shutdown::ShutdownLatch, models::delivery_window::DeliveryWindow,
};
use super::source::{
    Key, Root, StatisticsMaterial, StatisticsPublication, StatisticsSource, cancelled,
};
use pl_protocol::products::feed::{
    performance_history as history, performance_summaries as summaries, session_costs as costs,
};
use pl_protocol::products::identity::*;
use pl_protocol::products::references::*;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use serde::Serialize;
use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

/// 一次活跃会话费用订阅持有的原 root 观察需求，以及与登记同一边界的费用基线。
///
/// 只借用既有计费所有者：不创建或激活会话执行 owner，也不触发模型、工具或调用库扫描。
/// 调用方持有该租约到订阅关闭或释放，此后没有费用材料的空观察条目可被回收。
pub(in crate::studio::runtime) struct SessionCostsObservation {
    pub(in crate::studio::runtime) lease: Arc<()>,
    pub(in crate::studio::runtime) baseline: crate::StudioSessionCostsState,
}

struct Window {
    delivery: DeliveryWindow<StatisticsPublication>,
    previous: Option<Arc<StatisticsPublication>>,
}
struct Feed {
    identity: ProductFeedIdentity,
    source: Arc<StatisticsSource>,
    key: Key,
    runtime_stop: ShutdownLatch,
    _lease: Arc<()>,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}
pub struct StudioPerformanceSummariesFeed {
    feed: Feed,
}
pub struct StudioPerformanceHistoryFeed {
    feed: Feed,
}
pub struct StudioSessionCostsFeed {
    feed: Feed,
}
impl StudioRuntime {
    pub fn open_performance_summaries(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioPerformanceSummariesFeed>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Ok(StudioPerformanceSummariesFeed {
                feed: Feed::open(
                    &runtime,
                    Key::Summaries,
                    ProductResource::PerformanceSummaries,
                )?,
            })
        })
    }
    pub fn open_performance_history(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioPerformanceHistoryFeed>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Ok(StudioPerformanceHistoryFeed {
                feed: Feed::open(&runtime, Key::History, ProductResource::PerformanceHistory)?,
            })
        })
    }
    pub fn open_session_costs(
        &self,
        root_thread_id: String,
    ) -> impl Future<Output = anyhow::Result<StudioSessionCostsFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if root_thread_id.trim().is_empty() {
                return Err(StudioError::invalid_argument(
                    "SessionCosts requires a root Thread ID",
                )
                .into());
            }
            let lease = runtime
                .statistics_source
                .lease(&Key::Costs(root_thread_id.clone()))?;
            // 已取得 lease 的 root 必须登记观察，否则没有 rollup 的空材料收不到后续状态。
            let captured = runtime
                .model_performance
                .observe_session_costs(&root_thread_id)
                .await;
            let material = runtime.statistics_source.publish_costs(captured)?;
            let feed = Feed::open(
                &runtime,
                Key::Costs(root_thread_id),
                ProductResource::SessionCosts,
            )?;
            drop(material);
            drop(lease);
            Ok(StudioSessionCostsFeed { feed })
        })
    }
    /// 活跃会话费用订阅的观察边界：先登记原 root 需求，再交付同一边界的基线。
    ///
    /// 复用桌面费用订阅已有的 lease 与 `observe_session_costs`：尚无费用记录的 root 也进入同一
    /// 费用账本，因此随后只有 pending/gap/readFailed（或首次真实 rollup）变化时不会漏发。这里
    /// 不读取调用库、不激活 Thread 执行 owner、也不产生额外数据库扫描。
    pub(in crate::studio::runtime) async fn observe_session_costs_subscription(
        &self,
        root_thread_id: &str,
    ) -> Result<SessionCostsObservation, StudioError> {
        let lease = self
            .statistics_source
            .lease(&Key::Costs(root_thread_id.to_owned()))?;
        let baseline = self
            .model_performance
            .observe_session_costs(root_thread_id)
            .await;
        Ok(SessionCostsObservation { lease, baseline })
    }
}
impl Feed {
    fn open(
        runtime: &StudioRuntime,
        key: Key,
        resource: ProductResource,
    ) -> Result<Self, StudioError> {
        let source = runtime.statistics_source.clone();
        let lease = source.lease(&key)?;
        let (material, updates) = source.observe(&key)?;
        let origin = source.origin();
        let feed = Self {
            identity: ProductFeedIdentity {
                feed_id: crate::studio::new_id("product-feed"),
                owner_epoch: origin.owner_epoch.clone(),
                incarnation: origin.incarnation,
                resource,
            },
            source,
            key,
            _lease: lease,
            runtime_stop: runtime.shutdown_latch.clone(),
            cancel: CancellationToken::new(),
            updates: tokio::sync::Mutex::new(updates),
            credit: Notify::new(),
            window: Mutex::new(Window {
                delivery: DeliveryWindow::new(material),
                previous: None,
            }),
        };
        feed.ensure_open()?;
        Ok(feed)
    }
    fn check(&self, window: &Window) -> Result<(), StudioError> {
        if window.delivery.closing || self.cancel.is_cancelled() || self.runtime_stop.is_committed()
        {
            return Err(cancelled());
        }
        self.source.ensure_open()
    }
    fn ensure_open(&self) -> Result<(), StudioError> {
        self.check(
            &self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }
    fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.claim("Statistics")
    }
    fn send_pending<F: Serialize>(
        &self,
        build: impl FnOnce(
            u64,
            &StatisticsPublication,
            Option<&StatisticsPublication>,
        ) -> Result<F, StudioError>,
        resync: impl FnOnce(ProductResyncReason) -> F,
        send: impl FnOnce(F) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.require_claimed("Statistics")?;
        // 发布投影版本只在本来源单调；材料与状态在同一发布边界配对。
        let publication = self.source.current(&self.key)?;
        if window
            .previous
            .as_ref()
            .is_some_and(|old| old.revision == publication.revision)
        {
            return Ok(false);
        }
        window.delivery.pending = Some(publication.clone());
        if let Some(old) = &window.previous {
            let (upserted, removed) = diff(&publication.material, &old.material);
            if upserted.len() + removed.len() > 100 {
                window.delivery.closing = true;
                let result = window
                    .delivery
                    .send_control(|| send(resync(ProductResyncReason::SourceLagged)));
                drop(window);
                self.cancel.cancel();
                result?;
                return Ok(true);
            }
        }
        if !window.delivery.has_credit() {
            return Ok(false);
        }
        let previous = window.previous.clone();
        let sent = self.source.send_exposing(&publication.material, || {
            window
                .delivery
                .deliver(
                    "Statistics",
                    |sequence, publication| build(sequence, publication, previous.as_deref()),
                    send,
                )
                .map(|sent| sent.is_some())
        })?;
        if sent {
            window.previous = Some(publication);
        }
        Ok(sent)
    }
    fn stamp(&self, publication: &StatisticsPublication) -> ProductProjectionStamp {
        ProductProjectionStamp {
            owner_epoch: self.identity.owner_epoch.clone(),
            incarnation: self.identity.incarnation,
            revision: publication.revision,
        }
    }
    fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check(&window)?;
            window.delivery.ack_through(sequence, "Statistics")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased; () = self.cancelled() => Err(cancelled()), () = self.credit.notified() => Ok(()),
        result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(StudioErrorCode::Unavailable, "Statistics source disappeared", true)), }
    }
    fn request_close(&self) {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .closing = true;
        self.cancel.cancel();
    }
    fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
        let cancel = self.cancel.clone();
        let runtime = self.runtime_stop.clone();
        async move {
            tokio::select! { biased; () = cancel.cancelled() => {}, () = runtime.committed() => {} }
        }
    }
    fn control<F>(
        &self,
        frame: F,
        send: impl FnOnce(F) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(frame))
    }
    fn close_reason(&self) -> ProductFeedCloseReason {
        if self.runtime_stop.is_committed() || self.source.ensure_open().is_err() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        }
    }
}
impl Drop for Feed {
    fn drop(&mut self) {
        self.request_close();
    }
}

// Nominal DTO variants cannot be generic; ownership, admission and ACK remain in Feed above.
macro_rules! lifecycle {
    ($feed:ident, $frame:path) => {
        impl $feed {
            pub fn identity(&self) -> ProductFeedIdentity {
                self.feed.identity.clone()
            }
            pub fn ensure_open(&self) -> Result<(), StudioError> {
                self.feed.ensure_open()
            }
            pub fn claim(&self) -> Result<(), StudioError> {
                self.feed.claim()
            }
            pub fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
                self.feed.ack_through(sequence)
            }
            pub async fn changed(&self) -> Result<(), StudioError> {
                self.feed.changed().await
            }
            pub fn request_close(&self) {
                self.feed.request_close();
            }
            pub fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
                self.feed.cancelled()
            }
            pub fn is_closing(&self) -> bool {
                self.feed
                    .ensure_open()
                    .is_err_and(|error| error.code == StudioErrorCode::Cancelled)
            }
            pub fn send_closed(
                &self,
                send: impl FnOnce($frame) -> Result<(), StudioError>,
            ) -> Result<(), StudioError> {
                use $frame as Frame;
                self.feed.control(
                    Frame::Closed {
                        identity: self.identity(),
                        reason: self.feed.close_reason(),
                    },
                    send,
                )
            }
            pub fn send_failure(
                &self,
                error: StudioError,
                send: impl FnOnce($frame) -> Result<(), StudioError>,
            ) -> Result<(), StudioError> {
                use $frame as Frame;
                self.feed.control(
                    Frame::Failure {
                        identity: self.identity(),
                        error,
                    },
                    send,
                )
            }
        }
    };
}
lifecycle!(
    StudioPerformanceSummariesFeed,
    summaries::PerformanceSummariesFrame
);
lifecycle!(
    StudioPerformanceHistoryFeed,
    history::PerformanceHistoryFrame
);
lifecycle!(StudioSessionCostsFeed, costs::SessionCostsFrame);
impl StudioPerformanceSummariesFeed {
    pub fn send_pending(
        &self,
        send: impl FnOnce(summaries::PerformanceSummariesFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        self.feed.send_pending(
            |delivery_sequence, publication, previous| {
                let Root::Summaries(_) = &publication.material.root else {
                    return Err(cancelled());
                };
                let header = summaries::PerformanceSummariesHeader {
                    revision: publication.status.revision,
                    updated_at: publication.status.updated_at,
                    statistics_pending: publication.status.statistics_pending,
                    statistics_gap: publication.status.statistics_gap,
                    read_failed: publication.status.read_failed,
                    reference: PerformanceSummariesReadRef {
                        entry: publication.material.entry,
                        revision: publication.material.revision,
                    },
                };
                let stamp = self.feed.stamp(publication);
                let event = match previous {
                    None => summaries::PerformanceSummariesEvent::Baseline {
                        identity: self.identity(),
                        stamp,
                        value: summaries::PerformanceSummariesBaseline {
                            header,
                            collection: publication.material.collection,
                        },
                    },
                    Some(old) => {
                        let (upserted, removed_entries) =
                            diff(&publication.material, &old.material);
                        summaries::PerformanceSummariesEvent::Change {
                            stamp,
                            base_revision: old.revision,
                            value: summaries::PerformanceSummariesChange {
                                header,
                                base_collection_revision: old
                                    .material
                                    .collection
                                    .map(|collection| collection.revision),
                                collection: publication.material.collection,
                                upserted,
                                removed_entries,
                            },
                        }
                    }
                };
                Ok(summaries::PerformanceSummariesFrame::Data {
                    delivery_sequence,
                    event,
                })
            },
            |reason| summaries::PerformanceSummariesFrame::ResyncRequired {
                identity: self.identity(),
                reason,
            },
            send,
        )
    }
}
impl StudioPerformanceHistoryFeed {
    pub fn send_pending(
        &self,
        send: impl FnOnce(history::PerformanceHistoryFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        self.feed.send_pending(
            |delivery_sequence, publication, previous| {
                let Root::History { .. } = &publication.material.root else {
                    return Err(cancelled());
                };
                let header = history::PerformanceHistoryHeader {
                    revision: publication.status.revision,
                    updated_at: publication.status.updated_at,
                    statistics_pending: publication.status.statistics_pending,
                    statistics_gap: publication.status.statistics_gap,
                    read_failed: publication.status.read_failed,
                    reference: PerformanceHistoryReadRef {
                        entry: publication.material.entry,
                        revision: publication.material.revision,
                    },
                };
                let stamp = self.feed.stamp(publication);
                let event = match previous {
                    None => history::PerformanceHistoryEvent::Baseline {
                        identity: self.identity(),
                        stamp,
                        value: history::PerformanceHistoryBaseline {
                            header,
                            collection: publication.material.collection,
                        },
                    },
                    Some(old) => {
                        let (upserted, removed_entries) =
                            diff(&publication.material, &old.material);
                        history::PerformanceHistoryEvent::Change {
                            stamp,
                            base_revision: old.revision,
                            value: history::PerformanceHistoryChange {
                                header,
                                base_collection_revision: old
                                    .material
                                    .collection
                                    .map(|collection| collection.revision),
                                collection: publication.material.collection,
                                upserted,
                                removed_entries,
                            },
                        }
                    }
                };
                Ok(history::PerformanceHistoryFrame::Data {
                    delivery_sequence,
                    event,
                })
            },
            |reason| history::PerformanceHistoryFrame::ResyncRequired {
                identity: self.identity(),
                reason,
            },
            send,
        )
    }
}
impl StudioSessionCostsFeed {
    pub fn send_pending(
        &self,
        send: impl FnOnce(costs::SessionCostsFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        self.feed.send_pending(
            |delivery_sequence, publication, previous| {
                let Root::Costs(cost) = &publication.material.root else {
                    return Err(cancelled());
                };
                let header = costs::SessionCostsHeader {
                    revision: publication.status.revision,
                    updated_at: publication.status.updated_at,
                    statistics_pending: publication.status.statistics_pending,
                    statistics_gap: publication.status.statistics_gap,
                    read_failed: publication.status.read_failed,
                    has_cost: cost.is_some(),
                    has_unpriced_usage: cost.as_ref().map(|cost| cost.has_unpriced_usage),
                    reference: SessionCostsReadRef {
                        entry: publication.material.entry,
                        revision: publication.material.revision,
                    },
                };
                let stamp = self.feed.stamp(publication);
                let event = match previous {
                    None => costs::SessionCostsEvent::Baseline {
                        identity: self.identity(),
                        stamp,
                        value: header,
                    },
                    Some(old) => costs::SessionCostsEvent::Replace {
                        stamp,
                        base_revision: old.revision,
                        value: header,
                    },
                };
                Ok(costs::SessionCostsFrame::Data {
                    delivery_sequence,
                    event,
                })
            },
            |reason| costs::SessionCostsFrame::ResyncRequired {
                identity: self.identity(),
                reason,
            },
            send,
        )
    }
}
fn diff(
    material: &StatisticsMaterial,
    old: &StatisticsMaterial,
) -> (Vec<ProductEntityRef>, Vec<u64>) {
    (
        material
            .entities
            .iter()
            .filter(|entry| !old.entities.contains(entry))
            .copied()
            .collect(),
        old.entities
            .iter()
            .filter(|old| {
                !material
                    .entities
                    .iter()
                    .any(|entry| entry.entry == old.entry)
            })
            .map(|entry| entry.entry)
            .collect(),
    )
}
