//! Owned, retryable product projections of the Thread's committed effect stream.
//!
//! Observation consumes the Thread's reliable admission queue and is its **single realtime
//! projection owner**: it projects every admitted fact and the streaming overlay once, publishes the
//! content into the shared session and broadcasts the same typed changes on a bounded feed that
//! subscriptions only read. Billing, directory and terminal facts come from the same in-memory
//! projection, so an ordinary commit neither parks this observer behind the owner's command queue
//! nor waits for the disk. Durable history is read back once when the projection is installed on a
//! Thread whose work started earlier, and by the explicit cold recovery of an unloaded child.
mod billing;
mod directory;
mod reports;

use super::{ModelPerformanceOwner, StudioRuntime};
use crate::studio::{ProductEventBus, StudioStore};
use anyhow::{Context, Result, bail};
use pl_core::chat::Session;
use pl_core::thread::{
    ThreadHandle, ThreadLifecycle, ThreadSnapshot, UsageSummary, cold::ThreadWrite,
};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
use tokio::{
    sync::{Notify, broadcast, watch},
    task::JoinHandle,
};

use crate::studio::storage::thread_writer::HistoryChannel;
use crate::studio::thread_projection::{LiveEvent, LiveProjection, storage_state};

/// Fixed bound on the frames one subscriber may fall behind the projection owner.
///
/// The feed is a bounded observation channel, not a log: a subscriber that stops draining observes
/// a lag and resynchronizes from the database window instead of letting this queue grow with history.
const LIVE_FEED_FRAMES: usize = 512;

/// One output of a Thread's single realtime projection owner.
#[derive(Debug, Clone)]
pub(in crate::studio) enum ThreadLiveEvent {
    /// Changes produced by committed effect `sequence`.
    ///
    /// The vocabulary is deliberately content-free: the projection owner writes every body into the
    /// shared session and the GUI reads it from that one content window, so the status feed carries
    /// only Turn lifecycle and interaction facts. A subscriber therefore never projects or
    /// republishes content.
    Committed {
        sequence: u64,
        changes: Vec<LiveEvent>,
    },
    /// The projection owner could not prove continuity for `dropped` commits and re-seeded; every
    /// subscriber must resynchronize from the database window.
    Rebase { dropped: u64 },
    /// Current runtime facts, including live model availability (absent from checkpoints).
    Runtime {
        runtime: Arc<pl_protocol::ThreadRuntimeSnapshot>,
    },
    /// Current execution activity of the Thread; `None` means no activity.
    ///
    /// The activity is an independent typed projection of the same owner state (it never carries a
    /// second copy of the content), so it is published by the same single owner and only when it
    /// really changed; a subscriber only forwards it. It rides as one shared handle rather than an
    /// inline value: the feed is a `broadcast` channel that clones its frame once per subscriber, so
    /// the body must stay cheap to clone and must not bloat the frame every other variant shares.
    Activity {
        activity: Option<Arc<pl_protocol::ThreadActivity>>,
    },
}

/// The realtime projection feed of one Thread.
///
/// The Thread's observation worker is its only producer, and it publishes into the shared chat
/// session at the same time. Subscribers therefore forward typed events and never project, publish
/// or read the effect window themselves.
pub(in crate::studio) struct ThreadLiveFeed {
    events: broadcast::Sender<ThreadLiveEvent>,
    /// The Thread's authoritative typed storage state, published by this owner only.
    ///
    /// The projection owner is the one place that derives it from the owner snapshot and the
    /// coordinator's typed watch, so a subscriber mirrors this value instead of recomputing the
    /// state from its own copies. A storage pause changes neither the content nor the activity, so
    /// the value is watched on its own instead of riding the content feed: a subscriber parked on
    /// the feed still learns about a pause the moment the owner publishes it.
    storage: watch::Sender<Option<pl_protocol::ThreadStorageState>>,
    /// Newest terminal Turn this owner projected, published by this owner only.
    ///
    /// A subscription's authoritative snapshot carries only the *active* Turn, and `turnCompleted`
    /// is broadcast exactly once, so a terminal Turn that committed before a client registered —
    /// a late (re)subscription, or one that resynchronizes after observing a lag — has no other way
    /// to reach it. The owner retains the last terminal Turn here as the same typed fact its frame
    /// carried, so a new subscriber is told the authoritative terminal Turn instead of guessing it
    /// from the timeline window, re-reading SQL, or caching the `running` state it happened to see.
    /// It is a watch rather than a feed frame precisely because it has to outlive the broadcast: a
    /// fact nobody was subscribed for is still the fact the next subscriber must start from.
    last_turn: watch::Sender<Option<Arc<pl_protocol::Turn>>>,
}

impl ThreadLiveFeed {
    fn new(storage: Option<pl_protocol::ThreadStorageState>) -> Self {
        let (events, _) = broadcast::channel(LIVE_FEED_FRAMES);
        let (storage, _) = watch::channel(storage);
        let (last_turn, _) = watch::channel(None);
        Self {
            events,
            storage,
            last_turn,
        }
    }

    pub(in crate::studio) fn subscribe(&self) -> broadcast::Receiver<ThreadLiveEvent> {
        self.events.subscribe()
    }

    /// Watches the newest terminal Turn this owner projected, so a subscriber that registers after
    /// that commit never has to derive the fact from the window or from SQL.
    pub(in crate::studio) fn last_turn(&self) -> watch::Receiver<Option<Arc<pl_protocol::Turn>>> {
        self.last_turn.subscribe()
    }

    /// Publishes the newest terminal Turn the owner projected.
    ///
    /// Only a terminal Turn qualifies: the running Turn is already the authoritative snapshot's own
    /// fact, and replacing the retained terminal Turn with a busy one would let a resubscribing
    /// client mistake an in-flight Turn for the last finished one. A committed effect can also reach
    /// this owner *after* a newer one — a deferred admission that storage pressure released late is
    /// taken over behind the live stream — so the retained fact only ever moves forward and the newest
    /// terminal Turn is never replaced by an older one.
    fn publish_last_turn(&self, turn: Arc<pl_protocol::Turn>) {
        let current = self.last_turn.borrow().clone();
        if let Some(current) = current.as_ref() {
            // Only a strictly newer fact moves the slot. A duplicate of the newest fact — the same
            // effect sequence and identity, e.g. a cold seed the live path then re-derives — would
            // only wake every subscriber to deliver nothing, and a terminal Turn that storage
            // pressure released late must never replace a newer one.
            if current.revision > turn.revision
                || (current.revision == turn.revision && current.id == turn.id)
            {
                return;
            }
        }
        self.last_turn.send_replace(Some(turn));
    }

    /// Watches the owner's typed storage state, so a subscriber only mirrors it.
    pub(in crate::studio) fn storage(
        &self,
    ) -> watch::Receiver<Option<pl_protocol::ThreadStorageState>> {
        self.storage.subscribe()
    }

    /// Publishes the owner's newly derived typed storage state.
    fn publish_storage(&self, storage: Option<pl_protocol::ThreadStorageState>) {
        self.storage.send_replace(storage);
    }

    fn has_subscribers(&self) -> bool {
        self.events.receiver_count() != 0
    }

    fn publish(&self, event: impl FnOnce() -> ThreadLiveEvent) {
        // Demand is advisory, not the registration barrier. Facts and retained watches are updated
        // independently; no outward envelope (or its dedicated clone) is built without a receiver.
        if self.has_subscribers() {
            let _ = self.events.send(event());
        }
    }

    /// Tells every subscriber that the owner re-seeded and continuity is no longer provable.
    fn rebase(&self, dropped: u64) {
        self.publish(|| ThreadLiveEvent::Rebase { dropped });
    }
}

#[derive(Clone, Default)]
struct Progress {
    initialized: bool,
    applied: u64,
    /// Newest commit this projection owner had handed over when it applied `applied`.
    ///
    /// The durable barrier of a settled observation waits for exactly this ticket. It is not the
    /// absolute commit watermark: a Thread re-activated in this process starts from a fresh reliable
    /// channel whose commits are already durable, so waiting for the checkpoint's sequence would wait
    /// for a watermark that can never move.
    handoff: u64,
    error: Option<Arc<anyhow::Error>>,
    finished: bool,
}
struct WorkerState {
    progress: watch::Sender<Progress>,
    retry: Notify,
    /// The Thread's reliable admission channel, shared with its history writer.
    ///
    /// A settled observation reads a finished Turn back from history, and its own barrier has to ask
    /// the writer that took the projection's handoff how far it is durable. The handle is captured
    /// here, at observation time, so the barrier observes the very incarnation the writer admits
    /// into instead of a channel that a cleanly detached predecessor already released.
    channel: Arc<HistoryChannel>,
    #[cfg(test)]
    pending_hook: Option<Arc<PendingPhaseHook>>,
}
impl WorkerState {
    /// The pending-boundary phase hook of this owner, or the empty production slot.
    #[cfg(test)]
    fn pending_hook_slot(&self) -> PendingHookSlot {
        self.pending_hook.clone()
    }
}
struct Observation {
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
        let mut slot = self.task.lock().await;
        if let Some(task) = slot.as_mut() {
            let joined = task.await;
            *slot = None;
            if let Err(error) = joined {
                let error = Arc::new(anyhow::Error::new(error));
                self.state.progress.send_modify(|progress| {
                    progress.finished = true;
                    progress.error = Some(error.clone());
                });
                bail!("Thread product observer join failed: {error:#}");
            }
            if !self.state.progress.borrow().finished {
                let error = Arc::new(anyhow::anyhow!(
                    "Thread product observer ended without its final durable projection"
                ));
                self.state.progress.send_modify(|progress| {
                    progress.finished = true;
                    progress.error = Some(error.clone());
                });
            }
        }
        if let Some(error) = self.state.progress.borrow().error.as_ref() {
            bail!("Thread product observer failed: {error:#}");
        }
        Ok(())
    }
}
#[derive(Clone)]
pub(super) struct ObservationServices {
    pub(super) config: crate::config::ConfigRuntime,
    pub(super) recovery: crate::studio::StudioRecoveryRegistry,
    pub(super) store: StudioStore,
    pub(super) events: ProductEventBus,
    pub(super) performance: ModelPerformanceOwner,
    pub(super) threads: crate::thread_assembler::StudioThreadAssembler,
    pub(super) writer: crate::studio::agent_host::ThreadWriteBehindWriter,
}
struct Shared {
    projector: ObservationServices,
    observations: Mutex<BTreeMap<String, Vec<Arc<Observation>>>>,
    /// One feed per currently observed Thread; removed when the Thread is drained.
    live: Mutex<BTreeMap<String, Arc<ThreadLiveFeed>>>,
    #[cfg(test)]
    pending_hooks: Mutex<BTreeMap<String, Arc<PendingPhaseHook>>>,
}
#[derive(Clone)]
pub(super) struct ThreadObservations(Arc<Shared>);

impl ThreadObservations {
    pub(super) fn new(projector: ObservationServices) -> Self {
        Self(Arc::new(Shared {
            projector,
            observations: Mutex::new(BTreeMap::new()),
            live: Mutex::new(BTreeMap::new()),
            #[cfg(test)]
            pending_hooks: Mutex::new(BTreeMap::new()),
        }))
    }

    /// Installs the per-owner pending-boundary phase hook of one Thread's fault test.
    #[cfg(test)]
    fn install_pending_hook(&self, id: &str, hook: Arc<PendingPhaseHook>) {
        self.0
            .pending_hooks
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(id.to_owned(), hook);
    }

    #[cfg(test)]
    fn pending_hook(&self, id: &str) -> Option<Arc<PendingPhaseHook>> {
        self.0
            .pending_hooks
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .cloned()
    }

    /// The live feed of one observed Thread, if its projection owner was installed.
    pub(super) fn live_feed(&self, id: &str) -> Option<Arc<ThreadLiveFeed>> {
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .cloned()
    }

    pub(super) fn install(
        &self,
        thread_factory: crate::studio::thread_factory::StudioThreadFactory,
        rejected_tools: super::rejected_tools::RejectedToolOwners,
    ) -> Result<()> {
        let rejected_preparations = rejected_tools.clone();
        self.0
            .projector
            .threads
            .retain_rejected_with(move |thread, tools| rejected_preparations.retain(thread, tools));
        let owner = Arc::downgrade(&self.0);
        let draining = owner.clone();
        let synchronizing = owner.clone();
        let message_store = self.0.projector.store.clone();
        let closing_factory = thread_factory.clone();
        self.0.projector.threads.observe_assembly(
            move |id, thread| {
                if let Some(owner) = owner.upgrade() {
                    ThreadObservations(owner).observe(id, thread);
                }
            },
            move |id| {
                let owner = draining.clone();
                let thread_factory = thread_factory.clone();
                Box::pin(async move {
                    let owner = owner
                        .upgrade()
                        .ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    let observations = ThreadObservations(owner);
                    observations
                        .synchronize(Some(&id))
                        .await
                        .map_err(|source| {
                            crate::thread_assembler::ThreadAssemblyError::Resource {
                                operation: "drain Thread product observation",
                                source: source.into_boxed_dyn_error(),
                            }
                        })?;
                    if !observations.0.projector.threads.is_report_receiver(&id) {
                    thread_factory.forget_tool_binding(&id);
                    }
                    observations.drain(&id).await.map_err(|source| {
                        crate::thread_assembler::ThreadAssemblyError::Resource {
                            operation: "join Thread storage and observation workers",
                            source: source.into_boxed_dyn_error(),
                        }
                    })?;
                    Ok(())
                })
            },
            // 一条已受理消息的持久身份：per-Thread 身份索引给出正文摘要与原始受理序号，因此离开
            // 常驻窗口的重复投递会被裁决而不是再送一次。索引行缺少摘要（迁移回填）或时间线已提交
            // 但索引无法证明正文的旧消息都按“不可验证”上报，让上层 fail-closed；查询失败同样上报，
            // 绝不在无法证明身份时把投递当成新消息受理。
            Some(Arc::new(move |thread_id: String, message_id: String| {
                let store = message_store.clone();
                Box::pin(async move {
                    let identity_error = |source: anyhow::Error| {
                        crate::thread_assembler::ThreadAssemblyError::Resource {
                            operation: "read durable message identity",
                            source: source.into_boxed_dyn_error(),
                        }
                    };
                    // 该身份查询是冷读路径：没有活跃 writer 时 `history` 只是一个不做 IO 的句柄，
                    // 不建库也不升级它；有活跃 writer 时它正是这个 Thread 的同一权威句柄，读会等
                    // 本句柄 writer 完成建表与 identity meta，因此不会读到半初始化库。这里刻意不
                    // 另开独立 HistoryStore，避免未启动的冷读绕过本句柄的初始化锁。
                    let history = store.history(&thread_id).await.map_err(identity_error)?;
                    if let Some(identity) =
                        history.message_identity(&message_id).await.map_err(identity_error)?
                    {
                        return Ok(Some(match identity.digest {
                            Some(digest) => {
                                crate::thread_assembler::observation::DurableMessageIdentity::Proven {
                                    sequence: identity.sequence,
                                    digest,
                                }
                            }
                            None => crate::thread_assembler::observation::DurableMessageIdentity::Unverifiable,
                        }));
                    }
                    // 时间线已经提交这条消息、但索引没有它的记录：升级前的历史无法证明正文，
                    // 必须 fail-closed，而不是重新投递成新消息。
                    let item = crate::studio::thread_projection::order::message_id(&message_id);
                    let committed = history
                        .existing_items([item])
                        .await
                        .map_err(identity_error)?;
                    Ok((!committed.is_empty()).then_some(
                        crate::thread_assembler::observation::DurableMessageIdentity::Unverifiable,
                    ))
                })
            })),
            move |id, thread| {
                // Cancellation is synchronous, so no new preparation can pass the gate.
                let gate = closing_factory.stop_tool_operation(&id);
                let rejected = rejected_tools.clone();
                Box::pin(async move {
                    let _guard = match gate { Some(gate) => Some(gate.lock_owned().await), None => None };
                    rejected.retry(Some(&thread)).await.map_err(|source| crate::thread_assembler::ThreadAssemblyError::Resource {
                        operation: "drain Thread tool candidates", source: source.into_boxed_dyn_error(),
                    })
                })
            },
            move |id| {
                let owner = synchronizing.clone();
                Box::pin(async move {
                    let owner = owner.upgrade().ok_or(crate::thread_assembler::ThreadAssemblyError::Closed)?;
                    ThreadObservations(owner).synchronize(Some(&id)).await.map_err(|source| {
                        crate::thread_assembler::ThreadAssemblyError::Resource {
                            operation: "acknowledge parent report handoff",
                            source: source.into_boxed_dyn_error(),
                        }
                    })
                })
            },
        )?;
        Ok(())
    }

    /// Releases the retained observation for a drained or evicted Thread.
    ///
    /// The observation worker owns a strong `ThreadHandle`; keeping its entry after the assembly
    /// registry released the owner would keep every session that was ever activated resident. The
    /// entry is removed once its final projection is durable, so a later re-activation installs a
    /// fresh observation instead of reusing the released handle.
    async fn drain(&self, id: &str) -> Result<()> {
        let observations = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .cloned()
            .unwrap_or_default();
        let feed = self.live_feed(id);
        for observation in &observations {
            anyhow::ensure!(
                observation.thread.snapshot().lifecycle == ThreadLifecycle::Closed,
                "cannot retire workers of an open Thread"
            );
            observation.join().await?;
            observation.state.channel.stop_and_join().await?;
        }
        let mut all = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(entries) = all.get_mut(id) {
            entries.retain(|entry| !observations.iter().any(|old| Arc::ptr_eq(entry, old)));
            if entries.is_empty() {
                all.remove(id);
            }
        }
        drop(all);
        let mut live = self
            .0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if live
            .get(id)
            .zip(feed.as_ref())
            .is_some_and(|(current, old)| Arc::ptr_eq(current, old))
        {
            live.remove(id);
        }
        Ok(())
    }

    fn observe(&self, id: String, thread: ThreadHandle) {
        let recovered_through = thread.snapshot().commit_sequence;
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
            progress,
            retry: Notify::new(),
            channel,
            #[cfg(test)]
            pending_hook: self.pending_hook(&id),
        });
        // Seed the feed with the newest typed storage state the coordinator already reports, so a
        // subscriber that opens before this owner's first pass mirrors a real fact instead of an
        // unset placeholder. The owner republishes its own derivation on the first pass.
        let initial_storage = self
            .0
            .projector
            .store
            .thread_persistence()
            .snapshot()
            .threads
            .iter()
            .find(|detail| detail.thread_id == id)
            .map(|detail| storage_state(&thread.snapshot(), detail));
        let feed = Arc::new(ThreadLiveFeed::new(initial_storage));
        self.0
            .live
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(id.clone(), feed.clone());
        let worker_state = state.clone();
        let projector = self.0.projector.clone();
        let worker_thread = thread.clone();
        let worker_id = id.clone();
        let task = tokio::spawn(async move {
            run(
                projector,
                worker_id,
                worker_thread,
                worker_state,
                recovered_through,
                feed,
            )
            .await;
        });
        let observation = Arc::new(Observation {
            thread,
            state,
            task: tokio::sync::Mutex::new(Some(task)),
        });
        let mut all = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let previous = all.entry(id).or_default();
        previous.retain(|entry| {
            let progress = entry.state.progress.borrow();
            !progress.finished || progress.error.is_some()
        });
        previous.push(observation);
    }

    async fn synchronize(&self, id: Option<&str>) -> Result<()> {
        self.0.projector.writer.retry_now();
        let observations: Vec<_> = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|(key, _)| id.is_none_or(|id| id == key.as_str()))
            .flat_map(|(id, entries)| entries.iter().map(|entry| (id.clone(), entry.clone())))
            .collect();
        for (id, observation) in observations {
            let target_snapshot = observation.thread.snapshot();
            // The explicit retry only wakes the worker: an unresolved error is reported as it
            // stands, and only the worker's own successful pass — which replaces the whole
            // progress value, error included — can settle the observation again.
            observation.state.retry.notify_one();
            let durable_through =
                await_settled_target(&id, observation.as_ref(), &target_snapshot).await?;
            // A settled observation is also durable. Observation no longer flushes history per batch,
            // so this barrier is what keeps "the observer applied commit N" meaning "history holds
            // commit N": cold reads (an unloaded child's terminal repair, a restored Turn) read a
            // Turn's items straight from history after this. The wait is for the handoff ticket the
            // projection had reached when it applied `target` — every commit up to `target` it owns —
            // so it neither waits on the owner's command queue nor on a later, unprojected commit, and
            // it never asks for a watermark a channel created by a re-activation cannot move.
            await_history_durable(&observation.state.channel, &id, durable_through)
                .await
                .with_context(|| format!("Thread {id} product observation barrier"))?;
        }
        // The observation worker no longer waits on disk for each projected batch, so the explicit
        // sync barrier carries the durability: every product write admitted up to the watermark this
        // barrier just waited for is drained before the caller observes a settled terminal state.
        // The target is fixed at call time, so this never waits for unrelated later writes.
        let target = self.0.projector.writer.admitted_ticket();
        self.0.projector.writer.flush_through(target).await?;
        Ok(())
    }

    /// Explicit parent continuation repairs terminal notifications even for unloaded children.
    /// This prepares persisted schemas (including saved-representation versions) and reads
    /// checkpoints plus durable history; no child owner, model or workspace is opened.
    pub(super) async fn reconcile_children(&self, parent: &str) -> Result<()> {
        let services = &self.0.projector;
        for child in services.store.list_threads_for_root(parent).await? {
            if child.parent_thread_id.as_deref() != Some(parent) {
                continue;
            }
            if services.threads.thread(&child.id).is_some() {
                self.synchronize(Some(&child.id)).await?;
                continue;
            }
            let child = pl_protocol::Thread::from(child);
            // Parent recovery explicitly prepares its cold children's storage before projecting
            // their facts. It never activates a child, rebuilds its workspace or asks a model.
            let Some(checkpoint) =
                crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
                    &services.store,
                    &child,
                )
                .await?
            else {
                continue;
            };
            // A cold child's interruption is a fact the list must publish: a restart otherwise loses
            // "stopped, waiting for the main agent" for every member that is not loaded again. This
            // reads only the saved checkpoint — no activation, no workspace, no model request.
            directory::publish_cold_scheduling_state(services, &child, &checkpoint.state).await?;
            if let Some(turn) = checkpoint
                .state
                .turns
                .iter()
                .rev()
                .find(|turn| turn.state != pl_core::thread::TurnState::Running)
            {
                // An unloaded child has no resident projection, so this repair reads the Turn's
                // items from durable history: it is the cold path, and the checkpoint cannot carry
                // the finished Turn's body.
                let history = services.store.history(&child.id).await?;
                let terminal_sequence = history
                    .terminal_report_sequence(&turn.turn_id)
                    .await?
                    .ok_or_else(|| {
                        anyhow::anyhow!("terminal report has no committed effect identity")
                    })?;
                if let Some(message) = history.parent_report(terminal_sequence).await? {
                    let _delivery = services
                        .threads
                        .notify_parent(parent, message, false)
                        .await?;
                }
            }
        }
        Ok(())
    }

    pub(super) async fn finish(&self) -> Result<()> {
        self.synchronize(None).await?;
        let observations: Vec<_> = self
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .flatten()
            .cloned()
            .collect();
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

impl StudioRuntime {
    /// Waits for product directories and billing to reach the current committed Thread watermark.
    /// Reattempts a previously failed projection without invoking models or tools.
    pub async fn synchronize_thread_observation(&self, thread_id: &str) -> Result<()> {
        self.thread_observations.synchronize(Some(thread_id)).await
    }
}

/// The single realtime projection owner of one Thread.
///
/// It lives in the Thread's observation worker, so a GUI opening and closing never changes who
/// projects or who publishes content: every committed effect is projected exactly once into the
/// shared chat session, and its typed changes are broadcast to whichever subscribers exist. The same
/// batch is handed to the Thread's reliable admission channel, so the history writer commits the
/// content this owner published instead of projecting the effect a second time.
struct LiveOwner {
    config: crate::config::ConfigRuntime,
    qualification_revision: u64,
    projection: LiveProjection,
    /// The Thread's only activity projection: the same owner derives it from the snapshot it just
    /// published, so activity never becomes a second fact source and never reads SQL.
    activity: crate::studio::thread_projection::ActivityProjection,
    /// Last activity already broadcast, so an unchanged projection does not produce a frame.
    activity_published: Option<pl_protocol::ThreadActivity>,
    runtime_published: Option<pl_protocol::ThreadRuntimeSnapshot>,
    /// Last typed storage state this owner published to its feed.
    ///
    /// The owner derives it from the owner snapshot plus the coordinator's typed watch, so a
    /// subscriber mirrors the value instead of recomputing it from its own copies. It is kept as one
    /// value so a change of fault kind, generation, watermark or phase is all one comparison.
    storage_published: Option<pl_protocol::ThreadStorageState>,
    /// The Thread's reliable admission channel, shared with the history writer.
    channel: Arc<HistoryChannel>,
    chat: Session,
    thread: pl_protocol::Thread,
    usage: UsageSummary,
    feed: Arc<ThreadLiveFeed>,
    /// The one committed batch this owner prepared but has not handed to the writer yet; see
    /// [`PendingHandoff`].
    pending: Option<PendingHandoff>,
    #[cfg(test)]
    pending_hook: PendingHookSlot,
}

/// Which path a retained handoff batch came from; a retry never re-decides it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum HandoffMode {
    /// The realtime path: accounting folded and the projection advanced with the delivery decision
    /// of the moment it was projected.
    Live,
    /// A commit the owner already held before this projection existed: folded for durability only,
    /// it never gains realtime publication rights.
    Behind,
}

/// One committed batch this projection owner prepared but has not handed to the writer yet.
///
/// This is not a second ledger: it is the single in-flight handoff of the owner's serial pass, at
/// most one batch, holding the very `ThreadWrite` the reliable queue admitted and the prepared
/// content the writer will commit. Retaining it closes the window between the report preparation
/// and the handoff — a failure, a cancelled wait or an explicit retry re-enters this same batch
/// instead of projecting the same commit a second time and bumping its content revisions.
struct PendingHandoff {
    write: Arc<ThreadWrite>,
    prepared: Arc<crate::studio::thread_projection::PreparedEffect>,
    /// The delivery changes the live path decided when it projected the commit; `None` on the
    /// behind path and when the projection produced no frame.
    changes: Option<Vec<LiveEvent>>,
    mode: HandoffMode,
}

impl PendingHandoff {
    /// Retained size of the prepared content while its owner still owes the handoff.
    ///
    /// The same measurement the reliable channel charges when it takes the batch over, so the
    /// Thread's existing budget covers the batch under exactly one owner at a time — never twice
    /// outside the one synchronous handoff boundary, and never unbounded while a report awaits.
    fn retained_bytes(&self) -> u64 {
        // The prepared batch is measured by its owning projection (`PreparedEffect::retained_bytes`,
        // the one implementation the writer shares); the delivery changes are this owner's own
        // residents and are charged element by element.
        let mut bytes = self.prepared.retained_bytes();
        if let Some(changes) = self.changes.as_ref() {
            for event in changes {
                bytes = bytes.saturating_add(event.retained_bytes());
            }
            // The Vec's spare capacity is resident too: every used element's shell is already part
            // of its own estimate, so only the unused slots add their element size here.
            let spare = changes.capacity() - changes.len();
            bytes = bytes.saturating_add(
                u64::try_from(spare)
                    .unwrap_or(u64::MAX)
                    .saturating_mul(std::mem::size_of::<LiveEvent>() as u64),
            );
        }
        bytes
    }

    /// Attaches the prepared batch to the reliable queue and publishes the accepted facts.
    ///
    /// # Errors
    /// The channel refused the handoff — the sequence is already durable or is not an admitted
    /// commit of this channel. The batch stays fully retained with its identity, so the refusal
    /// reaches the caller instead of a silent loss or a re-projection.
    fn hand_over(
        &self,
        channel: &HistoryChannel,
        feed: &ThreadLiveFeed,
    ) -> Result<Option<pl_core::thread::inbox::ThreadMessage>> {
        let sequence = self.prepared.sequence;
        if !channel.prepare(Arc::clone(&self.prepared)) {
            anyhow::bail!("reliable channel refused the handoff of live Thread commit {sequence}");
        }
        // Only the prepared content is authoritative for the terminal fact — never the optional
        // delivery changes, which a zero-subscriber commit may not carry at all.
        if let Some(turn) = crate::studio::thread_projection::prepared_terminal_turn(&self.prepared)
        {
            feed.publish_last_turn(Arc::new(turn));
        }
        if self.mode == HandoffMode::Live
            && let Some(changes) = self.changes.as_ref()
        {
            feed.publish(|| ThreadLiveEvent::Committed {
                sequence,
                changes: changes.clone(),
            });
        }
        Ok(self.prepared.parent_report.clone())
    }
}

/// The pending-boundary phase hook a fault test may install on exactly one owner; production code
/// always passes the empty slot and no test-less build contains the control type.
#[cfg(test)]
type PendingHookSlot = Option<Arc<PendingPhaseHook>>;

/// Test-only, per-owner one-shot control at the pending→report boundary of one `LiveOwner`.
///
/// `entered` fires for every batch that reaches the boundary (event semantics, so a retry of the
/// same sequence is visible too); `control` parks the owner until the owning test releases it once
/// with `Ok(())` or a failure message, after which the hook re-arms itself for the next entry. It
/// only controls timing and injects one error; the real projection, report preparation, writer and
/// synchronize keep running.
#[cfg(test)]
struct PendingPhaseHook {
    entered: tokio::sync::mpsc::UnboundedSender<u64>,
    control: watch::Sender<Option<Result<(), String>>>,
}

#[cfg(test)]
impl PendingPhaseHook {
    /// Returns the hook plus the test-owned entry stream and release control.
    fn new() -> (
        Arc<Self>,
        tokio::sync::mpsc::UnboundedReceiver<u64>,
        watch::Sender<Option<Result<(), String>>>,
    ) {
        let (entered, entered_rx) = tokio::sync::mpsc::unbounded_channel();
        // The sender is the release control: cloning it back to the test keeps
        // one authoritative channel, so a parked owner and its test observe the
        // same release sequence instead of two disconnected watch ends.
        let (control, _receiver) = watch::channel(None);
        (
            Arc::new(Self {
                entered,
                control: control.clone(),
            }),
            entered_rx,
            control,
        )
    }
}

impl LiveOwner {
    async fn open(
        projector: &ObservationServices,
        handle: &ThreadHandle,
        snapshot: &ThreadSnapshot,
        thread: pl_protocol::Thread,
        feed: Arc<ThreadLiveFeed>,
        channel: Arc<HistoryChannel>,
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
        #[cfg(test)] pending_hook: PendingHookSlot,
    ) -> Result<Self> {
        let id = thread.id.as_str();
        let chat = projector.store.chat_session(id).await?;
        let usage = live_usage(projector, id, snapshot);
        // The one cold read of a projection: the durable facts of work that already started before
        // this owner existed. Everything the commit and preview paths resolve afterwards comes from
        // these tables, so a re-activated Thread never waits on a history reader mid-Turn.
        let mut projection = LiveProjection::new();
        let retained = handle.effects().await?;
        let (seed_items, hidden) =
            cold_seed(&projector.store, &thread, snapshot, &channel, &retained).await?;
        projection.seed(seed_items, hidden);
        // Seed the activity projection from the very snapshot this owner was installed on, so a
        // subscriber that opens mid-Turn immediately sees the authoritative current activity.
        let mut activity = crate::studio::thread_projection::ActivityProjection::default();
        let activity_published = activity.observe(id, snapshot);
        // The owner is the single source of the typed storage state: publish the value it was
        // installed with, so a subscriber that opened before this first pass sees the authoritative
        // fact instead of an unset placeholder.
        let storage_published = persistence.map(|detail| storage_state(snapshot, detail));
        // Seed the runtime baseline from the same snapshot and cumulative usage that the first
        // stream pass will project. This prevents owner activation itself from emitting a duplicate
        // runtime frame; subsequent frames still advance only when the typed projection changes.
        let mut runtime = crate::studio::thread_projection::project_runtime(
            id,
            snapshot,
            thread.updated_at,
            &usage,
        )?;
        let (config, catalog) = projector.config.read_with_catalog()?;
        crate::studio::model_route::annotate_availability(&mut runtime, &thread, &config.config)?;
        let runtime_published = Some(runtime);
        feed.publish_storage(storage_published.clone());
        let owner = Self {
            config: projector.config.clone(),
            qualification_revision: catalog.revision,
            projection,
            activity,
            activity_published,
            runtime_published,
            storage_published,
            channel,
            chat,
            thread,
            usage,
            feed,
            pending: None,
            #[cfg(test)]
            pending_hook,
        };
        // The seeded facts are already resident, so the Thread's budget covers them from the moment
        // the owner is installed instead of only after its first commit.
        owner.publish_retained();
        // A Thread re-activated after its last Turn finished has no live frame left for that fact:
        // the authoritative snapshot carries only the active Turn and `turnCompleted` was broadcast
        // once, to subscribers that may be long gone. This is the very cold-read path the owner is
        // installed on, so the newest terminal Turn is read here once — bounded, without item bodies
        // — and seeded into the same retained fact the live projection publishes. The live path can
        // then only move it forward, so a seed can never hide a later finished Turn, and a late
        // duplicate of a Turn already retained is dropped by the same identity/revision guard.
        if let Some(turn) = projector
            .store
            .history(&owner.thread.id)
            .await?
            .newest_terminal_turn()
            .await?
        {
            owner.feed.publish_last_turn(Arc::new(turn));
        }
        Ok(owner)
    }

    /// Publishes how much this projection currently retains in its own tables.
    ///
    /// The projection owns the retained bodies and the Turn report accumulator, and both outlive
    /// the batch the writer already committed. The reliable channel's budget is what pauses new
    /// model/tool admission at a safe gap, so it has to see this number; nothing here waits for a
    /// GUI, because the owner publishes whether or not anyone is subscribed.
    fn publish_retained(&self) {
        // The activity summary and its bounded resident detail are resident facts of the same owner,
        // so they belong to the same Thread budget instead of living outside it.
        let mut bytes = self
            .projection
            .retained_bytes()
            .saturating_add(self.activity.retained_bytes());
        // The pending handoff batch is real resident product content this owner still holds. It is
        // charged here — under the same Thread budget — until the reliable channel takes it over;
        // the queue's own `ThreadWrite` Arc is the very object admission already charged, so only
        // the prepared content is added and no body is counted twice in steady state.
        if let Some(pending) = self.pending.as_ref() {
            bytes = bytes.saturating_add(pending.retained_bytes());
        }
        self.channel.set_projection_bytes(bytes);
    }

    /// Projects one admitted write into the session, broadcasts its live changes and hands the very
    /// same immutable batch to the Thread's reliable save channel.
    ///
    /// The batch is published before it is handed over, so the writer can only ever confirm a body
    /// the shared window already holds: there is no save-before-publish interleaving to lose.
    ///
    /// A reliable-output repair can name an identity the bounded window already released. This owner is
    /// still the single fact source for the canonical item and its content version, so it reads that
    /// already-committed body back once here and folds it in before projecting; the ordinary path reads
    /// nothing, and the writer never invents a version or re-projects a written effect.
    async fn advance(
        &mut self,
        services: &ObservationServices,
        thread_id: &str,
        write: &Arc<ThreadWrite>,
    ) -> Result<Option<pl_core::thread::inbox::ThreadMessage>> {
        self.seed_durable_targets(services, thread_id, write)
            .await?;
        self.project_write(services, write).await
    }

    /// Reads the identities one effect needs but this projection holds no canonical body for.
    ///
    /// Two effects reference an already-committed body the bounded window may have released: a
    /// reliable-output repair names a committed result, and a user-input interaction names the call
    /// that raised it — a call whose Turn is already finished, so after a restart the projection never
    /// saw it at all. Both are read back **by identity only** and handed to the projection as facts,
    /// so the projection still consumes facts and never performs IO. The ordinary path reads nothing,
    /// and a missing or invalid durable body fails here instead of being skipped.
    async fn seed_durable_targets(
        &mut self,
        services: &ObservationServices,
        thread_id: &str,
        write: &ThreadWrite,
    ) -> Result<()> {
        if write.effect.delivery_repairs.is_empty() && write.effect.interactions.is_empty() {
            return Ok(());
        }
        let history = services.store.history(thread_id).await?;
        crate::studio::thread_projection::seed_repaired_targets(
            &mut self.projection,
            &history,
            &write.effect,
        )
        .await
        .map_err(|error| anyhow::anyhow!("live Thread repair seed failed: {error}"))?;
        crate::studio::thread_projection::seed_interaction_targets(
            &mut self.projection,
            thread_id,
            &history,
            &write.effect,
        )
        .await
        .map_err(|error| anyhow::anyhow!("live Thread user-input seed failed: {error}"))?;
        Ok(())
    }

    /// Folds one admitted write into the shared session and the reliable save channel.
    async fn project_write(
        &mut self,
        services: &ObservationServices,
        write: &Arc<ThreadWrite>,
    ) -> Result<Option<pl_core::thread::inbox::ThreadMessage>> {
        let effect = &write.effect;
        let deliver = self.feed.has_subscribers();
        let projected = (|| {
            crate::studio::thread_projection::fold_effect_accounting(&mut self.usage, effect)?;
            self.projection.advance(
                &self.chat,
                &self.thread,
                effect,
                &write.checkpoint.state,
                deliver,
            )
        })();
        let (changes, prepared) = match projected {
            Ok(projected) => projected,
            Err(error) => {
                // The writer saves exactly what this owner projects, so a projection this owner cannot
                // complete is a fact that cannot be handed over or saved. Report it so the durable
                // barrier fails closed with the real reason instead of waiting forever.
                self.channel.fail_projection(
                    effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        // The folded commit is already resident in the shared session, so this owner retains the
        // whole handoff — the original write, the prepared batch, the delivery decision it made and
        // its mode — before the first await of the parent-report preparation. A failure, a
        // cancellation or a retry inside that window re-enters the same retained batch instead of
        // projecting the commit a second time, which would bump content revisions for the same fact.
        if let Some(pending) = self.pending.as_ref() {
            anyhow::bail!(
                "live projection still owes the handoff of commit {} before projecting commit {}",
                pending.write.effect.sequence,
                effect.sequence
            );
        }
        self.pending = Some(PendingHandoff {
            write: Arc::clone(write),
            prepared,
            changes,
            mode: HandoffMode::Live,
        });
        self.publish_retained();
        self.finish_pending(services).await
    }

    /// Prepares the retained batch's original parent report, then hands the batch over.
    async fn finish_pending(
        &mut self,
        services: &ObservationServices,
    ) -> Result<Option<pl_core::thread::inbox::ThreadMessage>> {
        // Test-only fault boundary: a fault test that installed a hook parks the real batch right
        // after its retention and before the report preparation, and may fail it once. Production
        // builds (and owners without a hook) pass straight through.
        #[cfg(test)]
        if let Some((hook, sequence)) = self.pending_hook.as_ref().zip(
            self.pending
                .as_ref()
                .map(|pending| pending.write.effect.sequence),
        ) {
            let _ = hook.entered.send(sequence);
            let mut release = hook.control.subscribe();
            loop {
                // The watch guard is a read lock on the same channel the arms
                // below write through `send_replace`; cloning the decision in
                // its own scope drops the guard before the match, so a parked
                // owner never synchronously deadlocks its own release.
                let decision = {
                    let guard = release.borrow_and_update();
                    guard.clone()
                };
                match decision {
                    Some(Ok(())) => {
                        hook.control.send_replace(None);
                        break;
                    }
                    Some(Err(message)) => {
                        hook.control.send_replace(None);
                        return Err(anyhow::anyhow!(message));
                    }
                    None => {}
                }
                if release.changed().await.is_err() {
                    break;
                }
            }
        }
        self.prepare_parent_report(services).await?;
        self.handover_pending()
    }

    /// Hands the retained batch to the reliable channel, or keeps it fully retained.
    ///
    /// Nothing in here awaits: the channel's decision, the terminal and realtime publications, the
    /// slot release and the budget update form one boundary, so the batch is either still this
    /// owner's responsibility with an explicit refusal, or handed over with its facts published
    /// exactly once. `prepare` accepting is the explicit handoff, not a durability confirmation —
    /// durability remains the writer's own watermark.
    fn handover_pending(&mut self) -> Result<Option<pl_core::thread::inbox::ThreadMessage>> {
        let Some(pending) = self.pending.as_ref() else {
            return Ok(None);
        };
        let report = pending.hand_over(&self.channel, &self.feed)?;
        self.pending = None;
        self.publish_retained();
        Ok(report)
    }

    /// Freezes the original terminal report of the retained batch into its prepared content.
    ///
    /// Every await in here belongs to the pending slot: the slot keeps holding the original write
    /// and prepared content, a local clone carries the waits, and only a fully successful build is
    /// written back. A failure or a cancelled wait leaves the slot exactly as it was, so the next
    /// pass reuses the same batch instead of rebuilding the report from a later checkpoint.
    async fn prepare_parent_report(&mut self, services: &ObservationServices) -> Result<()> {
        let (write, prepared) = match self.pending.as_ref() {
            Some(pending) => (Arc::clone(&pending.write), Arc::clone(&pending.prepared)),
            None => return Ok(()),
        };
        let Some(turn) = write.effect.turn.as_ref().filter(|turn| {
            turn.state != pl_core::thread::TurnState::Running
                && self.thread.parent_thread_id.is_some()
        }) else {
            return Ok(());
        };
        // The retry of a batch whose report already exists reuses the original copy: the report is
        // the frozen receipt of this very commit, never rebuilt from a DTO or a newer checkpoint.
        if prepared.parent_report.is_some() {
            return Ok(());
        }
        let turn = turn.clone();
        let result = if let Some(result) = self.projection.turn_result(&turn.turn_id) {
            result.clone()
        } else {
            // The durable fence is the ticket of batches this owner already handed over — never
            // the commit this slot still holds, which would wait for itself.
            await_history_durable(
                &self.channel,
                &self.thread.id,
                self.channel.handoff_ticket(),
            )
            .await?;
            let history = services.store.history(&self.thread.id).await?;
            let mut items = history
                .items_for_turn(&turn.turn_id)
                .await?
                .into_iter()
                .map(|item| (item.id.clone(), item))
                .collect::<std::collections::BTreeMap<_, _>>();
            for item in prepared
                .items
                .iter()
                .filter(|item| item.turn_id == turn.turn_id)
            {
                items.insert(item.id.clone(), item.clone());
            }
            let mut items = items.into_values().collect::<Vec<_>>();
            items.sort_by_key(|item| item.ordinal);
            crate::studio::thread_projection::TurnResult::from_items(&items)
        };
        // The report is built from read-only local clones while the slot keeps the only prepared
        // batch; only once the complete message exists are the clones dropped, so the write-back
        // below takes the slot's single strong reference and never copies the whole batch.
        let report = reports::terminal_message(
            &self.thread,
            &write.checkpoint.state,
            &turn,
            write.effect.sequence,
            &result,
        )?;
        drop(prepared);
        let shared = {
            let Some(pending) = self.pending.as_mut() else {
                unreachable!(
                    "the pending handoff slot cannot vanish while its owner prepares its report"
                );
            };
            match Arc::get_mut(&mut pending.prepared) {
                Some(batch) => {
                    batch.parent_report = Some(report);
                    None
                }
                // Before the handoff only this owner holds the batch; a second strong reference
                // is an internal invariant violation, reported while the slot stays retained.
                None => Some(pending.write.effect.sequence),
            }
        };
        if let Some(sequence) = shared {
            anyhow::bail!(
                "live Thread pending batch of commit {sequence} is unexpectedly shared before its handoff"
            );
        }
        // The report is now part of the retained batch: the Thread budget sees it before any
        // handoff attempt, and a refused handoff keeps the batch together with its report.
        self.publish_retained();
        Ok(())
    }

    /// Hands one admitted effect this owner installed *behind* to the reliable save channel.
    ///
    /// The Thread's initialization commits before the assembler publishes the observation, so those
    /// effects are already part of the snapshot this projection was seeded from and are never
    /// replayed as live frames. The history writer still owes them a durable row, so the same single
    /// projection folds their content into memory here — once, and never the writer projecting the
    /// effect itself.
    async fn prepare_behind(
        &mut self,
        services: &ObservationServices,
        thread_id: &str,
        write: &Arc<ThreadWrite>,
    ) -> Result<()> {
        self.seed_durable_targets(services, thread_id, write)
            .await?;
        let projected = self.projection.project_committed(
            &self.chat,
            &self.thread,
            &write.effect,
            &write.checkpoint.state,
        );
        let prepared = match projected {
            Ok(prepared) => prepared,
            Err(error) => {
                self.channel.fail_projection(
                    write.effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        // The behind batch is retained the same way before its report await; its mode keeps it from
        // ever gaining realtime publication rights on a retry.
        if let Some(pending) = self.pending.as_ref() {
            anyhow::bail!(
                "live projection still owes the handoff of commit {} before taking over commit {}",
                pending.write.effect.sequence,
                write.effect.sequence
            );
        }
        self.pending = Some(PendingHandoff {
            write: Arc::clone(write),
            prepared,
            changes: None,
            mode: HandoffMode::Behind,
        });
        self.publish_retained();
        self.finish_pending(services).await?;
        Ok(())
    }

    /// Projects the uncommitted streaming preview of the current owner snapshot.
    ///
    /// The preview is written into the shared session — the one content window — and emits no
    /// content frame; current activity and runtime facts are published separately.
    async fn stream(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        self.projection
            .stream(&self.chat, &self.thread, snapshot, snapshot.commit_sequence)
            .await
            .map_err(|error| anyhow::anyhow!("live Thread preview failed: {error}"))?;
        self.observe_runtime(snapshot)?;
        self.observe_activity(snapshot);
        self.publish_retained();
        Ok(())
    }

    /// Execution residency is live-only; next-admission availability also consumes current config.
    /// Derive runtime from the latest owner snapshot after folding all admitted usage,
    /// never from an effect's storage checkpoint. Stable timestamps allow deduplication.
    fn observe_runtime(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let at = self
            .runtime_published
            .as_ref()
            .map_or(self.thread.updated_at, |runtime| runtime.updated_at);
        let mut runtime = crate::studio::thread_projection::project_runtime(
            &self.thread.id,
            snapshot,
            at,
            &self.usage,
        )?;
        let same_identity = match (
            self.runtime_published
                .as_ref()
                .and_then(|runtime| runtime.model_route.as_ref()),
            runtime.model_route.as_ref(),
        ) {
            (Some(previous), Some(current)) => {
                previous.account_id == current.account_id
                    && previous.model_id == current.model_id
                    && previous.effort == current.effort
                    && previous.revision == current.revision
            }
            (None, None) => true,
            _ => false,
        };
        if self.config.model_catalog_revision()? == self.qualification_revision && same_identity {
            if let (Some(previous), Some(current)) = (
                self.runtime_published
                    .as_ref()
                    .and_then(|runtime| runtime.model_route.as_ref()),
                runtime.model_route.as_mut(),
            ) {
                current.available = previous.available;
                current.unavailable_reason = previous.unavailable_reason.clone();
            }
        } else {
            let (config, catalog) = self.config.read_with_catalog()?;
            crate::studio::model_route::annotate_availability(
                &mut runtime,
                &self.thread,
                &config.config,
            )?;
            self.qualification_revision = catalog.revision;
        }
        if self.runtime_published.as_ref() == Some(&runtime) {
            return Ok(());
        }
        runtime.updated_at = crate::studio::unix_seconds();
        runtime.usage.updated_at = runtime.updated_at;
        let runtime = self.runtime_published.insert(runtime);
        self.feed.publish(|| ThreadLiveEvent::Runtime {
            runtime: Arc::new(runtime.clone()),
        });
        Ok(())
    }

    /// Re-derives the Thread's current activity from the snapshot this owner just published.
    ///
    /// The activity is an independent projection of the same facts: a phase change, a new foreground
    /// tool or an interaction change reaches it through the owner snapshot, never through `effect`.
    /// Only a real change is broadcast, so a streaming body update does not cost a second status
    /// frame and no subscriber ever has to project the activity itself.
    fn observe_activity(&mut self, snapshot: &ThreadSnapshot) {
        let activity = self.activity.observe(&self.thread.id, snapshot);
        if activity == self.activity_published {
            return;
        }
        self.activity_published = activity;
        // One shared handle per published change: every subscriber clones that handle, never the body.
        self.feed.publish(|| ThreadLiveEvent::Activity {
            activity: self.activity_published.clone().map(Arc::new),
        });
    }

    /// Republishes the typed storage state this owner derives, only when it really changed.
    ///
    /// A storage pause, a pressure warning, the explicit-resume latch or a durable receipt change
    /// nothing about the content or the activity, so they need their own fact: the owner watches the
    /// coordinator's typed status directly and republishes here even when no other frame arrived, so
    /// a parked subscriber learns about a save failure without waiting for an unrelated commit.
    fn observe_storage(
        &mut self,
        snapshot: &ThreadSnapshot,
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
    ) {
        let storage = persistence.map(|detail| storage_state(snapshot, detail));
        if storage == self.storage_published {
            return;
        }
        self.storage_published = storage.clone();
        self.feed.publish_storage(storage);
    }
}

impl Drop for LiveOwner {
    /// Releases this owner's share of the Thread's budget when the observation ends.
    ///
    /// The retained bodies die with the owner, so leaving the gauge where it was would keep a
    /// released Thread reading as pending work forever. A re-activated Thread installs a new owner
    /// that republishes its own tables on its first step.
    fn drop(&mut self) {
        self.channel.set_projection_bytes(0);
    }
}

/// The one cold read of a live projection: the durable facts of the work it is installed onto.
///
/// The current owner snapshot is deliberately compact — it no longer holds the process bodies a
/// running Turn committed earlier — so a projection installed mid-Turn would be unable to resolve an
/// identity a later effect still references. Reading the running and newest Turn's committed items
/// once, together with the hidden dispositions of the inputs still in play, closes that gap without
/// putting a history read on the commit or preview path.
async fn cold_seed(
    store: &StudioStore,
    thread: &pl_protocol::Thread,
    snapshot: &ThreadSnapshot,
    channel: &HistoryChannel,
    retained: &[Arc<pl_core::thread::ThreadEffectBatch>],
) -> Result<(
    Vec<pl_protocol::ThreadItem>,
    std::collections::BTreeSet<String>,
)> {
    use std::collections::BTreeSet;

    // Capture before reading history: core may already have pruned the terminal Turn from
    // its current snapshot, but the reliable queue still owns the recovery commit's references.
    let pending = channel.unprojected_writes();
    let mut turn_ids = BTreeSet::new();
    let mut input_ids = BTreeSet::new();
    let mut item_ids = BTreeSet::new();
    for state in
        std::iter::once(snapshot).chain(pending.iter().map(|write| &write.checkpoint.state))
    {
        for turn in state.turns.iter() {
            turn_ids.insert(turn.turn_id.clone());
            input_ids.extend(turn.input_id.iter().cloned());
        }
        input_ids.extend(state.inputs.iter().map(|record| record.input.id.clone()));
        item_ids.extend(
            state.inbox.iter().map(|record| {
                crate::studio::thread_projection::order::message_id(&record.message.id)
            }),
        );
    }
    for write in &pending {
        // Reuse the projection's identity enumeration, including tool results whose attempt
        // already left the checkpoint. Do not maintain a second interpretation of effect kinds.
        let referenced = crate::studio::thread_projection::project_effect_items(
            thread,
            &write.checkpoint.state,
            &write.effect,
            &BTreeMap::new(),
            &BTreeMap::new(),
            &BTreeSet::new(),
        )?;
        for item in referenced.items {
            if !item.turn_id.is_empty() {
                turn_ids.insert(item.turn_id.clone());
            }
            item_ids.insert(item.id);
        }
        input_ids.extend(referenced.unresolved_inputs);
        item_ids.extend(referenced.unresolved_calls);
    }
    // Storage admission may lag behind core publication. These immutable effects remain in core
    // until durable acknowledgement, including recovery facts absent from both the pruned snapshot
    // and the admission queue. Enumerate their references before the first history read.
    for effect in retained {
        if let Some(turn) = &effect.turn {
            turn_ids.insert(turn.turn_id.clone());
            input_ids.extend(turn.input_id.iter().cloned());
        }
        if let Some(attempt) = &effect.attempt {
            turn_ids.insert(attempt.turn_id.clone());
        }
        for change in effect.inputs.iter() {
            use pl_core::thread::input::InputChange;
            input_ids.insert(match change {
                InputChange::Accepted(record) => record.input.id.clone(),
                InputChange::Transition { id, .. } => id.clone(),
            });
        }
        for task in effect.tasks.iter() {
            turn_ids.insert(task.turn_id.clone());
        }
        item_ids.extend(
            effect
                .tasks
                .iter()
                .map(|record| &record.call_id)
                .chain(effect.permissions.iter().map(|record| &record.call_id))
                .chain(effect.deliveries.iter().map(|record| &record.call_id))
                .chain(effect.delivery_repairs.iter().map(|record| &record.call_id))
                .map(|id| crate::studio::thread_projection::order::tool_id(id)),
        );
        item_ids.extend(
            effect.inbox.iter().map(|record| {
                crate::studio::thread_projection::order::message_id(&record.message.id)
            }),
        );
    }
    item_ids.extend(input_ids.iter().cloned());
    if turn_ids.is_empty() && item_ids.is_empty() {
        return Ok((Vec::new(), BTreeSet::new()));
    }
    let history = store.history(&thread.id).await?;
    history.prepare_activation().await?;
    let mut items = history.existing_items(item_ids).await?;
    turn_ids.extend(
        items
            .values()
            .filter(|item| !item.turn_id.is_empty())
            .map(|item| item.turn_id.clone()),
    );
    for turn_id in turn_ids {
        for item in history.items_for_turn(&turn_id).await? {
            items.insert(item.id.clone(), item);
        }
    }
    let hidden = history.hidden_input_identities(input_ids).await?;
    Ok((items.into_values().collect(), hidden))
}

/// Cumulative usage the live projection folds further effects onto.
///
/// The history writer's reported summary is the value a hot increment, a reconnect and a cold
/// restore agree on; a checkpoint that was loaded before any report seeds the same value.
fn live_usage(
    projector: &ObservationServices,
    id: &str,
    snapshot: &ThreadSnapshot,
) -> UsageSummary {
    let coordinator = projector.store.thread_persistence();
    match coordinator.usage(id) {
        Some(usage) => usage,
        None => {
            coordinator.seed_usage(id, snapshot.usage_summary.clone());
            snapshot.usage_summary.clone()
        }
    }
}

async fn run(
    projector: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    recovered_through: u64,
    feed: Arc<ThreadLiveFeed>,
) {
    use futures::FutureExt;
    let mut updates = thread.subscribe();
    // The reliable handoff can gain a commit this projection must take over without any new owner
    // snapshot: an admission that storage pressure deferred lands after the observation was
    // installed, so its fact is older than this projection's seed and is never replayed as a live
    // frame. The channel's own status is the signal for it, and it is what makes "the writer is
    // waiting for a handoff" reach the only task that can hand one over.
    let mut handoff = state.channel.subscribe();
    // The coordinator's typed persistence watch is a first-class wake source: a save failure can
    // change with no owner frame and no handoff, so without this arm the owner would only publish
    // the fault when something unrelated happened to arrive.
    let mut persistence = projector.store.thread_persistence().subscribe();
    let mut current = thread.snapshot();
    let mut worker = ProjectionWorker {
        services: projector,
        id,
        thread,
        state,
        recovered_through,
        feed,
        live: None,
    };
    // Product facts are projected once per committed revision; the live projection additionally
    // follows every owner snapshot so streaming previews reach the same single publisher.
    let mut projected = None;
    loop {
        let issue_id = format!("tool-cleanup:{}", worker.id);
        let issue = (!current.tool_cleanup.failures.is_empty()).then(|| {
            crate::studio::StudioRecoveryIssue {
                id: issue_id.clone(),
                scope: crate::studio::StudioRecoveryIssueScope::Thread,
                category: crate::studio::StudioRecoveryIssueCategory::ToolCatalog,
                impact: crate::studio::StudioRecoveryImpact::Advisory,
                action: crate::studio::StudioRecoveryIssueAction::Retry,
                project_id: None,
                thread_id: Some(worker.id.clone()),
                worktree: None,
                message: current
                    .tool_cleanup
                    .failures
                    .iter()
                    .map(|failure| format!("{}: {}", failure.tool_id, failure.error))
                    .collect::<Vec<_>>()
                    .join("; "),
            }
        });
        worker.services.recovery.update_if_current(
            &issue_id,
            issue,
            || {
                worker
                    .services
                    .threads
                    .observed_threads()
                    .iter()
                    .any(|(id, thread)| id == &worker.id && thread.same_instance(&worker.thread))
            },
            |issues| {
                worker.services.events.emit_recovery_state(issues);
            },
        );
        let products = projected != Some((current.commit_sequence, current.lifecycle));
        // Read the coordinator's newest typed facts before publishing: a storage change is a fact
        // this pass has to carry, exactly like a commit or a preview it also projects.
        let detail = persistence
            .borrow_and_update()
            .threads
            .iter()
            .find(|detail| detail.thread_id == worker.id)
            .cloned();
        // The projection stays isolated behind `catch_unwind`, so a panicking projection is
        // still reported as an error instead of taking down the observation worker.
        let result =
            std::panic::AssertUnwindSafe(worker.project(&current, products, detail.as_ref()))
                .catch_unwind()
                .await
                .unwrap_or_else(|_| Err(anyhow::anyhow!("Thread product projection panicked")));
        match result {
            Ok(()) => {
                if products {
                    projected = Some((current.commit_sequence, current.lifecycle));
                }
                let finished = current.lifecycle == ThreadLifecycle::Closed;
                worker.state.progress.send_replace(Progress {
                    initialized: true,
                    applied: current.commit_sequence,
                    handoff: worker.state.channel.handoff_ticket(),
                    error: None,
                    finished: false,
                });
                if finished {
                    // 固定目标 ticket：只等待本次观察已受理的产品写入，不等待整个系统空闲。
                    let target = worker.services.writer.admitted_ticket();
                    match worker.services.writer.flush_through(target).await {
                        Ok(()) => {
                            worker
                                .state
                                .progress
                                .send_modify(|progress| progress.finished = true);
                            return;
                        }
                        Err(error) => {
                            worker.state.progress.send_modify(|progress| {
                                progress.error = Some(Arc::new(anyhow::Error::new(error)));
                                progress.finished = false;
                            });
                        }
                    }
                }
            }
            Err(error) => {
                // A fact this owner could not project leaves the committed stream discontinuous for
                // every subscriber, so the feed tells them to resynchronize from the durable window
                // instead of letting the client splice a hole; the worker retries the same watermark.
                worker.feed.rebase(0);
                worker
                    .state
                    .progress
                    .send_modify(|progress| progress.error = Some(Arc::new(error)));
            }
        }
        if current.lifecycle == ThreadLifecycle::Closed {
            tokio::select! {
                () = worker.state.retry.notified() => {}
                _ = handoff.changed() => {}
            }
            current = worker.thread.snapshot();
            continue;
        }
        tokio::select! {
            () = worker.state.retry.notified() => current = worker.thread.snapshot(),
            // A handoff the writer is waiting for may be the only reason this worker still has work
            // to do; re-run the projection so a deferred admission is taken over and saved.
            _ = handoff.changed() => current = worker.thread.snapshot(),
            // A typed storage change with no owner frame still has to reach subscribers; re-run the
            // pass so the owner republishes the state it just read.
            _ = persistence.changed() => current = worker.thread.snapshot(),
            update = updates.next() => match update {
                Some(snapshot) => current = snapshot,
                None => {
                    worker.state.progress.send_modify(|progress| progress.error = Some(Arc::new(anyhow::anyhow!("Thread subscription ended before its final projection"))));
                    tokio::select! {
                        () = worker.state.retry.notified() => {}
                        _ = handoff.changed() => {}
                    }
                    current = worker.thread.snapshot();
                }
            }
        }
    }
}

/// Everything one Thread's observation worker carries across a projection: the product services, the
/// owner handle it reads committed effects from, its progress and retry channel, the feed it
/// broadcasts on and the live projection it folds into.
///
/// Keeping this as one domain value is what lets the worker project without threading nine
/// independent arguments through every call; the live projection above stays a pure function of one
/// effect.
struct ProjectionWorker {
    services: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    /// Committed watermark the Thread already had when this projection was seeded. Terminal reports
    /// for Turns at or below it are repairs, not fresh continuations, so they do not wake a parent.
    recovered_through: u64,
    feed: Arc<ThreadLiveFeed>,
    live: Option<LiveOwner>,
}

/// The report facts of one finished Turn: the live projection's bounded accumulator when it folded
/// the Turn, otherwise the durable single-Turn slice.
///
/// The hot path takes the accumulator, which the projection maintained from the Turn's first
/// record, so a Turn that committed its visible output over many effects reports all of it without a
/// second copy of every body and without a history read. A Turn the resident projection never saw
/// from its start — a Thread re-activated once its Turn had already run, or a recovered child — has
/// no accumulator, and only then does this wait for the matching durable handoff and read the
/// bounded single-Turn slice from history. That is the cold recovery path, never a routine commit.
async fn turn_result(
    services: &ObservationServices,
    live: &LiveOwner,
    turn_id: &str,
) -> Result<crate::studio::thread_projection::TurnResult> {
    if let Some(result) = live.projection.turn_result(turn_id) {
        return Ok(result.clone());
    }
    await_history_durable(
        &live.channel,
        &live.thread.id,
        live.channel.handoff_ticket(),
    )
    .await?;
    let items = services
        .store
        .history(&live.thread.id)
        .await?
        .items_for_turn(turn_id)
        .await?;
    Ok(crate::studio::thread_projection::TurnResult::from_items(
        &items,
    ))
}

/// Waits until the history writer's durable watermark covers the handoff ticket `sequence`.
///
/// This deliberately does not use `Thread::flush`. That barrier targets *every commit the owner has
/// admitted*, including ones this projection has not handed over yet, and the writer refuses to save
/// a fact no projection holds — so an observer waiting on it would wait for its own next step, and
/// the request itself travels through the owner's command queue, which a running Turn only reaches at
/// its own safety points. Waiting for this projection's own handoff ticket asks for exactly the
/// commits it already prepared, in the order they were prepared, so it always completes, and a
/// channel that never saw a handoff (`0`) is trivially durable instead of waiting for a watermark a
/// re-activated Thread's fresh channel can no longer move.
///
/// The writer publishes its terminal diagnostic on the same channel, so a storage failure ends this
/// barrier with the real reason instead of hanging on a watermark that can no longer advance.
async fn await_history_durable(channel: &HistoryChannel, id: &str, sequence: u64) -> Result<()> {
    let mut status = channel.subscribe();
    loop {
        {
            let status = status.borrow_and_update();
            if status.committed_sequence >= sequence {
                return Ok(());
            }
            if let Some(error) = &status.error {
                bail!("Thread {id} history did not become durable through {sequence}: {error}");
            }
        }
        status
            .changed()
            .await
            .context("Thread history progress channel closed")?;
    }
}

/// The write this owner owes work on next: the retained handoff first, then the reliable queue.
///
/// The retained batch wins even when its queue entry has already left the unprojected set — the
/// owner still owes its report and handoff — and queue work is only picked up with no batch
/// retained, so a retry never depends on the queue still listing the commit.
fn next_projection_write(
    pending: &Option<PendingHandoff>,
    channel: &HistoryChannel,
) -> Option<Arc<ThreadWrite>> {
    pending
        .as_ref()
        .map(|pending| Arc::clone(&pending.write))
        .or_else(|| channel.next_unprojected())
}

/// Waits for one observation to reach the committed target fixed at call time.
///
/// An existing error is reported as it stands: an explicit retry wakes the worker, but only the
/// worker's own successful pass, which replaces the whole progress value, clears the error — so a
/// synchronize call may wake the retry and still return the original failure, while a later call
/// observes the real success. The returned handoff ticket is the watermark this observation's own
/// durable barrier waits for.
///
/// # Errors
/// The observation's retained failure, or its worker ending before the target was reached.
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

/// The Thread's product association, from the resident directory entry or from durable storage.
///
/// An archived hot entry may disappear before its original registration reaches SQLite, so the cold
/// branch drains the accepted directory writes first. The target is fixed at admission time and later
/// unrelated writes do not extend the wait. Only the first install and a product refresh resolve this
/// DTO: a streaming preview belongs to the owner already installed and never reads the directory.
async fn product_association(
    services: &ObservationServices,
    id: &str,
) -> Result<pl_protocol::Thread> {
    if let Some(thread) = services.events.thread_snapshot(id) {
        return Ok(thread);
    }
    let target = services.writer.admitted_ticket();
    services.writer.flush_through(target).await?;
    let association = services
        .store
        .read_thread_association(id)
        .await?
        .context("observed Thread has no product association")?;
    Ok(pl_protocol::Thread::from(association))
}

// The worker carries the projection owner, its feed and the product watermark across one projection;
// splitting them into a context struct would only hide the same state behind one more indirection.
impl ProjectionWorker {
    /// Takes over every admitted fact this projection owner has not folded yet, projects the current
    /// streaming overlay and, when `products` is set, the product directory and billing facts they
    /// imply.
    ///
    /// The reliable admission queue is the one source of committed work: a fact enters it when core
    /// commits it and leaves it only once this owner folded it *and* the durable store saved it, so
    /// the projection never races the owner's command queue or the disk. Facts the owner had already
    /// folded into the snapshot this projection was seeded from are taken over without being replayed
    /// as live frames.
    ///
    /// # Errors
    /// Returns a projection, storage association or directory failure. The worker reports it through
    /// its progress channel and retries the same watermark instead of skipping a commit.
    async fn project(
        &mut self,
        snapshot: &ThreadSnapshot,
        products: bool,
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
    ) -> Result<()> {
        let Self {
            services,
            id,
            thread,
            state,
            recovered_through,
            feed,
            live,
            ..
        } = self;
        let recovered_through = *recovered_through;
        if live.is_none() {
            // The product association is resolved once, when this projection owner is installed.
            // A Thread re-activated after its directory entry left memory reads it from SQLite here.
            let product = product_association(services, id).await?;
            *live = Some(
                LiveOwner::open(
                    services,
                    thread,
                    snapshot,
                    product,
                    Arc::clone(feed),
                    Arc::clone(&state.channel),
                    persistence,
                    #[cfg(test)]
                    state.pending_hook_slot(),
                )
                .await?,
            );
        }
        let live = live
            .as_mut()
            .expect("live projection owner was just installed");
        // The projection owner is the single producer of realtime content: it folds every admitted
        // fact exactly once, publishes it into the shared session and broadcasts the typed change,
        // whether or not a GUI is open.
        //
        // The association the owner was installed with is what identifies a parent or a billing
        // root; it never changes for a Thread, so a commit does not re-read the directory DTO for it.
        let owner_product = live.thread.clone();
        let mut newest_commit_at = 0_i64;
        loop {
            // The retained handoff is completed before any new queue work: its write is the very
            // Arc the queue admitted, so even a queue entry that already disappeared cannot make
            // this owner forget or re-project the commit it still owes.
            let retained_mode = live.pending.as_ref().map(|pending| pending.mode);
            let Some(write) = next_projection_write(&live.pending, &live.channel) else {
                break;
            };
            // Core admits effects before publishing its snapshot. Do not cross that publication
            // boundary: after a zero-demand decision, a later receiver registers before capturing a
            // snapshot that must already cover this effect. Otherwise admission could race receiver
            // registration and leave a skipped commit out of both baseline and feed. The existing
            // snapshot watch wakes us when this watermark advances; the reliable queue retains work.
            // A retained batch always satisfies the boundary it was taken over under, so it is
            // retried along its original mode instead of being parked again.
            if retained_mode.is_none() && write.effect.sequence > snapshot.commit_sequence {
                break;
            }
            let sequence = write.effect.sequence;
            if let Some(mode) = retained_mode {
                // Same batch, same mode: no re-seed, no re-fold, no re-projection and no
                // re-decided delivery — only the report preparation and the handoff are retried.
                let parent_report = live.finish_pending(services).await?;
                if mode == HandoffMode::Live {
                    billing::record(
                        &services.performance,
                        &owner_product.root_thread_id,
                        &write.effect,
                    )?;
                    newest_commit_at = newest_commit_at.max(write.effect.committed_at);
                    if let Some(message) = parent_report {
                        let _delivery = reports::publish_terminal(
                            services,
                            &owner_product,
                            message,
                            sequence > recovered_through,
                        )
                        .await?;
                    }
                }
                continue;
            }
            if sequence <= recovered_through {
                // A fact the owner committed before this projection existed: it is already part of
                // the snapshot the projection was seeded from, so it is folded for durability only.
                live.prepare_behind(services, id.as_str(), &write).await?;
                continue;
            }
            let parent_report = live.advance(services, id.as_str(), &write).await?;
            billing::record(
                &services.performance,
                &owner_product.root_thread_id,
                &write.effect,
            )?;
            newest_commit_at = newest_commit_at.max(write.effect.committed_at);
            if let Some(message) = parent_report {
                let _delivery = reports::publish_terminal(
                    services,
                    &owner_product,
                    message,
                    sequence > recovered_through,
                )
                .await?;
            }
        }
        // Streaming previews change without a commit and belong to the same publisher.
        live.stream(snapshot).await?;
        // The typed storage state is one owner fact: it is republished here whether this pass was
        // triggered by a commit, a preview or the coordinator's own typed status changing.
        live.observe_storage(snapshot, persistence);
        if !products {
            return Ok(());
        }
        // The directory DTO is re-read for a product refresh, because a concurrent title, mode or
        // archive operation owns those fields and a preview-only pass must not pay for the lookup.
        let mut product = product_association(services, id).await?;
        product.status = crate::studio::thread_projection::status(snapshot);
        product.updated_at = product.updated_at.max(newest_commit_at);
        // The directory summary is derived from the same reliable owner as the terminal report: the
        // in-memory projection on the hot path, and durable history only for a Turn it never saw.
        let summary = match snapshot
            .turns
            .last()
            .filter(|turn| turn.state != pl_core::thread::TurnState::Running)
        {
            Some(turn) => turn_result(services, live, &turn.turn_id)
                .await?
                .final_text(),
            None => None,
        };
        directory::publish(services, product, snapshot, summary).await?;
        Ok(())
    }
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;
    use crate::studio::storage::history::{EffectCommit, FactReceiptWrite};
    use crate::studio::storage::thread_writer::ThreadStorageSink;
    use crate::thread_assembler::{
        StudioActivationFactory, StudioThreadSpec, ThreadActivation, ThreadAssemblyError,
        ThreadPreparation,
    };
    use pl_core::{
        context::{ContextContent, OpaquePayload},
        model::{
            DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
            PreparedModelCall,
        },
        thread::{
            ModelStepLimit, ThreadCheckpoint, ThreadEffectBatch, TurnInput, TurnOutcome,
            TurnRecord, TurnState,
            cold::{ColdStore, ColdStoreHandle},
            input::{InputChange, InputRecord, InputState, ThreadInput},
        },
    };
    use pl_protocol::{ThreadItem, ThreadItemState};
    use std::time::Duration;

    #[tokio::test]
    async fn recovery_projection_loads_references_pruned_from_the_current_snapshot() -> Result<()> {
        recovery_projection(false).await?;
        recovery_projection(true).await
    }

    /// 普通问答的交互构造：问题来自生产者格式，回答用真实的 `pl.studio.user-answer` 载荷。
    fn qa_record(
        call_id: &str,
        revision: u64,
        state: pl_core::thread::interactions::InteractionState,
    ) -> Result<pl_core::thread::interactions::InteractionRecord> {
        let questions = vec![pl_protocol::UserQuestion {
            id: "provider".into(),
            header: "Provider".into(),
            question: "Which provider should the next release verify?".into(),
            is_other: true,
            is_secret: false,
            options: None,
        }];
        Ok(pl_core::thread::interactions::InteractionRecord {
            created_at: 10,
            updated_at: 10 + i64::try_from(revision)?,
            continuation_id: None,
            request: pl_core::thread::interactions::InteractionRequest {
                id: pl_core::tool::opaque::tool_interaction_id(call_id),
                turn_id: "turn-qa".into(),
                payload: OpaquePayload::new(
                    "pl.tool.user-input",
                    1,
                    serde_json::to_string(&questions)?,
                )?,
            },
            revision,
            state,
            extension_mutations: vec![],
        })
    }

    async fn register_test_thread(store: &StudioStore, thread: &pl_protocol::Thread) -> Result<()> {
        let mut delta = crate::studio::store::directory::DirectoryDelta::upsert_project(
            crate::studio::store::directory::ProjectDirectoryRecord {
                id: thread.project_id.clone(),
                name: "Test".into(),
                path: "/tmp/project-test".into(),
                ssh_alias: None,
                created_at: 1,
                updated_at: 1,
                last_opened_at: None,
                closed: false,
            },
        );
        delta.thread_upserts = vec![thread.clone()];
        store.persist_directory_summaries(&delta).await
    }

    fn bound_thread(thread_id: &str) -> pl_protocol::Thread {
        let mut thread = pl_protocol::Thread::placeholder(thread_id);
        thread.project_id = "project-test".into();
        thread.agent_path = thread_id.to_owned();
        thread.root_thread_id = thread_id.to_owned();
        thread
    }

    #[tokio::test]
    async fn observation_join_retains_wait_ownership_and_worker_failure() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("observation-stop-ack");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let owner = ThreadHandle::resume_without_model(thread.id.clone(), None)?;
        owner.close().await?;
        let (progress, _) = watch::channel(Progress::default());
        let publication = progress.clone();
        let (release, released) = tokio::sync::oneshot::channel();
        let observation = Observation {
            thread: owner.clone(),
            state: Arc::new(WorkerState {
                progress,
                retry: Notify::new(),
                channel: channel.clone(),
                #[cfg(test)]
                pending_hook: None,
            }),
            task: tokio::sync::Mutex::new(Some(tokio::spawn(async move {
                let _ = released.await;
                publication.send_modify(|progress| progress.finished = true);
            }))),
        };
        let mut waiting = Box::pin(observation.join());
        assert!(futures::poll!(waiting.as_mut()).is_pending());
        drop(waiting);
        assert!(
            observation.task.lock().await.is_some(),
            "cancellation cannot detach the observer's join handle"
        );
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("controlled observer lost its owner"))?;
        observation.join().await?;
        assert!(observation.task.lock().await.is_none());
        observation.join().await?;

        let (progress, _) = watch::channel(Progress::default());
        let failed = Observation {
            thread: owner,
            state: Arc::new(WorkerState {
                progress,
                retry: Notify::new(),
                channel: channel.clone(),
                #[cfg(test)]
                pending_hook: None,
            }),
            task: tokio::sync::Mutex::new(Some(tokio::spawn(async {
                panic!("controlled history observation exit");
            }))),
        };
        assert!(failed.join().await.is_err());
        assert!(failed.state.progress.borrow().finished);
        assert!(failed.task.lock().await.is_none());
        assert!(
            failed.join().await.is_err(),
            "retry cannot erase the failed observation ACK"
        );
        channel.stop_and_join().await?;
        drop(sink);
        Ok(())
    }

    /// 一个最小终态 Turn 提交：交接与报告路径的专项测试共用同一真实 effect/checkpoint。
    fn terminal_turn_write(
        thread: &pl_protocol::Thread,
        turn_id: &str,
    ) -> Result<(TurnRecord, ThreadWrite)> {
        let turn = TurnRecord {
            input_id: None,
            turn_id: turn_id.into(),
            state: TurnState::Interrupted,
            model_steps: 0,
            elapsed_ms: None,
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            turns: Arc::from([turn.clone()]),
            ..Default::default()
        };
        let write = ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 1,
                committed_at: 1,
                turn: Some(turn.clone()),
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 1, state),
            output_claim: None,
        };
        Ok((turn, write))
    }

    /// 交接被拒时批次与原报告原样保留；behind 批次即使带 changes 也不获得实时发布资格。
    ///
    /// 真实 worker 级的保槽/重试/同步收束由下方真实观察回归覆盖；这里只补真实流程无法自然
    /// 触达的两个交接边界：通道拒绝（未受理/已 durable）与 behind 模式的发布资格。
    #[tokio::test]
    async fn a_refused_or_behind_batch_keeps_retention_and_never_publishes_realtime() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("pending-handoff-manual");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let (turn, write) = terminal_turn_write(&thread, "pending-handoff-turn")?;
        let mut projection = LiveProjection::new();
        let (changes, prepared) =
            projection.advance(&chat, &thread, &write.effect, &write.checkpoint.state, true)?;
        let original_items = prepared.items.clone();
        let result = crate::studio::thread_projection::TurnResult::from_items(&original_items);
        let original_report =
            reports::terminal_message(&thread, &write.checkpoint.state, &turn, 1, &result)?;
        let mut prepared = prepared;
        Arc::make_mut(&mut prepared).parent_report = Some(original_report.clone());
        let pending = PendingHandoff {
            write: Arc::new(write.clone()),
            prepared,
            changes,
            mode: HandoffMode::Behind,
        };
        let feed = ThreadLiveFeed::new(None);
        let mut frames = feed.subscribe();
        let mut last_turn = feed.last_turn();
        // 1) 通道尚未受理该提交：交接被拒，批次与原报告原样保留，预算可见。
        assert!(pending.hand_over(&channel, &feed).is_err());
        assert_eq!(channel.handoff_ticket(), 0);
        assert_eq!(pending.prepared.items, original_items);
        assert!(pending.retained_bytes() > 0);
        // 2) 受理后同一批次交接：behind 即使带 changes 也不发实时帧，终态事实仍发布，
        //    报告原件随真实 writer 落盘。
        sink.admit(&thread.id, write.clone())?;
        let report = pending.hand_over(&channel, &feed)?;
        let report_id = report.as_ref().map(|message| message.id.clone());
        assert_eq!(report_id.as_deref(), Some(original_report.id.as_str()));
        assert!(matches!(
            frames.try_recv(),
            Err(broadcast::error::TryRecvError::Empty)
        ));
        let retained = last_turn
            .borrow_and_update()
            .clone()
            .context("retained terminal turn")?;
        assert_eq!(retained.id, turn.turn_id);
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
        let saved = store
            .history(&thread.id)
            .await?
            .parent_report(1)
            .await?
            .context("saved parent report")?;
        assert_eq!(saved.id, original_report.id);
        assert_eq!(saved.payload.content(), original_report.payload.content());
        drop(sink);
        Ok(())
    }

    /// A minimal model that returns one final text and no tool calls: the real core turn loop
    /// completes the turn, commits its terminal effect and hands it to the real storage.
    #[derive(Debug)]
    struct FinalTextModel;

    impl ModelSession for FinalTextModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: Arc::from("child finished"),
                    }],
                    tool_calls: Vec::new(),
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    /// Runs one real turn whose single model step is the final text; the turn must complete.
    async fn run_final_turn(handle: &ThreadHandle, turn_id: &str) -> Result<()> {
        let outcome = handle
            .run_turn(TurnInput {
                turn_id: turn_id.into(),
                attempt_prefix: turn_id.into(),
                content: vec![ContextContent::Text {
                    text: Arc::from("finish the child turn"),
                }],
                max_model_steps: ModelStepLimit::Limited(1.try_into()?),
                cancellation: tokio_util::sync::CancellationToken::new(),
            })
            .await?;
        assert_eq!(outcome.outcome, TurnOutcome::Completed);
        Ok(())
    }

    /// A registered child of a real parent thread, as the directory and the report path require.
    fn child_thread(child_id: &str, parent_id: &str) -> pl_protocol::Thread {
        let mut thread = pl_protocol::Thread::placeholder(child_id);
        thread.project_id = "project-test".into();
        thread.agent_path = child_id.to_owned();
        thread.root_thread_id = parent_id.to_owned();
        thread.parent_thread_id = Some(parent_id.to_owned());
        thread
    }

    /// The observation services exactly as the runtime assembles them, on an isolated store.
    struct ObservationFixture {
        // RAII keep-alive for the fixture's store directory: never read, but
        // dropping the fixture must not delete the store while it is in use.
        _temp: tempfile::TempDir,
        store: StudioStore,
        services: ObservationServices,
        observations: ThreadObservations,
        writer: crate::studio::agent_host::ThreadWriteBehindWriter,
    }

    async fn observation_fixture() -> Result<ObservationFixture> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let writer = crate::studio::agent_host::ThreadWriteBehindWriter::new(store.clone());
        let events = ProductEventBus::new(store.clone(), writer.clone());
        let config = crate::config::ConfigRuntime::initialize(crate::config::ConfigStore::new(
            crate::config::ConfigPaths::from_config_dir(
                store.paths().home().join("isolated-observation-config"),
            ),
        ))?;
        let performance = ModelPerformanceOwner::new(
            store.clone(),
            events.clone(),
            crate::studio::ids::new_id("observation-fixture"),
        );
        let recovery = crate::studio::StudioRecoveryRegistry::new();
        let source = crate::worker_assets::RemoteHelperSource::External;
        let bots =
            crate::bots::BotRuntime::new(store.paths().clone(), config.clone(), events.clone())?;
        let worktrees =
            crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
        let factory = crate::studio::thread_factory::StudioThreadFactory::new(
            crate::studio::thread_factory::StudioThreadServices {
                store: store.clone(),
                worktrees: worktrees.clone(),
                product_events: events.clone(),
                config_runtime: config.clone(),
                mcp_runtime: pl_tool::mcp::McpRuntime::new(pl_tool::mcp::McpConnector::default())
                    .handle(),
                lsp_runtime: pl_lsp::runtime::LspRuntimeRegistry::new(),
                skills: crate::studio::runtime::SkillCatalogRuntime::new(
                    events.clone(),
                    store.paths().home().join("isolated-observation-skills"),
                ),
                thread_modes: config.thread_mode_manager(),
                ssh_manager: Arc::new(crate::worker_assets::ssh_manager(&source)),
                helper_source: source,
                bots,
            },
        );
        let threads = crate::thread_assembler::StudioThreadAssembler::default();
        threads.set_agent_services(
            config.clone(),
            store.clone(),
            events.clone(),
            factory.clone(),
            performance.clone(),
            recovery.clone(),
        )?;
        threads.set_child_factory(crate::thread_assembler::ConfiguredChildFactory::new(
            config.clone(),
            factory.clone(),
        ))?;
        let services = ObservationServices {
            config,
            recovery,
            store: store.clone(),
            events,
            performance,
            threads,
            writer: writer.clone(),
        };
        let observations = ThreadObservations::new(services.clone());
        observations.install(
            factory.clone(),
            crate::studio::runtime::rejected_tools::RejectedToolOwners::default(),
        )?;
        Ok(ObservationFixture {
            _temp: temp,
            store,
            services,
            observations,
            writer,
        })
    }

    /// A real parent activation: the parent gets a real handle with the real storage attached and
    /// a route no turn ever calls, so the child's terminal report is delivered to a real receiver.
    struct ParentActivation {
        store: StudioStore,
        sink: ThreadStorageSink,
    }

    impl std::fmt::Debug for ParentActivation {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            // The store owns live runtime state that must not be structurally
            // printed; the fixture identity is all a failure report needs.
            f.debug_struct("ParentActivation")
                .field("store", &"StudioStore(..)")
                .field("sink", &self.sink)
                .finish()
        }
    }

    fn activation_error(source: impl Into<anyhow::Error>) -> ThreadAssemblyError {
        ThreadAssemblyError::Resource {
            operation: "observation fixture activation",
            source: source.into().into_boxed_dyn_error(),
        }
    }

    impl StudioActivationFactory for ParentActivation {
        async fn root_delegation(
            &self,
            identity: &ThreadActivation,
        ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
            let _ = identity;
            Ok(Default::default())
        }

        async fn prepare(
            &self,
            request: ThreadPreparation,
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            let id = request.identity.id.clone();
            let model_info = pl_model::model::ModelInfo::compatible("observation-parent");
            let route = pl_model::config::ResolvedModelRoute {
                pricing_mode: Default::default(),
                role: crate::config::root_agent_route_id(),
                account_id: pl_model::config::AccountId::new("observation-fixture-account")
                    .map_err(activation_error)?,
                endpoint: pl_model::protocol::ProtocolEndpoint::compatible(
                    "observation fixture",
                    "http://127.0.0.1:0",
                ),
                context: model_info.resolve_context(None),
                model: model_info,
                effort: None,
            };
            let model = pl_model::runtime::ThreadModel::new(
                pl_model::runtime::ModelRuntime::from_route(&route).map_err(activation_error)?,
                None,
            );
            let resources_dir = self
                .store
                .session_resources_dir(&id)
                .map_err(activation_error)?;
            // The preflight selection and the prepared spec must agree: freeze
            // the same default delegation selection the root preflight returns
            // into the spec's initial extensions.
            let mut initial_extensions = BTreeMap::new();
            initial_extensions.insert(
                crate::studio::delegation::EXTENSION.to_owned(),
                crate::studio::delegation::encode(Default::default()).map_err(activation_error)?,
            );
            Ok(StudioThreadSpec {
                workspace_usage: None,
                preparation_guard: None,
                context_preparation: None,
                agent_controls: request.agent_controls,
                execution: pl_core::thread::input::InputDriverOptions {
                    max_model_steps: ModelStepLimit::Unlimited,
                },
                id,
                parent_id: None,
                route,
                model_available: true,
                model,
                checkpoint: None,
                initial_context: Vec::new(),
                initial_runtime_facts: Vec::new(),
                initial_extensions,
                tools: Vec::new(),
                resources: pl_core::context::ResourceAccess::new(
                    crate::resource_store::FileResourceStore::new(resources_dir),
                ),
                capacity: Default::default(),
                cold_store: Some(ColdStoreHandle::new(self.sink.clone())),
            })
        }
    }

    fn channel_gauge(channel: &HistoryChannel) -> u64 {
        channel.subscribe().borrow().queued_bytes
    }

    /// The shared session's committed items of one turn: identity, order, revision and body.
    async fn turn_items(chat: &Session, turn_id: &str) -> Result<Vec<pl_core::chat::ChatItem>> {
        let page = chat
            .page(pl_core::chat::ChatPageRequest {
                before: None,
                limit: Some(100),
            })
            .await?;
        Ok(page
            .items
            .into_iter()
            .filter(|item| item.turn_id == turn_id)
            .collect())
    }

    /// 真实 worker 级回归：child 的真实终态提交在报告准备处受控失败后，批次保留、真实
    /// synchronize 返回原错不假成功；受控放行后同一批次完成报告与交接，修订不变、报告原件
    /// 落盘、发布资格与预算随保槽/释放收束，最后真实关闭并回收全部观察与写入资源。
    #[tokio::test]
    async fn a_child_terminal_report_failure_retains_the_batch_until_a_real_retry() -> Result<()> {
        let fixture = observation_fixture().await?;
        let child_id = "child-terminal-report";
        let parent_id = "child-terminal-report-parent";
        let parent = bound_thread(parent_id);
        let child = child_thread(child_id, parent_id);
        register_test_thread(&fixture.store, &parent).await?;
        register_test_thread(&fixture.store, &child).await?;
        let sink = ThreadStorageSink::new(fixture.store.clone(), child.clone(), None).await?;
        let channel = fixture.store.thread_persistence().history_channel(child_id);

        let (hook, entered_rx, control) = PendingPhaseHook::new();
        fixture.observations.install_pending_hook(child_id, hook);
        let entered = Arc::new(tokio::sync::Mutex::new(entered_rx));

        // Real parent receiver, activated through the production path before the child runs.
        let parent_sink =
            ThreadStorageSink::new(fixture.store.clone(), parent.clone(), None).await?;
        let parent_handle = tokio::time::timeout(
            Duration::from_secs(10),
            fixture.services.threads.activate(
                crate::thread_assembler::ThreadActivation {
                    id: parent_id.into(),
                    parent_id: None,
                },
                ParentActivation {
                    store: fixture.store.clone(),
                    sink: parent_sink.clone(),
                },
            ),
        )
        .await??;

        // Real child: a real handle with real storage, observed by the real worker before the
        // turn, so every real commit of the turn is projected by the live path.
        let handle = ThreadHandle::start(child_id.into(), DynModelSession::new(FinalTextModel))?;
        handle
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        fixture
            .observations
            .observe(child_id.to_owned(), handle.clone());
        let observation = fixture
            .observations
            .0
            .observations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(child_id)
            .and_then(|entries| entries.last())
            .cloned()
            .context("child observation registered")?;
        let mut progress = observation.state.progress.subscribe();

        // Subscribed before the retry, so the retained batch's handover frame has a receiver.
        let feed = fixture
            .observations
            .live_feed(child_id)
            .context("child live feed")?;
        let mut frames = feed.subscribe();
        let mut last_turn = feed.last_turn();

        run_final_turn(&handle, "child-terminal-turn").await?;
        let terminal = handle.snapshot().commit_sequence;

        // Pass every earlier batch at the phase boundary; the terminal batch stays parked.
        loop {
            let sequence = {
                let mut entries = entered.lock().await;
                tokio::time::timeout(Duration::from_secs(10), entries.recv())
                    .await?
                    .context("pending hook closed")?
            };
            if sequence == terminal {
                break;
            }
            control.send_replace(Some(Ok(())));
        }
        // The parked batch is already folded into the shared session: freeze its observable facts.
        let chat = fixture.store.chat_session(child_id).await?;
        let first = turn_items(&chat, "child-terminal-turn").await?;
        assert!(!first.is_empty());
        let gauge_parked = channel_gauge(&channel);
        assert!(gauge_parked > 0);

        // Release the terminal batch with the controlled failure; the real worker reports it.
        control.send_replace(Some(Err("controlled report failure".to_owned())));
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if progress.borrow_and_update().error.is_some() {
                    break;
                }
                progress.changed().await.context("worker progress closed")?;
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        // The retained batch keeps its budget while the failure stands.
        assert_eq!(channel_gauge(&channel), gauge_parked);

        // The real synchronizer returns the original failure instead of clearing it or faking
        // success from the already-applied earlier watermark.
        let synchronized = tokio::time::timeout(
            Duration::from_secs(10),
            fixture.observations.synchronize(Some(child_id)),
        )
        .await?;
        let failure =
            synchronized.expect_err("synchronize must surface the retained observation error");
        assert!(failure.to_string().contains("controlled report failure"));

        // Allow one real retry: the same batch re-enters the boundary and proceeds.
        let retry_pump = tokio::spawn({
            let entered = entered.clone();
            let control = control.clone();
            async move {
                let sequence = entered.lock().await.recv().await.context("retry entry")?;
                control.send_replace(Some(Ok(())));
                Ok::<_, anyhow::Error>(sequence)
            }
        });
        // The retry synchronize only has to wake the worker; reading the still
        // retained error immediately afterwards is its documented behavior.
        let _ = tokio::time::timeout(
            Duration::from_secs(10),
            fixture.observations.synchronize(Some(child_id)),
        )
        .await?;
        let retried = retry_pump.await??;
        assert_eq!(retried, terminal);
        // The real worker, not the test, clears the error: wait until its own
        // progress reports the terminal watermark with no failure standing.
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let state = progress.borrow_and_update().clone();
                if state.error.is_none() && state.applied >= terminal {
                    break;
                }
                progress
                    .changed()
                    .await
                    .context("worker progress closed before the retry settled")?;
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        // Only a synchronize after the real settlement succeeds.
        tokio::time::timeout(
            Duration::from_secs(10),
            fixture.observations.synchronize(Some(child_id)),
        )
        .await??;

        // The same batch was handed over exactly once; the original report is durable with its
        // integrity receipt, the session items are identical to the parked read, and the live
        // publications carry the terminal facts.
        assert_eq!(channel.handoff_ticket(), terminal);
        assert!(channel.next_unprojected().is_none());
        let history = fixture.store.history(child_id).await?;
        assert_eq!(history.watermark().await?, terminal);
        let report = history
            .parent_report(terminal)
            .await?
            .context("original terminal report durable")?;
        assert_eq!(
            report.id,
            crate::studio::agent_close::terminal_report_id(child_id, terminal)
        );
        let second = turn_items(&chat, "child-terminal-turn").await?;
        assert_eq!(second, first);
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                // Earlier batches and status frames may have queued while subscribed; only the
                // retained terminal batch's committed frame proves the live publication.
                match frames.recv().await? {
                    ThreadLiveEvent::Committed { sequence, .. } if sequence == terminal => break,
                    _ => continue,
                }
            }
            Ok::<_, tokio::sync::broadcast::error::RecvError>(())
        })
        .await??;
        let retained_turn = last_turn
            .borrow_and_update()
            .clone()
            .context("retained terminal turn")?;
        assert_eq!(retained_turn.id, "child-terminal-turn");
        // The pending share left the Thread budget with the handoff.
        assert!(channel_gauge(&channel) < gauge_parked);
        // The report reached the real parent receiver; a skipped delivery is never claimed here.
        assert!(
            parent_handle
                .snapshot()
                .inbox
                .iter()
                .any(|record| record.message.id == report.id),
            "the original parent delivery reached the real parent receiver"
        );

        // Real close: the close commits pass the boundary, the worker retires, and the
        // observation, channel and writer all reach their real terminal states.
        let close_pump = tokio::spawn({
            let entered = entered.clone();
            let control = control.clone();
            async move {
                while let Some(_sequence) = entered.lock().await.recv().await {
                    control.send_replace(Some(Ok(())));
                }
            }
        });
        handle.close().await?;
        fixture.observations.drain(child_id).await?;
        // The registry keeps the hook registered, so the pump cannot observe channel closure;
        // once the observation is joined no further entry can arrive and the parked pump stops.
        close_pump.abort();
        let _ = close_pump.await;
        parent_handle.close().await?;
        fixture.observations.drain(parent_id).await?;
        drop(sink);
        drop(parent_sink);
        fixture.writer.shutdown().await?;
        Ok(())
    }

    /// 取消等待不丢批次：真实 owner 在报告等待点被 poll 后丢弃调用 future，槽仍在；同一
    /// owner 的真实报告准备与交接接续，修订不变，预算随报告增长并在交接后释放。
    #[tokio::test]
    async fn dropping_the_report_wait_keeps_the_pending_batch_and_its_revisions() -> Result<()> {
        let fixture = observation_fixture().await?;
        let child_id = "child-cancel-wait";
        let parent_id = "child-cancel-wait-parent";
        let parent = bound_thread(parent_id);
        let child = child_thread(child_id, parent_id);
        register_test_thread(&fixture.store, &parent).await?;
        register_test_thread(&fixture.store, &child).await?;
        let sink = ThreadStorageSink::new(fixture.store.clone(), child.clone(), None).await?;
        let channel = fixture.store.thread_persistence().history_channel(child_id);
        let (hook, mut entered_rx, control) = PendingPhaseHook::new();

        // A real turn commits its real writes; no observation worker is installed, so this owner
        // is the only projection consumer of the admitted queue.
        let handle = ThreadHandle::start(child_id.into(), DynModelSession::new(FinalTextModel))?;
        handle
            .attach_storage(ColdStoreHandle::new(sink.clone()))
            .await?;
        run_final_turn(&handle, "cancel-wait-turn").await?;
        let terminal = handle.snapshot().commit_sequence;

        let feed = Arc::new(ThreadLiveFeed::new(None));
        let snapshot = handle.snapshot();
        let mut live = LiveOwner::open(
            &fixture.services,
            &handle,
            &snapshot,
            child.clone(),
            feed,
            channel.clone(),
            None,
            Some(hook),
        )
        .await?;
        // Earlier batches pass the boundary; each pre-armed release covers exactly one entry.
        while let Some(write) = channel.next_unprojected() {
            if write.effect.sequence == terminal {
                break;
            }
            control.send_replace(Some(Ok(())));
            live.advance(&fixture.services, child_id, &write).await?;
        }
        let write = channel
            .next_unprojected()
            .context("the terminal write is still admitted")?;
        assert_eq!(write.effect.sequence, terminal);

        // Park the real advance on the pending boundary, then cancel the calling future.
        let mut parked = Box::pin(live.advance(&fixture.services, child_id, &write));
        assert!(futures::poll!(parked.as_mut()).is_pending());
        let entered = tokio::time::timeout(Duration::from_secs(10), entered_rx.recv())
            .await?
            .context("hook entered")?;
        assert_eq!(entered, terminal);
        assert!(futures::poll!(parked.as_mut()).is_pending());
        drop(parked);

        // The cancelled call leaves the batch retained; nothing re-projected it.
        let pending = live
            .pending
            .as_ref()
            .context("retained batch after cancellation")?;
        assert_eq!(pending.write.effect.sequence, terminal);
        assert_eq!(pending.mode, HandoffMode::Live);
        let chat = fixture.store.chat_session(child_id).await?;
        let first = turn_items(&chat, "cancel-wait-turn").await?;
        assert!(!first.is_empty());
        let gauge_before = channel_gauge(&channel);
        let pending_bytes = pending.retained_bytes();
        assert!(pending_bytes > 0);

        // The real report preparation attaches to the retained batch and the budget grows with it.
        live.prepare_parent_report(&fixture.services).await?;
        let with_report = live
            .pending
            .as_ref()
            .context("batch retained through report preparation")?
            .retained_bytes();
        assert!(with_report > pending_bytes);
        assert!(channel_gauge(&channel) > gauge_before);

        // The same owner finishes the handoff; the hook consumes one pre-armed release.
        control.send_replace(Some(Ok(())));
        let report = live
            .finish_pending(&fixture.services)
            .await?
            .context("original report handed over")?;
        assert!(live.pending.is_none());
        let second = turn_items(&chat, "cancel-wait-turn").await?;
        assert_eq!(second, first);
        tokio::time::timeout(Duration::from_secs(10), sink.flush(child_id, terminal)).await??;
        let history = fixture.store.history(child_id).await?;
        assert_eq!(history.watermark().await?, terminal);
        assert_eq!(
            history
                .parent_report(terminal)
                .await?
                .context("original report durable")?
                .id,
            report.id
        );
        drop(live);
        drop(sink);
        channel.stop_and_join().await?;
        fixture.writer.shutdown().await?;
        Ok(())
    }

    /// 跨重开的普通问答：回答 effect 只带交互与隐藏 continuation。
    ///
    /// 回答时那条调用已经不在 Thread 状态里（工具成功的 Task 已是终态、Turn 已结束），新建的
    /// LiveProjection 也没有它的正文。owner 必须按 identity 从可靠 history 补读那一条再投影，
    /// 否则这份被采纳的回答会以 MissingDurableToolCall 失败、永不落盘。
    #[tokio::test]
    async fn a_question_answered_after_a_restart_is_projected_and_saved() -> Result<()> {
        use pl_core::thread::interactions::{InteractionResponse, InteractionState};

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("qa-restart");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let history = store.history(&thread.id).await?;
        let call_id = "call-restart";
        let tool_id = crate::studio::thread_projection::order::tool_id(call_id);

        // 1) 提问在重启之前就已落盘：工具条目（尚未带问答）+ pending 交互回执。
        let pending = qa_record(call_id, 1, InteractionState::Pending)?;
        let question = ThreadItem::new(
            tool_id.clone(),
            thread.id.clone(),
            "turn-qa".into(),
            1,
            2,
            10,
            11,
            ThreadItemState::Tool(pl_protocol::ThreadToolItem::new(
                pl_protocol::ThreadToolInvocation::new(
                    call_id.into(),
                    "request_user_input".into(),
                    "{\"questions\":[]}".into(),
                ),
                pl_protocol::ThreadToolState::Running(pl_protocol::RunningThreadTool::new(
                    String::new(),
                )),
            )),
        );
        history
            .commit_effect(
                1,
                EffectCommit {
                    items: std::slice::from_ref(&question),
                    rolled_back_turns: &Default::default(),
                    identities: &[],
                    messages: &[],
                    receipts: &[FactReceiptWrite {
                        item_id: crate::studio::thread_projection::order::receipt_id(
                            "interaction",
                            &pending.request.id,
                        ),
                        revision: pending.revision,
                        kind: "interaction",
                        payload: serde_json::to_string(&pending)?,
                    }],
                    tasks: &[],
                    deliveries: &[],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;

        // 2) 重启：新投影没有任何驻留正文，Turn/Task 都不在（空且已剪枝的状态）。
        let mut projection = LiveProjection::new();
        let answered = qa_record(
            call_id,
            2,
            InteractionState::Resolved(InteractionResponse {
                payload: OpaquePayload::new(
                    "pl.studio.user-answer",
                    1,
                    serde_json::to_string(
                        &serde_json::json!({"answers": {"provider": {"answers": ["anthropic"]}}}),
                    )?,
                )?,
                context: vec![],
            }),
        )?;
        let answer_effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 2,
            committed_at: 2,
            interactions: [answered].into(),
            ..Default::default()
        };
        let answered_state = ThreadSnapshot {
            commit_sequence: 2,
            ..Default::default()
        };

        // 没有补读时这张投影无法完成这份回答：这是缺 body 的真实失败，而不是可接受的限制。
        assert!(
            projection
                .advance(&chat, &thread, &answer_effect, &answered_state, true)
                .is_err()
        );
        // owner 按 identity 补读那一条 durable 正文后，同一次投影就能完成。
        crate::studio::thread_projection::seed_interaction_targets(
            &mut projection,
            &thread.id,
            &history,
            &answer_effect,
        )
        .await?;
        let (_, prepared) =
            projection.advance(&chat, &thread, &answer_effect, &answered_state, true)?;

        // 3) 走真实 writer：回答必须落盘在原条目上，身份/顺序/创建时间不变。
        let answer_write = ThreadWrite {
            effect: Arc::new(answer_effect),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 2, answered_state),
            output_claim: None,
        };
        sink.admit(&thread.id, answer_write)?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 2)).await??;
        let saved = history
            .existing_items([tool_id.clone()])
            .await?
            .remove(&tool_id)
            .context("answered question item")?;
        assert_eq!(saved.ordinal, 1);
        assert_eq!(saved.created_at, 10);
        let user_input = saved
            .tool()
            .and_then(|tool| tool.user_input())
            .context("saved Q&A")?;
        assert_eq!(user_input.answers()[0].answers(), ["anthropic"]);
        Ok(())
    }

    /// 当前压缩回执必须同时穿过计量、时间线与真实 writer，不能在投影阶段阻塞保存。
    #[tokio::test]
    async fn a_current_compaction_receipt_is_projected_and_saved() -> Result<()> {
        use pl_core::thread::{
            ContextReplacement, ContextReplacementReason,
            extensions::{ExtensionChange, ExtensionRecord},
        };
        use pl_model::{
            protocol::{ProtocolKind, WireApi},
            runtime::ModelCallBinding,
        };

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("compaction-save");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let receipt = crate::compaction::CompactionReceipt {
            inference_id: "compaction-1".into(),
            binding: ModelCallBinding {
                account_id: "account".into(),
                model_id: "model".into(),
                protocol: ProtocolKind::OpenAi,
                wire_api: WireApi::Responses,
                isolation: thread.id.clone(),
                purpose: "compaction".into(),
                context_window: Some(100_000),
                max_context_window: Some(100_000),
                auto_compact_limit: Some(80_000),
            },
            reasoning_effort: None,
            context_window: Some(100_000),
            turn_id: "pruned-turn".into(),
            accounting: Default::default(),
            model_observation: None,
            implementation: Some("native".into()),
            error: None,
        };
        let extension = ExtensionRecord {
            revision: 1,
            payload: receipt.clone().into_payload()?,
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            extension_sequence: 1,
            extensions: [(crate::compaction::LATEST_RECEIPT.into(), extension.clone())].into(),
            ..Default::default()
        };
        let effect = ThreadEffectBatch {
            thread_id: thread.id.clone(),
            sequence: 1,
            committed_at: 10,
            extensions: [ExtensionChange::Put {
                id: crate::compaction::LATEST_RECEIPT.into(),
                record: extension,
            }]
            .into(),
            replacements: [ContextReplacement {
                reason: ContextReplacementReason::Compaction,
                previous: Default::default(),
                current: state.context.clone(),
                previous_private_context: None,
            }]
            .into(),
            ..Default::default()
        };
        let mut usage = Default::default();
        crate::studio::thread_projection::fold_effect_accounting(&mut usage, &effect)?;
        assert_eq!(usage.inference_count, 1);
        let mut projection = LiveProjection::new();
        let (_, prepared) = projection.advance(&chat, &thread, &effect, &state, true)?;
        let write = ThreadWrite {
            effect: Arc::new(effect),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 1, state),
            output_claim: None,
        };
        sink.admit(&thread.id, write)?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
        let history = store.history(&thread.id).await?;
        let items = history.items_for_turn(&receipt.turn_id).await?;
        assert_eq!(items.len(), 1);
        let saved = &items[0];
        assert_eq!(saved.turn_id, receipt.turn_id);
        assert!(matches!(
            saved.state(),
            ThreadItemState::ContextCompaction(_)
        ));
        Ok(())
    }

    async fn recovery_projection(delayed_admission: bool) -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let thread = bound_thread("recovered-hidden-input");
        register_test_thread(&store, &thread).await?;
        let sink = ThreadStorageSink::new(store.clone(), thread.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&thread.id);
        let chat = store.chat_session(&thread.id).await?;
        let input_id = "interaction:approved:continuation";
        let turn = TurnRecord {
            input_id: Some(input_id.into()),
            turn_id: "interrupted-turn".into(),
            state: TurnState::Running,
            model_steps: 0,
            elapsed_ms: None,
        };
        let input = InputRecord {
            continuation: None,
            input: ThreadInput {
                purpose: pl_core::thread::input::InputPurpose::Message,
                id: input_id.into(),
                payload: OpaquePayload::new(
                    "pl.studio.interaction-continuation",
                    1,
                    r#"{"interactionId":"approved","presentation":"hidden"}"#,
                )?,
                context: Vec::new(),
            },
            accepted_sequence: 1,
            ordinal: 1,
            revision: 1,
            delivery: Default::default(),
            state: InputState::Consumed {
                turn_id: turn.turn_id.clone(),
                attempt_id: "attempt".into(),
            },
        };
        let state = ThreadSnapshot {
            commit_sequence: 1,
            inputs: Arc::from([input.clone()]),
            turns: Arc::from([turn.clone()]),
            ..Default::default()
        };
        let write = ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 1,
                committed_at: 1,
                inputs: Arc::from([InputChange::Accepted(input)]),
                turn: Some(turn.clone()),
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 1, state),
            output_claim: None,
        };
        sink.admit(&thread.id, write.clone())?;
        let mut projection = LiveProjection::new();
        let (_, prepared) =
            projection.advance(&chat, &thread, &write.effect, &write.checkpoint.state, true)?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 1)).await??;
        drop(projection);

        let interrupted = TurnRecord {
            state: TurnState::Interrupted,
            ..turn
        };
        let state = ThreadSnapshot {
            commit_sequence: 2,
            turns: Arc::from([interrupted.clone()]),
            ..Default::default()
        };
        let recovery = ThreadWrite {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: thread.id.clone(),
                sequence: 2,
                committed_at: 2,
                turn: Some(interrupted.clone()),
                ..Default::default()
            }),
            checkpoint: ThreadCheckpoint::capture_transfer(thread.id.clone(), 2, state),
            output_claim: None,
        };
        let current = recovery.checkpoint.clone().pruned().state;
        assert!(current.turns.is_empty());
        // Admission can be delayed by storage pressure until after observer installation.
        if !delayed_admission {
            sink.admit(&thread.id, recovery.clone())?;
        }
        let retained = if delayed_admission {
            assert!(channel.next_unprojected().is_none());
            vec![recovery.effect.clone()]
        } else {
            Vec::new()
        };
        let (items, hidden) = cold_seed(&store, &thread, &current, &channel, &retained).await?;
        let mut restored = LiveProjection::new();
        restored.seed(items, hidden);
        restored.stream(&chat, &thread, &current, 2).await?;
        if delayed_admission {
            sink.admit(&thread.id, recovery.clone())?;
        }
        let prepared = restored.project_committed(
            &chat,
            &thread,
            &recovery.effect,
            &recovery.checkpoint.state,
        )?;
        assert!(channel.prepare(prepared));
        tokio::time::timeout(Duration::from_secs(5), sink.flush(&thread.id, 2)).await??;
        let history = store.history(&thread.id).await?;
        assert_eq!(history.watermark().await?, 2);
        assert!(history.existing_items([input_id.into()]).await?.is_empty());
        assert!(
            history
                .hidden_input_identities([input_id.into()])
                .await?
                .contains(input_id)
        );
        let saved = history
            .newest_terminal_turn()
            .await?
            .context("saved interrupted turn")?;
        assert_eq!(saved.id, interrupted.turn_id);
        assert!(matches!(saved.state, pl_protocol::TurnState::Cancelled(_)));
        Ok(())
    }
}
