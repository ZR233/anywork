use std::{
    future::Future,
    panic::AssertUnwindSafe,
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
};

use futures::FutureExt;
use tokio::sync::oneshot;
use tokio_util::{sync::CancellationToken, task::task_tracker::TaskTrackerToken};

use crate::{
    AttemptId, CloseError, Managed, ManagedResource, OpenError, ResourceId,
    member::{Attempt, ErasedResource},
    scope::Scope,
};

pub(crate) struct WorkerGuard<E: Send + Sync + 'static> {
    scope: Arc<Scope<E>>,
    id: ResourceId,
    armed: bool,
}

impl<E: Send + Sync + 'static> WorkerGuard<E> {
    pub(crate) fn new(scope: Arc<Scope<E>>, id: ResourceId) -> Self {
        Self {
            scope,
            id,
            armed: true,
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

impl<E: Send + Sync + 'static> Drop for WorkerGuard<E> {
    fn drop(&mut self) {
        if self.armed {
            self.scope.worker_stopped(self.id);
        }
    }
}

// Drop the worker and its termination guard before releasing the tracker token.
// This also runs when the runtime discards a future that was never polled.
struct TrackedWorker<E: Send + Sync + 'static> {
    future: Option<Pin<Box<dyn Future<Output = ()> + Send>>>,
    token: Option<TaskTrackerToken>,
    scope: Arc<Scope<E>>,
}

impl<E: Send + Sync + 'static> Future for TrackedWorker<E> {
    type Output = ();
    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<()> {
        self.future
            .as_mut()
            .expect("worker is polled only before completion")
            .as_mut()
            .poll(cx)
    }
}

impl<E: Send + Sync + 'static> Drop for TrackedWorker<E> {
    fn drop(&mut self) {
        drop(self.future.take());
        drop(self.token.take());
        self.scope.changed();
        self.scope.retire_if_empty();
    }
}

fn spawn<E: Send + Sync + 'static>(
    scope: Arc<Scope<E>>,
    tracked: TaskTrackerToken,
    future: impl Future<Output = ()> + Send + 'static,
) {
    let task = TrackedWorker {
        future: Some(Box::pin(future)),
        token: Some(tracked),
        scope: Arc::clone(&scope),
    };
    scope.runtime.spawn(task);
}

pub(crate) fn spawn_open<E, R, F, Fut>(
    scope: Arc<Scope<E>>,
    id: ResourceId,
    token: CancellationToken,
    factory: F,
    sender: oneshot::Sender<Result<Managed<R>, OpenError<E>>>,
    guard: WorkerGuard<E>,
    tracked: TaskTrackerToken,
) where
    E: Send + Sync + 'static,
    R: ManagedResource<Error = E>,
    F: FnOnce(CancellationToken) -> Fut + Send + 'static,
    Fut: Future<Output = Result<R, E>> + Send + 'static,
{
    let worker_scope = Arc::clone(&scope);
    spawn(scope, tracked, async move {
        let mut guard = guard;
        let result = AssertUnwindSafe(async { factory(token.clone()).await })
            .catch_unwind()
            .await;
        match result {
            Ok(Ok(resource)) => {
                let published = worker_scope.publish_open(id, Arc::new(resource), sender);
                if published {
                    token.cancelled().await;
                    worker_scope.request_member(id);
                }
                if let Some((attempt_id, cell, resource)) = worker_scope.current_cleanup(id) {
                    cleanup(worker_scope, id, attempt_id, cell, resource, guard).await;
                } else {
                    guard.disarm();
                }
            }
            Ok(Err(error)) => {
                guard.disarm();
                worker_scope.opening_failed(id, None);
                let _ = sender.send(Err(OpenError::Resource(Arc::new(error))));
            }
            Err(_) => {
                guard.disarm();
                worker_scope.opening_failed(id, Some(CloseError::Panicked));
                let _ = sender.send(Err(OpenError::Panicked));
            }
        }
    });
}

pub(crate) fn spawn_cleanup<E: Send + Sync + 'static>(
    scope: Arc<Scope<E>>,
    id: ResourceId,
    attempt_id: AttemptId,
    cell: Arc<Attempt<E>>,
    resource: Arc<dyn ErasedResource<E>>,
    guard: WorkerGuard<E>,
    tracked: TaskTrackerToken,
) {
    let worker_scope = Arc::clone(&scope);
    spawn(
        scope,
        tracked,
        cleanup(worker_scope, id, attempt_id, cell, resource, guard),
    );
}

async fn cleanup<E: Send + Sync + 'static>(
    scope: Arc<Scope<E>>,
    id: ResourceId,
    attempt_id: AttemptId,
    _cell: Arc<Attempt<E>>,
    resource: Arc<dyn ErasedResource<E>>,
    mut guard: WorkerGuard<E>,
) {
    crate::scope::request_resource(&resource);
    let result = AssertUnwindSafe(async { resource.close().await })
        .catch_unwind()
        .await;
    let result = match result {
        Ok(Ok(())) => Ok(()),
        Ok(Err(error)) => Err(CloseError::Resource(Arc::new(error))),
        Err(_) => Err(CloseError::Panicked),
    };
    // No domain operation follows publication. A retry can start immediately
    // while prior waiters still hold their own retained attempt cell.
    guard.disarm();
    scope.finish_cleanup(id, attempt_id, result);
}
