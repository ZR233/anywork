//! Maps the host's search preferences to provider settings.
use crate::search::{WebSearchConfig, WebSearchMode};
use pl_model::completion::WebSearchFilters;
use pl_model_openai::search::{
    ExternalWebAccess, ExternalWebAccessMode, SearchAllowedCaller, SearchSettings,
};

pub(super) fn settings_from_config(config: &WebSearchConfig) -> SearchSettings {
    SearchSettings {
        user_location: config
            .location
            .as_ref()
            .filter(|location| !location.is_empty())
            .map(Into::into),
        search_context_size: config.context_size,
        filters: (!config.allowed_domains.is_empty()).then(|| WebSearchFilters {
            allowed_domains: config.allowed_domains.clone(),
        }),
        allowed_callers: vec![SearchAllowedCaller::Direct],
        external_web_access: match config.mode {
            WebSearchMode::Disabled | WebSearchMode::Cached => ExternalWebAccess::Boolean(false),
            WebSearchMode::Indexed => ExternalWebAccess::Mode(ExternalWebAccessMode::Indexed),
            WebSearchMode::Live => ExternalWebAccess::Boolean(true),
        },
    }
}
