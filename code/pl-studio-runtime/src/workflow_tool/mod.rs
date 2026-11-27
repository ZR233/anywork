//! Product workflow state transitions and Thread-owned dynamic tools.
mod compiler;
mod context;
mod dynamic;
pub(crate) mod machine;
mod output;
mod preview;
mod runtime;
mod state;
mod types;

pub use compiler::{
    CompiledWorkflowDefinition, MAX_WORKFLOW_DEFINITION_BYTES, MAX_WORKFLOW_STATES,
    MAX_WORKFLOW_TRANSITIONS, WorkflowCompilerError, WorkflowValidationIssue,
    compile_workflow_definition,
};
pub(crate) use context::workflow_model_context_section;
pub use dynamic::{WORKFLOW_EXTENSION, decode_workflow_state, encode_workflow_state};
pub(crate) use dynamic::{
    WorkflowOperationKind, workflow_registrations, workflow_tool_definitions,
};
pub(crate) use preview::preview_workflow;
pub(crate) use runtime::{WorkflowBinding, new_run, reconcile_workflow_for_turn};
pub(crate) use state::archive_workflow_for_mode_change;
pub use types::*;
pub const TOOL_WORKFLOW_CURRENT: &str = "workflow_current";
pub const TOOL_WORKFLOW_GRAPH: &str = "workflow_graph";
pub const TOOL_WORKFLOW_HISTORY: &str = "workflow_history";
pub const TOOL_WORKFLOW_NEXT: &str = "workflow_next";
pub const TOOL_WORKFLOW_TRANSITION: &str = "workflow_transition";
pub const TOOL_WORKFLOW_RESTART: &str = "workflow_restart";

/// Stable identities used by the host's request visibility policy.
pub(crate) fn workflow_tool_ids() -> [&'static str; 6] {
    [
        TOOL_WORKFLOW_CURRENT,
        TOOL_WORKFLOW_NEXT,
        TOOL_WORKFLOW_GRAPH,
        TOOL_WORKFLOW_HISTORY,
        TOOL_WORKFLOW_TRANSITION,
        TOOL_WORKFLOW_RESTART,
    ]
}
