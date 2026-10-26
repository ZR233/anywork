//! Immutable Mode catalog material; authoring replies retain the command's original target.
use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::products::references::ModeCatalogReadTarget;
use crate::studio::{ReadText, StudioCommandReceipt};
use crate::{ThreadModeDefinitionSnapshot, ThreadModeId};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeDefinitionCommandReply {
    pub catalog: ModeCatalogReadTarget,
    pub definition: Option<ThreadModeDefinitionSnapshot>,
    pub receipt: StudioCommandReceipt,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeCatalogReadHeader {
    pub revision: u64,
    pub modes: TypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModeDescriptorRead {
    pub id: ThreadModeId,
    pub display_name: ReadText,
    pub description: ReadText,
    pub order: u32,
    pub has_workflow: bool,
    pub read_only: bool,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeCatalogEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModeCatalogEntityRead {
    pub reference: ProductEntityRef,
    pub value: ThreadModeDescriptorRead,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadModeDescriptorReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<ThreadModeDescriptorRead>,
    pub next_offset: Option<u64>,
}
