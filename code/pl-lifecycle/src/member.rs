use std::{future::Future, sync::Arc};

use futures::future::BoxFuture;
use tokio::sync::watch;

use tokio_util::sync::CancellationToken;

use crate::{
    AttemptId, CloseError, Phase, ResourceId, ResourceInfo, registration::Cleanup, scope::Scope,
};

pub(crate) enum EntryKind<E> {
    Async {
        token: CancellationToken,
        resource: Option<Arc<dyn ErasedResource<E>>>,
        attempt: Option<Arc<Attempt<E>>>,
        close_requested: bool,
    },
    Sync {
        cleanup: Option<Cleanup>,
    },
}

pub(crate) struct Entry<E> {
    pub(crate) info: ResourceInfo,
    pub(crate) phase: Phase,
    pub(crate) attempt_id: AttemptId,
    pub(crate) kind: EntryKind<E>,
}

/// 能够报告真实清理结果的资源。
///
/// `request_close` 必须同步、非阻塞、幂等且不 panic。`close` 成功表示真实关闭已
/// 完成；失败后可在同一个实例上再次调用。构造函数交出资源之前的部分初始化仍由
/// 构造函数负责回滚。
pub trait ManagedResource: Send + Sync + 'static {
    /// 原资源的清理错误；作用域按原类型保留，不要求其实现 Clone。
    type Error: Send + Sync + 'static;

    /// 同步封闭操作准入并唤醒等待，不阻塞、不 panic，也不代替清理完成确认。
    fn request_close(&self);
    /// 等待原资源实际关闭；允许失败后顺序重试，不应关闭或等待所属祖先作用域。
    fn close(&self) -> impl Future<Output = Result<(), Self::Error>> + Send;
}

pub(crate) trait ErasedResource<E>: Send + Sync {
    fn request_close(&self);
    fn close(self: Arc<Self>) -> BoxFuture<'static, Result<(), E>>;
}

impl<R: ManagedResource> ErasedResource<R::Error> for R {
    fn request_close(&self) {
        ManagedResource::request_close(self);
    }

    fn close(self: Arc<Self>) -> BoxFuture<'static, Result<(), R::Error>> {
        Box::pin(async move { ManagedResource::close(&*self).await })
    }
}

pub(crate) struct Attempt<E> {
    result: watch::Sender<Option<Result<(), CloseError<E>>>>,
}

impl<E> Attempt<E> {
    pub(crate) fn new() -> Arc<Self> {
        let (result, _) = watch::channel(None);
        Arc::new(Self { result })
    }

    pub(crate) fn finish(&self, result: Result<(), CloseError<E>>) {
        self.result.send_replace(Some(result));
    }

    pub(crate) fn error(&self) -> Option<CloseError<E>> {
        self.result
            .borrow()
            .as_ref()
            .and_then(|result| result.as_ref().err().cloned())
    }

    pub(crate) async fn wait(&self) -> Result<(), CloseError<E>> {
        let mut receiver = self.result.subscribe();
        loop {
            if let Some(result) = receiver.borrow_and_update().as_ref().cloned() {
                return result;
            }
            if receiver.changed().await.is_err() {
                return Err(CloseError::WorkerStopped);
            }
        }
    }
}

/// 作用域托管资源的独占句柄。
///
/// 借出的资源仍受领域自身的操作准入约束。丢弃句柄会请求清理，但不会等待完成。
pub struct Managed<R: ManagedResource> {
    pub(crate) resource: Arc<R>,
    pub(crate) scope: Arc<Scope<R::Error>>,
    pub(crate) id: ResourceId,
}

impl<R: ManagedResource> Managed<R> {
    /// 借用原资源；不能通过该借用绕过资源自身的关闭或读写约束。
    pub fn get(&self) -> &R {
        &self.resource
    }

    /// 请求关闭，不等待异步清理。
    pub fn request_close(&self) {
        self.scope.request_member(self.id);
    }

    /// 等待当前关闭尝试。取消等待不会取消清理，失败后再次调用不会隐式重试。
    pub async fn close(&self) -> Result<(), CloseError<R::Error>> {
        match self.scope.close_member(self.id, false) {
            Some(attempt) => attempt.wait().await,
            None => Ok(()),
        }
    }

    /// 在活动状态开始首次关闭，在关闭中共享当前尝试，在失败后启动一次重试。
    /// 本次尝试若失败，调用直接返回失败，不会自动再次重试。
    pub async fn retry_close(&self) -> Result<(), CloseError<R::Error>> {
        match self.scope.close_member(self.id, true) {
            Some(attempt) => attempt.wait().await,
            None => Ok(()),
        }
    }
}

impl<R: ManagedResource> Drop for Managed<R> {
    fn drop(&mut self) {
        self.request_close();
    }
}
