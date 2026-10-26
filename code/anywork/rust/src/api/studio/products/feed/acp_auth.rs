//! `acpAuth` feed 的 FRB 镜像帧；payload 是 canonical `BridgeAcpAuthSnapshot`。
use super::super::identity::*;
use crate::api::studio::convert::acp::bridge_acp_auth_snapshot;
use crate::api::studio::types::{BridgeAcpAuthSnapshot, BridgeError};
use pl_protocol::products::feed::acp_auth as protocol;

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpAuthEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeAcpAuthSnapshot,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeAcpAuthSnapshot,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpAuthFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeAcpAuthEvent,
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

impl From<protocol::AcpAuthEvent> for BridgeAcpAuthEvent {
    fn from(value: protocol::AcpAuthEvent) -> Self {
        match value {
            protocol::AcpAuthEvent::Baseline {
                identity,
                stamp,
                value,
            } => Self::Baseline {
                identity: identity.into(),
                stamp: stamp.into(),
                value: bridge_acp_auth_snapshot(value),
            },
            protocol::AcpAuthEvent::Change {
                stamp,
                base_revision,
                value,
            } => Self::Change {
                stamp: stamp.into(),
                base_revision,
                value: bridge_acp_auth_snapshot(value),
            },
        }
    }
}

impl From<protocol::AcpAuthFrame> for BridgeAcpAuthFrame {
    fn from(value: protocol::AcpAuthFrame) -> Self {
        match value {
            protocol::AcpAuthFrame::Data {
                delivery_sequence,
                event,
            } => Self::Data {
                delivery_sequence,
                event: event.into(),
            },
            protocol::AcpAuthFrame::ResyncRequired { identity, reason } => Self::ResyncRequired {
                identity: identity.into(),
                reason: reason.into(),
            },
            protocol::AcpAuthFrame::Failure { identity, error } => Self::Failure {
                identity: identity.into(),
                error: error.into(),
            },
            protocol::AcpAuthFrame::Closed { identity, reason } => Self::Closed {
                identity: identity.into(),
                reason: reason.into(),
            },
        }
    }
}
