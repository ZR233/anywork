//! Provider compatibility projection for canonical tool specifications.

use crate::completion::{ToolCallerMode, ToolFormat, ToolSpec};
use pl_agent_tool::{InputFormat, ToolDefinition};

use crate::model::ModelCapabilities;
use crate::protocol::ProtocolEndpoint;

mod hosted_output_schema;
mod input_schema;

pub use hosted_output_schema::{
    HOSTED_OUTPUT_SCHEMA_DIALECT, HostedOutputSchemaError, HostedOutputSchemaResources,
};

const APPLY_PATCH_FUNCTION_DESCRIPTION: &str = "Apply a Codex-style patch to workspace files. Pass the complete patch text, beginning with *** Begin Patch and ending with *** End Patch, in the required `input` string. Every file operation uses one of *** Add File: <path>, *** Delete File: <path>, or *** Update File: <path> (optionally followed by *** Move to: <path>). Do not use ---/+++ unified diff, *** File: metadata, or natural-language edit instructions such as Insert after. Update hunk lines start with a control prefix: space for context, `-` for deletion, `+` for addition; preserve a leading `-` or `+` in the file content after that prefix. If a previous patch failed, read the target file again and retry with a smaller patch based on current content.";

const APPLY_PATCH_FUNCTION_FALLBACK_DESCRIPTION: &str = "Complete Codex-style apply_patch text beginning with *** Begin Patch and ending with *** End Patch. Each file operation must use one of these hunk headers: *** Add File: <path>, *** Delete File: <path>, or *** Update File: <path>. Do not use ---/+++ unified diff, *** File: metadata, or natural-language edit instructions such as Insert after. If a previous patch failed, read the target file again and retry with a smaller patch based on current content; do not repeat the same failed patch. Minimal update example:\n*** Begin Patch\n*** Update File: notes.txt\n@@\n-old line\n+new line\n*** End Patch";

/// Host-selected model calling eligibility, independent of execution authorization.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ToolCallPolicy {
    #[default]
    DirectOnly,
    DirectAndProgrammatic,
}

/// Projects an author's complete declaration into the existing model wire DTO.
///
/// Programmatic eligibility requires an author-declared output schema. Execution permissions
/// come from the host policy and provider-specific schema restrictions belong to the codecs.
pub fn tool_definition_to_spec(definition: &ToolDefinition, policy: ToolCallPolicy) -> ToolSpec {
    let output_schema = definition.output_schema().cloned();
    let allowed_callers =
        if policy == ToolCallPolicy::DirectAndProgrammatic && output_schema.is_some() {
            vec![ToolCallerMode::Direct, ToolCallerMode::Programmatic]
        } else {
            Vec::new()
        };
    let name = definition.name().to_owned();
    let description = definition.description().to_owned();
    match definition.input() {
        InputFormat::JsonSchema(schema) => ToolSpec::Function {
            name,
            description,
            input_schema: schema.clone(),
            allowed_callers,
            output_schema,
        },
        InputFormat::Text => ToolSpec::Custom {
            name,
            description,
            format: ToolFormat::Text,
            allowed_callers,
            output_schema,
        },
        InputFormat::Grammar { syntax, definition } => ToolSpec::Custom {
            name,
            description,
            format: ToolFormat::Grammar {
                syntax: syntax.clone(),
                definition: definition.clone(),
            },
            allowed_callers,
            output_schema,
        },
    }
}

/// Custom 工具与 apply_patch 在目标 wire 上的投影策略。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToolProjection {
    /// endpoint 与模型原生支持 custom tool，apply_patch 还受账号配置约束。
    Native { apply_patch_freeform: bool },
    /// 目标 wire 或模型不支持 custom tool，投影为 Function fallback。
    ToFunction,
}

impl ToolProjection {
    pub fn for_endpoint(endpoint: &ProtocolEndpoint, capabilities: &ModelCapabilities) -> Self {
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

pub fn provider_compatible_tool(mut tool: ToolSpec, projection: ToolProjection) -> ToolSpec {
    if let ToolSpec::Function { input_schema, .. } = &mut tool {
        project_function_schema(input_schema);
    }
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

/// Removes generator annotations and redundant declarations from a model-facing copy.
///
/// Schema-valued positions are traversed; instance values in enum/const remain data.
/// This does not impose a function argument root on output or embedded SDK schemas.
pub fn project_schema_for_model(schema: &mut serde_json::Value) {
    input_schema::project(schema);
}

/// Function argument providers require an object root even for a union of objects.
/// Adapt only the request copy: the frozen author declaration remains intact.
pub fn project_function_schema(schema: &mut serde_json::Value) {
    project_schema_for_model(schema);
    let Some(object) = schema.as_object_mut() else {
        return;
    };
    let object_union = ["oneOf", "anyOf"].iter().any(|key| {
        object
            .get(*key)
            .and_then(serde_json::Value::as_array)
            .is_some_and(|variants| {
                !variants.is_empty()
                    && variants.iter().all(|variant| {
                        variant.get("type").and_then(serde_json::Value::as_str) == Some("object")
                            || variant.get("properties").is_some()
                    })
            })
    });
    if object.contains_key("properties") || object_union {
        object
            .entry("type")
            .or_insert_with(|| serde_json::Value::String("object".into()));
    }
}
