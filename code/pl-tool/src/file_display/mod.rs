//! Explicit user file display, separate from model media input.
mod archive;
mod thread;

pub use crate::workspace_file::DeferredWorkspaceFile;
pub use pl_core::context::ResourceReference;
use pl_core::{context::OpaquePayload, tool::opaque::ToolError};
pub use pl_model::completion::AttachmentModality;
pub use pl_tool_media::show_files::{Input as ShowFilesInput, Source as ShowFileSource};
pub use thread::ThreadShowFilesTool;

pub const TOOL_SHOW_FILES: &str = "show_files";
pub const FILE_DISPLAY_FORMAT: &str = "pl.tool.files";
pub const FILE_DISPLAY_VERSION: u32 = 2;
pub const FILE_DISPLAY_PRESENTATION: &str = "builtin.show_files@1";

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
    Deferred {
        filename: String,
        target: DeferredWorkspaceFile,
    },
    NetworkImage {
        filename: String,
        url: String,
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
    if !matches!(payload.version(), 1 | FILE_DISPLAY_VERSION) {
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
        match file {
            FileDisplayResult::Ready { resource, .. } => {
                resource.validate().map_err(ToolError::new)?
            }
            FileDisplayResult::Failed { .. } => {}
            FileDisplayResult::Deferred { .. } | FileDisplayResult::NetworkImage { .. }
                if payload.version() == 1 =>
            {
                return Err(failure("v1 file display cannot contain v2 items"));
            }
            FileDisplayResult::NetworkImage { url, .. } => {
                pl_tool_media::show_files::validate_network_image_url(url)
                    .map_err(ToolError::new)?;
            }
            FileDisplayResult::Deferred { .. } => {}
        }
    }
    Ok(Some(receipt))
}

pub fn thread_show_files_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        TOOL_SHOW_FILES,
        pl_tool_media::show_files::DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<ShowFilesInput>(),
    )
    .expect("static tool definition")
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_SHOW_FILES, message))
}
