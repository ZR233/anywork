//! Canonical per-account query stages, last-good facts and retained operation ownership.

mod cache;
pub(crate) use cache::AccountUsageCacheMigrationError;

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, PoisonError, Weak};

use crate::{
    AccountUsageFailure, AccountUsageFailureCode, AccountUsageObservation, AccountUsagePhase,
    AccountUsageSuccess,
};
use anyhow::{Result, anyhow};
use futures::FutureExt;
use pl_model::config::AccountId;
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use crate::StudioStore;
use crate::account_usage::{AccountUsageQueryOutcome, query_account_usage};
use crate::config::{ConfigRuntime, ConfigRuntimeSnapshot};
use crate::studio::ids::unix_seconds;
use crate::studio::store::settings::payload::KEY as CACHE_KEY;

use super::acp_ops::retained_output;
use super::task_registry::RetainedTaskRegistry;

#[derive(Clone)]
pub(crate) struct AccountUsageRuntime {
    store: StudioStore,
    config: ConfigRuntime,
    state: Arc<Mutex<UsageState>>,
    tasks: Arc<Mutex<UsageTasks>>,
    commit: Arc<tokio::sync::Mutex<()>>,
    updates: watch::Sender<()>,
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
struct UsageTasks(RetainedTaskRegistry<AccountId, u64, Result<()>>);

impl Default for UsageTasks {
    fn default() -> Self {
        Self(RetainedTaskRegistry::default())
    }
}

impl std::ops::Deref for UsageTasks {
    type Target = RetainedTaskRegistry<AccountId, u64, Result<()>>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl std::ops::DerefMut for UsageTasks {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

async fn wait_usage(task: &super::acp_ops::RetainedTask<Result<()>>) -> Result<()> {
    retained_output(
        task.join().await,
        |result| result.map_err(|error| format!("{error:#}")),
        |error| format!("account usage task failed: {error}"),
    )
    .map_err(|error| anyhow!(error))
}

struct UsageConfigObserver {
    state: Weak<Mutex<UsageState>>,
    tasks: Weak<Mutex<UsageTasks>>,
    updates: watch::Sender<()>,
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
            let _ = self.updates.send(());
        }
        drop(state);
        if let Some(tasks) = self.tasks.upgrade() {
            let tasks = tasks.lock().unwrap_or_else(PoisonError::into_inner);
            for (id, task) in tasks.active_pairs() {
                if snapshot.usage_query_revision(id) != Some(task.payload) {
                    task.cancel.cancel();
                }
            }
        }
    }
}

impl AccountUsageRuntime {
    pub(crate) fn new(store: StudioStore, config: ConfigRuntime) -> Self {
        Self {
            store,
            config,
            updates: watch::channel(()).0,
            state: Arc::new(Mutex::new(UsageState::default())),
            tasks: Arc::new(Mutex::new(UsageTasks::default())),
            commit: Arc::new(tokio::sync::Mutex::new(())),
        }
    }

    pub(crate) fn subscribe(&self) -> watch::Receiver<()> {
        self.updates.subscribe()
    }

    pub(crate) async fn load_cache(&self) -> Result<()> {
        let config = self.config.read()?;
        if let Some(value) = self.store.load_setting(CACHE_KEY).await? {
            // The value is already the current payload: the Settings schema migration
            // boundary converted any historical bytes exactly once. Loading only binds
            // the retained observations to the current configuration; it never writes.
            let state = cache::load(&value, &config.config.models.accounts, |id| {
                config.usage_query_revision(id)
            })?;
            *self.state.lock().unwrap_or_else(PoisonError::into_inner) = state;
        }
        self.config
            .install_settings_observer(Arc::new(UsageConfigObserver {
                state: Arc::downgrade(&self.state),
                tasks: Arc::downgrade(&self.tasks),
                updates: self.updates.clone(),
            }))?;
        Ok(())
    }

    pub(crate) fn observations(&self) -> (u64, Vec<AccountUsageObservation>) {
        let state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        (state.revision, state.accounts.values().cloned().collect())
    }

    /// Caller cancellation stops waiting, never the registered network/commit owner.
    pub(crate) async fn check(&self, account_id: &str) -> Result<()> {
        let id = AccountId::new(account_id)?;
        let finished = {
            let tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            tasks
                .finished_ids()
                .into_iter()
                .filter_map(|key| tasks.task(key).map(|task| (key, task)))
                .collect::<Vec<_>>()
        };
        for (key, task) in finished {
            let outcome = wait_usage(&task).await;
            let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            tasks.remove(key);
            if outcome.is_err() {
                tracing::warn!(
                    "a completed usage operation failed; its typed failure remains observable"
                );
            }
        }
        // Config -> task registry is the lock order also used by the commit observer.
        let config = self.config.read()?;
        let revision = config
            .usage_query_revision(&id)
            .ok_or_else(|| crate::StudioError::invalid_argument("Account does not exist"))?;
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
                return Ok(());
            }
            let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            if tasks.is_closing() {
                return Err(stopped());
            }
            if let Some(task) = tasks
                .get(&id)
                .filter(|task| task.payload == revision && !task.task.finished())
            {
                Arc::clone(&task.task)
            } else {
                if let Some(old) = tasks.get(&id) {
                    old.cancel.cancel();
                }
                let key = tasks
                    .allocate_id()
                    .ok_or_else(|| anyhow!("usage operation identity exhausted"))?;
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
                let task = tasks.retain(key, id, revision, cancel, join);
                task
            }
        };
        wait_usage(&task).await
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
            outcome = query_account_usage(account) => Some(outcome),
        };
        let _commit = self.commit.lock().await;
        let accepted = self.config.if_usage_query_current(&id, revision, || {
            let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            if let Some(entry) = state.accounts.get_mut(&id) {
                complete_observation(entry, observed.clone());
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
        let _ = self.updates.send(());
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
        let _ = tasks.begin_close();
    }

    pub(crate) async fn close(&self) -> Result<()> {
        let retained = {
            let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
            tasks.begin_close()
        };
        let mut failure = None;
        for task in retained {
            if let Err(error) = wait_usage(&task).await {
                failure.get_or_insert(error);
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        let mut tasks = self.tasks.lock().unwrap_or_else(PoisonError::into_inner);
        tasks.clear();
        Ok(())
    }
}

fn complete_observation(
    entry: &mut AccountUsageObservation,
    result: Option<AccountUsageQueryOutcome>,
) {
    entry.checked_at = Some(unix_seconds());
    entry.revision = entry.revision.saturating_add(1);
    entry.failure = None;
    entry.phase = match result {
        Some(AccountUsageQueryOutcome::Ready { checked_at, value }) => {
            entry.last_good = Some(AccountUsageSuccess { checked_at, value });
            AccountUsagePhase::Succeeded
        }
        Some(AccountUsageQueryOutcome::Unsupported) => AccountUsagePhase::Unsupported,
        Some(AccountUsageQueryOutcome::MissingCredential) => AccountUsagePhase::MissingCredential,
        Some(AccountUsageQueryOutcome::Failed(failure)) => {
            entry.failure = Some(failure);
            AccountUsagePhase::Failed
        }
        None => {
            entry.failure = Some(AccountUsageFailure {
                code: AccountUsageFailureCode::Cancelled,
                retryable: true,
            });
            AccountUsagePhase::Failed
        }
    };
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
    crate::StudioError::new(
        crate::StudioErrorCode::RuntimeStopped,
        "Account usage owner is closing",
        false,
    )
    .into()
}
