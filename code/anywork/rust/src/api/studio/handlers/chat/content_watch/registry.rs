//! Bounded ownership and non-reusable identities, independent of native observation mechanics.
use std::collections::BTreeMap;

pub(crate) const MAX_CONTENT_WATCHES: usize = 32;

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum AdmissionError {
    Closed,
    Full,
    Exhausted,
}

pub(crate) struct WatchRegistry<T> {
    prefix: String,
    issued: u64,
    sealed: bool,
    entries: BTreeMap<String, T>,
}

impl<T> WatchRegistry<T> {
    pub(crate) fn new(subscription_id: &str) -> Self {
        Self {
            prefix: format!("{subscription_id}:content-watch:"),
            issued: 0,
            sealed: false,
            entries: BTreeMap::new(),
        }
    }

    pub(crate) fn insert_with(
        &mut self,
        create: impl FnOnce() -> T,
    ) -> Result<String, AdmissionError> {
        if self.sealed {
            return Err(AdmissionError::Closed);
        }
        if self.entries.len() == MAX_CONTENT_WATCHES {
            return Err(AdmissionError::Full);
        }
        let next = self
            .issued
            .checked_add(1)
            .ok_or(AdmissionError::Exhausted)?;
        let id = format!("{}{next}", self.prefix);
        self.entries.insert(id.clone(), create());
        self.issued = next;
        Ok(id)
    }

    /// The monotonic issuance watermark permits idempotent retired IDs without growing tombstones.
    /// It is only local resource bookkeeping; callers treat every ID as an opaque string.
    pub(crate) fn get(&self, id: &str) -> Result<Option<&T>, ()> {
        let serial = id
            .strip_prefix(&self.prefix)
            .and_then(|serial| serial.parse::<u64>().ok())
            .filter(|serial| *serial > 0 && *serial <= self.issued)
            .filter(|serial| id == format!("{}{serial}", self.prefix))
            .ok_or(())?;
        debug_assert!(serial <= self.issued);
        Ok(self.entries.get(id))
    }

    pub(crate) fn remove(&mut self, id: &str) {
        self.entries.remove(id);
    }

    pub(crate) fn values(&self) -> impl Iterator<Item = (&String, &T)> {
        self.entries.iter()
    }

    pub(crate) fn seal(&mut self) {
        self.sealed = true;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opening_and_unresolved_resources_hold_capacity_until_successful_removal() {
        let mut registry = WatchRegistry::new("original");
        let ids = (0..MAX_CONTENT_WATCHES)
            .map(|_| registry.insert_with(|| ()).unwrap())
            .collect::<Vec<_>>();
        assert_eq!(
            registry.insert_with(|| panic!("a refused open must not construct a resource")),
            Err(AdmissionError::Full)
        );
        // Merely looking up/cancelling a resource cannot free its capacity.
        assert!(registry.get(&ids[0]).unwrap().is_some());
        assert_eq!(registry.insert_with(|| ()), Err(AdmissionError::Full));
        registry.remove(&ids[0]);
        let replacement = registry.insert_with(|| ()).unwrap();
        assert_ne!(replacement, ids[0]);
        assert!(registry.get(&ids[0]).unwrap().is_none());
        assert!(registry.get(&replacement).unwrap().is_some());
        assert_eq!(registry.values().count(), MAX_CONTENT_WATCHES);
    }

    #[test]
    fn retired_ids_are_idempotent_but_unknown_and_foreign_ids_never_resolve() {
        let mut original = WatchRegistry::new("original");
        let mut other = WatchRegistry::new("other");
        let id = original.insert_with(|| ()).unwrap();
        let foreign = other.insert_with(|| ()).unwrap();
        assert!(original.get(&foreign).is_err());
        assert!(other.get(&id).is_err());
        assert!(original.get("original:content-watch:0").is_err());
        assert!(original.get("original:content-watch:01").is_err());
        assert!(original.get("original:content-watch:2").is_err());
        original.remove(&id);
        original.remove(&id);
        assert!(original.get(&id).unwrap().is_none());
        assert!(other.get(&foreign).unwrap().is_some());
    }

    #[test]
    fn sealing_and_identity_exhaustion_do_not_construct_late_resources() {
        let mut registry: WatchRegistry<()> = WatchRegistry::new("original");
        registry.issued = u64::MAX;
        assert_eq!(
            registry.insert_with(|| panic!("exhausted")),
            Err(AdmissionError::Exhausted)
        );
        registry.seal();
        assert_eq!(
            registry.insert_with(|| panic!("sealed")),
            Err(AdmissionError::Closed)
        );
    }
}
