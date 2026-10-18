//! Thread 归属的 Mode 注册、状态图编译、Turn 快照与工作流工具。

mod compiler;
mod context;
mod manager;
mod model_compatibility;
pub(crate) use model_compatibility::validate_thread_mode_model;
mod registration;
mod runtime;
pub mod state;

pub use compiler::{
    CompiledWorkflowDefinition, MAX_WORKFLOW_DEFINITION_BYTES, MAX_WORKFLOW_STATES,
    MAX_WORKFLOW_TRANSITIONS, WorkflowCompilerError, WorkflowValidationIssue,
    compile_workflow_definition,
};
pub use context::workflow_model_context_section;
pub use manager::{
    RegisteredThreadMode, ThreadModeManager, ThreadModeManagerError, ThreadModeRegistrySnapshot,
    ThreadModeSource, ThreadModeSourceId, ThreadModeSourceKind,
};
pub use registration::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition, ThreadModeRegistration,
};
pub use runtime::{new_run, reconcile_workflow_for_turn};

/// 工作流上下文段的稳定标识符。
pub const WORKFLOW_CONTEXT_SECTION_ID: &str = "pl.workflow";

/// Decode the one canonical Mode extension shared by preparation and projection.
pub(crate) fn decode_saved_mode(
    payload: &pl_core::context::OpaquePayload,
) -> Result<pl_protocol::ThreadModeId, pl_protocol::PureError> {
    if payload.format() != "pl.studio.mode" || payload.version() != 1 {
        return Err(pl_protocol::PureError::ConfigError(
            "unsupported saved Mode".into(),
        ));
    }
    Ok(serde_json::from_str(payload.content())?)
}
