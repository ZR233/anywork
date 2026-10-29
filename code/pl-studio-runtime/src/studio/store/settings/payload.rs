//! `observed:accountUsage:v2` setting value: the current payload plus the historical
//! conversion entry point.
//!
//! The current payload below is the only live shape: the runtime and the write
//! boundary consume it directly, and it keeps using the current protocol DTOs. The
//! historical wire trees are frozen in [`super::history`] and are decoded only through
//! [`migrate_legacy`] at the Settings schema migration boundary.

use std::collections::BTreeSet;

use anyhow::{Result, ensure};
use pl_model::config::AccountId;
use pl_protocol::studio::AccountUsageObservation;
use serde::{Deserialize, Serialize};

use super::history;

/// The only setting key whose value has a schema beyond an opaque string.
pub(in crate::studio) const KEY: &str = "observed:accountUsage:v2";

/// Current payload of [`KEY`]: no embedded format version.
///
/// `deny_unknown_fields` makes both the runtime load and the write boundary reject any
/// legacy shape (for example a `formatVersion` header) instead of silently re-persisting it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct AccountUsageSettingPayload {
    pub(in crate::studio) revision: u64,
    pub(in crate::studio) updated_at: i64,
    pub(in crate::studio) accounts: Vec<AccountUsageSettingBinding>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(in crate::studio) legacy_unbound: Option<String>,
}

/// One account's private query identity plus its retained observation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct AccountUsageSettingBinding {
    pub(in crate::studio) query_identity: String,
    pub(in crate::studio) observation: AccountUsageObservation,
}

/// Parses and validates a current payload. Account ids must be valid and unique so an
/// ambiguous cached identity can never reach the runtime binding step.
pub(in crate::studio) fn parse_current(raw: &str) -> Result<AccountUsageSettingPayload> {
    let payload: AccountUsageSettingPayload = serde_json::from_str(raw)?;
    validate_bindings(&payload.accounts)?;
    Ok(payload)
}

/// Converts a historical value of [`KEY`] into the current payload.
///
/// * No embedded `formatVersion`: the frozen v2 snapshot tree validates the input and
///   its business revision/time survive, while the exact original bytes move to
///   `legacyUnbound`. No current observation is constructed; nothing is claimed as a
///   success for today's credentials.
/// * `formatVersion = 3`: the frozen v3 cache tree validates the input, then converts
///   into the current payload through the explicit `TryFrom` bridge, dropping the
///   embedded version header.
/// * Unknown versions, malformed JSON and identity conflicts fail the whole
///   candidate; callers never persist a partial conversion.
pub(super) fn migrate_legacy(raw: &str) -> Result<AccountUsageSettingPayload> {
    let probe: history::FormatVersionProbe = serde_json::from_str(raw)?;
    match probe.format_version {
        None => {
            let snapshot: history::SnapshotV2 = serde_json::from_str(raw)?;
            Ok(AccountUsageSettingPayload {
                revision: snapshot.state.revision(),
                updated_at: snapshot.state.updated_at(),
                accounts: Vec::new(),
                legacy_unbound: Some(raw.to_owned()),
            })
        }
        Some(version) => {
            ensure!(
                version == 3,
                "unsupported account usage cache format version {version}"
            );
            let cache: history::CacheV3 = serde_json::from_str(raw)?;
            AccountUsageSettingPayload::try_from(cache)
        }
    }
}

fn validate_bindings(accounts: &[AccountUsageSettingBinding]) -> Result<()> {
    let mut seen = BTreeSet::new();
    for binding in accounts {
        let id = AccountId::new(&binding.observation.account_id)?;
        ensure!(seen.insert(id), "duplicate account usage cache identity");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::studio::AccountUsagePhase;

    const LEGACY_V2: &str = r#"{"state":{"kind":"ready","data":{"revision":19,"updatedAt":22,"lastCheckedAt":22,"value":{"configFingerprint":"legacy-inputs","usages":[{"accountId":"legacy-balance","revision":9,"updatedAt":22,"lastOperationId":"legacy-check","state":{"kind":"ready","data":{"data":{"kind":"deepSeekBalance","data":{"is_available":true,"balances":[{"currency":"USD","total_balance":"1.000001","granted_balance":"0.000001","topped_up_balance":"1.000000"},{"currency":"CNY","total_balance":"7.25","granted_balance":"2.00","topped_up_balance":"5.25"}]}}}}}]}}}}"#;

    fn observation(account_id: &str) -> AccountUsageObservation {
        AccountUsageObservation {
            account_id: account_id.to_owned(),
            query_revision: 2,
            revision: 3,
            phase: AccountUsagePhase::Succeeded,
            operation_id: None,
            checked_at: Some(76),
            failure: None,
            last_good: None,
        }
    }

    #[test]
    fn legacy_v2_snapshot_keeps_bytes_and_business_revision() {
        let payload = migrate_legacy(LEGACY_V2).expect("frozen v2 snapshot validates");
        assert_eq!(payload.revision, 19);
        assert_eq!(payload.updated_at, 22);
        assert!(payload.accounts.is_empty());
        assert_eq!(payload.legacy_unbound.as_deref(), Some(LEGACY_V2));
    }

    #[test]
    fn legacy_v3_cache_drops_version_and_keeps_bound_accounts() {
        // Historical writers always emitted `legacyUnbound`, including null.
        let raw = r#"{"formatVersion":3,"revision":5,"updatedAt":77,"accounts":[{"queryIdentity":"identity-a","observation":{"accountId":"acct-1","queryRevision":2,"revision":3,"phase":"succeeded","operationId":null,"checkedAt":76,"failure":null,"lastGood":{"checkedAt":76,"value":{"kind":"balance","available":true,"balances":[{"currency":"USD","total":"1.0","granted":"0.25","toppedUp":"0.75"}]}}}}],"legacyUnbound":null}"#;
        let payload = migrate_legacy(raw).expect("frozen v3 cache validates");
        assert_eq!(payload.revision, 5);
        assert_eq!(payload.updated_at, 77);
        assert_eq!(payload.legacy_unbound, None);
        let binding = payload.accounts.first().expect("bound account survives");
        assert_eq!(binding.query_identity, "identity-a");
        assert_eq!(binding.observation.account_id, "acct-1");
        let encoded = serde_json::to_string(&payload).expect("current payload encodes");
        let reparsed = parse_current(&encoded).expect("current payload round-trips");
        assert_eq!(reparsed, payload);
    }

    #[test]
    fn unknown_or_malformed_versions_and_bad_json_fail_the_candidate() {
        for raw in [
            r#"{"formatVersion":999,"futurePayload":"preserve exactly"}"#,
            r#"{"formatVersion":"3"}"#,
            r#"{"formatVersion":3.5}"#,
            r#"{"formatVersion":null}"#,
            "invalid json",
            r#"{"configFingerprint":"missing the state envelope"}"#,
        ] {
            assert!(
                migrate_legacy(raw).is_err(),
                "candidate must fail completely: {raw}"
            );
        }
    }

    #[test]
    fn explicit_invalid_version_never_falls_back_to_a_valid_unversioned_snapshot() {
        for version in ["null", "\"3\"", "3.0", "-1", "0", "999"] {
            let raw = format!("{{\"formatVersion\":{version},{}", &LEGACY_V2[1..]);
            assert!(
                migrate_legacy(&raw).is_err(),
                "a present invalid header cannot select the unversioned import: {version}"
            );
        }
    }

    #[test]
    fn duplicate_or_invalid_identities_fail_current_parse() {
        let binding = AccountUsageSettingBinding {
            query_identity: "identity-a".to_owned(),
            observation: observation("acct-1"),
        };
        let duplicated = AccountUsageSettingPayload {
            revision: 4,
            updated_at: 5,
            accounts: vec![binding.clone(), binding],
            legacy_unbound: None,
        };
        let raw = serde_json::to_string(&duplicated).expect("payload encodes");
        assert!(parse_current(&raw).is_err(), "identity conflict must fail");

        let blank = AccountUsageSettingPayload {
            revision: 4,
            updated_at: 5,
            accounts: vec![AccountUsageSettingBinding {
                query_identity: "identity-a".to_owned(),
                observation: observation("   "),
            }],
            legacy_unbound: None,
        };
        let raw = serde_json::to_string(&blank).expect("payload encodes");
        assert!(parse_current(&raw).is_err(), "blank account id must fail");
    }

    #[test]
    fn current_parse_rejects_embedded_versions() {
        assert!(
            parse_current(r#"{"formatVersion":3,"revision":1,"updatedAt":2,"accounts":[]}"#)
                .is_err()
        );
    }
}
