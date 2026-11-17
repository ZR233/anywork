//! Studio 订阅由作用域保留原资源，取消回执等待真实 producer 和 sink 结束。

pub(crate) mod close_failures;
pub(crate) mod error;
pub(crate) mod factory;
pub(crate) mod product_topic;
pub(crate) mod shutdown;
pub(crate) mod startup;
pub(crate) mod task;

pub use product_topic::create_product_topic_subscription;
pub use shutdown::subscribe_shutdown_progress;
pub use startup::subscribe_startup_progress;

use std::sync::{Mutex as SyncMutex, OnceLock};
use std::time::Instant;

use pl_lifecycle::{Managed, ManagedResource, ScopeOwner};
use tokio::sync::{Mutex, mpsc};
use tokio_util::sync::CancellationToken;

use crate::api::studio::handlers::StartupFrame;
use crate::api::studio::types::{
    BridgeError, BridgeProductTopicStreamEnvelope, BridgeShutdownIssue,
};
use close_failures::CloseFailures;
use pl_studio_runtime::StudioShutdownProgress;
use task::OwnedTaskSlot;

/// 一个独占受管句柄；丢弃时请求取消，成功回执表示原任务已结束。
pub struct BridgeEventSubscription {
    inner: Managed<BridgeSubscriptionInner>,
    // 启动观察的子作用域与对应句柄同寿命，父作用域保留未完成或失败的子项。
    _scope: Option<ScopeOwner<BridgeError>>,
}

pub(crate) struct BridgeSubscriptionInner {
    kind: BridgeSubscriptionKind,
    cancel: CancellationToken,
    producer_task: Mutex<OwnedTaskSlot>,
    sink_task: Mutex<OwnedTaskSlot>,
    product_topic_receiver: Mutex<Option<mpsc::Receiver<BridgeProductTopicStreamEnvelope>>>,
    shutdown_receiver: Mutex<Option<tokio::sync::broadcast::Receiver<StudioShutdownProgress>>>,
    startup_receiver: Mutex<Option<tokio::sync::watch::Receiver<StartupFrame>>>,
}

#[derive(Debug, Clone)]
pub(crate) enum BridgeSubscriptionKind {
    ProductTopic {
        topic: crate::api::studio::types::BridgeProductTopic,
    },
    Shutdown,
    Startup {
        attempt: u64,
    },
}

impl BridgeSubscriptionInner {
    /// 同一槽位裁决任务安装与关闭；取得槽后不再跨等待安装任务。
    async fn attach_sink(
        &self,
        work: impl std::future::Future<Output = Result<(), BridgeError>> + Send + 'static,
    ) -> bool {
        let mut slot = self.sink_task.lock().await;
        if self.cancel.is_cancelled() {
            return false;
        }
        slot.task = Some(tokio::spawn(work));
        true
    }
}

impl ManagedResource for BridgeSubscriptionInner {
    type Error = BridgeError;

    fn request_close(&self) {
        match &self.kind {
            BridgeSubscriptionKind::ProductTopic { topic } => {
                tracing::trace!(?topic, "closing product topic")
            }
            BridgeSubscriptionKind::Startup { attempt } => {
                tracing::trace!(attempt, "closing startup progress")
            }
            BridgeSubscriptionKind::Shutdown => tracing::trace!("closing shutdown progress"),
        }
        self.cancel.cancel();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        self.request_close();
        let (producer, sink) = tokio::join!(
            async {
                self.producer_task
                    .lock()
                    .await
                    .join("subscription producer task failed")
                    .await
            },
            async {
                self.sink_task
                    .lock()
                    .await
                    .join("subscription sink task failed")
                    .await
            },
        );
        let mut failures = CloseFailures::default();
        if let Err(error) = producer {
            failures.record("producer", error);
        }
        if let Err(error) = sink {
            failures.record("sink", error);
        }
        failures.outcome().map_or(Ok(()), Err)
    }
}

impl BridgeEventSubscription {
    /// 请求取消并等待原订阅任务真正结束；失败保留原句柄以供显式重试。
    pub async fn cancel(&self) -> Result<(), BridgeError> {
        self.inner.retry_close().await.map_err(error::close_error)
    }
}

/// 有界队列满时，取消也必须唤醒发送方。
pub(crate) async fn send_or_cancel<T>(
    cancel: &CancellationToken,
    sender: &mpsc::Sender<T>,
    value: T,
) -> bool {
    tokio::select! {
        _ = cancel.cancelled() => false,
        result = sender.send(value) => result.is_ok(),
    }
}

struct StartupScopes {
    closed: bool,
    attempt: Option<u64>,
    owner: Option<ScopeOwner<BridgeError>>,
}

impl StartupScopes {
    fn prepare(&mut self, attempt: u64) -> Option<ScopeOwner<BridgeError>> {
        self.attempt = Some(attempt);
        self.owner.take()
    }

    fn child(
        &mut self,
        root: &ScopeOwner<BridgeError>,
        attempt: u64,
    ) -> Result<ScopeOwner<BridgeError>, BridgeError> {
        if self.closed {
            return Err(BridgeError::runtime_stopped());
        }
        if self.attempt != Some(attempt) {
            return Err(BridgeError::invalid_argument(
                "startup attempt is no longer active",
            ));
        }
        if self.owner.is_none() {
            self.owner = Some(
                root.handle()
                    .child("startup-attempt")
                    .map_err(|_| BridgeError::runtime_stopped())?,
            );
        }
        self.owner
            .as_ref()
            .expect("attempt owner was installed")
            .handle()
            .child("startup-observer")
            .map_err(|_| BridgeError::runtime_stopped())
    }
}

static STARTUP_SCOPES: SyncMutex<StartupScopes> = SyncMutex::new(StartupScopes {
    closed: false,
    attempt: None,
    owner: None,
});
static STARTUP_ROOT: OnceLock<ScopeOwner<BridgeError>> = OnceLock::new();

/// 与启动令牌的发布同步更新；旧尝试在新令牌可见前封门。
pub(crate) fn prepare_startup_scope(attempt: u64) {
    let previous = STARTUP_SCOPES
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .prepare(attempt);
    drop(previous);
}

fn startup_child_scope(attempt: u64) -> Result<ScopeOwner<BridgeError>, BridgeError> {
    let mut scopes = STARTUP_SCOPES
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    if scopes.closed {
        return Err(BridgeError::runtime_stopped());
    }
    if scopes.attempt != Some(attempt) {
        return Err(BridgeError::invalid_argument(
            "startup attempt is no longer active",
        ));
    }
    let root =
        STARTUP_ROOT.get_or_init(|| ScopeOwner::new("startup", tokio::runtime::Handle::current()));
    scopes.child(root, attempt)
}

/// 与启动令牌一起同步封门，不依赖 bridge 是否已经安装。
pub(crate) fn close_startup_scope() {
    let mut scopes = STARTUP_SCOPES
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    scopes.closed = true;
    drop(scopes);
    if let Some(root) = STARTUP_ROOT.get() {
        root.request_close();
    }
}

pub(crate) async fn wait_startup_scope(deadline: Instant) -> Vec<BridgeShutdownIssue> {
    match STARTUP_ROOT.get() {
        Some(root) => error::shutdown_issues(
            root.retry_cleanup(tokio::time::Instant::from_std(deadline))
                .await,
        ),
        None => Vec::new(),
    }
}

fn shutdown_progress_scope() -> &'static ScopeOwner<BridgeError> {
    static SCOPE: OnceLock<ScopeOwner<BridgeError>> = OnceLock::new();
    SCOPE.get_or_init(|| ScopeOwner::new("shutdown-progress", tokio::runtime::Handle::current()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::poll;
    use std::task::Poll;
    use tokio::sync::oneshot;

    async fn subscription(scope: &ScopeOwner<BridgeError>) -> Managed<BridgeSubscriptionInner> {
        scope
            .handle()
            .open("test", |cancel| async move {
                Ok(BridgeSubscriptionInner {
                    kind: BridgeSubscriptionKind::Shutdown,
                    cancel,
                    producer_task: Mutex::new(OwnedTaskSlot::default()),
                    sink_task: Mutex::new(OwnedTaskSlot::default()),
                    product_topic_receiver: Mutex::new(None),
                    shutdown_receiver: Mutex::new(None),
                    startup_receiver: Mutex::new(None),
                })
            })
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn new_startup_attempt_seals_even_unconsumed_previous_observers() {
        let root = ScopeOwner::new("startup-test", tokio::runtime::Handle::current());
        let mut scopes = StartupScopes {
            closed: false,
            attempt: None,
            owner: None,
        };
        drop(scopes.prepare(1));
        let old_scope = scopes.child(&root, 1).unwrap();
        let old = subscription(&old_scope).await;
        assert!(!old.get().cancel.is_cancelled());

        drop(scopes.prepare(2));
        assert!(old.get().cancel.is_cancelled());
        assert!(scopes.child(&root, 1).is_err());
        let new_scope = scopes.child(&root, 2).unwrap();
        let new = subscription(&new_scope).await;
        assert!(!new.get().cancel.is_cancelled());
        old.close().await.unwrap();
        new.close().await.unwrap();
    }

    #[tokio::test]
    async fn sink_attach_and_close_share_the_same_gate() {
        let scope = ScopeOwner::new("test", tokio::runtime::Handle::current());
        let managed = subscription(&scope).await;
        let guard = managed.get().sink_task.lock().await;
        let mut attaching = Box::pin(managed.get().attach_sink(async { Ok(()) }));
        assert!(matches!(poll!(attaching.as_mut()), Poll::Pending));
        managed.request_close();
        drop(guard);
        assert!(!attaching.await);
        managed.close().await.unwrap();

        let managed = subscription(&scope).await;
        let (started, entered) = oneshot::channel();
        let (release, held) = oneshot::channel();
        assert!(
            managed
                .get()
                .attach_sink(async move {
                    let _ = started.send(());
                    let _ = held.await;
                    Ok(())
                })
                .await
        );
        entered.await.unwrap();
        managed.request_close();
        let mut closing = Box::pin(managed.close());
        assert!(matches!(poll!(closing.as_mut()), Poll::Pending));
        release.send(()).unwrap();
        closing.await.unwrap();
    }

    #[tokio::test]
    async fn full_queue_send_is_woken_by_close() {
        let cancel = CancellationToken::new();
        let (sender, mut receiver) = mpsc::channel(1);
        sender.send(1).await.unwrap();
        let mut blocked = Box::pin(send_or_cancel(&cancel, &sender, 2));
        assert!(matches!(poll!(blocked.as_mut()), Poll::Pending));
        cancel.cancel();
        assert!(!blocked.await);
        assert_eq!(receiver.recv().await, Some(1));
    }

    #[tokio::test]
    async fn terminal_sink_failure_survives_cleanup_retry() {
        let scope = ScopeOwner::new("test", tokio::runtime::Handle::current());
        let managed = subscription(&scope).await;
        let failure: BridgeError = pl_studio_runtime::StudioError::new(
            pl_studio_runtime::StudioErrorCode::Internal,
            "sink failed",
            false,
        )
        .into();
        let original = failure.clone();
        assert!(managed.get().attach_sink(async move { Err(failure) }).await);
        assert_eq!(
            error::close_error(managed.close().await.unwrap_err()),
            original
        );
        assert_eq!(
            error::close_error(managed.retry_close().await.unwrap_err()),
            original
        );
    }
}
