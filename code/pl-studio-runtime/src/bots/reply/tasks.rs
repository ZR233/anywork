use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;

use tokio::sync::OwnedSemaphorePermit;
use tokio::task::{Id, JoinError, JoinSet};
use tokio_util::sync::CancellationToken;

use crate::bots::InboundWorkOutcome;
use crate::bots::owner::BotRuntime;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{FrozenInbound, MarkOutcome, WorkFinish};

use crate::bots::archive::archive_error;

#[derive(Clone)]
pub(in crate::bots) struct ReplyIdentity {
    pub bot_id: String,
    pub chat_id: String,
    pub message_id: String,
    pub worker_id: String,
}

impl ReplyIdentity {
    pub(in crate::bots) fn new(inbound: &FrozenInbound, worker_id: &str) -> Self {
        Self {
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            worker_id: worker_id.into(),
        }
    }

    pub(in crate::bots) async fn finish(
        &self,
        runtime: &BotRuntime,
        outcome: &InboundWorkOutcome,
    ) -> Result<(), FeishuError> {
        let finish = match outcome {
            InboundWorkOutcome::Completed => WorkFinish::Completed,
            InboundWorkOutcome::Interrupted => WorkFinish::Interrupted,
            InboundWorkOutcome::Recoverable { diagnostic } => WorkFinish::Retryable(diagnostic),
            InboundWorkOutcome::NeedsAttention { diagnostic } => {
                WorkFinish::NeedsAttention(diagnostic)
            }
            // The successor owns the durable claim. Do not overwrite its result.
            InboundWorkOutcome::LostClaim => return Ok(()),
        };
        let managed = runtime.managed(&self.bot_id).await?;
        match managed
            .store
            .finish_inbound_work(
                &self.bot_id,
                &self.chat_id,
                &self.message_id,
                &self.worker_id,
                finish,
            )
            .await?
        {
            MarkOutcome::Applied | MarkOutcome::LostClaim => Ok(()),
        }
    }
}

pub(in crate::bots) struct PendingReplyFinish {
    pub(in crate::bots) identity: ReplyIdentity,
    pub(in crate::bots) outcome: InboundWorkOutcome,
}

pub(in crate::bots) type ReplyResult = Result<InboundWorkOutcome, Box<PendingReplyFinish>>;

pub(in crate::bots) struct ReplyOwner {
    pub(in crate::bots) thread_id: String,
    pub(in crate::bots) identity: ReplyIdentity,
    pub(in crate::bots) cancellation: CancellationToken,
    // A failed finisher still consumes the original bounded reply budget.
    _permit: OwnedSemaphorePermit,
}

#[derive(Default)]
pub(in crate::bots) struct BotReplyTasks {
    tasks: JoinSet<ReplyResult>,
    pub(in crate::bots) owners: BTreeMap<Id, ReplyOwner>,
    pending: Vec<(ReplyOwner, PendingReplyFinish)>,
    faults: BTreeSet<String>,
}

impl BotReplyTasks {
    /// A claimed work item rejected before spawning still owns its original finisher.
    pub(in crate::bots) fn finish_unstarted<'a>(
        &'a mut self,
        runtime: &'a BotRuntime,
        thread_id: String,
        identity: ReplyIdentity,
        cancellation: CancellationToken,
        permit: OwnedSemaphorePermit,
    ) -> impl Future<Output = Result<(), FeishuError>> + Send + 'a {
        // Register synchronously, even if the returned future is never polled.
        // Cancellation of a ledger wait must not release this claim's owner.
        self.pending.push((
            ReplyOwner {
                thread_id,
                identity: identity.clone(),
                cancellation,
                _permit: permit,
            },
            PendingReplyFinish {
                identity,
                outcome: InboundWorkOutcome::Interrupted,
            },
        ));
        self.retry_finishes(runtime, None)
    }

    /// Caller holds the same reply mutex used by archive sealing and shutdown.
    pub(in crate::bots) fn spawn(
        &mut self,
        thread_id: String,
        identity: ReplyIdentity,
        cancellation: CancellationToken,
        permit: OwnedSemaphorePermit,
        task: impl Future<Output = ReplyResult> + Send + 'static,
    ) {
        let handle = self.tasks.spawn(task);
        self.owners.insert(
            handle.id(),
            ReplyOwner {
                thread_id,
                identity,
                cancellation,
                _permit: permit,
            },
        );
    }

    fn accept_join(&mut self, joined: Result<(Id, ReplyResult), JoinError>) {
        let id = match &joined {
            Ok((id, _)) => *id,
            Err(error) => error.id(),
        };
        let owner = self
            .owners
            .remove(&id)
            .expect("reply registration and join share one owner");
        match joined {
            Ok((_, Ok(_))) => {}
            Ok((_, Err(pending))) => self.pending.push((owner, *pending)),
            Err(_) => {
                self.faults.insert(owner.thread_id.clone());
                let pending = PendingReplyFinish {
                    identity: owner.identity.clone(),
                    // This releases only the original work claim. It does not
                    // assert that its model/input side effects never happened.
                    outcome: InboundWorkOutcome::Interrupted,
                };
                self.pending.push((owner, pending));
            }
        }
    }

    pub(in crate::bots) fn reap(&mut self) {
        while let Some(joined) = self.tasks.try_join_next_with_id() {
            self.accept_join(joined);
        }
    }

    pub(in crate::bots) async fn join_one(&mut self) -> Result<(), FeishuError> {
        let joined = self
            .tasks
            .join_next_with_id()
            .await
            .ok_or_else(|| archive_error("bot reply join owner is missing"))?;
        self.accept_join(joined);
        Ok(())
    }

    pub(in crate::bots) async fn retry_finishes(
        &mut self,
        runtime: &BotRuntime,
        threads: Option<&BTreeSet<String>>,
    ) -> Result<(), FeishuError> {
        let mut index = 0;
        while index < self.pending.len() {
            let (owner, pending) = &self.pending[index];
            if threads.is_some_and(|threads| !threads.contains(&owner.thread_id)) {
                index += 1;
                continue;
            }
            pending.identity.finish(runtime, &pending.outcome).await?;
            self.pending.swap_remove(index);
        }
        Ok(())
    }

    pub(in crate::bots) fn report_faults(
        &mut self,
        threads: Option<&BTreeSet<String>>,
    ) -> Result<(), FeishuError> {
        let mut failed = false;
        self.faults.retain(|id| {
            if threads.is_none_or(|threads| threads.contains(id)) {
                failed = true;
                false
            } else {
                true
            }
        });
        if failed {
            return Err(archive_error("bot reply task terminated abnormally"));
        }
        Ok(())
    }
}

impl BotRuntime {
    pub(in crate::bots) async fn finish_reply(
        &self,
        identity: ReplyIdentity,
        outcome: InboundWorkOutcome,
    ) -> ReplyResult {
        match identity.finish(self, &outcome).await {
            Ok(()) => Ok(outcome),
            Err(error) => {
                tracing::warn!(%error, "bot reply ledger finish remains owned for retry");
                Err(Box::new(PendingReplyFinish { identity, outcome }))
            }
        }
    }

    pub(in crate::bots) async fn drain_replies(&self) -> Result<(), FeishuError> {
        let mut replies = self.inner.reply_work.tasks.lock().await;
        while !replies.owners.is_empty() {
            replies.join_one().await?;
        }
        replies.retry_finishes(self, None).await?;
        replies.report_faults(None)
    }
}
