//! Observation registration and incarnation lifecycle.

use super::super::ModelPerformanceOwner;
use super::directory;
use super::slot::ObservationSlot;
use super::worker::{Progress, WorkerState, await_history_durable, run};
use crate::studio::{ProductEventBus, StudioStore};
use anyhow::{Context, Result, bail};
use pl_core::thread::{ThreadHandle, ThreadLifecycle, ThreadSnapshot};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, watch};
use tokio::task::JoinHandle;

pub(crate) struct Observation {
    owner: std::sync::Weak<crate::session::NativeResources>,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    task: tokio::sync::Mutex<Option<JoinHandle<()>>>,
}
impl Drop for Observation {
    fn drop(&mut self) {
        if let Some(task) = self.task.get_mut().take() {
            task.abort();
        }
    }
}

impl Observation {
    async fn join(&self) -> Result<()> {
        self.join_for_purpose(crate::thread_assembler::ClosePurpose::Preserve)
            .await
    }

    async fn join_for_purpose(&self, purpose: crate::thread_assembler::ClosePurpose) -> Result<()> {
        let mut slot = self.task.lock().await;
        if let Some(task) = slot.as_mut() {
            let joined = task.await;
            *slot = None;
            if let Err(error) = joined {
                let error = Arc::new(anyhow::Error::new(error));
                *self
                    .state
                    .join_failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(error.clone());
                self.state.progress.send_modify(|progress| {
                    progress.finished = true;
                    progress.error = Some(error.clone());
                });
                bail!("Thread product observer join failed: {error:#}");
            }
            if purpose == crate::thread_assembler::ClosePurpose::Preserve
                && !self.state.progress.borrow().finished
            {
                let error = Arc::new(anyhow::anyhow!(
                    "Thread product observer ended without its final durable projection"
                ));
                self.state.progress.send_modify(|progress| {
                    progress.finished = true;
                    progress.error = Some(error.clone());
                });
            }
        }
        if let Some(error) = self
            .state
            .join_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
        {
            bail!("Thread product observer join failed: {error:#}");
        }
        if purpose == crate::thread_assembler::ClosePurpose::Delete {
            return Ok(());
        }
        if let Some(error) = self.state.progress.borrow().error.as_ref() {
            bail!("Thread product observer failed: {error:#}");
        }
        Ok(())
    }
}
#[derive(Clone)]
pub(in crate::studio::runtime) struct ObservationServices {
    pub(in crate::studio::runtime) config: crate::config::ConfigRuntime,
    pub(in crate::studio::runtime) settings_updates:
        watch::Receiver<crate::config::ConfigRuntimeSnapshot>,
    pub(in crate::studio::runtime) recovery: crate::studio::StudioRecoveryRegistry,
    pub(in crate::studio::runtime) store: StudioStore,
    pub(in crate::studio::runtime) events: ProductEventBus,
    pub(in crate::studio::runtime) performance: ModelPerformanceOwner,
    pub(in crate::studio::runtime) sessions: crate::session::WeakSessionTable,
    pub(in crate::studio::runtime) writer:
        crate::studio::storage::write_behind::ThreadWriteBehindWriter,
    pub(in crate::studio::runtime) run_export:
        Option<std::sync::Arc<crate::studio::runtime::run_export::RunExportCoordinator>>,
}
impl ObservationServices {
    pub(super) fn session_of(&self, id: &str) -> Option<crate::session::SessionRuntime> {
        if let Some((identity, _, _)) = self.events.agent_execution_identity(id) {
            return self.sessions.upgrade()?.get(&identity.session_id);
        }
        self.sessions.upgrade()?.holding(id)
    }

    pub(super) fn require_session(&self, id: &str) -> Result<crate::session::SessionRuntime> {
        self.session_of(id)
            .context("Thread has no resident session")
    }
}
struct Shared {
    delivery_closed: tokio_util::sync::CancellationToken,
    projector: ObservationServices,
    observations: Mutex<BTreeMap<String, Vec<std::sync::Weak<Observation>>>>,
    /// Stable passive slots survive absent → live → absent transitions.
    live: Mutex<BTreeMap<String, Arc<ObservationSlot>>>,
}
#[derive(Clone)]
pub(in crate::studio::runtime) struct ThreadObservations(Arc<Shared>);

impl ThreadObservations {
    fn observations(&self, id: Option<&str>) -> Vec<(String, Arc<Observation>)> {
        self.0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|(key, _)| id.is_none_or(|id| key.as_str() == id))
            .flat_map(|(id, entries)| {
                entries
                    .iter()
                    .filter_map(std::sync::Weak::upgrade)
                    .map(|entry| (id.clone(), entry))
            })
            .collect()
    }

    pub(in crate::studio::runtime) fn new(projector: ObservationServices) -> Self {
        Self(Arc::new(Shared {
            delivery_closed: Default::default(),
            projector,
            observations: Mutex::new(BTreeMap::new()),
            live: Mutex::new(BTreeMap::new()),
        }))
    }

    /// The live `MetaEventBus` of one observed Thread, if its projection owner was installed.
    pub(in crate::studio::runtime) fn meta_bus(
        &self,
        id: &str,
    ) -> Option<crate::timeline::MetaEventBus> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .and_then(|slot| slot.meta_bus())
    }

    /// End outward delivery before joining producers; their original save
    /// responsibility continues independently of an idle external receiver.
    pub(in crate::studio::runtime) fn close_deliveries(&self) {
        self.0.delivery_closed.cancel();
    }

    fn close_delivery(&self, id: &str, _thread: &ThreadHandle) {
        if let Some(bus) = self.meta_bus(id) {
            self.observation_slot(id).retire_bus(&bus);
        }
    }

    /// Register the passive source before asynchronous reads without activating execution.
    pub(in crate::studio::runtime) fn observation_slot(&self, id: &str) -> Arc<ObservationSlot> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(id.to_owned())
            .or_default()
            .clone()
    }

    pub(in crate::studio::runtime) fn install(&self) -> Result<()> {
        self.0
            .projector
            .sessions
            .upgrade()
            .context("Session table closed")?
            .push_assignment(self.session_assignment())?;
        Ok(())
    }

    fn session_assignment(&self) -> crate::thread_assembler::SessionAssignment {
        let owner = Arc::downgrade(&self.0);
        let draining = owner.clone();
        let synchronizing = owner.clone();
        let closing = owner.clone();
        let terminal = owner.clone();
        crate::thread_assembler::SessionAssignment::observation(
            move |id, thread, resources| {
                if let Some(owner) = owner.upgrade() {
                    ThreadObservations(owner).observe(id, thread, resources);
                }
            },
            move |id, purpose| {
                let owner = draining.clone();
                Box::pin(async move {
                    let owner = owner
                        .upgrade()
                        .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    let observations = ThreadObservations(owner);
                    if purpose == crate::thread_assembler::ClosePurpose::Preserve {
                        observations
                            .synchronize(Some(&id))
                            .await
                            .map_err(|source| {
                                crate::thread_assembler::ThreadAssemblyError::Resource {
                                    operation: "drain Thread product observation",
                                    source: source.into_boxed_dyn_error(),
                                }
                            })?;
                    }
                    observations
                        .drain_for_purpose(&id, purpose)
                        .await
                        .map_err(|source| {
                            crate::thread_assembler::ThreadAssemblyError::Resource {
                                operation: "join Thread storage and observation workers",
                                source: source.into_boxed_dyn_error(),
                            }
                        })?;
                    Ok(())
                })
            },
            Some(Arc::new(move |id: &str| {
                let owner = terminal.upgrade()?;
                ThreadObservations(owner).observation_slot(id).last_turn()
            })),
            move |id, thread, purpose| {
                if let Some(owner) = closing.upgrade() {
                    let observations = ThreadObservations(owner);
                    observations.close_delivery(&id, &thread);
                    if purpose == crate::thread_assembler::ClosePurpose::Delete {
                        observations.cancel_for_deletion(&id);
                    }
                }
                Box::pin(async { Ok(()) })
            },
            move |id| {
                let owner = synchronizing.clone();
                Box::pin(async move {
                    let owner = owner
                        .upgrade()
                        .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    ThreadObservations(owner)
                        .synchronize(Some(&id))
                        .await
                        .map_err(
                            |source| crate::thread_assembler::ThreadAssemblyError::Resource {
                                operation: "acknowledge parent report handoff",
                                source: source.into_boxed_dyn_error(),
                            },
                        )
                })
            },
        )
    }

    fn cancel_for_deletion(&self, id: &str) {
        for (_, observation) in self.observations(Some(id)) {
            observation.state.deletion.cancel();
        }
    }

    async fn drain_for_purpose(
        &self,
        id: &str,
        purpose: crate::thread_assembler::ClosePurpose,
    ) -> Result<()> {
        let observations = self
            .observations(Some(id))
            .into_iter()
            .map(|(_, observation)| observation)
            .collect::<Vec<_>>();
        let slot = self.observation_slot(id);
        for observation in &observations {
            anyhow::ensure!(
                observation.thread.snapshot().lifecycle == ThreadLifecycle::Closed,
                "cannot retire workers of an open Thread"
            );
            observation.join_for_purpose(purpose).await?;
            if purpose == crate::thread_assembler::ClosePurpose::Delete {
                observation
                    .state
                    .channel
                    .stop_and_join_for_deletion()
                    .await?;
            } else {
                observation.state.channel.stop_and_join().await?;
            }
        }
        for observation in &observations {
            if let Some(owner) = observation.owner.upgrade() {
                owner
                    .observations
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .retain(|current| !Arc::ptr_eq(current, observation));
            }
        }
        {
            let mut all = self
                .0
                .observations
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(entries) = all.get_mut(id) {
                entries.retain(|entry| {
                    entry
                        .upgrade()
                        .is_some_and(|entry| !observations.iter().any(|old| Arc::ptr_eq(&entry, old)))
                });
                if entries.is_empty() {
                    all.remove(id);
                }
            }
        }
        if let Some(bus) = slot.meta_bus() {
            slot.retire_bus(&bus);
            bus.close().await;
        }
        Ok(())
    }

    fn observe(
        &self,
        id: String,
        thread: ThreadHandle,
        resources: Arc<crate::session::NativeResources>,
    ) {
        let observed = thread.snapshot();
        let recovered_through = observed.commit_sequence;
        // Bootstrap facts/extensions can already have commits. The monotonic execution/call
        // ledgers, not a zero commit fence, prove that no prior model Turn needs reconciliation.
        let observed_before_execution = observed.lifecycle == ThreadLifecycle::Open
            && observed.execution_sequence == 0
            && observed.execution.is_none()
            && observed.turns.is_empty()
            && observed.attempts.is_empty()
            && observed.attempt_ids.is_empty()
            && observed.live_calls.is_empty()
            && observed
                .context
                .records
                .iter()
                .all(|record| record.turn_id.is_none());
        let (progress, _) = watch::channel(Progress {
            applied: recovered_through,
            ..Progress::default()
        });
        // The same channel the writer incarnation admits into: the observation barrier below asks
        // this handle how far the writer is durable, not a freshly created one.
        let channel = self
            .0
            .projector
            .store
            .thread_persistence()
            .history_channel(&id);
        let state = Arc::new(WorkerState {
            native_directory: self.0.projector.events.begin_native_observation(&id),
            deletion: Default::default(),
            join_failure: Default::default(),
            terminal_transfer: Default::default(),
            progress,
            retry: Notify::new(),
            channel,
            reconciliation_through: Arc::new(std::sync::atomic::AtomicU64::new(recovered_through)),
            observed_before_execution,
        });
        let slot = self.observation_slot(&id);
        let catalogs = self.0.projector.config.subscribe_model_catalogs();
        let worker_state = state.clone();
        let projector = self.0.projector.clone();
        let worker_thread = thread.clone();
        let worker_id = id.clone();
        let deletion = state.deletion.clone();
        let task = tokio::spawn(async move {
            tokio::select! {
                biased;
                () = deletion.cancelled() => {},
                () = run(
                projector,
                worker_id,
                worker_thread,
                worker_state,
                recovered_through,
                slot,
                catalogs,
                ) => {},
            }
        });
        let observation = Arc::new(Observation {
            owner: Arc::downgrade(&resources),
            thread,
            state,
            task: tokio::sync::Mutex::new(Some(task)),
        });
        resources
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(observation.clone());
        let mut all = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let previous = all.entry(id).or_default();
        previous.retain(|entry| entry.strong_count() > 0);
        previous.push(Arc::downgrade(&observation));
    }

    pub(in crate::studio::runtime) async fn synchronize(&self, id: Option<&str>) -> Result<()> {
        self.0.projector.writer.retry_now();
        let observations = self.observations(id);
        for (id, observation) in observations {
            let target_snapshot = observation.thread.snapshot();
            let target = target_snapshot.commit_sequence;
            // A fixed durability wait is not a new observation source. Only recovery from a
            // discontinuity revokes first-send authority; otherwise a caller merely observing a
            // healthy terminal could race and cancel its legitimate live feedback.
            if observation.state.progress.borrow().error.is_some() {
                observation
                    .state
                    .reconciliation_through
                    .fetch_max(target, std::sync::atomic::Ordering::AcqRel);
            }
            // The explicit retry only wakes the worker: an unresolved error is reported as it
            // stands, and only the worker's own successful pass — which replaces the whole
            // progress value, error included — can settle the observation again.
            observation.state.retry.notify_one();
            let durable_through =
                await_settled_target(&id, observation.as_ref(), &target_snapshot).await?;
            // A settled observation is also durable. Observation no longer flushes history per batch,
            // so this barrier is what keeps "the observer applied commit N" meaning "history holds
            // commit N" for explicit history queries and shutdown verification. The wait is for
            // the handoff ticket the
            // projection had reached when it applied `target` — every commit up to `target` it owns —
            // so it neither waits on the owner's command queue nor on a later, unprojected commit, and
            // it never asks for a watermark a channel created by a re-activation cannot move.
            await_history_durable(&observation.state.channel, &id, durable_through)
                .await
                .with_context(|| format!("Thread {id} product observation barrier"))?;
            if let Some(bus) = self.meta_bus(&id) {
                bus.flush_through_commit(target)
                    .await
                    .with_context(|| format!("Thread {id} MetaEventBus durability barrier"))?;
            }
        }
        // The observation worker no longer waits on disk for each projected batch, so the explicit
        // sync barrier carries the durability: every product write admitted up to the watermark this
        // barrier just waited for is drained before the caller observes a settled terminal state.
        // The target is fixed at call time, so this never waits for unrelated later writes.
        let target = self.0.projector.writer.admitted_ticket();
        self.0.projector.writer.flush_through(target).await?;
        Ok(())
    }

    /// Explicit parent continuation repairs only Current-backed pending Native deliveries even for
    /// unloaded children. It may prepare storage, but opens no child model, tool or workspace.
    pub(in crate::studio::runtime) async fn reconcile_children(&self, parent: &str) -> Result<()> {
        let services = &self.0.projector;
        let parent_record = services
            .store
            .read_thread(parent)
            .await?
            .context("missing parent Thread record")?;
        services
            .require_session(parent)?
            .recover_saved_review_deliveries(&crate::Thread::from(parent_record))
            .await?;
        for member in services.store.read_directory_tree(parent).await? {
            if !member.is_native() || member.parent_thread_id.as_deref() != Some(parent) {
                continue;
            }
            let child =
                crate::studio::records::thread_projection(&member.session, &member.agent, |id| {
                    services
                        .store
                        .catalog()
                        .get_agent(id)
                        .map(|agent| agent.thread_id)
                })?;
            if services
                .session_of(&child.id)
                .and_then(|session| session.thread(&child.id))
                .is_some()
            {
                self.synchronize(Some(&child.id)).await?;
                services
                    .require_session(&child.id)?
                    .recover_saved_review_deliveries(&child)
                    .await?;
                continue;
            }
            // Parent recovery explicitly prepares its cold children's storage before projecting
            // their facts. It never activates a child, rebuilds its workspace or asks a model.
            // A complete Current can retain large domain state. Keep its
            // recovery result on the heap across directory/delivery awaits.
            let Some(current) = Box::pin(async {
                crate::studio::thread_factory::recovery::load_current_for_recovery(
                    &services.store,
                    &child,
                )
                .await
                .map(|current| current.map(Box::new))
            })
            .await?
            else {
                continue;
            };
            // A cold child's interruption is a fact the list must publish: a restart otherwise loses
            // "stopped, waiting for the main agent" for every member that is not loaded again. This
            // reads only the complete saved Current — no activation, no workspace, no model request.
            directory::publish_cold_scheduling_state(
                services,
                &child,
                &member.agent,
                &current.state.to_paused_snapshot(),
            )
            .await?;
            services
                .require_session(&child.id)?
                .recover_saved_review_deliveries(&child)
                .await?;
        }
        Ok(())
    }

    pub(in crate::studio::runtime) async fn finish(&self) -> Result<()> {
        // 执行实例更换保留内容资格；整个运行时结束则封闭旧资格并等待在途读取。
        self.close_deliveries();
        let slots = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for slot in slots {
            slot.close_readers().await?;
        }
        self.synchronize(None).await?;
        let observations = self
            .observations(None)
            .into_iter()
            .map(|(_, observation)| observation);
        for observation in observations {
            let mut progress = observation.state.progress.subscribe();
            loop {
                let state = progress.borrow().clone();
                if let Some(error) = state.error {
                    bail!("Thread product observer failed: {error:#}");
                }
                if state.finished {
                    break;
                }
                tokio::select! {
                    changed = progress.changed() => {
                        changed.context("Thread product observer ended without final state")?;
                    }
                    joined = observation.join() => joined?,
                }
            }
            observation.join().await?;
            observation.state.channel.stop_and_join().await?;
        }
        Ok(())
    }
}

/// Waits for the fixed commit target, returning the handoff ticket for its durable barrier.
///
/// A call can wake a retry and still see the original error. Only the worker's next successful
/// pass clears that error by replacing the progress value.
async fn await_settled_target(
    id: &str,
    observation: &Observation,
    target_snapshot: &ThreadSnapshot,
) -> Result<u64> {
    let target = target_snapshot.commit_sequence;
    let mut progress = observation.state.progress.subscribe();
    loop {
        let state = progress.borrow().clone();
        if let Some(error) = state.error {
            bail!("Thread {id} product observation failed: {error:#}");
        }
        if state.initialized
            && state.applied >= target
            && (target_snapshot.lifecycle != ThreadLifecycle::Closed || state.finished)
        {
            break Ok(state.handoff);
        }
        if state.finished {
            bail!("Thread {id} product observer ended before commit {target}");
        }
        tokio::select! {
            changed = progress.changed() => {
                changed.context("Thread product observer progress closed")?;
            }
            joined = observation.join() => joined?,
        }
    }
}
