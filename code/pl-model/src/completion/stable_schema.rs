//! Deterministic encoding for supported typed tool declarations.
use crate::completion::ToolSpec;

/// Orders declarations by stable tool identity and recursively sorts JSON object keys.
/// Arrays retain producer-specified order; this function does not decode opaque tool inputs.
pub fn stable_tool_schemas(mut tools: Vec<ToolSpec>) -> Vec<ToolSpec> {
    for tool in &mut tools {
        match tool {
            ToolSpec::Function {
                input_schema,
                output_schema,
                ..
            } => {
                input_schema.sort_all_objects();
                if let Some(output) = output_schema {
                    output.sort_all_objects();
                }
            }
            ToolSpec::Custom { output_schema, .. } => {
                if let Some(output) = output_schema {
                    output.sort_all_objects();
                }
            }
            ToolSpec::ProgrammaticToolCalling | ToolSpec::WebSearch { .. } => {}
        }
    }
    tools.sort_by(|left, right| left.name().cmp(right.name()));
    tools
}
