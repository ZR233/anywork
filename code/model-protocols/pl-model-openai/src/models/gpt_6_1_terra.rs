use super::{Definition, EXTENDED_CONTEXT, OPTIONAL_EFFORTS, TokenPriceTier, context_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6.1-terra",
    name: "GPT-6.1 Terra",
    description: "OpenAI model for visual reasoning, screen interaction, and natural writing.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: None,
    efforts: OPTIONAL_EFFORTS,
    default_effort: Some("medium"),
    cache_write_tokens: true,
    tiers: context_tiers(
        TokenPriceTier::flat(1.0, 5.0, Some(0.05), Some(1.25)),
        TokenPriceTier::flat(2.0, 7.5, Some(0.1), Some(2.5)),
    ),
    pricing_source: "https://developers.openai.com/api/docs/models/gpt-6.1-terra",
    verified_at: 1_793_059_200,
};
