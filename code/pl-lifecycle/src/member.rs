use std::{future::Future, sync::Arc};

use futures::future::BoxFuture;
use tokio::sync::watch;

use crate::{CloseError, ResourceId, scope::Scope};

/// A resource whose successful close acknowledges that its real cleanup finished.
///
/// `request_close` must be synchronous, nonblocking, idempotent and must not
/// panic. `close` may be called again after a failure, on the same instance.
pub trait ManagedResource: Send + Sync + 'static {
    type Error: Send + Sync + 'static;

    fn request_close(&self);
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

/// Exclusive ownership of a scope-managed resource.
///
/// The borrowed resource remains subject to its own domain operation gates.
/// Dropping this guard requests cleanup; it does not wait for cleanup to finish.
pub struct Managed<R: ManagedResource> {
    pub(crate) resource: Arc<R>,
    pub(crate) scope: Arc<Scope<R::Error>>,
    pub(crate) id: ResourceId,
}

impl<R: ManagedResource> Managed<R> {
    pub fn get(&self) -> &R {
        &self.resource
    }

    pub fn request_close(&self) {
        self.scope.request_member(self.id);
    }

    pub async fn close(&self) -> Result<(), CloseError<R::Error>> {
        match self.scope.close_member(self.id, false) {
            Some(attempt) => attempt.wait().await,
            None => Ok(()),
        }
    }

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
