use super::super::StudioRuntime;
use super::material::ReadMaterial;
use super::scope::LspScope;
use super::*;
use anyhow::Result;
use pl_protocol::products::identity::ProductReadVersion;
use std::future::Future;
pub struct StudioLspRead {
    scope: LspScope<ReadMaterial>,
}
impl StudioRuntime {
    /// Pins only an actually exposed, original origin/ref; never reconstructs expired material.
    pub fn open_lsp_read(
        &self,
        reference: LspReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioLspRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.lsp_source.clone();
            let material = source.pin(&origin, reference)?;
            let scope = LspScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ReadMaterial::new(material),
            )?;
            Ok(StudioLspRead { scope })
        })
    }
}
impl StudioLspRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(&self) -> impl Future<Output = Result<LspReadHeader>> + Send + 'static + use<> {
        self.scope.query(ReadMaterial::header)
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
    ) -> impl Future<Output = Result<LspEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<LspEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.entity(reference))
    }
    pub fn lookup_server(
        &self,
        key: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |material| material.lookup(&key))
    }
    pub fn servers(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<LspServerReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.members(list_id, offset, limit))
    }
    pub fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<TextReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.strings_page(list_id, offset, limit))
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
