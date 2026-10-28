//! Explicit close responsibility for history connections and the lifetime of their state.
//!
//! A history handle shares one connection state between the Thread's writer, its readers and the
//! coordinator's weak registry, so its last strong reference drops in whichever task released it —
//! and sometimes with no Tokio runtime left at all. Dropping a pool is explicitly *not* a join point:
//! its remaining connections go away inside whatever task dropped the last handle.
//!
//! This owner therefore tracks two facts about the same resource, in one place:
//!
//! * the **lifetime of each real `HistoryStoreState`**, registered synchronously when the state is
//!   built. Every clone of the handle — including the one a `Session` keeps — pins the same token, so
//!   "a legitimate holder still exists" is something the final close waits on instead of a hope;
//! * the **close duty of each handed-over connection**. The state's last `Drop` ends its lifetime and
//!   takes over published connections under one lock. Unpublished guards hand their original pools
//!   to this same owner on failure/cancellation while the state is still pinned, so neither path has
//!   a window in which both the lifetime and its open-pool responsibility disappear.
//!
//! Each close attempt carries its own identity: only the current attempt of a duty may write its
//! outcome, so a late observer can neither drop a newer task nor overwrite it with an older failure.

use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex, MutexGuard, PoisonError},
};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use sea_orm::DatabaseConnection;

/// Which connection of a history state a duty owns.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HistoryConnectionRole {
    /// The single ordered writer connection.
    Writer,
    /// The read-only connection a cold read opened.
    Reader,
}

impl HistoryConnectionRole {
    fn label(self) -> &'static str {
        match self {
            Self::Writer => "writer",
            Self::Reader => "reader",
        }
    }
}

type CloseOutcome = Result<(), Arc<HistoryCloseFailure>>;
type CloseCompletion = Shared<BoxFuture<'static, CloseOutcome>>;

/// Why one original connection (or one still-lived state) is not closed.
#[derive(Debug, thiserror::Error)]
pub(crate) enum HistoryCloseFailure {
    #[error("history {role} connection {id} of Thread {thread_id} could not be closed")]
    Database {
        id: u64,
        thread_id: String,
        role: &'static str,
        #[source]
        source: sea_orm::DbErr,
    },
    #[error("history {role} connection {id} of Thread {thread_id} has no close task to join")]
    Task {
        id: u64,
        thread_id: String,
        role: &'static str,
        #[source]
        source: Arc<tokio::task::JoinError>,
    },
    #[error("history {role} connection {id} of Thread {thread_id} could not start its close")]
    Unstarted {
        id: u64,
        thread_id: String,
        role: &'static str,
    },
    #[error("history {role} connection {id} of Thread {thread_id} did not finish closing here")]
    Unfinished {
        id: u64,
        thread_id: String,
        role: &'static str,
    },
    #[error("Thread {thread_id} still holds a live history state")]
    StateHeld { thread_id: String },
}

impl HistoryCloseFailure {
    /// Whether another close entry may attempt this same responsibility again.
    ///
    /// A close task that panicked or was cancelled leaves the original connection in this owner, so a
    /// later explicit close retries that same connection. That is not an automatic writer rerun: the
    /// writer's own terminal failure stays a separate fact.
    pub(crate) fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::Database { .. }
                | Self::Task { .. }
                | Self::Unstarted { .. }
                | Self::Unfinished { .. }
                | Self::StateHeld { .. }
        )
    }
}

/// Every responsibility a close entry could not finish, as one typed report.
#[derive(Debug)]
pub(crate) struct HistoryCloseGroup {
    failures: Vec<Arc<HistoryCloseFailure>>,
}

impl HistoryCloseGroup {
    /// Whether every retained responsibility could still be settled by a later entry.
    pub(crate) fn is_retryable(&self) -> bool {
        !self.failures.is_empty() && self.failures.iter().all(|failure| failure.is_retryable())
    }
}

impl std::fmt::Display for HistoryCloseGroup {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "{} history close responsibility(ies) are not settled",
            self.failures.len()
        )
    }
}

impl std::error::Error for HistoryCloseGroup {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.failures
            .first()
            .map(|failure| failure.as_ref() as &(dyn std::error::Error + 'static))
    }
}

/// One close attempt of one duty.
struct Attempt;

/// One original connection awaiting its real close.
struct Duty {
    id: u64,
    thread_id: String,
    role: HistoryConnectionRole,
    connection: Option<DatabaseConnection>,
    attempt: Option<Arc<Attempt>>,
    task: Option<CloseCompletion>,
    failure: Option<Arc<HistoryCloseFailure>>,
}

/// A newly installed attempt, captured before the lifecycle lock is released.
struct StartedClose {
    id: u64,
    attempt: Arc<Attempt>,
    completion: CloseCompletion,
    #[cfg(test)]
    observer_gate: Option<tokio::sync::oneshot::Receiver<()>>,
    #[cfg(test)]
    observer_ack: Option<tokio::sync::oneshot::Sender<()>>,
}

struct State {
    duties: BTreeMap<u64, Duty>,
    next_duty: u64,
    completed: u64,
    /// One entry per real `HistoryStoreState` that still has a legitimate holder.
    live_states: BTreeMap<u64, String>,
    next_state: u64,
    sealed: bool,
    /// Wake-ups for a close entry waiting on state lifetimes.
    changed: tokio::sync::watch::Sender<u64>,
    generation: u64,
    #[cfg(test)]
    close_failure_armed: bool,
    #[cfg(test)]
    close_panic_armed: bool,
    #[cfg(test)]
    observer_delay: Option<tokio::sync::oneshot::Receiver<()>>,
    #[cfg(test)]
    observer_ack: Option<(HistoryConnectionRole, tokio::sync::oneshot::Sender<()>)>,
}

impl State {
    /// Both last-state release and unpublished cleanup register the same kind of original duty.
    fn accept_connection(
        &mut self,
        thread_id: &str,
        role: HistoryConnectionRole,
        connection: DatabaseConnection,
    ) -> u64 {
        self.next_duty += 1;
        let id = self.next_duty;
        self.duties.insert(
            id,
            Duty {
                id,
                thread_id: thread_id.to_owned(),
                role,
                connection: Some(connection),
                attempt: None,
                task: None,
                failure: None,
            },
        );
        id
    }
}

/// The narrow owner of "these history states still live and their connections still have to close".
#[derive(Clone)]
pub(crate) struct HistoryCloseOwner(Arc<Mutex<State>>);

impl std::fmt::Debug for HistoryCloseOwner {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryCloseOwner")
            .field("states", &self.live_states())
            .field("outstanding", &self.outstanding())
            .field("completed", &self.completed())
            .finish_non_exhaustive()
    }
}

/// The lifetime token of one real `HistoryStoreState`.
pub(crate) struct HistoryStateLease {
    owner: HistoryCloseOwner,
    id: u64,
    thread_id: String,
    finished: bool,
}

impl HistoryStateLease {
    /// Synchronously transfers one unpublished connection to this same owner and returns a wait
    /// for its original attempt. Dropping that wait never drops or reselects the owner's task.
    pub(crate) fn hand_over_connection(
        &self,
        role: HistoryConnectionRole,
        connection: DatabaseConnection,
    ) -> BoxFuture<'static, CloseOutcome> {
        let handle = tokio::runtime::Handle::try_current().ok();
        let (id, started) = {
            let mut state = self.owner.lock();
            let id = state.accept_connection(&self.thread_id, role, connection);
            // Registration and capture of this exact attempt share the lock: another settle cannot
            // finish/remove it before the local cleanup obtained its real completion.
            let started = handle
                .as_ref()
                .and_then(|handle| self.owner.start_locked(&mut state, id, handle));
            (id, started)
        };
        let original = started
            .as_ref()
            .map(|started| (started.attempt.clone(), started.completion.clone()));
        if let Some(started) = started {
            self.owner.observe(started);
        }
        self.owner.notify();
        let owner = self.owner.clone();
        let thread_id = self.thread_id.clone();
        async move {
            match original {
                Some((attempt, completion)) => {
                    let outcome = completion.await;
                    owner.record(id, &attempt, outcome.clone());
                    outcome
                }
                None => Err(Arc::new(HistoryCloseFailure::Unstarted {
                    id,
                    thread_id,
                    role: role.label(),
                })),
            }
        }
        .boxed()
    }

    /// Ends this state's lifetime and takes over its still-open connections.
    ///
    /// Both facts are published under one lock, so no observer can see "no live state" while a
    /// connection of that state is still unregistered. Calling it twice is a no-op.
    pub(crate) fn finish(
        &mut self,
        connections: impl IntoIterator<Item = (HistoryConnectionRole, DatabaseConnection)>,
    ) {
        if self.finished {
            return;
        }
        self.finished = true;
        let mut started = Vec::new();
        {
            let mut state = self.owner.lock();
            state.live_states.remove(&self.id);
            for (role, connection) in connections {
                started.push(state.accept_connection(&self.thread_id, role, connection));
            }
        }
        for id in started {
            self.owner.start(id);
        }
        self.owner.notify();
    }
}

impl std::fmt::Debug for HistoryStateLease {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryStateLease")
            .field("state", &self.id)
            .field("thread_id", &self.thread_id)
            .field("finished", &self.finished)
            .finish()
    }
}

impl HistoryCloseOwner {
    pub(crate) fn new() -> Self {
        let (changed, _) = tokio::sync::watch::channel(0_u64);
        Self(Arc::new(Mutex::new(State {
            duties: BTreeMap::new(),
            next_duty: 0,
            completed: 0,
            live_states: BTreeMap::new(),
            next_state: 0,
            sealed: false,
            changed,
            generation: 0,
            #[cfg(test)]
            close_failure_armed: false,
            #[cfg(test)]
            close_panic_armed: false,
            #[cfg(test)]
            observer_delay: None,
            #[cfg(test)]
            observer_ack: None,
        })))
    }

    fn lock(&self) -> MutexGuard<'_, State> {
        self.0.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn notify(&self) {
        let mut state = self.lock();
        state.generation += 1;
        let generation = state.generation;
        state.changed.send_replace(generation);
    }

    /// Registers one real history state and returns the token that keeps it alive.
    ///
    /// Registration is refused at the same boundary as the seal, so an external caller cannot
    /// "promise" it is early enough and a refused registration never yields a state.
    pub(crate) fn register_state(
        &self,
        thread_id: &str,
    ) -> Result<HistoryStateLease, anyhow::Error> {
        let id = {
            let mut state = self.lock();
            if state.sealed {
                return Err(closed_history());
            }
            state.next_state += 1;
            let id = state.next_state;
            state.live_states.insert(id, thread_id.to_owned());
            id
        };
        self.notify();
        Ok(HistoryStateLease {
            owner: self.clone(),
            id,
            thread_id: thread_id.to_owned(),
            finished: false,
        })
    }

    #[cfg(test)]
    /// Makes the next close attempt fail with a controlled typed database error.
    pub(crate) fn arm_close_failure(&self) {
        self.lock().close_failure_armed = true;
    }

    #[cfg(test)]
    /// Makes the next close *task* panic, so the failure is a real `JoinError`, not a database one.
    pub(crate) fn arm_close_panic(&self) {
        self.lock().close_panic_armed = true;
    }

    #[cfg(test)]
    /// Delays the next close observer until the test releases the gate.
    pub(crate) fn arm_observer_delay(&self, gate: tokio::sync::oneshot::Receiver<()>) {
        self.lock().observer_delay = Some(gate);
    }

    #[cfg(test)]
    /// Signals once the next observer of `role` has recorded its outcome.
    ///
    /// Bound to the role so a test can wait for the reader's own record instead of whichever
    /// observer happens to run first.
    pub(crate) fn arm_observer_ack(
        &self,
        role: HistoryConnectionRole,
        ack: tokio::sync::oneshot::Sender<()>,
    ) {
        self.lock().observer_ack = Some((role, ack));
    }

    /// Starts the real close for one duty when a runtime can await it.
    ///
    /// Checking the duty, allocating this attempt, spawning its task, building its completion and
    /// installing both slots all happen under **one** lock with no await in between: a concurrent
    /// caller can therefore neither spawn a second attempt nor lose an already-spawned handle. The
    /// spawned task only ever re-enters this lock through `record`, and `tokio::spawn` does not poll
    /// the future it is given, so nothing re-enters while the lock is held.
    fn start(&self, id: u64) {
        let Ok(handle) = tokio::runtime::Handle::try_current() else {
            // No runtime can await this close yet: the duty stays explicitly unstarted and a later
            // async entry starts the very same responsibility.
            return;
        };
        let started = {
            let mut state = self.lock();
            self.start_locked(&mut state, id, &handle)
        };
        if let Some(started) = started {
            self.observe(started);
        }
    }

    /// Installs an attempt while the caller still owns this duty's registration boundary.
    fn start_locked(
        &self,
        state: &mut State,
        id: u64,
        handle: &tokio::runtime::Handle,
    ) -> Option<StartedClose> {
        let (thread_id, role, connection) = {
            let duty = state.duties.get(&id)?;
            if duty.attempt.is_some() || duty.failure.is_some() {
                return None;
            }
            let connection = duty.connection.clone()?;
            (duty.thread_id.clone(), duty.role, connection)
        };
        let attempt = Arc::new(Attempt);
        #[cfg(test)]
        let (fail, panic_task, observer_gate, observer_ack) = self.take_close_seams(state, role);
        // The task receives its own shared handle; the duty keeps the original connection until
        // the close really succeeded, so a panicking or cancelled task cannot lose the resource.
        #[cfg(test)]
        let join = handle.spawn(async move {
            if panic_task {
                panic!("controlled history close task panic");
            }
            if fail {
                return Err(sea_orm::DbErr::Custom(
                    "controlled history close failure".to_owned(),
                ));
            }
            connection.close_by_ref().await
        });
        #[cfg(not(test))]
        let join = handle.spawn(async move { connection.close_by_ref().await });
        let completion: CloseCompletion = async move {
            match join.await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(source)) => Err(Arc::new(HistoryCloseFailure::Database {
                    id,
                    thread_id,
                    role: role.label(),
                    source,
                })),
                Err(source) => Err(Arc::new(HistoryCloseFailure::Task {
                    id,
                    thread_id,
                    role: role.label(),
                    source: Arc::new(source),
                })),
            }
        }
        .boxed()
        .shared();
        let duty = state
            .duties
            .get_mut(&id)
            .expect("the duty stays registered under the close lock");
        // The slot is installed before the lock is released, so the spawned task is never lost.
        duty.attempt = Some(attempt.clone());
        duty.task = Some(completion.clone());
        Some(StartedClose {
            id,
            attempt,
            completion,
            #[cfg(test)]
            observer_gate,
            #[cfg(test)]
            observer_ack,
        })
    }

    fn observe(&self, started: StartedClose) {
        // The owner settles its own duties: a successful close releases the record and the original
        // connection right away instead of waiting for some later global close to look at it.
        let observer = self.clone();
        tokio::spawn(async move {
            #[cfg(test)]
            if let Some(gate) = started.observer_gate {
                let _ = gate.await;
            }
            let outcome = started.completion.await;
            observer.record(started.id, &started.attempt, outcome);
            // Acknowledged only after this observer's own record is applied.
            #[cfg(test)]
            if let Some(ack) = started.observer_ack {
                let _ = ack.send(());
            }
        });
    }

    #[cfg(test)]
    fn take_close_seams(
        &self,
        state: &mut State,
        role: HistoryConnectionRole,
    ) -> (
        bool,
        bool,
        Option<tokio::sync::oneshot::Receiver<()>>,
        Option<tokio::sync::oneshot::Sender<()>>,
    ) {
        let ack = match state.observer_ack.take() {
            Some((armed, ack)) if armed == role => Some(ack),
            other => {
                state.observer_ack = other;
                None
            }
        };
        (
            std::mem::take(&mut state.close_failure_armed),
            std::mem::take(&mut state.close_panic_armed),
            state.observer_delay.take(),
            ack,
        )
    }

    /// Records one joined outcome, but only for the attempt that is current now.
    fn record(&self, id: u64, attempt: &Arc<Attempt>, outcome: CloseOutcome) {
        {
            let mut state = self.lock();
            let Some(duty) = state.duties.get_mut(&id) else {
                return;
            };
            let current = duty
                .attempt
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(current, attempt));
            if !current {
                // A superseded attempt only ever settles itself; the newer slot is untouched.
                return;
            }
            match outcome {
                Ok(()) => {
                    state.duties.remove(&id);
                    state.completed += 1;
                }
                Err(failure) => {
                    duty.failure = Some(failure);
                    duty.task = None;
                    duty.attempt = None;
                }
            }
        }
        self.notify();
    }

    fn running(&self) -> Vec<(u64, Arc<Attempt>, CloseCompletion)> {
        let state = self.lock();
        state
            .duties
            .values()
            .filter_map(|duty| match (&duty.attempt, &duty.task) {
                (Some(attempt), Some(task)) => Some((duty.id, attempt.clone(), task.clone())),
                _ => None,
            })
            .collect()
    }

    fn pending(&self) -> Vec<u64> {
        let state = self.lock();
        state
            .duties
            .values()
            .filter(|duty| duty.failure.is_none() && duty.attempt.is_none())
            .map(|duty| duty.id)
            .collect()
    }

    /// Re-arms the responsibilities a later close entry is allowed to attempt again.
    fn rearm(&self) {
        let mut state = self.lock();
        for duty in state.duties.values_mut() {
            if duty
                .failure
                .as_ref()
                .is_some_and(|failure| failure.is_retryable())
            {
                duty.failure = None;
                duty.attempt = None;
                duty.task = None;
            }
        }
    }

    /// One close entry: attempt every outstanding original connection exactly once.
    pub(crate) async fn settle(&self) -> Result<(), HistoryCloseGroup> {
        self.rearm();
        for id in self.pending() {
            self.start(id);
        }
        for (id, attempt, task) in self.running() {
            let outcome = task.await;
            self.record(id, &attempt, outcome);
        }
        self.report()
    }

    /// Waits until no registered state is left, then closes like [`Self::settle`].
    pub(crate) async fn settle_when_no_state_is_left(&self) -> Result<(), HistoryCloseGroup> {
        // Subscribe before the first check so a state that ends in between always leaves a wake.
        let mut changed = {
            let state = self.lock();
            state.changed.subscribe()
        };
        loop {
            let _ = changed.borrow_and_update();
            if self.live_states() == 0 {
                return self.settle().await;
            }
            if changed.changed().await.is_err() {
                // This owner holds the sender for as long as it is awaited, so a closed channel
                // cannot stand for a legitimate holder: report whatever is still open instead.
                return self.report();
            }
        }
    }

    /// Marks the boundary after which no new state may be registered.
    pub(crate) fn seal(&self) {
        self.lock().sealed = true;
    }

    /// Real history states that still have a legitimate holder.
    pub(crate) fn live_states(&self) -> u64 {
        self.lock().live_states.len() as u64
    }

    /// Connections still owed a close, failed ones included.
    pub(crate) fn outstanding(&self) -> u64 {
        self.lock().duties.len() as u64
    }

    /// Number of connections whose close really succeeded.
    pub(crate) fn completed(&self) -> u64 {
        self.lock().completed
    }

    /// Everything this close entry could not finish, as typed failures.
    fn report(&self) -> Result<(), HistoryCloseGroup> {
        let state = self.lock();
        let mut failures: Vec<Arc<HistoryCloseFailure>> = Vec::new();
        for duty in state.duties.values() {
            match &duty.failure {
                Some(failure) => failures.push(failure.clone()),
                None if duty.attempt.is_none() => {
                    failures.push(Arc::new(HistoryCloseFailure::Unstarted {
                        id: duty.id,
                        thread_id: duty.thread_id.clone(),
                        role: duty.role.label(),
                    }));
                }
                None => failures.push(Arc::new(HistoryCloseFailure::Unfinished {
                    id: duty.id,
                    thread_id: duty.thread_id.clone(),
                    role: duty.role.label(),
                })),
            }
        }
        for thread_id in state.live_states.values() {
            failures.push(Arc::new(HistoryCloseFailure::StateHeld {
                thread_id: thread_id.clone(),
            }));
        }
        drop(state);
        if failures.is_empty() {
            return Ok(());
        }
        Err(HistoryCloseGroup { failures })
    }
}

/// The typed rejection for a history handle asked for after the final close sealed admission.
fn closed_history() -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Cancelled,
        "Studio history is closed",
        false,
    )
    .into()
}
