//! Member metadata belongs to the original fold. Candidates stage changes; only accepted
//! publications mutate this index, so preparing an unrelated effect never clones a large group.
use super::*;

#[derive(Debug, Default)]
pub(super) struct Members {
    groups: BTreeMap<String, BTreeMap<u64, MemberChange>>,
    bytes: u64,
}

fn member_bytes(member: &MemberChange) -> u64 {
    serde_json::to_vec(member)
        .map_or(u64::MAX, |bytes| bytes.len() as u64)
        .saturating_add(512)
}

impl Members {
    pub(super) fn retained_bytes(&self) -> u64 {
        self.bytes
            .saturating_add(std::mem::size_of::<Self>() as u64)
    }
    pub(super) fn page(&self, item: &str, upper: u64, limit: usize) -> Vec<MemberChange> {
        self.groups
            .get(item)
            .into_iter()
            .flat_map(|members| members.range(..upper).rev())
            .take(limit.saturating_add(1))
            .map(|(_, member)| member.clone())
            .collect()
    }
    pub(super) fn freeze(&self, groups: &[String], changes: &[MemberChange]) -> Vec<MemberChange> {
        let mut result = Vec::new();
        for group in groups {
            let mut members = self.groups.get(group).cloned().unwrap_or_default();
            for change in changes.iter().filter(|change| &change.item_id == group) {
                members.insert(change.member_order, change.clone());
            }
            result.extend(members.into_values());
        }
        result
    }
    fn apply(&mut self, update: &TimelineUpdate) {
        for change in &update.members {
            if !self.groups.contains_key(&change.item_id) {
                self.bytes = self.bytes.saturating_add(change.item_id.len() as u64 + 256);
            }
            let members = self.groups.entry(change.item_id.clone()).or_default();
            let added = member_bytes(change);
            if let Some(previous) = members.insert(change.member_order, change.clone()) {
                if self.bytes != u64::MAX {
                    self.bytes = self.bytes.saturating_sub(member_bytes(&previous));
                }
            }
            self.bytes = self.bytes.saturating_add(added);
        }
        for group in &update.finished_groups {
            if let Some(members) = self.groups.remove(group) {
                if self.bytes != u64::MAX {
                    self.bytes = self.bytes.saturating_sub(group.len() as u64 + 256);
                }
                for member in members.into_values() {
                    if self.bytes != u64::MAX {
                        self.bytes = self.bytes.saturating_sub(member_bytes(&member));
                    }
                }
            }
        }
        if self.groups.is_empty() {
            self.bytes = 0;
        }
    }
}

impl TimelineProjection {
    /// No fallible work follows the runtime publication's acceptance. Migration owners
    /// accept each successful fold step inside their one transaction.
    pub(in crate::studio) fn accept_members(&mut self, update: &TimelineUpdate) {
        if update.members.is_empty() && update.finished_groups.is_empty() {
            return;
        }
        self.members
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .apply(update);
        self.retained_bytes.take();
    }
}
