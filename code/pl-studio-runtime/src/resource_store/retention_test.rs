//! Test-only gate inside the real blocking copy, keyed by one resource root.
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, OnceLock, Weak};

use tokio::sync::Notify;

#[derive(Default)]
struct State {
    started: bool,
    released: bool,
}

#[derive(Default)]
struct Gate {
    state: Mutex<State>,
    started: Notify,
    released: Condvar,
}

fn gates() -> &'static Mutex<BTreeMap<PathBuf, Weak<Gate>>> {
    static GATES: OnceLock<Mutex<BTreeMap<PathBuf, Weak<Gate>>>> = OnceLock::new();
    GATES.get_or_init(Mutex::default)
}

/// Dropping the registration releases a blocked copy even if a test assertion fails.
pub(crate) struct RetentionGate {
    root: PathBuf,
    gate: Arc<Gate>,
}

pub(crate) fn pause(root: PathBuf) -> RetentionGate {
    let gate = Arc::new(Gate::default());
    let mut registered = gates().lock().unwrap();
    assert!(
        registered.get(&root).and_then(Weak::upgrade).is_none(),
        "resource root already has a test retention gate"
    );
    registered.insert(root.clone(), Arc::downgrade(&gate));
    RetentionGate { root, gate }
}

impl RetentionGate {
    pub(crate) async fn wait_started(&self) {
        loop {
            let notified = self.gate.started.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if self.gate.state.lock().unwrap().started {
                return;
            }
            notified.await;
        }
    }

    pub(crate) fn release(&self) {
        self.gate.state.lock().unwrap().released = true;
        self.gate.released.notify_all();
    }
}

impl Drop for RetentionGate {
    fn drop(&mut self) {
        self.release();
        let mut gates = gates().lock().unwrap();
        if gates
            .get(&self.root)
            .and_then(Weak::upgrade)
            .is_some_and(|gate| Arc::ptr_eq(&gate, &self.gate))
        {
            gates.remove(&self.root);
        }
    }
}

pub(super) fn wait_if_registered(root: &Path) {
    let gate = gates().lock().unwrap().get(root).and_then(Weak::upgrade);
    let Some(gate) = gate else { return };
    let mut state = gate.state.lock().unwrap();
    if state.started {
        return;
    }
    state.started = true;
    gate.started.notify_waiters();
    while !state.released {
        state = gate.released.wait(state).unwrap();
    }
}
