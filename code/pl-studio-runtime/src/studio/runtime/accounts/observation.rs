use super::super::StudioRuntime;
use crate::StudioProductTopic;
use anyhow::Result;
use pl_protocol::studio::{
    AccountDomainFrame, AccountObservationTarget, ResourceStamp, StudioError, StudioErrorCode,
};
use std::sync::Arc;
use tokio::sync::{Mutex, watch};
use tokio_util::sync::CancellationToken;

/// A pull-only latest complete frame. There is no producer task, ACK, timer or unbounded port.
#[derive(Clone)]
pub struct AccountObservation {
    inner: Arc<ObservationInner>,
}

struct ObservationInner {
    runtime: StudioRuntime,
    target: AccountObservationTarget,
    cancellation: CancellationToken,
    next: Mutex<ReadState>,
}

struct ReadState {
    signal: Option<watch::Receiver<()>>,
    initial: bool,
    last: Option<ResourceStamp>,
    target_revision: Option<Option<u64>>,
}

pub(super) fn open(
    runtime: StudioRuntime,
    target: AccountObservationTarget,
) -> Result<AccountObservation> {
    let topic = match &target {
        AccountObservationTarget::Summaries => StudioProductTopic::SettingsConfig,
        AccountObservationTarget::Detail { identity } => {
            let id = match identity {
                super::AccountIdentity::Native { account_id }
                | super::AccountIdentity::Acp { account_id } => account_id,
            };
            if id.trim().is_empty() {
                return Err(StudioError::invalid_argument("Account identity is required").into());
            }
            StudioProductTopic::SettingsConfig
        }
        AccountObservationTarget::Models { account_id } => {
            pl_model::config::AccountId::new(account_id)?;
            StudioProductTopic::ModelCatalog
        }
        AccountObservationTarget::Usage => StudioProductTopic::AccountUsage,
        AccountObservationTarget::AcpAuth => StudioProductTopic::AcpAuth,
        AccountObservationTarget::AcpInstall => StudioProductTopic::AcpInstall,
    };
    let signal = runtime
        .agent_facility
        .product_events
        .subscribe_topic_signal(&topic);
    Ok(AccountObservation {
        inner: Arc::new(ObservationInner {
            runtime,
            target,
            cancellation: CancellationToken::new(),
            next: Mutex::new(ReadState {
                signal: Some(signal),
                initial: true,
                last: None,
                target_revision: None,
            }),
        }),
    })
}

impl AccountObservation {
    /// At most one in-flight call. The consumer reduces this frame before asking for the next.
    /// Dropping a wait cannot lose a frame: watch retains a wake and the next call rereads the owner.
    pub async fn next(&self) -> Result<Option<AccountDomainFrame>> {
        let mut state = self.inner.next.try_lock().map_err(|_| {
            StudioError::new(
                StudioErrorCode::Busy,
                "An account next read is already in flight",
                true,
            )
        })?;
        loop {
            if self.inner.cancellation.is_cancelled() {
                return Ok(None);
            }
            if !state.initial {
                let Some(signal) = state.signal.as_mut() else {
                    return Ok(None);
                };
                tokio::select! {
                    biased;
                    _ = self.inner.cancellation.cancelled() => return Ok(None),
                    changed = signal.changed() => { if changed.is_err() { return Ok(None); } }
                }
            }
            state.initial = false;
            if let Some(signal) = state.signal.as_mut() {
                signal.borrow_and_update();
            }
            let target_revision = match &self.inner.target {
                AccountObservationTarget::Detail { identity } => Some(
                    self.inner
                        .runtime
                        .config_runtime
                        .account_configuration_revision(identity)?,
                ),
                AccountObservationTarget::Models { account_id } => Some(
                    self.inner
                        .runtime
                        .config_runtime
                        .account_catalog_revision(account_id)?,
                ),
                _ => None,
            };
            if target_revision.is_some() && target_revision == state.target_revision {
                continue;
            }
            let frame = self.inner.runtime.read_account_domain(&self.inner.target)?;
            let stamp = stamp(&frame);
            if state.last.as_ref().is_some_and(|old| old == stamp) {
                continue;
            }
            // There is no await between owner read, last-delivered stamp, and returning the frame.
            state.last = Some(stamp.clone());
            state.target_revision = target_revision;
            return Ok(Some(frame));
        }
    }

    /// Seals admission and wakes an idle next read. It does not cancel any accepted business work.
    pub fn request_close(&self) {
        self.inner.cancellation.cancel();
    }

    /// Waits for the actual next-read lease before releasing its original registered receiver.
    pub async fn close(&self) -> Result<()> {
        self.request_close();
        self.inner.next.lock().await.signal.take();
        Ok(())
    }
}

fn stamp(frame: &AccountDomainFrame) -> &ResourceStamp {
    match frame {
        AccountDomainFrame::Summaries { stamp, .. }
        | AccountDomainFrame::Detail { stamp, .. }
        | AccountDomainFrame::Models { stamp, .. }
        | AccountDomainFrame::Usage { stamp, .. }
        | AccountDomainFrame::AcpAuth { stamp, .. }
        | AccountDomainFrame::AcpInstall { stamp, .. } => stamp,
    }
}
