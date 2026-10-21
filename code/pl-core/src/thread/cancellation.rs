//! A narrow live cancellation capability; canonical execution state remains actor-owned.
use std::sync::{Arc, Mutex};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Default)]
pub(super) struct InterruptHandle(Arc<Mutex<InterruptState>>);

#[derive(Debug, Default)]
struct InterruptState {
    active: Option<CancellationToken>,
    closing: bool,
}

impl InterruptHandle {
    pub(super) fn activate(&self, parent: &CancellationToken) -> ActiveExecution {
        let token = parent.child_token();
        {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing {
                token.cancel();
            }
            state.active = Some(token.clone());
        }
        ActiveExecution {
            handle: self.clone(),
            token,
        }
    }
    pub(super) fn begin_close(&self) {
        let token = {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            state.active.clone()
        };
        if let Some(token) = token {
            token.cancel();
        }
    }
    pub(super) fn is_closing(&self) -> bool {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing
    }

    /// Snapshot of the resident generation's token, if one is active.
    ///
    /// The lock is released before the caller awaits anything: waiting for the token's cancellation
    /// while holding the interrupt lock would block every other entry point. A clone is enough
    /// because a cancelled token is cancelled for every clone.
    pub(super) fn active_token(&self) -> Option<CancellationToken> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .active
            .clone()
    }

    /// Whether an external stop already cancelled the resident generation.
    ///
    /// Cancelling the input's own token and [`super::ThreadHandle::interrupt`] both cancel this
    /// token without recording an interrupted Turn, so publishing consults the token itself instead
    /// of only the interrupted/closing state.
    pub(super) fn active_cancelled(&self) -> bool {
        self.active_token()
            .is_some_and(|token| token.is_cancelled())
    }

    pub(super) fn interrupt(&self) -> bool {
        let token = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .active
            .clone();
        if let Some(token) = token {
            token.cancel();
            true
        } else {
            false
        }
    }
}

pub(super) struct ActiveExecution {
    handle: InterruptHandle,
    pub(super) token: CancellationToken,
}
impl Drop for ActiveExecution {
    fn drop(&mut self) {
        self.handle
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .active
            .take();
    }
}
