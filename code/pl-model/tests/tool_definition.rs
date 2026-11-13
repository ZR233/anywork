use pl_agent_tool::ToolDefinition;
use pl_model::completion::{ToolCallPolicy, ToolSpec, tool_definition_to_spec};
use pl_protocol::{ToolCallerMode, ToolFormat};
use serde_json::json;

#[test]
fn author_definitions_project_without_rewriting_schema_or_input_format() {
    let input = json!({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "Author input",
        "$defs": {"message": {"type": "string"}},
        "oneOf": [
            {"type": "object", "properties": {"text": {"$ref": "#/$defs/message"}}},
            {"type": "object", "properties": {"count": {"type": "integer"}}}
        ]
    });
    let output = json!({"anyOf": [{"type": "string"}, {"type": "null"}]});
    let definitions = [
        ToolDefinition::json("json", "JSON input", input.clone()).unwrap(),
        ToolDefinition::text("text", "Text input").unwrap(),
        ToolDefinition::grammar("grammar", "Grammar input", "lark", "start: WORD\n").unwrap(),
    ];
    for definition in definitions {
        for has_output in [false, true] {
            let definition = if has_output {
                definition
                    .clone()
                    .with_output_schema(output.clone())
                    .unwrap()
            } else {
                definition.clone()
            };
            for policy in [
                ToolCallPolicy::DirectOnly,
                ToolCallPolicy::DirectAndProgrammatic,
            ] {
                let spec = tool_definition_to_spec(&definition, policy);
                assert_eq!(spec.name(), definition.name());
                assert_eq!(spec.description(), definition.description());
                let (callers, actual_output) = match &spec {
                    ToolSpec::Function {
                        input_schema,
                        allowed_callers,
                        output_schema,
                        ..
                    } => {
                        assert_eq!(input_schema, &input);
                        (allowed_callers, output_schema)
                    }
                    ToolSpec::Custom {
                        format,
                        allowed_callers,
                        output_schema,
                        ..
                    } => {
                        if definition.name() == "text" {
                            assert_eq!(format, &ToolFormat::Text);
                        } else {
                            assert_eq!(
                                format,
                                &ToolFormat::Grammar {
                                    syntax: "lark".into(),
                                    definition: "start: WORD\n".into(),
                                }
                            );
                        }
                        (allowed_callers, output_schema)
                    }
                    _ => panic!("local definitions must not become hosted tools"),
                };
                let expected_output = if has_output {
                    Some(output.clone())
                } else if policy == ToolCallPolicy::DirectAndProgrammatic {
                    Some(json!({"type":"object", "additionalProperties":true}))
                } else {
                    None
                };
                assert_eq!(actual_output, &expected_output);
                if policy == ToolCallPolicy::DirectOnly {
                    assert!(callers.is_empty());
                } else {
                    assert_eq!(
                        callers,
                        &[ToolCallerMode::Direct, ToolCallerMode::Programmatic]
                    );
                }
                let declaration = pl_model::runtime::thread_tool_declaration(&spec).unwrap();
                assert_eq!(declaration.format(), "pl.model.tool-spec");
                assert_eq!(declaration.version(), 1);
                let restored: ToolSpec = serde_json::from_str(declaration.content()).unwrap();
                assert_eq!(restored, spec);
            }
        }
    }
}
