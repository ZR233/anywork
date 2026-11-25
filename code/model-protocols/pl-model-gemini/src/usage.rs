use pl_model_wire::model::UsageReport;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GeminiUsageMetadata {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prompt_token_count: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool_use_prompt_token_count: Option<u64>,
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
            && self.tool_use_prompt_token_count.is_none()
            && self.candidates_token_count.is_none()
            && self.thoughts_token_count.is_none()
            && self.cached_content_token_count.is_none()
            && self.total_token_count.is_none()
        {
            return None;
        }
        let input_tokens = match (self.prompt_token_count, self.tool_use_prompt_token_count) {
            (None, None) => None,
            (prompt, tools) => Some(prompt.unwrap_or(0).saturating_add(tools.unwrap_or(0))),
        };
        let output_tokens = match (self.candidates_token_count, self.thoughts_token_count) {
            (None, None) => None,
            (candidates, thoughts) => Some(
                candidates
                    .unwrap_or(0)
                    .saturating_add(thoughts.unwrap_or(0)),
            ),
        };
        // Gemini REST uses Proto3 JSON serialization, which omits `cachedContentTokenCount` when 0
        // (e.g., short prompts below the 4,096-token implicit cache threshold or cache misses).
        // Normalize omitted cache counts to `Some(0)` whenever prompt token counts are reported so
        // tiered/discounted cache pricing can price cache-miss calls instead of reporting
        // `UnpricedReason::MissingCacheUsage`.
        let cache_read_tokens = if self.prompt_token_count.is_some() {
            self.cached_content_token_count.or(Some(0))
        } else {
            self.cached_content_token_count
        };
        Some(UsageReport {
            input_tokens,
            output_tokens,
            total_tokens: self.total_token_count,
            cache_read_tokens,
            cache_write_tokens: None,
            reasoning_tokens: self.thoughts_token_count,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_model_types::model::{PricingMode, PricingOutcome};

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

    #[test]
    fn tool_use_prompts_are_input_tokens_without_replacing_the_reported_total() {
        let meta: GeminiUsageMetadata = serde_json::from_value(serde_json::json!({
            "promptTokenCount":120,"toolUsePromptTokenCount":15,"candidatesTokenCount":40,
            "thoughtsTokenCount":30,"cachedContentTokenCount":50,"totalTokenCount":205
        }))
        .unwrap();
        let report = meta.to_usage_report().unwrap();
        assert_eq!(report.input_tokens, Some(135));
        assert_eq!(report.output_tokens, Some(70));
        assert_eq!(report.total_tokens, Some(205));
        assert_eq!(report.cache_read_tokens, Some(50));
    }

    #[test]
    fn omitted_cached_content_token_count_normalizes_to_zero_when_prompt_tokens_present() {
        let meta: GeminiUsageMetadata = serde_json::from_str(
            r#"{
                "promptTokenCount": 120,
                "candidatesTokenCount": 40,
                "thoughtsTokenCount": 30,
                "totalTokenCount": 190
            }"#,
        )
        .unwrap();
        let report = meta.to_usage_report().unwrap();
        assert_eq!(report.cache_read_tokens, Some(0));
    }

    #[test]
    fn pricing_estimates_both_cache_miss_and_cache_hit_for_gemini_4_hydrogen() {
        let bundled = crate::bundled_definition().unwrap();
        let hydrogen = bundled
            .models
            .iter()
            .find(|m| m.base.slug == "gemini-4-hydrogen")
            .unwrap();

        let miss: GeminiUsageMetadata = serde_json::from_str(
            r#"{
                "promptTokenCount": 1000,
                "candidatesTokenCount": 200,
                "thoughtsTokenCount": 300,
                "totalTokenCount": 1500
            }"#,
        )
        .unwrap();
        let miss_accounting = hydrogen.extra.pricing.account(
            miss.to_usage_report().unwrap(),
            PricingMode::Catalog,
            0,
        );
        let PricingOutcome::Estimated {
            cost,
            cache_savings,
        } = miss_accounting.pricing
        else {
            panic!(
                "expected estimated cost on cache miss, got {:?}",
                miss_accounting.pricing
            );
        };
        assert_eq!(cost.currency, "USD");
        // (1000 * 1.50 + 500 * 7.50) / 1_000_000 = 0.00525
        assert!((cost.amount - 0.00525).abs() < 1e-12);
        assert_eq!(cache_savings.unwrap().amount, 0.0);

        let hit: GeminiUsageMetadata = serde_json::from_str(
            r#"{
                "promptTokenCount": 10000,
                "cachedContentTokenCount": 6000,
                "candidatesTokenCount": 100,
                "thoughtsTokenCount": 100,
                "totalTokenCount": 10200
            }"#,
        )
        .unwrap();
        let hit_accounting =
            hydrogen
                .extra
                .pricing
                .account(hit.to_usage_report().unwrap(), PricingMode::Catalog, 0);
        let PricingOutcome::Estimated {
            cost,
            cache_savings,
        } = hit_accounting.pricing
        else {
            panic!(
                "expected estimated cost on cache hit, got {:?}",
                hit_accounting.pricing
            );
        };
        // (4000 * 1.50 + 6000 * 0.075 + 200 * 7.50) / 1_000_000 = 0.00795
        assert!((cost.amount - 0.00795).abs() < 1e-12);
        // 6000 * (1.50 - 0.075) / 1_000_000 = 0.00855
        assert!((cache_savings.unwrap().amount - 0.00855).abs() < 1e-12);
    }
}
