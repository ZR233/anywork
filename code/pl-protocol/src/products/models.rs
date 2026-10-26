//! Pure Models-only editing suggestions; these values do not select an execution route.
use serde::{Deserialize, Serialize};

/// A model is identified within its original account, never by a display name or bare slug.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountModelKey {
    pub account_id: String,
    pub model_id: String,
}

/// An editing suggestion from one pinned catalog. `None` effort omits the parameter; it does not
/// grant a save/execute validator permission to replace an explicitly omitted choice.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelSelection {
    pub model: AccountModelKey,
    pub effort: Option<String>,
}

/// Models-only canonical material. Desired editing fields and credentials remain Configuration's.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelsValue {
    pub accounts: Vec<AccountCatalogEntry>,
    pub web_search: EffectiveWebSearch,
    pub deepseek_web_search: EffectiveDeepSeekSearch,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AccountCatalogEntry {
    pub account_id: String,
    pub credential_required: bool,
    pub capability_source: String,
    pub hosted_web_search: bool,
    pub hosted_web_search_dialect: String,
    pub standalone_web_search: Option<String>,
    pub prompt_cache_dialect: String,
    pub responses_programmatic_tool_calling: bool,
    pub default_model_id: String,
    pub effective_models: Vec<crate::ModelDescriptor>,
    pub model_catalog: crate::studio::StudioModelCatalogStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EffectiveWebSearch {
    pub effective_mode: String,
    pub availability: String,
    pub account_id: Option<String>,
    pub model_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct EffectiveDeepSeekSearch {
    pub effective_enabled: bool,
    pub effective_fetch_enabled: bool,
    pub availability: String,
    pub account_id: Option<String>,
}
