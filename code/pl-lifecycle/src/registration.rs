use std::panic::{AssertUnwindSafe, catch_unwind};

use crate::{
    AttemptId, CloseError, FailedResource, Phase, RegistrationError, ResourceId, member::EntryKind,
    scope::Scope,
};

pub(crate) type Cleanup = Box<dyn FnOnce() + Send + 'static>;

/// 同步清理回调的独占凭证；作用域或凭证释放时回调恰好执行一次。
pub struct Registration {
    release: Option<Box<dyn FnOnce() + Send + 'static>>,
}

impl Registration {
    pub(crate) fn new(release: impl FnOnce() + Send + 'static) -> Self {
        Self {
            release: Some(Box::new(release)),
        }
    }
}

impl Drop for Registration {
    fn drop(&mut self) {
        if let Some(release) = self.release.take() {
            // Cleanup panics are caught and recorded by the scope itself.
            release();
        }
    }
}

pub(crate) fn reject(cleanup: Cleanup) -> Result<Registration, RegistrationError> {
    match catch_unwind(AssertUnwindSafe(cleanup)) {
        Ok(()) => Err(RegistrationError::ScopeClosed),
        Err(_) => Err(RegistrationError::RejectedCleanupPanicked),
    }
}

impl<E: Send + Sync + 'static> Scope<E> {
    pub(crate) fn run_registration(&self, id: ResourceId) {
        let mut state = self.state();
        let Some(entry) = state.entries.get_mut(&id) else {
            return;
        };
        let EntryKind::Sync { cleanup } = &mut entry.kind else {
            return;
        };
        let Some(cleanup) = cleanup.take() else {
            return;
        };
        entry.phase = Phase::Closing;
        drop(state);
        self.changed();
        let result = catch_unwind(AssertUnwindSafe(cleanup));
        let mut state = self.state();
        if let Some(entry) = state.entries.remove(&id)
            && result.is_err()
        {
            state.diagnostics.push(FailedResource {
                resource: entry.info,
                attempt_id: AttemptId(1),
                phase: Phase::Closing,
                error: CloseError::Panicked,
                retained: false,
            });
        }
        drop(state);
        self.changed();
        self.retire_if_empty();
    }

    pub(crate) fn run_callbacks(&self) {
        let (ids, children) = {
            let state = self.state();
            (
                state
                    .entries
                    .iter()
                    .filter_map(|(&id, entry)| {
                        matches!(entry.kind, EntryKind::Sync { .. }).then_some(id)
                    })
                    .collect::<Vec<_>>(),
                state.children.clone(),
            )
        };
        for id in ids {
            self.run_registration(id);
        }
        for child in children {
            child.run_callbacks();
        }
    }
}
