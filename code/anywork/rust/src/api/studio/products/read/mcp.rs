//! Opaque Mcp scopes share the original runtime scope/call budgets and bridge owner.
use super::super::identity::{
    BridgeProductCollectionRef, BridgeProductEntityRef, BridgeProductReadOrigin,
    BridgeProductReadScopeIdentity, BridgeProductSourceStatusRef,
};
use super::super::references::{BridgeMcpReadRef, BridgeMcpReadTarget};
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::super::source::BridgeSourceStateErrorRead;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::primitives::BridgeTextReadPage;
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::mcp as protocol;
use pl_studio_runtime::mcp::{StudioMcpRead, StudioMcpSourceStatusRead};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpHealthRead {
    pub mcp_servers: BridgeTypedListRef,
    pub active_mcp_servers: BridgeTypedListRef,
}
impl From<protocol::McpHealthRead> for BridgeMcpHealthRead {
    fn from(value: protocol::McpHealthRead) -> Self {
        Self {
            mcp_servers: value.mcp_servers.into(),
            active_mcp_servers: value.active_mcp_servers.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpReadHeader {
    pub desired_config_fingerprint: BridgeReadText,
    pub applied_config_fingerprint: BridgeReadText,
    pub health: BridgeMcpHealthRead,
}
impl From<protocol::McpReadHeader> for BridgeMcpReadHeader {
    fn from(value: protocol::McpReadHeader) -> Self {
        Self {
            desired_config_fingerprint: value.desired_config_fingerprint.into(),
            applied_config_fingerprint: value.applied_config_fingerprint.into(),
            health: value.health.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeMcpServerStateRead {
    Disabled {
        message: BridgeReadText,
    },
    MissingCredential {
        message: BridgeReadText,
    },
    Checking {
        message: BridgeReadText,
    },
    Available {
        checked_at: i64,
        tool_count: u64,
    },
    Unavailable {
        checked_at: i64,
        error: BridgeSourceStateErrorRead,
    },
}
impl From<protocol::McpServerStateRead> for BridgeMcpServerStateRead {
    fn from(value: protocol::McpServerStateRead) -> Self {
        match value {
            protocol::McpServerStateRead::Disabled { message } => Self::Disabled {
                message: message.into(),
            },
            protocol::McpServerStateRead::MissingCredential { message } => {
                Self::MissingCredential {
                    message: message.into(),
                }
            }
            protocol::McpServerStateRead::Checking { message } => Self::Checking {
                message: message.into(),
            },
            protocol::McpServerStateRead::Available {
                checked_at,
                tool_count,
            } => Self::Available {
                checked_at,
                tool_count,
            },
            protocol::McpServerStateRead::Unavailable { checked_at, error } => Self::Unavailable {
                checked_at,
                error: error.into(),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpServerRead {
    pub id: BridgeReadText,
    pub transport: BridgeReadText,
    pub endpoint: BridgeReadText,
    pub source_kind: BridgeReadText,
    pub mutation_policy: BridgeReadText,
    pub state: BridgeMcpServerStateRead,
}
impl From<protocol::McpServerRead> for BridgeMcpServerRead {
    fn from(value: protocol::McpServerRead) -> Self {
        Self {
            id: value.id.into(),
            transport: value.transport.into(),
            endpoint: value.endpoint.into(),
            source_kind: value.source_kind.into(),
            mutation_policy: value.mutation_policy.into(),
            state: value.state.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeMcpServerRead,
}
impl From<protocol::McpEntityRead> for BridgeMcpEntityRead {
    fn from(value: protocol::McpEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
impl From<protocol::McpEntryPage> for BridgeMcpEntryPage {
    fn from(value: protocol::McpEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpServerReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeMcpServerRead>,
    pub next_offset: Option<u64>,
}
impl From<protocol::McpServerReadPage> for BridgeMcpServerReadPage {
    fn from(value: protocol::McpServerReadPage) -> Self {
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
native_read!(StudioMcpRead);
native_read!(StudioMcpSourceStatusRead);
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeMcpReadConnection {
    read: ModelsReadHandle<StudioMcpRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeMcpSourceStatusReadConnection {
    read: ModelsReadHandle<StudioMcpSourceStatusRead>,
}
pub async fn open_mcp_read(
    reference: BridgeMcpReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeMcpReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeMcpReadConnection {
        read: open_read(move |runtime| runtime.open_mcp_read(reference, origin)).await?,
    })
}
pub async fn open_mcp_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeMcpSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeMcpSourceStatusReadConnection {
        read: open_read(move |runtime| runtime.open_mcp_source_status_read(reference, origin))
            .await?,
    })
}
impl BridgeMcpReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeMcpReadHeader, BridgeError> {
        Ok(self.read.query(StudioMcpRead::header)?.await?.into())
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
    ) -> Result<BridgeMcpEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeMcpEntityRead, BridgeError> {
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
    ) -> Result<BridgeMcpServerReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.servers(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn active_servers(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.active_servers(list_id, offset, limit))?
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
impl BridgeMcpSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioMcpSourceStatusRead::header)?
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
pub async fn mcp_reset_server(server_id: String) -> Result<BridgeMcpReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge.studio.mcp_reset_server(server_id).await?.into())
}
pub async fn mcp_reset_all() -> Result<BridgeMcpReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge.studio.mcp_reset_all().await?.into())
}
