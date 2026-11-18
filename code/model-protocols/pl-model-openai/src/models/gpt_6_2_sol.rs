use super::{COMMON_EFFORTS, Definition, EXTENDED_CONTEXT, PRICING_SOURCE, SOL_TIERS};

pub(super) const MODEL: Definition = Definition {
    id: "gpt-6.2-sol",
    name: "GPT-6.2 Sol",
    description: "OpenAI versatile model for everyday coding, writing, and multi-step agent tasks.",
    context: EXTENDED_CONTEXT,
    max_output_tokens: Some(128_000),
    auto_compact_token_limit: Some(475_000),
    efforts: COMMON_EFFORTS,
    default_effort: Some("medium"),
    cache_write_tokens: true,
    tiers: SOL_TIERS,
    pricing_source: PRICING_SOURCE,
    verified_at: 1_794_960_000,
};
