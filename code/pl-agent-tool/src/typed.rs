//! The optional typed author layer.
//!
//! This module is an author convenience, not a second consumption path: hosts
//! keep working with [`Tool`] and [`crate::ToolHandle`] only. Authors whose
//! tools follow the static "JSON arguments in, typed Rust out" shape derive
//! or hand-write [`TypedTool`], prepare a validated declaration with
//! [`prepare_json`], and attach the instance later; [`JsonAdapter`] performs
//! the single decode step and forwards to the business future unchanged.

use std::{error::Error as StdError, fmt, future::Future, marker::PhantomData};

pub use serde::de::DeserializeOwned;

pub use schemars::JsonSchema;
pub use serde_json::Error as JsonError;

use crate::{DefinitionError, JsonValue, Tool, ToolDefinition};

/// A tool authored against static JSON arguments.
///
/// Names and descriptions come from static constants, so hosts can prepare
/// declarations with [`prepare_json`] before any tool instance exists. Tools
/// with dynamic metadata or per-instance input contracts implement [`Tool`]
/// directly instead of faking a static `Args` type.
pub trait TypedTool: Send + Sync + 'static {
    /// The stable tool name.
    const NAME: &'static str;

    /// The stable tool description.
    const DESCRIPTION: &'static str;

    /// Owned JSON arguments, decoded once before the business future starts.
    type Args: DeserializeOwned + JsonSchema + Send + 'static;

    /// Owned per-call context transferred into one execution.
    type Context: Send + 'static;

    /// Owned output of a successful execution.
    type Output: Send + 'static;

    /// The tool's concrete error type.
    type Error: StdError + Send + Sync + 'static;

    /// Executes one call with owned arguments and context.
    fn execute(
        &self,
        args: Self::Args,
        context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send;

    /// Releases tool-held resources; the default closes nothing.
    fn close(&self) -> impl Future<Output = Result<(), Self::Error>> + Send {
        async { Ok(()) }
    }
}

/// Generates the input schema document for `A` exactly as this library binds it.
///
/// All schemas derived from Rust argument types converge here: draft 2020-12,
/// generated for deserialization, once per binding and never per execution.
/// Dynamic tool families call this for their argument type while freezing a
/// declaration at bind time.
pub fn input_schema_for<A: JsonSchema>() -> JsonValue {
    schemars::generate::SchemaSettings::draft2020_12()
        .for_deserialize()
        .into_generator()
        .into_root_schema_for::<A>()
        .to_value()
}

/// A validated declaration for `T`, prepared before any instance exists.
///
/// The schema is generated exactly once here; there is no per-monotonization
/// caching layer.
pub struct PreparedJson<T: TypedTool> {
    definition: ToolDefinition,
    _type: PhantomData<fn() -> T>,
}

/// The single decode-plus-forward adapter over a [`TypedTool`] instance.
pub struct JsonAdapter<T: TypedTool, I = String> {
    tool: T,
    definition: ToolDefinition,
    input_text: for<'a> fn(&'a I) -> Result<&'a str, ArgumentError>,
}

/// Prepares the declaration for `T` without an instance.
///
/// # Errors
///
/// Returns [`DefinitionError`] when the generated schema or the static name
/// fail declaration validation; no tool instance has been taken yet.
pub fn prepare_json<T: TypedTool>() -> Result<PreparedJson<T>, DefinitionError> {
    let schema = input_schema_for::<T::Args>();

    let definition = ToolDefinition::json(T::NAME, T::DESCRIPTION, schema)?;

    Ok(PreparedJson {
        definition,
        _type: PhantomData,
    })
}

impl<T: TypedTool> PreparedJson<T> {
    /// Returns the prepared immutable declaration.
    pub fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    /// Attaches an instance that consumes raw JSON text; attaching cannot fail.
    ///
    /// The default consumes the original [`String`] without parsing or
    /// re-encoding it as a [`JsonValue`].
    pub fn attach(self, tool: T) -> JsonAdapter<T, String> {
        JsonAdapter {
            tool,
            definition: self.definition,
            input_text: |raw: &String| Ok(raw.as_str()),
        }
    }

    /// Attaches an instance with a host-provided input extractor.
    ///
    /// The extractor borrows the input only to produce the raw JSON text; the
    /// borrow ends before the business future starts.
    pub fn attach_input<I: Send + 'static>(
        self,
        tool: T,
        input_text: for<'a> fn(&'a I) -> Result<&'a str, ArgumentError>,
    ) -> JsonAdapter<T, I> {
        JsonAdapter {
            tool,
            definition: self.definition,
            input_text,
        }
    }

    /// Publishes the serialization schema of `T::Output` on the declaration.
    ///
    /// The schema is generated with `for_serialize()` for the actual output
    /// type and validated at its root; it adds no runtime output encoding.
    /// Only available before [`PreparedJson::attach`] consumes this value.
    ///
    /// # Errors
    ///
    /// Returns [`DefinitionError::InvalidOutputSchema`] when the generated
    /// document is not a JSON object at its root.
    pub fn with_output_schema(self) -> Result<Self, DefinitionError>
    where
        T::Output: JsonSchema,
    {
        let schema = schemars::generate::SchemaSettings::draft2020_12()
            .for_serialize()
            .into_generator()
            .into_root_schema_for::<T::Output>()
            .to_value();
        let definition = self.definition.with_output_schema(schema)?;
        Ok(Self {
            definition,
            _type: PhantomData,
        })
    }
}

/// Failures while turning raw tool input into typed arguments.
#[derive(Debug, thiserror::Error)]
pub enum ArgumentError {
    /// The payload kind is not one the extractor supports.
    ///
    /// This variant exists for host extractors such as opaque payload
    /// readers; this library itself does not know any payload format.
    #[error("unsupported tool payload {format:?} version {version}")]
    UnsupportedPayload {
        /// The rejected payload format identifier.
        format: String,
        /// The rejected payload version.
        version: u32,
    },

    /// The input is not valid JSON for the argument type at the given path.
    #[error("invalid tool arguments at {path}: {source}")]
    Decode {
        /// The field or index path reported by the deserializer.
        path: String,
        #[source]
        source: JsonError,
    },

    /// Valid arguments were followed by unexpected extra input.
    #[error("unexpected trailing input after tool arguments: {source}")]
    Trailing {
        #[source]
        source: JsonError,
    },
}

/// The adapter-level error: argument decoding versus the tool's own failure.
#[derive(Debug, thiserror::Error)]
pub enum InvocationError<E>
where
    E: StdError + Send + Sync + 'static,
{
    /// The raw input never became typed arguments.
    #[error("invalid tool arguments: {0}")]
    Arguments(#[source] ArgumentError),

    /// The underlying `execute` or `close` failed with its concrete error.
    #[error("tool operation failed: {0}")]
    Tool(#[source] E),
}

/// Decodes one JSON document into `T`, keeping the deserializer's real path.
///
/// The path is whatever `serde_path_to_error` actually reports (field or
/// index positions); it is not an RFC 6901 JSON Pointer. Type mismatches and
/// syntax errors keep the original [`JsonError`] as their source, and input
/// after the first document is rejected.
///
/// # Errors
///
/// Returns [`ArgumentError::Decode`] when the document does not deserialize
/// into `T`, and [`ArgumentError::Trailing`] when non-whitespace input
/// follows the first document.
pub fn decode_json<T: DeserializeOwned>(raw: &str) -> Result<T, ArgumentError> {
    let mut deserializer = serde_json::Deserializer::from_str(raw);

    let args = serde_path_to_error::deserialize(&mut deserializer).map_err(|error| {
        let path = error.path().to_string();
        ArgumentError::Decode {
            path,
            source: error.into_inner(),
        }
    })?;

    deserializer
        .end()
        .map_err(|source| ArgumentError::Trailing { source })?;

    Ok(args)
}

impl<T, I> Tool for JsonAdapter<T, I>
where
    T: TypedTool,
    I: Send + 'static,
{
    type Input = I;
    type Context = T::Context;
    type Output = T::Output;
    type Error = InvocationError<T::Error>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: I,
        context: T::Context,
    ) -> Result<T::Output, InvocationError<T::Error>> {
        let args = {
            let raw = (self.input_text)(&input).map_err(InvocationError::Arguments)?;
            decode_json::<T::Args>(raw).map_err(InvocationError::Arguments)?
        };

        TypedTool::execute(&self.tool, args, context)
            .await
            .map_err(InvocationError::Tool)
    }

    async fn close(&self) -> Result<(), InvocationError<T::Error>> {
        TypedTool::close(&self.tool)
            .await
            .map_err(InvocationError::Tool)
    }
}

impl<T: TypedTool> fmt::Debug for PreparedJson<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PreparedJson")
            .field("name", &self.definition.name())
            .field("tool_type", &std::any::type_name::<T>())
            .finish()
    }
}

impl<T: TypedTool, I> fmt::Debug for JsonAdapter<T, I> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("JsonAdapter")
            .field("name", &self.definition.name())
            .field("tool_type", &std::any::type_name::<T>())
            .finish()
    }
}
