use super::super::StudioRuntime;
use super::material::ReadMaterial;
use super::scope::SkillsScope;
use super::*;
use anyhow::Result;
use pl_protocol::products::identity::ProductReadVersion;
use std::future::Future;
pub struct StudioSkillsRead {
    scope: SkillsScope<ReadMaterial>,
}
impl StudioRuntime {
    /// Pins only an actually exposed, original origin/ref; never reconstructs expired material.
    pub fn open_skills_read(
        &self,
        reference: SkillsReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioSkillsRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let source = runtime.skills_source.find(&origin)?;
            let material = source.pin(&origin, reference)?;
            let scope = SkillsScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ReadMaterial::new(material),
            )?;
            Ok(StudioSkillsRead { scope })
        })
    }
}
impl StudioSkillsRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<SkillsReadHeader>> + Send + 'static + use<> {
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
    ) -> impl Future<Output = Result<SkillsEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<SkillsEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.entity(reference))
    }
    pub fn lookup_skill(
        &self,
        key: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |material| material.lookup(&key))
    }
    pub fn skills(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<SkillSummaryReadPage>> + Send + 'static + use<> {
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
