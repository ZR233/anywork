use pl_protocol::ToolSpec;
use serde_json::Value;

use crate::approval::ToolEffect;
use crate::typed_tool_input_schema;

use super::ops::{ApplyPatchInput, ListFilesInput};

pub const TOOL_LIST_FILES: &str = "list_files";
pub const TOOL_APPLY_PATCH: &str = "apply_patch";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceFileToolKind {
    ListFiles,
    ApplyPatch,
}

impl WorkspaceFileToolKind {
    pub fn all() -> &'static [Self] {
        &[Self::ListFiles, Self::ApplyPatch]
    }

    pub fn from_name(name: &str) -> Option<Self> {
        match name {
            TOOL_LIST_FILES => Some(Self::ListFiles),
            TOOL_APPLY_PATCH => Some(Self::ApplyPatch),
            _ => None,
        }
    }

    /// 该类别工具的副作用声明。
    pub fn effect(self) -> ToolEffect {
        match self {
            Self::ListFiles => ToolEffect::Read,
            Self::ApplyPatch => ToolEffect::WorkspaceWrite,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::ListFiles => TOOL_LIST_FILES,
            Self::ApplyPatch => TOOL_APPLY_PATCH,
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Self::ListFiles => {
                "List descendants from the agent workspace with an optional glob and bounded result count. Omit path or use `.` for the workspace root. For pagination, reuse the exact nextCursor and keep path, cwd, glob, and includeDirs unchanged; limit may change. Any intervening workspace write, exec, or Git mutation invalidates existing cursors. Results are filtered (including internal Git/build paths); an empty list does not prove the physical directory is empty. Use stat_path for a specific excluded path. A missing or empty workspace directory returns an empty list."
            }
            Self::ApplyPatch => {
                "Apply a Codex-style patch to workspace files. The input field must contain a complete patch beginning with *** Begin Patch and ending with *** End Patch. Every Update hunk line starts with a control prefix: space for context, `-` for deletion, or `+` for addition. Preserve a leading `-` or `+` in the file content after that prefix; for example, replace Markdown `- old` with `-- old` and `+- new`."
            }
        }
    }

    pub fn input_schema(self) -> Value {
        match self {
            Self::ListFiles => typed_tool_input_schema::<ListFilesInput>(),
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
