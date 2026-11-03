//! Product provenance derived from typed facts, never from a frozen/deferred payload.
use pl_protocol::*;

pub(crate) fn atom(item: &ThreadItem) -> ChatAtom {
    let kind = match item.state() {
        ThreadItemState::Text(text) if text.channel() == ThreadTextChannel::User => {
            ChatAtomKind::Input
        }
        ThreadItemState::Text(_) => ChatAtomKind::Text,
        ThreadItemState::Thinking(_) => ChatAtomKind::Reasoning,
        ThreadItemState::Tool(tool)
            if tool.user_input().is_some()
                && tool.invocation().name() == crate::plan_tool::TOOL_PLAN_SUBMIT =>
        {
            ChatAtomKind::Plan
        }
        ThreadItemState::Tool(tool) if tool.user_input().is_some() => ChatAtomKind::Interaction,
        ThreadItemState::Tool(_) => ChatAtomKind::ToolCall,
        ThreadItemState::File(_) => ChatAtomKind::FileChange,
        ThreadItemState::Skill(_) => ChatAtomKind::Skill,
        ThreadItemState::Turn(_) => ChatAtomKind::TurnReceipt,
        ThreadItemState::ContextCompaction(_) => ChatAtomKind::Compaction,
        ThreadItemState::Raw(_) | ThreadItemState::Agent(_) | ThreadItemState::Inference(_) => {
            ChatAtomKind::Unknown
        }
    };
    let source = if kind == ChatAtomKind::Input {
        ChatSourceId::Input {
            input_id: item.id.clone(),
        }
    } else if !item.turn_id.is_empty() {
        ChatSourceId::ForegroundTurn {
            turn_id: item.turn_id.clone(),
        }
    } else {
        ChatSourceId::Receipt {
            receipt_id: item.id.clone(),
        }
    };
    let content_outcome = |lifecycle: &ThreadContentLifecycle| match lifecycle {
        ThreadContentLifecycle::Failed(_) => ChatTerminalOutcome::Failed,
        ThreadContentLifecycle::Cancelled(_) => ChatTerminalOutcome::Cancelled,
        _ => ChatTerminalOutcome::Completed,
    };
    let outcome = match item.state() {
        ThreadItemState::Text(text) => content_outcome(text.lifecycle()),
        ThreadItemState::Thinking(thinking) => content_outcome(thinking.lifecycle()),
        ThreadItemState::Tool(tool)
            if tool.user_input().is_some_and(|input| {
                matches!(input.state(), ThreadToolUserInputState::Cancelled)
            }) =>
        {
            ChatTerminalOutcome::Cancelled
        }
        ThreadItemState::Tool(tool) => match tool.state() {
            ThreadToolState::Failed(_) | ThreadToolState::Denied(_) => ChatTerminalOutcome::Failed,
            ThreadToolState::Cancelled(_) | ThreadToolState::Interrupted(_) => {
                ChatTerminalOutcome::Cancelled
            }
            _ => ChatTerminalOutcome::Completed,
        },
        ThreadItemState::Turn(turn) => match turn.state() {
            TurnState::Failed(_) => ChatTerminalOutcome::Failed,
            TurnState::Cancelled(_) => ChatTerminalOutcome::Cancelled,
            _ => ChatTerminalOutcome::Completed,
        },
        _ => ChatTerminalOutcome::Completed,
    };
    ChatAtom {
        id: item.id.clone(),
        completion_item_id: None,
        completion_seq: None,
        source,
        source_state: None,
        source_order: (item.ordinal > 0).then_some(item.ordinal),
        kind,
        delivery: ChatDeliveryKind::Foreground,
        lifecycle: if item.is_terminal() {
            ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome,
            }
        } else {
            ChatAtomLifecycle::Active {
                started: None,
                status: ChatActiveStatus::Running,
            }
        },
        turn_id: (!item.turn_id.is_empty()).then(|| item.turn_id.clone()),
        attempt_id: None,
        tool: match item.state() {
            ThreadItemState::Tool(tool) => Some(ChatToolIdentity {
                call_id: tool.invocation().tool_call_id().into(),
                name: tool.invocation().name().into(),
            }),
            _ => None,
        },
        wait: match item.state() {
            ThreadItemState::Tool(tool) if !item.is_terminal() => tool.wait().cloned(),
            _ => None,
        },
        text_channel: match item.state() {
            ThreadItemState::Text(text) => Some(text.channel()),
            _ => None,
        },
        started_at: None,
        finished_at: item.state().terminal_at(),
        contents: Vec::new(),
        payload: None,
    }
}
