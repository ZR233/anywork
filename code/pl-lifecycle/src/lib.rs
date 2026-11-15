//! Resource ownership and observable cleanup for explicitly injected scopes.
//!
//! An owner controls a scope; its weak handle can register resources without
//! gaining authority to close the scope. Dropping an owner or managed resource
//! requests best-effort cleanup. For deterministic shutdown, await the root
//! before shutting down its Tokio runtime and inspect the report. Scope cleanup
//! does not determine the domain's writer, process, or database shutdown order.
//!
//! ```
//! use pl_lifecycle::{Handle, Instant, ManagedResource, ScopeOwner};
//! use std::{convert::Infallible, sync::{Arc, atomic::{AtomicBool, Ordering}}, time::Duration};
//!
//! struct Connection(Arc<AtomicBool>);
//! impl ManagedResource for Connection {
//!     type Error = Infallible;
//!     fn request_close(&self) {}
//!     async fn close(&self) -> Result<(), Infallible> {
//!         self.0.store(true, Ordering::SeqCst);
//!         Ok(())
//!     }
//! }
//!
//! # tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async {
//! let owner = ScopeOwner::<Infallible>::new("application", Handle::current());
//! let handle = owner.handle(); // Inject this weak capability into consumers.
//! let _listener = handle.on_close("listener", || { /* unregister */ }).unwrap();
//! let closed = Arc::new(AtomicBool::new(false));
//! let connection = handle.open("connection", {
//!     let closed = Arc::clone(&closed);
//!     move |_cancel| async move { Ok(Connection(closed)) }
//! }).await.unwrap();
//! let _borrowed_connection = connection.get();
//! let report = owner.close(Instant::now() + Duration::from_secs(1)).await;
//! assert!(report.is_clean());
//! assert!(closed.load(Ordering::SeqCst));
//! # });
//! ```

mod error;
mod member;
mod registration;
mod scope;
mod worker;

pub use error::{
    AttemptId, CloseError, CloseReport, FailedResource, OpenError, PendingResource, Phase,
    RegistrationError, ResourceId, ResourceInfo, ScopeClosed, ScopeId,
};
pub use member::{Managed, ManagedResource};
pub use registration::Registration;
pub use scope::{ScopeHandle, ScopeOwner};
pub use tokio::runtime::Handle;
pub use tokio::time::Instant;
pub use tokio_util::sync::CancellationToken;
