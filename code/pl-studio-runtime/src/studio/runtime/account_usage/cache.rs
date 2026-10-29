//! Current `observed:accountUsage:v2` payload read/write.
//!
//! Historical value formats are converted only at the Settings schema migration
//! boundary (`store::settings::payload`); this module never dispatches on an embedded
//! version and never writes one. Loading binds the retained private query identities to
//! the current configuration: same-identity observations survive restarts, crashed
//! querying states recover as retryable cancellations, and mismatched identities reset
//! instead of claiming a last-good for today's credentials.

use std::collections::BTreeMap;

use anyhow::{Result, anyhow, bail};
use pl_model::config::{AccountConfig, AccountId};
use pl_protocol::studio::{AccountUsageFailure, AccountUsageFailureCode, AccountUsagePhase};
use sha2::{Digest, Sha256};

use super::{UsageState, unchecked};
use crate::studio::store::settings::payload::{
    AccountUsageSettingBinding, AccountUsageSettingPayload, parse_current,
};

#[derive(Debug, thiserror::Error)]
#[error("account usage setting value is not the current payload; original record preserved")]
pub(crate) struct AccountUsageCacheMigrationError {
    #[source]
    source: anyhow::Error,
}

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

/// Restores in-memory usage state from the current payload.
///
/// Accounts missing from the current configuration (or without a query revision) are
/// skipped here; that is business eviction driven by the configuration observer, never a
/// schema decision, and the persisted payload itself is only rewritten by the next
/// successful business commit.
pub(super) fn load(
    raw: &str,
    accounts: &BTreeMap<AccountId, AccountConfig>,
    query_revision: impl Fn(&AccountId) -> Option<u64>,
) -> Result<UsageState> {
    let payload = parse(raw)?;
    let mut state = UsageState {
        revision: payload.revision,
        updated_at: payload.updated_at,
        accounts: BTreeMap::new(),
        query_identities: BTreeMap::new(),
        legacy_unbound: payload.legacy_unbound,
    };
    for binding in payload.accounts {
        let id = AccountId::new(&binding.observation.account_id)?;
        let Some(account) = accounts.get(&id) else {
            continue;
        };
        let Some(revision) = query_revision(&id) else {
            continue;
        };
        let identity = query_identity(&id, account);
        let mut observation = if identity == binding.query_identity {
            binding.observation
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
    Ok(state)
}

pub(super) fn encode(state: &UsageState) -> Result<String> {
    let mut accounts = Vec::with_capacity(state.accounts.len());
    for (id, observation) in &state.accounts {
        let identity = state
            .query_identities
            .get(id)
            .ok_or_else(|| anyhow!("account usage query binding is missing"))?;
        accounts.push(AccountUsageSettingBinding {
            query_identity: identity.clone(),
            observation: observation.clone(),
        });
    }
    Ok(serde_json::to_string(&AccountUsageSettingPayload {
        revision: state.revision,
        updated_at: state.updated_at,
        accounts,
        legacy_unbound: state.legacy_unbound.clone(),
    })?)
}

fn parse(raw: &str) -> Result<AccountUsageSettingPayload> {
    parse_current(raw)
        .map_err(|source| anyhow::Error::new(AccountUsageCacheMigrationError { source }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::studio::AccountUsageObservation;

    fn environment() -> (AccountId, AccountConfig, u64) {
        (
            AccountId::new("acct-1").expect("valid id"),
            AccountConfig::deepseek_template(),
            7,
        )
    }

    fn observation(account_id: &str, phase: AccountUsagePhase) -> AccountUsageObservation {
        AccountUsageObservation {
            account_id: account_id.to_owned(),
            query_revision: 2,
            revision: 3,
            phase,
            operation_id: None,
            checked_at: Some(76),
            failure: None,
            last_good: None,
        }
    }

    #[test]
    fn same_identity_restores_the_last_observation() {
        let (id, account, revision) = environment();
        let accounts = BTreeMap::from([(id.clone(), account)]);
        let revisions = BTreeMap::from([(id.clone(), revision)]);
        let payload = AccountUsageSettingPayload {
            revision: 11,
            updated_at: 77,
            accounts: vec![AccountUsageSettingBinding {
                query_identity: query_identity(&id, &accounts[&id]),
                observation: observation("acct-1", AccountUsagePhase::Succeeded),
            }],
            legacy_unbound: Some("legacy bytes".to_owned()),
        };
        let raw = serde_json::to_string(&payload).expect("payload encodes");
        let state = load(&raw, &accounts, |probe| revisions.get(probe).copied())
            .expect("current payload loads");
        assert_eq!(state.revision, 11);
        assert_eq!(state.updated_at, 77);
        assert_eq!(state.legacy_unbound.as_deref(), Some("legacy bytes"));
        let restored = state.accounts.get(&id).expect("bound account survives");
        assert_eq!(restored.query_revision, revision);
        assert_eq!(restored.revision, 3);
        assert_eq!(restored.phase, AccountUsagePhase::Succeeded);
        assert_eq!(
            state.query_identities.get(&id),
            Some(&query_identity(&id, &accounts[&id]))
        );
    }

    #[test]
    fn mismatched_identity_resets_instead_of_claiming_last_good() {
        let (id, account, revision) = environment();
        let accounts = BTreeMap::from([(id.clone(), account)]);
        let revisions = BTreeMap::from([(id.clone(), revision)]);
        let payload = AccountUsageSettingPayload {
            revision: 11,
            updated_at: 77,
            accounts: vec![AccountUsageSettingBinding {
                query_identity: "stale-identity".to_owned(),
                observation: observation("acct-1", AccountUsagePhase::Succeeded),
            }],
            legacy_unbound: None,
        };
        let raw = serde_json::to_string(&payload).expect("payload encodes");
        let state = load(&raw, &accounts, |probe| revisions.get(probe).copied())
            .expect("current payload loads");
        let restored = state.accounts.get(&id).expect("account stays tracked");
        assert_eq!(restored.phase, AccountUsagePhase::Unchecked);
        assert_eq!(restored.query_revision, revision);
        assert_eq!(restored.revision, 0);
        assert!(restored.last_good.is_none());
    }

    #[test]
    fn crashed_querying_recovers_as_retryable_cancellation() {
        let (id, account, revision) = environment();
        let accounts = BTreeMap::from([(id.clone(), account)]);
        let revisions = BTreeMap::from([(id.clone(), revision)]);
        let payload = AccountUsageSettingPayload {
            revision: 11,
            updated_at: 77,
            accounts: vec![AccountUsageSettingBinding {
                query_identity: query_identity(&id, &accounts[&id]),
                observation: observation("acct-1", AccountUsagePhase::Querying),
            }],
            legacy_unbound: None,
        };
        let raw = serde_json::to_string(&payload).expect("payload encodes");
        let state = load(&raw, &accounts, |probe| revisions.get(probe).copied())
            .expect("current payload loads");
        let restored = state.accounts.get(&id).expect("bound account survives");
        assert_eq!(restored.phase, AccountUsagePhase::Failed);
        let failure = restored
            .failure
            .as_ref()
            .expect("cancellation is observable");
        assert_eq!(failure.code, AccountUsageFailureCode::Cancelled);
        assert!(failure.retryable);
        assert_eq!(restored.revision, 4);
    }

    #[test]
    fn accounts_without_current_configuration_are_business_evicted() {
        let (id, account, revision) = environment();
        let accounts = BTreeMap::from([(id.clone(), account)]);
        let revisions = BTreeMap::from([(id.clone(), revision)]);
        let payload = AccountUsageSettingPayload {
            revision: 11,
            updated_at: 77,
            accounts: vec![
                AccountUsageSettingBinding {
                    query_identity: query_identity(&id, &accounts[&id]),
                    observation: observation("acct-1", AccountUsagePhase::Succeeded),
                },
                AccountUsageSettingBinding {
                    query_identity: "identity-gone".to_owned(),
                    observation: observation("acct-gone", AccountUsagePhase::Succeeded),
                },
                AccountUsageSettingBinding {
                    query_identity: "identity-stale".to_owned(),
                    observation: observation("acct-stale", AccountUsagePhase::Succeeded),
                },
            ],
            legacy_unbound: None,
        };
        let raw = serde_json::to_string(&payload).expect("payload encodes");
        let state = load(&raw, &accounts, |probe| {
            (probe.as_str() != "acct-stale")
                .then(|| revisions.get(probe).copied())
                .flatten()
        })
        .expect("current payload loads");
        assert_eq!(state.accounts.len(), 1);
        assert!(state.accounts.contains_key(&id));
    }

    #[test]
    fn legacy_shapes_and_duplicate_identities_fail_the_load() {
        let (id, account, _) = environment();
        let accounts = BTreeMap::from([(id, account)]);
        for raw in [
            r#"{"formatVersion":3,"revision":1,"updatedAt":2,"accounts":[]}"#,
            r#"{"formatVersion":999}"#,
            "invalid json",
        ] {
            let error = match load(raw, &accounts, |_| None) {
                Ok(_) => panic!("only the current payload is accepted"),
                Err(error) => error,
            };
            assert!(
                error
                    .chain()
                    .any(|cause| cause.is::<AccountUsageCacheMigrationError>()),
                "expected the typed payload error, got: {error:#}"
            );
        }
    }

    #[test]
    fn encode_round_trips_the_current_payload() {
        let (id, account, _) = environment();
        let identity = query_identity(&id, &account);
        let mut state = UsageState {
            revision: 12,
            updated_at: 78,
            accounts: BTreeMap::from([(
                id.clone(),
                observation("acct-1", AccountUsagePhase::Succeeded),
            )]),
            query_identities: BTreeMap::from([(id.clone(), identity.clone())]),
            legacy_unbound: None,
        };
        let raw = encode(&state).expect("state encodes");
        let reparsed = parse_current(&raw).expect("encoded value is a current payload");
        assert_eq!(reparsed.revision, 12);
        assert_eq!(reparsed.updated_at, 78);
        assert_eq!(reparsed.accounts.len(), 1);
        assert_eq!(reparsed.accounts[0].query_identity, identity);

        state.query_identities.clear();
        assert!(
            encode(&state).is_err(),
            "unbound accounts cannot be persisted"
        );
    }
}
