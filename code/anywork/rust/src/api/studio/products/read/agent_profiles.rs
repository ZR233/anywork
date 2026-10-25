//! Opaque Profiles scope over the existing registered late-open/query/close owner.
use super::super::identity::{
    BridgeProductEntityRef, BridgeProductReadOrigin, BridgeProductReadScopeIdentity,
};
use super::super::references::BridgeAgentProfilesReadRef;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::profile_values::*;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::identity::ProductReadScopeIdentity;
use pl_protocol::studio::{FeedCloseReport, StudioError};
use pl_studio_runtime::configuration::StudioAgentProfilesRead;
use std::future::Future;

impl ModelsRead for StudioAgentProfilesRead {
    fn identity(&self) -> ProductReadScopeIdentity {
        StudioAgentProfilesRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), StudioError> {
        StudioAgentProfilesRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioAgentProfilesRead::request_close(self);
    }
    fn close(&self) -> impl Future<Output = FeedCloseReport> + Send {
        StudioAgentProfilesRead::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAgentProfilesReadConnection {
    read: ModelsReadHandle<StudioAgentProfilesRead>,
}
pub async fn open_agent_profiles_read(
    reference: BridgeAgentProfilesReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeAgentProfilesReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeAgentProfilesReadConnection {
        read: open_read(move |runtime| runtime.open_agent_profiles_read(reference, origin)).await?,
    })
}
impl BridgeAgentProfilesReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeAgentProfilesReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioAgentProfilesRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAgentProfilesEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeAgentProfilesEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_profile(
        &self,
        profile_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_profile(profile_id))?
            .await?
            .map(Into::into))
    }
    pub async fn profiles(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAgentProfileReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.profiles(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn diagnostics(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeProfileDiagnosticReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.diagnostics(list_id, offset, limit))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
}
