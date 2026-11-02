//! Bounded, target-only projection of ordered completed messages and current previews.

use super::content::{
    FinalError, MAX_TURN_BODY_BYTES, MAX_TURN_CONTENT_ITEMS, ReplyItem, ReplyItemKind,
};
use pl_protocol::{
    ChatPlacement, CurrentContentRole, CurrentProjection, ThreadTextChannel, TurnState,
};

#[derive(Clone)]
pub(super) struct ReplyProjection {
    turn_id: String,
    items: Vec<ReplyItem>,
    covered: bool,
    active: bool,
    current: Vec<(String, String)>,
}

impl ReplyProjection {
    pub(super) fn new(turn_id: &str) -> Self {
        Self {
            turn_id: turn_id.into(),
            items: Vec::new(),
            covered: false,
            active: false,
            current: Vec::new(),
        }
    }

    pub(super) fn apply(
        &mut self,
        placement: ChatPlacement,
        items: Vec<ReplyItem>,
    ) -> Result<(), FinalError> {
        let existing = if placement == ChatPlacement::Set {
            &[][..]
        } else {
            &self.items[..]
        };
        let bytes = existing
            .iter()
            .chain(&items)
            .try_fold(0usize, |size, item| size.checked_add(item.preview_bytes()))
            .ok_or_else(|| gap("reply body size overflow"))?;
        if existing.len().saturating_add(items.len()) > MAX_TURN_CONTENT_ITEMS
            || bytes > MAX_TURN_BODY_BYTES
        {
            return Err(FinalError::Attention(
                "reply projection exceeded its item or UTF-8 budget".into(),
            ));
        }
        for (index, item) in items.iter().enumerate() {
            if existing
                .iter()
                .chain(&items[..index])
                .any(|old| old.id == item.id || old.member_id == item.member_id)
            {
                return Err(gap("duplicate reply completion identity"));
            }
        }
        if existing
            .iter()
            .chain(&items)
            .filter(|item| matches!(item.kind, ReplyItemKind::Terminal(_)))
            .count()
            > 1
        {
            return Err(gap("reply target has conflicting terminal messages"));
        }
        match placement {
            ChatPlacement::Set => {
                self.items = items;
                self.covered = false;
                self.active = false;
                self.current.clear();
            }
            ChatPlacement::Append => self.items.extend(items),
            ChatPlacement::Prepend => {
                let mut all = items;
                all.append(&mut self.items);
                self.items = all;
            }
        }
        Ok(())
    }

    pub(super) fn mark_covered(&mut self) {
        self.covered = true;
    }

    pub(super) fn set_current(&mut self, current: CurrentProjection) -> Result<(), FinalError> {
        // Completed members have already been accepted from this same batch. A concrete
        // empty snapshot retires the current preview; None is handled by the caller.
        let mut previews = Vec::new();
        let active = current.execution_present
            && current
                .active_turn
                .as_ref()
                .is_some_and(|turn| turn.id == self.turn_id);
        if active {
            for part in current.previews {
                // Display role is not an outbound channel. Only the producer's
                // canonical Final fact can authorize a streaming card preview.
                if part.role == CurrentContentRole::Response
                    && part.text_channel == Some(ThreadTextChannel::Final)
                {
                    previews.push((part.id, part.text));
                }
            }
        }
        let bytes = previews
            .iter()
            .try_fold(0usize, |size, (_, text)| size.checked_add(text.len()));
        if previews.len() > MAX_TURN_CONTENT_ITEMS
            || bytes.is_none_or(|size| size > MAX_TURN_BODY_BYTES)
        {
            return Err(gap("current reply preview exceeded its bounded budget"));
        }
        self.current = previews;
        self.active = active;
        Ok(())
    }

    pub(super) fn active(&self) -> bool {
        self.active
    }

    pub(super) fn validate_budget(&self) -> Result<(), FinalError> {
        let completed = self
            .items
            .iter()
            .try_fold(0usize, |size, item| size.checked_add(item.preview_bytes()));
        let bytes = self
            .current
            .iter()
            .filter(|(id, _)| !self.items.iter().any(|item| item.member_id == *id))
            .try_fold(completed.unwrap_or(usize::MAX), |size, (_, text)| {
                size.checked_add(text.len())
            });
        if bytes.is_none_or(|size| size > MAX_TURN_BODY_BYTES) {
            return Err(FinalError::Attention(
                "reply completed/current body budget exceeded".into(),
            ));
        }
        Ok(())
    }

    /// A hint only. The explicit reliable barrier is still required before any final delivery.
    pub(super) fn terminal(&self) -> Option<TurnState> {
        self.items.iter().rev().find_map(|item| match &item.kind {
            ReplyItemKind::Terminal(state) => Some(state.clone()),
            _ => None,
        })
    }

    pub(super) fn completed(&self) -> Result<&[ReplyItem], FinalError> {
        if !self.covered || self.terminal().is_none() {
            return Err(gap("canonical terminal target content is not yet covered"));
        }
        Ok(&self.items)
    }

    pub(super) fn interactions(&self) -> impl Iterator<Item = &str> {
        self.items.iter().filter_map(|item| match &item.kind {
            ReplyItemKind::Interaction(id) => Some(id.as_str()),
            _ => None,
        })
    }

    pub(super) fn preview(&self) -> Option<String> {
        if !self.covered {
            return None;
        }
        let mut text = String::new();
        for item in &self.items {
            if let ReplyItemKind::Final { body, preview } = &item.kind {
                text.push_str(preview);
                // Do not concatenate a later fragment onto an omitted suffix.
                if preview.len() as u64 != body.byte_length {
                    return (!text.trim().is_empty()).then_some(text);
                }
            }
        }
        for (id, preview) in &self.current {
            if !self.items.iter().any(|item| item.member_id == *id) {
                text.push_str(preview);
            }
        }
        (!text.trim().is_empty()).then_some(text)
    }
}

pub(super) fn gap(message: &str) -> FinalError {
    FinalError::Retryable(message.into())
}
