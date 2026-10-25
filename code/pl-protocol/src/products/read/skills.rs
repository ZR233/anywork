//! Typed immutable Skills detail schema. IDs belong only to their original read scope.
use super::primitives::TypedListRef;
use crate::products::identity::{ProductCollectionRef, ProductEntityRef};
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillCatalogRead {
    pub project_dir: ReadText,
    pub skills: TypedListRef,
    pub warnings: TypedListRef,
    pub complete: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsReadHeader {
    pub project_id: ReadText,
    pub config_fingerprint: ReadText,
    pub catalog_revision: u64,
    pub catalog: SkillCatalogRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SkillSource {
    Project,
    User,
    System,
    External,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillInvocationPolicyRead {
    pub model_invocable: bool,
    pub user_invocable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum SkillResourceBaseRead {
    Directory { path: ReadText },
    Url { url: ReadText },
    Opaque { description: ReadText },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillSummaryRead {
    pub name: ReadText,
    pub description: ReadText,
    pub category: Option<ReadText>,
    pub platforms: TypedListRef,
    pub source: SkillSource,
    pub provider_id: ReadText,
    pub invocation: SkillInvocationPolicyRead,
    pub resource_base: SkillResourceBaseRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsEntityRead {
    pub reference: ProductEntityRef,
    pub value: SkillSummaryRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsEntryPage {
    pub collection: ProductCollectionRef,
    pub offset: u64,
    pub items: Vec<ProductEntityRef>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillSummaryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<SkillSummaryRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillSearchInvocationPolicy {
    pub model_invocable: bool,
    pub user_invocable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum SkillSearchResourceBase {
    Directory { path: String },
    Url { url: String },
    Opaque { description: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillSearchSummary {
    pub name: String,
    pub description: String,
    pub category: Option<String>,
    pub platforms: Vec<String>,
    pub source: SkillSource,
    pub provider_id: String,
    pub invocation: SkillSearchInvocationPolicy,
    pub resource_base: SkillSearchResourceBase,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SkillsSearchResult {
    pub project_id: String,
    pub catalog_revision: u64,
    pub matches: Vec<SkillSearchSummary>,
    pub truncated: bool,
}
