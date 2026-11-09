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

fn summary(value: protocol::WorkSummary) -> BridgeWorkSummary {
    BridgeWorkSummary {
        total: value.total,
        terminal: value.terminal,
        running: value.running,
        waiting: value.waiting,
        failed: value.failed,
        cancelled: value.cancelled,
        transferred: value.transferred,
        started_at: value.started_at,
        finished_at: value.finished_at,
        duration_ms: value.duration_ms,
        thinking_summary: value.thinking_summary,
        thinking_content: value.thinking_content.map(chat::content_ref),
    }
}

fn body(value: protocol::DisplayBlockBody) -> BridgeDisplayBlockBody {
    match value {
        protocol::DisplayBlockBody::Work {
            summary: value,
            members,
        } => BridgeDisplayBlockBody::Work {
            summary: Box::new(summary(*value)),
            members: block_ref(members),
        },
        protocol::DisplayBlockBody::Single {
            atom,
            completion_id,
        } => BridgeDisplayBlockBody::Single {
            atom: Box::new(chat::atom(*atom)),
            completion_id,
        },
    }
}

pub(crate) fn live_window(value: protocol::LiveDisplayWindow) -> BridgeLiveDisplayWindow {
    BridgeLiveDisplayWindow {
        revision: value.revision,
        history_through: value.history_through,
        execution_present: value.execution_present,
        blocks: value
            .blocks
            .into_iter()
            .map(|block| BridgeLiveDisplayBlock {
                id: block.id,
                block_order: block.block_order,
                body: body(block.body),
                closing: block.closing,
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
                atom: chat::atom(member.atom),
                completion_id: member.completion_id,
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
            summary: Box::new(protocol::WorkSummary {
                total: 3,
                terminal: 2,
                running: 0,
                waiting: 1,
                failed: 1,
                cancelled: 0,
                transferred: 1,
                ..Default::default()
            }),
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
        assert!(mapped.live.is_none(), "split cut must not clear live");

        let mut live_only = cut();
        live_only.blocks.clear();
        live_only.from_pos = Some(4);
        live_only.live = Some(protocol::LiveDisplayWindow {
            revision: 8,
            history_through: 4,
            execution_present: false,
            blocks: vec![protocol::LiveDisplayBlock {
                id: "unresolved".into(),
                block_order: 11,
                body: work(),
                closing: true,
            }],
            older: Some("original-live-continuation".into()),
        });
        let mapped = batch(live_only).unwrap();
        assert!(mapped.blocks.is_empty());
        let live = mapped.live.unwrap();
        assert!(!live.execution_present);
        assert_eq!(live.older.as_deref(), Some("original-live-continuation"));
        assert!(live.blocks[0].closing);
        let BridgeDisplayBlockBody::Work { summary, members } = &live.blocks[0].body else {
            panic!("work body must not be inferred from completed content");
        };
        assert_eq!(protocol_block_ref(members.clone()), reference());
        assert_eq!(summary.total, 3);
        assert_eq!(summary.terminal, 2);
        assert_eq!(summary.waiting, 1);
        assert_eq!(summary.failed, 1);
        assert_eq!(summary.transferred, 1);
        assert_eq!(summary.started_at, None);
        assert_eq!(summary.finished_at, None);
        assert_eq!(summary.duration_ms, None);
    }

    #[test]
    fn unsupported_presentation_is_rejected_before_bridge_delivery() {
        let mut value = cut();
        value.presentation_version = 0;
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
                atom: atom(protocol::ChatAtomLifecycle::Terminal {
                    started: None,
                    ended: Some(protocol::ChatFactPosition {
                        effect_seq: 19,
                        suborder: 2,
                    }),
                    outcome: protocol::ChatTerminalOutcome::Cancelled,
                }),
                completion_id: None,
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
        assert!(member.completion_id.is_none());
        assert!(member.atom.completion_seq.is_none());
        assert!(member.atom.payload.is_none());
        assert!(matches!(
            member.atom.lifecycle,
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
