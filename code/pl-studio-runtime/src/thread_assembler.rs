//! One assembly and resource-owner registry for root, child and restored Threads.
mod activation;
mod admission;
mod agent_close;
mod agent_close_recovery;
mod agent_evaluation;
mod agent_operations;
pub(crate) mod agent_review;
mod agent_services;
pub(crate) mod agent_wait;
mod agents;
pub(crate) use agents::AgentHost;

#[cfg(test)]
pub(crate) use agents::archive_tests::spawn_failed_archive_fixture;
#[cfg(test)]
pub(crate) use agents::archive_tests::spec as archive_test_spec;
pub(crate) mod delegation_models;
pub(crate) mod observation;
pub(crate) mod review_delivery;
pub(crate) mod review_dispatch;
pub use activation::{StudioActivationFactory, ThreadActivation, ThreadPreparation};
mod interaction_key;
mod user_input;
pub use user_input::{UserInteractionError, project_user_input};
mod interaction_router;
pub(crate) use interaction_key::encode as encode_interaction_key;
pub use interaction_key::{InteractionKeyError, decode_interaction_key};
pub(crate) use interaction_router::project_pending_child_interactions;
pub use interaction_router::{StudioInteractionError, project_thread_interaction};
mod approval;
mod permission_projection;
mod plan_confirmation;
pub(crate) use approval::authorize_remote_workspace;
pub(crate) use approval::{ApprovalHost, StudioApprovalOptions};
pub use permission_projection::{PermissionProjectionError, project_execution_permission};
pub(crate) use plan_confirmation::document_identity as plan_confirmation_document_identity;
pub use plan_confirmation::{PlanInteractionError, project_plan_confirmation};
mod child_resources;
pub use child_resources::WorkspacePreparationOwner;
mod children;
mod close_storage;
pub(crate) use agent_services::WorkspaceRecoveryPublisher;
pub(crate) use child_resources::CleanupGate;
pub(crate) use close_storage::CloseStorage;

/// Deletion releases the same owners without creating a final preservation obligation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ClosePurpose {
    Preserve,
    Delete,
}
mod published_resources;
mod report_receiver;
pub use children::{
    ChildThreadRequest, ConfiguredChildFactory, StudioChildFactory, StudioChildResources,
};
mod mcp;
pub(crate) mod media;
mod tools;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex},
};
pub use tools::{StudioCommandBinding, StudioGitBinding, StudioThreadTools, StudioWorkspaceTools};

pub use crate::studio::WorkspaceUsageLease;
use pl_core::{
    context::ResourceAccess,
    model::ModelFactory,
    thread::{
        ContextCapacity, ThreadCheckpoint, ThreadError, ThreadHandle, ThreadLifecycle,
        cold::ColdStoreHandle,
    },
    tool::opaque::Registration,
};
use pl_model::{config::ResolvedModelRoute, runtime::ThreadModel};
pub use pl_protocol::{DelegationSettings, PureError};

/// Product-selected collaboration exposure, independent from core tool scheduling.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum AgentControlExposure {
    #[default]
    Disabled,
    Enabled,
}

/// Already resolved product inputs. Tool instances are transferred once, never cloned.
pub struct StudioThreadSpec {
    /// Product factories supply the canonical workspace use. Standalone, non-Studio assemblers
    /// without a product workspace may leave this absent.
    pub workspace_usage: Option<WorkspaceUsageLease>,
    /// Owns unpublished preparation until the assembler registers its cleanup owner.
    pub preparation_guard: Option<ThreadPreparationGuard>,
    pub context_preparation: Option<pl_core::thread::context_preparation::ContextPreparer>,
    /// Root-only controls prepared from one Profile generation before allocating physical tools.
    pub agent_controls: Vec<Registration>,
    pub execution: pl_core::thread::input::InputDriverOptions,
    pub id: String,
    pub parent_id: Option<String>,
    pub route: ResolvedModelRoute,
    /// False publishes the owner without a physical model until a later deferred update succeeds.
    pub model_available: bool,
    pub model: ThreadModel,
    pub checkpoint: Option<ThreadCheckpoint>,
    /// Initial instructions and records for a new Thread only; never used to re-render recovery.
    pub initial_context: Vec<pl_core::context::ContextRecord>,
    /// Latest host facts queued after assembly. Recovery may supply them; they never re-render
    /// frozen instructions or replace restored history.
    pub initial_runtime_facts: Vec<pl_core::thread::RuntimeFact>,
    pub initial_extensions: BTreeMap<String, pl_core::context::OpaquePayload>,
    pub tools: Vec<Registration>,
    pub resources: ResourceAccess,
    pub capacity: ContextCapacity,
    pub cold_store: Option<ColdStoreHandle>,
}

impl StudioThreadSpec {
    fn frozen_delegation(&self) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
        let selection = match &self.checkpoint {
            Some(checkpoint) => crate::studio::delegation::saved(&checkpoint.state),
            None => self
                .initial_extensions
                .get(crate::studio::delegation::EXTENSION)
                .map(crate::studio::delegation::decode)
                .transpose(),
        }
        .map_err(|source| ThreadAssemblyError::Resource {
            operation: "decode frozen root delegation selection",
            source: source.into(),
        })?;
        selection.ok_or_else(|| {
            ThreadAssemblyError::Identity("root has no frozen delegation selection".into())
        })
    }
}

/// Synchronous ownership transfer for preparation that has not entered the owner registry.
pub struct ThreadPreparationGuard(Option<Box<dyn FnOnce() + Send + Sync>>);
impl ThreadPreparationGuard {
    pub(crate) fn new(cleanup: impl FnOnce() + Send + Sync + 'static) -> Self {
        Self(Some(Box::new(cleanup)))
    }
    fn disarm(mut self) {
        self.0.take();
    }
}
impl Drop for ThreadPreparationGuard {
    fn drop(&mut self) {
        if let Some(cleanup) = self.0.take() {
            cleanup();
        }
    }
}

impl std::fmt::Debug for StudioThreadSpec {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StudioThreadSpec")
            .field("id", &self.id)
            .field("parent_id", &self.parent_id)
            .field(
                "checkpoint_revision",
                &self
                    .checkpoint
                    .as_ref()
                    .map(|checkpoint| checkpoint.state_revision),
            )
            .field("tools", &self.tools.len())
            .finish_non_exhaustive()
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ThreadAssemblyError {
    #[error("Agent backend {backend:?} is not supported by the Native runtime")]
    UnsupportedBackend {
        backend: pl_protocol::AgentBackendKind,
    },
    #[error("Thread activation failed")]
    ActivationFailed(#[source] Arc<ThreadAssemblyError>),
    #[error("Thread resource preparation panicked")]
    ActivationPanicked,
    #[error("Thread {0} has unpublished resources requiring cleanup")]
    Unpublished(String),
    #[error("Studio resource operation failed: {operation}")]
    Resource {
        operation: &'static str,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    /// Only child workspace preparation exposes its existing safe operational diagnostic.
    /// Other resource boundaries deliberately keep their original redacted Display behavior.
    #[error("prepare child workspace failed: {source}")]
    ChildWorkspacePreparation {
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    #[error("only a root Thread may create child agents")]
    ChildDepth,
    #[error(
        "agent tree capacity of {0} reached (root, open and preparing children included); use close_agent only for agents whose delivery, review and revisions are all finished; idle agents awaiting integration must remain open"
    )]
    ChildCapacity(usize),
    #[error("Profile {0} does not accept a directory write scope")]
    WorkspaceScope(String),
    #[error("Profile {0} does not accept a review target")]
    ReviewTargetScope(String),
    #[error("review Profile {0} requires a review target agentId")]
    ReviewTargetMissing(String),
    #[error("review target {0} is not a reviewable child workspace")]
    ReviewTargetInvalid(String),
    #[error("child configuration resolution failed")]
    Configuration(#[from] crate::config::ConfigRuntimeError),
    #[error("child preparation worker failed")]
    PreparationWorker(#[from] tokio::task::JoinError),
    #[error("tool catalog registration failed")]
    Registry(#[from] pl_core::tool::opaque::RegistryError),
    #[error(transparent)]
    Definition(#[from] pl_agent_tool::DefinitionError),
    #[error(transparent)]
    ToolBinding(#[from] pl_tool::binding::BindingError),
    #[error("Thread assembly is closed")]
    Closed,
    #[error("initial context cannot replace restored Thread history during assembly")]
    InitialContextOnRecovery,
    #[error("Thread identity is already owned or has an invalid parent: {0}")]
    Identity(String),
    #[error("Thread tool binding was invalidated: {0}")]
    InvalidatedBinding(String),
    #[error("message identity {0} conflicts with an accepted delivery")]
    MessageConflict(String),
    #[error("message identity {0} is already accepted with an unverifiable body")]
    MessageUnverifiable(String),
    #[error("Thread {thread_id} workspace is unavailable: {reason}")]
    Workspace { thread_id: String, reason: String },
    #[error("Thread is still being assembled: {0}")]
    Preparing(String),
    #[error("Thread {0} workspace close disposition is already frozen")]
    CloseDisposition(String),
    #[error("Thread close is waiting for descendant {0}")]
    Descendant(String),
    #[error("Thread subtree close failed for {id}")]
    SubtreeClose {
        id: String,
        #[source]
        first: Box<ThreadAssemblyError>,
        others: Vec<(String, ThreadAssemblyError)>,
    },
    #[error("model binding construction failed")]
    Binding(#[from] pl_model::PureError),
    #[error("model session construction failed")]
    Model(#[from] pl_core::model::ModelError),
    #[error("Thread setup or close failed")]
    Thread(#[from] ThreadError),
    #[error("Thread {id} setup failed ({setup}); cleanup also failed ({cleanup})")]
    Cleanup {
        id: String,
        #[source]
        setup: Box<ThreadAssemblyError>,
        cleanup: Box<ThreadAssemblyError>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EntryPurpose {
    Execution,
    CloseStorage,
    ReportReceiver,
}

use crate::session::AgentInstance;
mod acp;

type ActivationOutcome = Result<ThreadHandle, Arc<ThreadAssemblyError>>;
#[derive(Debug)]
struct Preparation {
    resources: crate::session::PreparedResources,
    identity: Option<pl_protocol::AgentThreadIdentity>,
    /// The factory has stopped; its original preparation still owns settlement until ACK.
    settlement: Option<WorkspacePreparationOwner>,
    purpose: Option<activation::ActivationPurpose>,
    parent_id: Option<String>,
    cancellation: tokio_util::sync::CancellationToken,
    result: Option<tokio::sync::watch::Receiver<Option<ActivationOutcome>>>,
}

#[derive(Debug)]
struct FailedPreparation {
    resources: crate::session::PreparedResources,
    identity: Option<pl_protocol::AgentThreadIdentity>,
    settlement: Option<WorkspacePreparationOwner>,
    gate: tokio::sync::Mutex<()>,
}

#[derive(Debug, Default)]
struct State {
    #[cfg(test)]
    storage_attachment_gate: Option<close_storage::AttachmentAckGate>,
    #[cfg(test)]
    s2_settlement_probe: Option<Arc<s2_close_regression_tests::SettlementProbe>>,
    #[cfg(test)]
    s2_failed_retry_probe: Option<s2_close_regression_tests::FailedRetryProbe>,
    #[cfg(test)]
    s2_close_broadcast: Option<tokio::sync::oneshot::Sender<()>>,
    operation_gates: BTreeMap<String, std::sync::Weak<tokio::sync::Mutex<()>>>,
    sealed_agents: BTreeMap<String, usize>,
    agent_services: Option<Arc<agent_services::AgentServices>>,
    observation: Option<observation::AssemblyObservation>,
    child_factory: Option<children::ChildFactory>,
    closing: bool,
    creating: BTreeMap<String, Preparation>,
    preparing_children: BTreeMap<String, children::PreparingChild>,
    unpublished_children: BTreeMap<String, child_resources::UnpublishedChild>,
    entries: BTreeMap<String, AgentInstance>,
    by_agent: BTreeMap<pl_protocol::AgentId, String>,
    pending_activation: BTreeMap<String, crate::thread_assembler::ThreadActivation>,
    failed_preparations: BTreeMap<String, Arc<FailedPreparation>>,
}

impl State {
    fn insert_entry(&mut self, id: String, entry: AgentInstance) {
        self.by_agent
            .insert(entry.identity.agent_id.clone(), id.clone());
        self.entries.insert(id, entry);
    }

    fn remove_entry(&mut self, id: &str) -> Option<AgentInstance> {
        let entry = self.entries.remove(id)?;
        if self
            .by_agent
            .get(&entry.identity.agent_id)
            .is_some_and(|current| current == id)
        {
            self.by_agent.remove(&entry.identity.agent_id);
        }
        Some(entry)
    }

    /// 成员树父 Thread。只用冻结 `parent_agent_id` 解析，不从 Native 字段回退。
    fn membership_parent<'a>(
        by_agent: &'a BTreeMap<pl_protocol::AgentId, String>,
        entry: &'a AgentInstance,
    ) -> Option<&'a str> {
        if let Some(parent) = entry.identity.parent_agent_id.as_ref() {
            return by_agent.get(parent).map(String::as_str);
        }
        None
    }
}

pub(crate) type SessionCloseReport = Arc<Vec<(String, Arc<ThreadAssemblyError>)>>;

type CloseCompletion =
    futures::future::Shared<futures::future::BoxFuture<'static, SessionCloseReport>>;

#[derive(Debug)]
struct CloseLife {
    phase: crate::session::SessionPhase,
    last: Option<SessionCloseReport>,
    // Shared retains the JoinHandle and its result even when every external waiter is cancelled.
    current: Option<CloseCompletion>,
}

#[derive(Debug)]
pub(crate) struct Registry {
    pub(crate) session_id: pl_protocol::SessionId,
    state: Mutex<State>,
    changed: tokio::sync::Notify,
    life: Mutex<CloseLife>,
}

impl Registry {
    pub(crate) fn open(session_id: pl_protocol::SessionId) -> Self {
        Self {
            session_id,
            state: Mutex::new(State::default()),
            changed: tokio::sync::Notify::new(),
            life: Mutex::new(CloseLife {
                phase: crate::session::SessionPhase::Open,
                last: None,
                current: None,
            }),
        }
    }

    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn life(&self) -> std::sync::MutexGuard<'_, CloseLife> {
        self.life
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub(crate) fn phase(&self) -> crate::session::SessionPhase {
        self.life().phase
    }
}

impl Drop for Registry {
    fn drop(&mut self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing = true;
        for preparation in state.creating.values() {
            preparation.cancellation.cancel();
        }
        for child in state.preparing_children.values() {
            child.cancellation.cancel();
        }
        for entry in state.entries.values() {
            entry.cancel();
        }
    }
}

pub(crate) use crate::session::SessionRuntime;

pub(crate) struct Reservation {
    registry: Arc<Registry>,
    id: String,
}
impl Drop for Reservation {
    fn drop(&mut self) {
        let mut state = self.registry.state();
        if let Some(preparation) = state.creating.remove(&self.id)
            && (preparation.settlement.is_some()
                || (!state.entries.contains_key(&self.id)
                    && !state.unpublished_children.contains_key(&self.id)
                    && preparation.resources.has_obligations()))
        {
            state.failed_preparations.insert(
                self.id.clone(),
                Arc::new(FailedPreparation {
                    resources: preparation.resources,
                    identity: preparation.identity,
                    settlement: preparation.settlement,
                    gate: Default::default(),
                }),
            );
        }
        state.pending_activation.remove(&self.id);
        drop(state);
        self.registry.changed.notify_waiters();
    }
}

impl SessionRuntime {
    /// Retains the canonical default Thread address of a cold directory member,
    /// without materializing any execution resources for that member.
    pub(crate) fn retain_directory_identity(
        &self,
        identity: &pl_protocol::AgentThreadIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        if &identity.session_id != self.id() {
            return Err(ThreadAssemblyError::Identity(
                identity.thread_id.to_string(),
            ));
        }
        let mut state = self.0.state();
        if state.closing {
            return Err(ThreadAssemblyError::Closed);
        }
        if let Some(current) = state.by_agent.get(&identity.agent_id)
            && current != identity.thread_id.as_str()
        {
            return Err(ThreadAssemblyError::Identity(
                identity.thread_id.to_string(),
            ));
        }
        state
            .by_agent
            .insert(identity.agent_id.clone(), identity.thread_id.to_string());
        Ok(())
    }

    pub(crate) fn native_resources(
        &self,
        thread: &ThreadHandle,
    ) -> Result<Arc<crate::session::NativeResources>, ThreadAssemblyError> {
        self.0
            .state()
            .entries
            .values()
            .find(|entry| {
                entry
                    .native()
                    .is_ok_and(|native| native.thread.same_instance(thread))
            })
            .and_then(|entry| {
                let native = entry.native().ok()?;
                Some(native.resources.clone())
            })
            .ok_or(ThreadAssemblyError::Closed)
    }

    pub(crate) async fn close_failed_preparation(
        &self,
        id: &str,
    ) -> Result<(), ThreadAssemblyError> {
        let failed = self.0.state().failed_preparations.get(id).cloned();
        let Some(failed) = failed else {
            return Ok(());
        };
        #[cfg(test)]
        self.s2_failed_retry_checkpoint(id).await;
        let _permit = failed.gate.lock().await;
        // A waiter can retain an obsolete gate after another retry retired this owner.
        // Keep the qualified owner registered until cleanup ACKs so reserve stays blocked.
        if !self
            .0
            .state()
            .failed_preparations
            .get(id)
            .is_some_and(|current| Arc::ptr_eq(current, &failed))
        {
            return Ok(());
        }
        if let Some(workspace) = &failed.settlement {
            self.settle_failed_activation(id, workspace).await?;
        } else {
            self.close_prepared_resources(id, &failed.resources).await?;
        }
        let mut state = self.0.state();
        if state
            .failed_preparations
            .get(id)
            .is_some_and(|current| Arc::ptr_eq(current, &failed))
        {
            state.failed_preparations.remove(id);
        }
        Ok(())
    }

    async fn close_prepared_resources(
        &self,
        id: &str,
        resources: &crate::session::PreparedResources,
    ) -> Result<(), ThreadAssemblyError> {
        let scope = match resources {
            crate::session::PreparedResources::Native(native) => native,
            crate::session::PreparedResources::Acp(acp) => {
                let events = self
                    .0
                    .state()
                    .agent_services
                    .as_ref()
                    .map(|services| services.events.clone());
                let settlement = if let Some(events) = events {
                    acp.settle_association(&events).await.map_err(|source| {
                        ThreadAssemblyError::Resource {
                            operation: "settle successful ACP session association",
                            source: source.into_boxed_dyn_error(),
                        }
                    })
                } else {
                    Ok(())
                };
                let outcome = acp.close().await;
                settlement?;
                return if outcome.local_complete {
                    Ok(())
                } else {
                    Err(ThreadAssemblyError::Unpublished(id.into()))
                };
            }
        };
        scope
            .candidates
            .retry(None)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "close preparation candidates",
                source: source.into_boxed_dyn_error(),
            })?;
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services
                .factory
                .close_scope_tools(id, scope)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "close preparation binding and MCP",
                    source: source.into_boxed_dyn_error(),
                })?;
        }
        if scope.has_obligations() {
            return Err(ThreadAssemblyError::Unpublished(id.into()));
        }
        Ok(())
    }

    pub(crate) fn resource_scopes(&self) -> Vec<Arc<crate::session::NativeResources>> {
        let state = self.0.state();
        state
            .entries
            .values()
            .filter_map(|entry| {
                let native = entry.native().ok()?;
                Some(native.resources.clone())
            })
            .chain(
                state
                    .creating
                    .values()
                    .filter_map(|preparing| preparing.resources.native().cloned()),
            )
            .chain(
                state
                    .unpublished_children
                    .values()
                    .map(|child| child.workspace.native_resources()),
            )
            .chain(
                state
                    .failed_preparations
                    .values()
                    .filter_map(|failed| failed.resources.native().cloned()),
            )
            .collect()
    }
    pub(crate) fn hosts(&self, thread_id: &str) -> bool {
        let state = self.0.state();
        state.entries.contains_key(thread_id)
            || state.creating.contains_key(thread_id)
            || state.preparing_children.contains_key(thread_id)
            || state.unpublished_children.contains_key(thread_id)
            || state.failed_preparations.contains_key(thread_id)
    }

    /// 取出本次装配预先放入的目录身份。没有目录身份就拒绝，不从 ThreadId 合成 AgentId。
    fn consume_activation(&self, thread_id: &str) -> Result<ThreadActivation, ThreadAssemblyError> {
        let mut state = self.0.state();
        let activation = match state.pending_activation.remove(thread_id) {
            Some(activation) => activation,
            None => {
                let services = state
                    .agent_services
                    .as_ref()
                    .ok_or_else(|| ThreadAssemblyError::Identity(thread_id.to_owned()))?;
                let (agent, binding, parent_thread_id) = services
                    .events
                    .agent_execution_identity(thread_id)
                    .ok_or_else(|| ThreadAssemblyError::Identity(thread_id.to_owned()))?;
                ThreadActivation {
                    agent,
                    binding,
                    parent_thread_id,
                }
            }
        };
        activation.ensure_native()?;
        if &activation.agent.session_id != self.id() || activation.id() != thread_id {
            return Err(ThreadAssemblyError::Identity(thread_id.to_owned()));
        }
        Ok(activation)
    }

    #[cfg(test)]
    pub(crate) fn install_explicit_activation(&self, activation: ThreadActivation) {
        self.0
            .state()
            .pending_activation
            .insert(activation.id().to_owned(), activation);
    }

    /// Shared admission order for evaluation, cold activation, user/agent input and close.
    /// Never acquire a lifecycle lock while holding this permit. No model Turn is awaited here.
    pub(crate) async fn agent_operation(&self, id: &str) -> tokio::sync::OwnedMutexGuard<()> {
        let gate = {
            let mut state = self.0.state();
            match state
                .operation_gates
                .get(id)
                .and_then(std::sync::Weak::upgrade)
            {
                Some(gate) => gate,
                None => {
                    state
                        .operation_gates
                        .retain(|_, gate| gate.strong_count() > 0);
                    let gate = Arc::new(tokio::sync::Mutex::new(()));
                    state
                        .operation_gates
                        .insert(id.to_owned(), Arc::downgrade(&gate));
                    gate
                }
            }
        };
        gate.lock_owned().await
    }

    pub(crate) fn ensure_agent_admission_open(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let state = self.0.state();
        if let Some(entry) = state.entries.get(id)
            && let crate::session::AgentRuntime::Native(native) = &entry.runtime
            && crate::studio::agent_close::is_explicitly_closed(&native.thread.snapshot()).map_err(
                |source| ThreadAssemblyError::Resource {
                    operation: "read child close intent",
                    source: source.into(),
                },
            )?
        {
            return Err(ThreadAssemblyError::Closed);
        }
        if state.closing
            || state.sealed_agents.contains_key(id)
            || !state
                .entries
                .get(id)
                .is_some_and(|entry| match &entry.runtime {
                    crate::session::AgentRuntime::Native(native) => {
                        native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
                    }
                    crate::session::AgentRuntime::Acp(acp) => {
                        !acp.cancellation.is_cancelled() && acp.session().is_ok()
                    }
                })
        {
            return Err(ThreadAssemblyError::Closed);
        }
        Ok(())
    }
    /// Installs the product factory before publishing any Thread that can create descendants.
    ///
    /// # Errors
    /// Rejects changes after assembly has begun or shutdown has started.
    pub fn set_child_factory(
        &self,
        factory: impl StudioChildFactory,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        if state.closing || !state.entries.is_empty() || !state.creating.is_empty() {
            return Err(ThreadAssemblyError::Closed);
        }
        state.child_factory = Some(children::ChildFactory::new(factory));
        Ok(())
    }

    /// Validates history, opens a fresh model session, binds tools/services and publishes once.
    /// History recovery does not invoke models or tools or re-render old content.
    ///
    /// # Errors
    /// Rejects duplicate identities and corrupt history; failed cleanup keeps its owner registered.
    pub async fn assemble(
        &self,
        spec: StudioThreadSpec,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        let reservation = self.reserve(&spec.id, spec.parent_id.as_deref())?;
        self.assemble_reserved(spec, &reservation).await
    }

    async fn assemble_reserved(
        &self,
        mut spec: StudioThreadSpec,
        reservation: &Reservation,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        tracing::debug!(
            target: "conversation_work",
            thread_id = %spec.id,
            tool_or_ssh_initialization = 1,
            "execution resources requested"
        );
        if spec.id != reservation.id {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        if spec.id.is_empty()
            || spec.parent_id.as_deref() == Some(spec.id.as_str())
            || spec.parent_id.as_ref().is_some_and(String::is_empty)
        {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        if spec.checkpoint.is_some() && !spec.initial_context.is_empty() {
            return Err(ThreadAssemblyError::InitialContextOnRecovery);
        }
        pl_core::context::ContextSnapshot {
            revision: 0,
            records: spec.initial_context.clone().into(),
        }
        .validate_complete()
        .map_err(ThreadError::from)?;
        if spec
            .checkpoint
            .as_ref()
            .is_some_and(|checkpoint| checkpoint.thread_id != spec.id)
        {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        if spec.model_available {
            let services = { self.0.state().agent_services.clone() };
            if let Some(services) = services {
                let record = services.record(&spec.id).await.map_err(|source| {
                    ThreadAssemblyError::Resource {
                        operation: "resolve model archive admission",
                        source: source.into_boxed_dyn_error(),
                    }
                })?;
                services
                    .store
                    .ensure_archive_execution_allowed(&record.workspace_id, Some(&spec.id))
                    .await
                    .map_err(|source| ThreadAssemblyError::Resource {
                        operation: "model archive admission",
                        source: source.into_boxed_dyn_error(),
                    })?;
            }
        }
        let activation = self.consume_activation(&spec.id)?;
        if activation.parent_id() != spec.parent_id.as_deref() {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        let identity = activation.agent.clone();
        let binding = activation.binding.clone();
        let is_root = identity.parent_agent_id.is_none();
        if !is_root && !spec.agent_controls.is_empty() {
            return Err(ThreadAssemblyError::ChildDepth);
        }
        spec.tools.append(&mut spec.agent_controls);
        // Model opening is still owned by the managed preparation, including the unpublished
        // use. If it fails, install a cleanup-only Thread so every allocated tool is closed/joined.
        // Successful restoration keeps core's normal model-at-resume contract for pending inputs.
        let (thread, opening_failure) = if spec.model_available {
            match ModelFactory::new(spec.model).open_session().await {
                Ok(model) => (
                    ThreadHandle::resume(spec.id.clone(), model, spec.checkpoint)?,
                    None,
                ),
                Err(error) => (
                    ThreadHandle::resume_without_model(spec.id.clone(), spec.checkpoint)?,
                    Some(ThreadAssemblyError::from(error)),
                ),
            }
        } else {
            (
                ThreadHandle::resume_without_model(spec.id.clone(), spec.checkpoint)?,
                None,
            )
        };
        let resources = self
            .0
            .state()
            .creating
            .get(&spec.id)
            .expect("reserved preparation")
            .resources
            .require_native()?
            .clone();
        self.0.state().insert_entry(
            spec.id.clone(),
            crate::session::AgentInstance {
                identity,
                binding,
                runtime: crate::session::AgentRuntime::Native(Box::new(
                    crate::session::NativeThreadRuntime {
                        resources,
                        purpose: EntryPurpose::Execution,
                        workspace_usage: spec.workspace_usage.take(),
                        close_storage: None,
                        published_resources_closed: false,
                        workspace_disposition: None,
                        cleanup: Arc::new(child_resources::CleanupGate::default()),
                        execution: spec.execution,
                        incarnation: Arc::new(()),
                        parent_id: spec.parent_id,
                        ready: false,
                        thread: thread.clone(),
                    },
                )),
            },
        );
        let mut preparation_guard = spec.preparation_guard.take();
        let setup = async {
            thread
                .set_context_preparation(spec.context_preparation)
                .await?;
            thread.set_resources(spec.resources).await?;
            thread.set_capacity(spec.capacity).await?;
            if let Err(error) = thread.register_tools(spec.tools).await {
                match error {
                    ThreadError::RejectedTools(resources) => {
                        let diagnostic = resources.to_string();
                        self.native_resources(&thread)?
                            .candidates
                            .retain(thread.clone(), resources);
                        return Err(ThreadAssemblyError::Resource {
                            operation: "register prepared Thread tools",
                            source: Box::new(std::io::Error::other(diagnostic)),
                        });
                    }
                    error => return Err(error.into()),
                }
            }
            if let Some(error) = opening_failure {
                return Err(error);
            }
            if let Some(store) = spec.cold_store {
                self.attach_execution_storage(&spec.id, store).await?;
            }
            if !spec.initial_extensions.is_empty() {
                thread
                    .mutate_extensions(
                        spec.initial_extensions
                            .into_iter()
                            .map(|(id, payload)| {
                                pl_core::thread::extensions::ExtensionMutation::Put {
                                    id,
                                    expected_revision: None,
                                    payload,
                                }
                            })
                            .collect(),
                    )
                    .await?;
            }
            if !spec.initial_context.is_empty() {
                thread
                    .replace_context(pl_core::thread::ReplaceContext {
                        expected_revision: 0,
                        reason: pl_core::thread::ContextReplacementReason::Rebuild,
                        records: spec.initial_context,
                    })
                    .await?;
            }
            if !spec.initial_runtime_facts.is_empty() {
                thread
                    .queue_runtime_facts(spec.initial_runtime_facts)
                    .await?;
            }
            // Freeze the observer's recovery baseline before exposing this owner to execution.
            // Observers may query the registry, so invoke them without its lock held.
            self.publish_observation(&spec.id, &thread);
            if let Some(guard) = preparation_guard.take() {
                guard.disarm();
            }
            let mut state = self.0.state();
            if state.closing {
                return Err(ThreadAssemblyError::Thread(ThreadError::Closed));
            }
            let ready = !state.unpublished_children.contains_key(&spec.id);
            let entry = state.entries.get_mut(&spec.id).ok_or(ThreadError::Closed)?;
            entry.native_mut()?.ready = ready;
            Ok::<_, ThreadAssemblyError>(())
        }
        .await;
        if let Err(setup) = setup {
            if let Err(cleanup) = self.prepare_close(&spec.id, &thread).await {
                return Err(ThreadAssemblyError::Cleanup {
                    id: spec.id,
                    setup: Box::new(setup),
                    cleanup: Box::new(cleanup),
                });
            }
            match thread.close().await {
                Ok(()) => {
                    let settled = async {
                        self.drain_observation(&spec.id).await?;
                        self.join_close_storage(&spec.id).await?;
                        self.confirm_preparation_close(&spec.id, is_root).await?;
                        Ok::<(), ThreadAssemblyError>(())
                    }
                    .await;
                    if let Err(cleanup) = settled {
                        return Err(ThreadAssemblyError::Cleanup {
                            id: spec.id,
                            setup: Box::new(setup),
                            cleanup: Box::new(cleanup),
                        });
                    }
                    let removed = { self.0.state().remove_entry(&spec.id) };
                    drop(removed);
                }
                Err(cleanup) => {
                    return Err(ThreadAssemblyError::Cleanup {
                        id: spec.id,
                        setup: Box::new(setup),
                        cleanup: Box::new(cleanup.into()),
                    });
                }
            }
            return Err(setup);
        }
        if is_root {
            let services = { self.0.state().agent_services.clone() };
            if let Some(services) = services
                && services
                    .store
                    .thread_preparation(&spec.id)
                    .await
                    .map_err(|source| ThreadAssemblyError::Resource {
                        operation: "read root preparation publication",
                        source: source.into_boxed_dyn_error(),
                    })?
                    .is_some()
            {
                services
                    .store
                    .publish_preparation(&spec.id)
                    .await
                    .map_err(|source| ThreadAssemblyError::Resource {
                        operation: "confirm root preparation publication",
                        source: source.into_boxed_dyn_error(),
                    })?;
            }
        }
        Ok(thread)
    }

    /// Creates a child with an independent context from its frozen Profile and initial facts.
    /// Model sessions, task state, mutable extensions and executors are created independently.
    ///
    /// # Errors
    /// Rejects mismatched parent identities or recovery history.
    pub async fn assemble_child(
        &self,
        spec: StudioThreadSpec,
        caller: &pl_tool::collaboration::control::AgentCallContext,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        let caller_thread = self
            .0
            .state()
            .by_agent
            .get(&caller.caller)
            .cloned()
            .ok_or(ThreadAssemblyError::Closed)?;
        if spec.parent_id.as_deref() != Some(caller_thread.as_str()) || spec.checkpoint.is_some() {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        self.assemble(spec).await
    }

    fn reserve(&self, id: &str, parent: Option<&str>) -> Result<Reservation, ThreadAssemblyError> {
        self.reserve_resources(id, parent, None)
    }

    fn reserve_resources(
        &self,
        id: &str,
        parent: Option<&str>,
        resources: Option<crate::session::PreparedResources>,
    ) -> Result<Reservation, ThreadAssemblyError> {
        if id.is_empty() || parent.is_some_and(|parent| parent.is_empty() || parent == id) {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        let mut state = self.0.state();
        if state.closing
            || state.sealed_agents.contains_key(id)
            || parent.is_some_and(|parent| state.sealed_agents.contains_key(parent))
        {
            return Err(ThreadAssemblyError::Closed);
        }
        if state.failed_preparations.contains_key(id) {
            return Err(ThreadAssemblyError::Unpublished(id.into()));
        }
        if state.creating.contains_key(id) || state.entries.contains_key(id) {
            return Err(ThreadAssemblyError::Identity(id.to_owned()));
        }
        if let Some(parent) = parent {
            let admitted = match state.entries.get(parent) {
                Some(entry) => match &entry.runtime {
                    crate::session::AgentRuntime::Native(native) => {
                        native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
                    }
                    crate::session::AgentRuntime::Acp(acp) => !acp.cancellation.is_cancelled(),
                },
                None => state.by_agent.values().any(|thread| thread == parent),
            };
            if !admitted {
                return Err(ThreadAssemblyError::Identity(parent.to_owned()));
            }
        }
        let mut cursor = parent;
        let mut visited = BTreeSet::new();
        while let Some(parent) = cursor {
            if parent == id || !visited.insert(parent) {
                return Err(ThreadAssemblyError::Identity(id.to_owned()));
            }
            cursor = state
                .entries
                .get(parent)
                .and_then(|entry| State::membership_parent(&state.by_agent, entry))
                .or_else(|| {
                    state
                        .creating
                        .get(parent)
                        .and_then(|preparation| preparation.parent_id.as_deref())
                });
        }
        let resources = resources.unwrap_or_else(|| {
            crate::session::PreparedResources::Native(
                state
                    .unpublished_children
                    .get(id)
                    .map(|child| child.workspace.native_resources())
                    .unwrap_or_default(),
            )
        });
        let cancellation = match &resources {
            crate::session::PreparedResources::Native(_) => Default::default(),
            crate::session::PreparedResources::Acp(acp) => acp.cancellation.clone(),
        };
        state.creating.insert(
            id.to_owned(),
            Preparation {
                resources,
                identity: None,
                settlement: None,
                purpose: None,
                parent_id: parent.map(str::to_owned),
                cancellation,
                result: None,
            },
        );
        Ok(Reservation {
            registry: self.0.clone(),
            id: id.to_owned(),
        })
    }

    /// Returns only fully assembled owners, never partially initialized resources.
    pub fn thread(&self, id: &str) -> Option<ThreadHandle> {
        let state = self.0.state();
        if state.closing {
            return None;
        }
        state
            .entries
            .get(id)
            .filter(|entry| {
                entry.native().is_ok_and(|native| {
                    native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
                })
            })
            .and_then(|entry| {
                let native = entry.native().ok()?;
                Some(native.thread.clone())
            })
    }

    /// A resident owner's real state, including an unpublished or retryable closing owner.
    /// Reading this never activates a cold Thread or opens its history.
    pub(crate) fn observed_thread(&self, id: &str) -> Option<ThreadHandle> {
        self.0.state().entries.get(id).and_then(|entry| {
            let native = entry.native().ok()?;
            Some(native.thread.clone())
        })
    }

    /// Returns read-only handles for all published or closing owners, including failed shutdowns.
    pub fn observed_threads(&self) -> Vec<(String, ThreadHandle)> {
        self.0
            .state()
            .entries
            .iter()
            .filter_map(|(id, entry)| {
                let native = entry.native().ok()?;
                Some((id.clone(), native.thread.clone()))
            })
            .collect()
    }

    /// Evicts a leaf only after core atomically seals idle admission and saves its final facts.
    ///
    /// # Errors
    /// Retains an unpublished closing owner when resource release or persistence fails.
    pub async fn evict_idle(&self, id: &str) -> Result<bool, ThreadAssemblyError> {
        if self.phase() != crate::session::SessionPhase::Open {
            return Ok(false);
        }
        let candidate =
            {
                let mut state = self.0.state();
                if state.entries.get(id).is_some_and(|entry| {
                    matches!(entry.runtime, crate::session::AgentRuntime::Acp(_))
                }) {
                    return Ok(false);
                }
                if state.creating.contains_key(id)
                    || state.entries.get(id).is_some_and(|entry| {
                        entry.native().is_ok_and(|native| {
                            entry.identity.parent_agent_id.is_some()
                                && native.thread.snapshot().lifecycle != ThreadLifecycle::Closed
                        })
                    })
                    || state
                        .entries
                        .values()
                        .any(|entry| State::membership_parent(&state.by_agent, entry) == Some(id))
                    || state
                        .creating
                        .values()
                        .any(|entry| entry.parent_id.as_deref() == Some(id))
                    || state
                        .preparing_children
                        .values()
                        .any(|entry| entry.parent == id)
                    || state
                        .unpublished_children
                        .values()
                        .any(|entry| entry.parent == id)
                {
                    return Ok(false);
                }
                state.entries.get_mut(id).and_then(|entry| {
                    let native = entry.native_mut().ok()?;
                    Some({
                        native.ready = false;
                        (native.incarnation.clone(), native.thread.clone())
                    })
                })
            };
        let Some((incarnation, thread)) = candidate else {
            return Ok(true);
        };
        if !thread.close_if_idle().await? {
            let mut state = self.0.state();
            if !state.closing
                && let Some(entry) = state.entries.get_mut(id)
                && Arc::ptr_eq(&entry.native()?.incarnation, &incarnation)
            {
                entry.native_mut()?.ready = true;
            }
            return Ok(false);
        }
        self.close(id).await?;
        Ok(true)
    }

    /// Closes one tree from leaves to root, retaining failures for a later retry.
    ///
    /// # Errors
    /// Propagates resource cleanup or concurrent preparation failures without removing the owner.
    pub(crate) async fn close_tree(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
    ) -> Result<(), ThreadAssemblyError> {
        self.close_tree_with_purpose(root, members, ClosePurpose::Preserve)
            .await
    }

    pub(crate) async fn close_tree_for_deletion(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
    ) -> Result<(), ThreadAssemblyError> {
        self.close_tree_with_purpose(root, members, ClosePurpose::Delete)
            .await
    }

    pub(crate) fn prepare_deletion(&self, ids: &[String]) {
        for id in ids {
            self.begin_operation_close(id, ClosePurpose::Delete);
            if let Some(thread) = self.observed_thread(id) {
                drop(self.prepare_close_for_purpose(id, &thread, ClosePurpose::Delete));
            }
        }
    }

    async fn close_tree_with_purpose(
        &self,
        root: &str,
        members: &[crate::studio::store::thread_preparation::PreparationIdentity],
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let root_operation = self.agent_operation(root).await;
        let mut targets = {
            let state = self.0.state();
            let mut targets = Vec::new();
            let identities = state
                .entries
                .keys()
                .map(String::as_str)
                .chain(members.iter().map(|member| member.thread_id.as_str()))
                .collect::<BTreeSet<_>>();
            for id in identities {
                let mut cursor = Some(id);
                let mut depth = 0;
                while let Some(current) = cursor {
                    if current == root {
                        targets.push((depth, id.to_owned()));
                        break;
                    }
                    depth += 1;
                    if depth > state.entries.len() + members.len() {
                        return Err(ThreadAssemblyError::Identity(id.to_owned()));
                    }
                    cursor = state
                        .entries
                        .get(current)
                        .and_then(|entry| State::membership_parent(&state.by_agent, entry))
                        .or_else(|| {
                            members
                                .iter()
                                .find(|member| member.thread_id == current)
                                .and_then(|member| member.parent_id.as_deref())
                        });
                }
            }
            targets
        };
        let ids = targets
            .iter()
            .filter(|(_, id)| id != root)
            .map(|(_, id)| id.clone())
            .collect::<Vec<_>>();
        let _child_seals = self.seal_agent_operations(&ids).await;
        let _root_seal = self.seal_agent_operation(root);
        drop(root_operation);
        targets.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        // Broadcast cancellation to the entire tree before the first dependent wait.
        // Each close below awaits the same retained cleanup barrier.
        let owners = {
            let mut state = self.0.state();
            targets
                .iter()
                .filter_map(|(_, id)| {
                    state.entries.get_mut(id).and_then(|entry| {
                        let native = entry.native_mut().ok()?;
                        Some({
                            native.ready = false;
                            (id.clone(), native.thread.clone())
                        })
                    })
                })
                .collect::<Vec<_>>()
        };
        for (id, owner) in owners {
            self.begin_operation_close(&id, purpose);
            drop(self.prepare_close_for_purpose(&id, &owner, purpose));
        }
        // A deletion scope can contain cold intermediate members. Freeze only dependency
        // positions here; their identities do not become executable or storage owners.
        let dependencies = {
            let state = self.0.state();
            let live = targets
                .iter()
                .map(|(_, id)| id.as_str())
                .filter(|id| purpose == ClosePurpose::Delete || state.entries.contains_key(*id))
                .collect::<BTreeSet<_>>();
            let mut dependencies: BTreeMap<String, Vec<String>> = BTreeMap::new();
            for id in &live {
                if *id == root {
                    continue;
                }
                let mut cursor = *id;
                let mut seen = BTreeSet::new();
                loop {
                    if !seen.insert(cursor) {
                        return Err(ThreadAssemblyError::Identity((*id).to_owned()));
                    }
                    let parent = state
                        .entries
                        .get(cursor)
                        .and_then(|entry| State::membership_parent(&state.by_agent, entry))
                        .or_else(|| {
                            members
                                .iter()
                                .find(|member| member.thread_id == cursor)
                                .and_then(|member| member.parent_id.as_deref())
                        })
                        .ok_or_else(|| ThreadAssemblyError::Identity((*id).to_owned()))?;
                    if parent == root || live.contains(parent) {
                        dependencies
                            .entry(parent.to_owned())
                            .or_default()
                            .push((*id).to_owned());
                        break;
                    }
                    cursor = parent;
                }
            }
            dependencies
        };
        let mut failures = self
            .close_entry_tree_in_scope(root.to_owned(), purpose, Some(&dependencies))
            .await
            .into_iter();
        match failures.next() {
            None => {
                if purpose == ClosePurpose::Delete {
                    // All frozen identities, including cold intermediates, passed through the
                    // operation seals and real collaboration joins above. Check every registry
                    // owner before acknowledging a durable private preparation.
                    let services = {
                        let state = self.0.state();
                        for member in members {
                            let id = &member.thread_id;
                            if state.entries.contains_key(id)
                                || state.creating.contains_key(id)
                                || state.preparing_children.contains_key(id)
                                || state.unpublished_children.contains_key(id)
                                || state.failed_preparations.contains_key(id)
                                || state.pending_activation.contains_key(id)
                            {
                                return Err(ThreadAssemblyError::Preparing(id.clone()));
                            }
                        }
                        state.agent_services.clone()
                    };
                    if let Some(services) = services {
                        for member in members {
                            let record = services
                                .store
                                .thread_preparation_for_deletion(&member.thread_id)
                                .await
                                .map_err(|source| ThreadAssemblyError::Resource {
                                    operation: "read deletion preparation",
                                    source: source.into(),
                                })?;
                            if let Some(record) = record {
                                if record.identity != *member {
                                    return Err(ThreadAssemblyError::Identity(
                                        member.thread_id.clone(),
                                    ));
                                }
                                if !record.published && !record.deletion_stopped {
                                    services
                                        .store
                                        .confirm_preparation_stop_for_deletion(&member.thread_id)
                                        .await
                                        .map_err(|source| ThreadAssemblyError::Resource {
                                            operation: "acknowledge drained deletion preparation",
                                            source: source.into(),
                                        })?;
                                }
                            }
                        }
                    }
                }
                Ok(())
            }
            Some((id, first)) => Err(ThreadAssemblyError::SubtreeClose {
                id,
                first: Box::new(first),
                others: failures.collect(),
            }),
        }
    }

    /// Closes an owner, including failed unpublished assembly, while retaining failed closes for retry.
    ///
    /// # Errors
    /// Returns in-progress assembly or the actual Thread shutdown failure.
    pub async fn close(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        self.close_for_purpose(id, ClosePurpose::Preserve).await
    }

    async fn close_for_purpose(
        &self,
        id: &str,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let purpose = self.operation_close_purpose(id, purpose);
        let _seal = self.seal_agent_operation(id);
        self.begin_operation_close(id, purpose);
        if let Some((_, thread)) = self.admit_thread_close(id)? {
            drop(self.prepare_close_for_purpose(id, &thread, purpose));
        }
        let operation = self.agent_operation(id).await;
        self.close_with_permit_for_purpose(id, operation, purpose)
            .await
    }

    /// The caller retains this identity's operation permit, including cold close restoration.
    async fn close_with_permit(
        &self,
        id: &str,
        operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<(), ThreadAssemblyError> {
        self.close_with_permit_for_purpose(id, operation, ClosePurpose::Preserve)
            .await
    }

    async fn close_with_permit_for_purpose(
        &self,
        id: &str,
        operation: tokio::sync::OwnedMutexGuard<()>,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let purpose = self.operation_close_purpose(id, purpose);
        let _seal = self.seal_agent_operation(id);
        // Signal the actual owner before a retained collaboration producer can
        // wait for its projection. close_thread awaits the original cleanup.
        if let Some((_, thread)) = self.admit_thread_close(id)? {
            drop(self.prepare_close_for_purpose(id, &thread, purpose));
        }
        let acp = self
            .0
            .state()
            .entries
            .get(id)
            .is_some_and(|entry| matches!(entry.runtime, crate::session::AgentRuntime::Acp(_)));
        drop(operation);
        if !acp && purpose == ClosePurpose::Preserve {
            self.retry_failed_review_deliveries(id)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "recover failed terminal review producer",
                    source: source.into(),
                })?;
        }
        self.join_root_operations(id)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join root collaboration operations",
                source: source.into(),
            })?;
        let operation = self.agent_operation(id).await;
        self.close_thread_for_purpose(id, operation, purpose)
            .await?;
        self.discard_unpublished_child(id).await
    }

    /// Reject invalid targets before revoking delivery; a failed admitted close
    /// keeps this owner unavailable for new work until the original close retries.
    fn admit_thread_close(
        &self,
        id: &str,
    ) -> Result<Option<(Arc<()>, ThreadHandle)>, ThreadAssemblyError> {
        let mut state = self.0.state();
        if let Some(preparation) = state.creating.get(id) {
            preparation.cancellation.cancel();
        }
        if let Some(entry) = state.entries.get(id)
            && let crate::session::AgentRuntime::Acp(acp) = &entry.runtime
        {
            acp.cancel();
        }
        if state.preparing_children.contains_key(id) {
            return Err(ThreadAssemblyError::Preparing(id.into()));
        }
        Self::close_entry(&mut state, id)
    }

    // Internal cleanup already owns its reservation and operation permit. Only
    // external admission cancels or rejects the target's own preparation.
    fn close_entry(
        state: &mut State,
        id: &str,
    ) -> Result<Option<(Arc<()>, ThreadHandle)>, ThreadAssemblyError> {
        if state
            .creating
            .get(id)
            .is_some_and(|preparation| preparation.settlement.is_none())
        {
            return Err(ThreadAssemblyError::Preparing(id.into()));
        }
        if let Some((child, _)) = state
            .unpublished_children
            .iter()
            .find(|(_, child)| child.parent == id)
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        if let Some((child, _)) = state
            .entries
            .iter()
            .find(|(_, entry)| State::membership_parent(&state.by_agent, entry) == Some(id))
        {
            return Err(ThreadAssemblyError::Descendant(child.clone()));
        }
        if let Some((child, _)) = state
            .creating
            .iter()
            .find(|(_, preparation)| preparation.parent_id.as_deref() == Some(id))
        {
            return Err(ThreadAssemblyError::Preparing(child.clone()));
        }
        Ok(state.entries.get_mut(id).and_then(|entry| {
            let native = entry.native_mut().ok()?;
            Some({
                native.ready = false;
                (native.incarnation.clone(), native.thread.clone())
            })
        }))
    }

    async fn close_thread_for_purpose(
        &self,
        id: &str,
        operation: tokio::sync::OwnedMutexGuard<()>,
        purpose: ClosePurpose,
    ) -> Result<(), ThreadAssemblyError> {
        let _seal = self.seal_agent_operation(id);
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let preparing = {
                let mut state = self.0.state();
                if let Some(entry) = state.entries.get_mut(id) {
                    match &mut entry.runtime {
                        crate::session::AgentRuntime::Native(native) => native.ready = false,
                        crate::session::AgentRuntime::Acp(acp) => acp.cancel(),
                    }
                }
                state
                    .preparing_children
                    .values()
                    .filter(|child| child.parent == id)
                    .map(|child| child.cancellation.clone())
                    .collect::<Vec<_>>()
            };
            if preparing.is_empty() {
                break;
            }
            for cancellation in preparing {
                cancellation.cancel();
            }
            changed.await;
        }
        {
            let state = self.0.state();
            if let Some((child, _)) = state
                .preparing_children
                .iter()
                .find(|(_, preparing)| preparing.parent == id)
            {
                return Err(ThreadAssemblyError::Preparing(child.clone()));
            }
        }
        let (thread, acp) = {
            let mut state = self.0.state();
            let thread = Self::close_entry(&mut state, id)?;
            let acp = state
                .entries
                .get(id)
                .and_then(|entry| match &entry.runtime {
                    crate::session::AgentRuntime::Acp(acp) => Some(acp.clone()),
                    crate::session::AgentRuntime::Native(_) => None,
                });
            (thread, acp)
        };
        if let Some(acp) = acp {
            let outcome = acp.close().await;
            if outcome.local_complete {
                let mut state = self.0.state();
                if state
                    .entries
                    .get(id)
                    .is_some_and(|entry| match &entry.runtime {
                        crate::session::AgentRuntime::Acp(current) => Arc::ptr_eq(current, &acp),
                        crate::session::AgentRuntime::Native(_) => false,
                    })
                {
                    state.remove_entry(id);
                }
            } else {
                return Err(ThreadAssemblyError::Unpublished(id.into()));
            }
            return Ok(());
        }
        let Some((incarnation, thread)) = thread else {
            return Ok(());
        };
        self.attach_close_storage_for_purpose(id, purpose).await?;
        self.prepare_close_for_purpose(id, &thread, purpose).await?;
        // Pause queued execution and let the admitted execution settle while application CAS is
        // still available. A terminal producer must be able to save its diagnostic before this
        // core/writer is retired; closing the core first would force it to recreate its own source.
        if purpose == ClosePurpose::Preserve && thread.snapshot().lifecycle == ThreadLifecycle::Open
        {
            thread.interrupt_turn(None).await?;
            let mut updates = thread.subscribe();
            while thread.snapshot().execution.is_some() {
                if updates.next().await.is_none() {
                    return Err(ThreadAssemblyError::Closed);
                }
            }
        }
        if purpose == ClosePurpose::Preserve && self.0.state().observation.is_some() {
            self.synchronize_observation(id).await?;
        }
        drop(operation);
        self.join_root_operations(id)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join review producers before core shutdown",
                source: source.into(),
            })?;
        let operation = self.agent_operation(id).await;
        if self.0.state().entries.get(id).is_some_and(|entry| {
            entry
                .native()
                .is_ok_and(|native| !Arc::ptr_eq(&native.incarnation, &incarnation))
        }) {
            return Box::pin(self.close_thread_for_purpose(id, operation, purpose)).await;
        }
        if purpose == ClosePurpose::Delete {
            match thread.close_for_deletion().await {
                Ok(()) => {}
                Err(ThreadError::Closed)
                    if thread.snapshot().lifecycle == ThreadLifecycle::Closed => {}
                Err(error) => return Err(error.into()),
            }
        } else if self.close_storage_binding(id)?.is_some() {
            self.close_storage_core(id).await?;
        } else {
            match thread.close().await {
                Ok(()) => {}
                Err(ThreadError::Closed)
                    if thread.snapshot().lifecycle == ThreadLifecycle::Closed =>
                {
                    thread.flush().await?;
                }
                Err(error) => return Err(error.into()),
            }
        }
        if purpose == ClosePurpose::Preserve && self.0.state().observation.is_some() {
            self.synchronize_observation(id).await?;
        }
        // Core shutdown can itself publish a terminal. Its producer is registered before the
        // projection ACK. Join outside this gate: storage-only repair may need that same gate.
        drop(operation);
        self.join_root_operations(id)
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "join terminal review delivery",
                source: source.into(),
            })?;
        let operation = self.agent_operation(id).await;
        if self.0.state().entries.get(id).is_some_and(|entry| {
            entry
                .native()
                .is_ok_and(|native| !Arc::ptr_eq(&native.incarnation, &incarnation))
        }) {
            return Box::pin(self.close_thread_for_purpose(id, operation, purpose)).await;
        }
        let resources = self.native_resources(&thread)?;
        let services = self.0.state().agent_services.clone();
        if let Some(services) = services {
            services
                .factory
                .close_scope_tools(id, &resources)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "close Native tool binding and MCP",
                    source: source.into_boxed_dyn_error(),
                })?;
        }
        self.drain_observation_for_purpose(id, purpose).await?;
        self.join_close_storage_for_purpose(id, purpose).await?;
        self.close_published_resources(id, &incarnation).await?;
        let retired = !self.0.state().unpublished_children.contains_key(id);
        self.confirm_preparation_close_for_purpose(id, retired, purpose)
            .await?;
        if resources.has_obligations() {
            return Err(ThreadAssemblyError::Unpublished(id.into()));
        }
        let removed = {
            let mut state = self.0.state();
            if state.entries.get(id).is_some_and(|entry| {
                entry
                    .native()
                    .is_ok_and(|native| Arc::ptr_eq(&native.incarnation, &incarnation))
            }) {
                state.remove_entry(id)
            } else {
                None
            }
        };
        drop(removed);
        Ok(())
    }

    /// Seals shared admission, broadcasts cancellation, then closes every independent
    /// forest/branch concurrently while a global final ACK confirms all admitted preparations
    /// actually drained.
    ///
    /// 与旧实现的区别：全局 preparation 等待不再是**前置** barrier——它与独立森林/分支的关闭并发
    /// （`futures::join!`），所以某个 root 的卡住子分支/准备只阻塞它自己之外，独立资源仍立即
    /// close；但本方法**绝不**在还有已准入 `creating`/`preparing_children` 未真实排空时返回成功，
    /// 因此不会让严格关闭误判生产者已停而停止 writer / 关库 / 发布 `Stopped`。父子依赖（子关闭
    /// 确认先于需要它的父关闭）与 owner 保留规则不变：失败累计、entry 保留、可重试。
    ///
    /// Failures retain their entries and can be retried with this method or `close`.
    ///
    /// 会话收束。等待者取消只放弃自己的等待，不取消已启动的共享任务；重复调用加入同一次运行。
    /// 失败留在 Closing，旧任务结束后才允许重试剩余义务。成功后对象进入 Closed，不能 reopen。
    pub(crate) async fn close_session(&self) -> SessionCloseReport {
        use futures::FutureExt;
        let completion = {
            let mut life = self.0.life();
            if let Some(current) = &life.current
                && current.peek().is_none()
            {
                current.clone()
            } else if life.phase == crate::session::SessionPhase::Closed {
                return life
                    .last
                    .clone()
                    .expect("closed session retains its successful result");
            } else {
                life.phase = crate::session::SessionPhase::Closing;
                self.0.state().closing = true;
                let owner = self.clone();
                let task = tokio::spawn(async move {
                    let report = Arc::new(
                        owner
                            .run_close_algorithm()
                            .await
                            .into_iter()
                            .map(|(id, error)| (id, Arc::new(error)))
                            .collect::<Vec<_>>(),
                    );
                    // Completing cleanup publishes its terminal phase even if every waiter left.
                    let mut life = owner.0.life();
                    life.last = Some(Arc::clone(&report));
                    if report.is_empty() {
                        life.phase = crate::session::SessionPhase::Closed;
                    }
                    drop(life);
                    report
                });
                let registry = Arc::downgrade(&self.0);
                let id = self.id().as_str().to_owned();
                let completion = async move {
                    let report = match task.await {
                        Ok(report) => report,
                        Err(source) => Arc::new(vec![(
                            id,
                            Arc::new(ThreadAssemblyError::Resource {
                                operation: "join session close task",
                                source: Box::new(source),
                            }),
                        )]),
                    };
                    // JoinHandle has really finished before failure permits another run.
                    if let Some(registry) = registry.upgrade() {
                        let mut life = registry.life();
                        life.last = Some(Arc::clone(&report));
                        if report.is_empty() {
                            life.phase = crate::session::SessionPhase::Closed;
                        }
                    }
                    report
                }
                .boxed()
                .shared();
                life.current = Some(completion.clone());
                completion
            }
        };
        completion.await
    }

    async fn run_close_algorithm(&self) -> Vec<(String, ThreadAssemblyError)> {
        // 共享准入先封闭，所有准备过程 cancellation 先广播；此处不等待它们排空。
        let (preparing, executing, resources) = {
            let mut state = self.0.state();
            state.closing = true;
            for preparation in state.creating.values() {
                preparation.resources.cancel();
            }
            for failed in state.failed_preparations.values() {
                failed.resources.cancel();
            }
            let preparing = state
                .preparing_children
                .values()
                .map(|child| child.cancellation.clone())
                .chain(
                    state
                        .creating
                        .values()
                        .map(|preparation| preparation.cancellation.clone()),
                )
                .collect::<Vec<_>>();
            for entry in state.entries.values() {
                if let crate::session::AgentRuntime::Acp(acp) = &entry.runtime {
                    acp.cancel();
                }
            }
            let executing = state
                .entries
                .values_mut()
                .filter_map(|entry| {
                    let native = entry.native_mut().ok()?;
                    Some({
                        native.ready = false;
                        native.thread.clone()
                    })
                })
                .collect::<Vec<_>>();
            let resources = state
                .entries
                .values()
                .filter_map(|entry| {
                    let native = entry.native().ok()?;
                    Some(native.resources.clone())
                })
                .chain(
                    state
                        .creating
                        .values()
                        .filter_map(|preparation| preparation.resources.native().cloned()),
                )
                .chain(
                    state
                        .unpublished_children
                        .values()
                        .map(|child| child.workspace.native_resources()),
                )
                .chain(
                    state
                        .failed_preparations
                        .values()
                        .filter_map(|failed| failed.resources.native().cloned()),
                )
                .collect::<Vec<_>>();
            (preparing, executing, resources)
        };
        for cancellation in preparing {
            cancellation.cancel();
        }
        for thread in executing {
            thread.request_shutdown();
        }
        for resources in resources {
            resources.cancel_tool_producers();
        }
        #[cfg(test)]
        if let Some(ack) = self.0.state().s2_close_broadcast.take() {
            let _ = ack.send(());
        }

        let mut covered: BTreeSet<String> = BTreeSet::new();
        let mut failures = Vec::new();

        // 第一轮：独立森林/orphan 关闭与「全部已准入 creating/preparing 真实排空」的全局最终 ACK
        // 并发推进——独立资源先开始自身 close，不被全局 ACK 前置阻塞；全局 ACK 又保证最终成功前
        // 不存在仍在清理/持有资源的准备 owner。
        let (roots, orphan_unpublished) = self.select_uncovered_roots(&covered);
        self.mark_covered(&mut covered, &roots, &orphan_unpublished);
        let (first_failures, ()) = futures::join!(
            self.close_independent_batch(roots, orphan_unpublished),
            self.await_all_preparations_drained(),
        );
        failures.extend(first_failures);

        // 迟到 owner：准备排空后才可见、第一轮快照未覆盖的 entries/unpublished（例如 closing 前
        // 已准入、快照之后才插入 entry、setup 失败后 cleanup 也失败而保留 owner），用同一局部化
        // 方式收尾。此刻不会再有新的 assembly / child preparation，集合只会收缩，循环终止。
        loop {
            let (roots, orphan_unpublished) = self.select_uncovered_roots(&covered);
            if roots.is_empty() && orphan_unpublished.is_empty() {
                break;
            }
            self.mark_covered(&mut covered, &roots, &orphan_unpublished);
            let batch_failures = self
                .close_independent_batch(roots, orphan_unpublished)
                .await;
            failures.extend(batch_failures);
        }
        let failed = self
            .0
            .state()
            .failed_preparations
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        let outcomes = futures::future::join_all(failed.into_iter().map(|id| async move {
            let result = self.close_failed_preparation(&id).await;
            (id, result)
        }))
        .await;
        for (id, result) in outcomes {
            if let Err(error) = result {
                failures.push((id, error));
            }
        }
        // Closing a core can still publish its final normal finish. Keep the retained operation
        // owner open until every such producer has registered and its source owner has drained.
        if failures.is_empty()
            && let Err(source) = self.close_agent_operations().await
        {
            failures.push((
                "agent-operations".into(),
                ThreadAssemblyError::Resource {
                    operation: "join collaboration operations",
                    source: source.into(),
                },
            ));
        }
        failures
    }

    /// 选取当前尚未负责（`covered` 之外）的独立森林根与 orphan unpublished 子资源。
    ///
    /// 根 = 父 entry 不在册，或父 entry 已在 `covered`（其自身 close 不会再等待该子项）。orphan =
    /// 父 entry 不在册，或父 entry 已在 `covered`。这样迟到 owner 也有归属、不被漏关。
    fn select_uncovered_roots(&self, covered: &BTreeSet<String>) -> (Vec<String>, Vec<String>) {
        let state = self.0.state();
        let mut roots = Vec::new();
        for (id, entry) in state.entries.iter() {
            if covered.contains(id) {
                continue;
            }
            let parent = State::membership_parent(&state.by_agent, entry).map(str::to_owned);
            let parent_present = parent
                .as_deref()
                .is_some_and(|parent| state.entries.contains_key(parent));
            let parent_covered = parent
                .as_deref()
                .is_some_and(|parent| covered.contains(parent));
            if !parent_present || parent_covered {
                roots.push(id.clone());
            }
        }
        let mut orphan_unpublished = Vec::new();
        for (id, child) in state.unpublished_children.iter() {
            if covered.contains(id) {
                continue;
            }
            if !state.entries.contains_key(&child.parent) || covered.contains(&child.parent) {
                orphan_unpublished.push(id.clone());
            }
        }
        (roots, orphan_unpublished)
    }

    /// 把一批根及其可达子树、以及 orphan 子资源标记为已负责，避免后续批次重复 close。
    fn mark_covered(
        &self,
        covered: &mut BTreeSet<String>,
        roots: &[String],
        orphan_unpublished: &[String],
    ) {
        let state = self.0.state();
        let mut stack = roots.to_vec();
        while let Some(id) = stack.pop() {
            if !covered.insert(id.clone()) {
                continue;
            }
            for (child, entry) in state.entries.iter() {
                if State::membership_parent(&state.by_agent, entry) == Some(id.as_str()) {
                    stack.push(child.clone());
                }
            }
        }
        for id in orphan_unpublished {
            covered.insert(id.clone());
        }
    }

    /// 并发关闭一批独立森林根与 orphan unpublished，返回累计失败（`join_all` 保序，顺序确定）。
    async fn close_independent_batch(
        &self,
        roots: Vec<String>,
        orphan_unpublished: Vec<String>,
    ) -> Vec<(String, ThreadAssemblyError)> {
        let mut root_futures = Vec::with_capacity(roots.len());
        for root in roots {
            root_futures.push(self.close_entry_tree(root));
        }
        let mut orphan_futures = Vec::with_capacity(orphan_unpublished.len());
        for child in orphan_unpublished {
            orphan_futures.push(async move {
                // 只有该子资源自身的创建准备排空后才可 discard（`close_thread` 会拒绝 preparing 者）。
                self.await_own_preparations_drained(&child).await;
                match self.discard_unpublished_child(&child).await {
                    Ok(()) => Vec::new(),
                    Err(error) => vec![(child, error)],
                }
            });
        }
        let (tree_failures, orphan_failures) = futures::join!(
            futures::future::join_all(root_futures),
            futures::future::join_all(orphan_futures),
        );
        let mut failures = Vec::new();
        for group in tree_failures {
            failures.extend(group);
        }
        for group in orphan_failures {
            failures.extend(group);
        }
        failures
    }

    /// 全局最终 ACK：等待**全部**已准入的 `creating`/`preparing_children` owner 真实排空。
    ///
    /// 与独立树关闭并发进行，不是前置 barrier；但 close_session 成功返回前必须等到它完成，避免仍在
    /// 清理/持有资源的准备 owner 被误判为已停（否则严格关闭会停 writer / 关库 / 发布 `Stopped`）。
    /// 取消已广播，`closing` 保证不会新增准备 owner，因此集合只会收缩。
    async fn await_all_preparations_drained(&self) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let drained = {
                let state = self.0.state();
                state.creating.is_empty() && state.preparing_children.is_empty()
            };
            if drained {
                break;
            }
            changed.await;
        }
    }

    /// 递归关闭一个在册 entry 及其整棵依赖子树，只等待自身需要的子资源与准备过程。
    ///
    /// 依赖：该 entry 的每个子 entry（`parent_id == id`）、它自己的 unpublished 子资源，以及它
    /// 自己的 creating/preparing 子过程。它们彼此独立，因此并发收束；全部就绪后才 `close(id)`。
    /// 只等待自身依赖，绝不等待其他森林/分支。失败累计并保留 owner，返回本子树全部失败（含 id
    /// 自身）。通过 boxed future 递归，避免 async fn 的无限类型。
    fn close_entry_tree<'a>(
        &'a self,
        id: String,
    ) -> futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>> {
        self.close_entry_tree_for_purpose(id, ClosePurpose::Preserve)
    }

    fn close_entry_tree_for_purpose<'a>(
        &'a self,
        id: String,
        purpose: ClosePurpose,
    ) -> futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>> {
        self.close_entry_tree_in_scope(id, purpose, None)
    }

    fn close_entry_tree_in_scope<'a>(
        &'a self,
        id: String,
        purpose: ClosePurpose,
        dependencies: Option<&'a BTreeMap<String, Vec<String>>>,
    ) -> futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>> {
        Box::pin(async move {
            let mut failures = Vec::new();

            // 一次持锁快照自身直接子依赖，不跨 await。
            let (child_entries, child_unpublished) = {
                let state = self.0.state();
                let mut child_entries = Vec::new();
                let mut child_unpublished = Vec::new();
                if let Some(dependencies) = dependencies {
                    child_entries.extend(dependencies.get(&id).into_iter().flatten().cloned());
                } else {
                    for (child, entry) in state.entries.iter() {
                        if State::membership_parent(&state.by_agent, entry) == Some(id.as_str()) {
                            child_entries.push(child.clone());
                        }
                    }
                }
                for (child, unpublished) in state.unpublished_children.iter() {
                    if unpublished.parent == id {
                        child_unpublished.push(child.clone());
                    }
                }
                (child_entries, child_unpublished)
            };

            let mut child_futures: Vec<
                futures::future::BoxFuture<'a, Vec<(String, ThreadAssemblyError)>>,
            > = Vec::with_capacity(child_entries.len());
            for child in child_entries {
                child_futures.push(self.close_entry_tree_in_scope(child, purpose, dependencies));
            }
            let mut unpublished_futures = Vec::with_capacity(child_unpublished.len());
            for child in child_unpublished {
                unpublished_futures.push(async move {
                    // 该子资源自身的创建准备排空后才可 discard（`discard_unpublished_child` 会拒绝
                    // preparing 者）。
                    self.await_own_preparations_drained(&child).await;
                    let outcome = self.discard_unpublished_child(&child).await;
                    (child, outcome)
                });
            }
            // 自身的 creating/preparing 子过程：取消已由 `close_session` 会话内广播，这里只对自身这部分
            // 有界等待，不等待其他分支。
            let own_preparations = self.await_own_preparations_drained(&id);
            let (child_failures, unpublished_outcomes, ()) = futures::join!(
                futures::future::join_all(child_futures),
                futures::future::join_all(unpublished_futures),
                own_preparations,
            );
            for group in child_failures {
                failures.extend(group);
            }
            for (child, outcome) in unpublished_outcomes {
                if let Err(error) = outcome {
                    failures.push((child, error));
                }
            }

            // 依赖就绪后才关闭自身：原 `close` 的真实父子保护与 incarnation/owner 保留规则不变，
            // 子关闭未确认（失败保留）时 `close` 返回对应错误并被累计，绝不早释放。
            if let Err(error) = self.close_for_purpose(&id, purpose).await {
                failures.push((id, error));
            } else if purpose == ClosePurpose::Delete
                && let Err(error) = self.close_failed_preparation(&id).await
            {
                failures.push((id, error));
            }
            failures
        })
    }

    /// 等待并只等待某个节点的自身依赖型准备过程排空。
    ///
    /// 覆盖两类真实依赖：节点**自身**的创建准备（`creating`/`preparing_children` 含该 id），以及
    /// 节点**子项**的创建准备（`creating` 的 parent/`preparing_children` 的 parent 指向该 id）。
    /// 取消已由 `close_session` 会话内广播；这里只在该节点确有对应准备过程时等待其真实离开注册表，不等待
    /// 任何其他分支或全局集合。`closing`/`entry.native_mut()?.ready =false` 保证等待期间不会产生新的子过程。
    async fn await_own_preparations_drained(&self, id: &str) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            let blocked = {
                let state = self.0.state();
                state.creating.contains_key(id)
                    || state.preparing_children.contains_key(id)
                    || state
                        .creating
                        .values()
                        .any(|preparation| preparation.parent_id.as_deref() == Some(id))
                    || state
                        .preparing_children
                        .values()
                        .any(|child| child.parent == id)
            };
            if !blocked {
                break;
            }
            changed.await;
        }
    }
}

pub(crate) use tools::{StudioCommandProcesses, WeakCommandProcesses};

#[cfg(test)]
mod s2_close_regression_tests {
    //! Incremental S2 regressions for preparation settlement and Session cancellation ordering.
    use super::*;
    use crate::session::{AgentInstance, NativeResources, NativeThreadRuntime, SessionPhase};
    use pl_core::{
        context::ContextContent,
        model::{DynModelSession, ModelError, ModelRequest, ModelSession, PreparedModelCall},
        thread::{
            ModelStepLimit, ThreadLifecycle, TurnInput,
            cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
        },
    };
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use tokio::sync::{Semaphore, oneshot};
    use tokio_util::sync::CancellationToken;

    #[derive(Debug)]
    pub(super) struct SettlementProbe {
        id: String,
        barrier: tokio::sync::Mutex<Option<(oneshot::Sender<()>, oneshot::Receiver<()>)>>,
        fail: AtomicBool,
        attempts: AtomicUsize,
    }

    #[derive(Debug)]
    pub(super) struct FailedRetryProbe {
        id: String,
        captured: oneshot::Sender<()>,
        resume: oneshot::Receiver<()>,
    }

    impl SessionRuntime {
        pub(crate) fn s2_has_failed_preparation(&self, id: &str) -> bool {
            self.0.state().failed_preparations.contains_key(id)
        }

        pub(super) async fn s2_failed_retry_checkpoint(&self, id: &str) {
            let probe = {
                let mut state = self.0.state();
                if state
                    .s2_failed_retry_probe
                    .as_ref()
                    .is_some_and(|probe| probe.id == id)
                {
                    state.s2_failed_retry_probe.take()
                } else {
                    None
                }
            };
            if let Some(probe) = probe {
                let _ = probe.captured.send(());
                probe.resume.await.unwrap();
            }
        }

        pub(super) async fn s2_activation_settlement_checkpoint(
            &self,
            id: &str,
        ) -> Result<(), ThreadAssemblyError> {
            let probe = self.0.state().s2_settlement_probe.clone();
            let Some(probe) = probe.filter(|probe| probe.id == id) else {
                return Ok(());
            };
            probe.attempts.fetch_add(1, Ordering::SeqCst);
            let barrier = probe.barrier.lock().await.take();
            if let Some((entered, release)) = barrier {
                let _ = entered.send(());
                release.await.expect("test retains the settlement release");
            }
            if probe.fail.load(Ordering::SeqCst) {
                return Err(ThreadAssemblyError::Resource {
                    operation: "settle original activation preparation",
                    source: Box::new(std::io::Error::other("injected settlement failure")),
                });
            }
            Ok(())
        }
    }

    #[derive(Debug)]
    struct RefusedFactory {
        panic: bool,
    }
    impl StudioActivationFactory for RefusedFactory {
        async fn root_delegation(
            &self,
            _: &ThreadActivation,
        ) -> Result<pl_protocol::DelegationSettings, ThreadAssemblyError> {
            assert!(!self.panic, "factory unwind before resource publication");
            Err(ThreadAssemblyError::Identity(
                "factory refused preparation".into(),
            ))
        }
        async fn prepare(
            &self,
            _: ThreadPreparation,
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            unreachable!("root delegation refuses before resource preparation")
        }
    }

    async fn settlement_blocks_close(panic: bool) {
        let owner = SessionRuntime::default();
        let (entered, paused) = oneshot::channel();
        let (release, resume) = oneshot::channel();
        let probe = Arc::new(SettlementProbe {
            id: "settling-root".into(),
            barrier: tokio::sync::Mutex::new(Some((entered, resume))),
            fail: AtomicBool::new(false),
            attempts: AtomicUsize::new(0),
        });
        owner.0.state().s2_settlement_probe = Some(probe);
        let activation = {
            let owner = owner.clone();
            tokio::spawn(async move {
                owner
                    .activate(
                        ThreadActivation::native_test("settling-root", None),
                        RefusedFactory { panic },
                    )
                    .await
            })
        };
        paused.await.unwrap();
        // A failed assembly can already own a concrete core. Settlement must close it while
        // retaining its preparation registration, without waiting on that same registration.
        register_member(
            &owner,
            "settling-root",
            None,
            ThreadHandle::resume_without_model("settling-root".into(), None).unwrap(),
        );
        assert!(
            owner.0.state().creating["settling-root"]
                .settlement
                .is_some()
        );
        let (broadcast, observed) = oneshot::channel();
        owner.0.state().s2_close_broadcast = Some(broadcast);
        let close = owner.close_session();
        tokio::pin!(close);
        tokio::select! {
            result = &mut close => panic!("close escaped retained settlement: {result:?}"),
            result = observed => result.unwrap(),
        }
        assert_eq!(owner.phase(), SessionPhase::Closing);
        assert!(futures::poll!(&mut close).is_pending());
        release.send(()).unwrap();
        assert!(activation.await.unwrap().is_err());
        let report = close.await;
        assert!(report.is_empty(), "{report:?}");
        assert_eq!(owner.phase(), SessionPhase::Closed);
        assert!(owner.0.state().creating.is_empty());
        assert!(owner.0.state().failed_preparations.is_empty());
    }

    #[tokio::test]
    async fn s2_close_waits_for_original_failed_activation_settlement() {
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            settlement_blocks_close(false),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn s2_close_waits_for_original_panicked_factory_settlement() {
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            settlement_blocks_close(true),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn s2_failed_settlement_survives_empty_native_resources_and_retries() {
        let owner = SessionRuntime::default();
        let probe = Arc::new(SettlementProbe {
            id: "failed-settlement".into(),
            barrier: Default::default(),
            fail: AtomicBool::new(true),
            attempts: AtomicUsize::new(0),
        });
        owner.0.state().s2_settlement_probe = Some(probe.clone());
        assert!(
            owner
                .activate(
                    ThreadActivation::native_test(&probe.id, None),
                    RefusedFactory { panic: false }
                )
                .await
                .is_err()
        );
        {
            let state = owner.0.state();
            let failed = &state.failed_preparations[&probe.id];
            assert!(failed.settlement.is_some());
            assert!(
                !failed.resources.has_obligations(),
                "settlement must not depend on Native resource occupancy"
            );
        }
        let failed = owner.close_session().await;
        assert!(!failed.is_empty());
        assert_eq!(owner.phase(), SessionPhase::Closing);
        assert!(owner.0.state().failed_preparations.contains_key(&probe.id));
        probe.fail.store(false, Ordering::SeqCst);
        assert!(owner.close_session().await.is_empty());
        assert!(probe.attempts.load(Ordering::SeqCst) >= 3);
        assert!(owner.0.state().failed_preparations.is_empty());
        assert_eq!(owner.phase(), SessionPhase::Closed);
    }

    struct WaitingModel {
        started: Option<oneshot::Sender<CancellationToken>>,
    }

    #[tokio::test]
    async fn s2_stale_failed_retry_cannot_close_replacement_owner() {
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            let owner = SessionRuntime::default();
            let id = "retry-incarnation";
            let probe = Arc::new(SettlementProbe {
                id: id.into(),
                barrier: Default::default(),
                fail: AtomicBool::new(true),
                attempts: AtomicUsize::new(0),
            });
            owner.0.state().s2_settlement_probe = Some(probe.clone());
            let mut activation = ThreadActivation::native_test(id, None);
            activation.agent.agent_id = pl_protocol::AgentId::new(format!("agent-{id}")).unwrap();
            assert!(
                owner
                    .activate(activation, RefusedFactory { panic: false })
                    .await
                    .is_err()
            );
            assert!(owner.s2_has_failed_preparation(id));
            let old = owner.0.state().failed_preparations[id].clone();
            probe.fail.store(false, Ordering::SeqCst);
            let (entered, paused) = oneshot::channel();
            let (release, resume) = oneshot::channel();
            *probe.barrier.lock().await = Some((entered, resume));
            let first = {
                let owner = owner.clone();
                tokio::spawn(async move { owner.close_failed_preparation(id).await })
            };
            paused.await.unwrap();
            assert!(
                owner.reserve(id, None).is_err(),
                "qualified cleanup must block reuse"
            );
            let (captured, capture) = oneshot::channel();
            let (resume, paused) = oneshot::channel();
            owner.0.state().s2_failed_retry_probe = Some(FailedRetryProbe {
                id: id.into(),
                captured,
                resume: paused,
            });
            let stale = {
                let owner = owner.clone();
                tokio::spawn(async move { owner.close_failed_preparation(id).await })
            };
            capture.await.unwrap();
            assert!(Arc::ptr_eq(&old, &owner.0.state().failed_preparations[id]));
            release.send(()).unwrap();
            first.await.unwrap().unwrap();
            assert!(!owner.s2_has_failed_preparation(id));
            let (started, running) = oneshot::channel();
            let thread = ThreadHandle::start(
                id.into(),
                DynModelSession::new(WaitingModel {
                    started: Some(started),
                }),
            )
            .unwrap();
            register_member(&owner, id, None, thread.clone());
            let turn = start_turn(thread.clone());
            let cancellation = running.await.unwrap();
            let attempts = probe.attempts.load(Ordering::SeqCst);
            resume.send(()).unwrap();
            stale.await.unwrap().unwrap();
            assert_eq!(probe.attempts.load(Ordering::SeqCst), attempts);
            assert!(
                owner.0.state().entries[id]
                    .native()
                    .unwrap()
                    .thread
                    .same_instance(&thread)
            );
            assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Open);
            assert!(!cancellation.is_cancelled());
            assert!(owner.close_session().await.is_empty());
            let _ = turn.await.unwrap();
        })
        .await
        .unwrap();
    }
    impl ModelSession for WaitingModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            if let Some(started) = self.started.take() {
                let _ = started.send(request.cancellation.clone());
            }
            Ok(PreparedModelCall::new(async move {
                request.cancellation.cancelled().await;
                Err(ModelError {
                    details: None,
                    kind: pl_core::model::ModelFailureKind::Cancelled,
                    usage: Default::default(),
                    source: None,
                })
            }))
        }
        async fn close(&mut self) -> Result<(), ModelError> {
            Ok(())
        }
    }

    #[derive(Debug, Clone)]
    struct GatedFinalSave {
        closing: Arc<AtomicBool>,
        entered: Arc<Mutex<Option<oneshot::Sender<()>>>>,
        release: Arc<Semaphore>,
    }
    impl ColdStore for GatedFinalSave {
        fn pressure(&self, _: &str) -> StoragePressure {
            StoragePressure::default()
        }
        fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
            if write.checkpoint.state.lifecycle == ThreadLifecycle::Closed {
                self.closing.store(true, Ordering::SeqCst);
            }
            Ok(())
        }
        async fn flush(&self, _: &str, _: u64) -> Result<(), ColdStoreError> {
            if self.closing.load(Ordering::SeqCst) {
                if let Some(entered) = self.entered.lock().unwrap().take() {
                    let _ = entered.send(());
                }
                self.release.acquire().await.unwrap().forget();
            }
            Ok(())
        }
    }

    fn register_member(
        owner: &SessionRuntime,
        id: &str,
        parent: Option<&str>,
        thread: ThreadHandle,
    ) {
        owner.0.state().insert_entry(
            id.into(),
            AgentInstance {
                identity: pl_protocol::AgentThreadIdentity {
                    session_id: owner.id().clone(),
                    agent_id: pl_protocol::AgentId::new(format!("agent-{id}")).unwrap(),
                    parent_agent_id: parent
                        .map(|id| pl_protocol::AgentId::new(format!("agent-{id}")).unwrap()),
                    thread_id: pl_protocol::ThreadId::new(id).unwrap(),
                },
                binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                    route: None,
                    system_instructions: None,
                }),
                runtime: crate::session::AgentRuntime::Native(Box::new(NativeThreadRuntime {
                    resources: Arc::new(NativeResources::default()),
                    purpose: EntryPurpose::Execution,
                    workspace_usage: None,
                    close_storage: None,
                    published_resources_closed: false,
                    workspace_disposition: None,
                    cleanup: Default::default(),
                    execution: pl_core::thread::input::InputDriverOptions {
                        max_model_steps: ModelStepLimit::Unlimited,
                    },
                    incarnation: Arc::new(()),
                    parent_id: parent.map(str::to_owned),
                    ready: true,
                    thread,
                })),
            },
        );
    }

    fn start_turn(
        thread: ThreadHandle,
    ) -> tokio::task::JoinHandle<Result<pl_core::thread::TurnCompletion, ThreadError>> {
        tokio::spawn(async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "running-turn".into(),
                    attempt_prefix: "waiting-model".into(),
                    content: vec![ContextContent::Text {
                        text: "run until cancelled".into(),
                    }],
                    max_model_steps: ModelStepLimit::Unlimited,
                    cancellation: CancellationToken::new(),
                })
                .await
        })
    }

    #[tokio::test]
    async fn s2_close_cancels_parent_before_blocked_child_and_preserves_other_session() {
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            let owner = SessionRuntime::open(pl_protocol::SessionId::new("session-a").unwrap());
            let other = SessionRuntime::open(pl_protocol::SessionId::new("session-b").unwrap());
            let (started, model_started) = oneshot::channel();
            let parent = ThreadHandle::start(
                "parent-thread".into(),
                DynModelSession::new(WaitingModel {
                    started: Some(started),
                }),
            )
            .unwrap();
            register_member(&owner, "parent-thread", None, parent.clone());
            let parent_run = start_turn(parent.clone());
            let parent_cancel = model_started.await.unwrap();
            let (started, model_started) = oneshot::channel();
            let unrelated = ThreadHandle::start(
                "unrelated-thread".into(),
                DynModelSession::new(WaitingModel {
                    started: Some(started),
                }),
            )
            .unwrap();
            register_member(&other, "unrelated-thread", None, unrelated.clone());
            let unrelated_run = start_turn(unrelated);
            let unrelated_cancel = model_started.await.unwrap();
            let child = ThreadHandle::resume_without_model("child-thread".into(), None).unwrap();
            let (entered, child_waiting) = oneshot::channel();
            let store = GatedFinalSave {
                closing: Arc::new(AtomicBool::new(false)),
                entered: Arc::new(Mutex::new(Some(entered))),
                release: Arc::new(Semaphore::new(0)),
            };
            child
                .attach_storage(ColdStoreHandle::new(store.clone()))
                .await
                .unwrap();
            register_member(&owner, "child-thread", Some("parent-thread"), child);
            let close = owner.close_session();
            tokio::pin!(close);
            tokio::select! {
                result = &mut close => panic!("child save barrier was skipped: {result:?}"),
                result = child_waiting => result.unwrap(),
            }
            assert!(
                parent_cancel.is_cancelled(),
                "parent execution must be cancelled before waiting for child save"
            );
            assert!(
                !unrelated_cancel.is_cancelled(),
                "Session A cannot cancel Session B"
            );
            assert!(futures::poll!(&mut close).is_pending());
            store.release.add_permits(8);
            let report = close.await;
            assert!(report.is_empty(), "{report:?}");
            assert!(parent_run.await.unwrap().is_err());
            assert!(!unrelated_cancel.is_cancelled());
            assert!(other.close_session().await.is_empty());
            assert!(unrelated_run.await.unwrap().is_err());
        })
        .await
        .unwrap();
    }
}
