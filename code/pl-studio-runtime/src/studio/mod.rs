pub(crate) mod agent_close;
mod agent_host;
pub(crate) mod catalog;
pub(crate) mod delegation;
pub(crate) mod entity;
mod ids;
mod instance;
mod merged_page;
pub(crate) mod model_binding;
pub(crate) mod model_route;
pub(crate) mod paths;
pub(crate) mod payload_alias;
#[allow(hidden_glob_reexports)] // 本地 persistence 模块有意遮蔽 `runtime::*` 的同名导出。
mod persistence;
mod product_event_bus;
mod records;
mod recovery_registry;
mod runtime;
mod runtime_lock;
mod runtime_state;
#[allow(hidden_glob_reexports)] // 本地 startup 模块有意遮蔽 `runtime::*` 的同名导出。
pub(crate) mod startup;
mod storage;
pub(crate) mod store;
mod store_support;
pub(crate) mod thread;
pub(crate) mod thread_factory;
pub(crate) mod thread_projection;
mod toml_store;
pub(crate) mod workspace_receipt;

pub(crate) use ids::{new_id, unix_seconds};
pub use instance::{StudioInstance, StudioInstanceLease};
pub(crate) use paths::StudioPaths;
pub use persistence::*;
pub use product_event_bus::ProductEventBus;
pub use records::{AttachmentRecord, ProjectRecord, ThreadKind, ThreadRecord, ThreadVisibility};
pub use recovery_registry::StudioRecoveryRegistry;
pub(crate) use runtime::ObservationCloseFailure;
pub(crate) use runtime::RejectedToolsCloseFailure;
pub use runtime::StudioProductTopicSubscription;
pub use runtime::*;
// Internal names avoid the storage/backup modules; lib.rs exports one canonical product path.
pub use runtime::{persistence as persistence_products, startup as startup_products};
pub use runtime_lock::{StudioHostKind, StudioRuntimeOptions};
pub use runtime_state::*;
pub use startup::{StudioStartupError, StudioStartupErrorKind, StudioStartupRecovery};
pub(crate) use storage::history::HistoryReadFailure;
pub use store::{StudioDatabaseError, StudioStore};

pub(crate) use thread_factory::StudioThreadFactory;
