//! JSON argument and receipt handling for Studio-owned tool adapters.

use pl_core::{
    context::{ContextContent, OpaquePayload, content_hash},
    thread::extensions::ExtensionMutation,
    tool::{ToolOutput, opaque::ToolError},
};
use serde::{Serialize, de::DeserializeOwned};

pub(crate) struct JsonToolInput<'a>(&'a str);

impl<'a> JsonToolInput<'a> {
    pub(crate) fn new(input: &'a OpaquePayload) -> Result<Self, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                format!(
                    "unsupported input payload {} v{}",
                    input.format(),
                    input.version()
                ),
            )));
        }
        Ok(Self(input.content()))
    }

    pub(crate) fn decode<T: DeserializeOwned>(&self) -> Result<T, ToolError> {
        pl_agent_tool::typed::decode_json(self.0).map_err(ToolError::new)
    }

    pub(crate) fn argument_hash(&self) -> String {
        content_hash(self.0.as_bytes())
    }
}

pub(crate) fn json_output(format: &str, value: &impl Serialize) -> Result<ToolOutput, ToolError> {
    let text = serde_json::to_string(value).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        OpaquePayload::new(format, 1, text.clone()).map_err(ToolError::new)?,
        vec![ContextContent::Text { text: text.into() }],
    ))
}

pub(crate) fn put_extension(
    output: ToolOutput,
    id: &str,
    expected_revision: Option<u64>,
    payload: OpaquePayload,
) -> ToolOutput {
    output.with_extension_mutations(vec![ExtensionMutation::Put {
        id: id.into(),
        expected_revision,
        payload,
    }])
}
