//! Thread 归属的 Mode 注册、状态图编译、Turn 快照与工作流工具。

mod compiler;
mod context;
mod editor;
mod manager;
mod registration;
mod runtime;
pub mod state;

pub use compiler::{
    CompiledWorkflowDefinition, MAX_WORKFLOW_DEFINITION_BYTES, MAX_WORKFLOW_STATES,
    MAX_WORKFLOW_TRANSITIONS, WorkflowCompilerError, WorkflowValidationIssue,
    compile_workflow_definition,
};
pub use context::workflow_model_context_section;
pub(crate) use editor::MAX_MODE_DOCUMENT_BYTES;
pub use editor::{mode_document_schema, validate_mode_document, validate_mode_json};
pub use manager::{
    RegisteredThreadMode, ThreadModeManager, ThreadModeManagerError, ThreadModeRegistrySnapshot,
    ThreadModeSource, ThreadModeSourceId, ThreadModeSourceKind,
};
pub use pl_protocol::ThreadModeDefinition;
pub use registration::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition,
};
pub use runtime::{new_run, reconcile_workflow_for_turn};

/// 工作流上下文段的稳定标识符。
pub const WORKFLOW_CONTEXT_SECTION_ID: &str = "pl.workflow";

mod snapshot;
pub(crate) use snapshot::{
    SavedThreadMode, decode_mode_snapshot, decode_saved_mode, encode_mode_snapshot,
    migrate_mode_snapshot, saved_registered_mode,
};
mod preview;
pub use preview::preview_workflow;
