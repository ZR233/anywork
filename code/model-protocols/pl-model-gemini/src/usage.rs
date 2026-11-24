use pl_model_wire::model::UsageReport;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GeminiUsageMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_token_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidates_token_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub thoughts_token_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cached_content_token_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_token_count: Option<u64>,
}

impl GeminiUsageMetadata {
    /// Converts Google `usageMetadata` to canonical `UsageReport`.
    ///
    /// Returns `None` when an intermediate chunk carries only non-count metadata such as
    /// `trafficType` without any token counters.
    ///
    /// Note: Gemini `candidatesTokenCount` excludes `thoughtsTokenCount`, whereas billing and
    /// throughput (TPS) metrics require `output_tokens` to include thinking tokens without
    /// double-counting.
    pub fn to_usage_report(&self) -> Option<UsageReport> {
        if self.prompt_token_count.is_none()
            && self.candidates_token_count.is_none()
            && self.thoughts_token_count.is_none()
            && self.cached_content_token_count.is_none()
            && self.total_token_count.is_none()
        {
            return None;
        }
        let output_tokens = match (self.candidates_token_count, self.thoughts_token_count) {
            (None, None) => None,
            (candidates, thoughts) => Some(
                candidates
                    .unwrap_or(0)
                    .saturating_add(thoughts.unwrap_or(0)),
            ),
        };
        Some(UsageReport {
            input_tokens: self.prompt_token_count,
            output_tokens,
            total_tokens: self.total_token_count,
            cache_read_tokens: self.cached_content_token_count,
            cache_write_tokens: None,
            reasoning_tokens: self.thoughts_token_count,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_metadata_with_only_traffic_type_yields_none() {
        let meta: GeminiUsageMetadata =
            serde_json::from_str(r#"{"trafficType":"ON_DEMAND"}"#).unwrap();
        assert!(meta.to_usage_report().is_none());
    }

    #[test]
    fn merges_candidates_and_thoughts_into_output_tokens() {
        let meta: GeminiUsageMetadata = serde_json::from_str(
            r#"{
                "promptTokenCount": 120,
                "candidatesTokenCount": 40,
                "thoughtsTokenCount": 30,
                "cachedContentTokenCount": 50,
                "totalTokenCount": 190
            }"#,
        )
        .unwrap();
        let report = meta.to_usage_report().unwrap();
        assert_eq!(report.input_tokens, Some(120));
        assert_eq!(report.output_tokens, Some(70));
        assert_eq!(report.reasoning_tokens, Some(30));
        assert_eq!(report.cache_read_tokens, Some(50));
        assert_eq!(report.total_tokens, Some(190));
    }
}
