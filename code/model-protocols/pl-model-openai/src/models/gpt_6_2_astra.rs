use super::{
    COMMON_EFFORTS, Definition, EXTENDED_CONTEXT, PRICING_SOURCE, TokenPriceTier, context_tiers,
};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6.2-astra",
    name: "GPT-6.2 Astra",
    description: "OpenAI frontier model for complex reasoning, coding, and professional work.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: None,
    efforts: COMMON_EFFORTS,
    default_effort: Some("medium"),
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(8.0, 40.0, Some(0.4), Some(10.0)),
        TokenPriceTier::flat(16.0, 60.0, Some(0.8), Some(20.0)),
    ),
    pricing_source: PRICING_SOURCE,
    verified_at: 1_794_960_000,
};
