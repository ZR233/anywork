use pl_protocol::products::read::workspace as protocol;
use pl_studio_runtime::workspace::StudioThreadDirectoryRead;

use super::super::identity::{
    BridgeProductCollectionRef, BridgeProductEntityRef, BridgeProductReadOrigin,
    BridgeProductReadScopeIdentity,
};
use super::super::references::BridgeThreadDirectoryReadRef;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{
    BridgeDelegationMode, BridgeDelegationPreference, BridgeError, BridgeFeedCloseReport,
    BridgeThreadStatus,
};

impl ModelsRead for StudioThreadDirectoryRead {
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
pub struct BridgeThreadDirectoryReadConnection {
    read: ModelsReadHandle<StudioThreadDirectoryRead>,
}

pub async fn open_thread_directory_read(
    reference: BridgeThreadDirectoryReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeThreadDirectoryReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeThreadDirectoryReadConnection {
        read: open_read(move |runtime| runtime.open_thread_directory_read(reference, origin))
            .await?,
    })
}
impl BridgeThreadDirectoryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeThreadDirectoryReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioThreadDirectoryRead::header)?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        cursor: Option<String>,
        limit: u32,
    ) -> Result<BridgeThreadDirectoryEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(cursor, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeThreadDirectoryEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_thread(
        &self,
        thread_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.lookup_thread(thread_id))?
            .await?
            .map(Into::into))
    }
    pub async fn threads(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeWorkspaceThreadRecordReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.threads(list_id, offset, limit))?
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
pub enum BridgeThreadDirectoryScope {
    Query {
        query: BridgeThreadDirectoryQuery,
        include_pinned: bool,
    },
    Thread {
        thread_id: String,
    },
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryQuery {
    pub project_id: Option<String>,
    pub search: Option<String>,
    pub archived: bool,
    pub filter: BridgeThreadDirectoryFilter,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadDirectoryFilter {
    All,
    Running,
    Attention,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadWorkspaceMode {
    Local,
    Worktree,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryReadHeader {
    pub threads: BridgeTypedListRef,
    pub next_cursor: Option<BridgeReadText>,
    pub has_more: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeFrozenModelSelectionRead {
    pub account_id: BridgeReadText,
    pub model_id: BridgeReadText,
    pub effort: Option<BridgeReadText>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkspaceThreadRecordRead {
    pub id: BridgeReadText,
    pub project_id: BridgeReadText,
    pub title: BridgeReadText,
    pub mode: BridgeReadText,
    pub workspace_mode: BridgeThreadWorkspaceMode,
    pub delegation_mode: BridgeDelegationMode,
    pub delegation_preference: BridgeDelegationPreference,
    pub frozen_model: Option<BridgeFrozenModelSelectionRead>,
    pub workspace_path: BridgeReadText,
    pub root_thread_id: BridgeReadText,
    pub parent_thread_id: Option<BridgeReadText>,
    pub role: BridgeReadText,
    pub agent_path: BridgeReadText,
    pub status: BridgeThreadStatus,
    pub created_at: i64,
    pub updated_at: i64,
    pub last_user_message_at: Option<i64>,
    pub archived: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeWorkspaceThreadRecordRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_cursor: Option<BridgeReadText>,
    pub has_more: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWorkspaceThreadRecordReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeWorkspaceThreadRecordRead>,
    pub next_offset: Option<u64>,
}

impl From<BridgeThreadDirectoryScope> for protocol::ThreadDirectoryScope {
    fn from(value: BridgeThreadDirectoryScope) -> Self {
        match value {
            BridgeThreadDirectoryScope::Query {
                query,
                include_pinned,
            } => Self::Query {
                query: query.into(),
                include_pinned,
            },
            BridgeThreadDirectoryScope::Thread { thread_id } => Self::Thread { thread_id },
        }
    }
}
impl From<BridgeThreadDirectoryQuery> for pl_protocol::studio::ThreadDirectoryQuery {
    fn from(value: BridgeThreadDirectoryQuery) -> Self {
        Self {
            project_id: value.project_id,
            search: value.search,
            archived: value.archived,
            filter: match value.filter {
                BridgeThreadDirectoryFilter::All => pl_protocol::studio::ThreadDirectoryFilter::All,
                BridgeThreadDirectoryFilter::Running => {
                    pl_protocol::studio::ThreadDirectoryFilter::Running
                }
                BridgeThreadDirectoryFilter::Attention => {
                    pl_protocol::studio::ThreadDirectoryFilter::Attention
                }
            },
        }
    }
}
impl From<pl_protocol::ThreadWorkspaceMode> for BridgeThreadWorkspaceMode {
    fn from(value: pl_protocol::ThreadWorkspaceMode) -> Self {
        match value {
            pl_protocol::ThreadWorkspaceMode::Local => Self::Local,
            pl_protocol::ThreadWorkspaceMode::Worktree => Self::Worktree,
        }
    }
}
impl From<protocol::ThreadDirectoryReadHeader> for BridgeThreadDirectoryReadHeader {
    fn from(value: protocol::ThreadDirectoryReadHeader) -> Self {
        Self {
            threads: value.threads.into(),
            next_cursor: value.next_cursor.map(Into::into),
            has_more: value.has_more,
        }
    }
}
impl From<protocol::FrozenModelSelectionRead> for BridgeFrozenModelSelectionRead {
    fn from(value: protocol::FrozenModelSelectionRead) -> Self {
        Self {
            account_id: value.account_id.into(),
            model_id: value.model_id.into(),
            effort: value.effort.map(Into::into),
        }
    }
}
impl From<protocol::WorkspaceThreadRecordRead> for BridgeWorkspaceThreadRecordRead {
    fn from(value: protocol::WorkspaceThreadRecordRead) -> Self {
        Self {
            id: value.id.into(),
            project_id: value.project_id.into(),
            title: value.title.into(),
            mode: value.mode.into(),
            workspace_mode: value.workspace_mode.into(),
            delegation_mode: value.delegation_mode.into(),
            delegation_preference: value.delegation_preference.into(),
            frozen_model: value.frozen_model.map(Into::into),
            workspace_path: value.workspace_path.into(),
            root_thread_id: value.root_thread_id.into(),
            parent_thread_id: value.parent_thread_id.map(Into::into),
            role: value.role.into(),
            agent_path: value.agent_path.into(),
            status: value.status.into(),
            created_at: value.created_at,
            updated_at: value.updated_at,
            last_user_message_at: value.last_user_message_at,
            archived: value.archived,
        }
    }
}
impl From<protocol::ThreadDirectoryEntityRead> for BridgeThreadDirectoryEntityRead {
    fn from(value: protocol::ThreadDirectoryEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}
impl From<protocol::ThreadDirectoryEntryPage> for BridgeThreadDirectoryEntryPage {
    fn from(value: protocol::ThreadDirectoryEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            items: value.items.into_iter().map(Into::into).collect(),
            next_cursor: value.next_cursor.map(Into::into),
            has_more: value.has_more,
        }
    }
}
impl From<protocol::WorkspaceThreadRecordReadPage> for BridgeWorkspaceThreadRecordReadPage {
    fn from(value: protocol::WorkspaceThreadRecordReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
