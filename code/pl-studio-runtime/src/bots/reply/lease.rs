//! Owns the durable claim fence for all reply side effects and heartbeat waits.
use super::session::ReplySession;
use super::tasks::ReplyIdentity;
use crate::bots::{
    owner::BotRuntime,
    storage::{ClaimLease, FrozenInbound},
};
use std::time::Duration;
use tokio_util::sync::CancellationToken;

const CLAIM_RENEW_INTERVAL: Duration = Duration::from_secs(15);

pub(super) enum ClaimGuard {
    Held,
    Lost,
}

pub(super) struct ClaimLeaseGuard {
    runtime: BotRuntime,
    identity: ReplyIdentity,
}

impl ClaimLeaseGuard {
    pub(super) fn new(runtime: BotRuntime, inbound: &FrozenInbound, worker_id: &str) -> Self {
        Self {
            runtime,
            identity: ReplyIdentity::new(inbound, worker_id),
        }
    }

    /// Close waits for the reply runner to drain. A lost lease independently
    /// cancels the runner before it can start another side effect.
    pub(super) async fn until_lost(&self, cancel: &CancellationToken) {
        loop {
            tokio::select! {
                _ = cancel.cancelled() => std::future::pending::<()>().await,
                _ = tokio::time::sleep(CLAIM_RENEW_INTERVAL) => {}
            }
            let identity = &self.identity;
            if matches!(
                self.runtime
                    .renew_reply_claim(
                        &identity.bot_id,
                        &identity.chat_id,
                        &identity.message_id,
                        &identity.worker_id
                    )
                    .await,
                ClaimGuard::Lost
            ) {
                return;
            }
        }
    }
}

impl BotRuntime {
    pub(super) async fn renew_claim(&self, run: &ReplySession) -> ClaimGuard {
        self.renew_reply_claim(&run.bot_id, &run.chat_id, &run.message_id, &run.worker_id)
            .await
    }

    async fn renew_reply_claim(
        &self,
        bot_id: &str,
        chat_id: &str,
        message_id: &str,
        worker_id: &str,
    ) -> ClaimGuard {
        let Ok(managed) = self.managed(bot_id).await else {
            return ClaimGuard::Lost;
        };
        match managed
            .store
            .renew_inbound_claim(bot_id, chat_id, message_id, worker_id)
            .await
        {
            Ok(ClaimLease::Renewed) => ClaimGuard::Held,
            Ok(ClaimLease::LostClaim) | Err(_) => ClaimGuard::Lost,
        }
    }
}
