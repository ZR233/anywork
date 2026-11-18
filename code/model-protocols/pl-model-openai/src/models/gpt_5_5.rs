use super::{Definition, PRICING_SOURCE, STANDARD_CONTEXT, TokenPriceTier, context_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-5.5",
    name: "GPT-5.5",
    description: "Frontier model for complex coding, research, and real-world work.",
    context: STANDARD_CONTEXT,
    max_output_tokens: None,
    auto_compact_token_limit: None,
    efforts: &["low", "medium", "high", "xhigh"],
    default_effort: None,
    cache_write_tokens: false,
    tiers: context_tiers(
        TokenPriceTier::flat(5.0, 30.0, Some(0.5), None),
        TokenPriceTier::flat(10.0, 45.0, Some(1.0), None),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
