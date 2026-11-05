//! Author-owned tool declarations.
//!
//! A [`ToolDefinition`] is the sole declaration a tool author makes: name,
//! description, input contract, and an optional output schema. Construction
//! validates declarations before any tool instance is transferred, but keeps
//! accepted values byte-for-byte as authored. Declarations serialize for host
//! consumers; there is intentionally no deserialization back into these types.

use std::fmt;

use serde::Serialize;

use crate::JsonValue;

/// Declares how a tool consumes raw model input.
///
/// [`InputFormat::JsonSchema`] keeps the author's complete JSON Schema
/// document as authored, [`InputFormat::Text`] declares free-form text, and
/// [`InputFormat::Grammar`] declares a grammar in a named syntax such as
/// `lark`. The schema root is only checked to be a JSON object; object-only
/// or strict rules for specific providers belong to model projection.
#[derive(Clone, PartialEq, Eq, Serialize)]
pub enum InputFormat {
    /// A complete JSON Schema document for structured input.
    JsonSchema(JsonValue),
    /// Free-form text input.
    Text,
    /// A grammar declaration in the given syntax.
    Grammar {
        /// The grammar syntax identifier, for example `lark`.
        syntax: String,
        /// The grammar definition itself.
        definition: String,
    },
}

impl fmt::Debug for InputFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::JsonSchema(_) => f.write_str("JsonSchema(..)"),
            Self::Text => f.write_str("Text"),
            Self::Grammar { .. } => f.write_str("Grammar { .. }"),
        }
    }
}

/// Rejects a declaration that would otherwise reach consumers unusable.
///
/// Validation happens in constructors and [`ToolDefinition::with_output_schema`]
/// before a tool instance is transferred, so later attach and registration
/// steps cannot fail on declaration problems.
#[derive(Debug, thiserror::Error)]
pub enum DefinitionError {
    /// The tool name contains only whitespace.
    #[error("tool name must contain a non-whitespace character")]
    EmptyName,
    /// The grammar syntax identifier is empty or whitespace only.
    #[error("grammar syntax must not be empty")]
    EmptyGrammarSyntax,
    /// The grammar definition is empty or whitespace only.
    #[error("grammar definition must not be empty")]
    EmptyGrammar,
    /// The input schema document root is not a JSON object.
    #[error("input schema document must be a JSON object")]
    InvalidInputSchema,
    /// The output schema document root is not a JSON object.
    #[error("output schema document must be a JSON object")]
    InvalidOutputSchema,
}

/// The sole author declaration of a tool.
///
/// Fields are private: callers construct definitions through
/// [`ToolDefinition::json`], [`ToolDefinition::text`], or
/// [`ToolDefinition::grammar`], optionally finishing with
/// [`ToolDefinition::with_output_schema`]. Whitespace-only names and grammar
/// fields are rejected, while accepted values are never rewritten; schema
/// documents keep their root checked as a JSON object and their bytes
/// otherwise unchanged. Provider-side naming or strictness rules are not
/// applied here.
#[derive(Clone, PartialEq, Eq, Serialize)]
pub struct ToolDefinition {
    name: String,
    description: String,
    input: InputFormat,
    output_schema: Option<JsonValue>,
}

fn ensure_name(name: &str) -> Result<(), DefinitionError> {
    if name.trim().is_empty() {
        Err(DefinitionError::EmptyName)
    } else {
        Ok(())
    }
}

impl ToolDefinition {
    /// Declares a tool whose input is described by a JSON Schema document.
    ///
    /// # Errors
    ///
    /// Returns [`DefinitionError::EmptyName`] when `name` contains only
    /// whitespace, and [`DefinitionError::InvalidInputSchema`] when `schema`
    /// is not a JSON object at its root.
    pub fn json(
        name: impl Into<String>,
        description: impl Into<String>,
        schema: JsonValue,
    ) -> Result<Self, DefinitionError> {
        let name = name.into();
        ensure_name(&name)?;
        if !schema.is_object() {
            return Err(DefinitionError::InvalidInputSchema);
        }
        Ok(Self {
            name,
            description: description.into(),
            input: InputFormat::JsonSchema(schema),
            output_schema: None,
        })
    }

    /// Declares a tool that consumes free-form text.
    ///
    /// # Errors
    ///
    /// Returns [`DefinitionError::EmptyName`] when `name` contains only
    /// whitespace.
    pub fn text(
        name: impl Into<String>,
        description: impl Into<String>,
    ) -> Result<Self, DefinitionError> {
        let name = name.into();
        ensure_name(&name)?;
        Ok(Self {
            name,
            description: description.into(),
            input: InputFormat::Text,
            output_schema: None,
        })
    }

    /// Declares a tool whose input follows a grammar in a named syntax.
    ///
    /// # Errors
    ///
    /// Returns [`DefinitionError::EmptyName`] when `name` contains only
    /// whitespace, [`DefinitionError::EmptyGrammarSyntax`] when `syntax` is
    /// empty, and [`DefinitionError::EmptyGrammar`] when `definition` is
    /// empty.
    pub fn grammar(
        name: impl Into<String>,
        description: impl Into<String>,
        syntax: impl Into<String>,
        definition: impl Into<String>,
    ) -> Result<Self, DefinitionError> {
        let name = name.into();
        ensure_name(&name)?;
        let syntax = syntax.into();
        if syntax.trim().is_empty() {
            return Err(DefinitionError::EmptyGrammarSyntax);
        }
        let definition = definition.into();
        if definition.trim().is_empty() {
            return Err(DefinitionError::EmptyGrammar);
        }
        Ok(Self {
            name,
            description: description.into(),
            input: InputFormat::Grammar { syntax, definition },
            output_schema: None,
        })
    }

    /// Attaches an output schema document to this declaration.
    ///
    /// # Errors
    ///
    /// Returns [`DefinitionError::InvalidOutputSchema`] when `schema` is not
    /// a JSON object at its root; `self` is consumed so the original value is
    /// not silently reused.
    pub fn with_output_schema(self, schema: JsonValue) -> Result<Self, DefinitionError> {
        if !schema.is_object() {
            return Err(DefinitionError::InvalidOutputSchema);
        }
        Ok(Self {
            output_schema: Some(schema),
            ..self
        })
    }

    /// Returns the declared tool name, byte-for-byte as authored.
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Returns the declared description.
    pub fn description(&self) -> &str {
        &self.description
    }

    /// Returns the declared input contract.
    pub fn input(&self) -> &InputFormat {
        &self.input
    }

    /// Returns the declared output schema, when present.
    pub fn output_schema(&self) -> Option<&JsonValue> {
        self.output_schema.as_ref()
    }
}

impl fmt::Debug for ToolDefinition {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ToolDefinition")
            .field("name", &self.name)
            .field("input", &self.input)
            .field("has_output_schema", &self.output_schema.is_some())
            .finish()
    }
}
