use pl_model_openai_wire::build_request;
use pl_model_wire::{
    completion::{CompletionRequest, ToolCallerMode, ToolSpec},
    model::{ModelDefinition, ModelTransportProfile},
    protocol::{InstructionWireRole, WireApi},
};
use serde_json::{Value, json};

const DIALECT: &str = "https://json-schema.org/draft/2020-12/schema";

fn tool(name: &str, schema: Value, caller: ToolCallerMode) -> ToolSpec {
    ToolSpec::Function {
        name: name.into(),
        description: "Lookup".into(),
        input_schema: json!({"type": "object"}),
        allowed_callers: vec![caller],
        output_schema: Some(schema),
    }
}

fn encode(tools: Vec<ToolSpec>) -> pl_protocol::Result<Value> {
    let mut model = ModelDefinition::compatible("schema-test");
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let request = CompletionRequest::builder().tools(tools).build();
    build_request(
        WireApi::Responses,
        InstructionWireRole::Developer,
        &request,
        &model,
        None,
        false,
    )
    .map(|body| serde_json::to_value(body).unwrap())
}

#[test]
fn hosted_output_resources_preserve_local_refs_and_stable_distinct_ids() {
    let author = json!({
        "$defs": {"leaf": {"type": "integer"}, "literal": {
            "const": {"$id": "literal.json", "$schema": "literal"},
            "enum": [{"$id": "literal.json", "$schema": "literal"}]
        }},
        "anyOf": [{"$ref": "#/$defs/leaf"}, {"type": "array", "items": {"$ref": "#"}}],
        "examples": [{"$id": "literal.json", "$schema": "literal", "$ref": "literal.json"}]
    });
    let program = ToolCallerMode::Programmatic;
    let first = tool("first", author.clone(), program);
    let second = tool("second", author.clone(), program);
    let body = encode(vec![first.clone(), second.clone()]).unwrap();
    let output_schemas = |body: &Value, index: usize| body["tools"][index]["output_schema"].clone();
    let first_schema = output_schemas(&body, 0);
    let second_schema = output_schemas(&body, 1);
    let mut embedded = first_schema["properties"]["data"]
        .as_object()
        .unwrap()
        .clone();
    let id = embedded.remove("$id").unwrap();
    assert!(id.as_str().unwrap().starts_with("https://anywork.invalid/"));
    assert_ne!(id, second_schema["properties"]["data"]["$id"]);
    assert_eq!(first_schema["$schema"], DIALECT);
    assert_eq!(embedded.remove("$schema"), Some(json!(DIALECT)));
    assert_eq!(Value::Object(embedded), author);
    let reordered = encode(vec![second, first]).unwrap();
    assert_eq!(output_schemas(&reordered, 1), first_schema);
    assert_eq!(output_schemas(&reordered, 0), second_schema);
    let changed = encode(vec![tool("first", json!({"type": "boolean"}), program)]).unwrap();
    assert_ne!(output_schemas(&changed, 0)["properties"]["data"]["$id"], id);
}

#[test]
fn hosted_output_resources_preserve_author_bases_and_reject_ambiguous_identity() {
    let program = ToolCallerMode::Programmatic;
    let author = json!({
        "$schema": DIALECT,
        "$id": "https://example.test/schema/root.json",
        "$defs": {"nested": {"$id": "nested.json", "$ref": "other.json"}},
        "$ref": "nested.json"
    });
    let body = encode(vec![tool("first", author.clone(), program)]).unwrap();
    assert_eq!(
        body["tools"][0]["output_schema"]["properties"]["data"],
        author
    );
    let urn = json!({"$schema": DIALECT, "$id": "urn:example:resource",
        "$defs":{"value":{"type":"string"}}, "$ref":"#/$defs/value"});
    let body = encode(vec![tool("urn", urn.clone(), program)]).unwrap();
    assert_eq!(body["tools"][0]["output_schema"]["properties"]["data"], urn);
    let conflicting = json!({"$id": author["$id"], "type": "string"});
    let error = encode(vec![
        tool("first", author, program),
        tool("second", conflicting, program),
    ])
    .unwrap_err();
    assert!(
        error.to_string().contains("conflicting output schema $id"),
        "{error}"
    );
}

#[test]
fn hosted_output_resources_resolve_nested_ids_across_tool_declarations() {
    let author = |root: &str, inner: &str, value_type: &str| {
        json!({
            "$schema": DIALECT,
            "$id": root,
            "$defs": {"parent": {"$id": inner,
                "$defs": {"child": {"$id": "shared.json", "type": value_type}},
                "$ref": "shared.json"
            }},
            "$ref": inner
        })
    };
    let left = author(
        "https://example.test/left.json",
        "left/parent.json",
        "integer",
    );
    let right = author(
        "https://example.test/right.json",
        "right/parent.json",
        "string",
    );
    let program = ToolCallerMode::Programmatic;
    let left_tool = tool("left", left.clone(), program);
    let body = encode(vec![
        left_tool.clone(),
        tool("right", right.clone(), program),
    ])
    .unwrap();
    assert_eq!(
        body["tools"][0]["output_schema"]["properties"]["data"],
        left
    );
    assert_eq!(
        body["tools"][1]["output_schema"]["properties"]["data"],
        right
    );

    let sibling = |root, value_type| {
        json!({
            "$id": root,
            "$defs": {"shared": {"$id": "shared.json", "type": value_type}},
            "$ref": "shared.json"
        })
    };
    let left = tool(
        "left",
        sibling("https://example.test/left.json", "integer"),
        program,
    );
    let right = tool(
        "right",
        sibling("https://example.test/right.json", "string"),
        program,
    );
    let error = encode(vec![left, right]).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("conflicting output schema $id https://example.test/shared.json"),
        "{error}"
    );

    let error = encode(vec![
        left_tool,
        tool(
            "right",
            json!({
                "$id": "https://example.test/right.json",
                "$defs": {"shared": {"$id": "left/shared.json", "type": "string"}}
            }),
            program,
        ),
    ])
    .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("conflicting output schema $id https://example.test/left/shared.json"),
        "{error}"
    );
}

#[test]
fn hosted_output_resources_detect_root_to_nested_collisions_in_one_declaration() {
    let resource = json!({"$id": "https://example.test/current.json", "type":"object",
        "properties":{"part":{"$id":"./current.json", "type":"integer"}},
        "const":{"$id":"./current.json","$schema":"plain data"},
        "enum":[{"$id":"./current.json"}]
    });
    let error = encode(vec![tool("lookup", resource, ToolCallerMode::Programmatic)]).unwrap_err();
    assert!(
        error
            .to_string()
            .contains("conflicting output schema $id https://example.test/current.json"),
        "{error}"
    );
}

#[test]
fn hosted_output_resources_reject_unavailable_bases_and_explicit_old_dialects() {
    let old = "http://json-schema.org/draft-07/schema#";
    let cases = [
        (json!({"$schema": old}), "2020-12"),
        (
            json!({"$defs": {"old": {"$id": "https://example.test/old", "$schema": old}}}),
            "2020-12",
        ),
        (json!({"$id": "relative.json"}), "$id"),
        (
            json!({"$id": "https://example.test/schema#fragment"}),
            "$id",
        ),
        (json!({"$id": "https://example.test/schema#"}), "$id"),
        (json!({"$id": 1}), "$id"),
        (
            json!({"$defs": {"nested": {"$id": "relative.json"}}}),
            "$id",
        ),
        (
            json!({"properties": {"field": {"$ref": "other.json"}}}),
            "$ref",
        ),
        (
            json!({"$dynamicRef": "//example.test/schema#node"}),
            "$dynamicRef",
        ),
        (
            json!({"$id":"urn:example:resource", "items":{"$id":"relative.json"}}),
            "$id",
        ),
        (
            json!({"$id":"urn:example:resource", "$ref":"relative.json"}),
            "$ref",
        ),
    ];
    for (schema, expected) in cases {
        let direct = encode(vec![tool("lookup", schema.clone(), ToolCallerMode::Direct)]).unwrap();
        assert!(direct["tools"][0].get("output_schema").is_none());
        let error = encode(vec![tool(
            "lookup",
            schema.clone(),
            ToolCallerMode::Programmatic,
        )])
        .unwrap_err();
        assert!(error.to_string().contains(expected), "{schema}: {error}");
    }
}
