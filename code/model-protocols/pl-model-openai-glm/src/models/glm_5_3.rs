use super::{Definition, TokenPriceTier};

pub(super) const MODEL: Definition = Definition {
    id: "glm-5.3",
    name: "GLM-5.3",
    description: "Zhipu flagship model for complex coding and agent work with always-on thinking.",
    context: 1_000_000,
    max_output_tokens: Some(128_000),
    tiers: &[TokenPriceTier::flat(8.0, 28.0, Some(2.0), None)],
};
