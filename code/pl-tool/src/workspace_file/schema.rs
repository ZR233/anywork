use pl_protocol::ToolSpec;

use crate::approval::ToolEffect;

pub const TOOL_APPLY_PATCH: &str = "apply_patch";
pub const APPLY_PATCH_FREEFORM_DESCRIPTION: &str = "The `apply_patch` tool can be used to edit files. This is a FREEFORM tool, so do not wrap the patch in JSON. The input is a complete Codex-style patch beginning with *** Begin Patch and ending with *** End Patch; each file operation uses one of *** Add File: <path>, *** Delete File: <path>, or *** Update File: <path> (optionally followed by *** Move to: <path>). Do not use ---/+++ unified diff, *** File: metadata, or natural-language edit instructions such as Insert after. Update hunk lines start with a control prefix: space for context, `-` for deletion, `+` for addition; preserve a leading `-` or `+` in the file content after that prefix. If a previous patch failed, read the target file again and retry with a smaller patch based on current content.";

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

    pub fn to_spec(self) -> ToolSpec {
        match self {
            Self::ApplyPatch => ToolSpec::custom_grammar(
                TOOL_APPLY_PATCH,
                APPLY_PATCH_FREEFORM_DESCRIPTION,
                "lark",
                pl_patch::APPLY_PATCH_LARK_GRAMMAR,
            ),
        }
    }
}
