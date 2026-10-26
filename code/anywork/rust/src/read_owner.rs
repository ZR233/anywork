//! Bridge-internal read scope owners.
//!
//! These contracts return native resolve futures, so they live outside the `crate::api::studio`
//! tree that flutter_rust_bridge scans. Keeping them here preserves the explicit `Send` future
//! bounds required by the project's async trait convention without exposing them to codegen.

use std::future::Future;

use pl_protocol::products::identity::ProductReadScopeIdentity;
use pl_protocol::studio::{FeedCloseReport, StudioError};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;

/// Lifetime owner for a concrete Thread facet read scope.
pub(crate) trait ExecutionRead: Send + Sync + 'static {
    fn identity(&self) -> ReadScopeIdentity;
    fn ensure_open(&self) -> Result<(), StudioError>;
    fn request_close(&self);
    fn close(&self) -> impl Future<Output = FeedCloseReport> + Send;
}

/// Lifetime owner for a concrete product read scope.
pub(crate) trait ModelsRead: Send + Sync + 'static {
    fn identity(&self) -> ProductReadScopeIdentity;
    fn ensure_open(&self) -> Result<(), StudioError>;
    fn request_close(&self);
    fn close(&self) -> impl Future<Output = FeedCloseReport> + Send;
}
