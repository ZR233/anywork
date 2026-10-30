//! Thread-scoped reply admission and retained join/ledger responsibilities.
use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;
use std::sync::Arc;

use tokio::sync::OwnedSemaphorePermit;
use tokio::task::{Id, JoinError, JoinSet};
use tokio_util::sync::CancellationToken;

use super::InboundWorkOutcome;
use super::owner::{BotRuntime, BotRuntimeInner};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::storage::{FrozenInbound, MarkOutcome, WorkFinish};

#[derive(Clone)]
pub(super) struct ReplyIdentity {
    pub bot_id: String,
    pub chat_id: String,
    pub message_id: String,
    pub worker_id: String,
}

impl ReplyIdentity {
    pub(super) fn new(inbound: &FrozenInbound, worker_id: &str) -> Self {
        Self {
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            worker_id: worker_id.into(),
        }
    }

    async fn finish(
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

pub(super) struct PendingReplyFinish {
    identity: ReplyIdentity,
    outcome: InboundWorkOutcome,
}

pub(super) type ReplyResult = Result<InboundWorkOutcome, Box<PendingReplyFinish>>;

struct ReplyOwner {
    thread_id: String,
    identity: ReplyIdentity,
    cancellation: CancellationToken,
    // A failed finisher still consumes the original bounded reply budget.
    _permit: OwnedSemaphorePermit,
}

#[derive(Default)]
pub(super) struct BotReplyTasks {
    tasks: JoinSet<ReplyResult>,
    owners: BTreeMap<Id, ReplyOwner>,
    pending: Vec<(ReplyOwner, PendingReplyFinish)>,
    faults: BTreeSet<String>,
}

impl BotReplyTasks {
    /// A claimed work item rejected before spawning still owns its original finisher.
    pub(super) fn finish_unstarted<'a>(
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
    pub(super) fn spawn(
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

    pub(super) fn reap(&mut self) {
        while let Some(joined) = self.tasks.try_join_next_with_id() {
            self.accept_join(joined);
        }
    }

    async fn join_one(&mut self) -> Result<(), FeishuError> {
        let joined = self
            .tasks
            .join_next_with_id()
            .await
            .ok_or_else(|| archive_error("bot reply join owner is missing"))?;
        self.accept_join(joined);
        Ok(())
    }

    pub(super) async fn retry_finishes(
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

    fn report_faults(&mut self, threads: Option<&BTreeSet<String>>) -> Result<(), FeishuError> {
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

/// The reliable archive operation remains the durable seal after this guard drops.
pub(crate) struct BotArchiveGuard {
    inner: Arc<BotRuntimeInner>,
    threads: BTreeSet<String>,
}

impl Drop for BotArchiveGuard {
    fn drop(&mut self) {
        let mut seals = self
            .inner
            .reply_archive_seals
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        for id in &self.threads {
            if let Some(count) = seals.get_mut(id) {
                *count -= 1;
                if *count == 0 {
                    seals.remove(id);
                }
            }
        }
    }
}

impl BotRuntime {
    /// Call after the archive scope is durable, and retain the guard until publication.
    pub(crate) async fn quiesce_archive_threads(
        &self,
        thread_ids: &[String],
    ) -> Result<BotArchiveGuard, FeishuError> {
        let threads = thread_ids.iter().cloned().collect::<BTreeSet<_>>();
        let mut replies = self.inner.replies.lock().await;
        let guard = BotArchiveGuard {
            inner: self.inner.clone(),
            threads,
        };
        {
            let mut seals = self
                .inner
                .reply_archive_seals
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            for id in &guard.threads {
                *seals.entry(id.clone()).or_default() += 1;
            }
        }
        for owner in replies.owners.values() {
            if guard.threads.contains(&owner.thread_id) {
                owner.cancellation.cancel();
            }
        }
        while replies
            .owners
            .values()
            .any(|owner| guard.threads.contains(&owner.thread_id))
        {
            replies.join_one().await?;
        }
        replies.retry_finishes(self, Some(&guard.threads)).await?;
        replies.report_faults(Some(&guard.threads))?;
        Ok(guard)
    }

    /// Used under the reply registration mutex, never the runtime lifecycle lock.
    pub(super) async fn ensure_reply_admission(
        &self,
        workspace_id: &str,
        thread_id: &str,
    ) -> Result<(), FeishuError> {
        if self
            .inner
            .reply_archive_seals
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .contains_key(thread_id)
        {
            return Err(archive_error("bot Thread archive is in progress"));
        }
        self.studio_host()
            .ok_or_else(|| archive_error("studio runtime host is unavailable"))?
            .ensure_bot_dispatch_allowed(workspace_id, thread_id)
            .await
            .map_err(|error| {
                archive_error(&format!("bot Thread dispatch admission failed: {error:#}"))
            })
    }

    pub(super) async fn finish_reply(
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

    pub(super) async fn drain_replies(&self) -> Result<(), FeishuError> {
        let mut replies = self.inner.replies.lock().await;
        while !replies.owners.is_empty() {
            replies.join_one().await?;
        }
        replies.retry_finishes(self, None).await?;
        replies.report_faults(None)
    }
}

fn archive_error(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Unavailable, message, true, None)
}
