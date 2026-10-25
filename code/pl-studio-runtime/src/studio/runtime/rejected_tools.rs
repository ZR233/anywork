//! Owns original rejected tool batches across retries and cancelled close waiters.
use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_core::{
    thread::ThreadHandle,
    tool::opaque::{RejectedTools, ToolError},
};
use std::sync::{
    Arc, Mutex, Weak,
    atomic::{AtomicBool, Ordering},
};

#[derive(Clone, Default)]
pub(super) struct RejectedToolOwners {
    entries: Arc<Mutex<Vec<Arc<Entry>>>>,
    stop: Arc<Mutex<tokio_util::sync::CancellationToken>>,
}
struct Entry {
    thread: ThreadHandle,
    gate: tokio::sync::Mutex<()>,
    resources: Mutex<Option<Box<RejectedTools>>>,
    failure: Mutex<Option<Arc<ToolError>>>,
    wait: Mutex<Option<RejectedWait>>,
    completed: AtomicBool,
    resources_missing: AtomicBool,
}
struct Lease {
    entry: Weak<Entry>,
    resources: Option<Box<RejectedTools>>,
}
impl Drop for Lease {
    fn drop(&mut self) {
        if let Some(resources) = self.resources.take()
            && let Some(entry) = self.entry.upgrade()
        {
            let retired = entry
                .resources
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .replace(resources);
            drop(retired);
        }
    }
}
type RejectedWait = Shared<BoxFuture<'static, Result<(), Arc<ToolError>>>>;

#[derive(Debug, Clone)]
pub(in crate::studio::runtime) struct RejectedToolCloseIssue {
    pub(in crate::studio::runtime) batch: usize,
    pub(in crate::studio::runtime) source: Option<Arc<ToolError>>,
    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    pub(in crate::studio::runtime) resources_missing: bool,
}

/// A failed close retains the exact batches, not a later lookup by Thread ID.
#[derive(Clone)]
pub(crate) struct RejectedToolsCloseFailure {
    owner: RejectedToolOwners,
    entries: Vec<Arc<Entry>>,
    pub(in crate::studio::runtime) issues: Vec<RejectedToolCloseIssue>,
}
impl std::fmt::Debug for RejectedToolsCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RejectedToolsCloseFailure")
            .field("issues", &self.issues)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Display for RejectedToolsCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original rejected tool batches still require cleanup")
    }
}
impl std::error::Error for RejectedToolsCloseFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.issues
            .iter()
            .find_map(|issue| issue.source.as_ref().map(|source| source.as_ref() as _))
    }
}

// Keep the existing anyhow return/boxed consumers. Its std source chain includes the concrete
// witness even when anyhow's boxed adapter is not directly downcastable to that witness.
#[derive(Debug, thiserror::Error)]
#[error("rejected tool candidate cleanup failed: {0}")]
struct CleanupFailure(#[source] RejectedToolsCloseFailure);

impl RejectedToolsCloseFailure {
    pub(crate) fn matches_thread(&self, thread: &ThreadHandle) -> bool {
        !self.entries.is_empty()
            && self
                .entries
                .iter()
                .all(|entry| entry.thread.same_instance(thread))
    }

    pub(crate) fn original_is_complete(&self) -> bool {
        self.entries
            .iter()
            .all(|entry| entry.completed.load(Ordering::Acquire))
    }

    /// Pure capability of these original batches. An empty resource slot belongs to its retained
    /// accepted wait, never evidence that the batch completed.
    pub(crate) fn can_resume_original(&self) -> bool {
        self.entries.iter().any(|entry| {
            !entry.completed.load(Ordering::Acquire)
                && !entry.resources_missing.load(Ordering::Acquire)
        })
    }

    pub(crate) async fn resume_original(&self) -> Result<(), Self> {
        if !self.can_resume_original() && !self.original_is_complete() {
            return Err(self.clone());
        }
        self.owner
            .close_entries(self.entries.clone(), Some(self))
            .await
    }
}

impl RejectedToolOwners {
    pub(super) fn start(&self) -> tokio_util::sync::CancellationToken {
        let token = tokio_util::sync::CancellationToken::new();
        *self
            .stop
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = token.clone();
        token
    }
    pub(super) fn stop(&self) {
        self.stop
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cancel();
    }
    pub(super) fn retain(&self, thread: ThreadHandle, resources: Box<RejectedTools>) {
        self.entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(Arc::new(Entry {
                thread,
                gate: Default::default(),
                resources: Mutex::new(Some(resources)),
                failure: Mutex::new(None),
                wait: Mutex::new(None),
                completed: AtomicBool::new(false),
                resources_missing: AtomicBool::new(false),
            }));
    }

    pub(super) async fn retry(&self, thread: Option<&ThreadHandle>) -> anyhow::Result<()> {
        let entries = self
            .entries
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .iter()
            .filter(|entry| thread.is_none_or(|thread| thread.same_instance(&entry.thread)))
            .cloned()
            .collect();
        self.close_entries(entries, None)
            .await
            .map_err(|failure| anyhow::Error::new(CleanupFailure(failure)))
    }

    fn close_batch(&self, entry: &Arc<Entry>, resources: Box<RejectedTools>) -> RejectedWait {
        let entry = Arc::downgrade(entry);
        let owner = Arc::downgrade(&self.entries);
        async move {
            // Only weak back-edges live in the future stored by this Entry. A timeout in tool
            // refresh drops its waiter, not the original accepted tool close or its resources.
            let mut lease = Lease {
                entry: entry.clone(),
                resources: Some(resources),
            };
            if let Err(error) = lease
                .resources
                .as_mut()
                .expect("original batch lease")
                .retry_close()
                .await
            {
                if let Some(entry) = entry.upgrade() {
                    let retired = entry
                        .failure
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .replace(error.clone());
                    drop(retired);
                }
                return Err(error);
            }
            lease.resources = None;
            if let Some(entry) = entry.upgrade() {
                entry.completed.store(true, Ordering::Release);
                let retired = entry
                    .failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .take();
                drop(retired);
                let retired = owner.upgrade().and_then(|owner| {
                    let mut all = owner
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    all.iter()
                        .position(|current| Arc::ptr_eq(current, &entry))
                        .map(|index| all.remove(index))
                });
                drop(retired);
            }
            Ok(())
        }
        .boxed()
        .shared()
    }

    async fn close_entries(
        &self,
        entries: Vec<Arc<Entry>>,
        previous: Option<&RejectedToolsCloseFailure>,
    ) -> Result<(), RejectedToolsCloseFailure> {
        // Capture every raw failure before waiting for any gate. A concurrent cleanup may finish
        // or fail while we wait; a newly observed failure is not this call's retry grant.
        let grants: Vec<_> = entries
            .iter()
            .enumerate()
            .map(|(batch, entry)| match previous {
                Some(previous) => previous
                    .issues
                    .iter()
                    .find(|issue| issue.batch == batch)
                    .and_then(|issue| issue.source.clone()),
                None => entry
                    .failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone(),
            })
            .collect();
        let outcomes = futures::future::join_all(entries.iter().zip(grants).enumerate().map(
            |(batch, (entry, original))| async move {
                let _permit = entry.gate.lock().await;
                if entry.completed.load(Ordering::Acquire) {
                    return None;
                }
                if entry.resources_missing.load(Ordering::Acquire) {
                    return Some(RejectedToolCloseIssue {
                        batch,
                        source: entry
                            .failure
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .clone(),
                        resources_missing: true,
                    });
                }
                let current = entry
                    .failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                let same_failure = match (&original, &current) {
                    (None, None) => true,
                    (Some(original), Some(current)) => Arc::ptr_eq(original, current),
                    _ => false,
                };
                if !same_failure {
                    return Some(RejectedToolCloseIssue {
                        batch,
                        source: current,
                        resources_missing: false,
                    });
                }
                let existing = entry
                    .wait
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .clone();
                let (wait, retired) = if let Some(wait) = existing
                    && !matches!(wait.peek(), Some(Err(_)))
                {
                    (wait, None)
                } else {
                    let resources = entry
                        .resources
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .take();
                    let Some(resources) = resources else {
                        entry.resources_missing.store(true, Ordering::Release);
                        return Some(RejectedToolCloseIssue {
                            batch,
                            source: current,
                            resources_missing: true,
                        });
                    };
                    let wait = self.close_batch(entry, resources);
                    let retired = entry
                        .wait
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .replace(wait.clone());
                    (wait, retired)
                };
                drop(retired);
                wait.await.err().map(|error| RejectedToolCloseIssue {
                    batch,
                    source: Some(error),
                    resources_missing: false,
                })
            },
        ))
        .await;
        let issues: Vec<_> = outcomes.into_iter().flatten().collect();
        if issues.is_empty() {
            Ok(())
        } else {
            Err(RejectedToolsCloseFailure {
                owner: self.clone(),
                entries,
                issues,
            })
        }
    }
}
