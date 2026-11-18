use super::{
    COMMON_EFFORTS, Definition, EXTENDED_CONTEXT, PRICING_SOURCE, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6-astra",
    name: "GPT-6 Astra",
    description: "OpenAI flagship model for complex reasoning, coding and agent tasks.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: None,
    efforts: COMMON_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(10.0, 50.0, Some(1.0), Some(12.5)),
        TokenPriceTier::flat(20.0, 75.0, Some(2.0), Some(25.0)),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
