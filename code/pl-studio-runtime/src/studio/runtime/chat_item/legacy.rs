//! The sole v9 execution-item → immutable-completion migration boundary.

use super::*;

pub(crate) fn legacy_completion_drafts(item: &ThreadItem) -> Result<Vec<ChatDraft>> {
    if !item.is_terminal()
        || matches!(
            item.state(),
            ThreadItemState::Tool(tool) if tool.user_input().is_some_and(|input| matches!(
                input.state(), ThreadToolUserInputState::Pending
            ))
        )
    {
        return Ok(Vec::new());
    }
    let mut parts = Vec::new();
    match item.state() {
        ThreadItemState::Thinking(thinking)
            if thinking.summary().len() + thinking.content().len() > 1 =>
        {
            for (kind, chunks) in [
                ("summary", thinking.summary()),
                ("reasoning", thinking.content()),
            ] {
                for (index, chunk) in chunks.iter().enumerate() {
                    let state = ThreadItemState::Thinking(ThreadThinkingItem::new(
                        if kind == "summary" {
                            vec![chunk.clone()]
                        } else {
                            Vec::new()
                        },
                        if kind == "reasoning" {
                            vec![chunk.clone()]
                        } else {
                            Vec::new()
                        },
                        thinking.lifecycle().clone(),
                    ));
                    let mut part = item.clone().with_state(state);
                    part.id = part_id(&item.id, kind, index);
                    parts.push(part);
                }
            }
        }
        ThreadItemState::Raw(raw) if raw.payloads.len() > 1 => {
            for (index, payload) in raw.payloads.iter().enumerate() {
                let mut value = raw.clone();
                value.payloads = vec![payload.clone()];
                let mut part = item.clone().with_state(ThreadItemState::Raw(value));
                part.id = part_id(&item.id, "payload", index);
                parts.push(part);
            }
        }
        _ => parts.push(item.clone()),
    }
    parts
        .iter()
        .map(|part| {
            let mut draft = completion_draft(part, 1)?;
            // A last-write revision or timestamp cannot establish the original seal's provenance.
            draft.source_effect_seq = None;
            draft.sealed_at = None;
            Ok(draft)
        })
        .collect()
}

fn part_id(id: &str, kind: &str, index: usize) -> String {
    format!("legacy-part:{}:{id}:{kind}:{index}", id.len())
}
