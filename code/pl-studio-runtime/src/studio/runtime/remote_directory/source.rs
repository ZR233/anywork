use pl_protocol::products::identity::ProductReadOrigin;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::BTreeSet;
use std::sync::{Arc, Mutex};

struct State {
    sealed: bool,
    cursors: BTreeSet<(String, String)>,
}
/// Only cleanup responsibility is retained here; listing contents live solely in their read scope.
pub(in crate::studio) struct RemoteDirectorySource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
}
impl RemoteDirectorySource {
    pub(in crate::studio) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        Arc::new(Self {
            origin,
            state: Mutex::new(State {
                sealed: false,
                cursors: BTreeSet::new(),
            }),
        })
    }
    pub(super) fn origin(&self) -> ProductReadOrigin {
        self.origin.clone()
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        if self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed
        {
            Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "Remote directory reads are closing",
                false,
            ))
        } else {
            Ok(())
        }
    }
    // An accepted browse must register even after seal; shutdown waits read calls before cleanup.
    pub(super) fn remember(&self, alias: &str, previous: Option<&str>, next: Option<&str>) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(previous) = previous {
            state.cursors.remove(&(alias.into(), previous.into()));
        }
        if let Some(next) = next {
            state.cursors.insert((alias.into(), next.into()));
        }
    }
    pub(super) fn forget(&self, alias: &str, cursor: &str) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cursors
            .remove(&(alias.into(), cursor.into()));
    }
    pub(in crate::studio) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
    }
    /// Retry only the original cursor set. Failures remain registered, including unknown openings.
    pub(in crate::studio) async fn finish_close(
        &self,
        runtime: &super::super::StudioRuntime,
    ) -> anyhow::Result<()> {
        self.seal();
        let cursors: Vec<_> = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cursors
            .iter()
            .cloned()
            .collect();
        let mut failures = Vec::new();
        for (alias, cursor) in cursors {
            match runtime.close_remote_directory(&alias, cursor.clone()).await {
                Ok(()) => self.forget(&alias, &cursor),
                Err(error) => failures.push(error),
            }
        }
        if !failures.is_empty() {
            let diagnostics = failures
                .iter()
                .map(|error| format!("{error:#}"))
                .collect::<Vec<_>>()
                .join("; ");
            anyhow::bail!(
                "Remote directory cursor cleanup retained {} failures: {diagnostics}",
                failures.len()
            );
        }
        Ok(())
    }
}
