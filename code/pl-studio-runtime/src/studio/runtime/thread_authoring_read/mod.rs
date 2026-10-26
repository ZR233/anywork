//! Exact Authoring reads over the original shared ThreadReadGroup and ReadCalls.
mod open;
mod queries;

use anyhow::Result;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use pl_protocol::thread_facets::authoring::PlanDocumentRef;
pub use pl_protocol::thread_facets::identity::{
    ReadScopeIdentity, ThreadFacetStamp, TodoReadRef, WorkflowReadRef,
};
pub use pl_protocol::thread_facets::read::values::{
    PlanDocumentReadHeader, PlanDocumentValue, TodoItemPage, TodoReadHeader, WorkflowReadHeader,
};
pub use queries::{StudioPlanDocumentRead, StudioTodoRead, StudioWorkflowRead};
use std::future::Future;

use super::StudioRuntime;
use super::thread_observation::ThreadFacetLease;
use super::thread_observation::facets::authoring::Material;
use super::thread_reads::lifetime::ThreadReadScope;
use super::thread_reads::{
    scalar::{PlanDocumentMaterial, WorkflowMaterial},
    todo::TodoMaterial,
};

type Scope<M> = ThreadReadScope<M, Material>;
