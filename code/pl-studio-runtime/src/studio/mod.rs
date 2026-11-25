pub(crate) mod agent_close;
#[cfg(feature = "benchmarks")]
#[doc(hidden)]
pub mod benchmark;
pub(crate) mod bot_owner;
pub(crate) mod catalog;
pub(crate) mod conversation_store;
pub(crate) mod delegation;
mod ids;
mod instance;
pub(crate) mod model_binding;
pub(crate) mod model_route;
pub(crate) mod paths;
pub(crate) mod payload_alias;
mod persistence;
pub(crate) mod producer_migration;
mod product_event_bus;
mod records;
mod recovery_registry;
pub(crate) mod runtime;
mod runtime_lock;
mod runtime_options;
mod runtime_state;
pub(crate) mod startup;
pub(crate) mod storage;
mod worktree;

pub(crate) mod store;
pub(crate) mod thread;
pub(crate) mod thread_factory;
pub(crate) mod thread_projection;
mod toml_store;
pub(crate) mod workspace_receipt;

pub(crate) use ids::{content_owner_key, new_id, unix_seconds};
pub use instance::{StudioInstance, StudioInstanceLease};
pub(crate) use paths::StudioPaths;
pub use persistence::*;
pub use product_event_bus::{
    ProductEventBus, ProductTopicReceiver, ProductTopicRecvError, ProductTopicTryRecvError,
};
pub use records::{AttachmentRecord, ThreadKind, ThreadRecord, ThreadVisibility, WorkspaceRecord};
pub use recovery_registry::StudioRecoveryRegistry;
pub use recovery_registry::{
    StudioRecoveryImpact, StudioRecoveryIssue, StudioRecoveryIssueAction,
    StudioRecoveryIssueCategory, StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner,
    StudioWorktreeInspection, StudioWorktreeRecoveryPreview,
};
pub use runtime::StudioProductTopicSubscription;
pub use runtime::*;
pub use runtime_options::{StudioHostKind, StudioRuntimeOptions, StudioStartupPolicy};
pub use runtime_state::*;
pub use startup::{StudioStartupError, StudioStartupErrorKind, StudioStartupRecovery};
pub(crate) use storage::thread_writer::{HistoryChannel, ThreadStorageBinding};
pub use store::{StudioDatabaseError, StudioStore};
pub use worktree::worktree_lease::WorkspaceUsageLease;

pub(crate) use thread_factory::StudioThreadFactory;

#[cfg(test)]
pub(crate) mod storage_fault_test_support {
    pub(crate) use super::storage::thread_writer::storage_fault_tests::{
        close_factory, register_test_thread, save_terminal_report, spawn_live_projection_for_thread,
    };
    pub(crate) use super::storage::thread_writer::{HistoryChannel, ThreadStorageSink};
}

pub(crate) mod history_delivery;

pub(crate) mod history_resources;
