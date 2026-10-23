use serde::{Deserialize, Serialize};
use crate::studio::ReadText;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TypedListRef { pub list_id: u64, pub total: u64 }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TextReadItem { pub value: ReadText }

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct TextReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<TextReadItem>,
    pub next_offset: Option<u64>,
}
