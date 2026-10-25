use crate::api::studio::observation::{BridgeReadText, BridgeTypedListRef};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesReadHeader {
    pub schema_version: u32,
    pub revision: BridgeReadText,
    pub templates: BridgeTypedListRef,
    pub model_catalogs: BridgeTypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplateRead {
    pub pricing_enabled: bool,
    pub id: BridgeReadText,
    pub display_name: BridgeReadText,
    pub description: Option<BridgeReadText>,
    pub base_url: BridgeReadText,
    pub credential: BridgeCredentialDescriptorRead,
    pub model_catalog_id: BridgeReadText,
    pub protocol: BridgeReadText,
    pub suggested_model_id: BridgeReadText,
    pub icon_key: Option<BridgeReadText>,
    pub service_capabilities: BridgeAccountServiceCapabilitiesRead,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCredentialDescriptorRead {
    pub label: BridgeReadText,
    pub env_var: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountServiceCapabilitiesRead {
    pub web_search: BridgeWebSearchServiceCapabilitiesRead,
    pub prompt_cache_dialect: BridgeReadText,
    pub responses_programmatic_tool_calling: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeWebSearchServiceCapabilitiesRead {
    pub hosted_responses: bool,
    pub hosted_dialect: BridgeReadText,
    pub standalone: Option<BridgeReadText>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeNamedModelCatalogRead {
    pub id: BridgeReadText,
    pub models: BridgeTypedListRef,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeNamedModelCatalogReadItem {
    pub key: BridgeReadText,
    pub value: BridgeNamedModelCatalogRead,
}
