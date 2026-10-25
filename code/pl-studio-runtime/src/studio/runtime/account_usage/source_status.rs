use super::super::StudioRuntime;
use super::{material::UsageReadMaterial, scope::UsageScope, source::UsageMaterial};
use anyhow::Result;
use pl_protocol::ObservedResource;
use pl_protocol::products::identity::{
    ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion, ProductSourceStatusRef,
};
use pl_protocol::products::source::{ObservedBrief, ObservedHeader, ProductSourceStatusReadHeader};
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioAccountUsageSourceStatusRead {
    scope: UsageScope<UsageReadMaterial>,
}
impl StudioRuntime {
    pub fn open_account_usage_source_status_read(
        &self,
        reference: ProductSourceStatusRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioAccountUsageSourceStatusRead>> + Send + 'static + use<>
    {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.usage_source.pin_status(&origin, reference)?;
            let scope = UsageScope::open(
                &runtime,
                origin,
                ProductReadVersion::SourceStatus {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                UsageReadMaterial::new(material),
            )?;
            Ok(StudioAccountUsageSourceStatusRead { scope })
        })
    }
}
impl StudioAccountUsageSourceStatusRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ProductSourceStatusReadHeader>> + Send + 'static + use<> {
        self.scope.query(UsageReadMaterial::status_header)
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
pub(super) fn observed_header(material: &UsageMaterial) -> ObservedHeader {
    let brief = match &material.value.state {
        ObservedResource::Uninitialized(value) => ObservedBrief::Uninitialized {
            revision: value.revision(),
            updated_at: value.updated_at(),
        },
        ObservedResource::Loading(value) => ObservedBrief::Loading {
            revision: value.revision(),
            started_at: value.started_at(),
        },
        ObservedResource::Ready(value) => ObservedBrief::Ready {
            revision: value.revision(),
            updated_at: value.updated_at(),
            last_checked_at: value.last_checked_at(),
        },
        ObservedResource::Refreshing(value) => ObservedBrief::Refreshing {
            revision: value.revision(),
            started_at: value.started_at(),
            last_checked_at: value.last_checked_at(),
        },
        ObservedResource::Stale(value) => ObservedBrief::Stale {
            revision: value.revision(),
            stale_at: value.stale_at(),
            last_checked_at: value.last_checked_at(),
        },
        ObservedResource::Degraded(value) => ObservedBrief::Degraded {
            revision: value.revision(),
            failed_at: value.failed_at(),
            last_checked_at: value.last_checked_at(),
            retryable: value.error().retryable,
        },
        ObservedResource::Failed(value) => ObservedBrief::Failed {
            revision: value.revision(),
            failed_at: value.failed_at(),
            retryable: value.error().retryable,
        },
        ObservedResource::Stopped(value) => ObservedBrief::Stopped {
            revision: value.revision(),
            stopped_at: value.stopped_at(),
        },
    };
    ObservedHeader {
        brief,
        status: material.status,
    }
}
