use super::{
    Definition, EXTENDED_CONTEXT, OPTIONAL_EFFORTS, PRICING_SOURCE, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6-sol",
    name: "GPT-6 Sol",
    description: "Built to power complex coding and agentic workflows.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: None,
    efforts: OPTIONAL_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(2.0, 10.0, Some(0.2), Some(2.5)),
        TokenPriceTier::flat(4.0, 15.0, Some(0.4), Some(5.0)),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
