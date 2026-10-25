//! One supervised transport owns each feed. There is no extra pump, payload queue or task registry.
use std::collections::BTreeMap;
use std::future::Future;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use futures::FutureExt;
use pl_protocol::products::identity::{ProductFeedCloseReason, ProductResyncReason};
use pl_protocol::studio::StudioErrorCode;
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, StudioShutdownIssue};
use tokio::sync::{Notify, broadcast, watch};
use tokio_util::sync::CancellationToken;

use super::super::StudioRuntime;
use super::super::background_task::BackgroundTask;
use super::super::models::delivery_window::DeliveryWindow;
use super::capture;
use super::frames::{AgentFrames, DirectoryFrames, FrameError, ProjectFrames, ThreadFrames};
use super::source::{DirectoryBinding, DirectoryOwner, DirectorySnapshot};
use super::*;

struct Window {
    delivery: DeliveryWindow<DirectorySnapshot>,
    previous: Option<Arc<DirectorySnapshot>>,
    lagged: bool,
    // These are the same task objects registered in ReadCalls, not a second pool or permit.
    queries: BTreeMap<String, Arc<BackgroundTask>>,
    issues: BTreeMap<String, FeedCloseIssue>,
}
struct Updates {
    topics: Vec<broadcast::Receiver<crate::StudioProductEventEnvelope>>,
    publication: watch::Receiver<()>,
}
struct DirectoryFeed {
    runtime: StudioRuntime,
    directory: Arc<DirectoryOwner>,
    identity: ProductFeedIdentity,
    cancel: CancellationToken,
    credit: Notify,
    updates: tokio::sync::Mutex<Updates>,
    window: Mutex<Window>,
}

pub struct StudioProjectDirectoryFeed {
    core: Arc<DirectoryFeed>,
}
pub struct StudioAgentDirectoryFeed {
    core: Arc<DirectoryFeed>,
}
pub struct StudioThreadDirectoryFeed {
    core: Arc<DirectoryFeed>,
}

impl StudioRuntime {
    pub fn open_project_directory(
        &self,
    ) -> impl Future<Output = Result<StudioProjectDirectoryFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Ok(StudioProjectDirectoryFeed {
                core: DirectoryFeed::open(runtime, DirectoryBinding::Projects).await?,
            })
        })
    }
    pub fn open_agent_directory(
        &self,
    ) -> impl Future<Output = Result<StudioAgentDirectoryFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Ok(StudioAgentDirectoryFeed {
                core: DirectoryFeed::open(runtime, DirectoryBinding::Agents).await?,
            })
        })
    }
    pub fn open_thread_directory(
        &self,
        scope: ThreadDirectoryScope,
    ) -> impl Future<Output = Result<StudioThreadDirectoryFeed>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            Ok(StudioThreadDirectoryFeed {
                core: DirectoryFeed::open(runtime, DirectoryBinding::Threads(scope)).await?,
            })
        })
    }
}

impl DirectoryFeed {
    async fn open(runtime: StudioRuntime, binding: DirectoryBinding) -> Result<Arc<Self>> {
        let directory = runtime.workspace_source.directory(binding.clone())?;
        let events = &runtime.agent_facility.product_events;
        let mut topics = match &binding {
            DirectoryBinding::Projects => {
                vec![events.subscribe_topic(&crate::StudioProductTopic::ProjectDirectory)]
            }
            DirectoryBinding::Agents => {
                vec![events.subscribe_topic(&crate::StudioProductTopic::AgentDirectory)]
            }
            DirectoryBinding::Threads(_) => {
                vec![events.subscribe_topic(&crate::StudioProductTopic::ThreadDirectory)]
            }
        };
        if let DirectoryBinding::Threads(ThreadDirectoryScope::Query {
            query,
            include_pinned,
        }) = &binding
        {
            if query.search.is_some() {
                topics.push(events.subscribe_topic(&crate::StudioProductTopic::ProjectDirectory));
            }
            if *include_pinned && !query.archived {
                topics.push(events.subscribe_topic(&crate::StudioProductTopic::SettingsConfig));
            }
        }
        let publication = directory.subscribe();
        let cancel = CancellationToken::new();
        let snapshot = {
            let _gate = directory.capture_gate.lock().await;
            let captured = capture::capture(&runtime, &binding, None, &cancel).await?;
            directory.publish(&runtime.workspace_source, captured)?
        };
        let origin = runtime.workspace_source.origin();
        let feed = Arc::new(Self {
            identity: ProductFeedIdentity {
                feed_id: crate::studio::new_id("product-feed"),
                owner_epoch: origin.owner_epoch,
                incarnation: origin.incarnation,
                resource: binding.resource(),
            },
            runtime,
            directory,
            cancel,
            credit: Notify::new(),
            updates: tokio::sync::Mutex::new(Updates {
                topics,
                publication,
            }),
            window: Mutex::new(Window {
                delivery: DeliveryWindow::new(snapshot),
                previous: None,
                lagged: false,
                queries: BTreeMap::new(),
                issues: BTreeMap::new(),
            }),
        });
        feed.ensure_open()?;
        Ok(feed)
    }
    fn ensure_open(&self) -> Result<(), StudioError> {
        self.check_open(
            &self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }
    fn check_open(&self, window: &Window) -> Result<(), StudioError> {
        if window.delivery.closing
            || self.cancel.is_cancelled()
            || self.runtime.shutdown_committed()
        {
            return Err(super::cancelled());
        }
        self.runtime.workspace_source.ensure_open()
    }
    fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.delivery.claim("Workspace")
    }
    fn refresh(self: &Arc<Self>) -> impl Future<Output = Result<()>> + Send + 'static + use<> {
        self.query(|feed| async move {
            let _gate = feed.directory.capture_gate.lock().await;
            feed.ensure_open()?;
            if feed
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .lagged
            {
                return Ok(());
            }
            let previous = feed.directory.current();
            let capture = capture::capture(
                &feed.runtime,
                &feed.directory.binding,
                previous.as_ref(),
                &feed.cancel,
            )
            .await?;
            let window = feed
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            feed.check_open(&window)?;
            feed.directory
                .publish(&feed.runtime.workspace_source, capture)?;
            Ok(())
        })
    }
    /// Registration and the handle's close fence share the window guard. The original runtime
    /// task survives a cancelled waiter; the feed retains that exact task until it truly joins.
    fn query<T, F, G>(
        self: &Arc<Self>,
        read: G,
    ) -> impl Future<Output = Result<T>> + Send + 'static + use<T, F, G>
    where
        T: Send + 'static,
        F: Future<Output = Result<T>> + Send + 'static,
        G: FnOnce(Arc<Self>) -> F + Send + 'static,
    {
        let admitted = {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check_open(&window)
                .map_err(anyhow::Error::from)
                .and_then(|()| {
                    window.queries.retain(|_, task| !task.succeeded());
                    let call = self.runtime.read_calls.register(read(self.clone()))?;
                    window.queries.insert(call.id.clone(), call.task.clone());
                    Ok(call)
                })
        };
        async move { admitted?.wait().await }
    }
    async fn close(&self) -> FeedCloseReport {
        self.request_close();
        let tasks = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .queries
            .iter()
            .map(|(id, task)| (id.clone(), task.clone()))
            .collect::<Vec<_>>();
        let results = futures::future::join_all(tasks.iter().map(|(_, task)| task.join())).await;
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for ((id, _), result) in tasks.into_iter().zip(results) {
            if result.is_err() {
                window.issues.entry(id).or_insert_with(|| FeedCloseIssue {
                    diagnostic: StudioShutdownIssue {
                        stage: "workspaceFeedRead".into(),
                        code: "joinError".into(),
                        message: "An original Workspace feed query did not join successfully"
                            .into(),
                        retryable: false,
                        correlation_id: StudioError::internal().correlation_id,
                    },
                    recovery: CleanupRecovery::Terminal,
                });
            }
        }
        window.queries.retain(|_, task| !task.succeeded());
        let issues = window.issues.values().cloned().collect::<Vec<_>>();
        FeedCloseReport {
            feed_id: self.identity.feed_id.clone(),
            outcome: if issues.is_empty() {
                FeedCloseOutcome::Clean
            } else {
                FeedCloseOutcome::Unresolved { issues }
            },
        }
    }
    fn send_pending<F: DirectoryFrames>(
        &self,
        send: impl FnOnce(F::Frame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_open(&window)?;
        window.delivery.require_claimed("Workspace")?;
        if window.lagged {
            window.delivery.closing = true;
            let result = window.delivery.send_control(|| {
                send(F::resync(
                    self.identity.clone(),
                    ProductResyncReason::SourceLagged,
                ))
            });
            drop(window);
            self.cancel.cancel();
            result?;
            return Ok(true);
        }
        let snapshot = self.directory.current().ok_or_else(super::cancelled)?;
        if window
            .previous
            .as_ref()
            .is_some_and(|previous| previous.revision == snapshot.revision)
        {
            return Ok(false);
        }
        window.delivery.pending = Some(snapshot.clone());
        let event = match F::event(&self.identity, &snapshot, window.previous.as_deref()) {
            Ok(event) => event,
            Err(FrameError::Source(error)) => return Err(error),
            Err(FrameError::Resync(reason)) => {
                window.delivery.closing = true;
                let result = window
                    .delivery
                    .send_control(|| send(F::resync(self.identity.clone(), reason)));
                drop(window);
                self.cancel.cancel();
                result?;
                return Ok(true);
            }
        };
        let sent = self.runtime.workspace_source.send_exposing(&snapshot, || {
            window
                .delivery
                .deliver(
                    "Workspace",
                    |sequence, _| Ok(F::data(sequence, event)),
                    send,
                )
                .map(|value| value.is_some())
        })?;
        if sent {
            window.previous = Some(snapshot);
        }
        Ok(sent)
    }
    fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
        {
            let mut window = self
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.check_open(&window)?;
            window.delivery.ack_through(sequence, "Workspace")?;
        }
        self.credit.notify_one();
        Ok(())
    }
    async fn changed(&self) -> Result<(), StudioError> {
        let source_stop = self.runtime.workspace_source.stopped();
        tokio::select! { biased;
            () = self.cancelled() => Err(super::cancelled()),
            () = self.credit.notified() => Ok(()),
            result = async {
                let mut updates = self.updates.lock().await;
                let Updates { topics, publication } = &mut *updates;
                let topics = futures::future::select_all(topics.iter_mut().map(|receiver| receiver.recv().boxed()));
                tokio::select! { biased;
                    () = source_stop.cancelled() => Err(super::cancelled()),
                    result = publication.changed() => result.map_err(|_| super::cancelled()),
                    (result, _, _) = topics => match result {
                        Ok(_) => Ok(()),
                        Err(broadcast::error::RecvError::Lagged(_)) => {
                            self.window.lock().unwrap_or_else(std::sync::PoisonError::into_inner).lagged = true;
                            Ok(())
                        }
                        Err(broadcast::error::RecvError::Closed) => Err(StudioError::new(StudioErrorCode::Unavailable,
                            "The original Workspace directory source disappeared", true)),
                    },
                }
            } => result,
        }
    }
    fn request_close(&self) {
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .closing = true;
        self.cancel.cancel();
    }
    fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
        let cancel = self.cancel.clone();
        let source = self.runtime.workspace_source.stopped();
        let stop = self.runtime.shutdown_latch.clone();
        async move {
            tokio::select! { biased; () = cancel.cancelled() => {}, () = source.cancelled() => {}, () = stop.committed() => {} }
        }
    }
    fn send_closed<F: DirectoryFrames>(
        &self,
        send: impl FnOnce(F::Frame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        let reason = if self.runtime.shutdown_committed()
            || self.runtime.workspace_source.ensure_open().is_err()
        {
            ProductFeedCloseReason::RuntimeStopped
        } else {
            ProductFeedCloseReason::Requested
        };
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(F::closed(self.identity.clone(), reason)))
    }
    fn send_failure<F: DirectoryFrames>(
        &self,
        error: StudioError,
        send: impl FnOnce(F::Frame) -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        self.request_close();
        self.window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .delivery
            .send_control(|| send(F::failure(self.identity.clone(), error)))
    }
}

impl StudioThreadDirectoryFeed {
    /// Registered before awaiting. Cancellation never detaches a frontier query from ReadCalls.
    pub fn extend_window(
        &self,
        expected_collection: ProductCollectionRef,
        limit: u32,
    ) -> impl Future<Output = Result<ThreadDirectoryReadTarget>> + Send + 'static + use<> {
        self.core.query(move |feed| async move {
            let _gate = feed.directory.capture_gate.lock().await;
            let previous = {
                let window = feed
                    .window
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                feed.check_open(&window)?;
                if window
                    .previous
                    .as_ref()
                    .is_none_or(|previous| previous.collection != expected_collection)
                {
                    return Err(super::stale().into());
                }
                let previous = feed.directory.current().ok_or_else(super::cancelled)?;
                if previous.collection != expected_collection {
                    return Err(super::stale().into());
                }
                previous
            };
            let capture = capture::extend(&feed.runtime, &previous, limit, &feed.cancel).await?;
            let window = feed
                .window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            feed.check_open(&window)?;
            let snapshot = feed
                .directory
                .publish(&feed.runtime.workspace_source, capture)?;
            feed.runtime.workspace_source.expose_extension(&snapshot)?;
            Ok(ThreadDirectoryReadTarget {
                origin: feed.runtime.workspace_source.origin(),
                reference: ThreadDirectoryReadRef {
                    entry: snapshot.entry,
                    revision: snapshot.revision,
                },
            })
        })
    }
}

// Only the nominal frame parameter differs. All state transitions and ownership remain above.
macro_rules! feed_handle {
    ($handle:ident, $frames:ident, $frame:ident) => {
        impl $handle {
            pub fn identity(&self) -> ProductFeedIdentity {
                self.core.identity.clone()
            }
            pub fn ensure_open(&self) -> Result<(), StudioError> {
                self.core.ensure_open()
            }
            pub fn claim(&self) -> Result<(), StudioError> {
                self.core.claim()
            }
            pub fn refresh(&self) -> impl Future<Output = Result<()>> + Send + 'static + use<> {
                self.core.refresh()
            }
            pub fn send_pending(
                &self,
                send: impl FnOnce($frame) -> Result<(), StudioError>,
            ) -> Result<bool, StudioError> {
                self.core.send_pending::<$frames>(send)
            }
            pub fn ack_through(&self, sequence: u64) -> Result<(), StudioError> {
                self.core.ack_through(sequence)
            }
            pub async fn changed(&self) -> Result<(), StudioError> {
                self.core.changed().await
            }
            pub fn request_close(&self) {
                self.core.request_close();
            }
            pub async fn close(&self) -> FeedCloseReport {
                self.core.close().await
            }
            pub async fn retry_close(&self) -> FeedCloseReport {
                self.core.close().await
            }
            pub fn cancelled(&self) -> impl Future<Output = ()> + Send + 'static + use<> {
                self.core.cancelled()
            }
            pub fn is_closing(&self) -> bool {
                self.ensure_open().is_err()
            }
            pub fn send_closed(
                &self,
                send: impl FnOnce($frame) -> Result<(), StudioError>,
            ) -> Result<(), StudioError> {
                self.core.send_closed::<$frames>(send)
            }
            pub fn send_failure(
                &self,
                error: StudioError,
                send: impl FnOnce($frame) -> Result<(), StudioError>,
            ) -> Result<(), StudioError> {
                self.core.send_failure::<$frames>(error, send)
            }
        }
        impl Drop for $handle {
            fn drop(&mut self) {
                self.request_close();
            }
        }
    };
}
feed_handle!(
    StudioProjectDirectoryFeed,
    ProjectFrames,
    ProjectDirectoryFrame
);
feed_handle!(StudioAgentDirectoryFeed, AgentFrames, AgentDirectoryFrame);
feed_handle!(
    StudioThreadDirectoryFeed,
    ThreadFrames,
    ThreadDirectoryFrame
);
