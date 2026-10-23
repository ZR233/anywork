use crate::api::studio::observation::BridgeReadText;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTextReadItem { pub value: BridgeReadText }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTextReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeTextReadItem>,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountModelKey { pub account_id: String, pub model_id: String }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelSelection { pub model: BridgeAccountModelKey, pub effort: Option<String> }
