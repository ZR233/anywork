use super::types::*;
use crate::api::studio::convert::{
    acp::{bridge_acp_account_settings, bridge_acp_auth_snapshot},
    acp_install::bridge_acp_install_snapshot,
    settings::{bridge_account_settings, bridge_model_catalog_account},
};
use crate::api::studio::types::BridgeResourceStamp;
use pl_protocol::studio as p;

impl From<BridgeAccountIdentity> for p::AccountIdentity {
    fn from(value: BridgeAccountIdentity) -> Self {
        match value {
            BridgeAccountIdentity::Native { account_id } => Self::Native { account_id },
            BridgeAccountIdentity::Acp { account_id } => Self::Acp { account_id },
        }
    }
}

impl From<p::AccountIdentity> for BridgeAccountIdentity {
    fn from(value: p::AccountIdentity) -> Self {
        match value {
            p::AccountIdentity::Native { account_id } => Self::Native { account_id },
            p::AccountIdentity::Acp { account_id } => Self::Acp { account_id },
        }
    }
}

impl From<BridgeAccountObservationTarget> for p::AccountObservationTarget {
    fn from(value: BridgeAccountObservationTarget) -> Self {
        match value {
            BridgeAccountObservationTarget::Summaries => Self::Summaries,
            BridgeAccountObservationTarget::Detail { identity } => Self::Detail {
                identity: identity.into(),
            },
            BridgeAccountObservationTarget::Models { account_id } => Self::Models { account_id },
            BridgeAccountObservationTarget::Usage => Self::Usage,
            BridgeAccountObservationTarget::AcpAuth => Self::AcpAuth,
            BridgeAccountObservationTarget::AcpInstall => Self::AcpInstall,
        }
    }
}

fn stamp(value: p::ResourceStamp) -> BridgeResourceStamp {
    BridgeResourceStamp {
        resource_key: value.resource_key,
        owner_epoch: value.owner_epoch,
        revision: value.revision,
    }
}

pub(super) fn frame(value: p::AccountDomainFrame) -> BridgeAccountDomainFrame {
    match value {
        p::AccountDomainFrame::Summaries {
            stamp: source,
            accounts,
        } => BridgeAccountDomainFrame::Summaries {
            stamp: stamp(source),
            accounts: accounts
                .into_iter()
                .map(|account| BridgeAccountSummary {
                    identity: account.identity.into(),
                    name: account.name,
                    brand_key: account.brand_key,
                    display_endpoint: account.display_endpoint,
                    is_default: account.is_default,
                    billing_kind: account.billing_kind.map(Into::into),
                    billing_kind_override: account.billing_kind_override.map(Into::into),
                    credential_ready: account.credential_ready,
                    usage_query_revision: account.usage_query_revision,
                    acp_connection_revision: account.acp_connection_revision,
                    capabilities: BridgeAccountCapabilities {
                        set_default: account.capabilities.set_default,
                        edit: account.capabilities.edit,
                        remove: account.capabilities.remove,
                        query_usage: account.capabilities.query_usage,
                        sync_models: account.capabilities.sync_models,
                        edit_models: account.capabilities.edit_models,
                        acp_auth: account.capabilities.acp_auth,
                    },
                })
                .collect(),
        },
        p::AccountDomainFrame::Detail {
            stamp: source,
            identity,
            account,
        } => BridgeAccountDomainFrame::Detail {
            stamp: stamp(source),
            identity: identity.into(),
            account: account.map(|account| match account {
                p::AccountDetail::Native(account) => {
                    BridgeAccountDetail::Native(Box::new(bridge_account_settings(*account)))
                }
                p::AccountDetail::Acp(account) => {
                    BridgeAccountDetail::Acp(bridge_acp_account_settings(account))
                }
            }),
        },
        p::AccountDomainFrame::Models {
            stamp: source,
            account_id,
            catalog,
        } => BridgeAccountDomainFrame::Models {
            stamp: stamp(source),
            account_id,
            catalog: catalog.map(bridge_model_catalog_account),
        },
        p::AccountDomainFrame::Usage {
            stamp: source,
            accounts,
        } => BridgeAccountDomainFrame::Usage {
            stamp: stamp(source),
            accounts: accounts.into_iter().map(usage).collect(),
        },
        p::AccountDomainFrame::AcpAuth {
            stamp: source,
            snapshot,
        } => BridgeAccountDomainFrame::AcpAuth {
            stamp: stamp(source),
            snapshot: bridge_acp_auth_snapshot(snapshot),
        },
        p::AccountDomainFrame::AcpInstall {
            stamp: source,
            snapshot,
        } => BridgeAccountDomainFrame::AcpInstall {
            stamp: stamp(source),
            snapshot: bridge_acp_install_snapshot(snapshot),
        },
    }
}

fn usage(value: p::AccountUsageObservation) -> BridgeAccountUsageObservation {
    BridgeAccountUsageObservation {
        account_id: value.account_id,
        query_revision: value.query_revision,
        revision: value.revision,
        phase: match value.phase {
            p::AccountUsagePhase::Unchecked => BridgeAccountUsagePhase::Unchecked,
            p::AccountUsagePhase::Querying => BridgeAccountUsagePhase::Querying,
            p::AccountUsagePhase::Succeeded => BridgeAccountUsagePhase::Succeeded,
            p::AccountUsagePhase::Unsupported => BridgeAccountUsagePhase::Unsupported,
            p::AccountUsagePhase::MissingCredential => BridgeAccountUsagePhase::MissingCredential,
            p::AccountUsagePhase::Failed => BridgeAccountUsagePhase::Failed,
        },
        operation_id: value.operation_id,
        checked_at: value.checked_at,
        failure: value.failure.map(|failure| BridgeAccountUsageFailure {
            code: match failure.code {
                p::AccountUsageFailureCode::Configuration => {
                    BridgeAccountUsageFailureCode::Configuration
                }
                p::AccountUsageFailureCode::Query => BridgeAccountUsageFailureCode::Query,
                p::AccountUsageFailureCode::Cancelled => BridgeAccountUsageFailureCode::Cancelled,
                p::AccountUsageFailureCode::TaskFailed => BridgeAccountUsageFailureCode::TaskFailed,
            },
            retryable: failure.retryable,
        }),
        last_good: value.last_good.map(|good| BridgeAccountUsageSuccess {
            checked_at: good.checked_at,
            value: match good.value {
                p::AccountUsageValue::Balance {
                    available,
                    balances,
                } => BridgeAccountUsageValue::Balance {
                    available,
                    balances: balances
                        .into_iter()
                        .map(|item| BridgeAccountMoneyBalance {
                            currency: item.currency,
                            total: item.total,
                            granted: item.granted,
                            topped_up: item.topped_up,
                        })
                        .collect(),
                },
                p::AccountUsageValue::Subscription { level, quotas } => {
                    BridgeAccountUsageValue::Subscription {
                        level,
                        quotas: quotas
                            .into_iter()
                            .map(|item| BridgeAccountQuota {
                                window: match item.window {
                                    p::AccountQuotaWindow::FiveHour => {
                                        BridgeAccountQuotaWindow::FiveHour
                                    }
                                    p::AccountQuotaWindow::Weekly => {
                                        BridgeAccountQuotaWindow::Weekly
                                    }
                                    p::AccountQuotaWindow::McpMonthly => {
                                        BridgeAccountQuotaWindow::McpMonthly
                                    }
                                    p::AccountQuotaWindow::Other(value) => {
                                        BridgeAccountQuotaWindow::Other(value)
                                    }
                                },
                                percentage: item.percentage,
                                used: item.used,
                                total: item.total,
                                remaining: item.remaining,
                                reset_at: item.reset_at,
                                details: item
                                    .details
                                    .into_iter()
                                    .map(|item| BridgeAccountQuotaDetail {
                                        name: item.name,
                                        used: item.used,
                                        total: item.total,
                                        percentage: item.percentage,
                                    })
                                    .collect(),
                            })
                            .collect(),
                    }
                }
            },
        }),
    }
}
