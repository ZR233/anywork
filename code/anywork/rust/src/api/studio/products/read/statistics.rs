//! Opaque native reads. Transport admission and cleanup stay in the original bridge registry.
use super::super::identity::*;
use super::super::references::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::statistics as protocol;
use pl_studio_runtime::statistics::{
    StudioPerformanceEffortIdentityRead, StudioPerformanceHistoryRead,
    StudioPerformanceSampleIdentityRead, StudioPerformanceSummariesRead,
    StudioPerformanceSummaryIdentityRead, StudioSessionCostsRead,
};

/// Model matching facts carried by one statistics sample's named identity read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeModelMatchState {
    Matched,
    Mismatched,
    Unreported,
    LegacyUnknown,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceCounters {
    pub sample_count: u64,
    pub completion_tokens: u64,
    pub total_ttft_millis: u64,
    pub ttft_sample_count: u64,
    pub total_response_millis: u64,
    pub tokens_per_second: f64,
    pub average_ttft_millis: Option<f64>,
    pub average_response_millis: f64,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceSampleCounters {
    pub completed_at: i64,
    pub completion_tokens: u64,
    pub ttft_millis: Option<u64>,
    pub decode_millis: Option<u64>,
    pub total_response_millis: Option<u64>,
    pub tokens_per_second: Option<f64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummariesReadHeader {
    pub summaries: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceHistoryReadHeader {
    pub samples: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceSummaryRead {
    pub identity: BridgePerformanceSummaryIdentityRef,
    pub counters: BridgePerformanceCounters,
    pub effort_breakdowns: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceEffortRead {
    pub identity: BridgePerformanceEffortIdentityRef,
    pub counters: BridgePerformanceCounters,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceSampleRead {
    pub identity: BridgePerformanceSampleIdentityRef,
    pub counters: BridgePerformanceSampleCounters,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummaryIdentityRead {
    pub account_id: BridgeReadText,
    pub account_display_name: BridgeReadText,
    pub model_id: BridgeReadText,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceEffortIdentityRead {
    pub effort: Option<BridgeReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSampleIdentityRead {
    pub account_id: BridgeReadText,
    pub account_display_name: BridgeReadText,
    pub model_id: Option<BridgeReadText>,
    pub sent_model: Option<BridgeReadText>,
    pub reported_model: Option<BridgeReadText>,
    pub model_match_state: BridgeModelMatchState,
    pub effort: Option<BridgeReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSessionCostsReadHeader {
    pub cost: Option<BridgeSessionCostRead>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSessionCostRead {
    pub root_thread_id: BridgeReadText,
    pub purpose_costs: BridgeTypedListRef,
    pub estimated_costs: BridgeTypedListRef,
    pub has_unpriced_usage: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePurposeCostRead {
    pub purpose: Option<BridgeReadText>,
    pub estimated_costs: BridgeTypedListRef,
    pub has_unpriced_usage: bool,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeRuntimeCostRead {
    pub currency: BridgeReadText,
    pub amount: f64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummariesEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceSummariesEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgePerformanceSummaryRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceHistoryEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceHistoryEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgePerformanceSampleRead,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceSummaryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgePerformanceSummaryRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceEffortReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgePerformanceEffortRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePerformanceSampleReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgePerformanceSampleRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgePurposeCostReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgePurposeCostRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeRuntimeCostReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeRuntimeCostRead>,
    pub next_offset: Option<u64>,
}
impl From<protocol::PerformanceCounters> for BridgePerformanceCounters {
    fn from(value: protocol::PerformanceCounters) -> Self {
        Self {
            sample_count: value.sample_count,
            completion_tokens: value.completion_tokens,
            total_ttft_millis: value.total_ttft_millis,
            ttft_sample_count: value.ttft_sample_count,
            total_response_millis: value.total_response_millis,
            tokens_per_second: value.tokens_per_second,
            average_ttft_millis: value.average_ttft_millis,
            average_response_millis: value.average_response_millis,
        }
    }
}

impl From<protocol::PerformanceSampleCounters> for BridgePerformanceSampleCounters {
    fn from(value: protocol::PerformanceSampleCounters) -> Self {
        Self {
            completed_at: value.completed_at,
            completion_tokens: value.completion_tokens,
            ttft_millis: value.ttft_millis,
            decode_millis: value.decode_millis,
            total_response_millis: value.total_response_millis,
            tokens_per_second: value.tokens_per_second,
        }
    }
}

impl From<protocol::PerformanceSummariesReadHeader> for BridgePerformanceSummariesReadHeader {
    fn from(value: protocol::PerformanceSummariesReadHeader) -> Self {
        Self {
            summaries: value.summaries.into(),
        }
    }
}

impl From<protocol::PerformanceHistoryReadHeader> for BridgePerformanceHistoryReadHeader {
    fn from(value: protocol::PerformanceHistoryReadHeader) -> Self {
        Self {
            samples: value.samples.into(),
        }
    }
}

impl From<protocol::PerformanceSummaryRead> for BridgePerformanceSummaryRead {
    fn from(value: protocol::PerformanceSummaryRead) -> Self {
        Self {
            identity: value.identity.into(),
            counters: value.counters.into(),
            effort_breakdowns: value.effort_breakdowns.into(),
        }
    }
}

impl From<protocol::PerformanceEffortRead> for BridgePerformanceEffortRead {
    fn from(value: protocol::PerformanceEffortRead) -> Self {
        Self {
            identity: value.identity.into(),
            counters: value.counters.into(),
        }
    }
}

impl From<protocol::PerformanceSampleRead> for BridgePerformanceSampleRead {
    fn from(value: protocol::PerformanceSampleRead) -> Self {
        Self {
            identity: value.identity.into(),
            counters: value.counters.into(),
        }
    }
}

impl From<protocol::PerformanceSummaryIdentityRead> for BridgePerformanceSummaryIdentityRead {
    fn from(value: protocol::PerformanceSummaryIdentityRead) -> Self {
        Self {
            account_id: value.account_id.into(),
            account_display_name: value.account_display_name.into(),
            model_id: value.model_id.into(),
        }
    }
}

impl From<protocol::PerformanceEffortIdentityRead> for BridgePerformanceEffortIdentityRead {
    fn from(value: protocol::PerformanceEffortIdentityRead) -> Self {
        Self {
            effort: value.effort.map(Into::into),
        }
    }
}

impl From<protocol::PerformanceSampleIdentityRead> for BridgePerformanceSampleIdentityRead {
    fn from(value: protocol::PerformanceSampleIdentityRead) -> Self {
        Self {
            account_id: value.account_id.into(),
            account_display_name: value.account_display_name.into(),
            model_id: value.model_id.map(Into::into),
            sent_model: value.sent_model.map(Into::into),
            reported_model: value.reported_model.map(Into::into),
            model_match_state: match value.model_match_state {
                pl_protocol::ModelMatchState::Matched => BridgeModelMatchState::Matched,
                pl_protocol::ModelMatchState::Mismatched => BridgeModelMatchState::Mismatched,
                pl_protocol::ModelMatchState::Unreported => BridgeModelMatchState::Unreported,
                pl_protocol::ModelMatchState::LegacyUnknown => BridgeModelMatchState::LegacyUnknown,
            },
            effort: value.effort.map(Into::into),
        }
    }
}

impl From<protocol::SessionCostsReadHeader> for BridgeSessionCostsReadHeader {
    fn from(value: protocol::SessionCostsReadHeader) -> Self {
        Self {
            cost: value.cost.map(Into::into),
        }
    }
}

impl From<protocol::SessionCostRead> for BridgeSessionCostRead {
    fn from(value: protocol::SessionCostRead) -> Self {
        Self {
            root_thread_id: value.root_thread_id.into(),
            purpose_costs: value.purpose_costs.into(),
            estimated_costs: value.estimated_costs.into(),
            has_unpriced_usage: value.has_unpriced_usage,
        }
    }
}

impl From<protocol::PurposeCostRead> for BridgePurposeCostRead {
    fn from(value: protocol::PurposeCostRead) -> Self {
        Self {
            purpose: value.purpose.map(Into::into),
            estimated_costs: value.estimated_costs.into(),
            has_unpriced_usage: value.has_unpriced_usage,
        }
    }
}

impl From<protocol::RuntimeCostRead> for BridgeRuntimeCostRead {
    fn from(value: protocol::RuntimeCostRead) -> Self {
        Self {
            currency: value.currency.into(),
            amount: value.amount,
        }
    }
}

impl From<protocol::PerformanceSummariesEntryPage> for BridgePerformanceSummariesEntryPage {
    fn from(value: protocol::PerformanceSummariesEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::PerformanceSummariesEntityRead> for BridgePerformanceSummariesEntityRead {
    fn from(value: protocol::PerformanceSummariesEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

impl From<protocol::PerformanceHistoryEntryPage> for BridgePerformanceHistoryEntryPage {
    fn from(value: protocol::PerformanceHistoryEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::PerformanceHistoryEntityRead> for BridgePerformanceHistoryEntityRead {
    fn from(value: protocol::PerformanceHistoryEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

impl From<protocol::PerformanceSummaryReadPage> for BridgePerformanceSummaryReadPage {
    fn from(value: protocol::PerformanceSummaryReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::PerformanceEffortReadPage> for BridgePerformanceEffortReadPage {
    fn from(value: protocol::PerformanceEffortReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::PerformanceSampleReadPage> for BridgePerformanceSampleReadPage {
    fn from(value: protocol::PerformanceSampleReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::PurposeCostReadPage> for BridgePurposeCostReadPage {
    fn from(value: protocol::PurposeCostReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::RuntimeCostReadPage> for BridgeRuntimeCostReadPage {
    fn from(value: protocol::RuntimeCostReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl ModelsRead for StudioPerformanceSummariesRead {
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
pub struct BridgePerformanceSummariesReadConnection {
    read: ModelsReadHandle<StudioPerformanceSummariesRead>,
}
pub async fn open_performance_summaries_read(
    reference: BridgePerformanceSummariesReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePerformanceSummariesReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePerformanceSummariesReadConnection {
        read: open_read(move |runtime| runtime.open_performance_summaries_read(reference, origin))
            .await?,
    })
}
impl BridgePerformanceSummariesReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePerformanceSummariesReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioPerformanceSummariesRead::header)?
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
    ) -> Result<BridgePerformanceSummariesEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgePerformanceSummariesEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_summary(
        &self,
        account_id: String,
        model_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_summary(account_id, model_id))?
            .await?
            .map(Into::into))
    }
    pub async fn summaries(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgePerformanceSummaryReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.summaries(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn effort_breakdowns(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgePerformanceEffortReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.effort_breakdowns(list_id, offset, limit))?
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

impl ModelsRead for StudioPerformanceHistoryRead {
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
pub struct BridgePerformanceHistoryReadConnection {
    read: ModelsReadHandle<StudioPerformanceHistoryRead>,
}
pub async fn open_performance_history_read(
    reference: BridgePerformanceHistoryReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePerformanceHistoryReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePerformanceHistoryReadConnection {
        read: open_read(move |runtime| runtime.open_performance_history_read(reference, origin))
            .await?,
    })
}
impl BridgePerformanceHistoryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePerformanceHistoryReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioPerformanceHistoryRead::header)?
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
    ) -> Result<BridgePerformanceHistoryEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgePerformanceHistoryEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn samples(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgePerformanceSampleReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.samples(list_id, offset, limit))?
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

impl ModelsRead for StudioSessionCostsRead {
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
pub struct BridgeSessionCostsReadConnection {
    read: ModelsReadHandle<StudioSessionCostsRead>,
}
pub async fn open_session_costs_read(
    reference: BridgeSessionCostsReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeSessionCostsReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeSessionCostsReadConnection {
        read: open_read(move |runtime| runtime.open_session_costs_read(reference, origin)).await?,
    })
}
impl BridgeSessionCostsReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeSessionCostsReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioSessionCostsRead::header)?
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
    pub async fn purposes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgePurposeCostReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.purposes(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn amounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeRuntimeCostReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.amounts(list_id, offset, limit))?
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

impl ModelsRead for StudioPerformanceSummaryIdentityRead {
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
pub struct BridgePerformanceSummaryIdentityReadConnection {
    read: ModelsReadHandle<StudioPerformanceSummaryIdentityRead>,
}
pub async fn open_summary_identity(
    reference: BridgePerformanceSummaryIdentityRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePerformanceSummaryIdentityReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePerformanceSummaryIdentityReadConnection {
        read: open_read(move |runtime| runtime.open_summary_identity(reference, origin)).await?,
    })
}
impl BridgePerformanceSummaryIdentityReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePerformanceSummaryIdentityRead, BridgeError> {
        Ok(self
            .read
            .query(StudioPerformanceSummaryIdentityRead::header)?
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

impl ModelsRead for StudioPerformanceEffortIdentityRead {
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
pub struct BridgePerformanceEffortIdentityReadConnection {
    read: ModelsReadHandle<StudioPerformanceEffortIdentityRead>,
}
pub async fn open_effort_identity(
    reference: BridgePerformanceEffortIdentityRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePerformanceEffortIdentityReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePerformanceEffortIdentityReadConnection {
        read: open_read(move |runtime| runtime.open_effort_identity(reference, origin)).await?,
    })
}
impl BridgePerformanceEffortIdentityReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePerformanceEffortIdentityRead, BridgeError> {
        Ok(self
            .read
            .query(StudioPerformanceEffortIdentityRead::header)?
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

impl ModelsRead for StudioPerformanceSampleIdentityRead {
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
pub struct BridgePerformanceSampleIdentityReadConnection {
    read: ModelsReadHandle<StudioPerformanceSampleIdentityRead>,
}
pub async fn open_sample_identity(
    reference: BridgePerformanceSampleIdentityRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgePerformanceSampleIdentityReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePerformanceSampleIdentityReadConnection {
        read: open_read(move |runtime| runtime.open_sample_identity(reference, origin)).await?,
    })
}
impl BridgePerformanceSampleIdentityReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePerformanceSampleIdentityRead, BridgeError> {
        Ok(self
            .read
            .query(StudioPerformanceSampleIdentityRead::header)?
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
