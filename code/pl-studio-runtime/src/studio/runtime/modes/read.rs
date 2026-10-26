use super::super::StudioRuntime;
use super::{material::ModesReadMaterial, scope::ModesScope};
use anyhow::Result;
use pl_protocol::ThreadModeId;
use pl_protocol::products::identity::{
    ProductEntityRef, ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion,
};
use pl_protocol::products::read::modes::*;
use pl_protocol::products::references::ModeCatalogReadRef;
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioModeCatalogRead {
    scope: ModesScope<ModesReadMaterial>,
}
impl StudioRuntime {
    pub fn open_mode_catalog_read(
        &self,
        reference: ModeCatalogReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioModeCatalogRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.modes_source.pin(&origin, reference)?;
            let scope = ModesScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ModesReadMaterial::new(material),
            )?;
            Ok(StudioModeCatalogRead { scope })
        })
    }
}
impl StudioModeCatalogRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ModeCatalogReadHeader>> + Send + 'static + use<> {
        self.scope.query(ModesReadMaterial::header)
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
    ) -> impl Future<Output = Result<ModeCatalogEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<ModeCatalogEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.entity(reference))
    }
    pub fn lookup_mode(
        &self,
        mode: ThreadModeId,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |material| material.lookup(mode))
    }
    pub fn modes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ThreadModeDescriptorReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.modes(list_id, offset, limit))
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
