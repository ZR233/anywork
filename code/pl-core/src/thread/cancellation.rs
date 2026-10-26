//! A narrow live cancellation capability; canonical execution state remains actor-owned.
use std::sync::{Arc, Mutex};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Default)]
pub(super) struct InterruptHandle(Arc<Mutex<InterruptState>>);

#[derive(Debug, Default)]
struct InterruptState {
    active: Option<CancellationToken>,
    closing: bool,
    /// Monotonic count of stop requests issued against this Thread.
    ///
    /// A replacement cancels the preparing generation itself and remembers the count it produced, so
    /// any later stop — the public interrupt, a Turn stop, an execution stop — makes the count differ
    /// and is never mistaken for the replacement it did not cause.
    stops: u64,
}

impl InterruptHandle {
    /// Starts the next execution generation, optionally bound to the stop count that authorized it.
    ///
    /// The comparison and the installation share one lock acquisition, so a queued Turn authorized
    /// by an earlier stop generation can never lose a stop between its check and its start: a stop
    /// that already arrived makes the fresh generation born cancelled — it settles as stopped
    /// instead of making the request that stop never authorized — and a stop that arrives afterwards
    /// cancels the token this call installed.
    pub(super) fn activate(
        &self,
        parent: &CancellationToken,
        authorized_stops: Option<u64>,
    ) -> ActiveExecution {
        let token = parent.child_token();
        {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing || authorized_stops.is_some_and(|authorized| authorized != state.stops)
            {
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
        self.interrupt_generation().0
    }

    /// Cancels the active generation and returns the exact stop generation it produced.
    ///
    /// The counter and the token snapshot are taken under one lock acquisition, so an internal caller
    /// (a replacement cancelling its own preparing generation) records a generation that is provably its
    /// own: a concurrent external stop can only ever produce a *later* number, which is what keeps the two
    /// cancellations distinguishable without a second read that another thread could slip between.
    pub(super) fn interrupt_generation(&self) -> (bool, u64) {
        let (token, generation) = {
            let mut state = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.stops = state.stops.saturating_add(1);
            (state.active.clone(), state.stops)
        };
        match token {
            Some(token) => {
                token.cancel();
                (true, generation)
            }
            None => (false, generation),
        }
    }

    /// Monotonic count of stop requests issued against this Thread.
    ///
    /// It is the observable "an external stop happened" state: a caller that cancels for its own reason
    /// records the count its cancellation produced, and any later stop makes the count differ.
    pub(super) fn stops(&self) -> u64 {
        self.0
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
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .active
            .take();
    }
}
