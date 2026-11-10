//! 本机检测结果的逐字段映射；读、命令、基线与事件使用同一转换。

use pl_protocol::studio::{
    AcpLocalDetectionCommandReply, AcpLocalDetectionFailureKind, AcpLocalDetectionSnapshot,
    AcpLocalDetectionState,
};

use crate::api::studio::types::{
    BridgeAcpLocalDetectionCommandReply, BridgeAcpLocalDetectionFailure,
    BridgeAcpLocalDetectionFailureKind, BridgeAcpLocalDetectionSnapshot,
    BridgeAcpLocalDetectionState,
};

pub(crate) fn bridge_acp_local_detection_snapshot(
    snapshot: AcpLocalDetectionSnapshot,
) -> BridgeAcpLocalDetectionSnapshot {
    BridgeAcpLocalDetectionSnapshot {
        revision: snapshot.revision,
        operation_id: snapshot.operation_id,
        state: match snapshot.state {
            AcpLocalDetectionState::Idle => BridgeAcpLocalDetectionState::Idle,
            AcpLocalDetectionState::Checking => BridgeAcpLocalDetectionState::Checking,
            AcpLocalDetectionState::Available { program, version } => {
                BridgeAcpLocalDetectionState::Available { program, version }
            }
            AcpLocalDetectionState::Missing => BridgeAcpLocalDetectionState::Missing,
            AcpLocalDetectionState::Unsupported => BridgeAcpLocalDetectionState::Unsupported,
            AcpLocalDetectionState::Failed { failure } => BridgeAcpLocalDetectionState::Failed {
                failure: BridgeAcpLocalDetectionFailure {
                    kind: match failure.kind {
                        AcpLocalDetectionFailureKind::Timeout => {
                            BridgeAcpLocalDetectionFailureKind::Timeout
                        }
                        AcpLocalDetectionFailureKind::OutputLimit => {
                            BridgeAcpLocalDetectionFailureKind::OutputLimit
                        }
                        AcpLocalDetectionFailureKind::Execution => {
                            BridgeAcpLocalDetectionFailureKind::Execution
                        }
                        AcpLocalDetectionFailureKind::Cleanup => {
                            BridgeAcpLocalDetectionFailureKind::Cleanup
                        }
                    },
                    message: failure.message,
                },
            },
            AcpLocalDetectionState::Cancelling => BridgeAcpLocalDetectionState::Cancelling,
            AcpLocalDetectionState::Cancelled => BridgeAcpLocalDetectionState::Cancelled,
        },
    }
}

pub(crate) fn bridge_acp_local_detection_reply(
    reply: AcpLocalDetectionCommandReply,
) -> BridgeAcpLocalDetectionCommandReply {
    BridgeAcpLocalDetectionCommandReply {
        receipt: super::commands::command_receipt(reply.receipt),
        snapshot: bridge_acp_local_detection_snapshot(reply.snapshot),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::studio::convert::event::{bridge_product_baseline, bridge_product_event};
    use crate::api::studio::types::{BridgeProductBaseline, BridgeProductEventPayload};
    use pl_protocol::studio::AcpLocalDetectionFailure;
    use pl_studio_runtime::{
        StudioProductBaseline, StudioProductBaselineState, StudioProductEventEnvelope,
        StudioProductEventKind, StudioProductTopic,
    };

    #[test]
    fn acp_detection_preserves_every_state_and_operation_identity() -> anyhow::Result<()> {
        let mut states = vec![
            (
                AcpLocalDetectionState::Idle,
                BridgeAcpLocalDetectionState::Idle,
            ),
            (
                AcpLocalDetectionState::Checking,
                BridgeAcpLocalDetectionState::Checking,
            ),
            (
                AcpLocalDetectionState::Available {
                    program: "/a path/agent".into(),
                    version: "1.2.3".into(),
                },
                BridgeAcpLocalDetectionState::Available {
                    program: "/a path/agent".into(),
                    version: "1.2.3".into(),
                },
            ),
            (
                AcpLocalDetectionState::Missing,
                BridgeAcpLocalDetectionState::Missing,
            ),
            (
                AcpLocalDetectionState::Unsupported,
                BridgeAcpLocalDetectionState::Unsupported,
            ),
            (
                AcpLocalDetectionState::Cancelling,
                BridgeAcpLocalDetectionState::Cancelling,
            ),
            (
                AcpLocalDetectionState::Cancelled,
                BridgeAcpLocalDetectionState::Cancelled,
            ),
        ];
        for (kind, bridge_kind) in [
            (
                AcpLocalDetectionFailureKind::Timeout,
                BridgeAcpLocalDetectionFailureKind::Timeout,
            ),
            (
                AcpLocalDetectionFailureKind::OutputLimit,
                BridgeAcpLocalDetectionFailureKind::OutputLimit,
            ),
            (
                AcpLocalDetectionFailureKind::Execution,
                BridgeAcpLocalDetectionFailureKind::Execution,
            ),
            (
                AcpLocalDetectionFailureKind::Cleanup,
                BridgeAcpLocalDetectionFailureKind::Cleanup,
            ),
        ] {
            states.push((
                AcpLocalDetectionState::Failed {
                    failure: AcpLocalDetectionFailure {
                        kind,
                        message: "safe summary".into(),
                    },
                },
                BridgeAcpLocalDetectionState::Failed {
                    failure: BridgeAcpLocalDetectionFailure {
                        kind: bridge_kind,
                        message: "safe summary".into(),
                    },
                },
            ));
        }
        for (state, expected) in states {
            for operation_id in [None, Some("current-op".to_owned())] {
                let snapshot = AcpLocalDetectionSnapshot {
                    revision: 29,
                    operation_id: operation_id.clone(),
                    state: state.clone(),
                };
                let mapped = bridge_acp_local_detection_snapshot(snapshot.clone());
                assert_eq!(mapped.revision, 29);
                assert_eq!(mapped.operation_id, operation_id);
                assert_eq!(mapped.state, expected);
                let (revision, baseline) = bridge_product_baseline(StudioProductBaseline {
                    topic: StudioProductTopic::AcpLocalDetection,
                    revision: 29,
                    state: StudioProductBaselineState::AcpLocalDetection(Box::new(
                        snapshot.clone(),
                    )),
                })?;
                assert_eq!(revision, 29);
                assert_eq!(
                    baseline,
                    BridgeProductBaseline::AcpLocalDetection(Box::new(mapped.clone()))
                );
                let event = bridge_product_event(StudioProductEventEnvelope {
                    event_id: "event-id".into(),
                    sequence: 9,
                    created_at: 100,
                    kind: StudioProductEventKind::AcpLocalDetectionStateChanged(Box::new(snapshot)),
                })?;
                assert_eq!(event.sequence, 9);
                assert_eq!(event.event_id, "event-id");
                assert_eq!(event.created_at, 100);
                assert_eq!(
                    event.payload,
                    BridgeProductEventPayload::AcpLocalDetectionStateChanged(Box::new(mapped))
                );
            }
        }
        Ok(())
    }

    #[test]
    fn acp_detection_cancel_reply_keeps_command_id_distinct_from_target() {
        use pl_protocol::studio::{
            CommandDisposition, CommandEffectPoint, ResourceStamp, StudioCommandReceipt,
        };
        let reply = bridge_acp_local_detection_reply(AcpLocalDetectionCommandReply {
            receipt: StudioCommandReceipt {
                operation_id: "cancel-op".into(),
                disposition: CommandDisposition::Applied,
                targets: vec![ResourceStamp {
                    resource_key: "acp-local-detection".into(),
                    owner_epoch: "owner".into(),
                    revision: 7,
                }],
                effect: CommandEffectPoint::Immediate,
                effective: true,
                durable: false,
                requires_identity_observation: false,
            },
            snapshot: AcpLocalDetectionSnapshot {
                revision: 7,
                operation_id: Some("target-op".into()),
                state: AcpLocalDetectionState::Cancelling,
            },
        });
        assert_eq!(reply.receipt.operation_id, "cancel-op");
        assert_eq!(reply.snapshot.operation_id.as_deref(), Some("target-op"));
        assert_eq!(
            reply.snapshot.state,
            BridgeAcpLocalDetectionState::Cancelling
        );
        assert_eq!(reply.receipt.targets[0].revision, reply.snapshot.revision);
        assert_eq!(reply.receipt.targets[0].resource_key, "acp-local-detection");
        assert!(!reply.receipt.durable);
    }
}
