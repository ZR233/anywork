//! One registered current writer per Thread. History is neither a queue nor a durability gate here.

use std::{
    fmt,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, anyhow, ensure};
use futures::future::BoxFuture;
use pl_core::thread::{
    ThreadHandle,
    current::{RuntimeEpoch, ThreadCurrent},
};
use tokio::{
    sync::{Notify, mpsc, oneshot, watch},
    task::JoinHandle,
    time::Instant,
};
use tokio_util::sync::CancellationToken;

use super::current_file::{CurrentFile, VerifiedResources};

const SAVE_INTERVAL: Duration = Duration::from_secs(2);
const RETRY_DELAY: Duration = Duration::from_secs(5);
const CAPTURE_TIMEOUT: Duration = Duration::from_secs(1);

/// Thin adapters to the existing Core owner. Capture must not hold a business lock across await.
/// Finish stops admission, cancels and joins producers, and returns their complete final handoff;
/// it must not ask an already destroyed producer to capture again or await another network frame.
#[derive(Clone)]
pub(crate) struct CurrentSource {
    capture: Arc<
        dyn Fn(RuntimeEpoch, CancellationToken) -> BoxFuture<'static, Result<ThreadCurrent>>
            + Send
            + Sync,
    >,
    finish: Arc<dyn Fn(RuntimeEpoch) -> BoxFuture<'static, Result<ThreadCurrent>> + Send + Sync>,
    /// Only the concrete Core binding has observations. The writer owns and joins its subscription.
    observations: Option<ThreadHandle>,
}

impl CurrentSource {
    pub(crate) fn new(
        capture: impl Fn(RuntimeEpoch, CancellationToken) -> BoxFuture<'static, Result<ThreadCurrent>>
        + Send
        + Sync
        + 'static,
        finish: impl Fn(RuntimeEpoch) -> BoxFuture<'static, Result<ThreadCurrent>>
        + Send
        + Sync
        + 'static,
    ) -> Self {
        Self {
            capture: Arc::new(capture),
            finish: Arc::new(finish),
            observations: None,
        }
    }

    /// Binds a `start_current`/`restore_current` owner without attaching a checkpoint store.
    /// Closing reads the owner's final producer handoff only after its real resource close.
    pub(crate) fn from_thread(handle: ThreadHandle) -> Self {
        let capture = handle.clone();
        let finish = handle.clone();
        let mut source = Self::new(
            move |epoch, cancellation| {
                let handle = capture.clone();
                Box::pin(async move {
                    validate_owner(&handle, epoch)?;
                    handle
                        .capture_current(cancellation)
                        .await
                        .context("capture Core current")
                })
            },
            move |epoch| {
                let handle = finish.clone();
                Box::pin(async move {
                    validate_owner(&handle, epoch)?;
                    match handle.close().await {
                        Ok(()) => {}
                        Err(pl_core::thread::ThreadError::Closed)
                            if handle.snapshot().lifecycle
                                == pl_core::thread::ThreadLifecycle::Closed => {}
                        Err(error) => return Err(error).context("close Core current owner"),
                    }
                    let cancellation = CancellationToken::new();
                    let _cancel = cancellation.clone().drop_guard();
                    // The Session may already have joined this physical owner. In either case,
                    // only Core's actual final_current proves a successful handoff; a closed
                    // mailbox or lifecycle snapshot alone cannot stand in for it.
                    tokio::time::timeout(CAPTURE_TIMEOUT, handle.capture_current(cancellation))
                        .await
                        .context("final Core current handoff exceeded one second")?
                        .context("read final Core current handoff")
                })
            },
        );
        source.observations = Some(handle);
        source
    }
}

fn validate_owner(handle: &ThreadHandle, epoch: RuntimeEpoch) -> Result<()> {
    ensure!(
        handle.runtime_epoch() == epoch,
        "Core current source belongs to another runtime epoch"
    );
    // Schema 25 deliberately allows the independent current owner to observe a Core owner that
    // also has the append-only history sink attached. The two writers never share a transaction.
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CurrentSaveReceipt {
    pub(crate) runtime_epoch: RuntimeEpoch,
    pub(crate) snapshot_revision: u64,
}

/// Cloneable only to publish the same underlying failure to all close waiters and observers.
#[derive(Debug, Clone)]
pub(crate) struct CurrentFailure(Arc<anyhow::Error>);

impl fmt::Display for CurrentFailure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:#}", self.0)
    }
}
impl std::error::Error for CurrentFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(self.0.as_ref().as_ref())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CurrentLifecycle {
    Unbound,
    Open,
    Closing,
    Closed,
}

#[derive(Debug, Clone)]
pub(crate) struct CurrentSaveState {
    pub(crate) runtime_epoch: Option<RuntimeEpoch>,
    pub(crate) lifecycle: CurrentLifecycle,
    pub(crate) dirty: bool,
    pub(crate) in_flight: bool,
    /// Latest coalesced dirty notification, never a history watermark.
    pub(crate) observed_revision: Option<u64>,
    /// A retained subscription task, including a completed one until its real join.
    pub(crate) observer_registered: bool,
    pub(crate) error: Option<CurrentFailure>,
    pub(crate) receipt: Option<CurrentSaveReceipt>,
    pub(crate) last_successful_save_at: Option<i64>,
    pub(crate) last_successful_capture_at: Option<i64>,
}

impl CurrentSaveState {
    pub(crate) fn persistence_snapshot(&self) -> crate::CurrentPersistenceSnapshot {
        crate::CurrentPersistenceSnapshot {
            runtime_epoch: self.runtime_epoch.map(|epoch| epoch.to_string()),
            dirty: self.dirty,
            in_flight: self.in_flight,
            saved_runtime_epoch: self
                .receipt
                .as_ref()
                .map(|receipt| receipt.runtime_epoch.to_string()),
            saved_revision: self
                .receipt
                .as_ref()
                .map(|receipt| receipt.snapshot_revision),
            last_successful_save_at: self.last_successful_save_at,
            last_successful_capture_at: self.last_successful_capture_at,
            snapshot_age_millis: self
                .last_successful_capture_at
                .map(|captured| u64::try_from(utc_millis().saturating_sub(captured)).unwrap_or(0)),
            last_error: self.error.as_ref().map(ToString::to_string),
        }
    }
}

struct State {
    view: CurrentSaveState,
    capture: Option<CancellationToken>,
    observer: Option<CancellationToken>,
    retry_at: Option<Instant>,
    close_result: Option<std::result::Result<(), CurrentFailure>>,
    close_purpose: Option<crate::thread_assembler::ClosePurpose>,
    final_current: Option<Arc<ThreadCurrent>>,
    joined: bool,
}

struct Shared {
    state: Mutex<State>,
    changed: watch::Sender<CurrentSaveState>,
    close: Notify,
    on_change: Box<dyn Fn() + Send + Sync>,
    #[cfg(test)]
    observer_tasks: Arc<std::sync::atomic::AtomicUsize>,
}

impl Shared {
    fn update<T>(&self, update: impl FnOnce(&mut State) -> T) -> T {
        self.update_notifying(|state| (update(state), true))
    }

    fn update_notifying<T>(&self, update: impl FnOnce(&mut State) -> (T, bool)) -> T {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (result, notify) = update(&mut state);
        // Publish under the same narrow lock so concurrent dirty/close updates cannot reorder views.
        self.changed.send_replace(state.view.clone());
        drop(state);
        // The coordinator reads this writer while holding its own registry lock. Never call it
        // under the writer lock, and coalesce token-only changes while dirty is already true.
        if notify {
            (self.on_change)();
        }
        result
    }
    fn read<T>(&self, read: impl FnOnce(&State) -> T) -> T {
        read(
            &self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }

    fn mark_dirty(&self, epoch: RuntimeEpoch, observed_revision: Option<u64>) {
        self.update_notifying(|state| {
            let mut notify = false;
            if state.view.lifecycle == CurrentLifecycle::Open
                && state.view.runtime_epoch == Some(epoch)
            {
                notify = !state.view.dirty;
                state.view.dirty = true;
                if let Some(revision) = observed_revision {
                    state.view.observed_revision = Some(revision);
                }
            }
            ((), notify)
        });
    }
}

enum Command {
    Activate {
        previous: Option<RuntimeEpoch>,
        epoch: RuntimeEpoch,
        source: Box<CurrentSource>,
        reply: oneshot::Sender<Result<()>>,
    },
    Flush {
        epoch: RuntimeEpoch,
        reply: oneshot::Sender<Result<CurrentSaveReceipt>>,
    },
}

/// The coordinator's existing Thread slot retains this owner until close has actually joined it.
pub(crate) struct CurrentWriter {
    file: CurrentFile,
    shared: Arc<Shared>,
    commands: mpsc::Sender<Command>,
    task: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}

impl fmt::Debug for CurrentWriter {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CurrentWriter")
            .field("file", &self.file)
            .field("state", &self.snapshot())
            .finish_non_exhaustive()
    }
}

impl CurrentWriter {
    pub(super) fn new(
        file: CurrentFile,
        on_change: impl Fn() + Send + Sync + 'static,
    ) -> Arc<Self> {
        let view = CurrentSaveState {
            runtime_epoch: None,
            lifecycle: CurrentLifecycle::Unbound,
            dirty: false,
            in_flight: false,
            observed_revision: None,
            observer_registered: false,
            error: None,
            receipt: None,
            last_successful_save_at: None,
            last_successful_capture_at: None,
        };
        let (changed, _) = watch::channel(view.clone());
        let shared = Arc::new(Shared {
            state: Mutex::new(State {
                view,
                capture: None,
                observer: None,
                retry_at: None,
                close_result: None,
                close_purpose: None,
                final_current: None,
                joined: false,
            }),
            changed,
            close: Notify::new(),
            on_change: Box::new(on_change),
            #[cfg(test)]
            observer_tasks: Arc::new(std::sync::atomic::AtomicUsize::new(0)),
        });
        // This queue holds control requests, never tokens or snapshots. Dirty is a single bit.
        let (commands, receiver) = mpsc::channel(16);
        let task = tokio::spawn(run(file.clone(), shared.clone(), receiver));
        Arc::new(Self {
            file,
            shared,
            commands,
            task: tokio::sync::Mutex::new(Some(task)),
        })
    }

    pub(super) fn directory(&self) -> &std::path::Path {
        self.file.directory()
    }
    pub(super) fn is_joined(&self) -> bool {
        self.shared.read(|s| s.joined)
    }
    pub(crate) fn snapshot(&self) -> CurrentSaveState {
        self.shared.read(|s| s.view.clone())
    }
    /// Compare-and-replace admission prevents a delayed old owner's offer from reviving its epoch.
    /// The writer processes this only after the previous capture/encode/file operation has ended.
    pub(crate) async fn activate(
        &self,
        previous: Option<RuntimeEpoch>,
        epoch: RuntimeEpoch,
        source: CurrentSource,
    ) -> Result<()> {
        let (reply, result) = oneshot::channel();
        self.commands
            .send(Command::Activate {
                previous,
                epoch,
                source: Box::new(source),
                reply,
            })
            .await
            .context("current writer stopped")?;
        result
            .await
            .context("current writer stopped before epoch admission")?
    }

    pub(crate) async fn flush(&self, epoch: RuntimeEpoch) -> Result<CurrentSaveReceipt> {
        let (reply, result) = oneshot::channel();
        self.commands
            .send(Command::Flush { epoch, reply })
            .await
            .context("current writer stopped")?;
        result
            .await
            .context("current writer stopped before flush receipt")?
    }

    /// Closing is writer-owned, including when a caller drops its waiting future. The join handle
    /// remains in its owner slot across await; a cancelled waiter cannot detach the writer.
    pub(crate) async fn close(
        &self,
        epoch: RuntimeEpoch,
        purpose: crate::thread_assembler::ClosePurpose,
    ) -> Result<()> {
        self.shared.update(|state| -> Result<()> {
            ensure!(
                state.view.runtime_epoch.is_none()
                    || state.view.runtime_epoch.as_ref() == Some(&epoch),
                "stale current runtime epoch"
            );
            if state.close_purpose.is_none()
                || purpose == crate::thread_assembler::ClosePurpose::Delete
            {
                state.close_purpose = Some(purpose);
            }
            if matches!(
                state.view.lifecycle,
                CurrentLifecycle::Unbound | CurrentLifecycle::Open
            ) {
                state.view.lifecycle = CurrentLifecycle::Closing;
                if let Some(capture) = &state.capture {
                    capture.cancel();
                }
                if let Some(observer) = &state.observer {
                    observer.cancel();
                }
            }
            Ok(())
        })?;
        self.shared.close.notify_one();
        let mut task = self.task.lock().await;
        if task.is_none() {
            let retry = self.shared.update(|state| {
                if state.close_purpose == Some(crate::thread_assembler::ClosePurpose::Delete) {
                    state.final_current = None;
                    return None;
                }
                let current = state.final_current.clone()?;
                if !matches!(state.close_result, Some(Err(_))) {
                    return None;
                }
                state.view.lifecycle = CurrentLifecycle::Closing;
                state.joined = false;
                Some(current)
            });
            if let Some(current) = retry {
                let file = self.file.clone();
                let shared = self.shared.clone();
                // The original producer is already joined. Retry only its retained final data,
                // under this writer's lease and owned join slot, even if this waiter is dropped.
                *task = Some(tokio::spawn(async move {
                    let result =
                        save_final(&file, &shared, current, &mut VerifiedResources::new()).await;
                    record_close(&shared, result.map(|_| ()));
                }));
            }
        }
        if let Some(handle) = task.as_mut() {
            let outcome = handle.await;
            *task = None;
            self.shared.update(|state| {
                state.joined = true;
                if let Err(error) = outcome {
                    let failure =
                        CurrentFailure(Arc::new(anyhow!(error).context("join current writer")));
                    state.view.lifecycle = CurrentLifecycle::Closed;
                    state.view.in_flight = false;
                    state.view.error = Some(failure.clone());
                    state.close_result = Some(Err(failure));
                    state.final_current = None;
                }
            });
        }
        self.shared
            .read(|s| s.close_result.clone())
            .context("current writer ended without a close result")?
            .map_err(Into::into)
    }
}

struct Active {
    epoch: RuntimeEpoch,
    source: CurrentSource,
    observer: Option<CurrentObserver>,
    verified_resources: VerifiedResources,
}

struct CurrentObserver {
    cancellation: CancellationToken,
    task: JoinHandle<()>,
}

#[cfg(test)]
struct ObserverTask(Arc<std::sync::atomic::AtomicUsize>);

#[cfg(test)]
impl Drop for ObserverTask {
    fn drop(&mut self) {
        self.0.fetch_sub(1, std::sync::atomic::Ordering::Relaxed);
    }
}

impl CurrentObserver {
    fn start(
        mut subscription: watch::Receiver<u64>,
        mut revision: u64,
        epoch: RuntimeEpoch,
        shared: Arc<Shared>,
        cancellation: CancellationToken,
    ) -> Self {
        let stopped = cancellation.clone();
        #[cfg(test)]
        let guard = {
            shared
                .observer_tasks
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            ObserverTask(shared.observer_tasks.clone())
        };
        let task = tokio::spawn(async move {
            #[cfg(test)]
            let _guard = guard;
            loop {
                tokio::select! {
                    biased;
                    () = stopped.cancelled() => break,
                    changed = subscription.changed() => {
                        if changed.is_err() { break; }
                        let next = *subscription.borrow_and_update();
                        if next != revision {
                            revision = next;
                            shared.mark_dirty(epoch, Some(revision));
                        }
                    }
                }
            }
        });
        Self { cancellation, task }
    }
}

impl Active {
    async fn stop_observer(&mut self, shared: &Shared) -> Result<()> {
        let Some(observer) = self.observer.as_mut() else {
            return Ok(());
        };
        observer.cancellation.cancel();
        let result = (&mut observer.task).await;
        self.observer = None;
        shared.update(|state| {
            state.observer = None;
            state.view.observer_registered = false;
        });
        result.context("join Core current observer")
    }
}

fn validate_admission(
    state: &State,
    previous: Option<RuntimeEpoch>,
    epoch: RuntimeEpoch,
) -> Result<()> {
    ensure!(
        matches!(
            state.view.lifecycle,
            CurrentLifecycle::Unbound | CurrentLifecycle::Open
        ),
        "current writer is closing"
    );
    ensure!(
        state.view.runtime_epoch == previous,
        "current epoch offer superseded"
    );
    ensure!(
        previous != Some(epoch),
        "new current owner must use a new runtime epoch"
    );
    Ok(())
}

async fn activate_source(
    shared: &Arc<Shared>,
    active: &mut Option<Active>,
    previous: Option<RuntimeEpoch>,
    epoch: RuntimeEpoch,
    source: CurrentSource,
) -> Result<()> {
    shared.read(|state| validate_admission(state, previous, epoch))?;
    if let Some(handle) = &source.observations {
        validate_owner(handle, epoch)?;
    }
    if let Some(owner) = active.as_mut() {
        owner.stop_observer(shared).await?;
    }
    let mut observation = match &source.observations {
        Some(handle) => {
            let mut subscription = handle.subscribe_current_dirty();
            let initial = *subscription.borrow_and_update();
            Some((subscription, initial, CancellationToken::new()))
        }
        None => None,
    };
    shared.update(|state| -> Result<()> {
        // close may have sealed admission while the previous observer was joining.
        validate_admission(state, previous, epoch)?;
        state.view.runtime_epoch = Some(epoch);
        state.view.lifecycle = CurrentLifecycle::Open;
        state.view.dirty = true;
        state.view.observed_revision = observation.as_ref().map(|(_, revision, _)| *revision);
        state.view.observer_registered = observation.is_some();
        state.observer = observation
            .as_ref()
            .map(|(_, _, cancellation)| cancellation.clone());
        // Owner replacement does not acknowledge a publication failure or shorten its backoff.
        Ok(())
    })?;
    let observer = observation
        .take()
        .map(|(subscription, revision, cancellation)| {
            CurrentObserver::start(subscription, revision, epoch, shared.clone(), cancellation)
        });
    *active = Some(Active {
        epoch,
        source,
        observer,
        verified_resources: VerifiedResources::new(),
    });
    Ok(())
}

async fn run(file: CurrentFile, shared: Arc<Shared>, mut commands: mpsc::Receiver<Command>) {
    let mut next_tick = Instant::now() + SAVE_INTERVAL;
    let mut active: Option<Active> = None;
    loop {
        // Ticks which arrived during an operation are skipped, not replayed immediately when it
        // finishes between ticks. Keep the original two-second cadence without a second task.
        let now = Instant::now();
        if next_tick < now {
            let remainder = now.duration_since(next_tick).as_nanos() % SAVE_INTERVAL.as_nanos();
            next_tick = now
                + if remainder == 0 {
                    Duration::ZERO
                } else {
                    Duration::from_nanos((SAVE_INTERVAL.as_nanos() - remainder) as u64)
                };
        }
        if shared.read(|s| s.view.lifecycle == CurrentLifecycle::Closing) {
            let result = match active.as_mut() {
                Some(owner) => {
                    let stopped = owner.stop_observer(&shared).await;
                    let saved = if shared.read(|state| state.close_purpose)
                        == Some(crate::thread_assembler::ClosePurpose::Delete)
                    {
                        // The resource owner still closes and joins, but explicit deletion neither
                        // retries a failed save nor publishes new persistence evidence.
                        (owner.source.finish)(owner.epoch).await.map(|_| ())
                    } else {
                        finish(&file, &shared, owner).await.map(|_| ())
                    };
                    match (stopped, saved) {
                        (Ok(()), result) => result,
                        (Err(error), Ok(_)) => {
                            shared.update(|state| state.final_current = None);
                            Err(error)
                        }
                        (Err(error), Err(save)) => {
                            shared.update(|state| state.final_current = None);
                            Err(error.context(format!("final current also failed: {save:#}")))
                        }
                    }
                }
                None => Err(anyhow!("current writer has no source for final handoff")),
            };
            record_close(&shared, result);
            break;
        }
        let retry_at = shared.read(|s| s.retry_at);
        tokio::select! {
            biased;
            _ = shared.close.notified() => {}
            command = commands.recv() => {
                let Some(command) = command else { break; };
                match command {
                    Command::Activate { previous, epoch, source, reply } => {
                        let result = activate_source(&shared, &mut active, previous, epoch, *source).await;
                        let _ = reply.send(result);
                    }
                    Command::Flush { epoch, reply } => {
                        let admitted = shared.read(|s| s.view.lifecycle == CurrentLifecycle::Open && s.view.runtime_epoch.as_ref() == Some(&epoch));
                        let result = if admitted {
                            save(&file, &shared, active.as_mut().expect("open writer source")).await
                        } else { Err(anyhow!("stale current runtime epoch or closing writer")) };
                        let _ = reply.send(result);
                    }
                }
            }
            _ = retry_ready(retry_at) => {
                if let Some(owner) = &mut active { let _ = save(&file, &shared, owner).await; }
            }
            _ = tokio::time::sleep_until(next_tick) => {
                next_tick += SAVE_INTERVAL;
                let ready = shared.read(|s| s.view.dirty && s.retry_at.is_none() && s.view.lifecycle == CurrentLifecycle::Open);
                if ready && let Some(owner) = &mut active { let _ = save(&file, &shared, owner).await; }
            }
        }
    }
    if let Some(owner) = active.as_mut()
        && let Err(error) = owner.stop_observer(&shared).await
    {
        shared.update(|state| state.view.error = Some(CurrentFailure(Arc::new(error))));
    }
    commands.close();
    // Rejected queued controls get channel closure, never a false save/admission receipt.
}

fn record_close(shared: &Shared, result: Result<()>) {
    shared.update(|state| {
        state.view.lifecycle = CurrentLifecycle::Closed;
        state.close_result = Some(result.map_err(|error| CurrentFailure(Arc::new(error))));
        state.view.in_flight = false;
        if matches!(state.close_result, Some(Ok(())))
            || state.close_purpose == Some(crate::thread_assembler::ClosePurpose::Delete)
        {
            state.final_current = None;
        }
        if let Some(Err(error)) = &state.close_result
            && (state.close_purpose != Some(crate::thread_assembler::ClosePurpose::Delete)
                || state.view.error.is_none())
        {
            state.view.error = Some(error.clone());
        }
    });
}

async fn retry_ready(deadline: Option<Instant>) {
    match deadline {
        Some(deadline) => tokio::time::sleep_until(deadline).await,
        None => std::future::pending().await,
    }
}

async fn save(
    file: &CurrentFile,
    shared: &Shared,
    owner: &mut Active,
) -> Result<CurrentSaveReceipt> {
    let cancellation = CancellationToken::new();
    let started_revision = shared.update(|state| -> Result<Option<u64>> {
        ensure!(
            state.view.lifecycle == CurrentLifecycle::Open
                && state.view.runtime_epoch.as_ref() == Some(&owner.epoch),
            "current writer is closing or superseded"
        );
        state.view.dirty = false;
        state.view.in_flight = true;
        state.capture = Some(cancellation.clone());
        Ok(state.view.observed_revision)
    })?;
    let _cancel = cancellation.clone().drop_guard();
    let result = async {
        let mut current = tokio::select! {
            biased;
            _ = cancellation.cancelled() => return Err(anyhow!("current capture cancelled")),
            result = tokio::time::timeout(CAPTURE_TIMEOUT, (owner.source.capture)(owner.epoch, cancellation.clone())) => {
                result.context("current capture exceeded one second")??
            }
        };
        // A producer can accept a newer delta after returning its captured stream but before the
        // owner reads the dirty sequence. A successful save only acknowledges the sequence that
        // was observed before capture began; later notifications still require another save.
        if let Some(revision) = started_revision {
            current.snapshot_revision = revision;
        }
        // This denotes completed capture, not a prediction of successful writing.
        current.saved_at = utc_millis();
        let captured = std::time::Instant::now();
        let result = async {
            ensure!(!cancellation.is_cancelled(), "current capture cancelled");
            file.validate(&current, Some(&owner.epoch))?;
            file.verify_resources(&current, &mut owner.verified_resources, cancellation.clone()).await?;
            ensure!(!cancellation.is_cancelled(), "current capture cancelled");
            publish(file, shared, Arc::new(current)).await
        }.await;
        tracing::debug!(target: "current_work",
            thread_id = file.thread_id(),
            current_save_ms = captured.elapsed().as_secs_f64() * 1000.0,
            success = result.is_ok(),
            "current save finished"
        );
        result
    }.await;
    complete_attempt(shared, result)
}

async fn finish(
    file: &CurrentFile,
    shared: &Shared,
    owner: &mut Active,
) -> Result<CurrentSaveReceipt> {
    shared.update(|state| {
        state.view.in_flight = true;
        state.view.dirty = false;
    });
    // A failed handoff has no snapshot to retry; keep its original failure. A successful handoff
    // remains owned here across filesystem failures without recapturing a destroyed producer.
    let current = match (owner.source.finish)(owner.epoch)
        .await
        .context("final current handoff")
    {
        Ok(mut current) => {
            current.saved_at = utc_millis();
            Arc::new(current)
        }
        Err(error) => return complete_attempt(shared, Err(error)),
    };
    let captured = std::time::Instant::now();
    shared.update(|state| state.final_current = Some(current.clone()));
    let result = save_final(file, shared, current, &mut owner.verified_resources).await;
    tracing::debug!(target: "current_work",
        thread_id = file.thread_id(),
        current_save_ms = captured.elapsed().as_secs_f64() * 1000.0,
        success = result.is_ok(),
        final_save = true,
        "current save finished"
    );
    result
}

async fn save_final(
    file: &CurrentFile,
    shared: &Shared,
    current: Arc<ThreadCurrent>,
    resources: &mut VerifiedResources,
) -> Result<CurrentSaveReceipt> {
    shared.update(|state| {
        state.view.in_flight = true;
        state.view.dirty = false;
    });
    let result = async {
        let epoch = shared
            .read(|state| state.view.runtime_epoch)
            .context("final Current owner is absent")?;
        file.validate(&current, Some(&epoch))?;
        file.verify_resources(&current, resources, CancellationToken::new())
            .await?;
        publish(file, shared, current).await
    }
    .await;
    complete_attempt(shared, result)
}

async fn publish(
    file: &CurrentFile,
    shared: &Shared,
    current: Arc<ThreadCurrent>,
) -> Result<CurrentSaveReceipt> {
    let receipt = CurrentSaveReceipt {
        runtime_epoch: current.saved_runtime_epoch,
        snapshot_revision: current.snapshot_revision,
    };
    let captured_at = current.saved_at;
    ensure!(
        shared.read(|state| state
            .view
            .receipt
            .as_ref()
            .is_none_or(|previous| previous.runtime_epoch != receipt.runtime_epoch
                || previous.snapshot_revision <= receipt.snapshot_revision)),
        "current capture regressed its saved revision"
    );
    let thread_id = current.thread_id.clone();
    file.save(current).await?;
    tracing::debug!(target: "current_work",
        thread_id = file.thread_id(),
        current_snapshot_age_ms = utc_millis().saturating_sub(captured_at).max(0),
        "current capture saved"
    );
    super::state::clear_checkpoint_recovery(&thread_id);
    shared.update(|state| {
        state.view.receipt = Some(receipt.clone());
        state.view.last_successful_capture_at = Some(captured_at);
        state.view.last_successful_save_at = Some(utc_millis());
        state.view.error = None;
        state.retry_at = None;
    });
    Ok(receipt)
}

fn complete_attempt(
    shared: &Shared,
    result: Result<CurrentSaveReceipt>,
) -> Result<CurrentSaveReceipt> {
    let result = result.map_err(|error| CurrentFailure(Arc::new(error)));
    shared.update(|state| {
        state.capture = None;
        state.view.in_flight = false;
        if let Err(error) = &result {
            state.view.dirty = true;
            state.view.error = Some(error.clone());
            state.retry_at = Some(Instant::now() + RETRY_DELAY);
        }
    });
    result.map_err(Into::into)
}

fn utc_millis() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => i64::try_from(duration.as_millis()).unwrap_or(i64::MAX),
        Err(error) => -i64::try_from(error.duration().as_millis()).unwrap_or(i64::MAX),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::{
        paths::CURRENT_FILE_NAME,
        storage::{coordinator::ThreadPersistenceCoordinator, state::StateStore},
    };
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        model::{
            CurrentCaptureHandle, DynModelSession, ModelCallExit, ModelError, ModelFailureKind,
            ModelRequest, ModelSession, PreparedModelCall,
        },
        thread::{
            ModelExecutionPhase, RuntimeFact, StepInput, ThreadLifecycle, current::SavedModelPhase,
        },
    };
    use std::{
        io,
        sync::atomic::{AtomicU64, AtomicUsize, Ordering},
    };

    fn current(epoch: RuntimeEpoch, revision: u64) -> ThreadCurrent {
        let mut current = ThreadCurrent::new("current-test".into(), epoch);
        current.snapshot_revision = revision;
        current
    }

    #[tokio::test]
    async fn already_closed_core_still_saves_its_original_final_current() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let core = ThreadHandle::restore_current(
            ThreadCurrent::new("current-test".into(), RuntimeEpoch::new()),
            None,
        )?;
        let epoch = core.runtime_epoch();
        let coordinator = ThreadPersistenceCoordinator::default();
        let mut store = StateStore::new(directory.path().into(), "current-test");
        store
            .attach_current(
                coordinator.clone(),
                None,
                epoch,
                CurrentSource::from_thread(core.clone()),
            )
            .await?;
        let writer = coordinator
            .current_writer("current-test", directory.path().into())
            .await?;

        // The Session owner can finish physical shutdown before the independent JSON owner.
        core.close().await?;
        let final_current = core.capture_current(CancellationToken::new()).await?;
        store
            .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        let saved = store
            .load_current()
            .await?
            .context("final current was not saved")?;
        assert_eq!(saved.saved_runtime_epoch, epoch);
        assert_eq!(saved.snapshot_revision, final_current.snapshot_revision);
        assert_eq!(
            serde_json::to_value(&saved.state)?,
            serde_json::to_value(&final_current.state)?
        );
        assert_eq!(core.snapshot().lifecycle, ThreadLifecycle::Closed);
        assert!(writer.is_joined());
        Ok(())
    }

    fn source(
        revision: Arc<AtomicU64>,
        captures: Arc<AtomicUsize>,
        finishes: Arc<AtomicUsize>,
    ) -> CurrentSource {
        let final_revision = revision.clone();
        CurrentSource::new(
            move |epoch, _| {
                captures.fetch_add(1, Ordering::SeqCst);
                let current = current(epoch, revision.load(Ordering::SeqCst));
                Box::pin(async { Ok(current) })
            },
            move |epoch| {
                finishes.fetch_add(1, Ordering::SeqCst);
                let current = current(epoch, final_revision.load(Ordering::SeqCst));
                Box::pin(async { Ok(current) })
            },
        )
    }

    async fn observed(
        writer: &CurrentWriter,
        predicate: impl Fn(&CurrentSaveState) -> bool,
    ) -> CurrentSaveState {
        let mut changes = writer.shared.changed.subscribe();
        loop {
            let state = changes.borrow_and_update().clone();
            if predicate(&state) {
                return state;
            }
            changes
                .changed()
                .await
                .expect("writer status remains observable");
        }
    }

    type ProducerChange = (String, oneshot::Sender<()>);

    /// Only the external model endpoint is synthetic: owner, capture requests, dirty watch,
    /// writer, file publication, resource validation and cold load are production implementations.
    struct StreamingModel {
        changes: Option<mpsc::UnboundedReceiver<ProducerChange>>,
        started: Option<oneshot::Sender<()>>,
        captures: Arc<AtomicUsize>,
        closes: Arc<AtomicUsize>,
    }

    fn model_cancelled() -> ModelError {
        ModelError {
            kind: ModelFailureKind::Cancelled,
            details: None,
            usage: Box::default(),
            source: None,
        }
    }

    impl ModelSession for StreamingModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> std::result::Result<PreparedModelCall, ModelError> {
            let mut changes = self
                .changes
                .take()
                .expect("one prepared call in this fixture");
            let started = self.started.take().expect("start receipt");
            let captures = self.captures.clone();
            let (capture, mut receiver) = CurrentCaptureHandle::channel();
            Ok(PreparedModelCall::new_with_current(async move {
                let mut accepted = OpaquePayload::text("initial complete producer state");
                let _ = started.send(());
                loop {
                    tokio::select! {
                        biased;
                        () = request.cancellation.cancelled() => return ModelCallExit {
                            result: Err(model_cancelled()),
                            current: Some(OpaquePayload::text("final producer handoff before accumulator drop")),
                        },
                        change = changes.recv() => {
                            let Some((text, reply)) = change else {
                                return ModelCallExit { result: Err(model_cancelled()), current: Some(accepted) };
                            };
                            accepted = OpaquePayload::text(text);
                            // No UI progress preview or effect commit: this producer-only change
                            // reaches the writer through the owner's small dirty watch.
                            receiver.mark_dirty();
                            let _ = reply.send(());
                        },
                        request = receiver.recv() => {
                            let Some(request) = request else {
                                return ModelCallExit { result: Err(model_cancelled()), current: Some(accepted) };
                            };
                            if !request.cancellation.is_cancelled() {
                                captures.fetch_add(1, Ordering::Relaxed);
                                let _ = request.reply.send(Ok(accepted.clone()));
                            }
                        }
                    }
                }
            }).with_current_capture(capture).with_request_metadata(OpaquePayload::text("frozen current test options")))
        }

        async fn close(&mut self) -> std::result::Result<(), ModelError> {
            self.closes.fetch_add(1, Ordering::Relaxed);
            Ok(())
        }
    }

    fn saved_stream(current: &ThreadCurrent) -> &str {
        match &current
            .model_call
            .as_ref()
            .expect("saved active model call")
            .phase
        {
            SavedModelPhase::Streaming { stream } => stream.content(),
            phase => panic!("expected complete saved streaming observation, got {phase:?}"),
        }
    }

    #[tokio::test(start_paused = true)]
    async fn real_core_producer_dirty_saves_json_and_close_uses_final_handoff_then_restores_paused()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history = directory.path().join("history.sqlite");
        std::fs::write(&history, b"unreadable independent history")?;
        let (updates, changes) = mpsc::unbounded_channel();
        let (started, running) = oneshot::channel();
        let captures = Arc::new(AtomicUsize::new(0));
        let closes = Arc::new(AtomicUsize::new(0));
        let handle = ThreadHandle::start_current(
            "current-test".into(),
            Some(DynModelSession::new(StreamingModel {
                changes: Some(changes),
                started: Some(started),
                captures: captures.clone(),
                closes: closes.clone(),
            })),
        )?;
        let epoch = handle.runtime_epoch();
        let coordinator = ThreadPersistenceCoordinator::default();
        let mut store = StateStore::new(directory.path().into(), "current-test");
        store
            .attach_current(
                coordinator.clone(),
                None,
                epoch,
                CurrentSource::from_thread(handle.clone()),
            )
            .await?;
        let writer = coordinator
            .current_writer("current-test", directory.path().into())
            .await?;
        assert!(writer.snapshot().observer_registered);
        let step = tokio::spawn({
            let handle = handle.clone();
            async move {
                handle
                    .step(StepInput {
                        turn_id: "current-turn".into(),
                        attempt_id: uuid::Uuid::new_v4().to_string(),
                        content: vec![ContextContent::Text {
                            text: "confirmed direct current input".into(),
                        }],
                        cancellation: CancellationToken::new(),
                    })
                    .await
            }
        });
        running.await?;
        assert_eq!(
            handle.snapshot().model_execution,
            Some(ModelExecutionPhase::Running)
        );
        assert!(!handle.snapshot().persistence.attached);
        let baseline = *handle.subscribe_current_dirty().borrow();
        observed(&writer, |state| {
            state
                .observed_revision
                .is_some_and(|revision| revision >= baseline)
        })
        .await;
        store.flush_current(epoch).await?;
        assert!(!store.current_save_state()?.dirty);
        assert_eq!(
            saved_stream(&store.load_current().await?.unwrap()),
            "initial complete producer state"
        );
        let changed = "完整生产者流正文".repeat(12_000);
        let (reply, accepted) = oneshot::channel();
        updates.send((changed.clone(), reply))?;
        accepted.await?;
        observed(&writer, |state| {
            state.dirty
                && state
                    .observed_revision
                    .is_some_and(|revision| revision > baseline)
        })
        .await;
        tokio::time::advance(SAVE_INTERVAL).await;
        observed(&writer, |state| {
            !state.dirty
                && !state.in_flight
                && state
                    .receipt
                    .as_ref()
                    .is_some_and(|receipt| receipt.snapshot_revision > baseline)
        })
        .await;
        let saved = store.load_current().await?.unwrap();
        assert_eq!(saved_stream(&saved), changed);
        assert!(saved.state.context.records.iter().any(|record| {
            record.content.iter().any(|content| {
                matches!(content,
            ContextContent::Text { text } if text.as_ref() == "confirmed direct current input")
            })
        }));
        let captures_before_close = captures.load(Ordering::Relaxed);
        store
            .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert!(
            step.await?.is_err(),
            "Core joined the cancelled model execution"
        );
        assert_eq!(closes.load(Ordering::Relaxed), 1);
        assert_eq!(
            captures.load(Ordering::Relaxed),
            captures_before_close,
            "final flush never requests capture from the destroyed producer"
        );
        assert_eq!(handle.snapshot().lifecycle, ThreadLifecycle::Closed);
        assert!(writer.is_joined());
        assert!(!writer.snapshot().observer_registered);
        assert_eq!(writer.shared.observer_tasks.load(Ordering::Relaxed), 0);
        let final_current = store.load_current().await?.unwrap();
        assert_eq!(
            saved_stream(&final_current),
            "final producer handoff before accumulator drop"
        );
        let bytes: serde_json::Value =
            serde_json::from_slice(&std::fs::read(directory.path().join(CURRENT_FILE_NAME))?)?;
        assert_eq!(bytes["savedRuntimeEpoch"], epoch.to_string());
        assert!(store.flush_current(epoch).await.is_err());
        assert_eq!(std::fs::read(&history)?, b"unreadable independent history");

        let restored = ThreadHandle::restore_current(final_current, None)?;
        let restored_epoch = restored.runtime_epoch();
        assert_ne!(restored_epoch, epoch);
        assert!(!restored.snapshot().persistence.attached);
        store
            .attach_current(
                coordinator,
                None,
                restored_epoch,
                CurrentSource::from_thread(restored.clone()),
            )
            .await?;
        store.flush_current(restored_epoch).await?;
        let paused = store.load_current().await?.unwrap();
        assert_eq!(paused.saved_runtime_epoch, restored_epoch);
        assert_eq!(paused.model_call.as_ref().unwrap().source_run_id, epoch);
        assert_eq!(
            saved_stream(&paused),
            "final producer handoff before accumulator drop"
        );
        assert_eq!(
            closes.load(Ordering::Relaxed),
            1,
            "paused restore opens no model session"
        );
        store
            .close_current(
                restored_epoch,
                crate::thread_assembler::ClosePurpose::Preserve,
            )
            .await?;
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn real_core_observer_replacement_joins_old_subscription_and_close_rejects_new_admission()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let coordinator = ThreadPersistenceCoordinator::default();
        let old = ThreadHandle::restore_current(
            ThreadCurrent::new("current-test".into(), RuntimeEpoch::new()),
            None,
        )?;
        let new = ThreadHandle::restore_current(
            ThreadCurrent::new("current-test".into(), RuntimeEpoch::new()),
            None,
        )?;
        let mut store = StateStore::new(directory.path().into(), "current-test");
        store
            .attach_current(
                coordinator.clone(),
                None,
                old.runtime_epoch(),
                CurrentSource::from_thread(old.clone()),
            )
            .await?;
        let writer = coordinator
            .current_writer("current-test", directory.path().into())
            .await?;
        let previous_observer = writer.shared.read(|state| state.observer.clone()).unwrap();
        store
            .attach_current(
                coordinator.clone(),
                Some(old.runtime_epoch()),
                new.runtime_epoch(),
                CurrentSource::from_thread(new.clone()),
            )
            .await?;
        assert!(Arc::ptr_eq(
            &writer,
            &coordinator
                .current_writer("current-test", directory.path().into())
                .await?
        ));
        assert!(previous_observer.is_cancelled());
        assert_eq!(
            writer.shared.observer_tasks.load(Ordering::Relaxed),
            1,
            "previous task has exited and joined before new admission returns"
        );
        store.flush_current(new.runtime_epoch()).await?;
        old.patch_runtime_facts(vec![RuntimeFact {
            source_id: "old-fact".into(),
            content: vec![ContextContent::Text {
                text: "old owner update".into(),
            }],
        }])
        .await?;
        assert!(!store.current_save_state()?.dirty);
        new.patch_runtime_facts(vec![RuntimeFact {
            source_id: "new-fact".into(),
            content: vec![ContextContent::Text {
                text: "new owner update".into(),
            }],
        }])
        .await?;
        observed(&writer, |state| state.dirty).await;
        store
            .close_current(
                new.runtime_epoch(),
                crate::thread_assembler::ClosePurpose::Preserve,
            )
            .await?;
        assert_eq!(writer.shared.observer_tasks.load(Ordering::Relaxed), 0);
        assert!(!store.current_save_state()?.observer_registered);
        assert!(
            writer
                .activate(
                    Some(new.runtime_epoch()),
                    old.runtime_epoch(),
                    CurrentSource::from_thread(old.clone())
                )
                .await
                .is_err()
        );
        old.close().await?;
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn two_second_tick_coalesces_changes_and_skips_in_flight_ticks() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let epoch = RuntimeEpoch::new();
        let revision = Arc::new(AtomicU64::new(1));
        let captures = Arc::new(AtomicUsize::new(0));
        let writes = Arc::new(AtomicUsize::new(0));
        let (started, waiting) = oneshot::channel();
        let gate = Mutex::new(Some((started, std::sync::mpsc::channel::<()>())));
        let release = gate.lock().unwrap().as_ref().unwrap().1.0.clone();
        let writes_for_io = writes.clone();
        let file = CurrentFile::new(directory.path().into(), "current-test".into()).with_write(
            Arc::new(move |_, _| {
                writes_for_io.fetch_add(1, Ordering::SeqCst);
                if let Some((started, (_, released))) = gate.lock().unwrap().take() {
                    let _ = started.send(());
                    released.recv().unwrap();
                }
                Ok(())
            }),
        );
        let writer = CurrentWriter::new(file, || {});
        writer
            .activate(
                None,
                epoch,
                source(
                    revision.clone(),
                    captures.clone(),
                    Arc::new(AtomicUsize::new(0)),
                ),
            )
            .await?;
        tokio::time::advance(Duration::from_millis(1999)).await;
        assert_eq!(captures.load(Ordering::SeqCst), 0);
        tokio::time::advance(Duration::from_millis(1)).await;
        waiting.await?;
        for next in 2..=100 {
            revision.store(next, Ordering::SeqCst);
            writer.shared.mark_dirty(epoch, None);
        }
        tokio::time::advance(Duration::from_secs(5)).await; // t=7, between ticks; I/O still owns the slot.
        assert_eq!(captures.load(Ordering::SeqCst), 1);
        assert_eq!(writes.load(Ordering::SeqCst), 1);
        assert!(writer.snapshot().dirty && writer.snapshot().in_flight);
        release.send(())?;
        observed(&writer, |s| {
            !s.in_flight && s.receipt.as_ref().is_some_and(|r| r.snapshot_revision == 1)
        })
        .await;
        assert_eq!(
            captures.load(Ordering::SeqCst),
            1,
            "missed t=4/6 ticks are not replayed"
        );
        tokio::time::advance(Duration::from_millis(999)).await;
        assert_eq!(captures.load(Ordering::SeqCst), 1);
        tokio::time::advance(Duration::from_millis(1)).await;
        observed(&writer, |s| {
            !s.in_flight
                && s.receipt
                    .as_ref()
                    .is_some_and(|r| r.snapshot_revision == 100)
        })
        .await;
        assert_eq!(captures.load(Ordering::SeqCst), 2);
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert!(writer.is_joined());
        Ok(())
    }

    #[tokio::test]
    async fn save_acknowledges_only_the_dirty_revision_at_capture_start() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let owner = ThreadHandle::restore_current(
            ThreadCurrent::new("current-test".into(), RuntimeEpoch::new()),
            None,
        )?;
        let epoch = owner.runtime_epoch();
        let started = Arc::new(Notify::new());
        let release = Arc::new(Notify::new());
        let calls = Arc::new(AtomicUsize::new(0));
        let mut source = CurrentSource::new(
            {
                let started = started.clone();
                let release = release.clone();
                move |epoch, _| {
                    let started = started.clone();
                    let release = release.clone();
                    let calls = calls.clone();
                    Box::pin(async move {
                        if calls.fetch_add(1, Ordering::SeqCst) == 0 {
                            started.notify_one();
                            release.notified().await;
                        }
                        // The captured owner may already report a later sequence than its stream.
                        Ok(current(epoch, 100))
                    })
                }
            },
            |epoch| Box::pin(async move { Ok(current(epoch, 100)) }),
        );
        source.observations = Some(owner.clone());
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()),
            || {},
        );
        writer.activate(None, epoch, source).await?;
        let before = writer.snapshot().observed_revision.unwrap();
        let flushing = tokio::spawn({
            let writer = writer.clone();
            async move { writer.flush(epoch).await }
        });
        started.notified().await;
        owner
            .patch_runtime_facts(vec![RuntimeFact {
                source_id: "during-capture".into(),
                content: vec![ContextContent::Text {
                    text: "new state".into(),
                }],
            }])
            .await?;
        let newer = observed(&writer, |state| {
            state.dirty
                && state
                    .observed_revision
                    .is_some_and(|revision| revision > before)
        })
        .await;
        release.notify_one();
        assert_eq!(flushing.await??.snapshot_revision, before);
        assert!(writer.snapshot().dirty);
        assert_eq!(
            writer.flush(epoch).await?.snapshot_revision,
            newer.observed_revision.unwrap()
        );
        assert!(!writer.snapshot().dirty);
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        owner.close().await?;
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn automatic_failure_waits_five_seconds_from_failure_not_next_tick() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let calls = Arc::new(AtomicUsize::new(0));
        let calls_io = calls.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |_, _| {
                    if calls_io.fetch_add(1, Ordering::SeqCst) == 0 {
                        Err(io::Error::other("disk unavailable"))
                    } else {
                        Ok(())
                    }
                },
            )),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        writer
            .activate(
                None,
                epoch,
                source(
                    Arc::new(AtomicU64::new(1)),
                    Arc::new(AtomicUsize::new(0)),
                    Arc::new(AtomicUsize::new(0)),
                ),
            )
            .await?;
        tokio::time::advance(SAVE_INTERVAL).await;
        let failed = observed(&writer, |s| s.error.is_some()).await;
        assert!(
            failed.dirty && failed.receipt.is_none() && failed.last_successful_save_at.is_none()
        );
        let successor = RuntimeEpoch::new();
        writer
            .activate(
                Some(epoch),
                successor,
                source(
                    Arc::new(AtomicU64::new(2)),
                    Arc::new(AtomicUsize::new(0)),
                    Arc::new(AtomicUsize::new(0)),
                ),
            )
            .await?;
        assert!(
            writer.snapshot().error.is_some(),
            "epoch admission cannot acknowledge an old failure"
        );
        writer.shared.mark_dirty(epoch, None);
        tokio::time::advance(Duration::from_millis(4999)).await;
        tokio::task::yield_now().await;
        assert_eq!(
            calls.load(Ordering::SeqCst),
            1,
            "2s ticks cannot shorten backoff"
        );
        tokio::time::advance(Duration::from_millis(1)).await;
        let saved = observed(&writer, |s| s.receipt.is_some()).await;
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert!(saved.error.is_none() && saved.last_successful_save_at.is_some());
        assert!(saved.persistence_snapshot().snapshot_age_millis.is_some());
        assert_eq!(saved.receipt.unwrap().runtime_epoch, successor);
        writer
            .close(successor, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn explicit_flush_bypasses_backoff_once_and_close_does_not_retry() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let calls = Arc::new(AtomicUsize::new(0));
        let io_calls = calls.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |_, _| {
                    io_calls.fetch_add(1, Ordering::SeqCst);
                    Err(io::Error::other("write refused"))
                },
            )),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        writer
            .activate(
                None,
                epoch,
                source(
                    Arc::new(AtomicU64::new(1)),
                    Arc::new(AtomicUsize::new(0)),
                    Arc::new(AtomicUsize::new(0)),
                ),
            )
            .await?;
        let before = Instant::now();
        assert!(writer.flush(epoch).await.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(Instant::now(), before);
        assert!(writer.flush(epoch).await.is_err());
        assert_eq!(
            calls.load(Ordering::SeqCst),
            2,
            "explicit flush ignores the retry deadline but attempts once"
        );
        assert!(
            writer
                .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await
                .is_err()
        );
        assert_eq!(
            calls.load(Ordering::SeqCst),
            3,
            "close makes one final write, without retrying"
        );
        assert!(writer.is_joined());
        assert_eq!(writer.snapshot().lifecycle, CurrentLifecycle::Closed);
        assert!(writer.snapshot().receipt.is_none());
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn epoch_handoff_waits_old_io_and_rejects_old_offers_and_flushes() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let (started, waiting) = oneshot::channel();
        let (release, released) = std::sync::mpsc::channel();
        let gate = Mutex::new(Some((started, released)));
        let epochs = Arc::new(Mutex::new(Vec::new()));
        let written = epochs.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |_, bytes| {
                    let current: ThreadCurrent = serde_json::from_slice(bytes)?;
                    if let Some((started, released)) = gate.lock().unwrap().take() {
                        let _ = started.send(());
                        released.recv().unwrap();
                    }
                    written.lock().unwrap().push(current.saved_runtime_epoch);
                    Ok(())
                },
            )),
            || {},
        );
        let old = RuntimeEpoch::new();
        let new = RuntimeEpoch::new();
        let revision = Arc::new(AtomicU64::new(1));
        let producer = source(
            revision.clone(),
            Arc::new(AtomicUsize::new(0)),
            Arc::new(AtomicUsize::new(0)),
        );
        writer.activate(None, old, producer.clone()).await?;
        let flushing = tokio::spawn({
            let writer = writer.clone();
            async move { writer.flush(old).await }
        });
        waiting.await?;
        revision.store(2, Ordering::SeqCst);
        writer.shared.mark_dirty(old, None);
        // Admit a second explicit flush behind the blocked write. It must capture again rather
        // than treating the first in-flight receipt as coverage of the newer current.
        let (flush_reply, flushed_again) = oneshot::channel();
        writer
            .commands
            .send(Command::Flush {
                epoch: old,
                reply: flush_reply,
            })
            .await
            .unwrap();
        let switching = tokio::spawn({
            let writer = writer.clone();
            let producer = producer.clone();
            async move { writer.activate(Some(old), new, producer).await }
        });
        tokio::task::yield_now().await;
        assert_eq!(writer.snapshot().runtime_epoch, Some(old));
        assert!(!switching.is_finished());
        release.send(())?;
        assert_eq!(flushing.await??.snapshot_revision, 1);
        assert_eq!(flushed_again.await??.snapshot_revision, 2);
        switching.await??;
        writer.flush(new).await?;
        writer.shared.mark_dirty(old, None);
        assert!(!writer.snapshot().dirty);
        assert!(writer.flush(old).await.is_err());
        assert!(writer.activate(Some(old), old, producer).await.is_err());
        assert_eq!(epochs.lock().unwrap().as_slice(), &[old, old, new]);
        writer
            .close(new, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn close_cancels_capture_and_saves_final_handoff_without_recapture() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let (started, waiting) = oneshot::channel();
        let started = Mutex::new(Some(started));
        let finishes = Arc::new(AtomicUsize::new(0));
        let final_count = finishes.clone();
        let source = CurrentSource::new(
            move |_, cancellation| {
                let _ = started.lock().unwrap().take().unwrap().send(cancellation);
                Box::pin(std::future::pending())
            },
            move |epoch| {
                final_count.fetch_add(1, Ordering::SeqCst);
                Box::pin(async move { Ok(current(epoch, 99)) })
            },
        );
        let saved = Arc::new(Mutex::new(Vec::new()));
        let output = saved.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |_, bytes| {
                    output
                        .lock()
                        .unwrap()
                        .push(serde_json::from_slice::<ThreadCurrent>(bytes)?.snapshot_revision);
                    Ok(())
                },
            )),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        writer.activate(None, epoch, source).await?;
        tokio::time::advance(SAVE_INTERVAL).await;
        let capture_cancellation = waiting.await?;
        let before = Instant::now();
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert_eq!(
            Instant::now(),
            before,
            "close does not wait the capture timeout or next frame"
        );
        assert!(capture_cancellation.is_cancelled());
        assert_eq!(finishes.load(Ordering::SeqCst), 1);
        assert_eq!(saved.lock().unwrap().as_slice(), &[99]);
        assert_eq!(writer.snapshot().receipt.unwrap().snapshot_revision, 99);
        writer.shared.mark_dirty(epoch, None);
        assert!(!writer.snapshot().dirty);
        assert!(writer.flush(epoch).await.is_err());
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert_eq!(finishes.load(Ordering::SeqCst), 1);
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn capture_timeout_keeps_dirty_without_entering_file_stage() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let (started, waiting) = oneshot::channel();
        let started = Mutex::new(Some(started));
        let source = CurrentSource::new(
            move |_, token| {
                if let Some(started) = started.lock().unwrap().take() {
                    let _ = started.send(token);
                }
                Box::pin(std::future::pending())
            },
            move |epoch| Box::pin(async move { Ok(current(epoch, 2)) }),
        );
        let writes = Arc::new(AtomicUsize::new(0));
        let io_writes = writes.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |_, _| {
                    io_writes.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                },
            )),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        writer.activate(None, epoch, source).await?;
        tokio::time::advance(SAVE_INTERVAL).await;
        let token = waiting.await?;
        tokio::time::advance(CAPTURE_TIMEOUT).await;
        observed(&writer, |s| s.error.is_some() && !s.in_flight).await;
        assert!(token.is_cancelled());
        assert!(writer.snapshot().dirty);
        assert_eq!(writes.load(Ordering::SeqCst), 0);
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert_eq!(writes.load(Ordering::SeqCst), 1);
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn cancelled_close_waiter_retains_join_and_final_handoff_failure_is_explicit()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let (entered, waiting) = oneshot::channel();
        let (release, released) = oneshot::channel();
        let finish = Mutex::new(Some((entered, released)));
        let source = CurrentSource::new(
            |epoch, _| Box::pin(async move { Ok(current(epoch, 1)) }),
            move |_| {
                let (entered, released) = finish.lock().unwrap().take().unwrap();
                let _ = entered.send(());
                Box::pin(async move {
                    released.await?;
                    Err(anyhow!("producer did not hand off final stream"))
                })
            },
        );
        let writes = Arc::new(AtomicUsize::new(0));
        let io_writes = writes.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |_, _| {
                    io_writes.fetch_add(1, Ordering::SeqCst);
                    Ok(())
                },
            )),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        writer.activate(None, epoch, source).await?;
        let close = tokio::spawn({
            let writer = writer.clone();
            async move {
                writer
                    .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                    .await
            }
        });
        waiting.await?;
        close.abort();
        assert!(close.await.unwrap_err().is_cancelled());
        release.send(()).unwrap();
        observed(&writer, |s| s.lifecycle == CurrentLifecycle::Closed).await;
        assert!(!writer.is_joined());
        let error = writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await
            .unwrap_err();
        assert!(format!("{error:#}").contains("producer did not hand off"));
        assert!(writer.is_joined());
        assert_eq!(
            writes.load(Ordering::SeqCst),
            0,
            "missing final data must not publish incomplete current"
        );
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn failed_overwrite_does_not_acknowledge_and_partial_file_can_be_retried() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let mode = Arc::new(AtomicUsize::new(0));
        let io_mode = mode.clone();
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()).with_write(Arc::new(
                move |path, bytes| {
                    let mode = io_mode.load(Ordering::SeqCst);
                    if mode == 1 {
                        return Err(io::Error::other("injected failure before write"));
                    }
                    if mode == 2 {
                        std::fs::write(path, &bytes[..bytes.len() / 2])?;
                        return Err(io::Error::other("injected failure during write"));
                    }
                    std::fs::write(path, bytes)
                },
            )),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        let revision = Arc::new(AtomicU64::new(1));
        writer
            .activate(
                None,
                epoch,
                source(
                    revision.clone(),
                    Arc::new(AtomicUsize::new(0)),
                    Arc::new(AtomicUsize::new(0)),
                ),
            )
            .await?;
        writer.flush(epoch).await?;
        let success = writer.snapshot();
        let path = directory.path().join("current.json");
        for (failure_mode, next) in [(1, 2), (2, 3)] {
            mode.store(failure_mode, Ordering::SeqCst);
            revision.store(next, Ordering::SeqCst);
            let error = writer.flush(epoch).await.unwrap_err();
            assert!(format!("{error:#}").contains("injected"));
            let bytes = std::fs::read(&path)?;
            if failure_mode == 1 {
                assert_eq!(
                    serde_json::from_slice::<ThreadCurrent>(&bytes)?.snapshot_revision,
                    1
                );
            } else {
                assert!(serde_json::from_slice::<ThreadCurrent>(&bytes).is_err());
            }
            let state = writer.snapshot();
            assert_eq!(state.receipt, success.receipt);
            assert_eq!(
                state.last_successful_save_at,
                success.last_successful_save_at
            );
            assert_eq!(
                state.last_successful_capture_at,
                success.last_successful_capture_at
            );
            assert!(state.dirty && state.error.is_some());
        }
        mode.store(0, Ordering::SeqCst);
        revision.store(4, Ordering::SeqCst);
        assert_eq!(writer.flush(epoch).await?.snapshot_revision, 4);
        assert_eq!(
            serde_json::from_slice::<ThreadCurrent>(&std::fs::read(&path)?)?.snapshot_revision,
            4
        );
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn failed_final_write_retries_retained_data_without_recapturing_the_producer()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join(CURRENT_FILE_NAME);
        std::fs::create_dir(&path)?;
        let finishes = Arc::new(AtomicUsize::new(0));
        let source =
            CurrentSource::new(|epoch, _| Box::pin(async move { Ok(current(epoch, 1)) }), {
                let finishes = finishes.clone();
                move |epoch| {
                    assert_eq!(finishes.fetch_add(1, Ordering::AcqRel), 0);
                    Box::pin(async move { Ok(current(epoch, 2)) })
                }
            });
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()),
            || {},
        );
        let epoch = RuntimeEpoch::new();
        writer.activate(None, epoch, source).await?;
        assert!(
            writer
                .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
                .await
                .is_err()
        );
        assert!(writer.is_joined());
        let failed = writer.snapshot();
        assert!(failed.error.is_some());
        assert!(failed.receipt.is_none());
        std::fs::remove_dir(&path)?;
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Preserve)
            .await?;
        assert!(writer.is_joined());
        assert_eq!(finishes.load(Ordering::Acquire), 1);
        let saved = ThreadCurrent::from_json(&std::fs::read(path)?, "current-test")?;
        assert_eq!(saved.saved_runtime_epoch, epoch);
        assert_eq!(saved.snapshot_revision, 2);
        let closed = writer.snapshot();
        assert_eq!(
            closed
                .receipt
                .as_ref()
                .map(|receipt| receipt.snapshot_revision),
            Some(2)
        );
        assert!(closed.error.is_none());
        assert!(!closed.dirty && !closed.in_flight);
        Ok(())
    }

    #[tokio::test(start_paused = true)]
    async fn deletion_joins_the_original_source_without_retrying_or_acknowledging_a_save()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let epoch = RuntimeEpoch::new();
        let fail_capture = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let finishes = Arc::new(AtomicUsize::new(0));
        let source = CurrentSource::new(
            {
                let fail_capture = fail_capture.clone();
                move |epoch, _| {
                    let fail_capture = fail_capture.clone();
                    Box::pin(async move {
                        ensure!(
                            !fail_capture.load(Ordering::Acquire),
                            "original Current save failure"
                        );
                        Ok(current(epoch, 1))
                    })
                }
            },
            {
                let finishes = finishes.clone();
                move |epoch| {
                    finishes.fetch_add(1, Ordering::AcqRel);
                    Box::pin(async move { Ok(current(epoch, 2)) })
                }
            },
        );
        let writer = CurrentWriter::new(
            CurrentFile::new(directory.path().into(), "current-test".into()),
            || {},
        );
        writer.activate(None, epoch, source).await?;
        writer.flush(epoch).await?;
        let before = std::fs::read(directory.path().join(CURRENT_FILE_NAME))?;
        fail_capture.store(true, Ordering::Release);
        assert!(writer.flush(epoch).await.is_err());
        let failed = writer.snapshot();
        let original_error = failed.error.as_ref().unwrap().to_string();
        writer
            .close(epoch, crate::thread_assembler::ClosePurpose::Delete)
            .await?;
        assert!(writer.is_joined());
        assert_eq!(finishes.load(Ordering::Acquire), 1);
        assert_eq!(
            std::fs::read(directory.path().join(CURRENT_FILE_NAME))?,
            before
        );
        let closed = writer.snapshot();
        assert_eq!(closed.receipt, failed.receipt);
        assert_eq!(
            closed.last_successful_save_at,
            failed.last_successful_save_at
        );
        assert_eq!(closed.error.as_ref().unwrap().to_string(), original_error);
        assert!(!closed.in_flight);
        assert!(!closed.observer_registered);
        Ok(())
    }
}

#[cfg(all(test, target_os = "linux"))]
mod responses_current_tests;
