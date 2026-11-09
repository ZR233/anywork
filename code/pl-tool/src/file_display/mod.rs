//! Explicit user file display, separate from model media input.
mod archive;
mod thread;

pub use pl_core::context::ResourceReference;
use pl_core::{context::OpaquePayload, tool::opaque::ToolError};
pub use pl_protocol::AttachmentModality;
pub use thread::ThreadShowFilesTool;

pub const TOOL_SHOW_FILES: &str = "show_files";
pub const FILE_DISPLAY_FORMAT: &str = "pl.tool.files";
pub const FILE_DISPLAY_VERSION: u32 = 1;
pub const FILE_DISPLAY_PRESENTATION: &str = "builtin.show_files@1";
const DESCRIPTION: &str = "Display an ordered selection of workspace files or this Thread's archived attachments to the user. Workspace files are archived exactly (maximum 50 MiB each); partial failures are reported in order. This does not read file contents into model context or require image input support. Use view_image to inspect an image yourself. Optional caption is trimmed and limited to 240 characters.";

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ShowFilesInput {
    pub files: Vec<ShowFileSource>,
    pub caption: Option<String>,
}

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ShowFileSource {
    Workspace { path: String },
    Attachment { attachment_id: String },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileDisplayReceipt {
    pub caption: Option<String>,
    pub files: Vec<FileDisplayResult>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "status", rename_all = "camelCase", deny_unknown_fields)]
pub enum FileDisplayResult {
    Ready {
        resource: ResourceReference,
        filename: String,
        modality: AttachmentModality,
        origin: FileDisplayOrigin,
    },
    Failed {
        filename: String,
        message: String,
    },
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum FileDisplayOrigin {
    Local { path: String },
    Remote,
    Archive,
}

/// Reads a saved display fact, never invoking the tool or reopening its source.
///
/// # Errors
/// Rejects unsupported versions, malformed receipts and invalid resource metadata.
pub fn saved_file_display_receipt(
    payload: &OpaquePayload,
) -> Result<Option<FileDisplayReceipt>, ToolError> {
    if payload.format() != FILE_DISPLAY_FORMAT {
        return Ok(None);
    }
    if payload.version() != FILE_DISPLAY_VERSION {
        return Err(failure(&format!(
            "unsupported {FILE_DISPLAY_FORMAT} receipt version {}",
            payload.version()
        )));
    }
    let receipt: FileDisplayReceipt =
        serde_json::from_str(payload.content()).map_err(ToolError::new)?;
    if receipt.files.is_empty()
        || receipt.caption.as_ref().is_some_and(|caption| {
            caption.trim() != caption || caption.is_empty() || caption.chars().count() > 240
        })
    {
        return Err(failure("invalid file display receipt"));
    }
    for file in &receipt.files {
        if let FileDisplayResult::Ready { resource, .. } = file {
            resource.validate().map_err(ToolError::new)?;
        }
    }
    Ok(Some(receipt))
}

pub fn thread_show_files_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        TOOL_SHOW_FILES,
        DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<ShowFilesInput>(),
    )
    .expect("static tool definition")
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_SHOW_FILES, message))
}
