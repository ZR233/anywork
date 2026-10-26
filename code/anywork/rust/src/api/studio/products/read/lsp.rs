//! Opaque Lsp scopes share the original runtime scope/call budgets and bridge owner.
use super::super::identity::{
    BridgeProductCollectionRef, BridgeProductEntityRef, BridgeProductReadOrigin,
    BridgeProductReadScopeIdentity, BridgeProductSourceStatusRef,
};
use super::super::references::{BridgeLspReadRef, BridgeLspReadTarget};
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::super::source::BridgeSourceStateErrorRead;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::primitives::BridgeTextReadPage;
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::lsp as protocol;
use pl_studio_runtime::lsp::{StudioLspRead, StudioLspSourceStatusRead};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLspReadHeader {
    pub lsp_servers: BridgeTypedListRef,
    pub active_lsp_servers: BridgeTypedListRef,
}
impl From<protocol::LspReadHeader> for BridgeLspReadHeader {
    fn from(value: protocol::LspReadHeader) -> Self {
        Self {
            lsp_servers: value.lsp_servers.into(),
            active_lsp_servers: value.active_lsp_servers.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLspActivityRead {
    Idle,
    Busy {
        title: Option<BridgeReadText>,
        message: Option<BridgeReadText>,
        percentage: Option<u32>,
    },
    Indexing {
        title: Option<BridgeReadText>,
        message: Option<BridgeReadText>,
        percentage: Option<u32>,
    },
}
impl From<protocol::LspActivityRead> for BridgeLspActivityRead {
    fn from(value: protocol::LspActivityRead) -> Self {
        match value {
            protocol::LspActivityRead::Idle => Self::Idle,
            protocol::LspActivityRead::Busy {
                title,
                message,
                percentage,
            } => Self::Busy {
                title: title.map(Into::into),
                message: message.map(Into::into),
                percentage,
            },
            protocol::LspActivityRead::Indexing {
                title,
                message,
                percentage,
            } => Self::Indexing {
                title: title.map(Into::into),
                message: message.map(Into::into),
                percentage,
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeLspServerStateRead {
    Checking {
        message: BridgeReadText,
    },
    Disabled {
        message: BridgeReadText,
    },
    Unavailable {
        checked_at: i64,
        error: BridgeSourceStateErrorRead,
    },
    Available {
        checked_at: i64,
        diagnostic_count: u64,
        activity: BridgeLspActivityRead,
    },
}
impl From<protocol::LspServerStateRead> for BridgeLspServerStateRead {
    fn from(value: protocol::LspServerStateRead) -> Self {
        match value {
            protocol::LspServerStateRead::Checking { message } => Self::Checking {
                message: message.into(),
            },
            protocol::LspServerStateRead::Disabled { message } => Self::Disabled {
                message: message.into(),
            },
            protocol::LspServerStateRead::Unavailable { checked_at, error } => Self::Unavailable {
                checked_at,
                error: error.into(),
            },
            protocol::LspServerStateRead::Available {
                checked_at,
                diagnostic_count,
                activity,
            } => Self::Available {
                checked_at,
                diagnostic_count,
                activity: activity.into(),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLspServerRead {
    pub id: BridgeReadText,
    pub display_name: BridgeReadText,
    pub extensions: BridgeTypedListRef,
    pub language_ids: BridgeTypedListRef,
    pub state: BridgeLspServerStateRead,
}
impl From<protocol::LspServerRead> for BridgeLspServerRead {
    fn from(value: protocol::LspServerRead) -> Self {
        Self {
            id: value.id.into(),
            display_name: value.display_name.into(),
            extensions: value.extensions.into(),
            language_ids: value.language_ids.into(),
            state: value.state.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLspEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeLspServerRead,
}
impl From<protocol::LspEntityRead> for BridgeLspEntityRead {
    fn from(value: protocol::LspEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLspEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
impl From<protocol::LspEntryPage> for BridgeLspEntryPage {
    fn from(value: protocol::LspEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLspServerReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeLspServerRead>,
    pub next_offset: Option<u64>,
}
impl From<protocol::LspServerReadPage> for BridgeLspServerReadPage {
    fn from(value: protocol::LspServerReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

macro_rules! native_read {
    ($source:ty) => {
        impl ModelsRead for $source {
            fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
                <$source>::identity(self)
            }
            fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
                <$source>::ensure_open(self)
            }
            fn request_close(&self) {
                <$source>::request_close(self);
            }
            fn close(
                &self,
            ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send
            {
                <$source>::close(self)
            }
        }
    };
}
native_read!(StudioLspRead);
native_read!(StudioLspSourceStatusRead);
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeLspReadConnection {
    read: ModelsReadHandle<StudioLspRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeLspSourceStatusReadConnection {
    read: ModelsReadHandle<StudioLspSourceStatusRead>,
}
pub async fn open_lsp_read(
    reference: BridgeLspReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeLspReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeLspReadConnection {
        read: open_read(move |runtime| runtime.open_lsp_read(reference, origin)).await?,
    })
}
pub async fn open_lsp_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeLspSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeLspSourceStatusReadConnection {
        read: open_read(move |runtime| runtime.open_lsp_source_status_read(reference, origin))
            .await?,
    })
}
impl BridgeLspReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeLspReadHeader, BridgeError> {
        Ok(self.read.query(StudioLspRead::header)?.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeLspEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeLspEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_server(
        &self,
        key: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.lookup_server(key))?
            .await?
            .map(Into::into))
    }
    pub async fn servers(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeLspServerReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.servers(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.strings(list_id, offset, limit))?
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
impl BridgeLspSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioLspSourceStatusRead::header)?
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
            .query(move |read| read.text(field_id, offset, max_bytes))?
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
pub async fn lsp_probe(project_id: String) -> Result<BridgeLspReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge.studio.lsp_probe(project_id).await?.into())
}
pub async fn lsp_repair(
    project_id: String,
    server_id: String,
) -> Result<BridgeLspReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge
        .studio
        .lsp_repair(project_id, server_id)
        .await?
        .into())
}
pub async fn lsp_reset_server(
    project_id: String,
    server_id: String,
) -> Result<BridgeLspReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge
        .studio
        .lsp_reset_server(project_id, server_id)
        .await?
        .into())
}
pub async fn lsp_reset_workspace(project_id: String) -> Result<BridgeLspReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge.studio.lsp_reset_workspace(project_id).await?.into())
}
