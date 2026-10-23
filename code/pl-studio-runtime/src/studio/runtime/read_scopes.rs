//! One runtime scope lifecycle: real resource keys, shared ReadCalls tasks and release after join.
use std::collections::BTreeMap;
use std::future::Future;
use std::sync::{Arc, Mutex, Weak};

use anyhow::Result;
use pl_protocol::products::identity::ProductResource;
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport,
    StudioError, StudioErrorCode, StudioErrorDetails, StudioShutdownIssue};

use super::background_task::BackgroundTask;
use super::read_calls::ReadCalls;

const SCOPE_LIMIT: usize = 8;

/// Only implemented original business bindings belong here; never a ref, incarnation or feed ID.
#[derive(Clone, PartialEq, Eq)]
pub(super) enum ProductScopeBinding { Unscoped }

#[derive(Clone, PartialEq, Eq)]
pub(super) enum ReadScopeBudgetKey {
    Thread(String),
    Product { resource: ProductResource, scope: ProductScopeBinding },
}

impl ReadScopeBudgetKey {
    fn is_thread(&self) -> bool { matches!(self, Self::Thread(_)) }
    fn stage(&self) -> &'static str { if self.is_thread() { "threadRead" } else { "productRead" } }
    fn cancelled(&self) -> StudioError {
        StudioError::new(StudioErrorCode::Cancelled,
            if self.is_thread() { "The Thread detail scope is closing or replaced" }
            else { "The product detail scope is closing or replaced" }, false)
    }
    fn exhausted(&self) -> StudioError {
        StudioError::new(StudioErrorCode::Overloaded,
            if self.is_thread() { "Thread detail-scope capacity is exhausted" }
            else { "Product detail-scope capacity is exhausted" }, true)
            .with_details(StudioErrorDetails::ResourceLimit {
                resource: if self.is_thread() { "threadReadScopes" } else { "productReadScopes" }.into(),
                capacity: SCOPE_LIMIT as u64,
            })
    }
}

type ScopeTable = Mutex<RegistryState>;
#[derive(Default)]
struct RegistryState {
    sealed: bool,
    threads_sealed: bool,
    scopes: BTreeMap<String, Arc<ReadScopeOwner>>,
}

#[derive(Clone, Default)]
pub(super) struct ReadScopeRegistry(Arc<ScopeTable>);

impl ReadScopeRegistry {
    pub(super) fn group(&self, key: ReadScopeBudgetKey, incarnation: u64) -> ReadScopeGroup {
        ReadScopeGroup { registry: Arc::downgrade(&self.0), key, incarnation, closing: Mutex::new(false) }
    }

    /// No new group admission or existing scope query can escape this synchronous fence.
    pub(super) fn seal(&self) {
        let mut state = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        state.sealed = true;
        for owner in state.scopes.values() { owner.request_close(); }
    }

    pub(super) async fn close(&self) -> Vec<FeedCloseIssue> {
        self.seal();
        let owners: Vec<_> = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .scopes.values().cloned().collect();
        close_owners(owners).await
    }

    /// The Thread adapter seals only its domain; global shutdown independently closes all domains.
    pub(super) async fn close_threads(&self) -> Vec<FeedCloseIssue> {
        let owners: Vec<_> = {
            let mut state = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            state.threads_sealed = true;
            state.scopes.values().filter(|owner| owner.key.is_thread()).cloned().collect()
        };
        close_owners(owners).await
    }
}

pub(super) struct ReadScopeGroup {
    registry: Weak<ScopeTable>,
    key: ReadScopeBudgetKey,
    incarnation: u64,
    closing: Mutex<bool>,
}

impl ReadScopeGroup {
    /// Material (including its real domain leases) is built before taking admission locks. On
    /// rejection the locks drop before this parameter, so a Cold rollback cannot re-enter them.
    pub(super) fn open<M: Send + Sync + 'static>(&self, scope_id: String, material: M)
        -> Result<(Arc<ReadScopeOwner>, Arc<PinnedMaterial<M>>), StudioError> {
        let closing = self.closing.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if *closing { return Err(self.key.cancelled()); }
        let registry = self.registry.upgrade().ok_or_else(|| self.key.cancelled())?;
        let mut state = registry.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed || (state.threads_sealed && self.key.is_thread()) { return Err(self.key.cancelled()); }
        if state.scopes.values().filter(|owner| owner.key == self.key).count() >= SCOPE_LIMIT {
            return Err(self.key.exhausted());
        }
        if state.scopes.contains_key(&scope_id) {
            return Err(StudioError::new(StudioErrorCode::Protocol, "A detail scope identity was registered twice", false));
        }
        let pinned = Arc::new(PinnedMaterial(Mutex::new(Some(material))));
        let owner = Arc::new(ReadScopeOwner { scope_id, key: self.key.clone(), incarnation: self.incarnation,
            registry: Arc::downgrade(&registry), resource: pinned.clone(), cleanup: Mutex::new(()),
            state: Mutex::new(ReadState { closing: false, released: false,
                tasks: BTreeMap::new(), issues: BTreeMap::new() }) });
        state.scopes.insert(owner.scope_id.clone(), owner.clone());
        Ok((owner, pinned))
    }

    pub(super) fn request_close(&self) {
        let mut closing = self.closing.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        *closing = true;
        if let Some(registry) = self.registry.upgrade() {
            let state = registry.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            for owner in state.scopes.values().filter(|owner|
                owner.key == self.key && owner.incarnation == self.incarnation) { owner.request_close(); }
        }
    }

    pub(super) async fn close(&self) -> Vec<FeedCloseIssue> {
        self.request_close();
        let owners = self.registry.upgrade().map(|registry|
            registry.lock().unwrap_or_else(std::sync::PoisonError::into_inner).scopes.values()
                .filter(|owner| owner.key == self.key && owner.incarnation == self.incarnation)
                .cloned().collect()).unwrap_or_default();
        close_owners(owners).await
    }
}

// Only release is erased. Every query still borrows its concrete domain material M.
trait ReadResource: Send + Sync { fn release(&self); }
pub(super) struct PinnedMaterial<M>(Mutex<Option<M>>);

impl<M> PinnedMaterial<M> {
    pub(super) fn read<T>(&self, read: impl FnOnce(&M) -> Result<T, StudioError>) -> Result<T> {
        let material = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        let material = material.as_ref().ok_or_else(|| StudioError::new(StudioErrorCode::Cancelled,
            "The detail scope material was released", false))?;
        read(material).map_err(Into::into)
    }
}

impl<M: Send + Sync> ReadResource for PinnedMaterial<M> {
    fn release(&self) {
        let material = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
        // Domain Drop may take source/registry locks. No payload/admission/registry guard survives.
        drop(material);
    }
}

struct ReadState {
    closing: bool,
    released: bool,
    tasks: BTreeMap<String, Arc<BackgroundTask>>,
    issues: BTreeMap<String, FeedCloseIssue>,
}

pub(super) struct ReadScopeOwner {
    scope_id: String,
    key: ReadScopeBudgetKey,
    incarnation: u64,
    registry: Weak<ScopeTable>,
    resource: Arc<dyn ReadResource>,
    cleanup: Mutex<()>,
    state: Mutex<ReadState>,
}

impl ReadScopeOwner {
    pub(super) fn request_close(&self) {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).closing = true;
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        if self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).closing {
            Err(self.key.cancelled())
        } else { Ok(()) }
    }

    pub(super) fn run<T, F>(self: &Arc<Self>, calls: &ReadCalls, read: F)
        -> impl Future<Output = Result<T>> + Send + 'static + use<T, F>
    where T: Send + 'static, F: Future<Output = Result<T>> + Send + 'static {
        let admitted = {
            let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing { Err(self.key.cancelled().into()) } else {
                state.tasks.retain(|_, task| !task.succeeded());
                calls.register(read).map(|call| {
                    state.tasks.insert(call.id.clone(), call.task.clone());
                    call
                })
            }
        };
        let owner = self.clone();
        async move {
            let value = admitted?.wait().await?;
            owner.ensure_open()?;
            Ok(value)
        }
    }

    pub(super) fn release_if_joined(&self) {
        let _cleanup = self.cleanup.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        let release = {
            let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing && !state.released && state.issues.is_empty()
                && state.tasks.values().all(|task| task.succeeded()) {
                state.released = true;
                true
            } else { false }
        };
        if !release { return; }
        self.resource.release();
        if let Some(registry) = self.registry.upgrade() {
            registry.lock().unwrap_or_else(std::sync::PoisonError::into_inner).scopes.remove(&self.scope_id);
        }
    }

    pub(super) async fn close(&self) -> FeedCloseReport {
        self.request_close();
        let tasks: Vec<_> = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .tasks.iter().map(|(id, task)| (id.clone(), task.clone())).collect();
        let results = futures::future::join_all(tasks.iter().map(|(_, task)| task.join())).await;
        {
            let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            for ((id, _), result) in tasks.iter().zip(results) {
                if result.is_err() {
                    state.issues.entry(id.clone()).or_insert_with(|| FeedCloseIssue {
                        diagnostic: StudioShutdownIssue { stage: self.key.stage().into(), code: "joinError".into(),
                            message: if self.key.is_thread() { "A Thread detail query did not join successfully" }
                            else { "A product detail query did not join successfully" }.into(), retryable: false,
                            correlation_id: StudioError::internal().correlation_id },
                        recovery: CleanupRecovery::Terminal,
                    });
                }
            }
        }
        self.release_if_joined();
        let issues: Vec<_> = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .issues.values().cloned().collect();
        FeedCloseReport { feed_id: self.scope_id.clone(), outcome: if issues.is_empty() {
            FeedCloseOutcome::Clean
        } else { FeedCloseOutcome::Unresolved { issues } } }
    }
}

async fn close_owners(owners: Vec<Arc<ReadScopeOwner>>) -> Vec<FeedCloseIssue> {
    for owner in &owners { owner.request_close(); }
    let reports = futures::future::join_all(owners.iter().map(|owner| owner.close())).await;
    reports.into_iter().flat_map(|report| match report.outcome {
        FeedCloseOutcome::Clean => Vec::new(),
        FeedCloseOutcome::Unresolved { issues } => issues,
    }).collect()
}

#[derive(Debug, thiserror::Error)]
#[error("Detail read cleanup retained unresolved owners")]
pub(super) struct ReadScopesCloseFailure {
    #[source]
    pub(super) call_error: Option<anyhow::Error>,
    pub(super) call_failures: Vec<super::read_calls::ReadCallJoinFailure>,
    pub(super) scope_issues: Vec<FeedCloseIssue>,
}

impl super::StudioRuntime {
    pub(super) async fn close_detail_reads(&self) -> Result<()> {
        let (calls, scope_issues) = futures::join!(self.read_calls.close(), self.read_scopes.close());
        if calls.is_empty() && scope_issues.is_empty() {
            self.models_source.finish_close();
            self.templates_source.finish_close();
            return Ok(());
        }
        let call_error = calls.first().map(|failure| anyhow::Error::new(failure.error.clone()));
        Err(ReadScopesCloseFailure { call_error, call_failures: calls, scope_issues }.into())
    }
}
