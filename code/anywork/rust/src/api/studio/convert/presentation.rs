//! Mechanical presentation mappings; membership and cuts belong to the runtime owner.

use pl_protocol as protocol;

use super::chat;
use crate::api::studio::types::*;

pub(crate) fn protocol_block_ref(value: BridgeDisplayBlockRef) -> protocol::DisplayBlockRef {
    protocol::DisplayBlockRef {
        database_id: value.database_id,
        block_id: value.block_id,
    }
}

pub(crate) fn block_ref(value: protocol::DisplayBlockRef) -> BridgeDisplayBlockRef {
    BridgeDisplayBlockRef {
        database_id: value.database_id,
        block_id: value.block_id,
    }
}

pub(crate) fn member_window(value: BridgeDisplayMemberWindow) -> protocol::DisplayMemberWindow {
    match value {
        BridgeDisplayMemberWindow::Latest => protocol::DisplayMemberWindow::Latest,
        BridgeDisplayMemberWindow::Before { member_order } => {
            protocol::DisplayMemberWindow::Before { member_order }
        }
    }
}

fn timing(value: protocol::WorkTiming) -> BridgeWorkTiming {
    BridgeWorkTiming {
        started_at: value.started_at,
        finished_at: value.finished_at,
    }
}

fn record(value: protocol::DisplayRecord) -> BridgeDisplayRecord {
    BridgeDisplayRecord {
        atom: chat::atom(value.atom),
        start_fact: value.start_fact.map(chat::fact_position),
        end_fact: value.end_fact.map(chat::fact_position),
        content_source: match value.content_source {
            protocol::DisplayContentSource::CurrentAtom => BridgeDisplayContentSource::CurrentAtom,
            protocol::DisplayContentSource::FrozenObservation {
                captured_at,
                available,
            } => BridgeDisplayContentSource::FrozenObservation {
                captured_at,
                available,
            },
            protocol::DisplayContentSource::CompletedOriginal { completion_id } => {
                BridgeDisplayContentSource::CompletedOriginal { completion_id }
            }
        },
    }
}

fn body(value: protocol::DisplayBlockBody) -> BridgeDisplayBlockBody {
    match value {
        protocol::DisplayBlockBody::Work {
            timing: value,
            members,
        } => BridgeDisplayBlockBody::Work {
            timing: timing(value),
            members: block_ref(members),
        },
        protocol::DisplayBlockBody::Single {
            record: value,
            visibility,
        } => BridgeDisplayBlockBody::Single {
            record: Box::new(record(*value)),
            visibility: match visibility {
                protocol::SingleVisibility::Content => BridgeSingleVisibility::Content,
                protocol::SingleVisibility::FinalEmptyAfterContent => {
                    BridgeSingleVisibility::FinalEmptyAfterContent
                }
            },
        },
    }
}

pub(crate) fn member_page(value: protocol::DisplayMemberPage) -> BridgeDisplayMemberPage {
    BridgeDisplayMemberPage {
        block: block_ref(value.block),
        revision: value.revision,
        sealed: value.sealed,
        entries: value
            .entries
            .into_iter()
            .map(|member| BridgeDisplayMemberHead {
                member_key: member.member_key,
                member_order: member.member_order,
                record: record(member.record),
            })
            .collect(),
        before: value.before,
    }
}

pub(crate) fn open_timeline(value: protocol::OpenTimeline) -> BridgeOpenTimeline {
    BridgeOpenTimeline {
        reader_id: value.reader_id,
        presentation_version: value.presentation_version,
        reader_protocol_version: value.reader_protocol_version,
        initial_cursor: value.initial_cursor.0,
    }
}
fn display_blocks(values: Vec<protocol::DisplayBlock>) -> Vec<BridgeDisplayBlock> {
    values
        .into_iter()
        .map(|value| BridgeDisplayBlock {
            id: value.id,
            block_order: value.block_order,
            body: body(value.body),
        })
        .collect()
}
pub(crate) fn tail_snapshot(value: protocol::TailSnapshot) -> BridgeTailSnapshot {
    BridgeTailSnapshot {
        revision: value.revision,
        layout_revision: value.layout_revision,
        ready_frontier: value.ready_frontier,
        execution_present: value.execution_present,
        current_work_id: value.current_work_id,
        older: value.older,
        blocks: value
            .blocks
            .into_iter()
            .map(|block| BridgeLiveDisplayBlock {
                id: block.id,
                block_order: block.block_order,
                source: block.source.map(chat::source_id),
                body: body(block.body),
                has_unfinished_members: block.has_unfinished_members,
                thinking_summary: block.thinking_summary,
                state: match block.state {
                    protocol::DisplayBlockState::Open => BridgeDisplayBlockState::Open,
                    protocol::DisplayBlockState::Sealed => BridgeDisplayBlockState::Sealed,
                },
            })
            .collect(),
    }
}
pub(crate) fn view_update(value: protocol::ViewUpdate) -> BridgeViewUpdate {
    BridgeViewUpdate {
        presentation_version: value.presentation_version,
        reader_protocol_version: value.reader_protocol_version,
        after: value.after.0,
        next: value.next.0,
        history: BridgeHistoryDelta {
            placement: match value.history.placement {
                protocol::HistoryPlacement::Set => BridgeHistoryPlacement::Set,
                protocol::HistoryPlacement::Append => BridgeHistoryPlacement::Append,
            },
            from_order: value.history.from_order,
            through_order: value.history.through_order,
            blocks: display_blocks(value.history.blocks),
            before: value.history.before,
        },
        tail: match value.tail {
            protocol::TailUpdate::Keep {} => BridgeTailUpdate::Keep,
            protocol::TailUpdate::Replace { snapshot } => BridgeTailUpdate::Replace {
                snapshot: tail_snapshot(snapshot),
            },
            protocol::TailUpdate::Status {
                base_layout_revision,
                revision,
                current_work_id,
                thinking_summary,
            } => BridgeTailUpdate::Status {
                base_layout_revision,
                revision,
                current_work_id,
                thinking_summary,
            },
        },
    }
}
pub(crate) fn timeline_page(value: protocol::TimelinePage) -> BridgeTimelinePage {
    BridgeTimelinePage {
        presentation_version: value.presentation_version,
        database_id: value.database_id,
        ceiling: value.ceiling,
        blocks: display_blocks(value.blocks),
        before: value.before,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reference() -> protocol::DisplayBlockRef {
        protocol::DisplayBlockRef {
            database_id: "database".into(),
            block_id: "work".into(),
        }
    }

    fn work() -> protocol::DisplayBlockBody {
        protocol::DisplayBlockBody::Work {
            timing: protocol::WorkTiming {
                started_at: Some(1_700_000_000),
                finished_at: Some(1_700_000_125),
            },
            members: reference(),
        }
    }

    #[test]
    fn cursor_handoff_preserves_keep_and_independent_versions() {
        let mapped = view_update(protocol::ViewUpdate {
            presentation_version: 6,
            reader_protocol_version: 1,
            after: protocol::ViewCursor("C0".into()),
            next: protocol::ViewCursor("C1".into()),
            history: protocol::HistoryDelta {
                placement: protocol::HistoryPlacement::Append,
                from_order: Some(3),
                through_order: 4,
                before: None,
                blocks: vec![protocol::DisplayBlock {
                    id: "work".into(),
                    block_order: 4,
                    body: work(),
                }],
            },
            tail: protocol::TailUpdate::Keep {},
        });
        assert_eq!(mapped.after, "C0");
        assert_eq!(mapped.next, "C1");
        assert!(matches!(mapped.tail, BridgeTailUpdate::Keep));
        assert_eq!(mapped.history.from_order, Some(3));
        let BridgeDisplayBlockBody::Work { timing, .. } = &mapped.history.blocks[0].body else {
            panic!("Work")
        };
        assert_eq!(timing.finished_at, Some(1_700_000_125));
    }

    #[test]
    fn live_source_preserves_unknown_and_independent_ownership() {
        let mut window = protocol::TailSnapshot {
            revision: 1,
            layout_revision: 1,
            ready_frontier: 0,
            execution_present: false,
            current_work_id: Some("not-an-encoded-turn".into()),
            blocks: vec![protocol::LiveDisplayBlock {
                has_unfinished_members: false,
                thinking_summary: None,
                id: "not-an-encoded-turn".into(),
                block_order: 1,
                source: None,
                body: work(),
                state: protocol::DisplayBlockState::Open,
            }],
            older: None,
        };
        let mapped = tail_snapshot(window.clone());
        assert!(mapped.blocks[0].source.is_none());
        assert_eq!(mapped.current_work_id, window.current_work_id);
        window.blocks[0].source = Some(protocol::ChatSourceId::Input {
            input_id: "independent-input".into(),
        });
        assert!(matches!(&tail_snapshot(window).blocks[0].source,
            Some(BridgeChatSourceId::Input { input_id }) if input_id == "independent-input"));
    }

    #[test]
    fn single_visibility_keeps_authoritative_empty_content_typed() {
        for (visibility, expected) in [
            (
                protocol::SingleVisibility::Content,
                BridgeSingleVisibility::Content,
            ),
            (
                protocol::SingleVisibility::FinalEmptyAfterContent,
                BridgeSingleVisibility::FinalEmptyAfterContent,
            ),
        ] {
            let mapped = body(protocol::DisplayBlockBody::Single {
                record: Box::new(protocol::DisplayRecord {
                    atom: atom(protocol::ChatAtomLifecycle::Terminal {
                        started: None,
                        ended: None,
                        outcome: protocol::ChatTerminalOutcome::Completed,
                    }),
                    start_fact: None,
                    end_fact: None,
                    content_source: protocol::DisplayContentSource::CompletedOriginal {
                        completion_id: "empty".into(),
                    },
                }),
                visibility,
            });
            let BridgeDisplayBlockBody::Single { visibility, record } = mapped else {
                panic!("expected Single");
            };
            assert_eq!(visibility, expected);
            assert!(record.atom.payload.is_none());
        }
    }

    fn atom(lifecycle: protocol::ChatAtomLifecycle) -> protocol::ChatAtom {
        protocol::ChatAtom {
            id: "reasoning".into(),
            completion_item_id: None,
            completion_seq: None,
            source: protocol::ChatSourceId::ForegroundTurn {
                turn_id: "turn".into(),
            },
            source_state: None,
            source_order: Some(1),
            kind: protocol::ChatAtomKind::Reasoning,
            delivery: protocol::ChatDeliveryKind::Foreground,
            lifecycle,
            turn_id: Some("turn".into()),
            attempt_id: None,
            tool: None,
            wait: None,
            text_channel: None,
            content_present: Some(false),
            started_at: None,
            finished_at: None,
            contents: Vec::new(),
            payload: None,
        }
    }

    #[test]
    fn member_page_keeps_real_interruption_without_fabricating_completion() {
        let mapped = member_page(protocol::DisplayMemberPage {
            block: reference(),
            revision: 9,
            sealed: true,
            entries: vec![protocol::DisplayMemberHead {
                member_key: "original-member".into(),
                member_order: 7,
                record: protocol::DisplayRecord {
                    atom: atom(protocol::ChatAtomLifecycle::Terminal {
                        started: None,
                        ended: Some(protocol::ChatFactPosition {
                            effect_seq: 19,
                            suborder: 2,
                        }),
                        outcome: protocol::ChatTerminalOutcome::Cancelled,
                    }),
                    start_fact: None,
                    end_fact: Some(protocol::ChatFactPosition {
                        effect_seq: 19,
                        suborder: 2,
                    }),
                    content_source: protocol::DisplayContentSource::FrozenObservation {
                        captured_at: None,
                        available: true,
                    },
                },
            }],
            before: Some(7),
        });
        assert_eq!(protocol_block_ref(mapped.block), reference());
        assert_eq!(mapped.revision, 9);
        assert!(mapped.sealed);
        assert_eq!(mapped.before, Some(7));
        let member = &mapped.entries[0];
        assert_eq!(member.member_key, "original-member");
        assert_eq!(member.member_order, 7);
        assert!(matches!(
            member.record.content_source,
            BridgeDisplayContentSource::FrozenObservation {
                available: true,
                ..
            }
        ));
        assert!(member.record.start_fact.is_none());
        assert!(matches!(
            member.record.end_fact,
            Some(BridgeChatFactPosition {
                effect_seq: 19,
                suborder: 2
            })
        ));
        assert!(member.record.atom.completion_seq.is_none());
        assert!(member.record.atom.payload.is_none());
        assert!(matches!(
            member.record.atom.lifecycle,
            BridgeChatAtomLifecycle::Terminal {
                ended: Some(BridgeChatFactPosition {
                    effect_seq: 19,
                    suborder: 2
                }),
                outcome: BridgeChatTerminalOutcome::Cancelled,
                ..
            }
        ));
        assert_eq!(
            member_window(BridgeDisplayMemberWindow::Before { member_order: 7 }),
            protocol::DisplayMemberWindow::Before { member_order: 7 }
        );
        assert_eq!(
            member_window(BridgeDisplayMemberWindow::Latest),
            protocol::DisplayMemberWindow::Latest
        );
    }
}
