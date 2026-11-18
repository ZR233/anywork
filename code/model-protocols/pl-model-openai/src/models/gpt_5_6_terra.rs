use super::{
    COMMON_EFFORTS, Definition, PRICING_SOURCE, STANDARD_CONTEXT, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-5.6-terra",
    name: "GPT-5.6 Terra",
    description: "Balanced agentic coding model for everyday work.",
    context: STANDARD_CONTEXT,
    max_output_tokens: None,
    auto_compact_token_limit: None,
    efforts: COMMON_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(2.0, 12.0, Some(0.2), Some(2.5)),
        TokenPriceTier::flat(4.0, 18.0, Some(0.4), Some(5.0)),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_788_566_400,
};
