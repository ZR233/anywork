//! Exact immutable execution reads over the original ThreadReadGroup/ReadCalls lifecycle.
mod open;
mod queries;

use anyhow::Result;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
pub use pl_protocol::thread_facets::identity::{
    ActivityReadRef, InteractionIndexRef, InteractionReadRef, ReadScopeIdentity, StorageReadRef,
    ThreadFacetStamp, TurnReadRef,
};
pub use pl_protocol::thread_facets::read::execution::*;
pub use pl_protocol::thread_facets::read::interaction::*;
pub use queries::{
    StudioActivityRead, StudioInteractionIndexRead, StudioInteractionRead, StudioStorageRead,
    StudioTurnRead,
};
use std::future::Future;
use std::sync::Arc;

use super::StudioRuntime;
use super::thread_observation::ThreadFacetLease;
use super::thread_observation::facets::execution::Material;
use super::thread_reads::lifetime::ThreadReadScope;

type Scope<M> = ThreadReadScope<M, Material>;
