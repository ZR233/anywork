use super::{
    COMMON_EFFORTS, Definition, PRICING_SOURCE, STANDARD_CONTEXT, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-5.6-luna",
    name: "GPT-5.6 Luna",
    description: "Fast and affordable agentic coding model.",
    context: STANDARD_CONTEXT,
    max_output_tokens: None,
    auto_compact_token_limit: None,
    efforts: COMMON_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(0.2, 1.2, Some(0.020000000000000004), Some(0.25)),
        TokenPriceTier::flat(
            0.4,
            1.7999999999999998,
            Some(0.04000000000000001),
            Some(0.5),
        ),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
