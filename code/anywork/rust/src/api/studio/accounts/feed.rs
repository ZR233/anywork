use super::{
    convert,
    types::{BridgeAccountDomainFrame, BridgeAccountObservationTarget},
};
use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::subscription::{
    error::{close_error, open_error},
    factory::BridgeObservationFactory,
};
use crate::api::studio::types::BridgeError;
use pl_lifecycle::{Managed, ManagedResource};
use pl_studio_runtime::accounts::AccountObservation;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio_util::sync::CancellationToken;

/// 在作用域登记创建过程；迟到的原始观察仍由同一作用域关闭。
pub async fn open_account_observation(
    target: BridgeAccountObservationTarget,
) -> Result<BridgeAccountObservation, BridgeError> {
    let bridge = active_bridge().await?;
    bridge.observation_factory.open_account(target).await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_account(
        &self,
        target: BridgeAccountObservationTarget,
    ) -> Result<BridgeAccountObservation, BridgeError> {
        let source = self.source.clone();
        let inner = self
            .scope
            .open("accountObservations", move |shutdown| async move {
                Ok(BridgeAccountObservationInner {
                    observation: source.open_account_observation(target.into())?,
                    shutdown,
                    closing: AtomicBool::new(false),
                    next_gate: tokio::sync::Mutex::new(()),
                })
            })
            .await
            .map_err(open_error)?;
        Ok(BridgeAccountObservation { inner })
    }
}

pub async fn read_account_domain(
    target: BridgeAccountObservationTarget,
) -> Result<BridgeAccountDomainFrame, BridgeError> {
    Ok(convert::frame(
        active_bridge()
            .await?
            .studio
            .read_account_domain(&target.into())?,
    ))
}

/// An opaque pull handle: no FRB StreamSink or native port queue can bypass its one-next limit.
pub struct BridgeAccountObservation {
    inner: Managed<BridgeAccountObservationInner>,
}

pub(crate) struct BridgeAccountObservationInner {
    observation: AccountObservation,
    shutdown: CancellationToken,
    closing: AtomicBool,
    next_gate: tokio::sync::Mutex<()>,
}

impl ManagedResource for BridgeAccountObservationInner {
    type Error = BridgeError;

    fn request_close(&self) {
        self.closing.store(true, Ordering::Release);
        self.observation.request_close();
    }
    async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        self.observation.close().await?;
        let _next = self.next_gate.lock().await;
        Ok(())
    }
}

impl BridgeAccountObservation {
    pub async fn next(&self) -> Result<Option<BridgeAccountDomainFrame>, BridgeError> {
        let inner = self.inner.get();
        if inner.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let _next = inner.next_gate.try_lock().map_err(|_| {
            BridgeError::from(pl_studio_runtime::StudioError::new(
                pl_studio_runtime::StudioErrorCode::Busy,
                "An account next read is already in flight",
                true,
            ))
        })?;
        if inner.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        tokio::select! {
            biased;
            _ = inner.shutdown.cancelled() => { self.inner.request_close(); Ok(None) },
            next = inner.observation.next() => Ok(next?.map(convert::frame)),
        }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    /// Cancellation or timeout retains this exact registered owner for a later close retry.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.retry_close().await.map_err(close_error)
    }
}
