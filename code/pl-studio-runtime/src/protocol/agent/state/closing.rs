use serde::{Deserialize, Serialize};

/// 已拒绝新工作、正在释放资源的 Agent。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ClosingAgentState {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    turn_id: Option<crate::TurnId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    error: Option<crate::StateError>,
}

impl ClosingAgentState {
    pub fn new() -> Self {
        Self::default()
    }
    pub fn turn_id(&self) -> Option<&crate::TurnId> {
        self.turn_id.as_ref()
    }
    pub fn error(&self) -> Option<&crate::StateError> {
        self.error.as_ref()
    }
}
