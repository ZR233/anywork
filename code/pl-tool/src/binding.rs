//! Host binding for typed authors, prepared before transferring resource owners.
use std::fmt;

pub use pl_agent_tool::typed::{JsonError, JsonSchema, TypedTool};
pub use pl_agent_tool::{DefinitionError, ToolDefinition};
use pl_agent_tool::{
    Tool,
    typed::{self, ArgumentError, InvocationError, JsonAdapter, PreparedJson},
};
use pl_core::context::ContextContent;
pub use pl_core::{
    context::OpaquePayload,
    model::ModelError,
    tool::{
        ToolOutput,
        opaque::{CallContext, PreparedRegistration, Registration, RegistryError, ToolError},
    },
};
pub use pl_model::completion::ToolCallPolicy;
pub use serde::Serialize;

#[derive(Debug, thiserror::Error)]
pub enum BindingError {
    #[error(transparent)]
    Definition(#[from] DefinitionError),
    #[error(transparent)]
    Model(#[from] ModelError),
    #[error(transparent)]
    Registry(#[from] RegistryError),
}

pub fn prepare_registration(
    tool_id: impl Into<String>,
    definition: &ToolDefinition,
    policy: ToolCallPolicy,
) -> Result<PreparedRegistration, BindingError> {
    let spec = pl_model::completion::tool_definition_to_spec(definition, policy);
    let declaration = pl_model::runtime::thread_tool_declaration(&spec)?;
    Ok(Registration::prepare(tool_id.into(), declaration)?)
}

fn core_json_text(input: &OpaquePayload) -> Result<&str, ArgumentError> {
    if input.format() != "application/json" || input.version() != 1 {
        return Err(ArgumentError::UnsupportedPayload {
            format: input.format().to_owned(),
            version: input.version(),
        });
    }
    Ok(input.content())
}

fn native_error(error: InvocationError<ToolError>) -> ToolError {
    match error {
        InvocationError::Arguments(error) => ToolError::new(error),
        InvocationError::Tool(error) => error,
    }
}

pub struct PreparedNativeTool<T: TypedTool> {
    inner: PreparedJson<T>,
}

pub struct NativeTool<T: TypedTool> {
    inner: JsonAdapter<T, OpaquePayload>,
}

pub fn prepare_native_tool<T>() -> Result<PreparedNativeTool<T>, DefinitionError>
where
    T: TypedTool<Context = CallContext, Output = ToolOutput, Error = ToolError>,
{
    Ok(PreparedNativeTool {
        inner: typed::prepare_json()?,
    })
}

impl<T> PreparedNativeTool<T>
where
    T: TypedTool<Context = CallContext, Output = ToolOutput, Error = ToolError>,
{
    pub fn definition(&self) -> &ToolDefinition {
        self.inner.definition()
    }

    pub fn attach(self, tool: T) -> NativeTool<T> {
        NativeTool {
            inner: self.inner.attach_input(tool, core_json_text),
        }
    }
}

impl<T> Tool for NativeTool<T>
where
    T: TypedTool<Context = CallContext, Output = ToolOutput, Error = ToolError>,
{
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        self.inner.definition()
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.inner
            .execute(input, context)
            .await
            .map_err(native_error)
    }

    async fn close(&self) -> Result<(), ToolError> {
        self.inner.close().await.map_err(native_error)
    }
}

pub struct PreparedJsonTool<T: TypedTool> {
    inner: PreparedJson<T>,
    map_context: fn(CallContext) -> T::Context,
    map_tool_error: fn(T::Error) -> ToolError,
}

pub struct JsonTool<T: TypedTool> {
    inner: JsonAdapter<T, OpaquePayload>,
    map_context: fn(CallContext) -> T::Context,
    map_tool_error: fn(T::Error) -> ToolError,
}

pub fn prepare_json_tool<T>(
    map_context: fn(CallContext) -> T::Context,
    map_tool_error: fn(T::Error) -> ToolError,
) -> Result<PreparedJsonTool<T>, DefinitionError>
where
    T: TypedTool,
    T::Output: serde::Serialize,
{
    Ok(PreparedJsonTool {
        inner: typed::prepare_json()?,
        map_context,
        map_tool_error,
    })
}

impl<T> PreparedJsonTool<T>
where
    T: TypedTool,
    T::Output: serde::Serialize,
{
    pub fn definition(&self) -> &ToolDefinition {
        self.inner.definition()
    }

    pub fn attach(self, tool: T) -> JsonTool<T> {
        JsonTool {
            inner: self.inner.attach_input(tool, core_json_text),
            map_context: self.map_context,
            map_tool_error: self.map_tool_error,
        }
    }

    pub fn with_output_schema(mut self) -> Result<Self, DefinitionError>
    where
        T::Output: JsonSchema,
    {
        self.inner = self.inner.with_output_schema()?;
        Ok(self)
    }
}

#[derive(Debug, thiserror::Error)]
#[error(
    "tool {tool:?} returned successfully, but output JSON encoding failed; side effects may have occurred; the binding did not retry execution: {source}"
)]
pub struct JsonOutputError {
    pub tool: String,
    #[source]
    pub source: JsonError,
}

impl<T> JsonTool<T>
where
    T: TypedTool,
{
    fn map_error(&self, error: InvocationError<T::Error>) -> ToolError {
        match error {
            InvocationError::Arguments(error) => ToolError::new(error),
            InvocationError::Tool(error) => (self.map_tool_error)(error),
        }
    }
}

impl<T> Tool for JsonTool<T>
where
    T: TypedTool,
    T::Output: serde::Serialize,
{
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        self.inner.definition()
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let output = self
            .inner
            .execute(input, (self.map_context)(context))
            .await
            .map_err(|error| self.map_error(error))?;
        let text = serde_json::to_string(&output).map_err(|source| {
            ToolError::new(JsonOutputError {
                tool: self.definition().name().to_owned(),
                source,
            })
        })?;
        Ok(ToolOutput::new(
            OpaquePayload::new("application/json", 1, text.clone()).map_err(ToolError::new)?,
            vec![ContextContent::Text { text: text.into() }],
        ))
    }

    async fn close(&self) -> Result<(), ToolError> {
        self.inner
            .close()
            .await
            .map_err(|error| self.map_error(error))
    }
}

macro_rules! bounded_debug {
    ($($name:ident),+ $(,)?) => {$(
        impl<T: TypedTool> fmt::Debug for $name<T> {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.debug_struct(stringify!($name))
                    .field("inner", &self.inner)
                    .finish()
            }
        }
    )+};
}
bounded_debug!(PreparedNativeTool, NativeTool, PreparedJsonTool, JsonTool);
