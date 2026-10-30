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
mod persistence;
pub(crate) mod producer_migration;
mod product_event_bus;
mod records;
mod recovery_registry;
mod runtime;
mod runtime_lock;
mod runtime_state;
pub(crate) mod startup;
mod storage;
#[cfg(test)]
pub(crate) mod storage_fault_test_support {
    pub(crate) use super::storage::thread_writer::storage_fault_tests::{
        close_factory, register_test_thread, save_terminal_report, spawn_live_projection,
        spawn_live_projection_for_thread, ticket,
    };
    pub(crate) use super::storage::thread_writer::{HistoryChannel, ThreadStorageSink};
}
pub(crate) mod store;
mod store_support;
pub(crate) mod thread;
pub(crate) mod thread_factory;
pub(crate) mod thread_projection;
mod toml_store;
pub(crate) mod workspace_receipt;

pub use agent_host::worktree_lease::WorkspaceUsageLease;
pub(crate) use ids::{new_id, unix_seconds};
pub use instance::{StudioInstance, StudioInstanceLease};
pub(crate) use paths::StudioPaths;
pub use persistence::*;
pub use product_event_bus::ProductEventBus;
pub use records::{AttachmentRecord, ThreadKind, ThreadRecord, ThreadVisibility, WorkspaceRecord};
pub use recovery_registry::StudioRecoveryRegistry;
pub use runtime::StudioProductTopicSubscription;
pub use runtime::*;
pub use runtime_lock::{StudioHostKind, StudioRuntimeOptions};
pub use runtime_state::*;
pub use startup::{StudioStartupError, StudioStartupErrorKind, StudioStartupRecovery};
pub(crate) use storage::thread_writer::{HistoryChannel, ThreadStorageBinding};
pub use store::{StudioDatabaseError, StudioStore};

pub(crate) use thread_factory::StudioThreadFactory;
