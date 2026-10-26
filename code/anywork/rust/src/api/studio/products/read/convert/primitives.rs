use super::super::primitives::*;
use crate::api::studio::observation::BridgeTypedListRef;
use pl_protocol::products::{models as model, read::primitives as protocol};

impl From<protocol::TypedListRef> for BridgeTypedListRef {
    fn from(value: protocol::TypedListRef) -> Self {
        Self {
            list_id: value.list_id,
            total: value.total,
        }
    }
}

impl From<protocol::TextReadItem> for BridgeTextReadItem {
    fn from(value: protocol::TextReadItem) -> Self {
        Self {
            value: value.value.into(),
        }
    }
}

impl From<protocol::TextReadPage> for BridgeTextReadPage {
    fn from(value: protocol::TextReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<model::AccountModelKey> for BridgeAccountModelKey {
    fn from(value: model::AccountModelKey) -> Self {
        Self {
            account_id: value.account_id,
            model_id: value.model_id,
        }
    }
}

impl From<model::ModelSelection> for BridgeModelSelection {
    fn from(value: model::ModelSelection) -> Self {
        Self {
            model: value.model.into(),
            effort: value.effort,
        }
    }
}
