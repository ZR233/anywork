//! Typed request/reply mapping for local audience inspection and control.

use pl_protocol::studio as protocol;

use super::{commands::command_receipt, runtime::bridge_diagnostic, thread_audience as audience};
use crate::api::studio::types::*;

pub(crate) fn read_closed_request(
    value: BridgeReadThreadClosedAuthorizationsRequest,
) -> protocol::ReadThreadClosedAuthorizationsRequest {
    protocol::ReadThreadClosedAuthorizationsRequest {
        thread_id: value.thread_id,
        cursor: value.cursor,
        limit: value.limit,
    }
}

pub(crate) fn closed_reply(
    value: protocol::ReadThreadClosedAuthorizationsReply,
) -> BridgeReadThreadClosedAuthorizationsReply {
    BridgeReadThreadClosedAuthorizationsReply {
        thread_id: value.thread_id,
        result: match value.result {
            protocol::ThreadClosedAuthorizationsRead::Unbound {} => {
                BridgeThreadClosedAuthorizationsRead::Unbound
            }
            protocol::ThreadClosedAuthorizationsRead::Unavailable { reason } => {
                BridgeThreadClosedAuthorizationsRead::Unavailable {
                    reason: audience::unavailable_reason(reason),
                }
            }
            protocol::ThreadClosedAuthorizationsRead::Page { page } => {
                BridgeThreadClosedAuthorizationsRead::Page {
                    page: BridgeThreadClosedAuthorizationPage {
                        target: audience::target(page.target),
                        authorizations: page
                            .authorizations
                            .into_iter()
                            .map(audience::closed_authorization)
                            .collect(),
                        next_cursor: page.next_cursor,
                    },
                }
            }
        },
    }
}

fn authorization_id(value: BridgeBotAuthorizationId) -> pl_protocol::BotAuthorizationId {
    pl_protocol::BotAuthorizationId {
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        generation: value.generation,
    }
}

pub(crate) fn items_request(
    value: BridgeReadThreadAudienceItemsRequest,
) -> protocol::ReadThreadAudienceItemsRequest {
    protocol::ReadThreadAudienceItemsRequest {
        thread_id: value.thread_id,
        authorization: authorization_id(value.authorization),
        item_ids: value.item_ids,
    }
}

pub(crate) fn sync_request(
    value: BridgeChangeBotThreadSyncRequest,
) -> protocol::ChangeBotThreadSyncRequest {
    protocol::ChangeBotThreadSyncRequest {
        operation_id: value.operation_id,
        thread_id: value.thread_id,
        expected: pl_protocol::BotSyncCas {
            binding_revision: value.expected.binding_revision,
            authorization_head: match value.expected.authorization_head {
                BridgeBotAuthorizationHead::None => pl_protocol::BotAuthorizationHead::None {},
                BridgeBotAuthorizationHead::Present { authorization } => {
                    pl_protocol::BotAuthorizationHead::Present {
                        authorization: pl_protocol::BotAuthorizationRef {
                            id: authorization_id(authorization.id),
                            revision: authorization.revision,
                        },
                    }
                }
            },
        },
        action: match value.action {
            BridgeBotThreadSyncAction::Pause => protocol::BotThreadSyncAction::Pause,
            BridgeBotThreadSyncAction::Resume => protocol::BotThreadSyncAction::Resume,
            BridgeBotThreadSyncAction::Close => protocol::BotThreadSyncAction::Close,
            BridgeBotThreadSyncAction::Enable => protocol::BotThreadSyncAction::Enable,
        },
    }
}

pub(crate) fn sync_reply(
    value: protocol::ChangeBotThreadSyncReply,
) -> BridgeChangeBotThreadSyncReply {
    BridgeChangeBotThreadSyncReply {
        thread_id: value.thread_id,
        audience: audience::bridge_audience(value.audience),
        state: match value.state {
            protocol::BotThreadSyncCommandState::Settled {} => {
                BridgeBotThreadSyncCommandState::Settled
            }
            protocol::BotThreadSyncCommandState::PendingStart { authorization } => {
                BridgeBotThreadSyncCommandState::PendingStart {
                    authorization: audience::authorization_id(authorization),
                }
            }
            protocol::BotThreadSyncCommandState::Superseded { authorization } => {
                BridgeBotThreadSyncCommandState::Superseded {
                    authorization: audience::authorization_id(authorization),
                }
            }
        },
        receipt: command_receipt(value.receipt),
    }
}

pub(crate) fn items_reply(
    value: protocol::ReadThreadAudienceItemsReply,
) -> BridgeReadThreadAudienceItemsReply {
    BridgeReadThreadAudienceItemsReply {
        thread_id: value.thread_id,
        authorization: audience::authorization_id(value.authorization),
        result: match value.result {
            protocol::BotAudienceItemsRead::Unavailable { reason } => {
                BridgeBotAudienceItemsRead::Unavailable {
                    reason: match reason {
                        protocol::BotAudienceItemsUnavailableReason::OwnerUnavailable => {
                            BridgeBotAudienceItemsUnavailableReason::OwnerUnavailable
                        }
                        protocol::BotAudienceItemsUnavailableReason::LedgerUnreadable => {
                            BridgeBotAudienceItemsUnavailableReason::LedgerUnreadable
                        }
                        protocol::BotAudienceItemsUnavailableReason::CanonicalReadInvalidated => {
                            BridgeBotAudienceItemsUnavailableReason::CanonicalReadInvalidated
                        }
                        protocol::BotAudienceItemsUnavailableReason::ScopeChanged => {
                            BridgeBotAudienceItemsUnavailableReason::ScopeChanged
                        }
                    },
                }
            }
            protocol::BotAudienceItemsRead::Items {
                authorization,
                phase,
                summary_version,
                delivery_version,
                items,
            } => BridgeBotAudienceItemsRead::Items {
                authorization: audience::authorization_ref(authorization),
                phase: match phase {
                    protocol::BotAuthorizationPhase::PendingStart => {
                        BridgeBotAuthorizationPhase::PendingStart
                    }
                    protocol::BotAuthorizationPhase::Active => BridgeBotAuthorizationPhase::Active,
                    protocol::BotAuthorizationPhase::Paused => BridgeBotAuthorizationPhase::Paused,
                    protocol::BotAuthorizationPhase::Closed => BridgeBotAuthorizationPhase::Closed,
                },
                summary_version,
                delivery_version,
                items: items.into_iter().map(item_status).collect(),
            },
        },
    }
}

fn item_status(value: protocol::BotAudienceItemStatus) -> BridgeBotAudienceItemStatus {
    BridgeBotAudienceItemStatus {
        item_id: value.item_id,
        canonical: match value.canonical {
            protocol::BotAudienceCanonicalItem::Present {
                revision,
                saved,
                eligibility: value,
            } => BridgeBotAudienceCanonicalItem::Present {
                revision,
                saved,
                eligibility: eligibility(value),
            },
            protocol::BotAudienceCanonicalItem::Removed {} => {
                BridgeBotAudienceCanonicalItem::Removed
            }
            protocol::BotAudienceCanonicalItem::Unavailable { reason } => {
                BridgeBotAudienceCanonicalItem::Unavailable {
                    reason: match reason {
                        protocol::BotCanonicalUnavailableReason::Missing => {
                            BridgeBotCanonicalUnavailableReason::Missing
                        }
                        protocol::BotCanonicalUnavailableReason::ReadInvalidated => {
                            BridgeBotCanonicalUnavailableReason::ReadInvalidated
                        }
                        protocol::BotCanonicalUnavailableReason::StorageUnavailable => {
                            BridgeBotCanonicalUnavailableReason::StorageUnavailable
                        }
                        protocol::BotCanonicalUnavailableReason::InvalidMetadata => {
                            BridgeBotCanonicalUnavailableReason::InvalidMetadata
                        }
                        protocol::BotCanonicalUnavailableReason::StartProofUnavailable => {
                            BridgeBotCanonicalUnavailableReason::StartProofUnavailable
                        }
                    },
                }
            }
        },
        delivery: match value.delivery {
            protocol::BotItemDelivery::NotProjected {} => BridgeBotItemDelivery::NotProjected,
            protocol::BotItemDelivery::Known { ledger } => BridgeBotItemDelivery::Known {
                ledger: Box::new(BridgeBotItemLedgerSummary {
                    observed_revision: ledger.observed_revision,
                    projected: presentation(ledger.projected),
                    accepted: presentation(ledger.accepted),
                    platform: platform(ledger.platform),
                }),
            },
        },
    }
}

fn eligibility(value: protocol::BotItemEligibility) -> BridgeBotItemEligibility {
    match value {
        protocol::BotItemEligibility::Text { channel } => BridgeBotItemEligibility::Text {
            channel: match channel {
                protocol::BotPublicTextChannel::Commentary => {
                    BridgeBotPublicTextChannel::Commentary
                }
                protocol::BotPublicTextChannel::Final => BridgeBotPublicTextChannel::Final,
            },
        },
        protocol::BotItemEligibility::PublicArtifact {} => BridgeBotItemEligibility::PublicArtifact,
        protocol::BotItemEligibility::NotAuthorized { reason } => {
            BridgeBotItemEligibility::NotAuthorized {
                reason: match reason {
                    protocol::BotItemExclusion::NonPublicContent => {
                        BridgeBotItemExclusion::NonPublicContent
                    }
                    protocol::BotItemExclusion::OutsideAuthorization => {
                        BridgeBotItemExclusion::OutsideAuthorization
                    }
                    protocol::BotItemExclusion::ExcludedStartedTurn => {
                        BridgeBotItemExclusion::ExcludedStartedTurn
                    }
                    protocol::BotItemExclusion::LegacyOnly => BridgeBotItemExclusion::LegacyOnly,
                },
            }
        }
    }
}

fn presentation(value: protocol::BotItemPresentation) -> BridgeBotItemPresentation {
    match value {
        protocol::BotItemPresentation::None {} => BridgeBotItemPresentation::None,
        protocol::BotItemPresentation::File { revision } => {
            BridgeBotItemPresentation::File { revision }
        }
        protocol::BotItemPresentation::Text {
            revision,
            integrity,
            saved,
        } => BridgeBotItemPresentation::Text {
            revision,
            saved,
            integrity: match integrity {
                protocol::BotTextIntegrity::Full => BridgeBotTextIntegrity::Full,
                protocol::BotTextIntegrity::Truncated => BridgeBotTextIntegrity::Truncated,
            },
        },
    }
}

fn platform_result(value: protocol::BotPlatformResult) -> BridgeBotPlatformResult {
    match value {
        protocol::BotPlatformResult::NotStarted {} => BridgeBotPlatformResult::NotStarted,
        protocol::BotPlatformResult::InFlight {} => BridgeBotPlatformResult::InFlight,
        protocol::BotPlatformResult::Accepted {} => BridgeBotPlatformResult::Accepted,
        protocol::BotPlatformResult::Rejected { diagnostic } => BridgeBotPlatformResult::Rejected {
            diagnostic: bridge_diagnostic(diagnostic),
        },
        protocol::BotPlatformResult::Unknown { diagnostic } => BridgeBotPlatformResult::Unknown {
            diagnostic: bridge_diagnostic(diagnostic),
        },
    }
}

fn platform(value: protocol::BotItemPlatform) -> BridgeBotItemPlatform {
    match value {
        protocol::BotItemPlatform::None {} => BridgeBotItemPlatform::None,
        protocol::BotItemPlatform::Blocked { reason } => BridgeBotItemPlatform::Blocked {
            reason: match reason {
                protocol::BotFileBlockReason::EmptyFile => BridgeBotFileBlockReason::EmptyFile,
                protocol::BotFileBlockReason::PlatformSizeLimit => {
                    BridgeBotFileBlockReason::PlatformSizeLimit
                }
                protocol::BotFileBlockReason::SourceUnavailable => {
                    BridgeBotFileBlockReason::SourceUnavailable
                }
                protocol::BotFileBlockReason::BudgetUnavailable => {
                    BridgeBotFileBlockReason::BudgetUnavailable
                }
            },
        },
        protocol::BotItemPlatform::Card { latest_operation } => BridgeBotItemPlatform::Card {
            latest_operation: BridgeBotCardOperationSummary {
                operation_id: latest_operation.operation_id,
                content_revision: latest_operation.content_revision,
                action: match latest_operation.action {
                    protocol::BotCardOperationKind::Create => BridgeBotCardOperationKind::Create,
                    protocol::BotCardOperationKind::Send => BridgeBotCardOperationKind::Send,
                    protocol::BotCardOperationKind::Content => BridgeBotCardOperationKind::Content,
                    protocol::BotCardOperationKind::Settings => {
                        BridgeBotCardOperationKind::Settings
                    }
                },
                result: platform_result(latest_operation.result),
            },
        },
        protocol::BotItemPlatform::File {
            operation_id,
            content_revision,
            upload,
            message,
            outcome,
            local_stop,
        } => BridgeBotItemPlatform::File {
            operation_id,
            content_revision,
            upload: platform_result(upload),
            message: platform_result(message),
            outcome: match outcome {
                protocol::BotFileOutcome::Pending => BridgeBotFileOutcome::Pending,
                protocol::BotFileOutcome::Delivered => BridgeBotFileOutcome::Delivered,
                protocol::BotFileOutcome::Partial => BridgeBotFileOutcome::Partial,
                protocol::BotFileOutcome::Rejected => BridgeBotFileOutcome::Rejected,
                protocol::BotFileOutcome::Unknown => BridgeBotFileOutcome::Unknown,
                protocol::BotFileOutcome::Stopped => BridgeBotFileOutcome::Stopped,
            },
            local_stop: local_stop.map(|reason| match reason {
                protocol::BotSendStopReason::Cancelled => BridgeBotSendStopReason::Cancelled,
                protocol::BotSendStopReason::LocalFailure => BridgeBotSendStopReason::LocalFailure,
            }),
        },
    }
}
