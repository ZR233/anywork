use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-5.2",
    name: "GLM-5.2",
    description: "Zhipu latest flagship model with stronger coding and long-horizon agent work.",
    context: 1_000_000,
    max_output_tokens: Some(128_000),
    tiers: &[TokenPriceTier::flat(8.0, 28.0, Some(2.0), None)],
};
