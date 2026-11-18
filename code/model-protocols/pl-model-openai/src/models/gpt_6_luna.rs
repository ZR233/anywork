use super::{
    Definition, EXTENDED_CONTEXT, OPTIONAL_EFFORTS, PRICING_SOURCE, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6-luna",
    name: "GPT-6 Luna",
    description: "Efficient model for focused, high-volume tasks.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: None,
    efforts: OPTIONAL_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(0.1, 0.5, Some(0.010000000000000002), Some(0.125)),
        TokenPriceTier::flat(0.2, 0.75, Some(0.020000000000000004), Some(0.25)),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
