use super::super::identity::{BridgeProductCollectionRef, BridgeProductEntityRef};
use super::configuration_values::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeAccountConfigurationRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountConfigurationReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAccountConfigurationRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAcpAccountConfigurationReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeAcpAccountConfigurationRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeCustomModelConfigurationReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeCustomModelConfigurationRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelConnectionReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelConnectionRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelAutoCompactReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModelAutoCompactRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeModelRouteReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeModeModelRouteRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRoleModelRouteReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeRoleModelRouteRead>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpConfigurationReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeMcpConfigurationRead>,
    pub next_offset: Option<u64>,
}
