//! Independent history visibility classification.

use crate::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome,
};

pub(crate) fn work(atom: &ChatAtom) -> bool {
    let background_tool = atom.kind == ChatAtomKind::ToolCall
        && matches!(atom.source, ChatSourceId::BackgroundResult { .. })
        && atom
            .tool
            .as_ref()
            .is_some_and(|tool| tool.name != pl_tool::file_display::TOOL_SHOW_FILES);
    background_tool
        || (matches!(
            atom.kind,
            ChatAtomKind::Reasoning
                | ChatAtomKind::ToolCall
                | ChatAtomKind::FileChange
                | ChatAtomKind::Skill
        ) && atom.delivery != ChatDeliveryKind::Independent)
}

pub(crate) fn hidden(atom: &ChatAtom) -> bool {
    !matches!(atom.source, ChatSourceId::InboxMessage { .. })
        && (atom.kind == ChatAtomKind::Inference
            || (atom.kind == ChatAtomKind::TurnReceipt
                && matches!(
                    atom.lifecycle,
                    ChatAtomLifecycle::Terminal {
                        outcome: ChatTerminalOutcome::Completed,
                        ..
                    }
                )))
}
