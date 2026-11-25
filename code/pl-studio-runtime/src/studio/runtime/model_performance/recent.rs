use std::collections::{BTreeMap, VecDeque};

const RECENT_IDENTITY_LIMIT: usize = 256;

/// 最近 inference 身份窗口（固定上限、不持久化）。
///
/// inference ID 只在执行它的 Thread 内唯一；根 Thread 只用于清理整棵会话树的缓存。
#[derive(Debug, Clone, Default)]
pub(super) struct RecentIdentities {
    entries: BTreeMap<(String, String), RecentInference>,
    order: VecDeque<(String, String)>,
}

#[derive(Debug, Clone)]
struct RecentInference {
    root_thread_id: String,
    fingerprint: String,
}

impl RecentIdentities {
    pub(super) fn get(&self, thread_id: &str, identity: &str) -> Option<&String> {
        self.entries
            .get(&(thread_id.to_owned(), identity.to_owned()))
            .map(|entry| &entry.fingerprint)
    }

    pub(super) fn insert(
        &mut self,
        root_thread_id: &str,
        thread_id: &str,
        identity: &str,
        fingerprint: String,
    ) {
        let key = (thread_id.to_owned(), identity.to_owned());
        let entry = RecentInference {
            root_thread_id: root_thread_id.to_owned(),
            fingerprint,
        };
        if self.entries.insert(key.clone(), entry).is_none() {
            self.order.push_back(key);
        }
        while self.order.len() > RECENT_IDENTITY_LIMIT {
            if let Some(oldest) = self.order.pop_front() {
                self.entries.remove(&oldest);
            }
        }
    }

    pub(super) fn remove_root(&mut self, root_thread_id: &str) {
        self.entries
            .retain(|_, entry| entry.root_thread_id != root_thread_id);
        self.order.retain(|key| self.entries.contains_key(key));
    }
}
