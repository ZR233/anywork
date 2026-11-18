use super::{Definition, TokenPriceTier, context_tiers};

pub(super) const MODEL: Definition = Definition {
    id: "glm-5",
    name: "GLM-5",
    description: "Zhipu high-intelligence foundation model for coding and agentic planning.",
    context: 200_000,
    max_output_tokens: Some(128_000),
    tiers: &context_tiers(
        TokenPriceTier::flat(4.0, 18.0, Some(1.0), None),
        TokenPriceTier::flat(6.0, 22.0, Some(1.5), None),
    ),
};
