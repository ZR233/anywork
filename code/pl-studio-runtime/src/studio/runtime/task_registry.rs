//! Generation-keyed ownership for retained background tasks.
//!
//! The registry keeps every spawned handle until a waiter observes its terminal
//! poll. Replacing the active generation cancels the previous token but does not
//! drop its handle. Close cancels admission and still joins the original tasks.

use std::collections::BTreeMap;
use std::sync::Arc;

use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use super::acp_ops::RetainedTask;

pub(super) struct Registered<P, T> {
    pub payload: P,
    pub cancel: CancellationToken,
    pub task: Arc<RetainedTask<T>>,
}

impl<P, T> std::ops::Deref for Registered<P, T> {
    type Target = P;

    fn deref(&self) -> &P {
        &self.payload
    }
}

impl<P, T> std::ops::DerefMut for Registered<P, T> {
    fn deref_mut(&mut self) -> &mut P {
        &mut self.payload
    }
}

pub(super) struct RetainedTaskRegistry<K, P, T = Result<()>> {
    closing: bool,
    next_id: u64,
    active: BTreeMap<K, u64>,
    by_id: BTreeMap<u64, Registered<P, T>>,
}

impl<K, P, T> Default for RetainedTaskRegistry<K, P, T> {
    fn default() -> Self {
        Self {
            closing: false,
            next_id: 0,
            active: BTreeMap::new(),
            by_id: BTreeMap::new(),
        }
    }
}

impl<K, P, T> RetainedTaskRegistry<K, P, T>
where
    K: Clone + Ord,
{
    pub(super) fn is_closing(&self) -> bool {
        self.closing
    }

    pub(super) fn len(&self) -> usize {
        self.by_id.len()
    }

    pub(super) fn is_empty(&self) -> bool {
        self.by_id.is_empty()
    }

    pub(super) fn get(&self, key: &K) -> Option<&Registered<P, T>> {
        let id = self.active.get(key)?;
        self.by_id.get(id)
    }

    pub(super) fn get_mut(&mut self, key: &K) -> Option<&mut Registered<P, T>> {
        let id = *self.active.get(key)?;
        self.by_id.get_mut(&id)
    }

    pub(super) fn values(&self) -> impl Iterator<Item = &Registered<P, T>> {
        self.by_id.values()
    }

    pub(super) fn values_mut(&mut self) -> impl Iterator<Item = &mut Registered<P, T>> {
        self.by_id.values_mut()
    }

    pub(super) fn keys(&self) -> impl Iterator<Item = &K> {
        self.active.keys()
    }

    pub(super) fn active_pairs(&self) -> impl Iterator<Item = (&K, &Registered<P, T>)> {
        self.active
            .iter()
            .filter_map(|(key, id)| self.by_id.get(id).map(|registered| (key, registered)))
    }

    pub(super) fn finished_ids(&self) -> Vec<u64> {
        self.by_id
            .iter()
            .filter(|(_, registered)| registered.task.finished())
            .map(|(id, _)| *id)
            .collect()
    }

    pub(super) fn task(&self, id: u64) -> Option<Arc<RetainedTask<T>>> {
        self.by_id
            .get(&id)
            .map(|registered| Arc::clone(&registered.task))
    }

    pub(super) fn payload(&self, id: u64) -> Option<&P> {
        self.by_id.get(&id).map(|registered| &registered.payload)
    }

    pub(super) fn remove(&mut self, id: u64) {
        self.by_id.remove(&id);
        self.active.retain(|_, active| *active != id);
    }

    pub(super) fn clear(&mut self) {
        self.active.clear();
        self.by_id.clear();
    }

    /// Mark closed and cancel every token. Handles stay in their slots.
    pub(super) fn begin_close(&mut self) -> Vec<Arc<RetainedTask<T>>> {
        self.closing = true;
        for registered in self.by_id.values() {
            registered.cancel.cancel();
        }
        self.by_id
            .values()
            .map(|registered| Arc::clone(&registered.task))
            .collect()
    }

    pub(super) fn allocate_id(&mut self) -> Option<u64> {
        let id = self.next_id.checked_add(1)?;
        self.next_id = id;
        Some(id)
    }

    /// Store an already allocated generation. The handle is retained even if `key`
    /// already names an older generation; that older handle stays in `by_id`.
    pub(super) fn retain(
        &mut self,
        id: u64,
        key: K,
        payload: P,
        cancel: CancellationToken,
        handle: JoinHandle<T>,
    ) -> Arc<RetainedTask<T>> {
        let task = Arc::new(RetainedTask::running(handle));
        self.retain_task(id, key, payload, cancel, Arc::clone(&task));
        task
    }

    /// Store a prebuilt slot. Tests use an empty slot; production uses [`Self::retain`].
    pub(super) fn retain_task(
        &mut self,
        id: u64,
        key: K,
        payload: P,
        cancel: CancellationToken,
        task: Arc<RetainedTask<T>>,
    ) {
        self.by_id.insert(
            id,
            Registered {
                payload,
                cancel,
                task,
            },
        );
        self.active.insert(key, id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::runtime::acp_ops::RetainedJoin;
    use std::time::Duration;

    #[tokio::test]
    async fn replacement_retains_the_previous_handle_until_it_is_observed() {
        let mut registry = RetainedTaskRegistry::<&'static str, u64, ()>::default();
        let first_id = registry.allocate_id().expect("id");
        let first = registry.retain(
            first_id,
            "account",
            1,
            CancellationToken::new(),
            tokio::spawn(async {}),
        );
        let previous = registry.get("account").expect("active").cancel.clone();
        previous.cancel();
        let second_id = registry.allocate_id().expect("id");
        registry.retain(
            second_id,
            "account",
            2,
            CancellationToken::new(),
            tokio::spawn(std::future::pending()),
        );
        assert!(previous.is_cancelled());
        assert_eq!(registry.len(), 2);
        assert!(matches!(first.join().await, RetainedJoin::Observed(Ok(()))));
        let finished = registry.finished_ids();
        assert_eq!(finished.len(), 1);
        registry.remove(finished[0]);
        assert_eq!(registry.len(), 1);
        assert_eq!(registry.get("account").map(|entry| entry.payload), Some(2));
        assert_eq!(
            registry
                .get("account")
                .and_then(|entry| entry.task.running_handle_retained()),
            Some(true)
        );
    }

    #[tokio::test]
    async fn close_cancels_without_dropping_a_timed_out_handle() {
        let mut registry = RetainedTaskRegistry::<u64, (), ()>::default();
        let id = registry.allocate_id().expect("id");
        registry.retain(
            id,
            1,
            (),
            CancellationToken::new(),
            tokio::spawn(std::future::pending()),
        );
        let tasks = registry.begin_close();
        assert!(registry.is_closing());
        assert!(registry.get(&1).unwrap().cancel.is_cancelled());
        let deadline = tokio::time::Instant::now() + Duration::from_millis(30);
        assert!(matches!(
            tasks[0].join_until(deadline).await,
            RetainedJoin::TimedOut
        ));
        assert_eq!(tasks[0].running_handle_retained(), Some(true));
        assert_eq!(registry.len(), 1);
    }

    #[test]
    fn identity_exhaustion_does_not_overwrite_the_active_generation() {
        let mut registry = RetainedTaskRegistry::<u8, (), ()>::default();
        registry.next_id = u64::MAX;
        assert!(registry.allocate_id().is_none());
        assert!(registry.is_empty());
    }
}
