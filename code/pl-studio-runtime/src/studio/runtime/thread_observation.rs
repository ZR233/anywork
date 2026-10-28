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
use crate::thread_assembler::agent_review::ReviewDeliverySource;

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

    fn publish(&self, event: ThreadLiveEvent) {
        // A feed with no subscriber is the normal state of a Thread without an open GUI; the
        // projection owner still consumed and published the fact.
        let _ = self.events.send(event);
    }

    /// Tells every subscriber that the owner re-seeded and continuity is no longer provable.
    fn rebase(&self, dropped: u64) {
        self.publish(ThreadLiveEvent::Rebase { dropped });
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
    terminal_transfer: Arc<
        std::sync::Mutex<Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>>,
    >,
    progress: watch::Sender<Progress>,
    retry: Notify,
    /// The Thread's reliable admission channel, shared with its history writer.
    ///
    /// A settled observation reads a finished Turn back from history, and its own barrier has to ask
    /// the writer that took the projection's handoff how far it is durable. The handle is captured
    /// here, at observation time, so the barrier observes the very incarnation the writer admits
    /// into instead of a channel that a cleanly detached predecessor already released.
    channel: Arc<HistoryChannel>,
    /// Explicit reconciliation is observation only, even when it catches a newly committed Turn.
    reconciliation_through: Arc<std::sync::atomic::AtomicU64>,
    observed_before_execution: bool,
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
}
#[derive(Clone)]
pub(super) struct ThreadObservations(Arc<Shared>);

impl ThreadObservations {
    pub(super) fn new(projector: ObservationServices) -> Self {
        Self(Arc::new(Shared {
            projector,
            observations: Mutex::new(BTreeMap::new()),
            live: Mutex::new(BTreeMap::new()),
        }))
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
            terminal_transfer: Default::default(),
            progress,
            retry: Notify::new(),
            channel,
            reconciliation_through: Arc::new(std::sync::atomic::AtomicU64::new(recovered_through)),
            observed_before_execution,
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
            let mut progress = observation.state.progress.subscribe();
            observation.state.progress.send_modify(|progress| {
                if !progress.finished {
                    progress.error = None;
                }
            });
            observation.state.retry.notify_one();
            let durable_through = loop {
                let state = progress.borrow().clone();
                if let Some(error) = state.error {
                    bail!("Thread {id} product observation failed: {error:#}");
                }
                if state.initialized
                    && state.applied >= target
                    && (target_snapshot.lifecycle != ThreadLifecycle::Closed || state.finished)
                {
                    break state.handoff;
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
            };
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
            services
                .threads
                .recover_saved_review_deliveries(&child)
                .await?;
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
        self.thread_observations
            .synchronize(Some(thread_id))
            .await?;
        self.threads.settle_review_deliveries(thread_id).await?;
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
    terminal_transfer: Arc<
        std::sync::Mutex<Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>>,
    >,
    terminal_revocation: Arc<std::sync::atomic::AtomicU64>,
    terminal_floor: u64,
    first_send: bool,
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
}

impl LiveOwner {
    async fn open(
        projector: &ObservationServices,
        handle: &ThreadHandle,
        snapshot: &ThreadSnapshot,
        thread: pl_protocol::Thread,
        feed: Arc<ThreadLiveFeed>,
        state: Arc<WorkerState>,
        persistence: Option<&pl_protocol::ThreadPersistenceSnapshot>,
    ) -> Result<Self> {
        let channel = state.channel.clone();
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
            terminal_transfer: state.terminal_transfer.clone(),
            terminal_revocation: state.reconciliation_through.clone(),
            terminal_floor: state.progress.borrow().applied,
            first_send: state.observed_before_execution,
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
        let bytes = self
            .projection
            .retained_bytes()
            .saturating_add(self.activity.retained_bytes());
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
    ) -> Result<()> {
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
    ) -> Result<()> {
        let effect = &write.effect;
        let projected = (|| {
            crate::studio::thread_projection::fold_effect_accounting(&mut self.usage, effect)?;
            self.projection
                .advance(&self.chat, &self.thread, effect, &write.checkpoint.state)
        })();
        let (changes, mut prepared) = match projected {
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
        self.prepare_parent_report(services, write, &mut prepared)
            .await?;
        self.handoff_terminal(services, write, &mut prepared)?;
        // Retain the terminal Turn of this commit as the owner's own last-turn fact before the frame
        // is broadcast: `turnCompleted` reaches only the subscribers that exist right now, so the
        // value a later subscriber is told has to be the very frame this commit produced.
        if let Some(turn) = changes.iter().rev().find_map(|change| match change {
            LiveEvent::Turn { turn, .. } if turn.state.is_terminal() => Some(turn),
            _ => None,
        }) {
            self.feed.publish_last_turn(Arc::new(turn.clone()));
        }
        self.feed.publish(ThreadLiveEvent::Committed {
            sequence: effect.sequence,
            changes,
        });
        self.publish_retained();
        Ok(())
    }

    fn handoff_terminal(
        &self,
        services: &ObservationServices,
        write: &Arc<ThreadWrite>,
        prepared: &mut Arc<crate::studio::thread_projection::PreparedEffect>,
    ) -> Result<()> {
        if let Some(original) = prepared.parent_report.clone() {
            let authority = Arc::new(
                crate::thread_assembler::review_dispatch::TerminalAuthority::capture(
                    &write.checkpoint.state,
                )?,
            );
            let bytes = self.channel.terminal_material_bytes(&authority, &original);
            let retention = services
                .store
                .thread_persistence()
                .retain_terminal_material(&self.thread.id, &self.channel, bytes);
            Arc::make_mut(prepared).terminal_retention = Some(retention.clone());
            let terminal = Arc::new(crate::thread_assembler::review_dispatch::TerminalDelivery {
                thread: self.thread.clone(),
                sequence: write.effect.sequence,
                authority,
                original: Some(original),
                source: if self.first_send && write.effect.sequence > self.terminal_floor {
                    ReviewDeliverySource::LiveTerminal
                } else {
                    ReviewDeliverySource::Reconciliation
                },
                revocation: self.terminal_revocation.clone(),
                channel: Some(self.channel.clone()),
                wake: write.effect.sequence > self.terminal_floor,
                _material: Some(retention),
            });
            let mut transfer = self
                .terminal_transfer
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            anyhow::ensure!(
                transfer.is_none(),
                "terminal responsibility has not been handed over"
            );
            *transfer = Some(terminal);
        }
        if !self.channel.prepare(prepared.clone()) {
            // Already durable replays have no new handoff ticket. Their durable original wins;
            // rebuilding an equal identity must never mint live first-send authority.
            let mut transfer = self
                .terminal_transfer
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(terminal) = transfer.as_mut() {
                let terminal = Arc::make_mut(terminal);
                terminal
                    .revocation
                    .fetch_max(terminal.sequence, std::sync::atomic::Ordering::AcqRel);
                terminal.source = ReviewDeliverySource::Reconciliation;
                terminal.original = None;
                terminal.wake = false;
            }
            anyhow::ensure!(
                self.channel.delivery_retry_mark().0 >= prepared.sequence,
                "terminal prepared handoff was not accepted"
            );
        }
        Ok(())
    }

    async fn prepare_parent_report(
        &self,
        services: &ObservationServices,
        write: &ThreadWrite,
        prepared: &mut Arc<crate::studio::thread_projection::PreparedEffect>,
    ) -> Result<()> {
        let Some(turn) = write.effect.turn.as_ref().filter(|turn| {
            turn.state != pl_core::thread::TurnState::Running
                && self.thread.parent_thread_id.is_some()
        }) else {
            return Ok(());
        };
        let mut result = if let Some(result) = self.projection.turn_result(&turn.turn_id) {
            result.clone()
        } else {
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
        if result.finish.is_none() {
            await_history_durable(
                &self.channel,
                &self.thread.id,
                self.channel.handoff_ticket(),
            )
            .await?;
            restore_finish(services, &self.thread.id, &turn.turn_id, &mut result).await?;
        }
        Arc::make_mut(prepared).parent_report = Some(Arc::new(reports::terminal_message(
            &self.thread,
            &write.checkpoint.state,
            turn,
            write.effect.sequence,
            &result,
        )?));
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
        let mut prepared = match projected {
            Ok(prepared) => prepared,
            Err(error) => {
                self.channel.fail_projection(
                    write.effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        self.prepare_parent_report(services, write, &mut prepared)
            .await?;
        if let Some(turn) = crate::studio::thread_projection::prepared_terminal_turn(&prepared) {
            self.feed.publish_last_turn(Arc::new(turn));
        }
        self.handoff_terminal(services, write, &mut prepared)?;
        self.publish_retained();
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
        self.runtime_published = Some(runtime.clone());
        self.feed.publish(ThreadLiveEvent::Runtime {
            runtime: Arc::new(runtime),
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
        self.activity_published = activity.clone();
        // One shared handle per published change: every subscriber clones that handle, never the body.
        self.feed.publish(ThreadLiveEvent::Activity {
            activity: activity.map(Arc::new),
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
    let continuous = state.observed_before_execution;
    let mut worker = ProjectionWorker {
        services: projector,
        id,
        thread,
        state,
        recovered_through,
        feed,
        live: None,
        live_floor: recovered_through,
        // Fresh bootstrap may have a nonzero fence; the registered owner proved that its
        // reliable channel was installed before any execution or model call.
        continuous,
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
                worker.continuous = true;
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
                            worker.continuous = false;
                            worker.live_floor = worker.live_floor.max(current.commit_sequence);
                            worker
                                .state
                                .reconciliation_through
                                .fetch_max(worker.live_floor, std::sync::atomic::Ordering::AcqRel);
                            worker.state.progress.send_modify(|progress| {
                                progress.error = Some(Arc::new(anyhow::Error::new(error)));
                                progress.finished = false;
                            });
                        }
                    }
                }
            }
            Err(error) => {
                worker.continuous = false;
                worker.live_floor = worker.live_floor.max(current.commit_sequence);
                worker
                    .state
                    .reconciliation_through
                    .fetch_max(current.commit_sequence, std::sync::atomic::Ordering::AcqRel);
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
                    worker.continuous = false;
                    worker.live_floor = worker.live_floor.max(worker.thread.snapshot().commit_sequence);
                    worker.state.reconciliation_through.fetch_max(worker.live_floor, std::sync::atomic::Ordering::AcqRel);
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
    /// Commits already visible at installation or across an observation failure cannot first-send.
    live_floor: u64,
    continuous: bool,
}

async fn restore_finish(
    services: &ObservationServices,
    id: &str,
    turn: &str,
    result: &mut crate::studio::thread_projection::TurnResult,
) -> Result<()> {
    if result.finish.is_some() {
        return Ok(());
    }
    let Some(tool) = result
        .last_tool()
        .filter(|tool| tool.invocation().name() == pl_tool::finish_turn::TOOL_FINISH_TURN)
    else {
        return Ok(());
    };
    let Some(saved) = services
        .store
        .history(id)
        .await?
        .tool_task(tool.invocation().tool_call_id())
        .await?
    else {
        return Ok(());
    };
    if saved.task.turn_id == turn {
        result.finish = saved
            .delivery
            .as_ref()
            .and_then(crate::studio::thread_projection::committed_finish);
    }
    Ok(())
}

async fn transfer_terminal(services: &ObservationServices, state: &WorkerState) -> Result<()> {
    let pending = state
        .terminal_transfer
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    let Some(pending) = pending else {
        return Ok(());
    };
    let channel = pending
        .channel
        .as_ref()
        .context("terminal transfer has no history channel")?;
    anyhow::ensure!(
        channel.handoff_ticket() >= pending.sequence
            || channel.delivery_retry_mark().0 >= pending.sequence,
        "terminal transfer precedes handoff"
    );
    services
        .threads
        .start_terminal_delivery(pending.clone())
        .await?;
    let mut slot = state
        .terminal_transfer
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if slot
        .as_ref()
        .is_some_and(|current| Arc::ptr_eq(current, &pending))
    {
        *slot = None;
    }
    Ok(())
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
    channel.await_handoff_durable(id, sequence).await
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
            live_floor,
            continuous,
            ..
        } = self;
        let recovered_through = *recovered_through;
        transfer_terminal(services, state).await?;
        if !*continuous {
            *live_floor = (*live_floor).max(snapshot.commit_sequence);
        }
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
                    state.clone(),
                    persistence,
                )
                .await?,
            );
        }
        let live = live
            .as_mut()
            .expect("live projection owner was just installed");
        live.first_send &= *continuous;
        // The projection owner is the single producer of realtime content: it folds every admitted
        // fact exactly once, publishes it into the shared session and broadcasts the typed change,
        // whether or not a GUI is open.
        //
        // The association the owner was installed with is what identifies a parent or a billing
        // root; it never changes for a Thread, so a commit does not re-read the directory DTO for it.
        let owner_product = live.thread.clone();
        let mut newest_commit_at = 0_i64;
        while let Some(write) = live.channel.next_unprojected() {
            let sequence = write.effect.sequence;
            if sequence <= recovered_through {
                // A fact the owner committed before this projection existed: it is already part of
                // the snapshot the projection was seeded from, so it is folded for durability only.
                live.prepare_behind(services, id.as_str(), &write).await?;
                transfer_terminal(services, state).await?;
                continue;
            }
            live.advance(services, id.as_str(), &write).await?;
            billing::record(
                &services.performance,
                &owner_product.root_thread_id,
                &write.effect,
            )?;
            newest_commit_at = newest_commit_at.max(write.effect.committed_at);
            transfer_terminal(services, state).await?;
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
    use pl_core::{
        context::OpaquePayload,
        thread::{
            ThreadCheckpoint, ThreadEffectBatch, TurnRecord, TurnState,
            cold::ColdStore,
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

    /// History fault scenarios use the production ProjectionWorker and its real managed terminal
    /// handoff. Only its already-committed core facts are constructed here; no report/exception is
    /// preinserted and no substitute projection, terminal producer or receipt decoder is used.
    async fn terminal_projection_fixture(
        store: &StudioStore,
        review: bool,
    ) -> Result<(
        crate::studio::storage::thread_writer::storage_fault_tests::CloseFactoryFixture,
        ThreadObservations,
        ProjectionWorker,
        ThreadStorageSink,
    )> {
        use crate::studio::storage_fault_test_support::{close_factory, ticket};
        let resources = close_factory(store)?;
        let threads = crate::thread_assembler::StudioThreadAssembler::default();
        resources.install(&threads)?;
        let services = ObservationServices {
            config: resources.config.clone(),
            recovery: crate::studio::StudioRecoveryRegistry::new(),
            store: store.clone(),
            events: resources.events.clone(),
            performance: ModelPerformanceOwner::new(
                store.clone(),
                resources.events.clone(),
                "terminal-fault".into(),
            ),
            threads,
            writer: resources.writer.clone(),
        };
        let observations = ThreadObservations::new(services.clone());
        observations.install(resources.factory.clone(), Default::default())?;
        // A genuinely cold parent with a real checkpoint. Reception must use the production
        // receive-only owner, not an executable fixture Entry or a fake ACK callback.
        let parent = bound_thread("terminal-parent");
        register_test_thread(store, &parent).await?;
        let parent_sink = ThreadStorageSink::new(store.clone(), parent.clone(), None).await?;
        let initial = ticket(&parent.id, 1);
        let (_, prepared) = LiveProjection::new().advance(
            &store.chat_session(&parent.id).await?,
            &parent,
            &initial.effect,
            &initial.checkpoint.state,
        )?;
        parent_sink.admit(&parent.id, initial)?;
        let parent_channel = store.thread_persistence().history_channel(&parent.id);
        assert!(parent_channel.prepare(prepared));
        parent_sink.flush(&parent.id, 1).await?;
        parent_channel.stop_and_join().await?;

        let mut child = bound_thread(if review {
            "terminal-review"
        } else {
            "terminal-child"
        });
        child.role = if review {
            "custom-history-review"
        } else {
            "history-executor"
        }
        .into();
        child.root_thread_id = parent.id.clone();
        child.parent_thread_id = Some(parent.id.clone());
        register_test_thread(store, &child).await?;
        if review {
            let mut target = bound_thread("unstarted-executor");
            target.root_thread_id = parent.id.clone();
            target.parent_thread_id = Some(parent.id);
            target.role = "history-executor".into();
            register_test_thread(store, &target).await?;
        }
        let sink = ThreadStorageSink::new(store.clone(), child.clone(), None).await?;
        let channel = store.thread_persistence().history_channel(&child.id);
        let (progress, _) = watch::channel(Progress::default());
        let mut worker = ProjectionWorker {
            services,
            id: child.id.clone(),
            thread: ThreadHandle::resume_without_model(child.id.clone(), None)?,
            state: Arc::new(WorkerState {
                terminal_transfer: Default::default(),
                progress,
                retry: Notify::new(),
                channel,
                reconciliation_through: Arc::new(std::sync::atomic::AtomicU64::new(0)),
                observed_before_execution: true,
            }),
            recovered_through: 0,
            feed: Arc::new(ThreadLiveFeed::new(None)),
            live: None,
            live_floor: 0,
            continuous: true,
        };
        let initial = ticket(&child.id, 1);
        sink.admit(&child.id, initial.clone())?;
        worker
            .project(&initial.checkpoint.state, false, None)
            .await?;
        sink.flush(&child.id, 1).await?;
        Ok((resources, observations, worker, sink))
    }

    fn terminal_write(id: &str, review: bool) -> Result<ThreadWrite> {
        use pl_core::{
            context::{ContextContent, ContextRecord, ContextSource},
            thread::{
                ToolDelivery, ToolOutcome, TurnOutcome,
                extensions::ExtensionRecord,
                journal::ContextChange,
                task::{TaskRecord, TaskStatus},
            },
        };
        let mut write = crate::studio::storage_fault_test_support::ticket(id, 2);
        let turn = TurnRecord {
            turn_id: "terminal-turn".into(),
            input_id: None,
            state: TurnState::Finished(TurnOutcome::Completed),
            model_steps: 0,
            elapsed_ms: None,
        };
        let state = &mut write.checkpoint.state;
        state.turns = Arc::from([turn.clone()]);
        let effect = Arc::make_mut(&mut write.effect);
        effect.turn = Some(turn);
        if !review {
            return Ok(write);
        }
        let workspace = pl_protocol::AgentWorkspaceAssignmentSnapshot {
            mode: pl_protocol::AgentWorkspaceMode::Review,
            project_root: "/proved-root".into(),
            root: "/proved-root".into(),
            writable_paths: Some(vec![]),
            worktree: None,
            review_target: Some(pl_protocol::AgentReviewTargetSnapshot {
                agent_id: "unstarted-executor".into(),
                feedback: Some(pl_protocol::AgentReviewFeedback::ToExecutor),
                baseline: Some(pl_protocol::AgentReviewBaseline {
                    turn_id: "executor-terminal".into(),
                    input_id: None,
                    terminal_sequence: 1,
                    commit_sequence: 1,
                    input_ordinal: 0,
                    message_sequence: 0,
                    consumed_messages: 0,
                    wake_messages_through: 0,
                    execution_sequence: 0,
                    continuation_id: None,
                }),
            }),
        };
        let profile = pl_protocol::AgentProfileSnapshot {
            profile_id: "custom-history-review".into(),
            display_name: "History review".into(),
            description: String::new(),
            when_to_use: String::new(),
            system_instructions: String::new(),
            account_id: "unused".into(),
            model_id: "unused".into(),
            effort: None,
            source: "fixture".into(),
            revision: "frozen".into(),
            content_hash: "immutable-profile".into(),
            system: false,
            enabled: true,
            workspace_mode: pl_protocol::AgentWorkspaceMode::Review,
        };
        for (id, payload) in [
            (
                crate::studio::workspace_receipt::EXTENSION,
                crate::studio::workspace_receipt::to_payload(&workspace)?,
            ),
            (
                crate::studio::model_route::AGENT_PROFILE_EXTENSION,
                crate::studio::model_route::encode_profile(&profile)?,
            ),
        ] {
            state.extensions.insert(
                id.into(),
                ExtensionRecord {
                    revision: 1,
                    payload,
                },
            );
        }
        let saved = pl_tool::finish_turn::SavedFinishTurn {
            message: "不可泄漏到父 compact 的完整 findings".into(),
            review: Some(pl_tool::finish_turn::ReviewResult {
                disposition: pl_tool::finish_turn::ReviewDisposition::NeedsChanges,
                summary: "持久化边界需要返修".into(),
                reviewed_version: "diff:history-fault-fixture".into(),
            }),
            feedback_message: Some("固定宿主 wrapper 与原始完整 findings".into()),
        };
        let tool = pl_tool::finish_turn::TOOL_FINISH_TURN;
        let call = "terminal-finish";
        let output = pl_core::tool::ToolOutput::new(
            OpaquePayload::new("pl.tool.finish-turn", 2, serde_json::to_string(&saved)?)?,
            vec![ContextContent::Text {
                text: saved.message.into(),
            }],
        )
        .ending_turn();
        let delivery = ToolDelivery {
            target: Default::default(),
            call_id: call.into(),
            tool_id: tool.into(),
            delivered_context: output.context().to_vec(),
            output,
            outcome: ToolOutcome::Succeeded,
        };
        let task = TaskRecord {
            id: format!("task:{call}"),
            call_id: call.into(),
            tool_id: tool.into(),
            turn_id: "terminal-turn".into(),
            revision: 1,
            status: TaskStatus::Succeeded,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(2),
        };
        state.live_calls.insert(call.into(), "terminal-turn".into());
        state.tasks.insert(task.id.clone(), task.clone());
        state.deliveries = Arc::from([delivery.clone()]);
        let record = ContextRecord {
            id: "terminal-call-record".into(),
            turn_id: Some("terminal-turn".into()),
            source: ContextSource::Assistant,
            content: vec![],
            tool_calls: vec![pl_core::model::ModelToolCall {
                rejection: None,
                call_id: call.into(),
                tool_id: tool.into(),
                arguments: OpaquePayload::text("{}"),
            }],
        };
        let result = ContextRecord {
            id: "terminal-result-record".into(),
            turn_id: Some("terminal-turn".into()),
            source: ContextSource::ToolResult {
                call_id: call.into(),
                tool_id: tool.into(),
            },
            content: delivery.delivered_context.clone(),
            tool_calls: vec![],
        };
        state.context.revision = 1;
        state.context.records = Arc::from([record.clone(), result.clone()]);
        effect.context = Some(ContextChange::Append {
            revision: 1,
            records: Arc::from([record, result]),
        });
        effect.tasks = Arc::from([task]);
        effect.deliveries = Arc::from([delivery]);
        Ok(write)
    }

    async fn wait_terminal_receipt(store: &StudioStore, id: &str) -> Result<()> {
        // Subscribe before the lookup: completion of an arbitrarily short SQL write cannot be lost.
        let mut updates = store.thread_persistence().subscribe();
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if store
                    .history("terminal-parent")
                    .await?
                    .message_identity(id)
                    .await?
                    .is_some()
                {
                    return Ok::<_, anyhow::Error>(());
                }
                updates.changed().await?;
            }
        })
        .await
        .context("automatic terminal parent arrival")?
    }

    #[tokio::test]
    async fn terminal_projection_history_recovery_automatically_delivers_ordinary_and_review()
    -> Result<()> {
        use sea_orm::ConnectionTrait;
        for review in [false, true] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
            let (resources, observations, mut worker, sink) =
                terminal_projection_fixture(&store, review).await?;
            let db = sea_orm::Database::connect(
                crate::studio::paths::sqlite_file_options(
                    &store
                        .session_paths("project-test", &worker.id)?
                        .history_database(),
                    crate::studio::paths::SqliteFileMode::ReadWrite,
                    |options| options,
                )
                .await?,
            )
            .await?;
            db.execute_unprepared("CREATE TRIGGER reject_terminal BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'controlled terminal save rejection'); END").await?;
            let write = terminal_write(&worker.id, review)?;
            sink.admit(&worker.id, write.clone())?;
            // This is the production projection/handoff. It must return before N can be saved.
            tokio::time::timeout(
                Duration::from_secs(5),
                worker.project(&write.checkpoint.state, false, None),
            )
            .await??;
            assert!(worker.state.terminal_transfer.lock().unwrap().is_none());
            assert!(
                tokio::time::timeout(
                    Duration::from_secs(5),
                    worker.services.threads.join_review_delivery(&worker.id)
                )
                .await?
                .is_err()
            );
            let id = crate::studio::agent_close::terminal_report_id(&worker.id, 2);
            assert!(
                store
                    .history("terminal-parent")
                    .await?
                    .message_identity(&id)
                    .await?
                    .is_none()
            );
            assert!(
                worker.state.channel.has_delivery_bytes(),
                "blocked owner retains shared terminal material"
            );
            let generation = worker.state.channel.subscribe().borrow().fault_generation;
            db.execute_unprepared("DROP TRIGGER reject_terminal")
                .await?;
            store
                .thread_persistence()
                .retry_history(&worker.id, generation)
                .await?;
            // No settle/collector/close/cold scan: only the original writer's recovery notification.
            wait_terminal_receipt(&store, &id).await?;
            tokio::time::timeout(
                Duration::from_secs(10),
                worker.services.threads.join_review_delivery(&worker.id),
            )
            .await
            .context("join repaired terminal operation")??;
            if review {
                let original = store
                    .history(&worker.id)
                    .await?
                    .parent_report(2)
                    .await?
                    .context("original report")?;
                assert!(!original.payload.content().contains("不可泄漏"));
                let facts = store
                    .history(&worker.id)
                    .await?
                    .review_delivery_exceptions("")
                    .await?;
                assert_eq!(facts.len(), 1);
                assert!(
                    facts[0]
                        .message
                        .payload
                        .content()
                        .contains("recoveryRequiresScheduling"),
                    "{}",
                    facts[0].message.payload.content()
                );
                wait_terminal_receipt(&store, &facts[0].message.id).await?;
            }
            worker.state.channel.stop_and_join().await?;
            tokio::time::timeout(Duration::from_secs(10), observations.finish())
                .await
                .context("finish repaired terminal observers")??;
            resources.shutdown().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn terminal_projection_capacity_release_automatically_resumes_without_first_send()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let (resources, observations, mut worker, sink) =
            terminal_projection_fixture(&store, true).await?;
        // Another Thread has accepted operation output, not a review-retention guard. The public
        // ColdStore entry below is exactly the production OutputBudget::release backend boundary.
        let output_thread = bound_thread("output-quota-thread");
        register_test_thread(&store, &output_thread).await?;
        let output_sink =
            ThreadStorageSink::new(store.clone(), output_thread.clone(), None).await?;
        let output_channel = store
            .thread_persistence()
            .history_channel(&output_thread.id);
        let initial = crate::studio::storage_fault_test_support::ticket(&output_thread.id, 1);
        let (_, prepared) = LiveProjection::new().advance(
            &store.chat_session(&output_thread.id).await?,
            &output_thread,
            &initial.effect,
            &initial.checkpoint.state,
        )?;
        output_sink.admit(&output_thread.id, initial)?;
        assert!(output_channel.prepare(prepared));
        wait_history_test_signal(output_channel.effects_released.subscribe(), 1).await?;
        let write = terminal_write(&worker.id, true)?;
        sink.admit(&worker.id, write.clone())?;
        let occupied = store.thread_persistence().delivery_process_bytes();
        let accepted = 256 * 1024 * 1024 - occupied - 1;
        let operation = "retained-producer-output";
        assert_eq!(
            output_sink.reserve_operation_output(&output_thread.id, operation, accepted)?,
            accepted
        );
        output_sink.charge_operation_output(&output_thread.id, operation, accepted)?;
        worker.project(&write.checkpoint.state, false, None).await?;
        assert!(
            tokio::time::timeout(
                Duration::from_secs(5),
                worker.services.threads.join_review_delivery(&worker.id)
            )
            .await?
            .is_err()
        );
        assert!(worker.state.channel.has_delivery_bytes());
        // All previous real wake sources must have returned Pending, AFTER writer ACK released N.
        // This excludes a leftover writer/status event masking a missing release notification.
        wait_history_test_signal(worker.state.channel.terminal_parked.subscribe(), 2).await?;
        let mut capacity = store.thread_persistence().subscribe_delivery_capacity();
        capacity.borrow_and_update();
        let before_release = store.thread_persistence().delivery_process_bytes();
        output_sink.release_operation_output(&output_thread.id, operation);
        assert_eq!(
            store.thread_persistence().delivery_process_bytes(),
            before_release - accepted
        );
        assert!(
            capacity.has_changed()?,
            "R1: cross-Thread operation output release did not publish capacity after the terminal producer parked"
        );
        let id = crate::studio::agent_close::terminal_report_id(&worker.id, 2);
        wait_terminal_receipt(&store, &id).await?;
        tokio::time::timeout(
            Duration::from_secs(10),
            worker.services.threads.join_review_delivery(&worker.id),
        )
        .await
        .context("join capacity-repaired terminal operation")??;
        let facts = store
            .history(&worker.id)
            .await?
            .review_delivery_exceptions("")
            .await?;
        assert_eq!(facts.len(), 1);
        assert!(
            facts[0]
                .message
                .payload
                .content()
                .contains("recoveryRequiresScheduling"),
            "{}",
            facts[0].message.payload.content()
        );
        wait_terminal_receipt(&store, &facts[0].message.id).await?;
        assert!(
            worker
                .services
                .threads
                .observed_thread("unstarted-executor")
                .is_none()
        );
        worker.state.channel.stop_and_join().await?;
        output_channel.stop_and_join().await?;
        tokio::time::timeout(Duration::from_secs(10), observations.finish())
            .await
            .context("finish capacity-repaired observers")??;
        resources.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn terminal_projection_cancelled_join_keeps_original_publication_owner() -> Result<()> {
        use pl_core::context::{ContextContent, ContextRecord, ContextSource};
        use pl_core::thread::journal::ContextChange;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let (resources, observations, mut worker, sink) =
            terminal_projection_fixture(&store, true).await?;
        let source = worker.services.threads.clone();
        let parent_gate = source.agent_operation("terminal-parent").await;
        let old_text: Arc<str> = "older context body; ".repeat(256 * 1024).into();
        let old_context = Arc::downgrade(&old_text);
        let record = ContextRecord {
            id: "previous-context".into(),
            turn_id: Some("previous-turn".into()),
            source: ContextSource::Runtime {
                source_id: "historical-context".into(),
            },
            content: vec![ContextContent::Text { text: old_text }],
            tool_calls: vec![],
        };
        let mut prior = crate::studio::storage_fault_test_support::ticket(&worker.id, 2);
        prior.checkpoint.state.context.revision = 1;
        prior.checkpoint.state.context.records = Arc::from([record]);
        Arc::make_mut(&mut prior.effect).context = Some(ContextChange::Append {
            revision: 1,
            records: prior.checkpoint.state.context.records.clone(),
        });
        sink.admit(&worker.id, prior.clone())?;
        worker.project(&prior.checkpoint.state, false, None).await?;
        wait_history_test_signal(worker.state.channel.effects_released.subscribe(), 2).await?;
        let mut write = terminal_write(&worker.id, true)?;
        write.checkpoint.state.commit_sequence = 3;
        write.checkpoint.state_revision = 3;
        write.checkpoint.history_fence = 3;
        let terminal_context = write.checkpoint.state.context.records.clone();
        write.checkpoint.state.context.records = prior
            .checkpoint
            .state
            .context
            .records
            .iter()
            .chain(terminal_context.iter())
            .cloned()
            .collect::<Vec<_>>()
            .into();
        write.checkpoint.state.context.revision = 2;
        let effect = Arc::make_mut(&mut write.effect);
        effect.sequence = 3;
        effect.context = Some(ContextChange::Append {
            revision: 2,
            records: terminal_context,
        });
        assert!(
            write.effect.encode()?.content().len() < 16 * 1024,
            "terminal effect must stay small despite its older checkpoint context"
        );
        drop(prior);
        sink.admit(&worker.id, write.clone())?;
        let queued = worker
            .state
            .channel
            .next_unprojected()
            .context("queued terminal write")?;
        let old_write = Arc::downgrade(&queued);
        drop(queued);
        // Parent publication is blocked at the real operation gate, but projection must hand off.
        tokio::time::timeout(
            Duration::from_secs(5),
            worker.project(&write.checkpoint.state, false, None),
        )
        .await??;
        drop(write); // No caller-owned checkpoint may be mistaken for the producer's retention.
        wait_history_test_signal(worker.state.channel.effects_released.subscribe(), 3).await?;
        let mut replacement = crate::studio::storage_fault_test_support::ticket(&worker.id, 4);
        Arc::make_mut(&mut replacement.effect).context =
            Some(ContextChange::Replace(Default::default()));
        sink.admit(&worker.id, replacement.clone())?;
        worker
            .project(&replacement.checkpoint.state, false, None)
            .await?;
        drop(replacement);
        wait_history_test_signal(worker.state.channel.effects_released.subscribe(), 4).await?;
        assert!(
            old_write.upgrade().is_none(),
            "R2: the terminal producer still pins the entire old ThreadWrite after the writer and caller released it"
        );
        assert!(
            old_context.upgrade().is_none(),
            "the producer must not retain unused historical context after replacement"
        );
        let held_bytes = worker.state.channel.retained_delivery_bytes();
        assert!(
            held_bytes > 0 && held_bytes < 128 * 1024,
            "the retained budget must cover only the small report/authority and its bounded in-flight copies: {held_bytes}"
        );
        let mut caller = Box::pin(source.join_review_delivery(&worker.id));
        assert!(futures::poll!(caller.as_mut()).is_pending());
        drop(caller);
        assert!(worker.state.channel.has_delivery_bytes());
        let id = crate::studio::agent_close::terminal_report_id(&worker.id, 3);
        let original = store
            .history(&worker.id)
            .await?
            .parent_report(3)
            .await?
            .context("frozen original")?;
        assert!(
            store
                .history("terminal-parent")
                .await?
                .message_identity(&id)
                .await?
                .is_none()
        );
        drop(parent_gate);
        wait_terminal_receipt(&store, &id).await?;
        tokio::time::timeout(
            Duration::from_secs(10),
            source.join_review_delivery(&worker.id),
        )
        .await??;
        let receipt = store
            .history("terminal-parent")
            .await?
            .message_identity(&id)
            .await?
            .context("original report ACK")?;
        assert_eq!(receipt.digest.as_deref(), Some(original.digest().as_str()));
        let facts = store
            .history(&worker.id)
            .await?
            .review_delivery_exceptions("")
            .await?;
        assert_eq!(facts.len(), 1);
        let exception: crate::thread_assembler::review_delivery::ReviewDeliveryException =
            serde_json::from_str(facts[0].message.payload.content())?;
        assert_eq!(
            exception.target_agent_id, "unstarted-executor",
            "use the original frozen authority after the old checkpoint was released"
        );
        assert!(
            !worker.state.channel.has_delivery_bytes(),
            "only actual joined completion releases the shared terminal material"
        );
        worker.state.channel.stop_and_join().await?;
        observations.finish().await?;
        resources.shutdown().await?;
        Ok(())
    }

    async fn wait_history_test_signal(
        mut signal: watch::Receiver<u64>,
        through: u64,
    ) -> Result<()> {
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if *signal.borrow_and_update() >= through {
                    return Ok::<_, anyhow::Error>(());
                }
                signal.changed().await?;
            }
        })
        .await
        .context("controlled writer/park ownership boundary")?
    }

    #[tokio::test]
    async fn terminal_projection_exception_cas_save_recovery_keeps_original_and_independent_ack()
    -> Result<()> {
        use sea_orm::ConnectionTrait;
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("studio/v2/studio.sqlite")).await?;
        let (resources, observations, mut worker, sink) =
            terminal_projection_fixture(&store, true).await?;
        let db = sea_orm::Database::connect(
            crate::studio::paths::sqlite_file_options(
                &store
                    .session_paths("project-test", &worker.id)?
                    .history_database(),
                crate::studio::paths::SqliteFileMode::ReadWrite,
                |options| options,
            )
            .await?,
        )
        .await?;
        db.execute_unprepared("CREATE TRIGGER reject_review_exception BEFORE INSERT ON history_fact_receipts WHEN NEW.kind='reviewDeliveryException' BEGIN SELECT RAISE(ABORT,'controlled exception save rejection'); END").await?;
        let write = terminal_write(&worker.id, true)?;
        sink.admit(&worker.id, write.clone())?;
        worker.project(&write.checkpoint.state, false, None).await?;
        let source = worker.services.threads.clone();
        assert!(
            tokio::time::timeout(
                Duration::from_secs(5),
                source.join_review_delivery(&worker.id)
            )
            .await?
            .is_err()
        );
        let carrier = source
            .observed_thread(&worker.id)
            .context("retained source storage owner")?
            .snapshot()
            .extensions
            .values()
            .find_map(|record| {
                crate::thread_assembler::review_delivery::ReviewDeliveryFact::decode(
                    &record.payload,
                )
                .ok()
            })
            .context("accepted exception CAS carrier")?;
        let digest = carrier.message.digest();
        let generation = worker.state.channel.subscribe().borrow().fault_generation;
        // A blocked join/close cannot release the undurable operation or its writer.
        assert!(source.join_review_delivery(&worker.id).await.is_err());
        assert!(
            worker.state.channel.stop_and_join().await.is_err(),
            "blocked close must retain the undurable writer"
        );
        assert!(worker.state.channel.has_delivery_bytes());
        db.execute_unprepared("DROP TRIGGER reject_review_exception")
            .await?;
        store
            .thread_persistence()
            .retry_history(&worker.id, generation)
            .await?;
        wait_terminal_receipt(&store, &carrier.message.id).await?;
        tokio::time::timeout(
            Duration::from_secs(10),
            source.join_review_delivery(&worker.id),
        )
        .await
        .context("join repaired exception operation")??;
        let saved = store
            .history(&worker.id)
            .await?
            .review_delivery_exception(&carrier.message.id)
            .await?
            .context("durable original exception")?;
        assert_eq!(
            saved.message.digest(),
            digest,
            "recovery must not replace the original rejection with an invented reason"
        );
        tokio::time::timeout(Duration::from_secs(10), observations.finish())
            .await
            .context("finish repaired exception observers")??;
        resources.shutdown().await?;
        Ok(())
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
                terminal_transfer: Default::default(),
                progress,
                retry: Notify::new(),
                channel: channel.clone(),
                reconciliation_through: Arc::new(std::sync::atomic::AtomicU64::new(u64::MAX)),
                observed_before_execution: false,
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
                terminal_transfer: Default::default(),
                progress,
                retry: Notify::new(),
                channel: channel.clone(),
                reconciliation_through: Arc::new(std::sync::atomic::AtomicU64::new(u64::MAX)),
                observed_before_execution: false,
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
                .advance(&chat, &thread, &answer_effect, &answered_state)
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
        let (_, prepared) = projection.advance(&chat, &thread, &answer_effect, &answered_state)?;

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
        let (_, prepared) = projection.advance(&chat, &thread, &effect, &state)?;
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
            projection.advance(&chat, &thread, &write.effect, &write.checkpoint.state)?;
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
