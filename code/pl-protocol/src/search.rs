use crate::{WebSearchContextSize, WebSearchUserLocation, WebSearchUserLocationType};
use serde::{Deserialize, Serialize};

/// Web 搜索访问模式。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum WebSearchMode {
    Disabled,
    #[default]
    Cached,
    Indexed,
    Live,
}

impl WebSearchMode {
    pub fn is_disabled(self) -> bool {
        self == Self::Disabled
    }
}

/// Web 搜索使用的近似位置。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct WebSearchLocation {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub region: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub city: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timezone: Option<String>,
}

impl WebSearchLocation {
    pub fn is_empty(&self) -> bool {
        self.country.as_deref().is_none_or(str::is_empty)
            && self.region.as_deref().is_none_or(str::is_empty)
            && self.city.as_deref().is_none_or(str::is_empty)
            && self.timezone.as_deref().is_none_or(str::is_empty)
    }
}

/// Web 搜索的产品无关配置。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct WebSearchConfig {
    #[serde(default)]
    pub mode: WebSearchMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_size: Option<WebSearchContextSize>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub allowed_domains: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub location: Option<WebSearchLocation>,
}

impl WebSearchConfig {
    pub fn is_default(&self) -> bool {
        self == &Self::default()
    }
}

impl From<&WebSearchLocation> for WebSearchUserLocation {
    fn from(location: &WebSearchLocation) -> Self {
        Self {
            kind: WebSearchUserLocationType::Approximate,
            country: location.country.clone(),
            region: location.region.clone(),
            city: location.city.clone(),
            timezone: location.timezone.clone(),
        }
    }
}
