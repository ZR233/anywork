use super::{
    COMMON_EFFORTS, Definition, PRICING_SOURCE, STANDARD_CONTEXT, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-5.6-sol",
    name: "GPT-5.6 Sol",
    description: "Latest frontier agentic coding model.",
    context: STANDARD_CONTEXT,
    max_output_tokens: None,
    auto_compact_token_limit: None,
    efforts: COMMON_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(4.0, 20.0, Some(0.4), Some(5.0)),
        TokenPriceTier::flat(8.0, 30.0, Some(0.8), Some(10.0)),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
