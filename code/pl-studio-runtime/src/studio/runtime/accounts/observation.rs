use super::super::StudioRuntime;
use super::super::pull_observation::{PullObservation, PullSignal, PullStep};
use crate::StudioProductTopic;
use crate::studio::product_event_bus::ProductTopicSignal;
use crate::{
    AccountDomainFrame, AccountObservationTarget, ResourceStamp, StudioError, StudioErrorCode,
};
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

/// A pull-only latest complete frame. There is no producer task, ACK, timer or unbounded port.
#[derive(Clone)]
pub struct AccountObservation {
    inner: Arc<ObservationInner>,
}

struct ObservationInner {
    runtime: StudioRuntime,
    target: AccountObservationTarget,
    next: PullObservation<AccountSignal, AccountMemory>,
}

struct AccountMemory {
    last: Option<ResourceStamp>,
    target_revision: Option<Option<u64>>,
}

enum AccountSignal {
    Topic(ProductTopicSignal),
    Watch(watch::Receiver<()>),
}

impl AccountSignal {
    async fn changed(&mut self) -> Result<(), watch::error::RecvError> {
        match self {
            Self::Topic(signal) => signal.changed().await,
            Self::Watch(signal) => signal.changed().await,
        }
    }

    fn mark_current(&mut self) {
        match self {
            Self::Topic(signal) => signal.mark_current(),
            Self::Watch(signal) => {
                signal.borrow_and_update();
            }
        }
    }
}

impl PullSignal for AccountSignal {
    fn changed(
        &mut self,
    ) -> impl std::future::Future<Output = Result<(), watch::error::RecvError>> + Send {
        AccountSignal::changed(self)
    }

    fn mark_current(&mut self) {
        AccountSignal::mark_current(self);
    }
}

pub(super) fn open(
    runtime: StudioRuntime,
    target: AccountObservationTarget,
) -> Result<AccountObservation> {
    let signal = match &target {
        AccountObservationTarget::ChatGptLogin { .. } => {
            AccountSignal::Watch(runtime.chatgpt_auth.subscribe())
        }
        AccountObservationTarget::Usage => AccountSignal::Watch(runtime.account_usage.subscribe()),
        other => {
            let topic = match other {
                AccountObservationTarget::Summaries => StudioProductTopic::SettingsConfig,
                AccountObservationTarget::Detail { identity } => {
                    let id = match identity {
                        super::AccountIdentity::Native { account_id }
                        | super::AccountIdentity::Acp { account_id } => account_id,
                    };
                    if id.trim().is_empty() {
                        return Err(
                            StudioError::invalid_argument("Account identity is required").into(),
                        );
                    }
                    StudioProductTopic::SettingsConfig
                }
                AccountObservationTarget::Models { account_id } => {
                    pl_model::config::AccountId::new(account_id)?;
                    StudioProductTopic::ModelCatalog
                }
                AccountObservationTarget::AcpAuth => StudioProductTopic::AcpAuth,
                AccountObservationTarget::AcpInstall => StudioProductTopic::AcpInstall,
                AccountObservationTarget::AcpLocalDetection => {
                    StudioProductTopic::AcpLocalDetection
                }
                AccountObservationTarget::ChatGptLogin { .. } | AccountObservationTarget::Usage => {
                    unreachable!("handled above")
                }
            };
            AccountSignal::Topic(
                runtime
                    .agent_facility
                    .product_events
                    .subscribe_topic_signal(&topic),
            )
        }
    };
    let cancellation = CancellationToken::new();
    Ok(AccountObservation {
        inner: Arc::new(ObservationInner {
            runtime,
            target,
            next: PullObservation::open(
                signal,
                AccountMemory {
                    last: None,
                    target_revision: None,
                },
                cancellation,
            ),
        }),
    })
}

impl AccountObservation {
    /// At most one in-flight call. The consumer reduces this frame before asking for the next.
    /// Dropping a wait cannot lose a frame: watch retains a wake and the next call rereads the owner.
    pub async fn next(&self) -> Result<Option<AccountDomainFrame>> {
        self.inner
            .next
            .next(
                StudioError::new(
                    StudioErrorCode::Busy,
                    "An account next read is already in flight",
                    true,
                ),
                |memory| {
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
                    if target_revision.is_some() && target_revision == memory.target_revision {
                        return Ok(PullStep::WaitAgain);
                    }
                    let frame = self.inner.runtime.read_account_domain(&self.inner.target)?;
                    let stamp = stamp(&frame);
                    if memory.last.as_ref().is_some_and(|old| old == stamp) {
                        return Ok(PullStep::WaitAgain);
                    }
                    // There is no await between owner read, last-delivered stamp, and returning the frame.
                    memory.last = Some(stamp.clone());
                    memory.target_revision = target_revision;
                    Ok(PullStep::Deliver(frame))
                },
            )
            .await
    }

    /// Seals admission and wakes an idle next read. It does not cancel any accepted business work.
    pub fn request_close(&self) {
        self.inner.next.request_close();
    }

    /// Waits for the actual next-read lease before releasing its original registered receiver.
    pub async fn close(&self) -> Result<()> {
        self.inner.next.close().await
    }
}

fn stamp(frame: &AccountDomainFrame) -> &ResourceStamp {
    match frame {
        AccountDomainFrame::Summaries { stamp, .. }
        | AccountDomainFrame::ChatGptLogin { stamp, .. }
        | AccountDomainFrame::Detail { stamp, .. }
        | AccountDomainFrame::Models { stamp, .. }
        | AccountDomainFrame::Usage { stamp, .. }
        | AccountDomainFrame::AcpAuth { stamp, .. }
        | AccountDomainFrame::AcpInstall { stamp, .. }
        | AccountDomainFrame::AcpLocalDetection { stamp, .. } => stamp,
    }
}
