use super::super::StudioRuntime;
use super::{material::RecoveryMaterial, scope::RecoveryReadScope};
use anyhow::Result;
use pl_protocol::products::{
    identity::*,
    read::{primitives::TextReadPage, recovery::*},
    references::RecoveryReadRef,
};
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

pub struct StudioRecoveryRead {
    scope: RecoveryReadScope<RecoveryMaterial>,
}
impl StudioRuntime {
    pub fn open_recovery_read(
        &self,
        reference: RecoveryReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioRecoveryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let snapshot =
                runtime
                    .recovery_source
                    .pin(&origin, reference.entry, reference.revision, false)?;
            Ok(StudioRecoveryRead {
                scope: RecoveryReadScope::open(
                    &runtime,
                    origin,
                    ProductReadVersion::Value {
                        entry: reference.entry,
                        revision: reference.revision,
                    },
                    RecoveryMaterial::new(snapshot),
                )?,
            })
        })
    }
}
impl StudioRecoveryRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<RecoveryReadHeader>> + Send + 'static + use<> {
        self.scope.query(RecoveryMaterial::header)
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<RecoveryEntryPage>> + Send + 'static + use<> {
        self.scope.query(move |m| m.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<RecoveryEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |m| m.entity(reference))
    }
    pub fn lookup_issue(
        &self,
        id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |m| m.lookup(&id))
    }
    pub fn issues(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<RecoveryIssueReadPage>> + Send + 'static + use<> {
        self.scope.query(move |m| m.issues(list_id, offset, limit))
    }
    pub fn changed_files(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<TextReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |m| m.changed_files(list_id, offset, limit))
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
