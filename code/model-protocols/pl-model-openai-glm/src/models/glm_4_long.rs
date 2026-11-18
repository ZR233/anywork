use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-4-long",
    name: "GLM-4-Long",
    description: "Zhipu long-context model for very large inputs and memory-heavy tasks.",
    context: 1_000_000,
    max_output_tokens: Some(4_000),
    tiers: &[TokenPriceTier::flat(1.0, 1.0, Some(1.0), None)],
};
