use super::super::StudioRuntime;
use super::{
    material::PersistenceMaterial, queue_material::QueueMaterial, scope::PersistenceReadScope,
};
use anyhow::Result;
use pl_protocol::products::{
    identity::*,
    read::persistence::*,
    references::{PersistenceQueueReadRef, PersistenceReadRef},
};
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioPersistenceRead {
    scope: PersistenceReadScope<PersistenceMaterial>,
}
pub struct StudioPersistenceQueueRead {
    scope: PersistenceReadScope<QueueMaterial>,
}
impl StudioRuntime {
    pub fn open_persistence_read(
        &self,
        reference: PersistenceReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPersistenceRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let snapshot = runtime.persistence_source.pin(&origin, reference)?;
            Ok(StudioPersistenceRead {
                scope: PersistenceReadScope::open_for_resource(
                    &runtime,
                    origin,
                    ProductReadVersion::Value {
                        entry: reference.entry,
                        revision: reference.revision,
                    },
                    ProductResource::Persistence,
                    PersistenceMaterial::new(snapshot),
                )?,
            })
        })
    }
    pub fn open_persistence_queue_read(
        &self,
        reference: PersistenceQueueReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioPersistenceQueueRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let snapshot = runtime.persistence_queue_source.pin(&origin, reference)?;
            Ok(StudioPersistenceQueueRead {
                scope: PersistenceReadScope::open_for_resource(
                    &runtime,
                    origin,
                    ProductReadVersion::Value {
                        entry: reference.entry,
                        revision: reference.revision,
                    },
                    ProductResource::PersistenceQueue,
                    QueueMaterial::new(snapshot),
                )?,
            })
        })
    }
}
impl StudioPersistenceRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<PersistenceReadHeader>> + Send + 'static + use<> {
        self.scope.query(PersistenceMaterial::header)
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |m| m.text(field_id, offset, max_bytes))
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
impl StudioPersistenceQueueRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<PersistenceQueueReadHeader>> + Send + 'static + use<> {
        self.scope.query(QueueMaterial::header)
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<PersistenceQueueEntryPage>> + Send + 'static + use<> {
        self.scope.query(move |m| m.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<PersistenceQueueEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |m| m.entity(reference))
    }
    pub fn lookup_thread(
        &self,
        id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |m| m.lookup(&id))
    }
    pub fn threads(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ThreadPersistenceReadPage>> + Send + 'static + use<> {
        self.scope.query(move |m| m.threads(list_id, offset, limit))
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |m| m.text(field_id, offset, max_bytes))
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
