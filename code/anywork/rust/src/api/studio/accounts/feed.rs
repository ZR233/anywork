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
use crate::pull_observation::{ManagedPullObservation, PullObservationSource};
use pl_lifecycle::Managed;
use pl_studio_runtime::accounts::AccountObservation;

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
                Ok(ManagedPullObservation::new(
                    source.open_account_observation(target.into())?,
                    shutdown,
                    "An account next read is already in flight",
                ))
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

impl PullObservationSource for AccountObservation {
    type Frame = BridgeAccountDomainFrame;

    async fn next(&self) -> Result<Option<Self::Frame>, BridgeError> {
        Ok(self.next().await?.map(convert::frame))
    }

    fn request_close(&self) {
        self.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        Ok(self.close().await?)
    }
}

/// An opaque pull handle: no FRB StreamSink or native port queue can bypass its one-next limit.
pub struct BridgeAccountObservation {
    inner: Managed<ManagedPullObservation<AccountObservation>>,
}

impl BridgeAccountObservation {
    pub async fn next(&self) -> Result<Option<BridgeAccountDomainFrame>, BridgeError> {
        self.inner.get().next().await
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
