//! 一个 Native 会话的共享数据所有者；弱注册不延长冷会话的寿命。
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use std::sync::{Arc, Mutex};

use pl_core::chat::{Session, TimelineEpoch};

use super::runtime::thread_observation::publication::ConversationSource;
use super::runtime::thread_observation::{
    RetainedProjection, publication::ConversationPublication,
};
use super::storage::history::HistoryStore;
use super::storage::thread_writer::{HistoryChannel, ThreadStorageBinding};
use super::thread_projection::presentation::{DisplayMemberCut, PresentationCut};
use super::thread_projection::{LiveProjection, PreparedEffect};

pub(in crate::studio) enum ReadRequest<'a> {
    Current,
    Display {
        before: Option<u64>,
        limit: usize,
        after: Option<u64>,
        pending: usize,
    },
    Members {
        block: &'a str,
        before: Option<u64>,
        limit: usize,
    },
}

pub(in crate::studio) enum ReadCut {
    Ready {
        source: Arc<ConversationSource>,
        display: Option<PresentationCut>,
        members: Option<DisplayMemberCut>,
    },
    Cold(Option<super::storage::history::ConversationSnapshot>),
}

type Initialization = Shared<BoxFuture<'static, Result<(), Arc<anyhow::Error>>>>;
type Initializer =
    Arc<dyn Fn() -> BoxFuture<'static, anyhow::Result<RetainedProjection>> + Send + Sync>;
enum Mode {
    Cold,
    Initializing {
        operation: Initialization,
    },
    Ready,
    Faulted {
        error: Arc<anyhow::Error>,
        factory: Initializer,
    },
}

pub(crate) struct ConversationStore {
    lifecycle: tokio::sync::Mutex<()>,
    mode: Mutex<Mode>,
    driver_taken: std::sync::atomic::AtomicBool,
    history: HistoryStore,
    session: Session,
    pub(in crate::studio) publication: Arc<ConversationPublication>,
    retained: Mutex<Option<RetainedProjection>>,
    mutation: Mutex<()>,
    database_id: std::sync::OnceLock<String>,
    execution: Mutex<(usize, Option<usize>)>,
    channel: Mutex<std::sync::Weak<HistoryChannel>>,
    #[cfg(test)]
    last_locked_us: std::sync::atomic::AtomicU64,
    #[cfg(test)]
    before_meta: tokio::sync::Mutex<
        Option<(
            tokio::sync::oneshot::Sender<()>,
            tokio::sync::oneshot::Receiver<()>,
        )>,
    >,
}

impl std::fmt::Debug for ConversationStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationStore").finish_non_exhaustive()
    }
}

impl ConversationStore {
    /// 初始化操作归 Store 保留；取消一个等待者不会取消原恢复操作。
    pub(in crate::studio) async fn initialize_projection(
        self: &Arc<Self>,
        factory: Initializer,
    ) -> anyhow::Result<()> {
        let operation = {
            let _gate = self.lifecycle.lock().await;
            let mut mode = self
                .mode
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Mode::Ready = &*mode {
                return Ok(());
            }
            if let Mode::Initializing { operation, .. } = &*mode {
                operation.clone()
            } else {
                let factory = match &*mode {
                    Mode::Faulted { factory, .. } => factory.clone(),
                    Mode::Cold => factory,
                    Mode::Ready | Mode::Initializing { .. } => {
                        unreachable!("handled initialized modes")
                    }
                };
                let weak = Arc::downgrade(self);
                let retry = factory.clone();
                let initializer = factory.clone();
                let operation = async move {
                    let result = initializer().await;
                    let store = weak.upgrade().ok_or_else(|| {
                        Arc::new(anyhow::anyhow!("conversation closed during initialization"))
                    })?;
                    let _gate = store.lifecycle.lock().await;
                    let result = result.and_then(|mut retained| {
                        store
                            .publication
                            .bind_presentation(retained.projection.presentation());
                        let baseline = retained
                            .baseline
                            .take()
                            .map(|current| {
                                store.publication.prepare(
                                    &store.session,
                                    store.session.head_seq(),
                                    current,
                                )
                            })
                            .transpose()?;
                        Ok((retained, baseline))
                    });
                    match result {
                        Ok((retained, baseline)) => {
                            if let Some(baseline) = baseline {
                                store.publication.apply(baseline);
                            }
                            *store
                                .retained
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner) =
                                Some(retained);
                            *store
                                .mode
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner) = Mode::Ready;
                            Ok(())
                        }
                        Err(error) => {
                            let error = Arc::new(error);
                            *store
                                .mode
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner) =
                                Mode::Faulted {
                                    error: error.clone(),
                                    factory: retry,
                                };
                            Err(error)
                        }
                    }
                }
                .boxed()
                .shared();
                *mode = Mode::Initializing {
                    operation: operation.clone(),
                };
                operation
            }
        };
        operation
            .await
            .map_err(crate::error_mapping::shared_runtime_error)
    }

    async fn wait_initialization(&self) -> anyhow::Result<()> {
        let pending = {
            let mode = self
                .mode
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match &*mode {
                Mode::Initializing { operation, .. } => Some(operation.clone()),
                Mode::Faulted { error, .. } => {
                    return Err(crate::error_mapping::shared_runtime_error(error.clone()));
                }
                Mode::Cold | Mode::Ready => None,
            }
        };
        if let Some(pending) = pending {
            pending
                .await
                .map_err(crate::error_mapping::shared_runtime_error)?;
        }
        Ok(())
    }

    pub(crate) fn open_reader(self: &Arc<Self>) -> ConversationReadHandle {
        ConversationReadHandle(self.clone())
    }
    pub(crate) fn new(history: HistoryStore) -> anyhow::Result<Arc<Self>> {
        let session = Session::new(
            history.clone(),
            TimelineEpoch::new(super::ids::new_id("timeline"))?,
        );
        Ok(Arc::new(Self {
            lifecycle: tokio::sync::Mutex::new(()),
            mode: Mutex::new(Mode::Cold),
            driver_taken: std::sync::atomic::AtomicBool::new(false),
            history,
            session,
            publication: Arc::new(ConversationPublication::new()),
            retained: Mutex::new(None),
            mutation: Mutex::new(()),
            database_id: std::sync::OnceLock::new(),
            execution: Mutex::new((0, None)),
            channel: Mutex::new(std::sync::Weak::new()),
            #[cfg(test)]
            last_locked_us: std::sync::atomic::AtomicU64::new(0),
            #[cfg(test)]
            before_meta: tokio::sync::Mutex::new(None),
        }))
    }

    pub(crate) fn session(&self) -> &Session {
        &self.session
    }

    pub(in crate::studio) fn take_projection(&self) -> anyhow::Result<Option<RetainedProjection>> {
        anyhow::ensure!(
            !self
                .driver_taken
                .swap(true, std::sync::atomic::Ordering::AcqRel),
            "conversation already has an execution driver"
        );
        Ok(self
            .retained
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take())
    }

    pub(in crate::studio) fn retain_projection(&self, retained: Option<RetainedProjection>) {
        let mut slot = self
            .retained
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        assert!(
            slot.is_none(),
            "conversation already has a projection owner"
        );
        *slot = retained;
        self.driver_taken
            .store(false, std::sync::atomic::Ordering::Release);
    }

    pub(in crate::studio) fn admit_prepared(
        &self,
        binding: &ThreadStorageBinding,
        channel: &HistoryChannel,
        retained: &mut RetainedProjection,
    ) -> anyhow::Result<Arc<PreparedEffect>> {
        let admission_started = std::time::Instant::now();
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let locked = std::time::Instant::now();
        anyhow::ensure!(
            matches!(
                *self
                    .mode
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner),
                Mode::Ready
            ),
            "conversation is not ready for admission"
        );
        anyhow::ensure!(
            std::ptr::eq(self, binding.conversation.as_ref())
                && std::ptr::eq(channel, binding.channel.as_ref())
                && self
                    .execution
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .1
                    == Some(binding.incarnation),
            "stale conversation execution binding"
        );
        let pending = retained
            .pending
            .as_mut()
            .ok_or_else(|| anyhow::anyhow!("no retained handoff"))?;
        anyhow::ensure!(
            pending.write.effect.thread_id == self.history.thread_id()
                && pending.prepared.sequence == pending.write.effect.sequence
                && pending.prepared.current.projection().source_effect_seq
                    == pending.prepared.sequence
                && pending.prepared.accounting.thread_id == self.history.thread_id(),
            "prepared effect does not match the accepted original"
        );
        let Some(drafts) = pending.prepared.completion_drafts.as_ref() else {
            anyhow::ensure!(
                pending.admitted,
                "unadmitted effect has no fresh publication plan"
            );
            return Ok(pending.prepared.clone());
        };
        let plan = self.session.prepare_fresh(drafts.clone())?;
        let (display_state, display) = retained
            .projection
            .plan_display(&pending.prepared, plan.records())?;
        let source = pending
            .publishes_current()
            .then_some(&pending.prepared)
            .and_then(|prepared| prepared.current_state.as_ref())
            .map(|current| {
                self.publication
                    .prepare(&self.session, plan.head_seq(), current.clone())
            })
            .transpose()?;
        let mut prepared = pending.prepared.as_ref().clone();
        LiveProjection::complete_prepared(&mut prepared, plan.records().clone(), display);
        prepared.current_state = None;
        let prepared = Arc::new(prepared);
        channel.set_projection_retention(super::storage::thread_writer::ProjectionRetention {
            resident_bytes: retained
                .projection
                .retained_bytes()
                .saturating_add(pending.extra_retained_bytes()),
            pending: Some(super::storage::thread_writer::PendingProjectionRetention {
                sequence: prepared.sequence,
                prepared_bytes: prepared.retained_bytes(),
            }),
        })?;
        channel.prepare_with(Some(&pending.write), prepared.clone(), || {
            self.session.admit_prepared(plan, || {
                retained.projection.apply_display(display_state);
                if let Some(source) = source {
                    self.publication.apply(source);
                }
            })?;
            Ok(())
        })?;
        for item in prepared.completions.iter() {
            channel
                .order_index()
                .mark_completion(&item.header.item_id, true);
        }
        pending.prepared = prepared.clone();
        pending.admitted = true;
        #[cfg(test)]
        self.last_locked_us.store(
            locked.elapsed().as_micros() as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        tracing::debug!(target: "conversation_work", source_effect_seq = prepared.sequence,
            admission_wait_us = locked.duration_since(admission_started).as_micros() as u64,
            admission_locked_us = locked.elapsed().as_micros() as u64,
            completion_records = prepared.completions.len(),
            prepared_bytes = prepared.retained_bytes(),
            queued_bytes = channel.subscribe().borrow().queued_bytes,
            "conversation memory admission");
        Ok(prepared)
    }

    #[cfg(test)]
    pub(in crate::studio) fn last_admission_locked_us(&self) -> u64 {
        self.last_locked_us
            .load(std::sync::atomic::Ordering::Relaxed)
    }

    pub(crate) async fn attach_execution(
        &self,
        binding: &ThreadStorageBinding,
    ) -> anyhow::Result<()> {
        anyhow::ensure!(
            std::ptr::eq(self, binding.conversation.as_ref()),
            "binding belongs to another conversation"
        );
        self.session.initialize().await?;
        let database = self
            .history
            .conversation_database_id()
            .await?
            .ok_or_else(|| anyhow::anyhow!("execution database is not initialized"))?;
        anyhow::ensure!(
            self.database_id
                .get()
                .is_none_or(|current| current == &database),
            pl_core::chat::ChatError::StaleContent
        );
        self.database_id.get_or_init(|| database);
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut execution = self
            .execution
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        anyhow::ensure!(
            execution.1 == Some(binding.incarnation)
                || (execution.1.is_none() && binding.incarnation > execution.0),
            "execution binding is stale or another execution is attached"
        );
        *execution = (binding.incarnation, Some(binding.incarnation));
        *self
            .channel
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Arc::downgrade(&binding.channel);
        Ok(())
    }

    pub(crate) fn detach_execution(&self, binding: &ThreadStorageBinding) {
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut execution = self
            .execution
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if execution.1 == Some(binding.incarnation) {
            execution.1 = None;
            self.publication.retire_execution();
        }
    }

    #[cfg(test)]
    pub(in crate::studio) fn retire_test_execution(&self) {
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.publication.retire_execution();
    }

    pub(in crate::studio) fn confirm_committed(
        &self,
        committed: &super::storage::thread_writer::CommittedBatch,
    ) -> anyhow::Result<()> {
        let _mutation = self
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        anyhow::ensure!(
            self.database_id
                .get()
                .is_none_or(|database| database == committed.database_id()),
            "committed database identity differs"
        );
        if let Some(through) = committed.append_seq() {
            self.session.confirm_durable(through)?;
        }
        if let Some(source) = self.publication.current() {
            let mut presentation = source
                .presentation
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some((effect, frontier, last)) = committed.display() {
                anyhow::ensure!(
                    effect <= committed.effect(),
                    "display commit exceeds its batch"
                );
                presentation.confirm_cut(effect, frontier, last)?;
            }
        }
        self.database_id
            .get_or_init(|| committed.database_id().to_owned());
        Ok(())
    }
}

impl Drop for ConversationStore {
    fn drop(&mut self) {
        // 先释放投影引用的身份索引，再发布最终预算，避免残留已释放索引的旧计数。
        drop(
            self.retained
                .get_mut()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .take(),
        );
        if let Some(channel) = self
            .channel
            .get_mut()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .upgrade()
        {
            channel.release_projection_retention();
        }
    }
}

#[derive(Clone)]
pub(crate) struct ConversationReadHandle(Arc<ConversationStore>);

impl ConversationReadHandle {
    pub(in crate::studio) async fn capture(
        &self,
        request: ReadRequest<'_>,
    ) -> anyhow::Result<ReadCut> {
        loop {
            self.0.wait_initialization().await?;
            if let Some(cut) = self.capture_ready(&request) {
                return Ok(cut);
            }
            // BEGIN 在 gate 外取得连接。首次 meta SELECT 留在 gate 内建立真实快照。
            let mut snapshot = self.0.history.conversation_snapshot().await?;
            let gate = self.0.lifecycle.lock().await;
            let initializing = {
                let mode = self
                    .0
                    .mode
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                match &*mode {
                    Mode::Faulted { error, .. } => {
                        return Err(crate::error_mapping::shared_runtime_error(error.clone()));
                    }
                    Mode::Initializing { .. } => true,
                    Mode::Cold | Mode::Ready => false,
                }
            };
            if initializing {
                drop(gate);
                drop(snapshot);
                continue;
            }
            if let Some(cut) = self.capture_ready(&request) {
                return Ok(cut);
            }
            #[cfg(test)]
            if let Some((entered, release)) = self.0.before_meta.lock().await.take() {
                let _ = entered.send(());
                let _ = release.await;
            }
            if let Some(snapshot) = &mut snapshot {
                snapshot.pin(self.0.history.thread_id()).await?;
                anyhow::ensure!(
                    self.0
                        .database_id
                        .get()
                        .is_none_or(|database| database == &snapshot.database_id),
                    pl_core::chat::ChatError::StaleContent
                );
                self.0
                    .database_id
                    .get_or_init(|| snapshot.database_id.clone());
            }
            drop(gate);
            return Ok(ReadCut::Cold(snapshot));
        }
    }

    pub(in crate::studio) async fn current_state(
        &self,
    ) -> anyhow::Result<Option<Arc<super::thread_projection::CurrentState>>> {
        match self.capture(ReadRequest::Current).await? {
            ReadCut::Ready { source, .. } => Ok(Some(source.current.clone())),
            ReadCut::Cold(Some(snapshot)) => Ok(Some(snapshot.current_state().await?)),
            ReadCut::Cold(None) => Ok(None),
        }
    }

    fn capture_ready(&self, request: &ReadRequest<'_>) -> Option<ReadCut> {
        let _mutation = self
            .0
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let source = self.0.publication.current()?;
        let owner = source
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (display, members) = match request {
            ReadRequest::Current => (None, None),
            ReadRequest::Display {
                before,
                limit,
                after,
                pending,
            } => (Some(owner.capture(*before, *limit, *after, *pending)), None),
            ReadRequest::Members {
                block,
                before,
                limit,
            } => (None, owner.member_cut(block, *before, *limit)),
        };
        drop(owner);
        Some(ReadCut::Ready {
            source,
            display,
            members,
        })
    }

    pub(crate) fn session(&self) -> &Session {
        self.0.session()
    }

    pub(in crate::studio) fn identity_matches(&self, database: Option<&str>) -> bool {
        self.0.database_id.get().map(String::as_str) == database
    }

    pub(in crate::studio) fn bind_database(&self, database: Option<&str>) -> anyhow::Result<()> {
        anyhow::ensure!(
            self.0
                .database_id
                .get()
                .is_none_or(|current| Some(current.as_str()) == database),
            pl_core::chat::ChatError::StaleContent
        );
        if let Some(database) = database {
            self.0.database_id.get_or_init(|| database.to_owned());
        }
        Ok(())
    }
    pub(crate) async fn wait_initialization(&self) -> anyhow::Result<()> {
        self.0.wait_initialization().await
    }

    pub(in crate::studio) fn current_conversation(
        &self,
    ) -> Option<Arc<super::runtime::thread_observation::publication::ConversationSource>> {
        let _mutation = self
            .0
            .mutation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.0.publication.current()
    }

    pub(in crate::studio) fn content_changes(&self) -> tokio::sync::watch::Receiver<u64> {
        self.0.publication.content_changes()
    }

    pub(in crate::studio) fn subscribe_progress(
        &self,
    ) -> tokio::sync::watch::Receiver<
        Option<Arc<super::runtime::thread_observation::publication::ConversationSource>>,
    > {
        self.0.publication.subscribe_progress()
    }
}

#[cfg(test)]
mod tests {
    use super::super::storage::coordinator::ThreadPersistenceCoordinator;
    use super::*;
    use sea_orm::{ConnectionTrait, Database};

    #[tokio::test]
    async fn concurrent_passive_opens_share_a_weak_store_without_creating_history()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("absent/history.sqlite");
        let history = HistoryStore::open(&path, "passive").await?;
        let registry = ThreadPersistenceCoordinator::default();
        let (first, second) = tokio::join!(
            async {
                Ok::<_, anyhow::Error>(registry.install_conversation_store(
                    "passive",
                    ConversationStore::new(history.clone())?,
                ))
            },
            async {
                Ok::<_, anyhow::Error>(registry.install_conversation_store(
                    "passive",
                    ConversationStore::new(history.clone())?,
                ))
            },
        );
        let (first, second) = (first?, second?);
        assert!(Arc::ptr_eq(&first, &second));
        let reader = first.open_reader();
        assert!(matches!(
            reader.capture(ReadRequest::Current).await?,
            ReadCut::Cold(None)
        ));
        assert_eq!(registry.snapshot().pending_commits, 0);
        assert_eq!(history.reader_calls(), 1);
        println!("COLD_EMPTY_READ_PORT_CALLS=1 COLD_PAGE_ROWS=0");
        assert!(!path.try_exists()?);
        let weak = Arc::downgrade(&first);
        drop(first);
        drop(second);
        assert!(weak.upgrade().is_some());
        drop(reader);
        assert!(weak.upgrade().is_none());
        assert!(registry.conversation_store("passive").is_none());
        Ok(())
    }

    #[tokio::test]
    async fn cold_meta_cut_precedes_attach_and_page_read_does_not_hold_the_gate()
    -> anyhow::Result<()> {
        for before_select in [true, false] {
            let directory = tempfile::tempdir()?;
            let path = directory.path().join("history.sqlite");
            let history = HistoryStore::open(&path, "cold-race").await?;
            history.prepare_write().await?;
            let store = ConversationStore::new(history)?;
            let reader = store.open_reader();
            let (entered, waiting) = tokio::sync::oneshot::channel();
            let (release, resume) = tokio::sync::oneshot::channel();
            if before_select {
                *store.before_meta.lock().await = Some((entered, resume));
            }
            let read = tokio::spawn(async move { reader.capture(ReadRequest::Current).await });
            let factory = Arc::new({
                let path = path.clone();
                move || {
                    let path = path.clone();
                    Box::pin(async move {
                        let db = Database::connect(format!("sqlite://{}?mode=rw", path.display()))
                            .await?;
                        db.execute_unprepared(
                            "UPDATE history_meta SET applied_write_seq=1 WHERE id=1",
                        )
                        .await?;
                        db.close().await?;
                        anyhow::bail!("controlled initialization failure")
                    }) as BoxFuture<'static, anyhow::Result<RetainedProjection>>
                }
            });
            if before_select {
                waiting.await?;
            }
            let mut initializing = Box::pin(store.initialize_projection(factory));
            if before_select {
                assert!(futures::poll!(initializing.as_mut()).is_pending());
                release.send(()).ok();
            }
            let ReadCut::Cold(Some(snapshot)) = read.await?? else {
                panic!("expected pinned cold snapshot")
            };
            // 整页物化尚未开始；初始化必须能取得 gate 并完成原结果。
            let failed =
                tokio::time::timeout(std::time::Duration::from_secs(3), initializing).await?;
            assert!(failed.is_err());
            let cold = snapshot.presentation_baseline().await?;
            assert_eq!(
                cold.current.source_effect_seq, 0,
                "page mixed the later metadata into its pinned snapshot"
            );
            assert!(
                store
                    .open_reader()
                    .capture(ReadRequest::Current)
                    .await
                    .is_err(),
                "failed initialization appeared as empty success"
            );
        }
        Ok(())
    }
}
