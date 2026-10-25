//! One runtime-owned source per original project; no global cache and no reconstructed origins.
use super::super::observation_ids::ObservationIds;
use super::source::{SkillsSnapshot, SkillsSource};
use pl_protocol::products::identity::ProductReadOrigin;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

struct State {
    sealed: bool,
    sources: BTreeMap<String, Arc<SkillsSource>>,
}
pub(crate) struct SkillsSources {
    ids: ObservationIds,
    state: Mutex<State>,
}
impl SkillsSources {
    pub(in crate::studio::runtime) fn new(ids: ObservationIds) -> Arc<Self> {
        Arc::new(Self {
            ids,
            state: Mutex::new(State {
                sealed: false,
                sources: BTreeMap::new(),
            }),
        })
    }
    pub(crate) fn source(&self, project_id: &str) -> Result<Arc<SkillsSource>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        if let Some(source) = state.sources.get(project_id) {
            return Ok(source.clone());
        }
        let source = SkillsSource::new(
            ProductReadOrigin {
                owner_epoch: self.ids.epoch().to_owned(),
                incarnation: self.ids.next()?,
            },
            project_id.to_owned(),
        );
        source.publish(&pl_protocol::ObservedResource::uninitialized(
            crate::studio::ids::unix_seconds(),
        ))?;
        state.sources.insert(project_id.to_owned(), source.clone());
        Ok(source)
    }
    pub(crate) fn find(
        &self,
        origin: &ProductReadOrigin,
    ) -> Result<Arc<SkillsSource>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        state
            .sources
            .values()
            .find(|source| source.origin() == origin)
            .cloned()
            .ok_or_else(cancelled)
    }
    /// Called at the catalog's original publish boundary, including Stale and Stopped changes.
    pub(crate) fn publish(
        &self,
        snapshot: &crate::SkillsStateSnapshot,
    ) -> Result<Arc<SkillsSnapshot>, StudioError> {
        let source = {
            let state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.sealed {
                if !matches!(&snapshot.state, pl_protocol::ObservedResource::Stopped(_)) {
                    return Err(cancelled());
                }
                state
                    .sources
                    .get(&snapshot.project_id)
                    .cloned()
                    .ok_or_else(cancelled)?
            } else {
                drop(state);
                self.source(&snapshot.project_id)?
            }
        };
        let captured = crate::StudioSkillsStateSnapshot::from(snapshot.clone());
        source.publish(&captured.state)
    }
    pub(crate) fn seal(&self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.sealed = true;
        for source in state.sources.values() {
            source.seal();
        }
    }
    pub(crate) fn finish_close(&self) {
        let sources = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.sealed = true;
            std::mem::take(&mut state.sources)
        };
        for source in sources.into_values() {
            source.finish_close();
        }
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Original Skills owner is closing or replaced",
        false,
    )
}
