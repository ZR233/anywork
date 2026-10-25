use super::super::StudioRuntime;
use super::{material::UsageReadMaterial, scope::UsageScope};
use anyhow::Result;
use pl_protocol::products::identity::{
    ProductEntityRef, ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion,
};
use pl_protocol::products::read::account_usage::*;
use pl_protocol::products::references::AccountUsageReadRef;
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioAccountUsageRead {
    scope: UsageScope<UsageReadMaterial>,
}
impl StudioRuntime {
    pub fn open_account_usage_read(
        &self,
        reference: AccountUsageReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioAccountUsageRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.usage_source.pin(&origin, reference)?;
            let scope = UsageScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                UsageReadMaterial::new(material),
            )?;
            Ok(StudioAccountUsageRead { scope })
        })
    }
}
impl StudioAccountUsageRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<AccountUsageReadHeader>> + Send + 'static + use<> {
        self.scope.query(UsageReadMaterial::header)
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
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AccountUsageEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<AccountUsageEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.entity(reference))
    }
    pub fn lookup_account(
        &self,
        account: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |material| material.lookup(&account))
    }
    pub fn usages(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AccountUsageReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.usages(list_id, offset, limit))
    }
    pub fn balances(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<BalanceReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.balances(list_id, offset, limit))
    }
    pub fn quota_limits(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<QuotaLimitReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.quota_limits(list_id, offset, limit))
    }
    pub fn quota_details(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<QuotaDetailReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.quota_details(list_id, offset, limit))
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
