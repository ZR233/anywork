//! Opaque Workspace reads use the original native pin and the shared bridge close owner.
use pl_protocol::products::read::workspace as protocol;
use pl_studio_runtime::workspace::{StudioProjectDirectoryRead, StudioWorkspaceSourceStatusRead};

use super::super::identity::{
    BridgeProductCollectionRef, BridgeProductEntityRef, BridgeProductReadOrigin,
    BridgeProductReadScopeIdentity, BridgeProductSourceStatusRef,
};
use super::super::references::BridgeProjectDirectoryReadRef;
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};

impl ModelsRead for StudioProjectDirectoryRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        Self::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        Self::ensure_open(self)
    }
    fn request_close(&self) {
        Self::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        Self::close(self)
    }
}
impl ModelsRead for StudioWorkspaceSourceStatusRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        Self::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        Self::ensure_open(self)
    }
    fn request_close(&self) {
        Self::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        Self::close(self)
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeProjectDirectoryReadConnection {
    read: ModelsReadHandle<StudioProjectDirectoryRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeWorkspaceSourceStatusReadConnection {
    read: ModelsReadHandle<StudioWorkspaceSourceStatusRead>,
}

pub async fn open_project_directory_read(
    reference: BridgeProjectDirectoryReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeProjectDirectoryReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeProjectDirectoryReadConnection {
        read: open_read(move |runtime| runtime.open_project_directory_read(reference, origin))
            .await?,
    })
}
pub async fn open_workspace_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeWorkspaceSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeWorkspaceSourceStatusReadConnection {
        read: open_read(move |runtime| {
            runtime.open_workspace_source_status_read(reference, origin)
        })
        .await?,
    })
}

impl BridgeProjectDirectoryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProjectDirectoryReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioProjectDirectoryRead::header)?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeProjectDirectoryEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeProjectDirectoryEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_project(
        &self,
        project_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_project(project_id))?
            .await?
            .map(Into::into))
    }
    pub async fn projects(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeProjectRecordReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.projects(list_id, offset, limit))?
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
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}
impl BridgeWorkspaceSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioWorkspaceSourceStatusRead::header)?
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
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryReadHeader {
    pub projects: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectRecordRead {
    pub id: BridgeReadText,
    pub name: BridgeReadText,
    pub path: BridgeReadText,
    pub ssh_alias: Option<BridgeReadText>,
    pub updated_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeProjectRecordRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectRecordReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeProjectRecordRead>,
    pub next_offset: Option<u64>,
}

impl From<protocol::ProjectDirectoryReadHeader> for BridgeProjectDirectoryReadHeader {
    fn from(value: protocol::ProjectDirectoryReadHeader) -> Self {
        Self {
            projects: value.projects.into(),
        }
    }
}
impl From<protocol::ProjectRecordRead> for BridgeProjectRecordRead {
    fn from(value: protocol::ProjectRecordRead) -> Self {
        Self {
            id: value.id.into(),
            name: value.name.into(),
            path: value.path.into(),
            ssh_alias: value.ssh_alias.map(Into::into),
            updated_at: value.updated_at,
        }
    }
}
impl From<protocol::ProjectDirectoryEntityRead> for BridgeProjectDirectoryEntityRead {
    fn from(value: protocol::ProjectDirectoryEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}
impl From<protocol::ProjectDirectoryEntryPage> for BridgeProjectDirectoryEntryPage {
    fn from(value: protocol::ProjectDirectoryEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl From<protocol::ProjectRecordReadPage> for BridgeProjectRecordReadPage {
    fn from(value: protocol::ProjectRecordReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
