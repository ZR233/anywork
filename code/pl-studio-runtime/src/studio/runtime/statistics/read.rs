use super::super::StudioRuntime;
use super::material::{StatisticsIdentityReadMaterial, StatisticsReadMaterial};
use super::scope::StatisticsScope;
use super::source::{IdentityValue, Key};
use anyhow::Result;
use pl_protocol::products::identity::{
    ProductEntityRef, ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion,
    ProductResource,
};
use pl_protocol::products::read::statistics::*;
use pl_protocol::products::references::*;
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioPerformanceSummariesRead {
    scope: StatisticsScope<StatisticsReadMaterial>,
}
pub struct StudioPerformanceHistoryRead {
    scope: StatisticsScope<StatisticsReadMaterial>,
}
pub struct StudioSessionCostsRead {
    scope: StatisticsScope<StatisticsReadMaterial>,
}
pub struct StudioPerformanceSummaryIdentityRead {
    scope: StatisticsScope<StatisticsIdentityReadMaterial>,
}
pub struct StudioPerformanceEffortIdentityRead {
    scope: StatisticsScope<StatisticsIdentityReadMaterial>,
}
pub struct StudioPerformanceSampleIdentityRead {
    scope: StatisticsScope<StatisticsIdentityReadMaterial>,
}

impl StudioRuntime {
    pub fn open_performance_summaries_read(
        &self,
        reference: PerformanceSummariesReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPerformanceSummariesRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.statistics_source.pin(
                &origin,
                reference.entry,
                reference.revision,
                |key| *key == Key::Summaries,
            )?;
            let scope = StatisticsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::PerformanceSummaries,
                "statistics.summaries",
                StatisticsReadMaterial::new(material),
            )?;
            Ok(StudioPerformanceSummariesRead { scope })
        })
    }
    pub fn open_performance_history_read(
        &self,
        reference: PerformanceHistoryReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPerformanceHistoryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.statistics_source.pin(
                &origin,
                reference.entry,
                reference.revision,
                |key| *key == Key::History,
            )?;
            let scope = StatisticsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::PerformanceHistory,
                "statistics.samples",
                StatisticsReadMaterial::new(material),
            )?;
            Ok(StudioPerformanceHistoryRead { scope })
        })
    }
    pub fn open_session_costs_read(
        &self,
        reference: SessionCostsReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioSessionCostsRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.statistics_source.pin(
                &origin,
                reference.entry,
                reference.revision,
                |key| matches!(key, Key::Costs(_)),
            )?;
            let scope = StatisticsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::SessionCosts,
                "statistics.costs",
                StatisticsReadMaterial::new(material),
            )?;
            Ok(StudioSessionCostsRead { scope })
        })
    }
    pub fn open_summary_identity(
        &self,
        reference: PerformanceSummaryIdentityRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPerformanceSummaryIdentityRead>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.statistics_source.pin_identity(
                &origin,
                ProductEntityRef {
                    entry: reference.entry,
                    revision: reference.revision,
                },
            )?;
            if !matches!(material.value, IdentityValue::Summary { .. }) {
                return Err(StudioError::invalid_argument("Expected a summary identity").into());
            }
            let scope = StatisticsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::PerformanceSummaries,
                "statistics.summaryIdentity",
                StatisticsIdentityReadMaterial::new(material),
            )?;
            Ok(StudioPerformanceSummaryIdentityRead { scope })
        })
    }
    pub fn open_effort_identity(
        &self,
        reference: PerformanceEffortIdentityRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPerformanceEffortIdentityRead>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.statistics_source.pin_identity(
                &origin,
                ProductEntityRef {
                    entry: reference.entry,
                    revision: reference.revision,
                },
            )?;
            if !matches!(material.value, IdentityValue::Effort(_)) {
                return Err(StudioError::invalid_argument("Expected an effort identity").into());
            }
            let scope = StatisticsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::PerformanceSummaries,
                "statistics.effortIdentity",
                StatisticsIdentityReadMaterial::new(material),
            )?;
            Ok(StudioPerformanceEffortIdentityRead { scope })
        })
    }
    pub fn open_sample_identity(
        &self,
        reference: PerformanceSampleIdentityRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPerformanceSampleIdentityRead>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.statistics_source.pin_identity(
                &origin,
                ProductEntityRef {
                    entry: reference.entry,
                    revision: reference.revision,
                },
            )?;
            if !matches!(material.value, IdentityValue::Sample { .. }) {
                return Err(StudioError::invalid_argument("Expected a sample identity").into());
            }
            let scope = StatisticsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::PerformanceHistory,
                "statistics.sampleIdentity",
                StatisticsIdentityReadMaterial::new(material),
            )?;
            Ok(StudioPerformanceSampleIdentityRead { scope })
        })
    }
}
macro_rules! lifecycle {
    ($read:ident, $header:ty, $material:ty, $method:ident) => {
        impl $read {
            pub fn identity(&self) -> ProductReadScopeIdentity {
                self.scope.identity()
            }
            pub fn ensure_open(&self) -> Result<(), StudioError> {
                self.scope.ensure_open()
            }
            pub fn header(&self) -> impl Future<Output = Result<$header>> + Send + 'static + use<> {
                self.scope.query(<$material>::$method)
            }
            pub fn text(
                &self,
                field_id: u64,
                offset: u64,
                max_bytes: u32,
            ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
                self.scope
                    .query(move |material| material.text(field_id, offset, max_bytes))
            }
            pub fn request_close(&self) {
                self.scope.request_close();
            }
            pub async fn close(&self) -> FeedCloseReport {
                self.scope.close().await
            }
            pub async fn retry_close(&self) -> FeedCloseReport {
                self.scope.close().await
            }
        }
    };
}
lifecycle!(
    StudioPerformanceSummariesRead,
    PerformanceSummariesReadHeader,
    StatisticsReadMaterial,
    summaries_header
);
lifecycle!(
    StudioPerformanceHistoryRead,
    PerformanceHistoryReadHeader,
    StatisticsReadMaterial,
    history_header
);
lifecycle!(
    StudioSessionCostsRead,
    SessionCostsReadHeader,
    StatisticsReadMaterial,
    costs_header
);
lifecycle!(
    StudioPerformanceSummaryIdentityRead,
    PerformanceSummaryIdentityRead,
    StatisticsIdentityReadMaterial,
    summary
);
lifecycle!(
    StudioPerformanceEffortIdentityRead,
    PerformanceEffortIdentityRead,
    StatisticsIdentityReadMaterial,
    effort
);
lifecycle!(
    StudioPerformanceSampleIdentityRead,
    PerformanceSampleIdentityRead,
    StatisticsIdentityReadMaterial,
    sample
);
impl StudioPerformanceSummariesRead {
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PerformanceSummariesEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.summaries_entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<PerformanceSummariesEntityRead>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.summary_entity(reference))
    }
    pub fn lookup_summary(
        &self,
        account_id: String,
        model_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.lookup_summary(&account_id, &model_id))
    }
    pub fn summaries(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PerformanceSummaryReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.summaries(list_id, offset, limit))
    }
    pub fn effort_breakdowns(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PerformanceEffortReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.effort_breakdowns(list_id, offset, limit))
    }
}
impl StudioPerformanceHistoryRead {
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PerformanceHistoryEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.history_entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<PerformanceHistoryEntityRead>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.sample_entity(reference))
    }
    pub fn samples(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PerformanceSampleReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.samples(list_id, offset, limit))
    }
}
impl StudioSessionCostsRead {
    pub fn purposes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PurposeCostReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.purposes(list_id, offset, limit))
    }
    pub fn amounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<RuntimeCostReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.amounts(list_id, offset, limit))
    }
}
