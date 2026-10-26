//! `acpInstall` 的有界 typed feed：只读取安装 owner 的 canonical 快照并发布。
//!
//! 与 `acpAuth` 完全同构但**互相独立**：安装是共享资产，拥有自己的 revision、窗口与关闭通道；
//! 两条 feed 不共享 ACK 额度，也不互相取消（见 design/28 §28.5–28.8）。

use pl_protocol::products::feed::acp_install::{AcpInstallEvent, AcpInstallFrame};
use pl_protocol::products::identity::{
    ProductFeedCloseReason, ProductFeedIdentity, ProductProjectionStamp, ProductResource,
    ProductResyncReason,
};
use pl_protocol::studio::{AcpInstallSnapshot, StudioError, StudioErrorCode};
use std::future::Future;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, watch};
use tokio_util::sync::CancellationToken;

use super::super::{
    StudioRuntime, lifecycle::shutdown::ShutdownLatch, models::delivery_window::DeliveryWindow,
};
use super::AcpInstallRuntime;

struct Window {
    delivery: DeliveryWindow<AcpInstallSnapshot>,
    /// 本 feed 实际发出的上一个快照：`base_revision` 的唯一来源。
    previous: Option<AcpInstallSnapshot>,
}

/// 安装域的有界 feed；只共享窗口，不复制 owner 事实。
pub struct StudioAcpInstallFeed {
    identity: ProductFeedIdentity,
    owner: AcpInstallRuntime,
    runtime_stop: ShutdownLatch,
    cancel: CancellationToken,
    updates: tokio::sync::Mutex<watch::Receiver<()>>,
    credit: Notify,
    window: Mutex<Window>,
}

impl StudioRuntime {
    pub fn open_acp_install(
        &self,
    ) -> impl Future<Output = anyhow::Result<StudioAcpInstallFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let owner = runtime.acp_install.clone();
            let (snapshot, updates) = owner.observe()?;
            let origin = owner.origin();
            let feed = StudioAcpInstallFeed {
                identity: ProductFeedIdentity {
                    feed_id: crate::studio::new_id("product-feed"),
                    owner_epoch: origin.owner_epoch,
                    incarnation: origin.incarnation,
                    resource: ProductResource::AcpInstall,
                },
                window: Mutex::new(Window {
                    delivery: DeliveryWindow::new(Arc::new(snapshot)),
                    previous: None,
                }),
                owner,
                runtime_stop: runtime.shutdown_latch.clone(),
                cancel: CancellationToken::new(),
                updates: tokio::sync::Mutex::new(updates),
                credit: Notify::new(),
            };
            feed.ensure_open()?;
            Ok(feed)
        })
    }
}

impl StudioAcpInstallFeed {
    pub fn identity(&self) -> ProductFeedIdentity {
        self.identity.clone()
    }

    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.check(
            &self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }

    pub fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.claim("AcpInstall")
    }

    /// `send` 必须同步、有界且不可重入（含内联 ACK/读取）。
    pub fn send_pending(
        &self,
        send: impl FnOnce(AcpInstallFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&window)?;
        window.delivery.require_claimed("AcpInstall")?;
        let snapshot = self.owner.current()?;
        let event = match &window.previous {
            None => AcpInstallEvent::Baseline {
                identity: self.identity.clone(),
                stamp: stamp(&self.identity, &snapshot),
                value: snapshot.clone(),
            },
            Some(previous) if previous.revision == snapshot.revision => return Ok(false),
            Some(previous) if previous.revision.checked_add(1) == Some(snapshot.revision) => {
                AcpInstallEvent::Change {
                    stamp: stamp(&self.identity, &snapshot),
                    base_revision: previous.revision,
                    value: snapshot.clone(),
                }
            }
            // 水位与 owner revision 之间出现空洞：消费者必须重开拿新 baseline，而不是接受跳变。
            Some(_) => {
                window.delivery.closing = true;
                let result = window.delivery.send_control(|| {
                    send(AcpInstallFrame::ResyncRequired {
                        identity: self.identity.clone(),
                        reason: ProductResyncReason::RevisionGap,
                    })
                });
                drop(window);
                self.cancel.cancel();
                result?;
                return Ok(true);
            }
        };
        if !window.delivery.has_credit() {
            return Ok(false);
        }
        window.delivery.pending = Some(Arc::new(snapshot.clone()));
        let sent = window
            .delivery
            .deliver(
                "AcpInstall",
                |delivery_sequence, _| {
                    Ok(AcpInstallFrame::Data {
                        delivery_sequence,
                        event,
                    })
                },
                send,
            )
            .map(|sent| sent.is_some())?;
        if sent {
            window.previous = Some(snapshot);
        }
        Ok(sent)
    }

    /// 只有本 handle 实际发出的连续前缀可以 ACK；baseline 占普通 Data 额度。
    pub fn ack_through(&self, delivery_sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check(&window)?;
            window
                .delivery
                .ack_through(delivery_sequence, "AcpInstall")?;
        }
        self.credit.notify_one();
        Ok(())
    }

    pub async fn changed(&self) -> Result<(), StudioError> {
        tokio::select! { biased;
            () = self.cancelled() => Err(cancelled()),
            () = self.credit.notified() => Ok(()),
            result = async { self.updates.lock().await.changed().await } => result.map_err(|_| StudioError::new(
                StudioErrorCode::Unavailable, "The original acpInstall owner disappeared", true)),
        }
    }

    pub fn request_close(&self) {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .closing = true;
        self.cancel.cancel();
    }

    pub fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
        let cancel = self.cancel.clone();
        let runtime = self.runtime_stop.clone();
        async move {
            tokio::select! { biased; () = cancel.cancelled() => {}, () = runtime.committed() => {} }
        }
    }

    pub fn is_closing(&self) -> bool {
        self.ensure_open()
            .is_err_and(|error| error.code == StudioErrorCode::Cancelled)
    }

    pub fn send_closed(
        &self,
        send: impl FnOnce(AcpInstallFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime_stop.is_committed() || self.owner.ensure_open().is_err() {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.control(
            AcpInstallFrame::Closed {
                identity: self.identity.clone(),
                reason,
            },
            send,
        )
    }

    pub fn send_failure(
        &self,
        error: StudioError,
        send: impl FnOnce(AcpInstallFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.control(
            AcpInstallFrame::Failure {
                identity: self.identity.clone(),
                error,
            },
            send,
        )
    }

    fn control(
        &self,
        frame: AcpInstallFrame,
        send: impl FnOnce(AcpInstallFrame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(frame))
    }

    fn check(&self, window: &Window) -> Result<(), StudioError> {
        if window.delivery.closing || self.cancel.is_cancelled() || self.runtime_stop.is_committed()
        {
            return Err(cancelled());
        }
        self.owner.ensure_open()
    }
}

impl Drop for StudioAcpInstallFeed {
    fn drop(&mut self) {
        self.request_close();
    }
}

fn stamp(identity: &ProductFeedIdentity, snapshot: &AcpInstallSnapshot) -> ProductProjectionStamp {
    ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "AcpInstall feed is closing",
        false,
    )
}
