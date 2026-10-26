use super::super::super::StudioRuntime;
use super::super::scope::ConfigurationScope;
use super::material::ProfilesReadMaterial;
use anyhow::Result;
use pl_protocol::products::identity::{
    ProductEntityRef, ProductReadOrigin, ProductReadScopeIdentity, ProductReadVersion,
    ProductResource,
};
use pl_protocol::products::read::agent_profiles::*;
use pl_protocol::products::references::AgentProfilesReadRef;
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::future::Future;

/// One real AgentProfiles scope, sharing the existing 8-product-scope and 64-read-call owners.
pub struct StudioAgentProfilesRead {
    scope: ConfigurationScope<ProfilesReadMaterial>,
}
impl StudioRuntime {
    pub fn open_agent_profiles_read(
        &self,
        reference: AgentProfilesReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioAgentProfilesRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.profiles_source.pin(&origin, reference)?;
            let scope = ConfigurationScope::open_for_resource(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                ProductResource::AgentProfiles,
                ProfilesReadMaterial::new(material),
            )?;
            Ok(StudioAgentProfilesRead { scope })
        })
    }
}
impl StudioAgentProfilesRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<AgentProfilesReadHeader>> + Send + 'static + use<> {
        self.scope.query(ProfilesReadMaterial::header)
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
    ) -> impl Future<Output = Result<AgentProfilesEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<AgentProfilesEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.entity(reference))
    }
    pub fn lookup_profile(
        &self,
        profile_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.lookup_profile(&profile_id))
    }
    pub fn profiles(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AgentProfileReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.profiles(list_id, offset, limit))
    }
    pub fn diagnostics(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ProfileDiagnosticReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.diagnostics(list_id, offset, limit))
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
