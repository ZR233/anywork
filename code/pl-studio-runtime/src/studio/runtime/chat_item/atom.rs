//! Product provenance derived from typed facts, never from a frozen/deferred payload.
use crate::{ExecutionItem, ExecutionShape};
use pl_protocol::*;

pub(crate) fn atom(item: &ExecutionItem) -> ChatAtom {
    let kind = match item.state() {
        ExecutionShape::Text(text) if text.channel() == ThreadTextChannel::User => {
            ChatAtomKind::Input
        }
        ExecutionShape::Text(_) => ChatAtomKind::Text,
        ExecutionShape::Thinking(_) => ChatAtomKind::Reasoning,
        ExecutionShape::Tool(tool)
            if tool.invocation().name() == crate::plan_tool::TOOL_PLAN_SUBMIT =>
        {
            ChatAtomKind::Plan
        }
        ExecutionShape::Tool(tool)
            if tool.invocation().name() == "request_user_input" || tool.user_input().is_some() =>
        {
            ChatAtomKind::Interaction
        }
        ExecutionShape::Tool(_) => ChatAtomKind::ToolCall,
        ExecutionShape::File(_) => ChatAtomKind::FileChange,
        ExecutionShape::Skill(_) => ChatAtomKind::Skill,
        ExecutionShape::Turn(_) => ChatAtomKind::TurnReceipt,
        ExecutionShape::ContextCompaction(_) => ChatAtomKind::Compaction,
        ExecutionShape::Raw(_) => ChatAtomKind::Raw,
        ExecutionShape::Agent(_) => ChatAtomKind::Agent,
        ExecutionShape::Inference(_) => ChatAtomKind::Inference,
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
        ExecutionShape::Text(text) => content_outcome(text.lifecycle()),
        ExecutionShape::Thinking(thinking) => content_outcome(thinking.lifecycle()),
        ExecutionShape::Tool(tool)
            if tool.user_input().is_some_and(|input| {
                matches!(input.state(), ThreadToolUserInputState::Cancelled)
            }) =>
        {
            ChatTerminalOutcome::Cancelled
        }
        ExecutionShape::Tool(tool) => match tool.state() {
            ThreadToolState::Failed(_) | ThreadToolState::Denied(_) => ChatTerminalOutcome::Failed,
            ThreadToolState::Cancelled(_) | ThreadToolState::Interrupted(_) => {
                ChatTerminalOutcome::Cancelled
            }
            _ => ChatTerminalOutcome::Completed,
        },
        ExecutionShape::Turn(turn) => match turn.state() {
            TurnState::Failed(_) => ChatTerminalOutcome::Failed,
            TurnState::Cancelled(_) => ChatTerminalOutcome::Cancelled,
            _ => ChatTerminalOutcome::Completed,
        },
        _ => ChatTerminalOutcome::Completed,
    };
    ChatAtom {
        id: item.id.clone(),
        completion_item_id: None,
        // This item may be a static_state shell. Only freeze(), which owns
        // the actual content blocks, can prove that a terminal text is empty.
        content_present: None,
        completion_seq: None,
        source,
        source_state: None,
        source_order: (item.ordinal > 0).then_some(item.ordinal),
        kind,
        delivery: match item.state() {
            // Explicit user output is not implementation work to hide in a folded Run.
            // Keep the original Turn source and let the existing Independent rule classify it.
            ExecutionShape::Tool(tool)
                if tool.invocation().presentation_contract()
                    == Some(pl_tool::file_display::FILE_DISPLAY_PRESENTATION) =>
            {
                ChatDeliveryKind::Independent
            }
            _ => ChatDeliveryKind::Foreground,
        },
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
            ExecutionShape::Tool(tool) => Some(ChatToolIdentity {
                call_id: tool.invocation().tool_call_id().into(),
                name: tool.invocation().name().into(),
            }),
            _ => None,
        },
        wait: match item.state() {
            ExecutionShape::Tool(tool) if !item.is_terminal() => tool.wait().cloned(),
            _ => None,
        },
        text_channel: match item.state() {
            ExecutionShape::Text(text) => Some(text.channel()),
            _ => None,
        },
        started_at: None,
        finished_at: item.state().terminal_at(),
        contents: Vec::new(),
        payload: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_sources_keep_kind_origin_and_foreground_identity() -> anyhow::Result<()> {
        let cases = [
            (
                ExecutionShape::Raw(ThreadRawItem::stored(vec![], "undecodable", 7)),
                ChatAtomKind::Raw,
            ),
            (
                ExecutionShape::Raw(ThreadRawItem::runtime_control("control", 7)),
                ChatAtomKind::Raw,
            ),
            (
                ExecutionShape::Agent(ThreadAgentItem::new(
                    ThreadAgentIdentity::new(
                        "child".into(),
                        "root/child".into(),
                        "worker".into(),
                        "task".into(),
                        1,
                    ),
                    ThreadAgentState::Succeeded(SucceededThreadAgent::new(7, "done".into())),
                )),
                ChatAtomKind::Agent,
            ),
            (
                ExecutionShape::Inference(ThreadInferenceItem::new(
                    "call".into(),
                    "model".into(),
                    ThreadInferenceState::Running(RunningThreadInference),
                )),
                ChatAtomKind::Inference,
            ),
        ];
        for (index, (state, kind)) in cases.into_iter().enumerate() {
            let original = state.clone();
            let item = ExecutionItem::new(
                format!("item-{index}"),
                "thread".into(),
                "turn".into(),
                1,
                1,
                1,
                7,
                state,
            );
            let metadata = atom(&item);
            assert_eq!(metadata.kind, kind);
            assert_eq!(
                metadata.source,
                ChatSourceId::ForegroundTurn {
                    turn_id: "turn".into()
                }
            );
            assert_eq!(item.state(), &original);
            if let ExecutionShape::Raw(raw) = item.state() {
                let draft = super::super::completion_draft(&item, 1, "database")?;
                let envelope: serde_json::Value = serde_json::from_slice(draft.payload.as_ref())?;
                assert_eq!(envelope["type"], "raw");
                assert_eq!(
                    envelope["data"]["origin"],
                    serde_json::to_value(raw.origin)?
                );
            }
        }
        Ok(())
    }
}
