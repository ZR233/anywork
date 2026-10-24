//! Opening leases bridge workspace lookup, physical preparation and transfer registration.
use super::*;
use tokio::sync::Notify;

#[derive(Debug, Default)]
struct Workspace {
    opening: usize,
    sealed: bool,
}

#[derive(Debug, Default)]
struct State {
    sealed: bool,
    opening: usize,
    workspaces: HashMap<String, Workspace>,
}

#[derive(Debug, Default)]
struct Inner {
    state: std::sync::Mutex<State>,
    changed: Notify,
}

#[derive(Debug, Default)]
pub(super) struct Admission(Arc<Inner>);

#[derive(Debug)]
pub(crate) struct OpeningLease {
    inner: Arc<Inner>,
    workspace: String,
}

impl Admission {
    pub(super) fn is_open(&self, workspace: &str) -> bool {
        let state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        !state.sealed
            && !state
                .workspaces
                .get(workspace)
                .is_some_and(|value| value.sealed)
    }

    pub(super) fn enter(&self, workspace: &str) -> Result<OpeningLease, RemoteError> {
        let mut state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(remote_error(
                RemoteErrorCode::RemoteDisconnected,
                "file admission is closed",
            ));
        }
        if state
            .workspaces
            .get(workspace)
            .is_some_and(|value| value.sealed)
        {
            return Err(remote_error(
                RemoteErrorCode::WorkspaceNotFound,
                "workspace file admission is closing",
            ));
        }
        let total = state.opening.checked_add(1).ok_or_else(exhausted)?;
        let value = state.workspaces.entry(workspace.to_owned()).or_default();
        value.opening = value.opening.checked_add(1).ok_or_else(exhausted)?;
        state.opening = total;
        Ok(OpeningLease {
            inner: self.0.clone(),
            workspace: workspace.to_owned(),
        })
    }

    pub(super) async fn seal_workspace(&self, workspace: &str) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let idle = {
                let mut state = self
                    .0
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let value = state.workspaces.entry(workspace.to_owned()).or_default();
                value.sealed = true;
                value.opening == 0
            };
            if idle {
                return;
            }
            changed.await;
        }
    }

    pub(super) async fn seal_all(&self) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let idle = {
                let mut state = self
                    .0
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.sealed = true;
                state.opening == 0
            };
            if idle {
                return;
            }
            changed.await;
        }
    }

    pub(super) fn forget_closed_workspace(&self, workspace: &str) {
        let mut state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Called only after the authoritative workspace registry is closed. Late admission
        // must still resolve that registry *after* acquiring its lease, so it cannot open IO.
        // Concurrent closes must not erase a late lookup's live counter.
        if state
            .workspaces
            .get(workspace)
            .is_some_and(|value| value.opening == 0)
        {
            state.workspaces.remove(workspace);
        }
    }
}

impl Drop for OpeningLease {
    fn drop(&mut self) {
        {
            let mut state = self
                .inner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            // A live lease prevents removal of its workspace counter; one non-Clone lease
            // corresponds to exactly one increment, and no IO is performed under this lock.
            let value = state
                .workspaces
                .get_mut(&self.workspace)
                .expect("live opening lease retains its counter");
            value.opening -= 1;
            if value.opening == 0 && !value.sealed {
                state.workspaces.remove(&self.workspace);
            }
            state.opening -= 1;
        }
        self.inner.changed.notify_waiters();
    }
}
