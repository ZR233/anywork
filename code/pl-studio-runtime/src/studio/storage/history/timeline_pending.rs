//! Secondary indexes over the original writer's frozen allocations.
//! They never own another copy of an item, member, body or recovery state.

use super::conversation::current::PreparedCurrent;
use std::{collections::BTreeMap, sync::Arc};
type IndexedCurrent = (usize, Arc<PreparedCurrent>);
type MemberVersions = BTreeMap<u64, IndexedCurrent>;
type IndexedHead = (bool, usize, Arc<PreparedCurrent>);

pub(super) struct MemberPageCapture {
    pub members: Vec<IndexedCurrent>,
    pub head: Option<IndexedHead>,
}

#[derive(Default)]
pub(super) struct TimelinePending {
    pub(super) effects: BTreeMap<u64, Arc<PreparedCurrent>>,
    main: BTreeMap<u64, MemberVersions>,
    main_through: BTreeMap<u64, u64>,
    members: BTreeMap<String, BTreeMap<u64, MemberVersions>>,
    heads: BTreeMap<String, BTreeMap<u64, IndexedHead>>,
}

impl TimelinePending {
    pub(super) fn publish(&mut self, current: Arc<PreparedCurrent>) {
        let effect = current.projection().source_effect_seq;
        if let Some(previous) = self.effects.insert(effect, current.clone()) {
            self.remove_members(effect, &previous);
            self.remove_main(effect, &previous);
            self.main_through.remove(&effect);
        }
        for (index, item) in current.history_items().enumerate() {
            if let Some(position) = item.position {
                self.main
                    .entry(position)
                    .or_default()
                    .insert(effect, (index, current.clone()));
                self.main_through
                    .entry(effect)
                    .and_modify(|through| *through = (*through).max(position))
                    .or_insert(position);
            }
            if item.members.is_some() {
                self.heads
                    .entry(item.id.clone())
                    .or_default()
                    .insert(effect, (false, index, current.clone()));
            }
        }
        let mut changed = std::collections::BTreeSet::new();
        for (index, member) in current.timeline_update.members().iter().enumerate() {
            self.members
                .entry(member.item_id.clone())
                .or_default()
                .entry(member.member_order)
                .or_default()
                .insert(effect, (index, current.clone()));
            changed.insert(member.item_id.as_str());
        }
        for (index, item) in current.timeline_update.current().iter().enumerate() {
            if changed.contains(item.id.as_str()) {
                self.heads
                    .entry(item.id.clone())
                    .or_default()
                    .insert(effect, (true, index, current.clone()));
            }
        }
    }

    pub(super) fn member_page(
        &self,
        item: &str,
        before: Option<u64>,
        ceiling: u64,
        effect_cut: u64,
        max_items: usize,
    ) -> MemberPageCapture {
        let head = self
            .heads
            .get(item)
            .and_then(|heads| heads.range(..=effect_cut).next_back())
            .map(|(_, head)| head.clone());
        let count = head.as_ref().and_then(|(is_current, index, current)| {
            let item = if *is_current {
                &current.timeline_update.current()[*index]
            } else {
                current.history_item(*index)
            };
            item.summary
                .as_ref()
                .map(|summary| u64::from(summary.member_count))
        });
        let upper = before
            .unwrap_or(ceiling)
            .min(ceiling)
            .min(count.unwrap_or(u64::MAX));
        let members = self
            .members
            .get(item)
            .into_iter()
            .flat_map(|members| members.range(..upper).rev())
            .take(max_items.saturating_add(1))
            .filter_map(|(_, versions)| {
                versions
                    .range(..=effect_cut)
                    .next_back()
                    .map(|(_, location)| location.clone())
            })
            .collect();
        MemberPageCapture { members, head }
    }

    fn remove_members(&mut self, effect: u64, current: &PreparedCurrent) {
        for member in current.timeline_update.members() {
            if let Some(orders) = self.members.get_mut(&member.item_id) {
                if let Some(versions) = orders.get_mut(&member.member_order) {
                    versions.remove(&effect);
                    if versions.is_empty() {
                        orders.remove(&member.member_order);
                    }
                }
                if orders.is_empty() {
                    self.members.remove(&member.item_id);
                }
            }
            if let Some(heads) = self.heads.get_mut(&member.item_id) {
                heads.remove(&effect);
                if heads.is_empty() {
                    self.heads.remove(&member.item_id);
                }
            }
        }
        for item in current.history_items() {
            if let Some(heads) = self.heads.get_mut(&item.id) {
                heads.remove(&effect);
                if heads.is_empty() {
                    self.heads.remove(&item.id);
                }
            }
        }
    }
    fn remove_main(&mut self, effect: u64, current: &PreparedCurrent) {
        for item in current.history_items() {
            if let Some(position) = item.position
                && let Some(versions) = self.main.get_mut(&position)
            {
                versions.remove(&effect);
                if versions.is_empty() {
                    self.main.remove(&position);
                }
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
            .filter_map(|(_, versions)| {
                versions
                    .range(..=effect_cut)
                    .next_back()
                    .map(|(_, (index, current))| (*index, current.clone()))
            })
            .take(max_items.saturating_add(1))
            .collect()
    }

    pub(super) fn saved(&mut self, through: u64) {
        let Some(keep_effect) = through.checked_add(1) else {
            self.effects.clear();
            self.main.clear();
            self.main_through.clear();
            self.members.clear();
            self.heads.clear();
            return;
        };
        self.main_through = self.main_through.split_off(&keep_effect);
        let remaining = self.effects.split_off(&keep_effect);
        let saved = std::mem::replace(&mut self.effects, remaining);
        for (effect, current) in saved {
            self.remove_main(effect, &current);
            self.remove_members(effect, &current);
        }
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
    fn indexed_members_select_the_group_and_cut_and_survive_saved_pruning() {
        use crate::studio::thread_projection::timeline::TimelineProjection;
        let mut projection = TimelineProjection::new("db".into(), "generation".into(), 0);
        let mut pending = TimelinePending::default();
        let mut group = String::new();
        let mut first = None;
        for effect in 1..=128 {
            let target = effect <= 8;
            let atom = ChatAtom {
                id: format!("member-{effect}"),
                completion_item_id: None,
                content_present: None,
                completion_seq: None,
                source: ChatSourceId::ForegroundTurn {
                    turn_id: if target {
                        "target".into()
                    } else {
                        format!("other-{effect}")
                    },
                },
                source_state: None,
                source_order: Some(effect),
                kind: ChatAtomKind::ToolCall,
                delivery: ChatDeliveryKind::Foreground,
                lifecycle: ChatAtomLifecycle::Active {
                    started: Some(ChatFactPosition {
                        effect_seq: effect,
                        suborder: 0,
                    }),
                    status: ChatActiveStatus::Running,
                },
                turn_id: None,
                attempt_id: None,
                tool: None,
                wait: None,
                text_channel: None,
                started_at: None,
                finished_at: None,
                contents: Vec::new(),
                payload: None,
            };
            projection.observe(&atom, None).unwrap();
            let mut current = super::super::test_current(effect);
            current.timeline_update = Arc::new(projection.take_update().unwrap());
            if effect == 1 {
                group = current.timeline_update.current()[0].id.clone();
                first = Some(atom);
            }
            pending.publish(Arc::new(current));
        }
        let captured = pending.member_page(&group, None, 100, 8, 2);
        let orders = |page: &MemberPageCapture| {
            page.members
                .iter()
                .map(|(index, current)| current.timeline_update.members()[*index].member_order)
                .collect::<Vec<_>>()
        };
        assert_eq!(orders(&captured), [7, 6, 5]);
        assert!(Arc::ptr_eq(&captured.members[0].1, &pending.effects[&8]));
        let mut waiting = first.unwrap();
        waiting.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            status: ChatActiveStatus::Waiting,
        };
        projection.observe(&waiting, None).unwrap();
        let mut current = super::super::test_current(129);
        current.timeline_update = Arc::new(projection.take_update().unwrap());
        pending.publish(Arc::new(current));
        let old = pending.member_page(&group, Some(1), 100, 8, 2);
        let new = pending.member_page(&group, Some(1), 100, 129, 2);
        assert!(matches!(
            old.members[0].1.timeline_update.members()[old.members[0].0]
                .atom
                .lifecycle,
            ChatAtomLifecycle::Active {
                status: ChatActiveStatus::Running,
                ..
            }
        ));
        assert!(matches!(
            new.members[0].1.timeline_update.members()[new.members[0].0]
                .atom
                .lifecycle,
            ChatAtomLifecycle::Active {
                status: ChatActiveStatus::Waiting,
                ..
            }
        ));
        pending.saved(128);
        assert_eq!(orders(&pending.member_page(&group, None, 100, 129, 2)), [0]);
        assert_eq!(orders(&captured), [7, 6, 5]);
        pending.saved(u64::MAX);
        assert!(pending.members.is_empty() && pending.heads.is_empty());
        assert_eq!(orders(&captured), [7, 6, 5]);
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
