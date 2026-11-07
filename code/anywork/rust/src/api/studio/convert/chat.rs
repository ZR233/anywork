//! Mechanical mappings of Studio display items and independently read members.
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
        BridgeChatScope::GroupMembers { reference } => protocol::ChatScope::GroupMembers {
            reference: protocol::TimelineMembersRef {
                database_id: reference.database_id,
                projection_version: reference.projection_version,
                projection_generation: reference.projection_generation,
                item_id: reference.item_id,
            },
        },
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

fn source_id(value: protocol::ChatSourceId) -> BridgeChatSourceId {
    match value {
        protocol::ChatSourceId::ForegroundTurn { turn_id } => {
            BridgeChatSourceId::ForegroundTurn { turn_id }
        }
        protocol::ChatSourceId::Input { input_id } => BridgeChatSourceId::Input { input_id },
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

fn fact_position(value: protocol::ChatFactPosition) -> BridgeChatFactPosition {
    BridgeChatFactPosition {
        effect_seq: value.effect_seq,
        suborder: value.suborder,
    }
}

fn terminal_outcome(value: protocol::ChatTerminalOutcome) -> BridgeChatTerminalOutcome {
    match value {
        protocol::ChatTerminalOutcome::Completed => BridgeChatTerminalOutcome::Completed,
        protocol::ChatTerminalOutcome::Failed => BridgeChatTerminalOutcome::Failed,
        protocol::ChatTerminalOutcome::Cancelled => BridgeChatTerminalOutcome::Cancelled,
        protocol::ChatTerminalOutcome::Transferred => BridgeChatTerminalOutcome::Transferred,
    }
}

fn atom_kind(value: protocol::ChatAtomKind) -> BridgeChatAtomKind {
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

fn delivery(value: protocol::ChatDeliveryKind) -> BridgeChatDeliveryKind {
    match value {
        protocol::ChatDeliveryKind::Foreground => BridgeChatDeliveryKind::Foreground,
        protocol::ChatDeliveryKind::BackgroundHandoff => BridgeChatDeliveryKind::BackgroundHandoff,
        protocol::ChatDeliveryKind::Independent => BridgeChatDeliveryKind::Independent,
    }
}

fn text_channel(value: protocol::ThreadTextChannel) -> BridgeThreadTextChannel {
    match value {
        protocol::ThreadTextChannel::User => BridgeThreadTextChannel::User,
        protocol::ThreadTextChannel::ParentAgent => BridgeThreadTextChannel::ParentAgent,
        protocol::ThreadTextChannel::Commentary => BridgeThreadTextChannel::Commentary,
        protocol::ThreadTextChannel::Final => BridgeThreadTextChannel::FinalAnswer,
    }
}

fn atom_content(value: protocol::ChatAtomContent) -> BridgeChatAtomContent {
    BridgeChatAtomContent {
        role: match value.role {
            protocol::ChatContentRole::Body => BridgeChatContentRole::Body,
            protocol::ChatContentRole::ReasoningSummary => BridgeChatContentRole::ReasoningSummary,
            protocol::ChatContentRole::ToolArguments => BridgeChatContentRole::ToolArguments,
            protocol::ChatContentRole::ToolOutput => BridgeChatContentRole::ToolOutput,
        },
        reference: content_ref(value.reference),
    }
}

fn timeline_item(value: protocol::TimelineItem) -> BridgeTimelineItem {
    BridgeTimelineItem {
        id: value.id,
        kind: match value.kind {
            protocol::TimelineItemKind::Text => BridgeTimelineItemKind::Text,
            protocol::TimelineItemKind::WorkGroup => BridgeTimelineItemKind::WorkGroup,
            protocol::TimelineItemKind::Status => BridgeTimelineItemKind::Status,
        },
        source: source_id(value.source),
        atom_kind: value.atom_kind.map(atom_kind),
        delivery: delivery(value.delivery),
        outcome: value.outcome.map(terminal_outcome),
        text_channel: value.text_channel.map(text_channel),
        turn_id: value.turn_id,
        started_at: value.started_at,
        finished_at: value.finished_at,
        summary: value.summary.map(|summary| BridgeTimelineGroupSummary {
            latest_thinking_summary: summary.latest_thinking_summary,
            member_count: summary.member_count,
            active_count: summary.active_count,
            failed_count: summary.failed_count,
            cancelled_count: summary.cancelled_count,
            categories: summary
                .categories
                .into_iter()
                .map(|count| BridgeTimelineCategoryCount {
                    category: match count.category {
                        protocol::TimelineCategory::Thinking => BridgeTimelineCategory::Thinking,
                        protocol::TimelineCategory::Read => BridgeTimelineCategory::Read,
                        protocol::TimelineCategory::Image => BridgeTimelineCategory::Image,
                        protocol::TimelineCategory::Command => BridgeTimelineCategory::Command,
                        protocol::TimelineCategory::Search => BridgeTimelineCategory::Search,
                        protocol::TimelineCategory::Edit => BridgeTimelineCategory::Edit,
                        protocol::TimelineCategory::Wait => BridgeTimelineCategory::Wait,
                        protocol::TimelineCategory::Other => BridgeTimelineCategory::Other,
                    },
                    count: count.count,
                })
                .collect(),
            started_at: summary.started_at,
            finished_at: summary.finished_at,
        }),
        members: value.members.map(|reference| BridgeTimelineMembersRef {
            database_id: reference.database_id,
            projection_version: reference.projection_version,
            projection_generation: reference.projection_generation,
            item_id: reference.item_id,
        }),
        contents: value.contents.into_iter().map(atom_content).collect(),
        payload: value.payload.map(payload),
        content_item_id: value.content_item_id,
        position: value.position,
        admission_closed: value.admission_closed,
    }
}

fn atom(value: protocol::ChatAtom) -> BridgeChatAtom {
    BridgeChatAtom {
        id: value.id,
        completion_item_id: value.completion_item_id,
        completion_seq: value.completion_seq,
        source: source_id(value.source),
        source_state: value.source_state.map(source_state),
        source_order: value.source_order,
        kind: atom_kind(value.kind),
        delivery: delivery(value.delivery),
        lifecycle: match value.lifecycle {
            protocol::ChatAtomLifecycle::Active { started, status } => {
                BridgeChatAtomLifecycle::Active {
                    started: started.map(fact_position),
                    status: match status {
                        protocol::ChatActiveStatus::Running => BridgeChatActiveStatus::Running,
                        protocol::ChatActiveStatus::Waiting => BridgeChatActiveStatus::Waiting,
                    },
                }
            }
            protocol::ChatAtomLifecycle::Terminal {
                started,
                ended,
                outcome,
            } => BridgeChatAtomLifecycle::Terminal {
                started: started.map(fact_position),
                ended: ended.map(fact_position),
                outcome: terminal_outcome(outcome),
            },
        },
        turn_id: value.turn_id,
        attempt_id: value.attempt_id,
        tool: value.tool.map(|tool| BridgeChatToolIdentity {
            call_id: tool.call_id,
            name: tool.name,
        }),
        wait: value.wait.map(super::thread_stream::wait_presentation),
        text_channel: value.text_channel.map(text_channel),
        started_at: value.started_at,
        finished_at: value.finished_at,
        content_present: value.content_present,
        contents: value.contents.into_iter().map(atom_content).collect(),
        payload: value.payload.map(payload),
    }
}

fn source_state(value: protocol::ChatSourceState) -> BridgeChatSourceState {
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

fn entry(value: protocol::ChatEntry) -> BridgeChatEntry {
    match value {
        protocol::ChatEntry::Item(value) => BridgeChatEntry::Item(Box::new(timeline_item(*value))),
        protocol::ChatEntry::Atom(value) => BridgeChatEntry::Atom(Box::new(atom(*value))),
        protocol::ChatEntry::Source(value) => BridgeChatEntry::Source(source_state(value)),
    }
}

pub(crate) fn batch(value: protocol::ChatBatch) -> BridgeChatBatch {
    BridgeChatBatch {
        placement: match value.placement {
            protocol::ChatPlacement::Set => BridgeChatPlacement::Set,
            protocol::ChatPlacement::Prepend => BridgeChatPlacement::Prepend,
            protocol::ChatPlacement::Append => BridgeChatPlacement::Append,
            protocol::ChatPlacement::Update => BridgeChatPlacement::Update,
        },
        entries: value.entries.into_iter().map(entry).collect(),
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
        }),
        sources: value.sources.into_iter().map(source_state).collect(),
        atoms: value.atoms.into_iter().map(atom).collect(),
        items: value.items.into_iter().map(timeline_item).collect(),
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
    fn display_items_and_member_qualification_are_mapped_without_atom_reconstruction() {
        let reference = protocol::TimelineMembersRef {
            database_id: "original-db".into(),
            projection_version: 7,
            projection_generation: "projection-incarnation:α".into(),
            item_id: "stable-item".into(),
        };
        let group = protocol::TimelineItem {
            id: reference.item_id.clone(),
            kind: protocol::TimelineItemKind::WorkGroup,
            source: protocol::ChatSourceId::ForegroundTurn {
                turn_id: "turn".into(),
            },
            atom_kind: None,
            delivery: protocol::ChatDeliveryKind::Foreground,
            outcome: None,
            text_channel: None,
            turn_id: Some("turn".into()),
            started_at: Some(100),
            finished_at: None,
            summary: Some(protocol::TimelineGroupSummary {
                latest_thinking_summary: Some("Reviewing updates".into()),
                member_count: 11,
                active_count: 2,
                failed_count: 1,
                cancelled_count: 3,
                categories: vec![protocol::TimelineCategoryCount {
                    category: protocol::TimelineCategory::Wait,
                    count: 11,
                }],
                started_at: Some(100),
                finished_at: None,
            }),
            members: Some(reference.clone()),
            contents: vec![],
            payload: None,
            content_item_id: None,
            position: Some(23),
            admission_closed: true,
        };
        let mut projection =
            protocol::CurrentProjection::empty(41, protocol::ThreadStatus::Running);
        let mut live = group.clone();
        live.position = None;
        projection.items.push(live);
        let mapped = batch(protocol::ChatBatch {
            placement: protocol::ChatPlacement::Set,
            entries: vec![protocol::ChatEntry::Item(Box::new(group.clone()))],
            before: Some("opaque-item-cursor".into()),
            current: Some(projection),
        });
        let BridgeChatEntry::Item(item) = &mapped.entries[0] else {
            panic!("not an item");
        };
        assert_eq!(item.kind, BridgeTimelineItemKind::WorkGroup);
        assert_eq!(item.position, Some(23));
        assert!(item.payload.is_none() && item.contents.is_empty());
        assert!(item.outcome.is_none());
        let summary = item.summary.as_ref().unwrap();
        assert_eq!(
            summary.latest_thinking_summary.as_deref(),
            Some("Reviewing updates")
        );
        assert_eq!(
            (
                summary.member_count,
                summary.active_count,
                summary.failed_count,
                summary.cancelled_count
            ),
            (11, 2, 1, 3)
        );
        assert_eq!(summary.categories[0].category, BridgeTimelineCategory::Wait);
        let members = item.members.clone().unwrap();
        assert_eq!(members.projection_generation, "projection-incarnation:α");
        assert_eq!(
            scope(BridgeChatScope::GroupMembers { reference: members }),
            protocol::ChatScope::GroupMembers { reference }
        );
        let current = mapped.current.unwrap();
        assert_eq!(current.items[0].id, "stable-item");
        assert_eq!(current.items[0].position, None);
        assert!(current.atoms.is_empty());
        for kind in [
            protocol::TimelineItemKind::Text,
            protocol::TimelineItemKind::Status,
        ] {
            let mapped = timeline_item(protocol::TimelineItem {
                kind,
                atom_kind: Some(protocol::ChatAtomKind::Text),
                outcome: Some(protocol::ChatTerminalOutcome::Cancelled),
                text_channel: Some(protocol::ThreadTextChannel::Commentary),
                summary: None,
                members: None,
                payload: Some(protocol::PayloadData::Inline {
                    bytes: vec![0, 255, b' '],
                }),
                content_item_id: Some("original-content".into()),
                ..group.clone()
            });
            assert_eq!(mapped.outcome, Some(BridgeChatTerminalOutcome::Cancelled));
            assert_eq!(
                mapped.text_channel,
                Some(BridgeThreadTextChannel::Commentary)
            );
            assert_eq!(mapped.content_item_id.as_deref(), Some("original-content"));
            assert!(
                matches!(mapped.payload, Some(BridgePayloadData::Inline { bytes }) if bytes == [0, 255, b' '])
            );
        }
    }

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
            entries: vec![
                protocol::ChatEntry::Atom(Box::new(protocol::ChatAtom {
                    id: "member-id".into(),
                    completion_item_id: Some("frozen-payload-id".into()),
                    completion_seq: Some(12),
                    source: protocol::ChatSourceId::BackgroundResult {
                        message_id: "source-id".into(),
                    },
                    source_state: Some(protocol::ChatSourceState {
                        source: protocol::ChatSourceId::BackgroundResult {
                            message_id: "source-id".into(),
                        },
                        lifecycle: protocol::ChatSourceLifecycle::Active,
                        started: Some(protocol::ChatFactPosition {
                            effect_seq: 8,
                            suborder: 2,
                        }),
                        ended: None,
                    }),
                    source_order: None,
                    kind: protocol::ChatAtomKind::ToolCall,
                    delivery: protocol::ChatDeliveryKind::BackgroundHandoff,
                    lifecycle: protocol::ChatAtomLifecycle::Terminal {
                        started: None,
                        ended: None,
                        outcome: protocol::ChatTerminalOutcome::Transferred,
                    },
                    turn_id: Some("turn-id".into()),
                    attempt_id: None,
                    tool: None,
                    wait: None,
                    text_channel: None,
                    content_present: None,
                    started_at: None,
                    finished_at: None,
                    contents: vec![],
                    payload: Some(protocol::PayloadData::Inline {
                        bytes: bytes.clone(),
                    }),
                })),
                protocol::ChatEntry::Source(protocol::ChatSourceState {
                    source: protocol::ChatSourceId::ForegroundTurn {
                        turn_id: "unknown-turn".into(),
                    },
                    lifecycle: protocol::ChatSourceLifecycle::Unknown,
                    started: None,
                    ended: None,
                }),
            ],
            before: Some("opaque-cursor".into()),
            current: None,
        };
        let mapped = batch(value.clone());
        assert!(mapped.current.is_none());
        assert_eq!(mapped.before.as_deref(), Some("opaque-cursor"));
        let BridgeChatEntry::Atom(atom) = &mapped.entries[0] else {
            panic!("atom entry changed kind");
        };
        assert_eq!(atom.id, "member-id");
        assert_eq!(
            atom.completion_item_id.as_deref(),
            Some("frozen-payload-id")
        );
        assert_eq!(atom.completion_seq, Some(12));
        assert_eq!(atom.source_order, None);
        assert!(matches!(
            &atom.source,
            BridgeChatSourceId::BackgroundResult { message_id } if message_id == "source-id"
        ));
        let source_state = atom.source_state.as_ref().expect("source cut is present");
        assert!(matches!(
            &source_state.source,
            BridgeChatSourceId::BackgroundResult { message_id } if message_id == "source-id"
        ));
        assert!(matches!(
            &source_state.lifecycle,
            BridgeChatSourceLifecycle::Active
        ));
        assert_eq!(
            source_state.started,
            Some(BridgeChatFactPosition {
                effect_seq: 8,
                suborder: 2
            })
        );
        assert_eq!(source_state.ended, None);
        assert!(matches!(
            &atom.lifecycle,
            BridgeChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: BridgeChatTerminalOutcome::Transferred
            }
        ));
        assert!(matches!(
            &atom.payload,
            Some(BridgePayloadData::Inline { bytes: mapped }) if *mapped == bytes
        ));
        let BridgeChatEntry::Source(source) = &mapped.entries[1] else {
            panic!("source state entry changed kind");
        };
        assert!(matches!(
            source.lifecycle,
            BridgeChatSourceLifecycle::Unknown
        ));
        assert_eq!(source.started, None);
        assert_eq!(source.ended, None);
        let mut projection =
            protocol::CurrentProjection::empty(29, protocol::ThreadStatus::Running);
        let protocol::ChatEntry::Atom(current_atom) = &value.entries[0] else {
            panic!("atom entry changed kind");
        };
        let active_position = protocol::ChatFactPosition {
            effect_seq: 29,
            suborder: 1,
        };
        let mut active_atom = current_atom.as_ref().clone();
        active_atom.id = "active-member".into();
        active_atom.completion_item_id = None;
        active_atom.completion_seq = None;
        active_atom.source = protocol::ChatSourceId::ForegroundTurn {
            turn_id: "active-turn".into(),
        };
        active_atom.source_state = None;
        active_atom.source_order = Some(1);
        active_atom.kind = protocol::ChatAtomKind::Text;
        active_atom.delivery = protocol::ChatDeliveryKind::Foreground;
        active_atom.lifecycle = protocol::ChatAtomLifecycle::Active {
            started: Some(active_position),
            status: protocol::ChatActiveStatus::Running,
        };
        active_atom.turn_id = Some("active-turn".into());
        active_atom.payload = None;
        projection.atoms.push(active_atom);
        projection.sources.push(protocol::ChatSourceState {
            source: protocol::ChatSourceId::ForegroundTurn {
                turn_id: "active-turn".into(),
            },
            lifecycle: protocol::ChatSourceLifecycle::Active,
            started: Some(active_position),
            ended: None,
        });
        let mapped = current(projection);
        assert_eq!(mapped.atoms[0].id, "active-member");
        assert_eq!(mapped.atoms[0].completion_seq, None);
        assert_eq!(mapped.atoms[0].source_order, Some(1));
        assert!(mapped.atoms[0].source_state.is_none());
        assert!(mapped.atoms[0].payload.is_none());
        assert!(matches!(
            &mapped.atoms[0].lifecycle,
            BridgeChatAtomLifecycle::Active {
                started: Some(BridgeChatFactPosition {
                    effect_seq: 29,
                    suborder: 1
                }),
                status: BridgeChatActiveStatus::Running
            }
        ));
        assert!(matches!(
            &mapped.sources[0].lifecycle,
            BridgeChatSourceLifecycle::Active
        ));
        assert_eq!(
            mapped.sources[0].started,
            Some(BridgeChatFactPosition {
                effect_seq: 29,
                suborder: 1
            })
        );
        assert_eq!(mapped.sources[0].ended, None);
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
