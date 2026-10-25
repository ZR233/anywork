//! Provider usage detail pages. Nullable measurements remain nullable.
use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::products::references::AccountUsageReadTarget;
use crate::products::source::SourceStateErrorRead;
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageCheckResult {
    pub target: AccountUsageReadTarget,
    pub account_id: String,
    pub usage_query_revision: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageReadHeader {
    pub config_fingerprint: ReadText,
    pub usages: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageRead {
    pub account_id: ReadText,
    pub revision: u64,
    pub updated_at: i64,
    pub last_operation_id: ReadText,
    pub state: AccountUsageResultRead,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AccountUsageResultRead {
    Unsupported,
    MissingCredential { message: ReadText },
    Ready { data: AccountUsageDataRead },
    Failed { error: SourceStateErrorRead },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum AccountUsageDataRead {
    DeepSeekBalance {
        is_available: bool,
        balances: TypedListRef,
    },
    ZhipuCodingPlan {
        level: Option<ReadText>,
        limits: TypedListRef,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BalanceRead {
    pub currency: ReadText,
    pub total_balance: ReadText,
    pub granted_balance: ReadText,
    pub topped_up_balance: ReadText,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuotaLimitRead {
    pub window: QuotaWindowRead,
    pub percentage: f64,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub remaining: Option<f64>,
    pub next_reset_at: Option<i64>,
    pub usage_details: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum QuotaWindowRead {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(ReadText),
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuotaDetailRead {
    pub name: ReadText,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub percentage: Option<f64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageEntityRead {
    pub reference: ProductEntityRef,
    pub value: AccountUsageRead,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountUsageReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<AccountUsageRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BalanceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BalanceRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuotaLimitReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<QuotaLimitRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct QuotaDetailReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<QuotaDetailRead>,
    pub next_offset: Option<u64>,
}
