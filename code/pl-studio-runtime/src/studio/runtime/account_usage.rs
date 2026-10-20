//! Per-instance usage queries; only short cache commits share a lock.

use std::collections::{BTreeMap, BTreeSet, hash_map::DefaultHasher};
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use anyhow::{Context, Result};
use pl_model::config::AccountId;
use pl_protocol::{ObservedResource, ObservedResourceCommand, StateOperation};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock};

use crate::account_usage::query_account_usage;
use crate::config::{ConfigRuntime, ConfigRuntimeSnapshot};
use crate::studio::ids::unix_seconds;
use crate::{AccountUsageRecord, StudioStore};

const CACHE_KEY: &str = "observed:accountUsage:v2";
type QueryLocks = BTreeMap<(AccountId, u64), Arc<Mutex<()>>>;

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
pub struct AccountUsageRuntime {
    store: StudioStore,
    config: ConfigRuntime,
    commit_lock: Arc<Mutex<()>>,
    queries: Arc<Mutex<QueryLocks>>,
    state: Arc<RwLock<AccountUsageStateSnapshot>>,
    events: crate::ProductEventBus,
}

impl AccountUsageRuntime {
    pub fn new(store: StudioStore, config: ConfigRuntime, events: crate::ProductEventBus) -> Self {
        Self {
            store,
            config,
            commit_lock: Arc::new(Mutex::new(())),
            queries: Arc::new(Mutex::new(BTreeMap::new())),
            state: Arc::new(RwLock::new(AccountUsageStateSnapshot {
                state: ObservedResource::uninitialized(unix_seconds()),
            })),
            events,
        }
    }

    pub async fn load_cache(&self) -> Result<()> {
        if let Some(value) = self.store.load_setting(CACHE_KEY).await? {
            *self.state.write().await = serde_json::from_str(&value)?;
        }
        self.apply_config().await?;
        Ok(())
    }

    /// Reads last-known facts without contacting a provider.
    pub async fn read(&self) -> AccountUsageStateSnapshot {
        self.state.read().await.clone()
    }

    /// Queries one current input identity. Different identities never wait on each other's network.
    pub async fn check(&self, account_id: &str) -> Result<AccountUsageStateSnapshot> {
        let id = AccountId::new(account_id)?;
        let config = self.config.read()?;
        let query_revision = config.usage_query_revision(&id).ok_or_else(|| {
            pl_protocol::studio::StudioError::invalid_argument("Provider does not exist")
        })?;
        let account = config
            .config
            .models
            .accounts
            .get(&id)
            .context("account usage identity has no configuration")?
            .clone();
        let baseline = self.read().await;
        let record = usage_record(&baseline, account_id);
        let query_lock = {
            let mut queries = self.queries.lock().await;
            let latest = self.config.read()?;
            queries.retain(|(id, revision), _| latest.usage_query_revision(id) == Some(*revision));
            queries
                .entry((id.clone(), query_revision))
                .or_default()
                .clone()
        };
        let _query = query_lock.lock().await;
        if self.config.read()?.usage_query_revision(&id) != Some(query_revision) {
            return Ok(self.read().await);
        }
        let current = self.read().await;
        if usage_record(&current, account_id).revision() != record.revision() {
            // A concurrent check of this same identity already published its result.
            return Ok(current);
        }
        let operation_id = format!(
            "account-usage-{account_id}-{query_revision}-{}",
            record.revision().saturating_add(1)
        );
        let observed = query_account_usage(record, account, operation_id.clone()).await?;

        let _commit = self.commit_lock.lock().await;
        let current_config = self.config.read()?;
        if current_config.usage_query_revision(&id) != Some(query_revision) {
            return Ok(self.read().await);
        }
        let previous = self.read().await;
        let mut usages = previous
            .state
            .value()
            .map(|data| data.usages.clone())
            .unwrap_or_default();
        let current_ids = account_ids(&current_config);
        usages.retain(|usage| {
            current_ids.contains(usage.account_id()) && usage.account_id() != account_id
        });
        usages.push(observed);
        usages.sort_by(|left, right| left.account_id().cmp(right.account_id()));
        let checked_at = unix_seconds();
        let running = previous
            .state
            .decide(ObservedResourceCommand::Begin {
                expected_revision: previous.state.revision(),
                operation: StateOperation::Check,
                operation_id,
                started_at: checked_at,
            })?
            .next_state;
        let next = AccountUsageStateSnapshot {
            state: running
                .decide(ObservedResourceCommand::Succeed {
                    expected_revision: running.revision(),
                    updated_at: checked_at,
                    last_checked_at: Some(checked_at),
                    value: AccountUsageStateData {
                        config_fingerprint: config_fingerprint(&current_config)?,
                        usages,
                    },
                })?
                .next_state,
        };
        // Persist only at this short merge boundary, never while querying a provider.
        self.store
            .save_setting(CACHE_KEY, &serde_json::to_string(&next)?)
            .await?;
        let accepted = {
            let mut state = self.state.write().await;
            self.config
                .if_usage_query_current(&id, query_revision, || {
                    *state = next.clone();
                })?
        };
        if accepted {
            self.events.emit_account_usage_state(next.clone());
            Ok(next)
        } else {
            Ok(self.read().await)
        }
    }

    /// Invalidates inputs and removes deleted instances without network or cache IO in a save path.
    pub async fn apply_config(&self) -> Result<AccountUsageStateSnapshot> {
        let _commit = self.commit_lock.lock().await;
        let config = self.config.read()?;
        self.queries
            .lock()
            .await
            .retain(|(id, revision), _| config.usage_query_revision(id) == Some(*revision));
        let previous = self.read().await;
        let Some(mut data) = previous.state.value().cloned() else {
            return Ok(previous);
        };
        let ids = account_ids(&config);
        let fingerprint = config_fingerprint(&config)?;
        let changed = data.config_fingerprint != fingerprint
            || data
                .usages
                .iter()
                .any(|usage| !ids.contains(usage.account_id()));
        if !changed {
            return Ok(previous);
        }
        data.usages.retain(|usage| ids.contains(usage.account_id()));
        data.config_fingerprint = fingerprint;
        let next = AccountUsageStateSnapshot {
            state: previous
                .state
                .decide(ObservedResourceCommand::MarkStale {
                    expected_revision: previous.state.revision(),
                    stale_at: unix_seconds(),
                    value: data,
                })?
                .next_state,
        };
        self.publish(next.clone()).await;
        Ok(next)
    }

    async fn publish(&self, snapshot: AccountUsageStateSnapshot) {
        *self.state.write().await = snapshot.clone();
        self.events.emit_account_usage_state(snapshot);
    }
}

fn usage_record(snapshot: &AccountUsageStateSnapshot, account_id: &str) -> AccountUsageRecord {
    snapshot
        .state
        .value()
        .and_then(|data| {
            data.usages
                .iter()
                .find(|usage| usage.account_id() == account_id)
        })
        .cloned()
        .unwrap_or_else(|| AccountUsageRecord::new(account_id))
}

fn account_ids(config: &ConfigRuntimeSnapshot) -> BTreeSet<String> {
    config
        .config
        .models
        .accounts
        .keys()
        .map(ToString::to_string)
        .collect()
}

fn config_fingerprint(config: &ConfigRuntimeSnapshot) -> Result<String> {
    // No secret or secret hash leaves the owner. Revisions are minted by the config owner.
    let identities = config
        .config
        .models
        .accounts
        .keys()
        .map(|id| (id.to_string(), config.usage_query_revision(id)))
        .collect::<BTreeMap<_, _>>();
    let mut hasher = DefaultHasher::new();
    serde_json::to_string(&identities)?.hash(&mut hasher);
    Ok(format!("{:x}", hasher.finish()))
}
