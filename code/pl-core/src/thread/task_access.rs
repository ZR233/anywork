//! Restricted task capabilities; weak commands never keep their Thread alive.
use super::*;
use futures::future::select_all;
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    sync::{RwLock, Weak},
    time::Duration,
};

const COMPLETED_LEDGER_CAPACITY: usize = 256;

/// Bounded in-memory ledger of recently completed tasks and their deliveries.
#[derive(Debug, Default)]
pub(super) struct CompletedTaskLedger {
    order: VecDeque<String>,
    by_id: BTreeMap<String, cold::DurableToolTask>,
    by_call_id: BTreeMap<String, String>,
}

impl CompletedTaskLedger {
    pub(super) fn record(&mut self, task: task::TaskRecord, delivery: Option<ToolDelivery>) {
        if task.status == task::TaskStatus::Running {
            return;
        }
        let id = task.id.clone();
        let call_id = task.call_id.clone();
        if let Some(existing) = self.by_id.get_mut(&id) {
            if existing.task == task && existing.delivery.is_none() {
                existing.delivery = delivery;
            }
            return;
        }
        self.order.push_back(id.clone());
        if self.order.len() > COMPLETED_LEDGER_CAPACITY
            && let Some(evicted_id) = self.order.pop_front()
            && let Some(removed) = self.by_id.remove(&evicted_id)
        {
            self.by_call_id.remove(&removed.task.call_id);
        }
        self.by_call_id.insert(call_id, id.clone());
        self.by_id
            .insert(id, cold::DurableToolTask { task, delivery });
    }

    pub(super) fn get(&self, id: &str) -> Option<cold::DurableToolTask> {
        self.by_id
            .get(id)
            .or_else(|| {
                self.by_call_id
                    .get(id)
                    .and_then(|task_id| self.by_id.get(task_id))
            })
            .cloned()
    }
}

/// A coherent wait result; pending messages remain unconsumed until model admission.
#[derive(Debug, Clone)]
pub struct TaskWaitSnapshot {
    /// Known selected tasks in request order. A pending lookup can leave an identity unresolved.
    pub tasks: Vec<task::TaskRecord>,
    pub messages_ready: bool,
    pub user_inputs_ready: bool,
    /// True only when the fixed deadline was reached without a ready task, message, or user input.
    pub timed_out: bool,
}

/// Thread-local task reads and explicitly granted controls for one running tool call.
#[derive(Debug, Clone)]
pub struct TaskAccess {
    executor: crate::tool::opaque::ExecutionAuthority,
    authorization: Option<crate::tool::opaque::ToolAuthorization>,
    snapshots: watch::Receiver<super::subscription::OwnerPublication>,
    effect_window: Arc<EffectWindow>,
    completed_tasks: Arc<RwLock<CompletedTaskLedger>>,
    storage: Option<Weak<dyn cold::ErasedStorage>>,
    thread_id: String,
    cancellation: CancellationToken,
    commands: mpsc::WeakSender<handle::LoopEvent>,
    caller: String,
    may_wait: bool,
    may_cancel: bool,
    nested_catalog: Arc<[NestedToolDeclaration]>,
    pub(super) nested_invocations: Arc<std::sync::Mutex<Vec<String>>>,
}

/// One frozen program-only binding. The payload is the original host declaration.
#[derive(Debug, Clone)]
pub struct NestedToolDeclaration {
    pub declaration: ModelToolDeclaration,
    pub parallel: bool,
}
impl TaskAccess {
    /// Owner-assigned identity of the invocation holding this capability.
    /// Reading it neither creates a task nor grants additional control permission.
    pub fn current_task_id(&self) -> &str {
        &self.caller
    }

    pub(crate) fn with_nested_plan(
        mut self,
        plan: Option<Arc<crate::tool::opaque::ToolPlan>>,
    ) -> Self {
        self.nested_catalog = plan
            .as_ref()
            .map(|plan| {
                plan.nested()
                    .map(|(_, tool)| NestedToolDeclaration {
                        declaration: tool.declaration().clone(),
                        parallel: tool.nested_policy().expect("filtered policy").parallel,
                    })
                    .collect::<Vec<_>>()
                    .into()
            })
            .unwrap_or_else(|| Arc::from([]));
        self
    }
    pub fn nested_tools(&self) -> Vec<NestedToolDeclaration> {
        self.nested_catalog.to_vec()
    }
    /// Owner-assigned identities of this invocation's admitted children, in submission order.
    /// This derived index contains no executors or grants.
    pub fn nested_call_ids(&self) -> Vec<String> {
        self.nested_invocations
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
    }
    /// Dispatches through the original owner. No executor or grant crosses this capability.
    /// A committed terminal fact includes failed and cancelled outcomes. An error means the call
    /// could not be admitted or its completion could not be obtained from the owner.
    pub async fn call_nested(
        &self,
        tool_id: String,
        arguments: OpaquePayload,
        cancellation: CancellationToken,
    ) -> Result<ToolCompletion, ThreadError> {
        if self.nested_catalog.is_empty() {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::InvokeNested {
                caller: self.caller.clone(),
                executor: self.executor.clone(),
                tool_id,
                arguments,
                cancellation,
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }
    /// Waits for every admitted child to settle, even after the program was cancelled.
    pub async fn drain_nested(&self) -> Result<(), ThreadError> {
        let parent = self
            .caller
            .strip_prefix("task:")
            .ok_or(ThreadError::InvalidIdentity)?;
        let mut snapshots = self.snapshots.clone();
        loop {
            if !snapshots.borrow_and_update().tasks.values().any(|task| {
                task.parent_call_id.as_deref() == Some(parent)
                    && task.status == task::TaskStatus::Running
            }) {
                return Ok(());
            }
            snapshots.changed().await.map_err(|_| ThreadError::Closed)?;
        }
    }
    pub(super) fn new(
        owner: &Owner,
        caller: &str,
        executor: &crate::tool::opaque::FrozenTool,
        cancellation: CancellationToken,
    ) -> Self {
        let permissions = executor.task_permissions();
        Self {
            executor: executor.authority(),
            authorization: permissions.authorization,
            snapshots: owner.publish.subscribe(),
            effect_window: owner.effect_window.clone(),
            completed_tasks: owner.completed_tasks.clone(),
            storage: owner
                .cold
                .as_ref()
                .map(|storage| Arc::downgrade(&storage.0)),
            thread_id: owner.id.clone(),
            cancellation,
            commands: owner.task_commands.clone(),
            caller: format!("task:{caller}"),
            may_wait: permissions.wait,
            may_cancel: permissions.cancel,
            nested_catalog: Arc::from([]),
            nested_invocations: Arc::new(std::sync::Mutex::new(Vec::new())),
        }
    }

    /// Publishes an opaque execution receipt through the reliable Thread effect queue.
    /// The host folds each committed receipt into durable accounting; it never changes model context.
    ///
    /// # Errors
    /// Rejects completed callers and closed owners. Cancellation or revoked execution permission does
    /// not reject an already incurred receipt; this operation grants no execution permission.
    pub async fn record_observation(&self, payload: OpaquePayload) -> Result<(), ThreadError> {
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::RecordTaskObservation {
                caller: self.caller.clone(),
                payload,
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Registers a durable model review bound to this running task's Thread and Turn.
    pub async fn begin_model_review(
        &self,
    ) -> Result<ModelSettlementPort, crate::model::ModelMemberError> {
        use crate::model::ModelMemberError;
        let (reply, response) = oneshot::channel();
        self.commands
            .upgrade()
            .ok_or(ModelMemberError::Closed)?
            .send(handle::LoopEvent::OpenAuxiliaryModel {
                caller: Some(self.caller.clone()),
                turn_id: None,
                reply,
            })
            .await
            .map_err(|_| ModelMemberError::Closed)?;
        response.await.map_err(|_| ModelMemberError::Closed)?
    }

    pub(crate) async fn validate_execution(&self) -> Result<(), ThreadError> {
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::ValidateExecution {
                caller: self.caller.clone(),
                executor: self.executor.clone(),
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Requests one execution decision for this exact running call and waits without consuming context.
    ///
    /// # Errors
    /// Rejects expired or revoked callers, cancellation, conflicting repeated prompts and closed owners.
    pub async fn request_execution_permission(
        &self,
        payload: OpaquePayload,
        cancellation: CancellationToken,
    ) -> Result<permissions::PermissionDecision, ThreadError> {
        if cancellation.is_cancelled() {
            return Err(ThreadError::Cancelled);
        }
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::RequestPermission {
                caller: self.caller.clone(),
                authority: self.executor.clone(),
                payload,
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        let record = response.await.map_err(|_| ThreadError::Closed)??;
        let mut snapshots = self.snapshots.clone();
        loop {
            if cancellation.is_cancelled() {
                return Err(ThreadError::Cancelled);
            }
            {
                let snapshot = snapshots.borrow_and_update();
                self.ensure_running(&snapshot)?;
                let current = snapshot
                    .permissions
                    .get(&record.id)
                    .ok_or(ThreadError::InvalidIdentity)?;
                match current.state {
                    permissions::PermissionState::Allowed => {
                        return Ok(permissions::PermissionDecision::Allow);
                    }
                    permissions::PermissionState::Denied => {
                        return Ok(permissions::PermissionDecision::Deny);
                    }
                    permissions::PermissionState::Cancelled => return Err(ThreadError::Cancelled),
                    permissions::PermissionState::Pending => {}
                }
            }
            tokio::select! {
                _ = cancellation.cancelled() => return Err(ThreadError::Cancelled),
                changed = snapshots.changed() => changed.map_err(|_| ThreadError::Closed)?,
            }
        }
    }

    /// Reports one increment of this running call's live output without committing history or model
    /// context.
    ///
    /// The producer sends only what changed — one chunk for an append, or the whole bounded window
    /// when it rolled over — and the owner charges the resulting accepted total against the call's
    /// reliable output quota before it accepts the increment. A refused increment therefore leaves
    /// the accepted output exactly as it was, and the producer never keeps a second full copy of the
    /// output it is streaming.
    ///
    /// # Errors
    /// Rejects an output identity or total beyond the live bound, an expired or revoked executor
    /// and a closed owner.
    pub async fn report_output(
        &self,
        update: crate::model::ToolProgressUpdate,
    ) -> Result<(), ThreadError> {
        self.ensure_running(&self.snapshots.borrow())?;
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::ToolProgress {
                caller: self.caller.clone(),
                executor: self.executor.clone(),
                update,
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Reports that this running call's accepted output could not be stored.
    ///
    /// A capture write or archive failure is a fact about accepted output, not about the call's final
    /// result, so the tool reports it through this reliable, bounded channel as soon as it happens:
    /// the owner latches the typed fault — and blocks other model/tool admission — before the call
    /// returns, instead of only when `execute` unwinds. The fault keeps its
    /// [`cold::OutputRetryObligation`], so the pause stays until that exact obligation is retried and
    /// its bytes really stored; a healthy history write cannot stand in for it.
    ///
    /// # Errors
    /// Rejects an expired or revoked executor and a closed owner; the latch itself is idempotent.
    pub async fn report_output_storage_fault(
        &self,
        fault: Arc<cold::OutputStorageFault>,
    ) -> Result<(), ThreadError> {
        self.ensure_running(&self.snapshots.borrow())?;
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::ToolOutputStorageFault {
                caller: self.caller.clone(),
                executor: self.executor.clone(),
                fault,
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Lists this Thread's immutable task metadata in stable task-identity order.
    /// Reading does not consume messages, authorize cancellation or keep the owner alive.
    pub fn list(&self) -> Vec<task::TaskRecord> {
        self.snapshots.borrow().tasks.values().cloned().collect()
    }

    /// Reads immutable task metadata without consuming a message or result.
    ///
    /// # Errors
    /// Rejects a task not owned by this Thread.
    pub fn get(&self, id: &str) -> Result<task::TaskRecord, ThreadError> {
        let snapshot = self.snapshots.borrow();
        snapshot
            .tasks
            .get(id)
            .or_else(|| {
                snapshot
                    .terminal_tasks
                    .iter()
                    .find(|record| record.id == id)
            })
            .cloned()
            .ok_or_else(|| ThreadError::TaskNotFound { task_id: id.into() })
    }

    /// Reads a terminal result; `None` means execution has not committed a terminal state.
    ///
    /// # Errors
    /// Rejects unknown tasks or an inconsistent terminal result reference.
    pub fn result(&self, id: &str) -> Result<Option<ToolDelivery>, ThreadError> {
        let snapshot = self.snapshots.borrow();
        self.ensure_running(&snapshot)?;
        let task = snapshot
            .tasks
            .get(id)
            .or_else(|| {
                snapshot
                    .terminal_tasks
                    .iter()
                    .find(|record| record.id == id)
            })
            .ok_or_else(|| ThreadError::TaskNotFound { task_id: id.into() })?;

        if task.status == task::TaskStatus::Running {
            return Ok(None);
        }
        if let Some(delivery) = self
            .completed(id)
            .filter(|fact| fact.task.id == id)
            .and_then(|fact| fact.delivery)
        {
            return Ok(Some(delivery));
        }
        // A result still owed to model context is resident. Unsaved results remain in the
        // reliable effect window and older results are accessible through `durable`.
        let call_id = task.call_id.as_str();
        if let Some(delivery) = snapshot
            .deliveries
            .iter()
            .find(|delivery| delivery.call_id == call_id)
        {
            return Ok(Some(delivery.clone()));
        }
        match recent_effect_fact(&self.effect_window, |effect| {
            effect
                .deliveries
                .iter()
                .rev()
                .find(|delivery| delivery.call_id == call_id)
                .cloned()
        }) {
            Some(delivery) => Ok(Some(delivery)),
            None => Err(ThreadError::InvalidOutput),
        }
    }

    /// Reads a terminal task and its original delivery from the live window or attached History.
    /// A missing identity remains unknown. No execution or delivery is repeated.
    pub async fn durable(&self, id: &str) -> Result<Option<cold::DurableToolTask>, ThreadError> {
        self.validate_execution().await?;
        let cached = self.completed(id);
        if cached.as_ref().is_some_and(|fact| fact.delivery.is_some()) {
            return Ok(cached);
        }
        {
            let snapshot = self.snapshots.borrow();
            if let Some(task) = snapshot
                .tasks
                .get(id)
                .or_else(|| snapshot.tasks.values().find(|task| task.call_id == id))
                && task.status != task::TaskStatus::Running
                && let Some(delivery) = snapshot
                    .deliveries
                    .iter()
                    .find(|delivery| delivery.call_id == task.call_id)
            {
                return Ok(Some(cold::DurableToolTask {
                    task: task.clone(),
                    delivery: Some(delivery.clone()),
                }));
            }
        }
        if let Some(fact) = recent_effect_fact(&self.effect_window, |effect| {
            let task = effect.tasks.iter().find(|task| {
                task.status != task::TaskStatus::Running && (task.id == id || task.call_id == id)
            })?;
            let delivery = effect
                .deliveries
                .iter()
                .find(|delivery| delivery.call_id == task.call_id)?;
            Some(cold::DurableToolTask {
                task: task.clone(),
                delivery: Some(delivery.clone()),
            })
        }) {
            return Ok(Some(fact));
        }
        let Some(storage) = self.storage.as_ref().and_then(Weak::upgrade) else {
            return Ok(cached);
        };
        let saved = tokio::select! {
            biased;
            _ = self.cancellation.cancelled() => return Err(ThreadError::Cancelled),
            read = storage.read_saved_tool_task(&self.thread_id, id) => read,
        };
        self.validate_execution().await?;
        let saved = saved.map_err(|error| ThreadError::Storage(Arc::new(error)))?;
        if let Some(fact) = &saved {
            let task = &fact.task;
            if (task.id != id && task.call_id != id)
                || task.id != format!("task:{}", task.call_id)
                || task.status == task::TaskStatus::Running
                || task.invocation.as_ref().is_some_and(|invocation| {
                    invocation.call_id != task.call_id || invocation.tool_id != task.tool_id
                })
                || fact.delivery.as_ref().is_some_and(|delivery| {
                    delivery.call_id != task.call_id
                        || delivery.tool_id != task.tool_id
                        || task.status != task::TaskStatus::from_outcome(&delivery.outcome)
                        || match &delivery.target {
                            ToolDeliveryTarget::Nested { parent_call_id } => {
                                task.parent_call_id.as_ref() != Some(parent_call_id)
                            }
                            _ => task.parent_call_id.is_some(),
                        }
                })
            {
                return Err(ThreadError::InvalidIdentity);
            }
        }
        Ok(saved.or(cached))
    }

    fn completed(&self, id: &str) -> Option<cold::DurableToolTask> {
        self.completed_tasks
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
    }

    /// Waits for any selected task to finish or for a pending Thread message.
    /// Empty IDs wait only for messages. This operation never consumes inbox contents or cancels
    /// selected tasks. The readiness deadline is fixed on entry, including across unrelated wakes;
    /// the final observation always checks committed readiness before reporting a timeout.
    ///
    /// While waiting for readiness, archived identities are resolved from the Thread's durable
    /// facts. Readiness and the fixed deadline may return a snapshot with unresolved identities
    /// omitted. A missing or unreadable original reported by storage is an error.
    ///
    /// # Errors
    /// Rejects missing or revoked permission, self-waits, stale callers, unknown tasks, an
    /// unrepresentable deadline, cancelled waits and durable read failures.
    pub async fn wait(
        &self,
        ids: &[String],
        timeout: Duration,
        cancellation: CancellationToken,
    ) -> Result<TaskWaitSnapshot, ThreadError> {
        if !self.may_wait {
            return Err(ThreadError::TaskAccessDenied);
        }
        if ids.iter().any(|id| id == &self.caller) {
            return Err(ThreadError::TaskSelfWait);
        }
        let deadline = tokio::time::Instant::now()
            .checked_add(timeout)
            .ok_or(ThreadError::InvalidWaitTimeout)?;
        let mut snapshots = self.snapshots.clone();
        // Only immutable terminal facts are retained locally, for this wait alone. Live task and
        // inbox state always come from the same owner observation, never from a second registry.
        let mut archived = BTreeMap::new();
        let mut lookups = BTreeMap::new();
        loop {
            if cancellation.is_cancelled() {
                return Err(ThreadError::Cancelled);
            }
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => return Err(ThreadError::Cancelled),
                validated = self.validate_execution() => validated?,
            }
            let (observed, missing, ready) = {
                let snapshot = snapshots.borrow_and_update();
                self.ensure_running(&snapshot)?;
                let mut tasks = Vec::with_capacity(ids.len());
                let mut missing = BTreeSet::new();
                for id in ids {
                    let known = snapshot
                        .tasks
                        .get(id)
                        .or_else(|| {
                            snapshot
                                .terminal_tasks
                                .iter()
                                .find(|record| record.id == *id)
                        })
                        .or_else(|| archived.get(id.as_str()))
                        .cloned()
                        .or_else(|| {
                            self.completed(id)
                                .map(|fact| fact.task)
                                .filter(|task| task.id == *id)
                        })
                        .or_else(|| {
                            recent_effect_fact(&self.effect_window, |effect| {
                                effect
                                    .tasks
                                    .iter()
                                    .rev()
                                    .find(|task| {
                                        task.id == *id && task.status != task::TaskStatus::Running
                                    })
                                    .cloned()
                            })
                        });
                    match known {
                        Some(task) => tasks.push(task),
                        None => {
                            missing.insert(id.as_str());
                        }
                    }
                }

                // The resident queue holds only pending messages/inputs, so readiness checks for any
                // pending entry instead of polling lengths.
                let messages_ready = snapshot
                    .inbox
                    .iter()
                    .any(|record| record.sequence > snapshot.consumed_messages);
                let user_inputs_ready = snapshot
                    .inputs
                    .iter()
                    .any(|record| record.state == input::InputState::Pending);
                let ready = messages_ready
                    || user_inputs_ready
                    || tasks
                        .iter()
                        .any(|task| task.status != task::TaskStatus::Running);
                (
                    TaskWaitSnapshot {
                        tasks,
                        messages_ready,
                        user_inputs_ready,
                        // Check the clock while still borrowing this exact observation: a publish
                        // between releasing the borrow and checking the clock cannot be missed.
                        timed_out: !ready && tokio::time::Instant::now() >= deadline,
                    },
                    missing,
                    ready,
                )
            };
            if ready {
                return Ok(observed);
            }
            if self.storage.is_none()
                && let Some(id) = ids.iter().find(|id| missing.contains(id.as_str()))
            {
                return Err(ThreadError::TaskNotFound {
                    task_id: id.clone(),
                });
            }
            if observed.timed_out {
                return Ok(observed);
            }
            // Keep each in-flight lookup through unrelated publications. Drop reads when their
            // identities become resident or when this wait returns.
            lookups.retain(|id, _| missing.contains(id));
            for id in missing {
                lookups
                    .entry(id)
                    .or_insert_with(|| Box::pin(async move { (id, self.durable(id).await) }));
            }
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => return Err(ThreadError::Cancelled),
                changed = snapshots.changed() => changed.map_err(|_| ThreadError::Closed)?,
                _ = tokio::time::sleep_until(deadline) => {},
                (id, fact) = async { select_all(lookups.values_mut()).await.0 }, if !lookups.is_empty() => {
                    lookups.remove(id);
                    match fact? {
                        Some(fact) if fact.task.id == id && fact.task.status != task::TaskStatus::Running => {
                            archived.insert(id, fact.task);
                        }
                        _ => return Err(ThreadError::TaskNotFound { task_id: id.into() }),
                    }
                }
            }
        }
    }

    /// Requests cancellation only while the granted caller task is still active.
    ///
    /// # Errors
    /// Rejects missing permission, expired callers, unknown targets or a closed owner.
    pub async fn cancel(&self, id: String) -> Result<task::TaskCancellationReceipt, ThreadError> {
        if !self.may_cancel {
            return Err(ThreadError::TaskAccessDenied);
        }
        self.ensure_running(&self.snapshots.borrow())?;
        let commands = self.commands.upgrade().ok_or(ThreadError::Closed)?;
        let (reply, response) = oneshot::channel();
        commands
            .send(handle::LoopEvent::ToolCancelTask {
                caller: self.caller.clone(),
                authorization: self.authorization.clone(),
                target: id.clone(),
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        match response.await.map_err(|_| ThreadError::Closed)? {
            Ok(receipt) => Ok(receipt),
            // The owner's terminal task ledger is bounded, so a finished task that left it is
            // adjudicated from the durable task lifecycle instead of being reported as unknown.
            // A durable terminal row is already finished, and a recorded cancellation request is
            // already requested: neither answer revives the task nor starts new work.
            Err(ThreadError::TaskNotFound { .. }) => {
                match self.durable(&id).await? {
                    Some(fact) if fact.task.status != task::TaskStatus::Running => {
                        Ok(task::TaskCancellationReceipt::AlreadyFinished)
                    }
                    Some(fact) if fact.task.cancel_requested => {
                        Ok(task::TaskCancellationReceipt::AlreadyRequested)
                    }
                    // A still-running task the owner does not know about is a real inconsistency:
                    // report it instead of inventing a cancellation receipt.
                    _ => Err(ThreadError::TaskNotFound { task_id: id }),
                }
            }
            Err(error) => Err(error),
        }
    }

    fn ensure_running(&self, snapshot: &ThreadSnapshot) -> Result<(), ThreadError> {
        if self
            .authorization
            .as_ref()
            .is_some_and(|authority| !authority.is_active())
        {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        if snapshot
            .tasks
            .get(&self.caller)
            .is_some_and(|task| task.status == task::TaskStatus::Running)
        {
            Ok(())
        } else {
            Err(ThreadError::TaskAccessExpired)
        }
    }
}
