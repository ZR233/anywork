//! Versioned product-state payloads over core's opaque extension contract.
use pl_core::{context::OpaquePayload, tool::opaque::ToolError};
use pl_protocol::{AgentSessionPlanState, PureError, WorkflowSessionState};
use serde::{Serialize, de::DeserializeOwned};

#[derive(Debug, thiserror::Error)]
#[error("unsupported state payload {format} version {version}")]
struct UnsupportedPayload {
    format: String,
    version: u32,
}

pub(crate) trait ExtensionState: Serialize + DeserializeOwned {
    const FORMAT: &'static str;
    fn validate(&self) -> Result<(), PureError>;

    fn encode(&self) -> Result<OpaquePayload, ToolError> {
        self.validate().map_err(ToolError::new)?;
        OpaquePayload::new(
            Self::FORMAT,
            1,
            serde_json::to_string(self).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)
    }

    fn decode(payload: &OpaquePayload) -> Result<Self, ToolError> {
        if payload.format() != Self::FORMAT || payload.version() != 1 {
            return Err(ToolError::new(UnsupportedPayload {
                format: payload.format().into(),
                version: payload.version(),
            }));
        }
        let state: Self = serde_json::from_str(payload.content()).map_err(ToolError::new)?;
        state.validate().map_err(ToolError::new)?;
        Ok(state)
    }
}

impl ExtensionState for AgentSessionPlanState {
    const FORMAT: &'static str = "pl.studio.plan";
    fn validate(&self) -> Result<(), PureError> {
        pl_studio_workflow::plan::validate_session_state_size(self)
    }
}

impl ExtensionState for WorkflowSessionState {
    const FORMAT: &'static str = "pl.studio.workflow";
    fn validate(&self) -> Result<(), PureError> {
        pl_studio_workflow::mode::state::validate_session_state_size(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{plan_tool::decode_plan_state, workflow_tool::decode_workflow_state};

    #[test]
    fn saved_extensions_reject_wrong_identity_future_versions_and_invalid_state() {
        let plan = OpaquePayload::new("pl.studio.plan", 1, r#"{"revision":0,"state":"drafting"}"#)
            .unwrap();
        assert_eq!(
            decode_plan_state(&plan).unwrap(),
            AgentSessionPlanState::default()
        );
        assert!(decode_workflow_state(&plan).is_err());
        let workflow = OpaquePayload::new("pl.studio.workflow", 1, "{}").unwrap();
        assert_eq!(
            decode_workflow_state(&workflow).unwrap(),
            WorkflowSessionState::default()
        );
        assert!(decode_plan_state(&workflow).is_err());
        for format in ["pl.studio.plan", "pl.studio.workflow"] {
            let future = OpaquePayload::new(format, 2, "{}").unwrap();
            assert!(decode_plan_state(&future).is_err());
            assert!(decode_workflow_state(&future).is_err());
        }
        let invalid_plan =
            OpaquePayload::new("pl.studio.plan", 1, r#"{"state":"approved"}"#).unwrap();
        assert!(decode_plan_state(&invalid_plan).is_err());
        let excessive = WorkflowSessionState {
            archived_run_digest: "x"
                .repeat(pl_studio_workflow::mode::state::MAX_WORKFLOW_STATE_BYTES),
            ..Default::default()
        };
        assert!(excessive.encode().is_err());
        let excessive = OpaquePayload::new(
            "pl.studio.workflow",
            1,
            serde_json::to_string(&excessive).unwrap(),
        )
        .unwrap();
        assert!(decode_workflow_state(&excessive).is_err());
    }
}
