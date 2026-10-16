//! Product-independent Turn admission gating.
//!
//! A gate answers one question about one Thread: may the next Turn start? It is deliberately
//! separate from durable input admission, from the serial execution driver and from the storage
//! safety point, so a host can hold new Turns back without touching any of them — and without core
//! knowing why the host holds them.
//!
//! Closing is expressed as a *reason held by RAII*: every [`TurnAdmissionGate::close`] call returns
//! one [`TurnAdmissionHold`], and the gate admits again only while no such hold is alive. Several
//! reasons can therefore close the same gate at once, and dropping one of them can never reopen a
//! gate that another reason still holds: there is no unconditional `open` that a stale caller could
//! invoke. The counterpart is [`TurnAdmissionPermit`], held by a Turn that already passed the gate,
//! so a reason taken while that Turn runs holds back the *next* Turn only.

use std::sync::{Arc, Mutex};

use tokio::sync::watch;

/// Live gate state.
///
/// The lock is the only authority. The watch channel published next to it is a wake-up for waiters,
/// never a second copy of this fact.
#[derive(Debug, Default)]
struct GateState {
    /// Live reasons the gate is closed, one per [`TurnAdmissionHold`].
    ///
    /// Bounded by the number of holds a process can actually keep alive, so it cannot overflow from
    /// holding reasons.
    holds: usize,
    /// Turns that passed the gate and have not ended yet, one per [`TurnAdmissionPermit`].
    admitted_turns: usize,
}

/// Published hold transition. It is descriptive only, so a waiter still re-reads the state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum GateSignal {
    Closed,
    Open,
}

#[derive(Debug)]
struct GateInner {
    state: Mutex<GateState>,
    changed: watch::Sender<GateSignal>,
}

/// A shared gate that holds back the next Turn of one Thread.
///
/// The handle is cheap to clone and every clone addresses the same gate, so the host keeps one clone
/// to close and release admission while the owner keeps another to wait on. A gate starts open, so a
/// Thread assembled without one behaves exactly as an ungated Thread.
#[derive(Clone)]
pub struct TurnAdmissionGate {
    inner: Arc<GateInner>,
}

impl std::fmt::Debug for TurnAdmissionGate {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Never block a diagnostic print behind a concurrent close, mirroring the effect window's
        // own `Debug` contract.
        let mut debug = formatter.debug_struct("TurnAdmissionGate");
        match self.inner.state.try_lock() {
            Ok(state) => debug
                .field("holds", &state.holds)
                .field("admitted_turns", &state.admitted_turns)
                .finish(),
            Err(_) => debug.finish_non_exhaustive(),
        }
    }
}

impl Default for TurnAdmissionGate {
    fn default() -> Self {
        Self::new()
    }
}

impl TurnAdmissionGate {
    /// Creates an open gate: no reason to hold new Turns, exactly like an ungated Thread.
    pub fn new() -> Self {
        Self {
            inner: Arc::new(GateInner {
                state: Mutex::new(GateState::default()),
                changed: watch::channel(GateSignal::Open).0,
            }),
        }
    }

    /// Closes admission until the returned hold is dropped.
    ///
    /// Every call is one independent reason, and its hold is the only way this reason can be
    /// released. Two callers therefore cannot release each other's reason, and a reason taken later
    /// is not cancelled by an earlier release.
    pub fn close(&self) -> TurnAdmissionHold {
        let holds = {
            let mut state = self.lock();
            state.holds += 1;
            state.holds
        };
        self.publish(holds);
        TurnAdmissionHold { gate: self.clone() }
    }

    /// Whether a Turn may be admitted right now.
    pub fn is_open(&self) -> bool {
        self.lock().holds == 0
    }

    /// gate 已开放，且没有仍在执行的已准入 Turn。
    ///
    /// 关闭后的排空检查应在持有关闭原因期间查询 `admitted_turns() == 0`：此时没有在跑的
    /// Turn，下一条 Turn 也必须等待。`is_clear` 在任何关闭原因仍存活时都返回 `false`。
    pub fn is_clear(&self) -> bool {
        let state = self.lock();
        state.holds == 0 && state.admitted_turns == 0
    }

    /// Number of live reasons keeping the gate closed.
    pub fn holds(&self) -> usize {
        self.lock().holds
    }

    /// Number of Turns that passed the gate and have not ended yet.
    pub fn admitted_turns(&self) -> usize {
        self.lock().admitted_turns
    }

    /// Claims admission for one Turn, or `None` while the gate is closed.
    ///
    /// The check and the claim happen under one lock: a caller that observed `Some` provably held
    /// admission at that instant, and a reason taken immediately afterwards cannot revoke it — it
    /// only holds back the next Turn. The caller holds the returned permit until its Turn ends.
    pub fn try_admit(&self) -> Option<TurnAdmissionPermit> {
        let mut state = self.lock();
        if state.holds > 0 {
            return None;
        }
        state.admitted_turns += 1;
        Some(TurnAdmissionPermit {
            gate: Some(self.clone()),
        })
    }

    /// Subscribes to hold transitions.
    ///
    /// The subscription must be taken *before* the state is read: subscribing marks the current
    /// value as seen, so a caller that read the state first could end up waiting for a gate that
    /// already opened.
    pub(crate) fn subscribe(&self) -> TurnAdmissionWait {
        TurnAdmissionWait {
            changed: self.inner.changed.subscribe(),
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, GateState> {
        self.inner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn publish(&self, holds: usize) {
        let signal = if holds == 0 {
            GateSignal::Open
        } else {
            GateSignal::Closed
        };
        self.inner.changed.send_replace(signal);
    }
}

/// One live reason keeping a [`TurnAdmissionGate`] closed.
///
/// Dropping the hold releases exactly this reason. Two holds keep the gate closed until both are
/// gone, so an older release cannot reopen a gate that a newer reason closed.
#[derive(Debug)]
pub struct TurnAdmissionHold {
    gate: TurnAdmissionGate,
}

impl Drop for TurnAdmissionHold {
    fn drop(&mut self) {
        let holds = {
            let mut state = self.gate.lock();
            state.holds -= 1;
            state.holds
        };
        self.gate.publish(holds);
    }
}

/// Proof that one Turn passed a [`TurnAdmissionGate`].
///
/// The permit is held for the whole Turn, so reasons taken later only hold back the *next* Turn.
/// Dropping it never reopens anything: it stops counting the Turn as admitted, which is what
/// [`TurnAdmissionGate::is_clear`] and [`TurnAdmissionGate::admitted_turns`] report.
#[derive(Debug)]
pub struct TurnAdmissionPermit {
    /// `None` for an owner assembled without a gate: that Turn is admitted unconditionally and there
    /// is no gate to count it in.
    gate: Option<TurnAdmissionGate>,
}

impl TurnAdmissionPermit {
    /// Admission of an owner that has no gate; it never affects a gate.
    pub(crate) fn ungated() -> Self {
        Self { gate: None }
    }
}

impl Drop for TurnAdmissionPermit {
    fn drop(&mut self) {
        let Some(gate) = &self.gate else {
            return;
        };
        let mut state = gate.lock();
        state.admitted_turns -= 1;
    }
}

/// One observation stream over a gate's hold transitions.
pub(crate) struct TurnAdmissionWait {
    changed: watch::Receiver<GateSignal>,
}

impl TurnAdmissionWait {
    /// Resolves after the next published transition. `false` means no gate handle is left, so
    /// admission can never be granted again.
    pub(crate) async fn changed(&mut self) -> bool {
        self.changed.changed().await.is_ok()
    }
}
