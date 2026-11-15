//! 通过显式注入的作用域管理资源归属，并观察真实清理结果。
//!
//! 所有者控制作用域；弱句柄只能登记资源，不能关闭作用域。丢弃所有者或受管资源会
//! 发出尽力而为的清理请求。正常退出时，须在关闭 Tokio 运行时之前等待根作用域，
//! 并检查报告。作用域不决定写入器、进程或数据库的领域关闭顺序。
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
//! let handle = owner.handle(); // 将弱句柄注入使用方。
//! let _listener = handle.on_close("listener", || { /* 解绑监听器 */ }).unwrap();
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
