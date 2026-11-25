//! Bounded target projection of immutable records and independent Final activity.

use std::collections::HashSet;

use super::content::{
    FinalError, MAX_TURN_BODY_BYTES, MAX_TURN_CONTENT_ITEMS, ReplyItem, ReplyItemKind,
};
use crate::TurnState;

#[derive(Clone)]
pub(super) struct ReplyProjection {
    items: Vec<ReplyItem>,
    covered: bool,
    active: bool,
    previews: Vec<(String, String)>,
    history_terminal: bool,
}

impl ReplyProjection {
    pub(super) fn new() -> Self {
        Self {
            items: Vec::new(),
            covered: false,
            active: false,
            previews: Vec::new(),
            history_terminal: false,
        }
    }

    pub(super) fn replace(&mut self, items: Vec<ReplyItem>) -> Result<(), FinalError> {
        let bytes = items
            .iter()
            .try_fold(0usize, |size, item| size.checked_add(item.preview_bytes()))
            .ok_or_else(|| gap("reply body size overflow"))?;
        if items.len() > MAX_TURN_CONTENT_ITEMS || bytes > MAX_TURN_BODY_BYTES {
            return Err(FinalError::Attention(
                "reply projection exceeded its item or UTF-8 budget".into(),
            ));
        }
        let mut ids = HashSet::with_capacity(items.len());
        let mut member_ids = HashSet::with_capacity(items.len());
        let mut terminal = false;
        for item in &items {
            if !ids.insert(item.id.as_str()) || !member_ids.insert(item.member_id.as_str()) {
                return Err(gap("duplicate reply completion identity"));
            }
            if matches!(&item.kind, ReplyItemKind::Terminal(_)) {
                if terminal {
                    return Err(gap("reply target has conflicting terminal messages"));
                }
                terminal = true;
            }
        }
        self.items = items;
        self.covered = false;
        self.active = false;
        self.previews.clear();
        self.history_terminal = false;
        Ok(())
    }

    pub(super) fn mark_covered(&mut self) {
        self.covered = true;
    }

    pub(super) fn set_activity(
        &mut self,
        active: bool,
        previews: Vec<(String, String)>,
    ) -> Result<(), FinalError> {
        let bytes = previews
            .iter()
            .try_fold(0usize, |size, (_, text)| size.checked_add(text.len()));
        if previews.len() > MAX_TURN_CONTENT_ITEMS
            || bytes.is_none_or(|size| size > MAX_TURN_BODY_BYTES)
        {
            return Err(gap("active reply preview exceeded its bounded budget"));
        }
        self.previews = if active { previews } else { Vec::new() };
        self.active = active;
        Ok(())
    }

    pub(super) fn active(&self) -> bool {
        self.active && self.terminal().is_none()
    }

    pub(super) fn validate_budget(&self) -> Result<(), FinalError> {
        let completed = self
            .items
            .iter()
            .try_fold(0usize, |size, item| size.checked_add(item.preview_bytes()));
        let bytes = self
            .previews
            .iter()
            .filter(|(id, _)| !self.items.iter().any(|item| item.member_id == *id))
            .try_fold(completed.unwrap_or(usize::MAX), |size, (_, text)| {
                size.checked_add(text.len())
            });
        if bytes.is_none_or(|size| size > MAX_TURN_BODY_BYTES) {
            return Err(FinalError::Attention(
                "reply completed/activity body budget exceeded".into(),
            ));
        }
        Ok(())
    }

    /// A hint only. The explicit reliable barrier is still required before any final delivery.
    pub(super) fn terminal(&self) -> Option<TurnState> {
        let receipt = self.items.iter().rev().find_map(|item| match &item.kind {
            ReplyItemKind::Terminal(state) => Some(state.clone()),
            _ => None,
        })?;
        // State is the real execution outcome. The immutable Turn receipt proves
        // that its completed content prefix has actually reached this consumer.
        self.history_terminal.then_some(receipt)
    }

    pub(super) fn mark_history_terminal(&mut self) {
        self.history_terminal = true;
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

    pub(super) fn file_displays(
        &self,
    ) -> impl Iterator<Item = (&str, &pl_tool::file_display::FileDisplayReceipt)> {
        self.items.iter().filter_map(|item| match &item.kind {
            ReplyItemKind::Files {
                call_id, receipt, ..
            } if self.covered => Some((call_id.as_str(), receipt)),
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
        for (id, preview) in &self.previews {
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

#[cfg(test)]
mod tests {
    use super::*;

    fn item(member_id: &str, id: &str) -> ReplyItem {
        ReplyItem {
            member_id: member_id.into(),
            id: id.into(),
            kind: ReplyItemKind::Interaction(member_id.into()),
        }
    }

    fn terminal(member_id: &str) -> ReplyItem {
        ReplyItem {
            member_id: member_id.into(),
            id: member_id.into(),
            kind: ReplyItemKind::Terminal(TurnState::Completed(crate::CompletedTurnState::new(
                Some(1),
                3,
                crate::TurnCompletion::Normal,
            ))),
        }
    }

    #[test]
    fn replace_rejects_duplicate_identities_and_keeps_the_current_projection() {
        let mut projection = ReplyProjection::new();
        projection.replace(vec![terminal("kept")]).unwrap();
        projection.mark_history_terminal();
        projection.mark_covered();
        for (left, right, message) in [
            (
                item("a", "shared"),
                item("b", "shared"),
                "duplicate reply completion identity",
            ),
            (
                item("shared", "a"),
                item("shared", "b"),
                "duplicate reply completion identity",
            ),
            (
                terminal("first"),
                terminal("second"),
                "conflicting terminal messages",
            ),
        ] {
            let error = projection
                .replace(vec![left, right])
                .expect_err("conflicting items must be rejected");
            assert!(error.to_string().contains(message), "{error}");
            assert_eq!(
                projection.completed().expect("coverage is retained").len(),
                1,
                "a rejected replacement must keep the previous items"
            );
        }
        projection
            .replace(vec![item("a", "a"), item("b", "b")])
            .expect("distinct identities are accepted");
    }
}

#[cfg(test)]
mod terminals;
