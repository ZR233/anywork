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
mod assembly;
mod close;
mod entry_registry;
pub(crate) mod host_agent_tools;
pub(crate) mod host_task_tools;
pub(crate) mod host_workspace_tools;
pub(crate) use agents::AgentHost;

#[cfg(test)]
pub(crate) use agents::archive_tests::spawn_failed_archive_fixture;
#[cfg(test)]
pub(crate) use agents::archive_tests::spec as archive_test_spec;
pub(crate) mod delegation_models;
pub(crate) mod observation;
mod pending_delivery;
pub(crate) mod review_delivery;
pub(crate) mod review_dispatch;
pub use activation::{StudioActivationFactory, ThreadActivation, ThreadPreparation};
mod interaction_key;
mod interaction_projection;
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
pub(crate) use child_resources::WorkspaceBindingAdmission;
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
pub(crate) use published_resources::ArchiveScopeSeal;
mod report_receiver;
pub use children::{ChildThreadRequest, StudioChildFactory, StudioChildResources};
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
    thread::{
        ContextCapacity, ThreadError, ThreadHandle, ThreadLifecycle,
        current::{CurrentError, ThreadCurrent},
    },
    tool::opaque::Registration,
};
use pl_model::config::ResolvedModelRoute;

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
    /// Root-only controls prepared from one Profile generation before allocating physical tools.
    pub agent_controls: Vec<Registration>,
    pub execution: pl_core::thread::input::InputDriverOptions,
    pub id: String,
    pub parent_id: Option<String>,
    pub route: ResolvedModelRoute,
    /// The preflighted configuration; Core opens and installs it with the tools and host facts.
    pub model: Option<pl_core::thread::RuntimeModel>,
    /// Complete current facts restored from `current.json`. New Threads start with no value.
    ///
    /// The assembler hands this exact object to Core, preserving saved model-call, tool-preview and
    /// context facts; it never converts through a legacy checkpoint.
    pub current: Option<ThreadCurrent>,
    /// Initial instructions and records for a new Thread only; never used to re-render recovery.
    pub initial_context: Vec<pl_core::context::ContextRecord>,
    /// Latest host facts queued after assembly. Recovery may supply them; they never re-render
    /// frozen instructions or replace restored history.
    pub initial_runtime_facts: Vec<pl_core::thread::RuntimeFact>,
    pub initial_extensions: BTreeMap<String, pl_core::context::OpaquePayload>,
    pub tools: Vec<Registration>,
    pub resources: ResourceAccess,
    pub capacity: ContextCapacity,
    pub(crate) history_sink: Option<crate::studio::storage::thread_writer::ThreadStorageSink>,
}

impl StudioThreadSpec {
    fn frozen_delegation(&self) -> Result<crate::DelegationSettings, ThreadAssemblyError> {
        let selection = match &self.current {
            Some(current) => crate::studio::delegation::saved(&current.state.to_paused_snapshot()),
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
                "current_revision",
                &self
                    .current
                    .as_ref()
                    .map(|current| current.snapshot_revision),
            )
            .field("tools", &self.tools.len())
            .finish_non_exhaustive()
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ThreadAssemblyError {
    #[error("Agent backend {backend:?} is not supported by the Native runtime")]
    UnsupportedBackend { backend: crate::AgentBackendKind },
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
    #[error("Thread current setup failed")]
    Current(#[from] CurrentError),
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
    identity: Option<crate::AgentThreadIdentity>,
    /// The factory has stopped; its original preparation still owns settlement until ACK.
    settlement: Option<WorkspacePreparationOwner>,
    parent_id: Option<String>,
    cancellation: tokio_util::sync::CancellationToken,
    result: Option<tokio::sync::watch::Receiver<Option<ActivationOutcome>>>,
}

#[derive(Debug)]
struct FailedPreparation {
    resources: crate::session::PreparedResources,
    identity: Option<crate::AgentThreadIdentity>,
    settlement: Option<WorkspacePreparationOwner>,
    gate: tokio::sync::Mutex<()>,
}

/// One transaction boundary for registration, activation publication and close admission.
/// Sub-owners never acquire independent locks: a commit spanning them remains atomic.
#[derive(Debug, Default)]
struct State {
    members: EntryRegistry,
    activation: ActivationCoordinator,
    close: CloseCoordinator,
    agent_services: Option<Arc<agent_services::AgentServices>>,
    observation: Option<observation::AssemblyObservation>,
    child_factory: Option<children::ChildFactory>,
}

use activation::ActivationCoordinator;
use close::CloseCoordinator;
use entry_registry::EntryRegistry;

pub(crate) type SessionCloseReport = Arc<Vec<(String, Arc<ThreadAssemblyError>)>>;

/// Prepared session installation data. The table checks and commits these slots; it does not run callbacks.
#[derive(Clone)]
pub(crate) struct SessionAssignment(AssignmentKind);

#[derive(Clone)]
enum AssignmentKind {
    Services {
        services: Arc<agent_services::AgentServices>,
        child_factory: children::ChildFactory,
    },
    Observation(observation::AssemblyObservation),
    WorkspaceRecovery(WorkspaceRecoveryPublisher),
    #[cfg(test)]
    Factory(children::ChildFactory),
}

impl SessionAssignment {
    fn kind(&self) -> &AssignmentKind {
        &self.0
    }

    pub(crate) fn services(
        config: crate::config::ConfigRuntime,
        store: crate::studio::StudioStore,
        events: crate::studio::ProductEventBus,
        factory: crate::studio::StudioThreadFactory,
        performance: crate::studio::ModelPerformanceOwner,
        recovery: crate::studio::StudioRecoveryRegistry,
        acp_business: crate::studio::runtime::acp_business::AcpBusinessOwner,
    ) -> Self {
        let child_factory = children::ChildFactory::new(children::ConfiguredChildFactory::new(
            config.clone(),
            factory.clone(),
        ));
        Self(AssignmentKind::Services {
            services: Arc::new(agent_services::AgentServices {
                factory,
                config,
                store,
                events,
                performance,
                recovery,
                operations: Default::default(),
                workspace_recovery: None,
                acp_business: Some(acp_business),
            }),
            child_factory,
        })
    }

    pub(crate) fn workspace_recovery(publisher: WorkspaceRecoveryPublisher) -> Self {
        Self(AssignmentKind::WorkspaceRecovery(publisher))
    }
}

/// Outcome of admitting one assignment onto one generation.
pub(crate) enum AssignmentAdmission {
    Ready,
    /// The generation is already leaving and is not an installation target.
    Skipping,
    Rejected(ThreadAssemblyError),
}

pub(crate) struct AssignmentGuard<'a> {
    state: std::sync::MutexGuard<'a, State>,
}

impl AssignmentGuard<'_> {
    pub(crate) fn admission(&self, assignment: &SessionAssignment) -> AssignmentAdmission {
        if self.state.close.closing {
            return AssignmentAdmission::Skipping;
        }
        match self.reject_reason(assignment) {
            Some(error) => AssignmentAdmission::Rejected(error),
            None => AssignmentAdmission::Ready,
        }
    }

    pub(crate) fn accepts(
        &self,
        assignment: &SessionAssignment,
    ) -> Result<(), ThreadAssemblyError> {
        self.reject_reason(assignment).map_or(Ok(()), Err)
    }

    pub(crate) fn commit(&mut self, assignment: &SessionAssignment) {
        match assignment.kind() {
            AssignmentKind::Services {
                services,
                child_factory,
            } => {
                self.state.agent_services = Some(Arc::clone(services));
                self.state.child_factory = Some(child_factory.clone());
            }
            AssignmentKind::Observation(observation) => {
                self.state.observation = Some(observation.clone());
            }
            AssignmentKind::WorkspaceRecovery(publisher) => {
                let services = self
                    .state
                    .agent_services
                    .as_mut()
                    .expect("recovery admission requires agent services");
                // In-flight operations keep the leases they already captured.
                Arc::make_mut(services).workspace_recovery = Some(publisher.clone());
            }
            #[cfg(test)]
            AssignmentKind::Factory(factory) => {
                self.state.child_factory = Some(factory.clone());
            }
        }
    }

    fn reject_reason(&self, assignment: &SessionAssignment) -> Option<ThreadAssemblyError> {
        let busy = self.state.close.closing
            || !self.state.members.entries.is_empty()
            || !self.state.activation.creating.is_empty();
        let rejected = match assignment.kind() {
            AssignmentKind::Services { .. } => {
                busy || self.state.agent_services.is_some() || self.state.child_factory.is_some()
            }
            AssignmentKind::Observation(_) => busy || self.state.observation.is_some(),
            AssignmentKind::WorkspaceRecovery(_) => {
                busy || self
                    .state
                    .agent_services
                    .as_ref()
                    .is_none_or(|services| services.workspace_recovery.is_some())
            }
            #[cfg(test)]
            AssignmentKind::Factory(_) => busy || self.state.child_factory.is_some(),
        };
        rejected.then_some(ThreadAssemblyError::Closed)
    }
}

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
    pub(crate) session_id: crate::SessionId,
    state: Mutex<State>,
    changed: tokio::sync::Notify,
    life: Mutex<CloseLife>,
}

impl Registry {
    pub(crate) fn open(session_id: crate::SessionId) -> Self {
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
        state.close.closing = true;
        for preparation in state.activation.creating.values() {
            preparation.cancellation.cancel();
        }
        for child in state.activation.preparing_children.values() {
            child.cancellation.cancel();
        }
        for entry in state.members.entries.values() {
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
        let registered_owner = state.members.entries.contains_key(&self.id)
            || state.activation.unpublished_children.contains_key(&self.id);
        state
            .activation
            .release_reservation(&self.id, registered_owner);
        drop(state);
        self.registry.changed.notify_waiters();
    }
}

impl SessionRuntime {
    /// Retains the canonical default Thread address of a cold directory member,
    /// without materializing any execution resources for that member.
    pub(crate) fn retain_directory_identity(
        &self,
        identity: &crate::AgentThreadIdentity,
    ) -> Result<(), ThreadAssemblyError> {
        if &identity.session_id != self.id() {
            return Err(ThreadAssemblyError::Identity(
                identity.thread_id.to_string(),
            ));
        }
        let mut state = self.0.state();
        if state.close.closing {
            return Err(ThreadAssemblyError::Closed);
        }
        if let Some(current) = state.members.by_agent.get(&identity.agent_id)
            && current != identity.thread_id.as_str()
        {
            return Err(ThreadAssemblyError::Identity(
                identity.thread_id.to_string(),
            ));
        }
        state
            .members
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
            .members
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
        let failed = self
            .0
            .state()
            .activation
            .failed_preparations
            .get(id)
            .cloned();
        let Some(failed) = failed else {
            return Ok(());
        };
        self.settle_retained_failed_preparation(id, failed).await
    }

    async fn settle_retained_failed_preparation(
        &self,
        id: &str,
        failed: Arc<FailedPreparation>,
    ) -> Result<(), ThreadAssemblyError> {
        let _permit = failed.gate.lock().await;
        // A waiter can retain an obsolete gate after another retry retired this owner.
        // Keep the qualified owner registered until cleanup ACKs so reserve stays blocked.
        if !self
            .0
            .state()
            .activation
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
            .activation
            .failed_preparations
            .get(id)
            .is_some_and(|current| Arc::ptr_eq(current, &failed))
        {
            state.activation.failed_preparations.remove(id);
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
            .members
            .entries
            .values()
            .filter_map(|entry| {
                let native = entry.native().ok()?;
                Some(native.resources.clone())
            })
            .chain(
                state
                    .activation
                    .creating
                    .values()
                    .filter_map(|preparing| preparing.resources.native().cloned()),
            )
            .chain(
                state
                    .activation
                    .unpublished_children
                    .values()
                    .map(|child| child.workspace.native_resources()),
            )
            .chain(
                state
                    .activation
                    .failed_preparations
                    .values()
                    .filter_map(|failed| failed.resources.native().cloned()),
            )
            .collect()
    }
    pub(crate) fn hosts(&self, thread_id: &str) -> bool {
        let state = self.0.state();
        state.members.entries.contains_key(thread_id)
            || state.activation.creating.contains_key(thread_id)
            || state.activation.preparing_children.contains_key(thread_id)
            || state
                .activation
                .unpublished_children
                .contains_key(thread_id)
            || state.activation.failed_preparations.contains_key(thread_id)
    }

    #[cfg(test)]
    pub(crate) async fn wait_for_registered_activation(&self, id: &str) {
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self
                .0
                .state()
                .activation
                .creating
                .get(id)
                .is_some_and(|preparation| preparation.result.is_some())
            {
                return;
            }
            changed.await;
        }
    }

    /// 取出本次装配预先放入的目录身份。没有目录身份就拒绝，不从 ThreadId 合成 AgentId。
    fn consume_activation(&self, thread_id: &str) -> Result<ThreadActivation, ThreadAssemblyError> {
        let mut state = self.0.state();
        let activation = match state.activation.pending_activation.remove(thread_id) {
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
            .activation
            .pending_activation
            .insert(activation.id().to_owned(), activation);
    }

    /// Shared admission order for evaluation, cold activation, user/agent input and close.
    /// Never acquire a lifecycle lock while holding this permit. No model Turn is awaited here.
    pub(crate) async fn agent_operation(&self, id: &str) -> tokio::sync::OwnedMutexGuard<()> {
        let gate = self.0.state().close.operation_gate(id);
        gate.lock_owned().await
    }

    pub(crate) fn ensure_agent_admission_open(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let state = self.0.state();
        if let Some(entry) = state.members.entries.get(id)
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
        if state.close.closing
            || state.close.sealed_agents.contains_key(id)
            || !state
                .members
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
    #[cfg(test)]
    pub fn set_child_factory(
        &self,
        factory: impl StudioChildFactory,
    ) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        if state.close.closing
            || !state.members.entries.is_empty()
            || !state.activation.creating.is_empty()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        state.child_factory = Some(children::ChildFactory::new(factory));
        Ok(())
    }

    #[cfg(test)]
    pub(crate) fn test_enter_closing(&self) {
        let mut life = self.0.life();
        life.phase = crate::session::SessionPhase::Closing;
    }

    pub(crate) fn lock_assignment(&self) -> AssignmentGuard<'_> {
        AssignmentGuard {
            state: self.0.state(),
        }
    }

    #[cfg(test)]
    pub(crate) fn test_has_observation(&self) -> bool {
        self.0.state().observation.is_some()
    }

    #[cfg(test)]
    pub(crate) fn test_has_child_factory(&self) -> bool {
        self.0.state().child_factory.is_some()
    }

    /// Returns only fully assembled owners, never partially initialized resources.
    pub fn thread(&self, id: &str) -> Option<ThreadHandle> {
        let state = self.0.state();
        if state.close.closing {
            return None;
        }
        state
            .members
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
        self.0.state().members.entries.get(id).and_then(|entry| {
            let native = entry.native().ok()?;
            Some(native.thread.clone())
        })
    }

    /// Returns read-only handles for all published or closing owners, including failed shutdowns.
    pub fn observed_threads(&self) -> Vec<(String, ThreadHandle)> {
        self.0
            .state()
            .members
            .entries
            .iter()
            .filter_map(|(id, entry)| {
                let native = entry.native().ok()?;
                Some((id.clone(), native.thread.clone()))
            })
            .collect()
    }
}

pub(crate) use tools::{StudioCommandProcesses, WeakCommandProcesses};

#[cfg(test)]
#[path = "thread_assembler/close_tests.rs"]
mod close_regression_tests;

#[cfg(test)]
pub(crate) mod test_support;
