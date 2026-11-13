//! 工作模式注册、状态图编译、不可变执行定义与工作流状态转换。

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
pub use editor::MAX_MODE_DOCUMENT_BYTES;
pub use editor::{mode_document_schema, validate_mode_document, validate_mode_json};
pub use manager::{
    RegisteredThreadMode, ThreadModeManager, ThreadModeManagerError, ThreadModeRegistrySnapshot,
    ThreadModeSource, ThreadModeSourceId, ThreadModeSourceKind,
};
pub use pl_protocol::{
    ContextSectionId, ModelContextSectionSnapshot, PureError, ThreadModeCatalogSnapshot,
    ThreadModeDefinition, ThreadModeDescriptor, ThreadModeDocument, ThreadModeEditorLayout,
    ThreadModeId, ThreadModeValidationIssue, ThreadModeValidationResult, UnknownLabelError,
    WorkflowDefinition, WorkflowOperationReceipt, WorkflowPreviewRequest, WorkflowPreviewSnapshot,
    WorkflowRun, WorkflowRunLifecycle, WorkflowSessionState, WorkflowState, WorkflowStateKind,
    WorkflowTransition,
};
pub use registration::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition,
};
pub use runtime::{new_run, reconcile_workflow_for_turn};

/// 工作流上下文段的稳定标识符。
pub const WORKFLOW_CONTEXT_SECTION_ID: &str = "pl.workflow";

mod preview;
pub use preview::preview_workflow;
mod machine;
pub use machine::{
    CompletionInput, EmptyInput, RestartInput, TransitionInput, WorkflowMachine,
    WorkflowMutationResponse, WorkflowOperation,
};

// JSON query snapshots and mutation responses use the same serde_json type identity.
pub use serde_json::Value;
