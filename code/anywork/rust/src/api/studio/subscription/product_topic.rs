//! typed 产品 topic 订阅：首帧基线 + 该领域事件；作用域由 topic 表达。

use tokio::sync::mpsc;

use super::{
    BridgeEventSubscription, BridgeSubscriptionInner, BridgeSubscriptionKind,
    BridgeSubscriptionReceiver, error::open_error, factory::BridgeObservationFactory,
    send_or_cancel, task::OwnedTaskSlot,
};
use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::event::{bridge_product_baseline, bridge_product_event};
use crate::api::studio::types::{
    BridgeError, BridgeProductTopic, BridgeProductTopicStreamEnvelope,
};
use crate::frb_generated::StreamSink;
use pl_studio_runtime::StudioProductFrame;

/// 订阅一个 typed 产品 topic。
///
/// 一次订阅只观察一个领域：runtime 先登记该 topic 的接收者，再读取领域基线；本模块
/// producer 把首帧 `Baseline` 与后续事件转发给 Dart sink，`Lagged` 帧提示客户端仅重读
/// 该 topic 的基线（无 durable replay）。
pub async fn create_product_topic_subscription(
    topic: BridgeProductTopic,
) -> Result<BridgeEventSubscription, BridgeError> {
    topic.validate_scope()?;
    let bridge = active_bridge().await?;
    bridge.observation_factory.open_product_topic(topic).await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_product_topic(
        &self,
        topic: BridgeProductTopic,
    ) -> Result<BridgeEventSubscription, BridgeError> {
        let source = self.source.clone();
        let inner =
            self.scope
                .open("productTopics", move |cancel| async move {
                    let runtime_topic = topic.to_runtime();
                    let producer_topic = topic.clone();
                    let mut events = source.subscribe_product_topic(runtime_topic).await?;
                    let producer_cancel = cancel.clone();
                    let (sender, receiver) = mpsc::channel(64);
                    let producer_task = tokio::spawn(async move {
                        let topic = producer_topic;
                        loop {
                            let frame = tokio::select! {
                                _ = producer_cancel.cancelled() => break,
                                frame = events.recv() => match frame {
                                    Ok(Some(frame)) => frame,
                                    Ok(None) => break,
                                    Err(error) => {
                                        let _ = send_or_cancel(
                                            &producer_cancel,
                                            &sender,
                                            BridgeProductTopicStreamEnvelope::Failure {
                                                error: BridgeError::from(error),
                                            },
                                        ).await;
                                        break;
                                    }
                                },
                            };
                            let converted = match frame {
                                StudioProductFrame::Baseline(baseline) => {
                                    bridge_product_baseline(*baseline).map(|(revision, state)| {
                                        BridgeProductTopicStreamEnvelope::Baseline {
                                            topic: topic.clone(),
                                            revision,
                                            state: Box::new(state),
                                        }
                                    })
                                }
                                StudioProductFrame::Event(event) => bridge_product_event(*event)
                                    .map(|event| BridgeProductTopicStreamEnvelope::Data {
                                        event: Box::new(event),
                                    }),
                                StudioProductFrame::Lagged { dropped, .. } => {
                                    Ok(BridgeProductTopicStreamEnvelope::Lagged {
                                        topic: topic.clone(),
                                        dropped,
                                    })
                                }
                            };
                            let envelope = match converted {
                                Ok(envelope) => envelope,
                                Err(error) => {
                                    let error = BridgeError::from(error);
                                    tracing::warn!(
                                        code = ?error.code,
                                        correlation_id = %error.correlation_id,
                                        "failed to convert Studio product frame"
                                    );
                                    let _ = send_or_cancel(
                                        &producer_cancel,
                                        &sender,
                                        BridgeProductTopicStreamEnvelope::Failure { error },
                                    )
                                    .await;
                                    break;
                                }
                            };
                            if !send_or_cancel(&producer_cancel, &sender, envelope).await {
                                break;
                            }
                        }
                        // 终态 Closed 尽力交付：取消与满队列都不得让 cancel_and_wait 永久等待。
                        let _ = send_or_cancel(
                            &producer_cancel,
                            &sender,
                            BridgeProductTopicStreamEnvelope::Closed,
                        )
                        .await;
                        Ok(())
                    });
                    Ok(BridgeSubscriptionInner {
                        kind: BridgeSubscriptionKind::ProductTopic { topic },
                        cancel,
                        producer_task: tokio::sync::Mutex::new(OwnedTaskSlot {
                            task: Some(producer_task),
                            outcome: None,
                        }),
                        sink_task: tokio::sync::Mutex::new(OwnedTaskSlot::default()),
                        receiver: tokio::sync::Mutex::new(Some(
                            BridgeSubscriptionReceiver::ProductTopic(receiver),
                        )),
                    })
                })
                .await
                .map_err(open_error)?;
        Ok(BridgeEventSubscription {
            inner,
            _scope: None,
        })
    }
}

impl BridgeEventSubscription {
    /// 打开该 topic 订阅的产品流；每个订阅只能打开一次。
    ///
    /// # Errors
    /// 拒绝其他订阅种类或第二个流消费者。
    pub async fn product_topic_stream(
        &self,
        sink: StreamSink<BridgeProductTopicStreamEnvelope>,
    ) -> Result<(), BridgeError> {
        let inner = self.inner.get();
        if !matches!(inner.kind, BridgeSubscriptionKind::ProductTopic { .. }) {
            return Err(BridgeError::invalid_argument(
                "non-product subscription cannot open a product topic stream",
            ));
        }
        let mut receiver = match inner.receiver.lock().await.take() {
            Some(BridgeSubscriptionReceiver::ProductTopic(receiver)) => receiver,
            _ => {
                return Err(BridgeError::invalid_argument(
                    "product topic stream can only be opened once",
                ));
            }
        };
        let cancel = inner.cancel.clone();
        inner
            .attach_sink(async move {
                loop {
                    tokio::select! {
                        _ = cancel.cancelled() => break,
                        envelope = receiver.recv() => {
                            let Some(envelope) = envelope else {
                                break;
                            };
                            if sink.add(envelope).is_err() {
                                cancel.cancel();
                                break;
                            }
                        }
                    }
                }
                Ok(())
            })
            .await;
        Ok(())
    }
}
