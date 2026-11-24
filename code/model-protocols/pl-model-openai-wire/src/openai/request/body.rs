use crate::completion::ToolFormat;
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(super) enum ToolFormatBody {
    Text,
    Grammar { syntax: String, definition: String },
}

impl From<&ToolFormat> for ToolFormatBody {
    fn from(format: &ToolFormat) -> Self {
        match format {
            ToolFormat::Text => Self::Text,
            ToolFormat::Grammar { syntax, definition } => Self::Grammar {
                syntax: syntax.clone(),
                definition: definition.clone(),
            },
        }
    }
}
