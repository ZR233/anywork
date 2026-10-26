//! Opaque native reads. Transport admission and cleanup stay in the original bridge registry.
use super::super::identity::*;
use super::super::references::*;
use super::super::source::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::account_usage as protocol;
use pl_studio_runtime::{StudioAccountUsageRead, StudioAccountUsageSourceStatusRead};
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageCheckResult {
    pub target: BridgeAccountUsageReadTarget,
    pub account_id: String,
    pub usage_query_revision: u64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageReadHeader {
    pub config_fingerprint: BridgeReadText,
    pub usages: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAccountUsageRead {
    pub account_id: BridgeReadText,
    pub revision: u64,
    pub updated_at: i64,
    pub last_operation_id: BridgeReadText,
    pub state: BridgeAccountUsageResultRead,
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAccountUsageResultRead {
    Unsupported,
    MissingCredential { message: BridgeReadText },
    Ready { data: BridgeAccountUsageDataRead },
    Failed { error: BridgeSourceStateErrorRead },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAccountUsageDataRead {
    DeepSeekBalance {
        is_available: bool,
        balances: BridgeTypedListRef,
    },
    ZhipuCodingPlan {
        level: Option<BridgeReadText>,
        limits: BridgeTypedListRef,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBalanceRead {
    pub currency: BridgeReadText,
    pub total_balance: BridgeReadText,
    pub granted_balance: BridgeReadText,
    pub topped_up_balance: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeQuotaLimitRead {
    pub window: BridgeQuotaWindowRead,
    pub percentage: f64,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub remaining: Option<f64>,
    pub next_reset_at: Option<i64>,
    pub usage_details: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeQuotaWindowRead {
    FiveHour,
    Weekly,
    McpMonthly,
    Other(BridgeReadText),
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeQuotaDetailRead {
    pub name: BridgeReadText,
    pub current_value: Option<f64>,
    pub total: Option<f64>,
    pub percentage: Option<f64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAccountUsageEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeAccountUsageRead,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAccountUsageReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAccountUsageRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeBalanceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeBalanceRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeQuotaLimitReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeQuotaLimitRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeQuotaDetailReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeQuotaDetailRead>,
    pub next_offset: Option<u64>,
}
impl From<protocol::AccountUsageCheckResult> for BridgeAccountUsageCheckResult {
    fn from(value: protocol::AccountUsageCheckResult) -> Self {
        Self {
            target: value.target.into(),
            account_id: value.account_id,
            usage_query_revision: value.usage_query_revision,
        }
    }
}

impl From<protocol::AccountUsageReadHeader> for BridgeAccountUsageReadHeader {
    fn from(value: protocol::AccountUsageReadHeader) -> Self {
        Self {
            config_fingerprint: value.config_fingerprint.into(),
            usages: value.usages.into(),
        }
    }
}

impl From<protocol::AccountUsageRead> for BridgeAccountUsageRead {
    fn from(value: protocol::AccountUsageRead) -> Self {
        Self {
            account_id: value.account_id.into(),
            revision: value.revision,
            updated_at: value.updated_at,
            last_operation_id: value.last_operation_id.into(),
            state: value.state.into(),
        }
    }
}

impl From<protocol::BalanceRead> for BridgeBalanceRead {
    fn from(value: protocol::BalanceRead) -> Self {
        Self {
            currency: value.currency.into(),
            total_balance: value.total_balance.into(),
            granted_balance: value.granted_balance.into(),
            topped_up_balance: value.topped_up_balance.into(),
        }
    }
}

impl From<protocol::QuotaLimitRead> for BridgeQuotaLimitRead {
    fn from(value: protocol::QuotaLimitRead) -> Self {
        Self {
            window: value.window.into(),
            percentage: value.percentage,
            current_value: value.current_value,
            total: value.total,
            remaining: value.remaining,
            next_reset_at: value.next_reset_at,
            usage_details: value.usage_details.into(),
        }
    }
}

impl From<protocol::QuotaDetailRead> for BridgeQuotaDetailRead {
    fn from(value: protocol::QuotaDetailRead) -> Self {
        Self {
            name: value.name.into(),
            current_value: value.current_value,
            total: value.total,
            percentage: value.percentage,
        }
    }
}

impl From<protocol::AccountUsageEntryPage> for BridgeAccountUsageEntryPage {
    fn from(value: protocol::AccountUsageEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::AccountUsageEntityRead> for BridgeAccountUsageEntityRead {
    fn from(value: protocol::AccountUsageEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

impl From<protocol::AccountUsageReadPage> for BridgeAccountUsageReadPage {
    fn from(value: protocol::AccountUsageReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::BalanceReadPage> for BridgeBalanceReadPage {
    fn from(value: protocol::BalanceReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::QuotaLimitReadPage> for BridgeQuotaLimitReadPage {
    fn from(value: protocol::QuotaLimitReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::QuotaDetailReadPage> for BridgeQuotaDetailReadPage {
    fn from(value: protocol::QuotaDetailReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::AccountUsageResultRead> for BridgeAccountUsageResultRead {
    fn from(value: protocol::AccountUsageResultRead) -> Self {
        match value {
            protocol::AccountUsageResultRead::Unsupported => Self::Unsupported,
            protocol::AccountUsageResultRead::MissingCredential { message } => {
                Self::MissingCredential {
                    message: message.into(),
                }
            }
            protocol::AccountUsageResultRead::Ready { data } => Self::Ready { data: data.into() },
            protocol::AccountUsageResultRead::Failed { error } => Self::Failed {
                error: error.into(),
            },
        }
    }
}

impl From<protocol::AccountUsageDataRead> for BridgeAccountUsageDataRead {
    fn from(value: protocol::AccountUsageDataRead) -> Self {
        match value {
            protocol::AccountUsageDataRead::DeepSeekBalance {
                is_available,
                balances,
            } => Self::DeepSeekBalance {
                is_available,
                balances: balances.into(),
            },
            protocol::AccountUsageDataRead::ZhipuCodingPlan { level, limits } => {
                Self::ZhipuCodingPlan {
                    level: level.map(Into::into),
                    limits: limits.into(),
                }
            }
        }
    }
}

impl From<protocol::QuotaWindowRead> for BridgeQuotaWindowRead {
    fn from(value: protocol::QuotaWindowRead) -> Self {
        match value {
            protocol::QuotaWindowRead::FiveHour => Self::FiveHour,
            protocol::QuotaWindowRead::Weekly => Self::Weekly,
            protocol::QuotaWindowRead::McpMonthly => Self::McpMonthly,
            protocol::QuotaWindowRead::Other(value) => Self::Other(value.into()),
        }
    }
}

impl ModelsRead for StudioAccountUsageRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAccountUsageReadConnection {
    read: ModelsReadHandle<StudioAccountUsageRead>,
}
pub async fn open_account_usage_read(
    reference: BridgeAccountUsageReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeAccountUsageReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeAccountUsageReadConnection {
        read: open_read(move |runtime| runtime.open_account_usage_read(reference, origin)).await?,
    })
}
impl BridgeAccountUsageReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeAccountUsageReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioAccountUsageRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAccountUsageEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeAccountUsageEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_account(
        &self,
        account: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_account(account))?
            .await?
            .map(Into::into))
    }
    pub async fn usages(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAccountUsageReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.usages(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn balances(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeBalanceReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.balances(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn quota_limits(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeQuotaLimitReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.quota_limits(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn quota_details(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeQuotaDetailReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.quota_details(list_id, offset, limit))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

impl ModelsRead for StudioAccountUsageSourceStatusRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAccountUsageSourceStatusReadConnection {
    read: ModelsReadHandle<StudioAccountUsageSourceStatusRead>,
}
pub async fn open_account_usage_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeAccountUsageSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeAccountUsageSourceStatusReadConnection {
        read: open_read(move |runtime| {
            runtime.open_account_usage_source_status_read(reference, origin)
        })
        .await?,
    })
}
impl BridgeAccountUsageSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioAccountUsageSourceStatusRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

pub async fn check_account_usage_cas(
    account_id: String,
    expected_usage_query_revision: u64,
) -> Result<BridgeAccountUsageCheckResult, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .check_account_usage_cas(account_id, expected_usage_query_revision)
        .await?
        .into())
}
