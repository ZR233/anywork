//! Base declaration contract: construction, validation, serialization, and
//! bounded debug output, without any optional feature.

use pl_agent_tool::{DefinitionError, InputFormat, ToolDefinition};
use serde_json::json;

#[test]
fn json_definition_keeps_valid_values_and_exposes_them() {
    let schema = json!({"type": "object", "properties": {"left": {"type": "integer"}}});
    let definition = ToolDefinition::json("add", "Adds integers.", schema.clone()).unwrap();

    assert_eq!(definition.name(), "add");
    assert_eq!(definition.description(), "Adds integers.");
    assert_eq!(definition.input(), &InputFormat::JsonSchema(schema));
    assert_eq!(definition.output_schema(), None);
}

#[test]
fn schema_root_must_be_a_json_object_but_stays_uninterpreted() {
    for schema in [
        json!([1, 2]),
        json!("object"),
        json!(7),
        json!(null),
        json!(true),
    ] {
        let error = ToolDefinition::json("add", "Adds integers.", schema).unwrap_err();
        assert!(
            matches!(error, DefinitionError::InvalidInputSchema),
            "{error:?}"
        );
    }

    // Roots that are JSON objects are accepted even when they do not declare
    // `type: object` at the top; provider-side strictness is not applied here.
    let branches = json!({"anyOf": [], "$defs": {}});
    assert!(ToolDefinition::json("lookup", "Lookup.", branches).is_ok());
}

#[test]
fn whitespace_only_names_are_rejected_but_legal_bytes_are_kept() {
    for name in ["", "   ", " \t\r\n"] {
        let error = ToolDefinition::json(name, "d", json!({})).unwrap_err();
        assert!(matches!(error, DefinitionError::EmptyName));
        let error = ToolDefinition::text(name, "d").unwrap_err();
        assert!(matches!(error, DefinitionError::EmptyName));
        let error = ToolDefinition::grammar(name, "d", "lark", "start: A").unwrap_err();
        assert!(matches!(error, DefinitionError::EmptyName));
    }

    // Accepted values keep their original bytes; nothing is trimmed silently.
    let definition = ToolDefinition::json("  add  ", " d ", json!({})).unwrap();
    assert_eq!(definition.name(), "  add  ");
    assert_eq!(definition.description(), " d ");

    let text = ToolDefinition::text("note", "Writes a note.").unwrap();
    assert_eq!(text.input(), &InputFormat::Text);
}

#[test]
fn grammar_fields_are_validated_and_kept_verbatim() {
    let error = ToolDefinition::grammar("g", "d", "  ", "start: A").unwrap_err();
    assert!(matches!(error, DefinitionError::EmptyGrammarSyntax));
    let error = ToolDefinition::grammar("g", "d", "lark", "\t \n").unwrap_err();
    assert!(matches!(error, DefinitionError::EmptyGrammar));

    let grammar =
        ToolDefinition::grammar(" patch ", " description ", " lark ", "start: WORD\n").unwrap();
    let InputFormat::Grammar { syntax, definition } = grammar.input() else {
        panic!("grammar input expected");
    };
    assert_eq!(syntax, " lark ");
    assert_eq!(definition, "start: WORD\n");
}

#[test]
fn output_schema_is_optional_and_root_checked() {
    let schema = json!({"type": "array"});
    let definition = ToolDefinition::json("add", "d", json!({}))
        .unwrap()
        .with_output_schema(schema.clone())
        .unwrap();
    assert_eq!(definition.output_schema(), Some(&schema));

    let error = ToolDefinition::json("add", "d", json!({}))
        .unwrap()
        .with_output_schema(json!("not an object"))
        .unwrap_err();
    assert!(matches!(error, DefinitionError::InvalidOutputSchema));
}

#[test]
fn declarations_serialize_for_consumers() {
    let schema = json!({"type": "object"});
    let definition = ToolDefinition::json("add", "Adds.", schema.clone())
        .unwrap()
        .with_output_schema(json!({"type": "array"}))
        .unwrap();

    let encoded = serde_json::to_value(&definition).unwrap();
    assert_eq!(
        encoded,
        json!({
            "name": "add",
            "description": "Adds.",
            "input": {"JsonSchema": schema},
            "output_schema": {"type": "array"},
        })
    );

    let text = serde_json::to_value(ToolDefinition::text("note", "n").unwrap().input()).unwrap();
    assert_eq!(text, json!("Text"));

    let grammar = serde_json::to_value(
        ToolDefinition::grammar("g", "d", "lark", "start: A")
            .unwrap()
            .input(),
    )
    .unwrap();
    assert_eq!(
        grammar,
        json!({"Grammar": {"syntax": "lark", "definition": "start: A"}})
    );
}

#[test]
fn debug_output_stays_bounded() {
    let definition = ToolDefinition::json(
        "add",
        "SECRET-DESCRIPTION",
        json!({"properties": {"SECRET-SCHEMA": {}}}),
    )
    .unwrap()
    .with_output_schema(json!({"SECRET-OUTPUT": true}))
    .unwrap();

    let debug = format!("{definition:?}");
    assert!(debug.contains("add"), "{debug}");
    assert!(debug.contains("has_output_schema: true"), "{debug}");
    assert!(!debug.contains("SECRET-DESCRIPTION"), "{debug}");
    assert!(!debug.contains("SECRET-SCHEMA"), "{debug}");
    assert!(!debug.contains("SECRET-OUTPUT"), "{debug}");

    let grammar =
        ToolDefinition::grammar("g", "SECRET-DESCRIPTION", "lark", "SECRET-GRAMMAR").unwrap();
    let debug = format!("{:?} {:?}", grammar.input(), grammar);
    assert!(!debug.contains("SECRET-DESCRIPTION"), "{debug}");
    assert!(!debug.contains("SECRET-GRAMMAR"), "{debug}");

    let without_output = ToolDefinition::text("note", "n").unwrap();
    assert!(format!("{without_output:?}").contains("has_output_schema: false"));
}

#[test]
fn declarations_are_cloneable_and_comparable() {
    let definition = ToolDefinition::json("add", "d", json!({})).unwrap();
    let clone = definition.clone();
    assert_eq!(definition, clone);

    let other = ToolDefinition::json("sub", "d", json!({})).unwrap();
    assert_ne!(definition, other);
}
