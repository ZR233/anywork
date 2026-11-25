//! Runtime 纯观察任务的唯一所有者；业务任务与服务仍由原领域 owner 关闭。

use std::future::Future;
use std::sync::{Arc, OnceLock};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_lifecycle::{
    CancellationToken, CloseError, CloseReport, Managed, ManagedResource, OpenError, ScopeHandle,
    ScopeOwner,
};
use tokio::task::{JoinError, JoinHandle};

#[derive(Clone, Debug, thiserror::Error)]
#[error("observer task did not exit normally: {0}")]
pub(super) struct ObservationCleanupError(#[source] Arc<JoinError>);

/// 只取消等待通知的任务；已经开始的投影必须自然完成，绝不 abort。
pub(super) struct ObserverTask {
    cancellation: CancellationToken,
    completion: Shared<BoxFuture<'static, Result<(), Arc<JoinError>>>>,
}

impl ObserverTask {
    pub(super) fn new(cancellation: CancellationToken, task: JoinHandle<()>) -> Self {
        Self {
            cancellation,
            completion: async move { task.await.map_err(Arc::new) }.boxed().shared(),
        }
    }
}

impl ManagedResource for ObserverTask {
    type Error = ObservationCleanupError;

    fn request_close(&self) {
        self.cancellation.cancel();
    }

    async fn close(&self) -> Result<(), Self::Error> {
        // 协作取消返回 Ok；JoinError（含非预期 abort）始终保留同一原错误。
        self.completion
            .clone()
            .await
            .map_err(ObservationCleanupError)
    }
}

pub(super) type ObserverOpenResult =
    Result<Arc<Managed<ObserverTask>>, Arc<OpenError<ObservationCleanupError>>>;
type ObserverOpening = Shared<BoxFuture<'static, ObserverOpenResult>>;

/// 只缓存本 epoch 的同一次启动，不维护另一套关闭或重启状态。
#[derive(Default)]
struct ObserverStart(OnceLock<ObserverOpening>);

impl ObserverStart {
    fn get_or_init<F, Fut>(
        &self,
        scope: ScopeHandle<ObservationCleanupError>,
        label: &'static str,
        create: F,
    ) -> ObserverOpening
    where
        F: FnOnce(CancellationToken) -> Fut + Send + 'static,
        Fut: Future<Output = Result<ObserverTask, ObservationCleanupError>> + Send + 'static,
    {
        self.0
            .get_or_init(move || {
                // 构造不 poll，不订阅、不 spawn。未来只持弱 scope 和明确的窄依赖。
                async move {
                    scope
                        .open(label, create)
                        .await
                        .map(Arc::new)
                        .map_err(Arc::new)
                }
                .boxed()
                .shared()
            })
            .clone()
    }
}

#[derive(Clone, Copy)]
pub(super) enum RuntimeObserver {
    Profiles,
    Persistence,
    Lsp,
    ModelRefresh,
}

impl RuntimeObserver {
    pub(super) fn label(self) -> &'static str {
        match self {
            Self::Profiles => "agentProfiles",
            Self::Persistence => "persistenceObserver",
            Self::Lsp => "lspState",
            Self::ModelRefresh => "modelRefresh",
        }
    }
}

pub(super) struct RuntimeObservationOwner {
    root: ScopeOwner<ObservationCleanupError>,
    profiles: ScopeOwner<ObservationCleanupError>,
    persistence_projection: ScopeOwner<ObservationCleanupError>,
    lsp_projection: ScopeOwner<ObservationCleanupError>,
    model_refresh: ScopeOwner<ObservationCleanupError>,
    pub(super) model_catalog_publication: super::model_refresh::ModelCatalogPublication,
    profiles_start: ObserverStart,
    persistence_start: ObserverStart,
    lsp_start: ObserverStart,
    model_refresh_start: ObserverStart,
}

impl RuntimeObservationOwner {
    pub(super) fn new() -> Self {
        let root = ScopeOwner::new("runtimeObservers", pl_lifecycle::Handle::current());
        let scope = root.handle();
        Self {
            profiles: scope.child("agentProfiles").expect("new observer root"),
            persistence_projection: scope
                .child("persistenceObserver")
                .expect("new observer root"),
            lsp_projection: scope.child("lspState").expect("new observer root"),
            model_refresh: scope.child("modelRefresh").expect("new observer root"),
            model_catalog_publication: Default::default(),
            root,
            profiles_start: ObserverStart::default(),
            persistence_start: ObserverStart::default(),
            lsp_start: ObserverStart::default(),
            model_refresh_start: ObserverStart::default(),
        }
    }

    fn child(&self, observer: RuntimeObserver) -> &ScopeOwner<ObservationCleanupError> {
        match observer {
            RuntimeObserver::Profiles => &self.profiles,
            RuntimeObserver::Persistence => &self.persistence_projection,
            RuntimeObserver::Lsp => &self.lsp_projection,
            RuntimeObserver::ModelRefresh => &self.model_refresh,
        }
    }

    pub(super) fn start<F, Fut>(&self, observer: RuntimeObserver, create: F) -> ObserverOpening
    where
        F: FnOnce(CancellationToken) -> Fut + Send + 'static,
        Fut: Future<Output = Result<ObserverTask, ObservationCleanupError>> + Send + 'static,
    {
        let start = match observer {
            RuntimeObserver::Profiles => &self.profiles_start,
            RuntimeObserver::Persistence => &self.persistence_start,
            RuntimeObserver::Lsp => &self.lsp_start,
            RuntimeObserver::ModelRefresh => &self.model_refresh_start,
        };
        start.get_or_init(self.child(observer).handle(), observer.label(), create)
    }

    pub(super) fn request_close(&self) {
        self.root.request_close();
    }

    pub(super) async fn close(
        &self,
        observer: RuntimeObserver,
        deadline: Option<pl_lifecycle::Instant>,
    ) -> CloseReport<ObservationCleanupError> {
        match deadline {
            Some(deadline) => self.child(observer).close(deadline).await,
            None => self.child(observer).wait_closed().await,
        }
    }
}

#[derive(Debug)]
pub(super) struct ObservationStartError(pub(super) Arc<OpenError<ObservationCleanupError>>);

impl std::fmt::Display for ObservationStartError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.0.as_ref() {
            OpenError::ScopeClosed => f.write_str("observer scope is closed"),
            OpenError::Cancelled => f.write_str("observer opening was cancelled"),
            OpenError::Resource(error) => write!(f, "{error}"),
            OpenError::Panicked => f.write_str("observer factory panicked"),
            OpenError::WorkerStopped => f.write_str("observer lifecycle worker stopped"),
        }
    }
}

impl std::error::Error for ObservationStartError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self.0.as_ref() {
            OpenError::Resource(error) => Some(error.as_ref()),
            _ => None,
        }
    }
}

/// 原 typed report 只在所属阶段映射一次；不再报告 root 的同一失败。
#[derive(Debug)]
pub(super) struct ObservationCloseError(pub(super) CloseReport<ObservationCleanupError>);

impl std::fmt::Display for ObservationCloseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "observer scope {} did not close cleanly",
            self.0.scope_id.get()
        )?;
        for failure in &self.0.failures {
            write!(
                f,
                "; {} (resource {}, attempt {}): ",
                failure.resource.label,
                failure.resource.resource_id.get(),
                failure.attempt_id.get()
            )?;
            match &failure.error {
                CloseError::Resource(error) => write!(f, "{error}")?,
                CloseError::Panicked => f.write_str("lifecycle worker panicked")?,
                CloseError::WorkerStopped => f.write_str("lifecycle worker stopped")?,
            }
        }
        Ok(())
    }
}

impl std::error::Error for ObservationCloseError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.0
            .failures
            .iter()
            .find_map(|failure| match &failure.error {
                CloseError::Resource(error) => Some(error.as_ref() as _),
                _ => None,
            })
    }
}

#[cfg(test)]
mod tests;
