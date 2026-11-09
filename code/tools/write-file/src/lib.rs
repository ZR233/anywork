//! Exact UTF-8 writes through an explicitly supplied filesystem capability.
use pl_agent_tool::typed::TypedTool;
use pl_tool_filesystem::WriteRequest;
pub use pl_tool_filesystem::{WriteBackend, WriteMode};
use std::marker::PhantomData;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteFileInput {
    /// Workspace-relative or permitted absolute destination path.
    pub path: String,
    /// UTF-8 text content.
    pub content: String,
    /// Create, replace, or append behavior.
    pub mode: WriteMode,
}

#[derive(Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WriteReceipt {
    pub path: String,
    pub mode: WriteMode,
    pub bytes_written: usize,
}

#[derive(Debug, Default)]
pub struct WriteFileTool<B>(PhantomData<fn() -> B>);

impl<B> WriteFileTool<B> {
    pub fn new() -> Self {
        Self(PhantomData)
    }
}

impl<B: WriteBackend + 'static> TypedTool for WriteFileTool<B> {
    const NAME: &'static str = "write_file";
    const DESCRIPTION: &'static str =
        "Write exact UTF-8 text to a workspace file using create, overwrite, or append mode.";
    type Args = WriteFileInput;
    type Context = B;
    type Output = WriteReceipt;
    type Error = B::Error;

    async fn execute(&self, input: Self::Args, backend: B) -> Result<WriteReceipt, B::Error> {
        let receipt = WriteReceipt {
            path: input.path.clone(),
            mode: input.mode,
            bytes_written: input.content.len(),
        };
        backend
            .write_text(WriteRequest {
                path: input.path,
                mode: input.mode,
                cwd: None,
                content: input.content,
            })
            .await?;
        Ok(receipt)
    }
}

pub fn definition<B: WriteBackend + 'static>() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::typed::prepare_json::<WriteFileTool<B>>()
        .expect("static file tool definition")
        .definition()
        .clone()
}
