//! Registration and sealing share one lock; the actual JoinHandle remains registered while joined.

use super::{unavailable, worker};
use crate::bots::BotRuntime;
use crate::bots::owner::ManagedBot;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::publication::{DeliveryScope, DeliveryScopePage};
use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

const TASK_LIMIT: usize = 8;
// A fixed reservation covers the bounded identity index (4 MiB), the core tail's 8 MiB cache
// plus core->wire conversion overlap, small pages, metadata and frozen request/SQL copies.
// It is released with the cycle, not cumulatively increased on every scan/token.
// The shared 64 MiB budget can impose a smaller concurrency than the task-count hard cap.
pub(super) const CYCLE_BYTES: usize = 30 * 1024 * 1024;
pub(super) const IDENTITY_BYTES: usize = 4 * 1024 * 1024;

pub(in crate::bots) struct PublicationTasks {
    state: Mutex<State>,
}

struct State {
    sealed: bool,
    tasks: BTreeMap<(String, String), Task>,
    failure: Option<FeishuError>,
    next_bot: Option<String>,
}

struct Task {
    cancel: CancellationToken,
    handle: JoinHandle<Result<(), FeishuError>>,
}

impl PublicationTasks {
    pub(in crate::bots) fn new() -> Self {
        Self {
            state: Mutex::new(State {
                sealed: false,
                tasks: BTreeMap::new(),
                failure: None,
                next_bot: None,
            }),
        }
    }

    async fn register(
        &self,
        runtime: &BotRuntime,
        managed: Arc<ManagedBot>,
        scope: DeliveryScope,
    ) -> Result<bool, FeishuError> {
        let key = (scope.bot_id.clone(), scope.key.storage_key()?);
        let mut state = self.state.lock().await;
        reap(&mut state).await;
        if state.sealed || runtime.inner.sealed.load(Ordering::Acquire) != 0 {
            return Ok(false);
        }
        if state.tasks.contains_key(&key) {
            return Ok(true);
        }
        if state.tasks.len() >= TASK_LIMIT {
            return Ok(false);
        }
        let budget = match runtime.inner.occupancy.task_budget(CYCLE_BYTES) {
            Ok(budget) => budget,
            Err(error) if error.retryable() => return Ok(false),
            Err(error) => return Err(error),
        };
        let cancel = CancellationToken::new();
        let worker_cancel = cancel.clone();
        let worker = runtime.clone();
        let handle = tokio::spawn(async move {
            let _budget = budget;
            worker::run(worker, managed, scope, worker_cancel).await
        });
        state.tasks.insert(key, Task { cancel, handle });
        Ok(true)
    }

    pub(in crate::bots) async fn stop_and_drain(&self) -> Result<(), FeishuError> {
        let mut state = self.state.lock().await;
        state.sealed = true;
        for task in state.tasks.values() {
            task.cancel.cancel();
        }
        while let Some(key) = state.tasks.keys().next().cloned() {
            // No take()/abort: if this waiter is cancelled, the same handle stays in the registry.
            let joined = (&mut state.tasks.get_mut(&key).expect("registered task").handle).await;
            state.tasks.remove(&key);
            record_result(&mut state, joined);
        }
        match state.failure.take() {
            Some(error) => Err(error),
            None => Ok(()),
        }
    }

    async fn finished_error(&self) -> Option<FeishuError> {
        let mut state = self.state.lock().await;
        reap(&mut state).await;
        state.failure.take()
    }

    async fn recovery_turn(&self, bot: &str, published: &[String]) -> bool {
        let mut state = self.state.lock().await;
        if state
            .next_bot
            .as_ref()
            .is_none_or(|next| !published.contains(next))
        {
            state.next_bot = published.first().cloned();
        }
        state.next_bot.as_deref() == Some(bot)
    }

    async fn advance_bot(&self, bot: &str, published: &[String]) {
        let mut state = self.state.lock().await;
        if state.next_bot.as_deref() == Some(bot) {
            state.next_bot = published
                .iter()
                .find(|next| next.as_str() > bot)
                .or_else(|| published.first())
                .cloned();
        }
    }
}

async fn reap(state: &mut State) {
    let ready: Vec<_> = state
        .tasks
        .iter()
        .filter(|(_, task)| task.handle.is_finished())
        .map(|(key, _)| key.clone())
        .collect();
    for key in ready {
        let joined = (&mut state.tasks.get_mut(&key).expect("registered task").handle).await;
        state.tasks.remove(&key);
        record_result(state, joined);
    }
}

fn record_result(
    state: &mut State,
    result: Result<Result<(), FeishuError>, tokio::task::JoinError>,
) {
    let failure = match result {
        Ok(Ok(())) => return,
        Ok(Err(error)) => error,
        Err(_) => unavailable(
            "publication owner terminated abnormally; original ledger recovery is required",
        ),
    };
    if state.failure.is_none() {
        state.failure = Some(failure);
    }
}

impl BotRuntime {
    /// Called by the existing recovery owner. The keyset cursor resumes immediately after the
    /// last admitted scope, preserving the first unadmitted scope on backpressure, and wraps at EOF.
    pub(in crate::bots) async fn recover_publications(
        &self,
        bot_id: &str,
    ) -> Result<(), FeishuError> {
        if self.inner.sealed.load(Ordering::Acquire) != 0 {
            return Ok(());
        }
        if let Some(error) = self.inner.publications.finished_error().await {
            return Err(error);
        }
        // Only a rotor over the original managed-bot registry, not another queue or list of
        // obligations. It prevents a small byte-limited pool from always serving bot #1 first.
        let published: Vec<String> = self
            .inner
            .bots
            .lock()
            .await
            .iter()
            .filter_map(|(id, record)| record.published.as_ref().map(|_| id.clone()))
            .collect();
        if !self
            .inner
            .publications
            .recovery_turn(bot_id, &published)
            .await
        {
            return Ok(());
        }
        let recovered = async {
            let managed = self.managed(bot_id).await?;
            let mut after = managed.publication_recovery_cursor.lock().await;
            let page: DeliveryScopePage = managed
                .store
                .delivery_scopes(after.as_deref(), TASK_LIMIT)
                .await?;
            let mut admitted = false;
            for scope in page.scopes {
                if scope.bot_id != bot_id {
                    return Err(super::attention("publication scope belongs to another bot"));
                }
                let key = scope.key.storage_key()?;
                if !self
                    .inner
                    .publications
                    .register(self, managed.clone(), scope)
                    .await?
                {
                    return Ok(admitted);
                }
                admitted = true;
                *after = Some(key);
            }
            *after = page.next_after;
            Ok(true)
        }
        .await;
        // An unreadable bot/scope must not pin the global rotor and starve every healthy bot.
        // Only pure capacity backpressure before any admission keeps the next turn reserved.
        if !matches!(recovered, Ok(false)) {
            self.inner
                .publications
                .advance_bot(bot_id, &published)
                .await;
        }
        recovered.map(|_| ())
    }
}
