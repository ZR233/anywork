//! Canonical live member index and frozen membership lookup.
use super::*;

#[derive(Debug, Default)]
pub(super) struct EntryRegistry {
    pub(super) entries: BTreeMap<String, AgentInstance>,
    pub(super) by_agent: BTreeMap<crate::AgentId, String>,
}

impl EntryRegistry {
    pub(super) fn insert_entry(&mut self, id: String, entry: AgentInstance) {
        self.by_agent
            .insert(entry.identity.agent_id.clone(), id.clone());
        self.entries.insert(id, entry);
    }

    pub(super) fn remove_entry(&mut self, id: &str) -> Option<AgentInstance> {
        let entry = self.entries.remove(id)?;
        if self
            .by_agent
            .get(&entry.identity.agent_id)
            .is_some_and(|current| current == id)
        {
            self.by_agent.remove(&entry.identity.agent_id);
        }
        Some(entry)
    }

    /// 成员树父 Thread。只用冻结 `parent_agent_id` 解析，不从 Native 字段回退。
    pub(super) fn membership_parent<'a>(
        by_agent: &'a BTreeMap<crate::AgentId, String>,
        entry: &'a AgentInstance,
    ) -> Option<&'a str> {
        if let Some(parent) = entry.identity.parent_agent_id.as_ref() {
            return by_agent.get(parent).map(String::as_str);
        }
        None
    }
}
impl EntryRegistry {
    pub(super) fn close_targets(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
    ) -> Result<Vec<(usize, String)>, ThreadAssemblyError> {
        let mut targets = Vec::new();
        let identities = self
            .entries
            .keys()
            .map(String::as_str)
            .chain(members.iter().map(|member| member.thread_id.as_str()))
            .collect::<BTreeSet<_>>();
        for id in identities {
            let mut cursor = Some(id);
            let mut depth = 0;
            while let Some(current) = cursor {
                if current == root {
                    targets.push((depth, id.to_owned()));
                    break;
                }
                depth += 1;
                if depth > self.entries.len() + members.len() {
                    return Err(ThreadAssemblyError::Identity(id.to_owned()));
                }
                cursor = self
                    .entries
                    .get(current)
                    .and_then(|entry| EntryRegistry::membership_parent(&self.by_agent, entry))
                    .or_else(|| {
                        members
                            .iter()
                            .find(|member| member.thread_id == current)
                            .and_then(|member| member.parent_id.as_deref())
                    });
            }
        }
        Ok(targets)
    }
    pub(super) fn close_dependencies(
        &self,
        root: &str,
        targets: &[(usize, String)],
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
        purpose: ClosePurpose,
    ) -> Result<BTreeMap<String, Vec<String>>, ThreadAssemblyError> {
        let live = targets
            .iter()
            .map(|(_, id)| id.as_str())
            .filter(|id| purpose == ClosePurpose::Delete || self.entries.contains_key(*id))
            .collect::<BTreeSet<_>>();
        let mut dependencies: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for id in &live {
            if *id == root {
                continue;
            }
            let mut cursor = *id;
            let mut seen = BTreeSet::new();
            loop {
                if !seen.insert(cursor) {
                    return Err(ThreadAssemblyError::Identity((*id).to_owned()));
                }
                let parent = self
                    .entries
                    .get(cursor)
                    .and_then(|entry| EntryRegistry::membership_parent(&self.by_agent, entry))
                    .or_else(|| {
                        members
                            .iter()
                            .find(|member| member.thread_id == cursor)
                            .and_then(|member| member.parent_id.as_deref())
                    })
                    .ok_or_else(|| ThreadAssemblyError::Identity((*id).to_owned()))?;
                if parent == root || live.contains(parent) {
                    dependencies
                        .entry(parent.to_owned())
                        .or_default()
                        .push((*id).to_owned());
                    break;
                }
                cursor = parent;
            }
        }
        Ok(dependencies)
    }
}
