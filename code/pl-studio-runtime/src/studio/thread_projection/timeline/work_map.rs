//! Test-only access observation around the real live-item BTreeMap.
//! The private map has no Deref, AsRef or raw-map escape hatch.
use super::LiveItem;
use serde::{Serialize, Serializer};
use std::{
    collections::{BTreeMap, btree_map},
    ops::Index,
    sync::atomic::{AtomicUsize, Ordering::Relaxed},
};

#[derive(Debug)]
pub(super) struct LiveItems {
    items: BTreeMap<u64, LiveItem>,
    visits: AtomicUsize,
}

fn visit(counter: &AtomicUsize) {
    counter
        .fetch_update(Relaxed, Relaxed, |previous| previous.checked_add(1))
        .expect("live item test access counter overflowed");
}

impl LiveItems {
    pub(super) fn new() -> Self {
        Self {
            items: BTreeMap::new(),
            visits: AtomicUsize::new(0),
        }
    }

    pub(super) fn reset_visits(&self) {
        self.visits.store(0, Relaxed);
    }

    pub(super) fn visits(&self) -> usize {
        self.visits.load(Relaxed)
    }

    pub(super) fn len(&self) -> usize {
        self.items.len()
    }

    pub(super) fn clear(&mut self) {
        self.items.clear();
    }

    pub(super) fn insert(&mut self, key: u64, item: LiveItem) -> Option<LiveItem> {
        self.items.insert(key, item)
    }

    pub(super) fn remove(&mut self, key: &u64) -> Option<LiveItem> {
        self.items.remove(key)
    }

    pub(super) fn get(&self, key: &u64) -> Option<&LiveItem> {
        let item = self.items.get(key)?;
        visit(&self.visits);
        Some(item)
    }

    pub(super) fn get_mut(&mut self, key: &u64) -> Option<&mut LiveItem> {
        let item = self.items.get_mut(key)?;
        visit(&self.visits);
        Some(item)
    }

    pub(super) fn iter(&self) -> Counted<'_, btree_map::Iter<'_, u64, LiveItem>> {
        Counted {
            inner: self.items.iter(),
            visits: &self.visits,
        }
    }

    pub(super) fn values(&self) -> Counted<'_, btree_map::Values<'_, u64, LiveItem>> {
        Counted {
            inner: self.items.values(),
            visits: &self.visits,
        }
    }

    pub(super) fn values_mut(&mut self) -> Counted<'_, btree_map::ValuesMut<'_, u64, LiveItem>> {
        Counted {
            inner: self.items.values_mut(),
            visits: &self.visits,
        }
    }
}

impl Clone for LiveItems {
    fn clone(&self) -> Self {
        Self {
            items: self
                .iter()
                .map(|(key, item)| (*key, item.clone()))
                .collect(),
            visits: AtomicUsize::new(0),
        }
    }
}

impl Serialize for LiveItems {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        // Preserve BTreeMap's ordered map encoding; the counter is never data.
        serializer.collect_map(self.iter())
    }
}

impl Index<&u64> for LiveItems {
    type Output = LiveItem;

    fn index(&self, key: &u64) -> &Self::Output {
        self.get(key).expect("indexed live item")
    }
}

impl<'a> IntoIterator for &'a LiveItems {
    type Item = (&'a u64, &'a LiveItem);
    type IntoIter = Counted<'a, btree_map::Iter<'a, u64, LiveItem>>;

    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

pub(super) struct Counted<'a, I> {
    inner: I,
    visits: &'a AtomicUsize,
}

impl<I: Iterator> Iterator for Counted<'_, I> {
    type Item = I::Item;

    fn next(&mut self) -> Option<Self::Item> {
        let item = self.inner.next()?;
        visit(self.visits);
        Some(item)
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        self.inner.size_hint()
    }
}

impl<I: DoubleEndedIterator> DoubleEndedIterator for Counted<'_, I> {
    fn next_back(&mut self) -> Option<Self::Item> {
        let item = self.inner.next_back()?;
        visit(self.visits);
        Some(item)
    }
}

impl<I: ExactSizeIterator> ExactSizeIterator for Counted<'_, I> {
    fn len(&self) -> usize {
        self.inner.len()
    }
}
