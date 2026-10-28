//! Opaque Recovery scopes and explicit typed DTO mappings.
use super::super::identity::*;
use super::super::references::{BridgeRecoveryReadRef, BridgeRecoveryReadTarget};
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::primitives::BridgeTextReadPage;
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::BridgeWorktreeOwner;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::recovery as protocol;
use pl_studio_runtime::recovery::{StudioRecoveryRead, StudioRecoverySourceStatusRead};
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryReadHeader {
    pub issues: BridgeTypedListRef,
}

impl From<protocol::RecoveryReadHeader> for BridgeRecoveryReadHeader {
    fn from(value: protocol::RecoveryReadHeader) -> Self {
        Self {
            issues: value.issues.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorktreeRecoveryPreviewRead {
    pub inspection: crate::api::studio::types::BridgeWorktreeInspection,
    pub owner_kind: BridgeWorktreeOwner,
    pub owner_thread_id: BridgeReadText,
    pub lease_revision: u64,
    pub state: BridgeReadText,
    pub repository_root: BridgeReadText,
    pub path: BridgeReadText,
    pub branch: BridgeReadText,
    pub base_commit: BridgeReadText,
    pub head_commit: Option<BridgeReadText>,
    pub dirty: Option<bool>,
    pub changed_files: Option<BridgeTypedListRef>,
}

impl From<protocol::WorktreeRecoveryPreviewRead> for BridgeWorktreeRecoveryPreviewRead {
    fn from(value: protocol::WorktreeRecoveryPreviewRead) -> Self {
        Self {
            inspection: match value.inspection {
                protocol::WorktreeInspection::Available => {
                    crate::api::studio::types::BridgeWorktreeInspection::Available
                }
                protocol::WorktreeInspection::Missing => {
                    crate::api::studio::types::BridgeWorktreeInspection::Missing
                }
                protocol::WorktreeInspection::IdentityMismatch => {
                    crate::api::studio::types::BridgeWorktreeInspection::IdentityMismatch
                }
                protocol::WorktreeInspection::Unavailable => {
                    crate::api::studio::types::BridgeWorktreeInspection::Unavailable
                }
            },
            owner_kind: value.owner_kind.into(),
            owner_thread_id: value.owner_thread_id.into(),
            lease_revision: value.lease_revision,
            state: value.state.into(),
            repository_root: value.repository_root.into(),
            path: value.path.into(),
            branch: value.branch.into(),
            base_commit: value.base_commit.into(),
            head_commit: value.head_commit.map(Into::into),
            dirty: value.dirty,
            changed_files: value.changed_files.map(Into::into),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryIssueRead {
    pub id: BridgeReadText,
    pub scope: BridgeRecoveryScope,
    pub category: BridgeRecoveryCategory,
    pub available_actions: Vec<BridgeRecoveryAction>,
    pub project_id: Option<BridgeReadText>,
    pub thread_id: Option<BridgeReadText>,
    pub message: BridgeReadText,
    pub worktree: Option<BridgeWorktreeRecoveryPreviewRead>,
}

impl From<protocol::RecoveryIssueRead> for BridgeRecoveryIssueRead {
    fn from(value: protocol::RecoveryIssueRead) -> Self {
        Self {
            id: value.id.into(),
            scope: value.scope.into(),
            category: value.category.into(),
            available_actions: value
                .available_actions
                .into_iter()
                .map(Into::into)
                .collect(),
            project_id: value.project_id.map(Into::into),
            thread_id: value.thread_id.map(Into::into),
            message: value.message.into(),
            worktree: value.worktree.map(Into::into),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeRecoveryIssueRead,
}

impl From<protocol::RecoveryEntityRead> for BridgeRecoveryEntityRead {
    fn from(value: protocol::RecoveryEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}

impl From<protocol::RecoveryEntryPage> for BridgeRecoveryEntryPage {
    fn from(value: protocol::RecoveryEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryIssueReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeRecoveryIssueRead>,
    pub next_offset: Option<u64>,
}

impl From<protocol::RecoveryIssueReadPage> for BridgeRecoveryIssueReadPage {
    fn from(value: protocol::RecoveryIssueReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRecoveryScope {
    Application,
    Project,
    Thread,
}

impl From<protocol::RecoveryScope> for BridgeRecoveryScope {
    fn from(value: protocol::RecoveryScope) -> Self {
        match value {
            protocol::RecoveryScope::Application => Self::Application,
            protocol::RecoveryScope::Project => Self::Project,
            protocol::RecoveryScope::Thread => Self::Thread,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRecoveryCategory {
    ProcessLease,
    ToolCatalog,
    Repository,
    Storage,
}

impl From<protocol::RecoveryCategory> for BridgeRecoveryCategory {
    fn from(value: protocol::RecoveryCategory) -> Self {
        match value {
            protocol::RecoveryCategory::ProcessLease => Self::ProcessLease,
            protocol::RecoveryCategory::ToolCatalog => Self::ToolCatalog,
            protocol::RecoveryCategory::Repository => Self::Repository,
            protocol::RecoveryCategory::Storage => Self::Storage,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRecoveryAction {
    None,
    Retry,
    CleanupThread,
    RemoveProject,
    CleanupWorktree,
}

impl From<protocol::RecoveryAction> for BridgeRecoveryAction {
    fn from(value: protocol::RecoveryAction) -> Self {
        match value {
            protocol::RecoveryAction::None => Self::None,
            protocol::RecoveryAction::Retry => Self::Retry,
            protocol::RecoveryAction::CleanupThread => Self::CleanupThread,
            protocol::RecoveryAction::RemoveProject => Self::RemoveProject,
            protocol::RecoveryAction::CleanupWorktree => Self::CleanupWorktree,
        }
    }
}

impl From<protocol::WorktreeOwner> for BridgeWorktreeOwner {
    fn from(value: protocol::WorktreeOwner) -> Self {
        match value {
            protocol::WorktreeOwner::Session => Self::Session,
            protocol::WorktreeOwner::Child => Self::Child,
        }
    }
}
impl ModelsRead for StudioRecoveryRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        StudioRecoveryRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        StudioRecoveryRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioRecoveryRead::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        StudioRecoveryRead::close(self)
    }
}
impl ModelsRead for StudioRecoverySourceStatusRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        StudioRecoverySourceStatusRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        StudioRecoverySourceStatusRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioRecoverySourceStatusRead::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        StudioRecoverySourceStatusRead::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeRecoveryReadConnection {
    read: ModelsReadHandle<StudioRecoveryRead>,
}
impl BridgeRecoveryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeRecoveryReadHeader, BridgeError> {
        let query = self.read.query(move |source| source.header())?;
        Ok(query.await?.into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeRecoveryEntryPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entries(offset, limit))?;
        Ok(query.await?.into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeRecoveryEntityRead, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entity(reference.into()))?;
        Ok(query.await?.into())
    }
    pub async fn lookup_issue(
        &self,
        id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        let query = self.read.query(move |source| source.lookup_issue(id))?;
        Ok(query.await?.map(Into::into))
    }
    pub async fn issues(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeRecoveryIssueReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.issues(list_id, offset, limit))?;
        Ok(query.await?.into())
    }
    pub async fn changed_files(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.changed_files(list_id, offset, limit))?;
        Ok(query.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        let query = self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?;
        Ok(query.await?.into())
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
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeRecoverySourceStatusReadConnection {
    read: ModelsReadHandle<StudioRecoverySourceStatusRead>,
}
impl BridgeRecoverySourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        let query = self.read.query(move |source| source.header())?;
        Ok(query.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        let query = self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?;
        Ok(query.await?.into())
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
pub async fn open_recovery_read(
    reference: BridgeRecoveryReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeRecoveryReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeRecoveryReadConnection {
        read: open_read(move |runtime| runtime.open_recovery_read(reference, origin)).await?,
    })
}
pub async fn open_recovery_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeRecoverySourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeRecoverySourceStatusReadConnection {
        read: open_read(move |runtime| runtime.open_recovery_source_status_read(reference, origin))
            .await?,
    })
}
pub async fn retry_recovery() -> Result<BridgeRecoveryReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::active_bridge().await?;
    let result = bridge.studio.retry_recovery().await?;
    Ok(result.target.into())
}
pub async fn cleanup_worktree(
    owner_kind: BridgeWorktreeOwner,
    owner_thread_id: String,
    expected_lease_revision: u64,
) -> Result<(), BridgeError> {
    let owner = match owner_kind {
        BridgeWorktreeOwner::Session => pl_studio_runtime::StudioRecoveryWorktreeOwner::Session,
        BridgeWorktreeOwner::Child => pl_studio_runtime::StudioRecoveryWorktreeOwner::Child,
    };
    crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .cleanup_preserved_worktree(owner, &owner_thread_id, expected_lease_revision)
        .await?;
    Ok(())
}
