//! Explicit v2 -> v3 setting-value migration. SQLite's schema/key do not change.

use anyhow::{Result, bail};
use pl_model::config::{AccountConfig, AccountId};
use pl_protocol::studio::{
    AccountUsageFailure, AccountUsageFailureCode, AccountUsageObservation, AccountUsagePhase,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

use super::{AccountUsageStateSnapshot, ConfigRuntimeSnapshot, UsageState, unchecked};

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CacheV3 {
    format_version: u32,
    revision: u64,
    updated_at: i64,
    accounts: Vec<CachedAccount>,
    /// v2 did not persist a provable per-account query identity. Preserve its exact bytes, without
    /// claiming it is a success for today's credentials or discarding the old amounts/diagnostics.
    legacy_unbound: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CachedAccount {
    query_identity: String,
    observation: AccountUsageObservation,
}

pub(super) struct Loaded {
    pub state: UsageState,
    pub migrated: bool,
}

#[derive(Debug, thiserror::Error)]
#[error("account usage setting-value migration failed; original record preserved: {0}")]
pub(crate) struct AccountUsageCacheMigrationError(String);

pub(super) fn query_identity(id: &AccountId, account: &AccountConfig) -> String {
    let mut hash = Sha256::new();
    // Length-prefix each input so concatenation cannot alias another query. The digest is private
    // persistence metadata, never a public query revision, account summary, log, or API response.
    for input in [
        id.as_str(),
        account.protocol.as_str(),
        account.template_id().map_or("", |id| id.as_str()),
        &account.base_url,
        account.resolved_bearer_token().as_deref().unwrap_or(""),
    ] {
        hash.update((input.len() as u64).to_le_bytes());
        hash.update(input.as_bytes());
    }
    if let Some(headers) = &account.http_headers {
        for (key, value) in headers {
            for input in [key, value] {
                hash.update((input.len() as u64).to_le_bytes());
                hash.update(input.as_bytes());
            }
        }
    }
    hex::encode(hash.finalize())
}

pub(super) fn load(raw: &str, config: &ConfigRuntimeSnapshot) -> Result<Loaded> {
    let header: serde_json::Value = serde_json::from_str(raw)?;
    if header.get("formatVersion").is_none() {
        // Decode only at this migration boundary using the unchanged v2 record/state types.
        let previous: AccountUsageStateSnapshot = serde_json::from_str(raw)?;
        return Ok(Loaded {
            state: UsageState {
                revision: previous.state.revision(),
                updated_at: previous.state.updated_at(),
                legacy_unbound: Some(raw.to_owned()),
                ..UsageState::default()
            },
            migrated: true,
        });
    }
    if header
        .get("formatVersion")
        .and_then(serde_json::Value::as_u64)
        != Some(3)
    {
        return Err(AccountUsageCacheMigrationError("unsupported format version".into()).into());
    }
    let cache: CacheV3 = serde_json::from_str(raw)?;
    let mut state = UsageState {
        revision: cache.revision,
        updated_at: cache.updated_at,
        accounts: BTreeMap::new(),
        query_identities: BTreeMap::new(),
        legacy_unbound: cache.legacy_unbound,
    };
    for entry in cache.accounts {
        let id = AccountId::new(&entry.observation.account_id)?;
        let Some(account) = config.config.models.accounts.get(&id) else {
            continue;
        };
        let Some(revision) = config.usage_query_revision(&id) else {
            continue;
        };
        let identity = query_identity(&id, account);
        let mut observation = if identity == entry.query_identity {
            entry.observation
        } else {
            unchecked(&id, revision)
        };
        observation.query_revision = revision;
        if observation.phase == AccountUsagePhase::Querying {
            observation.phase = AccountUsagePhase::Failed;
            observation.failure = Some(AccountUsageFailure {
                code: AccountUsageFailureCode::Cancelled,
                retryable: true,
            });
            observation.revision = observation.revision.saturating_add(1);
        }
        if state.accounts.insert(id.clone(), observation).is_some() {
            bail!("duplicate account usage cache identity");
        }
        state.query_identities.insert(id, identity);
    }
    Ok(Loaded {
        state,
        migrated: false,
    })
}

pub(super) fn encode(state: &UsageState) -> Result<String> {
    let mut accounts = Vec::with_capacity(state.accounts.len());
    for (id, observation) in &state.accounts {
        let identity = state
            .query_identities
            .get(id)
            .ok_or_else(|| anyhow::anyhow!("account usage query binding is missing"))?;
        accounts.push(CachedAccount {
            query_identity: identity.clone(),
            observation: observation.clone(),
        });
    }
    Ok(serde_json::to_string(&CacheV3 {
        format_version: 3,
        revision: state.revision,
        updated_at: state.updated_at,
        accounts,
        legacy_unbound: state.legacy_unbound.clone(),
    })?)
}
