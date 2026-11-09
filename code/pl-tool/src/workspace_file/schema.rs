use pl_agent_tool::ToolDefinition;

use crate::approval::ToolEffect;

pub use pl_tool_filesystem::apply_patch::{
    DESCRIPTION as APPLY_PATCH_FREEFORM_DESCRIPTION, NAME as TOOL_APPLY_PATCH,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceFileToolKind {
    ApplyPatch,
}

impl WorkspaceFileToolKind {
    pub fn all() -> &'static [Self] {
        &[Self::ApplyPatch]
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            TOOL_APPLY_PATCH => Some(Self::ApplyPatch),
            _ => None,
        }
    }

    /// 该类别工具的副作用声明。
    pub fn effect(self) -> ToolEffect {
        match self {
            Self::ApplyPatch => ToolEffect::WorkspaceWrite,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::ApplyPatch => TOOL_APPLY_PATCH,
        }
    }

    pub fn supports_parallel_tool_calls(self) -> bool {
        !matches!(self, Self::ApplyPatch)
    }

    pub fn definition(self) -> ToolDefinition {
        match self {
            Self::ApplyPatch => pl_tool_filesystem::apply_patch::definition(),
        }
    }
}
