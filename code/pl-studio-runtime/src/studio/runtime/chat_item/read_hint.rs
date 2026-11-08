//! Native index version 1. Historical classification changes require a named migration.
use pl_core::chat::{ChatKey, ChatReadHint};
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome,
    MainPresentation,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::studio) struct NativeReadClass {
    pub hint: ChatReadHint,
    pub main_presentation: MainPresentation,
}

pub(in crate::studio) fn native_read_class_v1(
    query_class: &str,
    atom: &ChatAtom,
) -> NativeReadClass {
    let (hint, main_presentation) = match (query_class, atom.kind) {
        (class, _) if class != "conversation" => (ChatReadHint::Hidden, MainPresentation::Hidden),
        (_, _) if matches!(atom.source, ChatSourceId::InboxMessage { .. }) => {
            (ChatReadHint::Single, MainPresentation::Single)
        }
        (_, ChatAtomKind::Inference) => (ChatReadHint::Hidden, MainPresentation::Hidden),
        (_, ChatAtomKind::Text) if atom.content_present == Some(false) => {
            (ChatReadHint::Hidden, MainPresentation::Hidden)
        }
        (_, ChatAtomKind::TurnReceipt)
            if matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal {
                    outcome: ChatTerminalOutcome::Completed,
                    ..
                }
            ) =>
        {
            (ChatReadHint::Hidden, MainPresentation::Hidden)
        }
        (_, ChatAtomKind::ToolCall)
            if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) =>
        {
            (
                ChatReadHint::Adjacent {
                    key: ChatKey::new("native-background-results", "terminal")
                        .expect("fixed nonempty native identity"),
                },
                MainPresentation::BackgroundResults,
            )
        }
        (
            _,
            ChatAtomKind::Reasoning
            | ChatAtomKind::ToolCall
            | ChatAtomKind::FileChange
            | ChatAtomKind::Skill,
        ) if matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
            && atom.delivery != ChatDeliveryKind::Independent =>
        {
            // Serialize the entire typed source, including its discriminant. ChatSourceId has
            // only string fields; encoding this closed type cannot fail.
            let source = serde_json::to_string(&atom.source).expect("typed native source encoding");
            (
                ChatReadHint::Adjacent {
                    key: ChatKey::new("native-work-source", &source)
                        .expect("nonempty encoded native source"),
                },
                MainPresentation::ForegroundWork,
            )
        }
        _ => (ChatReadHint::Single, MainPresentation::Single),
    };
    NativeReadClass {
        hint,
        main_presentation,
    }
}

pub(in crate::studio) fn native_read_hint_v1(query_class: &str, atom: &ChatAtom) -> ChatReadHint {
    native_read_class_v1(query_class, atom).hint
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> ChatAtom {
        ChatAtom {
            id: "原子".into(),
            completion_item_id: Some("完成".into()),
            content_present: Some(true),
            completion_seq: None,
            source: ChatSourceId::ForegroundTurn {
                turn_id: "前台:α".into(),
            },
            source_state: None,
            source_order: Some(1),
            kind: ChatAtomKind::ToolCall,
            delivery: ChatDeliveryKind::Foreground,
            lifecycle: ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: ChatTerminalOutcome::Completed,
            },
            turn_id: Some("前台:α".into()),
            attempt_id: None,
            tool: None,
            wait: None,
            text_channel: None,
            started_at: None,
            finished_at: None,
            contents: Vec::new(),
            payload: None,
        }
    }

    #[test]
    fn native_classification_keeps_opaque_source_and_presentation_in_one_decision() {
        let mut atom = fixture();
        let foreground = native_read_class_v1("conversation", &atom);
        assert_eq!(
            foreground.main_presentation,
            MainPresentation::ForegroundWork
        );
        assert!(matches!(foreground.hint, ChatReadHint::Adjacent { .. }));
        atom.delivery = ChatDeliveryKind::BackgroundHandoff;
        assert_eq!(native_read_class_v1("conversation", &atom), foreground);
        atom.delivery = ChatDeliveryKind::Independent;
        assert_eq!(
            native_read_hint_v1("conversation", &atom),
            ChatReadHint::Single
        );
        atom = fixture();
        atom.source = ChatSourceId::ForegroundTurn {
            turn_id: "前台:β".into(),
        };
        assert_ne!(native_read_hint_v1("conversation", &atom), foreground.hint);
        atom.source = ChatSourceId::BackgroundResult {
            message_id: "X".into(),
        };
        let background = native_read_class_v1("conversation", &atom);
        assert_eq!(
            background.main_presentation,
            MainPresentation::BackgroundResults
        );
        atom.source = ChatSourceId::BackgroundResult {
            message_id: "Y".into(),
        };
        assert_eq!(native_read_class_v1("conversation", &atom), background);
        assert_ne!(background.hint, foreground.hint);
        atom.source = ChatSourceId::InboxMessage {
            source_id: "external".into(),
            message_id: "received".into(),
        };
        let inbox = native_read_class_v1("conversation", &atom);
        assert_eq!(inbox.hint, ChatReadHint::Single);
        assert_eq!(inbox.main_presentation, MainPresentation::Single);
        assert_eq!(native_read_hint_v1("internal", &atom), ChatReadHint::Hidden);
    }

    #[test]
    fn hidden_diagnostics_empty_text_and_success_receipts_do_not_hide_public_independent_facts() {
        let mut atom = fixture();
        assert_eq!(native_read_hint_v1("internal", &atom), ChatReadHint::Hidden);
        atom.kind = ChatAtomKind::Inference;
        assert_eq!(
            native_read_hint_v1("conversation", &atom),
            ChatReadHint::Hidden
        );
        atom.kind = ChatAtomKind::Text;
        atom.content_present = Some(false);
        assert_eq!(
            native_read_hint_v1("conversation", &atom),
            ChatReadHint::Hidden
        );
        // Producer proves attachment-only text as content_present=true.
        atom.content_present = Some(true);
        assert_eq!(
            native_read_hint_v1("conversation", &atom),
            ChatReadHint::Single
        );
        atom.kind = ChatAtomKind::TurnReceipt;
        assert_eq!(
            native_read_hint_v1("conversation", &atom),
            ChatReadHint::Hidden
        );
        for outcome in [ChatTerminalOutcome::Failed, ChatTerminalOutcome::Cancelled] {
            atom.lifecycle = ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome,
            };
            assert_eq!(
                native_read_hint_v1("conversation", &atom),
                ChatReadHint::Single
            );
        }
        for kind in [
            ChatAtomKind::Plan,
            ChatAtomKind::Interaction,
            ChatAtomKind::Compaction,
            ChatAtomKind::Raw,
            ChatAtomKind::Agent,
            ChatAtomKind::Unknown,
            ChatAtomKind::Input,
        ] {
            atom.kind = kind;
            assert_eq!(
                native_read_hint_v1("conversation", &atom),
                ChatReadHint::Single
            );
        }
    }
}
