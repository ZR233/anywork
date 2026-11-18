use super::{Definition, TokenPriceTier, context_output_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4.7",
    name: "GLM-4.7",
    description: "Zhipu high-intelligence model for dialogue, reasoning, agents, and coding.",
    context: 200_000,
    max_output_tokens: Some(128_000),
    tiers: &context_output_tiers(
        TokenPriceTier::flat(2.0, 8.0, Some(0.4), None),
        TokenPriceTier::flat(3.0, 14.0, Some(0.6), None),
        TokenPriceTier::flat(4.0, 16.0, Some(0.8), None),
    ),
};
