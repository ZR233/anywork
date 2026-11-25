//! Thread 工作模式注册、编辑与持久化快照。

mod editor;
mod manager;
mod registration;
mod snapshot;
mod types;

pub(crate) use crate::thread_mode_id::MODE_EXTENSION;
pub use crate::thread_mode_id::ThreadModeId;
pub use crate::workflow_tool::WorkflowPreviewSnapshot;
pub(crate) use editor::MAX_MODE_DOCUMENT_BYTES;
pub use editor::{
    mode_document_schema, preview_workflow, validate_mode_document, validate_mode_json,
};
pub use manager::{
    RegisteredThreadMode, ThreadModeManager, ThreadModeManagerError, ThreadModeRegistrySnapshot,
    ThreadModeSource, ThreadModeSourceId, ThreadModeSourceKind,
};
pub use registration::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition,
};
pub use types::*;

pub(crate) use snapshot::{
    SavedThreadMode, decode_mode_snapshot, decode_saved_mode, encode_mode_snapshot,
    migrate_mode_snapshot, presentation_mode, saved_registered_mode,
    workflow_binding_from_snapshot,
};
#[cfg(test)]
mod authoring_tests;
#[cfg(test)]
mod saved_snapshot_tests;
