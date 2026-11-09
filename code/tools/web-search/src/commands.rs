use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// 独立搜索的完整命令集合。
#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct SearchCommands {
    /// Web search queries.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub search_query: Option<Vec<SearchQuery>>,
    /// Image search queries.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_query: Option<Vec<SearchQuery>>,
    /// Open pages or search result references.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub open: Option<Vec<OpenOperation>>,
    /// Click links within an opened page.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub click: Option<Vec<ClickOperation>>,
    /// Find text within opened pages.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub find: Option<Vec<FindOperation>>,
    /// Capture PDF pages.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub screenshot: Option<Vec<ScreenshotOperation>>,
    /// Query finance data.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub finance: Option<Vec<FinanceOperation>>,
    /// Query weather data.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather: Option<Vec<WeatherOperation>>,
    /// Query sports schedules or standings.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sports: Option<Vec<SportsOperation>>,
    /// Query current time by UTC offset.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub time: Option<Vec<TimeOperation>>,
    /// Desired response detail.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub response_length: Option<SearchResponseLength>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct SearchQuery {
    /// Search text.
    pub q: String,
    /// Only include results from the last number of days.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recency: Option<u64>,
    /// Optional domain allowlist.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub domains: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct OpenOperation {
    /// Search result reference or URL.
    pub ref_id: String,
    /// Optional line number to position the page.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lineno: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ClickOperation {
    /// Opened page reference.
    pub ref_id: String,
    /// Link id on the opened page.
    pub id: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct FindOperation {
    /// Opened page reference.
    pub ref_id: String,
    /// Text to find.
    pub pattern: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ScreenshotOperation {
    /// PDF page reference.
    pub ref_id: String,
    /// Zero-based PDF page number.
    pub pageno: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct FinanceOperation {
    pub ticker: String,
    #[serde(rename = "type")]
    pub asset_type: FinanceAssetType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub market: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum FinanceAssetType {
    Equity,
    Fund,
    Crypto,
    Index,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct WeatherOperation {
    pub location: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct SportsOperation {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool: Option<SportsToolName>,
    #[serde(rename = "fn")]
    pub function: SportsFunction,
    pub league: SportsLeague,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub team: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opponent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub date_from: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub date_to: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub num_games: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub locale: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SportsToolName {
    Sports,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SportsFunction {
    Schedule,
    Standings,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SportsLeague {
    Nba,
    Wnba,
    Nfl,
    Nhl,
    Mlb,
    Epl,
    Ncaamb,
    Ncaawb,
    Ipl,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct TimeOperation {
    pub utc_offset: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum SearchResponseLength {
    Short,
    Medium,
    Long,
}
