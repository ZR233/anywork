use super::ModelTextChannel;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletionPresentationItem {
    pub provider_item_id: String,
    pub output_index: Option<u32>,
    pub kind: CompletionPresentationItemKind,
    pub parts: Vec<CompletionPresentationPart>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "channel", rename_all = "camelCase")]
pub enum CompletionPresentationItemKind {
    Text(ModelTextChannel),
    Reasoning,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CompletionPresentationPart {
    pub content_index: u32,
    pub provider_part_id: Option<String>,
    pub kind: CompletionPresentationPartKind,
    pub text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CompletionPresentationPartKind {
    OutputText,
    ReasoningText,
    SummaryText,
}
