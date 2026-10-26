use super::primitives::TypedListRef;
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountTemplatesReadHeader {
    pub schema_version: u32,
    pub revision: ReadText,
    pub templates: TypedListRef,
    pub model_catalogs: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountTemplateRead {
    pub id: ReadText,
    pub display_name: ReadText,
    pub description: Option<ReadText>,
    pub base_url: ReadText,
    pub credential: CredentialDescriptorRead,
    pub model_catalog_id: ReadText,
    pub protocol: ReadText,
    pub suggested_model_id: ReadText,
    pub icon_key: Option<ReadText>,
    pub service_capabilities: AccountServiceCapabilitiesRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct CredentialDescriptorRead {
    pub label: ReadText,
    pub env_var: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct AccountServiceCapabilitiesRead {
    pub web_search: WebSearchServiceCapabilitiesRead,
    pub prompt_cache_dialect: ReadText,
    pub responses_programmatic_tool_calling: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct WebSearchServiceCapabilitiesRead {
    pub hosted_responses: bool,
    pub hosted_dialect: ReadText,
    pub standalone: Option<ReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct NamedModelCatalogRead {
    pub id: ReadText,
    pub models: TypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct NamedModelCatalogReadItem {
    pub key: ReadText,
    pub value: NamedModelCatalogRead,
}
