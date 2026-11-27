//! Explicit user file display, separate from model media input.
mod archive;
mod thread;

pub use crate::workspace_file::DeferredWorkspaceFile;
pub use pl_core::context::ResourceReference;
use pl_core::tool::opaque::ToolError;
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
/// Rejects malformed receipts and invalid resource metadata.
pub fn saved_file_display_receipt(
    details: Option<&serde_json::Value>,
) -> Result<Option<FileDisplayReceipt>, ToolError> {
    let Some(value) = details.and_then(|details| details.get("fileDisplay")) else {
        return Ok(None);
    };
    let receipt: FileDisplayReceipt =
        serde_json::from_value(value.clone()).map_err(ToolError::new)?;
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
    .with_output_schema(file_display_output_schema())
    .expect("static show files schema")
}

fn file_display_output_schema() -> serde_json::Value {
    use serde_json::json;
    let filename = json!({"type":"string"});
    json!({"type":"object","properties":{
        "caption":{"type":["string","null"]},
        "files":{"type":"array","items":{"oneOf":[
            {"type":"object","properties":{
                "status":{"const":"ready"},"filename":filename,"resource":crate::media::resource_reference_schema(),
                "modality":{"enum":["image","video","file"]}
            },"required":["status","filename","resource","modality"],"additionalProperties":false},
            {"type":"object","properties":{
                "status":{"const":"failed"},"filename":filename,"message":{"type":"string"}
            },"required":["status","filename","message"],"additionalProperties":false},
            {"type":"object","properties":{
                "status":{"enum":["deferred","networkImage"]},"filename":filename
            },"required":["status","filename"],"additionalProperties":false}
        ]}},
    },"required":["caption","files"],"additionalProperties":false})
}

fn failure(message: &str) -> ToolError {
    ToolError::new(crate::tool_error(TOOL_SHOW_FILES, message))
}
