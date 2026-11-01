//! One-to-one mappings only. Product ordering, current projection and admission live in Runtime.
use pl_protocol as protocol;

use crate::api::studio::types::*;

pub(crate) fn demand(value: BridgeReadDemand) -> protocol::ReadDemand {
    protocol::ReadDemand {
        max_items: value.max_items,
        max_bytes: value.max_bytes,
    }
}

pub(crate) fn scope(value: BridgeChatScope) -> protocol::ChatScope {
    match value {
        BridgeChatScope::Main => protocol::ChatScope::Main,
        BridgeChatScope::Children { parent_id } => protocol::ChatScope::Children { parent_id },
    }
}

pub(crate) fn content_ref(value: protocol::ContentRef) -> BridgeContentRef {
    BridgeContentRef {
        database_id: value.database_id,
        target: match value.target {
            protocol::ContentTarget::ItemPayload { item_id } => {
                BridgeContentTarget::ItemPayload { item_id }
            }
            protocol::ContentTarget::Body { owner, key } => BridgeContentTarget::Body {
                owner: match owner {
                    protocol::ContentOwner::Item { item_id } => {
                        BridgeContentOwner::Item { item_id }
                    }
                    protocol::ContentOwner::Current {
                        domain,
                        id,
                        revision,
                    } => BridgeContentOwner::Current {
                        domain,
                        id,
                        revision,
                    },
                },
                key,
            },
        },
    }
}

pub(crate) fn protocol_content_ref(value: BridgeContentRef) -> protocol::ContentRef {
    protocol::ContentRef {
        database_id: value.database_id,
        target: match value.target {
            BridgeContentTarget::ItemPayload { item_id } => {
                protocol::ContentTarget::ItemPayload { item_id }
            }
            BridgeContentTarget::Body { owner, key } => protocol::ContentTarget::Body {
                owner: match owner {
                    BridgeContentOwner::Item { item_id } => {
                        protocol::ContentOwner::Item { item_id }
                    }
                    BridgeContentOwner::Current {
                        domain,
                        id,
                        revision,
                    } => protocol::ContentOwner::Current {
                        domain,
                        id,
                        revision,
                    },
                },
                key,
            },
        },
    }
}

pub(crate) fn range(value: BridgeContentRange) -> protocol::ContentRange {
    protocol::ContentRange {
        offset: value.offset,
        max_bytes: value.max_bytes,
    }
}

fn payload(value: protocol::PayloadData) -> BridgePayloadData {
    match value {
        protocol::PayloadData::Inline { bytes } => BridgePayloadData::Inline { bytes },
        protocol::PayloadData::Deferred {
            reference,
            byte_length,
        } => BridgePayloadData::Deferred {
            reference: content_ref(reference),
            byte_length,
        },
    }
}

pub(crate) fn batch(value: protocol::ChatBatch) -> BridgeChatBatch {
    BridgeChatBatch {
        placement: match value.placement {
            protocol::ChatPlacement::Set => BridgeChatPlacement::Set,
            protocol::ChatPlacement::Prepend => BridgeChatPlacement::Prepend,
            protocol::ChatPlacement::Append => BridgeChatPlacement::Append,
        },
        messages: value
            .messages
            .into_iter()
            .map(|message| BridgeChatMessage {
                id: message.id,
                payload: payload(message.payload),
            })
            .collect(),
        before: value.before,
        current: value.current.map(current),
    }
}

fn current(value: protocol::CurrentProjection) -> BridgeCurrentProjection {
    BridgeCurrentProjection {
        source_effect_seq: value.source_effect_seq,
        logical_status: match value.logical_status {
            protocol::ThreadStatus::Idle => BridgeThreadStatus::Idle,
            protocol::ThreadStatus::Queued => BridgeThreadStatus::Queued,
            protocol::ThreadStatus::Running => BridgeThreadStatus::Running,
            protocol::ThreadStatus::WaitingTool => BridgeThreadStatus::WaitingTool,
            protocol::ThreadStatus::WaitingInteraction => BridgeThreadStatus::WaitingInteraction,
            protocol::ThreadStatus::Cancelling => BridgeThreadStatus::Cancelling,
            protocol::ThreadStatus::Closing => BridgeThreadStatus::Closing,
            protocol::ThreadStatus::Closed => BridgeThreadStatus::Closed,
            protocol::ThreadStatus::Faulted => BridgeThreadStatus::Faulted,
        },
        execution_present: value.execution_present,
        active: value.active.map(|head| BridgeCurrentActivityHead {
            id: head.id,
            kind: super::thread_stream::activity::activity_kind(head.kind),
            summary: head.summary,
            thinking_summary: head.thinking_summary,
            thinking_seconds: head.thinking_seconds,
            tool_count: head.tool_count,
            background_tool_count: head.background_tool_count,
            latest_tool: head.latest_tool.map(|tool| BridgeCurrentToolHead {
                call_id: tool.call_id,
                name: tool.name,
                state: super::thread_stream::activity::tool_state(tool.state),
            }),
        }),
        active_turn: value.active_turn.map(|head| BridgeCurrentTurnHead {
            id: head.id,
            phase: super::thread_stream::turn_phase(head.phase),
            children_parent_id: head.children_parent_id,
        }),
        plan: value.plan.map(|head| BridgeCurrentPlanHead {
            revision: head.revision,
            phase: super::thread_stream::plan_phase(head.phase),
            document: head.document.map(content_ref),
        }),
        interactions: value.interactions.map(collection_ref),
        previews: value
            .previews
            .into_iter()
            .map(|preview| BridgeCurrentContentPreview {
                id: preview.id,
                role: match preview.role {
                    protocol::CurrentContentRole::Reasoning => BridgeCurrentContentRole::Reasoning,
                    protocol::CurrentContentRole::Response => BridgeCurrentContentRole::Response,
                    protocol::CurrentContentRole::ToolArguments => {
                        BridgeCurrentContentRole::ToolArguments
                    }
                    protocol::CurrentContentRole::ToolOutput => {
                        BridgeCurrentContentRole::ToolOutput
                    }
                },
                text_channel: preview.text_channel.map(|channel| match channel {
                    protocol::ThreadTextChannel::User => BridgeThreadTextChannel::User,
                    protocol::ThreadTextChannel::ParentAgent => {
                        BridgeThreadTextChannel::ParentAgent
                    }
                    protocol::ThreadTextChannel::Commentary => BridgeThreadTextChannel::Commentary,
                    protocol::ThreadTextChannel::Final => BridgeThreadTextChannel::FinalAnswer,
                }),
                text: preview.text,
                reference: content_ref(preview.reference),
            })
            .collect(),
        collections: value.collections.into_iter().map(collection_ref).collect(),
    }
}

fn collection_ref(value: protocol::CurrentCollectionRef) -> BridgeCurrentCollectionRef {
    BridgeCurrentCollectionRef {
        database_id: value.database_id,
        collection: value.collection,
        revision: value.revision,
    }
}

pub(crate) fn protocol_collection_ref(
    value: BridgeCurrentCollectionRef,
) -> protocol::CurrentCollectionRef {
    protocol::CurrentCollectionRef {
        database_id: value.database_id,
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

pub(crate) fn manifest(value: protocol::ContentManifestPage) -> BridgeContentManifestPage {
    BridgeContentManifestPage {
        entries: value
            .entries
            .into_iter()
            .map(|entry| BridgeContentManifestEntry {
                key: entry.key,
                payload: entry.payload,
                reference: content_ref(entry.reference),
            })
            .collect(),
        continuation: value.continuation,
    }
}

pub(crate) fn collection_page(
    value: protocol::CurrentCollectionPage,
) -> BridgeCurrentCollectionPage {
    BridgeCurrentCollectionPage {
        revision: value.revision,
        entries: value
            .entries
            .into_iter()
            .map(|entry| BridgeCurrentCollectionEntry {
                id: entry.id,
                position: entry.position,
                payload: payload(entry.payload),
            })
            .collect(),
        continuation: value.continuation,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn current_text_channels_preserve_unknown_and_the_original_producer_channel() {
        for (channel, expected) in [
            (None, None),
            (
                Some(protocol::ThreadTextChannel::User),
                Some(BridgeThreadTextChannel::User),
            ),
            (
                Some(protocol::ThreadTextChannel::ParentAgent),
                Some(BridgeThreadTextChannel::ParentAgent),
            ),
            (
                Some(protocol::ThreadTextChannel::Commentary),
                Some(BridgeThreadTextChannel::Commentary),
            ),
            (
                Some(protocol::ThreadTextChannel::Final),
                Some(BridgeThreadTextChannel::FinalAnswer),
            ),
        ] {
            let reference = protocol::ContentRef {
                database_id: "original-database".into(),
                target: protocol::ContentTarget::Body {
                    owner: protocol::ContentOwner::Item {
                        item_id: "original-text".into(),
                    },
                    key: "body".into(),
                },
            };
            let mut projection =
                protocol::CurrentProjection::empty(23, protocol::ThreadStatus::Running);
            projection.previews.push(protocol::CurrentContentPreview {
                id: "original-text".into(),
                role: protocol::CurrentContentRole::Response,
                text_channel: channel,
                text: "正文".into(),
                reference: reference.clone(),
            });

            let mapped = current(projection);
            let preview = &mapped.previews[0];
            assert_eq!(preview.role, BridgeCurrentContentRole::Response);
            assert_eq!(preview.text_channel, expected);
            assert_eq!(preview.id, "original-text");
            assert_eq!(preview.text, "正文");
            assert_eq!(protocol_content_ref(preview.reference.clone()), reference);
        }
    }

    #[test]
    fn references_round_trip_without_reinterpreting_owner_identity() {
        for target in [
            protocol::ContentTarget::ItemPayload {
                item_id: "unknown:payload".into(),
            },
            protocol::ContentTarget::Body {
                owner: protocol::ContentOwner::Item {
                    item_id: "active-before-seal".into(),
                },
                key: "unrecognised-body-key".into(),
            },
            protocol::ContentTarget::Body {
                owner: protocol::ContentOwner::Current {
                    domain: "plan".into(),
                    id: "original-owner".into(),
                    revision: 19,
                },
                key: "document".into(),
            },
        ] {
            let original = protocol::ContentRef {
                database_id: "original-database".into(),
                target,
            };
            assert_eq!(
                protocol_content_ref(content_ref(original.clone())),
                original
            );
        }
    }

    #[test]
    fn payload_remains_opaque_and_none_current_is_not_an_empty_snapshot() {
        let bytes = vec![0, 255, b'{', b'}'];
        let value = protocol::ChatBatch {
            placement: protocol::ChatPlacement::Prepend,
            messages: vec![protocol::ChatMessage {
                id: "future-item".into(),
                payload: protocol::PayloadData::Inline {
                    bytes: bytes.clone(),
                },
            }],
            before: Some("opaque-cursor".into()),
            current: None,
        };
        let mapped = batch(value.clone());
        assert!(mapped.current.is_none());
        assert_eq!(mapped.before.as_deref(), Some("opaque-cursor"));
        assert!(
            matches!(&mapped.messages[0].payload, BridgePayloadData::Inline { bytes: mapped } if *mapped == bytes)
        );
        let mut empty = value;
        empty.current = Some(protocol::CurrentProjection::empty(
            23,
            protocol::ThreadStatus::Idle,
        ));
        let empty = batch(empty).current.unwrap();
        assert_eq!(empty.source_effect_seq, 23);
        assert!(empty.active.is_none());
        assert!(!empty.execution_present);
    }
}
