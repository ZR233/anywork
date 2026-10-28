//! Provider compatibility projection for canonical tool specifications.

use pl_protocol::ToolSpec;

use crate::model::ModelCapabilities;
use crate::protocol::ProtocolEndpoint;

const APPLY_PATCH_FUNCTION_DESCRIPTION: &str = "Apply a Codex-style patch to workspace files. Pass the complete patch text, beginning with *** Begin Patch and ending with *** End Patch, in the required `input` string. Every file operation uses one of *** Add File: <path>, *** Delete File: <path>, or *** Update File: <path> (optionally followed by *** Move to: <path>). Do not use ---/+++ unified diff, *** File: metadata, or natural-language edit instructions such as Insert after. Update hunk lines start with a control prefix: space for context, `-` for deletion, `+` for addition; preserve a leading `-` or `+` in the file content after that prefix. If a previous patch failed, read the target file again and retry with a smaller patch based on current content.";

const APPLY_PATCH_FUNCTION_FALLBACK_DESCRIPTION: &str = "Complete Codex-style apply_patch text beginning with *** Begin Patch and ending with *** End Patch. Each file operation must use one of these hunk headers: *** Add File: <path>, *** Delete File: <path>, or *** Update File: <path>. Do not use ---/+++ unified diff, *** File: metadata, or natural-language edit instructions such as Insert after. If a previous patch failed, read the target file again and retry with a smaller patch based on current content; do not repeat the same failed patch. Minimal update example:\n*** Begin Patch\n*** Update File: notes.txt\n@@\n-old line\n+new line\n*** End Patch";

/// Projects an explicitly eligible local declaration for a hosted coordinator.
/// The host validates the executor's side effects before requesting this projection.
pub fn programmatic_tool_declaration(spec: ToolSpec) -> ToolSpec {
    let output_schema = match &spec {
        ToolSpec::Function { output_schema, .. } | ToolSpec::Custom { output_schema, .. } => {
            output_schema.clone().unwrap_or_else(
                || serde_json::json!({"type":"object", "additionalProperties":true}),
            )
        }
        ToolSpec::ProgrammaticToolCalling | ToolSpec::WebSearch { .. } => return spec,
    };
    spec.allow_programmatic(output_schema)
}

/// Custom 工具与 apply_patch 在目标 wire 上的投影策略。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ToolProjection {
    /// endpoint 与模型原生支持 custom tool，apply_patch 还受账号配置约束。
    Native { apply_patch_freeform: bool },
    /// 目标 wire 或模型不支持 custom tool，投影为 Function fallback。
    ToFunction,
}

impl ToolProjection {
    pub(crate) fn for_endpoint(
        endpoint: &ProtocolEndpoint,
        capabilities: &ModelCapabilities,
    ) -> Self {
        if endpoint.uses_native_custom_tools()
            && capabilities.supports_custom_tools()
            && capabilities.supports_freeform_tools()
        {
            Self::Native {
                apply_patch_freeform: endpoint.apply_patch_tool_type.is_some(),
            }
        } else {
            Self::ToFunction
        }
    }
}

pub(crate) fn provider_compatible_tool(tool: ToolSpec, projection: ToolProjection) -> ToolSpec {
    if let ToolProjection::Native {
        apply_patch_freeform,
    } = projection
        && (apply_patch_freeform || tool.name() != "apply_patch")
    {
        return tool;
    }

    match tool {
        ToolSpec::Custom {
            name,
            allowed_callers,
            output_schema,
            ..
        } if name == "apply_patch" => ToolSpec::Function {
            name,
            description: APPLY_PATCH_FUNCTION_DESCRIPTION.to_owned(),
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "input": {
                        "type": "string",
                        "description": APPLY_PATCH_FUNCTION_FALLBACK_DESCRIPTION
                    }
                },
                "required": ["input"],
                "additionalProperties": false
            }),
            allowed_callers,
            output_schema,
        },
        ToolSpec::Custom {
            name,
            description,
            allowed_callers,
            output_schema,
            ..
        } => ToolSpec::Function {
            name,
            description,
            input_schema: serde_json::json!({
                "type": "object",
                "properties": {
                    "input": { "type": "string" }
                },
                "required": ["input"],
                "additionalProperties": false
            }),
            allowed_callers,
            output_schema,
        },
        tool => tool,
    }
}
