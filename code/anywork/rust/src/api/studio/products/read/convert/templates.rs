use super::super::template_values::*;
use pl_protocol::products::read::templates as protocol;

impl From<protocol::AccountTemplatesReadHeader> for BridgeAccountTemplatesReadHeader {
    fn from(value: protocol::AccountTemplatesReadHeader) -> Self {
        Self {
            schema_version: value.schema_version,
            revision: value.revision.into(),
            templates: value.templates.into(),
            model_catalogs: value.model_catalogs.into(),
        }
    }
}

impl From<protocol::AccountTemplateRead> for BridgeAccountTemplateRead {
    fn from(value: protocol::AccountTemplateRead) -> Self {
        Self {
            id: value.id.into(),
            display_name: value.display_name.into(),
            description: value.description.map(Into::into),
            base_url: value.base_url.into(),
            credential: value.credential.into(),
            model_catalog_id: value.model_catalog_id.into(),
            protocol: value.protocol.into(),
            suggested_model_id: value.suggested_model_id.into(),
            icon_key: value.icon_key.map(Into::into),
            service_capabilities: value.service_capabilities.into(),
        }
    }
}

impl From<protocol::CredentialDescriptorRead> for BridgeCredentialDescriptorRead {
    fn from(value: protocol::CredentialDescriptorRead) -> Self {
        Self {
            label: value.label.into(),
            env_var: value.env_var.map(Into::into),
        }
    }
}

impl From<protocol::AccountServiceCapabilitiesRead> for BridgeAccountServiceCapabilitiesRead {
    fn from(value: protocol::AccountServiceCapabilitiesRead) -> Self {
        Self {
            web_search: value.web_search.into(),
            prompt_cache_dialect: value.prompt_cache_dialect.into(),
            responses_programmatic_tool_calling: value.responses_programmatic_tool_calling,
        }
    }
}

impl From<protocol::WebSearchServiceCapabilitiesRead> for BridgeWebSearchServiceCapabilitiesRead {
    fn from(value: protocol::WebSearchServiceCapabilitiesRead) -> Self {
        Self {
            hosted_responses: value.hosted_responses,
            hosted_dialect: value.hosted_dialect.into(),
            standalone: value.standalone.map(Into::into),
        }
    }
}

impl From<protocol::NamedModelCatalogRead> for BridgeNamedModelCatalogRead {
    fn from(value: protocol::NamedModelCatalogRead) -> Self {
        Self {
            id: value.id.into(),
            models: value.models.into(),
        }
    }
}

impl From<protocol::NamedModelCatalogReadItem> for BridgeNamedModelCatalogReadItem {
    fn from(value: protocol::NamedModelCatalogReadItem) -> Self {
        Self {
            key: value.key.into(),
            value: value.value.into(),
        }
    }
}
