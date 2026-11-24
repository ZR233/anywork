//! Product workflow state transitions and Thread-owned dynamic tools.
mod dynamic;
pub(crate) mod machine;
mod types;

pub use dynamic::{
    WORKFLOW_EXTENSION, decode_workflow_state, encode_workflow_state, workflow_registrations,
};
pub(crate) use dynamic::{WorkflowOperationKind, workflow_tool_definitions};
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
