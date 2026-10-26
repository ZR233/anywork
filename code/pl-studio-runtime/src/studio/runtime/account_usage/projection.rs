//! Provider observations enter the owner once; legacy HTTP/topic shapes are read-only projections.

use super::{AccountUsageStateData, AccountUsageStateSnapshot, UsageState, unix_seconds};
use crate::AccountUsageRecord;
use crate::account_usage::{
    AccountUsageData, AccountUsageState, DeepSeekBalanceInfo, DeepSeekBalanceUsage,
    ZhipuCodingPlanUsage, ZhipuQuotaLimit, ZhipuQuotaWindow, ZhipuToolUsageDetail,
};
use pl_protocol::studio::*;

pub(super) fn complete(entry: &mut AccountUsageObservation, result: Option<&AccountUsageRecord>) {
    entry.checked_at = Some(unix_seconds());
    entry.revision = entry.revision.saturating_add(1);
    entry.failure = None;
    entry.phase = match result.map(AccountUsageRecord::state) {
        Some(AccountUsageState::Ready(ready)) => {
            entry.last_good = Some(AccountUsageSuccess {
                checked_at: result.map_or_else(unix_seconds, AccountUsageRecord::updated_at),
                value: value(ready.data()),
            });
            AccountUsagePhase::Succeeded
        }
        Some(AccountUsageState::Unsupported(_)) => AccountUsagePhase::Unsupported,
        Some(AccountUsageState::MissingCredential(_)) => AccountUsagePhase::MissingCredential,
        Some(AccountUsageState::Failed(failed)) => {
            entry.failure = Some(AccountUsageFailure {
                code: if failed.error().code == "accountUsageConfigurationFailed" {
                    AccountUsageFailureCode::Configuration
                } else {
                    AccountUsageFailureCode::Query
                },
                retryable: failed.error().retryable,
            });
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

fn value(data: &AccountUsageData) -> AccountUsageValue {
    match data {
        AccountUsageData::DeepSeekBalance(data) => AccountUsageValue::Balance {
            available: data.is_available,
            balances: data
                .balances
                .iter()
                .map(|item| AccountMoneyBalance {
                    currency: item.currency.clone(),
                    total: item.total_balance.clone(),
                    granted: item.granted_balance.clone(),
                    topped_up: item.topped_up_balance.clone(),
                })
                .collect(),
        },
        AccountUsageData::ZhipuCodingPlan(data) => AccountUsageValue::Subscription {
            level: data.level.clone(),
            quotas: data
                .limits
                .iter()
                .map(|item| AccountQuota {
                    window: match &item.window {
                        ZhipuQuotaWindow::FiveHour => AccountQuotaWindow::FiveHour,
                        ZhipuQuotaWindow::Weekly => AccountQuotaWindow::Weekly,
                        ZhipuQuotaWindow::McpMonthly => AccountQuotaWindow::McpMonthly,
                        ZhipuQuotaWindow::Other(value) => AccountQuotaWindow::Other(value.clone()),
                    },
                    percentage: item.percentage,
                    used: item.current_value,
                    total: item.total,
                    remaining: item.remaining,
                    reset_at: item.next_reset_at,
                    details: item
                        .usage_details
                        .iter()
                        .map(|detail| AccountQuotaDetail {
                            name: detail.name.clone(),
                            used: detail.current_value,
                            total: detail.total,
                            percentage: detail.percentage,
                        })
                        .collect(),
                })
                .collect(),
        },
    }
}

fn legacy_value(value: &AccountUsageValue) -> AccountUsageData {
    match value {
        AccountUsageValue::Balance {
            available,
            balances,
        } => AccountUsageData::DeepSeekBalance(DeepSeekBalanceUsage {
            is_available: *available,
            balances: balances
                .iter()
                .map(|item| DeepSeekBalanceInfo {
                    currency: item.currency.clone(),
                    total_balance: item.total.clone(),
                    granted_balance: item.granted.clone(),
                    topped_up_balance: item.topped_up.clone(),
                })
                .collect(),
        }),
        AccountUsageValue::Subscription { level, quotas } => {
            AccountUsageData::ZhipuCodingPlan(ZhipuCodingPlanUsage {
                level: level.clone(),
                limits: quotas
                    .iter()
                    .map(|item| ZhipuQuotaLimit {
                        window: match &item.window {
                            AccountQuotaWindow::FiveHour => ZhipuQuotaWindow::FiveHour,
                            AccountQuotaWindow::Weekly => ZhipuQuotaWindow::Weekly,
                            AccountQuotaWindow::McpMonthly => ZhipuQuotaWindow::McpMonthly,
                            AccountQuotaWindow::Other(value) => {
                                ZhipuQuotaWindow::Other(value.clone())
                            }
                        },
                        percentage: item.percentage,
                        current_value: item.used,
                        total: item.total,
                        remaining: item.remaining,
                        next_reset_at: item.reset_at,
                        usage_details: item
                            .details
                            .iter()
                            .map(|detail| ZhipuToolUsageDetail {
                                name: detail.name.clone(),
                                current_value: detail.used,
                                total: detail.total,
                                percentage: detail.percentage,
                            })
                            .collect(),
                    })
                    .collect(),
            })
        }
    }
}

pub(super) fn legacy_snapshot(state: &UsageState) -> AccountUsageStateSnapshot {
    let usages = state
        .accounts
        .values()
        .map(|entry| {
            let status = if let Some(good) = &entry.last_good {
                AccountUsageState::ready(legacy_value(&good.value))
            } else {
                match entry.phase {
                    AccountUsagePhase::Unchecked
                    | AccountUsagePhase::Querying
                    | AccountUsagePhase::Unsupported => AccountUsageState::unsupported(),
                    AccountUsagePhase::MissingCredential => {
                        AccountUsageState::missing_credential("account API key is not configured")
                    }
                    AccountUsagePhase::Failed => {
                        AccountUsageState::failed(pl_protocol::StateError {
                            code: "accountUsageQueryFailed".into(),
                            message: "Account usage query failed".into(),
                            retryable: entry.failure.as_ref().is_some_and(|error| error.retryable),
                        })
                    }
                    AccountUsagePhase::Succeeded => AccountUsageState::unsupported(),
                }
            };
            // This is a projection of canonical data, never an independently writable record.
            AccountUsageRecord::from_projection(
                entry.account_id.clone(),
                entry.revision,
                entry.checked_at.unwrap_or(0),
                entry.operation_id.clone().unwrap_or_default(),
                status,
            )
        })
        .collect();
    AccountUsageStateSnapshot {
        state: pl_protocol::ObservedResource::ready(
            state.revision,
            state.updated_at,
            AccountUsageStateData {
                config_fingerprint: String::new(),
                usages,
            },
        ),
    }
}
