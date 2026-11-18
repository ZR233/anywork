use serde::{Deserialize, Serialize};

/// Original ownership proof for a resource actually delivered or repaired in this effect.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct RetainedResourceFact {
    pub call_id: String,
    pub turn_id: Option<String>,
    pub reference: pl_core::context::ResourceReference,
}
