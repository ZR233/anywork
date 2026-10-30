//! Final provider usage and the immutable estimate attached to an invocation.

use serde::{Deserialize, Serialize};

use crate::{ModelPricingSnapshot, RuntimeCostAmount};

/// Provider-reported counters. Absence means unknown, not zero.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageReport {
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub cache_read_tokens: Option<u64>,
    pub cache_write_tokens: Option<u64>,
    pub reasoning_tokens: Option<u64>,
    pub total_tokens: Option<u64>,
}

/// Why a complete monetary estimate cannot be produced.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum UnpricedReason {
    MissingUsage,
    InvalidUsage,
    MissingPrice,
    MissingCacheUsage,
    UnsupportedServiceTier,
}

/// Monetary estimates are independent of whether tokens were reported.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum PricingOutcome {
    /// Historical requests whose monetary estimation was disabled, not a free call.
    Disabled,
    /// Frozen account declaration; no monetary contribution or invented tariff.
    NoCharge,
    Unpriced {
        reason: UnpricedReason,
    },
    Estimated {
        cost: RuntimeCostAmount,
        cache_savings: Option<RuntimeCostAmount>,
    },
}

impl Default for PricingOutcome {
    fn default() -> Self {
        Self::Unpriced {
            reason: UnpricedReason::MissingUsage,
        }
    }
}

/// Canonical final accounting, retained even when an invocation fails.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InferenceAccounting {
    pub usage: UsageReport,
    pub pricing: PricingOutcome,
    pub price_snapshot: Option<ModelPricingSnapshot>,
    pub request_started_at: Option<i64>,
}

impl InferenceAccounting {
    /// Frozen monetary contribution; no-charge, historical disabled and unknown are not zero rates.
    pub fn estimated_costs(&self) -> Vec<RuntimeCostAmount> {
        match &self.pricing {
            PricingOutcome::Estimated { cost, .. } => vec![cost.clone()],
            PricingOutcome::NoCharge
            | PricingOutcome::Disabled
            | PricingOutcome::Unpriced { .. } => Vec::new(),
        }
    }

    /// Frozen cache savings, when the input breakdown and rates were available.
    pub fn estimated_cache_savings(&self) -> Vec<RuntimeCostAmount> {
        match &self.pricing {
            PricingOutcome::Estimated { cache_savings, .. } => {
                cache_savings.iter().cloned().collect()
            }
            PricingOutcome::NoCharge
            | PricingOutcome::Disabled
            | PricingOutcome::Unpriced { .. } => Vec::new(),
        }
    }

    pub fn has_unpriced_usage(&self) -> bool {
        matches!(self.pricing, PricingOutcome::Unpriced { .. })
    }
}

/// Current request policy derived from the account category and frozen for each invocation.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PricingMode {
    #[default]
    Catalog,
    NoCharge,
}

impl From<crate::BillingKind> for PricingMode {
    fn from(kind: crate::BillingKind) -> Self {
        match kind {
            crate::BillingKind::NoCharge => Self::NoCharge,
            crate::BillingKind::Metered
            | crate::BillingKind::Subscription
            | crate::BillingKind::Unknown => Self::Catalog,
        }
    }
}
