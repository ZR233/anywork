//! Product behavior over the session-owned membership/activation/close transaction.
//!
//! Configuration, physical workspace eligibility, storage and product publication stay here.
//! The Core assembly layer owns registration and commit; these implementations use that same
//! transaction rather than copying membership into a second product registry.
pub(crate) use crate::thread_assembler::{
    ArchiveScopeSeal, AssignmentKind, ChildThreadRequest, ClosePurpose, EntryPurpose,
    EntryRegistry, Registry, Reservation, SessionAssignment, SessionRuntime, State,
    StudioActivationFactory, StudioChildFactory, StudioChildResources, StudioThreadSpec,
    ThreadActivation, ThreadAssemblyError, ThreadPreparation, WorkspaceBindingAdmission,
    WorkspacePreparationOwner, WorkspaceUsageLease, child_resources, children, observation, tools,
};
pub(crate) use agents::AgentHost;
pub(crate) use close_storage::CloseStorage;
use pl_core::thread::{ThreadError, ThreadHandle, ThreadLifecycle};
use std::sync::Arc;
pub(crate) mod acp;
pub(crate) mod agent_close;
pub(crate) mod agent_close_recovery;
pub(crate) mod agent_evaluation;
pub(crate) mod agent_review;
pub(crate) mod agent_wait;
pub(crate) mod agents;
pub(crate) mod close_storage;
pub(crate) mod delegation_models;
pub(crate) mod host_agent_tools;
pub(crate) mod host_workspace_tools;
pub(crate) mod owner;
pub(crate) mod pending_delivery;
pub(crate) mod report_receiver;
pub(crate) mod review_delivery;
pub(crate) mod review_dispatch;

pub(crate) mod admission;
mod lifecycle;
mod observation_delivery;
