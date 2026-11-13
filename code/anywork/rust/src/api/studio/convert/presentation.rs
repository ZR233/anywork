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

pub(crate) fn live_window(value: protocol::LiveDisplayWindow) -> BridgeLiveDisplayWindow {
    BridgeLiveDisplayWindow {
        revision: value.revision,
        history_through: value.history_through,
        execution_present: value.execution_present,
        current_work_id: value.current_work_id,
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
        older: value.older,
    }
}

pub(crate) fn batch(value: protocol::TimelineBatch) -> Result<BridgeTimelineBatch, BridgeError> {
    value.validate()?;
    Ok(BridgeTimelineBatch {
        presentation_version: value.presentation_version,
        placement: chat::placement(value.placement),
        blocks: value
            .blocks
            .into_iter()
            .map(|block| BridgeDisplayBlock {
                id: block.id,
                history_pos: block.history_pos,
                body: body(block.body),
            })
            .collect(),
        before: value.before,
        from_pos: value.from_pos,
        through_pos: value.through_pos,
        live: value.live.map(live_window),
    })
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
                started_at: 1_700_000_000,
                finished_at: Some(1_700_000_125),
            },
            members: reference(),
        }
    }

    fn cut() -> protocol::TimelineBatch {
        protocol::TimelineBatch {
            presentation_version: protocol::PRESENTATION_VERSION,
            placement: protocol::ChatPlacement::Append,
            blocks: vec![protocol::DisplayBlock {
                id: "work".into(),
                history_pos: 4,
                body: work(),
            }],
            before: None,
            from_pos: Some(3),
            through_pos: 4,
            live: None,
        }
    }

    #[test]
    fn split_handoff_preserves_absent_live_and_presentation_positions() {
        let mapped = batch(cut()).unwrap();
        assert_eq!(mapped.placement, BridgeChatPlacement::Append);
        assert_eq!(mapped.from_pos, Some(3));
        assert_eq!(mapped.through_pos, 4);
        assert_eq!(mapped.blocks[0].history_pos, 4);
        let BridgeDisplayBlockBody::Work { timing, .. } = &mapped.blocks[0].body else {
            panic!("expected Work");
        };
        assert_eq!(timing.started_at, 1_700_000_000);
        assert_eq!(timing.finished_at, Some(1_700_000_125));
        assert!(mapped.live.is_none(), "split cut must not clear live");

        let mut live_only = cut();
        live_only.blocks.clear();
        live_only.from_pos = Some(4);
        live_only.live = Some(protocol::LiveDisplayWindow {
            revision: 8,
            history_through: 4,
            execution_present: false,
            current_work_id: None,
            blocks: vec![protocol::LiveDisplayBlock {
                has_unfinished_members: false,
                thinking_summary: None,
                id: "unresolved".into(),
                block_order: 11,
                source: Some(protocol::ChatSourceId::ForegroundTurn {
                    turn_id: "original-work-turn".into(),
                }),
                body: work(),
                state: protocol::DisplayBlockState::Sealed,
            }],
            older: Some("original-live-continuation".into()),
        });
        let mapped = batch(live_only).unwrap();
        assert!(mapped.blocks.is_empty());
        let live = mapped.live.unwrap();
        assert!(!live.execution_present);
        assert_eq!(live.older.as_deref(), Some("original-live-continuation"));
        assert_eq!(live.blocks[0].state, BridgeDisplayBlockState::Sealed);
        assert!(matches!(&live.blocks[0].source,
            Some(BridgeChatSourceId::ForegroundTurn { turn_id }) if turn_id == "original-work-turn"));
        let BridgeDisplayBlockBody::Work { timing, members } = &live.blocks[0].body else {
            panic!("work body must not be inferred from completed content");
        };
        assert_eq!(protocol_block_ref(members.clone()), reference());

        assert_eq!(timing.started_at, 1_700_000_000);
        assert_eq!(timing.finished_at, Some(1_700_000_125));
    }

    #[test]
    fn live_source_preserves_unknown_and_independent_ownership() {
        let mut window = protocol::LiveDisplayWindow {
            revision: 1,
            history_through: 0,
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
        let mapped = live_window(window.clone());
        assert!(mapped.blocks[0].source.is_none());
        assert_eq!(mapped.current_work_id, window.current_work_id);
        window.blocks[0].source = Some(protocol::ChatSourceId::Input {
            input_id: "independent-input".into(),
        });
        assert!(matches!(&live_window(window).blocks[0].source,
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

    #[test]
    fn unsupported_presentation_is_rejected_before_bridge_delivery() {
        let mut value = cut();
        value.presentation_version = 2;
        let error = batch(value).unwrap_err();
        assert_eq!(error.code, BridgeErrorCode::Protocol);
        let details: serde_json::Value =
            serde_json::from_str(error.details_json.as_deref().unwrap()).unwrap();
        assert_eq!(details["reason"], "protocolVersionMismatch");
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
