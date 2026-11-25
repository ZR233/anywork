//! 模型目录价格展示、调用时价格快照与单次推理计费结果。

use serde::{Deserialize, Serialize};

use crate::config::BillingKind;

/// Display projection of all applicable catalog price bands, per million tokens.
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelPricingDto {
    pub currency: String,
    pub tiers: Vec<ModelPriceTierDto>,
    pub source: String,
    pub verified_at: i64,
}

/// A complete display row; clients format these rates without calculating multipliers.
#[derive(
    schemars::JsonSchema, Debug, Clone, Serialize, Deserialize, PartialEq, utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub struct ModelPriceTierDto {
    pub label: String,
    pub input_per_mtok: f64,
    pub output_per_mtok: f64,
    pub cache_read_per_mtok: Option<f64>,
    pub cache_write_per_mtok: Option<f64>,
}

/// 模型调用发生时使用的价格快照。
///
/// 历史账单只能使用该快照重建，不能按当前 catalog 价格重新计算。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ModelPricingSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_per_mtok: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_per_mtok: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_read_per_mtok: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_write_per_mtok: Option<f64>,
}

/// Estimated runtime cost in a single currency.
///
/// Costs are local estimates derived from configured per-million-token prices.
/// Different currencies must remain separate and are never converted or summed
/// together.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeCostAmount {
    pub currency: String,
    pub amount: f64,
}

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

impl From<BillingKind> for PricingMode {
    fn from(kind: BillingKind) -> Self {
        match kind {
            BillingKind::NoCharge => Self::NoCharge,
            BillingKind::Metered | BillingKind::Subscription | BillingKind::Unknown => {
                Self::Catalog
            }
        }
    }
}
