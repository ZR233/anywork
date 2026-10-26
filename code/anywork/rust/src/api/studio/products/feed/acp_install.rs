//! `acpInstall` feed 的 FRB 镜像帧；payload 是 canonical `BridgeAcpInstallSnapshot`。
use super::super::identity::*;
use crate::api::studio::convert::acp_install::bridge_acp_install_snapshot;
use crate::api::studio::types::{BridgeAcpInstallSnapshot, BridgeError};
use pl_protocol::products::feed::acp_install as protocol;

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpInstallEvent {
    Baseline {
        identity: BridgeProductFeedIdentity,
        stamp: BridgeProductProjectionStamp,
        value: BridgeAcpInstallSnapshot,
    },
    Change {
        stamp: BridgeProductProjectionStamp,
        base_revision: u64,
        value: BridgeAcpInstallSnapshot,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpInstallFrame {
    Data {
        delivery_sequence: u64,
        event: BridgeAcpInstallEvent,
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

impl From<protocol::AcpInstallEvent> for BridgeAcpInstallEvent {
    fn from(value: protocol::AcpInstallEvent) -> Self {
        match value {
            protocol::AcpInstallEvent::Baseline {
                identity,
                stamp,
                value,
            } => Self::Baseline {
                identity: identity.into(),
                stamp: stamp.into(),
                value: bridge_acp_install_snapshot(value),
            },
            protocol::AcpInstallEvent::Change {
                stamp,
                base_revision,
                value,
            } => Self::Change {
                stamp: stamp.into(),
                base_revision,
                value: bridge_acp_install_snapshot(value),
            },
        }
    }
}

impl From<protocol::AcpInstallFrame> for BridgeAcpInstallFrame {
    fn from(value: protocol::AcpInstallFrame) -> Self {
        match value {
            protocol::AcpInstallFrame::Data {
                delivery_sequence,
                event,
            } => Self::Data {
                delivery_sequence,
                event: event.into(),
            },
            protocol::AcpInstallFrame::ResyncRequired { identity, reason } => {
                Self::ResyncRequired {
                    identity: identity.into(),
                    reason: reason.into(),
                }
            }
            protocol::AcpInstallFrame::Failure { identity, error } => Self::Failure {
                identity: identity.into(),
                error: error.into(),
            },
            protocol::AcpInstallFrame::Closed { identity, reason } => Self::Closed {
                identity: identity.into(),
                reason: reason.into(),
            },
        }
    }
}
