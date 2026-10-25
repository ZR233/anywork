//! Exhaustive audience DTO conversion, independent of content and platform receipt payloads.

use pl_protocol as protocol;

use super::runtime::bridge_diagnostic;
use crate::api::studio::types::*;

pub(crate) fn bridge_audience(value: protocol::ThreadAudience) -> BridgeThreadAudience {
    match value {
        protocol::ThreadAudience::Unbound {} => BridgeThreadAudience::Unbound,
        protocol::ThreadAudience::Unavailable { reason } => BridgeThreadAudience::Unavailable {
            reason: unavailable_reason(reason),
        },
        protocol::ThreadAudience::Known { audience } => BridgeThreadAudience::Known {
            audience: Box::new(BridgeBotThreadAudience {
                target: target(audience.target),
                binding: match audience.binding {
                    protocol::BotThreadBindingPosition::Current { cas, sync } => {
                        BridgeBotThreadBindingPosition::Current {
                            cas: sync_cas(cas),
                            sync: Box::new(current_sync(*sync)),
                        }
                    }
                    protocol::BotThreadBindingPosition::Replaced {
                        last_binding_revision,
                        current_binding_revision,
                    } => BridgeBotThreadBindingPosition::Replaced {
                        last_binding_revision,
                        current_binding_revision,
                    },
                },
                latest_closed: audience.latest_closed.map(closed_authorization),
                has_older_closed: audience.has_older_closed,
                delivery: BridgeBotDeliverySummary {
                    version: audience.delivery.version,
                    pending_items: audience.delivery.pending_items,
                    unknown_operations: audience.delivery.unknown_operations,
                    incomplete_items: audience.delivery.incomplete_items,
                    counts_capped: audience.delivery.counts_capped,
                },
                legacy_final: BridgeBotLegacyFinalSummary {
                    unfinished_chains: audience.legacy_final.unfinished_chains,
                    unknown_operations: audience.legacy_final.unknown_operations,
                    needs_attention: audience.legacy_final.needs_attention,
                    counts_capped: audience.legacy_final.counts_capped,
                },
            }),
        },
    }
}

pub(crate) fn unavailable_reason(
    value: protocol::ThreadAudienceUnavailableReason,
) -> BridgeThreadAudienceUnavailableReason {
    match value {
        protocol::ThreadAudienceUnavailableReason::OwnershipUnproven => {
            BridgeThreadAudienceUnavailableReason::OwnershipUnproven
        }
        protocol::ThreadAudienceUnavailableReason::InvalidOwnership => {
            BridgeThreadAudienceUnavailableReason::InvalidOwnership
        }
        protocol::ThreadAudienceUnavailableReason::BotUnavailable => {
            BridgeThreadAudienceUnavailableReason::BotUnavailable
        }
        protocol::ThreadAudienceUnavailableReason::StateUnreadable => {
            BridgeThreadAudienceUnavailableReason::StateUnreadable
        }
        protocol::ThreadAudienceUnavailableReason::InconsistentScope => {
            BridgeThreadAudienceUnavailableReason::InconsistentScope
        }
        protocol::ThreadAudienceUnavailableReason::BindingUnavailable => {
            BridgeThreadAudienceUnavailableReason::BindingUnavailable
        }
        protocol::ThreadAudienceUnavailableReason::RuntimeClosed => {
            BridgeThreadAudienceUnavailableReason::RuntimeClosed
        }
    }
}

pub(crate) fn target(value: protocol::BotAudienceTarget) -> BridgeBotAudienceTarget {
    BridgeBotAudienceTarget {
        bot_id: value.bot_id,
        bot_name: value.bot_name,
        chat_id: value.chat_id,
        chat_name: value.chat_name,
        kind: match value.kind {
            protocol::studio::BotConversationKind::Direct => BridgeBotConversationKind::Direct,
            protocol::studio::BotConversationKind::Group => BridgeBotConversationKind::Group,
        },
    }
}

pub(crate) fn authorization_id(value: protocol::BotAuthorizationId) -> BridgeBotAuthorizationId {
    BridgeBotAuthorizationId {
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        generation: value.generation,
    }
}

pub(crate) fn authorization_ref(value: protocol::BotAuthorizationRef) -> BridgeBotAuthorizationRef {
    BridgeBotAuthorizationRef {
        id: authorization_id(value.id),
        revision: value.revision,
    }
}

fn sync_cas(value: protocol::BotSyncCas) -> BridgeBotSyncCas {
    BridgeBotSyncCas {
        binding_revision: value.binding_revision,
        authorization_head: match value.authorization_head {
            protocol::BotAuthorizationHead::None {} => BridgeBotAuthorizationHead::None,
            protocol::BotAuthorizationHead::Present { authorization } => {
                BridgeBotAuthorizationHead::Present {
                    authorization: authorization_ref(authorization),
                }
            }
        },
    }
}

fn start(value: protocol::BotAudienceStart) -> BridgeBotAudienceStart {
    BridgeBotAudienceStart {
        commit_sequence: value.commit_sequence,
        excluded_turn_id: value.excluded_turn_id,
    }
}

fn started(value: protocol::BotStartedAuthorization) -> BridgeBotStartedAuthorization {
    BridgeBotStartedAuthorization {
        authorization: authorization_ref(value.authorization),
        binding_revision: value.binding_revision,
        start: start(value.start),
    }
}

fn current_sync(value: protocol::BotCurrentSync) -> BridgeBotCurrentSync {
    match value {
        protocol::BotCurrentSync::PreparingThread {} => BridgeBotCurrentSync::PreparingThread,
        protocol::BotCurrentSync::RequiresUpgrade {} => BridgeBotCurrentSync::RequiresUpgrade,
        protocol::BotCurrentSync::PendingStart { pending } => BridgeBotCurrentSync::PendingStart {
            pending: BridgeBotPendingAuthorization {
                authorization: authorization_ref(pending.authorization),
                operation_id: pending.operation_id,
                diagnostic: pending.diagnostic.map(bridge_diagnostic),
            },
        },
        protocol::BotCurrentSync::Active { authorization } => BridgeBotCurrentSync::Active {
            authorization: started(authorization),
        },
        protocol::BotCurrentSync::Paused { authorization } => BridgeBotCurrentSync::Paused {
            authorization: started(authorization),
        },
        protocol::BotCurrentSync::Closed {} => BridgeBotCurrentSync::Closed,
    }
}

pub(crate) fn closed_authorization(
    value: protocol::BotClosedAuthorization,
) -> BridgeBotClosedAuthorization {
    BridgeBotClosedAuthorization {
        authorization: authorization_ref(value.authorization),
        binding_revision: value.binding_revision,
        start: match value.start {
            protocol::BotClosedStart::NeverActivated {} => BridgeBotClosedStart::NeverActivated,
            protocol::BotClosedStart::Saved { start: value } => BridgeBotClosedStart::Saved {
                start: start(value),
            },
        },
        reason: match value.reason {
            protocol::BotAudienceCloseReason::LocalClose => {
                BridgeBotAudienceCloseReason::LocalClose
            }
            protocol::BotAudienceCloseReason::BotDisabled => {
                BridgeBotAudienceCloseReason::BotDisabled
            }
            protocol::BotAudienceCloseReason::TrustRevoked => {
                BridgeBotAudienceCloseReason::TrustRevoked
            }
            protocol::BotAudienceCloseReason::BindingReplaced => {
                BridgeBotAudienceCloseReason::BindingReplaced
            }
            protocol::BotAudienceCloseReason::BindingUnavailable => {
                BridgeBotAudienceCloseReason::BindingUnavailable
            }
            protocol::BotAudienceCloseReason::StartCancelled => {
                BridgeBotAudienceCloseReason::StartCancelled
            }
            protocol::BotAudienceCloseReason::StartFailed => {
                BridgeBotAudienceCloseReason::StartFailed
            }
        },
        closed_at: value.closed_at,
    }
}
