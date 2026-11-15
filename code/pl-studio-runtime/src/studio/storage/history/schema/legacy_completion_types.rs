//! 原件索引 v1 的冻结迁移解码器；正常执行和读取禁止依赖。
use pl_core::chat::{ChatError, ChatKey};
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome,
};

/// Product-independent visibility and adjacent-run membership. Keys are opaque to Core.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(super) enum ChatReadHint {
    #[default]
    Hidden,
    Single,
    Adjacent {
        key: ChatKey,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct ChatRunPosition {
    pub start_seq: u64,
    pub ordinal: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct ChatRunSeed {
    pub seq: u64,
    pub hint: ChatReadHint,
    pub position: ChatRunPosition,
}

/// One cold snapshot's publication head and last visible record, never a retained group.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(super) struct ChatPublicationSeed {
    pub head_seq: u64,
    pub last_visible: Option<ChatRunSeed>,
}

impl ChatPublicationSeed {
    /// Checked allocation shared by publication and host migrations. Failure leaves the seed intact.
    pub fn advance(
        &mut self,
        hint: &ChatReadHint,
    ) -> Result<(u64, Option<ChatRunPosition>), ChatError> {
        let seq = self
            .head_seq
            .checked_add(1)
            .filter(|seq| *seq <= i64::MAX as u64)
            .ok_or(ChatError::SeqExhausted)?;
        let run = match hint {
            ChatReadHint::Hidden => None,
            ChatReadHint::Single => Some(ChatRunPosition {
                start_seq: seq,
                ordinal: 1,
            }),
            ChatReadHint::Adjacent { .. } => {
                let position = match self.last_visible.as_ref().filter(|last| last.hint == *hint) {
                    Some(last) => ChatRunPosition {
                        start_seq: last.position.start_seq,
                        ordinal: last
                            .position
                            .ordinal
                            .checked_add(1)
                            .filter(|ordinal| *ordinal <= i64::MAX as u64)
                            .ok_or(ChatError::SeqExhausted)?,
                    },
                    None => ChatRunPosition {
                        start_seq: seq,
                        ordinal: 1,
                    },
                };
                Some(position)
            }
        };
        if let Some(position) = run {
            self.last_visible = Some(ChatRunSeed {
                seq,
                hint: hint.clone(),
                position,
            });
        }
        self.head_seq = seq;
        Ok((seq, run))
    }
}

pub(super) fn native_read_hint_v1(query_class: &str, atom: &ChatAtom) -> ChatReadHint {
    match (query_class, atom.kind) {
        (class, _) if class != "conversation" => ChatReadHint::Hidden,
        (_, _) if matches!(atom.source, ChatSourceId::InboxMessage { .. }) => ChatReadHint::Single,
        (_, ChatAtomKind::Inference) => ChatReadHint::Hidden,
        (_, ChatAtomKind::Text) if atom.content_present == Some(false) => ChatReadHint::Hidden,
        (_, ChatAtomKind::TurnReceipt)
            if matches!(
                atom.lifecycle,
                ChatAtomLifecycle::Terminal {
                    outcome: ChatTerminalOutcome::Completed,
                    ..
                }
            ) =>
        {
            ChatReadHint::Hidden
        }
        (_, ChatAtomKind::ToolCall)
            if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) =>
        {
            ChatReadHint::Adjacent {
                key: ChatKey::new("native-background-results", "terminal").expect("fixed identity"),
            }
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
            let source = serde_json::to_string(&atom.source).expect("typed source");
            ChatReadHint::Adjacent {
                key: ChatKey::new("native-work-source", &source).expect("encoded source"),
            }
        }
        _ => ChatReadHint::Single,
    }
}
