//! Test-only observations at the actual index access/iteration boundary.
//! These count logical records, not std::BTreeMap's private comparison/tree nodes.
use std::{
    cell::{Cell, RefCell},
    collections::{BTreeMap, BTreeSet},
    ops::{Index, RangeBounds},
};

#[derive(Debug, Clone, Default)]
pub(in crate::studio) struct Access<K> {
    pub reads: u64,
    pub writes: u64,
    pub misses: u64,
    pub keys: BTreeSet<K>,
}

struct Probe<K> {
    enabled: Cell<bool>,
    access: RefCell<Access<K>>,
}
impl<K: Ord + Clone> Probe<K> {
    fn read(&self, key: &K, hit: bool) {
        if self.enabled.get() {
            let mut access = self.access.borrow_mut();
            if hit {
                access.reads += 1;
                access.keys.insert(key.clone());
            } else {
                access.misses += 1;
            }
        }
    }
    fn write(&self, key: &K) {
        if self.enabled.get() {
            let mut access = self.access.borrow_mut();
            access.writes += 1;
            access.keys.insert(key.clone());
        }
    }
}

pub(super) struct ObservedMap<K, V> {
    inner: BTreeMap<K, V>,
    probe: Probe<K>,
}
impl<K: Ord, V> Default for ObservedMap<K, V> {
    fn default() -> Self {
        Self {
            inner: BTreeMap::new(),
            probe: Probe {
                enabled: Cell::new(false),
                access: RefCell::new(Access {
                    reads: 0,
                    writes: 0,
                    misses: 0,
                    keys: BTreeSet::new(),
                }),
            },
        }
    }
}
impl<K: Ord + Clone, V> ObservedMap<K, V> {
    pub fn begin(&self) {
        *self.probe.access.borrow_mut() = Access {
            reads: 0,
            writes: 0,
            misses: 0,
            keys: BTreeSet::new(),
        };
        self.probe.enabled.set(true);
    }
    pub fn finish(&self) -> Access<K> {
        self.probe.enabled.set(false);
        self.probe.access.borrow().clone()
    }
    pub fn get(&self, key: &K) -> Option<&V> {
        let result = self.inner.get(key);
        self.probe.read(key, result.is_some());
        result
    }
    pub fn insert(&mut self, key: K, value: V) -> Option<V> {
        self.probe.write(&key);
        self.inner.insert(key, value)
    }
    pub fn remove(&mut self, key: &K) -> Option<V> {
        let result = self.inner.remove(key);
        if result.is_some() {
            self.probe.write(key);
        } else {
            self.probe.read(key, false);
        }
        result
    }
    pub fn range<R: RangeBounds<K>>(&self, range: R) -> impl DoubleEndedIterator<Item = (&K, &V)> {
        ObservedIter {
            inner: self.inner.range(range),
            probe: &self.probe,
        }
    }
    pub fn values(&self) -> impl DoubleEndedIterator<Item = &V> {
        ObservedIter {
            inner: self.inner.iter(),
            probe: &self.probe,
        }
        .map(|(_, value)| value)
    }
    pub fn len(&self) -> usize {
        self.inner.len()
    }
    pub fn is_empty(&self) -> bool {
        self.inner.is_empty()
    }
}
impl<K: Ord + Clone, V> Index<&K> for ObservedMap<K, V> {
    type Output = V;
    fn index(&self, key: &K) -> &V {
        self.get(key).expect("index key exists")
    }
}

struct ObservedIter<'a, K, I> {
    inner: I,
    probe: &'a Probe<K>,
}
impl<'a, K: Ord + Clone + 'a, V: 'a, I> Iterator for ObservedIter<'a, K, I>
where
    I: Iterator<Item = (&'a K, &'a V)>,
{
    type Item = (&'a K, &'a V);
    fn next(&mut self) -> Option<Self::Item> {
        let result = self.inner.next();
        if let Some((key, _)) = result {
            self.probe.read(key, true);
        }
        result
    }
}
impl<'a, K: Ord + Clone + 'a, V: 'a, I> DoubleEndedIterator for ObservedIter<'a, K, I>
where
    I: DoubleEndedIterator<Item = (&'a K, &'a V)>,
{
    fn next_back(&mut self) -> Option<Self::Item> {
        let result = self.inner.next_back();
        if let Some((key, _)) = result {
            self.probe.read(key, true);
        }
        result
    }
}

#[derive(Debug)]
pub(in crate::studio) struct Visits {
    pub members: Access<(u64, u64)>,
    pub heads: Access<u64>,
}
impl super::PresentationState {
    pub(in crate::studio) fn begin_cost_observation(&self) {
        self.members.begin();
        self.blocks.begin();
        self.frozen_headers.begin();
    }
    pub(in crate::studio) fn finish_cost_observation(&self) -> Visits {
        let members = self.members.finish();
        let mut heads = self.blocks.finish();
        let frozen = self.frozen_headers.finish();
        heads.reads += frozen.reads;
        heads.writes += frozen.writes;
        heads.misses += frozen.misses;
        heads.keys.extend(frozen.keys);
        Visits { members, heads }
    }
    pub(in crate::studio) fn resident_member_count(&self) -> usize {
        self.members.len()
    }
}
