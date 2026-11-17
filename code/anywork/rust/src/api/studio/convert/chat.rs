//! Mechanical mappings for typed Current sources and bounded content windows.
use pl_protocol as protocol;

use crate::api::studio::types::*;

pub(crate) fn demand(value: BridgeReadDemand) -> protocol::ReadDemand {
    protocol::ReadDemand {
        max_items: value.max_items,
        max_bytes: value.max_bytes,
    }
}

pub(crate) fn range(value: BridgeContentRange) -> protocol::ContentRange {
    protocol::ContentRange {
        offset: value.offset,
        max_bytes: value.max_bytes,
    }
}

pub(super) fn source_id(value: protocol::ChatSourceId) -> BridgeChatSourceId {
    match value {
        protocol::ChatSourceId::ForegroundTurn { turn_id } => {
            BridgeChatSourceId::ForegroundTurn { turn_id }
        }
        protocol::ChatSourceId::Input { input_id } => BridgeChatSourceId::Input { input_id },
        protocol::ChatSourceId::InboxMessage {
            source_id,
            message_id,
        } => BridgeChatSourceId::InboxMessage {
            source_id,
            message_id,
        },
        protocol::ChatSourceId::BackgroundResult { message_id } => {
            BridgeChatSourceId::BackgroundResult { message_id }
        }
        protocol::ChatSourceId::Operation { operation_id } => {
            BridgeChatSourceId::Operation { operation_id }
        }
        protocol::ChatSourceId::Receipt { receipt_id } => {
            BridgeChatSourceId::Receipt { receipt_id }
        }
    }
}

pub(super) fn fact_position(value: protocol::ChatFactPosition) -> BridgeChatFactPosition {
    BridgeChatFactPosition {
        effect_seq: value.effect_seq,
        suborder: value.suborder,
    }
}

pub(super) fn terminal_outcome(value: protocol::ChatTerminalOutcome) -> BridgeChatTerminalOutcome {
    match value {
        protocol::ChatTerminalOutcome::Completed => BridgeChatTerminalOutcome::Completed,
        protocol::ChatTerminalOutcome::Failed => BridgeChatTerminalOutcome::Failed,
        protocol::ChatTerminalOutcome::Cancelled => BridgeChatTerminalOutcome::Cancelled,
        protocol::ChatTerminalOutcome::Transferred => BridgeChatTerminalOutcome::Transferred,
    }
}

pub(super) fn atom_kind(value: protocol::ChatAtomKind) -> BridgeChatAtomKind {
    match value {
        protocol::ChatAtomKind::Input => BridgeChatAtomKind::Input,
        protocol::ChatAtomKind::Text => BridgeChatAtomKind::Text,
        protocol::ChatAtomKind::Reasoning => BridgeChatAtomKind::Reasoning,
        protocol::ChatAtomKind::ToolCall => BridgeChatAtomKind::ToolCall,
        protocol::ChatAtomKind::FileChange => BridgeChatAtomKind::FileChange,
        protocol::ChatAtomKind::Skill => BridgeChatAtomKind::Skill,
        protocol::ChatAtomKind::Interaction => BridgeChatAtomKind::Interaction,
        protocol::ChatAtomKind::Plan => BridgeChatAtomKind::Plan,
        protocol::ChatAtomKind::Compaction => BridgeChatAtomKind::Compaction,
        protocol::ChatAtomKind::TurnReceipt => BridgeChatAtomKind::TurnReceipt,
        protocol::ChatAtomKind::Receipt => BridgeChatAtomKind::Receipt,
        protocol::ChatAtomKind::Raw => BridgeChatAtomKind::Raw,
        protocol::ChatAtomKind::Agent => BridgeChatAtomKind::Agent,
        protocol::ChatAtomKind::Inference => BridgeChatAtomKind::Inference,
        protocol::ChatAtomKind::Unknown => BridgeChatAtomKind::Unknown,
    }
}

pub(super) fn delivery(value: protocol::ChatDeliveryKind) -> BridgeChatDeliveryKind {
    match value {
        protocol::ChatDeliveryKind::Foreground => BridgeChatDeliveryKind::Foreground,
        protocol::ChatDeliveryKind::BackgroundHandoff => BridgeChatDeliveryKind::BackgroundHandoff,
        protocol::ChatDeliveryKind::Independent => BridgeChatDeliveryKind::Independent,
    }
}

pub(super) fn text_channel(value: protocol::ThreadTextChannel) -> BridgeThreadTextChannel {
    match value {
        protocol::ThreadTextChannel::User => BridgeThreadTextChannel::User,
        protocol::ThreadTextChannel::ParentAgent => BridgeThreadTextChannel::ParentAgent,
        protocol::ThreadTextChannel::Commentary => BridgeThreadTextChannel::Commentary,
        protocol::ThreadTextChannel::Final => BridgeThreadTextChannel::FinalAnswer,
    }
}

pub(super) fn source_state(value: protocol::ChatSourceState) -> BridgeChatSourceState {
    BridgeChatSourceState {
        source: source_id(value.source),
        lifecycle: match value.lifecycle {
            protocol::ChatSourceLifecycle::Unknown => BridgeChatSourceLifecycle::Unknown,
            protocol::ChatSourceLifecycle::Active => BridgeChatSourceLifecycle::Active,
            protocol::ChatSourceLifecycle::Ended { outcome } => BridgeChatSourceLifecycle::Ended {
                outcome: terminal_outcome(outcome),
            },
        },
        started: value.started.map(fact_position),
        ended: value.ended.map(fact_position),
    }
}

pub(crate) fn business_refs(value: protocol::ThreadBusinessRefs) -> BridgeThreadBusinessRefs {
    BridgeThreadBusinessRefs {
        plan: value.plan.map(current_plan_head),
        interactions: value.interactions.map(collection_ref),
    }
}

fn current_plan_head(value: protocol::CurrentPlanHead) -> BridgeCurrentPlanHead {
    BridgeCurrentPlanHead {
        revision: value.revision,
        phase: super::thread_stream::plan_phase(value.phase),
        document: value.document.map(|reference| BridgeCurrentContentRef {
            owner_id: reference.owner_id,
            domain: reference.domain,
            entity_id: reference.entity_id,
            content_key: reference.content_key,
            generation: reference.generation,
        }),
    }
}

fn collection_ref(value: protocol::CurrentCollectionRef) -> BridgeCurrentCollectionRef {
    BridgeCurrentCollectionRef {
        owner_id: value.owner_id,
        collection: value.collection,
        revision: value.revision,
    }
}

pub(crate) fn window(value: protocol::ContentWindow) -> BridgeContentWindow {
    BridgeContentWindow {
        offset: value.offset,
        bytes: value.bytes,
        generation: value.generation,
        available_through: value.available_through,
        sealed: value.sealed,
    }
}
