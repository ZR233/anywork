//! Exact Thread Configuration details over the existing ThreadReadGroup/ReadCalls lifecycle.
use anyhow::Result;
use pl_protocol::studio::StudioErrorCode;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use pl_protocol::thread_facets::identity::{
    ConfigurationReadRef, ReadScopeIdentity, ThreadFacetStamp,
};
pub use pl_protocol::thread_facets::read::values::{ConfigurationReadHeader, SkillNamePage};
use std::future::Future;

use super::StudioRuntime;
use super::thread_reads::configuration::{ConfigurationMaterial, ConfigurationSource};
use super::thread_reads::lifetime::ThreadReadScope;

pub struct StudioThreadConfigurationRead {
    scope: ThreadReadScope<ConfigurationMaterial, ConfigurationSource>,
}

impl StudioThreadConfigurationRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ConfigurationReadHeader>> + Send + 'static + use<> {
        self.scope.query(ConfigurationMaterial::header)
    }
    pub fn active_skills(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<SkillNamePage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.active_skills(offset, limit))
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
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}

impl StudioRuntime {
    /// Validate original Thread, facet/incarnation, exposure and version before common admission.
    /// The stable Thread budget includes this scope together with the other four facets' details.
    pub fn open_thread_configuration_read(
        &self,
        thread_id: String,
        reference: ConfigurationReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioThreadConfigurationRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(StudioError::new(
                    StudioErrorCode::Cancelled,
                    "Thread Configuration reads are closed",
                    false,
                )
                .into());
            }
            let lease = runtime
                .thread_observations
                .configuration_sources_at(&thread_id, &origin)?
                .ok_or_else(|| {
                    StudioError::new(
                        StudioErrorCode::Superseded,
                        "The original Thread Configuration incarnation is no longer registered",
                        false,
                    )
                })?;
            let source = lease
                .source()
                .configuration
                .material_at(reference, &origin)?;
            let material = source.clone();
            let scope =
                ThreadReadScope::open(&runtime, lease, reference.revision, source, |identity| {
                    ConfigurationMaterial::new(identity, material)
                })?;
            Ok(StudioThreadConfigurationRead { scope })
        })
    }
}
