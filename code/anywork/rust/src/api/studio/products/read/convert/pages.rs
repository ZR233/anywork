use pl_protocol::products::read::model_pages as protocol;
use super::super::pages::*;

impl From<protocol::ModelCatalogEntryPage> for BridgeModelCatalogEntryPage {
    fn from(value: protocol::ModelCatalogEntryPage) -> Self {
        Self { collection: value.collection.into(), offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelCatalogEntityRead> for BridgeModelCatalogEntityRead {
    fn from(value: protocol::ModelCatalogEntityRead) -> Self { Self { reference: value.reference.into(), value: value.value.into() } }
}

impl From<protocol::AccountTemplatesEntryPage> for BridgeAccountTemplatesEntryPage {
    fn from(value: protocol::AccountTemplatesEntryPage) -> Self {
        Self { collection: value.collection.into(), offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::AccountTemplatesEntityRead> for BridgeAccountTemplatesEntityRead {
    fn from(value: protocol::AccountTemplatesEntityRead) -> Self { Self { reference: value.reference.into(), value: value.value.into() } }
}

impl From<protocol::AccountCatalogEntryReadPage> for BridgeAccountCatalogEntryReadPage {
    fn from(value: protocol::AccountCatalogEntryReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::AccountTemplateReadPage> for BridgeAccountTemplateReadPage {
    fn from(value: protocol::AccountTemplateReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::NamedModelCatalogReadPage> for BridgeNamedModelCatalogReadPage {
    fn from(value: protocol::NamedModelCatalogReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelDescriptorReadPage> for BridgeModelDescriptorReadPage {
    fn from(value: protocol::ModelDescriptorReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelTypeSupportReadPage> for BridgeModelTypeSupportReadPage {
    fn from(value: protocol::ModelTypeSupportReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelTypeExclusionReadPage> for BridgeModelTypeExclusionReadPage {
    fn from(value: protocol::ModelTypeExclusionReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ConnectionModeReadPage> for BridgeConnectionModeReadPage {
    fn from(value: protocol::ConnectionModeReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelInputCapabilityReadPage> for BridgeModelInputCapabilityReadPage {
    fn from(value: protocol::ModelInputCapabilityReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelInputSourceReadPage> for BridgeModelInputSourceReadPage {
    fn from(value: protocol::ModelInputSourceReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelModalityReadPage> for BridgeModelModalityReadPage {
    fn from(value: protocol::ModelModalityReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}

impl From<protocol::ModelPriceTierReadPage> for BridgeModelPriceTierReadPage {
    fn from(value: protocol::ModelPriceTierReadPage) -> Self {
        Self { list_id: value.list_id, offset: value.offset, total: value.total,
            items: value.items.into_iter().map(Into::into).collect(), next_offset: value.next_offset }
    }
}
