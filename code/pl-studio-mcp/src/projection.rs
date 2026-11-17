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
    #[error("author output schema must be a JSON object")]
    InvalidOutputSchema,
    #[error("embedded input schema must use JSON Schema 2020-12")]
    UnsupportedDialect,
    #[error("embedded input schema $id must be an absolute URI without a fragment")]
    InvalidSchemaId,
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
                .map(|schema| {
                    schema
                        .as_object()
                        .cloned()
                        .ok_or(ProjectionError::InvalidOutputSchema)
                })
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

fn embedded_resource(schema: &Map<String, Value>) -> Result<Map<String, Value>, ProjectionError> {
    if schema.get("$schema").and_then(Value::as_str) != Some(DIALECT) {
        return Err(ProjectionError::UnsupportedDialect);
    }
    if let Some(id) = schema.get("$id") {
        // A valid author URI is absolute iff it has an RFC 3986 scheme.
        // Do not parse it as an HTTP URI: identifiers may be non-hierarchical
        // (urn:uuid, for example). This only classifies the resource boundary,
        // not URI validity or the rest of the author's schema document.
        let absolute = id.as_str().is_some_and(|id| {
            !id.contains('#')
                && id.split_once(':').is_some_and(|(scheme, _)| {
                    scheme.starts_with(|c: char| c.is_ascii_alphabetic())
                        && scheme
                            .bytes()
                            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'+' | b'-' | b'.'))
                })
        });
        if !absolute {
            return Err(ProjectionError::InvalidSchemaId);
        }
    }
    let mut resource = schema.clone();
    // JSON Schema Core 2020-12 §§8.2.1 and 9.3: $id establishes an
    // independently rooted embedded resource. Local $ref values, including #,
    // still resolve against the original schema rather than the MCP envelope.
    resource.entry("$id").or_insert_with(|| {
        // An identifier, not a network endpoint. Hierarchical absolute IDs also
        // preserve local-fragment resolution in consumers using URL joiners.
        Value::String(format!(
            "https://anywork.invalid/tool-input/{}",
            Uuid::new_v4()
        ))
    });
    Ok(resource)
}
