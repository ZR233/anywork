//! Executor ownership is separate from the explicit leases used by frozen calls.
use super::{Executor, ToolError};
use futures::{FutureExt, StreamExt, future::BoxFuture, stream::FuturesUnordered};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
use tokio::sync::Notify;

#[derive(Debug)]
pub(super) struct ExecutorOwner {
    executor: Arc<dyn Executor>,
    users: AtomicUsize,
    released: Notify,
}

#[derive(Debug)]
pub(super) struct ExecutorLease(Arc<ExecutorOwner>);

impl ExecutorLease {
    pub(super) fn new(executor: impl Executor + 'static) -> Self {
        Self(Arc::new(ExecutorOwner {
            executor: Arc::new(executor),
            users: AtomicUsize::new(1),
            released: Notify::new(),
        }))
    }
}

impl Clone for ExecutorLease {
    fn clone(&self) -> Self {
        self.0.users.fetch_add(1, Ordering::Relaxed);
        Self(self.0.clone())
    }
}

impl Drop for ExecutorLease {
    fn drop(&mut self) {
        if self.0.users.fetch_sub(1, Ordering::AcqRel) == 1 {
            self.0.released.notify_one();
        }
    }
}

impl std::ops::Deref for ExecutorLease {
    type Target = dyn Executor;
    fn deref(&self) -> &Self::Target {
        self.0.executor.as_ref()
    }
}

enum Cleanup {
    Waiting,
    Failed(Arc<ToolError>),
}

struct OwnedExecutor {
    id: String,
    owner: Arc<ExecutorOwner>,
    cleanup: Cleanup,
}

type Completion = (Arc<ExecutorOwner>, Result<(), Arc<ToolError>>);

#[derive(Default)]
pub(super) struct Executors {
    instances: Vec<OwnedExecutor>,
    pending: std::sync::Mutex<FuturesUnordered<BoxFuture<'static, Completion>>>,
}

impl std::fmt::Debug for Executors {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Executors")
            .field("owned", &self.instances.len())
            .field(
                "cleanup",
                &self
                    .pending
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .len(),
            )
            .finish()
    }
}

impl Executors {
    pub(super) fn retain(&mut self, id: &str, lease: &ExecutorLease) {
        if self
            .instances
            .iter()
            .any(|entry| Arc::ptr_eq(&entry.owner, &lease.0))
        {
            return;
        }
        self.instances.push(OwnedExecutor {
            id: id.into(),
            owner: lease.0.clone(),
            cleanup: Cleanup::Waiting,
        });
        self.schedule(lease.0.clone());
    }

    fn schedule(&mut self, owner: Arc<ExecutorOwner>) {
        self.pending
            .get_mut()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(Box::pin(async move {
                while owner.users.load(Ordering::Acquire) != 0 {
                    owner.released.notified().await;
                }
                let result = crate::error_record::catch_boundary("tool close", async {
                    owner.executor.close().await
                })
                .await
                .map_err(ToolError::new)
                .and_then(|result| result)
                .map_err(Arc::new);
                (owner, result)
            }));
    }

    pub(super) fn has_pending(&self) -> bool {
        !self
            .pending
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .is_empty()
    }

    pub(super) async fn next(&mut self) {
        let Some((owner, result)) = self
            .pending
            .get_mut()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .next()
            .await
        else {
            return;
        };
        match result {
            Ok(()) => self
                .instances
                .retain(|entry| !Arc::ptr_eq(&entry.owner, &owner)),
            Err(error) => {
                if let Some(entry) = self
                    .instances
                    .iter_mut()
                    .find(|entry| Arc::ptr_eq(&entry.owner, &owner))
                {
                    entry.cleanup = Cleanup::Failed(error);
                }
            }
        }
    }

    pub(super) fn poll_ready(&mut self) -> bool {
        let mut changed = false;
        while self.has_pending() && self.next().now_or_never().is_some() {
            changed = true;
        }
        changed
    }

    pub(super) fn state<'a>(
        &self,
        current: impl Iterator<Item = &'a ExecutorLease>,
    ) -> crate::thread::ToolCleanupState {
        let current = current.map(|lease| &lease.0).collect::<Vec<_>>();
        let mut state = crate::thread::ToolCleanupState::default();
        for entry in &self.instances {
            if current.iter().any(|owner| Arc::ptr_eq(owner, &entry.owner)) {
                continue;
            }
            state.pending += 1;
            if let Cleanup::Failed(error) = &entry.cleanup {
                state.failures.push(crate::thread::ToolCleanupFailure {
                    tool_id: entry.id.clone(),
                    error: error.clone(),
                });
            }
        }
        state
    }

    pub(super) fn retry_failed(&mut self) {
        let failed = self
            .instances
            .iter_mut()
            .filter_map(|entry| {
                if matches!(entry.cleanup, Cleanup::Failed(_)) {
                    entry.cleanup = Cleanup::Waiting;
                    Some(entry.owner.clone())
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        for owner in failed {
            self.schedule(owner);
        }
    }

    pub(super) async fn close(&mut self) -> Result<(), ToolError> {
        self.retry_failed();
        while self.has_pending() {
            self.next().await;
        }
        match self
            .instances
            .iter()
            .find_map(|entry| match &entry.cleanup {
                Cleanup::Failed(error) => Some(error.clone()),
                Cleanup::Waiting => None,
            }) {
            Some(error) => Err(ToolError::new(error)),
            None => Ok(()),
        }
    }
}
