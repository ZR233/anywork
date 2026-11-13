use pl_protocol::PureError;
use pl_studio_workflow::mode::TransitionInput;
pub const TOOL_WORKFLOW_TRANSITION: &str = "workflow_transition";
/// Validates the same typed input accepted by the dynamic workflow tool.
pub fn validate_workflow_transition_arguments(
    arguments: serde_json::Value,
) -> Result<(), PureError> {
    serde_json::from_value::<TransitionInput>(arguments)
        .map(|_| ())
        .map_err(PureError::from)
}
