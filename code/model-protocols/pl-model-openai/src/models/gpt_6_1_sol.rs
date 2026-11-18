use super::{COMMON_EFFORTS, Definition, EXTENDED_CONTEXT, SOL_TIERS};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6.1-sol",
    name: "GPT-6.1 Sol",
    description: "Near-Astra performance for complex coding, computer use, and professional work.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: Some(475_000),
    efforts: COMMON_EFFORTS,
    default_effort: None,
    cache_write_tokens: true,
    tiers: SOL_TIERS,
    pricing_source: "https://developers.openai.com/api/docs/models/gpt-6.1-sol",
    verified_at: 1_790_985_600,
};
