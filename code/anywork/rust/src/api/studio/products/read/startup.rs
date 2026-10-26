//! Independent startup detail scopes over the native-issued narrow Ready reference.
use super::super::identity::*;
use super::super::source::BridgeSourceStateErrorRead;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::startup as protocol;
use pl_studio_runtime::startup::StudioStartupRead;
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRuntimeStartupReadRef {
    pub entry: u64,
    pub revision: u64,
}

impl From<protocol::RuntimeStartupReadRef> for BridgeRuntimeStartupReadRef {
    fn from(value: protocol::RuntimeStartupReadRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRuntimeReady {
    pub revision: u64,
    pub ready_at: i64,
    pub details: BridgeRuntimeStartupReadRef,
}

impl From<protocol::RuntimeReady> for BridgeRuntimeReady {
    fn from(value: protocol::RuntimeReady) -> Self {
        Self {
            revision: value.revision,
            ready_at: value.ready_at,
            details: value.details.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRuntimeStartupScopeIdentity {
    pub scope_id: String,
    pub owner_epoch: String,
    pub attempt_id: u64,
    pub revision: u64,
}

impl From<protocol::RuntimeStartupScopeIdentity> for BridgeRuntimeStartupScopeIdentity {
    fn from(value: protocol::RuntimeStartupScopeIdentity) -> Self {
        Self {
            scope_id: value.scope_id,
            owner_epoch: value.owner_epoch,
            attempt_id: value.attempt_id,
            revision: value.revision,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStartupRecoveryRead {
    pub backup_path: BridgeReadText,
    pub reason: BridgeReadText,
    pub created_at: i64,
}

impl From<protocol::StartupRecoveryRead> for BridgeStartupRecoveryRead {
    fn from(value: protocol::StartupRecoveryRead) -> Self {
        Self {
            backup_path: value.backup_path.into(),
            reason: value.reason.into(),
            created_at: value.created_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStartupActiveTurnRead {
    pub thread_id: BridgeReadText,
    pub turn_id: BridgeReadText,
}

impl From<protocol::StartupActiveTurnRead> for BridgeStartupActiveTurnRead {
    fn from(value: protocol::StartupActiveTurnRead) -> Self {
        Self {
            thread_id: value.thread_id.into(),
            turn_id: value.turn_id.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRuntimeStartupReadHeader {
    pub scope: BridgeRuntimeStartupScopeIdentity,
    pub reference: BridgeRuntimeStartupReadRef,
    pub revision: u64,
    pub state: BridgeRuntimeStateRead,
    pub startup_recovery: Option<BridgeStartupRecoveryRead>,
    pub active_turn_count: u64,
}

impl From<protocol::RuntimeStartupReadHeader> for BridgeRuntimeStartupReadHeader {
    fn from(value: protocol::RuntimeStartupReadHeader) -> Self {
        Self {
            scope: value.scope.into(),
            reference: value.reference.into(),
            revision: value.revision,
            state: value.state.into(),
            startup_recovery: value.startup_recovery.map(Into::into),
            active_turn_count: value.active_turn_count,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeStartupActiveTurnReadPage {
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeStartupActiveTurnRead>,
    pub next_offset: Option<u64>,
}

impl From<protocol::StartupActiveTurnReadPage> for BridgeStartupActiveTurnReadPage {
    fn from(value: protocol::StartupActiveTurnReadPage) -> Self {
        Self {
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRuntimeStateRead {
    Uninitialized {
        at: i64,
    },
    Initializing {
        at: i64,
    },
    Ready {
        at: i64,
    },
    ShuttingDown {
        at: i64,
    },
    Stopped {
        at: i64,
    },
    Failed {
        failed_at: i64,
        error: BridgeSourceStateErrorRead,
    },
}

impl From<protocol::RuntimeStateRead> for BridgeRuntimeStateRead {
    fn from(value: protocol::RuntimeStateRead) -> Self {
        match value {
            protocol::RuntimeStateRead::Uninitialized { at } => Self::Uninitialized { at },
            protocol::RuntimeStateRead::Initializing { at } => Self::Initializing { at },
            protocol::RuntimeStateRead::Ready { at } => Self::Ready { at },
            protocol::RuntimeStateRead::ShuttingDown { at } => Self::ShuttingDown { at },
            protocol::RuntimeStateRead::Stopped { at } => Self::Stopped { at },
            protocol::RuntimeStateRead::Failed { failed_at, error } => Self::Failed {
                failed_at,
                error: error.into(),
            },
        }
    }
}
impl ModelsRead for StudioStartupRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        StudioStartupRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        StudioStartupRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioStartupRead::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        StudioStartupRead::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeStartupReadConnection {
    read: ModelsReadHandle<StudioStartupRead>,
}
impl BridgeStartupReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeRuntimeStartupReadHeader, BridgeError> {
        let query = self.read.query(move |source| source.header())?;
        Ok(query.await?.into())
    }
    pub async fn active_turns(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeStartupActiveTurnReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.active_turns(offset, limit))?;
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
impl From<BridgeRuntimeStartupReadRef> for protocol::RuntimeStartupReadRef {
    fn from(value: BridgeRuntimeStartupReadRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
        }
    }
}
pub async fn open_startup_read(
    reference: BridgeRuntimeStartupReadRef,
) -> Result<BridgeStartupReadConnection, BridgeError> {
    let reference = reference.into();
    Ok(BridgeStartupReadConnection {
        read: open_read(move |runtime| runtime.open_startup_read(reference)).await?,
    })
}
