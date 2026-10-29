//! Frozen historical wire trees for the `observed:accountUsage:v2` setting value.
//!
//! Every structure below is a byte-faithful copy of the wire shapes the historical
//! writers actually emitted, including their per-type strictness (some denied unknown
//! fields, some did not). Nothing here is a live fact source: the types never evolve,
//! never back new writes, and are decoded only at the Settings schema migration
//! boundary. The current payload and the runtime keep consuming the current protocol
//! DTOs; the explicit `TryFrom` conversions below are the only bridge from a frozen
//! tree into current types, and they run at the fallible pre-validation boundary.

use anyhow::{Error, Result, ensure};
use pl_model::config::AccountId;
use pl_protocol::studio::{
    AccountMoneyBalance, AccountQuota, AccountQuotaDetail, AccountQuotaWindow, AccountUsageFailure,
    AccountUsageFailureCode, AccountUsageObservation, AccountUsagePhase, AccountUsageSuccess,
    AccountUsageValue,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

use super::payload::{AccountUsageSettingBinding, AccountUsageSettingPayload};

/// Typed admission for the embedded version header. The probe reads this one known
/// field as a real integer; every other field is validated afterwards by one of the
/// complete frozen structures below, never by inspecting a raw JSON value.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct FormatVersionProbe {
    #[serde(default, deserialize_with = "present_format_version")]
    pub(super) format_version: Option<u64>,
}

fn present_format_version<'de, D>(deserializer: D) -> std::result::Result<Option<u64>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    // Only an absent header selects V2. An explicitly present null is not "unversioned".
    u64::deserialize(deserializer).map(Some)
}

// ---------------------------------------------------------------------------
// Frozen v2 product snapshot: the value before any embedded version header.
// ---------------------------------------------------------------------------

/// Mirror of the historical `AccountUsageStateSnapshot` wire (camelCase, tolerant of
/// unknown fields exactly like the decoder that once wrote it).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SnapshotV2 {
    pub(super) state: ResourceV2<SnapshotDataV2>,
}

/// Mirror of the historical `AccountUsageStateData` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SnapshotDataV2 {
    pub(super) config_fingerprint: String,
    pub(super) usages: Vec<UsageRecordV2>,
}

/// Mirror of the historical `AccountUsageRecord` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct UsageRecordV2 {
    pub(super) account_id: String,
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) last_operation_id: String,
    pub(super) state: UsageStateV2,
}

/// Mirror of the historical `AccountUsageState` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum UsageStateV2 {
    Unsupported(UnsupportedUsageV2),
    MissingCredential(MissingCredentialUsageV2),
    Ready(ReadyUsageV2),
    Failed(FailedUsageV2),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct UnsupportedUsageV2;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct MissingCredentialUsageV2 {
    pub(super) message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReadyUsageV2 {
    pub(super) data: UsageDataV2,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FailedUsageV2 {
    pub(super) error: StateErrorV2,
}

/// Mirror of the historical `AccountUsageData` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum UsageDataV2 {
    DeepSeekBalance(BalanceUsageV2),
    ZhipuCodingPlan(CodingPlanUsageV2),
}

/// Historical DeepSeek usage wire; field names stayed snake_case, keep them so.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(super) struct BalanceUsageV2 {
    pub(super) is_available: bool,
    pub(super) balances: Vec<BalanceInfoV2>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) struct BalanceInfoV2 {
    pub(super) currency: String,
    pub(super) total_balance: String,
    pub(super) granted_balance: String,
    pub(super) topped_up_balance: String,
}

/// Historical Zhipu coding-plan wire; snake_case field names, default enum tagging.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(super) struct CodingPlanUsageV2 {
    pub(super) level: Option<String>,
    pub(super) limits: Vec<QuotaLimitV2>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(super) struct QuotaLimitV2 {
    pub(super) window: QuotaWindowV2,
    pub(super) percentage: f64,
    pub(super) current_value: Option<f64>,
    pub(super) total: Option<f64>,
    pub(super) remaining: Option<f64>,
    pub(super) next_reset_at: Option<i64>,
    pub(super) usage_details: Vec<ToolUsageDetailV2>,
}

/// Externally tagged, exactly like the historical `ZhipuQuotaWindow`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(super) enum QuotaWindowV2 {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(super) struct ToolUsageDetailV2 {
    pub(super) name: String,
    pub(super) current_value: Option<f64>,
    pub(super) total: Option<f64>,
    pub(super) percentage: Option<f64>,
}

/// Mirror of the historical `ObservedResource<T>` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(super) enum ResourceV2<T> {
    Uninitialized(UninitializedV2),
    Loading(LoadingV2),
    Ready(ReadyV2<T>),
    Refreshing(RefreshingV2<T>),
    Stale(StaleV2<T>),
    Degraded(DegradedV2<T>),
    Failed(FailedV2),
    Stopped(StoppedV2),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct UninitializedV2 {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct LoadingV2 {
    pub(super) revision: u64,
    pub(super) operation: StateOperationV2,
    pub(super) operation_id: String,
    pub(super) started_at: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReadyV2<T> {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) last_checked_at: Option<i64>,
    pub(super) value: T,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RefreshingV2<T> {
    pub(super) revision: u64,
    pub(super) operation: StateOperationV2,
    pub(super) operation_id: String,
    pub(super) started_at: i64,
    pub(super) last_checked_at: Option<i64>,
    pub(super) value: T,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct StaleV2<T> {
    pub(super) revision: u64,
    pub(super) stale_at: i64,
    pub(super) last_checked_at: Option<i64>,
    pub(super) value: T,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct DegradedV2<T> {
    pub(super) revision: u64,
    pub(super) failed_at: i64,
    pub(super) last_checked_at: Option<i64>,
    pub(super) operation: StateOperationV2,
    pub(super) error: StateErrorV2,
    pub(super) value: T,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FailedV2 {
    pub(super) revision: u64,
    pub(super) failed_at: i64,
    pub(super) operation: StateOperationV2,
    pub(super) error: StateErrorV2,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct StoppedV2 {
    pub(super) revision: u64,
    pub(super) stopped_at: i64,
}

/// Mirror of the historical `StateOperation` wire.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum StateOperationV2 {
    Initialize,
    Activate,
    Reload,
    Reconcile,
    Discover,
    Check,
    Probe,
    Repair,
    Reset,
    Shutdown,
}

/// Mirror of the historical `StateError` wire (camelCase, no unknown-field denial).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct StateErrorV2 {
    pub(super) code: String,
    pub(super) message: String,
    pub(super) retryable: bool,
}

impl<T> ResourceV2<T> {
    /// The business revision, mirroring the historical accessor for every phase.
    pub(super) fn revision(&self) -> u64 {
        match self {
            Self::Uninitialized(state) => state.revision,
            Self::Loading(state) => state.revision,
            Self::Ready(state) => state.revision,
            Self::Refreshing(state) => state.revision,
            Self::Stale(state) => state.revision,
            Self::Degraded(state) => state.revision,
            Self::Failed(state) => state.revision,
            Self::Stopped(state) => state.revision,
        }
    }

    /// The last state-change time, mirroring the historical per-phase timestamps.
    pub(super) fn updated_at(&self) -> i64 {
        match self {
            Self::Uninitialized(state) => state.updated_at,
            Self::Loading(state) => state.started_at,
            Self::Ready(state) => state.updated_at,
            Self::Refreshing(state) => state.started_at,
            Self::Stale(state) => state.stale_at,
            Self::Degraded(state) => state.failed_at,
            Self::Failed(state) => state.failed_at,
            Self::Stopped(state) => state.stopped_at,
        }
    }
}

// ---------------------------------------------------------------------------
// Frozen v3 cache value: current-shaped fields plus an embedded version header.
// ---------------------------------------------------------------------------

/// Mirror of the historical `formatVersion = 3` cache wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct CacheV3 {
    pub(super) format_version: u32,
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) accounts: Vec<BindingV3>,
    #[serde(default)]
    pub(super) legacy_unbound: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct BindingV3 {
    pub(super) query_identity: String,
    pub(super) observation: ObservationV3,
}

/// Mirror of the historical `AccountUsageObservation` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ObservationV3 {
    pub(super) account_id: String,
    pub(super) query_revision: u64,
    pub(super) revision: u64,
    pub(super) phase: PhaseV3,
    pub(super) operation_id: Option<String>,
    pub(super) checked_at: Option<i64>,
    pub(super) failure: Option<FailureV3>,
    pub(super) last_good: Option<SuccessV3>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum PhaseV3 {
    Unchecked,
    Querying,
    Succeeded,
    Unsupported,
    MissingCredential,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FailureV3 {
    pub(super) code: FailureCodeV3,
    pub(super) retryable: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum FailureCodeV3 {
    Configuration,
    Query,
    Cancelled,
    TaskFailed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct SuccessV3 {
    pub(super) checked_at: i64,
    pub(super) value: ValueV3,
}

/// Mirror of the historical `AccountUsageValue` wire.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(super) enum ValueV3 {
    Balance {
        available: bool,
        balances: Vec<MoneyBalanceV3>,
    },
    Subscription {
        level: Option<String>,
        quotas: Vec<QuotaV3>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct MoneyBalanceV3 {
    pub(super) currency: String,
    pub(super) total: String,
    pub(super) granted: String,
    pub(super) topped_up: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct QuotaV3 {
    pub(super) window: QuotaWindowV3,
    pub(super) percentage: f64,
    pub(super) used: Option<f64>,
    pub(super) total: Option<f64>,
    pub(super) remaining: Option<f64>,
    pub(super) reset_at: Option<i64>,
    pub(super) details: Vec<QuotaDetailV3>,
}

/// Adjacently tagged, exactly like the historical `AccountQuotaWindow`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub(super) enum QuotaWindowV3 {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct QuotaDetailV3 {
    pub(super) name: String,
    pub(super) used: Option<f64>,
    pub(super) total: Option<f64>,
    pub(super) percentage: Option<f64>,
}

// ---------------------------------------------------------------------------
// Explicit bridge from the frozen v3 tree into the current payload types. These
// conversions run only at the fallible pre-validation boundary, before the
// infallible `MigratesTo` step; total mappings stay plain `From`.
// ---------------------------------------------------------------------------

impl From<PhaseV3> for AccountUsagePhase {
    fn from(phase: PhaseV3) -> Self {
        match phase {
            PhaseV3::Unchecked => Self::Unchecked,
            PhaseV3::Querying => Self::Querying,
            PhaseV3::Succeeded => Self::Succeeded,
            PhaseV3::Unsupported => Self::Unsupported,
            PhaseV3::MissingCredential => Self::MissingCredential,
            PhaseV3::Failed => Self::Failed,
        }
    }
}

impl From<FailureCodeV3> for AccountUsageFailureCode {
    fn from(code: FailureCodeV3) -> Self {
        match code {
            FailureCodeV3::Configuration => Self::Configuration,
            FailureCodeV3::Query => Self::Query,
            FailureCodeV3::Cancelled => Self::Cancelled,
            FailureCodeV3::TaskFailed => Self::TaskFailed,
        }
    }
}

impl From<MoneyBalanceV3> for AccountMoneyBalance {
    fn from(balance: MoneyBalanceV3) -> Self {
        Self {
            currency: balance.currency,
            total: balance.total,
            granted: balance.granted,
            topped_up: balance.topped_up,
        }
    }
}

impl From<QuotaDetailV3> for AccountQuotaDetail {
    fn from(detail: QuotaDetailV3) -> Self {
        Self {
            name: detail.name,
            used: detail.used,
            total: detail.total,
            percentage: detail.percentage,
        }
    }
}

impl From<QuotaWindowV3> for AccountQuotaWindow {
    fn from(window: QuotaWindowV3) -> Self {
        match window {
            QuotaWindowV3::FiveHour => Self::FiveHour,
            QuotaWindowV3::Weekly => Self::Weekly,
            QuotaWindowV3::McpMonthly => Self::McpMonthly,
            QuotaWindowV3::Other(other) => Self::Other(other),
        }
    }
}

impl From<QuotaV3> for AccountQuota {
    fn from(quota: QuotaV3) -> Self {
        Self {
            window: quota.window.into(),
            percentage: quota.percentage,
            used: quota.used,
            total: quota.total,
            remaining: quota.remaining,
            reset_at: quota.reset_at,
            details: quota.details.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<ValueV3> for AccountUsageValue {
    fn from(value: ValueV3) -> Self {
        match value {
            ValueV3::Balance {
                available,
                balances,
            } => Self::Balance {
                available,
                balances: balances.into_iter().map(Into::into).collect(),
            },
            ValueV3::Subscription { level, quotas } => Self::Subscription {
                level,
                quotas: quotas.into_iter().map(Into::into).collect(),
            },
        }
    }
}

impl From<SuccessV3> for AccountUsageSuccess {
    fn from(success: SuccessV3) -> Self {
        Self {
            checked_at: success.checked_at,
            value: success.value.into(),
        }
    }
}

impl From<FailureV3> for AccountUsageFailure {
    fn from(failure: FailureV3) -> Self {
        Self {
            code: failure.code.into(),
            retryable: failure.retryable,
        }
    }
}

impl From<ObservationV3> for AccountUsageObservation {
    fn from(observation: ObservationV3) -> Self {
        Self {
            account_id: observation.account_id,
            query_revision: observation.query_revision,
            revision: observation.revision,
            phase: observation.phase.into(),
            operation_id: observation.operation_id,
            checked_at: observation.checked_at,
            failure: observation.failure.map(Into::into),
            last_good: observation.last_good.map(Into::into),
        }
    }
}

impl TryFrom<BindingV3> for AccountUsageSettingBinding {
    type Error = Error;

    fn try_from(binding: BindingV3) -> Result<Self> {
        AccountId::new(&binding.observation.account_id)?;
        Ok(Self {
            query_identity: binding.query_identity,
            observation: binding.observation.into(),
        })
    }
}

impl TryFrom<CacheV3> for AccountUsageSettingPayload {
    type Error = Error;

    fn try_from(cache: CacheV3) -> Result<Self> {
        let mut accounts = Vec::with_capacity(cache.accounts.len());
        let mut seen = BTreeSet::new();
        for binding in cache.accounts {
            let converted = AccountUsageSettingBinding::try_from(binding)?;
            let id = AccountId::new(&converted.observation.account_id)?;
            ensure!(seen.insert(id), "duplicate account usage cache identity");
            accounts.push(converted);
        }
        Ok(Self {
            revision: cache.revision,
            updated_at: cache.updated_at,
            accounts,
            legacy_unbound: cache.legacy_unbound,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEEPSEEK_V2: &str = r#"{"state":{"kind":"ready","data":{"revision":19,"updatedAt":22,"lastCheckedAt":22,"value":{"configFingerprint":"legacy-inputs","usages":[{"accountId":"legacy-balance","revision":9,"updatedAt":22,"lastOperationId":"legacy-check","state":{"kind":"ready","data":{"data":{"kind":"deepSeekBalance","data":{"is_available":true,"balances":[{"currency":"USD","total_balance":"1.000001","granted_balance":"0.000001","topped_up_balance":"1.000000"},{"currency":"CNY","total_balance":"7.25","granted_balance":"2.00","topped_up_balance":"5.25"}]}}}}}]}}}}"#;

    const ZHIPU_V2: &str = r#"{"state":{"kind":"ready","data":{"revision":3,"updatedAt":5,"lastCheckedAt":5,"value":{"configFingerprint":"zhipu-inputs","usages":[{"accountId":"zhipu-plan","revision":2,"updatedAt":5,"lastOperationId":"zhipu-check","state":{"kind":"ready","data":{"data":{"kind":"zhipuCodingPlan","data":{"level":"MAX","limits":[{"window":{"Other":"monthly"},"percentage":42.5,"current_value":1000.25,"total":2500.5,"remaining":1500.25,"next_reset_at":77,"usage_details":[{"name":"coder","current_value":10.5,"total":20.25,"percentage":51.9}]}]}}}}}]}}}}"#;

    const CACHE_V3: &str = r#"{"formatVersion":3,"revision":5,"updatedAt":77,"accounts":[{"queryIdentity":"identity-a","observation":{"accountId":"acct-1","queryRevision":2,"revision":3,"phase":"querying","operationId":"op-7","checkedAt":76,"failure":{"code":"cancelled","retryable":true},"lastGood":{"checkedAt":75,"value":{"kind":"subscription","level":"MAX","quotas":[{"window":{"kind":"fiveHour"},"percentage":50,"used":5.5,"total":10.25,"remaining":4.75,"resetAt":99,"details":[{"name":"tool","used":1.25,"total":2.5,"percentage":50}]}]}}}}],"legacyUnbound":"old bytes"}"#;

    #[test]
    fn frozen_v2_deepseek_tree_round_trips_and_preserves_every_field() {
        let snapshot: SnapshotV2 = serde_json::from_str(DEEPSEEK_V2).expect("v2 wire parses");
        assert_eq!(snapshot.state.revision(), 19);
        assert_eq!(snapshot.state.updated_at(), 22);
        let SnapshotDataV2 {
            config_fingerprint,
            usages,
        } = match &snapshot.state {
            ResourceV2::Ready(state) => &state.value,
            other => panic!("expected a ready snapshot, got {other:?}"),
        };
        assert_eq!(config_fingerprint, "legacy-inputs");
        let record = usages.first().expect("one usage record");
        assert_eq!(record.account_id, "legacy-balance");
        assert_eq!(record.revision, 9);
        assert_eq!(record.updated_at, 22);
        assert_eq!(record.last_operation_id, "legacy-check");
        let balance = match &record.state {
            UsageStateV2::Ready(ReadyUsageV2 {
                data: UsageDataV2::DeepSeekBalance(balance),
            }) => balance,
            other => panic!("expected a ready usage, got {other:?}"),
        };
        assert!(balance.is_available);
        assert_eq!(balance.balances.len(), 2);
        assert_eq!(balance.balances[0].currency, "USD");
        assert_eq!(balance.balances[0].total_balance, "1.000001");
        assert_eq!(balance.balances[1].granted_balance, "2.00");
        assert_eq!(balance.balances[1].topped_up_balance, "5.25");

        let serialized = serde_json::to_string(&snapshot).expect("frozen v2 serializes");
        let reparsed: SnapshotV2 = serde_json::from_str(&serialized).expect("frozen v2 re-parses");
        assert_eq!(reparsed, snapshot);
    }

    #[test]
    fn frozen_v2_zhipu_tree_round_trips_and_preserves_every_field() {
        let snapshot: SnapshotV2 = serde_json::from_str(ZHIPU_V2).expect("v2 wire parses");
        let value = match &snapshot.state {
            ResourceV2::Ready(state) => &state.value,
            other => panic!("expected a ready snapshot, got {other:?}"),
        };
        let record = value.usages.first().expect("one usage record");
        let plan = match &record.state {
            UsageStateV2::Ready(ReadyUsageV2 {
                data: UsageDataV2::ZhipuCodingPlan(plan),
            }) => plan,
            other => panic!("expected a ready usage, got {other:?}"),
        };
        assert_eq!(plan.level.as_deref(), Some("MAX"));
        let limit = plan.limits.first().expect("one quota limit");
        assert_eq!(limit.window, QuotaWindowV2::Other("monthly".to_owned()));
        assert_eq!(limit.percentage, 42.5);
        assert_eq!(limit.current_value, Some(1000.25));
        assert_eq!(limit.total, Some(2500.5));
        assert_eq!(limit.remaining, Some(1500.25));
        assert_eq!(limit.next_reset_at, Some(77));
        let detail = limit.usage_details.first().expect("one usage detail");
        assert_eq!(detail.name, "coder");
        assert_eq!(detail.total, Some(20.25));

        let serialized = serde_json::to_string(&snapshot).expect("frozen v2 serializes");
        let reparsed: SnapshotV2 = serde_json::from_str(&serialized).expect("frozen v2 re-parses");
        assert_eq!(reparsed, snapshot);
    }

    #[test]
    fn frozen_v2_lifecycle_accessors_mirror_the_historical_phases() {
        let loading: SnapshotV2 =
            serde_json::from_str(r#"{"state":{"kind":"loading","data":{"revision":4,"operation":"check","operationId":"op-9","startedAt":33}}}"#)
                .expect("loading wire parses");
        assert_eq!(loading.state.revision(), 4);
        assert_eq!(loading.state.updated_at(), 33);
        let stopped: SnapshotV2 = serde_json::from_str(
            r#"{"state":{"kind":"stopped","data":{"revision":6,"stoppedAt":88}}}"#,
        )
        .expect("stopped wire parses");
        assert_eq!(stopped.state.revision(), 6);
        assert_eq!(stopped.state.updated_at(), 88);
    }

    #[test]
    fn frozen_v3_tree_round_trips_and_preserves_every_field() {
        let cache: CacheV3 = serde_json::from_str(CACHE_V3).expect("v3 wire parses");
        assert_eq!(cache.format_version, 3);
        assert_eq!(cache.revision, 5);
        assert_eq!(cache.updated_at, 77);
        assert_eq!(cache.legacy_unbound.as_deref(), Some("old bytes"));
        let binding = cache.accounts.first().expect("one binding");
        assert_eq!(binding.query_identity, "identity-a");
        let observation = &binding.observation;
        assert_eq!(observation.account_id, "acct-1");
        assert_eq!(observation.query_revision, 2);
        assert_eq!(observation.revision, 3);
        assert_eq!(observation.phase, PhaseV3::Querying);
        assert_eq!(observation.operation_id.as_deref(), Some("op-7"));
        assert_eq!(observation.checked_at, Some(76));
        let failure = observation.failure.as_ref().expect("failure survives");
        assert_eq!(failure.code, FailureCodeV3::Cancelled);
        assert!(failure.retryable);
        let last_good = observation.last_good.as_ref().expect("last good survives");
        assert_eq!(last_good.checked_at, 75);
        let ValueV3::Subscription { level, quotas } = &last_good.value else {
            panic!("expected a subscription value");
        };
        assert_eq!(level.as_deref(), Some("MAX"));
        let quota = quotas.first().expect("one quota");
        assert_eq!(quota.window, QuotaWindowV3::FiveHour);
        assert_eq!(quota.used, Some(5.5));
        assert_eq!(quota.remaining, Some(4.75));
        assert_eq!(quota.reset_at, Some(99));
        assert_eq!(quota.details.first().expect("one detail").name, "tool");

        let serialized = serde_json::to_string(&cache).expect("frozen v3 serializes");
        let reparsed: CacheV3 = serde_json::from_str(&serialized).expect("frozen v3 re-parses");
        assert_eq!(reparsed, cache);
    }

    #[test]
    fn frozen_v3_converts_to_the_current_payload_via_try_from() {
        let cache: CacheV3 = serde_json::from_str(CACHE_V3).expect("v3 wire parses");
        let payload = AccountUsageSettingPayload::try_from(cache).expect("conversion succeeds");
        assert_eq!(payload.revision, 5);
        assert_eq!(payload.updated_at, 77);
        assert_eq!(payload.legacy_unbound.as_deref(), Some("old bytes"));
        let binding = payload.accounts.first().expect("one binding");
        assert_eq!(binding.query_identity, "identity-a");
        assert_eq!(binding.observation.account_id, "acct-1");
        assert_eq!(binding.observation.phase, AccountUsagePhase::Querying);
        assert_eq!(
            binding
                .observation
                .failure
                .as_ref()
                .map(|failure| failure.code),
            Some(AccountUsageFailureCode::Cancelled)
        );
        let AccountUsageValue::Subscription { level, quotas } = &binding
            .observation
            .last_good
            .as_ref()
            .expect("last good converts")
            .value
        else {
            panic!("expected a subscription value");
        };
        assert_eq!(level.as_deref(), Some("MAX"));
        assert_eq!(quotas[0].window, AccountQuotaWindow::FiveHour);
        assert_eq!(quotas[0].used, Some(5.5));
    }

    #[test]
    fn frozen_v3_try_from_rejects_invalid_and_duplicate_identities() {
        let duplicate_raw = r#"{"formatVersion":3,"revision":5,"updatedAt":77,"accounts":[{"queryIdentity":"a","observation":{"accountId":"dup","queryRevision":1,"revision":1,"phase":"unchecked","operationId":null,"checkedAt":null,"failure":null,"lastGood":null}},{"queryIdentity":"b","observation":{"accountId":"dup","queryRevision":1,"revision":1,"phase":"unchecked","operationId":null,"checkedAt":null,"failure":null,"lastGood":null}}],"legacyUnbound":null}"#;
        let cache: CacheV3 = serde_json::from_str(duplicate_raw).expect("v3 wire parses");
        assert!(AccountUsageSettingPayload::try_from(cache).is_err());

        let blank_raw = r#"{"formatVersion":3,"revision":5,"updatedAt":77,"accounts":[{"queryIdentity":"a","observation":{"accountId":"  ","queryRevision":1,"revision":1,"phase":"unchecked","operationId":null,"checkedAt":null,"failure":null,"lastGood":null}}],"legacyUnbound":null}"#;
        let cache: CacheV3 = serde_json::from_str(blank_raw).expect("v3 wire parses");
        assert!(AccountUsageSettingPayload::try_from(cache).is_err());
    }
}
