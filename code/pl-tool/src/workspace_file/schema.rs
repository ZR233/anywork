use pl_protocol::ToolSpec;
use serde_json::Value;

use crate::approval::ToolEffect;
use crate::typed_tool_input_schema;

use super::ops::ApplyPatchInput;

pub const TOOL_APPLY_PATCH: &str = "apply_patch";

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

    pub fn description(self) -> &'static str {
        match self {
            Self::ApplyPatch => {
                "Apply a Codex-style patch to workspace files. The input field must contain a complete patch beginning with *** Begin Patch and ending with *** End Patch. Every Update hunk line starts with a control prefix: space for context, `-` for deletion, or `+` for addition. Preserve a leading `-` or `+` in the file content after that prefix; for example, replace Markdown `- old` with `-- old` and `+- new`."
            }
        }
    }

    pub fn input_schema(self) -> Value {
        match self {
            Self::ApplyPatch => typed_tool_input_schema::<ApplyPatchInput>(),
        }
    }

    pub fn supports_parallel_tool_calls(self) -> bool {
        !matches!(self, Self::ApplyPatch)
    }

    pub fn to_spec(self) -> ToolSpec {
        ToolSpec::function(self.name(), self.description(), self.input_schema())
    }
}
