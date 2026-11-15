use std::{
    collections::BTreeMap,
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{
        Arc, Mutex, MutexGuard, Weak,
        atomic::{AtomicU64, Ordering},
    },
};

use tokio::{
    runtime::Handle,
    sync::{oneshot, watch},
    time::Instant,
};
use tokio_util::{sync::CancellationToken, task::TaskTracker};

use crate::{
    AttemptId, CloseError, CloseReport, FailedResource, Managed, ManagedResource, OpenError,
    PendingResource, Phase, Registration, RegistrationError, ResourceId, ResourceInfo, ScopeClosed,
    ScopeId,
    member::{Attempt, ErasedResource},
    registration,
    worker::{self, WorkerGuard},
};

type Cleanup = Box<dyn FnOnce() + Send + 'static>;
type CleanupAttempt<E> = (AttemptId, Arc<Attempt<E>>, Arc<dyn ErasedResource<E>>);

struct OpenTicket<R: ManagedResource> {
    receiver: oneshot::Receiver<Result<Managed<R>, OpenError<R::Error>>>,
    guard: OpeningGuard<R::Error>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ScopePhase {
    Open,
    Closing,
    Closed,
}

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
    info: ResourceInfo,
    phase: Phase,
    attempt_id: AttemptId,
    kind: EntryKind<E>,
}

struct State<E: Send + Sync + 'static> {
    phase: ScopePhase,
    next_resource: u64,
    entries: BTreeMap<ResourceId, Entry<E>>,
    diagnostics: Vec<FailedResource<E>>,
    children: Vec<Arc<Scope<E>>>,
}

struct Tree {
    next_scope: AtomicU64,
    changed: watch::Sender<u64>,
}

struct Generation {
    value: AtomicU64,
    parent: Option<Arc<Generation>>,
}

pub(crate) struct Scope<E: Send + Sync + 'static> {
    id: ScopeId,
    _label: &'static str,
    pub(crate) runtime: Handle,
    pub(crate) tracker: TaskTracker,
    parent: Weak<Scope<E>>,
    tree: Arc<Tree>,
    generation: Arc<Generation>,
    state: Mutex<State<E>>,
}

impl<E: Send + Sync + 'static> Scope<E> {
    fn state(&self) -> MutexGuard<'_, State<E>> {
        self.state
            .lock()
            .unwrap_or_else(|poison| poison.into_inner())
    }

    pub(crate) fn changed(&self) {
        self.tree
            .changed
            .send_modify(|value| *value = value.wrapping_add(1));
    }

    // A parent must notice new work anywhere below it. A child does not use
    // its siblings' generations or trackers to decide whether it is finished.
    fn worker_registered(&self) {
        let mut generation = Some(self.generation.as_ref());
        while let Some(current) = generation {
            current.value.fetch_add(1, Ordering::SeqCst);
            generation = current.parent.as_deref();
        }
    }

    fn create(
        id: ScopeId,
        label: &'static str,
        runtime: Handle,
        parent: Weak<Self>,
        tree: Arc<Tree>,
        parent_generation: Option<Arc<Generation>>,
    ) -> Arc<Self> {
        Arc::new(Self {
            id,
            _label: label,
            runtime,
            tracker: TaskTracker::new(),
            parent,
            tree,
            generation: Arc::new(Generation {
                value: AtomicU64::new(0),
                parent: parent_generation,
            }),
            state: Mutex::new(State {
                phase: ScopePhase::Open,
                next_resource: 0,
                entries: BTreeMap::new(),
                diagnostics: Vec::new(),
                children: Vec::new(),
            }),
        })
    }

    fn next_info(&self, state: &mut State<E>, label: &'static str) -> ResourceInfo {
        let id = ResourceId(state.next_resource);
        state.next_resource = state
            .next_resource
            .checked_add(1)
            .expect("resource ID space exhausted");
        ResourceInfo {
            scope_id: self.id,
            resource_id: id,
            label,
        }
    }

    fn child(self: &Arc<Self>, label: &'static str) -> Result<ScopeOwner<E>, ScopeClosed> {
        let mut state = self.state();
        if state.phase != ScopePhase::Open {
            return Err(ScopeClosed);
        }
        let id = self
            .tree
            .next_scope
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
            .expect("scope ID space exhausted");
        let child = Self::create(
            ScopeId(id),
            label,
            self.runtime.clone(),
            Arc::downgrade(self),
            Arc::clone(&self.tree),
            Some(Arc::clone(&self.generation)),
        );
        state.children.push(Arc::clone(&child));
        drop(state);
        self.changed();
        Ok(ScopeOwner { scope: child })
    }

    fn register(
        self: &Arc<Self>,
        label: &'static str,
        cleanup: Cleanup,
    ) -> Result<Registration, RegistrationError> {
        let mut state = self.state();
        if state.phase != ScopePhase::Open {
            drop(state);
            return registration::reject(cleanup);
        }
        let info = self.next_info(&mut state, label);
        let id = info.resource_id;
        state.entries.insert(
            id,
            Entry {
                info,
                phase: Phase::Active,
                attempt_id: AttemptId(1),
                kind: EntryKind::Sync {
                    cleanup: Some(cleanup),
                },
            },
        );
        drop(state);
        let scope = Arc::downgrade(self);
        Ok(Registration::new(move || {
            if let Some(scope) = scope.upgrade() {
                scope.run_registration(id);
            }
        }))
    }

    fn begin_open<R, F, Fut>(
        self: &Arc<Self>,
        label: &'static str,
        factory: F,
    ) -> Result<OpenTicket<R>, ScopeClosed>
    where
        R: ManagedResource<Error = E>,
        F: FnOnce(CancellationToken) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = Result<R, E>> + Send + 'static,
    {
        let mut state = self.state();
        if state.phase != ScopePhase::Open {
            return Err(ScopeClosed);
        }
        let info = self.next_info(&mut state, label);
        let id = info.resource_id;
        let token = CancellationToken::new();
        state.entries.insert(
            id,
            Entry {
                info,
                phase: Phase::Opening,
                attempt_id: AttemptId(0),
                kind: EntryKind::Async {
                    token: token.clone(),
                    resource: None,
                    attempt: None,
                    close_requested: false,
                },
            },
        );
        let tracked = self.tracker.token();
        self.worker_registered();
        let guard = WorkerGuard::new(Arc::clone(self), id);
        let (sender, receiver) = oneshot::channel();
        drop(state);
        worker::spawn_open(Arc::clone(self), id, token, factory, sender, guard, tracked);
        self.changed();
        Ok(OpenTicket {
            receiver,
            guard: OpeningGuard {
                scope: Arc::clone(self),
                id,
                armed: true,
            },
        })
    }

    pub(crate) fn publish_open<R: ManagedResource<Error = E>>(
        self: &Arc<Self>,
        id: ResourceId,
        resource: Arc<R>,
        sender: oneshot::Sender<Result<Managed<R>, OpenError<E>>>,
    ) -> bool {
        let mut state = self.state();
        let closing = state.phase != ScopePhase::Open;
        let Some(entry) = state.entries.get_mut(&id) else {
            return false;
        };
        let EntryKind::Async {
            token,
            resource: stored,
            attempt,
            close_requested,
        } = &mut entry.kind
        else {
            unreachable!()
        };
        let erased: Arc<dyn ErasedResource<E>> = resource.clone();
        *stored = Some(erased.clone());
        let should_close = closing || *close_requested || token.is_cancelled();
        if should_close {
            entry.phase = Phase::Closing;
            entry.attempt_id = AttemptId(1);
            *attempt = Some(Attempt::new());
            let token = token.clone();
            drop(state);
            let _ = sender.send(Err(OpenError::Cancelled));
            request_resource(&erased);
            token.cancel();
            self.changed();
            false
        } else {
            entry.phase = Phase::Active;
            let managed = Managed {
                resource,
                scope: Arc::clone(self),
                id,
            };
            // Publication and sealing share this gate. The rejected guard must be
            // dropped after unlocking because its Drop re-enters this scope.
            let rejected = sender.send(Ok(managed)).err();
            drop(state);
            drop(rejected);
            self.changed();
            true
        }
    }

    pub(crate) fn opening_failed(&self, id: ResourceId, error: Option<CloseError<E>>) {
        let mut state = self.state();
        if let Some(entry) = state.entries.remove(&id)
            && let Some(error) = error
        {
            state.diagnostics.push(FailedResource {
                resource: entry.info,
                attempt_id: AttemptId(0),
                phase: Phase::Opening,
                error,
                retained: false,
            });
        }
        drop(state);
        self.changed();
    }

    pub(crate) fn current_cleanup(&self, id: ResourceId) -> Option<CleanupAttempt<E>> {
        let state = self.state();
        let entry = state.entries.get(&id)?;
        let EntryKind::Async {
            resource: Some(resource),
            attempt: Some(attempt),
            ..
        } = &entry.kind
        else {
            return None;
        };
        Some((entry.attempt_id, Arc::clone(attempt), Arc::clone(resource)))
    }

    pub(crate) fn finish_cleanup(
        &self,
        id: ResourceId,
        attempt_id: AttemptId,
        result: Result<(), CloseError<E>>,
    ) {
        let mut state = self.state();
        let Some(entry) = state.entries.get_mut(&id) else {
            return;
        };
        if entry.phase != Phase::Closing || entry.attempt_id != attempt_id {
            return;
        }
        let EntryKind::Async {
            attempt: Some(attempt),
            ..
        } = &entry.kind
        else {
            return;
        };
        let attempt = Arc::clone(attempt);
        if result.is_ok() {
            let removed = state.entries.remove(&id);
            drop(state);
            attempt.finish(result);
            drop(removed);
        } else {
            entry.phase = Phase::Failed;
            drop(state);
            attempt.finish(result);
        }
        self.changed();
    }

    pub(crate) fn worker_stopped(&self, id: ResourceId) {
        let mut state = self.state();
        let Some(entry) = state.entries.get_mut(&id) else {
            return;
        };
        match entry.phase {
            Phase::Opening => {
                let entry = state.entries.remove(&id).expect("entry existed");
                state.diagnostics.push(FailedResource {
                    resource: entry.info,
                    attempt_id: AttemptId(0),
                    phase: Phase::Opening,
                    error: CloseError::WorkerStopped,
                    retained: false,
                });
                drop(state);
            }
            Phase::Active | Phase::Closing => {
                let EntryKind::Async { attempt, .. } = &mut entry.kind else {
                    return;
                };
                if entry.phase == Phase::Active {
                    entry.attempt_id = AttemptId(1);
                    *attempt = Some(Attempt::new());
                }
                entry.phase = Phase::Failed;
                let attempt = attempt.as_ref().map(Arc::clone);
                drop(state);
                if let Some(attempt) = attempt {
                    attempt.finish(Err(CloseError::WorkerStopped));
                }
            }
            _ => return,
        }
        self.changed();
    }

    pub(crate) fn request_member(self: &Arc<Self>, id: ResourceId) {
        let _ = self.close_member(id, false);
    }

    pub(crate) fn close_member(
        self: &Arc<Self>,
        id: ResourceId,
        retry: bool,
    ) -> Option<Arc<Attempt<E>>> {
        let mut state = self.state();
        let entry = state.entries.get_mut(&id)?;
        let EntryKind::Async {
            token,
            resource,
            attempt,
            close_requested,
        } = &mut entry.kind
        else {
            return None;
        };
        let mut request = None;
        let mut spawn = None;
        match entry.phase {
            Phase::Opening => {
                *close_requested = true;
                request = Some((None, token.clone()));
            }
            Phase::Active => {
                entry.phase = Phase::Closing;
                entry.attempt_id = AttemptId(1);
                let cell = Attempt::new();
                *attempt = Some(Arc::clone(&cell));
                request = Some((resource.clone(), token.clone()));
            }
            Phase::Failed if retry => {
                entry.phase = Phase::Closing;
                entry.attempt_id = AttemptId(
                    entry
                        .attempt_id
                        .0
                        .checked_add(1)
                        .expect("attempt ID space exhausted"),
                );
                let cell = Attempt::new();
                *attempt = Some(Arc::clone(&cell));
                let tracked = self.tracker.token();
                self.worker_registered();
                let guard = WorkerGuard::new(Arc::clone(self), id);
                spawn = Some((
                    entry.attempt_id,
                    Arc::clone(&cell),
                    resource.as_ref().expect("failed resource retained").clone(),
                    guard,
                    tracked,
                ));
            }
            _ => {}
        }
        let result = attempt.clone();
        drop(state);
        if let Some((resource, token)) = request {
            if let Some(resource) = resource {
                request_resource(&resource);
            }
            token.cancel();
        }
        if let Some((attempt_id, cell, resource, guard, tracked)) = spawn {
            worker::spawn_cleanup(
                Arc::clone(self),
                id,
                attempt_id,
                cell,
                resource,
                guard,
                tracked,
            );
        }
        self.changed();
        result
    }

    fn seal(self: &Arc<Self>) {
        let mut state = self.state();
        if state.phase != ScopePhase::Open {
            return;
        }
        state.phase = ScopePhase::Closing;
        self.tracker.close();
        let children = state.children.clone();
        let ids: Vec<_> = state
            .entries
            .iter()
            .filter_map(|(&id, entry)| matches!(entry.kind, EntryKind::Async { .. }).then_some(id))
            .collect();
        drop(state);
        // Each member remains under the same gate: a concurrent factory sees the
        // sealed scope before it is allowed to publish its result.
        for id in ids {
            self.request_member(id);
        }
        for child in children {
            child.seal();
        }
        self.changed();
        self.retire_if_empty();
    }

    fn run_registration(&self, id: ResourceId) {
        let mut state = self.state();
        let Some(entry) = state.entries.get_mut(&id) else {
            return;
        };
        let EntryKind::Sync { cleanup } = &mut entry.kind else {
            return;
        };
        let Some(cleanup) = cleanup.take() else {
            return;
        };
        entry.phase = Phase::Closing;
        drop(state);
        self.changed();
        let result = catch_unwind(AssertUnwindSafe(cleanup));
        let mut state = self.state();
        if let Some(entry) = state.entries.remove(&id)
            && result.is_err()
        {
            state.diagnostics.push(FailedResource {
                resource: entry.info,
                attempt_id: AttemptId(1),
                phase: Phase::Closing,
                error: CloseError::Panicked,
                retained: false,
            });
        }
        drop(state);
        self.changed();
        self.retire_if_empty();
    }

    fn run_callbacks(&self) {
        let (ids, children) = {
            let state = self.state();
            (
                state
                    .entries
                    .iter()
                    .filter_map(|(&id, entry)| {
                        matches!(entry.kind, EntryKind::Sync { .. }).then_some(id)
                    })
                    .collect::<Vec<_>>(),
                state.children.clone(),
            )
        };
        for id in ids {
            self.run_registration(id);
        }
        for child in children {
            child.run_callbacks();
        }
    }

    pub(crate) fn retire_if_empty(&self) {
        let can_retire = {
            let mut state = self.state();
            let released = state.phase != ScopePhase::Open
                && state.entries.is_empty()
                && state
                    .children
                    .iter()
                    .all(|child| child.state().phase == ScopePhase::Closed)
                && self.tracker.is_empty();
            if released {
                state.phase = ScopePhase::Closed;
            }
            released && state.children.is_empty() && state.diagnostics.is_empty()
        };
        if let Some(parent) = self.parent.upgrade() {
            if can_retire {
                let mut state = parent.state();
                state.children.retain(|child| child.id != self.id);
                drop(state);
                parent.changed();
            }
            parent.retire_if_empty();
        }
    }

    fn tree_scopes(self: &Arc<Self>) -> Vec<Arc<Self>> {
        let mut todo = vec![Arc::clone(self)];
        let mut scopes = Vec::new();
        while let Some(scope) = todo.pop() {
            todo.extend(scope.state().children.iter().cloned());
            scopes.push(scope);
        }
        scopes
    }

    fn report(self: &Arc<Self>) -> CloseReport<E> {
        let mut report = CloseReport {
            scope_id: self.id,
            sealed: true,
            workers_finished: true,
            failures: Vec::new(),
            pending: Vec::new(),
        };
        for scope in self.tree_scopes() {
            let state = scope.state();
            report.sealed &= state.phase != ScopePhase::Open;
            report.workers_finished &= scope.tracker.is_empty();
            report.failures.extend(state.diagnostics.iter().cloned());
            for entry in state.entries.values() {
                match entry.phase {
                    Phase::Opening | Phase::Closing => report.pending.push(PendingResource {
                        resource: entry.info.clone(),
                        attempt_id: entry.attempt_id,
                        phase: entry.phase,
                    }),
                    Phase::Active if state.phase != ScopePhase::Open => {
                        report.pending.push(PendingResource {
                            resource: entry.info.clone(),
                            attempt_id: entry.attempt_id,
                            phase: Phase::Closing,
                        })
                    }
                    Phase::Failed => {
                        if let EntryKind::Async {
                            attempt: Some(attempt),
                            ..
                        } = &entry.kind
                        {
                            if let Some(error) = attempt.error() {
                                report.failures.push(FailedResource {
                                    resource: entry.info.clone(),
                                    attempt_id: entry.attempt_id,
                                    phase: Phase::Closing,
                                    error,
                                    retained: true,
                                });
                            } else {
                                report.pending.push(PendingResource {
                                    resource: entry.info.clone(),
                                    attempt_id: entry.attempt_id,
                                    phase: Phase::Closing,
                                });
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        report
    }

    async fn wait(self: &Arc<Self>, deadline: Option<Instant>) -> CloseReport<E> {
        let mut changes = self.tree.changed.subscribe();
        loop {
            self.run_callbacks();
            let generation = self.generation.value.load(Ordering::SeqCst);
            let report = self.report();
            if generation != self.generation.value.load(Ordering::SeqCst)
                && deadline.is_none_or(|deadline| Instant::now() < deadline)
            {
                continue;
            }
            if report.sealed && report.workers_finished && report.pending.is_empty() {
                return report;
            }
            match deadline {
                Some(deadline) => {
                    if tokio::time::timeout_at(deadline, changes.changed())
                        .await
                        .is_err()
                    {
                        return self.report();
                    }
                }
                None => {
                    let _ = changes.changed().await;
                }
            }
        }
    }

    fn retry_existing(self: &Arc<Self>, selected: Vec<(Arc<Self>, ResourceId, AttemptId)>) {
        for (scope, id, previous) in selected {
            scope.retry_if_matching(id, previous);
        }
    }

    fn retry_if_matching(self: &Arc<Self>, id: ResourceId, previous: AttemptId) {
        // The selection and transition must be atomic with respect to other retries.
        let mut state = self.state();
        let Some(entry) = state.entries.get_mut(&id) else {
            return;
        };
        if entry.phase != Phase::Failed || entry.attempt_id != previous {
            return;
        }
        let EntryKind::Async {
            resource: Some(resource),
            attempt,
            ..
        } = &mut entry.kind
        else {
            return;
        };
        entry.phase = Phase::Closing;
        entry.attempt_id = AttemptId(
            previous
                .0
                .checked_add(1)
                .expect("attempt ID space exhausted"),
        );
        let cell = Attempt::new();
        *attempt = Some(Arc::clone(&cell));
        let resource = Arc::clone(resource);
        let attempt_id = entry.attempt_id;
        let tracked = self.tracker.token();
        self.worker_registered();
        let guard = WorkerGuard::new(Arc::clone(self), id);
        drop(state);
        worker::spawn_cleanup(
            Arc::clone(self),
            id,
            attempt_id,
            cell,
            resource,
            guard,
            tracked,
        );
        self.changed();
    }
}

pub(crate) fn request_resource<E: Send + Sync + 'static>(resource: &Arc<dyn ErasedResource<E>>) {
    // A broken implementation must not make an owner's Drop panic.
    let _ = catch_unwind(AssertUnwindSafe(|| resource.request_close()));
}

struct OpeningGuard<E: Send + Sync + 'static> {
    scope: Arc<Scope<E>>,
    id: ResourceId,
    armed: bool,
}
impl<E: Send + Sync + 'static> Drop for OpeningGuard<E> {
    fn drop(&mut self) {
        if self.armed {
            self.scope.request_member(self.id);
        }
    }
}

/// 作用域的唯一所有者。丢弃时请求尽力而为的清理，不等待异步工作。
pub struct ScopeOwner<E: Send + Sync + 'static> {
    scope: Arc<Scope<E>>,
}

impl<E: Send + Sync + 'static> ScopeOwner<E> {
    pub fn new(label: &'static str, runtime: Handle) -> Self {
        let (changed, _) = watch::channel(0);
        let tree = Arc::new(Tree {
            next_scope: AtomicU64::new(1),
            changed,
        });
        Self {
            scope: Scope::create(ScopeId(0), label, runtime, Weak::new(), tree, None),
        }
    }
    pub fn handle(&self) -> ScopeHandle<E> {
        ScopeHandle {
            scope: Arc::downgrade(&self.scope),
        }
    }
    /// 封闭作用域并请求取消，不等待清理。
    /// 同步登记在凭证或所有者丢弃时，或显式等待作用域关闭时执行。
    pub fn request_close(&self) {
        self.scope.seal();
    }
    /// 使用同一个绝对截止时刻等待本作用域及子作用域；超时不会取消清理工作。
    pub async fn close(&self, deadline: Instant) -> CloseReport<E> {
        self.request_close();
        self.scope.run_callbacks();
        self.scope.wait(Some(deadline)).await
    }
    /// 无截止时刻地等待本轮工作；失败成员不会令本方法等待未来重试。
    pub async fn wait_closed(&self) -> CloseReport<E> {
        self.request_close();
        self.scope.run_callbacks();
        self.scope.wait(None).await
    }
    /// 对本次调用选中的已有失败成员各启动一次重试，再等待当前作用域树。
    pub async fn retry_cleanup(&self, deadline: Instant) -> CloseReport<E> {
        let mut selected = Vec::new();
        for scope in self.scope.tree_scopes() {
            let ids: Vec<_> = scope
                .state()
                .entries
                .iter()
                .filter_map(|(&id, entry)| {
                    (entry.phase == Phase::Failed).then_some((id, entry.attempt_id))
                })
                .collect();
            selected.extend(
                ids.into_iter()
                    .map(|(id, attempt)| (Arc::clone(&scope), id, attempt)),
            );
        }
        self.request_close();
        self.scope.run_callbacks();
        self.scope.retry_existing(selected);
        self.scope.wait(Some(deadline)).await
    }
}

impl<E: Send + Sync + 'static> Drop for ScopeOwner<E> {
    fn drop(&mut self) {
        self.request_close();
        self.scope.run_callbacks();
        self.scope.retire_if_empty();
    }
}

/// 可克隆的弱能力，只能向开放作用域登记资源，不能延长所有者的生命周期。
pub struct ScopeHandle<E: Send + Sync + 'static> {
    scope: Weak<Scope<E>>,
}
impl<E: Send + Sync + 'static> Clone for ScopeHandle<E> {
    fn clone(&self) -> Self {
        Self {
            scope: self.scope.clone(),
        }
    }
}
impl<E: Send + Sync + 'static> ScopeHandle<E> {
    /// 新建子作用域。子作用域关闭不会关闭父作用域或兄弟作用域。
    pub fn child(&self, label: &'static str) -> Result<ScopeOwner<E>, ScopeClosed> {
        self.scope.upgrade().ok_or(ScopeClosed)?.child(label)
    }
    /// 登记同步解绑操作；拒绝登记时也会立即执行该操作。
    pub fn on_close<F>(
        &self,
        label: &'static str,
        cleanup: F,
    ) -> Result<Registration, RegistrationError>
    where
        F: FnOnce() + Send + 'static,
    {
        match self.scope.upgrade() {
            Some(scope) => scope.register(label, Box::new(cleanup)),
            None => registration::reject(Box::new(cleanup)),
        }
    }
    /// 先登记构造工作再运行工厂。取消等待不会丢弃工厂，迟到资源仍由作用域清理。
    pub async fn open<R, F, Fut>(
        &self,
        label: &'static str,
        factory: F,
    ) -> Result<Managed<R>, OpenError<E>>
    where
        R: ManagedResource<Error = E>,
        F: FnOnce(CancellationToken) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = Result<R, E>> + Send + 'static,
    {
        let scope = self.scope.upgrade().ok_or(OpenError::ScopeClosed)?;
        let OpenTicket {
            receiver,
            mut guard,
        } = scope
            .begin_open(label, factory)
            .map_err(|_| OpenError::ScopeClosed)?;
        let result = receiver.await.unwrap_or(Err(OpenError::WorkerStopped));
        guard.armed = false;
        result
    }
}
