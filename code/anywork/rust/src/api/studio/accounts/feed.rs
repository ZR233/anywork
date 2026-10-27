use super::{
    convert,
    types::{BridgeAccountDomainFrame, BridgeAccountObservationTarget},
};
use crate::api::studio::bridge_runtime::{active_bridge, current_bridge};
use crate::api::studio::types::BridgeError;
use pl_studio_runtime::accounts::AccountObservation;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use tokio_util::sync::CancellationToken;

/// Registration and baseline demand use no spawned task. A late open is either refused by the
/// sealed registry or remains strongly registered and receives the same shutdown broadcast.
pub async fn open_account_observation(
    target: BridgeAccountObservationTarget,
) -> Result<BridgeAccountObservation, BridgeError> {
    let bridge = active_bridge().await?;
    let observation = bridge.studio.open_account_observation(target.into())?;
    let inner = Arc::new(BridgeAccountObservationInner {
        id: bridge.subscriptions.next_id(),
        observation,
        shutdown: bridge.shutdown.child_token(),
        settled: AtomicBool::new(false),
        closing: AtomicBool::new(false),
        next_gate: tokio::sync::Mutex::new(()),
    });
    bridge
        .subscriptions
        .register_account_observation(&inner, &bridge.shutdown)?;
    Ok(BridgeAccountObservation { inner })
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
    pub(crate) inner: Arc<BridgeAccountObservationInner>,
}

pub(crate) struct BridgeAccountObservationInner {
    pub(crate) id: u64,
    observation: AccountObservation,
    shutdown: CancellationToken,
    settled: AtomicBool,
    closing: AtomicBool,
    next_gate: tokio::sync::Mutex<()>,
}

impl BridgeAccountObservationInner {
    pub(crate) fn request_close(&self) {
        self.closing.store(true, Ordering::Release);
        self.observation.request_close();
    }
    pub(crate) fn is_settled(&self) -> bool {
        self.settled.load(Ordering::Acquire)
    }
    pub(crate) async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        self.observation.close().await?;
        let _next = self.next_gate.lock().await;
        self.settled.store(true, Ordering::Release);
        Ok(())
    }
}

impl BridgeAccountObservation {
    pub async fn next(&self) -> Result<Option<BridgeAccountDomainFrame>, BridgeError> {
        if self.inner.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        let _next = self.inner.next_gate.try_lock().map_err(|_| {
            BridgeError::from(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Busy,
                "An account next read is already in flight",
                true,
            ))
        })?;
        if self.inner.closing.load(Ordering::Acquire) {
            return Ok(None);
        }
        tokio::select! {
            biased;
            _ = self.inner.shutdown.cancelled() => { self.inner.request_close(); Ok(None) },
            next = self.inner.observation.next() => Ok(next?.map(convert::frame)),
        }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.request_close();
    }

    /// Cancellation or timeout retains this exact registered owner for a later close retry.
    pub async fn close(&self) -> Result<(), BridgeError> {
        self.inner.close().await?;
        if let Some(bridge) = current_bridge() {
            bridge
                .subscriptions
                .unregister_account_observation(self.inner.id);
        }
        Ok(())
    }
}
