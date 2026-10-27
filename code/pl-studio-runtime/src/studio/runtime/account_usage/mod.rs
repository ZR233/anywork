//! Canonical per-account query stages, last-good facts and retained operation ownership.

mod cache;
mod projection;
pub(crate) use cache::AccountUsageCacheMigrationError;

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, PoisonError, Weak};

use anyhow::{Result, anyhow};
use futures::FutureExt;
use pl_model::config::AccountId;
use pl_protocol::{
    ObservedResource,
    studio::{
        AccountUsageFailure, AccountUsageFailureCode, AccountUsageObservation, AccountUsagePhase,
    },
};
use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;

use crate::account_usage::query_account_usage;
use crate::config::{ConfigRuntime, ConfigRuntimeSnapshot};
use crate::studio::ids::unix_seconds;
use crate::{AccountUsageRecord, StudioStore};

const CACHE_KEY: &str = "observed:accountUsage:v2";

/// Legacy public product-topic representation; the v2 load decoder remains unchanged.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountUsageStateSnapshot {
    pub state: ObservedResource<AccountUsageStateData>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountUsageStateData {
    pub config_fingerprint: String,
    pub usages: Vec<AccountUsageRecord>,
}

#[derive(Clone)]
pub(crate) struct AccountUsageRuntime {
    store: StudioStore,
    config: ConfigRuntime,
    state: Arc<Mutex<UsageState>>,
    tasks: Arc<Mutex<UsageTasks>>,
    commit: Arc<tokio::sync::Mutex<()>>,
    events: crate::ProductEventBus,
}

#[derive(Default)]
struct UsageState {
    revision: u64,
    updated_at: i64,
    accounts: BTreeMap<AccountId, AccountUsageObservation>,
    // Private persistence identities never enter HTTP/FRB frames or diagnostics.
    query_identities: BTreeMap<AccountId, String>,
    legacy_unbound: Option<String>,
}

#[derive(Default)]
struct UsageTasks {
    closing: bool,
    next_id: u64,
    active: BTreeMap<AccountId, u64>,
    retained: BTreeMap<u64, Arc<UsageTask>>,
}

struct UsageTask {
    query_revision: u64,
    cancel: CancellationToken,
    join: tokio::sync::Mutex<Option<tokio::task::JoinHandle<Result<()>>>>,
    outcome: Mutex<Option<Result<(), String>>>,
}

impl UsageTask {
    fn finished(&self) -> bool {
        self.join
            .try_lock()
            .is_ok_and(|slot| slot.as_ref().is_none_or(|task| task.is_finished()))
    }

    async fn wait(&self) -> Result<()> {
        let mut slot = self.join.lock().await;
        if let Some(task) = slot.as_mut() {
            let result = match task.await {
                Ok(result) => result.map_err(|error| format!("{error:#}")),
                Err(error) => Err(format!("account usage task failed: {error}")),
            };
            slot.take();
            *self.outcome.lock().unwrap_or_else(PoisonError::into_inner) = Some(result);
        }
        match self
            .outcome
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .as_ref()
        {
            Some(Err(error)) => Err(anyhow!("{error}")),
            _ => Ok(()),
        }
    }
}

struct UsageConfigObserver {
    state: Weak<Mutex<UsageState>>,
    tasks: Weak<Mutex<UsageTasks>>,
    events: crate::ProductEventBus,
}

impl crate::config::SettingsCommitObserver for UsageConfigObserver {
    fn settings_committed(&self, snapshot: &ConfigRuntimeSnapshot) {
        let Some(state) = self.state.upgrade() else {
            return;
        };
        let mut state = state.lock().unwrap_or_else(PoisonError::into_inner);
        let mut changed = false;
        state.accounts.retain(|id, _| {
            let keep = snapshot.usage_query_revision(id).is_some();
            changed |= !keep;
            keep
        });
        state
            .query_identities
            .retain(|id, _| snapshot.usage_query_revision(id).is_some());
        for (id, account) in &snapshot.config.models.accounts {
            let Some(revision) = snapshot.usage_query_revision(id) else {
                continue;
            };
            if state
                .accounts
                .get(id)
                .is_none_or(|entry| entry.query_revision != revision)
            {
                state.accounts.insert(id.clone(), unchecked(id, revision));
                state
                    .query_identities
                    .insert(id.clone(), cache::query_identity(id, account));
                changed = true;
            }
        }
        if changed {
            state.revision = state.revision.saturating_add(1);
            state.updated_at = unix_seconds();
            // No IO/await/reentry while ConfigRuntime holds its command boundary.
            self.events
                .emit_account_usage_state(projection::legacy_snapshot(&state));
        }
        drop(state);
        if let Some(tasks) = self.tasks.upgrade() {
            let tasks = tasks.lock().unwrap_or_else(PoisonError::into_inner);
            for (id, key) in &tasks.active {
                if let Some(task) = tasks.retained.get(key)
                    && snapshot.usage_query_revision(id) != Some(task.query_revision)
                {
                    task.cancel.cancel();
                }
            }
        }
    }
}

impl AccountUsageRuntime {
    pub(crate) fn new(
        store: StudioStore,
        config: ConfigRuntime,
        events: crate::ProductEventBus,
    ) -> Self {
        Self {
            store,
            config,
            events,
            state: Arc::new(Mutex::new(UsageState::default())),
            tasks: Arc::new(Mutex::new(UsageTasks::default())),
            commit: Arc::new(tokio::sync::Mutex::new(())),
        }
    }

    pub(crate) async fn load_cache(&self) -> Result<()> {
        let config = self.config.read()?;
        if let Some(value) = self.store.load_setting(CACHE_KEY).await? {
            let loaded = cache::load(&value, &config)?;
            // Explicit domain load migration, before normal observers. The old bytes are retained.
            if loaded.migrated {
                self.store
                    .save_setting(CACHE_KEY, &cache::encode(&loaded.state)?)
                    .await?;
            }
            *self.state.lock().unwrap_or_else(PoisonError::into_inner) = loaded.state;
        }
        self.config
            .install_settings_observer(Arc::new(UsageConfigObserver {
                state: Arc::downgrade(&self.state),
                tasks: Arc::downgrade(&self.tasks),
                events: self.events.clone(),
            }))?;
        Ok(())
    }

    pub(crate) async fn read(&self) -> AccountUsageStateSnapshot {
        projection::legacy_snapshot(&self.state.lock().unwrap_or_else(PoisonError::into_inner))
    }

    pub(crate) fn observations(&self) -> (u64, Vec<AccountUsageObservation>) {
        let state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        (state.revision, state.accounts.values().cloned().collect())
    }

    /// Caller cancellation stops waiting, never the registered network/commit owner.
    pub(crate) async fn check(&self, account_id: &str) -> Result<AccountUsageStateSnapshot> {
        let id = AccountId::new(account_id)?;
        let finished = {
            let tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            tasks
                .retained
                .iter()
                .filter(|(_, task)| task.finished())
                .map(|(key, task)| (*key, Arc::clone(task)))
                .collect::<Vec<_>>()
        };
        for (key, task) in finished {
            let outcome = task.wait().await;
            let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            tasks.retained.remove(&key);
            tasks.active.retain(|_, active| *active != key);
            if outcome.is_err() {
                tracing::warn!(
                    "a completed usage operation failed; its typed failure remains observable"
                );
            }
        }
        // Config -> task registry is the lock order also used by the commit observer.
        let config = self.config.read()?;
        let revision = config.usage_query_revision(&id).ok_or_else(|| {
            pl_protocol::studio::StudioError::invalid_argument("Account does not exist")
        })?;
        let account = config
            .config
            .models
            .accounts
            .get(&id)
            .cloned()
            .ok_or_else(|| anyhow!("account configuration is missing"))?;
        let task = {
            // The commit observer and admission share this short state boundary. An older caller
            // arriving after a newer generation must not cancel/overwrite that generation's slot.
            let state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            if state.accounts.get(&id).map(|entry| entry.query_revision) != Some(revision) {
                return Ok(projection::legacy_snapshot(&state));
            }
            let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            if tasks.closing {
                return Err(stopped());
            }
            if let Some(task) = tasks
                .active
                .get(&id)
                .and_then(|key| tasks.retained.get(key))
                && task.query_revision == revision
                && !task.finished()
            {
                Arc::clone(task)
            } else {
                if let Some(old) = tasks
                    .active
                    .get(&id)
                    .and_then(|key| tasks.retained.get(key))
                {
                    old.cancel.cancel();
                }
                tasks.next_id = tasks
                    .next_id
                    .checked_add(1)
                    .ok_or_else(|| anyhow!("usage operation identity exhausted"))?;
                let key = tasks.next_id;
                let cancel = CancellationToken::new();
                let worker_cancel = cancel.clone();
                let runtime = self.clone();
                let target = id.clone();
                let operation_id = format!("account-usage-{id}-{revision}-{key}");
                let join = tokio::spawn(async move {
                    let result = std::panic::AssertUnwindSafe(runtime.run_check(
                        target.clone(),
                        revision,
                        account,
                        operation_id,
                        worker_cancel,
                    ))
                    .catch_unwind()
                    .await;
                    let result = match result {
                        Ok(result) => result,
                        Err(_) => Err(anyhow!("account usage worker panicked")),
                    };
                    if result.is_err() {
                        runtime.fail_query(&target, revision);
                    }
                    result
                });
                let task = Arc::new(UsageTask {
                    query_revision: revision,
                    cancel,
                    join: tokio::sync::Mutex::new(Some(join)),
                    outcome: Mutex::new(None),
                });
                tasks.retained.insert(key, Arc::clone(&task));
                tasks.active.insert(id, key);
                task
            }
        };
        task.wait().await?;
        Ok(self.read().await)
    }

    async fn run_check(
        &self,
        id: AccountId,
        revision: u64,
        account: pl_model::config::AccountConfig,
        operation_id: String,
        cancel: CancellationToken,
    ) -> Result<()> {
        let accepted = self.config.if_usage_query_current(&id, revision, || {
            let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            if let Some(entry) = state.accounts.get_mut(&id) {
                entry.phase = AccountUsagePhase::Querying;
                entry.operation_id = Some(operation_id.clone());
                entry.failure = None;
                entry.revision = entry.revision.saturating_add(1);
                self.publish_locked(&mut state);
            }
        })?;
        if !accepted {
            return Ok(());
        }
        let observed = tokio::select! {
            biased;
            _ = cancel.cancelled() => None,
            result = query_account_usage(AccountUsageRecord::new(id.to_string()), account, operation_id.clone()) => Some(result?),
        };
        let _commit = self.commit.lock().await;
        let accepted = self.config.if_usage_query_current(&id, revision, || {
            let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            if let Some(entry) = state.accounts.get_mut(&id) {
                projection::complete(entry, observed.as_ref());
                self.publish_locked(&mut state);
            }
        })?;
        if !accepted {
            return Ok(());
        }
        let encoded = cache::encode(&self.state.lock().unwrap_or_else(PoisonError::into_inner))?;
        // Worker is never aborted while this durable operation is in flight.
        self.store.save_setting(CACHE_KEY, &encoded).await?;
        Ok(())
    }

    fn publish_locked(&self, state: &mut UsageState) {
        state.revision = state.revision.saturating_add(1);
        state.updated_at = unix_seconds();
        self.events
            .emit_account_usage_state(projection::legacy_snapshot(state));
    }

    fn fail_query(&self, id: &AccountId, revision: u64) {
        let result = self.config.if_usage_query_current(id, revision, || {
            let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            if let Some(entry) = state.accounts.get_mut(id) {
                entry.phase = AccountUsagePhase::Failed;
                entry.failure = Some(AccountUsageFailure {
                    code: AccountUsageFailureCode::TaskFailed,
                    retryable: true,
                });
                entry.revision = entry.revision.saturating_add(1);
                self.publish_locked(&mut state);
            }
        });
        if result.is_err() {
            tracing::error!("could not publish usage worker failure after owner shutdown");
        }
    }

    pub(crate) fn request_close(&self) {
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.closing = true;
        for task in tasks.retained.values() {
            task.cancel.cancel();
        }
    }

    pub(crate) async fn close(&self) -> Result<()> {
        self.request_close();
        let retained = self
            .tasks
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .retained
            .values()
            .cloned()
            .collect::<Vec<_>>();
        let mut failure = None;
        for task in retained {
            if let Err(error) = task.wait().await {
                failure.get_or_insert(error);
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.active.clear();
        tasks.retained.clear();
        Ok(())
    }
}

fn unchecked(id: &AccountId, revision: u64) -> AccountUsageObservation {
    AccountUsageObservation {
        account_id: id.to_string(),
        query_revision: revision,
        revision: 0,
        phase: AccountUsagePhase::Unchecked,
        operation_id: None,
        checked_at: None,
        failure: None,
        last_good: None,
    }
}

fn stopped() -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::RuntimeStopped,
        "Account usage owner is closing",
        false,
    )
    .into()
}
