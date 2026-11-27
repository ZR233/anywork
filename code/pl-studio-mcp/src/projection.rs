//! Frozen, transport-only projections of author-owned tool declarations.

use pl_agent_tool::{InputFormat, ToolDefinition};
use serde_json::{Map, Value, json};
use uuid::Uuid;

use crate::{HostError, HostTool};

const DIALECT: &str = "https://json-schema.org/draft/2020-12/schema";

/// Registration policy for JSON input; it never depends on a tool's name.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JsonInput {
    /// Encode the MCP arguments object directly as the author's JSON input.
    Object,
    /// Unwrap the sole `input` field as the author's arbitrary JSON value.
    Value,
}

/// Original author input recovered from the MCP arguments envelope.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProjectedInput {
    Json(String),
    Text(String),
}

/// A declaration cannot be projected without changing its schema semantics.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ProjectionError {
    #[error("author input schema must be a JSON object")]
    InvalidInputSchema,
    #[error("author output schema must be a JSON Schema object or boolean")]
    InvalidOutputSchema,
    #[error("embedded schema must use JSON Schema 2020-12")]
    UnsupportedDialect,
    #[error("embedded schema $id must be an absolute URI without a fragment")]
    InvalidSchemaId,
    #[error("embedded schema {0} needs an author-provided absolute base URI")]
    MissingReferenceBase(&'static str),
}

#[derive(Debug, Clone, Copy)]
enum Decode {
    Json(JsonInput),
    Text,
}

/// One prepared declaration and its matching argument decoding strategy.
///
/// This adapter does not validate business input, run grammars, or own execution.
/// Prepare once alongside the callable binding and reuse the frozen projection.
#[derive(Debug, Clone)]
pub struct ToolProjection {
    declaration: HostTool,
    decode: Decode,
}

impl ToolProjection {
    /// Projects the complete author schema without reconstructing its properties.
    ///
    /// `publish_output_schema` is the registrant's assertion that actual returned
    /// results satisfy the author's final output contract. Pass `false` for an
    /// execution path that can instead return a pending task receipt.
    ///
    /// JSON value envelopes require an explicit author `$schema` of 2020-12.
    /// Missing or different dialects are rejected rather than guessing their
    /// meaning. The author remains responsible for a valid schema document.
    pub fn prepare(
        definition: &ToolDefinition,
        json_input: JsonInput,
        publish_output_schema: bool,
    ) -> Result<Self, ProjectionError> {
        let (input_schema, decode) = match definition.input() {
            InputFormat::JsonSchema(schema) => {
                let schema = schema
                    .as_object()
                    .ok_or(ProjectionError::InvalidInputSchema)?;
                let schema = match json_input {
                    JsonInput::Object => schema.clone(),
                    JsonInput::Value => input_envelope(Value::Object(embedded_resource(schema)?)),
                };
                (schema, Decode::Json(json_input))
            }
            InputFormat::Text | InputFormat::Grammar { .. } => {
                (input_envelope(json!({"type": "string"})), Decode::Text)
            }
        };
        let output_schema = if publish_output_schema {
            definition
                .output_schema()
                .map(output_envelope)
                .transpose()?
        } else {
            None
        };
        Ok(Self {
            declaration: HostTool {
                tool_id: format!("anywork_{}", definition.name()),
                description: definition.description().to_owned(),
                input_schema,
                output_schema,
            },
            decode,
        })
    }

    /// Returns the exact frozen MCP declaration paired with this decoder.
    pub fn declaration(&self) -> &HostTool {
        &self.declaration
    }

    /// Removes only the transport envelope, leaving author validation to the tool.
    ///
    /// Wrapped inputs require exactly one `input` field. Text and grammar input
    /// must be a string and is returned without JSON quoting or normalization.
    pub fn decode(&self, arguments: Map<String, Value>) -> Result<ProjectedInput, HostError> {
        match self.decode {
            Decode::Json(JsonInput::Object) => {
                Ok(ProjectedInput::Json(Value::Object(arguments).to_string()))
            }
            Decode::Json(JsonInput::Value) => {
                Ok(ProjectedInput::Json(unwrap_input(arguments)?.to_string()))
            }
            Decode::Text => match unwrap_input(arguments)? {
                Value::String(input) => Ok(ProjectedInput::Text(input)),
                _ => Err(HostError::InvalidRequest),
            },
        }
    }
}

fn unwrap_input(mut arguments: Map<String, Value>) -> Result<Value, HostError> {
    if arguments.len() != 1 {
        return Err(HostError::InvalidRequest);
    }
    arguments.remove("input").ok_or(HostError::InvalidRequest)
}

fn input_envelope(input: Value) -> Map<String, Value> {
    Map::from_iter([
        ("$schema".into(), DIALECT.into()),
        ("type".into(), "object".into()),
        ("properties".into(), json!({"input": input})),
        ("required".into(), json!(["input"])),
        ("additionalProperties".into(), false.into()),
    ])
}

fn output_envelope(schema: &Value) -> Result<Map<String, Value>, ProjectionError> {
    let output = match schema {
        Value::Bool(_) => schema.clone(),
        Value::Object(schema) => {
            let mut schema = schema.clone();
            // MCP defaults an unspecified dialect to 2020-12. A resource
            // boundary keeps author-local references rooted in this schema.
            schema.entry("$schema").or_insert_with(|| DIALECT.into());
            Value::Object(embedded_resource(&schema)?)
        }
        _ => return Err(ProjectionError::InvalidOutputSchema),
    };
    Ok(Map::from_iter([
        ("$schema".into(), DIALECT.into()),
        ("type".into(), "object".into()),
        ("properties".into(), json!({"result": output})),
        ("required".into(), json!(["result"])),
        ("additionalProperties".into(), false.into()),
    ]))
}

fn embedded_resource(schema: &Map<String, Value>) -> Result<Map<String, Value>, ProjectionError> {
    if schema.get("$schema").and_then(Value::as_str) != Some(DIALECT) {
        return Err(ProjectionError::UnsupportedDialect);
    }
    validate_resource_scope(schema, false)?;
    let mut resource = schema.clone();
    // JSON Schema Core 2020-12 §§8.2.1 and 9.3: $id establishes an
    // independently rooted embedded resource. Local $ref values, including #,
    // still resolve against the original schema rather than the MCP envelope.
    resource.entry("$id").or_insert_with(|| {
        // An identifier, not a network endpoint. Hierarchical absolute IDs also
        // preserve local-fragment resolution in consumers using URL joiners.
        Value::String(format!(
            "https://anywork.invalid/tool-schema/{}",
            Uuid::new_v4()
        ))
    });
    Ok(resource)
}

// Classify the resource boundary only; the author remains responsible for a valid schema.
// Identifiers may be non-HTTP URIs (including URNs).
fn absolute_uri(value: &str) -> bool {
    value.split_once(':').is_some_and(|(scheme, _)| {
        scheme.starts_with(|c: char| c.is_ascii_alphabetic())
            && scheme
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'-' | b'.'))
    })
}

fn validate_resource_scope(
    schema: &Map<String, Value>,
    mut author_base: bool,
) -> Result<(), ProjectionError> {
    if let Some(dialect) = schema.get("$schema")
        && dialect.as_str() != Some(DIALECT)
    {
        return Err(ProjectionError::UnsupportedDialect);
    }
    if let Some(id) = schema.get("$id") {
        let id = id
            .as_str()
            .filter(|id| {
                !id.is_empty()
                    && !id.contains('#')
                    && id.bytes().all(|byte| byte.is_ascii_graphic())
            })
            .ok_or(ProjectionError::InvalidSchemaId)?;
        author_base |= absolute_uri(id);
        if !author_base {
            return Err(ProjectionError::InvalidSchemaId);
        }
    }
    if !author_base {
        for keyword in ["$ref", "$dynamicRef"] {
            if let Some(uri) = schema.get(keyword).and_then(Value::as_str)
                && !uri.is_empty()
                && !uri.starts_with('#')
                && !absolute_uri(uri)
            {
                return Err(ProjectionError::MissingReferenceBase(keyword));
            }
        }
    }
    // Only schema-valued keywords establish scope; const/enum/examples are author data.
    for key in [
        "$defs",
        "definitions",
        "properties",
        "patternProperties",
        "dependentSchemas",
        "dependencies",
    ] {
        if let Some(table) = schema.get(key).and_then(Value::as_object) {
            for child in table.values().filter_map(Value::as_object) {
                validate_resource_scope(child, author_base)?;
            }
        }
    }
    for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
        if let Some(list) = schema.get(key).and_then(Value::as_array) {
            for child in list.iter().filter_map(Value::as_object) {
                validate_resource_scope(child, author_base)?;
            }
        }
    }
    for key in [
        "items",
        "additionalItems",
        "unevaluatedItems",
        "contentSchema",
        "additionalProperties",
        "unevaluatedProperties",
        "contains",
        "propertyNames",
        "not",
        "if",
        "then",
        "else",
    ] {
        if let Some(child) = schema.get(key).and_then(Value::as_object) {
            validate_resource_scope(child, author_base)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_transport_envelope_preserves_author_schema_resource_and_finality() {
        let author = json!({
            "$schema": DIALECT,
            "$id": "https://example.test/answer",
            "$defs": {"answer": {"type": ["string", "null"]}},
            "$ref": "#/$defs/answer"
        });
        let definition = ToolDefinition::json("answer", "answer", json!({"type":"object"}))
            .unwrap()
            .with_output_schema(author.clone())
            .unwrap();
        let projection = ToolProjection::prepare(&definition, JsonInput::Object, true).unwrap();
        assert_eq!(
            projection.declaration().output_schema.as_ref().unwrap(),
            json!({
                "$schema": DIALECT,
                "type":"object",
                "properties":{"result":author},
                "required":["result"],
                "additionalProperties":false
            })
            .as_object()
            .unwrap()
        );
        assert!(
            ToolProjection::prepare(&definition, JsonInput::Object, false)
                .unwrap()
                .declaration()
                .output_schema
                .is_none()
        );
    }

    #[test]
    fn output_schema_rejects_incompatible_embedded_dialect_and_relative_identity() {
        assert_eq!(
            output_envelope(&json!({"$schema":"http://json-schema.org/draft-07/schema#"})),
            Err(ProjectionError::UnsupportedDialect)
        );
        assert_eq!(
            output_envelope(&json!({"$id":"relative.json"})),
            Err(ProjectionError::InvalidSchemaId)
        );
        let schema = output_envelope(&json!({"type":"array", "items":{"type":"integer"}})).unwrap();
        let resource = &schema["properties"]["result"];
        assert_eq!(resource["type"], "array");
        assert_eq!(resource["$schema"], DIALECT);
        assert!(
            resource["$id"]
                .as_str()
                .unwrap()
                .starts_with("https://anywork.invalid/")
        );
    }

    #[test]
    fn output_references_keep_author_scope_without_inventing_relative_bases() {
        for keyword in ["$ref", "$dynamicRef"] {
            let schema = json!({"properties":{"answer":{keyword:"other.json#/$defs/value"}}});
            assert_eq!(
                output_envelope(&schema),
                Err(ProjectionError::MissingReferenceBase(keyword))
            );
            let mut based = schema.clone();
            based["$id"] = "https://example.test/answer.json".into();
            assert!(output_envelope(&based).is_ok());
        }
        let recursive = json!({"$defs":{"child":{"$ref":"#"}},"$ref":"#/$defs/child",
            "const":{"$ref":"not-a-schema.json","$schema":"user data"}});
        let envelope = output_envelope(&recursive).unwrap();
        assert_eq!(
            envelope["properties"]["result"]["$defs"],
            recursive["$defs"]
        );
        assert_eq!(
            envelope["properties"]["result"]["const"],
            recursive["const"]
        );
        assert!(output_envelope(&json!({"$id":"urn:example:answer","$ref":"#"})).is_ok());
    }
}
