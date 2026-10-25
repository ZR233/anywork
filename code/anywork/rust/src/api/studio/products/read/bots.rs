//! Bots wire conversion and the original source-status scope. No business querying here.
use pl_protocol::products::read::bots as protocol;
use pl_studio_runtime::StudioBotsSourceStatusRead;

use super::super::identity::{
    BridgeProductFeedCloseReason, BridgeProductFeedIdentity, BridgeProductProjectionStamp,
    BridgeProductReadOrigin, BridgeProductReadScopeIdentity, BridgeProductResyncReason,
    BridgeProductSourceStatusRef,
};
use super::super::source::{BridgeObservedHeader, BridgeProductSourceStatusReadHeader};
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::convert::runtime::bridge_bots_state;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeBotsStateSnapshot, BridgeError, BridgeFeedCloseReport};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotsHeader {
    pub source: BridgeObservedHeader,
    pub bots_revision: Option<u64>,
    pub updated_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeBotsEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        header: BridgeBotsHeader,
        state: Option<BridgeBotsStateSnapshot>,
    },
    StateChanged {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        header: BridgeBotsHeader,
        state: Option<BridgeBotsStateSnapshot>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeBotsFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeBotsEvent,
    },
    ResyncRequired {
        identity: BridgeProductFeedIdentity,
        reason: BridgeProductResyncReason,
    },
    Failure {
        identity: BridgeProductFeedIdentity,
        error: BridgeError,
    },
    Closed {
        identity: BridgeProductFeedIdentity,
        reason: BridgeProductFeedCloseReason,
    },
}

impl From<protocol::BotsHeader> for BridgeBotsHeader {
    fn from(value: protocol::BotsHeader) -> Self {
        Self {
            source: value.source.into(),
            bots_revision: value.bots_revision,
            updated_at: value.updated_at,
        }
    }
}
impl From<protocol::BotsEvent> for BridgeBotsEvent {
    fn from(value: protocol::BotsEvent) -> Self {
        match value {
            protocol::BotsEvent::Baseline {
                identity,
                stamp,
                header,
                state,
            } => Self::Baseline {
                identity: identity.into(),
                stamp: stamp.into(),
                header: header.into(),
                state: state.map(bridge_bots_state),
            },
            protocol::BotsEvent::StateChanged {
                stamp,
                base_revision,
                header,
                state,
            } => Self::StateChanged {
                stamp: stamp.into(),
                base_revision,
                header: header.into(),
                state: state.map(bridge_bots_state),
            },
        }
    }
}
impl From<protocol::BotsFrame> for BridgeBotsFrame {
    fn from(value: protocol::BotsFrame) -> Self {
        match value {
            protocol::BotsFrame::Data {
                delivery_sequence,
                event,
            } => Self::Data {
                delivery_sequence,
                event: (*event).into(),
            },
            protocol::BotsFrame::ResyncRequired { identity, reason } => Self::ResyncRequired {
                identity: identity.into(),
                reason: reason.into(),
            },
            protocol::BotsFrame::Failure { identity, error } => Self::Failure {
                identity: identity.into(),
                error: error.into(),
            },
            protocol::BotsFrame::Closed { identity, reason } => Self::Closed {
                identity: identity.into(),
                reason: reason.into(),
            },
        }
    }
}

impl ModelsRead for StudioBotsSourceStatusRead {
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
pub struct BridgeBotsSourceStatusReadConnection {
    read: ModelsReadHandle<StudioBotsSourceStatusRead>,
}

pub async fn open_bots_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeBotsSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeBotsSourceStatusReadConnection {
        read: open_read(move |runtime| runtime.open_bots_source_status_read(reference, origin))
            .await?,
    })
}

impl BridgeBotsSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioBotsSourceStatusRead::header)?
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
