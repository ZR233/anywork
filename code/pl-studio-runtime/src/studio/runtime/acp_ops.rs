//! Private ACP admission and retained-join primitives.
//!
//! Command identity, topic acceptance, and join ownership are shared by the ACP
//! account, install, and detection owners. A timed-out or dropped waiter borrows
//! the `JoinHandle`; only an observed terminal poll clears the slot, and that
//! result stays readable for the next close.

use std::collections::BTreeMap;
use std::sync::{Mutex, PoisonError};

use tokio::task::{JoinError, JoinHandle};

use crate::{AcpAuthMethod, AcpAuthMethodKind, StudioError, StudioErrorCode};

/// Canonical snapshot plus whether this command changed domain facts.
pub(super) struct TopicAcceptance<S> {
    pub snapshot: S,
    pub changed: bool,
}

/// Retained command identities. Full ledgers reject new ids; they never evict.
pub(super) const COMMAND_LEDGER_MAX: usize = 4096;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum LedgerError {
    Conflict,
    Overloaded,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) enum LedgerCheck<I> {
    Fresh,
    Replay(I),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct CommandLedger<I> {
    entries: BTreeMap<String, I>,
}

impl<I> Default for CommandLedger<I> {
    fn default() -> Self {
        Self {
            entries: BTreeMap::new(),
        }
    }
}

impl<I: Clone + PartialEq> CommandLedger<I> {
    #[cfg(test)]
    pub(super) fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    #[cfg(test)]
    pub(super) fn len(&self) -> usize {
        self.entries.len()
    }

    #[cfg(test)]
    pub(super) fn get(&self, id: &str) -> Option<&I> {
        self.entries.get(id)
    }

    /// Identity only. Capacity stays at [`Self::ensure_capacity`] so earlier
    /// domain errors keep their existing priority.
    pub(super) fn check_or_replay(
        &self,
        id: &str,
        intent: &I,
    ) -> Result<LedgerCheck<I>, LedgerError> {
        match self.entries.get(id) {
            Some(recorded) if recorded == intent => Ok(LedgerCheck::Replay(recorded.clone())),
            Some(_) => Err(LedgerError::Conflict),
            None => Ok(LedgerCheck::Fresh),
        }
    }

    pub(super) fn ensure_capacity(&self) -> Result<(), LedgerError> {
        if self.entries.len() >= COMMAND_LEDGER_MAX {
            Err(LedgerError::Overloaded)
        } else {
            Ok(())
        }
    }

    /// Insert a fresh identity. A same-intent replay is a no-op and does not evict.
    pub(super) fn record(&mut self, id: String, intent: I) -> Result<(), LedgerError> {
        match self.check_or_replay(&id, &intent)? {
            LedgerCheck::Replay(_) => Ok(()),
            LedgerCheck::Fresh => {
                self.ensure_capacity()?;
                self.entries.insert(id, intent);
                Ok(())
            }
        }
    }
}

pub(super) fn studio_error(
    code: StudioErrorCode,
    message: impl Into<String>,
    retryable: bool,
) -> anyhow::Error {
    StudioError::new(code, message, retryable).into()
}

pub(super) fn ledger_error(error: LedgerError, conflict: &str, overloaded: &str) -> anyhow::Error {
    match error {
        LedgerError::Conflict => studio_error(StudioErrorCode::Conflict, conflict, false),
        LedgerError::Overloaded => studio_error(StudioErrorCode::Overloaded, overloaded, true),
    }
}

pub(super) fn map_auth_methods(methods: Vec<pl_acp::auth::AuthMethod>) -> Vec<AcpAuthMethod> {
    methods
        .into_iter()
        .map(|method| AcpAuthMethod {
            id: method.id,
            name: method.name,
            description: method.description,
            kind: match method.kind {
                pl_acp::auth::AuthMethodKind::Agent => AcpAuthMethodKind::Agent,
                pl_acp::auth::AuthMethodKind::Terminal => AcpAuthMethodKind::Terminal,
                pl_acp::auth::AuthMethodKind::Unsupported => AcpAuthMethodKind::Unsupported,
            },
        })
        .collect()
}

impl From<crate::config::AcpProvider> for crate::AcpProvider {
    fn from(provider: crate::config::AcpProvider) -> Self {
        match provider {
            crate::config::AcpProvider::Antigravity => Self::Antigravity,
        }
    }
}

impl From<crate::AcpProvider> for crate::config::AcpProvider {
    fn from(provider: crate::AcpProvider) -> Self {
        match provider {
            crate::AcpProvider::Antigravity => Self::Antigravity,
        }
    }
}

/// Owner slot for one spawned task. The handle leaves the slot only after its
/// terminal poll has been stored.
pub(super) struct RetainedTask<T> {
    join: tokio::sync::Mutex<Option<JoinHandle<T>>>,
    outcome: Mutex<Option<Result<(), String>>>,
}

impl<T> Default for RetainedTask<T> {
    fn default() -> Self {
        Self::empty()
    }
}

#[derive(Debug)]
pub(super) enum RetainedJoin<T> {
    /// This waiter observed the terminal poll and cleared the slot.
    Observed(Result<T, JoinError>),
    /// An earlier waiter already stored the terminal result.
    Settled(Result<(), String>),
    /// No handle has been installed.
    Absent,
    /// The deadline elapsed. The original handle is still owned here.
    TimedOut,
}

impl<T> RetainedTask<T> {
    pub(super) fn empty() -> Self {
        Self {
            join: tokio::sync::Mutex::new(None),
            outcome: Mutex::new(None),
        }
    }

    pub(super) fn running(handle: JoinHandle<T>) -> Self {
        Self {
            join: tokio::sync::Mutex::new(Some(handle)),
            outcome: Mutex::new(None),
        }
    }

    /// Install while this slot is still private to the admitting owner.
    pub(super) fn install(&self, handle: JoinHandle<T>) {
        *self
            .join
            .try_lock()
            .expect("retained task is private until published") = Some(handle);
    }

    pub(super) fn observed(&self) -> Option<Result<(), String>> {
        self.outcome
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }

    /// `None` means another waiter currently holds the join mutex.
    #[cfg(test)]
    pub(super) fn running_handle_retained(&self) -> Option<bool> {
        let slot = self.join.try_lock().ok()?;
        Some(slot.as_ref().is_some_and(|handle| !handle.is_finished()))
    }

    #[cfg(test)]
    pub(super) fn join_wait_in_progress(&self) -> bool {
        self.join.try_lock().is_err()
    }

    pub(super) fn finished(&self) -> bool {
        self.join
            .try_lock()
            .is_ok_and(|slot| slot.as_ref().is_none_or(|handle| handle.is_finished()))
    }

    #[cfg(test)]
    pub(super) async fn slot_is_empty(&self) -> bool {
        self.join.lock().await.is_none()
    }

    /// Non-blocking harvest. A running or borrowed handle stays in the slot.
    pub(super) async fn try_reap(&self) -> Option<Result<T, JoinError>> {
        let Ok(mut slot) = self.join.try_lock() else {
            return None;
        };
        if slot.as_ref().is_none_or(|handle| !handle.is_finished()) {
            return None;
        }
        let joined = slot.as_mut().expect("finished handle is present").await;
        self.remember(&joined);
        slot.take();
        Some(joined)
    }

    pub(super) async fn join(&self) -> RetainedJoin<T> {
        self.join_observed().await
    }

    /// Wait until `deadline`. Timeout and cancellation drop only this waiter.
    pub(super) async fn join_until(&self, deadline: tokio::time::Instant) -> RetainedJoin<T> {
        if let Some(joined) = self.try_reap().await {
            return RetainedJoin::Observed(joined);
        }
        if self.slot_empty_now() {
            return self.settled_or_absent();
        }
        tokio::select! {
            biased;
            joined = self.join_observed() => joined,
            _ = tokio::time::sleep_until(deadline) => RetainedJoin::TimedOut,
        }
    }

    async fn join_observed(&self) -> RetainedJoin<T> {
        let mut slot = self.join.lock().await;
        let Some(handle) = slot.as_mut() else {
            return self.settled_or_absent();
        };
        let joined = handle.await;
        self.remember(&joined);
        slot.take();
        RetainedJoin::Observed(joined)
    }

    fn slot_empty_now(&self) -> bool {
        self.join.try_lock().is_ok_and(|slot| slot.is_none())
    }

    fn remember(&self, joined: &Result<T, JoinError>) {
        let observed = match joined {
            Ok(_) => Ok(()),
            Err(error) => Err(error.to_string()),
        };
        *self.outcome.lock().unwrap_or_else(PoisonError::into_inner) = Some(observed);
    }

    fn settled_or_absent(&self) -> RetainedJoin<T> {
        match self.observed() {
            Some(result) => RetainedJoin::Settled(result),
            None => RetainedJoin::Absent,
        }
    }
}

pub(super) fn retained_output<T>(
    joined: RetainedJoin<T>,
    map_ok: impl FnOnce(T) -> Result<(), String>,
    join_error: impl FnOnce(&JoinError) -> String,
) -> Result<(), String> {
    match joined {
        RetainedJoin::Observed(Ok(value)) => map_ok(value),
        RetainedJoin::Observed(Err(error)) => Err(join_error(&error)),
        RetainedJoin::Settled(result) => result,
        RetainedJoin::Absent => Ok(()),
        RetainedJoin::TimedOut => Err("retained task is still running".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    #[test]
    fn ledger_replays_same_intent_and_rejects_conflict_without_eviction() {
        let mut ledger = CommandLedger::default();
        assert_eq!(
            ledger.check_or_replay("op", &"start").unwrap(),
            LedgerCheck::Fresh
        );
        ledger.record("op".into(), "start").unwrap();
        assert_eq!(
            ledger.check_or_replay("op", &"start").unwrap(),
            LedgerCheck::Replay("start")
        );
        assert_eq!(
            ledger.check_or_replay("op", &"cancel"),
            Err(LedgerError::Conflict)
        );
        assert_eq!(ledger.get("op"), Some(&"start"));
        assert_eq!(ledger.len(), 1);
    }

    #[test]
    fn full_ledger_rejects_a_new_identity_and_keeps_existing_ones() {
        let mut ledger = CommandLedger::default();
        for index in 0..COMMAND_LEDGER_MAX {
            ledger.record(index.to_string(), index).unwrap();
        }
        assert_eq!(ledger.ensure_capacity(), Err(LedgerError::Overloaded));
        assert_eq!(
            ledger.record(COMMAND_LEDGER_MAX.to_string(), 0),
            Err(LedgerError::Overloaded)
        );
        assert_eq!(ledger.len(), COMMAND_LEDGER_MAX);
        assert_eq!(
            ledger.check_or_replay("0", &0).unwrap(),
            LedgerCheck::Replay(0)
        );
        ledger.record("0".into(), 0).unwrap();
        assert_eq!(ledger.len(), COMMAND_LEDGER_MAX);
    }

    #[tokio::test]
    async fn join_timeout_retains_handle_and_later_join_observes_result() {
        let (release, released) = tokio::sync::oneshot::channel();
        let task = Arc::new(RetainedTask::running(tokio::spawn(async move {
            released.await.unwrap();
            7
        })));
        let deadline = tokio::time::Instant::now() + Duration::from_millis(40);
        assert!(matches!(
            task.join_until(deadline).await,
            RetainedJoin::TimedOut
        ));
        assert_eq!(task.running_handle_retained(), Some(true));
        release.send(()).unwrap();
        let joined = task
            .join_until(tokio::time::Instant::now() + Duration::from_secs(2))
            .await;
        assert!(matches!(joined, RetainedJoin::Observed(Ok(7))));
        assert!(task.slot_is_empty().await);
        assert!(matches!(task.join().await, RetainedJoin::Settled(Ok(()))));
    }

    #[tokio::test]
    async fn dropped_join_waiter_does_not_detach_handle() {
        let task = Arc::new(RetainedTask::running(tokio::spawn(
            std::future::pending::<()>(),
        )));
        let waiting = task.join();
        tokio::pin!(waiting);
        let _ = tokio::time::timeout(Duration::from_millis(20), &mut waiting).await;
        drop(waiting);
        assert_eq!(task.running_handle_retained(), Some(true));
        assert!(task.try_reap().await.is_none());
        assert_eq!(task.running_handle_retained(), Some(true));
    }

    #[tokio::test]
    async fn observed_panic_is_cleared_once_and_remains_visible() {
        let task = RetainedTask::running(tokio::spawn(async { panic!("boom") }));
        assert!(matches!(task.join().await, RetainedJoin::Observed(Err(_))));
        assert!(task.slot_is_empty().await);
        assert!(matches!(task.join().await, RetainedJoin::Settled(Err(_))));
        assert!(task.try_reap().await.is_none());
    }

    #[tokio::test]
    async fn shared_deadline_does_not_reset_per_task() {
        let started = Instant::now();
        let slow = Arc::new(RetainedTask::running(tokio::spawn(
            std::future::pending::<()>(),
        )));
        let fast = Arc::new(RetainedTask::running(tokio::spawn(async {})));
        let deadline = tokio::time::Instant::now() + Duration::from_millis(80);
        let (slow_join, fast_join) =
            tokio::join!(slow.join_until(deadline), fast.join_until(deadline));
        assert!(matches!(fast_join, RetainedJoin::Observed(Ok(()))));
        assert!(matches!(slow_join, RetainedJoin::TimedOut));
        assert!(started.elapsed() < Duration::from_millis(500));
        assert_eq!(slow.running_handle_retained(), Some(true));
    }
}
