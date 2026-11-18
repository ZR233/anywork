//! A narrow live cancellation capability; canonical execution state remains actor-owned.
use std::sync::{Arc, Mutex};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Default)]
pub(super) struct InterruptHandle {
    state: Arc<Mutex<InterruptState>>,
    shutdown: CancellationToken,
    deletion: CancellationToken,
}

#[derive(Debug, Default)]
struct InterruptState {
    active: Option<CancellationToken>,
    closing: Option<super::owner::ClosePurpose>,
    /// Monotonic count of stop requests issued against this Thread.
    ///
    /// Explicit stops advance this count; internal draining cancels only its original token.
    /// The owner compares a run's starting count so a later user stop keeps the queue paused.
    stops: u64,
}

impl InterruptHandle {
    /// Installs the one active token under the same lock used by direct Stop and shutdown.
    pub(super) fn activate(&self, parent: &CancellationToken) -> ActiveExecution {
        let token = parent.child_token();
        {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing.is_some() || self.shutdown.is_cancelled() {
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
        self.begin_close_with_purpose(super::owner::ClosePurpose::Preserve);
    }

    pub(super) fn begin_delete(&self) {
        self.begin_close_with_purpose(super::owner::ClosePurpose::Delete);
    }

    fn begin_close_with_purpose(&self, purpose: super::owner::ClosePurpose) {
        {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            // Deletion stays sealed even if a last-handle drop or an older preserving waiter
            // reaches this same cancellation boundary while resource cleanup is being retried.
            if state.closing != Some(super::owner::ClosePurpose::Delete) {
                state.closing = Some(purpose);
            }
        }
        if purpose == super::owner::ClosePurpose::Delete {
            self.deletion.cancel();
        }
        self.request_shutdown();
    }

    pub(super) fn is_deleting(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing
            == Some(super::owner::ClosePurpose::Delete)
    }

    pub(super) fn deletion_token(&self) -> CancellationToken {
        self.deletion.clone()
    }

    pub(super) fn request_shutdown(&self) {
        // No actor/storage wait and no mutex held while cancellation wakes executors.
        self.shutdown.cancel();
        let token = self.active_token();
        if let Some(token) = token {
            token.cancel();
        }
    }

    pub(super) fn background_token(&self) -> CancellationToken {
        self.shutdown.child_token()
    }

    pub(super) fn is_closing(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing
            .is_some()
    }

    /// Snapshot of the resident generation's token, if one is active.
    ///
    /// The lock is released before the caller awaits anything: waiting for the token's cancellation
    /// while holding the interrupt lock would block every other entry point. A clone is enough
    /// because a cancelled token is cancelled for every clone.
    pub(super) fn active_token(&self) -> Option<CancellationToken> {
        self.state
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
        let token = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.stops = state.stops.saturating_add(1);
            state.active.clone()
        };
        if let Some(token) = token {
            token.cancel();
            true
        } else {
            false
        }
    }

    /// Monotonic count of stop requests issued against this Thread.
    ///
    /// This records explicit stops independently of internal cancellation and physical completion.
    pub(super) fn stops(&self) -> u64 {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .stops
    }
}

pub(super) struct ActiveExecution {
    handle: InterruptHandle,
    pub(super) token: CancellationToken,
}

impl Drop for ActiveExecution {
    fn drop(&mut self) {
        self.handle
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .active
            .take();
    }
}
