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
            Self::ApplyPatch => pl_tool_filesystem::apply_patch::definition()
                .with_output_schema(patch_output_schema())
                .expect("static patch output schema"),
        }
    }
}

fn patch_output_schema() -> serde_json::Value {
    use serde_json::json;
    let text = json!({"type":"string"});
    let paths = json!({"type":"array","items":text});
    json!({"oneOf":[
        {"type":"object","properties":{
            "cwd":text,"added":paths,"updated":paths,"deleted":paths,"changedFiles":paths,
            "moved":{"type":"array","items":{"type":"object","properties":{"from":text,"to":text},"required":["from","to"],"additionalProperties":false}},
            "stdout":text,"stderr":text,"summary":text,
        },"required":["cwd","added","updated","deleted","moved","changedFiles","stdout","stderr"],"additionalProperties":false},
        {"type":"object","properties":{
            "cwd":text,"diagnostic":text,"changes_may_be_incomplete":{"type":"boolean"},
            "applied_changes":{"type":"array","items":{"oneOf":[
                {"type":"object","properties":{"Add":{"$ref":"#/$defs/PathChange"}},"required":["Add"],"additionalProperties":false},
                {"type":"object","properties":{"Update":{"$ref":"#/$defs/PathChange"}},"required":["Update"],"additionalProperties":false},
                {"type":"object","properties":{"Delete":{"$ref":"#/$defs/PathChange"}},"required":["Delete"],"additionalProperties":false},
                {"type":"object","properties":{"Move":{"type":"object","properties":{"source":text,"target":text},"required":["source","target"],"additionalProperties":false}},"required":["Move"],"additionalProperties":false},
            ]}},
        },"required":["cwd","diagnostic","changes_may_be_incomplete","applied_changes"],"additionalProperties":false},
    ],"$defs":{"PathChange":{"type":"object","properties":{"path":text},"required":["path"],"additionalProperties":false}}})
}
