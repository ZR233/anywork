//! Secondary indexes over the original writer's frozen allocations.
//! They never own another copy of an item, member, body or recovery state.

use super::conversation::current::PreparedCurrent;
use std::{collections::BTreeMap, sync::Arc};

#[derive(Default)]
pub(super) struct TimelinePending {
    pub(super) effects: BTreeMap<u64, Arc<PreparedCurrent>>,
    main: BTreeMap<u64, (u64, usize, Arc<PreparedCurrent>)>,
    main_through: BTreeMap<u64, u64>,
}

impl TimelinePending {
    pub(super) fn publish(&mut self, current: Arc<PreparedCurrent>) {
        let effect = current.projection().source_effect_seq;
        if let Some(previous) = self.effects.insert(effect, current.clone()) {
            for entry in previous.timeline.iter() {
                if let Some(position) = entry.item.position {
                    self.main.remove(&position);
                }
            }
            self.main_through.remove(&effect);
        }
        for (index, entry) in current.timeline.iter().enumerate() {
            if let Some(position) = entry.item.position {
                self.main.insert(position, (effect, index, current.clone()));
                self.main_through
                    .entry(effect)
                    .and_modify(|through| *through = (*through).max(position))
                    .or_insert(position);
            }
        }
    }

    /// Capture only the requested Main suffix before opening the SQLite snapshot.
    /// An older effect cut is located in the effect index, not by scanning newer items.
    pub(super) fn main_page(
        &self,
        before: Option<u64>,
        ceiling: u64,
        effect_cut: u64,
        max_items: usize,
    ) -> Vec<(usize, Arc<PreparedCurrent>)> {
        let Some((_, position)) = self.main_through.range(..=effect_cut).next_back() else {
            return Vec::new();
        };
        let upper = before
            .unwrap_or(ceiling)
            .min(ceiling)
            .min(position.saturating_add(1));
        self.main
            .range(..upper)
            .rev()
            .take(max_items.saturating_add(1))
            .map(|(_, (effect, index, current))| {
                debug_assert!(*effect <= effect_cut);
                (*index, current.clone())
            })
            .collect()
    }

    pub(super) fn saved(&mut self, through: u64) {
        let Some(keep_effect) = through.checked_add(1) else {
            self.effects.clear();
            self.main.clear();
            self.main_through.clear();
            return;
        };
        if let Some((_, position)) = self.main_through.range(..=through).next_back() {
            self.main = self.main.split_off(&position.saturating_add(1));
        }
        self.main_through = self.main_through.split_off(&keep_effect);
        self.effects = self.effects.split_off(&keep_effect);
    }
}

#[cfg(test)]
mod tests {
    use super::super::conversation::current::PreparedTimelineItem;
    use super::*;
    use pl_protocol::*;

    fn prepared(effect: u64, positions: &[u64]) -> Arc<PreparedCurrent> {
        let mut current = super::super::test_current(effect);
        current.timeline = positions
            .iter()
            .map(|position| PreparedTimelineItem {
                item: TimelineItem {
                    id: format!("item-{position}"),
                    kind: TimelineItemKind::Status,
                    source: ChatSourceId::ForegroundTurn {
                        turn_id: "turn".into(),
                    },
                    atom_kind: Some(ChatAtomKind::TurnReceipt),
                    delivery: ChatDeliveryKind::Foreground,
                    text_channel: None,
                    turn_id: Some("turn".into()),
                    started_at: None,
                    finished_at: None,
                    outcome: Some(ChatTerminalOutcome::Completed),
                    summary: None,
                    members: None,
                    contents: Vec::new(),
                    payload: None,
                    content_item_id: None,
                    position: Some(*position),
                    admission_closed: true,
                },
            })
            .collect::<Vec<_>>()
            .into();
        Arc::new(current)
    }

    fn positions(page: &[(usize, Arc<PreparedCurrent>)]) -> Vec<u64> {
        page.iter()
            .map(|(index, current)| current.timeline[*index].item.position.unwrap())
            .collect()
    }

    #[test]
    fn indexed_main_respects_cut_and_page_boundaries_and_retains_captured_allocations() {
        let mut pending = TimelinePending::default();
        assert!(pending.main_page(None, 100, 100, 3).is_empty());
        for effect in 1..=128 {
            pending.publish(prepared(effect, &[(effect - 1) * 2, (effect - 1) * 2 + 1]));
        }
        // A later effect without a committed item does not hide the existing indexed suffix.
        pending.publish(prepared(129, &[]));
        let captured = pending.main_page(None, 100, 10, 3);
        assert_eq!(positions(&captured), [19, 18, 17, 16]);
        assert!(Arc::ptr_eq(
            &captured[0].1,
            pending.effects.get(&10).unwrap()
        ));
        assert_eq!(
            positions(&pending.main_page(Some(18), 100, 10, 3)),
            [17, 16, 15, 14]
        );
        assert_eq!(
            positions(&pending.main_page(None, 21, 129, 3)),
            [20, 19, 18, 17]
        );
        assert!(pending.main_page(Some(0), 100, 129, 3).is_empty());
        pending.saved(12);
        assert!(pending.main_page(None, 100, 10, 3).is_empty());
        assert_eq!(
            positions(&pending.main_page(None, 100, 129, 3)),
            [99, 98, 97, 96]
        );
        pending.saved(u64::MAX);
        assert!(
            pending.effects.is_empty()
                && pending.main.is_empty()
                && pending.main_through.is_empty()
        );
        assert_eq!(positions(&captured), [19, 18, 17, 16]);
    }
}
