use super::super::StudioRuntime;
use super::material::ReadMaterial;
use super::scope::McpScope;
use super::*;
use anyhow::Result;
use pl_protocol::products::identity::ProductReadVersion;
use std::future::Future;
pub struct StudioMcpRead {
    scope: McpScope<ReadMaterial>,
}
impl StudioRuntime {
    /// Pins only an actually exposed, original origin/ref; never reconstructs expired material.
    pub fn open_mcp_read(
        &self,
        reference: McpReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioMcpRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.mcp_source.clone();
            let material = source.pin(&origin, reference)?;
            let scope = McpScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ReadMaterial::new(material),
            )?;
            Ok(StudioMcpRead { scope })
        })
    }
}
impl StudioMcpRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(&self) -> impl Future<Output = Result<McpReadHeader>> + Send + 'static + use<> {
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
    ) -> impl Future<Output = Result<McpEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<McpEntityRead>> + Send + 'static + use<> {
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
    ) -> impl Future<Output = Result<McpServerReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.members(list_id, offset, limit))
    }
    pub fn active_servers(
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
