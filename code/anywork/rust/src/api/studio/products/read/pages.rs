use super::super::identity::{BridgeProductCollectionRef, BridgeProductEntityRef};
use super::model_values::*;
use super::template_values::{BridgeAccountTemplateRead, BridgeNamedModelCatalogReadItem};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCatalogEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModelCatalogEntityRead { pub reference: BridgeProductEntityRef, pub value: BridgeAccountCatalogEntryRead }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesEntityRead { pub reference: BridgeProductEntityRef, pub value: BridgeAccountTemplateRead }

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAccountCatalogEntryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAccountCatalogEntryRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplateReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAccountTemplateRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeNamedModelCatalogReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeNamedModelCatalogReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModelDescriptorReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelDescriptorRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelTypeSupportReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelTypeSupportRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelTypeExclusionReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelTypeExclusionReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConnectionModeReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeConnectionModeRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelInputCapabilityReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelInputCapabilityRead>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelInputSourceReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelInputSourceReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelModalityReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelModalityReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModelPriceTierReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelPriceTierRead>,
    pub next_offset: Option<u64>,
}
