//! Mechanical mappings of immutable completed records and activity snapshots.
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
        BridgeChatScope::Run { reference } => protocol::ChatScope::Run {
            reference: protocol::CompletionRunRef {
                database_id: reference.database_id,
                index_version: reference.index_version,
                start_seq: reference.start_seq,
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

pub(crate) fn completed(value: protocol::CompletedEntry) -> BridgeCompletedEntry {
    BridgeCompletedEntry {
        record_id: value.record_id,
        completion_seq: value.completion_seq,
        run: value.run.map(|run| BridgeCompletionRunPosition {
            start_seq: run.start_seq,
            ordinal: run.ordinal,
        }),
        main_presentation: match value.main_presentation {
            protocol::MainPresentation::Hidden => BridgeMainPresentation::Hidden,
            protocol::MainPresentation::Single => BridgeMainPresentation::Single,
            protocol::MainPresentation::ForegroundWork => BridgeMainPresentation::ForegroundWork,
            protocol::MainPresentation::BackgroundResults => {
                BridgeMainPresentation::BackgroundResults
            }
        },
        atom: atom(value.atom),
    }
}

pub(crate) fn batch(value: protocol::ChatBatch) -> BridgeChatBatch {
    BridgeChatBatch {
        placement: match value.placement {
            protocol::ChatPlacement::Set => BridgeChatPlacement::Set,
            protocol::ChatPlacement::Prepend => BridgeChatPlacement::Prepend,
            protocol::ChatPlacement::Append => BridgeChatPlacement::Append,
        },
        entries: value.entries.into_iter().map(completed).collect(),
        before: value.before,
        from_seq: value.from_seq,
        through_seq: value.through_seq,
    }
}

pub(crate) fn activity(value: protocol::ActivitySnapshot) -> BridgeActivitySnapshot {
    BridgeActivitySnapshot {
        revision: value.revision,
        completed_through: value.completed_through,
        execution_present: value.execution_present,
        entries: value
            .entries
            .into_iter()
            .map(|entry| BridgeActivityEntry {
                identity: match entry.identity {
                    protocol::ActivityIdentity::ModelPart { atom_id } => {
                        BridgeActivityIdentity::ModelPart { atom_id }
                    }
                    protocol::ActivityIdentity::ForegroundTool { call_id } => {
                        BridgeActivityIdentity::ForegroundTool { call_id }
                    }
                    protocol::ActivityIdentity::BackgroundTool { call_id } => {
                        BridgeActivityIdentity::BackgroundTool { call_id }
                    }
                    protocol::ActivityIdentity::Other { domain, id } => {
                        BridgeActivityIdentity::Other { domain, id }
                    }
                },
                atom: atom(entry.atom),
            })
            .collect(),
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
        document: value.document.map(content_ref),
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

    fn atom(lifecycle: protocol::ChatAtomLifecycle) -> protocol::ChatAtom {
        protocol::ChatAtom {
            id: "atom-id".into(),
            completion_item_id: Some("record-id".into()),
            completion_seq: Some(7),
            source: protocol::ChatSourceId::ForegroundTurn {
                turn_id: "turn-id".into(),
            },
            source_state: None,
            source_order: Some(2),
            kind: protocol::ChatAtomKind::Text,
            delivery: protocol::ChatDeliveryKind::Foreground,
            lifecycle,
            turn_id: Some("turn-id".into()),
            attempt_id: Some("attempt-id".into()),
            tool: None,
            wait: None,
            text_channel: Some(protocol::ThreadTextChannel::Final),
            started_at: None,
            finished_at: None,
            content_present: Some(true),
            contents: Vec::new(),
            payload: Some(protocol::PayloadData::Deferred {
                reference: protocol::ContentRef {
                    database_id: "database".into(),
                    target: protocol::ContentTarget::ItemPayload {
                        item_id: "record-id".into(),
                    },
                },
                byte_length: 4096,
            }),
        }
    }

    #[test]
    fn run_scope_and_completed_batch_are_mechanically_mapped() {
        let run = BridgeCompletionRunRef {
            database_id: "database".into(),
            index_version: protocol::COMPLETED_READ_INDEX_VERSION,
            start_seq: 7,
        };
        assert_eq!(
            scope(BridgeChatScope::Run {
                reference: run.clone()
            }),
            protocol::ChatScope::Run {
                reference: protocol::CompletionRunRef {
                    database_id: run.database_id,
                    index_version: run.index_version,
                    start_seq: run.start_seq,
                }
            }
        );
        let mapped = batch(protocol::ChatBatch {
            placement: protocol::ChatPlacement::Append,
            entries: vec![protocol::CompletedEntry {
                record_id: "record-id".into(),
                completion_seq: 7,
                run: Some(protocol::CompletionRunPosition {
                    start_seq: 3,
                    ordinal: 2,
                }),
                main_presentation: protocol::MainPresentation::ForegroundWork,
                atom: atom(protocol::ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: None,
                    outcome: protocol::ChatTerminalOutcome::Completed,
                }),
            }],
            before: None,
            from_seq: Some(6),
            through_seq: 7,
        });
        assert_eq!(mapped.placement, BridgeChatPlacement::Append);
        assert_eq!(mapped.from_seq, Some(6));
        assert_eq!(mapped.through_seq, 7);
        assert_eq!(mapped.entries.len(), 1);
        let entry = &mapped.entries[0];
        assert_eq!(entry.record_id, "record-id");
        assert_eq!(entry.completion_seq, 7);
        assert_eq!(
            entry.run,
            Some(BridgeCompletionRunPosition {
                start_seq: 3,
                ordinal: 2
            })
        );
        assert_eq!(
            entry.main_presentation,
            BridgeMainPresentation::ForegroundWork
        );
        assert_eq!(entry.atom.completion_item_id.as_deref(), Some("record-id"));
        assert_eq!(entry.atom.completion_seq, Some(7));
    }

    #[test]
    fn inbox_message_source_preserves_both_typed_identity_parts() {
        let source = source_id(protocol::ChatSourceId::InboxMessage {
            source_id: "source-123".into(),
            message_id: "message-456".into(),
        });
        assert!(matches!(
            source,
            BridgeChatSourceId::InboxMessage { source_id, message_id }
                if source_id == "source-123" && message_id == "message-456"
        ));
    }

    #[test]
    fn business_refs_preserve_empty_and_nonempty_heads() {
        assert_eq!(
            business_refs(protocol::ThreadBusinessRefs::empty()),
            BridgeThreadBusinessRefs {
                plan: None,
                interactions: None,
            }
        );

        let mapped = business_refs(protocol::ThreadBusinessRefs {
            plan: Some(protocol::CurrentPlanHead {
                revision: 12,
                phase: protocol::AgentSessionPlanPhase::Approved,
                document: None,
            }),
            interactions: Some(protocol::CurrentCollectionRef {
                database_id: "db-1".into(),
                collection: "interactions".into(),
                revision: 8,
            }),
        });
        assert_eq!(mapped.plan.as_ref().map(|plan| plan.revision), Some(12));
        assert_eq!(
            mapped.plan.as_ref().map(|plan| plan.phase),
            Some(BridgePlanPhase::Approved)
        );
        assert_eq!(
            mapped.interactions,
            Some(BridgeCurrentCollectionRef {
                database_id: "db-1".into(),
                collection: "interactions".into(),
                revision: 8,
            })
        );
    }

    #[test]
    fn activity_keeps_typed_identity() {
        let snapshot = activity(protocol::ActivitySnapshot {
            revision: 11,
            completed_through: 7,
            execution_present: true,
            entries: vec![protocol::ActivityEntry {
                identity: protocol::ActivityIdentity::ForegroundTool {
                    call_id: "call-1".into(),
                },
                atom: atom(protocol::ChatAtomLifecycle::Active {
                    started: None,
                    status: protocol::ChatActiveStatus::Running,
                }),
            }],
        });
        assert_eq!(snapshot.revision, 11);
        assert_eq!(snapshot.completed_through, 7);
        assert!(snapshot.execution_present);
        assert!(matches!(
            &snapshot.entries[0].identity,
            BridgeActivityIdentity::ForegroundTool { call_id } if call_id == "call-1"
        ));
    }

    #[test]
    fn content_references_round_trip_without_reinterpreting_owner_identity() {
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
    fn opaque_atom_payload_and_source_cut_survive_completed_entry_mapping() {
        let bytes = vec![0, 255, b'{', b'}'];
        let mut original = atom(protocol::ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: protocol::ChatTerminalOutcome::Transferred,
        });
        original.id = "member-id".into();
        original.completion_seq = Some(12);
        original.source = protocol::ChatSourceId::BackgroundResult {
            message_id: "source-id".into(),
        };
        original.source_state = Some(protocol::ChatSourceState {
            source: protocol::ChatSourceId::BackgroundResult {
                message_id: "source-id".into(),
            },
            lifecycle: protocol::ChatSourceLifecycle::Active,
            started: Some(protocol::ChatFactPosition {
                effect_seq: 8,
                suborder: 2,
            }),
            ended: None,
        });
        original.source_order = None;
        original.kind = protocol::ChatAtomKind::ToolCall;
        original.delivery = protocol::ChatDeliveryKind::BackgroundHandoff;
        original.payload = Some(protocol::PayloadData::Inline {
            bytes: bytes.clone(),
        });
        let mapped = batch(protocol::ChatBatch {
            placement: protocol::ChatPlacement::Prepend,
            entries: vec![protocol::CompletedEntry {
                record_id: "record-id".into(),
                completion_seq: 12,
                run: None,
                main_presentation: protocol::MainPresentation::Hidden,
                atom: original,
            }],
            before: Some("opaque-cursor".into()),
            from_seq: None,
            through_seq: 12,
        });
        assert_eq!(mapped.before.as_deref(), Some("opaque-cursor"));
        assert_eq!(mapped.from_seq, None);
        assert_eq!(mapped.through_seq, 12);
        let entry = &mapped.entries[0];
        assert_eq!(entry.main_presentation, BridgeMainPresentation::Hidden);
        assert_eq!(entry.atom.id, "member-id");
        assert_eq!(entry.atom.completion_seq, Some(12));
        assert_eq!(entry.atom.source_order, None);
        let source = entry.atom.source_state.as_ref().expect("typed source cut");
        assert!(matches!(
            &source.lifecycle,
            BridgeChatSourceLifecycle::Active
        ));
        assert_eq!(
            source.started,
            Some(BridgeChatFactPosition {
                effect_seq: 8,
                suborder: 2,
            })
        );
        assert!(matches!(
            &entry.atom.payload,
            Some(BridgePayloadData::Inline { bytes: mapped }) if *mapped == bytes
        ));
    }
}
